extends Node
## Sonda de paridad (2026-10-29): cada disparador, Talismán y habilidad activada del catálogo se
## resuelve dos veces en el mismo tablero de relleno, una del Anfitrión (jugador 0) y otra del
## Remoto (jugador 1, partida en línea simulada: elige por red con RemotePlayerController, no como
## el bot), y se comparan los cambios en espejo ("propio"/"rival": mano, Castillo, Cementerio,
## Destierro, Aliados, fuerza, Oros). Las elecciones se responden solas con la misma regla para los
## dos: lo opcional se cancela; lo obligatorio elige primero lo propio, en el mismo orden de zonas.
## Una diferencia casi siempre es un camino escrito para un solo lado (jugador 0 fijo, bot en vez de
## Remoto). También junta los avisos [PARIDAD] de EffectContext y las esperas de un solo lado.
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/probe_parity.tscn -- salida.md [desde] [hasta] [nombre]

const PROBE_TYPES := ["on_enter_play", "on_leave_play", "on_attack", "on_block", "on_turn_end", "on_damage_dealt",
	"on_destroyed", "on_vigilia", "on_agrupacion", "on_ataque_start", "on_turn_start", "on_opponent_turn_end"]
const WAIT_FRAMES := 240
const WAIT_MS := 4000
const SETTLE_FRAMES := 6
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const TurnClockScript = preload("res://scripts/core/network/TurnClock.gd")

var main: Node
var _created: Array = []
var _clock_defaults: Node = null
var _chooser_note: String = ""


