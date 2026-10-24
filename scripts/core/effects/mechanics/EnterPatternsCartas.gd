extends "res://scripts/core/effects/mechanics/EnterPatternsBase.gd"
## EnterPatternsCartas — familia Cartas de EnterPatterns.gd (ver EnterPatternsBase.gd).


# =============================================================================
# CARTAS
# =============================================================================


static func _garfio(main: Node, card: Node, pid: int) -> void:
	var wielder = card.get_parent()
	if not is_instance_valid(wielder) or not (wielder.get("equipped_weapons") is Array) or await _window(card, pid):
		return
	EffectController.add_single_card_leave_play_immunity(wielder, pid)
	main._update_debug("%s: %s no puede salir del juego hasta tu próximo turno" % [_name(card), _name(wielder)])


static func _abd_el_kerim(main: Node, card: Node, pid: int) -> void:
	var others := _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO)
	var other: Node = await _pick_from(main, pid, "%s: elige otro Aliado que controles" % _name(card), others, false)
	if await _window(card, pid):
		return
	for c in [card, other]:
		if is_instance_valid(c):
			EffectController.add_single_card_leave_play_immunity(c, pid)
	main._update_debug("%s: no pueden salir del juego hasta tu próximo turno" % _name(card))


static func _turiel(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Un Aliado oponente queda con Fuerza 0"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente" % _name(card), rivals, true)
	if not target or await _window(card, pid) or not is_instance_valid(target):
		return
	ContinuousEffectManager.register_modifier({
		"source": target, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": 0, "operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "%s: Fuerza 0" % _name(card),
	})
	target.set_meta("no_leave_turn", GameManager.turn_serial)  # EffectController._try_consume_leave_play_prevention
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()


