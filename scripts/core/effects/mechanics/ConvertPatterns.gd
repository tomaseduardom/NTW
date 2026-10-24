extends RefCounted
## ConvertPatterns — Convertir cartas: en Tótem sin habilidad (tenshi z, Ángel Jeremiel) o en Aliado
## (Viejo del Saco, Vampiro de Rancagua).
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")


# -----------------------------------------------------------------------------
# Tótem convertidos (tenshi z, Ángel Jeremiel) y fortaleza hoshi
# -----------------------------------------------------------------------------
## Una carta EN JUEGO pasa a ser un Tótem sin habilidad de 'controller_id'
## (en su Línea de Apoyo). Sus Armas, si era un Aliado, van al Cementerio.
static func convert_in_play_to_totem(node: Node, source: Node, controller_id: int) -> bool:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(node) or await conversion_prevented(node, source):
		return false
	var wielder = node.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(node)
	var weapons = node.get("equipped_weapons")
	if weapons is Array:
		for w in weapons.duplicate():
			if is_instance_valid(w):
				await CardManager.destroy_card(w.owner_id if w.get("owner_id") != null else controller_id, w)
	if CardQuery.controller_of(node) != controller_id:
		ContinuousEffectManager.gain_control_of_card(node, controller_id)
		if CardQuery.controller_of(node) != controller_id:
			return false
	var line: Node = PlayerSideScript.line_containers(main, controller_id)[2]
	var old_parent = node.get_parent()
	if old_parent and old_parent != line:
		old_parent.remove_child(node)
		line.add_child(node)
	node.card_type = Constants.CardType.TOTEM
	node.top_level = false
	node.set_zone(Constants.Zone.LINEA_APOYO)
	node.can_interact = (controller_id == 0)
	node.is_converted = true
	await KeywordManager.silence_card(node, source, "permanent", true)
	ContinuousEffectManager.remove_modifiers_from_source(node)
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)
	return true


## tenshi z: "Una vez por turno, puedes convertir hasta dos cartas de coste 2
## o menos en Tótem sin habilidad y ganar su control." (Botón: AbilityButtonPatternsD.)
const TENSHI_TEXT := "convertir hasta dos cartas de coste 2 o menos en tótem sin habilidad y ganar su control"


static func tenshi_convert(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card) or not main._card_interaction:
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var candidates: Array = []
	for p in [0, 1]:
		for container in PlayerSideScript.line_containers(main, p):
			for c in container.get_children():
				if is_instance_valid(c) and ContinuousEffectManager.cost_at_most(c, 2) and c.get("card_type") != Constants.CardType.TOTEM:
					candidates.append(c)
				var weapons = c.get("equipped_weapons")
				if weapons is Array:
					for w in weapons:
						if is_instance_valid(w) and ContinuousEffectManager.cost_at_most(w, 2):
							candidates.append(w)
	if candidates.is_empty():
		main._update_debug("%s: no hay cartas de coste 2 o menos en juego" % title)
		return
	var chosen: Array = await main._card_interaction.await_multi_target(
		"%s: convierte hasta dos cartas de coste 2 o menos en Tótem sin habilidad" % title, candidates, 2,
		Callable(), Callable(), true, null, pid)
	if chosen.is_empty():
		return
	if await TriggerSystem.open_response_window(source_card, title, pid):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	for c in chosen:
		if is_instance_valid(c) and await convert_in_play_to_totem(c, source_card, pid):
			main._update_debug("%s: %s es ahora tu Tótem sin habilidad" % [title, str(c.get("card_name"))])


## Ángel Jeremiel: "Cuando entra en juego, tu oponente elige dos cartas de su
## mano. Conviértelas en Tótem sin habilidad y ponlos en tu Línea de Defensa."
static func jeremiel_enter(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Ángel Jeremiel"
	var opp: int = 1 - controller_id
	var hand: Array = PlayerSideScript.hand_cards(main, opp).filter(func(c): return is_instance_valid(c))
	if hand.is_empty():
		return
	var count: int = mini(2, hand.size())
	var chosen: Array = []
	if PlayerSideScript.is_bot(opp) or not main._card_interaction:
		hand.shuffle()
		chosen = hand.slice(0, count)
	else:
		while chosen.size() < count:
			chosen = await main._card_interaction.await_multi_target(
				"%s: elige %d cartas de tu mano — se convierten en Tótem del oponente" % [title, count], hand, count,
				Callable(), Callable(), false, null, opp)
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	var field: Node = PlayerSideScript.ally_containers(main, controller_id)[0]
	for c in chosen:
		if not is_instance_valid(c):
			continue
		var data: Dictionary = PlayerSideScript.take_from_hand(main, opp, c)
		data["tipo"] = Constants.CardType.TOTEM
		var node = main._create_card(data, false)
		node.owner_id = opp
		node.controller_id = controller_id
		main._connect_card_signals(node)
		field.add_child(node)
		node.set_zone(Constants.Zone.LINEA_DEFENSA)
		node.can_interact = (controller_id == 0)
		node.is_converted = true
		await KeywordManager.silence_card(node, card, "permanent", true)
		main._update_debug("%s: %s es ahora tu Tótem sin habilidad" % [title, str(data.get("nombre", ""))])
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)


