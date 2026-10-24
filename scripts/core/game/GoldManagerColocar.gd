extends "res://scripts/core/game/GoldManagerPago.gd"
## GoldManagerColocar — familia Colocar de GoldManager.gd (ver GoldManagerBase.gd).


func _place_card_as_gold(card: Node) -> void:
	# controller_id, no owner_id: el lado del tablero lo decide quién controla la carta
	# (arquitectura.md §38).
	var player_id: int = card.controller_id
	var hand_container = _main.player_hand if player_id == 0 else _main._opponent_fan
	var gold_container = _main.player_gold if player_id == 0 else _main.opponent_gold
	if card.get_parent() != hand_container:
		_main._update_debug("Solo puedes colocar cartas de la mano como Oro")
		return
	if card.card_type != Constants.CardType.ORO:
		_main._update_debug("Solo puedes colocar cartas de tipo Oro")
		return
	if _no_gold_turn.get(player_id, "") == "active":
		_main._update_debug("No puedes poner Oros en juego este turno (Escarapela Nacional)")
		if _main._card_interaction: _main._card_interaction.is_placing_gold = false
		return
	if not TurnManager.can_place_oro(GameManager.current_phase, card):
		_main._update_debug("No puedes colocar Oro ahora")
		if _main._card_interaction: _main._card_interaction.is_placing_gold = false
		return
	if PriorityManager.priority_window_active:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de colocar otro Oro")
		if _main._card_interaction: _main._card_interaction.is_placing_gold = false
		return
	var start_pos = card.global_position
	var idx = hand_container.cards.find(card)
	if idx >= 0:
		hand_container.cards.remove_at(idx)
	hand_container.remove_child(card)
	hand_container._arrange_cards()
	card.can_interact = false
	gold_container.add_child(card)
	update_gold_containers_spacing()
	card.top_level = false
	card.set_zone(Constants.Zone.RESERVA_ORO)
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	# Oro más chico en la Reserva para ganar espacio. Constants.GOLD_CARD_SCALE es el único valor
	# (también lo usan GameBootstrap, las fichas virtuales y el Oro Pagado directo);
	# _mover_oro_a_pagado()/_mover_oro_a_reserva() no tocan la escala.
	card.scale = Constants.GOLD_CARD_SCALE
	# base_scale ANTES del tween: CardInteraction calcula el tamaño de reposo con base_scale; si llega
	# tarde, un hover durante la animación la devuelve a tamaño completo.
	card.base_scale = Constants.GOLD_CARD_SCALE
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	card.can_interact = true
	TurnManager.oro_placed_this_turn = true
	TurnManager.any_card_played_this_turn = true
	if player_id == 0:
		_main.gold_cards.append(card)
	GameState.agregar_oro_reserva(player_id, 1)
	_register_gold_placed(player_id)
	var oro_actual = GameState.get_oro_reserva(player_id)
	_main._update_debug("%s colocado como Oro (Reserva: %d)" % [card.card_name, oro_actual])
	if _main._card_interaction: _main._card_interaction.is_placing_gold = false
	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
	# Corazón de Dragón ("entra en juego como una copia de un Oro que controle tu oponente"): es una
	# condición de juego, se resuelve aquí antes del ETB genérico. load_from_data() reemplaza
	# nombre/habilidad, así que el ETB del Oro copiado (p.ej. Drácula: Roba dos) dispara normal.
	if _is_become_opponent_gold_copy_text(card):
		await _resolve_become_opponent_gold_copy(card)
	# Los Oros también pueden tener habilidades "Al entrar" (p.ej. Signo
	# Amarillo: "mira 4 cartas del tope") — este camino nunca las disparaba,
	# a diferencia de _play_card_to_field()/_play_talisman() que sí lo hacen.
	await _trigger_enter_play(card, Constants.Zone.RESERVA_ORO)


func _is_become_opponent_gold_copy_text(card: Node) -> bool:
	var habilidad: String = str(card.get("card_ability")) if card.get("card_ability") != null else ""
	return "entra en juego como una copia de un oro que controle tu oponente" in habilidad.to_lower()


