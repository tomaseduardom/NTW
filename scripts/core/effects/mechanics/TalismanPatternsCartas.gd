extends "res://scripts/core/effects/mechanics/TalismanPatternsBase.gd"
## TalismanPatternsCartas — familia Cartas de TalismanPatterns.gd (ver TalismanPatternsBase.gd).


# =============================================================================
# CARTAS
# =============================================================================


static func _caceria_brujas(main: Node, card: Node, pid: int) -> void:
	await EnterScript._discard_from_opp_hand(main, card, pid, func(c): return c.get("card_type") != Constants.CardType.TALISMAN)


static func _caminar_tablon(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid):
		return
	var all: Array = EnterScript._hand(main, opp)
	var hand: Array = all.filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
	if all.is_empty():
		return
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	if hand.is_empty():
		return
	var idx := 0
	if PlayerSideScript.is_bot(pid):
		hand.sort_custom(func(a, b): return int(a.get("card_cost")) > int(b.get("card_cost")))
	elif hand.size() > 1:
		idx = await SelectionManager.await_choice(main, "%s: elige una carta que no sea Oro para Desterrarla" % _name(card),
			hand.map(func(c): return EnterScript._name(c)), pid)
	var chosen: Node = hand[clampi(idx, 0, hand.size() - 1)]
	if is_instance_valid(chosen):
		EnterScript._exile_from_hand(main, opp, [chosen])
		main._update_debug("%s: Destierra %s de la mano oponente" % [_name(card), EnterScript._name(chosen)])


static func _abduccion(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return ContinuousEffectManager.cost_at_most(c, 3) and c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube una carta oponente de coste 3 o menos a la mano de su dueño" % _name(card), rivals, false)
	if not is_instance_valid(target):
		return
	var was_ally_or_totem: bool = target.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM]
	var target_name := EnterScript._name(target)
	if not await EnterScript.bounce_to_owner_hand(main, target, card) or not was_ally_or_totem:
		return
	if main._gold_manager:
		main._gold_manager.lock_name_from_playing(target_name, 1 - pid, pid)
		main._gold_manager.generar_oro_virtual_restringido(1, func(t, _r, _c): return t in [Constants.CardType.ARMA, Constants.CardType.TOTEM],
			"%s: Oro para Armas o Tótem" % _name(card), pid)


static func _maestro_go(main: Node, card: Node, pid: int) -> void:
	var targets := _in_play_both(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2) and c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube una carta de coste 2 o menos a la mano de su dueño" % _name(card), targets, false)
	if not is_instance_valid(target):
		return
	var target_name := EnterScript._name(target)
	if await EnterScript.bounce_to_owner_hand(main, target, card) and main._gold_manager:
		main._gold_manager.lock_name_from_playing(target_name, 1 - pid, pid)


static func _bounce_opp_ally(main: Node, card: Node, pid: int, max_cost: int, optional: bool) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and (max_cost < 0 or ContinuousEffectManager.cost_at_most(c, max_cost)))
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube un Aliado oponente a la mano de su dueño" % _name(card), rivals, optional)
	if is_instance_valid(target):
		await EnterScript.bounce_to_owner_hand(main, target, card)


static func _justa(main: Node, card: Node, pid: int) -> void:
	await _raise_one(main, pid, "%s: puedes subir una carta de tu Cementerio a tu mano" % _name(card), true)
	await _bounce_opp_ally(main, card, pid, 2, true)


static func _renace_fe(main: Node, card: Node, pid: int) -> void:
	await _bounce_opp_ally(main, card, pid, -1, false)
	await _raise_one(main, pid, "%s: puedes subir una carta de tu Cementerio a tu mano" % _name(card), true)


static func _artilleria(main: Node, card: Node, pid: int) -> void:
	var n: int = 8 - EnterScript._hand(main, pid).size()
	if n <= 0:
		return
	await ActionModule.draw(pid, n, _name(card), true)
	if n > 4 and main._gold_manager:
		main._gold_manager.set_no_more_cards_this_turn(pid)
		main._update_debug("%s: robaste más de cuatro cartas; no puedes jugar más cartas este turno" % _name(card))


static func _juicio(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var target: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, false)
	if not is_instance_valid(target):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(target))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))
	if is_instance_valid(target):
		await ActionModule.destroy([target], card, true)


