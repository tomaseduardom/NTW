extends RefCounted
## ActionSearch — SEARCH (Buscar en zona, DAR Sección 8).
## Opera sobre ActionModule via _main (game board, trigger collection,
## validador, filtro de cartas compartido).
## Extraído de ActionModule.gd (Fase 4 de reestructuración, "módulos gordos").

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
var _main: Node


func setup(main: Node) -> void:
	_main = main


func _get_searchable_zone_data(player_id: int, zone: int) -> Variant:
	"""Devuelve el Array de datos (Dictionary) de la zona buscable, o null si
	la zona no es buscable. El Castillo y el Cementerio son las únicas zonas
	con datos de carta reales (no nodos) — Mano/Campo son nodos Card, y
	buscar ahí no tiene sentido en DAR (ya están a la vista).
	Se lee vía CardManager, que está sincronizado por referencia con
	Main.player_deck/player_cemetery (ver CardManager.sync_from_main) — así
	que remover una entrada aquí remueve la carta de verdad."""
	match zone:
		Constants.Zone.CASTILLO:
			return CardManager.get_deck(player_id)
		Constants.Zone.CEMENTERIO:
			return CardManager.get_cemetery(player_id)
		_:
			return null


func search(player_id: int, zone: int, filter: Dictionary, amount: int = 1, can_fail: bool = true, skip_validation: bool = false, may_play: bool = false, source_card: Node = null, destination: int = Constants.Zone.MANO, distinct_names: bool = false, chooser_id: int = -1) -> Dictionary:
	"""Busca cartas en el Castillo o Cementerio que cumplan el filtro (DAR
	Sección 8). El jugador elige cuáles llevarse. Si may_play es true, por
	cada carta encontrada se ofrece jugarla (pagando su coste) o dejarla en
	la mano (si no se puede pagar, queda en la mano — nunca se pierde).

	Args:
		player_id: ID del jugador dueño de la zona buscada (el destino
			también es SUYO — buscar en el Castillo rival y desterrar manda
			al Destierro del rival, no al propio; DAR: la carta sigue siendo
			del jugador de quien salió)
		chooser_id (2026-09-30, Fase 3 del plan de paridad remota): quién
			HACE la elección — no siempre es player_id. 'Busca en el Castillo
			OPONENTE y destiérralas' tiene player_id=oponente (es SU zona/
			destino) pero quien elige qué desterrar es el CONTROLADOR de la
			habilidad, no la víctima. Default -1 = usar player_id.
		zone: Zona donde buscar (CASTILLO o CEMENTERIO — únicas zonas con datos)
		filter: Filtro de cartas {type, raza, cost_max, cost_min, strength_min,
			name_contains, keyword}
		amount: Cantidad máxima a seleccionar
		can_fail: Si puede fallar sin encontrar (false = obligatorio)
		skip_validation: Si omitir validación previa
		destination: Zona final de las cartas encontradas (2026-08-25).
			Constants.Zone.MANO (default, puede jugarse si may_play) o
			Constants.Zone.DESTIERRO (p.ej. Rey de Amarillo: 'busca en un
			Castillo... y Destiérralas' — va directo, sin pasar por la mano).
		distinct_names: Si true, las cartas elegidas no pueden repetir nombre
			entre sí (2026-08-25, p.ej. necro-titan: 'busca... dos cartas de
			distinto nombre').
		may_play: Si true, ofrece jugar cada carta encontrada en vez de solo
			guardarla en mano (DAR: 'puedes ponerla en juego pagando su coste')
		source_card: Carta que causa la búsqueda (para triggers/log)

	Returns: {success, selected, matching, searched_zone, searched_zones}
	"""
	return await search_zones(player_id, [zone], filter, amount, can_fail, skip_validation, may_play, source_card,
		destination, distinct_names, chooser_id)


