extends RefCounted
## Noé (2026-10-17, a pedido del usuario):
##   "Cuando entra en juego o bloquee, muestra cartas del tope de tu Castillo
##   hasta mostras dos Aliados y ponlos en tu mano. Si tenían costes
##   distintos, puedes jugar uno reduciendo su coste en un Oro, hasta un
##   mínimo de 1."  ("mostras" es errata de la carta)
##   "Una vez por turno, un Aliado gana Furia." (por el turno)
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")
const REVEAL_TEXT := "dos aliados y ponlos en tu mano. si tenían costes distintos, puedes jugar uno reduciendo su coste en un oro"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ").strip_edges()
	# Al bloquear, la cláusula aislada es solo la primera oración: lo demás se
	# lee del texto de la carta.
	var card_lower: String = str(card.get("card_ability")).to_lower().replace("\n", " ") if is_instance_valid(card) else lower
	if "hasta mostra" in lower and "dos aliados y ponlos en tu mano" in lower and REVEAL_TEXT in card_lower:
		await _reveal_two_allies(card, controller_id)
		return true
	# Kai Piloto Prodigio (2026-10-17): "puedes hacer que un Aliado gane 1 de
	# Fuerza, Furia y haga doble daño de combate este turno".
	if "hacer que un aliado gane 1 de fuerza, furia y haga doble daño de combate este turno" in lower:
		await _kai_piloto(card, controller_id)
		return true
	# Javiera Carrera (2026-10-17).
	if "un aliado duplica su fuerza por el turno" in lower:
		await _javiera_double(card, controller_id, "si es un carrera, en vez de eso triplica su fuerza" in lower)
		return true
	if "destierra hasta tres cartas de un cementerio y roba una carta" in lower:
		await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, 3, true, card,
			Constants.Zone.DESTIERRO, false, true)
		await ActionModule.draw(controller_id, 1, str(card.get("card_name")) if is_instance_valid(card) else "", true)
		return true
	# Antonio Pincheira (2026-10-17): "En tu Fase Final, agrupa hasta dos
	# Aliados" — vuelven de la Línea de Ataque a la de Defensa.
	if "agrupa hasta dos aliados" in lower:
		await _regroup_up_to(card, controller_id, 2)
		return true
	# Ira (2026-10-17): "Un Aliado gana Furia, Imbloqueable, 3 de Fuerza y
	# hace daño al Destierro por el turno."
	if "un aliado gana furia, imbloqueable, 3 de fuerza y hace daño al destierro por el turno" in lower:
		await _ira(card, controller_id)
		return true
	# el monstruo (2026-10-18): "puedes Botar dos cartas para que hasta dos
	# Aliados ganen Furia y 1 de Fuerza por el turno."
	if "botar dos cartas para que hasta dos aliados ganen furia y 1 de fuerza por el turno" in lower:
		await _el_monstruo(card, controller_id)
		return true
	# Maldición Vudú (2026-10-18).
	if "cancela una habilidad o una carta en juego pierde su habilidad por el turno" in lower:
		await _maldicion_vudu(card, controller_id, "en tu fase final mueve tus oros a tu oro pagado" in lower)
		return true
	# Seducción (2026-10-18).
	if "cada jugador roba hasta tres cartas. por cada carta que robe tu oponente de esta forma" in lower:
		await _seduccion(card, controller_id)
		return true
	# el huascar (2026-10-18): al entrar, un Oro no se agrupa el próximo turno;
	# una vez por turno, Desterrar hasta un Arma o Tótem en juego y Robar dos.
	if "elige un oro para que no pueda ser agrupado el próximo turno" in lower:
		await _huascar_gold_lock(card, controller_id)
		return true
	if "desterrar hasta un arma o tótem en juego y robar dos cartas" in lower:
		await _banish_weapon_or_totem_draw(card, controller_id)
		return true
	var core := lower.trim_suffix(".").replace("una vez por turno,", "").strip_edges()
	if core == "un aliado gana furia":
		await _grant_furia(card, controller_id)
		return true
	return false


