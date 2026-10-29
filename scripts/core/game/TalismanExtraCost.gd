extends RefCounted
## TalismanExtraCost — coste adicional de un Talismán: "Para jugar este Talismán, Baraja una carta de tu mano"
## (golpe fulminante), "...Destruye una carta que controles" (duelo a siete pasos), "...Baraja un Oro de tu Reserva"
## (cae megido). Se paga al jugarlo (GoldManager.play_card(), antes del Oro): si no se puede pagar, no se juega.
## El coste lo entiende EffectCompiler.COST_PIECES y lo paga EffectInterpreter._pay_cost(), como en una activada.
## El compilador saltea esa oración al resolver (RULE_SKIP_RX). Se usa con preload.

const RX := "para jugar este talisman, (?<cost>[^.]+)"
## Imperativo del texto → infinitivo de COST_PIECES.
const INFINITIVE := {"baraja": "barajar", "destruye": "destruir", "destierra": "desterrar", "descarta": "descartar",
	"bota": "botar", "paga": "pagar"}


static func cost_steps(card: Node) -> Array:
	"""Pasos de coste del Talismán ([] si no tiene coste adicional). Un coste que no se entiende vuelve como
	{kind: "unknown"}: el Talismán no se puede jugar por aquí."""
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.TALISMAN:
		return []
	var norm: String = EffectCompiler.normalize(str(card.get("card_ability")))
	var m := RegEx.create_from_string(RX).search(norm)
	if m == null:
		return []
	var phrase: String = m.get_string("cost").strip_edges()
	var first: String = phrase.get_slice(" ", 0)
	if INFINITIVE.has(first):
		phrase = INFINITIVE[first] + phrase.substr(first.length())
	var costs: Dictionary = EffectCompiler._parse_costs(phrase + " para x")
	if costs.is_empty():
		return [{"op": "cost", "kind": "unknown", "text": m.get_string("cost")}]
	return costs.steps


static func unpayable(main: Node, card: Node, steps: Array, pid: int) -> String:
	var interp = TriggerSystem._effect_interpreter
	for c in steps:
		if c.get("kind", "") == "unknown":
			return "no se entiende el coste adicional (\"%s\")" % str(c.get("text", ""))
		if c.op == "pay":
			continue  # se suma al Oro del Talismán (pay())
		var why: String = interp._cost_unpayable(main, c, card, pid)
		if not why.is_empty():
			return why
	return ""


static func gold_extra(steps: Array) -> int:
	var n := 0
	for c in steps:
		if c.op == "pay":
			n += int(c.amount)
	return n


static func pay(main: Node, card: Node, steps: Array, pid: int) -> bool:
	"""Paga lo que no es Oro (el Oro lo suma quien llama). Anota en la carta el coste de lo Destruido/Desterrado
	(meta "extra_cost_paid_cost": duelo a siete pasos, "del mismo o menor coste que la carta destruida")."""
	var interp = TriggerSystem._effect_interpreter
	interp._each = {}
	for c in steps:
		if c.op == "pay":
			continue
		if not await interp._pay_cost(main, c, card, pid):
			return false
	if interp._each.has("paid_cost"):
		card.set_meta("extra_cost_paid_cost", int(interp._each.paid_cost))
	return true
