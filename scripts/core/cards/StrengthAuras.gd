extends RefCounted
## StrengthAuras — Fuerza de habilidades estáticas impresas que ContinuousEffectParser no cubre,
## leídas por oración (KeywordParser.sentences()) y evaluadas en vivo en cada cálculo de Fuerza
## (ModifierRegistry._get_modified_stat() las suma como modificadores virtuales, en la misma capa que
## los demás y con los negativos al final):
## - de la carta con condición: "Si tienes tres o más Aliados en tu Cementerio, gana 2 de Fuerza"
##   (hanzaki), "Si porta Armas gana 1 de Fuerza" (honda tadakatsu, date masamune).
## - del portador con condición: "Si el portador es de Raza Bestia, Dragón o Sombra, gana 2 de Fuerza"
##   (kanabo bestial, odachi, nodachi).
## - auras con condición, zona o calificador: "Los Aliados de coste 1 o menos pierden Furia y 1 de
##   Fuerza" (ahu tongariki), "Si está en tu Reserva, ..." (cuernos del inmortal, Legión de Honor),
##   "Si está en tu Cementerio, ..." (Gusano Vampiro, aklo sabaoth), "Si está en tu Oro Pagado, ..."
##   (Libro de Enoc), "Si controlas tres o más Aliados, ..." (zorya), "De lo contrario, ..." (dotaku).
##   Las auras sin nada de eso ("Los Aliados oponentes pierden 1 de Fuerza") siguen en
##   ContinuousEffectParser, que se salta las oraciones condicionales o de zona (_is_static_clause()).
## No soporta "por cada ..." (la cantidad sería variable) ni "de Fuerza N o menos" (pediría la Fuerza
## de la carta mientras se calcula). Corre donde corre la lógica (Anfitrión).
## Se usa con preload (sin class_name global; ver §54).

const KeywordParser = preload("res://scripts/core/cards/KeywordParser.gd")
const KeywordConditions = preload("res://scripts/core/cards/KeywordConditions.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")

const ZONES := {"tu reserva": "reserva", "tu oro pagado": "pagado", "tu cementerio": "cemetery", "tu destierro": "exile"}

static var _cache: Dictionary = {}
static var _busy: bool = false
static var _rx_zone: RegEx = null
static var _rx_if: RegEx = null
static var _rx_self: RegEx = null
static var _rx_aura: RegEx = null
static var _rx_skip: RegEx = null
static var _rx_lead_per: RegEx = null
static var _rx_clause_split: RegEx = null
static var _rx_subject: RegEx = null
static var _rx_per_copy: RegEx = null
static var _rx_per_cost: RegEx = null


static func entries(text: String) -> Array:
	"""[{amount, who: "self" | "wielder" | "allies" | "opponents" | "all", zone, cond, min_cost,
	max_cost, with_keyword, others_only}] de un texto."""
	if _cache.has(text):
		return _cache[text]
	_compile()
	var out: Array = []
	var previous := ""
	for sentence in KeywordParser.sentences(text):
		out.append_array(_parse_sentence(sentence, previous))
		previous = sentence
	_cache[text] = out
	return out


static func handles_sentence(sentence: String) -> bool:
	"""¿StrengthAuras resuelve esta oración? (ContinuousEffectParser no la registra entonces)."""
	_compile()
	return not _parse_sentence(sentence, "").is_empty()


static func is_conditional_sentence(sentence: String) -> bool:
	"""¿La oración tiene condición o zona? (ContinuousEffectParser no la registra como aura fija)."""
	_compile()
	return sentence.begins_with("de lo contrario") or _rx_zone.search(sentence) != null or _rx_if.search(sentence) != null \
		or " por cada " in " " + sentence


