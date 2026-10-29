extends "res://scripts/core/effects/mechanics/EnterPatternsCartas.gd"
## EnterPatternsLote2 — familia Lote2 de EnterPatterns.gd (ver EnterPatternsBase.gd).


# =============================================================================
# SEGUNDO LOTE
# =============================================================================


## Elige cartas de Cementerios (pick_in_zones). 'owners' = de quién se ofrecen. Devuelve [{owner, data}].
static func _pick_cemetery(pid: int, owners: Array, title: String, min_count: int, max_count: int,
		eligible: Callable = Callable()) -> Array:
	var pools: Array = []
	for p in owners:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": not eligible.is_valid() or eligible.call(d)})})
	if not pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		return []
	var raw: Array = await ActionModule.pick_in_zones(pid, title, pools, min_count, max_count)
	var out: Array = []
	for rp in raw:
		if not (rp is Array) or rp.size() != 2:
			continue
		var pi := int(rp[0])
		var ci := int(rp[1])
		if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			continue
		var d: Dictionary = pools[pi].cards[ci].data
		if out.size() < max_count and not out.any(func(o): return is_same(o.data, d)):
			out.append({"owner": owners[pi], "data": d})
	return out


## Cada jugador Bota per_player(jugador) cartas; si se Botaron Oros, uno de un Cementerio a tu Oro Pagado.
static func _mill_milled_gold_to_paid(main: Node, card: Node, pid: int, per_player: Callable) -> void:
	var milled_gold := false
	for p in [pid, 1 - pid]:
		var n: int = per_player.call(p)
		if n <= 0:
			continue
		var res: Dictionary = await ActionModule.mill(p, n, false, _name(card))
		for d in res.get("cards", []):
			if d is Dictionary and int(d.get("tipo", -1)) == Constants.CardType.ORO:
				milled_gold = true
	if not milled_gold or not main._gold_manager:
		return
	var picks := await _pick_cemetery(pid, [pid, 1 - pid], "%s: pon un Oro de un Cementerio en tu Oro Pagado" % _name(card), 1, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, pk.data)
			if is_instance_valid(gold):
				gold.owner_id = pk.owner


static func _set_strength_turn(target: Node, value: int, label: String) -> void:
	ContinuousEffectManager.register_modifier({
		"source": target, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": value, "operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": label,
	})
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()


## Cam / el cazador: pierden su habilidad, ganan Indestructible y tienen Fuerza 0 por el turno.
static func _blank_indestructible_zero(card: Node, targets: Array) -> void:
	for t in targets:
		if not is_instance_valid(t):
			continue
		await KeywordManager.silence_card(t, card, "turn")
		KeywordManager.grant_keyword(t, Constants.Keyword.INDESTRUCTIBLE, card, "turn")
		_set_strength_turn(t, 0, "%s: Fuerza 0" % _name(card))


static func _all_allies(main: Node, filter: Callable = Callable()) -> Array:
	var out: Array = []
	for side in [0, 1]:
		out.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
			and (not filter.is_valid() or filter.call(c))))
	return out


static func _mahishi(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(1 - pid)
	if deck.is_empty() or await _window(card, pid):
		return
	var node: Node = await LeavePlayScript._ally_from_data(main, deck.pop_front(), 1 - pid, pid, card, 3, [], "Sombra")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	main._update_debug("%s: %s es ahora tu Aliado Sombra de Fuerza 3 sin habilidad" % [_name(card), _name(node)])


static func _shikhandi(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados hacen el doble de daño por el turno" % _name(card),
		_in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO), 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	for c in chosen:
		if is_instance_valid(c):
			c.set_meta("double_combat_damage_turn", GameManager.turn_serial)  # BattleManager


static func _eurytus(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Subir una carta oponente a la mano de su dueño"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta oponente de coste 2 o menos" % _name(card), rivals, true)
	if target and not await _window(card, pid):
		await bounce_to_owner_hand(main, target, card)


static func _los_umbras(main: Node, card: Node, pid: int) -> void:
	if not _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO).is_empty():
		return
	if not await _window(card, pid):
		await ActionModule.mill(pid, 2, false, _name(card))