static func _semilla(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	while true:
		var shown := _reveal_until(main, opp, _name(card), func(s): return not s.is_empty() and int(s[-1].get("tipo", -1)) == Constants.CardType.ORO)
		for d in shown:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(opp, d)
		# "Cuando se resuelva, puedes pagar un Oro para repetir su efecto."
		if CardManager.get_deck(opp).is_empty() or not main._gold_manager or not main._gold_manager.puede_pagar(1, -1, "", -1, pid):
			return
		if not await EnterScript._confirm(main, pid, _name(card), "Pagar un Oro para repetir el efecto") \
				or not await PlayerSideScript.pay(main, pid, 1):
			return


static func _whitby(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var costs: Array = []
	var shown := _reveal_until(main, opp, _name(card), func(s):
		if s.is_empty():
			return false
		var last: Dictionary = s[-1]
		if int(last.get("tipo", -1)) == Constants.CardType.ALIADO and not costs.has(int(last.get("coste", 0))):
			costs.append(int(last.get("coste", 0)))
		return costs.size() >= 2)
	var deck: Array = CardManager.get_deck(opp)
	for d in shown:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(opp)
	AnimationQueue.queue_shuffle(opp, "Barajar mazo (%s)" % _name(card))
	if costs.size() < 2:
		return
	if costs.max() > 0:
		await ActionModule.mill(opp, costs.max(), false, _name(card))
	if costs.min() > 0:
		await ActionModule.draw(pid, costs.min(), _name(card), true)


static func _desembarco(main: Node, card: Node, _pid: int) -> void:
	var borrowed := _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and c.get("owner_id") != null and int(c.owner_id) != CardQuery.controller_of(c))
	for c in borrowed:
		await EnterScript.bounce_to_owner_hand(main, c, card)


static func _momificar(main: Node, card: Node, pid: int) -> void:
	if not main.get("_gold_manager"):
		return
	for p in [pid, 1 - pid]:
		var entries: Array = CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.ALIADO})
		if not entries.any(func(e): return e.eligible):
			continue
		var raw: Array = await ActionModule.pick_in_zones(p, "%s: elige un Aliado de tu Cementerio para ponerlo en juego" % _name(card),
			[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 1, 1)
		if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2 or int(raw[0][1]) < 0 or int(raw[0][1]) >= entries.size():
			continue
		var e: Dictionary = entries[int(raw[0][1])]
		if not e.eligible or not CardManager.take_from_cemetery(p, e.data):
			continue
		var data: Dictionary = e.data.duplicate()
		data["esta_oculta"] = false
		var node: Node = main._create_card(data, false)
		node.owner_id = p
		node.controller_id = p
		main._connect_card_signals(node)
		await main._gold_manager._play_card_to_field(node)


static func _de_rodillas(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados oponentes" % _name(card), rivals, 2, true)
	for c in chosen:
		if not is_instance_valid(c):
			continue
		await KeywordManager.silence_card(c, card, "turn")
		ContinuousEffectManager.register_modifier({
			"source": c, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 0, "operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
			"description": "%s: Fuerza 0" % _name(card),
		})
		if c.has_method("refresh_strength_badge"):
			c.refresh_strength_badge()


static func _gusano(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty():
		return
	var from_top := true
	if not PlayerSideScript.is_bot(pid):
		from_top = await SelectionManager.await_two_choice(main, _name(card), "Del tope", "Del fondo", pid)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_front() if from_top else deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _choque_colosos(main: Node, card: Node, pid: int) -> void:
	var allies := _in_play_both(main, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado en juego" % _name(card), allies, false)
	if not is_instance_valid(chosen):
		return
	var budget: int = EnterScript._cost(chosen)
	if budget > 0:
		await ActionModule.draw(pid, budget, _name(card), true)
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and EnterScript._cost(c) >= 1 and EnterScript._cost(c) <= budget)
	if rivals.is_empty():
		return
	var picked: Array = []
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		var total := 0
		for c in rivals:
			if total + EnterScript._cost(c) <= budget:
				picked.append(c)
				total += EnterScript._cost(c)
	else:
		var fits := func(so_far: Array, c: Node) -> bool:
			var total := 0
			for x in so_far:
				total += EnterScript._cost(x)
			return total + EnterScript._cost(c) <= budget
		picked = await main._card_interaction.await_multi_target(
			"%s: Destruye cartas oponentes cuyos costes sumen %d o menos" % [_name(card), budget], rivals, -1, Callable(), fits, true, null, pid)
	if not picked.is_empty():
		await ActionModule.destroy(picked, card, true)


static func _juramento(main: Node, card: Node, pid: int) -> void:
	if not main.get("_gold_manager"):
		return
	var pools: Array = []
	var owners: Array = []
	for p in [pid, 1 - pid]:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d,
				"eligible": int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2})})
		owners.append(p)
	if not pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: juega un Aliado de coste 2 o menos de un Cementerio" % _name(card), pools, 1, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var d: Dictionary = pools[pi].cards[ci].data
	if CardManager.take_from_cemetery(owners[pi], d):
		d["esta_oculta"] = false
		if not await main._gold_manager.play_card_for_free(d, pid):
			CardManager.add_to_cemetery(owners[pi], d)


