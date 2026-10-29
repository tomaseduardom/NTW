extends "res://scripts/core/effects/mechanics/ActivatedPatternsControl.gd"
## ActivatedPatternsZonas — familia Zonas de ActivatedPatterns.gd (ver ActivatedPatternsBase.gd).


# =============================================================================
# SEGUNDO LOTE: JUGAR DESDE ZONAS
# =============================================================================


## Elige una carta de unos pools (pick_in_zones) y la saca de su zona. {data, owner, zone} o {}.
static func _take_from_pools(main: Node, pid: int, title: String, specs: Array, hand_ok: Callable = Callable()) -> Dictionary:
	# specs: [{owner, zone, eligible: Callable}]
	var pools: Array = []
	for sp in specs:
		var arr: Array
		match int(sp.zone):
			Constants.Zone.CEMENTERIO: arr = CardManager.get_cemetery(sp.owner)
			Constants.Zone.DESTIERRO: arr = CardManager.get_exile(sp.owner)
			_: arr = CardManager.get_deck(sp.owner)
		pools.append({"is_own": sp.owner == pid, "zone": sp.zone, "exclusive": true,
			"cards": arr.map(func(d): return {"data": d, "eligible": sp.eligible.call(d)})})
	var hand_nodes: Array = []
	if hand_ok.is_valid():
		hand_nodes = EnterScript._hand(main, pid).filter(func(c): return c.get("card_data") != null and hand_ok.call(c.card_data))
	if hand_nodes.is_empty() and not pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		return {}
	var info: Dictionary = {}
	var raw: Array = await ActionModule.pick_in_zones(pid, title, pools, 0, 1, false, hand_nodes, info)
	for ci in info.get("opened_castles", []):
		CardManager.shuffle_deck(specs[ci].owner)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return {}
	var pi := int(raw[0][0])
	var idx := int(raw[0][1])
	if pi == -1:
		if idx < 0 or idx >= hand_nodes.size():
			return {}
		return {"data": PlayerSideScript.take_from_hand(main, pid, hand_nodes[idx]), "owner": pid, "zone": Constants.Zone.MANO}
	if pi < 0 or pi >= pools.size() or idx < 0 or idx >= pools[pi].cards.size() or not pools[pi].cards[idx].eligible:
		return {}
	var d: Dictionary = pools[pi].cards[idx].data
	var sp: Dictionary = specs[pi]
	match int(sp.zone):
		Constants.Zone.CEMENTERIO:
			if not CardManager.take_from_cemetery(sp.owner, d):
				return {}
		Constants.Zone.DESTIERRO:
			CardManager.get_exile(sp.owner).erase(d)
			CardManager._emit_exile_changed(sp.owner)
		_:
			CardManager.get_deck(sp.owner).erase(d)
			CardManager.shuffle_deck(sp.owner)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return {"data": d, "owner": sp.owner, "zone": sp.zone}


## Devuelve una carta tomada con _take_from_pools si no se pudo jugar.
static func _give_back(main: Node, taken: Dictionary) -> void:
	if taken.is_empty():
		return
	match int(taken.zone):
		Constants.Zone.MANO: PlayerSideScript.put_in_hand(main, taken.owner, taken.data)
		Constants.Zone.DESTIERRO: CardManager.append_to_exile(taken.owner, taken.data)
		_: CardManager.add_to_cemetery(taken.owner, taken.data)


static func _play_taken(main: Node, pid: int, taken: Dictionary, price: int) -> bool:
	if taken.is_empty():
		return false
	if await TalismanScript._play_paying(main, pid, taken.data, price):
		return true
	_give_back(main, taken)
	return false


static func _payable(main: Node, pid: int, price: Callable) -> Callable:
	return func(d) -> bool: return main._gold_manager != null and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)


static func _muma_padurii(main: Node, card: Node, pid: int) -> void:
	var ok := func(d): return _is_ally(d) and int(d.get("coste", 0)) == 1
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de coste 1 de tu mano o Cementerio" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	var name := str(taken.get("data", {}).get("nombre", ""))
	if not await _play_taken(main, pid, taken, 0):
		return
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		for c in _allies(main, pid):
			if EnterScript._name(c) == name and await EnterScript._confirm(main, pid, "Muma Padurii", "Subir %s a tu mano" % name):
				await EnterScript.bounce_to_owner_hand(main, c, null)
				break)