static func _reveal_two_allies(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main or not main._gold_manager:
		return
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "Noé"
	if await TriggerSystem.open_response_window(card, card_name, controller_id):
		return
	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var allies: Array = []
	while not deck.is_empty() and allies.size() < 2:
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		if int(top.get("tipo", -1)) == Constants.CardType.ALIADO:
			allies.append(top)
	if not revealed.is_empty():
		SelectionManager.open_reveal(revealed.duplicate(), "%s: cartas mostradas" % card_name, controller_id)
	for a in allies:
		revealed.erase(a)
	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	# A la mano.
	var hand = PlayerSideScript.hand(main, controller_id)
	var nodes: Array = []
	for data in allies:
		data["esta_oculta"] = false
		var node = main._create_card(data, false)
		node.owner_id = controller_id
		node.controller_id = controller_id
		if hand:
			hand.add_card(node)
		main._connect_card_signals(node)
		nodes.append(node)
	if nodes.size() < 2 or int(allies[0].get("coste", -1)) == int(allies[1].get("coste", -1)):
		return
	# Costes distintos: puedes jugar uno con -1 Oro (mínimo 1), si lo puedes pagar.
	var gm = main._gold_manager
	var playable: Array = nodes.filter(func(n):
		var cost: int = maxi(1, int(n.get("card_cost")) - 1)
		return is_instance_valid(n) and gm.puede_pagar(cost, Constants.CardType.ALIADO, str(n.get("card_raza")), int(n.get("card_cost")), controller_id))
	if playable.is_empty():
		return
	var picked: Node = null
	if PlayerSideScript.is_bot(controller_id):
		picked = playable[0]
	elif main._card_interaction:
		picked = await main._card_interaction.await_target(
			"%s: puedes jugar uno de esos Aliados con un Oro menos, mínimo 1 (N: no)" % card_name,
			func(c: Node) -> bool: return c in playable, true, controller_id)
	if not picked or not is_instance_valid(picked):
		return
	var data: Dictionary = picked.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, controller_id, picked)
	if is_instance_valid(picked):
		CardManager._disconnect_card_interaction_signals(picked)
		picked.queue_free()
	await gm.play_found_card(data, controller_id, controller_id, 1, false)


