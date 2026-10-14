extends RefCounted
## CemeteryTriggers — "Cuando sea puesta en tu Cementerio, ..." (2026-10-14,
## a pedido del usuario: Lanza Argenta y las demás cartas con este disparador
## no lo tenían en ningún lado).
##
## Toda carta que entra a un Cementerio pasa por CardManager._append_to_cemetery()
## (y al Destierro por append_to_exile()), que emiten card_put_in_cemetery /
## card_put_in_exile. Aquí se anota QUÉ entró, POR QUÉ (efecto/daño de quién,
## en el turno de quién) y el disparador se resuelve recién cuando NO queda
## nada resolviéndose (la regla que pidió el usuario: "Signo Amarillo descarta
## Lanza Argenta → Signo termina primero, después dispara la Lanza").
##
## Dos clases de cartas:
##  - la propia carta que entra al Cementerio (Lanza Argenta, kultrung,
##    piedra del chaman, haka pei, daiksuke, serpiente verde, manzana
##    envenenada): su texto vive en el Cementerio (es un Dictionary), así que
##    para la ventana de respuesta del rival se arma un Node temporal;
##  - cartas EN JUEGO que miran tu Cementerio (manu tara, fudo-myo), una vez
##    por turno.

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

## Textos (normalizados: minúsculas, sin ñ/tildes rotas) que reconocen cada carta.
const LANZA := "cuando sea puesta en tu cementerio, baraja esta carta y hasta otras dos cartas de un cementerio"
const KULTRUNG := "cuando sea puesto en tu cementerio por un efecto o dano oponente, puedes subirlo a tu mano"
const PIEDRA := "cuando sea puesto en tu cementerio por un efecto oponente, ponlo en tu oro pagado"
const HAKA_PEI := "sea puesto en tu cementerio por un efecto oponente, juegalo sin pagar su coste y destierralo"
const DAIKSUKE := "cuando sea puesto en tu cementerio durante el turno oponente, juegalo por un oro menos"
const SERPIENTE := "sea puesto en tu cementerio, si no controlas aliados de coste 1 o menos, puedes barajar hasta cuatro cartas de los cementerios"
const MANZANA := "si es puesta en tu cementerio en el turno oponente, puedes desterrarla para desterrar dos cartas del tope del castillo oponente"
const MANU_TARA := "cuando una carta sea puesta en tu cementerio, hasta una vez por turno, puedes barajarla en tu castillo"
const FUDO_MYO := "una vez por turno, cuando un talisman sea puesto en tu cementerio o destierro, puedes barajar hasta tres cartas de los cementerios"

var _pending: Array = []  # [{kind, owner, data, cause, watcher}]
var _running: bool = false
var _used_turn: Dictionary = {}  # instance_id del vigía -> turno en que se usó


# =============================================================================
# ENTRADA
# =============================================================================
func on_card_put_in_cemetery(player_id: int, card_data: Dictionary) -> void:
	if not GameManager.is_game_active:
		return
	var text := normalize(str(card_data.get("habilidad", "")))
	var cause := _cause(player_id)
	for kind in [LANZA, KULTRUNG, PIEDRA, HAKA_PEI, DAIKSUKE, SERPIENTE, MANZANA]:
		if kind in text:
			_queue({"kind": kind, "owner": player_id, "data": card_data, "cause": cause})
	var main := _main()
	if not main:
		return
	for w in _watchers(main, player_id, MANU_TARA):
		_queue({"kind": MANU_TARA, "owner": player_id, "data": card_data, "cause": cause, "watcher": w})
	if _is_talisman(card_data):
		for w in _watchers(main, player_id, FUDO_MYO):
			_queue({"kind": FUDO_MYO, "owner": player_id, "data": card_data, "cause": cause, "watcher": w})


func on_card_put_in_exile(player_id: int, card_data: Dictionary) -> void:
	if not GameManager.is_game_active or not _is_talisman(card_data):
		return
	var main := _main()
	if not main:
		return
	for w in _watchers(main, player_id, FUDO_MYO):
		_queue({"kind": FUDO_MYO, "owner": player_id, "data": card_data, "cause": _cause(player_id), "watcher": w})


