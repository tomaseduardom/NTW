extends "res://scripts/core/effects/triggers/EffectControllerAcciones.gd"
## EffectControllerPrevencion — familia Prevencion de EffectController.gd (ver EffectControllerBase.gd).


# =============================================================================
# PREVENCIÓN "SALE DEL JUEGO" (DAR - Utilizar Habilidades: Prevenir)
# =============================================================================


func add_blanket_leave_play_immunity(player_id: int) -> void:
	"""Activa la inmunidad para TODOS los Aliados de player_id hasta que
	vuelva a empezar SU turno (GameManager.turn_started con ese player_id)."""
	if _blanket_leave_play_immunity.get(player_id, false):
		return  # Ya activa — no hace falta una segunda conexión
	_blanket_leave_play_immunity[player_id] = true
	print("[EffectController] Inmunidad de salida del juego activada para J%d (hasta su próximo turno)" % (player_id + 1))
	var clear_it_box: Array = []  # la lambda captura por valor: se desconecta por aquí
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != player_id:
			return
		_blanket_leave_play_immunity[player_id] = false
		if GameManager.turn_started.is_connected(clear_it_box[0]):
			GameManager.turn_started.disconnect(clear_it_box[0])
		print("[EffectController] Inmunidad de salida del juego terminó para J%d" % (player_id + 1))
	clear_it_box.append(clear_it)
	GameManager.turn_started.connect(clear_it)


func add_leave_play_immunity_this_turn(player_id: int) -> void:
	_leave_play_immunity_turn[player_id] = GameManager.turn_serial


func add_single_card_leave_play_immunity(card: Node, player_id: int) -> void:
	"""Activa la inmunidad para ESTA carta hasta que vuelva a empezar el
	turno de player_id (el controlador de la fuente, no necesariamente el
	dueño de 'card' — DAR: la protección la otorga QUIEN controla el
	efecto)."""
	if not is_instance_valid(card):
		return
	var id := card.get_instance_id()
	if _single_card_leave_play_immunity.get(id, false):
		return  # ya activa — no hace falta una segunda conexión
	_single_card_leave_play_immunity[id] = true
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Carta"
	print("[EffectController] Inmunidad de salida del juego activada para %s (hasta el próximo turno de J%d)" % [card_name, player_id + 1])
	var clear_it_box: Array = []  # la lambda captura por valor: se desconecta por aquí
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != player_id:
			return
		_single_card_leave_play_immunity.erase(id)
		if GameManager.turn_started.is_connected(clear_it_box[0]):
			GameManager.turn_started.disconnect(clear_it_box[0])
	clear_it_box.append(clear_it)
	GameManager.turn_started.connect(clear_it)

# =============================================================================
# PREVENCIÓN REACTIVA (DAR — Utilizar Habilidades: Prevenir)
# =============================================================================


## Mitad "Anular" de Almirante Akari — disparador DISTINTO al registro de
## arriba (reacciona a "tu oponente juega una carta", no a "un efecto
## oponente afecta a un Aliado"). Llamar justo después de que 'played_card'
## termine de entrar en juego, del lado de QUIEN LA JUGÓ (ver GoldManager.
## _trigger_enter_play()/EasyBotController._play_ally()) — comprueba si el
## RIVAL de quien jugó controla un Akari disponible y la carta jugada cuesta
## 2 o menos; si el jugador confirma, paga el mismo costo compartido
## (_pay_akari_shuffle_cost) y Anula (destruye) la carta recién jugada.
func offer_counter_annul(played_card) -> void:  # sin tipo: puede llegar ya liberada
	if not is_instance_valid(played_card):
		return
	var played_owner: int = played_card.controller_id if played_card.get("controller_id") != null else 0
	var defender_id: int = 1 - played_owner
	if defender_id != 0:
		return  # el bot no responde todavía
	var cost = played_card.get("card_cost")
	if cost == null or int(cost) > 2:
		return

	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
		main.player_gold, main.player_oro_pagado]
	var akari: Node = null
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			var ability_text: String = str(card.card_ability) if card.get("card_ability") != null else ""
			if "anular una carta de coste 2 o menos" in ability_text.to_lower() \
					and not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial):
				akari = card
				break
		if akari:
			break
	if not akari:
		return

	var use_it: bool = await SelectionManager.await_two_choice(
		main, "¿Usar Almirante Akari para Anular a %s?" % str(played_card.get("card_name")), "Sí", "No")
	if not use_it:
		return
	var paid: bool = await _pay_akari_shuffle_cost(akari)
	if not paid:
		return
	UniversalCardParser.turn_registry.register(str(akari.get_instance_id()), 0, GameManager.turn_serial)
	if not is_instance_valid(played_card):
		return
	await ActionModule.destroy([played_card], akari, true, true)


