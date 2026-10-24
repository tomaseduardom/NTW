extends RefCounted
## CastleTopPlay — jugar desde el tope del Castillo (Escritura Sagrada). Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")


# -----------------------------------------------------------------------------
# Escritura Sagrada: "Cuando entra en juego, juega mostrando las primeras dos cartas de tu Castillo
# y puedes jugar cartas de coste 1 o más de ahí pagando su coste, por el turno. Si muestras Oros,
# puedes ponerlos en el fondo de tu Castillo."
# Anfitrión: al tocar tu Castillo se abre un visor con las dos primeras (como el del Cementerio,
# ZoneViewerModule) y los Oros van solos al fondo. Remoto: botón sobre el texto de la carta
# (habilidad sintética, CardInspectionLayer.usable_abilities_for).
# -----------------------------------------------------------------------------
const ESCRITURA_ABILITY_TEXT := "juega una carta de coste 1 o más de las dos primeras de tu castillo"


static func escritura_enter(_card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	RuleState.mark("escritura", controller_id)
	escritura_settle(controller_id)
	if main.get("_zone_viewer") and main._zone_viewer.has_method("refresh_castillo_top_reveal"):
		main._zone_viewer.refresh_castillo_top_reveal()


static func escritura_active(pid: int) -> bool:
	if GameManager.active_player_id != pid or not RuleState.marked("escritura", pid):
		return false
	return not CardQuery.cards_in_play_with(pid, "juega mostrando las primeras dos cartas de tu castillo").is_empty()


## Las dos primeras del Castillo de 'pid' (ya sin Oros arriba).
static func escritura_top(pid: int) -> Array:
	escritura_settle(pid)
	return CardManager.get_deck(pid).slice(0, 2)


static func escritura_settle(pid: int) -> void:
	"""Los Oros entre las dos primeras van solos al fondo (a pedido del
	usuario). Si todo lo que queda son Oros, no da más vueltas."""
	var deck: Array = CardManager.get_deck(pid)
	var moved := 0
	var guard: int = deck.size()
	while guard > 0:
		guard -= 1
		var gold_idx := -1
		for i in range(mini(2, deck.size())):
			if int(deck[i].get("tipo", -1)) == Constants.CardType.ORO:
				gold_idx = i
				break
		if gold_idx < 0:
			break
		deck.append(deck.pop_at(gold_idx))
		moved += 1
	var main := CardQuery.main_node()
	if moved > 0 and main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


## Habilidad sintética para el botón del Remoto (o {} si no corresponde).
static func escritura_synthetic_ability(source_card: Node, player_id: int, all_parsed: Array) -> Dictionary:
	if not PlayerSideScript.is_remote(player_id) or not is_instance_valid(source_card) or not escritura_active(player_id):
		return {}
	if KeywordManager.is_silenced(source_card) or not (source_card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return {}
	if not ("juega mostrando las primeras dos cartas de tu castillo" in CardQuery.ability_of(source_card)):
		return {}
	if escritura_candidates(player_id).is_empty():
		return {}
	var idx := 0
	for a in all_parsed:
		if "juega mostrando las primeras dos cartas" in str(a.get("raw_text", "")).to_lower():
			idx = int(a.get("ability_index", 0))
			break
	return {"ability_type": "ACTIVATED", "raw_text": ESCRITURA_ABILITY_TEXT, "ability_index": idx,
		"cost_text": "", "effect_text": "Juega una carta de coste 1 o más de las dos primeras de tu Castillo", "synthetic": true}


static func escritura_can_play(data: Dictionary, pid: int) -> bool:
	var main := CardQuery.main_node()
	if not main or not main.get("_gold_manager") or not escritura_active(pid):
		return false
	var cost: int = int(data.get("coste", 0))
	if int(data.get("tipo", -1)) == Constants.CardType.ORO or cost < 1:
		return false
	return main._gold_manager.puede_pagar(cost, int(data.get("tipo", -1)), str(data.get("raza", "")), cost, pid)


static func escritura_candidates(pid: int) -> Array:
	return escritura_top(pid).filter(func(d): return escritura_can_play(d, pid))


## Juega 'data' (una de las dos primeras del Castillo de 'pid').
static func escritura_play_data(data: Dictionary, pid: int) -> void:
	var main := CardQuery.main_node()
	var deck: Array = CardManager.get_deck(pid)
	if not main or not escritura_can_play(data, pid) or not (data in deck.slice(0, 2)):
		return
	deck.erase(data)
	var played: Dictionary = data.duplicate()
	played["esta_oculta"] = false
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	await main._gold_manager.play_found_card(played, pid, pid, 0, false)
	escritura_settle(pid)


## Botón del Remoto: elige cuál de las dos jugar.
static func escritura_play_from_top(source_card: Node) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card):
		return
	var pid: int = CardQuery.controller_of(source_card)
	var candidates: Array = escritura_candidates(pid)
	if candidates.is_empty():
		main._update_debug("No puedes pagar ninguna de las dos primeras cartas de tu Castillo")
		return
	var options: Array = candidates.map(func(d): return "Jugar %s (coste %d)" % [str(d.get("nombre", "")), int(d.get("coste", 0))])
	options.append("Cancelar")
	var idx: int = await SelectionManager.await_choice(main, "%s: juega una carta del tope de tu Castillo" % str(source_card.get("card_name")), options, pid)
	if idx >= 0 and idx < candidates.size():
		await escritura_play_data(candidates[idx], pid)