static func _omukade(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return _is_ally(d) and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de un Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}, {"owner": 1 - pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _vampiro_rancagua(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado o Arma de un Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}, {"owner": 1 - pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _mateo_toro(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return int(d.get("coste", 0))
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma de tu Cementerio o Destierro" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}, {"owner": pid, "zone": Constants.Zone.DESTIERRO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _general_washington(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] \
		and CemeteryTriggersScript.normalize(str(d.get("nombre", ""))) != "general washington" and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma o Aliado de tu mano o Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _put_into_play(main: Node, pid: int, data: Dictionary, owner: int) -> Node:
	data["esta_oculta"] = false
	var node: Node = main._create_card(data, false)
	node.owner_id = owner
	node.controller_id = pid
	main._connect_card_signals(node)
	await main._gold_manager._play_card_to_field(node)
	return node


static func _kuzuryu_activa(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 2) or not main._gold_manager:
		return
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: pon en juego un Aliado de tu mano" % _name(card), allies, false)
	if is_instance_valid(chosen):
		await _put_into_play(main, pid, PlayerSideScript.take_from_hand(main, pid, chosen), pid)


static func _miguel_cervantes(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).is_empty() or not main._gold_manager:
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: un Aliado de coste 2 o menos como Aliado sin habilidad" % _name(card), 0, 1,
		func(d): return _is_ally(d) and int(d.get("coste", 0)) <= 2)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["habilidad"] = ""
			await _put_into_play(main, pid, data, pid)


static func _castle_top_to_ally(main: Node, card: Node, pid: int, strength: int, keywords: Array) -> Node:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	if deck.is_empty():
		return null
	var node: Node = await LeavePlayScript._ally_from_data(main, deck.pop_front(), owner, pid, card, strength, keywords, "")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return node


static func _frederick_ransom(main: Node, card: Node, pid: int) -> void:
	if _allies(main, pid).size() > _allies(main, 1 - pid).size():
		return
	var node := await _castle_top_to_ally(main, card, pid, 2, [])
	if is_instance_valid(node):
		KeywordManager.grant_keyword(node, Constants.Keyword.FURIA, card, "turn")  # "puede atacar el turno que entra en juego"


static func _bistritz(main: Node, card: Node, pid: int) -> void:
	await _castle_top_to_ally(main, card, pid, 4, [Constants.Keyword.FURIA])


static func _behemot(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: un Aliado de cualquier Cementerio como Aliado Bestia sin habilidad" % _name(card), 0, 1,
		func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["habilidad"] = ""
			data["raza"] = "Bestia"
			await _put_into_play(main, pid, data, pk.owner)


static func _daikaiju(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 2, 0)
	var ok := func(d): return _is_ally(d) and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de tu mano o Cementerio por dos Oros menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	var cost: int = int(taken.get("data", {}).get("coste", 0))
	if not await _play_taken(main, pid, taken, price.call(taken.get("data", {}))) or cost <= 0:
		return
	var amount := cost
	if not PlayerSideScript.is_bot(pid):
		var options: Array = []
		for i in cost + 1:
			options.append("Robar %d" % i)
		amount = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta %d cartas" % [_name(card), cost], options, pid), 0)
	if amount > 0:
		await ActionModule.draw(pid, amount, _name(card), true)


static func _ten_no_senshi(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 2, 0)
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.TOTEM and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Tótem de tu mano o Cementerio por dos Oros menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	var cost: int = int(taken.get("data", {}).get("coste", 0))
	if await _play_taken(main, pid, taken, price.call(taken.get("data", {}))) and cost > 0:
		await ActionModule.draw(pid, cost, _name(card), true)


static func _nyssara_busca(main: Node, card: Node, pid: int) -> void:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: dos Aliados de distinto nombre" % _name(card), func(d): return _is_ally(d), 0, 2, true)
	if picked.is_empty():
		return
	var to_play: Dictionary = picked[0]
	if picked.size() == 2 and not PlayerSideScript.is_bot(pid):
		to_play = picked[0] if await SelectionManager.await_two_choice(main, "%s: ¿cuál juegas por un Oro menos?" % _name(card),
			str(picked[0].get("nombre", "")), str(picked[1].get("nombre", "")), pid) else picked[1]
	for d in picked:
		if d != to_play:
			PlayerSideScript.put_in_hand(main, pid, d)
	if not await TalismanScript._play_paying(main, pid, to_play, maxi(int(to_play.get("coste", 0)) - 1, 0)):
		PlayerSideScript.put_in_hand(main, pid, to_play)


static func _gabriel_ernest(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	var ok := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] \
		and _payable(main, pid, func(x): return int(x.get("coste", 0))).call(d)
	var taken := await _take_from_pools(main, pid, "%s: un Aliado o Arma de tu Castillo para jugar pagando su coste" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": ok}])
	if not taken.is_empty() and not await TalismanScript._play_paying(main, pid, taken.data, int(taken.data.get("coste", 0))):
		PlayerSideScript.put_in_hand(main, pid, taken.data)


static func _lucifer(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var ok := func(d): return _is_ally(d) and _payable(main, pid, func(x): return int(x.get("coste", 0))).call(d)
	var taken := await _take_from_pools(main, pid, "%s: puedes jugar un Aliado del Destierro oponente" % _name(card),
		[{"owner": opp, "zone": Constants.Zone.DESTIERRO, "eligible": ok}])
	await _play_taken(main, pid, taken, int(taken.get("data", {}).get("coste", 0)))
	var deck: Array = CardManager.get_deck(opp)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	await ActionModule.draw(pid, 1, _name(card), true)


static func _alucard_juega(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
	var ok := func(d): return int(d.get("tipo", -1)) not in [Constants.CardType.TALISMAN, Constants.CardType.ORO] and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega una carta del Destierro oponente por un Oro menos" % _name(card),
		[{"owner": 1 - pid, "zone": Constants.Zone.DESTIERRO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))

# =============================================================================
# SEGUNDO LOTE: CONVERTIR Y CONTROL
# =============================================================================


static func _pick_in_play(main: Node, pid: int, title: String, filter: Callable, bot_rivals: bool = true) -> Node:
	var all: Array = []
	for side in [1 - pid, pid]:
		all.append_array(EnterScript._in_play(main, side, filter))
	if PlayerSideScript.is_bot(pid) and bot_rivals:
		all = all.filter(func(c): return CardQuery.controller_of(c) != pid)
	return await EnterScript._pick_from(main, pid, title, all, true)


static func _pachamama(main: Node, card: Node, pid: int) -> void:
	var target: Node = await EnterScript._pick_from(main, pid, "%s: una carta oponente de coste 3 o menos" % _name(card),
		EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3)), true)
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, pid)


static func _shango(main: Node, card: Node, pid: int) -> void:
	var mine := _allies(main, pid)
	if mine.is_empty() or mine.any(func(c): return not ("eterno" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))):
		main._update_debug("%s: solo si controlas únicamente Eternos" % _name(card))
		return
	var target: Node = await _pick_in_play(main, pid, "%s: convierte un Aliado en Tótem sin habilidad" % _name(card), func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, CardQuery.controller_of(target))


static func _valva_apei(main: Node, card: Node, pid: int) -> void:
	if EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM).size() < 2:
		main._update_debug("%s: necesitas controlar dos o más Tótem" % _name(card))
		return
	var target: Node = await _pick_in_play(main, pid, "%s: una carta de coste 2 o menos pasa a ser tu Tótem sin habilidad" % _name(card),
		func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, pid)


static func _espada_magog(main: Node, card: Node, pid: int) -> void:
	var target: Node = await _pick_in_play(main, pid, "%s: una carta de coste 2 o menos pasa a ser un Oro sin habilidad en tu Oro Pagado" % _name(card),
		func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if is_instance_valid(target) and not await ConvertScript.conversion_prevented(target, card):
		await LeavePlayScript._in_play_to_paid_gold(main, target, pid, card)


static func _zmey(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	var convert := true
	if not PlayerSideScript.is_bot(pid):
		convert = await SelectionManager.await_two_choice(main, _name(card), "Convertir una carta de coste 2 o menos en Oro", "Robar dos cartas", pid)
	if not convert:
		await ActionModule.draw(pid, 2, _name(card), true)
		return
	await _espada_magog(main, card, pid)


static func _blank_one(main: Node, card: Node, pid: int, filter: Callable = Callable()) -> void:
	var target: Node = await _pick_in_play(main, pid, "%s: una carta queda sin habilidad" % _name(card),
		func(c): return c != card and (not filter.is_valid() or filter.call(c)))
	if is_instance_valid(target):
		await EnterScript._blank(target, card)


static func _los_sastres(main: Node, card: Node, pid: int) -> void:
	var weapons: Array = CardQuery.weapons_in_play(pid)
	if weapons.size() < 2:
		return
	var two: Array = await EnterScript._pick_many(main, pid, "%s: Destruye dos Armas que controles" % _name(card), weapons, 2, false)
	if two.size() < 2:
		return
	await ActionModule.destroy(two, card, true)
	await _blank_one(main, card, pid)


static func _trofeo_activa(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	if not await EffectController.exile_card(owner, card, true, card):
		return
	await _blank_one(main, null, pid)


static func _estrella_kirin(main: Node, card: Node, pid: int) -> void:
	await LeavePlayScript._gold_to_paid(main, card)  # pagarlo
	await EnterScript._blank(card, card)  # y convertirlo en un Oro sin habilidad
	await _blank_one(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ORO or ContinuousEffectManager.cost_at_most(c, 2))


static func _swap_control(main: Node, card: Node, pid: int, allowed: Callable) -> void:
	var mine: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	var give: Node = await EnterScript._pick_from(main, pid, "%s: una carta que controles" % _name(card), mine, true)
	if not is_instance_valid(give):
		return
	var theirs: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and allowed.call(give, c))
	var take: Node = await EnterScript._pick_from(main, pid, "%s: la carta oponente" % _name(card), theirs, true)
	if not is_instance_valid(take):
		return
	ContinuousEffectManager.gain_control_of_card(take, pid)
	ContinuousEffectManager.gain_control_of_card(give, 1 - pid)


static func _nodens(main: Node, card: Node, pid: int) -> void:
	await _swap_control(main, card, pid, func(give, c): return EnterScript._cost(c) <= EnterScript._cost(give))


static func _arturo_prat_sp(main: Node, card: Node, pid: int) -> void:
	await _swap_control(main, card, pid, func(give, c): return EnterScript._cost(c) <= EnterScript._cost(give) + 1)


static func _pnyx(main: Node, card: Node, pid: int) -> void:
	var until: int = RuleState.next_own_turn(pid) - 1
	var target: Node = await _pick_in_play(main, pid, "%s: hasta una carta en juego pierde su habilidad" % _name(card), func(c): return c != card)
	if is_instance_valid(target):
		target.set_meta("silenced_until", until)
	var specs: Array = []
	for p in [1 - pid, pid]:
		specs.append({"owner": p, "zone": Constants.Zone.CEMENTERIO, "eligible": func(_d): return true})
		specs.append({"owner": p, "zone": Constants.Zone.DESTIERRO, "eligible": func(_d): return true})
	var pools: Array = []
	for sp in specs:
		var arr: Array = CardManager.get_cemetery(sp.owner) if sp.zone == Constants.Zone.CEMENTERIO else CardManager.get_exile(sp.owner)
		pools.append({"is_own": sp.owner == pid, "zone": sp.zone, "exclusive": true, "cards": arr.map(func(d): return {"data": d, "eligible": true})})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta una carta de un Cementerio o Destierro pierde su habilidad" % _name(card), pools, 0, 1)
	if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2:
		var pi := int(raw[0][0])
		var ci := int(raw[0][1])
		if pi >= 0 and pi < pools.size() and ci >= 0 and ci < pools[pi].cards.size():
			pools[pi].cards[ci].data["_silenced_until"] = until  # CardManager.is_cemetery_card_silenced


static func _margaret(main: Node, card: Node, pid: int) -> void:
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var rivals := EnterScript._in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		named = EnterScript._name(rivals[0]) if not rivals.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait("%s: nombra una carta" % _name(card), pid)
		named = str(picked.get("nombre", ""))
	if not named.is_empty():
		KeywordManager.lock_name_until_next_turn(named, -1)
		main._update_debug("%s: hasta tu próximo turno no se pueden utilizar las habilidades de %s" % [_name(card), named])


static func _koto(main: Node, card: Node, pid: int) -> void:
	var all: Array = EnterScript._in_play(main, 1 - pid) + EnterScript._golds(main, [1 - pid])
	var target: Node = await EnterScript._pick_from(main, pid, "%s: elige una carta: usar su habilidad le cuesta un Oro a tu oponente" % _name(card), all, false)
	if is_instance_valid(target):
		target.set_meta("ability_toll_turn", GameManager.turn_serial)  # TriggerTollPatterns.ability_toll


static func _el_demeter(main: Node, card: Node, pid: int) -> void:
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado debe bloquear este turno si puede" % _name(card), _allies(main, 1 - pid), true)
	if is_instance_valid(target):
		target.set_meta("must_fight_turn", GameManager.turn_serial)


static func _tumba_esperanza(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.cost_of(o) == 0)
	var annul := not obj.is_empty()
	var zeros: Array = []
	for side in [1 - pid, pid]:
		zeros.append_array(EnterScript._in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and EnterScript._cost(c) == 0))
	if annul and not zeros.is_empty() and not PlayerSideScript.is_bot(pid):
		annul = await SelectionManager.await_two_choice(main, _name(card), "Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "")),
			"Destruir una carta de coste 0", pid)
	if annul:
		StackAnnulScript.apply(obj, card)
		return
	var target: Node = await EnterScript._pick_from(main, pid, "%s: Destruye una carta de coste 0" % _name(card), zeros, true)
	if is_instance_valid(target):
		await ActionModule.destroy([target], card, true)


static func _nyssara_anula(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		var node = StackAnnulScript.card_of(o)
		return StackAnnulScript.cost_of(o) == 0 or (node != null and is_instance_valid(node) and node.get_meta("played_free", false)))
	if obj.is_empty():
		main._update_debug("%s: no hay una carta de coste 0 o jugada sin pagar su coste que Anular" % _name(card))
		return
	StackAnnulScript.apply(obj, card)

# =============================================================================
# SEGUNDO LOTE: BUSCAR, MIRAR, MOSTRAR
# =============================================================================


static func _muneco_vudu(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).any(func(c): return KeywordManager.has_keyword(c, Constants.Keyword.FURIA)):
		main._update_debug("%s: necesitas controlar Aliados con Furia" % _name(card))
		return
	await LeavePlayScript._gold_to_paid(main, card)  # pagarlo
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid):
		return
	var all: Array = EnterScript._hand(main, opp)
	if not PlayerSideScript.is_bot(pid) and not all.is_empty():
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	var options: Array = all.filter(func(c): return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM])
	if options.is_empty():
		return
	var idx := 0
	if not PlayerSideScript.is_bot(pid) and options.size() > 1:
		idx = clampi(await SelectionManager.await_choice(main, "%s: elige un Talismán o Tótem para Barajarlo" % _name(card),
			options.map(func(c): return EnterScript._name(c)), pid), 0, options.size() - 1)
	PlayerSideScript.shuffle_from_hand(main, opp, options[idx], _name(card))


