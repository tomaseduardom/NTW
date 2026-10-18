extends RefCounted
## Plaga de Ratas (2026-10-17, a pedido del usuario):
##   "Cuando entra en juego, puedes buscar un Plaga de Ratas en tu Castillo o
##   Cementerio y juégalo sin pagar su coste.
##   Puedes Destruirlo para Barajar hasta dos cartas de los Cementerios o que
##   un Aliado gane 1 de Fuerza permanentemente."
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const ETB_RX := "(?i)busca(?:r)? (?:un|una) ([^.]+?) en tu castillo o cementerio y juégalo sin pagar su coste"
const DESTROY_TEXT := "destruirlo para barajar hasta dos cartas de los cementerios o que un aliado gane 1 de fuerza permanentemente"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower()
	if DESTROY_TEXT in lower:
		await _destroy_for_choice(card, controller_id)
		return true
	var m := RegEx.create_from_string(ETB_RX).search(text.replace("\n", " "))
	if m and "plaga de ratas" in m.get_string(1).to_lower():
		await _search_copy_and_play(card, m.get_string(1).strip_edges(), controller_id)
		return true
	return false


static func _search_copy_and_play(card: Node, wanted_name: String, controller_id: int) -> void:
	"""'Puedes buscar un Plaga de Ratas en tu Castillo o Cementerio y
	juégalo sin pagar su coste' — opcional: N/ESC o confirmar sin elegir."""
	var main := _main_node()
	if not main or not main._gold_manager:
		return
	var filter := {"name_contains": wanted_name}
	var res: Dictionary = await ActionModule.search_zones(controller_id,
		[Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO], filter, 1, true, false, false, card, -1)
	for data in res.get("selected", []):
		await main._gold_manager.play_found_card(data, controller_id, controller_id, 99, true)


static func _destroy_for_choice(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main or not is_instance_valid(card):
		return
	var card_name: String = str(card.get("card_name"))
	# Costo: Destruirlo. Si no se puede (Indestructible), no hay efecto.
	if not KeywordManager.can_be_destroyed(card):
		main._update_debug("%s no puede ser Destruido: no puedes pagar el costo" % card_name)
		return
	var shuffle_it: bool = true
	if PlayerSideScript.is_bot(controller_id):
		shuffle_it = randf() < 0.5
	else:
		shuffle_it = await SelectionManager.await_two_choice(main, card_name,
			"Barajar hasta dos cartas de los Cementerios", "Un Aliado gana 1 de Fuerza permanentemente", controller_id)
	var owner_id: int = card.owner_id if card.get("owner_id") != null else controller_id
	await EffectController.destroy_card(owner_id, card, false)
	if shuffle_it:
		var res: Dictionary = await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, 2,
			true, null, Constants.Zone.CASTILLO)
		var selected: Array = res.get("selected", [])
		for pid in [0, 1]:
			var deck: Array = CardManager.get_deck(pid)
			for d in selected:
				if deck.has(d):
					CardManager.shuffle_deck(pid)
					break
		return
	var allies_filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("current_zone") in Constants.ZONES_IN_PLAY
	var target: Node = null
	if PlayerSideScript.is_bot(controller_id):
		for c in PlayerSideScript.ally_containers(main, controller_id):
			for a in c.get_children():
				if is_instance_valid(a) and allies_filter.call(a):
					target = a
					break
			if target:
				break
	elif main._card_interaction:
		target = await main._card_interaction.await_target("%s: un Aliado gana 1 de Fuerza permanentemente" % card_name,
			allies_filter, false, controller_id)
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
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
		"description": "Plaga de Ratas +1",
	})
	main._update_debug("%s gana 1 de Fuerza permanentemente" % str(target.get("card_name")))
