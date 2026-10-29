extends RefCounted
## InPlayAbilities — Habilidades al entrar y botones: Aegishjalmur, Ciudad de los Césares, Quicaví,
## fortaleza hoshi (Desterrar del tope).
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const PreventionCosts = preload("res://scripts/core/effects/mechanics/PreventionCosts.gd")


# -----------------------------------------------------------------------------
# Aegishjalmur: "Cuando entra en juego, elige dos efectos: - Sube un Aliado de
# tu Cementerio a tu mano. - Baraja hasta una carta de coste 2 o menos. - Roba
# una carta."
# -----------------------------------------------------------------------------
static func aegishjalmur(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Aegishjalmur"
	var options: Array = ["Sube un Aliado de tu Cementerio a tu mano", "Baraja hasta una carta de coste 2 o menos", "Roba una carta"]
	var chosen: Array = []
	if PlayerSideScript.is_bot(controller_id):
		chosen = [0, 2]
	else:
		var first: int = await SelectionManager.await_choice(main, "%s: elige el primer efecto" % title, options, controller_id)
		var rest: Array = [0, 1, 2]
		rest.erase(first)
		var labels: Array = rest.map(func(i): return options[i])
		var second: int = await SelectionManager.await_choice(main, "%s: elige el segundo efecto" % title, labels, controller_id)
		chosen = [first, rest[clampi(second, 0, 1)]]
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	chosen.sort()
	for effect in chosen:
		match effect:
			0:
				await _raise_cemetery_ally(main, controller_id, title)
			1:
				await _shuffle_up_to_one_cost_2(main, card, controller_id, title)
			2:
				await ActionModule.draw(controller_id, 1, title, true)


static func _raise_cemetery_ally(main: Node, controller_id: int, title: String) -> void:
	var picked_data: Dictionary = {}
	if PlayerSideScript.is_bot(controller_id) or not main._zone_viewer:
		for d in CardManager.get_cemetery(controller_id):
			if int(d.get("tipo", -1)) == Constants.CardType.ALIADO:
				picked_data = d
				break
	else:
		var eligible := func(c: Node) -> bool:
			return c.owner_id == controller_id and c.get("card_type") == Constants.CardType.ALIADO
		var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"%s: sube un Aliado de tu Cementerio a tu mano" % title, eligible, 1, "cemetery", false, false, controller_id)
		if not picked.is_empty():
			picked_data = picked[0].data
	if picked_data.is_empty() or not CardManager.take_from_cemetery(controller_id, picked_data):
		return
	PlayerSideScript.put_in_hand(main, controller_id, picked_data)


static func _shuffle_up_to_one_cost_2(main: Node, card: Node, controller_id: int, title: String) -> void:
	# "hasta": el bot no lo usa.
	var target: Node = await PlayerSideScript.pick_in_play(main, controller_id,
		"%s: Baraja hasta una carta de coste 2 o menos (N: ninguna)" % title,
		func(c: Node) -> bool:
			return c.get("current_zone") in Constants.ZONES_IN_PLAY and ContinuousEffectManager.cost_at_most(c, 2),
		true, [], true)
	if target and is_instance_valid(target):
		await PlayerSideScript.shuffle_into_castle(target, card, title)


## fortaleza hoshi: "Una vez por turno, Destierra tantas cartas del tope de un
## Castillo como Tótem controles."
const HOSHI_TEXT := "destierra tantas cartas del tope de un castillo como tótem controles"


