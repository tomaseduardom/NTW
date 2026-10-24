extends RefCounted
## MechanicPatterns — Despachador: qué texto de carta va a qué mecánica (lo llama TriggerResolution).
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const CastleTopPlay = preload("res://scripts/core/effects/mechanics/CastleTopPlay.gd")
const ConvertPatterns = preload("res://scripts/core/effects/mechanics/ConvertPatterns.gd")
const InPlayAbilities = preload("res://scripts/core/effects/mechanics/InPlayAbilities.gd")
const SearchPatterns = preload("res://scripts/core/effects/mechanics/SearchPatterns.gd")
const TurnStartPatterns = preload("res://scripts/core/effects/mechanics/TurnStartPatterns.gd")


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ")
	var card_lower: String = CardQuery.ability_of(card) if is_instance_valid(card) else lower
	if "elige dos efectos" in lower and "sube un aliado de tu cementerio a tu mano" in card_lower \
			and "baraja hasta una carta de coste 2 o menos" in card_lower:
		await InPlayAbilities.aegishjalmur(card, controller_id)
		return true
	# ngenechen: "Al comienzo del turno oponente, genera un Oro por el turno y
	# Roba dos cartas."
	if "al comienzo del turno oponente, genera un oro por el turno y roba dos cartas" in lower:
		if await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			return true
		var main_n := CardQuery.main_node()
		if main_n and main_n._gold_manager:
			main_n._gold_manager.generar_oros_virtuales(1, controller_id)
		await ActionModule.draw(controller_id, 2, str(card.get("card_name")), true)
		return true
	if "tu oponente elige dos cartas de su mano. conviértelas en tótem sin habilidad y ponlos en tu línea de defensa" in lower:
		await ConvertPatterns.jeremiel_enter(card, controller_id)
		return true
	if "hasta mostrar dos tótem de coste 2 o menos de distinto nombre y juégalos sin pagar su coste" in lower:
		await SearchPatterns.hoshi_enter(card, controller_id)
		return true
	# Ciudad de los Césares: "Cuando entra o sale del juego, Baraja hasta una
	# carta oponente de coste 3 o menos y Roba dos cartas."
	if "baraja hasta una carta oponente de coste 3 o menos y roba dos cartas" in lower:
		await InPlayAbilities.shuffle_opponent_cost3_draw2(card, controller_id)
		return true
	# Ángel Redentor: "Cuando entra o salga del juego, puedes Descartar una
	# carta para buscar en tu Castillo una carta del mismo tipo y ponerla en
	# tu mano."
	if "puedes descartar una carta para buscar en tu castillo una carta del mismo tipo y ponerla en tu mano" in lower:
		await SearchPatterns.discard_for_same_type(card, controller_id)
		return true
	if TurnStartPatterns.MEDALLA_TEXT in lower:
		await TurnStartPatterns.medalla(card, controller_id)
		return true
	if TurnStartPatterns.KAMIDANA_TEXT in lower:
		await TurnStartPatterns.kamidana(card, controller_id)
		return true
	# Carcosa: "Destierra una carta que no sea Oro o mira la mano de tu
	# oponente y Destierra un Talismán de ahí. Roba una carta."
	if "destierra una carta que no sea oro o mira la mano de tu oponente y destierra un talismán de ahí" in lower:
		await TurnStartPatterns.carcosa(card, controller_id)
		return true
	if "juega mostrando las primeras dos cartas de tu castillo y puedes jugar cartas de coste 1 o más de ahí" in lower:
		await CastleTopPlay.escritura_enter(card, controller_id)
		return true
	# Sidhes del Bosque jugado normal (no en respuesta a una búsqueda).
	if "nombra dos cartas. este turno tu oponente debe mostrar las cartas que busca" in lower:
		await EffectController.resolve_sidhes_effect(controller_id, str(card.get("card_name")) if is_instance_valid(card) else "Sidhes del Bosque")
		return true
	if "convierte hasta una carta que no sea oro en aliado sin habilidad de fuerza 3, gana su control y roba una carta" in lower:
		await ConvertPatterns.convert_non_gold_strength_3(card, controller_id)
		return true
	if ConvertPatterns.VIEJO_TEXT in lower:
		await ConvertPatterns.viejo_del_saco(card, controller_id)
		return true
	if "busca dos cartas del mismo nombre que no sean talismán en tu castillo y ponlas en tu mano" in lower:
		await SearchPatterns.two_of_same_name(card, controller_id)
		return true
	if "busca en tu castillo una carta y ponla en tu mano" in lower \
			and "el próximo oro que ponga en juego tu oponente entra sin habilidad por el turno" in lower:
		await SearchPatterns.supremacia_kaiju(card, controller_id)
		return true
	return false
