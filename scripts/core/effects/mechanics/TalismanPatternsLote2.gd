extends "res://scripts/core/effects/mechanics/TalismanPatternsCartas.gd"
## TalismanPatternsLote2 — familia Lote2 de TalismanPatterns.gd (ver TalismanPatternsBase.gd).


# =============================================================================
# SEGUNDO LOTE
# =============================================================================


static func _buff_turn(target: Node, card, amount: int, permanent: bool = false) -> void:
	if not is_instance_valid(target) or amount == 0 \
			or await EffectController.offer_prevention(target, card if is_instance_valid(card) else null, "strength_change"):
		return
	ContinuousEffectManager.register_modifier({
		"source": null if permanent else target, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": amount, "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT if permanent else ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY, "description": "%s %+d" % [_name(card), amount],
	})
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()


static func _bounce_up_to(main: Node, card: Node, pid: int, filter: Callable, count: int, prompt: String) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, filter)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: %s" % [_name(card), prompt], rivals, count, true)
	for c in chosen:
		await EnterScript.bounce_to_owner_hand(main, c, card)


static func _favor_corte(main: Node, card: Node, pid: int) -> void:
	await _bounce_up_to(main, card, pid, func(c): return c.get("card_type") != Constants.CardType.ORO, 1,
		"sube una carta oponente que no sea Oro a la mano de su dueño")


static func _descarnados(main: Node, card: Node, pid: int) -> void:
	await _bounce_up_to(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 3), 1,
		"sube un Aliado oponente de coste 3 o menos a la mano de su dueño")


static func _trafalgar(main: Node, card: Node, pid: int) -> void:
	await _bounce_up_to(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 1), 3,
		"sube hasta tres Aliados oponentes de coste 1 o menos a la mano de su dueño")


static func _aliento_letal(main: Node, card: Node, pid: int) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: muestra cinco cartas de un Castillo" % _name(card),
			"Castillo oponente", "Tu Castillo", pid) else pid
	var shown := _reveal_until(main, owner, _name(card), func(s): return s.size() >= 5)
	if shown.is_empty():
		return
	for i in mini(2, shown.size()):
		var idx := 0
		var to_hand := owner == pid
		if not PlayerSideScript.is_bot(pid):
			if shown.size() > 1:
				idx = clampi(await SelectionManager.await_choice(main, "%s: carta %d de 2" % [_name(card), i + 1],
					shown.map(func(d): return str(d.get("nombre", "?"))), pid), 0, shown.size() - 1)
			to_hand = await SelectionManager.await_two_choice(main, str(shown[idx].get("nombre", "")),
				"A la mano de su dueño", "Al Destierro de su dueño", pid)
		var d: Dictionary = shown.pop_at(idx)
		if to_hand:
			PlayerSideScript.put_in_hand(main, owner, d)
		else:
			d["esta_oculta"] = false
			CardManager.append_to_exile(owner, d)
	for d in shown:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(owner, d)


static func _cadena_negra(main: Node, card: Node, pid: int) -> void:
	var no_damage := false
	if not PlayerSideScript.is_bot(pid):
		no_damage = await SelectionManager.await_two_choice(main, _name(card), "Hasta dos Aliados no hacen daño de combate",
			"Hasta dos Aliados ganan 2 de Fuerza", pid)
	var pool: Array = EnterScript._all_allies(main)
	if PlayerSideScript.is_bot(pid):
		pool = pool.filter(func(c): return CardQuery.controller_of(c) == pid)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados" % _name(card), pool, 2, true)
	for c in chosen:
		if not is_instance_valid(c):
			continue
		if no_damage:
			c.set_meta("no_damage_turn", GameManager.turn_serial)  # BattleManager
		else:
			await _buff_turn(c, card, 2)


