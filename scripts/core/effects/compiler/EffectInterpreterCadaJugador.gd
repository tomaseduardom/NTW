extends "res://scripts/core/effects/compiler/EffectInterpreterEjecucion.gd"
## EffectInterpreterCadaJugador — familia "cada jugador" de EffectInterpreter.gd (ver EffectInterpreterBase.gd):
## efectos que cada jugador hace sobre lo suyo (EffectCompiler, átomos each:*) y las oraciones "de esta
## forma" que leen lo que hicieron (_each, que también anota _keep_shuffle()).
## Cada jugador elige lo suyo: el Remoto por red (await_multi_target()/await_target() con su id), el bot
## aquí.

const ProtectionRulesScript = preload("res://scripts/core/effects/mechanics/ProtectionRules.gd")
const RevealedCardsScript = preload("res://scripts/core/effects/mechanics/RevealedCards.gd")


func _execute_step(main: Node, st: Dictionary, targets: Array, card: Node, controller_id: int) -> bool:
	if st.op == "each":
		return await _each_step(main, st, card, controller_id)
	return await super(main, st, targets, card, controller_id)


func _quantity_value(main: Node, q: Dictionary, card: Node, controller_id: int) -> int:
	if str(q.get("kind", "")) == "moved":  # "por cada carta Barajada de esta forma" (nahualismo)
		var total := 0
		for pid in _each.get("moved", {}):
			total += int(_each.moved[pid])
		return total
	return await super(main, q, card, controller_id)


func _condition_holds(cond, card: Node, controller_id: int = -1) -> bool:
	if cond is Dictionary and cond.get("kind", "") == "moved":
		# "Si tu oponente Barajó dos o menos Aliados de esta forma" (visión de noé).
		var pid: int = 1 - controller_id if cond.who == "opponent" else controller_id
		var n: int = int(_each.get("moved", {}).get(pid, 0))
		return n <= int(cond.n) if cond.cmp == "menos" else n >= int(cond.n)
	match str(cond):
		"duel_win", "duel_lose":
			# duelo nocturno: "Si tu Aliado tiene más Fuerza" / "Si tiene igual o menor Fuerza". Sin Aliado
			# propio no pasa ninguna; sin Aliado oponente, el tuyo tiene más.
			var duel: Dictionary = _each.get("duel", {})
			var mine = duel.get(controller_id)
			if mine == null or not _alive(mine):
				return false
			var theirs = duel.get(1 - controller_id)
			var their_str: int = ContinuousEffectManager.get_modified_strength(theirs) if theirs != null and _alive(theirs) else -1
			var wins: bool = ContinuousEffectManager.get_modified_strength(mine) > their_str
			return wins == (str(cond) == "duel_win")
		"drew_less_3":  # ensamble: "Si Robas menos de tres cartas"
			return int(_each.get("drawn", 0)) < 3
	return super(cond, card, controller_id)


func _alive(c) -> bool:
	return is_instance_valid(c) and c is Node and c.has_method("is_in_play") and c.is_in_play()


