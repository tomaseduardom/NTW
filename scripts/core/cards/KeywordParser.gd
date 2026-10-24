extends RefCounted
## KeywordParser — única fuente de las palabras clave impresas de una carta (Furia, Imbloqueable,
## Indestructible, Indesterrable, Única, Exhumar, Errante, Retador), leídas por oración y no por
## subcadena del texto completo:
## - propias: una oración que es solo una lista de palabras clave ("Furia.", "Furia e Imbloqueable.",
##   "Exhumar:") es de la carta. "Tus Aliados ganan Furia", "un Aliado gana Indestructible por el
##   turno" o "con la habilidad "Furia"" son efectos o habilidades otorgadas, no de la carta.
## - del portador (Armas): las propias del Arma (salvo Única/Exhumar, que son de la carta) más las
##   de "El portador gana..." sin condición.
## - condicionales: "Si <condición>, gana X" (de la carta o, con "el portador", del portador) y
##   "El portador gana X y, si es un Ángel, gana Y". La condición queda como Dictionary {kind, ...}
##   y la evalúa KeywordConditions.gd contra el estado de la partida (Card.has_keyword(),
##   ExhumarSystem). Una condición que no se reconoce no da la palabra clave.
## - quitadas por auras: "Los Aliados de coste 1 o menos pierden Furia", "Los Aliados oponentes pierden
##   Indestructible e Indesterrable", "Si está en tu Reserva, ..." (las evalúa KeywordAuras.gd).
## Las citas ("...") se quitan antes de partir en oraciones: son habilidades que otra carta recibe.
## Se usa con preload (sin class_name global; ver §54).

const K = preload("res://scripts/core/config/Constants.gd").Keyword

const WORDS := {
	"furia": K.FURIA,
	"imbloqueable": K.IMBLOQUEABLE,
	"indestructible": K.INDESTRUCTIBLE,
	"indesterrable": K.INDESTERRABLE,
	"única": K.UNICA,
	"unica": K.UNICA,
	"exhumar": K.EXHUMAR,
	"errante": K.ERRANTE,
	"retador": K.RETADOR,
}

## Se juega a sí misma desde el Cementerio: cuenta como Exhumar. "desde tu Cementerio" en otras
## habilidades ("Desterrarlo desde tu Cementerio", "poner este Aliado en juego desde tu Cementerio
## como un Aliado sin habilidad", p.ej. Alto Prime) no.
const SELF_PLAY_FROM_CEMETERY := [
	"jugarlo desde tu cementerio", "jugarla desde tu cementerio", "jugar esta carta desde tu cementerio",
	"jugar esta arma desde tu cementerio", "ponerlo en juego desde tu cementerio como si estuviera en tu mano",
	"poner este oro en juego desde tu cementerio",
]

const NUMBERS := {"un": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
	"ocho": 8, "nueve": 9, "diez": 10}
## "Si es un Aliado..." no es una condición de Raza.
const NOT_RACE := ["aliado", "arma", "oro", "tótem", "totem", "talismán", "talisman"]

## De la carta, no se pasan al portador.
const CARD_ONLY := [K.UNICA, K.EXHUMAR]

static var _cache: Dictionary = {}
static var _rx_quoted: RegEx = null
static var _rx_open_quote: RegEx = null
static var _rx_split: RegEx = null
static var _rx_list: RegEx = null
static var _rx_word: RegEx = null
static var _rx_condition: RegEx = null
static var _rx_if: RegEx = null
static var _rx_mid: RegEx = null
static var _rx_enter: RegEx = null
static var _rx_race_word: RegEx = null
static var _cond_rxs: Array = []
static var _rx_removal: RegEx = null
static var _rx_if_any: RegEx = null
static var _rx_removal_skip: RegEx = null


static func own_keywords(text: String) -> Array:
	"""Palabras clave impresas de la carta (Array de Constants.Keyword)."""
	return _parse(text).own


static func wielder_keywords(text: String) -> Array:
	"""Palabras clave que un Arma da a su portador."""
	return _parse(text).wielder


static func conditional_keywords(text: String) -> Array:
	"""Palabras clave con condición: [{keyword, who: "self" | "wielder", cond: {kind, ...}}]."""
	return _parse(text).conditional


static func removals(text: String) -> Array:
	"""Auras que quitan palabras clave: [{keywords, cards: "aliados" | "cartas", max_cost (-1 = sin
	tope), opponents: bool, zone: "play" | "reserva" | "exile", cond: {} o {kind, negate?}}]."""
	return _parse(text).removals


static func sentences(text: String) -> Array:
	"""Oraciones del texto en minúsculas, sin las citas (habilidades que otra carta recibe)."""
	_compile()
	var clean := _rx_quoted.sub(text.to_lower(), " ", true)
	clean = _rx_open_quote.sub(clean, " ")
	var out: Array = []
	for raw in _rx_split.sub(clean, "\n", true).split("\n", false):
		var sentence: String = raw.strip_edges()
		if not sentence.is_empty():
			out.append(sentence)
	return out


