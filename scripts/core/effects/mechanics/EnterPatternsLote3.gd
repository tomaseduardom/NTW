extends "res://scripts/core/effects/mechanics/EnterPatternsLote2.gd"
## EnterPatternsLote3 — familia Lote3 de EnterPatterns.gd (ver EnterPatternsBase.gd).


# =============================================================================
# TERCER LOTE
# =============================================================================


## Último turn_serial antes de tu próximo turno ("hasta tu próximo turno").
static func _until_before_next_turn(pid: int) -> int:
	return RuleState.next_own_turn(pid) - 1


## Elige una carta de una lista de datos con await_choice (el bot, la primera). -1 = ninguna.
static func _choose_data(main: Node, pid: int, title: String, datas: Array, allow_none: bool) -> int:
	if datas.is_empty():
		return -1
	if PlayerSideScript.is_bot(pid):
		return 0
	var labels: Array = datas.map(func(d): return str(d.get("nombre", "?")))
	if allow_none:
		labels.append("Ninguna")
	var idx: int = await SelectionManager.await_choice(main, title, labels, pid)
	return idx if idx >= 0 and idx < datas.size() else -1


static func _shuffle_back(main: Node, owner: int, datas: Array, label: String) -> void:
	var deck: Array = CardManager.get_deck(owner)
	for d in datas:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(owner)
	AnimationQueue.queue_shuffle(owner, "Barajar mazo (%s)" % label)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _angelus(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or await _window(card, pid):
		return
	var shown: Array = []
	for _i in mini(5, deck.size()):
		shown.append(deck.pop_front())
	RevealedCardsScript.record(pid, shown, _name(card))
	var is_wt := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ARMA, Constants.CardType.TOTEM]
	var wt: Array = shown.filter(is_wt)
	var two := wt.size() >= 2
	if not PlayerSideScript.is_bot(pid) and two:
		two = not await SelectionManager.await_two_choice(main, _name(card), "Una carta a tu mano", "Dos Armas y/o Tótem a tu mano", pid)
	var take: Array = []
	if two:
		for i in 2:
			var idx := await _choose_data(main, pid, "%s: Arma o Tótem %d de 2" % [_name(card), i + 1], wt, false)
			if idx >= 0:
				take.append(wt.pop_at(idx))
	else:
		var idx := await _choose_data(main, pid, "%s: una carta a tu mano" % _name(card), shown, false)
		if idx >= 0:
			take.append(shown[idx])
	for d in take:
		shown.erase(d)
		PlayerSideScript.put_in_hand(main, pid, d)
	await _shuffle_back(main, pid, shown, _name(card))