static func _hospital(main: Node, card: Node, pid: int) -> void:
	var cem: Array = CardManager.get_cemetery(1 - pid)
	if cem.is_empty() or not await _confirm(main, pid, _name(card), "Desterrar el Cementerio de tu oponente") or await _window(card, pid):
		return
	for d in cem.duplicate():
		if CardManager.take_from_cemetery(1 - pid, d):
			CardManager.append_to_exile(1 - pid, d)


static func _escudo_energia(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or await _window(card, pid):
		return
	var from_top := true
	if not PlayerSideScript.is_bot(pid):
		from_top = await SelectionManager.await_two_choice(main, _name(card), "Del tope", "Del fondo", pid)
	for _i in mini(2, deck.size()):
		PlayerSideScript.put_in_hand(main, pid, deck.pop_front() if from_top else deck.pop_back())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _templo_uppsala(_main: Node, card: Node, pid: int) -> void:
	if CardManager.get_deck(1 - pid).is_empty() or await _window(card, pid):
		return
	await ActionModule.search(1 - pid, Constants.Zone.CASTILLO, {}, 2, true, false, false, card, Constants.Zone.DESTIERRO, false, pid)


static func _orcus(main: Node, card: Node, pid: int) -> void:
	var n: int = _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and "sombra" in CemeteryTriggersScript.normalize(str(c.get("card_raza")))).size()
	if n <= 0 or CardManager.get_deck(1 - pid).is_empty() \
			or not await _confirm(main, pid, _name(card), "Buscar %d carta(s) en el Castillo oponente" % n) or await _window(card, pid):
		return
	await ActionModule.search(1 - pid, Constants.Zone.CASTILLO, {}, n, true, false, false, card, Constants.Zone.DESTIERRO, false, pid)


