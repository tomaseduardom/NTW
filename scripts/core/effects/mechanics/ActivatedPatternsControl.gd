extends "res://scripts/core/effects/mechanics/ActivatedPatternsBase.gd"
## ActivatedPatternsControl — familia Control de ActivatedPatterns.gd (ver ActivatedPatternsBase.gd).


# =============================================================================
# CONTROL Y BOTAR
# =============================================================================


static func _el_emperador(main: Node, card: Node, pid: int) -> void:
	var rivals := _allies(main, 1 - pid)
	if rivals.is_empty():
		return
	rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var top: int = int(ContinuousEffectManager.get_modified_strength(rivals[0]))
	var tied: Array = rivals.filter(func(c): return int(ContinuousEffectManager.get_modified_strength(c)) == top)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: el Aliado oponente de mayor Fuerza" % _name(card), tied, false)
	if not is_instance_valid(target) or not await ConvertScript._take_and_convert_in_play(target, pid, card):
		return
	target.card_raza = "Héroe"
	target.is_converted = true
	await KeywordManager.silence_card(target, card, "permanent", true)


static func _tue_tue(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		var mine := _allies(main, p)
		if mine.is_empty():
			continue
		if PlayerSideScript.is_bot(p):
			mine.sort_custom(func(a, b): return EnterScript._cost(a) < EnterScript._cost(b))
		var victim: Node = await EnterScript._pick_from(main, p, "%s: Destruye uno de tus Aliados" % _name(card), mine, false)
		if is_instance_valid(victim):
			await ActionModule.destroy([victim], card, true)


static func _tanuki(main: Node, card: Node, pid: int) -> void:
	var weak := _allies(main, 1 - pid).filter(func(c): return int(ContinuousEffectManager.get_modified_strength(c)) <= 1)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: gana el control de un Aliado de Fuerza 1 o menos" % _name(card), weak, true)
	if is_instance_valid(target):
		ContinuousEffectManager.gain_control_of_card(target, pid)


static func _gabriel_ultra(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: gana el control de una carta que no sea Oro" % _name(card), rivals, true)
	if is_instance_valid(target):
		ContinuousEffectManager.gain_control_of_card(target, pid)


static func _ur_nammu(main: Node, card: Node, pid: int) -> void:
	var n := _allies(main, pid).size()
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _murcielago(main: Node, card: Node, pid: int) -> void:
	var strengths: Dictionary = {}
	for c in EnterScript._all_allies(main):
		strengths[int(ContinuousEffectManager.get_modified_strength(c))] = true
	var who: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		who = 1 - pid if await SelectionManager.await_two_choice(main, "%s: un jugador Bota %d carta(s)" % [_name(card), strengths.size()],
			"Tu oponente", "Tú", pid) else pid
	if strengths.size() > 0:
		await ActionModule.mill(who, strengths.size(), false, _name(card))


static func _lupus_b7(main: Node, card: Node, pid: int) -> void:
	var mine: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	if PlayerSideScript.is_bot(pid):
		mine.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
	var two: Array = await EnterScript._pick_many(main, pid, "%s: otras dos cartas que controles (su coste total)" % _name(card), mine, 2, false)
	var n := 0
	for c in two:
		n += EnterScript._cost(c)
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _sargento_orok(main: Node, card: Node, _pid: int) -> void:
	var zeros: Array = EnterScript._all_allies(main, func(c): return int(ContinuousEffectManager.get_modified_strength(c)) <= 0)
	if not zeros.is_empty():
		await ActionModule.destroy(zeros, card, true)


static func _troll_soberano(main: Node, card: Node, pid: int) -> void:
	var rivals := _allies(main, 1 - pid)
	if rivals.is_empty():
		return
	rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) < ContinuousEffectManager.get_modified_strength(b))
	var low: int = int(ContinuousEffectManager.get_modified_strength(rivals[0]))
	var tied: Array = rivals.filter(func(c): return int(ContinuousEffectManager.get_modified_strength(c)) == low)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: Destierra el Aliado oponente de menor Fuerza" % _name(card), tied, true)
	if is_instance_valid(target):
		await ActionModule.banish([target], card, true)


static func _leyaden(main: Node, card: Node, pid: int) -> void:
	var n := 0
	for side in [0, 1]:
		n += EnterScript._in_play(main, side, func(c): return c != card and "leyaden" in CemeteryTriggersScript.normalize(str(c.get("card_name")))).size()
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))

# =============================================================================
# GENERAR ORO
# =============================================================================


