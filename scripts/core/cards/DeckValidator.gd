extends RefCounted
class_name DeckValidator
## DeckValidator — reglas de construcción del mazo (DAR 4.1) para las partidas en línea:
## - Exactamente Constants.DECK_SIZE cartas.
## - Hasta Constants.MAX_COPIES_PER_CARD copias por nombre; Única, una sola; los Oros sin habilidad y
##   las cartas con "puedes tener más de tres copias", sin límite.
## - Sin cartas baneadas (BANNED).
## "No puedes controlar más copias de esta carta" limita las copias en juego, no el mazo.

const KeywordParserScript = preload("res://scripts/core/cards/KeywordParser.gd")

const BANNED := ["liberar esclavos"]


static func validate_ids(card_ids: Array) -> Array:
	"""Errores del mazo recibido por red como lista de IDs (vacío si es válido). Un ID que no está en
	CardDatabase es un error: no se descarta en silencio."""
	var cards: Array = []
	var unknown := 0
	for card_id in card_ids:
		var data: Dictionary = CardDatabase.get_card(str(card_id)) if CardDatabase.is_loaded else {}
		if data.is_empty():
			unknown += 1
		else:
			cards.append(data)
	var errors := validate(cards)
	if unknown > 0:
		errors.push_front("%d carta(s) que no existen en la base de datos." % unknown)
	return errors


static func validate(cards: Array) -> Array:
	"""Errores del mazo (lista de datos de carta; vacío si es válido)."""
	var errors: Array = []
	if cards.is_empty():
		errors.append("El mazo está vacío.")
		return errors
	if cards.size() != Constants.DECK_SIZE:
		errors.append("El mazo tiene %d cartas (deben ser %d)." % [cards.size(), Constants.DECK_SIZE])

	var counts := {}
	var shown := {}
	var limits := {}
	for data in cards:
		var name := _norm(str(data.get("nombre", "")))
		counts[name] = int(counts.get(name, 0)) + 1
		shown[name] = str(data.get("nombre", ""))
		limits[name] = mini(int(limits.get(name, 1 << 30)), _copy_limit(data))

	for name in counts:
		if name in BANNED:
			errors.append("%s está baneada." % shown[name])
		elif counts[name] > limits[name]:
			errors.append("%s: %d copias (máximo %d)." % [shown[name], counts[name], limits[name]])
	return errors


static func _copy_limit(data: Dictionary) -> int:
	var ability := str(data.get("habilidad", "")).strip_edges()
	if int(data.get("tipo", -1)) == Constants.CardType.ORO and ability.is_empty():
		return 1 << 30
	var low := _norm(ability)
	if "puedes tener mas de tres copias" in low:
		return 1 << 30
	if KeywordParserScript.has_own(ability, Constants.Keyword.UNICA):
		return Constants.MAX_COPIES_UNIQUE
	return Constants.MAX_COPIES_PER_CARD


static func _norm(s: String) -> String:
	return preload("res://scripts/core/cards/CardText.gd").fold(s).strip_edges()
