extends "res://scripts/core/effects/mechanics/ActivatedPatternsManoCementerio.gd"
## ActivatedPatterns — familia Fases (ver ActivatedPatternsBase.gd para la cabecera, constantes y ayudas).


# =============================================================================
# QUINTO LOTE
# =============================================================================


## colmillo arcano, gema del grifo, amuleto de cazador: el Oro pasa a ser un Aliado de Fuerza N con la habilidad
## entre comillas hasta tu próximo turno (al empezarlo vuelve a ser ese Oro, en tu Oro Pagado).
static func _gold_to_ally_until_next_turn(main: Node, card: Node, pid: int, strength: int, ability: String) -> void:
	if card.get("card_type") != Constants.CardType.ORO or not (card.get("current_zone") in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]):
		return
	var original: String = str(card.card_data.get("habilidad", ""))
	if card.get("current_zone") == Constants.Zone.ORO_PAGADO:
		GameState.agregar_oro_pagado(pid, -1)
	else:
		GameState.agregar_oro_reserva(pid, -1)
	card.get_parent().remove_child(card)
	card.card_type = Constants.CardType.ALIADO
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	card.modulate = Color.WHITE
	PlayerSideScript.ally_containers(main, pid)[0].add_child(card)
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	EnterScript.set_ability(card, ability)
	ContinuousEffectManager.register_modifier({
		"source": card, "target": card, "type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
		"value": strength, "operation": "set", "duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "%s: Aliado de Fuerza %d" % [_name(card), strength],
	})
	if card.has_method("refresh_strength_badge"):
		card.refresh_strength_badge()
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	main._update_debug("%s pasa a ser un Aliado de Fuerza %d hasta tu próximo turno" % [_name(card), strength])
	_revert_on_next_turn(main, card, pid, original)


static func _revert_on_next_turn(main: Node, card: Node, pid: int, original: String) -> void:
	var revert_box: Array = []  # la lambda captura por valor: se desconecta por aquí
	var revert: Callable
	revert = func(started: int, _turn: int) -> void:
		if started != pid:
			return
		if GameManager.turn_started.is_connected(revert_box[0]):
			GameManager.turn_started.disconnect(revert_box[0])
		if not is_instance_valid(card) or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
			return
		ContinuousEffectManager.remove_modifiers_from_source(card)
		var wielder = card.get("wielder")
		if is_instance_valid(wielder):
			CardManager._unequip_from_wielder(card)
			card.wielder = null
		if card.get_parent():
			card.get_parent().remove_child(card)
		card.card_type = Constants.CardType.ORO
		KeywordManager.clear_all_for_card(card)
		EnterScript.set_ability(card, original)
		PlayerSideScript.oro_pagado(main, pid).add_child(card)
		card.set_zone(Constants.Zone.ORO_PAGADO)
		card.scale = Constants.GOLD_CARD_SCALE
		card.base_scale = Constants.GOLD_CARD_SCALE
		card.modulate = Color(0.6, 0.6, 0.6, 1.0)
		GameState.agregar_oro_pagado(pid, 1)
		if main._gold_manager:
			main._gold_manager._update_gold_display()
		main._update_debug("%s vuelve a ser un Oro" % _name(card))
	revert_box.append(revert)
	GameManager.turn_started.connect(revert)


static func _quoted(card: Node) -> String:
	var m := RegEx.create_from_string("con la habilidad [\"“”]([^\"“”]+)[\"“”]").search(str(card.card_data.get("habilidad", "")))
	return m.get_string(1) if m else ""


static func _colmillo_arcano(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).any(func(c): return KeywordManager.has_keyword(c, Constants.Keyword.FURIA)):
		main._update_debug("%s: necesitas controlar Aliados con Furia" % _name(card))
		return
	await _gold_to_ally_until_next_turn(main, card, pid, 3, _quoted(card))


static func _gema_grifo(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).any(func(c): return EnterScript._cost(c) >= 2):
		main._update_debug("%s: necesitas controlar Aliados de coste 2 o más" % _name(card))
		return
	await _gold_to_ally_until_next_turn(main, card, pid, 4, _quoted(card))


static func _amuleto_cazador(main: Node, card: Node, pid: int) -> void:
	if RuleState.count("played_type:%d" % Constants.CardType.TALISMAN, pid) < 2:
		main._update_debug("%s: necesitas haber jugado dos o más Talismanes este turno" % _name(card))
		return
	await _gold_to_ally_until_next_turn(main, card, pid, 5, _quoted(card))


## arpon sagrado: el Oro pasa a ser un Arma con la habilidad entre comillas hasta tu próximo turno y la porta un
## Aliado que controles.
static func _arpon_sagrado(main: Node, card: Node, pid: int) -> void:
	if not (card.get("current_zone") in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]) or not main._gold_manager:
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles porta el Arma" % _name(card), _allies(main, pid), true)
	if not is_instance_valid(ally):
		return
	var original: String = str(card.card_data.get("habilidad", ""))
	if card.get("current_zone") == Constants.Zone.ORO_PAGADO:
		GameState.agregar_oro_pagado(pid, -1)
	else:
		GameState.agregar_oro_reserva(pid, -1)
	card.card_type = Constants.CardType.ARMA
	card.modulate = Color.WHITE
	EnterScript.set_ability(card, _quoted(card))
	await main._gold_manager._equip_weapon(card, ally, false)
	main._gold_manager._update_gold_display()
	_revert_on_next_turn(main, card, pid, original)


static func _to_attack_line(main: Node, ally: Node, pid: int) -> void:
	var line: Node = PlayerSideScript.ally_containers(main, pid)[1] if PlayerSideScript.ally_containers(main, pid).size() > 1 else null
	if not line or not is_instance_valid(ally) or ally.get_parent() == line:
		return
	ally.get_parent().remove_child(ally)
	ally.set_meta("idle_attack_line", true)  # azul hielo mientras no ataque (CardInteractionModule)
	line.add_child(ally)
	ally.set_zone(Constants.Zone.LINEA_ATAQUE)
	main._update_debug("%s pasa a la Línea de Ataque" % EnterScript._name(ally))


