extends "res://scripts/core/game/GoldManagerBase.gd"
## GoldManagerPago — familia Pago de GoldManager.gd (ver GoldManagerBase.gd).


## gokin: "Sólo puedes usar este Oro para pagar el coste de una carta de coste 3 o más" — meta
## "only_cost_min" en el Oro de la Reserva. ¿Puede pagar 'card_cost' (-1 = una habilidad)?
static func gold_usable_for(gold: Node, card_cost: int) -> bool:
	var min_cost: int = int(gold.get_meta("only_cost_min", -1))
	return min_cost < 0 or card_cost >= min_cost


## Oros físicos de la Reserva que no sirven para pagar 'card_cost' (gokin).
func unusable_physical_golds(card_cost: int, player_id: int) -> int:
	var reserva: Node = _main.player_gold if player_id == 0 else _main.opponent_gold
	if not reserva:
		return 0
	var n := 0
	for g in reserva.get_children():
		if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO and not gold_usable_for(g, card_cost):
			n += 1
	return n


func puede_pagar(cantidad: int, card_type: int = -1, card_race: String = "", card_cost: int = -1, player_id: int = 0) -> bool:
	var oro_fisico = GameState.get_oro_reserva(player_id) - unusable_physical_golds(card_cost, player_id)
	var restringido = _restricted_gold_available_for(card_type, card_race, card_cost, player_id)
	var disponible = oros_virtuales.get(player_id, 0) + restringido + oro_fisico
	return disponible >= cantidad


func pagar_coste(cantidad: int, card_type: int = -1, card_race: String = "", card_cost: int = -1, player_id: int = 0) -> bool:
	"""card_type/card_race/card_cost identifican qué se paga, para saber si aplica el Oro Virtual
	restringido (p.ej. Padre de la Patria: "para jugar Armas o Aliados Caballero"). Pasar -1/"" si
	no corresponde (p.ej. una habilidad activada) y los pools restringidos se ignoran. player_id:
	de qué jugador se paga (arquitectura.md §33)."""
	EffectContextScript.check_payment(player_id, cantidad)
	var reserva_container: HBoxContainer = _main.player_gold if player_id == 0 else _main.opponent_gold
	if not puede_pagar(cantidad, card_type, card_race, card_cost, player_id):
		# reserva_container.get_child_count() incluye los tokens visuales de
		# Oro Virtual (genérico + restringido) — se restan para no contarlos
		# dos veces en el mensaje.
		var restricted_token_count := 0
		for pool in restricted_gold_pools.get(player_id, []):
			restricted_token_count += pool.tokens.size()
		var oro_fisico_visible = reserva_container.get_child_count() - virtual_gold_tokens.get(player_id, []).size() - restricted_token_count
		var restringido_disp = _restricted_gold_available_for(card_type, card_race, card_cost, player_id)
		var disponible = oros_virtuales.get(player_id, 0) + restringido_disp + oro_fisico_visible
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d (V:%d + R:%d + F:%d)" % [
			cantidad, disponible, oros_virtuales.get(player_id, 0), restringido_disp, oro_fisico_visible])
		return false
	if cantidad <= 0:
		return true
	var restante = cantidad

	# 1. Oro Virtual RESTRINGIDO primero — es el más específico: si no se usa
	# ahora que sí aplica, se pierde igual al pasar de turno, mientras que el
	# genérico y el físico se pueden guardar para otra compra.
	if restante > 0:
		var restr_usados = await _consume_restricted_gold_for(card_type, card_race, card_cost, restante, player_id)
		if restr_usados > 0:
			restante -= restr_usados
			_main._update_debug("Consumido %d Oro Virtual restringido (quedan %d por pagar)" % [restr_usados, restante])

	if restante > 0 and oros_virtuales.get(player_id, 0) > 0:
		var virtuales_usados = mini(oros_virtuales[player_id], restante)
		oros_virtuales[player_id] -= virtuales_usados
		restante -= virtuales_usados
		for i in range(virtuales_usados):
			await _despawn_virtual_gold_token(player_id)
		_main._update_debug("Consumido %d Oro Virtual (quedan %d)" % [virtuales_usados, oros_virtuales[player_id]])
	if restante > 0:
		_main._update_debug("Pagando %d Oro físico..." % restante)
		# El jugador elige CUÁLES Oros físicos gasta (p.ej. Monitor Araucano: "este Oro genera un Oro
		# adicional cuando sea usado para pagar Armas de coste 2 o más" — hay que saber qué Oro pagó). El
		# Oro Virtual (genérico y restringido) se gasta siempre primero.
		# El orden se elige una sola vez (_choose_physical_gold_to_spend() ya junta los que hagan falta) y
		# solo entre Oros físicos (las fichas de Oro Virtual de la Reserva no se pagan así).
		var token_nodes: Array = virtual_gold_tokens.get(player_id, []).duplicate()
		for pool in restricted_gold_pools.get(player_id, []):
			token_nodes.append_array(pool.tokens)
		var oros_reserva: Array = reserva_container.get_children().filter(func(c): return not (c in token_nodes) 			and gold_usable_for(c, card_cost))  # gokin
		var chosen_oros: Array = await _choose_physical_gold_to_spend(oros_reserva, restante, player_id)
		var chosen_idx := 0

		# Se gasta un Oro físico a la vez: el Oro adicional de Monitor Araucano cuenta para ESTA compra,
		# así que antes del siguiente se revisa si apareció Oro Virtual nuevo.
		var diverted := 0
		var physical_spent := 0
		while restante > 0:
			if oros_virtuales.get(player_id, 0) > 0:
				var v_now: int = mini(oros_virtuales[player_id], restante)
				oros_virtuales[player_id] -= v_now
				restante -= v_now
				for i in range(v_now):
					await _despawn_virtual_gold_token(player_id)
				if restante <= 0:
					break
			if chosen_idx >= chosen_oros.size():
				break  # no debería pasar (puede_pagar() ya validó), pero no colgarse si pasa
			var oro_card = chosen_oros[chosen_idx]
			chosen_idx += 1
			if not is_instance_valid(oro_card):
				continue
			# diverted = unidades que no terminaron en el Oro Pagado (p.ej. Jormundgander vuelve a ser
			# Aliado): se restan después de GameState.pagar_oro() para no regalar Oro en el próximo
			# Reagrupamiento.
			var was_diverted: bool = await _mover_oro_a_pagado(oro_card)
			if was_diverted:
				diverted += 1
			physical_spent += 1
			restante -= 1
			_resolve_gold_paid_reaction(oro_card, card_type, card_race, card_cost, player_id)
		GameState.pagar_oro(player_id, physical_spent)
		if diverted > 0:
			GameState.agregar_oro_pagado(player_id, -diverted)
	TurnManager.any_card_played_this_turn = true
	var oro_restante = GameState.get_oro_reserva(player_id)
	_main._update_debug("Pagado %d Oro total (Reserva: %d, Virtual: %d)" % [cantidad, oro_restante, oros_virtuales.get(player_id, 0)])
	_update_gold_display()
	return true