static func _libra(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar un Oro en un Castillo para tu Oro Pagado") or await _window(card, pid):
		return
	await ActionModule.search_either_owner(pid, [Constants.Zone.CASTILLO], {"type": Constants.CardType.ORO}, 1, true, card,
		Constants.Zone.ORO_PAGADO)


static func _vaku(main: Node, card: Node, pid: int) -> void:
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.TOTEM))
		targets.append_array(CardQuery.weapons_in_play(side))
	targets = targets.filter(func(c): return is_instance_valid(c) and (not PlayerSideScript.is_bot(pid) or CardQuery.controller_of(c) != pid))
	var chosen: Array = await _pick_many(main, pid, "%s: puedes Desterrar hasta dos Tótem o Armas" % _name(card), targets, 2, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.banish(chosen, card, true)


static func _escorpio(main: Node, card: Node, pid: int) -> void:
	var lines: Array = PlayerSideScript.ally_containers(main, 1 - pid)
	if lines.size() < 2:
		return
	var targets: Array = lines[1].get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Array = await _pick_many(main, pid, "%s: Destierra hasta tres Aliados de la Línea de Ataque oponente" % _name(card), targets, 3, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.banish(chosen, card, true)


static func _discard_own(main: Node, card: Node, pid: int, count: int) -> void:
	var hand := _hand(main, pid)
	if hand.is_empty():
		return
	var to_discard: Array = hand
	if hand.size() > count:
		if PlayerSideScript.is_bot(pid):
			hand.sort_custom(func(a, b): return int(a.get("card_cost")) < int(b.get("card_cost")))
			to_discard = hand.slice(0, count)
		else:
			to_discard = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, count, pid)
	if not to_discard.is_empty():
		await ActionModule.discard(pid, to_discard.slice(0, count), _name(card), true)


static func _chon_chon(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Robar tres, Descartar dos y Desterrar tres del tope de un Castillo") or await _window(card, pid):
		return
	await ActionModule.draw(pid, 3, _name(card), true)
	await _discard_own(main, card, pid, 2)
	var castle_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		castle_owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	await ActionModule.mill(castle_owner, 3, true, _name(card))


static func _samael(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var small: Array = []
	for side in [1 - pid, pid]:
		small.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
			and ContinuousEffectManager.cost_at_most(c, 1)))
	var one: Array = await _pick_many(main, pid, "%s: Destierra hasta una carta de coste 1 o menos" % _name(card), small, 1, true)
	if not one.is_empty():
		await ActionModule.banish(one, card, true)
	var picks := await _pick_cemetery(pid, [1 - pid, pid], "%s: Destierra hasta dos cartas de un Cementerio" % _name(card), 0, 2)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			CardManager.append_to_exile(pk.owner, pk.data)
	var castle_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		castle_owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: dos cartas del fondo de un Castillo" % _name(card),
			"Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(castle_owner)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(castle_owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _tauro(main: Node, card: Node, pid: int) -> void:
	var mine: int = _hand(main, pid).size()
	var theirs: int = _hand(main, 1 - pid).size()
	var n: int = maxi(mine, theirs)
	if not PlayerSideScript.is_bot(pid):
		n = mine if await SelectionManager.await_two_choice(main, "%s: tu oponente Bota una carta por cada carta en la mano de…" % _name(card),
			"Tu mano (%d)" % mine, "Su mano (%d)" % theirs, pid) else theirs
	if n > 0 and not await _window(card, pid):
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _vordenburg(main: Node, card: Node, pid: int) -> void:
	var allies := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if PlayerSideScript.is_bot(pid):
		allies.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var ally: Node = await _pick_from(main, pid, "%s: elige un Aliado que controles (su Fuerza)" % _name(card), allies, false)
	var n: int = (int(ContinuousEffectManager.get_modified_strength(ally)) if is_instance_valid(ally) else 0) + CardQuery.weapons_in_play(pid).size()
	if n > 0 and not await _window(card, pid):
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _wyrm(main: Node, card: Node, pid: int) -> void:
	if _golds(main, [pid]).size() < 7:
		return
	var n: int = _golds(main, [0, 1]).size()
	if not await _window(card, pid):
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _randolph(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var opp: int = 1 - pid
	# Jugar cartas: oros_mas_modifiers se vacía al empezar el próximo turno. Habilidades: TriggerTollPatterns.
	PaymentManager.agregar_oros_mas(card, 1, func(c: Node) -> bool: return c.get("owner_id") != null and int(c.owner_id) == opp)
	RuleState.set_until("any_ability_toll", opp, GameManager.turn_serial + 1)
	main._update_debug("%s: a tu oponente le cuesta un Oro más jugar cartas o utilizar habilidades este turno" % _name(card))


static func _serafin(main: Node, card: Node, pid: int) -> void:
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var rivals := _in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return _cost(a) > _cost(b))
		named = _name(rivals[0]) if not rivals.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"%s: nombra una carta: utilizar sus habilidades cuesta un Oro más hasta tu próximo turno" % _name(card), pid)
		named = str(picked.get("nombre", ""))
	if named.is_empty() or await _window(card, pid):
		return
	for p in [0, 1]:
		RuleState.set_until("name_ability_toll:" + named.to_lower(), p, RuleState.next_own_turn(pid))
	main._update_debug("%s: utilizar habilidades de %s cuesta un Oro más hasta tu próximo turno" % [_name(card), named])


static func _cam(main: Node, card: Node, pid: int) -> void:
	var protect := true
	if not PlayerSideScript.is_bot(pid):
		protect = await SelectionManager.await_two_choice(main, _name(card), "Un Aliado no puede salir del juego",
			"Hasta dos Aliados: Indestructible, sin habilidad y Fuerza 0", pid)
	if protect:
		var ally: Node = await _pick_from(main, pid, "%s: un Aliado no puede salir del juego hasta tu próximo turno" % _name(card),
			_all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)), false)
		if is_instance_valid(ally) and not await _window(card, pid):
			EffectController.add_single_card_leave_play_immunity(ally, pid)
		return
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados" % _name(card), _all_allies(main), 2, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await _blank_indestructible_zero(card, chosen)