func _resolve_become_opponent_gold_copy(card: Node) -> void:
	"""Convierte 'card' (Corazón de Dragón, ya colocado en su Reserva) en una
	copia completa (nombre, habilidad, keywords, fuerza, imagen — todo lo
	que load_from_data() carga) de un Oro elegido en la Reserva rival.
	instance_id sigue siendo el propio de 'card' (Card.gd no lo toca), así
	que ninguna referencia externa (contenedor, señales ya conectadas) se
	rompe — solo cambia QUÉ carta representa visualmente y funcionalmente."""
	var player_id: int = card.controller_id
	if not _main._card_interaction:
		return
	# Reserva y Oro Pagado del rival ("un Oro que controle tu oponente" incluye los pagados), sin las
	# fichas de Oro Virtual.
	var rival_id: int = 1 - player_id
	var token_nodes: Array = virtual_gold_tokens.get(rival_id, []).duplicate()
	for pool in restricted_gold_pools.get(rival_id, []):
		token_nodes.append_array(pool.tokens)
	var candidates: Array = []
	for rival_zone in [PlayerSideScript.gold_reserva(_main, rival_id), PlayerSideScript.oro_pagado(_main, rival_id)]:
		if not rival_zone:
			continue
		for c in rival_zone.get_children():
			if is_instance_valid(c) and c != card and not (c in token_nodes) and c.get("card_data") is Dictionary:
				candidates.append(c)
	if candidates.is_empty():
		_main._update_debug("No hay ningún Oro rival para copiar — %s se queda sin habilidad" % card.card_name)
		return
	var filter := func(c: Node) -> bool:
		return c in candidates
	# Condición de juego: no se puede rechazar. El bot elige solo (sin popup en la pantalla del
	# Anfitrión).
	var target: Node = null
	if PlayerSideScript.is_bot(player_id):
		target = candidates[0]
	else:
		target = await _main._card_interaction.await_target("Elige un Oro rival para copiar", filter, false, player_id)
	if not target or not is_instance_valid(target):
		return
	var copied_data: Dictionary = target.card_data.duplicate(true)
	card.load_from_data(copied_data, false)
	_main._update_debug("%s entra en juego como copia de %s" % [card.card_name, target.card_name])


func _has_card_named_in_play(name_lower: String) -> bool:
	"""Busca por nombre (sin distinguir mayúsculas) en las zonas de campo y Oro de ambos jugadores —
	para restricciones "mientras X esté en juego" (p.ej. Armería del Guerrero)."""
	for field in [_main.player_field, _main.opponent_field, _main.player_linea_ataque, _main.opponent_linea_ataque,
			_main.player_linea_apoyo, _main.opponent_linea_apoyo,
			_main.player_gold, _main.opponent_gold, _main.player_oro_pagado, _main.opponent_oro_pagado]:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and str(c.get("card_name")).to_lower() == name_lower:
				return true
	return false


func _register_armeria_opponent_turn_trigger(card: Node) -> void:
	"""Armería del Guerrero: "al comienzo del turno oponente, Baraja y/o Destierra hasta dos cartas de
	los Cementerios". El Oro Inicial no pasa por _trigger_enter_play() (lo coloca GameBootstrap),
	por eso se conecta aquí; se reevalúa en cada turn_started."""
	var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	if not ("al comienzo del turno oponente" in ability_text.to_lower()):
		return
	var handler: Callable
	handler = func(new_active_player: int, _turn: int) -> void:
		if not is_instance_valid(card) or not card.is_in_play():
			if GameManager.turn_started.is_connected(handler):
				GameManager.turn_started.disconnect(handler)
			return
		var owner: int = card.owner_id if card.get("owner_id") != null else 0
		if new_active_player == owner:
			return  # es el turno DE ella, no el del oponente
		if owner != 0:
			return  # el bot todavía no resuelve esta elección interactiva
		await _resolve_armeria_barajar_desterrar()
	GameManager.turn_started.connect(handler)