static func _parse_sentence(sentence: String, previous: String) -> Array:
	if _rx_skip.search(sentence):
		return []
	var zone := "play"
	var cond := {}
	var who_hint := ""
	var body := sentence
	var zm := _rx_zone.search(body)
	if zm:
		zone = ZONES[zm.get_string(1)]
		body = body.substr(zm.get_end())
	if body.begins_with("de lo contrario, "):
		var pm := _rx_if.search(previous)
		if not pm:
			return []
		cond = KeywordParser.parse_condition(pm.get_string(1))
		if cond.is_empty():
			return []
		cond = cond.duplicate()
		cond["negate"] = true
		body = body.trim_prefix("de lo contrario, ")
	else:
		var im := _rx_if.search(body)
		if im:
			cond = KeywordParser.parse_condition(im.get_string(1))
			if cond.is_empty():
				return []
			if im.get_string(1).begins_with("el portador"):
				who_hint = "wielder"
			body = body.substr(im.get_end())
	# "Por cada Aliado de coste 2 que controles, ..." (siete enanos): contador de toda la oración.
	var lead_per := {}
	var lm := _rx_lead_per.search(body)
	if lm:
		lead_per = _parse_per(lm.get_string(1))
		if lead_per.is_empty():
			return []
		body = body.substr(lm.get_end())
	var sm := _rx_self.search(body)
	if sm and lead_per.is_empty() and not " por cada " in body and (not cond.is_empty() or zone != "play"):
		var who := "wielder" if who_hint == "wielder" or sm.get_string(1) != "" else "self"
		return [{"amount": int(sm.get_string(2)), "who": who, "zone": zone, "cond": cond, "per": {},
			"min_cost": -1, "max_cost": -1, "with_keyword": -1, "others_only": false}]
	# Varias auras en una oración: "Los Aliados oponentes pierden 1 de Fuerza y tus Aliados ganan 1",
	# "... por cada Tótem que controles y ganan 1 de Fuerza por cada Talismán" (sin sujeto: el anterior).
	var out: Array = []
	var subject := ""
	var marked := _rx_clause_split.sub(body, "|", true)
	for raw in marked.split("|", false):
		var clause: String = raw.strip_edges()
		var sub := _rx_subject.search(clause)
		if sub:
			subject = sub.get_string()
		elif subject != "" and (clause.begins_with("ganan ") or clause.begins_with("pierden ")):
			clause = subject + clause
		var entry := _parse_aura(clause, zone, cond, lead_per)
		if not entry.is_empty():
			out.append(entry)
	return out


static func _parse_aura(clause: String, zone: String, cond: Dictionary, lead_per: Dictionary) -> Dictionary:
	var am := _rx_aura.search(clause)
	if not am:
		return {}
	var word := am.get_string(9)
	var amount := int(word) if word.is_valid_int() else (1 if word == "uno" else int(KeywordParser.NUMBERS.get(word, 0)))
	if am.get_string(8) == "pierden":
		amount = -amount
	var per := lead_per
	var tail := clause.substr(am.get_end())
	if tail.begins_with(" por cada "):
		if not lead_per.is_empty():
			return {}
		per = _parse_per(tail.trim_prefix(" por cada "))
		if per.is_empty():
			return {}
	var mine: bool = am.get_string(1) == "tus" or am.get_string(7) != ""
	var who := "opponents" if am.get_string(6) != "" else ("allies" if mine else "all")
	var cost_n := am.get_string(3)
	var entry := {"amount": amount, "who": who, "zone": zone, "cond": cond, "per": per,
		"min_cost": -1, "max_cost": -1, "with_keyword": -1, "others_only": am.get_string(2) != ""}
	if cost_n != "":
		var n := int(cost_n) if cost_n.is_valid_int() else int(KeywordParser.NUMBERS.get(cost_n, 0))
		entry["max_cost" if am.get_string(4) == "menos" else "min_cost"] = n
	if am.get_string(5) != "":
		entry.with_keyword = KeywordParser.keyword_of(am.get_string(5))
		if entry.with_keyword < 0:
			return {}
	# Lo que ContinuousEffectParser ya registra (sin condición, zona, contador, "con <keyword>" ni tope de
	# coste en un "pierden") no se repite aquí.
	# Lo que sí cubre: "Tus Aliados (de coste N o más) (que controlas) ganan N", "Los Aliados oponentes
	# pierden N", "Los Aliados en juego pierden N". "Tus demás", "que controles" o "tus Aliados pierden"
	# los resuelve StrengthAuras y el parser se salta la oración (handles_sentence()).
	var plain: bool = zone == "play" and cond.is_empty() and per.is_empty() and entry.with_keyword < 0 \
		and entry.max_cost < 0 and not entry.others_only and am.get_string(7) != " que controles"
	var parser_covers: bool = plain and ((amount > 0 and who == "allies") or (amount < 0 and who == "opponents") \
		or (amount < 0 and who == "all" and " en juego " in clause + " "))
	return {} if parser_covers else entry


