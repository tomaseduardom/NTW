extends "res://scripts/core/effects/mechanics/TalismanPatternsLote2.gd"
## TalismanPatternsLote3 — familia Lote3 de TalismanPatterns.gd (ver TalismanPatternsBase.gd).


# =============================================================================
# TERCER LOTE
# =============================================================================


static func _silenciar_mundo(main: Node, card: Node, pid: int) -> void:
	var targets: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	targets.append_array(CardQuery.weapons_in_play(1 - pid))
	var until: int = GameManager.turn_serial + (2 if GameManager.active_player_id == pid else 1)  # hasta el final de tu próximo turno
	var total := 0
	for c in targets:
		if is_instance_valid(c):
			c.set_meta("silenced_until", until)  # KeywordManager.is_silenced
			total += EnterScript._cost(c)
	main._update_debug("%s: las Armas y Tótem oponentes pierden su habilidad" % _name(card))
	if total <= 3:
		var options: Array = ["Robar 0", "Robar 1", "Robar 2"]
		var n := 2
		if not PlayerSideScript.is_bot(pid):
			n = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta dos cartas" % _name(card), options, pid), 0)
		if n > 0:
			await ActionModule.draw(pid, n, _name(card), true)


static func _aklo(main: Node, card: Node, pid: int) -> void:
	var until: int = GameManager.turn_serial + (2 if GameManager.active_player_id == pid else 1) + 1
	for p in [0, 1]:
		RuleState.set_until("two_per_type", p, until)  # GoldManager._card_play_locked
	main._update_debug("%s: hasta el final de tu próximo turno, hasta dos cartas de cada tipo por turno" % _name(card))


## Juega una carta (datos ya fuera de su zona) pagando 'price'. false si no se pudo: el llamador la devuelve.
static func _play_paying(main: Node, pid: int, data: Dictionary, price: int) -> bool:
	if not main._gold_manager or not main._gold_manager.puede_pagar(price, -1, "", -1, pid):
		return false
	if price > 0 and not await PlayerSideScript.pay(main, pid, price):
		return false
	data["esta_oculta"] = false
	return await main._gold_manager.play_card_for_free(data, pid)


static func _cancer(main: Node, card: Node, pid: int) -> void:
	var allies: Array = []
	var shown := _reveal_until(main, pid, _name(card), func(s):
		if not s.is_empty() and int(s[-1].get("tipo", -1)) == Constants.CardType.ALIADO:
			allies.append(s[-1])
		return allies.size() >= 2)
	for a in allies:
		shown.erase(a)
	if not allies.is_empty():
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and allies.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: ¿cuál puedes jugar por un Oro menos? (el otro va a tu mano)" % _name(card),
				allies.map(func(d): return str(d.get("nombre", "?"))), pid), 0, allies.size() - 1)
		var to_play: Dictionary = allies.pop_at(idx)
		for d in allies:
			PlayerSideScript.put_in_hand(main, pid, d)
		var price: int = maxi(int(to_play.get("coste", 0)) - 1, 0)
		var play_it: bool = main._gold_manager and main._gold_manager.puede_pagar(price, -1, "", -1, pid)
		if play_it and not PlayerSideScript.is_bot(pid):
			play_it = await SelectionManager.await_two_choice(main, str(to_play.get("nombre", "")), "Jugarlo (coste %d)" % price, "A tu mano", pid)
		if not play_it or not await _play_paying(main, pid, to_play, price):
			PlayerSideScript.put_in_hand(main, pid, to_play)
	var deck: Array = CardManager.get_deck(pid)
	for d in shown:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(pid)
	AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % _name(card))


## corrupción del alma: "El próximo Aliado que juegues este turno reduce su coste en un Oro hasta un mínimo
## de 0..." (cost_modifiers se vacía al empezar el turno siguiente). "No puede ser Anulado ni sus
## habilidades canceladas" no se aplica.
static func _corrupcion_alma(main: Node, card: Node, pid: int) -> void:
	var serial: int = GameManager.turn_serial
	PaymentManager.agregar_modificador_coste(card, -1, func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("owner_id") != null and int(c.owner_id) == pid \
			and int(TurnManager.ally_played_serial.get(pid, -1)) != serial, true)
	var deck: Array = CardManager.get_deck(pid)
	if not deck.is_empty():
		PlayerSideScript.put_in_hand(main, pid, deck.pop_back())
	var opp_deck: Array = CardManager.get_deck(1 - pid)
	for _i in mini(2, opp_deck.size()):
		var d: Dictionary = opp_deck.pop_front()
		d["esta_oculta"] = false
		CardManager.append_to_exile(1 - pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _humpty(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid):
		return
	var all: Array = EnterScript._hand(main, opp)
	if all.is_empty():
		return
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	var allies: Array = all.filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO and int(c.get("card_cost")) <= 2)
	var chosen: Dictionary = {}
	if not allies.is_empty():
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and allies.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: elige un Aliado de coste 2 o menos" % _name(card),
				allies.map(func(c): return EnterScript._name(c)), pid), 0, allies.size() - 1)
		chosen = allies[idx].card_data.duplicate()
	var copy := not chosen.is_empty() and not CardManager.get_deck(pid).is_empty()
	if copy and not PlayerSideScript.is_bot(pid):
		copy = await SelectionManager.await_two_choice(main, _name(card), "Convertir la primera carta de tu Castillo en una copia de %s" % str(chosen.get("nombre", "")),
			"Generar un Oro por el turno", pid)
	if copy:
		CardManager.get_deck(pid).pop_front()  # esa carta pasa a ser la copia
		chosen["esta_oculta"] = false
		var node: Node = main._create_card(chosen, false)
		node.owner_id = pid
		node.controller_id = pid
		main._connect_card_signals(node)
		await main._gold_manager._play_card_to_field(node)
		if main.get("_zone_manager"):
			main._zone_manager._update_castillo_counts()
	elif main._gold_manager:
		main._gold_manager.generar_oros_virtuales(1, pid)