func _choose_physical_gold_to_spend(oros_reserva: Array, restante: int, player_id: int = 0) -> Array:
	"""Elige qué Oros físicos de la Reserva se gastan para 'restante' unidades. Si no hay elección
	real (hay que gastar todos, o queda uno), no pregunta."""
	if restante >= oros_reserva.size() or oros_reserva.size() <= 1:
		return oros_reserva.slice(0, mini(restante, oros_reserva.size()))
	if not _main._card_interaction:
		return oros_reserva.slice(0, restante)

	# Click directo sobre las cartas (CardInteractionModule.await_target(), como el resto del juego),
	# con el brillo de "activable" en los Oros válidos.
	var chosen: Array = []
	var remaining_candidates: Array = oros_reserva.duplicate()
	for c in remaining_candidates:
		if is_instance_valid(c):
			c.set_activatable(true, CardBadges.GLOW_COLOR_GOLD, &"target_select")

	while chosen.size() < restante and not remaining_candidates.is_empty():
		var filter := func(c: Node) -> bool:
			return c in remaining_candidates
		var picked: Node = await _main._card_interaction.await_target(
			"Elige qué Oro gastar (%d de %d)" % [chosen.size() + 1, restante], filter, true, player_id)
		if not picked or not is_instance_valid(picked):
			break  # cancelado (ESC) — se completa abajo con el orden mecánico de siempre
		remaining_candidates.erase(picked)
		picked.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
		chosen.append(picked)

	for c in remaining_candidates:
		if is_instance_valid(c):
			c.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")

	if chosen.size() < restante:
		# Cancelado a mitad de camino (ESC) — completar con las que falten
		# en el orden mecánico de siempre, para no dejar el pago sin
		# resolver a medio camino.
		for c in oros_reserva:
			if chosen.size() >= restante:
				break
			if c not in chosen:
				chosen.append(c)

	return chosen