static func _gran_dragon(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if not (EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid)):
		var all: Array = EnterScript._hand(main, opp)
		if not PlayerSideScript.is_bot(pid) and not all.is_empty():
			SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	await TriggerSystem._effect_interpreter.try_execute(card, "puedes poner un oro de tu mano o cementerio en tu oro pagado", pid)


static func _carmilla(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var hand: Array = EnterScript._hand(main, opp).filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
		named = EnterScript._name(hand[0]) if not hand.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait("%s: nombra una carta que no sea Oro" % _name(card), pid)
		if int(picked.get("tipo", -1)) != Constants.CardType.ORO:
			named = str(picked.get("nombre", ""))
	if named.is_empty():
		return
	for c in EnterScript._hand(main, opp):
		if EnterScript._name(c).to_lower() == named.to_lower():
			EnterScript._exile_from_hand(main, opp, [c])
			main._update_debug("%s: Destierra %s de la mano oponente" % [_name(card), named])
			return
	if not EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.CASTILLO):
		var deck: Array = CardManager.get_deck(opp)
		for d in deck:
			if str(d.get("nombre", "")).to_lower() == named.to_lower():
				deck.erase(d)
				d["esta_oculta"] = false
				CardManager.append_to_exile(opp, d)
				main._update_debug("%s: Destierra %s del Castillo oponente" % [_name(card), named])
				break
		CardManager.shuffle_deck(opp)