static func _akashi(main: Node, card: Node, pid: int) -> void:
	var defenders: Array = _allies(main, pid).filter(func(c): return c.get("current_zone") == Constants.Zone.LINEA_DEFENSA)
	var mover: Node = await EnterScript._pick_from(main, pid, "Akashi: mueve un Aliado a la Línea de Ataque", defenders, true)
	if is_instance_valid(mover):
		_to_attack_line(main, mover, pid)
	var small: Array = EnterScript._all_allies(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	var t: Node = await EnterScript._pick_from(main, pid, "Akashi: sube un Aliado de coste 2 o menos a la mano de su dueño", small, true)
	if is_instance_valid(t):
		await EnterScript.bounce_to_owner_hand(main, t, card)


static func _batallon_ovejas(main: Node, card: Node, pid: int) -> void:
	_to_attack_line(main, card, pid)
	var t: Node = await EnterScript._pick_from(main, pid, "Batallón de Ovejas: un Aliado no puede bloquear este turno", _allies(main, 1 - pid), true)
	if not is_instance_valid(t):
		return
	ContinuousEffectManager.register_modifier({
		"source": t, "target": t, "type": ContinuousEffectManager.ModifierType.RESTRICTION, "restriction_type": "CANT_BLOCK",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN, "description": "No puede bloquear este turno (Batallón de Ovejas)",
	})
	main._update_debug("%s no puede bloquear este turno" % EnterScript._name(t))


static func _grant_in_cemetery(main: Node, card: Node, pid: int, filter: Callable, text: String, title: String) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: %s" % [_name(card), title], 0, 3, filter)
	for pk in picks:
		var d: Dictionary = pk.data
		if not (text in str(d.get("habilidad", ""))):
			d["habilidad"] = (str(d.get("habilidad", "")) + "\n" + text).strip_edges()
	if not picks.is_empty():
		main._update_debug("%s: %d carta(s) de tu Cementerio ganan \"%s\"" % [_name(card), picks.size(), text])


static func _tundra_viva(main: Node, card: Node, pid: int) -> void:
	await _grant_in_cemetery(main, card, pid, func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] \
		and int(d.get("coste", 0)) >= 1, TUNDRA_GRANT, "hasta tres Aliados y/o Armas de coste 1 o más")


static func _isla_gigantes(main: Node, card: Node, pid: int) -> void:
	await _grant_in_cemetery(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN \
		and int(d.get("coste", 0)) >= 1, ISLA_GRANT, "hasta tres Talismanes de coste 1 o más")


## El costo de las habilidades ganadas: Desterrar N otras cartas de tu Cementerio.
static func _exile_other_cemetery(main: Node, card: Node, pid: int, n: int) -> bool:
	var own: Dictionary = card.card_data if is_instance_valid(card) and card.get("card_data") is Dictionary else {}
	var others: Array = CardManager.get_cemetery(pid).filter(func(d): return _find_data([d], own).is_empty())
	if others.size() < n:
		main._update_debug("Necesitas otras %d cartas en tu Cementerio" % n)
		return false
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Destierra %d cartas de tu Cementerio" % n, n, n,
		func(d): return _find_data([d], own).is_empty())
	if picks.size() < n:
		return false
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			pk.data["esta_oculta"] = false
			CardManager.append_to_exile(pid, pk.data)
	return true


static func _tundra_granted(main: Node, card: Node, pid: int) -> void:
	if not await _exile_other_cemetery(main, card, pid, 2):
		return
	var d := _take_self(main, card, pid)
	if not d.is_empty():
		PlayerSideScript.put_in_hand(main, pid, d)


static func _isla_granted(main: Node, card: Node, pid: int) -> void:
	if not await _exile_other_cemetery(main, card, pid, 3):
		return
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return
	if not await TalismanScript._play_paying(main, pid, d, int(d.get("coste", 0))):
		CardManager.add_to_cemetery(pid, d)
		return
	# "y Destiérralo": el Talismán resuelto pasa del Cementerio al Destierro.
	var cem: Array = CardManager.get_cemetery(pid)
	for i in range(cem.size() - 1, -1, -1):
		if str(cem[i].get("nombre", "")) == str(d.get("nombre", "")):
			var t: Dictionary = cem[i]
			if CardManager.take_from_cemetery(pid, t):
				CardManager.append_to_exile(pid, t)
			break

# =============================================================================
# SEXTO LOTE: Báculo de los Eternos, ayyappan, Caos
# =============================================================================


static func _baculo_eternos(main: Node, card: Node, pid: int) -> void:
	var n: int = EnterScript._in_play(main, pid, func(c): return c.get("card_type") in [Constants.CardType.ARMA, Constants.CardType.TOTEM]).size()
	for a in _allies(main, pid):
		if a.get("equipped_weapons") is Array:
			n += a.equipped_weapons.filter(func(w): return is_instance_valid(w)).size()
	if n > 0:
		await CastleLookScript.look(pid, pid, n, true, CastleLookScript.rest_box(true), "%s: ordena las cartas del tope de tu Castillo" % _name(card))
	if await EnterScript._confirm(main, pid, _name(card), "Robar una carta (no Robas al finalizar tu turno)"):
		await ActionModule.draw(pid, 1, _name(card), true)
		TriggerSystem._oro_patterns.register_torii_skip_final_draw(pid)


## ayyappan: "puedes mostrar un Aliado Caballero de tu mano para activar la habilidad de un Arma que hayas
## activado este turno" (otra vez, sin su límite por turno).
static func _ayyappan(main: Node, card: Node, pid: int) -> void:
	var options: Array = []  # [{weapon, ability}]
	var weapons: Array = CardQuery.weapons_in_play(pid)
	for w in weapons:
		if not is_instance_valid(w) or w.get("card_data") == null:
			continue
		for ab in UniversalCardParser.parse_abilities(str(w.card_data.get("habilidad", "")), str(w.card_data.get("id", ""))):
			if ab.get("ability_type", "") == "ACTIVATED" and UniversalCardParser.turn_registry.was_used(
					str(w.get_instance_id()), int(ab.get("ability_index", 0)), GameManager.turn_serial):
				options.append({"weapon": w, "ability": ab})
	if options.is_empty():
		main._update_debug("Ayyappan: no activaste la habilidad de un Arma este turno")
		return
	var knights: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and "caballero" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	var shown: Node = await EnterScript._pick_from(main, pid, "Ayyappan: muestra un Aliado Caballero de tu mano", knights, true)
	if not is_instance_valid(shown):
		return
	main._update_debug("Ayyappan: muestra %s" % EnterScript._name(shown))
	var idx := 0
	if options.size() > 1 and not PlayerSideScript.is_bot(pid):
		idx = clampi(await SelectionManager.await_choice(main, "Ayyappan: ¿qué habilidad activas otra vez?",
			options.map(func(o): return "%s: %s" % [EnterScript._name(o.weapon), str(o.ability.get("raw_text", "")).substr(0, 50)]), pid), 0, options.size() - 1)
	var chosen: Dictionary = options[idx]
	if main.get("_card_inspector") and main._card_inspector.has_method("activate_ability_for"):
		await main._card_inspector.activate_ability_for(chosen.weapon, chosen.ability, pid)


static func _caos(main: Node, card: Node, pid: int) -> void:
	var golds: Array = EnterScript._golds(main, [pid]).filter(func(g): return not g.get_meta("caos_gold", false))
	var g: Node = await EnterScript._pick_from(main, pid, "Caos: un Oro gana la habilidad", golds, false)
	if not is_instance_valid(g):
		return
	g.set_meta("caos_original", str(g.card_data.get("habilidad", "")))
	g.set_meta("caos_gold", true)
	EnterScript.set_ability(g, (str(g.card_data.get("habilidad", "")) + "\n" + CAOS_GRANT).strip_edges())
	main._update_debug("Caos: %s gana \"%s\"" % [EnterScript._name(g), CAOS_GRANT])