func search_zones(player_id: int, zones: Array, filter: Dictionary, amount: int = 1, can_fail: bool = true,
		skip_validation: bool = false, may_play: bool = false, source_card: Node = null,
		destination: int = Constants.Zone.MANO, distinct_names: bool = false, chooser_id: int = -1,
		cost_reduction: int = 0) -> Dictionary:
	"""Como search(), pero sobre VARIAS zonas del mismo jugador a la vez
	(2026-10-11, a pedido del usuario — p.ej. Arturo de Bretaña: 'busca en
	tu Castillo y/o Cementerio hasta dos Armas'): el jugador mira cada zona
	en el selector del tablero (ZoneBrowsePicker), puede mezclar cartas de
	ambas y confirma una sola vez. Reemplaza al viejo "¿Dónde buscar?"
	(Castillo o Cementerio) + lista de una sola zona.
	'cost_reduction': con may_play, descuento al jugarla ('reduciendo su
	coste en un Oro'), con el piso 1 de siempre de PaymentManager."""
	var first_zone: int = zones[0] if not zones.is_empty() else Constants.Zone.CASTILLO
	var result = {
		"success": true,
		"selected": [],
		"matching": [],
		"searched_zone": first_zone,
		"searched_zones": zones,
		"must_shuffle": Constants.Zone.CASTILLO in zones
	}

	# DAR Sección 6: validar cada zona; las que no se pueden buscar se omiten.
	var zone_infos: Array = []  # [{zone, data, matching}]
	var last_reason: String = "unsupported_zone"
	for zone in zones:
		if not skip_validation:
			var validation = _main._validator._validate_search(player_id, zone, filter, amount)
			if not validation.valid:
				last_reason = validation.reason
				print("[ActionModule] SEARCH en zona %s rechazado: %s" % [zone, validation.reason])
				continue
			if not validation.warnings.is_empty():
				result.warnings = validation.warnings
		var zone_data = _get_searchable_zone_data(player_id, zone)
		if zone_data == null:
			push_warning("[ActionModule] SEARCH: zona no buscable (%s)" % zone)
			continue
		zone_infos.append({"zone": zone, "data": zone_data, "matching": []})
	if zone_infos.is_empty():
		result.success = can_fail
		result.error = last_reason
		result.validation_failed = true
		return result

	_main._begin_trigger_collection()

	for info in zone_infos:
		_main.emit_signal("action_search_started", player_id, info.zone, filter)
		info.matching = _main._apply_card_filter(info.data, filter)
		result.matching.append_array(info.matching)

	_main.emit_signal("action_search_revealed", player_id, result.matching)

	if result.matching.is_empty():
		result.success = can_fail
		if not can_fail:
			result.error = "no_matching_cards"
		_main.emit_signal("action_search_completed", player_id, result)
		await _main._end_trigger_collection_and_resolve()
		return result

	var to_select = mini(amount, result.matching.size())
	var effective_chooser: int = chooser_id if chooser_id >= 0 else player_id
	var min_count: int = 0 if can_fail else to_select
	var picks: Array = await _pick_from_zones(player_id, zone_infos, to_select, min_count, distinct_names,
		effective_chooser, source_card)

	var selected_data: Array = []
	for p in picks:
		selected_data.append(p.data)
	result.selected = selected_data
	_main.emit_signal("action_search_selected", player_id, selected_data)

	var main := _main.get_node_or_null("/root/Main")
	for p in picks:
		var card_data: Dictionary = p.data
		var from_zone: int = p.zone
		# Remover de la zona de origen (misma referencia que Main.player_deck/
		# player_cemetery — ver _get_searchable_zone_data).
		p.zone_data.erase(card_data)
		card_data["esta_oculta"] = false
		await _deliver(main, player_id, card_data, from_zone, destination, may_play, cost_reduction, result)

	# Barajar si buscó en el Castillo (DAR: siempre se baraja tras buscar en el
	# mazo, aunque al final la carta elegida haya salido de otra zona).
	if result.must_shuffle:
		var deck = _get_searchable_zone_data(player_id, Constants.Zone.CASTILLO)
		if deck != null:
			deck.shuffle()
		AnimationQueue.queue_shuffle(player_id, "Barajar mazo")

	# 2026-09-14, a pedido del usuario (La Ouija): buscar en el Castillo saca
	# cartas y después lo baraja (arriba), pero esta función genérica nunca
	# llamaba a ZoneManager._update_castillo_counts(), el único punto de
	# verdad real para refrescar tanto el contador visible del Castillo como
	# el revelado del tope de La Ouija (ver ZoneViewerModule.
	# refresh_castillo_top_reveal()).
	if result.must_shuffle and main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()

	_main.emit_signal("action_search_completed", player_id, result)

	await _main._end_trigger_collection_and_resolve()

	return result


