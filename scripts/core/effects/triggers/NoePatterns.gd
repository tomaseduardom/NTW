extends RefCounted
## Noé (2026-10-17, a pedido del usuario):
##   "Cuando entra en juego o bloquee, muestra cartas del tope de tu Castillo
##   hasta mostras dos Aliados y ponlos en tu mano. Si tenían costes
##   distintos, puedes jugar uno reduciendo su coste en un Oro, hasta un
##   mínimo de 1."  ("mostras" es errata de la carta)
##   "Una vez por turno, un Aliado gana Furia." (por el turno)
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
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