static func _caceria_impia(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and int(ContinuousEffectManager.get_modified_strength(c)) >= 4)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube un Aliado oponente de Fuerza 4 o más a la mano" % _name(card), rivals, false)
	if is_instance_valid(target):
		await EnterScript.bounce_to_owner_hand(main, target, card)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: hasta cinco cartas de tu Cementerio al fondo de tu Castillo" % _name(card), 0, 5)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			pk.data["esta_oculta"] = true
			CardManager.get_deck(pid).append(pk.data)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _ritual_bestia(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var seen: Array = []
	for _i in mini(6, deck.size()):
		seen.append(deck.pop_front())
	if seen.is_empty():
		return
	var to_cem: Array = []
	if PlayerSideScript.is_bot(pid):
		to_cem = seen.filter(func(d): return int(d.get("tipo", -1)) != Constants.CardType.ORO)
	else:
		SelectionManager.open_reveal(seen, "%s: las primeras seis cartas de tu Castillo" % _name(card), pid)
		var left: Array = seen.duplicate()
		while not left.is_empty():
			var labels: Array = left.map(func(d): return str(d.get("nombre", "?")))
			labels.append("Listo")
			var idx: int = await SelectionManager.await_choice(main, "%s: elige las que van a tu Cementerio" % _name(card), labels, pid)
			if idx < 0 or idx >= left.size():
				break
			to_cem.append(left.pop_at(idx))
	var rest: Array = seen.filter(func(d): return not to_cem.has(d))
	for d in to_cem:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(pid, d)
	for i in range(rest.size() - 1, -1, -1):
		deck.push_front(rest[i])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if to_cem.size() <= 2:
		var small := _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
		if PlayerSideScript.is_bot(pid):
			small = small.filter(func(c): return CardQuery.controller_of(c) != pid)
		var one: Array = await EnterScript._pick_many(main, pid, "%s: Destruye hasta una carta de coste 2 o menos" % _name(card), small, 1, true)
		if not one.is_empty():
			await ActionModule.destroy(one, card, true)


static func _duelo_ganryu(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid))
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 2 de Fuerza permanentemente" % _name(card), allies, false)
	if not is_instance_valid(target):
		return
	await _buff_turn(target, card, 2, true)
	EffectController.add_single_card_leave_play_immunity(target, pid)
	target.set_meta("no_control_change_until", RuleState.next_own_turn(pid) - 1)


static func _copies_in_cemetery(pid: int, card) -> int:  # sin tipo: puede llegar ya liberada
	var name := _name(card).to_lower()
	return CardManager.get_cemetery(pid).filter(func(d): return str(d.get("nombre", "")).to_lower() == name).size()


static func _kabuki(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Fuerza permanentemente" % _name(card), allies, false)
	if is_instance_valid(target):
		await _buff_turn(target, card, 1 + _copies_in_cemetery(pid, card), true)


static func _ubagabi(main: Node, card: Node, pid: int) -> void:
	var n := _copies_in_cemetery(pid, card)  # antes de jugar nada (la carta puede liberarse)
	if main._gold_manager:
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega un Aliado de tu Cementerio pagando su coste" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid))
		for pk in picks:
			if await PlayerSideScript.pay(main, pid, int(pk.data.get("coste", 0))) and CardManager.take_from_cemetery(pid, pk.data):
				pk.data["esta_oculta"] = false
				if not await main._gold_manager.play_card_for_free(pk.data, pid):
					CardManager.add_to_cemetery(pid, pk.data)
	if n > 0:
		var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
		var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana %d de Fuerza" % [_name(card), n], allies, false)
		await _buff_turn(target, card, n)


## aplastar / luz desafiante: juega un Aliado de tu Cementerio por un Oro menos (dos si es de la raza),
## mínimo 1; luego Destierra Aliados de esas razas cuyos costes sumen hasta 3.
static func _revive_and_banish_races(main: Node, card: Node, pid: int, bonus_race: String, races: Array) -> void:
	if main._gold_manager:
		var price := func(d) -> int:
			var red: int = 2 if bonus_race in CemeteryTriggersScript.normalize(str(d.get("raza", ""))) else 1
			return maxi(int(d.get("coste", 0)) - red, 1)
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega un Aliado de tu Cementerio con descuento" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid))
		for pk in picks:
			if await PlayerSideScript.pay(main, pid, price.call(pk.data)) and CardManager.take_from_cemetery(pid, pk.data):
				pk.data["esta_oculta"] = false
				if not await main._gold_manager.play_card_for_free(pk.data, pid):
					CardManager.add_to_cemetery(pid, pk.data)
	var of_race := func(c) -> bool:
		var r := CemeteryTriggersScript.normalize(str(c.get("card_raza")))
		return c.get("card_type") == Constants.CardType.ALIADO and races.any(func(x): return x in r)
	var pool := _in_play_both(main, of_race)
	if PlayerSideScript.is_bot(pid):
		pool = pool.filter(func(c): return CardQuery.controller_of(c) != pid)
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		pool.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		var total := 0
		for c in pool:
			if total + EnterScript._cost(c) <= 3:
				chosen.append(c)
				total += EnterScript._cost(c)
	elif not pool.is_empty():
		var fits := func(so_far: Array, c: Node) -> bool:
			var total := 0
			for x in so_far:
				total += EnterScript._cost(x)
			return total + EnterScript._cost(c) <= 3
		chosen = await main._card_interaction.await_multi_target("%s: Destierra Aliados cuyos costes sumen hasta 3" % _name(card),
			pool, -1, Callable(), fits, true, null, pid)
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)