func _deliver(main: Node, player_id: int, card_data: Dictionary, from_zone: int, destination: int,
		may_play: bool, cost_reduction: int, result: Dictionary) -> void:
	"""Lleva una carta encontrada a su destino (del dueño 'player_id')."""
	if destination == Constants.Zone.DESTIERRO:
		# Va directo al Destierro, sin pasar por la mano ni crear un
		# nodo Card (2026-08-25, p.ej. Rey de Amarillo).
		CardManager.add_to_exile(player_id, card_data)
		_main._notify_trigger("on_search_found", {
			"player_id": player_id, "card": card_data, "from_zone": from_zone
		})
	elif destination == Constants.Zone.RESERVA_ORO and main and main._gold_manager:
		# Va directo a la Reserva de Oro, sin pasar por la mano ni pagar
		# coste (2026-08-29, p.ej. Don de Amma: 'busca un Oro en tu
		# Castillo y ponlo en tu Reserva').
		var card_node = await main._gold_manager.put_gold_directly_in_reserva(player_id, card_data)
		_main._notify_trigger("on_search_found", {
			"player_id": player_id, "card": card_node, "from_zone": from_zone
		})
	elif destination == Constants.Zone.CEMENTERIO:
		# Va directo al Cementerio, sin pasar por la mano ni crear un
		# nodo Card (2026-09-04, p.ej. kitsune - sp: 'busca en tu
		# Castillo un Aliado y ponlo en tu mano o Cementerio') — mismo
		# patrón que DESTIERRO de arriba.
		CardManager.add_to_cemetery(player_id, card_data)
		_main._notify_trigger("on_search_found", {
			"player_id": player_id, "card": card_data, "from_zone": from_zone
		})
	elif destination == Constants.Zone.CASTILLO:
		# "Baraja N cartas de tu Cementerio en tu Castillo" (2026-10-12,
		# EffectInterpreter, p.ej. Cathach) — vuelve al mazo oculta y se
		# baraja abajo, mismo selector de zonas que el resto de búsquedas.
		card_data["esta_oculta"] = true
		CardManager.get_deck(player_id).append(card_data)
		result.must_shuffle = true
	elif destination == Constants.Zone.ORO_PAGADO and main and main._gold_manager:
		# Va directo al Oro Pagado (ya-gastado), sin pasar por la mano
		# (2026-09-04, p.ej. Aurora de Chile: 'pon uno en tu Oro Pagado y
		# otro en tu mano') — mismo patrón que RESERVA_ORO de arriba, pero
		# usando put_gold_directly_in_pagado() en vez de _in_reserva().
		var card_node = await main._gold_manager.put_gold_directly_in_pagado(player_id, card_data)
		_main._notify_trigger("on_search_found", {
			"player_id": player_id, "card": card_node, "from_zone": from_zone
		})
	elif main:
		var card_node = await _put_found_card_into_play(main, player_id, card_data, may_play, cost_reduction)
		_main._notify_trigger("on_search_found", {
			"player_id": player_id, "card": card_node, "from_zone": from_zone
		})


func search_either_owner(chooser: int, zones: Array, filter: Dictionary, amount: int, can_fail: bool = true,
		source_card: Node = null, destination: int = Constants.Zone.MANO, distinct_names: bool = false) -> Dictionary:
	"""'Busca en UN Castillo / un Cementerio' sin posesivo (2026-10-14, a
	pedido del usuario — voragh el devorador: elegía el rival y el bot se
	quedaba con las 2 primeras sin mostrarte nada). El selector del tablero
	con las zonas de LOS DOS jugadores: quien elige mira lo que quiera, pero
	al abrir un Castillo queda atado a ese (los Cementerios son públicos y se
	pueden seguir mirando). Cada carta va al destino de SU dueño (DAR) y todo
	Castillo mirado se baraja."""
	var result := {"success": true, "selected": [], "matching": []}
	var pools: Array = []
	var src: Array = []  # [{owner, zone, data}] en el mismo orden que pools
	for zone_owner in [chooser, 1 - chooser]:
		for zone in zones:
			var zone_data = _get_searchable_zone_data(zone_owner, zone)
			if zone_data == null:
				continue
			var matching: Array = _main._apply_card_filter(zone_data, filter)
			var cards: Array = []
			for d in zone_data:
				cards.append({"data": d, "eligible": matching.has(d)})
			pools.append({"is_own": zone_owner == chooser, "zone": zone, "cards": cards})
			src.append({"owner": zone_owner, "zone": zone, "data": zone_data})
			result.matching.append_array(matching)
	if result.matching.is_empty():
		result.success = can_fail
		return result

	EffectContextScript.check_chooser(chooser, "buscar")
	var title: String = "Buscar"
	if source_card and source_card.get("card_name") != null:
		title = "%s: elige hasta %d carta(s)" % [str(source_card.card_name), amount]
	var info: Dictionary = {}
	var raw_picks: Array = await pick_in_zones(chooser, title, pools, 0, amount, distinct_names, [], info)

	# Revalidación + un solo Castillo (por red puede llegar cualquier cosa).
	var picks: Array = []
	var locked := -1
	for p in _validated_picks(raw_picks, pools, src, amount, distinct_names):
		if p.zone == Constants.Zone.CASTILLO:
			if locked < 0:
				locked = p.pool
			elif p.pool != locked:
				continue
		picks.append(p)

	var main := _main.get_node_or_null("/root/Main")
	_main._begin_trigger_collection()
	var to_shuffle: Dictionary = {}
	for pi in info.get("opened_castles", []):
		var i := int(pi)
		if i >= 0 and i < pools.size() and pools[i].zone == Constants.Zone.CASTILLO:
			to_shuffle[src[i].owner] = true
	for p in picks:
		var zone_owner: int = src[p.pool].owner
		var card_data: Dictionary = p.data
		p.zone_data.erase(card_data)
		card_data["esta_oculta"] = false
		result.selected.append(card_data)
		if p.zone == Constants.Zone.CASTILLO:
			to_shuffle[zone_owner] = true
		await _deliver(main, zone_owner, card_data, p.zone, destination, false, 0, result)
	for zone_owner in to_shuffle:
		CardManager.get_deck(zone_owner).shuffle()
		AnimationQueue.queue_shuffle(zone_owner, "Barajar mazo")
	if not to_shuffle.is_empty() and main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	_main.emit_signal("action_search_selected", chooser, result.selected)
	await _main._end_trigger_collection_and_resolve()
	return result