## Ángel Jeremiel: "Una vez por turno, puedes Destruir un Tótem que controles
## para ganar el control de una carta oponente del mismo o menor coste."
const JEREMIEL_TEXT := "destruir un tótem que controles para ganar el control de una carta oponente del mismo o menor coste"


static func jeremiel_steal(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card) or not main._card_interaction:
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var totem: Node = await PlayerSideScript.pick_in_play(main, pid, "%s: Destruye un Tótem que controles (costo)" % title,
		func(c: Node) -> bool:
			return c.get("card_type") == Constants.CardType.TOTEM and c.get("current_zone") in Constants.ZONES_IN_PLAY \
				and CardQuery.controller_of(c) == pid, true, [pid])
	if not totem or not is_instance_valid(totem):
		return
	var max_cost: int = int(ContinuousEffectManager.get_modified_cost(totem))
	var target: Node = await PlayerSideScript.pick_in_play(main, pid,
		"%s: gana el control de una carta oponente de coste %d o menos" % [title, max_cost],
		func(c: Node) -> bool:
			return c.get("current_zone") in Constants.ZONES_IN_PLAY and CardQuery.controller_of(c) == 1 - pid \
				and ContinuousEffectManager.cost_at_most(c, max_cost), true, [1 - pid])
	if not target or not is_instance_valid(target):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await CardManager.destroy_card(totem.owner_id if totem.get("owner_id") != null else pid, totem)
	if await TriggerSystem.open_response_window(source_card, title, pid):
		return
	if is_instance_valid(target):
		ContinuousEffectManager.gain_control_of_card(target, pid)


# -----------------------------------------------------------------------------
# Viejo del Saco: "Cuando entra en juego o ataca, convierte una carta del tope
# de un Castillo o una carta de coste 1 o menos en un Aliado de Fuerza 2 con
# la habilidad Furia, Imbloqueable. Hace daño de combate al Destierro, y
# ponlo en juego bajo tu control o gana su control."
# -----------------------------------------------------------------------------
const VIEJO_TEXT := "convierte una carta del tope de un castillo o una carta de coste 1 o menos en un aliado de fuerza 2 con la habilidad furia, imbloqueable"


