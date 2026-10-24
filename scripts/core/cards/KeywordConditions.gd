extends RefCounted
## KeywordConditions — evalúa las condiciones de las palabras clave condicionales que arma
## KeywordParser ("Si tienes tres o más Aliados en juego, gana Furia", "Si el portador es de Raza
## Bestia..."), contra el estado actual de la partida. Corre donde corre la lógica (Anfitrión).
## Se usa con preload (sin class_name global; ver §54).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")


static func holds(cond: Dictionary, subject: Node, pid: int) -> bool:
	"""'subject': la carta cuya Raza/Armas/entrada se mira (el portador si la palabra clave es del
	portador; null para una carta en el Cementerio). 'pid': el jugador del "tienes"/"controlas".
	cond.negate: vale cuando NO se cumple ("De lo contrario, ...")."""
	return _holds(cond, subject, pid) != bool(cond.get("negate", false))


static func _holds(cond: Dictionary, subject: Node, pid: int) -> bool:
	var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")
	match str(cond.get("kind", "")):
		"armed":
			if subject == null or not (subject.get("equipped_weapons") is Array):
				return false
			for w in subject.equipped_weapons:
				if is_instance_valid(w):
					return true
			return false
		"race":
			return subject != null and _race_matches(str(subject.get("card_raza")), cond.races)
		"entered_this_turn":
			return subject != null and int(subject.get_meta("entered_play_turn", -1)) == GameManager.turn_serial
		"attacked_last_turn":
			return BattleManager.attacked_in_previous_own_turn(pid)
		"allies_at_least":
			return _allies(main, pid, str(cond.zone)) >= int(cond.n)
		"exile_types_at_least":
			var types := {}
			for d in CardManager.get_exile(pid):
				types[d.get("tipo")] = true
			return types.size() >= int(cond.n)
		"fewer_hand":
			return main != null and PlayerSideScript.hand_cards(main, pid).size() < PlayerSideScript.hand_cards(main, 1 - pid).size()
		"hand_at_most":
			return main != null and PlayerSideScript.hand_cards(main, pid).size() <= int(cond.n)
		"more_golds":
			return main != null and _golds(main, pid) > _golds(main, 1 - pid)
		"golds_at_least":
			return main != null and _golds(main, pid) >= int(cond.n)
		"exiles_at_least":
			return CardManager.get_exile(0).size() + CardManager.get_exile(1).size() >= int(cond.n)
		"exile_types_total_at_least":
			var all_types := {}
			for p in [0, 1]:
				for d in CardManager.get_exile(p):
					all_types[d.get("tipo")] = true
			return all_types.size() >= int(cond.n)
		"controls_other_with_keyword":
			# "Si controlas otro Aliado con Exhumar" (el mandinga): 'subject' es la fuente.
			for ally in _allies_in_play(main, pid):
				if ally != subject and KeywordManager.has_keyword(ally, int(cond.keyword)):
					return true
			return false
		"controls_named":
			# "Si controlas Pebre" (empanada): una carta en juego con ese nombre.
			if main == null:
				return false
			var zones: Array = PlayerSideScript.line_containers(main, pid)
			zones.append(PlayerSideScript.gold_reserva(main, pid))
			zones.append(PlayerSideScript.oro_pagado(main, pid))
			for zone in zones:
				if zone:
					for c in zone.get_children():
						if is_instance_valid(c) and _plain(str(c.get("card_name"))) == _plain(str(cond.name)):
							return true
			return false
		"controls_race":
			for ally in _allies_in_play(main, pid):
				if _race_matches(str(ally.get("card_raza")), cond.races):
					return true
			return false
	return false


static func _golds(main: Node, pid: int) -> int:
	"""Oros que controla: los de su Reserva y su Oro Pagado."""
	var n := 0
	for zone in [PlayerSideScript.gold_reserva(main, pid), PlayerSideScript.oro_pagado(main, pid)]:
		if zone:
			n += zone.get_children().filter(func(c): return is_instance_valid(c)).size()
	return n


static func _allies(main: Node, pid: int, zone: String) -> int:
	match zone:
		"cemetery":
			return CardManager.get_cemetery(pid).filter(func(d): return d.get("tipo") == Constants.CardType.ALIADO).size()
		"exile":
			return CardManager.get_exile(pid).filter(func(d): return d.get("tipo") == Constants.CardType.ALIADO).size()
	return _allies_in_play(main, pid).size()


static func _allies_in_play(main: Node, pid: int) -> Array:
	var out: Array = []
	if main == null:
		return out
	for container in PlayerSideScript.ally_containers(main, pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO:
				out.append(c)
	return out


static func race_matches(raza: String, races: Array) -> bool:
	return _race_matches(raza, races)


static func _race_matches(raza: String, races: Array) -> bool:
	var own := _plain(raza)
	for race in races:
		if _plain(race) in own:
			return true
	return false


static func _plain(text: String) -> String:
	var out := text.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"]]:
		out = out.replace(pair[0], pair[1])
	return out