func _pick_from_zones(player_id: int, zone_infos: Array, to_select: int, min_count: int, distinct_names: bool,
		chooser: int, source_card: Node) -> Array:
	"""Elección real de las cartas (2026-10-11): siempre con ZoneBrowsePicker
	— en la pantalla del Anfitrión si elige él, por red si elige un Remoto
	real (el Remoto corre el mismo selector y devuelve índices), o automática
	para el bot local. Devuelve [{zone, zone_data, data}]."""
	EffectContextScript.check_chooser(chooser, "buscar")
	var main := _main.get_node_or_null("/root/Main")
	var title: String = "Buscar"
	if source_card and source_card.get("card_name") != null:
		title = "%s: elige hasta %d carta(s)" % [str(source_card.card_name), to_select]

	# Pools completos (todas las cartas de cada zona, elegibles marcadas) —
	# el jugador ve la zona entera, como al buscar en un mazo físico.
	var pools: Array = []
	for info in zone_infos:
		var cards: Array = []
		for d in info.data:
			cards.append({"data": d, "eligible": info.matching.has(d)})
		pools.append({"is_own": player_id == chooser, "zone": info.zone, "cards": cards})

	var raw_picks: Array = await pick_in_zones(chooser, title, pools, min_count, to_select, distinct_names)
	return _validated_picks(raw_picks, pools, zone_infos, to_select, distinct_names)


func pick_in_zones(chooser: int, title: String, pools: Array, min_count: int, max_count: int,
		distinct_names: bool = false, hand_nodes: Array = [], out_info: Dictionary = {}) -> Array:
	"""Selector de zonas para QUIEN elige (2026-10-12, a pedido del usuario:
	"todos los cambios siempre tienen que ser para el Remoto igual"): en la
	pantalla del Anfitrión, por red en la del Remoto (corre el mismo
	ZoneBrowsePicker, también con sus cartas de la mano), o automático para
	el bot local. 'pools' con is_own relativo a 'chooser'; 'hand_nodes'
	(opcional) = cartas de la mano de 'chooser' también elegibles. Devuelve
	[[pool_idx, card_idx]], con pool_idx -1 para una carta de hand_nodes.
	El llamador revalida (por red puede llegar cualquier cosa).
	'out_info' (2026-10-14): se llena con "opened_castles" = índices de los
	pools de Castillo que quien elige llegó a mirar (hay que barajarlos)."""
	var main := _main.get_node_or_null("/root/Main")
	var raw_picks: Array = []
	if chooser == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		raw_picks = await _delegate_zone_pick_to_remote(title, pools, min_count, max_count, distinct_names, hand_nodes, out_info)
	elif chooser == 1 or not main or not main.get("_zone_browse_picker") or not main._zone_browse_picker:
		# Bot local (o sin selector disponible): las primeras elegibles.
		for pi in range(pools.size()):
			for ci in range(pools[pi].cards.size()):
				if raw_picks.size() < max_count and pools[pi].cards[ci].eligible:
					raw_picks.append([pi, ci])
		if raw_picks.is_empty() and not hand_nodes.is_empty() and min_count > 0:
			raw_picks.append([-1, 0])
		var opened: Array = []
		for rp in raw_picks:
			if rp[0] >= 0 and pools[rp[0]].zone == Constants.Zone.CASTILLO and not opened.has(rp[0]):
				opened.append(rp[0])
		out_info["opened_castles"] = opened
	else:
		raw_picks = await main._zone_browse_picker.pick(title, pools, min_count, max_count, distinct_names, hand_nodes)
		out_info["opened_castles"] = main._zone_browse_picker.last_opened_castles()
	return raw_picks


