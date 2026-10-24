extends RefCounted
## Prevenciones reactivas con coste (2026-10-21): "Puedes <coste> para prevenir que <algo> sea Anulado
## (o su habilidad cancelada) / sea afectado por un efecto oponente" — Ángel Gadreel, Serafín, wendy,
## ciudad subterranea, orden del águila negra, lucifer... El coste lo entiende
## EffectCompiler.COST_PIECES y lo paga EffectInterpreter._pay_cost(), igual que en una activada.
## Son dos entradas genéricas al final de EffectController._prevention_registry (una para Anular /
## Cancelar y otra para "afectada por un efecto oponente"); las entradas escritas a mano tienen
## prioridad: si alguna ya detecta el texto, estas no.
## La entrada solo recibe el objetivo en 'applies' y la carta en 'is_available': el objetivo de este
## ofrecimiento lo guarda EffectController en _last_applies_arg.

const RX := "puedes (?<cost>[^.]+?) para prevenir que (?<what>uno o mas oros|un aliado o totem|un aliado con (?<kw>[a-z, ]+?)" \
	+ "|(?:un|una|otra) (?:aliado|totem|carta|oro)) (?:sea|sean) (?<v>anulad[oa]s?(?: o su habilidad cancelada)?" \
	+ "|afectad[oa]s? por (?:un )?efectos? oponentes?)"
const KEYWORDS := {"furia": Constants.Keyword.FURIA, "imbloqueable": Constants.Keyword.IMBLOQUEABLE,
	"indestructible": Constants.Keyword.INDESTRUCTIBLE}

static var _rx: RegEx = null


static func spec(text: String, registry: Array) -> Dictionary:
	"""{kind: "annul"|"affect", types, keywords, other, costs, once} o {} si el texto no es una de estas
	prevenciones (o ya la cubre otra entrada del registro)."""
	if _rx == null:
		_rx = RegEx.create_from_string(RX)
	var norm: String = EffectCompiler.normalize(text.replace("\n", " "))
	var m := _rx.search(norm)
	if m == null:
		return {}
	for entry in registry:
		if str(entry.get("name", "")).begins_with("Prevención compilada"):
			continue
		var detect = entry.get("detect")
		if detect is Callable and detect.is_valid() and detect.call(text):
			return {}
	var costs: Dictionary = EffectCompiler._parse_costs(m.get_string("cost") + " para x")
	if costs.is_empty():
		return {}
	var what: String = m.get_string("what")
	var types: Array = []
	for t in ["aliado", "totem", "oro"]:
		if t in what:
			types.append(t)
	var kws: Array = []
	for k in KEYWORDS:
		if k in m.get_string("kw"):
			kws.append(KEYWORDS[k])
	# "Una vez por turno, puedes ..." justo antes de este "puedes".
	var before: String = norm.substr(maxi(0, m.get_start() - 40), mini(40, m.get_start()))
	return {"kind": "annul" if m.get_string("v").begins_with("anulad") else "affect", "types": types, "keywords": kws,
		"other": what.begins_with("otra"), "costs": costs.steps, "once": "una vez por turno" in before}


static func applies(sp: Dictionary, target, source_card: Node) -> bool:
	if target == null:
		return true
	if sp.get("other", false) and target is Node and target == source_card:
		return false
	var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
	var types: Array = sp.get("types", [])
	if not types.is_empty() and tipo != null:
		var word: String = {Constants.CardType.ALIADO: "aliado", Constants.CardType.TOTEM: "totem",
			Constants.CardType.ORO: "oro"}.get(int(tipo), "")
		if not (word in types):
			return false
	if not sp.get("keywords", []).is_empty():
		if not (target is Node):
			return false
		var has_any := false
		for k in sp.keywords:
			if ContinuousEffectManager.has_keyword(target, k):
				has_any = true
		if not has_any:
			return false
	return true


static func is_available(sp: Dictionary, card: Node) -> bool:
	var main := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")
	if not main or sp.is_empty():
		return false
	# Desde la mano solo si el coste es Descartarla (la entrada mira mano y juego).
	if card.get("current_zone") == Constants.Zone.MANO and not sp.costs.any(func(c): return c.get("kind", "") == "self_discard"):
		return false
	if sp.get("once", false) and UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 90, GameManager.turn_serial):
		return false
	var interp = TriggerSystem._effect_interpreter
	var controller_id: int = card.controller_id if card.get("controller_id") != null else 0
	for c in sp.costs:
		if c.op == "pay":
			if not main._gold_manager.puede_pagar(int(c.amount), -1, "", -1, controller_id):
				return false
		elif not interp._cost_unpayable(main, c, card, controller_id).is_empty():
			return false
	return true


static func pay(sp: Dictionary, card: Node) -> bool:
	var main := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")
	if not main:
		return false
	var interp = TriggerSystem._effect_interpreter
	var controller_id: int = card.controller_id if card.get("controller_id") != null else 0
	if sp.get("once", false):
		UniversalCardParser.turn_registry.register(str(card.get_instance_id()), 90, GameManager.turn_serial)
	for c in sp.costs:
		if c.op == "pay":
			if not await load("res://scripts/core/game/PlayerSide.gd").pay(main, controller_id, int(c.amount), null):
				return false
		elif not await interp._pay_cost(main, c, card, controller_id):
			return false
	return true