static func normalize(t: String) -> String:
	var s := t.to_lower().replace("\n", " ").replace("\r", "")
	for pair in [["ñ", "n"], ["�", "n"], ["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"]]:
		s = s.replace(pair[0], pair[1])
	return s


func _is_talisman(d: Dictionary) -> bool:
	return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN


func _cause(owner_id: int) -> Dictionary:
	"""Por qué entró: 'by' = jugador cuyo efecto/daño la mandó, 'opp_turn' =
	si fue en el turno del rival del dueño."""
	var out := {"kind": "other", "by": GameManager.active_player_id,
		"opp_turn": GameManager.active_player_id != owner_id}
	var ctx: Dictionary = EffectContextScript.current()
	var bm = Engine.get_main_loop().root.get_node_or_null("/root/BattleManager")
	if not ctx.is_empty():
		out.kind = "effect"
		out.by = int(ctx.controller_id)
	elif bm and bm.get("combat_in_progress"):
		out.kind = "damage"
	elif ActionPipeline.is_stack_processing() and PriorityManager.current_stack_controller >= 0:
		out.kind = "effect"
		out.by = PriorityManager.current_stack_controller
	return out


func _watchers(main: Node, player_id: int, kind: String) -> Array:
	"""Cartas en juego de 'player_id' con esta habilidad, sin silenciar y sin
	usar este turno."""
	var out: Array = []
	var containers: Array = PlayerSideScript.line_containers(main, player_id)
	containers.append(PlayerSideScript.gold_reserva(main, player_id))
	containers.append(PlayerSideScript.oro_pagado(main, player_id))
	for cont in containers:
		if not cont:
			continue
		for c in cont.get_children():
			if not is_instance_valid(c) or c.get("card_data") == null:
				continue
			if c.get("controller_id") != null and int(c.controller_id) != player_id:
				continue
			if not (kind in normalize(str(c.card_data.get("habilidad", "")))):
				continue
			if KeywordManager.is_silenced(c) or _used_turn.get(c.get_instance_id(), -1) == GameManager.current_turn:
				continue
			out.append(c)
	return out


func _queue(entry: Dictionary) -> void:
	_pending.append(entry)
	if not _running:
		_running = true
		_run.call_deferred()


# =============================================================================
# CUÁNDO SE RESUELVE
# =============================================================================
func _run() -> void:
	while not _pending.is_empty():
		if not await _wait_until_idle():
			break
		var entry: Dictionary = _pending.pop_front()
		await _resolve(entry)
	_pending.clear()
	_running = false


func _main() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Main")


func is_idle() -> bool:
	"""Nada resolviéndose ni esperando una elección del jugador."""
	var main := _main()
	if not main:
		return false
	if not EffectContextScript._stack.is_empty():
		return false
	if ActionPipeline.is_stack_processing() or TriggerSystem.awaiting_response or TriggerSystem.is_resolving:
		return false
	if not TriggerSystem.trigger_queue.is_empty():
		return false
	if main._zone_browse_picker and main._zone_browse_picker.is_active():
		return false
	if SelectionManager.is_open:
		return false
	var ci = main.get("_card_interaction")
	if ci and ci.get("_target_callback") is Callable and ci._target_callback.is_valid():
		return false
	var bm = main.get_node_or_null("/root/BattleManager")
	if bm and bm.get("combat_in_progress"):
		return false
	return true


func _wait_until_idle() -> bool:
	"""Espera hasta que todo esté quieto durante 0,3 s seguidos (entre el
	costo y el efecto de una habilidad puede haber un instante "quieto")."""
	var tree := Engine.get_main_loop() as SceneTree
	var quiet := 0
	for _i in 6000:  # hasta 10 min: puede haber una elección larga del jugador
		if not GameManager.is_game_active:
			return false
		quiet = quiet + 1 if is_idle() else 0
		if quiet >= 3:
			return true
		await tree.create_timer(0.1).timeout
	return false


