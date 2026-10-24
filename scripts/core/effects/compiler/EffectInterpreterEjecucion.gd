extends "res://scripts/core/effects/compiler/EffectInterpreterDeclaracion.gd"
## EffectInterpreterEjecucion — familia Ejecucion de EffectInterpreter.gd (ver EffectInterpreterBase.gd).


func _execute_steps(main: Node, steps: Array, chosen_targets: Dictionary, card: Node, controller_id: int) -> bool:
	"""Ejecuta en orden; corta en un paso 'then' si el anterior no se
	resolvió por completo. Devuelve si el último paso se resolvió."""
	var last_ok := true
	for i in range(steps.size()):
		var st: Dictionary = steps[i]
		if st.get("then", false) and not last_ok:
			print("[EffectInterpreter] %s: 'Luego' cortado (el paso anterior no se resolvió)" % _card_name(card))
			break
		last_ok = await _execute_step(main, st, chosen_targets.get(i, []), card, controller_id)
	return last_ok

# =============================================================================
# EJECUCIÓN
# =============================================================================


func _execute_step(main: Node, st: Dictionary, targets: Array, card: Node, controller_id: int) -> bool:
	"""Devuelve true si el paso se resolvió por completo (para 'Luego')."""
	var opponent_id := 1 - controller_id
	match st.op:
		"draw":
			if st.get("up_to", false):
				await ActionModule.draw_up_to(controller_id, st.amount, "efecto_compilado", true)
			else:
				await ActionModule.draw(controller_id, st.amount, "efecto_compilado", true)
			return true
		"draw_to_match":
			var missing: int = _hand_cards(main, opponent_id).size() - _hand_cards(main, controller_id).size()
			if missing <= 0:
				return true
			await ActionModule.draw(controller_id, missing, "efecto_compilado", true)
			return true
		"mill":
			var mill_pids: Array = [controller_id, opponent_id] if st.who == "both" \
				else [controller_id if st.who == "self" else opponent_id]
			var mill_amount: int = st.amount
			if st.get("per", "") != "":
				mill_amount *= _count_per(main, st.per, controller_id)
			if mill_amount > 0:
				for mill_pid in mill_pids:
					await ActionModule.mill(mill_pid, mill_amount, false, "efecto_compilado", true)
			return true
		"reveal_until":
			return await _reveal_until(main, st, card, controller_id)
		"hand_peek":
			return await _hand_peek(main, st, card, controller_id)
		"shuffle_from_cemetery":
			var res_cem: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], {},
				st.amount, st.up_to, false, false, card, Constants.Zone.CASTILLO)
			return st.up_to or res_cem.get("selected", []).size() >= st.amount
		"self_buff_per":
			var per_n: int = _count_per(main, str(st.per), controller_id)
			if per_n <= 0:
				return true
			if await EffectContextScript.ensure_window():
				return false
			return await _buff({"amount": int(st.amount) * per_n, "count": 1}, [card], card)
		"self":
			if not card.has_method("is_in_play") or not card.is_in_play():
				return false
			return await _apply_verb({"verb": st.verb, "count": 1, "up_to": false}, [card], card)
		"if":
			if not _condition_holds(st.cond, card):
				print("[EffectInterpreter] %s: condición '%s' no se cumple" % [_card_name(card), st.cond])
				return true
			return await _execute_steps(main, st.steps, {}, card, controller_id)
		"discard":
			return await _discard(main, st, controller_id)
		"shuffle_from_hand":
			return await _shuffle_from_hand(main, st, controller_id)
		"search":
			var zones: Array = []
			for z in st.zones:
				zones.append(Constants.Zone.CASTILLO if z == "castillo" else Constants.Zone.CEMENTERIO)
			var filter := _search_filter(st)
			var play: Dictionary = st.get("play", {})
			var dest: int = {"pagado": Constants.Zone.ORO_PAGADO, "cementerio": Constants.Zone.CEMENTERIO}.get(
				st.get("dest", "mano"), Constants.Zone.MANO)
			if play.get("free", false):
				dest = -1  # "y jugarlo sin pagar su coste": se juega desde los datos, sin pasar por la mano
			var res: Dictionary = await ActionModule.search_zones(controller_id, zones, filter, st.amount, true, false,
				not play.is_empty() and not play.get("free", false), card, dest, false, -1, int(play.get("reduce", 0)))
			if play.get("free", false) and main.get("_gold_manager"):
				for d in res.get("selected", []):
					await main._gold_manager.play_card_for_free(d, controller_id)
			return res.get("success", false) and not res.get("selected", []).is_empty()
		"gold_to_paid":
			return await _gold_to_paid(main, st, card, controller_id)
		"play_from":
			return await _play_from(main, st, card, controller_id)
		"peek_hand", "show_hand":
			# "Mira la mano de tu oponente" (la ve quien controla el efecto) / "Muestra tu mano" (la ve el
			# rival). Respeta Fisión Nuclear y Colapso Global como _hand_peek().
			if await EffectContextScript.ensure_window():
				return false
			var owner_pid: int = 1 - controller_id if st.op == "peek_hand" else controller_id
			var viewer: int = 1 - owner_pid
			if st.op == "peek_hand" and (EffectController.fision_hides_zones_of(owner_pid, controller_id, Constants.Zone.MANO)
					or await EffectController.offer_colapso_global(controller_id)):
				return false
			var shown: Array = PlayerSideScript.hand_cards(main, owner_pid).filter(func(c): return is_instance_valid(c)) \
				.map(func(c): return c.card_data)
			if not shown.is_empty() and not _is_bot(viewer):
				SelectionManager.open_reveal(shown, "%s: %s" % [_card_name(card),
					"la mano de tu oponente" if st.op == "peek_hand" else "la mano de tu oponente (te la muestra)"], viewer)
			return true
		"deck_to_hand":
			if await EffectContextScript.ensure_window():
				return false
			return _deck_to_hand(main, st, controller_id)
		"cancel_attack":
			return await _cancel_attack(main, st, card, controller_id)
		"mill_x":
			return await _mill_x(main, st, card, controller_id)
		"revive_blank":
			return await _revive_blank(main, st, card, controller_id)
		"opp_gold_to_paid":
			var opp_golds: Array = PlayerSideScript.gold_reserva(main, opponent_id).get_children().filter(
				func(g): return is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO)
			if opp_golds.is_empty():
				return false
			var gold: Node = opp_golds[0]
			if not _is_bot(controller_id) and opp_golds.size() > 1 and main.get("_card_interaction"):
				var g_pick: Node = await main._card_interaction.await_target("%s: elige un Oro oponente de su Reserva" % _card_name(card),
					func(c: Node) -> bool: return c in opp_golds, false, controller_id)
				if g_pick and is_instance_valid(g_pick):
					gold = g_pick
			if await EffectContextScript.ensure_window():
				return false
			if not await main._gold_manager._mover_oro_a_pagado(gold):
				GameState.pagar_oro(opponent_id, 1)
			main._gold_manager._update_gold_display()
			return true
		"self_raise":
			# "...para subirlo de tu Cementerio a tu mano" (Belial, sai): sus datos salen del Cementerio.
			var raise_owner: int = card.owner_id if card.get("owner_id") != null else controller_id
			var raise_idx: int = CardManager.get_cemetery(raise_owner).find(card.card_data)
			if raise_idx < 0:
				return false
			if await EffectContextScript.ensure_window():
				return false
			raise_idx = CardManager.get_cemetery(raise_owner).find(card.card_data)
			if raise_idx < 0:
				return false
			PlayerSideScript.put_in_hand(main, raise_owner, CardManager.remove_from_cemetery(raise_owner, raise_idx))
			return true
		"castle_exile":
			var exile_amount: int = int(st.amount)
			if st.get("per", "") == "opp_reserve":  # leng: "como Oros tenga en su Reserva"
				exile_amount = GameState.get_oro_reserva(opponent_id)
				if exile_amount <= 0:
					return true
			if await EffectContextScript.ensure_window():
				return false
			return not CardManager.banish_from_deck(opponent_id, exile_amount, st.get("bottom", false), controller_id).is_empty()
		"no_damage":
			if await EffectContextScript.ensure_window():
				return false
			var until: int = RuleState.next_own_turn(controller_id)
			RuleState.set_until("no_combat_damage", controller_id, until)
			if not st.get("combat_only", false):
				RuleState.set_until("no_direct_damage", controller_id, until)
			return true
		"target":
			return await _apply_verb(st, targets, card)
		"cemetery_cleanup":
			return await _cemetery_cleanup(main, st, card, controller_id)
		"gold":
			if main.get("_gold_manager"):
				var for_type: String = st.get("for", "")
				if for_type == "":
					main._gold_manager.generar_oros_virtuales(int(st.amount), controller_id)
				else:
					# "Genera un Oro para jugar Aliados": Oro Virtual restringido a ese tipo.
					var wanted: int = _type_enum(for_type)
					var predicate := func(card_type: int, _race: String, _cost: int) -> bool: return card_type == wanted
					main._gold_manager.generar_oro_virtual_restringido(int(st.amount), predicate,
						TYPE_LABELS.get(for_type, [for_type, for_type])[1].capitalize(), controller_id)
			return true
		"regroup_gold":
			if main.get("_gold_manager"):
				await main._gold_manager.agrupar_oros(controller_id, int(st.amount))
			return true
		"regroup_cards":
			if main.get("_gold_manager"):
				await main._gold_manager.agrupar_cartas(controller_id, int(st.amount))
			return true
		"castle_look":
			if await EffectContextScript.ensure_window():
				return false
			return await load("res://scripts/core/effects/CastleLook.gd").try_execute_text(card, str(st.text), controller_id)
		"buff":
			return await _buff(st, targets, card)
		"annul":
			var annul_res: Dictionary = StackAnnulScript.try_from_text(card, str(st.text), controller_id)
			if annul_res.is_empty():
				main._update_debug("%s: no hay nada en la pila que pueda Anular o Cancelar" % _card_name(card))
				return false
			return bool(annul_res.applied)
		"talisman_fizzle":
			_ts._totem_patterns.register_kotoku_in_talisman_fizzle(opponent_id)
			main._update_debug("%s: el próximo Talismán de tu oponente este turno se resuelve sin efecto" % _card_name(card))
			return true
		"mass_buff":
			return await execute_step_mass_buff(main, st, card, controller_id)
		"mass":
			var all := _candidates(main, st.target, card, controller_id)
			if all.is_empty():
				return true
			var mass_st := st.duplicate()
			mass_st["count"] = all.size()
			mass_st["up_to"] = false
			return await _apply_verb(mass_st, all, card)
	push_warning("[EffectInterpreter] Paso no soportado: %s" % st.op)
	return false


