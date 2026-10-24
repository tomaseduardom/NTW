extends "res://scripts/core/effects/mechanics/ActivatedPatternsZonas.gd"
## ActivatedPatternsManoCementerio — familia ManoCementerio de ActivatedPatterns.gd (ver ActivatedPatternsBase.gd).


# =============================================================================
# TERCER LOTE
# =============================================================================


static func _interp(card: Node, text: String, pid: int) -> bool:
	return await TriggerSystem._effect_interpreter.try_execute(card, text, pid)


static func _exile_self(card: Node, pid: int) -> bool:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	return await EffectController.exile_card(owner, card, true, card)


## "puedes pagarlo y convertirlo en un Oro sin habilidad": al Oro Pagado y sin habilidad.
static func _pay_self_blank(main: Node, card: Node) -> void:
	await LeavePlayScript._gold_to_paid(main, card)
	await EnterScript._blank(card, card)


static func _flor_de_lis(main: Node, card: Node, pid: int) -> void:
	var golds: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
	var gold: Node = await EnterScript._pick_from(main, pid, "%s: Descarta un Oro" % _name(card), golds, true)
	if not is_instance_valid(gold):
		return
	await ActionModule.discard(pid, [gold], _name(card), true)
	# Sólo los de coste 2 o menos pueden ser cancelados: el resto se aparta mientras se elige.
	var keep: Array = GameManager.attackers.filter(func(a): return is_instance_valid(a) and EnterScript._cost(a) > 2)
	for a in keep:
		GameManager.attackers.erase(a)
	await _interp(card, "cancela el ataque de hasta 2 aliados", pid)
	for a in keep:
		if is_instance_valid(a) and not (a in GameManager.attackers):
			GameManager.attackers.append(a)


static func _pulsera_energia(main: Node, card: Node, pid: int) -> void:
	await ActionModule.destroy([card], card, false, true)
	await _interp(card, "cancela el ataque de 1 aliado", pid)


static func _abadon(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, false, true)
	if obj.is_empty():
		main._update_debug("%s: no hay una habilidad que cancelar" % _name(card))
		return
	var totems: Array = EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	var t: Node = await EnterScript._pick_from(main, pid, "%s: sube un Tótem que controles a la mano" % _name(card), totems, true)
	if not is_instance_valid(t) or not await EnterScript.bounce_to_owner_hand(main, t, card):
		return
	StackAnnulScript.apply(obj, card)


static func _nido_dragon(main: Node, card: Node, pid: int) -> void:
	var hand_size: int = EnterScript._hand(main, pid).size()
	var obj: Dictionary = StackAnnulScript.find_target(pid, false, true, func(o): return StackAnnulScript.cost_of(o) <= hand_size)
	if obj.is_empty():
		main._update_debug("%s: no hay una habilidad que puedas cancelar" % _name(card))
		return
	var n: int = StackAnnulScript.cost_of(obj)
	if n > 0:
		await EnterScript._discard_own(main, card, pid, n)
	StackAnnulScript.apply(obj, card)


static func _libro_obras(main: Node, card: Node, pid: int) -> void:
	if EnterScript._golds(main, [1 - pid]).size() < EnterScript._golds(main, [pid]).size() + 2:
		main._update_debug("%s: tu oponente debe controlar dos o más Oros que tú" % _name(card))
		return
	await EnterScript._blank(card, card)
	var paid: Array = []
	for side in [1 - pid, pid]:
		var cont: Node = main.player_oro_pagado if side == 0 else main.opponent_oro_pagado
		if cont:
			paid.append_array(cont.get_children().filter(func(c): return is_instance_valid(c)))
	var g: Node = await EnterScript._pick_from(main, pid, "%s: un Oro del Oro Pagado a la mano de su dueño" % _name(card), paid, true)
	if is_instance_valid(g):
		await EnterScript.bounce_to_owner_hand(main, g, card)


static func _don_belial(main: Node, card: Node, pid: int) -> void:
	await _pay_self_blank(main, card)
	var others: Array = EnterScript._golds(main, [pid]).filter(func(g): return g != card)
	var g: Node = await EnterScript._pick_from(main, pid, "%s: sube otro Oro que controles a la mano" % _name(card), others, true)
	if not is_instance_valid(g) or not await EnterScript.bounce_to_owner_hand(main, g, card):
		return
	var golds: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
	var put: Node = await EnterScript._pick_from(main, pid, "%s: pon un Oro de tu mano en tu Oro Pagado" % _name(card), golds, false)
	if is_instance_valid(put) and main._gold_manager:
		await main._gold_manager.put_gold_directly_in_pagado(pid, PlayerSideScript.take_from_hand(main, pid, put))