func _ready() -> void:
	# Partida en línea simulada del lado del Anfitrión: el jugador 1 es un RemotePlayerController. Los
	# mensajes quedan en el buffer de reconexión (no hay socket) y NetworkClient no procesa.
	NetworkClient.set_process(false)
	NetworkClient.room_code = "PROBE"
	NetworkClient.is_host = true
	NetworkClient.peer_present = true
	NetworkClient._token = "probe"
	NetworkClient.reconnecting_now = true
	main = load("res://scenes/game/Main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	for i in 60:
		await get_tree().process_frame
	if not CardDatabase.is_loaded:
		print("ERROR: CardDatabase no cargó")
		get_tree().quit(1)
		return
	if not (main._easy_bot is RemotePlayerController):
		print("ERROR: el jugador 1 no es un RemotePlayerController")
		get_tree().quit(1)
		return
	# El reloj real no corre; sus respuestas por defecto sí se usan (ver _forced_remote()).
	if main.get("_turn_clock"):
		main._turn_clock.set_process(false)
	_clock_defaults = TurnClockScript.new()
	_clock_defaults._main = main
	NetworkClient.forced_intent = _forced_remote
	NetworkClient.local_timeout = true
	NetworkClient.set_process(false)
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://probe_parity.md"
	var from_i: int = int(args[1]) if args.size() > 1 else 0
	var to_i: int = int(args[2]) if args.size() > 2 else 1 << 30
	var name_filter: String = args[3].to_lower() if args.size() > 3 else ""
	GameManager.is_game_active = true
	var rows: Array = []
	var seen := {}
	var all: Array = CardDatabase.cards.values()
	for i in range(from_i, mini(to_i, all.size())):
		var d: Dictionary = all[i]
		var text: String = str(d.get("habilidad", ""))
		if text.strip_edges().is_empty() or seen.has(text):
			continue
		var nombre_l: String = str(d.get("nombre", "")).to_lower()
		if not name_filter.is_empty() and not ((nombre_l in name_filter.split("|")) if "|" in name_filter else (name_filter in nombre_l)):
			continue
		seen[text] = true
		rows.append_array(await _probe_card(d))
		if i % 50 == 0:
			print("PARITY: %d/%d" % [i, all.size()])
	_write(out_path, rows)
	get_tree().quit(0)


# =============================================================================
# UNA CARTA
# =============================================================================
func _probe_card(d: Dictionary) -> Array:
	var rows: Array = []
	var tipo := int(d.get("tipo", -1))
	var name := str(d.get("nombre", "?"))
	if tipo == Constants.CardType.TALISMAN:
		var cmp := await _compare(d, "Talismán", func(card: Node, pid: int):
			return await TriggerSystem._resolution._resolve_look_and_play_patterns(
				card, str(d.habilidad), str(d.habilidad), pid, {"card": card}))
		if not cmp.is_empty():
			rows.append(_row(name, "Talismán", cmp))
		return rows
	var probe: Node = _place(d, 1)
	var has_trigger: bool = probe.has_method("has_trigger")
	var types: Array = []
	if has_trigger:
		for ttype in PROBE_TYPES:
			if probe.has_trigger(ttype):
				types.append(ttype)
	for ttype in types:
		var cmp := await _compare(d, ttype, func(card: Node, pid: int):
			GameManager.attackers.clear()
			if ttype == "on_attack":
				GameManager.attackers.append(card)
			TriggerSystem.is_resolving = true
			var res = await TriggerSystem._resolution._execute_trigger_effect(card, ttype, {"player_id": pid, "card": card})
			TriggerSystem.is_resolving = false
			return res)
		if not cmp.is_empty():
			rows.append(_row(name, ttype, cmp))
	var parsed: Array = UniversalCardParser.parse_abilities(str(d.habilidad), str(d.get("id", "")))
	for a in parsed:
		if a.get("ability_type", "") != "ACTIVATED":
			continue
		var raw: String = str(a.get("raw_text", ""))
		var effect: String = str(a.get("effect_text", raw))
		var cmp := await _compare(d, "activada: " + raw.substr(0, 60), func(card: Node, pid: int):
			return await TriggerSystem.resolve_ability_effect(card, effect, pid))
		if not cmp.is_empty():
			rows.append(_row(name, "activada: " + raw.substr(0, 60), cmp))
	return rows


func _row(name: String, kind: String, cmp: Dictionary) -> Dictionary:
	return {"card": name, "kind": kind, "detail": cmp}


func _compare(d: Dictionary, kind: String, run: Callable) -> Dictionary:
	"""Corre el efecto del jugador 0 y del 1 en tableros iguales. {} si coinciden."""
	var out := {}
	for pid in [0, 1]:
		_reset(pid)
		var card := _place(d, pid)
		var before := _snap(pid)
		var reported_before: Dictionary = EffectContextScript._reported.duplicate()
		var token: int = EffectContextScript.push(card, pid, kind, "done")
		_chooser_note = ""
		var res = await _with_timeout(func(): return await run.call(card, pid))
		EffectContextScript.pop(token)
		TriggerSystem.is_resolving = false
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		var after := _snap(pid)
		var delta := {}
		for k in after:
			var dv: int = int(after[k]) - int(before.get(k, 0))
			if dv != 0:
				delta[k] = dv
		var paridad: Array = []
		for k in EffectContextScript._reported:
			if not reported_before.has(k):
				paridad.append(str(k).get_slice("|", 1))
		out[pid] = {"waited": res == null, "delta": delta, "paridad": paridad, "why": _chooser_note}
	var a: Dictionary = out[0]
	var b: Dictionary = out[1]
	if OS.get_environment("PARITY_VERBOSE") != "":
		print("PARITY %s | %s\n  J0: %s\n  J1: %s" % [str(d.get("nombre", "")), kind, _fmt(a), _fmt(b)])
	if a.waited == b.waited and a.delta == b.delta and b.paridad.is_empty():
		return {}
	return out


# =============================================================================
# ESTADO EN ESPEJO
# =============================================================================
func _side_nodes(s: int) -> Dictionary:
	if s == 0:
		return {"field": [main.player_field, main.player_linea_ataque], "support": [main.player_linea_apoyo],
			"gold": main.player_gold, "paid": main.player_oro_pagado}
	return {"field": [main.opponent_field, main.opponent_linea_ataque], "support": [main.opponent_linea_apoyo],
		"gold": main.opponent_gold, "paid": main.opponent_oro_pagado}


func _snap(pid: int) -> Dictionary:
	var snap := {}
	for rel in ["propio", "rival"]:
		var s: int = pid if rel == "propio" else 1 - pid
		var nodes := _side_nodes(s)
		var hand: Array = main.player_hand.cards if s == 0 else main._opponent_fan.get_cards()
		snap[rel + ".mano"] = hand.filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion()).size()
		snap[rel + ".castillo"] = CardManager.get_deck(s).size()
		snap[rel + ".cementerio"] = CardManager.get_cemetery(s).size()
		snap[rel + ".destierro"] = CardManager.get_exile(s).size()
		var allies := 0
		var strength := 0
		var weapons := 0
		for holder in nodes.field:
			for c in holder.get_children():
				if not is_instance_valid(c) or c.is_queued_for_deletion():
					continue
				if c.get("card_type") == Constants.CardType.ALIADO:
					allies += 1
					if c.has_method("get_strength"):
						strength += int(c.get_strength())
					var w = c.get("equipped_weapons")
					if w is Array:
						weapons += w.filter(func(x): return is_instance_valid(x)).size()
		snap[rel + ".aliados"] = allies
		snap[rel + ".fuerza"] = strength
		snap[rel + ".armas"] = weapons
		var support := 0
		for holder in nodes.support:
			support += holder.get_children().filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion()).size()
		snap[rel + ".totems"] = support
		snap[rel + ".reserva"] = GameState.get_oro_reserva(s)
		snap[rel + ".oro_pagado"] = nodes.paid.get_children().filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion()).size()
	return snap


