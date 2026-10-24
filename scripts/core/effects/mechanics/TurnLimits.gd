extends RefCounted
## TurnLimits — Límites por turno: Terminal P-12 (buscar, habilidades fuera del juego, mirar mano/Castillo)
## y Pan de Muerto (quince cartas Botadas/Desterradas por Castillo).
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")


# -----------------------------------------------------------------------------
# Terminal P-12: "Si está en tu Reserva, las cartas que controles no pueden
# perder su habilidad por habilidades y efectos oponentes y él no puede mirar
# tu mano ni tu Castillo. En cada turno, los jugadores sólo pueden buscar hasta
# dos cartas por efectos y utilizar hasta dos habilidades de cartas fuera del
# juego."
# -----------------------------------------------------------------------------
static func terminal_in_reserva(pid: int) -> bool:
	var main := CardQuery.main_node()
	if not main:
		return false
	var reserva = PlayerSideScript.gold_reserva(main, pid)
	if not reserva:
		return false
	for c in reserva.get_children():
		if is_instance_valid(c) and not KeywordManager.is_silenced(c) and "él no puede mirar tu mano ni tu castillo" in CardQuery.ability_of(c):
			return true
	return false


static func _terminal_in_play() -> bool:
	for pid in [0, 1]:
		if not CardQuery.cards_in_play_with(pid, "los jugadores sólo pueden buscar hasta dos cartas por efectos").is_empty():
			return true
	return false


## Cuántas cartas más puede buscar 'pid' este turno (-1 = sin límite).
static func search_room(pid: int) -> int:
	if not _terminal_in_play():
		return -1
	return maxi(0, 2 - RuleState.count("searched", pid))


static func note_searched(pid: int, amount: int) -> void:
	if amount > 0 and _terminal_in_play():
		RuleState.add("searched", pid, amount)


## ¿Puede 'pid' usar otra habilidad de una carta fuera del juego este turno?
static func outside_ability_allowed(pid: int) -> bool:
	return not _terminal_in_play() or RuleState.count("outside_ability", pid) < 2


static func note_outside_ability(pid: int) -> void:
	if _terminal_in_play():
		RuleState.add("outside_ability", pid)

const PAN_LIMIT_TEXT := "sólo se puede botar y/o desterrar hasta quince cartas de cada castillo por turno"


## ¿Cuántas cartas más se pueden Botar/Desterrar del Castillo de 'deck_owner'
## este turno? -1 = sin límite (no hay Pan de Muerto en juego).
static func castle_removal_room(deck_owner: int) -> int:
	var any := false
	for pid in [0, 1]:
		if not CardQuery.cards_in_play_with(pid, PAN_LIMIT_TEXT).is_empty():
			any = true
	if not any:
		return -1
	return maxi(0, 15 - RuleState.count("castle_removed", deck_owner))


static func note_castle_removed(deck_owner: int, amount: int) -> void:
	if amount > 0:
		RuleState.add("castle_removed", deck_owner, amount)