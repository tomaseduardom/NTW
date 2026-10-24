extends "res://scripts/core/effects/triggers/EffectControllerPrevencion.gd"
## EffectController — familia Inmunidades (ver EffectControllerBase.gd para la cabecera, constantes y ayudas).


func add_legacy_targeted_prevention(card: Node, amount: int = 1) -> void:
	if not is_instance_valid(card):
		return
	var id := card.get_instance_id()
	_legacy_targeted_preventions[id] = _legacy_targeted_preventions.get(id, 0) + amount


func activate_fision_shield(player_id: int) -> void:
	_fision_shields[player_id] = true
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != player_id:
			return
		_fision_shields.erase(player_id)
		if GameManager.turn_started.is_connected(clear_it):
			GameManager.turn_started.disconnect(clear_it)
	GameManager.turn_started.connect(clear_it)


## DAR abril 2026 (Afectar): "Los efectos que cancelen ataque afectan a los Aliados" (las restricciones de
## ataque afectan al jugador). Deja solo los atacantes cuyo ataque sí se cancela: "no puede ser afectado
## por efectos oponentes" y las prevenciones del Aliado (etiqueta "cancel_attack") lo evitan.
func filter_attack_cancel(attackers_in: Array, source: Node) -> Array:
	var out: Array = []
	for a in attackers_in:
		if is_instance_valid(a) and not await offer_prevention(a, source, "cancel_attack"):
			out.append(a)
	return out


## Lo mismo para una clave de RuleState puesta sobre 'payer' (PaymentManager, TriggerTollPatterns).
func rule_cost_waived(key: String, payer: int) -> bool:
	return opp_cost_waived(payer, RuleState.source_of(key, payer))


func fision_blocks_player_effect(player_id: int) -> bool:
	"""true si 'player_id' está protegido por Fisión Nuclear y el efecto en
	curso es de su rival (Descartar/Botar no ocurren)."""
	if not (is_fision_shielded(player_id) or player_opp_immune(player_id)) or _current_effect_controller(null) != 1 - player_id:
		return false
	var main := get_node_or_null("/root/Main")
	if main:
		main._update_debug("Fisión Nuclear: el jugador %d no puede ser afectado por efectos oponentes" % (player_id + 1))
	return true


func fision_hides_zones_of(zone_owner: int, chooser_id: int, zone: int = Constants.Zone.CASTILLO) -> bool:
	"""true si 'chooser_id' (el rival) no puede buscar/mirar en el Castillo
	(o la mano) de 'zone_owner' por Fisión Nuclear. El Cementerio no cuenta."""
	if zone not in [Constants.Zone.CASTILLO, Constants.Zone.MANO]:
		return false
	# Escudo Estelar: "Los jugadores no pueden buscar, mirar, ni mostrar cartas de la mano ni los Castillos
	# por efectos hasta tu próxima Fase Final" (también las propias).
	if RuleState.active("zones_hidden", zone_owner):
		var main_e := get_node_or_null("/root/Main")
		if main_e:
			main_e._update_debug("Escudo Estelar: no se puede buscar ni mirar en la mano ni en los Castillos")
		return true
	if chooser_id < 0 or chooser_id == zone_owner:
		return false
	# Terminal P-12: "Si está en tu Reserva, ... él no puede mirar tu mano ni tu Castillo."
	if TurnLimits.terminal_in_reserva(zone_owner):
		var main_t := get_node_or_null("/root/Main")
		if main_t:
			main_t._update_debug("Terminal P-12: no puedes mirar la mano ni el Castillo del jugador %d" % (zone_owner + 1))
		return true
	# Ofrenda a los Abuelos: "prevén que tu oponente busque cartas en tu Castillo" (este turno).
	if zone == Constants.Zone.CASTILLO and not RuleState.turn_data("castle_search_block:%d" % zone_owner).is_empty():
		var main_o := get_node_or_null("/root/Main")
		if main_o:
			main_o._update_debug("Ofrenda a los Abuelos: no puedes buscar cartas en el Castillo del jugador %d" % (zone_owner + 1))
		return true
	if not is_fision_shielded(zone_owner) and not player_opp_immune(zone_owner):
		return false
	var main := get_node_or_null("/root/Main")
	if main:
		main._update_debug("No puedes buscar ni elegir en las zonas del jugador %d (no puede ser afectado por efectos oponentes)" % (zone_owner + 1))
	return true