static func parse_condition(text: String) -> Dictionary:
	"""Condición de "Si <texto>, ..." como Dictionary {kind, ...} (KeywordConditions), o {}."""
	_compile()
	return _parse_condition(text)


static func keyword_of(word: String) -> int:
	"""Constants.Keyword de una palabra ("furia"), o -1."""
	return int(WORDS.get(word, -1))


static func has_own(text: String, keyword: int) -> bool:
	return keyword in _parse(text).own


static func _parse(text: String) -> Dictionary:
	if _cache.has(text):
		return _cache[text]
	_compile()
	var own: Array = []
	var wielder: Array = []
	var conditional: Array = []
	var removals: Array = []
	var previous := ""
	var lower := text.to_lower()
	var clean := _rx_quoted.sub(lower, " ", true)
	clean = _rx_open_quote.sub(clean, " ")
	for raw in _rx_split.sub(clean, "\n", true).split("\n", false):
		var sentence: String = raw.strip_edges()
		if sentence.is_empty():
			continue
		var removal := _parse_removal(sentence, previous)
		previous = sentence
		if not removal.is_empty():
			removals.append(removal)
			continue
		var head := sentence.get_slice(":", 0).strip_edges()
		if _rx_list.search(sentence) or _rx_list.search(head):
			_add_words(own, head if _rx_list.search(head) else sentence)
		elif sentence.begins_with("el portador"):
			_add_words(wielder, _before_condition(sentence))
			var mid := _rx_mid.search(sentence)
			if mid:
				_add_conditional(conditional, "wielder", _parse_condition(mid.get_string(1)), mid.get_string(2))
		elif sentence.begins_with("si "):
			var m := _rx_if.search(sentence)
			if m:
				var subject := m.get_string(1)
				var who := "wielder" if m.get_string(2) == "el portador " or subject.begins_with("el portador") else "self"
				_add_conditional(conditional, who, _parse_condition(subject), m.get_string(3))
		elif _rx_enter.search(sentence):
			# Los Señalados: "No puede ser bloqueado el turno que entra en juego".
			conditional.append({"keyword": K.IMBLOQUEABLE, "who": "self", "cond": {"kind": "entered_this_turn"}})
	for phrase in SELF_PLAY_FROM_CEMETERY:
		if phrase in lower and K.EXHUMAR not in own:
			own.append(K.EXHUMAR)
	for kw in own:
		if kw not in CARD_ONLY and kw not in wielder:
			wielder.append(kw)
	var result := {"own": own, "wielder": wielder, "conditional": conditional, "removals": removals}
	_cache[text] = result
	return result


static func _parse_removal(sentence: String, previous: String) -> Dictionary:
	"""Un aura "pierden X". "De lo contrario, ..." (dotaku) vale cuando NO se cumple la condición de la
	oración anterior ("Si controlas más Oros que tu oponente, ...")."""
	var cond := {}
	if sentence.begins_with("de lo contrario, "):
		var prev := _rx_if_any.search(previous)
		if not prev:
			return {}
		cond = _parse_condition(prev.get_string(1))
		if cond.is_empty():
			return {}
		cond = cond.duplicate()
		cond["negate"] = true
		sentence = sentence.trim_prefix("de lo contrario, ")
	elif _rx_removal_skip.search(sentence):
		return {}
	var m := _rx_removal.search(sentence)
	if not m:
		return {}
	var keywords: Array = []
	_add_words(keywords, m.get_string(6))
	if keywords.is_empty():
		return {}
	var zone := m.get_string(1)
	return {
		"keywords": keywords,
		"cards": m.get_string(3),
		"max_cost": _number(m.get_string(4)) if m.get_string(4) != "" else -1,
		"opponents": m.get_string(5) != "",
		"zone": "reserva" if zone == "reserva" else ("exile" if zone == "destierro" else "play"),
		"cond": cond,
	}


static func _before_condition(sentence: String) -> String:
	var m := _rx_condition.search(sentence)
	return sentence.substr(0, m.get_start()) if m else sentence


static func _add_conditional(into: Array, who: String, cond: Dictionary, granted: String) -> void:
	if cond.is_empty():
		return
	for m in _rx_word.search_all(granted):
		into.append({"keyword": WORDS[m.get_string()], "who": who, "cond": cond})