static func _banish_from_a_castle(main: Node, card: Node, pid: int, count: int, distinct: bool, eligible: Callable = Callable()) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: cartas para Desterrar" % _name(card),
		eligible if eligible.is_valid() else func(_d): return true, 0, count, distinct)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _strigoi(main: Node, card: Node, pid: int) -> void:
	var discard := not EnterScript._hand(main, pid).is_empty()
	var mine: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	if not PlayerSideScript.is_bot(pid) and discard and not mine.is_empty():
		discard = await SelectionManager.await_two_choice(main, _name(card), "Descartar una carta", "Destruir otra de tus cartas", pid)
	if discard:
		await EnterScript._discard_own(main, card, pid, 1)
	else:
		var victim: Node = await EnterScript._pick_from(main, pid, "%s: Destruye otra de tus cartas" % _name(card), mine, false)
		if not is_instance_valid(victim):
			return
		await ActionModule.destroy([victim], card, true)
	await _banish_from_a_castle(main, card, pid, 2, true)


static func _seth_destructor(main: Node, card: Node, pid: int) -> void:
	await _banish_from_a_castle(main, card, pid, 2, true)


static func _juan_patmos(main: Node, card: Node, pid: int) -> void:
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ALIADO}, 1, true, false, false, card, Constants.Zone.DESTIERRO)