static func _el_cazador(main: Node, card: Node, pid: int) -> void:
	var targets := _all_allies(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	if PlayerSideScript.is_bot(pid):
		targets = targets.filter(func(c): return CardQuery.controller_of(c) != pid)
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados de coste 2 o menos" % _name(card), targets, 2, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await _blank_indestructible_zero(card, chosen)


static func _abdul(main: Node, card: Node, pid: int) -> void:
	var rivals := _all_allies(main, func(c): return CardQuery.controller_of(c) != pid or not PlayerSideScript.is_bot(pid))
	var target: Node = await _pick_from(main, pid,
		"%s: un Aliado no puede atacar ni bloquear hasta la Fase Final de tu próximo turno" % _name(card), rivals, false)
	if not is_instance_valid(target) or await _window(card, pid):
		return
	# Fines de turno hasta la Fase Final de tu próximo turno incluida.
	var turns: int = 3 if GameManager.active_player_id == pid else 2
	for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
		ContinuousEffectManager.register_modifier({
			"source": target, "target": target, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
			"restriction_type": restriction, "duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": turns,
			"description": "%s: no ataca ni bloquea" % _name(card),
		})


static func _altar(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados ganan o pierden 2 de Fuerza permanentemente" % _name(card),
		_all_allies(main), 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	for c in chosen:
		if not is_instance_valid(c) or await EffectController.offer_prevention(c, card, "strength_change"):
			continue
		var gain: bool = CardQuery.controller_of(c) == pid
		if not PlayerSideScript.is_bot(pid):
			gain = await SelectionManager.await_two_choice(main, "%s: %s" % [_name(card), _name(c)], "Gana 2 de Fuerza", "Pierde 2 de Fuerza", pid)
		ContinuousEffectManager.register_modifier({
			"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 2 if gain else -2, "operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY, "description": "%s %+d" % [_name(card), 2 if gain else -2],
		})
		if c.has_method("refresh_strength_badge"):
			c.refresh_strength_badge()


static func _casimiro(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for i in 2:
		var source := 3  # 0 tu Cementerio, 1 Cementerio oponente, 2 tope de tu Castillo, 3 tope del Castillo oponente
		if not PlayerSideScript.is_bot(pid):
			source = await SelectionManager.await_choice(main, "%s: carta %d de 2, ¿de dónde?" % [_name(card), i + 1],
				["Tu Cementerio", "Cementerio oponente", "Tope de tu Castillo", "Tope del Castillo oponente"], pid)
		var owner: int = pid if source in [0, 2] else 1 - pid
		var data: Dictionary = {}
		if source >= 2:
			var deck: Array = CardManager.get_deck(owner)
			if deck.is_empty():
				continue
			data = deck.pop_front()
		else:
			var picks := await _pick_cemetery(pid, [owner], "%s: elige una carta del Cementerio" % _name(card), 1, 1)
			if picks.is_empty() or not CardManager.take_from_cemetery(owner, picks[0].data):
				continue
			data = picks[0].data
		await LeavePlayScript._ally_from_data(main, data, owner, pid, card, 2, [], "")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _plaga_inmunda(main: Node, card: Node, pid: int) -> void:
	var picks := await _pick_cemetery(pid, [pid], "%s: hasta dos cartas de tu Cementerio como Aliados de Fuerza 1 sin habilidad" % _name(card), 0, 2)
	if picks.is_empty() or await _window(card, pid):
		return
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			await LeavePlayScript._ally_from_data(main, pk.data, pid, pid, card, 1, [], "")


static func _luthairon(main: Node, card: Node, pid: int) -> void:
	var wielder = card.get_parent()
	var n: int = _cost(wielder) if is_instance_valid(wielder) and wielder.get("equipped_weapons") is Array else 0
	if n <= 0:
		return
	var amount := n
	if not PlayerSideScript.is_bot(pid):
		var options: Array = []
		for i in n + 1:
			options.append("Robar %d" % i)
		amount = await SelectionManager.await_choice(main, "%s: puedes Robar hasta %d cartas" % [_name(card), n], options, pid)
	if amount > 0 and not await _window(card, pid):
		await ActionModule.draw(pid, amount, _name(card), true)


static func _peacemaker(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar tres Armas de distinto nombre") or await _window(card, pid):
		return
	await ActionModule.search_zones(pid, [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO], {"type": Constants.CardType.ARMA}, 3, true,
		false, false, card, Constants.Zone.MANO, true)


static func _castle_to_hand(main: Node, card: Node, pid: int, title: String, eligible: Callable) -> void:
	if CardManager.get_deck(pid).is_empty() or not await _confirm(main, pid, _name(card), title) or await _window(card, pid):
		return
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: %s" % [_name(card), title], eligible, 0, 1, false)
	for d in picked:
		PlayerSideScript.put_in_hand(main, pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _pipin(main: Node, card: Node, pid: int) -> void:
	await _castle_to_hand(main, card, pid, "Buscar un Aliado Imbloqueable o Caballero, o un Arma de coste 2 o menos", func(d):
		var t := int(d.get("tipo", -1))
		if t == Constants.CardType.ARMA:
			return int(d.get("coste", 0)) <= 2
		return t == Constants.CardType.ALIADO and str(d.get("nombre", "")).to_lower() != "pipin el breve" \
			and ("imbloqueable" in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))) \
				or "caballero" in CemeteryTriggersScript.normalize(str(d.get("raza", "")))))


static func _morro_arica(main: Node, card: Node, pid: int) -> void:
	await _castle_to_hand(main, card, pid, "Buscar un Arma de coste 2",
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) == 2)


static func _solomon(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or await _window(card, pid):
		return
	var is_weapon_1 := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) == 1
	var pools: Array = []
	var where: Array = []
	for p in [pid, 1 - pid]:
		for zone in [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO]:
			var arr: Array = CardManager.get_deck(p) if zone == Constants.Zone.CASTILLO else CardManager.get_cemetery(p)
			pools.append({"is_own": p == pid, "zone": zone, "exclusive": true,
				"cards": arr.map(func(d): return {"data": d, "eligible": is_weapon_1.call(d)})})
			where.append({"owner": p, "zone": zone})
	var info: Dictionary = {}
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Arma de coste 1 de cualquier Castillo o Cementerio" % _name(card),
		pools, 1, 1, false, [], info)
	for ci in info.get("opened_castles", []):
		CardManager.shuffle_deck(where[ci].owner)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var idx := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or idx < 0 or idx >= pools[pi].cards.size() or not pools[pi].cards[idx].eligible:
		return
	var d: Dictionary = pools[pi].cards[idx].data
	var w: Dictionary = where[pi]
	if w.zone == Constants.Zone.CASTILLO:
		CardManager.get_deck(w.owner).erase(d)
		CardManager.shuffle_deck(w.owner)
	elif not CardManager.take_from_cemetery(w.owner, d):
		return
	d["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(d, pid):
		CardManager.add_to_cemetery(w.owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _roderick(main: Node, card: Node, pid: int) -> void:
	var weapons: Array = CardQuery.weapons_in_play(pid)
	var move := not weapons.is_empty()
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, _name(card),
			["Cambiar de portador un Arma", "Subir un Aliado o Arma de tu Cementerio a tu mano", "No"], pid)
		if pick < 0 or pick > 1:
			return
		move = pick == 0
	elif CardManager.get_cemetery(pid).any(func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA]):
		move = false
	if move:
		var w: Node = await _pick_from(main, pid, "%s: elige un Arma que controles" % _name(card), weapons, true)
		if not is_instance_valid(w) or not main._gold_manager:
			return
		var allies := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and c != w.get_parent())
		var new_wielder: Node = await _pick_from(main, pid, "%s: elige su nuevo portador" % _name(card), allies, true)
		if not is_instance_valid(new_wielder) or await _window(card, pid) or not is_instance_valid(w):
			return
		var old = w.get_parent()
		if old and old.get("equipped_weapons") is Array:
			old.equipped_weapons.erase(w)
		await main._gold_manager._equip_weapon(w, new_wielder, false)
		return
	var picks := await _pick_cemetery(pid, [pid], "%s: sube un Aliado o Arma de tu Cementerio a tu mano" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA])
	if picks.is_empty() or await _window(card, pid):
		return
	if CardManager.take_from_cemetery(pid, picks[0].data):
		PlayerSideScript.put_in_hand(main, pid, picks[0].data)