static func _aplastar(main: Node, card: Node, pid: int) -> void:
	await _revive_and_banish_races(main, card, pid, "daikaiju", ["caballero", "eterno", "guerrero", "heroe"])


static func _luz_desafiante(main: Node, card: Node, pid: int) -> void:
	await _revive_and_banish_races(main, card, pid, "tenshi", ["bestia", "dragon", "faerie", "sombra"])


static func _rugido_origen(main: Node, card: Node, pid: int) -> void:
	var races: Dictionary = {}
	for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		races[CemeteryTriggersScript.normalize(str(c.get("card_raza")))] = true
	var has := func(r: String) -> bool: return races.keys().any(func(k): return r in k)
	if has.call("bestia") and await EnterScript._confirm(main, pid, _name(card), "Bestia: tus Aliados ganan 1 de Fuerza"):
		for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
			await _buff_turn(c, card, 1)
	if has.call("dragon") and main._gold_manager and await EnterScript._confirm(main, pid, _name(card), "Dragón: una carta de tu Cementerio a tu Oro Pagado"):
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: una carta de tu Cementerio como Oro sin habilidad" % _name(card), 1, 1)
		for pk in picks:
			if CardManager.take_from_cemetery(pid, pk.data):
				await EnterScript._data_to_paid_gold(main, pk.data, pid, pid)
	if has.call("sombra") and await EnterScript._confirm(main, pid, _name(card), "Sombra: tu oponente Destierra cuatro cartas del tope de su Castillo"):
		await ActionModule.mill(1 - pid, 4, true, _name(card))


static func _depredar(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 3, 3,
		"%s: hasta tres Aliados cuyos costes sumen 3 o menos" % _name(card))
	chosen = chosen.filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	if not chosen.is_empty():
		await EnterScript._blank_indestructible_zero(card, chosen)