func _resolve_gold_paid_reaction(oro_card: Node, card_type: int, card_race: String, card_cost: int, player_id: int = 0) -> void:
	""""Este Oro genera un Oro adicional cuando sea usado para pagar X (de coste N o más)" (p.ej.
	Monitor Araucano), sobre el Oro que efectivamente pagó."""
	if not is_instance_valid(oro_card):
		return
	var ability_text: String = oro_card.get("card_ability") if oro_card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return
	var lower := _fix_mojibake(ability_text).to_lower()
	# Trono del Cielo: "Si en su turno anterior tu oponente generó o puso en juego más de un Oro,
	# cuenta como dos Oros para pagar el coste de una carta."
	if "cuenta como dos oros para pagar el coste de una carta" in lower and card_type >= 0 \
			and not KeywordManager.is_silenced(oro_card) and int(_gold_events_prev.get(1 - player_id, 0)) > 1:
		generar_oros_virtuales(1, player_id)
		_main._update_debug("%s cuenta como dos Oros" % str(oro_card.get("card_name")))
	# Alicanto: "Los Aliados de coste 2 o más pagados con este Oro no pueden ser Anulados" — se marca y
	# lo toma el próximo Aliado que entra (_trigger_enter_play), antes de su ventana de respuesta.
	if "aliados de coste 2 o más pagados con este oro no pueden ser anulados" in lower \
			and card_type == Constants.CardType.ALIADO and card_cost >= 2 and not KeywordManager.is_silenced(oro_card):
		_alicanto_paid_pending[player_id] = true
	if not ("este oro genera un oro adicional cuando sea usado para pagar" in lower):
		return

	var wanted_type: int = -1
	if "armas" in lower:
		wanted_type = Constants.CardType.ARMA
	elif "aliados" in lower:
		wanted_type = Constants.CardType.ALIADO
	elif "talismanes" in lower:
		wanted_type = Constants.CardType.TALISMAN
	elif "tótems" in lower or "totems" in lower:
		wanted_type = Constants.CardType.TOTEM
	if wanted_type != -1 and card_type != wanted_type:
		return

	var cost_rx := RegEx.new()
	cost_rx.compile("(?i)coste\\s+(\\w+)\\s+o\\s+m[aá]s")
	var m_cost := cost_rx.search(ability_text)
	if m_cost:
		var min_cost: int = UniversalCardParser._parse_amount(m_cost.get_string(1))
		if card_cost < min_cost:
			return

	generar_oros_virtuales(1, player_id)
	_main._update_debug("%s generó 1 Oro adicional" % str(oro_card.get("card_name")))


func generar_oros_virtuales(cantidad: int, player_id: int = 0) -> void:
	oros_virtuales[player_id] = oros_virtuales.get(player_id, 0) + cantidad
	_note_gold_event(player_id, cantidad)
	var tokens: Array = virtual_gold_tokens.get(player_id, [])
	for i in range(cantidad):
		_spawn_gold_token("Oro Virtual Libre", "Libre", tokens, player_id)
	virtual_gold_tokens[player_id] = tokens
	_main._update_debug("Generado %d Oro Virtual (total: %d)" % [cantidad, oros_virtuales[player_id]])
	_update_gold_display()


func generar_oro_virtual_restringido(cantidad: int, predicate: Callable, label: String, player_id: int = 0,
		until_own_next_turn: bool = false) -> void:
	_note_gold_event(player_id, cantidad)
	"""Oro Virtual que SOLO paga cartas que cumplan 'predicate(card_type,
	card_race) -> bool' (p.ej. Padre de la Patria: 'para jugar Armas o
	Aliados Caballero'). A diferencia de generar_oros_virtuales(), queda
	guardado en restricted_gold_pools[player_id] como su propia entrada —
	varias fuentes con distintas restricciones pueden coexistir sin
	mezclarse."""
	var tokens: Array = []
	for i in range(cantidad):
		_spawn_gold_token("Oro Virtual (%s)" % label, label, tokens, player_id)
	var pools: Array = restricted_gold_pools.get(player_id, [])
	# until_own_next_turn (Sariel: "Puedes usar ese Oro hasta el comienzo de tu próximo turno"):
	# sobrevive al comienzo del turno rival.
	pools.append({"amount": cantidad, "tokens": tokens, "predicate": predicate, "label": label,
		"until_player": player_id if until_own_next_turn else -1})
	restricted_gold_pools[player_id] = pools
	_main._update_debug("Generado %d Oro Virtual restringido (%s)" % [cantidad, label])
	_update_gold_display()