static func _remate_mortal(main: Node, card: Node, pid: int) -> void:
	var has_descanso := false
	for d in CardManager.get_cemetery(pid) + CardManager.get_exile(pid):
		if CemeteryTriggersScript.normalize(str(d.get("nombre", ""))) == "descanso solar":
			has_descanso = true
	var buff := true
	var revive := has_descanso
	if not has_descanso:
		buff = PlayerSideScript.is_bot(pid) or await SelectionManager.await_two_choice(main, _name(card),
			"Tus Aliados +1 y los oponentes -1 de Fuerza, permanentemente", "Juega una carta de tu Cementerio por un Oro menos", pid)
		revive = not buff
	if buff:
		for side in [pid, 1 - pid]:
			for c in EnterScript._in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
				await _buff_turn(c, card, 1 if side == pid else -1, true)
	if revive and main._gold_manager:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega una carta de tu Cementerio por un Oro menos" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) != Constants.CardType.ORO and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid))
		for pk in picks:
			if CardManager.take_from_cemetery(pid, pk.data) and not await _play_paying(main, pid, pk.data, price.call(pk.data)):
				CardManager.add_to_cemetery(pid, pk.data)


static func _transformacion_lucy(main: Node, card: Node, pid: int) -> void:
	var mine: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM] \
		and c.get("owner_id") != null and int(c.owner_id) == pid)
	var steal := not mine.is_empty()
	if not PlayerSideScript.is_bot(pid):
		steal = await SelectionManager.await_two_choice(main, _name(card), "Ganar el control de un Aliado o Tótem del que seas dueño",
			"Al final del turno, un Aliado gana 2 de Fuerza permanentemente e Indesterrable", pid)
	if steal:
		var target: Node = await EnterScript._pick_from(main, pid, "%s: elige una carta de la que seas dueño" % _name(card), mine, false)
		if not is_instance_valid(target):
			return
		var cost: int = EnterScript._cost(target)
		ContinuousEffectManager.gain_control_of_card(target, pid)
		await EnterScript._discard_own(main, card, pid, cost)
		return
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
		var ally: Node = await EnterScript._pick_from(main, pid, "Transformación de Lucy: un Aliado gana 2 de Fuerza e Indesterrable", allies, false)
		if is_instance_valid(ally):
			await _buff_turn(ally, null, 2, true)
			KeywordManager.grant_keyword(ally, Constants.Keyword.INDESTERRABLE, null, "permanent"))