# =============================================================================
# RESOLUCIÓN
# =============================================================================
func _resolve(e: Dictionary) -> void:
	var main := _main()
	if not main:
		return
	var owner_id: int = e.owner
	var data: Dictionary = e.data
	var cause: Dictionary = e.cause
	var by_opp: bool = int(cause.by) == 1 - owner_id
	if e.has("watcher"):
		var w: Node = e.watcher
		if not is_instance_valid(w) or KeywordManager.is_silenced(w) \
				or _used_turn.get(w.get_instance_id(), -1) == GameManager.current_turn:
			return
		match e.kind:
			MANU_TARA:
				await _manu_tara(main, w, owner_id, data)
			FUDO_MYO:
				await _fudo_myo(main, w, owner_id)
		return
	# La propia carta, desde el Cementerio: sin habilidad ahí (Sable de
	# Napoleón) o nombre bloqueado (Alicia) = no dispara.
	if CardManager.is_cemetery_card_silenced(data) or KeywordManager.is_name_locked(str(data.get("nombre", ""))):
		return
	match e.kind:
		LANZA:
			await _lanza(main, owner_id, data)
		KULTRUNG:
			if by_opp and cause.kind in ["effect", "damage", "other"]:
				await _kultrung(main, owner_id, data)
		PIEDRA:
			if by_opp and cause.kind in ["effect", "other"]:
				await _piedra(main, owner_id, data)
		HAKA_PEI:
			if by_opp and cause.kind in ["effect", "other"]:
				await _haka_pei(main, owner_id, data)
		DAIKSUKE:
			if cause.opp_turn:
				await _daiksuke(main, owner_id, data)
		SERPIENTE:
			await _serpiente(main, owner_id, data)
		MANZANA:
			if cause.opp_turn:
				await _manzana(main, owner_id, data)


func _in_cemetery(owner_id: int, data: Dictionary) -> bool:
	for d in CardManager.get_cemetery(owner_id):
		if is_same(d, data):
			return true
	return false


func _take(owner_id: int, data: Dictionary) -> bool:
	"""Saca la carta (esa misma entrada) de su Cementerio."""
	var cem: Array = CardManager.get_cemetery(owner_id)
	for i in range(cem.size()):
		if is_same(cem[i], data):
			cem.remove_at(i)
			CardManager._emit_cemetery_changed(owner_id)
			CardManager._update_cemetery_visual(owner_id)
			return true
	return false


func _proxy(main: Node, owner_id: int, data: Dictionary) -> Node:
	"""Node temporal de una carta del Cementerio (para la ventana de respuesta)."""
	var proxy: Node = main._create_card(data, false)
	proxy.visible = false
	main.add_child(proxy)
	proxy.owner_id = owner_id
	proxy.current_zone = Constants.Zone.CEMENTERIO
	return proxy


func _confirm(main: Node, owner_id: int, title: String, yes: String, no: String = "No") -> bool:
	if PlayerSideScript.is_bot(owner_id):
		return true  # el bot local acepta (sin popup en la pantalla del Anfitrión)
	return await SelectionManager.await_two_choice(main, title, yes, no, owner_id)


func _with_window(source: Node, owner_id: int, card_name: String) -> bool:
	"""Ventana de respuesta del rival para este disparador (después de
	declarar, §59 opción B). true = cancelado."""
	var token: int = EffectContextScript.push(source, owner_id, "disparada", "pending")
	var cancelled: bool = await TriggerSystem.open_response_window(source, card_name, owner_id)
	EffectContextScript.pop(token)
	return cancelled


func _pick_cemetery_cards(owner_id: int, title: String, max_count: int, exclusive: bool,
		exclude: Dictionary = {}) -> Array:
	"""Selector con los dos Cementerios. Devuelve [{owner, data}]."""
	var pools: Array = []
	var src: Array = []
	for zone_owner in [owner_id, 1 - owner_id]:
		var entries: Array = []
		for d in CardManager.get_cemetery(zone_owner):
			entries.append({"data": d, "eligible": not is_same(d, exclude)})
		pools.append({"is_own": zone_owner == owner_id, "zone": Constants.Zone.CEMENTERIO, "cards": entries,
			"exclusive": exclusive})
		src.append(zone_owner)
	var raw: Array = await ActionModule.pick_in_zones(owner_id, title, pools, 0, max_count)
	var picks: Array = []
	var first_pool := -1
	for rp in raw:
		if not (rp is Array) or rp.size() != 2:
			continue
		var pi := int(rp[0])
		var ci := int(rp[1])
		if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			continue
		if first_pool < 0:
			first_pool = pi
		if (exclusive and pi != first_pool) or picks.size() >= max_count:
			continue
		var d: Dictionary = pools[pi].cards[ci].data
		if picks.any(func(p): return is_same(p.data, d)):
			continue
		picks.append({"owner": src[pi], "data": d})
	return picks