func _apply_verb(st: Dictionary, targets: Array, card: Node) -> bool:
	"""Aplica el verbo de un paso 'target'/'mass'/'self' a sus objetivos,
	revalidando que sigan en juego (pudieron salir durante la ventana de
	respuesta). silence_first: pierden la habilidad antes (no disparan su
	'cuando salga del juego'). replace_if_keyword: "Si tiene Exhumar, en
	vez de eso, Destiérralo" — por objetivo."""
	var alive: Array = []
	for t in targets:
		if is_instance_valid(t) and t.has_method("is_in_play") and t.is_in_play():
			alive.append(t)
	if alive.is_empty():
		return false
	var all_ok: bool = alive.size() >= int(st.get("count", 1)) or st.get("up_to", false)

	if st.get("silence_first", false):
		for t in alive:
			if not _ts._targeted_executor._target_text_denies(t, ["no puede perder su habilidad", "no pierde su habilidad"]):
				await KeywordManager.silence_card(t, card, "permanent")

	# Separar por verbo final (el reemplazo por keyword puede cambiarlo).
	var by_verb := {}
	var repl: Dictionary = st.get("replace_if_keyword", {})
	for t in alive:
		var verb: String = st.verb
		if not repl.is_empty() and KeywordManager.has_keyword(t, _keyword_enum(repl.keyword)):
			verb = repl.verb
		if not by_verb.has(verb):
			by_verb[verb] = []
		by_verb[verb].append(t)

	for verb in by_verb:
		var group: Array = by_verb[verb]
		match verb:
			"destroy":
				var r: Dictionary = await ActionModule.destroy(group, card, true, true)
				all_ok = all_ok and r.get("success", true)
			"banish":
				var r2: Dictionary = await ActionModule.banish(group, card, true, true)
				all_ok = all_ok and r2.get("success", true)
			"cost_shift":
				for t in group:
					var amount: int = int(st.get("amount", 1))
					var raise: bool = _controller_of(t) == _controller_of(card)  # bot: sube las propias, baja las rivales
					if not _is_bot(_controller_of(card)):
						raise = await SelectionManager.await_two_choice(_ts.get_node_or_null("/root/Main"), _card_name(card),
							"Aumentar su coste en %d" % amount, "Reducir su coste en %d" % amount, _controller_of(card))
					ContinuousEffectManager.register_modifier({
						"source": card, "target": t,
						"type": ContinuousEffectManager.ModifierType.COST, "stat": "cost",
						"value": amount if raise else -amount, "operation": "add",
						"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
						"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
						"description": "%s: coste %+d" % [_card_name(card), amount if raise else -amount],
					})
			"silence":
				# silence_card() ya revisa las protecciones ("no pueden perder su habilidad") y ofrece la
				# Prevención del rival.
				for t in group:
					if not _ts._targeted_executor._target_text_denies(t, ["no puede perder su habilidad", "no pierde su habilidad"]):
						await KeywordManager.silence_card(t, card, str(st.get("duration", "permanent")))
			"shuffle":
				for t in group:
					var owner: int = int(t.owner_id) if t.get("owner_id") != null else _controller_of(t)
					if await ActionModule.return_to_deck(t, owner, true, card):
						CardManager.shuffle_deck(owner)
					else:
						all_ok = false
	return all_ok