static func _parse_per(text: String) -> Dictionary:
	"""Contador de "por cada <texto>", o {} si no se reconoce."""
	text = text.strip_edges()
	match text:
		"tótem que controles", "totem que controles":
			return {"kind": "totems"}
		"tipo de carta en tu destierro":
			return {"kind": "exile_types"}
		"talismán en tu destierro", "talisman en tu destierro":
			return {"kind": "exile_talismans"}
		"otro aliado de su controlador":
			return {"kind": "other_allies_of_target"}
		"aliado de coste distinto que controles":
			return {"kind": "distinct_costs"}
	var cm := _rx_per_copy.search(text)
	if cm:
		return {"kind": "copies", "zone": "pagado" if cm.get_string(2) == "oro pagado" else "reserva",
			"others": cm.get_string(1) != ""}
	var am := _rx_per_cost.search(text)
	if am:
		var n_word := am.get_string(1)
		return {"kind": "allies_cost", "n": int(n_word) if n_word.is_valid_int() else int(KeywordParser.NUMBERS.get(n_word, 0))}
	return {}


static func _count(per: Dictionary, main: Node, source: Node, source_name: String, source_pid: int, target: Node) -> int:
	match str(per.kind):
		"totems":
			var n := 0
			for container in PlayerSideScript.line_containers(main, source_pid):
				for c in container.get_children():
					if is_instance_valid(c) and c.get("card_type") == Constants.CardType.TOTEM:
						n += 1
			return n
		"exile_types":
			var types := {}
			for d in CardManager.get_exile(source_pid):
				types[d.get("tipo")] = true
			return types.size()
		"exile_talismans":
			return CardManager.get_exile(source_pid).filter(func(d): return d.get("tipo") == Constants.CardType.TALISMAN).size()
		"other_allies_of_target":
			return max(0, _allies(main, CardQuery.controller_of(target)).size() - 1)
		"distinct_costs":
			var costs := {}
			for a in _allies(main, source_pid):
				costs[ContinuousEffectManager.get_modified_cost(a)] = true
			return costs.size()
		"allies_cost":
			return _allies(main, source_pid).filter(func(a): return ContinuousEffectManager.get_modified_cost(a) == int(per.n)).size()
		"copies":
			var zone: Node = PlayerSideScript.oro_pagado(main, source_pid) if per.zone == "pagado" else PlayerSideScript.gold_reserva(main, source_pid)
			var n := 0
			if zone:
				for c in zone.get_children():
					if is_instance_valid(c) and str(c.get("card_name")).to_lower() == source_name and not (per.others and c == source):
						n += 1
			return n
	return 0