static func _each_castle(main: Node, card: Node, pid: int, count: int, title: String, eligible: Callable, place: Callable) -> void:
	for owner in [1 - pid, pid]:
		var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: %s (Castillo %s)" % [_name(card), title, "oponente" if owner != pid else "propio"],
			eligible, 0, count, false)
		await place.call(owner, picked)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _lord_ruthven(main: Node, card: Node, pid: int) -> void:
	await _each_castle(main, card, pid, 2, "hasta dos cartas de distinto tipo", func(_d): return true, func(owner: int, picked: Array) -> void:
		var types: Dictionary = {}
		for d in picked:
			if types.has(int(d.get("tipo", -1))):
				CardManager.get_deck(owner).append(d)  # mismo tipo: vuelve
				continue
			types[int(d.get("tipo", -1))] = true
			var to_exile := false
			if not PlayerSideScript.is_bot(pid):
				to_exile = not await SelectionManager.await_two_choice(main, str(d.get("nombre", "")), "Al Cementerio de su dueño", "Al Destierro de su dueño", pid)
			d["esta_oculta"] = false
			if to_exile:
				CardManager.append_to_exile(owner, d)
			else:
				CardManager.add_to_cemetery(owner, d))


static func _estandarte(main: Node, card: Node, pid: int) -> void:
	await LeavePlayScript._gold_to_paid(main, card)  # pagarlo
	await _each_castle(main, card, pid, 2, "dos cartas al Cementerio", func(_d): return true, func(owner: int, picked: Array) -> void:
		for d in picked:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(owner, d))