static func _calfucura(main: Node, card: Node, pid: int) -> void:
	_restricted_gold(main, pid, 1, func(t, _r, _c): return t in [Constants.CardType.ALIADO, Constants.CardType.ARMA], "%s: Oro para Aliados o Armas" % _name(card))


static func _don_quijote(main: Node, card: Node, pid: int) -> void:
	_restricted_gold(main, pid, 1, func(_t, _r, c): return int(c) >= 3, "%s: Oro para cartas de coste 3 o más" % _name(card))
	await ActionModule.draw(pid, 2, _name(card), true)


static func _kultrung(main: Node, card: Node, pid: int) -> void:
	await LeavePlayScript._gold_to_paid(main, card)  # el costo: pagarlo
	_restricted_gold(main, pid, 2, func(_t, _r, c): return int(c) >= 4, "%s: Oros para cartas de coste 4 o más" % _name(card))


static func _ryugu_jo(main: Node, card: Node, pid: int) -> void:
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"types_not": [Constants.CardType.TALISMAN]}, 1, true, false, false, card)
	if main._gold_manager:
		main._gold_manager.generar_oros_virtuales(1, pid)


static func _cueva_xalpen(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Arma o Tótem de coste 2 o más",
			"Generar un Oro para Armas o Tótem de coste 2 o más", pid)
	if search:
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": [Constants.CardType.ARMA, Constants.CardType.TOTEM], "cost_min": 2}, 1, true, false, false, card)
	else:
		_restricted_gold(main, pid, 1, func(t, _r, c): return t in [Constants.CardType.ARMA, Constants.CardType.TOTEM] and int(c) >= 2,
			"%s: Oro para Armas o Tótem de coste 2 o más" % _name(card))


static func _akashi_oro(main: Node, card: Node, pid: int) -> void:
	var lines: Array = PlayerSideScript.ally_containers(main, pid)
	if lines.size() > 1 and card.get_parent() == lines[1] and main._gold_manager:
		main._gold_manager.generar_oros_virtuales(1, pid)

# =============================================================================
# OROS EN JUEGO
# =============================================================================