static func _daga_bebedora(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.size() < 2 or not main._gold_manager:
		return
	if not await _confirm(main, pid, _name(card), "Desterrar dos cartas del tope de tu Castillo para buscar otra copia") or await _window(card, pid):
		return
	for _i in 2:
		var d: Dictionary = deck.pop_front()
		d["esta_oculta"] = false
		CardManager.append_to_exile(pid, d)
	var name := str(card.get("card_name")).to_lower()
	var found: Dictionary = {}
	for d in deck:
		if str(d.get("nombre", "")).to_lower() == name:
			found = d
			break
	if not found.is_empty():
		deck.erase(found)
	await _shuffle_back(main, pid, [], _name(card))
	if found.is_empty():
		main._update_debug("%s: no hay otra copia en tu Castillo" % _name(card))
		return
	found["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(found, pid):
		CardManager.add_to_cemetery(pid, found)


## Dr. Van Helsing: "puedes jugar un Tótem de tu mano o Cementerio reduciendo su coste en un Oro, hasta un
## mínimo de 0".
static func _van_helsing(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.TOTEM and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)
	var hand_nodes: Array = _hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return
	if not await _confirm(main, pid, _name(card), "Jugar un Tótem de tu mano o Cementerio por un Oro menos"):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Tótem de tu mano o Cementerio" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var data: Dictionary = {}
	var from_hand: Node = null
	if int(raw[0][0]) == -1:
		var hi := int(raw[0][1])
		if hi < 0 or hi >= hand_nodes.size():
			return
		from_hand = hand_nodes[hi]
		data = from_hand.card_data
	else:
		var ci := int(raw[0][1])
		if ci < 0 or ci >= entries.size() or not entries[ci].eligible:
			return
		data = entries[ci].data
	if await _window(card, pid) or not await PlayerSideScript.pay(main, pid, price.call(data)):
		return
	if from_hand:
		data = PlayerSideScript.take_from_hand(main, pid, from_hand)
	elif not CardManager.take_from_cemetery(pid, data):
		return
	data["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(data, pid):
		CardManager.add_to_cemetery(pid, data)


static func _paladin_esperanza(main: Node, card: Node, pid: int) -> void:
	var ok := func(d) -> bool:
		var t := int(d.get("tipo", -1))
		return t == Constants.CardType.ARMA or (t == Constants.CardType.ALIADO and "paladin" in CemeteryTriggersScript.normalize(str(d.get("raza", ""))))
	if CardManager.get_deck(pid).is_empty() or not await _confirm(main, pid, _name(card), "Buscar hasta dos Aliados Paladín o Armas") \
			or await _window(card, pid):
		return
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: hasta dos Aliados Paladín o Armas" % _name(card), ok, 0, 2, false)
	var draws := 0
	for d in picked:
		var to_hand := true
		if not PlayerSideScript.is_bot(pid):
			to_hand = await SelectionManager.await_two_choice(main, str(d.get("nombre", "")), "A tu mano", "A tu Cementerio", pid)
		elif int(d.get("tipo", -1)) == Constants.CardType.ARMA:
			to_hand = false
		if to_hand:
			PlayerSideScript.put_in_hand(main, pid, d)
		else:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(pid, d)
			if int(d.get("tipo", -1)) == Constants.CardType.ARMA:
				draws += 1
	if draws > 0 and await _confirm(main, pid, _name(card), "Robar %d carta(s)" % draws):
		await ActionModule.draw(pid, draws, _name(card), true)


static func _calfucura(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar dos Aliados de distinto coste") or await _window(card, pid):
		return
	var used_cost := -1
	for i in 2:
		var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) != used_cost
		var pools: Array = [
			{"is_own": true, "zone": Constants.Zone.CASTILLO, "exclusive": false, "cards": CardManager.get_deck(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
			{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "exclusive": false, "cards": CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
		]
		var raw: Array = await ActionModule.pick_in_zones(pid, "%s: Aliado %d de 2 (de distinto coste)" % [_name(card), i + 1], pools, 0, 1)
		if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
			break
		var pi := int(raw[0][0])
		var ci := int(raw[0][1])
		if pi < 0 or pi > 1 or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			break
		var d: Dictionary = pools[pi].cards[ci].data
		if pi == 0:
			CardManager.get_deck(pid).erase(d)
		elif not CardManager.take_from_cemetery(pid, d):
			break
		used_cost = int(d.get("coste", 0))
		PlayerSideScript.put_in_hand(main, pid, d)
	await _shuffle_back(main, pid, [], _name(card))


static func _haquika(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var is_priest := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and "sacerdote" in CemeteryTriggersScript.normalize(str(d.get("raza", "")))
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = []
	var priests: Array = []
	while not deck.is_empty() and priests.size() < 3:
		var d: Dictionary = deck.pop_front()
		shown.append(d)
		if is_priest.call(d):
			priests.append(d)
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	for d in priests:
		shown.erase(d)
	if priests.size() == 3:
		var idx := await _choose_data(main, pid, "%s: ¿qué Aliado Sacerdote se Destierra?" % _name(card), priests, false)
		var gone: Dictionary = priests.pop_at(maxi(idx, 0))
		gone["esta_oculta"] = false
		CardManager.append_to_exile(pid, gone)
	for d in priests:
		PlayerSideScript.put_in_hand(main, pid, d)
	await _shuffle_back(main, pid, shown, _name(card))
	# "No puedes recibir daño de combate hasta tu próximo turno" (RuleState, como Linaje Maldito).
	RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))


static func _jupitris(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for kind in ["no_combat_damage", "no_direct_damage"]:
		RuleState.set_until(kind, pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: no recibes daño hasta tu próximo turno" % _name(card))
	if await _confirm(main, pid, _name(card), "Robar tres cartas"):
		await ActionModule.draw(pid, 3, _name(card), true)


static func _tadg(main: Node, card: Node, pid: int) -> void:
	var n: int = CardManager.get_exile(pid).filter(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO).size()
	var deck: Array = CardManager.get_deck(pid)
	if n <= 0 or deck.is_empty() or not await _confirm(main, pid, _name(card), "Mirar %d carta(s) del tope de tu Castillo" % n) \
			or await _window(card, pid):
		return
	var seen: Array = []
	for _i in mini(n, deck.size()):
		seen.append(deck.pop_front())
	# Ordénalas: se eligen de arriba hacia abajo.
	var ordered: Array = []
	while not seen.is_empty():
		var idx: int = 0
		if seen.size() > 1:
			idx = maxi(await _choose_data(main, pid, "%s: ¿cuál va arriba? (%d de %d)" % [_name(card), ordered.size() + 1, n], seen, false), 0)
		ordered.append(seen.pop_at(idx))
	for i in range(ordered.size() - 1, -1, -1):
		deck.push_front(ordered[i])
	var top: Dictionary = deck.pop_front()
	top["esta_oculta"] = false
	CardManager.append_to_exile(pid, top)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _valva_bailor(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var made := 0
	while made < 2:
		var option := 0  # 0 en juego, 1 de un Cementerio, 2 listo
		if PlayerSideScript.is_bot(pid):
			option = 0 if made == 0 else 2
		else:
			option = await SelectionManager.await_choice(main, "%s: Tótem %d de 2" % [_name(card), made + 1],
				["Una carta de coste 2 o menos en juego", "Una carta de un Cementerio", "Listo"], pid)
		if option == 0:
			var targets: Array = []
			for side in [1 - pid, pid]:
				targets.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
					and ContinuousEffectManager.cost_at_most(c, 2)))
			var t: Node = await _pick_from(main, pid, "%s: elige una carta de coste 2 o menos" % _name(card), targets, true)
			if not is_instance_valid(t) or not await ConvertScript.convert_in_play_to_totem(t, card, pid):
				break
			t.card_cost = 5
		elif option == 1:
			var picks := await _pick_cemetery(pid, [pid, 1 - pid], "%s: una carta de un Cementerio" % _name(card), 0, 1)
			if picks.is_empty() or not CardManager.take_from_cemetery(picks[0].owner, picks[0].data):
				break
			var data: Dictionary = picks[0].data.duplicate()
			data["tipo"] = Constants.CardType.TOTEM
			data["coste"] = 5
			data["habilidad"] = ""
			data["esta_oculta"] = false
			var node: Node = main._create_card(data, false)
			node.owner_id = picks[0].owner
			node.controller_id = pid
			main._connect_card_signals(node)
			PlayerSideScript.line_containers(main, pid)[2].add_child(node)
			node.set_zone(Constants.Zone.LINEA_APOYO)
			node.can_interact = (pid == 0)
			node.is_converted = true
		else:
			break
		made += 1


static func _craneos_vivos(main: Node, card: Node, pid: int) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: un jugador muestra cartas del tope de su Castillo" % _name(card),
			"Tu oponente", "Tú", pid) else pid
	if CardManager.get_deck(owner).is_empty() or await _window(card, pid):
		return
	var deck: Array = CardManager.get_deck(owner)
	var shown: Array = []
	while not deck.is_empty():
		shown.append(deck.pop_front())
		if shown.size() >= 2 and int(shown[-1].get("tipo", -1)) != int(shown[0].get("tipo", -1)):
			break
	main._update_debug("%s muestra y Destierra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(owner, shown, _name(card))
	for d in shown:
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _illapa(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 2, 2, "%s: hasta dos Aliados cuyos costes sumen hasta 2" % _name(card))
	chosen = chosen.filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	if chosen.is_empty() or await _window(card, pid):
		return
	# Hasta tu próxima Fase Final (incluida).
	var own_turn: bool = GameManager.active_player_id == pid
	var until: int = GameManager.turn_serial + (2 if own_turn else 1)
	for c in chosen:
		c.set_meta("silenced_until", until)
		for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
			ContinuousEffectManager.register_modifier({
				"source": c, "target": c, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
				"restriction_type": restriction, "duration": ContinuousEffectManager.ModifierDuration.TIMED,
				"duration_value": 3 if own_turn else 2, "description": "%s: no ataca ni bloquea" % _name(card),
			})


static func _tukuturi(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for g in _golds(main, [0, 1]):
		if g != card:
			g.set_meta("silenced_until", _until_before_next_turn(pid))
	main._update_debug("%s: los demás Oros pierden su habilidad hasta tu próximo turno" % _name(card))


static func _kingstead(main: Node, card: Node, pid: int) -> void:
	var all: Array = []
	for side in [1 - pid, pid]:
		all.append_array(_in_play(main, side, func(c): return c != card))
	all.append_array(_golds(main, [1 - pid, pid]))
	if all.is_empty() or not await _confirm(main, pid, _name(card), "Dejar una carta sin habilidad hasta tu próximo turno"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta" % _name(card), all, true)
	if is_instance_valid(target) and not await _window(card, pid):
		target.set_meta("silenced_until", _until_before_next_turn(pid))


static func _argos(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for p in [0, 1]:
		RuleState.set_until("argos_tax", p, RuleState.next_own_turn(pid))  # PaymentManager._static_type_and_cheap_surcharge
	main._update_debug("%s: la primera carta de coste 1 o menos de cada turno cuesta un Oro más" % _name(card))


static func _plaza_armas(main: Node, card: Node, pid: int) -> void:
	var idx := 2  # el bot nombra Talismán
	if not PlayerSideScript.is_bot(pid):
		idx = clampi(await SelectionManager.await_choice(main, "%s: nombra un tipo de carta" % _name(card),
			PLAZA_TYPES.map(func(p): return p[0]), pid), 0, PLAZA_TYPES.size() - 1)
	card.set_meta("named_type", PLAZA_TYPES[idx][1])  # PaymentManager._static_type_and_cheap_surcharge
	main._update_debug("%s: las cartas de tipo %s cuestan un Oro adicional" % [_name(card), PLAZA_TYPES[idx][0]])


static func _perugia(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	# "Durante los próximos dos turnos": el siguiente y el que le sigue (no el actual).
	for p in [0, 1]:
		RuleState.set_window("one_per_type", p, GameManager.turn_serial + 1, GameManager.turn_serial + 3)  # GoldManager._card_play_locked
	main._update_debug("%s: durante los próximos dos turnos, una carta de cada tipo por turno" % _name(card))


static func _nuckelavee(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	TriggerSystem._totem_patterns.register_kotoku_in_talisman_fizzle(1 - pid, 1)
	main._update_debug("%s: el próximo Talismán de coste 1 o menos de tu oponente este turno es Anulado" % _name(card))


## Dispara el "cuando entra en juego" de otra carta tuya (Monjes Ortodoxos, rey de los pájaros).
static func _retrigger_enter(card: Node, pid: int, target: Node) -> void:
	if not is_instance_valid(target):
		return
	var token: int = load("res://scripts/core/effects/EffectContext.gd").push(target, pid, "disparada", "pending")
	await TriggerSystem._resolution._execute_trigger_effect(target, "on_enter_play", {"card": target, "player_id": pid})
	load("res://scripts/core/effects/EffectContext.gd").pop(token)


static func _monjes(main: Node, card: Node, pid: int) -> void:
	var totems := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM and ContinuousEffectManager.cost_at_most(c, 2) \
		and c.has_method("has_trigger") and c.has_trigger("on_enter_play") and not KeywordManager.is_silenced(c))
	var reuse := not totems.is_empty()
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, _name(card),
			["Utilizar la habilidad de un Tótem de coste 2 o menos al entrar", "Generar un Oro para jugar Tótem", "No"], pid)
		if pick < 0 or pick > 1:
			return
		reuse = pick == 0
	if await _window(card, pid):
		return
	if reuse:
		await _retrigger_enter(card, pid, await _pick_from(main, pid, "%s: elige un Tótem de coste 2 o menos" % _name(card), totems, true))
	elif main._gold_manager:
		main._gold_manager.generar_oro_virtual_restringido(1, func(t, _r, _c): return t == Constants.CardType.TOTEM, "%s: Oro para Tótem" % _name(card), pid)


static func _rey_pajaros(main: Node, card: Node, pid: int) -> void:
	var allies := _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO \
		and str(c.get("card_name")).to_lower() != str(card.get("card_name")).to_lower() and int(c.get("card_cost")) == 1 \
		and c.has_method("has_trigger") and c.has_trigger("on_enter_play") and not KeywordManager.is_silenced(c))
	if allies.is_empty() or not await _confirm(main, pid, _name(card), "Disparar la habilidad de entrada de un Aliado de coste 1"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado de coste 1" % _name(card), allies, true)
	if is_instance_valid(target) and not await _window(card, pid):
		await _retrigger_enter(card, pid, target)


static func _shakuhachi(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var picks := await _pick_cemetery(pid, [pid], "%s: puedes jugar un Talismán de tu Cementerio pagando su coste" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid))
	if picks.is_empty() or await _window(card, pid) or not await PlayerSideScript.pay(main, pid, int(picks[0].data.get("coste", 0))):
		return
	if CardManager.take_from_cemetery(pid, picks[0].data):
		picks[0].data["esta_oculta"] = false
		await main._gold_manager.play_card_for_free(picks[0].data, pid, true)


static func _felipe_augusto(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var knights := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and "caballero" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	if knights.is_empty():
		return
	var picks := await _pick_cemetery(pid, [pid], "%s: puedes jugar un Arma de coste 2 o menos de tu Cementerio en un Caballero" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) <= 2)
	if picks.is_empty():
		return
	var knight: Node = await _pick_from(main, pid, "%s: elige el Aliado Caballero que la porta" % _name(card), knights, false)
	if not is_instance_valid(knight) or await _window(card, pid) or not CardManager.take_from_cemetery(pid, picks[0].data):
		return
	var data: Dictionary = picks[0].data.duplicate()
	data["esta_oculta"] = false
	var weapon: Node = main._create_card(data, false)
	weapon.owner_id = pid
	weapon.controller_id = pid
	main._connect_card_signals(weapon)
	await main._gold_manager._equip_weapon(weapon, knight)


static func _kiyohime(main: Node, card: Node, pid: int) -> void:
	if not card.get_meta("entered_from_hand", false) or not main._gold_manager:
		return
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 4
	var hand_nodes: Array = _hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return
	if not await _confirm(main, pid, _name(card), "Poner en juego un Aliado de coste 4 o menos de tu mano o Cementerio"):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Aliado de coste 4 o menos" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2 or await _window(card, pid):
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
		data = entries[ci].data.duplicate()
	data["esta_oculta"] = false
	var node: Node = main._create_card(data, false)
	node.owner_id = pid
	node.controller_id = pid
	main._connect_card_signals(node)
	await main._gold_manager._play_card_to_field(node)


static func _ikuchi(main: Node, card: Node, pid: int) -> void:
	if not card.get_meta("entered_from_hand", false):
		return
	if not _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 1)).is_empty():
		return
	var rivals: Array = _in_play(main, 1 - pid) + _golds(main, [1 - pid])
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Desterrar hasta una carta oponente de cada tipo"):
		return
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		var seen_types: Dictionary = {}
		for c in rivals:
			if not seen_types.has(c.get("card_type")):
				seen_types[c.get("card_type")] = true
				chosen.append(c)
	else:
		var one_per_type := func(so_far: Array, c: Node) -> bool: return not so_far.any(func(x): return x.get("card_type") == c.get("card_type"))
		chosen = await main._card_interaction.await_multi_target("%s: hasta una carta oponente de cada tipo" % _name(card),
			rivals, -1, Callable(), one_per_type, true, null, pid)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.banish(chosen, card, true)