static func _parse_condition(text: String) -> Dictionary:
	"""Condición de "Si <texto>, gana...", o {} si no se reconoce."""
	for entry in _cond_rxs:
		var m: RegExMatch = entry.rx.search(text)
		if not m:
			continue
		match entry.kind:
			"armed", "fewer_hand", "attacked_last_turn", "more_golds":
				return {"kind": entry.kind}
			"allies_at_least":
				var zone := m.get_string(2)
				return {"kind": entry.kind, "n": _number(m.get_string(1)),
					"zone": "cemetery" if zone == "tu cementerio" else ("exile" if zone == "tu destierro" else "play")}
			"exile_types_at_least", "hand_at_most", "golds_at_least", "exiles_at_least", "exile_types_total_at_least":
				return {"kind": entry.kind, "n": _number(m.get_string(1))}
			"controls_named":
				var named := m.get_string(1)
				if named in ["armas", "un arma", "oros", "talismanes", "tótem", "totem", "aliados", "cartas"]:
					return {}
				return {"kind": "controls_named", "name": named}
			"controls_other_with_keyword":
				var kw := keyword_of(m.get_string(1))
				return {} if kw < 0 else {"kind": entry.kind, "keyword": kw}
			"controls_race", "race":
				var races := _races(m.get_string(1))
				return {} if races.is_empty() else {"kind": entry.kind, "races": races}
	return {}


static func _races(text: String) -> Array:
	"""'bestia, dragón o sombra' → ["bestia", "dragón", "sombra"]; [] si algo no es una sola palabra."""
	var out: Array = []
	for part in text.replace(" y/o ", ",").replace(" o ", ",").replace(" y ", ",").split(","):
		var race := part.strip_edges()
		if race.is_empty() or race in NOT_RACE or not _rx_race_word.search(race):
			return []
		out.append(race)
	return out


static func _number(word: String) -> int:
	return int(word) if word.is_valid_int() else int(NUMBERS.get(word, 0))


static func _add_words(into: Array, sentence: String) -> void:
	for m in _rx_word.search_all(sentence):
		var kw: int = WORDS[m.get_string()]
		if kw not in into:
			into.append(kw)


static func _compile() -> void:
	if _rx_word != null:
		return
	var word := "(?:furia|imbloqueable|indestructible|indesterrable|única|unica|exhumar|errante|retador)"
	_rx_word = RegEx.create_from_string(word)
	_rx_list = RegEx.create_from_string("^" + word + "(?:\\s*,\\s*" + word + "|\\s+[ye]\\s+" + word + ")*$")
	_rx_quoted = RegEx.create_from_string("[\"“”«»][^\"“”«»]*[\"“”«»]")
	_rx_open_quote = RegEx.create_from_string("[\"“”«»][\\s\\S]*$")
	_rx_split = RegEx.create_from_string("[.;\\n]")
	_rx_condition = RegEx.create_from_string(",? si |, si")
	_rx_if = RegEx.create_from_string("^si (.+?),? (el portador |este aliado )?(?:gana|tiene) (.+)$")
	_rx_mid = RegEx.create_from_string("^el portador .*?,? si (.+?),? gana (.+)$")
	_rx_enter = RegEx.create_from_string("^(?:este aliado )?no puede ser bloquead[oa] el turno que entra en juego")
	_rx_race_word = RegEx.create_from_string("^[a-záéíóúñü]+$")
	_rx_if_any = RegEx.create_from_string("^si (.+?), ")
	_rx_removal_skip = RegEx.create_from_string("^(?:cuando|una vez|-|al comienzo|en tu|puedes|elige|hasta)")
	_rx_removal = RegEx.create_from_string("^(?:si está en tu (reserva|destierro|cementerio), )?(?:.*? y )?(los|las) "
		+ "(aliados|cartas)(?: de coste (\\w+) o menos)?( oponentes)?(?: en juego)?"
		+ "(?: reducen su coste en un oro y)? pierden (.+)$")
	var num := "(\\d+|una?|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)"
	for entry in [
		["armed", "^porta (?:un |una )?armas?$"],
		["allies_at_least", "^(?:tienes|controlas) " + num + " o más aliados(?: en (juego|tu cementerio|tu destierro))?$"],
		["exile_types_at_least", "^tienes " + num + " tipos de cartas en tu destierro$"],
		["fewer_hand", "^tienes menos cartas en (?:la|tu) mano que tu oponente$"],
		["hand_at_most", "^tienes " + num + " o menos cartas en tu mano$"],
		["controls_race", "^controlas aliados (.+)$"],
		["race", "^(?:el portador )?es (?:de raza |un |una )?(.+)$"],
		["attacked_last_turn", "^atacaste en tu turno anterior$"],
		["more_golds", "^controlas más oros que tu oponente$"],
		["golds_at_least", "^controlas " + num + " o más oros$"],
		["exiles_at_least", "^hay " + num + " o más cartas en los destierros$"],
		["exile_types_total_at_least", "^hay " + num + " o más tipos de cartas? en los destierros$"],
		["controls_other_with_keyword", "^controlas otro aliado con (\\w+)$"],
		["controls_named", "^controlas ([a-záéíóúñ]+(?: [a-záéíóúñ]+)?)$"],
	]:
		_cond_rxs.append({"kind": entry[0], "rx": RegEx.create_from_string(entry[1])})