# =============================================================================
# ELECCIONES AUTOMÁTICAS (misma regla para los dos)
# =============================================================================
func _order_key(card: Node, chooser: int) -> Array:
	var ctrl: int = int(card.get("controller_id")) if card.get("controller_id") != null else -1
	var zone: int = int(card.get("current_zone")) if card.get("current_zone") != null else 99
	var parent: Node = card.get_parent()
	var idx: int = card.get_index() if parent else 0
	return [0 if ctrl == chooser else 1, zone, idx]


func _sorted_for(cards: Array, chooser: int) -> Array:
	var valid: Array = cards.filter(func(c): return is_instance_valid(c) and c is Node)
	valid.sort_custom(func(x, y):
		var kx := _order_key(x, chooser)
		var ky := _order_key(y, chooser)
		for i in kx.size():
			if kx[i] != ky[i]:
				return kx[i] < ky[i]
		return false)
	return valid


func _forced_remote(kinds: Array) -> Dictionary:
	"""Respuesta del Remoto: la de TurnClock (lo opcional se cancela), salvo los objetivos
	obligatorios, que siguen _sorted_for() como el Anfitrión."""
	var prompt: Dictionary = NetworkClient.last_prompt
	var candidates: Array = prompt.get("candidates", []) if prompt.get("candidates") is Array else []
	if _chooser_note.is_empty() and not kinds.is_empty():
		_chooser_note = "J1: " + str(kinds[0])
	var nodes_by_id := {}
	for c in candidates:
		if c is Dictionary and c.has("card_id"):
			var obj = instance_from_id(int(str(c.card_id))) if str(c.card_id).is_valid_int() else null
			if obj is Node:
				nodes_by_id[obj] = str(c.card_id)
	if not nodes_by_id.is_empty():
		var ordered: Array = _sorted_for(nodes_by_id.keys(), 1)
		if "await_target_choice" in kinds and not bool(prompt.get("cancellable", true)):
			return {"op": "intent", "kind": "await_target_choice", "card_id": nodes_by_id[ordered[0]]}
		if "await_multi_target_choice" in kinds and not bool(prompt.get("cancellable", true)):
			var n: int = maxi(1, int(prompt.get("max_selections", 1)))
			var ids: Array = []
			for c in ordered.slice(0, n):
				ids.append(nodes_by_id[c])
			return {"op": "intent", "kind": "await_multi_target_choice", "card_ids": ids}
	# Elegir Castillo: el propio, como el Anfitrion (_auto_resolve_host).
	if "await_target_or_castillo_choice" in kinds:
		return {"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo", "own": true}
	return _clock_defaults._default_intent(kinds, prompt)


