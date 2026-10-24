extends RefCounted
## CardQuery — Consultas comunes de las mecánicas: cartas en juego con un texto, controlador, Armas en juego,
## la oración "al comienzo del turno" que vale en este turno.
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")


static func main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func ability_of(c) -> String:
	return str(c.get("card_ability")).to_lower().replace("\n", " ")


## Cartas en juego (líneas y Oros) que controla 'pid', con habilidad (no
## silenciadas) y cuyo texto contiene 'phrase'.
static func cards_in_play_with(pid: int, phrase: String) -> Array:
	var main := main_node()
	if not main:
		return []
	var containers: Array = PlayerSideScript.line_containers(main, pid)
	containers.append(PlayerSideScript.gold_reserva(main, pid))
	containers.append(PlayerSideScript.oro_pagado(main, pid))
	var out: Array = []
	for container in containers:
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and not KeywordManager.is_silenced(c) and phrase in ability_of(c):
				out.append(c)
	return out


## La oración "al comienzo del turno" que vale en ESTE turno (ngenechen/Carcosa): "al comienzo de tu
## turno" solo en el tuyo, "al comienzo del turno oponente" solo en el del rival y "al comienzo del
## turno" a secas en los dos. "" si ninguna aplica.
static func turn_start_clause(text: String, is_own_turn: bool) -> String:
	for raw in text.replace("\n", ". ").split("."):
		var s: String = raw.strip_edges()
		var lower := s.to_lower()
		var opp: bool = "al comienzo del turno oponente" in lower or "al comienzo del turno de tu oponente" in lower
		var own: bool = "al comienzo de tu turno" in lower
		var any: bool = ("al comienzo del turno" in lower and not opp) or "al inicio del turno" in lower
		if (is_own_turn and (own or any)) or (not is_own_turn and (opp or any)):
			return s
	return ""


static func controller_of(c) -> int:
	if c == null or not is_instance_valid(c):
		return -1
	if c.get("controller_id") != null:
		return int(c.controller_id)
	return int(c.owner_id) if c.get("owner_id") != null else -1


# -----------------------------------------------------------------------------
# la esmeralda: "Al comienzo de cada turno, tu oponente Baraja una carta de su
# mano. Si controlas otra Arma, Roba dos cartas." (los dos turnos)
# -----------------------------------------------------------------------------
static func weapons_in_play(pid: int) -> Array:
	var main := main_node()
	var out: Array = []
	if not main:
		return out
	for container in PlayerSideScript.line_containers(main, pid):
		for c in container.get_children():
			if not is_instance_valid(c):
				continue
			if c.get("card_type") == Constants.CardType.ARMA and not (c in out):
				out.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and not (w in out):
						out.append(w)
	return out