static func _bojutsu(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		for g in PlayerSideScript.gold_reserva(main, p).get_children():
			if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO:
				await EnterScript._blank(g, card)
	for p in [pid, 1 - pid]:
		await ActionModule.search_zones(p, [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO], {"type": Constants.CardType.ORO}, 1, true)


static func _festin_orco(main: Node, card: Node, pid: int) -> void:
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.ORO})
	if not entries.any(func(e): return e.eligible) or not main._gold_manager:
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta dos Oros de tu Cementerio a tu Oro Pagado" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 2)
	var picked: Array = []
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size() \
				and entries[int(rp[1])].eligible and not picked.has(entries[int(rp[1])].data) and picked.size() < 2:
			picked.append(entries[int(rp[1])].data)
	for d in picked:
		if CardManager.take_from_cemetery(pid, d):
			await main._gold_manager.put_gold_directly_in_pagado(pid, d)


static func _stevenson(main: Node, card: Node, pid: int) -> void:
	var targets := _in_play_both(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2) and c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await PlayerSideScript.pick_in_play(main, pid,
		"%s: convierte una carta de coste 2 o menos en tu Tótem sin habilidad" % _name(card), func(c: Node) -> bool: return c in targets,
		false, [1 - pid])
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, pid)
	await TriggerSystem._effect_interpreter.try_execute(card, "muestra cartas del tope de tu castillo hasta mostrar un aliado y ponlo en tu mano", pid)


static func _falso_profeta(main: Node, card: Node, pid: int) -> void:
	while true:
		var deck: Array = CardManager.get_deck(pid)
		if deck.is_empty():
			return
		var d: Dictionary = deck.pop_front()
		main._update_debug("%s muestra: %s" % [_name(card), str(d.get("nombre", "?"))])
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(pid, [d], _name(card))
		d["esta_oculta"] = false
		if int(d.get("tipo", -1)) != Constants.CardType.ALIADO:
			PlayerSideScript.put_in_hand(main, pid, d)
			if main.get("_zone_manager"):
				main._zone_manager._update_castillo_counts()
			return
		CardManager.add_to_cemetery(pid, d)
		await ActionModule.mill(1 - pid, 2, false, _name(card))
		# "Puedes repetir este efecto hasta que Robes una carta que no sea Aliado."
		if not await EnterScript._confirm(main, pid, _name(card), "Repetir el efecto"):
			return


static func _conocimiento(main: Node, card: Node, pid: int) -> void:
	var is_tal := func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN
	var mine: Array = await AttackScript._pick_from_castle(pid, pid, "%s: un Talismán de coste 3 o menos de tu Castillo" % _name(card),
		func(d): return is_tal.call(d) and int(d.get("coste", 0)) <= 3, 1, 1, false)
	var theirs: Array = await AttackScript._pick_from_castle(1 - pid, pid, "%s: un Talismán del Castillo oponente" % _name(card),
		is_tal, 1, 1, false)
	var found: Array = []
	for d in mine:
		found.append({"data": d, "owner": pid})
	for d in theirs:
		found.append({"data": d, "owner": 1 - pid})
	if found.is_empty():
		return
	var play_idx := 0
	if found.size() == 2 and not PlayerSideScript.is_bot(pid):
		play_idx = 0 if await SelectionManager.await_two_choice(main, "%s: ¿cuál juegas sin pagar su coste?" % _name(card),
			str(found[0].data.get("nombre", "")), str(found[1].data.get("nombre", "")), pid) else 1
	for i in found.size():
		var f: Dictionary = found[i]
		f.data["esta_oculta"] = false
		if i != play_idx:
			CardManager.append_to_exile(f.owner, f.data)
	if main._gold_manager and not await main._gold_manager.play_card_for_free(found[play_idx].data, pid):
		CardManager.add_to_cemetery(found[play_idx].owner, found[play_idx].data)


