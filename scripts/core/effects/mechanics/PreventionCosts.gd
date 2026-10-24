extends RefCounted
## PreventionCosts — Prevención desde la mano o desterrando el Arma, y sus costos (Armadura Dorada,
## Dos de Cada Uno, ngenechen). Registro: EffectController._build_prevention_registry().
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")


# -----------------------------------------------------------------------------
# Prevención desde la mano o desterrando el Arma (registro de
# EffectController._build_prevention_registry):
#   Armadura Dorada: "Puedes Desterrar esta Arma o pagar un Oro y Desterrarla
#   de tu mano para prevenir que tus Aliados sean afectados o un Aliado
#   Anulado."
#   Dos de Cada Uno: "Puedes pagar un Oro y Desterrarlo de tu mano para
#   prevenir que hasta dos cartas de coste 1 o menos de un mismo tipo sean
#   afectadas por un efecto oponente."
# -----------------------------------------------------------------------------
const ARMADURA_TEXT := "puedes desterrar esta arma o pagar un oro y desterrarla de tu mano para prevenir que tus aliados sean afectados o un aliado anulado"


const DOS_DE_CADA_UNO_TEXT := "pagar un oro y desterrarlo de tu mano para prevenir que hasta dos cartas de coste 1 o menos de un mismo tipo sean afectadas por un efecto oponente"


static func in_hand(card: Node) -> bool:
	return is_instance_valid(card) and card.get("current_zone") == Constants.Zone.MANO


static func can_pay_one(card: Node) -> bool:
	var main := CardQuery.main_node()
	if not main or not main.get("_gold_manager"):
		return false
	var pid: int = card.owner_id if card.get("owner_id") != null else 0
	return main._gold_manager.puede_pagar(1, -1, "", -1, pid)


## Costo "pagar un Oro y Desterrarla de tu mano" o "Desterrar esta Arma".
static func pay_prevention_cost(card: Node) -> bool:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(card):
		return false
	var pid: int = card.owner_id if card.get("owner_id") != null else 0
	if in_hand(card):
		if not await PlayerSideScript.pay(main, pid, 1, null):
			return false
		CardManager.append_to_exile(pid, PlayerSideScript.take_from_hand(main, pid, card))
		return true
	var wielder = card.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(card)
	await EffectController.exile_card(pid, card, true)
	return true


## Costo "Barajar una carta de tu mano" (ngenechen). false si no eligió.
static func shuffle_one_from_hand_cost(card: Node) -> bool:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(card):
		return false
	var pid: int = CardQuery.controller_of(card)
	var title: String = str(card.get("card_name"))
	var picked: Node = await PlayerSideScript.pick_from_hand(main, pid, "%s: Baraja una carta de tu mano (costo)" % title,
		Callable(), true, true)
	if not picked or not is_instance_valid(picked):
		return false
	PlayerSideScript.shuffle_from_hand(main, pid, picked, title)
	return true


## Dos de Cada Uno: la segunda carta del mismo tipo y coste 1 o menos que el
## mismo efecto afecte también queda protegida.
static func same_type_low_cost_filter(first: Node) -> Callable:
	var tipo = first.get("card_type") if is_instance_valid(first) else -1
	return func(c: Node) -> bool:
		return is_instance_valid(c) and c.get("card_type") == tipo and ContinuousEffectManager.cost_at_most(c, 1)