static func viejo_del_saco(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main or not main._card_interaction:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Viejo del Saco"
	var filter := func(c: Node) -> bool:
		return c.get("current_zone") in Constants.ZONES_IN_PLAY and ContinuousEffectManager.cost_at_most(c, 1)
	var choice: Dictionary = {}
	if PlayerSideScript.is_bot(controller_id):
		choice = {"type": "castillo", "own": false}
	else:
		choice = await main._card_interaction.await_target_or_castillo_pick(
			"%s: elige una carta de coste 1 o menos o un Castillo (su tope) para convertir" % title, filter, title,
			false, false, controller_id)
	if choice.get("type", "none") == "none":
		return
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	var field: Node = PlayerSideScript.ally_containers(main, controller_id)[0]
	var node: Node = null
	if choice.type == "card":
		node = choice.card
		if not await _take_and_convert_in_play(node, controller_id, card):
			return
	else:
		var zone_owner: int = controller_id if choice.get("own", true) else 1 - controller_id
		var deck: Array = CardManager.get_deck(zone_owner)
		if deck.is_empty():
			return
		var data: Dictionary = deck.pop_front().duplicate()
		data["tipo"] = Constants.CardType.ALIADO
		data["esta_oculta"] = false
		node = main._create_card(data, false)
		node.owner_id = zone_owner
		node.controller_id = controller_id
		main._connect_card_signals(node)
		field.add_child(node)
		node.set_zone(Constants.Zone.LINEA_DEFENSA)
		if CardFactory and CardFactory.has_method("on_card_enters_play"):
			CardFactory.on_card_enters_play(node)
		if node.has_method("play_enter_animation"):
			node.play_enter_animation()
		if main.get("_zone_manager"):
			main._zone_manager._update_castillo_counts()
	await _finish_conversion(node, card, controller_id, 2, [Constants.Keyword.FURIA, Constants.Keyword.IMBLOQUEABLE], true)
	main._update_debug("%s: %s es ahora un Aliado de Fuerza 2 con Furia e Imbloqueable" % [title, str(node.get("card_name"))])


## Una carta EN JUEGO pasa a ser un Aliado en la Línea de Defensa de
## 'controller_id' (ganando su control si hace falta). false si no se pudo.
## Marca de la Bestia: "no puede ser convertido ... hasta tu próximo turno" (meta "no_convert_until").
static func cannot_be_converted(node: Node) -> bool:
	if GameManager.turn_serial <= int(node.get_meta("no_convert_until", -1)):
		var main := CardQuery.main_node()
		if main:
			main._update_debug("%s no puede ser convertido" % str(node.get("card_name")))
		return true
	return false


## Además de "no puede ser convertido", ofrece las prevenciones de "ser convertido" (Romualdito; tag "convert").
static func conversion_prevented(node: Node, source: Node) -> bool:
	if cannot_be_converted(node):
		return true
	return await EffectController.offer_prevention(node, source, "convert")


static func _take_and_convert_in_play(node: Node, controller_id: int, source: Node = null) -> bool:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(node) or await conversion_prevented(node, source):
		return false
	var wielder = node.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(node)
	if CardQuery.controller_of(node) != controller_id:
		ContinuousEffectManager.gain_control_of_card(node, controller_id)
		if CardQuery.controller_of(node) != controller_id:
			return false  # no se pudo ganar su control (Abu Simbel)
	var field: Node = PlayerSideScript.ally_containers(main, controller_id)[0]
	var old_parent = node.get_parent()
	if old_parent and old_parent != field:
		old_parent.remove_child(node)
		field.add_child(node)
	node.card_type = Constants.CardType.ALIADO
	node.top_level = false
	node.set_zone(Constants.Zone.LINEA_DEFENSA)
	return true


## Convertir (DAR 8): sin habilidad, Fuerza fija y, si el texto lo da, las
## keywords nuevas (se otorgan después de silenciar).
static func _finish_conversion(node: Node, source: Node, controller_id: int, strength: int, keywords: Array,
		damage_to_exile: bool) -> void:
	node.can_interact = (controller_id == 0)
	node.is_converted = true
	await KeywordManager.silence_card(node, source, "permanent", true)
	var removed: Dictionary = KeywordManager._removed_keywords.get(node.get_instance_id(), {})
	for kw in keywords:
		removed.erase(kw)
		KeywordManager.grant_keyword(node, kw, source, "permanent")
	if damage_to_exile:
		node.set_meta("converted_damage_to_exile", true)
	ContinuousEffectManager.register_modifier({
		"source": null,
		"target": node,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": strength,
		"operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "Convertido: Aliado de Fuerza %d" % strength,
	})
	if node.has_method("refresh_strength_badge"):
		node.refresh_strength_badge()


# -----------------------------------------------------------------------------
# Vampiro de Rancagua: "Cuando entra en juego, convierte hasta una carta que
# no sea Oro en Aliado sin habilidad de Fuerza 3, gana su control y Roba una
# carta." (una carta = en juego)
# -----------------------------------------------------------------------------
static func convert_non_gold_strength_3(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Vampiro de Rancagua"
	# El bot se queda con un Aliado del rival.
	var target: Node = await PlayerSideScript.pick_in_play(main, controller_id,
		"%s: convierte hasta una carta que no sea Oro en un Aliado de Fuerza 3 sin habilidad (N: ninguna)" % title,
		func(c: Node) -> bool:
			return c.get("current_zone") in Constants.ZONES_IN_PLAY and c.get("card_type") != Constants.CardType.ORO,
		true, [1 - controller_id], false,
		func(c: Node) -> bool: return c.get("card_type") == Constants.CardType.ALIADO)
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	if target and is_instance_valid(target) and await _take_and_convert_in_play(target, controller_id, card):
		await _finish_conversion(target, card, controller_id, 3, [], false)
		main._update_debug("%s: %s es ahora tu Aliado de Fuerza 3 sin habilidad" % [title, str(target.get("card_name"))])
	await ActionModule.draw(controller_id, 1, title, true)