func _each_step(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	var me := controller_id
	var opp := 1 - controller_id
	match str(st.kind):
		"shuffle_all":  # nahualismo: "Cada jugador Baraja las cartas que controle que no sean Oro"
			var groups := {}
			var all: Array = []
			for pid in [me, opp]:
				groups[pid] = _controlled_in_play(main, pid).filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
				all.append_array(groups[pid])
			_each = {"moved": {me: 0, opp: 0}}
			if all.is_empty():
				return true
			if await EffectContextScript.ensure_window():
				return false
			await _apply_verb({"verb": "shuffle", "count": all.size(), "up_to": true}, all, card if is_instance_valid(card) else null)
			for pid in groups:
				_each.moved[pid] = groups[pid].filter(func(c): return not _alive(c)).size()
			return true
		"hand_to":  # armagedon: "Barajan cartas de su mano o Roban cartas, hasta tener cinco cartas en su mano"
			var target_n: int = int(st.get("amount", 5))
			for pid in [me, opp]:
				var have: int = _hand_cards(main, pid).size()
				if have > target_n:
					await _shuffle_from_hand(main, {"amount": have - target_n, "up_to": false,
						"who": "self" if pid == me else "opponent"}, me)
				elif have < target_n:
					await ActionModule.draw(pid, target_n - have, "efecto_compilado", true)
			return true
		"duel_put":
			return await _duel_put(main, st, card, me)
		"duel_destroy":  # "Destruye el Aliado oponente"
			var theirs = _each.get("duel", {}).get(opp)
			if theirs == null or not _alive(theirs):
				return false
			return await _apply_verb({"verb": "destroy", "count": 1}, [theirs], card)
		"duel_shuffle":  # "Baraja ambos Aliados"
			var both: Array = _each.get("duel", {}).values().filter(func(c): return _alive(c))
			if both.is_empty():
				return false
			return await _apply_verb({"verb": "shuffle", "count": both.size(), "up_to": true}, both, card)
		"reveal_top":
			return await _reveal_each_top(main, st, card, me)
		"fog_banish":
			return await _fog_banish(main, card, me)
		"random_split":
			return await _random_split(main, card, me)
		"hand_discard_cost":
			return await _hand_discard_cost(main, st, card, me)
		"draw_per_discarded":  # ensamble: "Por cada carta Descartada de tu mano de esta forma, Roba una carta"
			var n: int = int(_each.get("moved", {}).get(me, 0))
			_each["drawn"] = n
			if n > 0:
				await ActionModule.draw(me, n, "efecto_compilado", true)
			return true
		"hand_show_exile":
			return await _hand_show_exile(main, card, me)
		"foreign_shuffle":
			return await _foreign_shuffle(main, st, card, me)
		"equalize_allies":
			return await _equalize_allies(main, card, me)
	push_warning("[EffectInterpreter] 'cada jugador' desconocido: %s" % st.kind)
	return false


func _duel_put(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""Duelo nocturno: cada jugador pone desde su mano en juego un Aliado de coste N o menos (si tiene); entran
	sin habilidad por el turno (silenced_until, como Expulsión) y sin pagar su coste."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var max_cost: int = int(st.get("amount", 2))
	_each = {"duel": {}}
	if await EffectContextScript.ensure_window():
		return false
	for pid in [me, 1 - me]:
		var fits := func(c) -> bool:
			return is_instance_valid(c) and c != card and c.get("card_type") == Constants.CardType.ALIADO and int(c.card_cost) <= max_cost
		var options: Array = _hand_cards(main, pid).filter(fits)
		if options.is_empty():
			continue
		options.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_data.get("fuerza", 0)) > int(b.card_data.get("fuerza", 0)))
		var picked: Node = options[0]
		if not _is_bot(pid):
			var chosen: Node = await PlayerSideScript.pick_from_hand(main, pid, "%s: pon en juego un Aliado de coste %d o menos" % [_card_name(card), max_cost],
				func(c): return c in options, false)
			if chosen and is_instance_valid(chosen):
				picked = chosen
		var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, picked)
		if data.is_empty():
			continue
		var node: Node = main._create_card(data, false)
		node.owner_id = pid
		node.controller_id = pid
		node.set_meta("silenced_until", GameManager.turn_serial)
		main._connect_card_signals(node)
		await gm._play_card_to_field(node)
		_each.duel[pid] = node
	return _each.duel.has(me)


