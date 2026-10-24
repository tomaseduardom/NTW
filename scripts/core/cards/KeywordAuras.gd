extends RefCounted
## KeywordAuras — auras que QUITAN palabras clave ("Los Aliados de coste 1 o menos pierden Furia"
## kuzuryu; "Los Aliados oponentes pierden Indestructible e Indesterrable" Ianthe; Diadema Celestial,
## Azrael, monumento heroico...). Se evalúan en vivo en cada consulta (KeywordManager.has_keyword()):
## cada fuente activa con una cláusula de KeywordParser.removals() que alcance a la carta se la quita.
## Fuentes: las cartas en juego (líneas, Reserva y Oro Pagado) que no perdieron su habilidad; con "Si
## está en tu Reserva" solo desde la Reserva; con "Si está en tu Destierro" (red shadow), las cartas
## del Destierro. Corre donde corre la lógica (Anfitrión).
## También las que DAN palabras clave ("Tus Aliados ganan Furia", "Si está en tu Oro Pagado, tus
## Aliados ganan 1 de Fuerza e Indestructible", "Tus Aliados que porten Armas ganan Furia"): grants().
## Se usa con preload (sin class_name global; ver §54).

const KeywordParser = preload("res://scripts/core/cards/KeywordParser.gd")
const KeywordConditions = preload("res://scripts/core/cards/KeywordConditions.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")


static func removes(card: Node, keyword: int) -> bool:
	var main := CardQuery.main_node()
	if main == null:
		return false
	for pid in [0, 1]:
		var reserva: Node = PlayerSideScript.gold_reserva(main, pid)
		var zones: Array = PlayerSideScript.line_containers(main, pid)
		zones.append(reserva)
		zones.append(PlayerSideScript.oro_pagado(main, pid))
		for zone in zones:
			if not zone:
				continue
			for source in zone.get_children():
				if not is_instance_valid(source) or source.get("is_converted") == true or KeywordManager.is_silenced(source):
					continue
				var in_reserva: bool = zone == reserva
				for r in KeywordParser.removals(str(source.get("card_ability"))):
					if (r.zone == "play" or (r.zone == "reserva" and in_reserva)) \
							and _applies(r, keyword, card, CardQuery.controller_of(source)):
						return true
		for data in CardManager.get_exile(pid):
			for r in KeywordParser.removals(str(data.get("habilidad", ""))):
				if r.zone == "exile" and _applies(r, keyword, card, pid):
					return true
	return false


static func _applies(r: Dictionary, keyword: int, card: Node, source_pid: int) -> bool:
	if keyword not in r.keywords:
		return false
	if r.cards == "aliados" and card.get("card_type") != Constants.CardType.ALIADO:
		return false
	if r.opponents and CardQuery.controller_of(card) == source_pid:
		return false
	if r.max_cost >= 0 and not ContinuousEffectManager.cost_at_most(card, r.max_cost):
		return false
	return r.cond.is_empty() or KeywordConditions.holds(r.cond, null, source_pid)


# =============================================================================
# AURAS QUE DAN PALABRAS CLAVE
# =============================================================================
const ZONES := {"tu reserva": "reserva", "tu oro pagado": "pagado", "tu cementerio": "cemetery", "tu destierro": "exile"}
const PLURALS := {"furias": "furia", "imbloqueables": "imbloqueable", "indestructibles": "indestructible",
	"indesterrables": "indesterrable"}
const NOT_RACE := ["de", "con", "que", "oponentes", "en", "demas", "demás"]

static var _grant_cache: Dictionary = {}
static var _grant_busy: Dictionary = {}
static var _rx_zone: RegEx = null
static var _rx_if: RegEx = null
static var _rx_grant: RegEx = null
static var _rx_skip: RegEx = null
static var _rx_kw: RegEx = null


static func grant_entries(text: String) -> Array:
	"""[{keywords, who: "allies" | "opponents" | "all", others_only, races, max_cost, min_cost,
	with_keyword, armed_target, zone, cond}] — auras estáticas que dan palabras clave."""
	if _grant_cache.has(text):
		return _grant_cache[text]
	_compile_grants()
	var out: Array = []
	for sentence in KeywordParser.sentences(text):
		var e := _parse_grant(sentence)
		if not e.is_empty():
			out.append(e)
	_grant_cache[text] = out
	return out