static func _hijos_noche(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty():
		return
	var entries: Array = deck.map(func(d): return {"data": d, "eligible": true})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta una carta de cada tipo del Castillo oponente" % _name(card),
		[{"is_own": false, "zone": Constants.Zone.CASTILLO, "cards": entries, "exclusive": true}], 0, 5)
	var banished: Array = []
	var types: Dictionary = {}
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size():
			var d: Dictionary = entries[int(rp[1])].data
			if not types.has(int(d.get("tipo", -1))) and not banished.has(d):
				types[int(d.get("tipo", -1))] = true
				banished.append(d)
	for d in banished:
		deck.erase(d)
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	CardManager.shuffle_deck(opp)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if banished.size() > 3 or not main._gold_manager:
		return
	var gold_here: Array = banished.filter(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO)
	var pick: int = 0 if not gold_here.is_empty() else 1
	if not PlayerSideScript.is_bot(pid):
		pick = await SelectionManager.await_choice(main, _name(card),
			["Un Oro de ahí a tu Oro Pagado y Robar dos cartas", "Jugar una carta del Destierro oponente por un Oro menos", "Nada"], pid)
	if pick == 0 and not gold_here.is_empty():
		var g: Dictionary = gold_here[0]
		var exile: Array = CardManager.get_exile(opp)
		if exile.has(g):
			exile.erase(g)
			CardManager._emit_exile_changed(opp)
			var node: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, g)
			if is_instance_valid(node):
				node.owner_id = opp
		await ActionModule.draw(pid, 2, _name(card), true)
	elif pick == 1:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
		var exile: Array = CardManager.get_exile(opp)
		var e2: Array = exile.map(func(d): return {"data": d, "eligible": int(d.get("tipo", -1)) not in [Constants.CardType.TALISMAN, Constants.CardType.ORO] \
			and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)})
		var raw2: Array = await ActionModule.pick_in_zones(pid, "%s: una carta del Destierro oponente" % _name(card),
			[{"is_own": false, "zone": Constants.Zone.DESTIERRO, "cards": e2, "exclusive": true}], 0, 1)
		if raw2.is_empty() or not (raw2[0] is Array) or raw2[0].size() != 2:
			return
		var ci := int(raw2[0][1])
		if ci < 0 or ci >= e2.size() or not e2[ci].eligible:
			return
		var d2: Dictionary = e2[ci].data
		exile.erase(d2)
		CardManager._emit_exile_changed(opp)
		if not await _play_paying(main, pid, d2, price.call(d2)):
			CardManager.append_to_exile(opp, d2)


static func _avistamientos(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var both := false
	if not deck.is_empty():
		var top: Dictionary = deck[0]
		main._update_debug("%s muestra: %s" % [_name(card), str(top.get("nombre", "?"))])
		both = int(top.get("tipo", -1)) == Constants.CardType.ALIADO
		# La carta mostrada sigue en el Castillo, que se Baraja.
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(pid, [top], _name(card))
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").shuffle_back(main, pid, [], _name(card))
	var first := true
	if not both and not PlayerSideScript.is_bot(pid):
		first = await SelectionManager.await_two_choice(main, _name(card), "Barajar una carta de la mano oponente que no sea Oro",
			"En la próxima Fase Final oponente, mover un Oro oponente a su Oro Pagado", pid)
	if both or first:
		var opp: int = 1 - pid
		if not (EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid)):
			var all: Array = EnterScript._hand(main, opp)
			var options: Array = all.filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
			if not PlayerSideScript.is_bot(pid) and not all.is_empty():
				SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
			if not options.is_empty():
				var idx := 0
				if not PlayerSideScript.is_bot(pid) and options.size() > 1:
					idx = clampi(await SelectionManager.await_choice(main, "%s: elige una carta para Barajarla en su Castillo" % _name(card),
						options.map(func(c): return EnterScript._name(c)), pid), 0, options.size() - 1)
				PlayerSideScript.shuffle_from_hand(main, opp, options[idx], _name(card))
	if both or not first:
		var opp2: int = 1 - pid
		EffectController.schedule_next_final_phase_effect(opp2, func() -> void:
			var golds: Array = EnterScript._golds(main, [opp2]).filter(func(g): return g.get_parent() == PlayerSideScript.gold_reserva(main, opp2))
			if golds.is_empty() or not await EnterScript._confirm(main, pid, "Avistamientos", "Mover un Oro oponente a su Oro Pagado"):
				return
			var g: Node = await EnterScript._pick_from(main, pid, "Avistamientos: elige un Oro oponente", golds, true)
			if is_instance_valid(g):
				await LeavePlayScript._gold_to_paid(main, g))