static func _hacha_seth(main: Node, card: Node, pid: int) -> void:
	await _each_castle(main, card, pid, 2, "dos cartas", func(_d): return true, func(owner: int, picked: Array) -> void:
		if picked.is_empty():
			return
		var idx := 0
		if picked.size() == 2 and not PlayerSideScript.is_bot(pid):
			idx = 0 if await SelectionManager.await_two_choice(main, "%s: ¿cuál va al Cementerio?" % _name(card),
				str(picked[0].get("nombre", "")), str(picked[1].get("nombre", "")), pid) else 1
		var to_cem: Dictionary = picked[idx]
		to_cem["esta_oculta"] = false
		CardManager.add_to_cemetery(owner, to_cem)
		if picked.size() == 2:
			var other: Dictionary = picked[1 - idx]
			var to_hand: bool = owner == pid
			if not PlayerSideScript.is_bot(pid):
				to_hand = await SelectionManager.await_two_choice(main, str(other.get("nombre", "")), "A la mano de su dueño", "Al Destierro de su dueño", pid)
			if to_hand:
				PlayerSideScript.put_in_hand(main, owner, other)
			else:
				other["esta_oculta"] = false
				CardManager.append_to_exile(owner, other))


static func _luxor(main: Node, card: Node, pid: int) -> void:
	var hand: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") != Constants.CardType.TALISMAN)
	var cost_card: Node = await EnterScript._pick_from(main, pid, "%s: Descarta una carta que no sea Talismán" % _name(card), hand, true)
	if not is_instance_valid(cost_card):
		return
	var t: int = int(cost_card.get("card_type"))
	await ActionModule.discard(pid, [cost_card], _name(card), true)
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": t}, 1, true, false, false, card)


static func _horda_tenebris(main: Node, card: Node, pid: int) -> void:
	await ActionModule.mill(pid, 3, false, _name(card))  # el costo
	var small: Array = []
	for side in [1 - pid, pid]:
		small.append_array(EnterScript._in_play(main, side, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2)))
	var t: Node = await EnterScript._pick_from(main, pid, "%s: hasta una carta de coste 2 o menos a la mano de su dueño" % _name(card), small, true)
	if is_instance_valid(t):
		await EnterScript.bounce_to_owner_hand(main, t, card)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: hasta una carta que no sea Talismán de tu Cementerio a tu mano" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


static func _alucard_destierra(main: Node, card: Node, pid: int) -> void:
	var top := true
	if not PlayerSideScript.is_bot(pid):
		top = await SelectionManager.await_two_choice(main, _name(card), "Desterrar cinco cartas del tope del Castillo oponente",
			"Desterrar hasta dos cartas en juego cuyos costes sumen hasta 3", pid)
	if top:
		await ActionModule.mill(1 - pid, 5, true, _name(card))
		return
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 2, 3, "%s: hasta dos cartas cuyos costes sumen hasta 3" % _name(card))
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)


static func _faraon_negro_1(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var theirs := _allies(main, opp)
	if PlayerSideScript.is_bot(opp):
		theirs.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) < ContinuousEffectManager.get_modified_strength(b))
	var chosen: Node = await EnterScript._pick_from(main, opp, "%s: elige un Aliado que controles" % _name(card), theirs, false)
	if not is_instance_valid(chosen):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(chosen))
	if n > 0:
		await ActionModule.mill(opp, n, false, _name(card))
	await EnterScript.bounce_to_owner_hand(main, chosen, card)


