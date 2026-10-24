extends RefCounted
## Peaje de Oro a habilidades disparadas (Mecha-Daikaiju: "...y hasta tu próximo turno tu oponente
## no puede utilizar habilidades disparadas a menos que pague un Oro."). El estado vive en RuleState
## ("trigger_gold_toll"). Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const TEXT := "hasta tu próximo turno tu oponente no puede utilizar habilidades disparadas a menos que pague un oro"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func register_if_text(full_text: String, controller_id: int) -> void:
	"""Llamar cuando se resuelve el efecto que trae el texto."""
	if not (TEXT in full_text.to_lower().replace("\n", " ")):
		return
	var main := _main_node()
	if not main:
		return
	# Hasta el próximo turno del controlador (RuleState: turnos de jugador).
	RuleState.set_until("trigger_gold_toll", 1 - controller_id, RuleState.next_own_turn(controller_id))
	main._update_debug("Hasta tu próximo turno, tu oponente debe pagar un Oro para usar habilidades disparadas")


static func blocks_trigger(card: Node, controller_id: int) -> bool:
	"""true si la habilidad disparada de 'card' no se usa (no pagó el Oro)."""
	if not is_instance_valid(card):
		return false
	var toll: int = ability_toll(card, controller_id) + (1 if RuleState.active("trigger_gold_toll", controller_id) else 0)
	return not await pay_toll(card, controller_id, toll)


## Recargos de "utilizar habilidades" (disparadas y activadas) que dependen de la carta, todos "hasta tu
## próximo turno" en RuleState:
## - jose miguel carrera: "a tu oponente le cuesta un Oro adicional utilizar habilidades de Aliados de
## ese coste" ("ally_cost_toll:<coste>");
## - capitan daisuke: "...utilizar habilidades de Oro" ("gold_ability_toll").
static func ability_toll(card: Node, controller_id: int) -> int:
	if not is_instance_valid(card):
		return 0
	var n := 0
	var card_type = card.get("card_type")
	# Un recargo que puso el rival no lo paga un jugador que no puede ser afectado (EffectController.rule_cost_waived).
	var toll := func(key: String) -> bool:
		return RuleState.active(key, controller_id) and not EffectController.rule_cost_waived(key, controller_id)
	if card_type == Constants.CardType.ALIADO and card.get("card_cost") != null \
			and toll.call("ally_cost_toll:%d" % int(card.card_cost)):
		n += 1
	if card_type == Constants.CardType.ORO and toll.call("gold_ability_toll"):
		n += 1
	# randolph carter: "...o utilizar habilidades por el turno"; Serafín: "utilizar habilidades de la carta
	# nombrada cuesta un Oro adicional".
	if toll.call("any_ability_toll"):
		n += 1
	if toll.call("name_ability_toll:" + str(card.get("card_name")).to_lower()):
		n += 1
	# koto: "elige una carta. Tu oponente no puede utilizar su habilidad este turno a menos que pague un Oro".
	if int(card.get_meta("ability_toll_turn", -1)) == GameManager.turn_serial \
			and not EffectController.opp_cost_waived(controller_id, 1 - controller_id):
		n += 1
	return n


## Gusano de Haftvad: "la próxima habilidad que utilice tu oponente este turno sea cancelada".
static func cancel_next_pending(controller_id: int) -> bool:
	return not RuleState.turn_data("cancel_next_ability:%d" % controller_id).is_empty()


## true = la habilidad se cancela (y se consume el efecto).
static func consume_cancel_next(card: Node, controller_id: int) -> bool:
	if not cancel_next_pending(controller_id):
		return false
	RuleState.set_turn_data("cancel_next_ability:%d" % controller_id, {})
	var main := _main_node()
	if main:
		main._update_debug("La habilidad de %s es Cancelada (Gusano de Haftvad)" % (str(card.get("card_name")) if is_instance_valid(card) else "esa carta"))
	return true


## Cobra el recargo antes de usar la habilidad. true = se puede usar (no había recargo o se pagó).
static func pay_toll(card: Node, controller_id: int, toll: int) -> bool:
	if toll <= 0:
		return true
	var main := _main_node()
	if not main or not main._gold_manager:
		return true
	var gm = main._gold_manager
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) and card.get("card_name") != null else "esa carta"
	if not gm.puede_pagar(toll, -1, "", -1, controller_id):
		main._update_debug("%s: no puedes pagar %d Oro(s) — la habilidad no se usa" % [card_name, toll])
		return false
	var pay: bool = PlayerSideScript.is_bot(controller_id)
	if not pay:
		pay = await SelectionManager.await_two_choice(main, card_name,
			"Pagar %d Oro%s para usar la habilidad" % [toll, "" if toll == 1 else "s"], "No usarla", controller_id)
	if not pay or not await gm.pagar_coste(toll, -1, "", -1, controller_id):
		main._update_debug("La habilidad de %s no se usa" % card_name)
		return false
	return true