func _shuffle_into_castles(main: Node, moves: Array, card_name: String) -> int:
	"""Cada carta vuelve al Castillo de SU dueño (DAR); se baraja cada
	Castillo tocado. moves = [{owner, data}]."""
	var shuffled: Dictionary = {}
	var moved := 0
	for m in moves:
		if not _take(m.owner, m.data):
			continue  # ya no está ahí (en medida de lo posible)
		m.data["esta_oculta"] = true
		CardManager.get_deck(m.owner).append(m.data)
		shuffled[m.owner] = true
		moved += 1
	for p in shuffled:
		CardManager.shuffle_deck(p)
		AnimationQueue.queue_shuffle(p, "Barajar mazo (%s)" % card_name)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return moved


# --- Lanza Argenta: "Baraja esta carta y hasta otras dos cartas de un
# Cementerio en el Castillo de su dueño."
func _lanza(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "Lanza Argenta"))
	main._update_debug("%s fue puesta en tu Cementerio: se dispara su habilidad" % card_name)
	var proxy := _proxy(main, owner_id, data)
	var token: int = EffectContextScript.push(proxy, owner_id, "disparada", "pending")
	var picks := await _pick_cemetery_cards(owner_id,
		"%s: elige hasta otras dos cartas de un Cementerio para barajar con ella" % card_name, 2, true, data)
	var cancelled: bool = await TriggerSystem.open_response_window(proxy, card_name, owner_id)
	EffectContextScript.pop(token)
	proxy.queue_free()
	if cancelled:
		return
	var moved := _shuffle_into_castles(main, [{"owner": owner_id, "data": data}] + picks, card_name)
	main._update_debug("%s: %d carta(s) barajadas en el Castillo" % [card_name, moved])


# --- kultrung: "por un efecto o daño oponente, puedes subirlo a tu mano".
func _kultrung(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "kultrung"))
	if not _in_cemetery(owner_id, data):
		return
	if not await _confirm(main, owner_id, "%s fue puesto en tu Cementerio" % card_name, "Subirlo a tu mano"):
		return
	var proxy := _proxy(main, owner_id, data)
	var cancelled := await _with_window(proxy, owner_id, card_name)
	proxy.queue_free()
	if cancelled or not _take(owner_id, data):
		return
	ActionModule._put_found_card_into_play(main, owner_id, data, false)
	main._update_debug("%s volvió a tu mano" % card_name)


# --- piedra del chaman: "por un efecto oponente, ponlo en tu Oro Pagado".
func _piedra(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "piedra del chaman"))
	# Sin ventana propia: poner el Oro en juego ya le da al rival su ventana
	# (una por efecto, §59 — con las dos, el rival pasaba dos veces).
	if not _take(owner_id, data):
		return
	await main._gold_manager.put_gold_directly_in_pagado(owner_id, data)
	main._update_debug("%s pasó a tu Oro Pagado" % card_name)


# --- haka pei: "por un efecto oponente, juégalo sin pagar su coste y
# Destiérralo". Sin ventana propia: jugarlo ya le da al rival su ventana
# (§59, una por efecto).
func _haka_pei(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "haka pei"))
	if not _take(owner_id, data):
		return
	main._update_debug("%s: se juega sin pagar su coste" % card_name)
	if not await main._gold_manager.play_card_for_free(data, owner_id, true):
		CardManager.add_to_cemetery(owner_id, data)  # no se pudo jugar: vuelve


# --- daiksuke: "durante el turno oponente, juégalo por un Oro menos".
func _daiksuke(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "daiksuke"))
	if not _in_cemetery(owner_id, data):
		return
	var cost: int = maxi(int(data.get("coste", 0)) - 1, 0)
	if main._gold_manager.get_oro_disponible(owner_id) < cost:
		main._update_debug("%s: no tienes Oro para jugarlo (%d)" % [card_name, cost])
		return
	if not _take(owner_id, data):
		return
	if not await PlayerSideScript.pay(main, owner_id, cost):
		CardManager.add_to_cemetery(owner_id, data)
		return
	main._update_debug("%s: se juega por %d Oro(s)" % [card_name, cost])
	if not await main._gold_manager.play_card_for_free(data, owner_id):
		CardManager.add_to_cemetery(owner_id, data)


