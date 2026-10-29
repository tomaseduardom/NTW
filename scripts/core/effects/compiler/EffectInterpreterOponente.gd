extends "res://scripts/core/effects/compiler/EffectInterpreterCadaJugador.gd"
## EffectInterpreterOponente — familia "tu oponente" de EffectInterpreter.gd (ver EffectInterpreterBase.gd):
## lo que tu oponente hace o elige sobre lo suyo (EffectCompiler, átomos opp:*) y las reglas que le pones
## para su próximo turno. Lo que hizo un paso lo leen las oraciones "de esta forma" que siguen (_each).
## Elige el oponente: el Remoto por red (con su id), el bot aquí.

const ConvertPatternsScript = preload("res://scripts/core/effects/mechanics/ConvertPatterns.gd")


func _execute_step(main: Node, st: Dictionary, targets: Array, card: Node, controller_id: int) -> bool:
	if st.op == "opp":
		return await _opp_step(main, st, card, controller_id)
	return await super(main, st, targets, card, controller_id)


func _condition_holds(cond, card: Node, controller_id: int = -1) -> bool:
	if str(cond) == "milled_less_10":  # vampiro eterno: "Si Bota menos de diez cartas"
		return int(_each.get("milled", 0)) < 10
	if cond is Dictionary and cond.get("kind", "") == "affected_cost":  # white worm: "Si era de coste 3 o más"
		var aff: Array = _each.get("affected", [])
		if aff.is_empty():
			return false
		var cost: int = int(aff[0].get("cost", 0))
		return cost >= int(cond.n) if cond.cmp == "mas" else cost <= int(cond.n)
	if cond is Dictionary and cond.get("kind", "") == "opp_exile_at_least":  # lucy
		return CardManager.get_exile(1 - controller_id).size() >= int(cond.n)
	if str(cond) == "no_golds":  # lucerna: "Si no tienes Oros" (en juego)
		var main := _ts.get_node_or_null("/root/Main")
		return main != null and _controlled_in_play(main, controller_id).filter(func(c): return c.get("card_type") == Constants.CardType.ORO).is_empty()
	if str(cond) == "exiled_less_6":  # furia del exilio
		return _each.get("exiled", []).size() < 6
	if str(cond) == "none_named_exiled":  # caída del alba / temaukel: "Si no Destierra ninguna"
		return int(_each.get("named_exiled", 0)) == 0
	return super(cond, card, controller_id)