static func _minamoto(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	await ActionModule.mill(1 - pid, 2, false, _name(card))
	if main._gold_manager:
		main._gold_manager.set_no_more_cards_this_turn(1 - pid)


static func _barachiel(main: Node, card: Node, pid: int) -> void:
	var zone_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		zone_owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: la primera carta de un Castillo pasa a tu Oro Pagado" % _name(card),
			"Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(zone_owner)
	if deck.is_empty() or not main._gold_manager or await _window(card, pid):
		return
	await _data_to_paid_gold(main, deck.pop_front(), zone_owner, pid)


static func _draig(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not main._gold_manager or await _window(card, pid):
		return
	await _data_to_paid_gold(main, deck.pop_front(), pid, pid)


static func _sibila(main: Node, card: Node, pid: int) -> void:
	var golds := _golds(main, [1 - pid]).filter(func(g): return g.get("is_converted") != true)
	var gold: Node = await _pick_from(main, pid, "%s: elige un Oro oponente: queda sin habilidad" % _name(card), golds, false)
	if gold and not await _window(card, pid):
		await _blank(gold, card)


static func _la_muerte(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for g in _golds(main, [0, 1]):
		await _blank(g, card)
	var doomed: Array = []
	for side in [0, 1]:
		doomed.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
			and ContinuousEffectManager.cost_at_most(c, 3)))
	for c in doomed:
		await _blank(c, card)
	if not doomed.is_empty():
		await ActionModule.destroy(doomed, card, true)


static func _zmeu(main: Node, card: Node, pid: int) -> void:
	var golds := _golds(main, [1 - pid, pid])
	if golds.is_empty() or not await _confirm(main, pid, _name(card), "Convertir un Oro y ganar su control"):
		return
	var gold: Node = await _pick_from(main, pid, "%s: elige un Oro" % _name(card), golds, true)
	if not gold or await _window(card, pid) or not is_instance_valid(gold):
		return
	await _blank(gold, card)
	ContinuousEffectManager.gain_control_of_card(gold, pid)


static func _lucy(main: Node, card: Node, pid: int) -> void:
	if CardManager.get_exile(1 - pid).size() < 8:
		return
	var golds := _golds(main, [1 - pid]).filter(func(g): return g.get("is_converted") != true)
	var chosen: Array = await _pick_many(main, pid, "%s: dos Oros oponentes quedan sin habilidad" % _name(card), golds, 2, false)
	if chosen.is_empty() or await _window(card, pid):
		return
	for g in chosen:
		await _blank(g, card)


static func _honengyo(main: Node, card: Node, pid: int) -> void:
	var n: int = _golds(main, [pid]).filter(func(g): return g.get_parent() == PlayerSideScript.oro_pagado(main, pid)).size()
	var who: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		who = 1 - pid if await SelectionManager.await_two_choice(main, "%s: un jugador Bota %d carta(s)" % [_name(card), n],
			"Tu oponente", "Tú", pid) else pid
	if await _window(card, pid):
		return
	if n > 0:
		await ActionModule.mill(who, n, false, _name(card))
	await TriggerSystem._effect_interpreter.try_execute(card, "puedes subir hasta un aliado y un oro de tu cementerio a tu mano", pid)


static func _garras(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var milled_gold := false
	for p in [pid, 1 - pid]:
		var n: int = _golds(main, [1 - p]).size()
		if n <= 0:
			continue
		var res: Dictionary = await ActionModule.mill(p, n, false, _name(card))
		for d in res.get("cards", []):
			if d is Dictionary and int(d.get("tipo", -1)) == Constants.CardType.ORO:
				milled_gold = true
	if not milled_gold or not main._gold_manager:
		return
	var pools: Array = []
	var owners: Array = []
	for p in [pid, 1 - pid]:
		var entries: Array = []
		for d in CardManager.get_cemetery(p):
			entries.append({"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.ORO})
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true})
		owners.append(p)
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: pon un Oro de un Cementerio en tu Oro Pagado" % _name(card), pools, 1, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var data: Dictionary = pools[pi].cards[ci].data
	if CardManager.take_from_cemetery(owners[pi], data):
		var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, data)
		if is_instance_valid(gold):
			gold.owner_id = owners[pi]


static func _lamec(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Cada jugador Destierra dos cartas de su mano") or await _window(card, pid):
		return
	for p in [pid, 1 - pid]:
		var hand := _hand(main, p)
		if hand.size() > 2:
			if PlayerSideScript.is_bot(p):
				hand.sort_custom(func(a, b): return int(a.get("card_cost")) < int(b.get("card_cost")))
			hand = await _pick_many(main, p, "%s: Destierra dos cartas de tu mano" % _name(card), hand, 2, false)
		_exile_from_hand(main, p, hand.slice(0, 2))


static func _jangseung(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for p in [pid, 1 - pid]:
		var picked: Array = []
		if CardManager.get_deck(p).size() >= 2:
			picked = await AttackScript._pick_from_castle(p, p, "%s: busca dos cartas en tu Castillo para tu Cementerio" % _name(card),
				func(_d): return true, 2, 2, false)
		for d in picked:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(p, d)
		if picked.size() < 2:
			await ActionModule.mill(p, 5, false, _name(card))
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _holmwood(main: Node, card: Node, pid: int) -> void:
	var hand := _hand(main, 1 - pid)
	if hand.is_empty() or not main._gold_manager or await _window(card, pid):
		return
	var shown: Node = hand.pick_random()
	main._gold_manager.lock_card_from_playing(shown, pid)
	main._update_debug("%s: tu oponente muestra %s y no puede jugarla hasta tu próximo turno" % [_name(card), _name(shown)])


static func _mina_maldita(main: Node, card: Node, pid: int) -> void:
	var targets := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if targets.is_empty() or await _window(card, pid):
		return
	await ActionModule.banish(targets, card, true)


static func _smaragos(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3))
	if rivals.is_empty():
		return
	var destroy := true
	if not PlayerSideScript.is_bot(pid):
		destroy = await SelectionManager.await_two_choice(main, _name(card), "Destruir", "Desterrar", pid)
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos cartas oponentes de coste 3 o menos" % _name(card), rivals, 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	if destroy:
		await ActionModule.destroy(chosen, card, true)
	else:
		await ActionModule.banish(chosen, card, true)


static func _los_almas(main: Node, card: Node, pid: int) -> void:
	var costs: Dictionary = {}
	for c in _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		costs[_cost(c)] = true
	if costs.is_empty() or await _window(card, pid):
		return
	await ActionModule.draw(pid, costs.size(), _name(card), true)


static func _baphomet(main: Node, card: Node, pid: int) -> void:
	var by_allies: int = _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO).size()
	var all_allies: Array = []
	for side in [0, 1]:
		all_allies.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO))
	var n := by_allies
	if PlayerSideScript.is_bot(pid):
		for a in all_allies:
			n = maxi(n, int(ContinuousEffectManager.get_modified_strength(a)))
	elif not all_allies.is_empty() and not await SelectionManager.await_two_choice(main, _name(card),
			"Tantas como Aliados controlas (%d)" % by_allies, "Tantas como la Fuerza de un Aliado", pid):
		var a: Node = await _pick_from(main, pid, "%s: elige un Aliado en juego" % _name(card), all_allies, false)
		n = int(ContinuousEffectManager.get_modified_strength(a)) if is_instance_valid(a) else 0
	if n <= 0 or await _window(card, pid):
		return
	await ActionModule.mill(1 - pid, n, false, _name(card))