static func _gusano_blanco(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var is_gold := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO
	var hand_nodes: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
	var pools: Array = []
	var owners: Array = []
	for p in [pid, 1 - pid]:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": is_gold.call(d)})})
		owners.append(p)
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Oro de tu mano o de un Cementerio a tu Reserva" % _name(card), pools, 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var data: Dictionary = {}
	var owner: int = pid
	if int(raw[0][0]) == -1:
		if int(raw[0][1]) >= 0 and int(raw[0][1]) < hand_nodes.size():
			data = PlayerSideScript.take_from_hand(main, pid, hand_nodes[int(raw[0][1])])
	else:
		var pi := int(raw[0][0])
		var ci := int(raw[0][1])
		if pi >= 0 and pi < pools.size() and ci >= 0 and ci < pools[pi].cards.size() and pools[pi].cards[ci].eligible:
			data = pools[pi].cards[ci].data
			owner = owners[pi]
			if not CardManager.take_from_cemetery(owner, data):
				data = {}
	if data.is_empty():
		return
	var gold: Node = await main._gold_manager.put_gold_directly_in_reserva(pid, data)
	if is_instance_valid(gold):
		gold.owner_id = owner


static func _tenebris(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var is_gold := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO
	var pools: Array = []
	var where: Array = []
	for p in [pid, 1 - pid]:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": is_gold.call(d)})})
		where.append({"owner": p, "zone": Constants.Zone.CEMENTERIO})
	pools.append({"is_own": false, "zone": Constants.Zone.DESTIERRO, "exclusive": true,
		"cards": CardManager.get_exile(1 - pid).map(func(d): return {"data": d, "eligible": is_gold.call(d)})})
	where.append({"owner": 1 - pid, "zone": Constants.Zone.DESTIERRO})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Oro de un Cementerio o del Destierro oponente" % _name(card), pools, 0, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var d: Dictionary = pools[pi].cards[ci].data
	var w: Dictionary = where[pi]
	if w.zone == Constants.Zone.CEMENTERIO:
		if not CardManager.take_from_cemetery(w.owner, d):
			return
	else:
		CardManager.get_exile(w.owner).erase(d)
		CardManager._emit_exile_changed(w.owner)
	var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, d)
	if is_instance_valid(gold):
		gold.owner_id = w.owner


static func _veela(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var top: Dictionary = deck.pop_front()
	main._update_debug("%s muestra: %s" % [_name(card), str(top.get("nombre", "?"))])
	RevealedCardsScript.record(pid, [top], _name(card))
	var ok: bool = int(top.get("tipo", -1)) == Constants.CardType.ORO or (int(top.get("tipo", -1)) != Constants.CardType.ORO and int(top.get("coste", 0)) <= 2)
	if ok and await EnterScript._confirm(main, pid, _name(card), "Poner %s en tu mano" % str(top.get("nombre", ""))):
		PlayerSideScript.put_in_hand(main, pid, top)
		if main.get("_zone_manager"):
			main._zone_manager._update_castillo_counts()
	else:
		RevealedCardsScript.shuffle_back(main, pid, [top], _name(card))


static func _rueda_fortuna(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var top: Dictionary = deck.pop_front()
	main._update_debug("%s muestra: %s" % [_name(card), str(top.get("nombre", "?"))])
	RevealedCardsScript.record(pid, [top], _name(card))
	if int(top.get("tipo", -1)) == Constants.CardType.ORO and await EnterScript._confirm(main, pid, _name(card), "Poner el Oro en tu mano y Robar una carta"):
		PlayerSideScript.put_in_hand(main, pid, top)
		await ActionModule.draw(pid, 1, _name(card), true)
	else:
		RevealedCardsScript.shuffle_back(main, pid, [top], _name(card))


static func _el_mundo(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not main._gold_manager or not await _pay_gold(main, pid, 1):
		return
	await EnterScript._data_to_paid_gold(main, deck.pop_back(), pid, pid)


static func _huevos_oro(main: Node, card: Node, pid: int) -> void:
	if card.get_meta("used_once_per_game", false) or not main._gold_manager:
		main._update_debug("%s: esta habilidad ya se usó en la partida" % _name(card))
		return
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	if deck.is_empty() or not await _pay_gold(main, pid, 1):
		return
	card.set_meta("used_once_per_game", true)
	await EnterScript._data_to_paid_gold(main, deck.pop_front(), owner, pid)

# =============================================================================
# FUERZA Y PROTECCIÓN
# =============================================================================


static func _tauro(main: Node, card: Node, pid: int) -> void:
	var draw := true
	if not PlayerSideScript.is_bot(pid):
		draw = await SelectionManager.await_two_choice(main, _name(card), "Robar dos cartas", "Un Aliado que controles es Imbloqueable por el turno", pid)
	if draw:
		await ActionModule.draw(pid, 2, _name(card), true)
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles" % _name(card), _allies(main, pid), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.IMBLOQUEABLE, card, "turn")


static func _hibridos(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).size() > 4:
		main._update_debug("%s: tienes más de cuatro cartas en tu mano" % _name(card))
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles gana 2 de Fuerza" % _name(card), _allies(main, pid), false)
	await _buff(ally, card, 2)


static func _search_to_cemetery(main: Node, card: Node, pid: int, eligible: Callable, title: String) -> Dictionary:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: %s" % [_name(card), title], eligible, 0, 1, false)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return picked[0] if not picked.is_empty() else {}


static func _is_ally(d) -> bool:
	return int(d.get("tipo", -1)) == Constants.CardType.ALIADO


static func _is_beast(d) -> bool:
	return _is_ally(d) and "bestia" in CemeteryTriggersScript.normalize(str(d.get("raza", "")))


static func _gnoll(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).size() > 4:
		main._update_debug("%s: tienes más de cuatro cartas en tu mano" % _name(card))
		return
	await _search_to_cemetery(main, card, pid, func(d): return _is_ally(d), "un Aliado de tu Castillo a tu Cementerio")


static func _sabuesos_arawn(main: Node, card: Node, pid: int) -> void:
	var found := await _search_to_cemetery(main, card, pid, func(d): return _is_beast(d), "un Aliado Bestia de tu Castillo a tu Cementerio")
	if not found.is_empty():
		await _buff(card, card, 2)


static func _cerbero(main: Node, card: Node, pid: int) -> void:
	var found := await _search_to_cemetery(main, card, pid, func(d): return _is_beast(d), "un Aliado Bestia de tu Castillo a tu Cementerio")
	if found.is_empty():
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana o pierde 2 de Fuerza" % _name(card), EnterScript._all_allies(main), false)
	if not is_instance_valid(ally):
		return
	var gain: bool = CardQuery.controller_of(ally) == pid
	if not PlayerSideScript.is_bot(pid):
		gain = await SelectionManager.await_two_choice(main, _name(card), "Gana 2 de Fuerza", "Pierde 2 de Fuerza", pid)
	await _buff(ally, card, 2 if gain else -2)


static func _cahuelche(main: Node, card: Node, pid: int) -> void:
	var found := await _search_to_cemetery(main, card, pid, func(d): return _is_ally(d), "un Aliado de tu Castillo a tu Cementerio")
	if found.is_empty():
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana %d de Fuerza" % [_name(card), int(found.get("coste", 0))],
		EnterScript._all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)), false)
	await _buff(ally, card, int(found.get("coste", 0)))


static func _dodomeki(main: Node, card: Node, pid: int) -> void:
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado oponente pierde 2 de Fuerza" % _name(card), _allies(main, 1 - pid), true)
	if not is_instance_valid(target):
		return
	await _buff(target, card, -2)
	if is_instance_valid(target) and int(ContinuousEffectManager.get_modified_strength(target)) <= 0 \
			and await EnterScript._confirm(main, pid, _name(card), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(card), true)


static func _endimion(main: Node, card: Node, pid: int) -> void:
	var heroes: Array = EnterScript._all_allies(main, func(c): return "heroe" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	var n: int = PlayerSideScript.oro_pagado(main, 1 - pid).get_child_count()
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Héroe gana %d de Fuerza" % [_name(card), n], heroes, false)
	await _buff(ally, card, n)


static func _oolaf(main: Node, card: Node, pid: int) -> void:
	var types: Dictionary = {}
	for d in CardManager.get_exile(pid):
		types[int(d.get("tipo", -1))] = true
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia y %d de Fuerza" % [_name(card), types.size()], EnterScript._all_allies(main), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "permanent")
		await _buff(ally, card, types.size())


static func _black_ursa(main: Node, card: Node, pid: int) -> void:
	var names: Dictionary = {}
	for d in CardManager.get_exile(pid):
		names[str(d.get("nombre", "")).to_lower()] = true
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana %d de Fuerza" % [_name(card), names.size()], EnterScript._all_allies(main), false)
	await _buff(ally, card, names.size())


static func _maza(main: Node, card: Node, _pid: int) -> void:
	var wielder = card.get_parent()
	if is_instance_valid(wielder) and wielder.get("equipped_weapons") is Array:
		await _buff(wielder, card, int(ContinuousEffectManager.get_modified_strength(wielder)))


static func _metalmorfo(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado es Imbloqueable y hace daño al Destierro este turno" % _name(card),
		EnterScript._all_allies(main), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.IMBLOQUEABLE, card, "turn")
		ally.set_meta("damage_to_exile_turn", GameManager.turn_serial)


static func _laboratorio_siniestro(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles gana Furia y hace daño al Destierro" % _name(card), _allies(main, pid), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "turn")
		ally.set_meta("damage_to_exile_turn", GameManager.turn_serial)


static func _faraon_negro_2(main: Node, card: Node, pid: int) -> void:
	var others: Array = EnterScript._all_allies(main, func(c): return c != card)
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: otro Aliado gana 1 de Fuerza y hace el doble de daño" % _name(card), others, false)
	if is_instance_valid(ally):
		await _buff(ally, card, 1)
		ally.set_meta("double_combat_damage_turn", GameManager.turn_serial)


static func _bandido_medieval(main: Node, card: Node, pid: int) -> void:
	var bandits: Array = _allies(main, pid).filter(func(c): return "bandido" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	var all_bandits := not bandits.is_empty()
	if not PlayerSideScript.is_bot(pid) and not bandits.is_empty():
		all_bandits = await SelectionManager.await_two_choice(main, _name(card), "Tus Aliados Bandido ganan 1 de Fuerza permanentemente",
			"Un Aliado gana 1 de Fuerza permanentemente", pid)
	if all_bandits:
		for b in bandits:
			await _buff(b, card, 1, true)
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza permanentemente" % _name(card), EnterScript._all_allies(main), false)
	await _buff(ally, card, 1, true)


static func _sirinia(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles no puede salir del juego hasta tu próximo turno" % _name(card), _allies(main, pid), false)
	if is_instance_valid(ally):
		EffectController.add_single_card_leave_play_immunity(ally, pid)


static func _iki_balam(main: Node, card: Node, pid: int) -> void:
	var mine: int = int(ContinuousEffectManager.get_modified_strength(card))
	var weaker: Array = EnterScript._all_allies(main, func(c): return c != card and int(ContinuousEffectManager.get_modified_strength(c)) < mine)
	if PlayerSideScript.is_bot(pid):
		weaker = weaker.filter(func(c): return CardQuery.controller_of(c) != pid)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados de menor Fuerza" % _name(card), weaker, 2, true)
	var until: int = RuleState.next_own_turn(pid) - 1
	for c in chosen:
		if not is_instance_valid(c):
			continue
		c.set_meta("silenced_until", until)
		ContinuousEffectManager.register_modifier({
			"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 0, "operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": 2 if GameManager.active_player_id == pid else 1,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "%s: Fuerza 0" % _name(card),
		})


static func _machete_abuelo(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia y 2 de Fuerza permanentemente" % _name(card), EnterScript._all_allies(main), false)
	if not is_instance_valid(ally):
		return
	KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "permanent")
	await _buff(ally, card, 2, true)
	var n: int = EnterScript._cost(ally) + 1
	var amount := n
	if not PlayerSideScript.is_bot(pid):
		var options: Array = []
		for i in n + 1:
			options.append("Robar %d" % i)
		amount = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta %d cartas" % [_name(card), n], options, pid), 0)
	if amount > 0:
		await ActionModule.draw(pid, amount, _name(card), true)


static func _qualmi(main: Node, card: Node, pid: int) -> void:
	var buff := true
	if not PlayerSideScript.is_bot(pid):
		buff = await SelectionManager.await_two_choice(main, _name(card), "Un Aliado gana 1 de Fuerza por el turno",
			"Pagar un Oro: subir una carta de coste 2 o menos a la mano de su dueño", pid)
	if buff:
		var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza" % _name(card), EnterScript._all_allies(main), false)
		await _buff(ally, card, 1)
		return
	if not await _pay_gold(main, pid, 1):
		return
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(EnterScript._in_play(main, side, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2)))
	var t: Node = await EnterScript._pick_from(main, pid, "%s: sube una carta de coste 2 o menos a la mano de su dueño" % _name(card), targets, false)
	if is_instance_valid(t):
		await EnterScript.bounce_to_owner_hand(main, t, card)

# =============================================================================
# EXHUMAR POR EL TURNO (meta "_exhumar_until" en los datos del Cementerio)
# =============================================================================


static func _grant_from_cemetery(main: Node, card: Node, pid: int, count: int, eligible: Callable, title: String) -> Array:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: %s" % [_name(card), title], 0, count, eligible)
	var datas: Array = picks.map(func(p): return p.data)
	_grant_exhumar(datas)
	if not datas.is_empty():
		main._update_debug("%s: %s gana Exhumar por el turno" % [_name(card), ", ".join(datas.map(func(d): return str(d.get("nombre", ""))))])
	return datas


static func _animita(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 1, func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN, "una carta que no sea Talismán gana Exhumar")


static func _arturo_bretana(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 1, func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA, "un Arma gana Exhumar")


static func _laboratorio_maldito(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 1, func(d): return _is_ally(d), "un Aliado gana Exhumar")


static func _voragh(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 2, func(d): return _is_ally(d), "hasta dos Aliados ganan Exhumar")


static func _cementerio_maldito(main: Node, card: Node, pid: int) -> void:
	var options := [["Aliado", Constants.CardType.ALIADO], ["Arma", Constants.CardType.ARMA], ["Tótem", Constants.CardType.TOTEM]]
	var idx := 0
	if not PlayerSideScript.is_bot(pid):
		idx = clampi(await SelectionManager.await_choice(main, "%s: elige un tipo de carta" % _name(card), options.map(func(o): return o[0]), pid), 0, 2)
	var t: int = options[idx][1]
	_grant_exhumar(CardManager.get_cemetery(pid).filter(func(d): return int(d.get("tipo", -1)) == t and int(d.get("coste", 0)) >= 1))
	main._update_debug("%s: las cartas de tipo %s de coste 1 o más en tu Cementerio ganan Exhumar por el turno" % [_name(card), options[idx][0]])


static func _quicavi(main: Node, card: Node, pid: int) -> void:
	var datas := await _grant_from_cemetery(main, card, pid, 1, func(_d): return true, "una carta gana Exhumar hasta tu próximo turno")
	var until: int = RuleState.next_own_turn(pid) - 1
	for d in datas:
		d["_exhumar_until"] = until
	RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))


static func _pulpo_colosal(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).size() > 4:
		main._update_debug("%s: tienes más de cuatro cartas en tu mano" % _name(card))
		return
	await _grant_from_cemetery(main, card, pid, 2, func(d): return _is_ally(d) and int(d.get("coste", 0)) == 1, "hasta dos Aliados de coste 1 ganan Exhumar")
	for c in _allies(main, pid):
		c.set_meta("protected_from_cancel_turn", GameManager.turn_serial)  # StackAnnul.protected_from_cancel