func _opp_step(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	var me := controller_id
	var opp := 1 - controller_id
	var title := _card_name(card)
	match str(st.kind):
		"mill_half":  # vampiro eterno: "Tu oponente Bota la mitad de su Castillo, redondeado hacia arriba"
			var half: int = ceili(CardManager.get_deck_count(opp) / 2.0)
			_each["milled"] = 0
			if half <= 0:
				return true
			var res: Dictionary = await ActionModule.mill(opp, half, false, "efecto_compilado", true)
			_each["milled"] = int(res.get("actual", 0))
			return true
		"discard_or_shuffle":
			return await _discard_or_shuffle(main, card, me)
		"silence_golds":
			return await _silence_golds(main, st, card, me)
		"convert_match":
			return await _convert_match(main, card, me)
		"convert_steal":  # pacto sangriento: "Si se convierten 3 o menos cartas de esa manera, gana su control"
			var converted: Array = _each.get("converted", []).filter(func(c): return _alive(c))
			if converted.is_empty() or converted.size() > int(st.get("amount", 3)):
				return true
			if await EffectContextScript.ensure_window():
				return false
			for c in converted:
				ContinuousEffectManager.gain_control_of_card(c, me)
			if main.get("_zone_manager"):
				main._zone_manager.compact_all_fields(true)
			main._update_debug("%s: ganas el control de %d Tótem" % [title, converted.size()])
			return true
		"next_turn_lock":  # daikaiju furioso: GameManager.attack_cap / GoldManager._card_play_locked
			var start: int = RuleState.next_own_turn(opp)
			RuleState.set_window("no_attacks", opp, start, start + 1)
			RuleState.set_window("one_per_type", opp, start, start + 1)
			main._update_debug("%s: en su próximo turno, tu oponente no puede atacar ni jugar más de una carta de cada tipo" % title)
			return true
		"ability_toll":
			# guerra celestial: la carta rival que se está jugando, un Aliado o Tótem de coste 3 o menos
			# (TriggerTollPatterns.ability_toll, como koto).
			var obj: Dictionary = StackAnnulScript.find_target(me, true, false, func(o: Dictionary) -> bool:
				return StackAnnulScript.type_of(o) in [Constants.CardType.ALIADO, Constants.CardType.TOTEM] and StackAnnulScript.cost_of(o) <= 3)
			var node = StackAnnulScript.card_of(obj) if not obj.is_empty() else null
			if node == null or not is_instance_valid(node):
				main._update_debug("%s: no hay un Aliado o Tótem oponente jugándose" % title)
				return false
			node.set_meta("ability_toll_turn", GameManager.turn_serial)
			_each["toll_card"] = node
			main._update_debug("%s: tu oponente debe pagar un Oro para usar las habilidades de %s este turno" % [title, str(node.get("card_name"))])
			return true
		"toll_reward_draw":  # "Cuando tu oponente pague un Oro de esta forma, tú Robas una carta" (TriggerTollPatterns.pay_toll)
			var toll_card = _each.get("toll_card")
			if toll_card == null or not is_instance_valid(toll_card):
				return false
			toll_card.set_meta("ability_toll_reward", {"turn": GameManager.turn_serial, "pid": me})
			return true
		"name_lock":
			return await _name_lock(main, card, me)
	push_warning("[EffectInterpreter] 'tu oponente' desconocido: %s" % st.kind)
	return false


func _discard_or_shuffle(main: Node, card: Node, me: int) -> bool:
	"""perun: 'hacer que tu oponente deba Descartar una carta o Barajar una carta que controle que no sea
	Oro' — elige él (el bot, descartar si tiene mano)."""
	var opp := 1 - me
	var title := _card_name(card)
	var hand := _hand_cards(main, opp)
	var pool: Array = _controlled_in_play(main, opp).filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
	if hand.is_empty() and pool.is_empty():
		main._update_debug("%s: tu oponente no tiene cartas en la mano ni en juego que no sean Oro" % title)
		return false
	var discard := not hand.is_empty()
	if not hand.is_empty() and not pool.is_empty() and not _is_bot(opp):
		discard = await SelectionManager.await_two_choice(main, title, "Descartar una carta", "Barajar una carta que controles", opp)
	if discard:
		return await _discard(main, {"who": "opponent", "amount": 1, "random": false}, me)
	if await EffectContextScript.ensure_window():
		return false
	var picked: Array = []
	if _is_bot(opp):
		pool.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get("card_cost")) < int(b.get("card_cost")))
		picked = pool.slice(0, 1)
	elif main.get("_card_interaction"):
		picked = await main._card_interaction._await_multi_target_raw("%s: baraja una carta que controles que no sea Oro" % title,
			pool, 1, Callable(), Callable(), false, null, opp)
	picked = picked.filter(func(c): return _alive(c))
	if picked.is_empty():
		return false
	return await _apply_verb({"verb": "shuffle", "count": 1, "up_to": false}, picked, card)


func _silence_golds(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""hambre del vacío: 'Tu oponente elige dos Oros con habilidad que controle y los convierte en Oros sin
	habilidad' (el bot, los primeros)."""
	var opp := 1 - me
	var title := _card_name(card)
	var pool: Array = _controlled_in_play(main, opp).filter(func(c): return (c.get("card_type") == Constants.CardType.ORO
		and not str(c.card_data.get("habilidad", "")).strip_edges().is_empty() and not KeywordManager.is_silenced(c)))
	var n: int = mini(int(st.get("amount", 1)), pool.size())
	if n <= 0:
		main._update_debug("%s: tu oponente no controla Oros con habilidad" % title)
		return int(st.get("amount", 1)) <= 0
	var picked: Array = pool.slice(0, n)
	if pool.size() > n and not _is_bot(opp) and main.get("_card_interaction"):
		picked = await main._card_interaction._await_multi_target_raw("%s: elige %d Oro(s) con habilidad que pierden su habilidad" % [title, n],
			pool, n, Callable(), Callable(), false, null, opp)
	picked = picked.filter(func(c): return _alive(c))
	if await EffectContextScript.ensure_window():
		return false
	for g in picked:
		await KeywordManager.silence_card(g, card, "permanent")
	return picked.size() >= int(st.get("amount", 1))


func _allies_and_golds(main: Node, pid: int) -> Array:
	return _controlled_in_play(main, pid).filter(func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.ORO])