func _restricted_gold_available_for(card_type: int, card_race: String, card_cost: int = -1, player_id: int = 0) -> int:
	if card_type < 0:
		return 0
	var total := 0
	for pool in restricted_gold_pools.get(player_id, []):
		if pool.predicate.call(card_type, card_race, card_cost):
			total += pool.amount
	return total


func _consume_restricted_gold_for(card_type: int, card_race: String, card_cost: int, needed: int, player_id: int = 0) -> int:
	var pools: Array = restricted_gold_pools.get(player_id, [])
	if card_type < 0 or needed <= 0 or pools.is_empty():
		return 0
	var consumed := 0
	var empty_indices: Array = []
	for i in range(pools.size()):
		if consumed >= needed:
			break
		var pool: Dictionary = pools[i]
		if not pool.predicate.call(card_type, card_race, card_cost):
			continue
		var usa: int = mini(pool.amount, needed - consumed)
		pool.amount -= usa
		consumed += usa
		for j in range(usa):
			await _despawn_gold_token(pool.tokens, player_id)
		if pool.amount <= 0:
			empty_indices.append(i)
	for i in range(empty_indices.size() - 1, -1, -1):
		pools.remove_at(empty_indices[i])
	restricted_gold_pools[player_id] = pools
	return consumed


func _spawn_gold_token(nombre: String, label: String, target_list: Array, player_id: int = 0) -> void:
	_visuals._spawn_gold_token(nombre, label, target_list, player_id)


func _despawn_virtual_gold_token(player_id: int = 0) -> void:
	var tokens: Array = virtual_gold_tokens.get(player_id, [])
	await _despawn_gold_token(tokens, player_id)
	virtual_gold_tokens[player_id] = tokens


func _despawn_gold_token(target_list: Array, player_id: int = 0) -> void:
	await _visuals._despawn_gold_token(target_list, player_id)


func _mover_oro_a_pagado(card: Node) -> bool:
	"""Devuelve true si la carta se desvió del movimiento normal (Jormundgander: vuelve a ser el
	Aliado original), false si fue al Oro Pagado. pagar_coste() lo usa para no contar de más en
	GameState."""
	if card.get("revert_to_data") != null and not (card.revert_to_data as Dictionary).is_empty():
		await _revert_gold_to_ally(card)
		return true
	# Caos: "Cuando lo pagues, conviértelo en un Aliado de Fuerza 3".
	if card.get_meta("caos_gold", false) and not KeywordManager.is_silenced(card):
		load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").caos_to_ally(_main, card)
		return true
	# controller_id (no siempre el Anfitrión): el Oro puede ser del rival (Tyet: "Puedes pagar este Oro
	# para que un Oro pierda su habilidad este turno y muévelo al Oro Pagado").
	var controller_id: int = card.controller_id if card.get("controller_id") != null else 0
	var reserva_container: HBoxContainer = _main.player_gold if controller_id == 0 else _main.opponent_gold
	var pagado_container: HBoxContainer = _main.player_oro_pagado if controller_id == 0 else _main.opponent_oro_pagado
	var start_pos = card.global_position
	reserva_container.remove_child(card)
	card.can_interact = false
	pagado_container.add_child(card)
	update_gold_containers_spacing()
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.25)
	await tween.finished
	card.can_interact = true
	return false


func _revert_gold_to_ally(card: Node) -> void:
	"""Jormundgander: "Si esta carta es un Oro, cuando lo pagues para jugar un Aliado, convierte este
	Oro en un Aliado y muévelo a tu Línea de Defensa" — la otra mitad de
	convert_ally_to_gold_in_pagado()."""
	var original_data: Dictionary = card.revert_to_data.duplicate()
	card.revert_to_data = {}
	var start_pos = card.global_position
	_main.player_gold.remove_child(card)
	card.can_interact = false
	card.load_from_data(original_data)
	_main.player_field.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	await get_tree().process_frame
	# Slot fijo (ZoneManager.pin_card_to_field_slot(), igual que _play_card_to_field()).
	var end_pos: Vector2 = _main._zone_manager.pin_card_to_field_slot(card, _main.player_field)
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), 0.3)
	await tween.finished
	card.can_interact = true
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	_update_gold_display()
	await _trigger_enter_play(card, Constants.Zone.LINEA_DEFENSA)