# --- serpiente verde: "si no controlas Aliados de coste 1 o menos, puedes
# Barajar hasta cuatro cartas de los Cementerios".
func _serpiente(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "serpiente verde"))
	for cont in PlayerSideScript.ally_containers(main, owner_id):
		for c in cont.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO \
					and int(c.get("controller_id") if c.get("controller_id") != null else owner_id) == owner_id \
					and PaymentManager.calcular_coste_real(c) <= 1:
				return  # controlas un Aliado de coste 1 o menos
	var proxy := _proxy(main, owner_id, data)
	var token: int = EffectContextScript.push(proxy, owner_id, "disparada", "pending")
	var picks := await _pick_cemetery_cards(owner_id,
		"%s: puedes barajar hasta cuatro cartas de los Cementerios" % card_name, 4, false)
	var cancelled := false
	if not picks.is_empty():
		cancelled = await TriggerSystem.open_response_window(proxy, card_name, owner_id)
	EffectContextScript.pop(token)
	proxy.queue_free()
	if cancelled or picks.is_empty():
		return
	_shuffle_into_castles(main, picks, card_name)


# --- manzana envenenada: "en el turno oponente, puedes Desterrarla para
# Desterrar dos cartas del tope del Castillo oponente".
func _manzana(main: Node, owner_id: int, data: Dictionary) -> void:
	var card_name := str(data.get("nombre", "manzana envenenada"))
	if not _in_cemetery(owner_id, data):
		return
	if not await _confirm(main, owner_id, "%s fue puesta en tu Cementerio" % card_name,
			"Desterrarla para desterrar 2 del tope del Castillo rival"):
		return
	if not _take(owner_id, data):
		return
	CardManager.append_to_exile(owner_id, data)  # costo
	var proxy := _proxy(main, owner_id, data)
	var cancelled := await _with_window(proxy, owner_id, card_name)
	proxy.queue_free()
	if cancelled:
		return
	var opp := 1 - owner_id
	var deck: Array = CardManager.get_deck(opp)
	for _i in range(2):
		if deck.is_empty():
			break
		var d: Dictionary = deck.pop_front()
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	CardManager._emit_deck_changed(opp)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# --- manu tara (en juego): "Cuando una carta sea puesta en tu Cementerio,
# hasta una vez por turno, puedes Barajarla en tu Castillo".
func _manu_tara(main: Node, watcher: Node, owner_id: int, data: Dictionary) -> void:
	if not _in_cemetery(owner_id, data):
		return
	var card_name := str(watcher.card_name)
	if not await _confirm(main, owner_id, "%s: %s fue puesta en tu Cementerio" % [card_name, str(data.get("nombre", "una carta"))],
			"Barajarla en tu Castillo"):
		return
	_used_turn[watcher.get_instance_id()] = GameManager.current_turn
	if await _with_window(watcher, owner_id, card_name):
		return
	_shuffle_into_castles(main, [{"owner": owner_id, "data": data}], card_name)


# --- fudo-myo (en juego): "Una vez por turno, cuando un Talismán sea puesto
# en tu Cementerio o Destierro, puedes Barajar hasta tres cartas de los
# Cementerios".
func _fudo_myo(main: Node, watcher: Node, owner_id: int) -> void:
	var card_name := str(watcher.card_name)
	var token: int = EffectContextScript.push(watcher, owner_id, "disparada", "pending")
	var picks := await _pick_cemetery_cards(owner_id,
		"%s: puedes barajar hasta tres cartas de los Cementerios" % card_name, 3, false)
	var cancelled := false
	if not picks.is_empty():
		_used_turn[watcher.get_instance_id()] = GameManager.current_turn
		cancelled = await TriggerSystem.open_response_window(watcher, card_name, owner_id)
	EffectContextScript.pop(token)
	if cancelled or picks.is_empty():
		return
	_shuffle_into_castles(main, picks, card_name)