static func _mr_smee(main: Node, card: Node, pid: int) -> void:
	var n: int = _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO).size()
	if await _window(card, pid):
		return
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))
	var cem: Array = CardManager.get_cemetery(1 - pid)
	if cem.is_empty():
		return
	var entries: Array = cem.map(func(d): return {"data": d, "eligible": true})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: Destierra dos cartas del Cementerio oponente" % _name(card),
		[{"is_own": false, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], mini(2, cem.size()), 2)
	var picked: Array = []
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size():
			var d: Dictionary = entries[int(rp[1])].data
			if not picked.has(d) and picked.size() < 2:
				picked.append(d)
	for d in picked:
		if CardManager.take_from_cemetery(1 - pid, d):
			CardManager.append_to_exile(1 - pid, d)


static func _diabolista(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var allies := _in_play(main, opp, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if await _window(card, pid):
		return
	if not allies.is_empty():
		if PlayerSideScript.is_bot(opp):
			allies.sort_custom(func(a, b): return _cost(a) < _cost(b))
		var victim: Node = await _pick_from(main, opp, "%s: elige un Aliado que controles: pierde su habilidad y es Destruido" % _name(card),
			allies, false)
		if is_instance_valid(victim):
			await _blank(victim, card)
			await ActionModule.destroy([victim], card, true)
	if GameManager.active_player_id == opp:
		await ActionModule.mill(opp, 4, false, _name(card))


static func _abadon(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var hand := _hand(main, opp)
	if hand.is_empty() or await _window(card, pid):
		return
	var discard := hand.size() >= 2
	if not PlayerSideScript.is_bot(opp):
		discard = await SelectionManager.await_two_choice(main, _name(card), "Descartar dos cartas de tu mano",
			"Desterrar una carta al azar de tu mano", opp)
	if discard:
		var cards: Array = hand
		if hand.size() > 2:
			cards = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, 2, opp)
		await ActionModule.discard(opp, cards.slice(0, 2), _name(card), true)
	else:
		_exile_from_hand(main, opp, [hand.pick_random()])


static func _discard_from_opp_hand(main: Node, card: Node, pid: int, keep: Callable) -> void:
	var opp: int = 1 - pid
	var hand := _hand(main, opp)
	if not hand.is_empty() and not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	var gone: Array = hand.filter(func(c): return not keep.call(c))
	if gone.is_empty() or await _window(card, pid):
		return
	await ActionModule.discard(opp, gone, _name(card), true)


static func _acuario(main: Node, card: Node, pid: int) -> void:
	await _discard_from_opp_hand(main, card, pid, func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.ORO])


static func _dupin(main: Node, card: Node, pid: int) -> void:
	await _discard_from_opp_hand(main, card, pid, func(c): return not (c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM]))


static func _regan(main: Node, card: Node, pid: int) -> void:
	var mine: Array = []
	for container in PlayerSideScript.line_containers(main, 1 - pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("owner_id") != null and int(c.owner_id) == pid and CardQuery.controller_of(c) != pid:
				mine.append(c)
	for g in _golds(main, [1 - pid]):
		if g.get("owner_id") != null and int(g.owner_id) == pid:
			mine.append(g)
	if mine.is_empty() or await _window(card, pid):
		return
	for c in mine:
		if is_instance_valid(c):
			ContinuousEffectManager.gain_control_of_card(c, pid)


static func _esfinge(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Convertir un Aliado oponente y ganar su control"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, true)
	if not target or await _window(card, pid) or not is_instance_valid(target):
		return
	ContinuousEffectManager.gain_control_of_card(target, pid)
	await _blank(target, card)


## Lucy Westenra / jack: una carta en juego pasa a ser tu Aliado Sombra sin habilidad de Fuerza N.
static func _to_shadow_ally(main: Node, card: Node, pid: int, node: Node, strength: int) -> void:
	if not await ConvertScript._take_and_convert_in_play(node, pid, card):
		return
	node.card_raza = "Sombra"
	await ConvertScript._finish_conversion(node, card, pid, strength, [], false)
	main._update_debug("%s: %s es ahora tu Aliado Sombra de Fuerza %d sin habilidad" % [_name(card), _name(node), strength])


static func _lucy_westenra(main: Node, card: Node, pid: int) -> void:
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c != card and ContinuousEffectManager.cost_at_most(c, 1)))
	if targets.is_empty() or not await _confirm(main, pid, _name(card), "Convertir una carta de coste 1 o menos"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta de coste 1 o menos" % _name(card), targets, true)
	if target and not await _window(card, pid) and is_instance_valid(target):
		await _to_shadow_ally(main, card, pid, target, 0)


static func _jack(main: Node, card: Node, pid: int) -> void:
	if CardManager.get_exile(1 - pid).size() < 3:
		return
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, false)
	if target and not await _window(card, pid) and is_instance_valid(target):
		await _to_shadow_ally(main, card, pid, target, 1)