## Azi del Abismo: "convertir este Aliado hasta tu próximo turno en un Oro con la habilidad ...".
## Queda en tu Oro Pagado con esa habilidad y, al empezar tu próximo turno, vuelve a ser el Aliado
## original (revert_converted_golds()).
func convert_ally_to_gold_until_next_turn(card: Node, gold_ability: String) -> void:
	if not is_instance_valid(card):
		return
	var pid: int = card.controller_id if card.get("controller_id") != null else 0
	var pagado: Node = PlayerSideScript.oro_pagado(_main, pid)
	var field = card.get_parent()
	var start_pos: Vector2 = card.global_position
	card.set_meta("converted_until_turn_of", pid)
	card.set_meta("converted_original_data", card.card_data.duplicate())
	if field:
		field.remove_child(card)
		if field is Control and _main._zone_manager:
			_main._zone_manager.compact_field_slots(field)
	card.can_interact = false
	var new_data: Dictionary = card.card_data.duplicate()
	new_data["tipo"] = Constants.CardType.ORO
	new_data["habilidad"] = gold_ability
	# Sus efectos continuos de Aliado ("Tus demás Aliados ganan 1 de
	# Fuerza") no siguen mientras es un Oro.
	ContinuousEffectManager.remove_modifiers_from_source(card)
	ContinuousEffectManager._invalidate_cache()
	card.load_from_data(new_data)
	pagado.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.ORO_PAGADO)
	card.scale = Constants.GOLD_CARD_SCALE
	card.base_scale = Constants.GOLD_CARD_SCALE
	GameState.agregar_oro_pagado(pid, 1)
	update_gold_containers_spacing()
	_update_gold_display()
	await get_tree().process_frame
	var end_pos: Vector2 = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.3)
	await tween.finished
	card.can_interact = true
	_main._update_debug("%s se convierte en un Oro en tu Oro Pagado hasta tu próximo turno" % str(card.card_name))


func convert_ally_to_gold_in_pagado(card: Node) -> void:
	"""Jormundgander: "Cuando haga daño, puedes convertirlo en un Oro y moverlo a tu Oro Pagado" —
	queda gastado hasta el próximo Reagrupamiento. Guarda los datos originales en
	card.revert_to_data para reconvertirlo si se lo paga (_mover_oro_a_pagado())."""
	if not is_instance_valid(card):
		return
	var owner_id: int = card.owner_id if card.get("owner_id") != null else 0
	# También para el jugador 1 (su Oro Pagado).
	var pagado_container: Node = PlayerSideScript.oro_pagado(_main, owner_id)

	card.revert_to_data = card.card_data.duplicate()

	var start_pos = card.global_position
	var parent = card.get_parent()
	if parent:
		parent.remove_child(card)
	card.can_interact = false

	# Re-tipar como Oro: card_data y las propiedades derivadas que el resto
	# del motor lee (PaymentManager.calcular_coste_real, filtros de
	# búsqueda/selección, etc.) leen card_type/card_cost, no re-parsean el
	# texto de la carta.
	var new_data: Dictionary = card.card_data.duplicate()
	new_data["tipo"] = Constants.CardType.ORO
	card.load_from_data(new_data)

	pagado_container.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.ORO_PAGADO)
	card.scale = Constants.GOLD_CARD_SCALE
	card.base_scale = Constants.GOLD_CARD_SCALE
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.3)
	await tween.finished
	card.can_interact = true
	GameState.agregar_oro_pagado(owner_id, 1)
	if owner_id == 0:
		_main.gold_cards.append(card)  # gold_cards es solo la Reserva del Anfitrión
	_update_gold_display()


func _mover_oro_a_reserva(card: Node) -> void:
	var start_pos = card.global_position
	_main.player_oro_pagado.remove_child(card)
	card.can_interact = false
	_main.player_gold.add_child(card)
	update_gold_containers_spacing()
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), 0.25)
	await tween.finished
	card.can_interact = true


func agrupar_oros(player_id: int, amount: int) -> int:
	"""'Agrupa un Oro': hasta 'amount' Oros del Oro Pagado de 'player_id' vuelven a su Reserva (como
	en la Agrupación). Si hay más que 'amount', el jugador elige (el Remoto por red, el bot los
	primeros). Devuelve cuántos agrupó."""
	var pagado: Node = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	if not pagado:
		return 0
	var candidates: Array = pagado.get_children().filter(func(c): return is_instance_valid(c))
	if candidates.is_empty():
		return 0
	var chosen: Array = candidates
	if candidates.size() > amount:
		if PlayerSideScript.is_bot(player_id):
			chosen = candidates.slice(0, amount)
		else:
			chosen = await _main._card_interaction.await_multi_target(
				"Agrupa %d Oro%s de tu Oro Pagado" % [amount, "" if amount == 1 else "s"],
				candidates, amount, Callable(), Callable(), false, null, player_id)
	var moved := 0
	for card in chosen.slice(0, amount):
		if await _agrupar_oro(player_id, card):
			moved += 1
	_update_gold_display()
	_main._update_debug("%d Oro%s agrupado%s" % [moved, "" if moved == 1 else "s", "" if moved == 1 else "s"])
	return moved