static func _ultima_bestia(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false)
	var annul := not obj.is_empty()
	if annul and not PlayerSideScript.is_bot(pid):
		annul = await SelectionManager.await_two_choice(main, _name(card), "Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "")),
			"Jugar un Aliado de tu Cementerio por un Oro menos", pid)
	if annul:
		StackAnnulScript.apply(obj, card)
		return
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
	var ok := func(d): return _is_ally(d) and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de tu Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _totem_to_ally_until_final(main: Node, card: Node, pid: int, furia: bool) -> void:
	var totems: Array = EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	var t: Node = await EnterScript._pick_from(main, pid, "%s: un Tótem pasa a ser Aliado de Fuerza igual a su coste" % _name(card), totems, true)
	if not is_instance_valid(t) or await ConvertScript.conversion_prevented(t, card):
		return
	var tp = TriggerSystem._totem_patterns
	tp._convert_totem_to_ally(t, pid, EnterScript._cost(t), "%s: Fuerza igual a su coste" % _name(card))
	tp._metropolitan_pending_reverts[t] = true  # vuelve a ser Tótem en la Fase Final
	if furia:
		KeywordManager.grant_keyword(t, Constants.Keyword.FURIA, card, "turn")


static func _puerta_firmamento(main: Node, card: Node, pid: int) -> void:
	await _totem_to_ally_until_final(main, card, pid, true)


static func _yggdrasil(main: Node, card: Node, pid: int) -> void:
	await _totem_to_ally_until_final(main, card, pid, false)


## Muestra cartas del tope hasta que 'match' se cumple; esa va a la mano y el resto se baraja.
static func _reveal_until_to_hand(main: Node, card: Node, pid: int, match: Callable, dest: int = Constants.Zone.MANO) -> Dictionary:
	var shown := TalismanScript._reveal_until(main, pid, _name(card), func(s): return not s.is_empty() and match.call(s[-1]))
	var found: Dictionary = shown[-1] if not shown.is_empty() and match.call(shown[-1]) else {}
	if not found.is_empty():
		await load("res://scripts/ui/zones/RevealWindow.gd").show_cards(main, pid, [found], _name(card),
			"Va a tu Cementerio" if dest == Constants.Zone.CEMENTERIO else "Va a tu mano")
	var deck: Array = CardManager.get_deck(pid)
	for d in shown:
		if d != found:
			d["esta_oculta"] = true
			deck.append(d)
	if not found.is_empty():
		if dest == Constants.Zone.CEMENTERIO:
			found["esta_oculta"] = false
			CardManager.add_to_cemetery(pid, found)
		else:
			PlayerSideScript.put_in_hand(main, pid, found)
	CardManager.shuffle_deck(pid)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return found


static func _monte_hermon(main: Node, card: Node, pid: int) -> void:
	var hand: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM])
	var cost_card: Node = await EnterScript._pick_from(main, pid, "%s: Descarta un Aliado o Tótem" % _name(card), hand, true)
	if not is_instance_valid(cost_card):
		return
	await ActionModule.discard(pid, [cost_card], _name(card), true)
	await _reveal_until_to_hand(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)


static func _manicomio_activa(main: Node, card: Node, pid: int) -> void:
	await _reveal_until_to_hand(main, card, pid, func(d): return _is_ally(d) and int(d.get("coste", 0)) <= 2)