func _search_filter(st: Dictionary) -> Dictionary:
	"""Filtro de ActionModule._apply_card_filter() para un paso 'search' / 'play_from'."""
	var filter := {}
	var card_types: Array = st.get("card_types", [])
	if card_types.size() > 1:
		filter["type"] = card_types.map(func(w): return _type_enum(w))
	elif st.get("card_type", "") != "":
		filter["type"] = _type_enum(st.card_type)
	if not st.get("types_not", []).is_empty():
		filter["types_not"] = st.types_not.map(func(w): return _type_enum(w))
	if int(st.get("cost_val", -1)) >= 0:
		if st.get("cost_cmp", "") != "mas":
			filter["cost_max"] = int(st.cost_val)
		if st.get("cost_cmp", "") != "menos":
			filter["cost_min"] = int(st.cost_val)
	if st.get("no_ability", false):
		filter["no_ability"] = true
	if str(st.get("name", "")) != "":
		filter["name_contains"] = str(st.name)  # "busca un Leyaden..."
	if st.has("alts"):
		filter["alts"] = st.alts.map(func(a): return {"type": _type_enum(a.type) if a.type != "" else -1, "race": a.race})
	return filter


func _play_from(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Jugar un Aliado de coste 2 o menos desde tu mano o Cementerio sin pagar su coste / reduciendo su
	coste en un Oro / pagando su coste'. Con las dos zonas, se elige de dónde (el bot: Cementerio
	primero). Gratis: GoldManager.play_card_for_free(). Con coste: la carta pasa por la mano con el
	descuento (PlayerSide.play_from_hand(); el bot solo juega Aliados) y, si no se jugó, vuelve al
	Cementerio de donde salió."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var filter := _search_filter(st)
	filter["types_not"] = filter.get("types_not", []) + [Constants.CardType.ORO]  # un Oro no se juega
	var play: Dictionary = st.get("play", {})
	var played := 0
	for _i in range(int(st.amount)):
		var hand_nodes: Array = []
		if "mano" in st.zones:
			hand_nodes = PlayerSideScript.hand_cards(main, controller_id).filter(func(c):
				return is_instance_valid(c) and c != card and not ActionModule._apply_card_filter([c.card_data], filter).is_empty())
		var cem_ok: bool = "cementerio" in st.zones \
			and not ActionModule._apply_card_filter(CardManager.get_cemetery(controller_id), filter).is_empty()
		if hand_nodes.is_empty() and not cem_ok:
			break
		var from_hand := not hand_nodes.is_empty()
		if from_hand and cem_ok:
			from_hand = false if _is_bot(controller_id) else await SelectionManager.await_two_choice(main, _card_name(card),
				"De tu mano", "De tu Cementerio", controller_id)
		var data := {}
		var node: Node = null
		if from_hand:
			node = await PlayerSideScript.pick_from_hand(main, controller_id, "%s: elige la carta para jugar" % _card_name(card),
				func(c): return c in hand_nodes)
			if not node:
				break
		else:
			var res: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], filter, 1, true,
				false, false, card, -1)
			if res.get("selected", []).is_empty():
				break
			data = res.selected[0]
		if await EffectContextScript.ensure_window():
			return false
		if play.get("free", false):
			if node:
				data = PlayerSideScript.take_from_hand(main, controller_id, node)
			await gm.play_card_for_free(data, controller_id, play.get("exile_after", false))
			played += 1
			continue
		if not node:
			node = PlayerSideScript.put_in_hand(main, controller_id, data)
		var reduce: int = int(play.get("reduce", 0))
		if reduce > 0:
			PaymentManager.agregar_modificador_coste(node, -reduce, func(c: Node) -> bool: return c == node,
				int(play.get("floor", 1)) == 0)  # "hasta un mínimo de 0"
		await PlayerSideScript.play_from_hand(main, controller_id, node)
		if is_instance_valid(node) and reduce > 0:
			PaymentManager.remover_modificador_coste(node)
		if is_instance_valid(node) and node.get("current_zone") == Constants.Zone.MANO:
			if not from_hand:  # no se jugó: vuelve al Cementerio
				CardManager.add_to_cemetery(controller_id, PlayerSideScript.take_from_hand(main, controller_id, node))
			break
		played += 1
	return played > 0 or st.get("up_to", false)