func _agrupar_oro(player_id: int, card: Node) -> bool:
	var pagado: Node = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	if not is_instance_valid(card) or not pagado or card.get_parent() != pagado:
		return false
	GameState.agregar_oro_pagado(player_id, -1)
	GameState.agregar_oro_reserva(player_id, 1)
	if player_id == 0:
		await _mover_oro_a_reserva(card)
	else:
		pagado.remove_child(card)
		card.can_interact = false
		_main.opponent_gold.add_child(card)
		update_gold_containers_spacing()
	card.set_zone(Constants.Zone.RESERVA_ORO)
	return true


func agrupar_cartas(player_id: int, amount: int) -> int:
	"""'Agrupa dos cartas' (iga ryu): hasta 'amount' cartas propias hacen lo de la Agrupación (DAR
	5.1): un Oro Pagado vuelve a la Reserva, un Aliado de Línea de Ataque vuelve a Defensa. El bot
	agrupa primero Oros. Devuelve cuántas agrupó."""
	var pagado: Node = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	var atk: Node = _main.player_linea_ataque if player_id == 0 else _main.opponent_linea_ataque
	var golds: Array = pagado.get_children().filter(func(c): return is_instance_valid(c)) if pagado else []
	var attackers: Array = atk.get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO) if atk else []
	var candidates: Array = golds + attackers
	if candidates.is_empty():
		return 0
	var chosen: Array = candidates
	if candidates.size() > amount:
		if PlayerSideScript.is_bot(player_id):
			chosen = candidates.slice(0, amount)
		else:
			chosen = await _main._card_interaction.await_multi_target(
				"Agrupa %d carta%s (Oro Pagado o Línea de Ataque)" % [amount, "" if amount == 1 else "s"],
				candidates, amount, Callable(), Callable(), false, null, player_id)
	var moved := 0
	for card in chosen.slice(0, amount):
		if card in golds:
			if await _agrupar_oro(player_id, card):
				moved += 1
		elif is_instance_valid(card) and card.get_parent() == atk and _main._card_interaction:
			await _main._card_interaction.unmark_attackers([card])
			moved += 1
	_update_gold_display()
	_main._update_debug("%d carta%s agrupada%s" % [moved, "" if moved == 1 else "s", "" if moved == 1 else "s"])
	return moved


func _reset_gold() -> void:
	"""Reagrupamiento del Oro (DAR, Agrupación): el Oro Pagado propio vuelve a la Reserva al empezar
	el turno. Lo llama PhaseFlowController. GameState.reagrupar_oro() resetea los contadores
	primero y después se mueven las cartas una a una con _mover_oro_a_reserva() (que no toca
	GameState)."""
	GameState.reagrupar_oro(0)
	# uriko-hime: "tu oponente sólo pueda agrupar hasta cuatro Oros en su próxima Agrupación".
	var cap: int = int(RuleState.take_pending("regroup_cap", 0)) if RuleState.has_pending("regroup_cap", 0) else -1
	var regrouped := 0
	if _main.player_oro_pagado:
		for card in _main.player_oro_pagado.get_children().duplicate():
			if is_instance_valid(card):
				# el huascar: "no puede ser agrupado el próximo turno".
				if int(card.get_meta("no_regroup_turn", -1)) == GameManager.turn_serial or card.get_meta("never_regroup", false) \
						or (cap >= 0 and regrouped >= cap):  # alma del viento, uriko-hime
					GameState.agregar_oro_reserva(0, -1)
					GameState.agregar_oro_pagado(0, 1)
					continue
				await _mover_oro_a_reserva(card)
				regrouped += 1
	_update_gold_display()


func get_oro_disponible(player_id: int = 0) -> int:
	return GameState.get_oro_reserva(player_id)


func get_oro_pagado(player_id: int = 0) -> int:
	return GameState.get_oro_pagado(player_id)


func get_oro_total(player_id: int = 0) -> int:
	return GameState.get_oro_total(player_id)