func _validated_picks(raw_picks: Array, pools: Array, zone_infos: Array, to_select: int, distinct_names: bool) -> Array:
	"""Revalida lo elegido (por red puede llegar cualquier cosa): índices
	válidos, solo elegibles, sin repetir, tope to_select, nombres distintos."""
	var picks: Array = []
	var seen: Dictionary = {}
	var names: Dictionary = {}
	for rp in raw_picks:
		if not (rp is Array) or rp.size() != 2:
			continue
		var pi: int = int(rp[0])
		var ci: int = int(rp[1])
		if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size():
			continue
		var key := "%d:%d" % [pi, ci]
		if seen.has(key) or not pools[pi].cards[ci].eligible or picks.size() >= to_select:
			continue
		var data: Dictionary = pools[pi].cards[ci].data
		var card_name := str(data.get("nombre", data.get("name", "")))
		if distinct_names and names.has(card_name):
			continue
		seen[key] = true
		names[card_name] = true
		picks.append({"zone": zone_infos[pi].zone, "zone_data": zone_infos[pi].data, "data": data, "pool": pi})
	return picks


func _delegate_zone_pick_to_remote(title: String, pools: Array, min_count: int, max_count: int,
		distinct_names: bool, hand_nodes: Array = [], out_info: Dictionary = {}) -> Array:
	"""Contraparte en red del selector: el Remoto lo corre en su pantalla
	(RemoteMirrorController._show_zone_pick_prompt()). 'is_own' ya viene
	relativo al Remoto (chooser == 1). Las cartas de la mano viajan por id
	(get_instance_id(), el mismo que usa hand_card_added para su mano
	espejo)."""
	var hand_ids: Array = []
	for c in hand_nodes:
		if is_instance_valid(c):
			hand_ids.append(str(c.get_instance_id()))
	NetworkClient.send_message({
		"op": "prompt", "kind": "zone_pick",
		"title": title,
		"pools": pools,
		"min_selections": min_count,
		"max_selections": max_count,
		"distinct_names": distinct_names,
		"hand_card_ids": hand_ids,
	})
	var intent: Dictionary = await NetworkClient.await_intent(["zone_pick_choice"])
	out_info["opened_castles"] = intent.get("opened_castles", [])
	return intent.get("picks", [])


func _put_found_card_into_play(main: Node, player_id: int, card_data: Dictionary, may_play: bool,
		cost_reduction: int = 0) -> Node:
	"""Instancia la carta encontrada y la mete en la mano. Con may_play
	(2026-10-11: ahora pregunta — 'puedes jugarla' es opcional, y Arturo de
	Bretaña dice 'puedes jugarlas... y/o ponerlas en tu mano'), ofrece
	jugarla de inmediato pagando su coste (con 'cost_reduction' si el efecto
	lo da). Si no se puede pagar o se elige la mano, se queda en la mano —
	nunca se pierde."""
	var is_hidden := player_id != 0
	var card_node = main._create_card(card_data, is_hidden)

	if player_id == 0:
		main.player_hand.add_card(card_node)
		main._connect_card_signals(card_node)
	else:
		main._opponent_fan.add_card(card_node)
		# 2026-09-14, mismo bug real que ZoneManager.draw_card() (ver ese
		# comentario) — faltaba aquí también.
		main._connect_card_signals(card_node)

	var can_decide: bool = player_id == 0 or main.get("_easy_bot") is RemotePlayerController
	if may_play and can_decide:
		await _main.get_tree().create_timer(0.3).timeout
		if cost_reduction > 0:
			PaymentManager.agregar_modificador_coste(card_node, -cost_reduction, func(c: Node) -> bool:
				return c == card_node, false)
		if PaymentManager.puede_jugar_carta(card_node, player_id):
			var coste: int = PaymentManager.calcular_coste_real(card_node)
			var card_name: String = str(card_data.get("nombre", "la carta"))
			var play_it: bool = await SelectionManager.await_two_choice(main, card_name,
				"Jugarla (coste %d)" % coste, "Ponerla en tu mano", player_id)
			if play_it:
				# 2026-10-12 (§57): play_card() es solo del Anfitrión ("No es
				# tu turno" para el jugador 1).
				await PlayerSideScript.play_from_hand(main, player_id, card_node)
		# Si no puede pagarla o eligió la mano, se queda en la mano.
		if cost_reduction > 0:
			PaymentManager.remover_modificador_coste(card_node)

	return card_node