static func hoshi_mill(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card):
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var count := 0
	for container in PlayerSideScript.line_containers(main, pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.TOTEM:
				count += 1
	if count <= 0:
		main._update_debug("%s: no controlas Tótem" % title)
		return
	var own: bool = await SelectionManager.await_two_choice(main, "%s: Destierra %d del tope de un Castillo" % [title, count],
		"Tu Castillo", "Castillo de tu oponente", pid) if not PlayerSideScript.is_bot(pid) else false
	if await TriggerSystem.open_response_window(source_card, title, pid):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.mill(pid if own else 1 - pid, count, true, title)


# -----------------------------------------------------------------------------
# Ciudad de los Césares
# -----------------------------------------------------------------------------
static func shuffle_opponent_cost3_draw2(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Ciudad de los Césares"
	var filter := func(c: Node) -> bool:
		return c.get("current_zone") in Constants.ZONES_IN_PLAY and CardQuery.controller_of(c) == 1 - controller_id \
			and ContinuousEffectManager.cost_at_most(c, 3)
	var target: Node = await PlayerSideScript.pick_in_play(main, controller_id,
		"%s: Baraja hasta una carta oponente de coste 3 o menos (N: ninguna)" % title, filter, true, [1 - controller_id])
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	if target and is_instance_valid(target):
		await PlayerSideScript.shuffle_into_castle(target, card, title)
	await ActionModule.draw(controller_id, 2, title, true)


## "Una vez por turno, puedes Barajar una carta de tu mano para Anular o
## Desterrar una carta de coste 1 o menos, o pagar un Oro para Anular una
## carta de coste 2 o más." (Botón: AbilityButtonPatternsD.)
const CIUDAD_TEXT := "barajar una carta de tu mano para anular o desterrar una carta de coste 1 o menos, o pagar un oro para anular una carta de coste 2 o más"


static func ciudad_activate(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card):
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var StackAnnulScript = load("res://scripts/core/effects/StackAnnul.gd")
	var low_obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		return StackAnnulScript.type_of(o) != Constants.CardType.ORO and StackAnnulScript.cost_of(o) <= 1)
	var high_obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		return StackAnnulScript.type_of(o) != Constants.CardType.ORO and StackAnnulScript.cost_of(o) >= 2)
	var has_hand: bool = not PlayerSideScript.hand_cards(main, pid).is_empty()
	var banish_filter := func(c: Node) -> bool:
		return c.get("current_zone") in Constants.ZONES_IN_PLAY and ContinuousEffectManager.cost_at_most(c, 1)
	var options: Array = []
	var kinds: Array = []
	if has_hand and not low_obj.is_empty():
		options.append("Barajar una de tu mano: Anular %s" % str(StackAnnulScript.data_of(low_obj).get("nombre", "")))
		kinds.append("annul_low")
	if has_hand:
		options.append("Barajar una de tu mano: Desterrar una carta de coste 1 o menos")
		kinds.append("banish")
	if not high_obj.is_empty() and main._gold_manager.puede_pagar(1, -1, "", -1, pid):
		options.append("Pagar un Oro: Anular %s" % str(StackAnnulScript.data_of(high_obj).get("nombre", "")))
		kinds.append("annul_high")
	if options.is_empty():
		main._update_debug("%s: no hay nada que Anular ni cartas en tu mano para Barajar" % title)
		return
	options.append("Cancelar")
	var idx: int = await SelectionManager.await_choice(main, title, options, pid)
	if idx < 0 or idx >= kinds.size():
		return
	var kind: String = kinds[idx]
	var target: Node = null
	if kind == "banish":
		target = await PlayerSideScript.pick_in_play(main, pid, "%s: Destierra una carta de coste 1 o menos" % title,
			banish_filter, true, [1 - pid])
		if not target or not is_instance_valid(target):
			return
	# Costo.
	if kind == "annul_high":
		if not await PlayerSideScript.pay(main, pid, 1, null):
			return
	elif not await PreventionCosts.shuffle_one_from_hand_cost(source_card):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	match kind:
		"annul_low":
			StackAnnulScript.apply(low_obj, source_card)
		"annul_high":
			StackAnnulScript.apply(high_obj, source_card)
		"banish":
			if is_instance_valid(target):
				await ActionModule.banish([target], source_card)


# -----------------------------------------------------------------------------
# Armadura Celestial: "Puedes Destruir el portador para Anular un Talismán de coste 2 o menos o
# cancelar la habilidad de una carta que afecte a un Aliado." (Botón: AbilityButtonPatternsD.) La
# Pila no dice a quién afecta una habilidad: se puede Cancelar cualquiera del rival.
# -----------------------------------------------------------------------------
const ARMADURA_TEXT := "puedes destruir el portador para anular un talismán de coste 2 o menos o cancelar la habilidad de una carta que afecte a un aliado"


static func armadura_celestial(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card):
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var wielder: Node = null
	for line in PlayerSideScript.line_containers(main, pid):
		for c in (line.get_children() if line else []):
			if is_instance_valid(c) and c.get("equipped_weapons") is Array and source_card in c.equipped_weapons:
				wielder = c
	if wielder == null:
		main._update_debug("%s: no está equipada" % title)
		return
	var StackAnnulScript = load("res://scripts/core/effects/StackAnnul.gd")
	var annul_obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN and StackAnnulScript.cost_of(o) <= 2)
	var cancel_obj: Dictionary = StackAnnulScript.find_target(pid, false, true)
	var options: Array = []
	var picks: Array = []
	if not annul_obj.is_empty():
		options.append("Anular %s" % str(StackAnnulScript.data_of(annul_obj).get("nombre", "")))
		picks.append(annul_obj)
	if not cancel_obj.is_empty():
		options.append("Cancelar la habilidad de %s" % str(StackAnnulScript.data_of(cancel_obj).get("nombre", "")))
		picks.append(cancel_obj)
	if options.is_empty():
		main._update_debug("%s: no hay un Talismán de coste 2 o menos ni una habilidad que Cancelar" % title)
		return
	var idx := 0
	if options.size() > 1 or not PlayerSideScript.is_bot(pid):
		options.append("No hacer nada")
		idx = await SelectionManager.await_choice(main, "%s: Destruye al portador para..." % title, options, pid)
	if idx < 0 or idx >= picks.size():
		return
	# Costo: Destruir el portador (el Arma, con él, sale del juego).
	var res: Dictionary = await ActionModule.destroy([wielder], source_card, false, true)
	if not res.get("success", true) or (is_instance_valid(wielder) and wielder.get("current_zone") in Constants.ZONES_IN_PLAY):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	StackAnnulScript.apply(picks[idx], source_card)