## flechar xoon: "Una vez por turno, puedes subir una carta que controles a la mano de su dueño para
## Anular un Talismán o Tótem de coste 2 o menos". Mismo mecanismo que offer_counter_annul()
## (Almirante Akari): "Anular X de coste N" se implementa como "cuando esa carta termina de
## entrar/resolver, puedes Destruirla". Llamar desde el mismo punto que offer_counter_annul(), del
## lado de quien la jugó.
func offer_flechar_xoon_annul(played_card) -> void:  # sin tipo: puede llegar ya liberada
	if not is_instance_valid(played_card):
		return
	var played_type = played_card.get("card_type")
	if played_type != Constants.CardType.TALISMAN and played_type != Constants.CardType.TOTEM:
		return
	var played_owner: int = played_card.controller_id if played_card.get("controller_id") != null else 0
	var defender_id: int = 1 - played_owner
	if defender_id != 0:
		return  # el bot no responde todavía
	var cost = played_card.get("card_cost")
	if cost == null or int(cost) > 2:
		return

	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo]
	var xoon: Node = null
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			var ability_text: String = str(card.card_ability) if card.get("card_ability") != null else ""
			if "para anular un talism" in ability_text.to_lower() \
					and not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial):
				xoon = card
				break
		if xoon:
			break
	if not xoon:
		return

	var use_it: bool = await SelectionManager.await_two_choice(
		main, "¿Usar %s para Anular a %s?" % [str(xoon.get("card_name")), str(played_card.get("card_name"))], "Sí", "No")
	if not use_it:
		return

	# Costo: subir una carta que controles a la mano de su dueño (mismo
	# criterio de picker que _pay_akari_shuffle_cost(), pero el destino es la
	# MANO, no el Mazo — "subir a la mano" es literal, no "Barajar").
	if not main._card_interaction:
		return
	var own_cards: Array = []
	for field in fields:
		if field:
			own_cards.append_array(field.get_children())
	if own_cards.is_empty():
		main._update_debug("%s: no controlas ninguna carta para subir a la mano" % str(xoon.get("card_name")))
		return
	var cost_filter := func(c: Node) -> bool: return c in own_cards
	var cost_node: Node = await main._card_interaction.await_target(
		"Elige una carta que controles para subir a la mano de su dueño (costo)", cost_filter)
	if not cost_node or not is_instance_valid(cost_node):
		return

	UniversalCardParser.turn_registry.register(str(xoon.get_instance_id()), 0, GameManager.turn_serial)
	var owner_id: int = cost_node.get("owner_id") if cost_node.get("owner_id") != null else 0
	var target_hand = main.player_hand if owner_id == 0 else null
	if target_hand and cost_node.get("card_data") != null:
		var data: Dictionary = cost_node.card_data.duplicate()
		var old_parent := cost_node.get_parent()
		if old_parent:
			old_parent.remove_child(cost_node)
		cost_node.queue_free()
		var new_node = main._create_card(data, false)
		target_hand.add_card(new_node)
		main._connect_card_signals(new_node)
	else:
		# Dueño es el rival (bot/remoto) — su mano real vive en _opponent_fan
		# (mismo camino que hangar de la ciudadela, arquitectura.md §12.8),
		# no en un 'opponent_hand' que no existe.
		if cost_node.get("card_data") != null and main._opponent_fan and main.has_method("_create_card"):
			var data2: Dictionary = cost_node.card_data.duplicate()
			var old_parent2 := cost_node.get_parent()
			if old_parent2:
				old_parent2.remove_child(cost_node)
			cost_node.queue_free()
			var opp_node = main._create_card(data2, false)
			main._opponent_fan.add_card(opp_node)

	if not is_instance_valid(played_card):
		return
	await ActionModule.destroy([played_card], xoon, true, true)