## Mira la mano rival (respetando Fisión Nuclear y Colapso Global) y elige hasta 'count' cartas que
## pasen 'filter' para Desterrarlas. 'who' = quien mira (por defecto pid).
static func _peek_banish(main: Node, card: Node, who: int, filter: Callable, count: int) -> void:
	var opp: int = 1 - who
	if EffectController.fision_hides_zones_of(opp, who, Constants.Zone.MANO) or await EffectController.offer_colapso_global(who):
		return
	var all: Array = _hand(main, opp)
	if all.is_empty():
		return
	if not PlayerSideScript.is_bot(who):
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), who)
	for _i in count:
		var options: Array = all.filter(func(c): return is_instance_valid(c) and filter.call(c))
		if options.is_empty():
			return
		var idx := 0
		if not PlayerSideScript.is_bot(who):
			var labels: Array = options.map(func(c): return _name(c))
			labels.append("Ninguna más")
			idx = await SelectionManager.await_choice(main, "%s: elige una carta para Desterrar" % _name(card), labels, who)
			if idx < 0 or idx >= options.size():
				return
		var chosen: Node = options[idx]
		all.erase(chosen)
		_exile_from_hand(main, opp, [chosen])


static func _erlik(main: Node, card: Node, pid: int) -> void:
	if not await _window(card, pid):
		await _peek_banish(main, card, pid, func(c): return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM], 1)