func _auto_resolve_host() -> void:
	var ci = main._card_interaction
	var dialogs = SelectionManager._dialogs
	if dialogs and dialogs._castillo_pick_active:
		if _chooser_note.is_empty():
			_chooser_note = "J0: castillo"
		dialogs._resolve_castillo_pick(true)  # tu Castillo, como la opcion 0 del Remoto
		return
	if ci and ci.is_selecting_target:
		if _chooser_note.is_empty():
			_chooser_note = "J0: objetivo"
		if ci._selection_cancellable:
			ci.cancel_target_selection()
			return
		var pool: Array = []
		pool.append_array(main.player_hand.cards)
		pool.append_array(main._opponent_fan.get_cards())
		for prop in TurnClockScript.IN_PLAY_CONTAINERS:
			var container: Node = main.get(prop)
			if container:
				pool.append_array(container.get_children())
		pool.append_array(ci._cemetery_target_nodes)
		for c in _sorted_for(pool, 0):
			if not ci._target_filter.is_valid() or ci._target_filter.call(c):
				ci._resolve_target_selection(c)
				return
		ci.cancel_target_selection()
		return
	if SelectionManager.is_open:
		if _chooser_note.is_empty():
			_chooser_note = "J0: selección"
		SelectionManager.force_default()
		return
	if PriorityManager.priority_window_active and PriorityManager.current_priority_player == 0:
		PriorityManager.pass_priority()


func _with_timeout(fn: Callable):
	"""null si sigue esperando a los WAIT_FRAMES (y WAIT_MS)."""
	var state := {"done": false, "res": null}
	var runner := func() -> void:
		state.res = await fn.call()
		state.done = true
	runner.call()
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while not state.done and (frames < WAIT_FRAMES or Time.get_ticks_msec() - t0 < WAIT_MS):
		await get_tree().process_frame
		_auto_resolve_host()
		frames += 1
	if not state.done:
		if main._card_interaction and main._card_interaction.get("is_selecting_target"):
			main._card_interaction.cancel_target_selection()
		return null
	return state.res if state.res != null else true


# =============================================================================
# TABLERO
# =============================================================================
func _place(d: Dictionary, pid: int) -> Node:
	var tipo := int(d.get("tipo", -1))
	var card: Node = main._create_card(d, false)
	var zone := Constants.Zone.LINEA_DEFENSA
	var holder: Node = main.player_field if pid == 0 else main.opponent_field
	match tipo:
		Constants.CardType.ORO:
			holder = main.player_gold if pid == 0 else main.opponent_gold
			zone = Constants.Zone.RESERVA_ORO
		Constants.CardType.TOTEM:
			holder = main.player_linea_apoyo if pid == 0 else main.opponent_linea_apoyo
			zone = Constants.Zone.LINEA_APOYO
	holder.add_child(card)
	card.owner_id = pid
	card.controller_id = pid
	card.set_zone(zone)
	_created.append(card)
	return card


func _filler(name: String, tipo: int = Constants.CardType.ALIADO, cost: int = 1) -> Dictionary:
	return {"id": "probe_" + name, "uuid": "probe_" + name, "nombre": name, "tipo": tipo, "coste": cost,
		"fuerza": 2, "habilidad": "", "raza": "Guerrero", "keywords": []}