# -----------------------------------------------------------------------------
# kabutowari: "En Guerra de Talismanes, una vez por turno, el portador gana 1 de Fuerza por cada
# Aliado en tu Línea de Defensa. Si el portador ganó 1 de Fuerza o menos de esta manera, Roba una
# carta. De lo contrario, Roba dos cartas." (Botón: AbilityButtonPatternsD; la fase la valida
# AbilityButtonSupport._validate_ability.) La Fuerza es por el turno.
# -----------------------------------------------------------------------------
const KABUTOWARI_TEXT := "el portador gana 1 de fuerza por cada aliado en tu línea de defensa"


static func kabutowari(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card):
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var wielder: Node = null
	for line in PlayerSideScript.line_containers(main, pid):
		for c in (line.get_children() if line else []):
			if is_instance_valid(c) and c.get("equipped_weapons") is Array and source_card in c.equipped_weapons:
				wielder = c
	if wielder == null:
		main._update_debug("%s: no está equipada" % title)
		return
	if await TriggerSystem.open_response_window(source_card, title, pid):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	var defense: Node = PlayerSideScript.line_containers(main, pid)[0]
	var gained: int = defense.get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO).size() if defense else 0
	if gained > 0 and is_instance_valid(wielder):
		ContinuousEffectManager.register_modifier({
			"source": source_card, "target": wielder,
			"type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
			"value": gained, "operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s +%d" % [title, gained],
		})
		if wielder.has_method("refresh_strength_badge"):
			wielder.refresh_strength_badge()
	await ActionModule.draw(pid, 1 if gained <= 1 else 2, title, true)


# -----------------------------------------------------------------------------
# Quicaví: "Una vez por turno, puedes hacer que hasta tu próximo turno, una
# carta de tu Cementerio gane Exhumar y no recibes daño de combate."
# (Botón: AbilityButtonPatternsD.)
# -----------------------------------------------------------------------------
const QUICAVI_TEXT := "una carta de tu cementerio gane exhumar y no recibes daño de combate"


static func quicavi(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card):
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	var picked_data: Dictionary = {}
	if PlayerSideScript.is_bot(pid) or not main._zone_viewer:
		for d in CardManager.get_cemetery(pid):
			if int(d.get("tipo", -1)) != Constants.CardType.ORO:
				picked_data = d
				break
	else:
		var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"%s: una carta de tu Cementerio gana Exhumar hasta tu próximo turno (N: ninguna)" % title,
			func(c: Node) -> bool: return c.owner_id == pid, 1, "cemetery", false, false, pid)
		if not picked.is_empty():
			picked_data = picked[0].data
	if await TriggerSystem.open_response_window(source_card, title, pid):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	# No recibes daño de combate hasta tu próximo turno (mismo registro que
	# Linaje Maldito, NoePatterns.damage_immune).
	RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: no recibes daño de combate hasta tu próximo turno" % title)
	if picked_data.is_empty():
		return
	var keywords: Array = picked_data.get("keywords", []).duplicate()
	if Constants.Keyword.EXHUMAR not in keywords and "EXHUMAR" not in keywords:
		keywords.append(Constants.Keyword.EXHUMAR)
	picked_data["keywords"] = keywords
	var clear_it_box: Array = []  # la lambda captura por valor: se desconecta por aquí
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != pid:
			return
		picked_data["keywords"] = picked_data.get("keywords", []).filter(func(k): return k != Constants.Keyword.EXHUMAR and k != "EXHUMAR")
		if GameManager.turn_started.is_connected(clear_it_box[0]):
			GameManager.turn_started.disconnect(clear_it_box[0])
	clear_it_box.append(clear_it)
	GameManager.turn_started.connect(clear_it)
	if PaymentManager.get("_exhumar") and PaymentManager._exhumar.has_method("invalidate_cache"):
		PaymentManager._exhumar.invalidate_cache()
	main._update_debug("%s gana Exhumar hasta tu próximo turno" % str(picked_data.get("nombre", "")))