static func _ataque_bandido(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Bandido en tu Castillo",
			"Jugar un Arma o Tótem de tu Cementerio o Destierro pagando su coste", pid)
	if search:
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"raza": "Bandido"}, 1, true, false, false, card)
		return
	if not main._gold_manager:
		return
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) in [Constants.CardType.ARMA, Constants.CardType.TOTEM] \
		and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid)
	var pools: Array = [
		{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "exclusive": true, "cards": CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
		{"is_own": true, "zone": Constants.Zone.DESTIERRO, "exclusive": true, "cards": CardManager.get_exile(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
	]
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Arma o Tótem de tu Cementerio o Destierro" % _name(card), pools, 0, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi > 1 or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var d: Dictionary = pools[pi].cards[ci].data
	if pi == 0:
		if not CardManager.take_from_cemetery(pid, d):
			return
	else:
		CardManager.get_exile(pid).erase(d)
		CardManager._emit_exile_changed(pid)
	if not await _play_paying(main, pid, d, int(d.get("coste", 0))):
		if pi == 0:
			CardManager.add_to_cemetery(pid, d)
		else:
			CardManager.append_to_exile(pid, d)


static func _vigilia_armas(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	# "Dos Oros: juega sin pagar su coste hasta dos Aliados de tu Cementerio cuyos costes sumen 2."
	if main._gold_manager.puede_pagar(2, -1, "", -1, pid) and await EnterScript._confirm(main, pid, _name(card),
			"Pagar dos Oros: jugar hasta dos Aliados de tu Cementerio cuyos costes sumen 2") and await PlayerSideScript.pay(main, pid, 2):
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: hasta dos Aliados cuyos costes sumen 2" % _name(card), 0, 2,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2)
		var total := 0
		for pk in picks:
			if total + int(pk.data.get("coste", 0)) > 2 or not CardManager.take_from_cemetery(pid, pk.data):
				continue
			total += int(pk.data.get("coste", 0))
			pk.data["esta_oculta"] = false
			if not await main._gold_manager.play_card_for_free(pk.data, pid):
				CardManager.add_to_cemetery(pid, pk.data)
	# "Un Oro: tus Aliados ganan 1 de Fuerza y hacen daño al Destierro este turno."
	if main._gold_manager.puede_pagar(1, -1, "", -1, pid) and await EnterScript._confirm(main, pid, _name(card),
			"Pagar un Oro: tus Aliados +1 de Fuerza y daño al Destierro este turno") and await PlayerSideScript.pay(main, pid, 1):
		for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
			await _buff_turn(c, card, 1)
			c.set_meta("damage_to_exile_turn", GameManager.turn_serial)


static func _proteger_botin(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
		var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.ARMA and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)
		var hand_nodes: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
		var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
		if not hand_nodes.is_empty() or entries.any(func(e): return e.eligible):
			var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Arma de tu mano o Cementerio por un Oro menos" % _name(card),
				[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 1, 1, false, hand_nodes)
			if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2:
				var data: Dictionary = {}
				if int(raw[0][0]) == -1 and int(raw[0][1]) >= 0 and int(raw[0][1]) < hand_nodes.size():
					data = PlayerSideScript.take_from_hand(main, pid, hand_nodes[int(raw[0][1])])
				elif int(raw[0][0]) == 0 and int(raw[0][1]) >= 0 and int(raw[0][1]) < entries.size() and entries[int(raw[0][1])].eligible \
						and CardManager.take_from_cemetery(pid, entries[int(raw[0][1])].data):
					data = entries[int(raw[0][1])].data
				if not data.is_empty() and not await _play_paying(main, pid, data, price.call(data)):
					CardManager.add_to_cemetery(pid, data)
		# "Puedes cambiar cualquier cantidad de Armas que controles de portador."
		while not CardQuery.weapons_in_play(pid).is_empty() and not PlayerSideScript.is_bot(pid) \
				and await SelectionManager.await_two_choice(main, _name(card), "Cambiar un Arma de portador", "Listo", pid):
			var w: Node = await EnterScript._pick_from(main, pid, "%s: elige un Arma" % _name(card), CardQuery.weapons_in_play(pid), true)
			if not is_instance_valid(w):
				break
			var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and c != w.get_parent())
			var nw: Node = await EnterScript._pick_from(main, pid, "%s: su nuevo portador" % _name(card), allies, true)
			if not is_instance_valid(nw):
				break
			var old = w.get_parent()
			if old and old.get("equipped_weapons") is Array:
				old.equipped_weapons.erase(w)
			await main._gold_manager._equip_weapon(w, nw, false)
	# "Los Aliados que porten Armas no pueden salir de juego este turno."
	for c in EnterScript._in_play(main, pid, func(c): return c.get("equipped_weapons") is Array and not c.equipped_weapons.is_empty()):
		c.set_meta("no_leave_turn", GameManager.turn_serial)


## Amarre de Bruja: "Gana el control del Aliado oponente, mientras tu Aliado esté en juego." Cuando tu
## Aliado sale del juego, el otro vuelve a su dueño.
static func _amarre_bruja(main: Node, card: Node, pid: int) -> void:
	var mine := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) >= 2)
	var anchor: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado que controles de coste 2 o más" % _name(card), mine, false)
	if not is_instance_valid(anchor):
		return
	var limit: int = int(ContinuousEffectManager.get_modified_strength(anchor))
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and int(ContinuousEffectManager.get_modified_strength(c)) <= limit)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado oponente de Fuerza %d o menos" % [_name(card), limit], rivals, false)
	if not is_instance_valid(target):
		return
	ContinuousEffectManager.gain_control_of_card(target, pid)
	var release: Callable
	release = func(_p: int, left: Node, _z: int) -> void:
		if left != anchor:
			return
		if EffectController.on_card_left_play.is_connected(release):
			EffectController.on_card_left_play.disconnect(release)
		if is_instance_valid(target) and target.get("current_zone") in Constants.ZONES_IN_PLAY and target.get("owner_id") != null:
			ContinuousEffectManager.gain_control_of_card(target, int(target.owner_id))
	EffectController.on_card_left_play.connect(release)