## Colapso Global: "En respuesta a que tu oponente fuera a mirar tu mano o buscar cartas en un
## Castillo, puedes Desterrar una carta de tu mano para jugarlo sin pagar su coste. Prevén que tu
## oponente mire tu mano o busque cartas y tú Robas una carta." Se ofrece en las búsquedas
## (ActionSearch) y al mirar la mano rival; true = no ocurre. Se paga su coste o se Destierra una
## carta de la mano; va al Cementerio.
## Sidhes del Bosque: "Puedes jugarlo en respuesta a que tu oponente fuera a buscar cartas en un
## Castillo. Nombra dos cartas...". ActionSearch lo ofrece antes de buscar y aplica el candado
## (sidhes_blocked_names) y el mostrar (sidhes_reveal_to).
func offer_sidhes(searcher_id: int) -> void:
	if searcher_id < 0:
		return
	var main := get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return
	var victim: int = 1 - searcher_id
	var sidhes: Node = null
	for c in PlayerSideScript.hand_cards(main, victim):
		if is_instance_valid(c) and "puedes jugarlo en respuesta a que tu oponente fuera a buscar cartas en un castillo" \
				in str(c.get("card_ability")).to_lower():
			sidhes = c
			break
	if sidhes == null:
		return
	var cost: int = int(PaymentManager.calcular_coste_real(sidhes))
	if not main._gold_manager.puede_pagar(cost, Constants.CardType.TALISMAN, "", int(sidhes.get("card_cost")), victim):
		return
	var card_name: String = str(sidhes.get("card_name"))
	if not PlayerSideScript.is_bot(victim):
		if not await SelectionManager.await_two_choice(main, "Tu oponente va a buscar en un Castillo",
				"Jugar %s (%d Oro)" % [card_name, cost], "No responder", victim):
			return
	if cost > 0:
		await main._gold_manager.pagar_coste(cost, Constants.CardType.TALISMAN, "", int(sidhes.get("card_cost")), victim)
	var sdata: Dictionary = sidhes.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, victim, sidhes)
	if is_instance_valid(sidhes):
		CardManager._disconnect_card_interaction_signals(sidhes)
		sidhes.queue_free()
	await resolve_sidhes_effect(victim, card_name)
	sdata["esta_oculta"] = false
	CardManager.add_to_cemetery(victim, sdata)


## Efecto de Sidhes del Bosque, jugado en respuesta (offer_sidhes) o como Talismán normal en tu
## Vigilia / Guerra de Talismanes ("puedes jugarlo en respuesta" no impide jugarlo normal). victim =
## quien juega Sidhes; el candado es para su oponente.
func resolve_sidhes_effect(victim: int, card_name: String) -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var searcher_id: int = 1 - victim
	# Nombrar dos cartas.
	var names: Array = []
	if PlayerSideScript.is_bot(victim):
		var deck: Array = CardManager.get_deck(searcher_id).duplicate()
		deck.shuffle()
		for d in deck:
			var n: String = str(d.get("nombre", "")).to_lower()
			if not n.is_empty() and not (n in names):
				names.append(n)
			if names.size() >= 2:
				break
	else:
		for i in range(2):
			var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
				"%s: nombra una carta que tu oponente no podrá buscar (%d de 2)" % [card_name, i + 1], victim)
			var n: String = str(picked.get("nombre", "")).to_lower()
			if not n.is_empty() and not (n in names):
				names.append(n)
	RuleState.set_turn_data("sidhes_lock", {"searcher": searcher_id, "names": names, "reveal_to": victim})
	main._update_debug("%s: este turno tu oponente muestra lo que busca y no puede buscar %s" % [card_name,
		" ni ".join(names) if not names.is_empty() else "nada nombrado"])
	# Roba una carta o sube un Aliado de tu Cementerio a tu mano.
	var has_ally_in_cemetery: bool = CardManager.get_cemetery(victim).any(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO)
	var draw_it := true
	if has_ally_in_cemetery and not PlayerSideScript.is_bot(victim):
		draw_it = await SelectionManager.await_two_choice(main, card_name, "Robar una carta", "Subir un Aliado de tu Cementerio a tu mano", victim)
	if draw_it:
		await ActionModule.draw(victim, 1, card_name, true)
	else:
		await ActionModule.search(victim, Constants.Zone.CEMENTERIO, {"type": Constants.CardType.ALIADO}, 1, true, false, false,
			null, Constants.Zone.MANO, false, victim)