func _gold_to_paid(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Pon un Oro de tu mano o Cementerio en tu Oro Pagado' (cueva del horror, Lord Ruthven) y 'poner
	un Oro en juego desde tu mano o Cementerio' (a la Reserva). Con las dos zonas posibles, se elige
	primero de dónde; el bot prefiere el Cementerio."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var is_gold := func(c) -> bool:
		var t = c.get("card_type") if c is Node else c.get("tipo")
		return t != null and int(t) == Constants.CardType.ORO
	var hand_ok: bool = "mano" in st.zones and PlayerSideScript.hand_cards(main, controller_id).any(is_gold)
	var cem_ok: bool = "cementerio" in st.zones and CardManager.get_cemetery(controller_id).any(is_gold)
	if not hand_ok and not cem_ok:
		return false
	var to_paid: bool = st.get("dest", "pagado") == "pagado"
	var from_hand := hand_ok
	if hand_ok and cem_ok:
		from_hand = false if _is_bot(controller_id) else await SelectionManager.await_two_choice(main, _card_name(card),
			"Un Oro de tu mano", "Un Oro de tu Cementerio", controller_id)
	if not from_hand:
		var res: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO],
			{"type": Constants.CardType.ORO}, 1, true, false, false, card,
			Constants.Zone.ORO_PAGADO if to_paid else Constants.Zone.RESERVA_ORO)
		return not res.get("selected", []).is_empty()
	var picked: Node = await PlayerSideScript.pick_from_hand(main, controller_id,
		"%s: elige un Oro de tu mano" % _card_name(card), is_gold)
	if not picked or await EffectContextScript.ensure_window():
		return false
	var data: Dictionary = PlayerSideScript.take_from_hand(main, controller_id, picked)
	if to_paid:
		await gm.put_gold_directly_in_pagado(controller_id, data)
	else:
		await gm.put_gold_directly_in_reserva(controller_id, data)
	return true