# -----------------------------------------------------------------------------
# iga ryu: "El primer Aliado que entre bajo el control de tu oponente cada turno, pierde su
# habilidad." Lo llama TriggerSystem._collect_triggers_for_event("on_enter_play") antes de
# recolectar los disparadores de esa carta. Sin duración escrita: permanente.
# -----------------------------------------------------------------------------
const IGA_RYU_SILENCE_TEXT := "el primer aliado que entre bajo el control de tu oponente cada turno, pierde su habilidad"


static func iga_ryu_on_ally_enters(card) -> void:
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ALIADO:
		return
	var ctrl := CardQuery.controller_of(card)
	var main := CardQuery.main_node()
	if ctrl < 0 or main == null:
		return
	var source: Node = null
	for c in PlayerSideScript.line_containers(main, 1 - ctrl):
		for x in c.get_children():
			if is_instance_valid(x) and not KeywordManager.is_silenced(x) and IGA_RYU_SILENCE_TEXT in CardQuery.ability_of(x):
				source = x
				break
		if source:
			break
	if source == null:
		return
	var key := "iga_ryu_first_ally:%d" % ctrl
	if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.turn_serial):
		return
	UniversalCardParser.turn_registry.register(key, 0, GameManager.turn_serial)
	KeywordManager.silence_card(card, source, "permanent", true)
	if main.has_method("_update_debug"):
		main._update_debug("%s pierde su habilidad (%s)" % [str(card.get("card_name")), str(source.get("card_name"))])


# -----------------------------------------------------------------------------
# iga ryu: "Una vez por turno, puedes convertir hasta tres Tótem en Aliados de Fuerza 4 por el
# turno." Activada (TriggerResolution → TotemAbilityPatterns). Misma conversión que metropolitan
# (TotemAbilityPatterns.convert_totem_to_ally), revertida al comenzar el turno siguiente.
# -----------------------------------------------------------------------------
const IGA_RYU_CONVERT_TEXT := "puedes convertir hasta tres tótem en aliados de fuerza 4 por el turno"


# -----------------------------------------------------------------------------
# Estación Fantasma: "Cuando ataques, elige hasta dos Aliados con Furia que controles para que no
# hagan daño este turno y tu oponente Destierre tantas cartas del fondo de su Castillo como su
# Fuerza." GameManager.confirm_attackers() lo llama una vez por ataque, con los atacantes ya
# declarados. "No hace daño": meta no_damage_turn (BattleManager no suma su daño ni destruye a su
# bloqueador). El bot elige solo Aliados con Furia que no atacan (no pierde daño).
# -----------------------------------------------------------------------------
const ESTACION_TEXT := "cuando ataques, elige hasta dos aliados con furia que controles para que no hagan daño este turno"


static func estacion_fantasma_on_attack(pid: int) -> void:
	var main := CardQuery.main_node()
	if main == null or not main._card_interaction:
		return
	for line in PlayerSideScript.line_containers(main, pid):
		for src in line.get_children():
			if is_instance_valid(src) and not KeywordManager.is_silenced(src) and ESTACION_TEXT in CardQuery.ability_of(src):
				await _estacion_fantasma(main, src, pid)


static func _estacion_fantasma(main: Node, src: Node, pid: int) -> void:
	var name := str(src.get("card_name"))
	var furia: Array = []
	for line in PlayerSideScript.ally_containers(main, pid):
		for a in line.get_children():
			if is_instance_valid(a) and a.get("card_type") == Constants.CardType.ALIADO \
					and KeywordManager.has_keyword(a, Constants.Keyword.FURIA):
				furia.append(a)
	if furia.is_empty():
		return
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		chosen = furia.filter(func(a): return not (a in GameManager.attackers)).slice(0, 2)
	else:
		chosen = await main._card_interaction.await_multi_target(
			"%s: elige hasta dos Aliados con Furia para que no hagan daño este turno" % name, furia, 2,
			Callable(), Callable(), true, null, pid)
	if chosen.is_empty():
		return
	if await TriggerSystem.open_response_window(src, name, pid):
		return
	var total := 0
	for a in chosen:
		if is_instance_valid(a):
			a.set_meta("no_damage_turn", GameManager.turn_serial)
			total += maxi(0, ContinuousEffectManager.get_modified_strength(a))
	if total > 0:
		CardManager.banish_from_deck(1 - pid, total, true, pid)
		if main.has_method("_update_debug"):
			main._update_debug("%s: tu oponente Destierra %d cartas del fondo de su Castillo" % [name, total])