static func _tuyango(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self(card, pid):
		return
	await _reveal_until_to_hand(main, card, pid, func(d): return _is_ally(d) and int(d.get("fuerza", 0)) >= 5, Constants.Zone.CEMENTERIO)


static func _plaza_armas_activa(main: Node, card: Node, pid: int) -> void:
	await _reveal_until_to_hand(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA)
	_restricted_gold(main, pid, 1, func(t, _r, c): return t == Constants.CardType.ARMA and int(c) >= 2, "%s: Oro para Armas de coste 2 o más" % _name(card))


static func _altar_juramento(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self(card, pid):
		return
	var cem: Array = CardManager.get_cemetery(pid).duplicate()
	cem.shuffle()
	for d in cem.slice(0, 2):
		if CardManager.take_from_cemetery(pid, d):
			PlayerSideScript.put_in_hand(main, pid, d)


static func _principe_orion(main: Node, card: Node, pid: int) -> void:
	var ok: bool = EnterScript._in_play(main, pid, func(c): return c.get("current_zone") == Constants.Zone.LINEA_ATAQUE).size() > 0 \
		or _allies(main, pid).any(func(c): return c.get("equipped_weapons") is Array and c.equipped_weapons.any(func(w): return is_instance_valid(w) and EnterScript._cost(w) >= 1))
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN)
	if not ok or obj.is_empty():
		main._update_debug("%s: no se cumple la condición o no hay un Talismán que Anular" % _name(card))
		return
	if await _exile_self(card, pid):
		StackAnnulScript.apply(obj, card)


static func _pazuzu(main: Node, card: Node, pid: int) -> void:
	if await _exile_self(card, pid):
		RuleState.set_until("opp_effect_immune", pid, GameManager.turn_serial)


static func _garshasp(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = []
	for _i in mini(4, deck.size()):
		shown.append(deck.pop_front())
	if shown.is_empty():
		return
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	var options: Array = shown.filter(func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ORO])
	if not options.is_empty():
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and options.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: un Aliado u Oro a tu mano" % _name(card),
				options.map(func(d): return str(d.get("nombre", ""))), pid), 0, options.size() - 1)
		shown.erase(options[idx])
		PlayerSideScript.put_in_hand(main, pid, options[idx])
	# Las demás mostradas vuelven al Castillo y se Baraja.
	RevealedCardsScript.shuffle_back(main, pid, shown, _name(card))


static func _desafiante(main: Node, card: Node, pid: int) -> void:
	var cheap := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
	var full := func(d) -> int: return int(d.get("coste", 0))
	var ok_cheap := func(d): return _is_ally(d) and _payable(main, pid, cheap).call(d)
	var ok_full := func(d): return _is_ally(d) and _payable(main, pid, full).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de tu mano o Cementerio (un Oro menos) o de tu Destierro" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok_cheap}, {"owner": pid, "zone": Constants.Zone.DESTIERRO, "eligible": ok_full}], ok_cheap)
	if taken.is_empty():
		return
	var price: int = full.call(taken.data) if int(taken.zone) == Constants.Zone.DESTIERRO else cheap.call(taken.data)
	await _play_taken(main, pid, taken, price)


