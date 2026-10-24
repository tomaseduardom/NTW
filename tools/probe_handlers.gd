extends Node
## Sonda de cobertura real (2026-10-21): resuelve cada disparador y cada Talismán del catálogo con
## el bot (jugador 1) en un tablero de relleno y anota si el juego encontró quién lo resolviera.
## Es la vara exacta, no una aproximación por texto (tools/audit_uncovered.gd): para disparadores
## usa el mismo TriggerResolution._execute_trigger_effect() del juego y su "no_handler"; para
## Talismanes, _resolve_look_and_play_patterns() (true = algún camino lo tomó). Las activadas: los
## botones especiales (AbilityButtonPatternsA-D.try_build, sin ejecutar) y si no,
## TriggerSystem.resolve_ability_effect().
## Resultados por bloque: resuelto | sin_handler | espera (quedó esperando una elección que el bot
## no puede hacer: casi siempre un patrón escrito solo para el Anfitrión, ver paridad remota) |
## sin_disparador (texto de disparador que has_trigger() no reconoce).
## Ojo: sin_handler en disparadores que no son de entrada puede ser un falso negativo si la carta se
## resuelve por una señal aparte (p.ej. CemeteryTriggers, GameManager.confirm_attackers()).
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/probe_handlers.tscn -- salida.md [desde] [hasta] [nombre]

const PROBE_TYPES := ["on_enter_play", "on_leave_play", "on_attack", "on_block", "on_turn_end", "on_damage_dealt",
	"on_destroyed", "on_vigilia", "on_agrupacion", "on_ataque_start", "on_turn_start", "on_opponent_turn_end"]
const WAIT_FRAMES := 240
const WAIT_MS := 4000
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")

var main: Node
var _created: Array = []