func _reveal_each_top(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""'Cada jugador muestra N cartas del tope de su Castillo': salen del Castillo y las ven los dos; la
	oración siguiente (fog_banish / random_split) decide qué se mueve y devuelve el resto barajado."""
	var title := _card_name(card)
	var shown := {}
	for pid in [me, 1 - me]:
		var deck: Array = CardManager.get_deck(pid)
		shown[pid] = []
		for _i in range(int(st.get("amount", 1))):
			if deck.is_empty():
				break
			var d: Dictionary = deck.pop_front()
			d["esta_oculta"] = false
			shown[pid].append(d)
		RevealedCardsScript.record(pid, shown[pid], title)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	_each = {"shown": shown}
	for viewer in [me, 1 - me]:
		var both: Array = shown[viewer] + shown[1 - viewer]
		if not both.is_empty() and not _is_bot(viewer):
			SelectionManager.open_reveal(both, "%s: tus %d cartas y luego las %d de tu oponente" % [title,
				shown[viewer].size(), shown[1 - viewer].size()], viewer)
	return not (shown[me].is_empty() and shown[1 - me].is_empty())


func _return_shown(main: Node, title: String) -> void:
	"""Lo mostrado que no se movió vuelve a su Castillo y se Baraja."""
	var shown: Dictionary = _each.get("shown", {})
	for pid in shown:
		RevealedCardsScript.shuffle_back(main, pid, shown[pid], title)
	_each.erase("shown")


func _fog_banish(main: Node, card: Node, me: int) -> bool:
	"""Niebla cuántica: por cada Aliado que mostraste, eliges una carta mostrada por tu oponente y la
	Destierras (el bot, las de mayor coste)."""
	var title := _card_name(card)
	var opp := 1 - me
	var shown: Dictionary = _each.get("shown", {})
	var mine: Array = shown.get(me, [])
	var theirs: Array = shown.get(opp, [])
	var k: int = mini(mine.filter(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO).size(), theirs.size())
	if ProtectionRulesScript.castle_banish_blocked(opp, me):
		k = 0
	var chosen_idx: Array = []
	if k > 0:
		if _is_bot(me):
			var order: Array = range(theirs.size())
			order.sort_custom(func(a: int, b: int) -> bool: return int(theirs[a].get("coste", 0)) > int(theirs[b].get("coste", 0)))
			chosen_idx = order.slice(0, k)
		else:
			var entries: Array = theirs.map(func(d): return {"data": d, "eligible": true})
			var raw: Array = await ActionModule.pick_in_zones(me, "%s: elige %d carta(s) de tu oponente para Desterrar" % [title, k],
				[{"is_own": false, "zone": Constants.Zone.CASTILLO, "cards": entries, "exclusive": true}], k, k)
			for r in raw:
				if r is Array and r.size() == 2 and int(r[1]) >= 0 and int(r[1]) < theirs.size() and not chosen_idx.has(int(r[1])):
					chosen_idx.append(int(r[1]))
			for i in range(theirs.size()):  # elegir es obligatorio: se completa si faltan
				if chosen_idx.size() >= k:
					break
				if not chosen_idx.has(i):
					chosen_idx.append(i)
	var banished: Array = chosen_idx.map(func(i): return theirs[i])
	shown[opp] = theirs.filter(func(d): return not banished.has(d))
	for d in banished:
		CardManager.add_to_exile(opp, d)
	if not banished.is_empty():
		main._update_debug("%s: Destierras %d carta(s) mostradas por tu oponente" % [title, banished.size()])
	_return_shown(main, title)
	return banished.size() >= k


func _random_split(main: Node, card: Node, me: int) -> bool:
	"""Pie de cueca: tu oponente Destierra una al azar entre las suyas y tú pones en tu mano una al azar
	entre las tuyas; el resto vuelve barajado."""
	var title := _card_name(card)
	var opp := 1 - me
	var shown: Dictionary = _each.get("shown", {})
	var theirs: Array = shown.get(opp, [])
	var mine: Array = shown.get(me, [])
	if not theirs.is_empty() and not ProtectionRulesScript.castle_banish_blocked(opp, opp):
		var gone: Dictionary = theirs.pick_random()
		theirs.erase(gone)
		CardManager.add_to_exile(opp, gone)
		main._update_debug("%s: tu oponente Destierra %s" % [title, str(gone.get("nombre", "una carta"))])
	if not mine.is_empty() and not ProtectionRulesScript.hand_by_effects_blocked(me):
		var got: Dictionary = mine.pick_random()
		mine.erase(got)
		PlayerSideScript.put_in_hand(main, me, got.duplicate())
		main._update_debug("%s: pones %s en tu mano" % [title, str(got.get("nombre", "una carta"))])
	_return_shown(main, title)
	return true


func _show_hands(main: Node, title: String, me: int) -> void:
	"""'Cada jugador muestra su mano': cada uno ve la del otro."""
	for pid in [me, 1 - me]:
		var viewer: int = 1 - pid
		var shown: Array = _hand_cards(main, pid).map(func(c): return c.card_data)
		if not shown.is_empty() and not _is_bot(viewer):
			SelectionManager.open_reveal(shown, "%s: la mano de tu oponente" % title, viewer)


func _hand_discard_cost(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""Ensamble: cada jugador muestra su mano y Descarta todas sus cartas de coste N o menos (un Oro no
	tiene coste)."""
	var title := _card_name(card)
	if await EffectContextScript.ensure_window():
		return false
	_show_hands(main, title, me)
	_each = {"moved": {me: 0, 1 - me: 0}}
	for pid in [me, 1 - me]:
		var cheap: Array = _hand_cards(main, pid).filter(func(c): return (c != card
			and c.get("card_type") != Constants.CardType.ORO and int(c.card_cost) <= int(st.get("amount", 1))))
		if cheap.is_empty():
			continue
		var before: int = _hand_cards(main, pid).size()
		await ActionModule.discard(pid, cheap, "efecto_compilado", true)
		_each.moved[pid] = maxi(0, before - _hand_cards(main, pid).size())
	return true


func _hand_show_exile(main: Node, card: Node, me: int) -> bool:
	"""Lobón: cada jugador muestra su mano y Destierra un Aliado de ahí (lo elige el dueño de la mano; el
	bot, el de menor coste)."""
	var title := _card_name(card)
	if await EffectContextScript.ensure_window():
		return false
	_show_hands(main, title, me)
	for pid in [me, 1 - me]:
		var allies: Array = _hand_cards(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
		if allies.is_empty():
			continue
		allies.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
		var picked: Node = allies[0]
		if not _is_bot(pid):
			var chosen: Node = await PlayerSideScript.pick_from_hand(main, pid, "%s: Destierra un Aliado de tu mano" % title,
				func(c): return c in allies, false)
			if chosen and is_instance_valid(chosen):
				picked = chosen
		var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, picked)
		if not data.is_empty():
			CardManager.add_to_exile(pid, data)
	return true


func _foreign_shuffle(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""Jurado descontento: cada jugador Baraja los Aliados y Tótems que controla de los que no es dueño (cada
	uno al Castillo de su dueño) y Destierra N cartas del tope de su Castillo por cada una."""
	var groups := {}
	var all: Array = []
	for pid in [me, 1 - me]:
		groups[pid] = _controlled_in_play(main, pid).filter(func(c): return (c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM]
			and c.get("owner_id") != null and int(c.owner_id) != pid))
		all.append_array(groups[pid])
	if all.is_empty():
		return true
	if await EffectContextScript.ensure_window():
		return false
	await _apply_verb({"verb": "shuffle", "count": all.size(), "up_to": true}, all, card)
	for pid in groups:
		var n: int = groups[pid].filter(func(c): return not _alive(c)).size() * int(st.get("amount", 2))
		if n > 0:
			CardManager.banish_from_deck(pid, n, false, me)
	return true


func _equalize_allies(main: Node, card: Node, me: int) -> bool:
	"""La Justicia: quien controla más Aliados Baraja los que sobran (los elige él; el bot, los de menor
	coste) hasta controlar los mismos que el otro."""
	var title := _card_name(card)
	var allies := {}
	for pid in [me, 1 - me]:
		allies[pid] = _controlled_in_play(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var extra: int = allies[me].size() - allies[1 - me].size()
	if extra == 0:
		return true
	var pid: int = me if extra > 0 else 1 - me
	var pool: Array = allies[pid]
	var n: int = absi(extra)
	if await EffectContextScript.ensure_window():
		return false
	pool.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
	var picked: Array = pool.slice(0, n)
	if not _is_bot(pid) and main.get("_card_interaction"):
		# Elegir los propios no tiene Oro adicional (no los afecta el rival).
		var chosen: Array = await main._card_interaction._await_multi_target_raw("%s: Baraja %d Aliado(s) que controles" % [title, n],
			pool, n, Callable(), Callable(), false, null, pid)
		chosen = chosen.filter(func(c): return is_instance_valid(c) and c in pool)
		if chosen.size() == n:
			picked = chosen
	return await _apply_verb({"verb": "shuffle", "count": n, "up_to": true}, picked, card)