static func _milena(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma de tu mano o Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _husar_cazador(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return int(d.get("coste", 0))
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma de tu Cementerio pagando su coste" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _taka_no_me(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO):
		return
	var hand: Array = EnterScript._hand(main, opp).duplicate()
	hand.shuffle()
	var seen: Array = hand.slice(0, 3)
	if seen.is_empty():
		return
	var chosen: Node = seen[0]
	if not PlayerSideScript.is_bot(pid):
		var idx: int = clampi(await SelectionManager.await_choice(main, "%s: no podrá ser jugada hasta tu próximo turno" % _name(card),
			seen.map(func(c): return EnterScript._name(c)), pid), 0, seen.size() - 1)
		chosen = seen[idx]
	else:
		seen.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		chosen = seen[0]
	if main._gold_manager and is_instance_valid(chosen):
		main._gold_manager.lock_card_from_playing(chosen, pid)


static func _wani(main: Node, card: Node, pid: int) -> void:
	await ActionModule.destroy([card], card, false, true)
	_restricted_gold(main, pid, 1, func(t, _r, c): return t == Constants.CardType.ALIADO and int(c) >= 3, "%s: Oro para Aliados de coste 3 o más" % _name(card))


static func _shamisen(main: Node, card: Node, pid: int) -> void:
	if GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
		main._update_debug("%s: sólo en Guerra de Talismanes" % _name(card))
		return
	if await _exile_self(card, pid):
		_restricted_gold(main, pid, 1, func(t, _r, _c): return t == Constants.CardType.TALISMAN, "%s: Oro para Talismanes" % _name(card))


static func _la_luna(main: Node, card: Node, pid: int) -> void:
	_restricted_gold(main, pid, 1, func(t, _r, _c): return t == Constants.CardType.TOTEM, "%s: Oro para jugar un Tótem" % _name(card))


static func _castillo_edo(main: Node, card: Node, pid: int) -> void:
	var opp_type := -1
	for p in [pid, 1 - pid]:
		var deck: Array = CardManager.get_deck(p)
		if deck.is_empty():
			continue
		var d: Dictionary = deck.pop_front()
		main._update_debug("%s: J%d muestra %s" % [_name(card), p + 1, str(d.get("nombre", "?"))])
		RevealedCardsScript.record(p, [d], _name(card))
		if p != pid:
			opp_type = int(d.get("tipo", -1))
		if p != pid and opp_type == Constants.CardType.ORO and main._gold_manager:
			await main._gold_manager.put_gold_directly_in_pagado(pid, d)  # "si mostró un Oro, ponlo en tu Oro Pagado"
		else:
			PlayerSideScript.put_in_hand(main, p, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if opp_type >= 0:
		RuleState.set_until("type_play_toll:%d" % opp_type, 1 - pid, RuleState.next_own_turn(pid) - 1)  # PaymentManager


static func _karl_red(main: Node, card: Node, pid: int) -> void:
	if not is_instance_valid(await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO, "muestra un Aliado de tu mano")):
		return
	var opp: int = 1 - pid
	var before: int = CardManager.get_cemetery(opp).size()
	await ActionModule.mill(opp, 3, false, _name(card))
	var milled: Array = CardManager.get_cemetery(opp).slice(before)
	if milled.any(func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ORO, Constants.CardType.ALIADO]):
		await _interp(card, "puedes poner un oro de un cementerio en tu oro pagado", pid)


static func _el_fantasma_activa(main: Node, card: Node, pid: int) -> void:
	var opp_cards: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var t: Node = await EnterScript._pick_from(main, pid, "%s: paga el coste de una carta oponente" % _name(card), opp_cards, true)
	if not is_instance_valid(t) or not await _pay_gold(main, pid, EnterScript._cost(t)):
		return
	var data: Dictionary = t.card_data.duplicate() if t.get("card_data") is Dictionary else {}
	var owner: int = int(t.owner_id) if t.get("owner_id") != null else 1 - pid
	await EnterScript._blank(t, card)
	await ActionModule.destroy([t], card, true)
	if data.is_empty():
		return
	for d in CardManager.get_cemetery(owner):
		if str(d.get("nombre", "")) == str(data.get("nombre", "")):
			if CardManager.take_from_cemetery(owner, d):
				if not await TalismanScript._play_paying(main, pid, d, 0):
					CardManager.add_to_cemetery(owner, d)
			break


static func _lord_blagrot(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: un Talismán de tu Cementerio pasa a ser Leyaden" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["nombre"] = "Leyaden"
			data["habilidad"] = "Una vez por turno, tu oponente Bota una carta."
			await LeavePlayScript._ally_from_data(main, data, pid, pid, card, 1, [], "")


static func _fusil_patriota(main: Node, card: Node, pid: int) -> void:
	var taken := await _take_from_pools(main, pid, "%s: un Aliado de tu Castillo o Cementerio a tu mano" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": func(d): return _is_ally(d)},
		{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": func(d): return _is_ally(d)}])
	if not taken.is_empty():
		PlayerSideScript.put_in_hand(main, pid, taken.data)
	RuleState.set_turn_data("fusil_patriota:%d" % pid, {"base": RuleState.count("ally2_played", pid)})  # PaymentManager
	PaymentManager.invalidate_cache()


static func _mina_maldita(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var hand: Array = EnterScript._hand(main, opp)
	var draw := hand.is_empty()
	if not draw and not PlayerSideScript.is_bot(pid):
		draw = await SelectionManager.await_two_choice(main, _name(card), "Robar dos cartas", "Una carta al azar de la mano oponente a tu Oro Pagado", pid)
	if draw:
		await ActionModule.draw(pid, 2, _name(card), true)
		return
	var c: Node = hand[randi() % hand.size()]
	var data: Dictionary = PlayerSideScript.take_from_hand(main, opp, c)
	data["habilidad"] = ""
	data["tipo"] = Constants.CardType.ORO
	if main._gold_manager:
		await main._gold_manager.put_gold_directly_in_pagado(pid, data)


static func _estrella_solitaria(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	var taken := await _take_from_pools(main, pid, "%s: una carta que no sea Talismán de tu Castillo" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN}])
	if not taken.is_empty():
		PlayerSideScript.put_in_hand(main, pid, taken.data)


static func _primer_escudo(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN)
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if obj.is_empty() or allies.size() < 2:
		main._update_debug("%s: necesitas un Talismán que Anular y dos Aliados en tu mano" % _name(card))
		return
	await EnterScript._blank(card, card)
	if not await _pay_gold(main, pid, 1):
		return
	var two: Array = await EnterScript._pick_many(main, pid, "%s: muestra dos Aliados de tu mano" % _name(card), allies, 2, false)
	main._update_debug("%s: muestra %s" % [_name(card), ", ".join(two.map(func(c): return EnterScript._name(c)))])
	StackAnnulScript.apply(obj, card)


static func _allan_quatermain(main: Node, card: Node, pid: int) -> void:
	var t: Node = await _pick_in_play(main, pid, "%s: una carta que no sea Oro pierde la habilidad y es Destruida" % _name(card),
		func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	if is_instance_valid(t):
		await EnterScript._blank(t, card)
		await ActionModule.destroy([t], card, true)


static func _otto_lidenbrock(main: Node, card: Node, pid: int) -> void:
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA
	var hand_weapons: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ARMA)
	var cem_weapons: Array = CardManager.get_cemetery(pid).filter(ok)
	if hand_weapons.is_empty() and cem_weapons.is_empty():
		return
	main._update_debug("%s: muestra un Arma" % _name(card))
	var in_play: Array = []
	for side in [1 - pid, pid]:
		in_play.append_array(EnterScript._in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3)))
	var from_play := not in_play.is_empty()
	if from_play and not PlayerSideScript.is_bot(pid):
		from_play = await SelectionManager.await_two_choice(main, _name(card), "Una carta en juego de coste 3 o menos", "Una carta de un Cementerio", pid)
	if from_play:
		var t: Node = await _pick_in_play(main, pid, "%s: pasa a ser tu Aliado de Fuerza 2 sin habilidad" % _name(card), func(c): return c in in_play)
		if not is_instance_valid(t) or await ConvertScript.conversion_prevented(t, card):
			return
		var data: Dictionary = t.card_data.duplicate()
		var owner: int = int(t.owner_id) if t.get("owner_id") != null else pid
		await ActionModule.banish([t], card, true)  # deja el juego para volver convertida
		var ex: Array = CardManager.get_exile(owner)
		for d in ex:
			if str(d.get("nombre", "")) == str(data.get("nombre", "")):
				ex.erase(d)
				CardManager._emit_exile_changed(owner)
				break
		await LeavePlayScript._ally_from_data(main, data, owner, pid, card, 2, [], "")
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: una carta de un Cementerio como Aliado de Fuerza 2" % _name(card), 0, 1)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			await LeavePlayScript._ally_from_data(main, pk.data, pk.owner, pid, card, 2, [], "")


static func _ahab(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if RuleState.count("played_any", opp) + RuleState.count("abilities_used", opp) <= 1:
		main._update_debug("%s: tu oponente no jugó cartas ni utilizó habilidades más de una vez este turno" % _name(card))
		return
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)


static func _medalla_legba(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if RuleState.count("played_any", opp) + RuleState.count("abilities_used", opp) <= 2 \
			or not _allies(main, pid).any(func(c): return KeywordManager.has_keyword(c, Constants.Keyword.FURIA)):
		main._update_debug("%s: no se cumple la condición" % _name(card))
		return
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty() or not main._gold_manager:
		return
	var data: Dictionary = deck.pop_front()
	data["habilidad"] = ""
	data["tipo"] = Constants.CardType.ORO
	await main._gold_manager.put_gold_directly_in_pagado(pid, data)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _james_moriarty(main: Node, card: Node, pid: int) -> void:
	if CardManager.get_exile(1 - pid).size() < 8:
		main._update_debug("%s: tu oponente necesita ocho o más cartas en su Destierro" % _name(card))
		return
	var others: Array = _allies(main, pid).filter(func(c): return c != card)
	var victim: Node = await EnterScript._pick_from(main, pid, "%s: Destruye otro Aliado que controles" % _name(card), others, true)
	if not is_instance_valid(victim):
		return
	await ActionModule.destroy([victim], card, true)
	DamageShieldsScript.add_next_zero(pid)


static func _escritura_sagrada(main: Node, card: Node, pid: int) -> void:
	var to_hand := true
	if not PlayerSideScript.is_bot(pid):
		to_hand = await SelectionManager.await_two_choice(main, _name(card), "Subirlo a tu mano", "Convertirlo en un Oro sin habilidad", pid)
	if to_hand:
		if not await EnterScript.bounce_to_owner_hand(main, card, card):
			return
	else:
		await EnterScript._blank(card, card)
	DamageShieldsScript.add_next_zero(pid)


static func _dulgruss(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var taken := await _take_from_pools(main, pid, "%s: un Aliado de tu Castillo para jugarlo bajo el control de tu oponente" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": func(d): return _is_ally(d) and _payable(main, pid, price).call(d)}])
	if taken.is_empty():
		return
	var name := str(taken.data.get("nombre", ""))
	if not await _play_taken(main, pid, taken, price.call(taken.data)):
		return
	for c in _allies(main, pid):
		if EnterScript._name(c) == name:
			ContinuousEffectManager.gain_control_of_card(c, 1 - pid)
			break


static func _zagovornik(main: Node, card: Node, pid: int) -> void:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: un Talismán al Cementerio" % _name(card),
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN, 0, 1, false)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(pid, d)
		_grant_exhumar([d])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _craneos_vivos(main: Node, card: Node, pid: int) -> void:
	await _pay_self_blank(main, card)
	var types: Dictionary = {}
	for p in [0, 1]:
		for d in CardManager.get_exile(p):
			types[int(d.get("tipo", -1))] = true
	if not types.is_empty():
		await ActionModule.mill(1 - pid, types.size(), false, _name(card))

# =============================================================================
# CUARTO LOTE: DESDE LA MANO, EL CEMENTERIO O EL ORO PAGADO
# =============================================================================


## Saca la propia carta de su zona (mano, Cementerio, Destierro) y devuelve sus datos. {} si ya no está
## (p.ej. el Paso B de la Pila ya pagó "Desterrarlo de tu Cementerio"); 'already' dice si ya no estaba.
static func _take_self(main: Node, card: Node, pid: int) -> Dictionary:
	if not is_instance_valid(card) or card.get("card_data") == null:
		return {}
	var zone = card.get("current_zone")
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	match zone:
		Constants.Zone.MANO:
			return PlayerSideScript.take_from_hand(main, owner, card)
		Constants.Zone.CEMENTERIO:
			var d: Dictionary = _find_data(CardManager.get_cemetery(owner), card.card_data)
			if not d.is_empty() and CardManager.take_from_cemetery(owner, d):
				return d
		Constants.Zone.DESTIERRO:
			var ex: Array = CardManager.get_exile(owner)
			var d2: Dictionary = _find_data(ex, card.card_data)
			if not d2.is_empty():
				ex.erase(d2)
				CardManager._emit_exile_changed(owner)
				return d2
	return {}


static func _find_data(arr: Array, data: Dictionary) -> Dictionary:
	for d in arr:
		if d == data or (str(d.get("id", "-")) == str(data.get("id", "+")) and str(d.get("nombre", "")) == str(data.get("nombre", ""))):
			return d
	return {}


## "Desterrarlo" (de la mano / Cementerio / en juego) como costo. true si se pagó o ya estaba pagado.
static func _exile_self_cost(main: Node, card: Node, pid: int) -> bool:
	if not is_instance_valid(card):
		return true  # ya lo pagó el Paso B
	var zone = card.get("current_zone")
	if zone in Constants.ZONES_IN_PLAY:
		return await _exile_self(card, pid)
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return zone != Constants.Zone.MANO  # del Cementerio ya no estaba: pagado
	d["esta_oculta"] = false
	CardManager.append_to_exile(owner, d)
	return true


## "Jugarlo" desde la mano o el Cementerio pagando 'price'.
static func _play_self(main: Node, card: Node, pid: int, price: int) -> void:
	var zone = card.get("current_zone") if is_instance_valid(card) else null
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return
	if not await TalismanScript._play_paying(main, pid, d, price):
		if zone == Constants.Zone.MANO:
			PlayerSideScript.put_in_hand(main, pid, d)
		else:
			CardManager.add_to_cemetery(pid, d)


static func _hikari_no_ga(main: Node, card: Node, pid: int) -> void:
	await ActionModule.mill(pid, 2, false, _name(card))
	await _play_self(main, card, pid, int(card.card_data.get("coste", 0)))


static func _el_carro(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	await _play_self(main, card, pid, int(card.card_data.get("coste", 0)))


## andras, iki balam, los korgors: "Si atacaste en tu turno anterior, puedes pagar un Oro para jugarlo sin
## pagar su coste".
static func _attacked_free_play(main: Node, card: Node, pid: int) -> void:
	if not BattleManager.attacked_in_previous_own_turn(pid):
		main._update_debug("%s: no atacaste en tu turno anterior" % _name(card))
		return
	if not await _pay_gold(main, pid, 1):
		return
	await _play_self(main, card, pid, 0)


static func _daikaiju_furioso(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1) or not main._gold_manager:
		return
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return
	var gold: Dictionary = d.duplicate()
	gold["habilidad"] = ""
	gold["tipo"] = Constants.CardType.ORO
	await main._gold_manager.put_gold_directly_in_pagado(pid, gold)


static func _orco_alpino(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "Orco Alpino: un Aliado pierde 2 de Fuerza", EnterScript._all_allies(main), false)
	if is_instance_valid(ally):
		await _buff(ally, null, -2)


static func _gusano_haftvad(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1) or not await _exile_self_cost(main, card, pid):
		return
	RuleState.set_turn_data("cancel_next_ability:%d" % (1 - pid), {"by": pid})  # TriggerTollPatterns.consume_cancel_next
	main._update_debug("Gusano de Haftvad: la próxima habilidad que utilice tu oponente este turno será cancelada")


static func _ignis_azotamundos(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Ignis Azotamundos: otro Aliado de tu Cementerio como Titán sin habilidad", 0, 1,
		func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["habilidad"] = ""
			data["nombre"] = "Titán"
			await _put_into_play(main, pid, data, pid)


static func _no_leave_until_next_turn(node: Node, pid: int) -> void:
	node.set_meta("no_leave_until", RuleState.next_own_turn(pid) - 1)  # EffectController.can_leave_play


static func _jared(main: Node, card: Node, pid: int) -> void:
	var small: Array = _allies(main, pid).filter(func(c): return ContinuousEffectManager.cost_at_most(c, 1))
	if small.is_empty() or _allies(main, pid).size() < 2:
		main._update_debug("Jared: necesitas un Aliado de coste 1 o menos y otro Aliado")
		return
	if not await _exile_self_cost(main, card, pid):
		return
	var cost_ally: Node = await EnterScript._pick_from(main, pid, "Jared: Destierra un Aliado de coste 1 o menos que controles", small, false)
	if not is_instance_valid(cost_ally):
		return
	await ActionModule.banish([cost_ally], null, true)
	var other: Node = await EnterScript._pick_from(main, pid, "Jared: otro Aliado queda sin habilidad y no puede salir del juego", _allies(main, pid), false)
	if is_instance_valid(other):
		await EnterScript._blank(other, null)
		other.set_meta("silenced_until", RuleState.next_own_turn(pid) - 1)
		_no_leave_until_next_turn(other, pid)


static func _jafet(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 2) or not await _exile_self_cost(main, card, pid):
		return
	var chosen: Array = await EnterScript._pick_many(main, pid, "Jafet: hasta dos Aliados no pueden salir del juego hasta tu próximo turno",
		EnterScript._all_allies(main), 2, true)
	for c in chosen:
		_no_leave_until_next_turn(c, pid)


static func _pablo_pincheira(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var chosen: Node = await EnterScript._pick_from(main, pid, "Pablo Pincheira: juega un Aliado de tu mano pagando su coste", allies, true)
	if not is_instance_valid(chosen):
		return
	var pincheira: bool = "pincheira" in CemeteryTriggersScript.normalize(EnterScript._name(chosen))
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	if pincheira:
		main._gold_manager._alicanto_paid_pending[pid] = true  # no puede ser Anulado (como Alicanto)
	if not await TalismanScript._play_paying(main, pid, data, int(data.get("coste", 0))):
		main._gold_manager._alicanto_paid_pending.erase(pid)
		PlayerSideScript.put_in_hand(main, pid, data)
		return
	if pincheira:
		for c in _allies(main, pid):
			if EnterScript._name(c) == str(data.get("nombre", "")):
				c.set_meta("protected_from_cancel_turn", GameManager.turn_serial)  # ni sus habilidades canceladas
				break


static func _baphomet(main: Node, card: Node, pid: int) -> void:
	var others: Array = EnterScript._hand(main, pid).filter(func(c): return c != card)
	var cost_card: Node = await EnterScript._pick_from(main, pid, "Baphomet: Descarta una carta de tu mano", others, true)
	if not is_instance_valid(cost_card):
		return
	await ActionModule.discard(pid, [cost_card], _name(card), true)
	await _play_self(main, card, pid, maxi(int(card.card_data.get("coste", 0)) - 1, 0))


static func _palo_del_caos(main: Node, card: Node, pid: int) -> void:
	if card.get("current_zone") != Constants.Zone.ORO_PAGADO:
		main._update_debug("Palo del Caos: solo si está en tu Oro Pagado")
		return
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Palo del Caos: un Aliado de tu Cementerio a tu mano", 0, 1, func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


static func _stegosaurus(main: Node, card: Node, pid: int) -> void:
	if is_instance_valid(card) and card.get("current_zone") == Constants.Zone.MANO:
		await ActionModule.discard(pid, [card], "Dinosaurio Stegosaurus", true)
	var g: Node = await EnterScript._pick_from(main, pid, "Dinosaurio Stegosaurus: un Oro oponente pierde su habilidad por el turno",
		EnterScript._golds(main, [1 - pid]), false)
	if is_instance_valid(g):
		g.set_meta("silenced_on_turn", GameManager.turn_serial)


static func _los_marcados(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	RuleState.set_turn_data("block_cap:%d" % (1 - pid), {"n": 2})  # GameManager.declare_blocker
	main._update_debug("Los Marcados: tu oponente no puede declarar más de dos bloqueadores este turno")


static func _alicia(main: Node, card: Node, pid: int) -> void:
	if EnterScript._golds(main, [pid]).size() > EnterScript._golds(main, [1 - pid]).size():
		main._update_debug("Alicia: controlas más Oros que tu oponente")
		return
	if not await _pay_gold(main, pid, 1) or not main._gold_manager:
		return
	var d := _take_self(main, card, pid)
	if not d.is_empty():
		await main._gold_manager.put_gold_directly_in_pagado(pid, d)


static func _altar_moloch(main: Node, card: Node, pid: int) -> void:
	var mine_there: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and int(c.get("owner_id")) == pid and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var t: Node = await EnterScript._pick_from(main, pid, "Altar de Moloch: paga el coste de una carta tuya que controle tu oponente", mine_there, true)
	if not is_instance_valid(t):
		return
	var name := EnterScript._name(t)
	if not await _pay_gold(main, pid, EnterScript._cost(t)) or not await EnterScript.bounce_to_owner_hand(main, t, card):
		return
	for c in EnterScript._hand(main, pid):
		if EnterScript._name(c) == name:
			var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, c)
			if not await TalismanScript._play_paying(main, pid, data, 0):
				PlayerSideScript.put_in_hand(main, pid, data)
			return


static func _hacha_perun(main: Node, card: Node, pid: int) -> void:
	var bearer = card.get("wielder") if is_instance_valid(card) else null
	var rivals: Array = []
	for attacker in GameManager.blockers:
		var b = GameManager.blockers[attacker]
		if not (is_instance_valid(attacker) and is_instance_valid(b)):
			continue
		if attacker == bearer:
			rivals.append(b)
		elif b == bearer:
			rivals.append(attacker)
	rivals = rivals.filter(func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	var t: Node = await EnterScript._pick_from(main, pid, "Hacha de Perun: Destruye el Aliado de coste 2 o menos", rivals, true)
	if is_instance_valid(t):
		await ActionModule.destroy([t], card, true)
	elif rivals.is_empty():
		main._update_debug("Hacha de Perun: el portador no bloquea ni es bloqueado por un Aliado de coste 2 o menos")


static func _hangaku_gozen(main: Node, card: Node, pid: int) -> void:
	if not (card.get("equipped_weapons") is Array and card.equipped_weapons.any(func(w): return is_instance_valid(w))):
		main._update_debug("Hangaku Gozen: solo si porta Armas")
		return
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and EnterScript._cost(c) <= 2 and not ("hangaku gozen" in CemeteryTriggersScript.normalize(EnterScript._name(c))))
	var chosen: Node = await EnterScript._pick_from(main, pid, "Hangaku Gozen: juega un Aliado de coste 2 o menos sin pagar su coste", allies, true)
	if not is_instance_valid(chosen):
		return
	var name := EnterScript._name(chosen)
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	if not await TalismanScript._play_paying(main, pid, data, 0):
		PlayerSideScript.put_in_hand(main, pid, data)
		return
	var played: Node = null
	for c in _allies(main, pid):
		if EnterScript._name(c) == name:
			played = c
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		if is_instance_valid(played) and played.get("current_zone") in Constants.ZONES_IN_PLAY:
			await EnterScript._blank(played, null)
			await ActionModule.banish([played], null, true))


static func _lord_john_roxton(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Lord John Roxton: un Arma de tu Cementerio a tu mano", 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)
	# "cambiar de portador un Arma que controles": pendiente (no hay una pieza para mover un Arma portada).