static func _oriflama(main: Node, card: Node, pid: int) -> void:
	var armed := EnterScript._all_allies(main, func(c): return c.get("equipped_weapons") is Array and not c.equipped_weapons.is_empty() \
		and (CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados que porten Armas" % _name(card), armed, 2, true)
	var weapons: int = CardQuery.weapons_in_play(pid).size()
	for c in chosen:
		if not is_instance_valid(c):
			continue
		KeywordManager.grant_keyword(c, Constants.Keyword.FURIA, card, "permanent")
		await _buff_turn(c, card, weapons)
		EffectController.add_single_card_leave_play_immunity(c, pid)


static func _conan_doyle(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var small := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2
	var hand_nodes: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_data") != null and small.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": small.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: juega un Aliado de coste 2 o menos de tu mano o Cementerio" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 1, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var data: Dictionary = {}
	if int(raw[0][0]) == -1:
		var hi := int(raw[0][1])
		if hi < 0 or hi >= hand_nodes.size():
			return
		data = PlayerSideScript.take_from_hand(main, pid, hand_nodes[hi])
	else:
		var ci := int(raw[0][1])
		if ci < 0 or ci >= entries.size() or not entries[ci].eligible or not CardManager.take_from_cemetery(pid, entries[ci].data):
			return
		data = entries[ci].data
	data["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(data, pid):
		CardManager.add_to_cemetery(pid, data)


static func _elemental(main: Node, card: Node, pid: int) -> void:
	var hand := EnterScript._hand(main, 1 - pid)
	if not hand.is_empty():
		var cards: Array = hand
		if hand.size() > 3:
			cards = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, 3, 1 - pid)
		await ActionModule.discard(1 - pid, cards.slice(0, 3), _name(card), true)
	if await EnterScript._confirm(main, pid, _name(card), "Buscar un Aliado Sherlock Holmes en tu Castillo"):
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ALIADO, "name_contains": "sherlock holmes"}, 1, true,
			false, false, card)


static func _murcielagos(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var seen: Array = []
	for _i in mini(6, deck.size()):
		seen.append(deck.pop_front())
	if seen.is_empty():
		return
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(seen, "%s: las primeras seis cartas de tu Castillo" % _name(card), pid)
	await EnterScript._look_place(main, card, pid, pid, seen, ["mano", "mano"])


static func _atacar_vampiro(main: Node, card: Node, pid: int) -> void:
	var all := _in_play_both(main, func(c): return c.get("is_converted") != true)
	var bot_rivals: Array = all.filter(func(c): return CardQuery.controller_of(c) != pid)
	var blank: Node = await EnterScript._pick_from(main, pid, "%s: una carta en juego queda sin habilidad" % _name(card),
		bot_rivals if PlayerSideScript.is_bot(pid) else all, false)
	if is_instance_valid(blank):
		await EnterScript._blank(blank, card)
	var small := EnterScript._in_play(main, 1 - pid, func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	var steal: Node = await EnterScript._pick_from(main, pid, "%s: gana el control de una carta de coste 2 o menos" % _name(card), small, false)
	if is_instance_valid(steal):
		ContinuousEffectManager.gain_control_of_card(steal, pid)


static func _comite_animales(main: Node, card: Node, pid: int) -> void:
	var n: int = EnterScript._all_allies(main, func(c): return not ContinuousEffectManager.cost_at_most(c, 0)).size()
	for i in n:
		var deck: Array = CardManager.get_deck(pid)
		if deck.is_empty():
			break
		var race := "Bestia"
		if not PlayerSideScript.is_bot(pid):
			race = RACES[clampi(await SelectionManager.await_choice(main, "%s: Aliado %d de %d, elige su Raza" % [_name(card), i + 1, n], RACES, pid),
				0, RACES.size() - 1)]
		await LeavePlayScript._ally_from_data(main, deck.pop_front(), pid, pid, card, 2, [Constants.Keyword.FURIA], race)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _sombra_eterea(main: Node, card: Node, pid: int) -> void:
	var named := ""
	var named_type := -1
	if PlayerSideScript.is_bot(pid):
		var rivals := EnterScript._in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		if not rivals.is_empty():
			named = EnterScript._name(rivals[0])
			named_type = int(rivals[0].get("card_type"))
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"%s: nombra una carta: no se pueden utilizar sus habilidades por el turno" % _name(card), pid)
		named = str(picked.get("nombre", ""))
		named_type = int(picked.get("tipo", -1))
	if named.is_empty():
		return
	KeywordManager.lock_name_this_turn(named, -1)
	main._update_debug("%s: no se pueden utilizar habilidades de %s por el turno" % [_name(card), named])
	var shown := _reveal_until(main, pid, _name(card), func(s): return not s.is_empty() and int(s[-1].get("tipo", -1)) == named_type)
	if shown.is_empty():
		return
	var deck: Array = CardManager.get_deck(pid)
	if int(shown[-1].get("tipo", -1)) == named_type:
		PlayerSideScript.put_in_hand(main, pid, shown.pop_back())
	for d in shown:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(pid)
	AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % _name(card))


static func _cancha_rayada(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		var is_w := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) <= 3
		var pools: Array = [
			{"is_own": true, "zone": Constants.Zone.CASTILLO, "exclusive": false, "cards": CardManager.get_deck(pid).map(func(d): return {"data": d, "eligible": is_w.call(d)})},
			{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "exclusive": false, "cards": CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": is_w.call(d)})},
		]
		var raw: Array = await ActionModule.pick_in_zones(pid, "%s: dos Armas cuyos costes sumen hasta 3" % _name(card), pools, 0, 2)
		var picked: Array = []
		var total := 0
		for rp in raw:
			if rp is Array and rp.size() == 2 and int(rp[0]) in [0, 1]:
				var e: Dictionary = pools[int(rp[0])].cards[int(rp[1])] if int(rp[1]) >= 0 and int(rp[1]) < pools[int(rp[0])].cards.size() else {}
				if not e.is_empty() and e.eligible and total + int(e.data.get("coste", 0)) <= 3 and picked.size() < 2:
					picked.append({"zone": int(rp[0]), "data": e.data})
					total += int(e.data.get("coste", 0))
		for pk in picked:
			if pk.zone == 0:
				CardManager.get_deck(pid).erase(pk.data)
			elif not CardManager.take_from_cemetery(pid, pk.data):
				continue
			pk.data["esta_oculta"] = false
			if not await main._gold_manager.play_card_for_free(pk.data, pid):
				CardManager.add_to_cemetery(pid, pk.data)
		CardManager.shuffle_deck(pid)
	EffectController.add_blanket_leave_play_immunity(pid)


static func _descanso_solar(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados ganan o pierden 3 de Fuerza" % _name(card),
		EnterScript._all_allies(main), 2, true)
	for c in chosen:
		if not is_instance_valid(c):
			continue
		var gain: bool = CardQuery.controller_of(c) == pid
		if not PlayerSideScript.is_bot(pid):
			gain = await SelectionManager.await_two_choice(main, "%s: %s" % [_name(card), EnterScript._name(c)], "Gana 3 de Fuerza", "Pierde 3 de Fuerza", pid)
		await _buff_turn(c, card, 3 if gain else -3)
		if is_instance_valid(c) and int(ContinuousEffectManager.get_modified_strength(c)) <= 0:
			await ActionModule.banish([c], card, true)
	var fighters: Array = []
	fighters.append_array(GameManager.attackers)
	fighters.append_array(GameManager.blockers.values())
	for c in fighters:
		if is_instance_valid(c):
			KeywordManager.grant_keyword(c, Constants.Keyword.INDESTRUCTIBLE, card, "turn")


static func _abordaje(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [1 - pid, pid], "%s: una carta de cualquier Cementerio" % _name(card), 1, 1)
	if picks.is_empty() or not CardManager.take_from_cemetery(picks[0].owner, picks[0].data):
		return
	var data: Dictionary = picks[0].data.duplicate()
	data["tipo"] = Constants.CardType.ALIADO
	data["fuerza"] = 0
	data["habilidad"] = "Indestructible. Tus Aliados pierden 2 de Fuerza."
	data["esta_oculta"] = false
	var node: Node = main._create_card(data, false)
	node.owner_id = picks[0].owner
	node.controller_id = 1 - pid
	main._connect_card_signals(node)
	PlayerSideScript.ally_containers(main, 1 - pid)[0].add_child(node)
	node.set_zone(Constants.Zone.LINEA_DEFENSA)
	node.can_interact = (1 - pid == 0)
	if CardFactory and CardFactory.has_method("on_card_enters_play"):
		CardFactory.on_card_enters_play(node)
	KeywordManager.scan_and_apply_keywords(node)
	main._update_debug("%s: %s es ahora un Aliado oponente de Fuerza 0" % [_name(card), str(data.get("nombre", ""))])