static func _allies(main: Node, pid: int) -> Array:
	var out: Array = []
	for container in PlayerSideScript.ally_containers(main, pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO:
				out.append(c)
	return out


static func virtual_modifiers(card: Node, main_cem: Node) -> Array:
	"""Modificadores de Fuerza que estas habilidades le aplican ahora a 'card'."""
	if _busy or not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ALIADO:
		return []
	var main := CardQuery.main_node()
	if main == null:
		return []
	_busy = true
	var out: Array = []
	var card_pid := CardQuery.controller_of(card)
	# De la carta y de sus Armas.
	if not KeywordManager.is_silenced(card):
		for e in entries(str(card.get("card_ability"))):
			if e.who == "self" and KeywordConditions.holds(e.cond, card, card_pid):
				out.append(_modifier(main_cem, e.amount, card, "condicional"))
	var weapons = card.get("equipped_weapons")
	if weapons is Array:
		for w in weapons:
			if not is_instance_valid(w) or KeywordManager.is_silenced(w):
				continue
			for e in entries(str(w.get("card_ability"))):
				if e.who == "wielder" and KeywordConditions.holds(e.cond, card, CardQuery.controller_of(w)):
					out.append(_modifier(main_cem, e.amount, w, "portador"))
	# Auras de las cartas en juego y de las zonas que nombran.
	for pid in [0, 1]:
		var reserva: Node = PlayerSideScript.gold_reserva(main, pid)
		var pagado: Node = PlayerSideScript.oro_pagado(main, pid)
		var zones: Array = PlayerSideScript.line_containers(main, pid)
		zones.append(reserva)
		zones.append(pagado)
		for zone in zones:
			if not zone:
				continue
			var where := "reserva" if zone == reserva else ("pagado" if zone == pagado else "play")
			for source in zone.get_children():
				if not is_instance_valid(source) or source.get("is_converted") == true or KeywordManager.is_silenced(source):
					continue
				for e in entries(str(source.get("card_ability"))):
					if e.who in ["allies", "opponents", "all"] and (e.zone == "play" or e.zone == where) \
							and _aura_applies(e, card, card_pid, source, pid):
						var per_n := 1 if e.per.is_empty() else _count(e.per, main, source, str(source.get("card_name")).to_lower(), pid, card)
						if per_n != 0:
							out.append(_modifier(main_cem, e.amount * per_n, source, "aura"))
		for zone_name in ["cemetery", "exile"]:
			var datas: Array = CardManager.get_cemetery(pid) if zone_name == "cemetery" else CardManager.get_exile(pid)
			for data in datas:
				for e in entries(str(data.get("habilidad", ""))):
					if e.zone == zone_name and e.who in ["allies", "opponents", "all"] and _aura_applies(e, card, card_pid, null, pid):
						var per_d := 1 if e.per.is_empty() else _count(e.per, main, null, str(data.get("nombre", "")).to_lower(), pid, card)
						if per_d != 0:
							out.append(_modifier(main_cem, e.amount * per_d, null, "aura de %s" % str(data.get("nombre", ""))))
	_busy = false
	return out


static func _aura_applies(e: Dictionary, card: Node, card_pid: int, source: Node, source_pid: int) -> bool:
	if e.who == "allies" and card_pid != source_pid:
		return false
	if e.who == "opponents" and card_pid == source_pid:
		return false
	if e.others_only and card == source:
		return false
	if e.max_cost >= 0 and not ContinuousEffectManager.cost_at_most(card, e.max_cost):
		return false
	if e.min_cost >= 0 and ContinuousEffectManager.get_modified_cost(card) < e.min_cost:
		return false
	if e.with_keyword >= 0 and not KeywordManager.has_keyword(card, e.with_keyword):
		return false
	return e.cond.is_empty() or KeywordConditions.holds(e.cond, source, source_pid)


static func _modifier(main_cem: Node, amount: int, source: Node, label: String) -> Dictionary:
	return {
		"id": "virtual", "source": null, "source_id": "virtual", "target": null,
		"type": main_cem.ModifierType.STRENGTH, "stat": "strength", "value": amount, "operation": "add",
		"duration": main_cem.ModifierDuration.PERMANENT, "duration_value": 0, "turns_remaining": 0,
		"condition": Callable(), "layer": main_cem.ModifierLayer.LAYER_7B_CHAR_MODIFY, "priority": 0,
		"filter": {}, "keywords_add": [], "keywords_remove": [], "static_ability": false, "is_active": true,
		"description": "%s %+d (%s)" % [str(source.get("card_name")) if is_instance_valid(source) else "", amount, label],
	}


static func _compile() -> void:
	if _rx_aura != null:
		return
	_rx_zone = RegEx.create_from_string("^s[ií] está en (tu reserva|tu oro pagado|tu cementerio|tu destierro),? ")
	_rx_if = RegEx.create_from_string("^si (.+?),? (?=(?:el portador |este aliado )?gana |tus (?:demás )?aliados|los aliados|las cartas)")
	_rx_self = RegEx.create_from_string("^(el portador )?(?:este aliado )?gana (\\d+) de fuerza")
	_rx_aura = RegEx.create_from_string("^(tus|los) (demás )?aliados(?: de coste (\\w+) o (menos|más))?(?: con (\\w+))?"
		+ "( oponentes)?(?: en juego)?( que control(?:as|es))? (ganan|pierden) [^.]*?(\\d+|uno|una|dos|tres) de fuerza")
	_rx_lead_per = RegEx.create_from_string("^por cada (.+?), ")
	_rx_clause_split = RegEx.create_from_string(" y (?=(?:tus|los) (?:demás )?aliados|ganan |pierden )")
	_rx_subject = RegEx.create_from_string("^(?:tus|los) (?:demás )?aliados[^.]*? (?=ganan |pierden )")
	_rx_per_copy = RegEx.create_from_string("^(otra )?copia de este oro en tu (reserva|oro pagado)$")
	_rx_per_cost = RegEx.create_from_string("^aliado de coste (\\w+) que controles$")
	_rx_skip = RegEx.create_from_string("^(?:cuando|una vez|-|al comienzo|al final|en tu|en la|puedes|elige|hasta)")