static func caos_to_ally(main: Node, g: Node) -> void:
	var pid: int = int(g.controller_id) if g.get("controller_id") != null else 0
	if g.get_parent():
		g.get_parent().remove_child(g)
	g.card_type = Constants.CardType.ALIADO
	g.scale = Vector2.ONE
	g.base_scale = Vector2.ONE
	g.modulate = Color.WHITE
	g.can_interact = pid == 0
	PlayerSideScript.ally_containers(main, pid)[0].add_child(g)
	g.set_zone(Constants.Zone.LINEA_DEFENSA)
	g.set_meta("caos_ally", true)
	ContinuousEffectManager.register_modifier({
		"source": g, "target": g, "type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
		"value": 3, "operation": "set", "duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "Caos: Aliado de Fuerza 3",
	})
	if g.has_method("refresh_strength_badge"):
		g.refresh_strength_badge()
	main._update_debug("%s pasa a ser un Aliado de Fuerza 3 (Caos)" % EnterScript._name(g))


static func caos_back_to_gold(main: Node, g: Node) -> void:
	if not is_instance_valid(g) or not g.get_meta("caos_ally", false) or not (g.get("current_zone") in Constants.ZONES_IN_PLAY):
		return
	var pid: int = int(g.controller_id) if g.get("controller_id") != null else 0
	ContinuousEffectManager.remove_modifiers_from_source(g)
	GameManager.attackers.erase(g)
	if g.get_parent():
		g.get_parent().remove_child(g)
	g.card_type = Constants.CardType.ORO
	g.remove_meta("caos_ally")
	g.remove_meta("caos_gold")
	EnterScript.set_ability(g, str(g.get_meta("caos_original", "")))
	PlayerSideScript.oro_pagado(main, pid).add_child(g)
	g.set_zone(Constants.Zone.ORO_PAGADO)
	g.scale = Constants.GOLD_CARD_SCALE
	g.base_scale = Constants.GOLD_CARD_SCALE
	g.modulate = Color(0.6, 0.6, 0.6, 1.0)
	GameState.agregar_oro_pagado(pid, 1)
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	main._update_debug("%s hizo daño: vuelve a ser un Oro en tu Oro Pagado (Caos)" % EnterScript._name(g))

# =============================================================================
# SÉPTIMO LOTE: Fase Final, Vigilia y Destruido
# =============================================================================


## Agrupar un Aliado (DAR 5.1): de la Línea de Ataque vuelve a la Línea de Defensa.
static func _regroup(main: Node, allies: Array) -> void:
	var in_atk: Array = allies.filter(func(a): return is_instance_valid(a) and a.get("current_zone") == Constants.Zone.LINEA_ATAQUE)
	if not in_atk.is_empty() and main.get("_card_interaction"):
		await main._card_interaction.unmark_attackers(in_atk)


## hacha de perun: "En tu Fase Final, agrupa al portador."
static func _regroup_bearer(main: Node, card: Node, _pid: int) -> void:
	var bearer = card.get("wielder")
	if is_instance_valid(bearer):
		await _regroup(main, [bearer])


## espada de akmallah: "En tu Fase Final, agrupa tus Aliados."
static func _regroup_own_allies(main: Node, _card: Node, pid: int) -> void:
	await _regroup(main, _allies(main, pid))


## ayyappan: "Tus Aliados que porten Armas pueden ser agrupados en tu Fase Final" (opcional, los que elijas).
static func _ayyappan_regroup(main: Node, card: Node, pid: int) -> void:
	var armed: Array = _allies(main, pid).filter(func(a): return a.get("current_zone") == Constants.Zone.LINEA_ATAQUE \
		and a.get("equipped_weapons") is Array and a.equipped_weapons.any(func(w): return is_instance_valid(w)))
	if armed.is_empty():
		return
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: agrupa tus Aliados que porten Armas" % _name(card), armed, armed.size(), true)
	await _regroup(main, chosen)


## ayyappan: "...y no pueden ser Destruidos en Asignación de Daño" (BattleManager).
static func ayyappan_protects(ally: Node) -> bool:
	if not is_instance_valid(ally) or not (ally.get("equipped_weapons") is Array) \
			or not ally.equipped_weapons.any(func(w): return is_instance_valid(w)):
		return false
	return not CardQuery.cards_in_play_with(CardQuery.controller_of(ally), "tus aliados que porten armas pueden ser agrupados en tu fase final").is_empty()


## martillo mjlnir: "En tu Fase Final, si el portador hizo daño de combate este turno, puedes Desterrar hasta
## cinco cartas de un Cementerio." (meta "combat_damage_turn", GoldManager)
static func _mjolnir_final(main: Node, card: Node, pid: int) -> void:
	var bearer = card.get("wielder")
	if not is_instance_valid(bearer) or int(bearer.get_meta("combat_damage_turn", -1)) != GameManager.turn_serial:
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: Destierra hasta cinco cartas de un Cementerio" % _name(card), 0, 5)
	for pk in picks:
		var owner: int = int(pk.get("owner", pid))
		if CardManager.take_from_cemetery(owner, pk.data):
			CardManager.append_to_exile(owner, pk.data)
	if not picks.is_empty():
		main._update_debug("%s: Destierras %d carta(s) de un Cementerio" % [_name(card), picks.size()])


## cahuelche: "Cuando sea Destruido, tu oponente Bota cartas igual a la Fuerza de un Aliado en juego."
static func _cahuelche_destroyed(main: Node, card: Node, pid: int) -> void:
	var allies: Array = EnterScript._all_allies(main, func(_c): return true)
	var t: Node = await EnterScript._pick_from(main, pid, "%s: tu oponente Bota cartas igual a la Fuerza de un Aliado en juego" % _name(card), allies, false)
	if not is_instance_valid(t):
		return
	var n: int = maxi(0, int(ContinuousEffectManager.get_modified_strength(t)))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func vigilia_start_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_cemetery(pid).duplicate():
		if PULSERA_VIGILIA in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))):
			await _pulsera_vigilia(main, pid, d)
	for c in EnterScript._in_play(main, 1 - pid, func(x): return PARIS_VIGILIA in CemeteryTriggersScript.normalize(CardQuery.ability_of(x))):
		if not KeywordManager.is_silenced(c):
			await _paris_vigilia(main, c, 1 - pid)


static func _pulsera_vigilia(main: Node, pid: int, data: Dictionary) -> void:
	var name := str(data.get("nombre", "Pulsera de Energía"))
	var others: Array = CardManager.get_cemetery(pid).filter(func(x): return not is_same(x, data))
	if others.size() < 2 or not await EnterScript._confirm(main, pid, name, "Desterrar dos cartas de tu Cementerio para subirla a tu mano"):
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: Destierra dos cartas de tu Cementerio" % name, 2, 2, func(x): return not is_same(x, data))
	if picks.size() < 2:
		return
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			CardManager.append_to_exile(pid, pk.data)
	if CardManager.take_from_cemetery(pid, data):
		PlayerSideScript.put_in_hand(main, pid, data)
		main._update_debug("%s vuelve a tu mano" % name)