func _convert_match(main: Node, card: Node, me: int) -> bool:
	"""pacto sangriento: tu oponente convierte Aliados y Oros que controle en Tótem sin habilidad hasta tener
	tantos Aliados y Oros como tú. Elige él cuáles (el bot, primero los Aliados de menos Fuerza). Los
	convertidos quedan en _each.converted para "si se convierten 3 o menos..."."""
	var opp := 1 - me
	var title := _card_name(card)
	_each["converted"] = []
	var pool := _allies_and_golds(main, opp)
	var extra: int = pool.size() - _allies_and_golds(main, me).size()
	if extra <= 0:
		return true
	var picked: Array = []
	if _is_bot(opp):
		var value := func(c: Node) -> int:
			return int(ContinuousEffectManager.get_modified_strength(c)) if c.get("card_type") == Constants.CardType.ALIADO else 99
		pool.sort_custom(func(a: Node, b: Node) -> bool: return value.call(a) < value.call(b))
		picked = pool.slice(0, extra)
	elif main.get("_card_interaction"):
		picked = await main._card_interaction._await_multi_target_raw("%s: convierte %d Aliado(s) u Oro(s) en Tótem sin habilidad" % [title, extra],
			pool, extra, Callable(), Callable(), false, null, opp)
	picked = picked.filter(func(c): return _alive(c))
	if picked.is_empty():
		return false
	if await EffectContextScript.ensure_window():
		return false
	var converted: Array = []
	for c in picked:
		var parent = c.get_parent()
		var was_reserve: bool = parent == PlayerSideScript.gold_reserva(main, opp)
		var was_paid: bool = parent == PlayerSideScript.oro_pagado(main, opp)
		if not await ConvertPatternsScript.convert_in_play_to_totem(c, card, opp):
			continue
		# Un Oro que sale de la Reserva / del Oro Pagado deja de contarse (como GoldManager._take_gold_out_of_play).
		if was_reserve:
			GameState.agregar_oro_reserva(opp, -1)
		elif was_paid:
			GameState.agregar_oro_pagado(opp, -1)
		if (was_reserve or was_paid) and opp == 0 and main.get("gold_cards") is Array:
			main.gold_cards.erase(c)
		converted.append(c)
	if main._gold_manager:
		main._gold_manager.update_gold_containers_spacing()
		main._gold_manager._update_gold_display()
	_each["converted"] = converted
	main._update_debug("%s: tu oponente convierte %d carta(s) en Tótem sin habilidad" % [title, converted.size()])
	return converted.size() >= extra


func _name_lock(main: Node, card: Node, me: int) -> bool:
	"""flechero: 'Nombra una carta. Las cartas con ese nombre no pueden ser jugadas en su próximo turno' —
	RuleState "name_play_lock:<nombre>" sobre el oponente, solo en su próximo turno
	(GoldManager.is_name_play_locked). El bot nombra una carta que no sea Oro de la mano rival."""
	var opp := 1 - me
	var picked_name := ""
	if _is_bot(me):
		var non_gold: Array = _hand_cards(main, opp).filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
		if not non_gold.is_empty():
			picked_name = str(non_gold.pick_random().get("card_name"))
	elif TriggerSystem.get("_card_name_search"):
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"%s: nombra una carta (tu oponente no puede jugarla en su próximo turno)" % _card_name(card), me)
		picked_name = str(picked.get("nombre", ""))
	if picked_name.is_empty():
		return false
	var start: int = RuleState.next_own_turn(opp)
	RuleState.set_window("name_play_lock:" + picked_name.strip_edges().to_lower(), opp, start, start + 1)
	main._update_debug("%s: tu oponente no puede jugar '%s' en su próximo turno" % [_card_name(card), picked_name])
	return true