static func _grant_furia(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("current_zone") in Constants.ZONES_IN_PLAY
	var target: Node = null
	if PlayerSideScript.is_bot(controller_id):
		for container in PlayerSideScript.ally_containers(main, controller_id):
			for a in container.get_children():
				if is_instance_valid(a) and filter.call(a):
					target = a
					break
			if target:
				break
	elif main._card_interaction:
		target = await main._card_interaction.await_target("Un Aliado gana Furia", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return
	# Permanente (2026-10-17, regla del usuario: sin duración escrita, solo
	# los cambios de Fuerza son "por el turno"; lo demás es permanente).
	KeywordManager.grant_keyword(target, Constants.Keyword.FURIA, card, "permanent")
	main._update_debug("%s gana Furia" % str(target.get("card_name")))


static func _kai_piloto(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("current_zone") in Constants.ZONES_IN_PLAY
	var target: Node = null
	if PlayerSideScript.is_bot(controller_id):
		for container in PlayerSideScript.ally_containers(main, controller_id):
			for a in container.get_children():
				if is_instance_valid(a) and filter.call(a):
					target = a
					break
			if target:
				break
	elif main._card_interaction:
		target = await main._card_interaction.await_target(
			"Un Aliado gana 1 de Fuerza, Furia y hace doble daño de combate este turno", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return
	if await EffectController.offer_prevention(target, card, "strength_change"):
		return
	ContinuousEffectManager.register_modifier({
		"source": target,
		"target": target,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": 1,
		"operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
		"description": "Kai Piloto Prodigio +1",
	})
	KeywordManager.grant_keyword(target, Constants.Keyword.FURIA, card, "turn")
	target.set_meta("double_combat_damage_turn", GameManager.current_turn)
	main._update_debug("%s gana 1 de Fuerza, Furia y hace doble daño de combate este turno" % str(target.get("card_name")))


## Javiera Carrera: "Una vez por turno, un Aliado duplica su Fuerza por el
## turno. Si es un Carrera, en vez de eso triplica su Fuerza y no puede salir
## del juego hasta tu próximo turno." ("un Carrera" = su nombre lo dice)
static func _javiera_double(card: Node, controller_id: int, carrera_clause: bool) -> void:
	var main := _main_node()
	if not main:
		return
	var filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("current_zone") in Constants.ZONES_IN_PLAY
	var target: Node = null
	if PlayerSideScript.is_bot(controller_id):
		for container in PlayerSideScript.ally_containers(main, controller_id):
			for a in container.get_children():
				if is_instance_valid(a) and filter.call(a):
					target = a
					break
			if target:
				break
	elif main._card_interaction:
		target = await main._card_interaction.await_target("Un Aliado duplica su Fuerza por el turno (un Carrera la triplica)",
			filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return
	if await EffectController.offer_prevention(target, card, "strength_change"):
		return
	var is_carrera: bool = carrera_clause and "carrera" in str(target.get("card_name")).to_lower()
	var current: int = int(ContinuousEffectManager.get_modified_strength(target))
	var extra: int = current * (2 if is_carrera else 1)
	if extra > 0:
		ContinuousEffectManager.register_modifier({
			"source": target,
			"target": target,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": extra,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "Javiera Carrera x%d" % (3 if is_carrera else 2),
		})
	if is_carrera:
		EffectController.add_single_card_leave_play_immunity(target, controller_id)
	main._update_debug("%s %s su Fuerza%s" % [str(target.get("card_name")), "triplica" if is_carrera else "duplica",
		" y no puede salir del juego hasta tu próximo turno" if is_carrera else " por el turno"])


static func _regroup_up_to(card: Node, controller_id: int, amount: int) -> void:
	var main := _main_node()
	if not main or not main._card_interaction:
		return
	var atk_line = main.player_linea_ataque if controller_id == 0 else main.opponent_linea_ataque
	if not atk_line:
		return
	var candidates: Array = atk_line.get_children().filter(func(c):
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	if candidates.is_empty():
		return
	var chosen: Array = []
	if PlayerSideScript.is_bot(controller_id):
		chosen = candidates.slice(0, amount)
	else:
		chosen = await main._card_interaction.await_multi_target(
			"%s: agrupa hasta %d Aliados" % [str(card.get("card_name")) if is_instance_valid(card) else "Agrupar", amount],
			candidates, amount, Callable(), Callable(), true, null, controller_id)
	if chosen.is_empty():
		return
	await main._card_interaction.unmark_attackers(chosen)
	main._update_debug("%d Aliado(s) agrupados" % chosen.size())


static func _pick_ally(main: Node, controller_id: int, prompt: String) -> Node:
	var filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("current_zone") in Constants.ZONES_IN_PLAY
	if PlayerSideScript.is_bot(controller_id):
		for container in PlayerSideScript.ally_containers(main, controller_id):
			for a in container.get_children():
				if is_instance_valid(a) and filter.call(a):
					return a
		return null
	if not main._card_interaction:
		return null
	return await main._card_interaction.await_target(prompt, filter, true, controller_id)


static func _turn_strength(target: Node, amount: int, label: String) -> void:
	ContinuousEffectManager.register_modifier({
		"source": target,
		"target": target,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": amount,
		"operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
		"description": label,
	})


static func _ira(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var target: Node = await _pick_ally(main, controller_id, "Ira: un Aliado gana Furia, Imbloqueable, 3 de Fuerza y hace daño al Destierro")
	if not target or not is_instance_valid(target):
		return
	if await EffectController.offer_prevention(target, card, "strength_change"):
		return
	_turn_strength(target, 3, "Ira +3")
	KeywordManager.grant_keyword(target, Constants.Keyword.FURIA, card, "turn")
	KeywordManager.grant_keyword(target, Constants.Keyword.IMBLOQUEABLE, card, "turn")
	target.set_meta("damage_to_exile_turn", GameManager.current_turn)  # BattleManager._accumulate_castle_damage
	main._update_debug("%s gana Furia, Imbloqueable, 3 de Fuerza y hace daño al Destierro por el turno" % str(target.get("card_name")))


## Ira, desde el Cementerio: "puedes Desterrarlo para que un Aliado gane 1 de
## Fuerza y su ataque no pueda ser cancelado por el turno."
static func ira_from_cemetery(source_card: Node) -> void:
	var main := _main_node()
	if not main or not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	var idx: int = cemetery.find(source_card.card_data)
	if idx < 0:
		return
	var target: Node = await _pick_ally(main, owner_id, "Ira: un Aliado gana 1 de Fuerza y su ataque no puede ser cancelado")
	if not target or not is_instance_valid(target):
		return
	idx = CardManager.get_cemetery(owner_id).find(source_card.card_data)
	if idx < 0:
		return
	var data: Dictionary = CardManager.remove_from_cemetery(owner_id, idx)
	data["esta_oculta"] = false
	CardManager.append_to_exile(owner_id, data)
	_turn_strength(target, 1, "Ira +1")
	target.set_meta("attack_uncancellable_turn", GameManager.current_turn)
	main._update_debug("%s gana 1 de Fuerza y su ataque no puede ser cancelado por el turno" % str(target.get("card_name")))


static func _el_monstruo(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "el monstruo"
	# Costo: Botar dos cartas de tu Castillo.
	if CardManager.get_deck_count(controller_id) < 2:
		main._update_debug("%s: no tienes dos cartas en tu Castillo para Botar" % card_name)
		return
	await ActionModule.mill(controller_id, 2, false, card_name)
	var candidates: Array = []
	for container in PlayerSideScript.ally_containers(main, controller_id):
		for a in container.get_children():
			if is_instance_valid(a) and a.get("card_type") == Constants.CardType.ALIADO:
				candidates.append(a)
	if candidates.is_empty():
		return
	var chosen: Array = []
	if PlayerSideScript.is_bot(controller_id):
		chosen = candidates.slice(0, 2)
	elif main._card_interaction:
		chosen = await main._card_interaction.await_multi_target(
			"%s: hasta dos Aliados ganan Furia y 1 de Fuerza por el turno" % card_name, candidates, 2,
			Callable(), Callable(), true, null, controller_id)
	for a in chosen:
		if not is_instance_valid(a):
			continue
		_turn_strength(a, 1, "el monstruo +1")
		KeywordManager.grant_keyword(a, Constants.Keyword.FURIA, card, "turn")
	if not chosen.is_empty():
		main._update_debug("%s: %d Aliado(s) ganan Furia y 1 de Fuerza por el turno" % [card_name, chosen.size()])


# -----------------------------------------------------------------------------
# Maldición Vudú: "Sólo puedes jugarlo durante tu turno. Cancela una habilidad
# o una carta en juego pierde su habilidad por el turno. En tu Fase Final
# mueve tus Oros a tu Oro Pagado. Puedes Desterrarlo de tu Cementerio para
# Barajar o Desterrar una carta de un Cementerio."
# -----------------------------------------------------------------------------
static func _maldicion_vudu(card: Node, controller_id: int, move_golds_at_final: bool) -> void:
	var main := _main_node()
	if not main:
		return
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "Maldición Vudú"
	var cancel_obj: Dictionary = StackAnnulScript.find_target(controller_id, false, true)
	var do_cancel := false
	if not cancel_obj.is_empty():
		if PlayerSideScript.is_bot(controller_id):
			do_cancel = true
		else:
			do_cancel = await SelectionManager.await_two_choice(main, card_name,
				"Cancelar la habilidad de %s" % str(StackAnnulScript.data_of(cancel_obj).get("nombre", "esa carta")),
				"Una carta en juego pierde su habilidad por el turno", controller_id)
	if do_cancel:
		StackAnnulScript.apply(cancel_obj, card)
	else:
		var filter := func(c: Node) -> bool:
			return c.get("current_zone") in Constants.ZONES_IN_PLAY and not KeywordManager.is_silenced(c)
		var target: Node = null
		if not PlayerSideScript.is_bot(controller_id) and main._card_interaction:
			target = await main._card_interaction.await_target("%s: una carta en juego pierde su habilidad por el turno (N: ninguna)" % card_name,
				filter, true, controller_id)
		if target and is_instance_valid(target):
			await KeywordManager.silence_card(target, card, "turn")
	if move_golds_at_final:
		_move_golds_to_paid_at_final(main, controller_id)


static func _move_golds_to_paid_at_final(main: Node, controller_id: int) -> void:
	var turn: int = GameManager.current_turn
	var gm = main._gold_manager
	var on_phase: Callable
	on_phase = func(new_phase) -> void:
		if GameManager.current_turn != turn:
			if GameManager.phase_changed.is_connected(on_phase):
				GameManager.phase_changed.disconnect(on_phase)
			return
		if new_phase != Constants.Phase.FINAL or GameManager.active_player_id != controller_id:
			return
		if GameManager.phase_changed.is_connected(on_phase):
			GameManager.phase_changed.disconnect(on_phase)
		if not is_instance_valid(gm):
			return
		var tokens: Array = gm.virtual_gold_tokens.get(controller_id, []).duplicate()
		for pool in gm.restricted_gold_pools.get(controller_id, []):
			tokens.append_array(pool.tokens)
		var reserva: Node = PlayerSideScript.gold_reserva(main, controller_id)
		var moved := 0
		for c in reserva.get_children().duplicate():
			if is_instance_valid(c) and not (c in tokens):
				if not await gm._mover_oro_a_pagado(c):
					moved += 1
		if moved > 0:
			GameState.pagar_oro(controller_id, moved)
			gm._update_gold_display()
			main._update_debug("Maldición Vudú: tus Oros van a tu Oro Pagado")
	GameManager.phase_changed.connect(on_phase)


static func maldicion_from_cemetery(source_card: Node) -> void:
	"""'Puedes Desterrarlo de tu Cementerio para Barajar o Desterrar una carta
	de un Cementerio.'"""
	var main := _main_node()
	if not main or not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var idx: int = CardManager.get_cemetery(owner_id).find(source_card.card_data)
	if idx < 0:
		return
	var shuffle_it: bool = await SelectionManager.await_two_choice(main, str(source_card.get("card_name")),
		"Barajar una carta de un Cementerio", "Desterrar una carta de un Cementerio", owner_id)
	idx = CardManager.get_cemetery(owner_id).find(source_card.card_data)
	if idx < 0:
		return
	var data: Dictionary = CardManager.remove_from_cemetery(owner_id, idx)
	data["esta_oculta"] = false
	CardManager.append_to_exile(owner_id, data)
	var res: Dictionary = await ActionModule.search_either_owner(owner_id, [Constants.Zone.CEMENTERIO], {}, 1, true, null,
		Constants.Zone.CASTILLO if shuffle_it else Constants.Zone.DESTIERRO)
	if shuffle_it:
		for pid in [0, 1]:
			for d in res.get("selected", []):
				if CardManager.get_deck(pid).has(d):
					CardManager.shuffle_deck(pid)
					break


# -----------------------------------------------------------------------------
# Seducción: "Cuando lo juegues, elige un efecto y Destiérralo.
#   - Cada jugador Roba hasta tres cartas. Por cada carta que Robe tu oponente
#     de esta forma, Destierra dos cartas del tope de su Castillo.
#   - Cada jugador pone un Oro de su mano en su Oro Pagado. El Oro oponente
#     entra en juego sin habilidad por el turno."
# -----------------------------------------------------------------------------
static func _seduccion(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "Seducción"
	var opponent_id: int = 1 - controller_id
	var draw_mode: bool = true
	if not PlayerSideScript.is_bot(controller_id):
		draw_mode = await SelectionManager.await_two_choice(main, card_name,
			"Cada jugador Roba hasta tres cartas", "Cada jugador pone un Oro de su mano en su Oro Pagado", controller_id)
	if draw_mode:
		await ActionModule.draw_up_to(controller_id, 3, card_name, true)
		var before: int = PlayerSideScript.hand_cards(main, opponent_id).size()
		await ActionModule.draw_up_to(opponent_id, 3, card_name, true)
		var drawn: int = maxi(0, PlayerSideScript.hand_cards(main, opponent_id).size() - before)
		if drawn > 0:
			await ActionModule.mill(opponent_id, drawn * 2, true, card_name)
			main._update_debug("%s: tu oponente robó %d y Destierra %d del tope de su Castillo" % [card_name, drawn, drawn * 2])
		return
	for pid in [controller_id, opponent_id]:
		var golds: Array = PlayerSideScript.hand_cards(main, pid).filter(func(c):
			return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ORO)
		if golds.is_empty():
			continue
		var picked: Node = golds[0]
		if not PlayerSideScript.is_bot(pid) and main._card_interaction:
			picked = await main._card_interaction.await_target("%s: pon un Oro de tu mano en tu Oro Pagado" % card_name,
				func(c: Node) -> bool: return c in golds, false, pid)
		if not picked or not is_instance_valid(picked):
			continue
		var data: Dictionary = picked.card_data.duplicate()
		data["esta_oculta"] = false
		PlayerSideScript.remove_from_hand(main, pid, picked)
		if is_instance_valid(picked):
			CardManager._disconnect_card_interaction_signals(picked)
			picked.queue_free()
		var node = await main._gold_manager.put_gold_directly_in_pagado(pid, data)
		if pid == opponent_id and node and is_instance_valid(node):
			await KeywordManager.silence_card(node, card, "turn", true)


# -----------------------------------------------------------------------------
# el huascar
# -----------------------------------------------------------------------------
static func _huascar_gold_lock(card: Node, controller_id: int) -> void:
	"""'Cuando entra en juego, elige un Oro para que no pueda ser agrupado el
	próximo turno.' Su próximo turno = el del controlador de ese Oro."""
	var main := _main_node()
	if not main:
		return
	var filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ORO and c.get("current_zone") in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]
	var target: Node = null
	if PlayerSideScript.is_bot(controller_id):
		for container in [PlayerSideScript.oro_pagado(main, 1 - controller_id), PlayerSideScript.gold_reserva(main, 1 - controller_id)]:
			for c in container.get_children():
				if is_instance_valid(c) and filter.call(c):
					target = c
					break
			if target:
				break
	elif main._card_interaction:
		target = await main._card_interaction.await_target("Elige un Oro: no podrá ser agrupado el próximo turno (N: ninguno)",
			filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return
	var gold_ctrl: int = target.controller_id if target.get("controller_id") != null else 1 - controller_id
	var next_turn: int = GameManager.current_turn + (1 if gold_ctrl != GameManager.active_player_id else 2)
	target.set_meta("no_regroup_turn", next_turn)  # GoldManager._reset_gold / EasyBot.reset_gold
	main._update_debug("%s no podrá ser agrupado el próximo turno" % str(target.get("card_name")))


static func _banish_weapon_or_totem_draw(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var filter := func(c: Node) -> bool:
		return c.get("card_type") in [Constants.CardType.ARMA, Constants.CardType.TOTEM] \
			and c.get("current_zone") in Constants.ZONES_IN_PLAY
	var target: Node = null
	if not PlayerSideScript.is_bot(controller_id) and main._card_interaction:
		target = await main._card_interaction.await_target("Destierra hasta un Arma o Tótem en juego (N: ninguna)",
			filter, true, controller_id)
	if target and is_instance_valid(target):
		await ActionModule.banish([target], card)
	await ActionModule.draw(controller_id, 2, str(card.get("card_name")) if is_instance_valid(card) else "", true)