func _ready() -> void:
	main = load("res://scenes/game/Main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	for i in 60:
		await get_tree().process_frame
	if not CardDatabase.is_loaded:
		print("ERROR: CardDatabase no cargó")
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://probe_handlers.md"
	var from_i: int = int(args[1]) if args.size() > 1 else 0
	var to_i: int = int(args[2]) if args.size() > 2 else 1 << 30
	var name_filter: String = args[3].to_lower() if args.size() > 3 else ""
	GameManager.is_game_active = true
	# El humano (jugador 0) no está: pasa solo en cada ventana de prioridad, como haría en partida. Si no, la
	# Pila acumulaba objetos y cada efecto esperaba.
	PriorityManager.priority_changed.connect(func(pid: int) -> void:
		if pid == 0 and PriorityManager.priority_window_active:
			await get_tree().process_frame
			if PriorityManager.priority_window_active and PriorityManager.current_priority_player == 0:
				PriorityManager.pass_priority())
	var rows: Array = []
	var seen := {}
	var all: Array = CardDatabase.cards.values()
	for i in range(from_i, mini(to_i, all.size())):
		var d: Dictionary = all[i]
		var text: String = str(d.get("habilidad", ""))
		if text.strip_edges().is_empty() or seen.has(text):
			continue
		var nombre_l: String = str(d.get("nombre", "")).to_lower()
		# "a|b|c": cualquiera de esos nombres exactos; sin "|", subcadena.
		if not name_filter.is_empty() and not ((nombre_l in name_filter.split("|")) if "|" in name_filter else (name_filter in nombre_l)):
			continue
		seen[text] = true
		rows.append_array(await _probe_card(d))
	_write(out_path, rows)
	get_tree().quit(0)


func _probe_card(d: Dictionary) -> Array:
	var rows: Array = []
	var tipo := int(d.get("tipo", -1))
	var name := str(d.get("nombre", "?"))
	if tipo == Constants.CardType.TALISMAN:
		_reset()
		var card := _place(d)
		var token: int = EffectContextScript.push(card, 1, "Talismán", "done")
		var res = await _with_timeout(func(): return await TriggerSystem._resolution._resolve_look_and_play_patterns(
			card, str(d.habilidad), str(d.habilidad), 1, {"card": card}))
		EffectContextScript.pop(token)
		rows.append({"card": name, "kind": "Talismán", "result": _label(res, true), "why": _last_why})
		return rows
	_reset()
	var card := _place(d)
	if not card.has_method("has_trigger"):
		return rows
	for ttype in PROBE_TYPES:
		# La carta pudo salir del juego en el disparador anterior (Cementerio de Kingstead se Destruye
		# como coste).
		if not is_instance_valid(card):
			_reset()
			card = _place(d)
		if not card.has_trigger(ttype):
			continue
		_reset()
		card = _place(d)
		# "Cuando ataque (solo)": la carta es el único atacante.
		GameManager.attackers.clear()
		if ttype == "on_attack":
			GameManager.attackers.append(card)
		var token: int = EffectContextScript.push(card, 1, "disparada", "done")
		TriggerSystem.is_resolving = true  # como TriggerResolution.resolve_next_trigger(): las cartas jugadas adentro se reconocen anidadas
		var res = await _with_timeout(func(): return await TriggerSystem._resolution._execute_trigger_effect(
			card, ttype, {"player_id": 1, "card": card}))
		TriggerSystem.is_resolving = false
		EffectContextScript.pop(token)
		var label := "espera"
		if res is Dictionary:
			label = "sin_handler" if res.get("no_handler", false) else "resuelto"
		# "Al comienzo del turno oponente", "en la Vigilia oponente"...: solo valen en el turno del rival.
		if label == "sin_handler":
			_reset()
			GameManager.active_player_id = 0
			card = _place(d)
			var token2: int = EffectContextScript.push(card, 1, "disparada", "done")
			TriggerSystem.is_resolving = true
			var res2 = await _with_timeout(func(): return await TriggerSystem._resolution._execute_trigger_effect(
				card, ttype, {"player_id": 0, "card": card}))
			TriggerSystem.is_resolving = false
			EffectContextScript.pop(token2)
			if res2 is Dictionary and not res2.get("no_handler", false):
				label = "resuelto"
		rows.append({"card": name, "kind": ttype, "result": label, "why": _last_why if label == "espera" else ""})
	# Activadas
	_reset()
	card = _place(d)
	var parsed: Array = UniversalCardParser.parse_abilities(str(d.habilidad), str(d.get("id", "")))
	for a in parsed:
		if a.get("ability_type", "") != "ACTIVATED":
			continue
		var raw: String = str(a.get("raw_text", ""))
		var label := "sin_handler"
		# Una activada anterior pudo sacar la carta del juego (y liberarla): se vuelve a poner.
		if not is_instance_valid(card):
			card = _place(d)
		if _has_button_pattern(card, a) or _is_reactive_prevention(raw):
			label = "resuelto"
		else:
			_reset()
			card = _place(d)
			var effect: String = str(a.get("effect_text", raw))
			var res = await _with_timeout(func(): return await TriggerSystem.resolve_ability_effect(card, effect, 1))
			label = _label(res, true)
		rows.append({"card": name, "kind": "activada: " + raw.substr(0, 70), "result": label, "why": _last_why if label == "espera" else ""})
	return rows


func _label(res, bool_means_handled: bool) -> String:
	if res == null:
		return "espera"
	if res is bool:
		return "resuelto" if res == bool_means_handled else "sin_handler"
	return "resuelto"


func _has_button_pattern(card: Node, ability: Dictionary) -> bool:
	var insp = main._card_inspector
	if insp == null:
		return false
	var lower := str(ability.get("raw_text", "")).to_lower()
	var btn := Button.new()
	var panel := Control.new()
	var handled := false
	for group in [insp._pattern_group_a, insp._pattern_group_b, insp._pattern_group_c, insp._pattern_group_d]:
		if group.try_build(lower, btn, panel, card, ability.duplicate()):
			handled = true
			break
	btn.free()
	panel.free()
	return handled


func _is_reactive_prevention(raw: String) -> bool:
	"""Prevenciones/anulaciones sin botón: las ofrece EffectController.offer_prevention() cuando
	corresponde (registro _prevention_registry)."""
	for entry in EffectController._prevention_registry:
		var detect = entry.get("detect")
		if detect is Callable and detect.is_valid() and detect.call(raw):
			return true
	return false


## Por qué quedó esperando la última carta (la selección abierta, EffectContext.last_prompt).
var _last_why: String = ""


func _with_timeout(fn: Callable):
	"""null si a los WAIT_FRAMES sigue esperando (una elección del Anfitrión, casi siempre)."""
	EffectContextScript.last_prompt = {}
	_last_why = ""
	var state := {"done": false, "res": null}
	var runner := func() -> void:
		state.res = await fn.call()
		state.done = true
	runner.call()
	# Tiempo real además de cuadros: sin pantalla los cuadros pasan muy rápido y una animación con
	# temporizador (0,5 s) parecía una espera.
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while not state.done and (frames < WAIT_FRAMES or Time.get_ticks_msec() - t0 < WAIT_MS):
		await get_tree().process_frame
		frames += 1
	if not state.done:
		var lp: Dictionary = EffectContextScript.last_prompt
		_last_why = ("elige J%d: %s" % [int(lp.chooser), str(lp.what).substr(0, 90)]) if not lp.is_empty() else "sin selección abierta"
		if main._card_interaction and main._card_interaction.get("is_selecting_target"):
			main._card_interaction.cancel_target_selection()
		return null
	return state.res if state.res != null else true


func _place(d: Dictionary) -> Node:
	var tipo := int(d.get("tipo", -1))
	var card: Node = main._create_card(d, false)
	var zone := Constants.Zone.LINEA_DEFENSA
	var holder: Node = main.opponent_field
	match tipo:
		Constants.CardType.ORO:
			holder = main.opponent_gold
			zone = Constants.Zone.RESERVA_ORO
		Constants.CardType.TOTEM:
			holder = main.opponent_linea_apoyo
			zone = Constants.Zone.LINEA_APOYO
	holder.add_child(card)
	card.owner_id = 1
	card.controller_id = 1
	card.set_zone(zone)
	_created.append(card)
	return card


func _filler(name: String, tipo: int = Constants.CardType.ALIADO, cost: int = 1) -> Dictionary:
	return {"id": "probe_" + name, "uuid": "probe_" + name, "nombre": name, "tipo": tipo, "coste": cost,
		"fuerza": 2, "habilidad": "", "raza": "Guerrero", "keywords": []}


func _reset() -> void:
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
			var fd := _filler("Mazo %d-%d" % [pid, i], t, i % 4)
			deck.append(fd)
			if not is_same(main_deck, deck):
				main_deck.append(fd)
		for i in 3:
			CardManager.get_cemetery(pid).append(_filler("Cementerio %d-%d" % [pid, i], Constants.CardType.ALIADO, i))
	# Una carta cortada por tiempo puede dejar el sistema de disparadores "ocupado": la siguiente esperaba 3 s
	# a que se liberara (no pasa en partida, donde nada se corta a mitad).
	TriggerSystem.is_collecting = false
	TriggerSystem.is_resolving = false
	TriggerSystem.trigger_queue.clear()
	TriggerSystem.pending_active_triggers.clear()
	TriggerSystem.pending_opponent_triggers.clear()
	KeywordManager._temporary_keywords.clear()
	KeywordManager._silenced_cards.clear()
	KeywordManager._turn_name_locks.clear()
	# Lo que dejaron las cartas anteriores (topes, recargos "por el resto del juego"...) no debe afectar a la
	# siguiente.
	RuleState.reset()
	GameManager.attack_strength_caps.clear()
	GameManager.turn_serial += 1
	GameManager.active_player_id = 1
	for pid in [0, 1]:
		var ally: Node = main._create_card(_filler("Aliado %d" % pid), pid != 0)
		(main.player_field if pid == 0 else main.opponent_field).add_child(ally)
		ally.owner_id = pid
		ally.controller_id = pid
		ally.set_zone(Constants.Zone.LINEA_DEFENSA)
		_created.append(ally)
		for g in 3:
			var oro: Node = main._create_card(_filler("Oro %d-%d" % [pid, g], Constants.CardType.ORO, 0), false)
			(main.player_gold if pid == 0 else main.opponent_gold).add_child(oro)
			oro.owner_id = pid
			oro.controller_id = pid
			oro.set_zone(Constants.Zone.RESERVA_ORO)
			_created.append(oro)
		for h in 3:
			var hc: Node = main._create_card(_filler("Mano %d-%d" % [pid, h]), pid != 0)
			(main.player_hand if pid == 0 else main._opponent_fan).add_card(hc)
			_created.append(hc)
	ContinuousEffectManager._invalidate_cache()


func _write(path: String, rows: Array) -> void:
	var counts := {}
	for r in rows:
		var k: String = ("Talismán" if r.kind == "Talismán" else ("activada" if r.kind.begins_with("activada") else r.kind)) + "|" + r.result
		counts[k] = int(counts.get(k, 0)) + 1
	var out := PackedStringArray()
	out.append("# Sonda de handlers (%s)" % Time.get_date_string_from_system())
	out.append("")
	out.append("| Tipo | resuelto | sin_handler | espera |")
	out.append("|---|---|---|---|")
	for kind in ["Talismán", "activada"] + PROBE_TYPES:
		var r := int(counts.get(kind + "|resuelto", 0))
		var s := int(counts.get(kind + "|sin_handler", 0))
		var e := int(counts.get(kind + "|espera", 0))
		if r + s + e > 0:
			out.append("| %s | %d | %d | %d |" % [kind, r, s, e])
			print("PROBE: %s — resuelto %d, sin_handler %d, espera %d" % [kind, r, s, e])
	for label in ["sin_handler", "espera"]:
		out.append("")
		out.append("## %s" % label)
		out.append("")
		for r in rows:
			if r.result == label:
				out.append("- **%s** — %s%s" % [r.card, r.kind, (" ⟶ " + str(r.get("why", ""))) if str(r.get("why", "")) != "" else ""])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("PROBE: detalle en %s" % path)
