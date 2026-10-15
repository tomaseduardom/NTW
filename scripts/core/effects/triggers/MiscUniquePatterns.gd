extends RefCounted
## MiscUniquePatterns — 7 de 7 mitades de LookAndPlayResolver.gd, dividido por
## tamaño el 2026-09-06 ("módulos gordos"). Cuatro patrones únicos que no
## encajaban limpio en ninguna de las otras 6 categorías: Fisión Nuclear
## (burbuja de protección + programación de Fase Final), Transformación
## (ventana de respuesta + exilio + elección multi-rama), shedo titan (robo de
## control + renombrado), Malleus Maleficarum (candado de nombre). Llamada
## solo desde LookAndPlayResolver.gd (facade) — ver ese archivo para la lista
## completa de las 7 mitades hermanas.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var _main: Node


func setup(main: Node) -> void:
	_main = main


func try_execute_bubble_protection_and_schedule_final_phase_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Fisión Nuclear: 'Hasta tu próximo turno, no puedes ser afectado por
	efectos oponentes y para afectar tus cartas en juego tu oponente debe
	Desterrar una carta de su mano. En la próxima Fase Final oponente,
	Baraja una carta de coste 2 o menos o Roba dos cartas.'
	Rehecha el 2026-10-14 (a pedido del usuario). El escudo vive en
	EffectController (activate_fision_shield, ver su comentario): protege al
	jugador y cobra el Destierro al rival por cada carta en juego que quiera
	afectar, también las que entren después. Antes eran 99 cargas sobre las
	cartas que ya estaban en juego, que frenaban hasta tus propios efectos.
	Fase Final oponente, sin popup: brillan las cartas en juego de coste 2 o
	menos (no Oros) y tu Castillo; tu Castillo = Robar dos cartas. Sin
	cartas que barajar, roba directo."""
	var lower := ability_text.to_lower()
	if not ("hasta tu próximo turno, no puedes ser afectado por efectos oponentes" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	if await TriggerSystem.open_response_window(card, "Fisión Nuclear", controller_id):
		return true

	EffectController.activate_fision_shield(controller_id)
	main._update_debug("Fisión Nuclear: hasta tu próximo turno no puedes ser afectado por efectos oponentes")

	# La carta se destierra al jugarla: el efecto suspendido no guarda la
	# referencia al Nodo (quedaría liberado).
	var opponent_id: int = 1 - controller_id
	EffectController.schedule_next_final_phase_effect(opponent_id, func() -> void:
		await _fision_final_phase(controller_id)
	)
	return true


func _fision_final_phase(controller_id: int) -> void:
	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return
	var candidates: Array = []
	for field in [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
			main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]:
		if not field:
			continue
		for c in field.get_children():
			if not is_instance_valid(c):
				continue
			if c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.get_modified_cost(c) <= 2:
				candidates.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and ContinuousEffectManager.get_modified_cost(w) <= 2:
						candidates.append(w)
	var target: Node = null
	if not candidates.is_empty() and main._card_interaction:
		if PlayerSideScript.is_bot(controller_id):
			target = candidates.filter(func(c): return c.get("controller_id") != controller_id).pick_random() \
				if candidates.any(func(c): return c.get("controller_id") != controller_id) else null
		else:
			var pick: Dictionary = await main._card_interaction.await_target_or_castillo_pick(
				"Fisión Nuclear: baraja una carta de coste 2 o menos, o tu Castillo para Robar dos cartas",
				func(c: Node) -> bool: return c in candidates, "Fisión Nuclear: Robar dos cartas", false, true, controller_id)
			if pick.get("type", "") == "card":
				target = pick.get("card")
	if target and is_instance_valid(target):
		var target_owner: int = target.owner_id if target.get("owner_id") != null else controller_id
		if await ActionModule.return_to_deck(target, target_owner, true):
			CardManager.shuffle_deck(target_owner)
	else:
		await ActionModule.draw(controller_id, 2, "Fisión Nuclear", true)




func try_execute_transformacion_pattern(ability_text: String, controller_id: int) -> bool:
	"""'Puedes jugarlo en respuesta a que tu oponente juegue una carta o
	utilice una habilidad y Destiérralo. Elige un efecto: - Prevén que una
	carta que controles sea afectada y Roba una carta. - Prevén un efecto
	que fuera a afectarte, busca un Aliado en tu Castillo y ponlo en tu
	mano' (Transformación, 2026-09-06). El 'Destiérralo' lo maneja el
	destino post-resolución genérico de GoldManager._play_talisman()
	(self_exile), aquí solo la elección A/B.

	Rama A usa el mismo mecanismo de cargas por carta que ya protege a
	Estaca (EffectController.add_opponent_effect_prevention() +
	try_consume_opponent_effect_prevention(), consultado en TODOS los
	choque genéricos: destroy/banish/debuff/silence — ver
	ActionModule.destroy()/banish(), TargetedEffectExecutor, KeywordManager).
	Rama B ('Prevén un efecto que fuera a afectarte', sin carta puntual que
	elegir) se aproxima con la misma idea pero repartida en TODAS las
	cartas propias en juego a la vez, un solo cargo cada una — mismo
	principio de aproximación ya usado y documentado en Fisión Nuclear
	(bubble de protección), aquí a escala de un solo efecto en vez de 'hasta
	tu próximo turno'. Límite conocido, igual que en Fisión Nuclear: no
	cubre daño directo al Castillo (jugador), solo efectos que apunten a
	una carta en juego."""
	var lower := ability_text.to_lower()
	if not lower.begins_with("puedes jugarlo en respuesta a que tu oponente juegue una carta o utilice una habilidad"):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true

	var choose_a: bool = await SelectionManager.await_two_choice(
		main, "Elige un efecto",
		"Protege una carta que controles y Roba una carta",
		"Protege tus cartas en juego de un efecto, busca un Aliado en tu Castillo", controller_id)
	var own_fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo, main.player_gold] if controller_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo, main.opponent_gold]
	if choose_a:
		if not main._card_interaction:
			return true
		var own_cards: Array = []
		for field in own_fields:
			if field:
				own_cards.append_array(field.get_children())
		if own_cards.is_empty():
			return true
		var filter := func(c: Node) -> bool:
			return c in own_cards
		var target: Node = await main._card_interaction.await_target("Elige una carta para proteger de un efecto rival", filter, true, controller_id)
		if not target or not is_instance_valid(target):
			return true
		EffectController.add_legacy_targeted_prevention(target, 1)
		await ActionModule.draw(controller_id, 1, "etb_trigger", true)
	else:
		for field in own_fields:
			if not field:
				continue
			for c in field.get_children():
				if is_instance_valid(c):
					EffectController.add_legacy_targeted_prevention(c, 1)
		await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {"type": Constants.CardType.ALIADO}, 1, true, false, false, null, Constants.Zone.MANO, false)
	return true




func try_execute_gain_control_ally_rename_titan_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, gana el control de un Aliado y cambia su
	nombre a Titán. Tu oponente Bota cartas igual a su coste' (shedo
	titan, 2026-09-04) — usa ContinuousEffectManager.gain_control_of_card(),
	el primer uso real de robo de control en el motor."""
	var lower := ability_text.to_lower()
	if not ("gana el control de un aliado y cambia su nombre a tit" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var filter := func(c: Node) -> bool:
		if c.get("card_type") != Constants.CardType.ALIADO:
			return false
		# 2026-09-12: current_zone en vez de get_parent() (ver §10.5)
		return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	var target: Node = await main._card_interaction.await_target("Elige un Aliado para ganar su control", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true

	if await EffectController.offer_prevention(target, card, "control"):
		return true
	var stolen_cost: int = ContinuousEffectManager.get_modified_cost(target)
	ContinuousEffectManager.gain_control_of_card(target, controller_id)
	# "cambia su nombre a Titán": solo el campo de datos (nombre), no la
	# raza — el pasivo de shedo titan filtra por RAZA impresa ("Ignis o
	# Titán"), no por este nombre; las cartas son arte de imagen, así que
	# esto no tiene reflejo visual, solo efectos que consulten el nombre.
	target.card_name = "Titán"
	if target.get("card_data") != null:
		target.card_data["nombre"] = "Titán"

	var opponent_id: int = 1 - controller_id
	if stolen_cost > 0:
		await ActionModule.mill(opponent_id, stolen_cost, false, "etb_trigger", true)
	return true




func try_execute_malleus_name_lock_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, nombra una carta que no sea Malleus
	Maleficarum. Si está en tu Reserva, las cartas nombradas con este Oro
	pierden su habilidad' (Malleus Maleficarum, 2026-09-04) — reusa
	KeywordManager.lock_ability_by_name()/is_name_locked() (Alicia en
	Wonderland). Simplificación: is_name_locked() valida 'mientras la
	fuente siga EN JUEGO' en general (Reserva u Oro Pagado), no
	específicamente 'en tu Reserva' — el texto real excluye Oro Pagado, no
	implementado por ahora (caso borde poco común)."""
	var lower := ability_text.to_lower()
	if not ("nombra una carta que no sea malleus maleficarum" in lower):
		return false
	var picked: Dictionary = await _main._card_name_search.open_and_wait(
		"Nombra una carta (pierde su habilidad mientras Malleus Maleficarum esté en juego)", controller_id)
	if picked.is_empty():
		return true
	var picked_name: String = str(picked.get("nombre", ""))
	if picked_name.is_empty() or picked_name.to_lower() == "malleus maleficarum":
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	KeywordManager.lock_ability_by_name(picked_name, card)
	return true


func try_execute_look_hand_name_play_lock_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando ataca, mira la mano de tu oponente y nombra una carta. Esa
	carta no puede ser jugada hasta tu próximo turno' (Zadquiel, 2026-10-14).
	Candado por NOMBRE (GoldManager.lock_name_from_playing): cubre toda copia
	del rival, también las que robe después. El bot nombra al azar una carta
	que no sea Oro de la mano rival."""
	var lower := ability_text.to_lower()
	if not ("mira la mano de tu oponente y nombra una carta" in lower
			and "no puede ser jugada hasta tu próximo turno" in lower):
		return false
	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var opponent_id: int = 1 - controller_id
	if EffectController.fision_hides_zones_of(opponent_id, controller_id, Constants.Zone.MANO):  # Fisión Nuclear
		return true
	if await EffectController.offer_colapso_global(controller_id):  # Colapso Global
		return true
	var opp_hand: Array = PlayerSideScript.hand_cards(main, opponent_id).filter(func(c): return is_instance_valid(c))
	var picked_name: String = ""
	if PlayerSideScript.is_bot(controller_id):
		var non_gold: Array = opp_hand.filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
		if non_gold.is_empty():
			return true
		picked_name = str(non_gold.pick_random().get("card_name"))
	else:
		if not opp_hand.is_empty():
			SelectionManager.open_reveal(opp_hand.map(func(c): return c.card_data), "Mano de tu oponente", controller_id)
		var picked: Dictionary = await _main._card_name_search.open_and_wait(
			"Nombra una carta: tu oponente no puede jugarla hasta tu próximo turno", controller_id)
		picked_name = str(picked.get("nombre", ""))
	if picked_name.is_empty():
		return true
	if await TriggerSystem.open_response_window(card, str(card.get("card_name")) if card else "Zadquiel", controller_id):
		return true
	main._gold_manager.lock_name_from_playing(picked_name, opponent_id, controller_id)
	main._update_debug("'%s' no puede jugarse hasta tu próximo turno" % picked_name)
	return true