func _deck_to_hand(main: Node, st: Dictionary, controller_id: int) -> bool:
	"""'Pon dos cartas del fondo de tu Castillo en tu mano' / 'la primera y la última' (el índice 0 es
	el tope)."""
	if load("res://scripts/core/effects/mechanics/ProtectionRules.gd").hand_by_effects_blocked(controller_id):
		return false
	var deck: Array = CardManager.get_deck(controller_id)
	var taken: Array = []
	if st.from == "both":
		if not deck.is_empty():
			taken.append(deck.pop_front())
		if not deck.is_empty():
			taken.append(deck.pop_back())
	else:
		for i in int(st.amount):
			if deck.is_empty():
				break
			taken.append(deck.pop_back() if st.from == "bottom" else deck.pop_front())
	for d in taken:
		PlayerSideScript.put_in_hand(main, controller_id, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return not taken.is_empty()


func _cemetery_cleanup(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Baraja y/o Destierra hasta N cartas de los Cementerios' (mode both),
	'Destierra hasta N...' (banish), 'Baraja hasta N...' (shuffle). Los dos
	Cementerios; cada carta va al Castillo / Destierro de su dueño. one_zone ("de un Cementerio"):
	todas del mismo."""
	var amount: int = int(st.amount)
	var one_zone: bool = st.get("one_zone", false)
	match str(st.mode):
		"both":
			if main.get("_gold_manager"):
				await main._gold_manager._resolve_armeria_barajar_desterrar(amount, _card_name(card), controller_id)
		"banish":
			await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, amount, true, card,
				Constants.Zone.DESTIERRO, false, one_zone)
		"shuffle":
			var res: Dictionary = await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {},
				amount, true, card, Constants.Zone.CASTILLO, false, one_zone)
			for pid in [0, 1]:
				for d in res.get("selected", []):
					if CardManager.get_deck(pid).has(d):
						CardManager.shuffle_deck(pid)
						break
	return true  # "hasta": siempre se resuelve


func execute_step_mass_buff(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Tus (demás) Aliados ganan... / Los Aliados oponentes pierden...': todos los Aliados en juego de
	ese lado en este momento (también lo usa AllyEventTriggers.gd)."""
	var side: int = 1 - controller_id if st.side == "opponent" else controller_id
	var allies: Array = []
	for container in PlayerSideScript.ally_containers(main, side):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and not (st.others and c == card):
				allies.append(c)
	var mass_st := st.duplicate()
	mass_st["count"] = allies.size()
	mass_st["up_to"] = true
	return await _buff(mass_st, allies, card)


func _buff(st: Dictionary, targets: Array, card: Node) -> bool:
	"""'Un Aliado gana/pierde N de Fuerza, Furia, ... y hace daño al
	Destierro'. Duración (regla del usuario): la Fuerza es por el turno salvo
	'permanentemente'; las keywords son permanentes salvo 'por el turno'; el
	daño al Destierro, por el turno salvo 'permanentemente'. Prevención del
	rival incluida."""
	var all_ok: bool = targets.size() >= int(st.get("count", 1)) or st.get("up_to", false)
	for t in targets:
		if not (is_instance_valid(t) and t.has_method("is_in_play") and t.is_in_play()):
			all_ok = false
			continue
		if await EffectController.offer_prevention(t, card, "strength_change"):
			continue
		var kw_duration: String = "turn" if st.get("turn_only", false) else "permanent"
		if st.get("duration", "") == "until_next_turn":
			kw_duration = "until_next_turn"
		for kw in st.get("keywords", []):
			KeywordManager.grant_keyword(t, _keyword_enum(kw), card, kw_duration)
		if st.get("no_shuffle", false):
			# ProtectionRules.cannot_be_shuffled(); hasta tu próximo turno = también el del rival.
			var until: int = GameManager.turn_serial + 1 if kw_duration == "until_next_turn" \
				else (GameManager.turn_serial if kw_duration == "turn" else 1 << 30)
			t.set_meta("cannot_be_shuffled_until", until)
		if st.get("to_exile", false):
			if st.get("permanent", false):
				t.set_meta("converted_damage_to_exile", true)  # ProtectionRules.combat_damage_to_exile
			else:
				t.set_meta("damage_to_exile_turn", GameManager.turn_serial)  # BattleManager._accumulate_castle_damage
		if st.get("double_damage", false):
			t.set_meta("double_combat_damage_turn", GameManager.turn_serial)  # BattleManager
		if st.get("no_damage", false):
			t.set_meta("no_damage_turn", GameManager.turn_serial)  # BattleManager: ni al Castillo ni al bloqueador
		if st.has("set_strength") or st.get("double", false):
			_set_or_double_strength(st, t, card)
			continue
		if int(st.amount) == 0:
			continue
		ContinuousEffectManager.register_modifier({
			"source": t,
			"target": t,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": int(st.amount),
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT if st.get("permanent", false)
				else ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s %+d" % [_card_name(card), int(st.amount)],
		})
		if t.has_method("refresh_strength_badge"):
			t.refresh_strength_badge()
	return all_ok


func _revive_blank(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Pon en juego (hasta) N Aliados de tu Cementerio como Aliados sin habilidad': mismo camino que
	Alto Prime (CemeteryRevivePatterns): los datos salen del Cementerio con el texto vacío y entran
	por GoldManager._play_card_to_field()."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var filter := _search_filter({"card_type": "aliado", "cost_val": st.get("cost_val", -1), "cost_cmp": st.get("cost_cmp", "")})
	if ActionModule._apply_card_filter(CardManager.get_cemetery(controller_id), filter).is_empty():
		return st.get("up_to", false)
	var res: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], filter, int(st.amount),
		true, false, false, card, -1)
	var picked: Array = res.get("selected", [])
	if picked.is_empty():
		return st.get("up_to", false)
	if await EffectContextScript.ensure_window():
		return false
	for d in picked:
		var ally_data: Dictionary = (d as Dictionary).duplicate()
		ally_data["habilidad"] = ""
		ally_data["esta_oculta"] = false
		var node: Node = main._create_card(ally_data, false)
		node.owner_id = controller_id
		node.controller_id = controller_id
		main._connect_card_signals(node)
		await gm._play_card_to_field(node)
	return picked.size() >= int(st.amount) or st.get("up_to", false)


func _mill_x(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""Botar (o Desterrar del tope del Castillo rival) tantas cartas como: la Fuerza de un Aliado que
	controles / que porte Armas (se elige; el bot, el de más Fuerza), la del portador de esta Arma, o
	los Aliados en la mano rival. 'un jugador': se elige quién (el bot, el rival)."""
	var n := 0
	match str(st.src):
		"own_ally", "armed_ally":
			var pool: Array = []
			var pids: Array = [controller_id] if st.src == "own_ally" else [0, 1]
			for pid in pids:
				for cont in PlayerSideScript.ally_containers(main, pid):
					for a in cont.get_children():
						if not is_instance_valid(a) or a.get("card_type") != Constants.CardType.ALIADO:
							continue
						if st.src == "armed_ally" and (not (a.get("equipped_weapons") is Array) or a.equipped_weapons.is_empty()):
							continue
						pool.append(a)
			if pool.is_empty():
				main._update_debug("%s: no hay un Aliado para contar su Fuerza" % _card_name(card))
				return false
			pool.sort_custom(func(a: Node, b: Node) -> bool:
				return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
			var pick: Node = pool[0]
			if not _is_bot(controller_id) and pool.size() > 1 and main.get("_card_interaction"):
				var chosen: Node = await main._card_interaction.await_target("%s: elige el Aliado (cuenta su Fuerza)" % _card_name(card),
					func(c: Node) -> bool: return c in pool, false, controller_id)
				if chosen and is_instance_valid(chosen):
					pick = chosen
			n = ContinuousEffectManager.get_modified_strength(pick)
		"bearer":
			var bearer = card.get("wielder")
			if not (bearer is Node and is_instance_valid(bearer)):
				bearer = card.get_parent() if card.get_parent() and card.get_parent().get("equipped_weapons") is Array else null
			if bearer == null:
				return false
			n = ContinuousEffectManager.get_modified_strength(bearer)
		"opp_hand_allies":
			n = PlayerSideScript.hand_cards(main, 1 - controller_id).filter(
				func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO).size()
	var target_pid: int = 1 - controller_id
	if st.get("who", "opponent") == "choose" and not _is_bot(controller_id):
		target_pid = 1 - controller_id if await SelectionManager.await_two_choice(main, "%s: ¿quién Bota %d?" % [_card_name(card), n],
			"Tu oponente", "Tú", controller_id) else controller_id
	if n <= 0:
		return true
	if await EffectContextScript.ensure_window():
		return false
	if st.get("exile", false):
		CardManager.banish_from_deck(1 - controller_id, n, false, controller_id)
	else:
		await ActionModule.mill(target_pid, n, false, "efecto_compilado", true)
	return true


func _cancel_attack(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Cancela el ataque de (hasta N) Aliado(s) (oponente)': salen de GameManager.attackers y
	vuelven a su aspecto (mismo camino que Drácula en HandCementerioAbilityHandler). Respeta "su
	ataque no puede ser cancelado" (ProtectionRules.attack_uncancellable)."""
	var rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var candidates: Array = []
	for a in GameManager.attackers:
		if not is_instance_valid(a) or rules.attack_uncancellable(a):
			continue
		if st.get("opponent", false) and _controller_of(a) == controller_id:
			continue
		candidates.append(a)
	if candidates.is_empty():
		main._update_debug("%s: no hay un ataque que cancelar" % _card_name(card))
		return false
	var n: int = int(st.get("count", 1))
	var chosen: Array = []
	if _is_bot(controller_id):
		chosen = candidates.filter(func(a): return _controller_of(a) != controller_id).slice(0, n)
	elif main.get("_card_interaction"):
		chosen = await main._card_interaction.await_multi_target("%s: cancela el ataque de %d Aliado%s" % [
			_card_name(card), n, "" if n == 1 else "s"], candidates, n, Callable(), Callable(), true, null, controller_id)
	chosen = chosen.filter(func(a): return is_instance_valid(a))
	if chosen.is_empty():
		return false
	if await EffectContextScript.ensure_window():
		return false
	chosen = await EffectController.filter_attack_cancel(chosen, card)  # cancelar ataque afecta al Aliado
	for a in chosen:
		GameManager.attackers.erase(a)
	if main._card_interaction and main._card_interaction.has_method("unmark_attackers") and not chosen.is_empty():
		await main._card_interaction.unmark_attackers(chosen)
	return true


func _set_or_double_strength(st: Dictionary, t: Node, card: Node) -> void:
	"""'Tiene Fuerza N' (capa 7A, operación set: lo que se sume después se suma a N) o 'duplica su
	Fuerza' (+ la Fuerza actual). Por el turno, o hasta tu próximo turno: TIMED, que se descuenta
	en cada fin de turno (2 si es tu turno: este y el del rival)."""
	var duration: int = ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN
	var turns := 0
	if st.get("duration", "") == "until_next_turn":
		duration = ContinuousEffectManager.ModifierDuration.TIMED
		turns = 2 if GameManager.active_player_id == _controller_of(card) else 1
	var doubling: bool = st.get("double", false)
	var current: int = ContinuousEffectManager.get_modified_strength(t)
	ContinuousEffectManager.register_modifier({
		"source": t,
		"target": t,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": current if doubling else int(st.set_strength),
		"operation": "add" if doubling else "set",
		"duration": duration,
		"duration_value": turns,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY if doubling
			else ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "%s: %s" % [_card_name(card), "duplica su Fuerza" if doubling else "Fuerza %d" % int(st.set_strength)],
	})
	if t.has_method("refresh_strength_badge"):
		t.refresh_strength_badge()


func _reveal_until(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar <specs> y ponlos
	en tu mano': se muestran del tope hasta completar cada spec (cantidad,
	tipos, coste); esas van a la mano y el resto se baraja en el Castillo."""
	var deck: Array = CardManager.get_deck(controller_id)
	var need: Array = []
	for sp in st.specs:
		need.append(int(sp.count))
	var revealed: Array = []
	var taken: Array = []
	while not deck.is_empty() and need.any(func(n): return n > 0):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		for i in range(st.specs.size()):
			if need[i] > 0 and _spec_matches(st.specs[i], top):
				need[i] -= 1
				taken.append(top)
				break
	var title := _card_name(card)
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, title)
	# Visor de mostrar para quien controla el efecto: solo las cartas que indica (RevealWindow).
	if not taken.is_empty():
		var reveal_window = load("res://scripts/ui/zones/RevealWindow.gd")
		if st.get("play_free", false) and taken.size() > 1:
			taken = await reveal_window.choose_order(main, controller_id, taken, title)
		else:
			await reveal_window.show_cards(main, controller_id, taken, title,
				"Se juega sin pagar su coste" if st.get("play_free", false) else "Van a tu mano")
	for d in taken:
		revealed.erase(d)
	for d in revealed:
		deck.append(d)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	var queue_before: int = _ts.trigger_queue.size() if _ts else 0
	for d in taken:
		if st.get("play_free", false) and main.get("_gold_manager") and int(d.get("tipo", -1)) != Constants.CardType.ORO:
			await main._gold_manager.play_card_for_free(d.duplicate(), controller_id)  # "y juégalo sin pagar su coste"
		else:
			PlayerSideScript.put_in_hand(main, controller_id, d.duplicate())
	if st.get("play_free", false) and taken.size() > 1:
		await load("res://scripts/core/effects/mechanics/SearchPatterns.gd").reorder_new_triggers(queue_before, controller_id)
	return not need.any(func(n): return n > 0)


func _hand_peek(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Mira la mano de tu oponente y Destierra/Descarta/Baraja N cartas
	(filtro) de ahí'. Quien elige ve la mano entera; respeta Fisión Nuclear,
	Colapso Global y Terminal P-12 (EffectController.fision_hides_zones_of)."""
	var opp: int = 1 - controller_id
	var title := _card_name(card)
	if EffectController.fision_hides_zones_of(opp, controller_id, Constants.Zone.MANO) \
			or await EffectController.offer_colapso_global(controller_id):
		return false
	var hand: Array = PlayerSideScript.hand_cards(main, opp).filter(func(c): return is_instance_valid(c))
	if hand.is_empty():
		return false
	if not _is_bot(controller_id):
		SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % title, controller_id)
	var spec := {"types": st.get("types", []), "cost_val": st.get("cost_val", -1), "cost_cmp": st.get("cost_cmp", "")}
	var types_not: Array = st.get("types_not", [])
	var picked_count := 0
	for _i in range(int(st.count)):
		var candidates: Array = hand.filter(func(c):
			return is_instance_valid(c) and _spec_matches(spec, c.card_data) and _type_word(int(c.card_type)) not in types_not)
		if candidates.is_empty():
			break
		var idx := 0
		if not _is_bot(controller_id) and candidates.size() > 1:
			idx = await SelectionManager.await_choice(main, "%s: elige una carta de su mano" % title,
				candidates.map(func(c): return str(c.get("card_name"))), controller_id)
		var chosen: Node = candidates[clampi(idx, 0, candidates.size() - 1)]
		hand.erase(chosen)
		match str(st.verb):
			"banish":
				CardManager.add_to_exile(opp, PlayerSideScript.take_from_hand(main, opp, chosen))
			"discard":
				await ActionModule.discard(opp, [chosen], title, true)
			_:
				PlayerSideScript.shuffle_from_hand(main, opp, chosen, title)
		picked_count += 1
	return picked_count >= int(st.count)


func _spec_matches(spec: Dictionary, data: Dictionary) -> bool:
	var types: Array = spec.get("types", [])
	if not types.is_empty() and _type_word(int(data.get("tipo", -1))) not in types:
		return false
	if _type_word(int(data.get("tipo", -1))) in spec.get("types_not", []):
		return false
	var race: String = str(spec.get("race", ""))
	if race != "" and not (race.substr(0, 5) in ActionModule._strip_accents(str(data.get("raza", "")).to_lower())):
		return false
	var cval: int = int(spec.get("cost_val", -1))
	if cval >= 0:
		if int(data.get("tipo", -1)) == Constants.CardType.ORO:
			return false  # un Oro no tiene coste
		var cost: int = int(data.get("coste", 0))
		match str(spec.get("cost_cmp", "")):
			"menos":
				return cost <= cval
			"mas":
				return cost >= cval
			_:
				return cost == cval
	return true


func _condition_holds(cond, card: Node) -> bool:
	if cond is Dictionary and cond.get("kind", "") == "controls":
		return _controls_holds(cond, card)
	match str(cond):
		"not_attacked_this_turn":
			return int(card.get_meta("declared_attacker_turn", -1)) != GameManager.turn_serial
	push_warning("[EffectInterpreter] Condición desconocida: %s" % str(cond))
	return false


func _controls_holds(cond: Dictionary, card: Node) -> bool:
	"""'Si controlas (otro) (N o más) <tipo/raza> (de Fuerza N o más) (en Línea
	de Ataque)' — se cuenta al resolver, entre las cartas que controla quien
	controla 'card'."""
	var main := _ts.get_node_or_null("/root/Main")
	if not main:
		return false
	var pid: int = _controller_of(card)
	var containers: Array = []
	if cond.get("attack_line", false):
		containers = [PlayerSideScript.line_containers(main, pid)[1]]
	else:
		containers = PlayerSideScript.line_containers(main, pid)
	if cond.get("type", "") in ["oro", ""]:
		containers.append(PlayerSideScript.gold_reserva(main, pid))
		containers.append(PlayerSideScript.oro_pagado(main, pid))
	var race_forms: Array = []
	var race: String = EffectCompilerScript.normalize(str(cond.get("race", "")))
	if not race.is_empty():
		race_forms.append(race)
		if race.ends_with("es") and race.length() > 4:
			race_forms.append(race.substr(0, race.length() - 2))
		if race.ends_with("s"):
			race_forms.append(race.substr(0, race.length() - 1))
	var count := 0
	for container in containers:
		if not container:
			continue
		var pool: Array = container.get_children()
		for c in container.get_children():
			if is_instance_valid(c) and c.get("equipped_weapons") is Array:
				pool.append_array(c.equipped_weapons)
		for c in pool:
			if not is_instance_valid(c) or c.get("card_type") == null:
				continue
			if cond.get("other", false) and c == card:
				continue
			if _controller_of(c) != pid:
				continue
			var t: String = str(cond.get("type", ""))
			if t != "" and _type_word(int(c.card_type)) != t:
				continue
			if int(c.card_type) == Constants.CardType.TALISMAN:
				continue
			if not race_forms.is_empty():
				var card_race: String = EffectCompilerScript.normalize(str(c.get("card_raza")))
				if not race_forms.any(func(f): return f in card_race):
					continue
			if int(cond.get("min_strength", -1)) >= 0 \
					and ContinuousEffectManager.get_modified_strength(c) < int(cond.min_strength):
				continue
			count += 1
	return count >= int(cond.get("count", 1))


func _count_per(main: Node, per: String, controller_id: int) -> int:
	"""Cantidades dinámicas de 'por cada ...'."""
	var n := 0
	match per:
		"own_allies_defense":
			var field = main.get("player_field" if controller_id == 0 else "opponent_field")
			if field:
				for c in field.get_children():
					if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO:
						n += 1
		"own_golds":  # dragones de la reina: Reserva y Oro Pagado
			for zone in [PlayerSideScript.gold_reserva(main, controller_id), PlayerSideScript.oro_pagado(main, controller_id)]:
				if zone:
					for g in zone.get_children():
						if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO:
							n += 1
		"opp_exile":  # udug
			n = CardManager.get_exile(1 - controller_id).size()
		"own_exile_allies":  # brujo mendigo
			for d in CardManager.get_exile(controller_id):
				if int(d.get("tipo", -1)) == Constants.CardType.ALIADO:
					n += 1
		"totems_in_play_and_exile":  # Dr. Van Helsing: "por cada Tótem en juego y en tu Destierro"
			n = _count_per(main, "totems_in_play", controller_id)
			for d in CardManager.get_exile(controller_id):
				if int(d.get("tipo", -1)) == Constants.CardType.TOTEM:
					n += 1
		"own_allies", "own_totems", "totems_in_play":
			var want: int = Constants.CardType.ALIADO if per == "own_allies" else Constants.CardType.TOTEM
			for cname in BOARD_CONTAINERS:
				var container = main.get(cname)
				if not container:
					continue
				var is_own: bool = cname.begins_with("player_") == (controller_id == 0)
				if per != "totems_in_play" and not is_own:
					continue
				for c in container.get_children():
					if is_instance_valid(c) and c.get("card_type") == want:
						n += 1
	return n


func _discard(main: Node, st: Dictionary, controller_id: int) -> bool:
	var pid: int = controller_id if st.who == "self" else 1 - controller_id
	var hand := _hand_cards(main, pid)
	if hand.is_empty():
		return false
	var amount: int = mini(st.amount, hand.size())
	var picked: Array = []
	if st.random:
		hand.shuffle()
		picked = hand.slice(0, amount)
	elif _is_bot(pid):
		hand.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
		picked = hand.slice(0, amount)
	else:
		picked = await _ts._targeted_executor._select_hand_cards_for_discard(hand, amount, pid)
	if picked.is_empty():
		return false
	await ActionModule.discard(pid, picked, "efecto_compilado", true)
	return picked.size() >= st.amount