func _resolve_armeria_barajar_desterrar(max_amount: int = 2, title: String = "Armería del Guerrero", chooser_id: int = 0) -> Array:
	"""Elige hasta 'max_amount' cartas de los dos Cementerios y, por cada una, Barajarla en el
	Castillo de su dueño o Desterrarla. Genérica: Armería del Guerrero, Belta, Perla de Sangre,
	Uriel, Torre de Babel, y el compilador ("Baraja y/o Destierra hasta N..."). La elección de
	cartas es con click en el Cementerio; Barajar/Desterrar por carta es un diálogo de dos botones
	(arquitectura.md §10.16/§10.18). Devuelve los datos de las cartas movidas (Ofrendas al Dragón cuenta
	sus tipos)."""
	var moved: Array = []
	if not _main._zone_viewer:
		return moved
	var no_filter := func(_c: Node) -> bool: return true
	var card_w := "carta" if max_amount == 1 else "cartas"
	var picked: Array = await _main._zone_viewer.open_cemetery_target_picker(
		"%s — elige hasta %d %s de los Cementerios" % [title, max_amount, card_w], no_filter, max_amount,
		"cemetery", false, false, chooser_id)
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		var idx: int = CardManager.get_cemetery(owner_of_picked).find(picked_data)
		if idx < 0:
			continue
		var shuffle_it: bool = await SelectionManager.await_two_choice(
			_main, "¿Qué hacer con esa carta?", "Barajarla (vuelve a su Castillo)", "Desterrarla", chooser_id)
		CardManager.remove_from_cemetery(owner_of_picked, idx)
		if shuffle_it:
			CardManager.get_deck(owner_of_picked).append(picked_data)
			CardManager.shuffle_deck(owner_of_picked)
			# Animación de barajado para que se vea.
			AnimationQueue.queue_shuffle(owner_of_picked, "Barajar mazo (%s)" % title)
		else:
			CardManager.add_to_exile(owner_of_picked, picked_data)
		moved.append(picked_data)
	return moved


func put_gold_directly_in_reserva(player_id: int, card_data: Dictionary) -> Node:
	"""Pone un Oro directo en la Reserva de un jugador sin pasar por la mano ("busca un Oro en tu
	Castillo y ponlo en tu Reserva", p.ej. Don de Amma). Mismo aspecto que el Oro Inicial.
	Es el punto real de "poner un Oro en juego por efectos": aplica Armería del Guerrero ("no
	pueden poner Oros en juego por efectos si ya lo hicieron esta partida") a los dos jugadores,
	solo si hay una en juego."""
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return null
	if _has_card_named_in_play("armería del guerrero") and _oro_por_efecto_used_game.get(player_id, false):
		_main._update_debug("Ya pusiste un Oro en juego por efectos esta partida (Armería del Guerrero)")
		return null
	_oro_por_efecto_used_game[player_id] = true
	oros_en_juego_turno[player_id] = oros_en_juego_turno.get(player_id, 0) + 1
	_note_gold_event(player_id)

	var card_node = _main._create_card(card_data, false)  # Oro es información pública (DAR), boca arriba siempre
	card_node.owner_id = player_id
	card_node.can_interact = true
	card_node.scale = Constants.GOLD_CARD_SCALE
	card_node.base_scale = Constants.GOLD_CARD_SCALE
	_main._connect_card_signals(card_node)
	var target_container: HBoxContainer = _main.player_gold if player_id == 0 else _main.opponent_gold
	target_container.add_child(card_node)
	card_node.set_zone(Constants.Zone.RESERVA_ORO)
	card_node._refresh_disabled_rotation()
	if player_id == 0:
		_main.gold_cards.append(card_node)
	GameState.agregar_oro_reserva(player_id, 1)
	if player_id == 0:
		_update_gold_display()
	await _trigger_enter_play(card_node, Constants.Zone.RESERVA_ORO)
	return card_node