func _reset(active_pid: int) -> void:
	"""Tablero simétrico: lo mismo de los dos lados, con el jugador del efecto como activo."""
	for c in _created:
		if is_instance_valid(c):
			if c.get_parent():
				c.get_parent().remove_child(c)
			c.queue_free()
	_created.clear()
	for h in [main.player_hand, main._opponent_fan]:
		if h.has_method("clear_hand"):
			h.clear_hand()
	for holder in [main.player_field, main.opponent_field, main.player_linea_ataque, main.opponent_linea_ataque,
			main.player_linea_apoyo, main.opponent_linea_apoyo, main.player_gold, main.opponent_gold,
			main.player_oro_pagado, main.opponent_oro_pagado]:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	for pid in [0, 1]:
		CardManager.get_cemetery(pid).clear()
		CardManager.get_exile(pid).clear()
		var deck: Array = CardManager.get_deck(pid)
		deck.clear()
		var main_deck: Array = main.player_deck if pid == 0 else main.opponent_deck
		if not is_same(main_deck, deck):
			main_deck.clear()
		for i in 15:
			var t: int = [Constants.CardType.ALIADO, Constants.CardType.ORO, Constants.CardType.ARMA,
				Constants.CardType.TALISMAN, Constants.CardType.TOTEM][i % 5]
			var fd := _filler("Mazo %d" % i, t, i % 4)
			deck.append(fd)
			if not is_same(main_deck, deck):
				main_deck.append(fd)
		for i in 3:
			CardManager.get_cemetery(pid).append(_filler("Cementerio %d" % i, Constants.CardType.ALIADO, i))
	TriggerSystem.is_collecting = false
	TriggerSystem.is_resolving = false
	TriggerSystem.trigger_queue.clear()
	TriggerSystem.pending_active_triggers.clear()
	TriggerSystem.pending_opponent_triggers.clear()
	KeywordManager._temporary_keywords.clear()
	KeywordManager._silenced_cards.clear()
	KeywordManager._turn_name_locks.clear()
	RuleState.reset()
	GameManager.attack_strength_caps.clear()
	GameManager.attackers.clear()
	GameManager.turn_serial += 1
	GameManager.active_player_id = active_pid
	GameManager.current_phase = Constants.Phase.VIGILIA
	if PriorityManager.priority_window_active:
		PriorityManager.force_close()
	for pid in [0, 1]:
		GameState.oro_reserva[pid] = 3
		GameState.oro_pagado[pid] = 0
		var ally: Node = main._create_card(_filler("Aliado"), pid != 0)
		(main.player_field if pid == 0 else main.opponent_field).add_child(ally)
		ally.owner_id = pid
		ally.controller_id = pid
		ally.set_zone(Constants.Zone.LINEA_DEFENSA)
		_created.append(ally)
		for g in 3:
			var oro: Node = main._create_card(_filler("Oro %d" % g, Constants.CardType.ORO, 0), false)
			(main.player_gold if pid == 0 else main.opponent_gold).add_child(oro)
			oro.owner_id = pid
			oro.controller_id = pid
			oro.set_zone(Constants.Zone.RESERVA_ORO)
			_created.append(oro)
		for h in 3:
			var hc: Node = main._create_card(_filler("Mano %d" % h), pid != 0)
			(main.player_hand if pid == 0 else main._opponent_fan).add_card(hc)
			hc.owner_id = pid
			hc.controller_id = pid
			_created.append(hc)
	ContinuousEffectManager._invalidate_cache()


# =============================================================================
# INFORME
# =============================================================================
func _fmt(side: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = side.delta.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %+d" % [k, int(side.delta[k])])
	var s: String = ", ".join(parts) if not parts.is_empty() else "sin cambios"
	if side.waited:
		s += " · QUEDÓ ESPERANDO"
	if str(side.why) != "":
		s += " · eligió " + str(side.why)
	return s


func _write(path: String, rows: Array) -> void:
	var waits := rows.filter(func(r): return r.detail[0].waited != r.detail[1].waited)
	var paridad := rows.filter(func(r): return not r.detail[1].paridad.is_empty())
	var diffs := rows.filter(func(r): return r.detail[0].waited == r.detail[1].waited and r.detail[0].delta != r.detail[1].delta)
	var out := PackedStringArray()
	out.append("# Sonda de paridad Anfitrión/Remoto (%s)" % Time.get_date_string_from_system())
	out.append("")
	out.append("- Resultado distinto: %d" % diffs.size())
	out.append("- Espera de un solo lado: %d" % waits.size())
	out.append("- Avisos [PARIDAD] (el Anfitrión elige/paga por el Remoto): %d" % paridad.size())
	for section in [["Resultado distinto", diffs], ["Espera de un solo lado", waits], ["Avisos [PARIDAD]", paridad]]:
		out.append("")
		out.append("## " + section[0])
		out.append("")
		for r in section[1]:
			out.append("- **%s** — %s" % [r.card, r.kind])
			out.append("  - Anfitrión: " + _fmt(r.detail[0]))
			out.append("  - Remoto: " + _fmt(r.detail[1]))
			if not r.detail[1].paridad.is_empty():
				out.append("  - [PARIDAD] " + "; ".join(PackedStringArray(r.detail[1].paridad)))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("PARITY: distintos %d, esperas %d, paridad %d — detalle en %s" % [diffs.size(), waits.size(), paridad.size(), path])