static func _paris_vigilia(main: Node, card: Node, pid: int) -> void:
	var options: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") in [Constants.CardType.ARMA, Constants.CardType.TOTEM] \
		and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: puedes jugar un Arma o Tótem de tu mano pagando su coste" % _name(card), options, true)
	if not is_instance_valid(chosen):
		return
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	if not await TalismanScript._play_paying(main, pid, data, int(data.get("coste", 0))):
		PlayerSideScript.put_in_hand(main, pid, data)

# =============================================================================
# OCTAVO LOTE: los últimos sin handler (Fase Final, Vigilia, daño, Agrupación, activadas sueltas)
# =============================================================================


static func _noop(_main: Node, _card: Node, _pid: int) -> void:
	pass


static func _bearer(card: Node) -> Node:
	var w = card.get("wielder")
	return w if is_instance_valid(w) else null


static func _exile_cemetery_picks(picks: Array) -> void:
	for pk in picks:
		var owner: int = int(pk.get("owner", 0))
		if CardManager.take_from_cemetery(owner, pk.data):
			CardManager.append_to_exile(owner, pk.data)


## "Destierra hasta N cartas de un/cualquier Cementerio" (uno solo).
static func _exile_from_a_cemetery(main: Node, card: Node, pid: int, n: int, min_n: int = 0, owners: Array = []) -> void:
	if owners.is_empty():
		owners = [1 - pid, pid]
	var picks: Array = await EnterScript._pick_cemetery(pid, owners, "%s: Destierra hasta %d carta(s) de un Cementerio" % [_name(card), n], min_n, n)
	_exile_cemetery_picks(picks)
	if not picks.is_empty():
		main._update_debug("%s: Destierras %d carta(s) de un Cementerio" % [_name(card), picks.size()])


static func _silence_until_next_turn(target: Node, pid: int) -> void:
	if is_instance_valid(target):
		target.set_meta("silenced_until", RuleState.next_own_turn(pid) - 1)  # KeywordManager.is_silenced
		KeywordManager._notify_abilities_changed()