static func _rugiaevit(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var cards := _in_play(main, opp, func(c): return c.get("card_type") != Constants.CardType.ORO)
	if cards.is_empty() or await _window(card, pid):
		return
	if PlayerSideScript.is_bot(opp):
		cards.sort_custom(func(a, b): return _cost(a) < _cost(b))
	var chosen: Node = await _pick_from(main, opp, "%s: elige una carta que controles: pasa a ser un Tótem sin habilidad del oponente" % _name(card),
		cards, false)
	if is_instance_valid(chosen):
		await ConvertScript.convert_in_play_to_totem(chosen, card, pid)


static func _kokudaka(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return ContinuousEffectManager.cost_at_most(c, 1) and c.get("is_converted") != true)
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Dejar sin habilidad una carta oponente de coste 1 o menos"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta oponente de coste 1 o menos" % _name(card), rivals, true)
	if target and not await _window(card, pid):
		await _blank(target, card)


static func _isabel(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var all: Array = _in_play(main, 1 - pid) + _golds(main, [1 - pid])
	for c in all:
		await _blank(c, card)
	main._update_debug("%s: las cartas oponentes quedan sin habilidad" % _name(card))


static func _hitotsume(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Intercambiar el control con un Aliado oponente"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, true)
	if not target or await _window(card, pid) or not is_instance_valid(target) or not is_instance_valid(card):
		return
	ContinuousEffectManager.gain_control_of_card(target, pid)
	ContinuousEffectManager.gain_control_of_card(card, 1 - pid)


static func _monjas(main: Node, card: Node, pid: int) -> void:
	var entries: Array = []
	for d in CardManager.get_cemetery(pid):
		entries.append({"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.TOTEM and int(d.get("coste", 0)) <= 3})
	if not entries.any(func(e): return e.eligible) or not main._gold_manager:
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta dos Tótem de tu Cementerio cuyos costes sumen 3 o menos" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 2)
	var picked: Array = []
	var total := 0
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size() and entries[int(rp[1])].eligible:
			var d: Dictionary = entries[int(rp[1])].data
			if not picked.has(d) and total + int(d.get("coste", 0)) <= 3:
				picked.append(d)
				total += int(d.get("coste", 0))
	if picked.is_empty() or await _window(card, pid):
		return
	for d in picked:
		if CardManager.take_from_cemetery(pid, d):
			d["esta_oculta"] = false
			if not await main._gold_manager.play_card_for_free(d, pid):
				CardManager.add_to_cemetery(pid, d)


static func _heracles(main: Node, card: Node, pid: int) -> void:
	var heroes: Array = []
	for side in [pid, 1 - pid]:
		heroes.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
			and "heroe" in CemeteryTriggersScript.normalize(str(c.get("card_raza")))))
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Héroes ganan 2 de Fuerza" % _name(card), heroes, 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	for h in chosen:
		if is_instance_valid(h) and not await EffectController.offer_prevention(h, card, "strength_change"):
			ContinuousEffectManager.register_modifier({
				"source": h, "target": h, "type": ContinuousEffectManager.ModifierType.STRENGTH,
				"stat": "strength", "value": 2, "operation": "add",
				"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
				"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
				"description": "%s +2" % _name(card),
			})
			if h.has_method("refresh_strength_badge"):
				h.refresh_strength_badge()


static func _veela(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or PlayerSideScript.oro_pagado(main, pid).get_child_count() == 0:
		return
	if not await _confirm(main, pid, _name(card), "Agrupar hasta dos Oros") or await _window(card, pid):
		return
	await main._gold_manager.agrupar_oros(pid, 2)


static func _kuzuryu(main: Node, card: Node, pid: int) -> void:
	var small := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and c != card \
		and ContinuousEffectManager.cost_at_most(c, 1))
	if not small.is_empty():
		return
	await TriggerSystem._effect_interpreter.try_execute(card, "puedes poner un oro de tu mano o cementerio en tu oro pagado", pid)
