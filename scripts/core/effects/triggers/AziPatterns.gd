extends RefCounted
## Azi del Abismo: "Una vez por turno, Descarta una carta de tu mano para convertir este Aliado
## hasta tu próximo turno en un Oro con la habilidad 'Reduce el daño recibido por tu Castillo en 1
## por cada Oro Azi que controles.'" La conversión y la vuelta a Aliado están en GoldManager
## (convert_ally_to_gold_until_next_turn / revert_converted_golds). Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var rx := RegEx.create_from_string(
		"(?i)descarta una carta de tu mano para convertir este aliado hasta tu próximo turno en un oro con la habilidad [\"“]([^\"”]+)[\"”]")
	var m := rx.search(text.replace("\n", " "))
	if not m:
		return false
	var main := _main_node()
	if not main or not main._gold_manager or not is_instance_valid(card):
		return true
	if card.get("card_type") != Constants.CardType.ALIADO or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return true
	var hand: Array = PlayerSideScript.hand_cards(main, controller_id)
	if hand.is_empty():
		main._update_debug("%s: no tienes cartas en tu mano para Descartar" % str(card.card_name))
		return true
	var picked: Node = null
	if PlayerSideScript.is_bot(controller_id):
		picked = hand[0]
	elif main._card_interaction:
		picked = await main._card_interaction.await_target("%s: Descarta una carta de tu mano" % str(card.card_name),
			func(c: Node) -> bool: return c in hand, false, controller_id)
	if not picked or not is_instance_valid(picked):
		return true
	await ActionModule.discard(controller_id, [picked], "costo_habilidad")
	if not is_instance_valid(card):
		return true
	await main._gold_manager.convert_ally_to_gold_until_next_turn(card, m.get_string(1).strip_edges())
	return true


static func castle_damage_reduction(pid: int) -> int:
	"""'Reduce el daño recibido por tu Castillo en 1 por cada Oro Azi que
	controles' — cada Oro con esta habilidad (no silenciado) reduce tantas
	como Oros Azi controles."""
	var main := _main_node()
	if not main:
		return 0
	var holders := 0
	var azi_golds := 0
	for container in [PlayerSideScript.gold_reserva(main, pid), PlayerSideScript.oro_pagado(main, pid)]:
		if not container:
			continue
		for c in container.get_children():
			if not is_instance_valid(c):
				continue
			if str(c.get("card_name")).to_lower().begins_with("azi") or "azi" in str(c.get("card_raza")).to_lower():
				azi_golds += 1
			if "reduce el daño recibido por tu castillo en 1 por cada oro azi que controles" in str(c.get("card_ability")).to_lower() \
					and not KeywordManager.is_silenced(c):
				holders += 1
	return holders * azi_golds
