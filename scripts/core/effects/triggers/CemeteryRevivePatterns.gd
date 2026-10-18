extends RefCounted
## Alto Prime (2026-10-17, a pedido del usuario): "Puedes Descartar una carta
## para poner este Aliado en juego desde tu Cementerio como un Aliado sin
## habilidad." — habilidad usable desde el Cementerio (no es Exhumar). Mismo
## "sin habilidad" que Belta: entra con el texto vacío. Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const DISCARD_TEXT := "descartar una carta para poner este aliado en juego desde tu cementerio como un aliado sin habilidad"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func discard_to_revive_without_ability(source_card: Node) -> void:
	var main := _main_node()
	if not main or not main._gold_manager or not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var card_name: String = str(source_card.get("card_name"))
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	if cemetery.find(source_card.card_data) < 0:
		return
	var hand: Array = PlayerSideScript.hand_cards(main, owner_id)
	if hand.is_empty():
		main._update_debug("%s: necesitas una carta en tu mano para Descartar" % card_name)
		return
	var picked: Node = null
	if main._card_interaction:
		picked = await main._card_interaction.await_target("%s: Descarta una carta para ponerlo en juego (N: no)" % card_name,
			func(c: Node) -> bool: return c in hand, true, owner_id)
	if not picked or not is_instance_valid(picked):
		return
	await ActionModule.discard(owner_id, [picked], "costo_habilidad")
	var idx: int = CardManager.get_cemetery(owner_id).find(source_card.card_data)
	if idx < 0:
		return
	var data: Dictionary = CardManager.remove_from_cemetery(owner_id, idx)
	var ally_data: Dictionary = data.duplicate()
	ally_data["habilidad"] = ""
	ally_data["esta_oculta"] = false
	var ally_node = main._create_card(ally_data, false)
	ally_node.owner_id = owner_id
	ally_node.controller_id = owner_id
	main._connect_card_signals(ally_node)
	await main._gold_manager._play_card_to_field(ally_node)
	main._update_debug("%s entra en juego desde tu Cementerio como un Aliado sin habilidad" % card_name)


## Kaitai (2026-10-17, bug real reportado por el usuario: en la Fase Final
## resolvía "Roba tres cartas y Descarta dos", que es la de entrada):
## "En tu Fase Final, una vez por turno, puedes Desterrar hasta tantas cartas
## de los Cementerios como Fuerza tenga este Aliado."
static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ")
	# Al atacar, la cláusula aislada es solo la primera oración ("...tu
	# oponente Bota seis cartas"): el resto se lee del texto de la carta.
	var card_lower: String = str(card.get("card_ability")).to_lower().replace("\n", " ") if is_instance_valid(card) else lower
	if "tu oponente bota seis cartas" in lower \
			and "tu oponente bota seis cartas. pon hasta un oro de su cementerio en tu reserva" in card_lower:
		await _pincheira(card, card_lower, controller_id)
		return true
	if not ("desterrar hasta tantas cartas de los cementerios como fuerza tenga este aliado" in lower):
		return false
	if not is_instance_valid(card):
		return true
	var amount: int = int(ContinuousEffectManager.get_modified_strength(card))
	if amount <= 0:
		return true
	await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, amount, true, card,
		Constants.Zone.DESTIERRO)
	return true


## Antonio Pincheira (2026-10-17, a pedido del usuario): "tu oponente Bota
## seis cartas. Pon hasta un Oro de su Cementerio en tu Reserva [y busca dos
## Aliados en tu Castillo y ponlos en tu mano]." — las dos versiones de la
## carta. El Oro sigue siendo de su dueño (vuelve a SU Cementerio) pero lo
## controlas tú.
static func _pincheira(card: Node, lower: String, controller_id: int) -> void:
	var main := _main_node()
	if not main or not main._gold_manager:
		return
	var opponent_id: int = 1 - controller_id
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "Antonio Pincheira"
	await ActionModule.mill(opponent_id, 6, false, card_name)
	var res: Dictionary = await ActionModule.search(opponent_id, Constants.Zone.CEMENTERIO, {"type": Constants.CardType.ORO},
		1, true, false, false, card, -1, false, controller_id)
	for data in res.get("selected", []):
		var node = await main._gold_manager.put_gold_directly_in_reserva(controller_id, data)
		if node and is_instance_valid(node):
			node.owner_id = opponent_id
			node.controller_id = controller_id
	if "busca dos aliados en tu castillo y ponlos en tu mano" in lower:
		await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {"type": Constants.CardType.ALIADO}, 2, true,
			false, false, card, Constants.Zone.MANO)