func _sidhes_lock_for(searcher_id: int) -> Dictionary:
	var lock: Dictionary = RuleState.turn_data("sidhes_lock")
	if lock.is_empty() or int(lock.get("searcher", -1)) != searcher_id:
		return {}
	return lock


func sidhes_blocked_names(searcher_id: int) -> Array:
	return _sidhes_lock_for(searcher_id).get("names", [])


func sidhes_reveal_to(searcher_id: int) -> int:
	return int(_sidhes_lock_for(searcher_id).get("reveal_to", -1))


func offer_colapso_global(searcher_id: int) -> bool:
	if searcher_id < 0:
		return false
	var main := get_node_or_null("/root/Main")
	if not main:
		return false
	var victim: int = 1 - searcher_id
	var hand: Array = PlayerSideScript.hand_cards(main, victim).filter(func(c): return is_instance_valid(c))
	var colapso: Node = null
	for c in hand:
		if "prevén que tu oponente mire tu mano o busque cartas" in str(c.get("card_ability")).to_lower():
			colapso = c
			break
	if colapso == null:
		return false
	var others: Array = hand.filter(func(c): return c != colapso)
	var can_pay: bool = main._gold_manager.puede_pagar(int(colapso.get("card_cost")), Constants.CardType.TALISMAN, "", -1, victim)
	if others.is_empty() and not can_pay:
		return false
	var use_banish: bool = not others.is_empty()
	if PlayerSideScript.is_bot(victim):
		pass  # el bot lo usa siempre que puede
	else:
		var label_banish := "Jugar Colapso Global Desterrando una carta de tu mano"
		var label_pay := "Jugar Colapso Global pagando %d Oro" % int(colapso.get("card_cost"))
		if not await SelectionManager.await_two_choice(main, "Tu oponente va a mirar tu mano o buscar cartas",
				label_banish if use_banish else label_pay, "No responder", victim):
			return false
		if use_banish and can_pay:
			use_banish = await SelectionManager.await_two_choice(main, "Colapso Global", label_banish, label_pay, victim)
	if use_banish:
		var paid: Node = others.pick_random() if PlayerSideScript.is_bot(victim) else null
		if paid == null and main._card_interaction:
			paid = await main._card_interaction.await_target("Colapso Global: Destierra una carta de tu mano",
				func(c: Node) -> bool: return c in others, false, victim)
		if paid == null or not is_instance_valid(paid):
			return false
		var pdata: Dictionary = paid.card_data.duplicate()
		PlayerSideScript.remove_from_hand(main, victim, paid)
		if is_instance_valid(paid):
			CardManager._disconnect_card_interaction_signals(paid)
			paid.queue_free()
		pdata["esta_oculta"] = false
		CardManager.append_to_exile(victim, pdata)
	else:
		await main._gold_manager.pagar_coste(int(colapso.get("card_cost")), Constants.CardType.TALISMAN, "", -1, victim)
	var cdata: Dictionary = colapso.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, victim, colapso)
	if is_instance_valid(colapso):
		CardManager._disconnect_card_interaction_signals(colapso)
		colapso.queue_free()
	cdata["esta_oculta"] = false
	CardManager.add_to_cemetery(victim, cdata)
	main._update_debug("Colapso Global: se previene la búsqueda o mirada del oponente")
	await ActionModule.draw(victim, 1, "Colapso Global", true)
	return true