static func _parse_grant(sentence: String) -> Dictionary:
	if _rx_skip.search(sentence):
		return {}
	for timed in ["por el turno", "este turno", "permanentemente", "hasta ", "mientras", "cuando"]:
		if timed in sentence:
			return {}
	var zone := "play"
	var cond := {}
	var body := sentence
	var zm := _rx_zone.search(body)
	if zm:
		zone = ZONES[zm.get_string(1)]
		body = body.substr(zm.get_end())
	var im := _rx_if.search(body)
	if im:
		cond = KeywordParser.parse_condition(im.get_string(1))
		if cond.is_empty():
			return {}
		body = body.substr(im.get_end())
	var m := _rx_grant.search(body)
	if not m:
		return {}
	var keywords: Array = []
	for km in _rx_kw.search_all(m.get_string(10)):
		var w: String = PLURALS.get(km.get_string(), km.get_string())
		var kw := KeywordParser.keyword_of(w)
		if kw >= 0 and kw not in keywords:
			keywords.append(kw)
	if keywords.is_empty():
		return {}
	var races: Array = []
	var with_word := m.get_string(6)
	if m.get_string(3) != "":
		# "Tus Aliados Imbloqueable ganan Indestructible" (okyo): la palabra es una palabra clave, no una Raza.
		var as_kw := KeywordParser.keyword_of(PLURALS.get(m.get_string(3), m.get_string(3)))
		if as_kw >= 0 and with_word == "":
			with_word = m.get_string(3)
		else:
			for r in m.get_string(3).split(" o "):
				if r in NOT_RACE:
					return {}
				races.append(r)
	var e := {"keywords": keywords, "others_only": m.get_string(2) != "", "races": races,
		"max_cost": -1, "min_cost": -1, "with_keyword": -1, "armed_target": m.get_string(9) != "",
		"zone": zone, "cond": cond,
		"who": "opponents" if m.get_string(7) != "" else ("allies" if m.get_string(1) == "tus" or m.get_string(8) != "" else "all")}
	if m.get_string(4) != "":
		var n := int(m.get_string(4)) if m.get_string(4).is_valid_int() else int(KeywordParser.NUMBERS.get(m.get_string(4), 0))
		e["max_cost" if m.get_string(5) == "menos" else "min_cost"] = n
	if with_word != "":
		e.with_keyword = KeywordParser.keyword_of(PLURALS.get(with_word, with_word))
		if e.with_keyword < 0:
			return {}
	return e


static func grants(card: Node, keyword: int) -> bool:
	"""¿Un aura activa le da esta palabra clave a 'card'?"""
	if _grant_busy.get(keyword, false) or card.get("card_type") != Constants.CardType.ALIADO:
		return false
	var main := CardQuery.main_node()
	if main == null:
		return false
	_grant_busy[keyword] = true
	var result := false
	var card_pid := CardQuery.controller_of(card)
	for pid in [0, 1]:
		if result:
			break
		var reserva: Node = PlayerSideScript.gold_reserva(main, pid)
		var pagado: Node = PlayerSideScript.oro_pagado(main, pid)
		var zones: Array = PlayerSideScript.line_containers(main, pid)
		zones.append(reserva)
		zones.append(pagado)
		for zone in zones:
			if result or not zone:
				continue
			var where := "reserva" if zone == reserva else ("pagado" if zone == pagado else "play")
			for source in zone.get_children():
				if not is_instance_valid(source) or source.get("is_converted") == true or KeywordManager.is_silenced(source):
					continue
				for e in grant_entries(str(source.get("card_ability"))):
					if (e.zone == "play" or e.zone == where) and _grant_applies(e, keyword, card, card_pid, source, pid):
						result = true
						break
				if result:
					break
		if not result:
			for zone_name in ["cemetery", "exile"]:
				var datas: Array = CardManager.get_cemetery(pid) if zone_name == "cemetery" else CardManager.get_exile(pid)
				for d in datas:
					for e in grant_entries(str(d.get("habilidad", ""))):
						if e.zone == zone_name and _grant_applies(e, keyword, card, card_pid, null, pid):
							result = true
	_grant_busy[keyword] = false
	return result


static func _grant_applies(e: Dictionary, keyword: int, card: Node, card_pid: int, source: Node, source_pid: int) -> bool:
	if keyword not in e.keywords:
		return false
	if e.who == "allies" and card_pid != source_pid:
		return false
	if e.who == "opponents" and card_pid == source_pid:
		return false
	if e.others_only and card == source:
		return false
	if not e.races.is_empty() and not KeywordConditions.race_matches(str(card.get("card_raza")), e.races):
		return false
	if e.max_cost >= 0 and not ContinuousEffectManager.cost_at_most(card, e.max_cost):
		return false
	if e.min_cost >= 0 and ContinuousEffectManager.get_modified_cost(card) < e.min_cost:
		return false
	if e.with_keyword >= 0 and not KeywordManager.has_keyword(card, e.with_keyword):
		return false
	if e.armed_target and not KeywordConditions.holds({"kind": "armed"}, card, card_pid):
		return false
	return e.cond.is_empty() or KeywordConditions.holds(e.cond, source, source_pid)


static func _compile_grants() -> void:
	if _rx_grant != null:
		return
	var word := "[a-záéíóúñ]+"
	_rx_zone = RegEx.create_from_string("^s[ií] está en (tu reserva|tu oro pagado|tu cementerio|tu destierro),? ")
	_rx_if = RegEx.create_from_string("^si (.+?),? (?=tus (?:demás )?aliados|los aliados)")
	_rx_skip = RegEx.create_from_string("^(?:cuando|una vez|-|al comienzo|al final|en tu|en la|puedes|elige|hasta|de lo contrario)")
	_rx_kw = RegEx.create_from_string("(?:furias?|imbloqueables?|indestructibles?|indesterrables?)")
	_rx_grant = RegEx.create_from_string("^(tus|los) (demás )?aliados(?: y t[óo]tem)?(?: (" + word + "(?: o " + word + ")?))??"
		+ "(?: de coste (\\w+) o (menos|más))?(?: con (\\w+))?( oponentes)?(?: en juego)?( que control(?:as|es))?"
		+ "( que porten armas?,?)? (?:ganan|tienen|son) ([^.]+)$")