static func _castillo_kumamoto(main: Node, card: Node, pid: int) -> void:
	await ActionModule.draw(pid, 2, _name(card), true)
	await EnterScript._discard_own(main, card, pid, 1)
	var unblockable: Array = EnterScript._all_allies(main, func(c): return KeywordManager.has_keyword(c, Constants.Keyword.IMBLOQUEABLE) \
		and (CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados Imbloqueable ganan Furia" % _name(card), unblockable, 2, true)
	for c in chosen:
		KeywordManager.grant_keyword(c, Constants.Keyword.FURIA, card, "turn")


static func _parche_pirata(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	await ActionModule.draw(pid, 2, _name(card), true)
	await EnterScript._discard_own(main, card, pid, 1)


static func _empanada(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	main._update_debug("¡Viva Chile!")
	await ActionModule.draw(pid, 1, _name(card), true)


static func _hand_to_bottom(main: Node, card: Node, pid: int, max_count: int) -> int:
	var hand := EnterScript._hand(main, pid)
	if hand.is_empty():
		return 0
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: cartas de tu mano al fondo de tu Castillo" % _name(card), hand, mini(max_count, hand.size()), true)
	if PlayerSideScript.is_bot(pid):
		chosen = []
	var deck: Array = CardManager.get_deck(pid)
	for c in chosen:
		var d: Dictionary = PlayerSideScript.take_from_hand(main, pid, c)
		d["esta_oculta"] = true
		deck.append(d)
	return chosen.size()


static func _cueva_salamanca(main: Node, card: Node, pid: int) -> void:
	var n := await _hand_to_bottom(main, card, pid, 99)
	var deck: Array = CardManager.get_deck(pid)
	for _i in mini(n, deck.size()):
		PlayerSideScript.put_in_hand(main, pid, deck.pop_front())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _necronomicon(main: Node, card: Node, pid: int) -> void:
	var n := await _hand_to_bottom(main, card, pid, 2)
	if n > 0:
		await ActionModule.draw(pid, n, _name(card), true)


static func _top_from_hand_bottom_to_hand(main: Node, card: Node, pid: int, bottom_count: int) -> void:
	var hand := EnterScript._hand(main, pid)
	if hand.is_empty():
		return
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: una carta de tu mano al tope de tu Castillo" % _name(card), hand, true)
	if not is_instance_valid(chosen):
		return
	var deck: Array = CardManager.get_deck(pid)
	var d: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	d["esta_oculta"] = true
	deck.push_front(d)
	for _i in mini(bottom_count, deck.size() - 1):
		PlayerSideScript.put_in_hand(main, pid, deck.pop_back())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _paris(main: Node, card: Node, pid: int) -> void:
	await _top_from_hand_bottom_to_hand(main, card, pid, 2)


static func _craneo_duvel(main: Node, card: Node, pid: int) -> void:
	await _top_from_hand_bottom_to_hand(main, card, pid, 1)


static func _ultimo_hombre(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = deck.slice(0, mini(3, deck.size()))
	if shown.is_empty():
		return
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	for d in shown:
		if _is_ally(d):
			var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza permanentemente" % _name(card), EnterScript._all_allies(main), false)
			await _buff(ally, card, 1, true)
	# "Devuelve las cartas mostradas en cualquier orden": quedan en el tope, en el mismo orden.


static func _show_from_hand(main: Node, card: Node, pid: int, filter: Callable, title: String) -> Node:
	var hand: Array = EnterScript._hand(main, pid).filter(filter)
	var shown: Node = await EnterScript._pick_from(main, pid, "%s: %s" % [_name(card), title], hand, true)
	if is_instance_valid(shown):
		main._update_debug("%s: muestra %s" % [_name(card), EnterScript._name(shown)])
	return shown


static func _long_john(main: Node, card: Node, pid: int) -> void:
	if not is_instance_valid(await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO, "muestra un Aliado de tu mano")):
		return
	var opp: int = 1 - pid
	var count := [0]
	var shown := TalismanScript._reveal_until(main, opp, _name(card), func(s):
		if not s.is_empty() and _is_ally(s[-1]):
			count[0] += 1
		return count[0] >= 2)
	for d in shown:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(opp, d)


static func _sandokan_activa(main: Node, card: Node, pid: int) -> void:
	var shown: Node = await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO, "muestra un Aliado de tu mano")
	if is_instance_valid(shown) and int(shown.get("card_strength")) > 0:
		await ActionModule.mill(1 - pid, int(shown.get("card_strength")), false, _name(card))


static func _prendick(main: Node, card: Node, pid: int) -> void:
	var armed: Array = EnterScript._all_allies(main, func(c): return c.get("equipped_weapons") is Array and not c.equipped_weapons.is_empty())
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que porte Armas (su Fuerza)" % _name(card), armed, false)
	if not is_instance_valid(ally):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(ally))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _monitor_araucano(main: Node, card: Node, pid: int) -> void:
	if not is_instance_valid(await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ARMA, "muestra un Arma de tu mano")):
		return
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	await LeavePlayScript._ally_from_data(main, deck.pop_front(), pid, pid, card, 0, [], "")


static func _ziroonderel(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = []
	var allies: Array = []
	var total := 0
	while not deck.is_empty():
		var d: Dictionary = deck[0]
		if _is_ally(d) and total + int(d.get("fuerza", 0)) > 4:
			break
		shown.append(deck.pop_front())
		if _is_ally(d):
			allies.append(d)
			total += int(d.get("fuerza", 0))
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(x): return str(x.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	for d in shown:
		if d in allies:
			PlayerSideScript.put_in_hand(main, pid, d)
		else:
			d["esta_oculta"] = true
			deck.append(d)
	CardManager.shuffle_deck(pid)


static func _azrael(main: Node, card: Node, pid: int) -> void:
	var allies: Array = []
	var shown := TalismanScript._reveal_until(main, pid, _name(card), func(s):
		if not s.is_empty() and _is_ally(s[-1]):
			allies.append(s[-1])
		return allies.size() >= 2)
	var deck: Array = CardManager.get_deck(pid)
	for d in shown:
		if not (d in allies):
			d["esta_oculta"] = true
			deck.append(d)
	if not allies.is_empty():
		var idx := 0
		if allies.size() == 2 and not PlayerSideScript.is_bot(pid):
			idx = 0 if await SelectionManager.await_two_choice(main, "%s: ¿cuál va a tu mano?" % _name(card), str(allies[0].get("nombre", "")),
				str(allies[1].get("nombre", "")), pid) else 1
		PlayerSideScript.put_in_hand(main, pid, allies[idx])
		if allies.size() == 2:
			allies[1 - idx]["esta_oculta"] = false
			CardManager.append_to_exile(pid, allies[1 - idx])
	CardManager.shuffle_deck(pid)


static func _lamia(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		await ActionModule.mill(p, 2, false, _name(card))
	var mine := _allies(main, pid)
	if not mine.is_empty() and mine.all(func(c): return "sombra" in CemeteryTriggersScript.normalize(str(c.get("card_raza")))) \
			and await EnterScript._confirm(main, pid, _name(card), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(card), true)


static func _el_diablo(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		await ActionModule.mill(p, 3, false, _name(card))
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: tres cartas de los Cementerios como Aliados Sombra de Fuerza 3" % _name(card), 3, 3)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			await LeavePlayScript._ally_from_data(main, pk.data, pk.owner, pid, card, 3, [], "Sombra")


static func _inti(main: Node, card: Node, pid: int) -> void:
	var options: Array = []  # [{node?, data, clause}]
	for t in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM):
		var cl: String = LeavePlayScript._activated_clause(t.card_data)
		if not cl.is_empty():
			options.append({"node": t, "data": t.card_data, "clause": cl})
	for d in CardManager.get_cemetery(pid):
		if int(d.get("tipo", -1)) == Constants.CardType.TOTEM:
			var cl2: String = LeavePlayScript._activated_clause(d)
			if not cl2.is_empty():
				options.append({"node": null, "data": d, "clause": cl2})
	if options.is_empty():
		main._update_debug("%s: no hay un Tótem con una habilidad que se pueda activar" % _name(card))
		return
	var idx := 0
	if not PlayerSideScript.is_bot(pid) and options.size() > 1:
		idx = clampi(await SelectionManager.await_choice(main, "%s: ¿la habilidad de qué Tótem?" % _name(card),
			options.map(func(o): return str(o.data.get("nombre", ""))), pid), 0, options.size() - 1)
	var o: Dictionary = options[idx]
	var source: Node = o.node
	var proxy: Node = null
	if not is_instance_valid(source):
		proxy = main._create_card(o.data, false)
		proxy.visible = false
		main.add_child(proxy)
		proxy.owner_id = pid
		proxy.controller_id = pid
		source = proxy
	await TriggerSystem._effect_interpreter.try_execute(source, o.clause, pid)
	if is_instance_valid(proxy):
		proxy.queue_free()


static func _castillo_dracula(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	var pick := 2
	if not PlayerSideScript.is_bot(pid):
		pick = await SelectionManager.await_choice(main, _name(card), ["No recibes daño de combate hasta tu próximo turno",
			"No puedes ser afectado por efectos oponentes hasta tu próximo turno", "Tu oponente Bota cinco cartas"], pid)
	match pick:
		0: RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))
		1: RuleState.set_until("opp_effect_immune", pid, RuleState.next_own_turn(pid))
		_: await ActionModule.mill(1 - pid, 5, false, _name(card))


static func _conde_dracula(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN)
	var options: Array = ["Robar dos cartas", "Un Aliado gana Furia por el turno"]
	if not obj.is_empty():
		options.push_front("Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "el Talismán")))
	var pick := 0
	if not PlayerSideScript.is_bot(pid):
		pick = clampi(await SelectionManager.await_choice(main, _name(card), options, pid), 0, options.size() - 1)
	var choice: String = options[pick]
	if choice.begins_with("Anular"):
		StackAnnulScript.apply(obj, card)
	elif choice.begins_with("Robar"):
		await ActionModule.draw(pid, 2, _name(card), true)
	else:
		var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia" % _name(card), EnterScript._all_allies(main), false)
		if is_instance_valid(ally):
			KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "turn")
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: dos cartas del fondo de un Castillo" % _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)


static func _cabeza_mimir(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var buff := true
	if not PlayerSideScript.is_bot(pid):
		buff = await SelectionManager.await_two_choice(main, _name(card), "Hasta tres Aliados ganan 1 de Fuerza e Imbloqueable",
			"Subir un Talismán de tu Cementerio a tu mano", pid)
	if not await EffectController.exile_card(owner, card, true, card):  # el costo: Desterrarlo
		return
	if buff:
		var chosen: Array = await EnterScript._pick_many(main, pid, "Cabeza de Mímir: hasta tres Aliados", _allies(main, pid), 3, true)
		for c in chosen:
			await _buff(c, null, 1)
			KeywordManager.grant_keyword(c, Constants.Keyword.IMBLOQUEABLE, null, "turn")
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Cabeza de Mímir: un Talismán de tu Cementerio a tu mano", 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)