static func _fujibayashi(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var tt := func(c): return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM]
	await _peek_banish(main, card, pid, tt, 2)
	await _peek_banish(main, card, 1 - pid, tt, 2)  # luego tu oponente, de tu mano


static func _daga_bandido(main: Node, card: Node, pid: int) -> void:
	if not await _window(card, pid):
		await _mill_milled_gold_to_paid(main, card, pid, func(_p): return 4)


static func _directorium(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar un Oro en tu Castillo") or await _window(card, pid):
		return
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ORO}, 1, true, false, false, card)


static func _trentren(main: Node, card: Node, pid: int) -> void:
	var all: Array = []
	for side in [0, 1]:
		all.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO))
	if all.is_empty() or not await _confirm(main, pid, _name(card), "Barajar las demás cartas en juego que no sean Oro") or await _window(card, pid):
		return
	for c in all:
		if is_instance_valid(c):
			await PlayerSideScript.shuffle_into_castle(c, card, _name(card))


## Reparte cartas miradas (ya fuera del mazo) entre destinos, una por destino ("mano", "cementerio",
## "destierro", "fondo"). Lo que sobra vuelve al tope en el mismo orden.
static func _look_place(main: Node, card: Node, pid: int, owner: int, cards: Array, dests: Array) -> void:
	var left: Array = cards.duplicate()
	for dest in dests:
		if left.is_empty():
			break
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and left.size() > 1:
			var label: String = {"mano": "tu mano", "cementerio": "el Cementerio", "destierro": "el Destierro",
				"fondo": "el fondo del Castillo"}.get(dest, dest)
			idx = await SelectionManager.await_choice(main, "%s: ¿qué carta va a %s?" % [_name(card), label],
				left.map(func(d): return str(d.get("nombre", "?"))), pid)
			idx = clampi(idx, 0, left.size() - 1)
		var d: Dictionary = left.pop_at(idx)
		match dest:
			"mano":
				PlayerSideScript.put_in_hand(main, pid, d)
			"cementerio":
				d["esta_oculta"] = false
				CardManager.add_to_cemetery(owner, d)
			"destierro":
				d["esta_oculta"] = false
				CardManager.append_to_exile(owner, d)
			"fondo":
				d["esta_oculta"] = true
				CardManager.get_deck(owner).append(d)
	var deck: Array = CardManager.get_deck(owner)
	for i in range(left.size() - 1, -1, -1):
		deck.push_front(left[i])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _polvo_hadas(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not await _confirm(main, pid, _name(card), "Mirar las primeras tres cartas de tu Castillo") or await _window(card, pid):
		return
	var seen: Array = []
	for _i in mini(3, deck.size()):
		seen.append(deck.pop_front())
	var last := "destierro"
	if not PlayerSideScript.is_bot(pid):
		last = "destierro" if await SelectionManager.await_two_choice(main, _name(card), "La tercera, al Destierro",
			"La tercera, al fondo del Castillo", pid) else "fondo"
	await _look_place(main, card, pid, pid, seen, ["mano", "cementerio", last])


static func _nombre_horus(main: Node, card: Node, pid: int) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, "%s: puedes mirar las primeras seis cartas de un Castillo" % _name(card),
			["Castillo oponente", "Tu Castillo", "No"], pid)
		if pick < 0 or pick > 1:
			return
		owner = 1 - pid if pick == 0 else pid
	var deck: Array = CardManager.get_deck(owner)
	if deck.is_empty() or await _window(card, pid):
		return
	var seen: Array = []
	for _i in mini(6, deck.size()):
		seen.append(deck.pop_front())
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(seen, "%s: las primeras cartas" % _name(card), pid)
	await _look_place(main, card, pid, owner, seen,
		["destierro", "destierro", "destierro"] if owner != pid else ["mano", "cementerio", "cementerio"])