static func _gold_from_castle_to_paid(main: Node, card: Node, pid: int) -> void:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: busca un Oro en tu Castillo y ponlo en tu Oro Pagado" % _name(card),
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO, 0, 1, false)
	for d in picked:
		d["esta_oculta"] = false
		await main._gold_manager.put_gold_directly_in_pagado(pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# --- Fase Final -----------------------------------------------------------------
## amuleto de thor: "puedes Desterrar la primera carta de tu Castillo para agrupar este Oro".
static func _amuleto_thor(main: Node, card: Node, pid: int) -> void:
	if card.get("current_zone") != Constants.Zone.ORO_PAGADO or CardManager.get_deck(pid).is_empty() or not main._gold_manager:
		return
	if not await EnterScript._confirm(main, pid, _name(card), "Desterrar la primera carta de tu Castillo para agrupar este Oro"):
		return
	await ActionModule.mill(pid, 1, true, _name(card))
	await main._gold_manager._agrupar_oro(pid, card)
	main._gold_manager._update_gold_display()


## atlatl: "si el portador hizo daño de combate este turno, puedes buscar un Oro en tu Castillo y ponerlo en tu Oro Pagado".
static func _atlatl(main: Node, card: Node, pid: int) -> void:
	var b := _bearer(card)
	if b and int(b.get_meta("combat_damage_turn", -1)) == GameManager.turn_serial:
		await _gold_from_castle_to_paid(main, card, pid)


## cañón naval: "puedes Botar las primeras dos carta de tu Castillo para agrupar un Oro".
static func _canon_naval_final(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or not await EnterScript._confirm(main, pid, _name(card), "Botar las dos primeras cartas de tu Castillo para agrupar un Oro"):
		return
	await ActionModule.mill(pid, 2, false, _name(card))
	await main._gold_manager.agrupar_oros(pid, 1)


## Cráneo de Cristal: "si no pusiste Oros en juego este turno, pon un Oro de tu mano o Cementerio en tu Reserva. Ese
## Oro entra en juego sin habilidad hasta tu próximo turno".
static func _craneo_cristal(main: Node, card: Node, pid: int) -> void:
	if GameManager.oro_played_this_turn or not main._gold_manager:
		return
	var is_gold := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO
	var taken := await _take_from_pools(main, pid, "%s: pon un Oro de tu mano o Cementerio en tu Reserva" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": is_gold}], is_gold)
	if taken.is_empty():
		return
	var gold: Node = await main._gold_manager.put_gold_directly_in_reserva(pid, taken.data)
	_silence_until_next_turn(gold, pid)
	main._gold_manager._update_gold_display()


## dietrich von bern: "Destierra hasta dos cartas del Cementerio oponente".
static func _dietrich(main: Node, card: Node, pid: int) -> void:
	await _exile_from_a_cemetery(main, card, pid, 2, 0, [1 - pid])


## reino de midgard: "Destierra hasta dos cartas de cualquier Cementerio" / "En la Fase Final oponente, tu oponente Bota una carta".
static func _midgard_final(main: Node, card: Node, pid: int) -> void:
	await _exile_from_a_cemetery(main, card, pid, 2)


static func _midgard_opp_final(_main: Node, card: Node, pid: int) -> void:
	await ActionModule.mill(1 - pid, 1, false, _name(card))


static func _controls_named(main: Node, pid: int, name: String) -> bool:
	return _allies(main, pid).any(func(a): return name in CemeteryTriggersScript.normalize(EnterScript._name(a)))


## fujin / raijin: "si controlas a Raijin, puedes agrupar un Oro" / "si controlas a Fujin, puedes Robar una carta".
static func _fujin(main: Node, card: Node, pid: int) -> void:
	if _controls_named(main, pid, "raijin") and main._gold_manager \
			and await EnterScript._confirm(main, pid, _name(card), "Agrupar un Oro"):
		await main._gold_manager.agrupar_oros(pid, 1)


static func _raijin(main: Node, card: Node, pid: int) -> void:
	if _controls_named(main, pid, "fujin") and await EnterScript._confirm(main, pid, _name(card), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(card), true)


## Guadaña de Santa Muerte: "si no controlas Aliados con Furia o Imbloqueable, agrupa un Oro y muestra cartas del tope de
## tu Castillo hasta mostrar un Talismán y ponlo en tu mano".
static func _guadana(main: Node, card: Node, pid: int) -> void:
	if _allies(main, pid).any(func(a): return KeywordManager.has_keyword(a, Constants.Keyword.FURIA) or KeywordManager.has_keyword(a, Constants.Keyword.IMBLOQUEABLE)):
		return
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)
	await _reveal_until_to_hand(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)


## katana kogitsunemaru: "si el portador atacó este turno, puedes agrupar una carta o Desterrar hasta cuatro cartas de los Cementerios".
static func _katana_kogitsunemaru(main: Node, card: Node, pid: int) -> void:
	var b := _bearer(card)
	if not b or int(b.get_meta("declared_attacker_turn", -1)) != GameManager.turn_serial:
		return
	var regroup := true
	if not PlayerSideScript.is_bot(pid):
		regroup = await SelectionManager.await_two_choice(main, _name(card), "Agrupar una carta", "Desterrar hasta cuatro cartas de los Cementerios", pid)
	if regroup and main._gold_manager:
		await main._gold_manager.agrupar_cartas(pid, 1)
	else:
		await _interp(card, "Destierra hasta cuatro cartas de los Cementerios", pid)


## leo: "puedes agrupar un Aliado que controles y hacer que una carta en juego pierda su habilidad hasta tu próximo turno".
static func _leo_final(main: Node, card: Node, pid: int) -> void:
	if not await EnterScript._confirm(main, pid, _name(card), "Agrupar un Aliado y que una carta pierda su habilidad"):
		return
	var atk: Array = _allies(main, pid).filter(func(a): return a.get("current_zone") == Constants.Zone.LINEA_ATAQUE)
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: agrupa un Aliado que controles" % _name(card), atk, true)
	if is_instance_valid(ally):
		await _regroup(main, [ally])
	var t: Node = await _pick_in_play(main, pid, "%s: una carta en juego pierde su habilidad hasta tu próximo turno" % _name(card), func(_c): return true)
	_silence_until_next_turn(t, pid)


## odachi: "puedes Destruir esta carta para agrupar un Oro".
static func _odachi_final(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or not await EnterScript._confirm(main, pid, _name(card), "Destruir esta carta para agrupar un Oro"):
		return
	await ActionModule.destroy([card], card, false, true)
	await main._gold_manager.agrupar_oros(pid, 1)


## rostam: "Destierra tantas cartas de un Cementerio como Fuerza tenga este Aliado".
static func _rostam_final(main: Node, card: Node, pid: int) -> void:
	# Exactamente tantas como su Fuerza (en medida de lo posible), de un Cementerio a elección.
	var n: int = maxi(0, int(ContinuousEffectManager.get_modified_strength(card)))
	var owners: Array = [1 - pid, pid].filter(func(p): return not CardManager.get_cemetery(p).is_empty())
	if n <= 0 or owners.is_empty():
		return
	var owner: int = owners[0]
	if owners.size() > 1 and not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Cementerio oponente", "Tu Cementerio", pid) else pid
	var take: int = mini(n, CardManager.get_cemetery(owner).size())
	await _exile_from_a_cemetery(main, card, pid, take, take, [owner])


## Shakar Raj: "Destierra hasta tantas cartas de un Cementerio como Aliados hayan modificado su Fuerza este turno más uno"
## (los que tienen Fuerza distinta de la impresa).
static func _shakar_raj(main: Node, card: Node, pid: int) -> void:
	# Cualquier Aliado en juego (de los dos) cuya Fuerza modificó un efecto este turno (meta "strength_mod_turn",
	# ContinuousEffectManager.register_modifier()) o con Fuerza distinta de la impresa por una continua.
	var modified: int = EnterScript._all_allies(main, func(a): return a.get("card_data") != null \
		and (int(a.get_meta("strength_mod_turn", -1)) == GameManager.turn_serial \
			or int(ContinuousEffectManager.get_modified_strength(a)) != int(a.card_data.get("fuerza", 0)))).size()
	await _exile_from_a_cemetery(main, card, pid, modified + 1)


## Snagov: "si no tienes Oros en Reserva, sube un Aliado de tu Cementerio a tu mano".
static func _snagov(main: Node, card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(pid) > 0:
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: sube un Aliado de tu Cementerio a tu mano" % _name(card), 1, 1, func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


## vorpal: "si el portador hizo daño este turno, elige un Aliado para que no pueda ser agrupado ni utilizar su habilidad
## hasta tu próximo turno. Agrupa un Oro y un Aliado que controles".
static func _vorpal(main: Node, card: Node, pid: int) -> void:
	var b := _bearer(card)
	if not b or int(b.get_meta("combat_damage_turn", -1)) != GameManager.turn_serial:
		return
	var t: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado no puede ser agrupado ni utilizar su habilidad hasta tu próximo turno" % _name(card),
		EnterScript._all_allies(main, func(_c): return true), false)
	if is_instance_valid(t):
		if CardQuery.controller_of(t) != pid:
			t.set_meta("no_regroup_turn", GameManager.turn_serial + 1)  # su próxima Agrupación (PhaseFlowController)
		_silence_until_next_turn(t, pid)
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)
	var atk: Array = _allies(main, pid).filter(func(a): return a.get("current_zone") == Constants.Zone.LINEA_ATAQUE)
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: agrupa un Aliado que controles" % _name(card), atk, false)
	if is_instance_valid(ally):
		await _regroup(main, [ally])


## zmeu: "En tu Fase Final, Destierra este Aliado".
static func _zmeu_final(_main: Node, card: Node, _pid: int) -> void:
	if card.get("current_zone") in Constants.ZONES_IN_PLAY:
		await ActionModule.banish([card], card)


## armadura imperial: "si declaraste ataque este turno, puedes Barajar y/o Desterrar hasta dos cartas de los Cementerios".
static func _armadura_final(_main: Node, card: Node, pid: int) -> void:
	if int(BattleManager.attacked_on_turn.get(pid, -1)) == GameManager.turn_serial:
		await _interp(card, "puedes Barajar y/o Desterrar hasta dos cartas de los Cementerios", pid)


## guitarra andaluza: "si no tienes Oros en tu Reserva, puedes Desterrar una carta de un Cementerio y Robar una carta".
static func _guitarra_final(main: Node, card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(pid) > 0 or not await EnterScript._confirm(main, pid, _name(card), "Desterrar una carta de un Cementerio y Robar una carta"):
		return
	await _exile_from_a_cemetery(main, card, pid, 1, 1)
	await ActionModule.draw(pid, 1, _name(card), true)


## Gehena (su Fase Final) y Azi Demoniaco (el Oro): ya resueltos por el intérprete o aquí.
static func _gehena_final(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)
	await ActionModule.draw(pid, 1, _name(card), true)


static func _azi_gold_final(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [1 - pid, pid], "%s: Baraja o Destierra una carta de un Cementerio" % _name(card), 1, 1)
	for pk in picks:
		var owner: int = int(pk.owner)
		var shuffle := false
		if not PlayerSideScript.is_bot(pid):
			shuffle = await SelectionManager.await_two_choice(main, _name(card), "Barajarla en su Castillo", "Desterrarla", pid)
		if CardManager.take_from_cemetery(owner, pk.data):
			if shuffle:
				pk.data["esta_oculta"] = true
				CardManager.get_deck(owner).append(pk.data)
				CardManager.shuffle_deck(owner)
			else:
				CardManager.append_to_exile(owner, pk.data)


## Los Señalados: "En la Fase Final, si hizo daño al Castillo oponente, gana uno de Fuerza permanentemente" (meta
## "castle_damage_turn", GoldManager). turn_end_extras() lo llama en la Fase Final de su controlador.
static func _senalados(_main: Node, card: Node, _pid: int) -> void:
	if GameManager.current_phase == Constants.Phase.FINAL and int(card.get_meta("castle_damage_turn", -1)) == GameManager.turn_serial:
		_buff(card, card, 1, true)


# --- Activadas -------------------------------------------------------------------
## Azi Demoniaco: "convierte este Aliado hasta tu próximo turno en un Oro con la habilidad "..." y ponlo en tu Oro Pagado".
static func _azi_demoniaco(main: Node, card: Node, _pid: int) -> void:
	if main._gold_manager and card.get("current_zone") in Constants.ZONES_IN_PLAY:
		await main._gold_manager.convert_ally_to_gold_until_next_turn(card, _quoted_any(card))


static func _quoted_any(card: Node) -> String:
	var m := RegEx.create_from_string("[\"“”]([^\"“”]+)[\"“”]").search(str(card.card_data.get("habilidad", "")))
	return m.get_string(1) if m else ""


## chamuel: "tu oponente Bota tantas cartas como coste tenga una carta en juego".
static func _chamuel(main: Node, card: Node, pid: int) -> void:
	var t: Node = await _pick_in_play(main, pid, "%s: tu oponente Bota tantas cartas como coste tenga una carta en juego" % _name(card),
		func(c): return c.get("card_type") != Constants.CardType.ORO, false)
	if is_instance_valid(t) and EnterScript._cost(t) > 0:
		await ActionModule.mill(1 - pid, EnterScript._cost(t), false, _name(card))


## cueva de montesinos: "Puedes Destruirlo para que tu oponente Bote cuatro cartas o Descarte una carta" (eliges tú).
static func _cueva_montesinos(main: Node, card: Node, pid: int) -> void:
	if card.get("current_zone") in Constants.ZONES_IN_PLAY:
		await ActionModule.destroy([card], card, false, true)
	var mill := true
	if not PlayerSideScript.is_bot(pid):
		mill = await SelectionManager.await_two_choice(main, _name(card), "Tu oponente Bota cuatro cartas", "Tu oponente Descarta una carta", pid)
	if mill:
		await ActionModule.mill(1 - pid, 4, false, _name(card))
	else:
		await EnterScript._discard_own(main, card, 1 - pid, 1)


## ebikame: "ganar el control de una carta de coste 2 o menos. Si es un Aliado gana Furia. En tu Fase Final, Baraja esa carta".
static func _ebikame(main: Node, card: Node, pid: int) -> void:
	var t: Node = await _pick_in_play(main, pid, "%s: gana el control de una carta de coste 2 o menos" % _name(card),
		func(c): return CardQuery.controller_of(c) != pid and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if not is_instance_valid(t):
		return
	ContinuousEffectManager.gain_control_of_card(t, pid)
	if CardQuery.controller_of(t) != pid:
		return
	if t.get("card_type") == Constants.CardType.ALIADO:
		KeywordManager.grant_keyword(t, Constants.Keyword.FURIA, card, "permanent")
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		if is_instance_valid(t) and t.get("current_zone") in Constants.ZONES_IN_PLAY:
			var owner: int = int(t.owner_id) if t.get("owner_id") != null else pid
			await ActionModule.return_to_deck(t, owner, false, card)
			ActionModule.shuffle_deck(owner))


## Gehena: "mirar la mano de tu oponente y nombrar dos cartas que no sean Talismán. Busca una de ellas en el Castillo
## oponente y Destiérrala y busca la otra en tu Castillo y ponla en tu mano".
static func _gehena(main: Node, card: Node, pid: int) -> void:
	var opp_hand: Array = PlayerSideScript.hand_cards(main, 1 - pid).filter(func(c): return is_instance_valid(c)).map(func(c): return c.card_data)
	if not EffectController.fision_hides_zones_of(1 - pid, pid, Constants.Zone.MANO) and not opp_hand.is_empty() and not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(opp_hand, "%s: la mano de tu oponente" % _name(card), pid)
		await SelectionManager.selection_completed
	var names: Array = []
	for i in 2:
		var named := ""
		if PlayerSideScript.is_bot(pid):
			var pool: Array = CardManager.get_deck(1 - pid) if i == 0 else CardManager.get_deck(pid)
			for d in pool:
				if int(d.get("tipo", -1)) != Constants.CardType.TALISMAN:
					named = str(d.get("nombre", ""))
					break
		else:
			var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait("%s: nombra una carta que no sea Talismán (%d de 2)" % [_name(card), i + 1], pid)
			if int(picked.get("tipo", -1)) == Constants.CardType.TALISMAN:
				main._update_debug("%s: no puedes nombrar Talismanes" % _name(card))
				return
			named = str(picked.get("nombre", ""))
		if named.is_empty():
			return
		names.append(named)
	var to_exile: int = 0
	if not PlayerSideScript.is_bot(pid):
		to_exile = await SelectionManager.await_choice(main, "%s: ¿cuál buscas en el Castillo oponente para Desterrarla?" % _name(card), names, pid)
	to_exile = clampi(to_exile, 0, 1)
	var exile_name: String = names[to_exile]
	var hand_name: String = names[1 - to_exile]
	var found: Array = await AttackScript._pick_from_castle(1 - pid, pid, "%s: busca %s en el Castillo oponente" % [_name(card), exile_name],
		func(d): return str(d.get("nombre", "")) == exile_name, 0, 1, false)
	for d in found:
		d["esta_oculta"] = false
		CardManager.append_to_exile(1 - pid, d)
	var mine: Array = await AttackScript._pick_from_castle(pid, pid, "%s: busca %s en tu Castillo" % [_name(card), hand_name],
		func(d): return str(d.get("nombre", "")) == hand_name, 0, 1, false)
	for d in mine:
		PlayerSideScript.put_in_hand(main, pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


## guitarra andaluza: "buscar una carta que no sea Talismán en un Castillo y ponla en el tope o fondo del Castillo de su dueño".
static func _guitarra_andaluza(main: Node, card: Node, pid: int) -> void:
	var owner: int = pid
	if not PlayerSideScript.is_bot(pid):
		owner = pid if await SelectionManager.await_two_choice(main, _name(card), "Buscar en tu Castillo", "Buscar en el Castillo oponente", pid) else 1 - pid
	var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: busca una carta que no sea Talismán" % _name(card),
		func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN, 0, 1, false)
	if picked.is_empty():
		return
	var top := true
	if not PlayerSideScript.is_bot(pid):
		top = await SelectionManager.await_two_choice(main, _name(card), "Ponerla en el tope", "Ponerla en el fondo", pid)
	var d: Dictionary = picked[0]
	d["esta_oculta"] = true
	var deck: Array = CardManager.get_deck(owner)
	if top:
		deck.push_front(d)
	else:
		deck.append(d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


## Gurzil: "Si atacaste en tu anterior turno puedes pagar dos Oros para jugarlo sin pagar su coste".
static func _gurzil(main: Node, card: Node, pid: int) -> void:
	if not BattleManager.attacked_in_previous_own_turn(pid):
		main._update_debug("%s: no atacaste en tu turno anterior" % _name(card))
		return
	if not await _pay_gold(main, pid, 2):
		return
	await _play_self(main, card, pid, 0)


## hrunting: "mostrar cuatro cartas del tope de tu Castillo. El portador gana tanta Fuerza como sumen sus costes por el
## turno, devuélvelas en cualquier orden y Roba una carta".
static func _hrunting(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var shown: Array = deck.slice(0, 4)
	var total := 0
	for d in shown:
		total += int(d.get("coste", 0)) if int(d.get("tipo", -1)) != Constants.CardType.ORO else 0
	RevealedCardsScript.record(pid, shown, _name(card))
	main._update_debug("%s muestra %s (suman %d)" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?")))), total])
	var b := _bearer(card)
	if b and total > 0:
		_buff(b, card, total)
	await CastleLookScript.look(pid, pid, shown.size(), true, CastleLookScript.rest_box(true), "%s: devuélvelas en cualquier orden" % _name(card))
	await ActionModule.draw(pid, 1, _name(card), true)


## Lanza de Exorcista: "Desterrar cartas oponentes cuyos costes sumen hasta 3" (Oros no: no tienen coste).
static func _lanza_exorcista(main: Node, card: Node, pid: int) -> void:
	var budget := 3
	var chosen: Array = []
	while budget > 0:
		var options: Array = EnterScript._in_play(main, 1 - pid,
			func(c): return c.get("card_type") != Constants.CardType.ORO and not (c in chosen) and EnterScript._cost(c) <= budget)
		var t: Node = await EnterScript._pick_from(main, pid, "%s: Destierra cartas oponentes cuyos costes sumen hasta 3 (quedan %d)" % [_name(card), budget], options, true)
		if not is_instance_valid(t):
			break
		chosen.append(t)
		budget -= EnterScript._cost(t)
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card)


# --- Daño ------------------------------------------------------------------------
## escorpio: "un oponente Destierra la primera carta de su Castillo por cada carta en su mano".
static func _escorpio_damage(main: Node, card: Node, pid: int) -> void:
	var n: int = EnterScript._hand(main, 1 - pid).size()
	if n > 0:
		await ActionModule.mill(1 - pid, n, true, _name(card))


## malafar sp: "puedes Robar una carta y un jugador debe Descartar una carta de su mano".
static func _malafar(main: Node, card: Node, pid: int) -> void:
	if not await EnterScript._confirm(main, pid, _name(card), "Robar una carta y que un jugador Descarte una"):
		return
	await ActionModule.draw(pid, 1, _name(card), true)
	var victim: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		victim = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Descarta tu oponente", "Descartas tú", pid) else pid
	await EnterScript._discard_own(main, card, victim, 1)


## nagaraja: "Si porta Armas, cuando haga daño por primera vez en el juego, el primer Aliado o Tótem que juegue tu oponente
## en su próximo turno entra en juego bajo tu control" (GoldManager lo aplica al entrar en juego).
static func _nagaraja(main: Node, card: Node, pid: int) -> void:
	if card.get_meta("nagaraja_used", false) or not (card.get("equipped_weapons") is Array and card.equipped_weapons.any(func(w): return is_instance_valid(w))):
		return
	card.set_meta("nagaraja_used", true)
	var opp_next: int = GameManager.turn_serial + (1 if GameManager.active_player_id == pid else 2)
	RuleState.set_turn_data("nagaraja_steal:%d" % (1 - pid), {})
	RuleState.set_pending("nagaraja_steal", 1 - pid, {"thief": pid, "turn": opp_next})
	main._update_debug("%s: el primer Aliado o Tótem que juegue tu oponente en su próximo turno entra bajo tu control" % _name(card))


static func nagaraja_on_entered(pid: int, node: Node) -> void:
	if not RuleState.has_pending("nagaraja_steal", pid) or not is_instance_valid(node) \
			or not (node.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM]):
		return
	var info = RuleState.take_pending("nagaraja_steal", pid)
	if not (info is Dictionary) or int(info.get("turn", -1)) != GameManager.turn_serial:
		if info is Dictionary and int(info.get("turn", -1)) > GameManager.turn_serial:
			RuleState.set_pending("nagaraja_steal", pid, info)  # todavía no es su próximo turno
		return
	ContinuousEffectManager.gain_control_of_card(node, int(info.thief))


## vinci y yang: "tu oponente elige entre Descartar dos cartas o una carta al azar".
static func _vinci_yang(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var hand: Array = EnterScript._hand(main, opp)
	if hand.is_empty():
		return
	var two := false
	if not PlayerSideScript.is_bot(opp):
		two = await SelectionManager.await_two_choice(main, _name(card), "Descartar dos cartas", "Descartar una carta al azar", opp)
	if two:
		await EnterScript._discard_own(main, card, opp, 2)
	else:
		await ActionModule.discard(opp, [hand[randi() % hand.size()]], _name(card), true)


# --- Vigilia, Fase Final oponente, comienzo de turno, Destruido, Agrupación ----------
## salmon del saber: "Al comienzo de tu Vigilia, Roba hasta tener dos cartas en tu mano".
static func _salmon(main: Node, card: Node, pid: int) -> void:
	var n: int = 2 - EnterScript._hand(main, pid).size()
	if n > 0:
		await ActionModule.draw(pid, n, _name(card), true)


## shakuhachi: "puedes jugar un Talismán de tu Cementerio pagando su coste y Destiérralo".
static func _shakuhachi(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega un Talismán de tu Cementerio pagando su coste (luego se Destierra)" % _name(card), 0, 1, ok)
	for pk in picks:
		if not CardManager.take_from_cemetery(pid, pk.data):
			continue
		var price: int = int(pk.data.get("coste", 0))
		if price > 0 and not await PlayerSideScript.pay(main, pid, price):
			CardManager.add_to_cemetery(pid, pk.data)
			continue
		pk.data["esta_oculta"] = false
		await main._gold_manager.play_card_for_free(pk.data, pid, true)


## armadura imperial: "si tu oponente tiene dos o más Oros en Reserva, puedes generar un Oro para jugar Aliados".
static func _armadura_vigilia(main: Node, _card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(1 - pid) >= 2 and main._gold_manager:
		main._gold_manager.generar_oro_virtual_restringido(1, func(t: int, _r: String, _c: int) -> bool: return t == Constants.CardType.ALIADO,
			"Aliados", pid)


## Amuleto de Serpiente: la misma habilidad que al entrar en juego.
static func _amuleto_serpiente_vigilia(main: Node, card: Node, pid: int) -> void:
	await EnterScript._amuleto_serpiente(main, card, pid)


## incienso sagrado: "En la Fase Final oponente, si no controlas Aliados, puedes subir un Aliado de tu Cementerio a tu mano".
static func _incienso(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).is_empty():
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: sube un Aliado de tu Cementerio a tu mano" % _name(card), 0, 1, func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


## Armería del Guerrero: "Al comienzo del turno oponente, Baraja y/o Destierra hasta dos cartas de los Cementerios".
static func _armeria(_main: Node, card: Node, pid: int) -> void:
	await _interp(card, "Baraja y/o Destierra hasta dos cartas de los Cementerios", pid)


## trapezoedro: "Si al comienzo del turno no tenías Oros en Reserva, cuando tu oponente ponga en juego su tercera carta en
## el turno, agrupa un Oro" (GoldManager: on_turn_start_trapezoedro / on_card_put_trapezoedro).
static func trapezoedro_turn_start() -> void:
	for p in [0, 1]:
		var armed: bool = GameState.get_oro_reserva(p) == 0 and not CardQuery.cards_in_play_with(p, "cuando tu oponente ponga en juego su tercera carta en el turno, agrupa un oro").is_empty()
		RuleState.set_turn_data("trapezoedro:%d" % p, {"armed": armed, "done": false} if armed else {})


static func trapezoedro_on_put(main: Node, putter: int) -> void:
	var p: int = 1 - putter
	var td: Dictionary = RuleState.turn_data("trapezoedro:%d" % p)
	if td.is_empty() or td.get("done", false):
		return
	RuleState.add("trapezoedro_put", putter)
	if RuleState.count("trapezoedro_put", putter) == 3 and main._gold_manager:
		td["done"] = true
		RuleState.set_turn_data("trapezoedro:%d" % p, td)
		await main._gold_manager.agrupar_oros(p, 1)
		main._update_debug("trapezoedro: tu oponente puso en juego su tercera carta, agrupas un Oro")


## caicai vilu: "Cuando sea Destruido, súbelo a tu mano".
static func _caicai_destroyed(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var d: Dictionary = _find_data(CardManager.get_cemetery(owner), card.card_data)
	if not d.is_empty() and CardManager.take_from_cemetery(owner, d):
		PlayerSideScript.put_in_hand(main, owner, d)


## tesoro del santiaguillo: "Cuando sea Destruido, puedes convertirlo en un Aliado de Fuerza 1 con la habilidad "...""
## (vuelve del Cementerio a juego como ese Aliado).
static func _santiaguillo_destroyed(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var d: Dictionary = _find_data(CardManager.get_cemetery(owner), card.card_data)
	if d.is_empty() or not main._gold_manager or not await EnterScript._confirm(main, pid, _name(card), "Convertirlo en un Aliado de Fuerza 1"):
		return
	var ability := _quoted_any(card)
	if not CardManager.take_from_cemetery(owner, d):
		return
	var ally_data: Dictionary = d.duplicate()
	ally_data["tipo"] = Constants.CardType.ALIADO
	ally_data["fuerza"] = 1
	ally_data["habilidad"] = ability
	var node: Node = await _put_into_play(main, pid, ally_data, owner)
	if is_instance_valid(node):
		node.is_converted = true


## Cartas en el Cementerio con disparo al comienzo de tu Vigilia / Agrupación (data-based).
static func _discard_or_exile_to_raise(main: Node, pid: int, data: Dictionary, cost: String) -> void:
	var name := str(data.get("nombre", "Carta"))
	if cost == "discard":
		var hand: Array = EnterScript._hand(main, pid)
		if hand.is_empty() or not await EnterScript._confirm(main, pid, name, "Descartar una carta para subirla de tu Cementerio a tu mano"):
			return
		var pick: Node = await EnterScript._pick_from(main, pid, "%s: Descarta una carta" % name, hand, true)
		if not is_instance_valid(pick):
			return
		await ActionModule.discard(pid, [pick], name, true)
	else:
		var others: Array = CardManager.get_cemetery(pid).filter(func(x): return not is_same(x, data))
		if others.is_empty() or not await EnterScript._confirm(main, pid, name, "Desterrar otra carta de tu Cementerio para ponerla en tu mano"):
			return
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: Destierra otra carta de tu Cementerio" % name, 1, 1, func(x): return not is_same(x, data))
		if picks.is_empty():
			return
		_exile_cemetery_picks(picks)
	if CardManager.take_from_cemetery(pid, data):
		PlayerSideScript.put_in_hand(main, pid, data)


static func vigilia_cemetery_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_cemetery(pid).duplicate():
		var t := CemeteryTriggersScript.normalize(str(d.get("habilidad", "")))
		if COMPENDIUM_VIGILIA in t:
			await _discard_or_exile_to_raise(main, pid, d, "exile")
		elif GUMYOCHO_VIGILIA in t and _allies(main, pid).filter(func(a): return EnterScript._cost(a) >= 1).size() >= 3 \
				and await EnterScript._confirm(main, pid, str(d.get("nombre", "")), "Jugarlo de tu Cementerio sin pagar su coste"):
			if CardManager.take_from_cemetery(pid, d):
				d["esta_oculta"] = false
				await main._gold_manager.play_card_for_free(d, pid)
	# veinte mil leguas de viaje submarino: "Al comienzo de la Vigilia" (de cualquiera), en juego o en tu Cementerio.
	for p in [0, 1]:
		var sources: Array = CardManager.get_cemetery(p).filter(func(x): return VEINTE_MIL_VIGILIA in CemeteryTriggersScript.normalize(str(x.get("habilidad", ""))))
		sources.append_array(CardQuery.cards_in_play_with(p, VEINTE_MIL_VIGILIA))
		if sources.is_empty():
			continue
		var golds: Array = CardManager.get_cemetery(p).filter(func(x): return int(x.get("tipo", -1)) == Constants.CardType.ORO)
		if golds.is_empty() or EnterScript._hand(main, p).is_empty():
			continue
		var hand: Array = EnterScript._hand(main, p)
		if not await EnterScript._confirm(main, p, "veinte mil leguas de viaje submarino", "Descartar una carta para subir un Oro de tu Cementerio a tu mano"):
			continue
		var pick: Node = await EnterScript._pick_from(main, p, "Descarta una carta", hand, true)
		if not is_instance_valid(pick):
			continue
		await ActionModule.discard(p, [pick], "veinte mil leguas de viaje submarino", true)
		var gp: Array = await EnterScript._pick_cemetery(p, [p], "Sube un Oro de tu Cementerio a tu mano", 1, 1, func(x): return int(x.get("tipo", -1)) == Constants.CardType.ORO)
		for pk in gp:
			if CardManager.take_from_cemetery(p, pk.data):
				PlayerSideScript.put_in_hand(main, p, pk.data)


static func agrupacion_cemetery_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_cemetery(pid).duplicate():
		if ORIGENES_AGRUPACION in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))):
			await _discard_or_exile_to_raise(main, pid, d, "discard")


## Fase Final: miroku (en tu Destierro) y Los Señalados ("En la Fase Final", sin "tu").
static func turn_end_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_exile(pid).duplicate():
		if "en tu fase final, si esta en tu destierro, puedes ver las primeras tres cartas de tu castillo y ordenarlas" in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))) \
				and not CardManager.get_deck(pid).is_empty() and await EnterScript._confirm(main, pid, str(d.get("nombre", "")), "Ver las primeras tres cartas de tu Castillo y ordenarlas"):
			await CastleLookScript.look(pid, pid, 3, true, CastleLookScript.rest_box(true), "%s: ordena las primeras tres cartas de tu Castillo" % str(d.get("nombre", "")))
	for a in CardQuery.cards_in_play_with(pid, "en la fase final, si hizo daño al castillo oponente, gana uno de fuerza permanentemente"):
		_senalados(main, a, pid)
