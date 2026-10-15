extends RefCounted
## TalismanSearchPatterns — "busca un Talismán en un Castillo y juégalo"
## (2026-10-14, revisión del mazo 170, docs/revision-mazo-170.md).
##
## Reina Nyssara: "busca un Talismán en un Castillo y juégalo reduciendo su
## coste en un Oro, hasta un mínimo de 0 y Roba dos cartas".
## Nyssara Cautiva: "puedes buscar un Talismán en un Castillo, juégalo pagando
## su coste y Roba una carta".
##
## Se elige en el selector del tablero (los dos Castillos, o solo el tuyo si
## dice "tu Castillo"); solo son elegibles los Talismanes que puedes pagar. El
## Talismán se juega bajo tu control pero sigue siendo de su dueño (vuelve a
## SU Cementerio). Se usa con preload, sin class_name global (ver §54).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ")
	var rx := RegEx.new()
	rx.compile("(puedes )?busca(?:r)? un talismán(?: de coste (\\w+) o más)? en (un|tu) castillo,?(?: y)? "
		+ "(?:juégalo|jugarlo) (?:reduciendo su coste en (\\w+) oros?,? hasta un mínimo de (\\w+)|pagando su coste)"
		+ "(?:,? y (?:roba|robar) (\\w+) cartas?)?")
	var m := rx.search(lower)
	if not m:
		return false
	var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var optional: bool = not m.get_string(1).is_empty()
	var min_cost: int = UniversalCardParser._parse_amount(m.get_string(2)) if not m.get_string(2).is_empty() else 0
	var any_castle: bool = m.get_string(3) == "un"
	var discount: int = UniversalCardParser._parse_amount(m.get_string(4)) if not m.get_string(4).is_empty() else 0
	var floor_val: int = UniversalCardParser._parse_amount(m.get_string(5)) if not m.get_string(5).is_empty() else 1
	var draw_n: int = UniversalCardParser._parse_amount(m.get_string(6)) if not m.get_string(6).is_empty() else 0
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "Buscar Talismán"

	if optional and not PlayerSideScript.is_bot(controller_id):
		if not await SelectionManager.await_two_choice(main, card_name, "Buscar un Talismán", "No buscar", controller_id):
			return true

	# Solo Talismanes que se puedan pagar (con el descuento).
	var can_pay := 0
	for n in range(0, 15):
		if main._gold_manager.puede_pagar(n, Constants.CardType.TALISMAN, "", -1, controller_id):
			can_pay = n
		else:
			break
	var filter := {"type": Constants.CardType.TALISMAN, "cost_max": can_pay + discount}
	if min_cost > 0:
		filter["cost_min"] = min_cost
	var res: Dictionary
	if any_castle:
		res = await ActionModule.search_either_owner(controller_id, [Constants.Zone.CASTILLO], filter, 1, true, card, -1)
	else:
		res = await ActionModule.search(controller_id, Constants.Zone.CASTILLO, filter, 1, true, false, false, card, -1)
	var picked: Array = res.get("selected", [])
	if not picked.is_empty():
		var owners: Array = res.get("selected_owners", [])
		var original_owner: int = int(owners[0]) if not owners.is_empty() else controller_id
		await main._gold_manager.play_found_card(picked[0], original_owner, controller_id, discount, floor_val <= 0)
	if draw_n > 0:
		await ActionModule.draw(controller_id, draw_n, card_name, true)
	return true