static func _koromodako(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
			and main._gold_manager.puede_pagar(_cost(c), -1, "", -1, pid)))
	if targets.is_empty() or not await _confirm(main, pid, _name(card), "Pagar el coste de una carta para Destruirla"):
		return
	if PlayerSideScript.is_bot(pid):
		targets = targets.filter(func(c): return CardQuery.controller_of(c) != pid)
		targets.sort_custom(func(a, b): return _cost(a) > _cost(b))
	var target: Node = await _pick_from(main, pid, "%s: elige una carta (pagas su coste)" % _name(card), targets, true)
	if not is_instance_valid(target) or not await PlayerSideScript.pay(main, pid, _cost(target)) or await _window(card, pid):
		return
	if is_instance_valid(target):
		await _blank(target, card)
		await ActionModule.destroy([target], card, true)


static func _amaterasu(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Tótem de coste 2 o menos y jugarlo por dos Oros menos",
			"Agrupar dos Oros", pid)
	if await _window(card, pid):
		return
	if search:
		await ActionModule.search_zones(pid, [Constants.Zone.CASTILLO], {"type": Constants.CardType.TOTEM, "cost_max": 2}, 1, true,
			false, true, card, Constants.Zone.MANO, false, -1, 2)
	elif main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 2)


static func _armadura_imperial(main: Node, card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(1 - pid) < 2 or not main._gold_manager:
		return
	if not await _confirm(main, pid, _name(card), "Generar un Oro para jugar Aliados") or await _window(card, pid):
		return
	main._gold_manager.generar_oro_virtual_restringido(1, func(t, _r, _c): return t == Constants.CardType.ALIADO,
		"%s: Oro para Aliados" % _name(card), pid)


static func _zmeoaica(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	await ActionModule.draw(pid, 2, _name(card), true)
	await _discard_own(main, card, pid, 1)


# Zmeoaica (custom_drac_038): "Cuando entra en juego, muestra un Aliado de coste 3 de tu mano para Robar
# dos cartas." Mostrarlo es el costo (opcional): sin uno, no Roba.
static func _zmeoaica_drac(main: Node, card: Node, pid: int) -> void:
	var shown: Node = await PlayerSideScript.pick_from_hand(main, pid,
		"%s: puedes mostrar un Aliado de coste 3 de tu mano para Robar dos cartas (N: no)" % _name(card),
		func(c): return c.get("card_type") == Constants.CardType.ALIADO and int(c.get("card_cost")) == 3)
	if not is_instance_valid(shown):
		return
	main._update_debug("%s: muestra %s" % [_name(card), _name(shown)])
	if CombatLog and CombatLog.has_method("log_action"):
		CombatLog.log_action("%s: muestra %s" % [_name(card), _name(shown)])
	if not await _window(card, pid):
		await ActionModule.draw(pid, 2, _name(card), true)