## Prevenir daño al Castillo con un Oro:
## - Alicanto: "En respuesta a que fueras a recibir daño, puedes Desterrar este Oro para prevenirlo.
## Luego, puedes convertir una carta de tu mano en un Oro sin habilidad y ponerla en tu Oro Pagado."
## - Escritura Sagrada: "Puedes subirlo a tu mano o convertirlo en un Oro sin habilidad para
## prevenir recibir daño."
## Se ofrece en BattleManager antes del daño de combate y previene todo ese daño.
func offer_castle_damage_prevention(defender_id: int, damage: int) -> bool:
	var main := get_node_or_null("/root/Main")
	if not main or damage <= 0:
		return false
	var candidates: Array = []
	for zone in [PlayerSideScript.gold_reserva(main, defender_id), PlayerSideScript.oro_pagado(main, defender_id)]:
		if not zone:
			continue
		for c in zone.get_children():
			if not is_instance_valid(c) or c.get("card_ability") == null or KeywordManager.is_silenced(c) \
					or c.get("is_converted") == true:
				continue
			var t: String = str(c.card_ability).to_lower()
			if "en respuesta a que fueras a recibir daño, puedes desterrar este oro para prevenirlo" in t:
				candidates.append({"card": c, "kind": "alicanto"})
			elif "puedes subirlo a tu mano o convertirlo en un oro sin habilidad para prevenir recibir daño" in t:
				candidates.append({"card": c, "kind": "escritura"})
	if candidates.is_empty():
		return false
	var chosen: Dictionary = {}
	if PlayerSideScript.is_bot(defender_id):
		if damage >= 2:
			chosen = candidates[0]
	else:
		for cand in candidates:
			if await SelectionManager.await_two_choice(main,
					"Vas a recibir %d de daño" % damage, "Usar %s para prevenirlo" % str(cand.card.card_name), "No",
					defender_id):
				chosen = cand
				break
	if chosen.is_empty() or not is_instance_valid(chosen.card):
		return false
	var oro: Node = chosen.card
	var oro_name: String = str(oro.card_name)
	if chosen.kind == "alicanto":
		main._gold_manager.exile_gold_from_play(oro)
		main._update_debug("%s: se previene el daño" % oro_name)
		await _alicanto_convert_hand_card(main, defender_id)
	else:
		var to_hand: bool = true
		if not PlayerSideScript.is_bot(defender_id):
			to_hand = await SelectionManager.await_two_choice(main, oro_name, "Subirlo a tu mano",
				"Convertirlo en un Oro sin habilidad", defender_id)
		if to_hand:
			main._gold_manager.return_gold_to_hand(oro)
		else:
			oro.is_converted = true
		main._update_debug("%s: se previene el daño" % oro_name)
	return true


func _alicanto_convert_hand_card(main: Node, pid: int) -> void:
	var hand: Array = PlayerSideScript.hand_cards(main, pid).filter(func(c): return is_instance_valid(c))
	if hand.is_empty() or PlayerSideScript.is_bot(pid) or not main._card_interaction:
		return
	var picked: Node = await main._card_interaction.await_target(
		"Alicanto: puedes convertir una carta de tu mano en un Oro sin habilidad en tu Oro Pagado (N: no)",
		func(c: Node) -> bool: return c in hand, true, pid)
	if not picked or not is_instance_valid(picked):
		return
	var data: Dictionary = picked.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, pid, picked)
	if is_instance_valid(picked):
		CardManager._disconnect_card_interaction_signals(picked)
		picked.queue_free()
	data["esta_oculta"] = false
	var gold_node: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, data)
	if is_instance_valid(gold_node):
		gold_node.card_type = Constants.CardType.ORO
		gold_node.is_converted = true


func schedule_next_final_phase_effect(player_id: int, effect: Callable) -> void:
	if not _scheduled_next_final_phase_effects.has(player_id):
		_scheduled_next_final_phase_effects[player_id] = []
	_scheduled_next_final_phase_effects[player_id].append(effect)


func consume_scheduled_final_phase_effects(player_id: int) -> void:
	"""Llamar al ENTRAR a la Fase Final de player_id (PhaseFlowController.
	_resolve_fase_final()) — ejecuta y limpia (una sola vez) los efectos
	suspendidos agendados para esta Fase Final puntual."""
	var effects: Array = _scheduled_next_final_phase_effects.get(player_id, [])
	if effects.is_empty():
		return
	_scheduled_next_final_phase_effects[player_id] = []
	for effect: Callable in effects:
		if effect.is_valid():
			await effect.call()
