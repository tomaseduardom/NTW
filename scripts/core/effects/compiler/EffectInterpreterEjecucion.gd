extends "res://scripts/core/effects/compiler/EffectInterpreterDeclaracion.gd"
## EffectInterpreterEjecucion — familia Ejecucion de EffectInterpreter.gd (ver EffectInterpreterBase.gd).

const KeywordParserScript = preload("res://scripts/core/cards/KeywordParser.gd")

## Lo que encontró la última búsqueda ("si buscaste un Dinosaurio, ...").
var _last_found: Array = []
## Lo que hizo el último paso "cada jugador" del efecto, para las oraciones "de esta forma" que siguen
## (EffectInterpreterCadaJugador): "moved" {jugador: cartas movidas}, "shown", "duel", "drawn".
var _each: Dictionary = {}


func _execute_steps(main: Node, steps: Array, chosen_targets: Dictionary, card: Node, controller_id: int) -> bool:
	"""Ejecuta en orden; corta en un paso 'then' si el anterior no se
	resolvió por completo. Devuelve si el último paso se resolvió."""
	var last_ok := true
	for i in range(steps.size()):
		var st: Dictionary = steps[i]
		if not is_instance_valid(card):
			card = null  # el paso anterior la sacó del juego (nahualismo la Baraja con el resto)
		if st.get("then", false) and not last_ok:
			print("[EffectInterpreter] %s: 'Luego' cortado (el paso anterior no se resolvió)" % _card_name(card))
			break
		if st.has("qty"):
			# Cantidad variable: se cuenta ahora ("por cada Aliado que controles", "tantas como su Fuerza").
			var v: int = await _quantity_value(main, st.qty.q, card, controller_id)
			st = st.duplicate()
			st[st.qty.key] = int(st[st.qty.key]) * v if st.qty.mode == "per" else v
			print("[EffectInterpreter] %s: cantidad variable = %d" % [_card_name(card), int(st[st.qty.key])])
			if int(st[st.qty.key]) <= 0:
				last_ok = true
				continue
		last_ok = await _execute_step(main, st, chosen_targets.get(i, []), card, controller_id)
	return last_ok


func _quantity_value(main: Node, q: Dictionary, card: Node, controller_id: int) -> int:
	"""Cuenta una cantidad de EffectCompiler._parse_quantity() al resolver."""
	match str(q.get("kind", "")):
		"distinct_types":
			var seen := {}
			for d in CardManager.get_exile(controller_id):
				seen[int(d.get("tipo", -1))] = true
			return seen.size()
		"zone_count":
			var n := 0
			for z in q.zones:
				var pool: Array = CardManager.get_cemetery(controller_id) if z == "cementerio" else CardManager.get_exile(controller_id)
				for d in pool:
					if _spec_matches({"types": q.get("types", []), "race": q.get("race", "")}, d):
						n += 1
			return n
		"stat":
			var of: String = str(q.of)
			var pool: Array = []
			if of in ["este aliado", "esta carta"]:
				pool = [card] if is_instance_valid(card) else []
			else:
				for pid in ([controller_id] if "que controles" in of else [0, 1]):
					pool.append_array(_cards_in_play_of(main, pid))
				if "aliado" in of:
					pool = pool.filter(func(x): return x.get("card_type") == Constants.CardType.ALIADO)
			if pool.is_empty():
				return 0
			var value := func(x: Node) -> int:
				if q.stat == "coste":
					return 0 if x.get("card_type") == Constants.CardType.ORO else int(x.card_data.get("coste", 0))
				return int(x.card_data.get("fuerza", 0)) if q.get("printed", false) else int(ContinuousEffectManager.get_modified_strength(x))
			pool.sort_custom(func(a: Node, b: Node) -> bool: return value.call(a) > value.call(b))
			var pick: Node = pool[0]
			if pool.size() > 1 and not _is_bot(controller_id) and main.get("_card_interaction"):
				var chosen: Node = await main._card_interaction.await_target("%s: elige la carta (cuenta su %s)" % [_card_name(card),
					"Coste" if q.stat == "coste" else "Fuerza"], func(c: Node) -> bool: return c in pool, false, controller_id)
				if chosen and is_instance_valid(chosen):
					pick = chosen
			return value.call(pick)
		"play_count":
			var counts: Array = []
			var pids: Array = {"self": [controller_id], "opponent": [1 - controller_id]}.get(str(q.who), [0, 1])
			for pid in pids:
				var pool: Array = []
				if q.get("defense", false):
					var lines: Array = PlayerSideScript.line_containers(main, pid)
					pool = lines[0].get_children().filter(func(x): return is_instance_valid(x)) if not lines.is_empty() else []
				else:
					pool = _cards_in_play_of(main, pid)
				var matched: Array = pool.filter(func(x: Node) -> bool:
					if not is_instance_valid(x) or x.get("card_data") == null:
						return false
					var d: Dictionary = x.card_data.duplicate()
					d["tipo"] = int(x.card_type)
					d["fuerza"] = int(ContinuousEffectManager.get_modified_strength(x)) if x.card_type == Constants.CardType.ALIADO else 0
					return _spec_matches(q, d))
				if q.get("distinct_cost", false):
					var costs := {}
					for x in matched:
						costs[int(x.card_data.get("coste", 0))] = true
					counts.append(costs.size())
				else:
					counts.append(matched.size())
			if str(q.who) == "any":
				return counts.reduce(func(a, b): return a + b, 0)
			if str(q.who) == "choose" and counts.size() == 2:
				# "como Aliados controle un jugador": se elige el jugador (el bot, el que más tenga).
				if _is_bot(controller_id):
					return maxi(counts[0], counts[1])
				var mine: bool = await SelectionManager.await_two_choice(main, _card_name(card),
					"Tú (%d)" % counts[controller_id], "Tu oponente (%d)" % counts[1 - controller_id], controller_id)
				return counts[controller_id] if mine else counts[1 - controller_id]
			return counts[0] if not counts.is_empty() else 0
	return 0

# =============================================================================
# EJECUCIÓN
# =============================================================================


func _execute_step(main: Node, st: Dictionary, targets: Array, card: Node, controller_id: int) -> bool:
	"""Devuelve true si el paso se resolvió por completo (para 'Luego')."""
	var opponent_id := 1 - controller_id
	match st.op:
		"draw":
			for pid in ([controller_id, opponent_id] if st.get("who", "") == "both" else [controller_id]):
				if st.get("up_to", false):
					await ActionModule.draw_up_to(pid, st.amount, "efecto_compilado", true)
				else:
					await ActionModule.draw(pid, st.amount, "efecto_compilado", true)
			return true
		"hand_exile":
			return await _hand_exile(main, st, card, controller_id)
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
		"reveal_top":
			return await _reveal_top(main, st, card, controller_id)
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
			if st.verb == "shuffle" and is_instance_valid(card) and not (card.has_method("is_in_play") and card.is_in_play()):
				return await _shuffle_self(main, card, controller_id)  # "si está en tu Destierro, puedes Barajarlo"
			if not card.has_method("is_in_play") or not card.is_in_play():
				return false
			return await _apply_verb({"verb": st.verb, "count": 1, "up_to": false}, [card], card)
		"if":
			if not _condition_holds(st.cond, card, controller_id):
				print("[EffectInterpreter] %s: condición '%s' no se cumple" % [_card_name(card), st.cond])
				return true
			return await _execute_steps(main, st.steps, {}, card, controller_id)
		"discard":
			return await _discard(main, st, controller_id)
		"shuffle_from_hand":
			return await _shuffle_from_hand(main, st, controller_id)
		"keep_shuffle":
			return await _keep_shuffle(main, st, card, controller_id)
		"rule":
			return _apply_rule(main, st, card, controller_id)
		"search":
			var zones: Array = []
			for z in st.zones:
				zones.append(Constants.Zone.CASTILLO if z == "castillo" else Constants.Zone.CEMENTERIO)
			var filter := _search_filter(st)
			if str(st.get("name", "")) == "@self":
				# "una copia de esta carta": mismo nombre que la carta del efecto.
				filter.erase("name_contains")
				filter["names_in"] = [str(card.card_data.get("nombre", "")).to_lower()] if card and card.get("card_data") != null else []
			var play: Dictionary = st.get("play", {})
			var dest: int = {"pagado": Constants.Zone.ORO_PAGADO, "cementerio": Constants.Zone.CEMENTERIO,
				"destierro": Constants.Zone.DESTIERRO}.get(st.get("dest", "mano"), Constants.Zone.MANO)
			var free_play: bool = play.get("free", false)
			var deliver_later: bool = st.has("dest_alts") or st.has("dist")
			if free_play or deliver_later:
				dest = -1  # se entrega desde los datos: jugarla sin pagar, elegir destino o repartir
			# "en el Castillo oponente" / "en un Castillo": busca en el Castillo de ese jugador y elige
			# quien controla el efecto; Destierro/Cementerio son los de su dueño.
			var owner: int = controller_id
			match str(st.get("owner", "")):
				"opponent":
					owner = 1 - controller_id
				"any":
					owner = 1 - controller_id if _is_bot(controller_id) else (controller_id if await SelectionManager.await_two_choice(
						main, _card_name(card), "Tu Castillo", "Castillo oponente", controller_id) else 1 - controller_id)
			var res: Dictionary = await ActionModule.search_zones(owner, zones, filter, st.amount, true, false,
				not play.is_empty() and not free_play, card, dest, st.get("distinct", false),
				controller_id if owner != controller_id else -1, int(play.get("reduce", 0)))
			var found_cards: Array = res.get("selected", [])
			_last_found = found_cards.duplicate()  # para "si buscaste un X, ..."
			if st.has("dist"):
				for mv in await _distribute(main, found_cards, st.dist, _card_name(card), controller_id):
					await _move_revealed(main, mv[0], str(mv[1]), controller_id)
			elif st.has("dest_alts"):
				var words := {"mano": "hand", "cementerio": "cemetery", "destierro": "exile", "jugar": "play_free", "pagado": "gold"}
				var labels := {"mano": "A tu mano", "cementerio": "A tu Cementerio", "destierro": "A tu Destierro",
					"jugar": "Jugarla sin pagar su coste", "pagado": "A tu Oro pagado"}
				for d in found_cards:
					var first: bool = true if _is_bot(controller_id) else await SelectionManager.await_two_choice(main,
						str(d.get("nombre", _card_name(card))), labels.get(st.dest_alts[0], ""), labels.get(st.dest_alts[1], ""), controller_id)
					await _move_revealed(main, d, words.get(st.dest_alts[0 if first else 1], "hand"), controller_id)
			elif free_play and main.get("_gold_manager"):
				for d in found_cards:
					await main._gold_manager.play_card_for_free(d, controller_id)
			return res.get("success", false) and not found_cards.is_empty()
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
					if not is_instance_valid(t):
						continue  # se fue con otra del grupo (un Arma con su portador)
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
	if str(st.get("name_not", "")) != "":
		filter["name_not"] = str(st.name_not)  # "un Aliado que no sea Ahab"
	if st.has("str_val"):
		if st.get("str_cmp", "") == "menos":
			filter["strength_max"] = int(st.str_val)
		elif st.get("str_cmp", "") == "mas":
			filter["strength_min"] = int(st.str_val)
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
		if st.get("no_block", false):
			ContinuousEffectManager.register_modifier({  # KeywordQuery.can_block()
				"source": t,
				"target": t,
				"type": ContinuousEffectManager.ModifierType.RESTRICTION,
				"restriction_type": "CANT_BLOCK",
				"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
				"description": "No puede bloquear este turno (%s)" % _card_name(card),
			})
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


func _cards_in_play_of(main: Node, pid: int) -> Array:
	"""Cartas en juego de 'pid' (Líneas, Armas portadas, Reserva, Oro Pagado); ver _controlled_in_play()."""
	return _controlled_in_play(main, pid)


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
		"self_strength":
			n = int(ContinuousEffectManager.get_modified_strength(card)) if is_instance_valid(card) else 0
		"own_paid_gold":
			var paid = PlayerSideScript.oro_pagado(main, controller_id)
			n = paid.get_children().filter(func(g): return is_instance_valid(g) and g.get("card_type") != null).size() if paid else 0
		"any_ally", "any_card_cost", "own_other_card_cost":
			var pool: Array = []
			for pid in ([controller_id] if st.src == "own_other_card_cost" else [0, 1]):
				pool.append_array(_cards_in_play_of(main, pid))
			if st.src == "any_ally":
				pool = pool.filter(func(x): return x.get("card_type") == Constants.CardType.ALIADO)
			elif st.src == "own_other_card_cost":
				pool = pool.filter(func(x): return x != card)
			if pool.is_empty():
				main._update_debug("%s: no hay una carta para contar" % _card_name(card))
				return false
			var measure := func(x: Node) -> int:
				return int(ContinuousEffectManager.get_modified_strength(x)) if st.src == "any_ally" else int(x.get("card_cost"))
			pool.sort_custom(func(a: Node, b: Node) -> bool: return measure.call(a) > measure.call(b))
			var pick: Node = pool[0]
			if not _is_bot(controller_id) and pool.size() > 1 and main.get("_card_interaction"):
				var chosen: Node = await main._card_interaction.await_target("%s: elige la carta (cuenta su %s)" % [_card_name(card),
					"Fuerza" if st.src == "any_ally" else "coste"], func(c: Node) -> bool: return c in pool, false, controller_id)
				if chosen and is_instance_valid(chosen):
					pick = chosen
			n = measure.call(pick)
		"own_allies_count":
			for cont in PlayerSideScript.ally_containers(main, controller_id):
				for a in cont.get_children():
					if is_instance_valid(a) and a.get("card_type") == Constants.CardType.ALIADO:
						n += 1
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
	var taken_names: Array = []  # por spec, para "de distinto nombre"
	for _sp in st.specs:
		taken_names.append([])
	while not deck.is_empty() and need.any(func(n): return n > 0):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var top_name: String = str(top.get("nombre", "")).to_lower()
		for i in range(st.specs.size()):
			if need[i] > 0 and _spec_matches(st.specs[i], top) \
					and not (st.specs[i].get("distinct", false) and top_name in taken_names[i]):
				need[i] -= 1
				taken.append(top)
				taken_names[i].append(top_name)
				break
	var title := _card_name(card)
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, title)
	var dest: String = str(st.get("dest", "play_free" if st.get("play_free", false) else "hand"))
	# Reparto ("pon uno en tu mano, tres en tu Cementerio"): quien controla el efecto elige cuáles van a
	# cada destino, en el orden del texto; lo que sobre se baraja.
	var moves: Array = []  # [[datos, destino]]
	if dest == "dist":
		moves = await _distribute(main, taken, st.get("dist", []), title, controller_id)
		var placed: Array = moves.map(func(mv): return mv[0])
		taken = taken.filter(func(d): return placed.has(d))  # lo que no tuvo destino vuelve al Castillo
	else:
		for d in taken:
			moves.append([d, dest])
	# Visor de mostrar para quien controla el efecto: solo las cartas que indica (RevealWindow).
	if not taken.is_empty():
		var reveal_window = load("res://scripts/ui/zones/RevealWindow.gd")
		if dest == "play_free" and taken.size() > 1:
			taken = await reveal_window.choose_order(main, controller_id, taken, title)
			moves = taken.map(func(d): return [d, dest])
		else:
			await reveal_window.show_cards(main, controller_id, taken, title,
				"Se reparten" if dest == "dist" else ("Van a %s" % REVEAL_DEST_LABELS.get(dest, "tu mano") if dest in ["hand", "cemetery", "exile", "gold"]
					else "Se juega sin pagar su coste"))
	for mv in moves:
		if mv[1] != "shuffle":
			revealed.erase(mv[0])
	for d in revealed:
		deck.append(d)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	var queue_before: int = _ts.trigger_queue.size() if _ts else 0
	var played := 0
	for mv in moves:
		if mv[1] in ["play_free", "put"]:
			played += 1
		await _move_revealed(main, mv[0].duplicate(), str(mv[1]), controller_id)
	if played > 1:
		await load("res://scripts/core/effects/mechanics/SearchPatterns.gd").reorder_new_triggers(queue_before, controller_id)
	return not need.any(func(n): return n > 0)


func _distribute(main: Node, cards: Array, dist: Array, title: String, controller_id: int) -> Array:
	"""Reparto "pon uno en tu mano, tres en tu Cementerio": quien controla el efecto elige cuáles van a cada
	destino, en el orden del texto (el bot, las primeras). Devuelve [[datos, destino]]; lo que no entra en
	ningún destino queda afuera (quien llama decide: barajarlo)."""
	var moves: Array = []
	var pool: Array = cards.duplicate()
	for item in dist:
		if pool.is_empty():
			break
		var n: int = mini(int(item.count), pool.size())
		var chosen: Array = pool.slice(0, n)
		if n < pool.size() and not _is_bot(controller_id):
			var entries: Array = pool.map(func(d): return {"data": d, "eligible": true})
			var raw: Array = await ActionModule.pick_in_zones(controller_id, "%s: elige %d para %s" % [title, n,
				REVEAL_DEST_LABELS.get(item.dest, "")], [{"is_own": true, "zone": Constants.Zone.CASTILLO, "cards": entries,
				"exclusive": true}], n, n)
			var picked: Array = []
			for r in raw:
				if r is Array and r.size() == 2 and int(r[1]) >= 0 and int(r[1]) < entries.size():
					picked.append(entries[int(r[1])].data)
			if picked.size() == n:
				chosen = picked
		for d in chosen:
			pool.erase(d)
			moves.append([d, str(item.dest)])
	return moves


const REVEAL_DEST_LABELS := {"hand": "tu mano", "cemetery": "tu Cementerio", "exile": "tu Destierro",
	"play_free": "jugar sin pagar su coste", "put": "poner en juego", "gold": "tu Oro pagado", "shuffle": "barajar en tu Castillo"}


func _move_revealed(main: Node, d: Dictionary, dest: String, controller_id: int) -> void:
	"""Lleva una carta mostrada (ya fuera del Castillo) a su destino. Un Oro nunca se juega: "ponlo en
	juego" lo pone en tu Reserva, "juégalo" lo deja en tu mano."""
	d["esta_oculta"] = false
	var is_gold: bool = int(d.get("tipo", -1)) == Constants.CardType.ORO
	var gm = main.get("_gold_manager")
	match dest:
		"cemetery":
			CardManager.add_to_cemetery(controller_id, d)
		"exile":
			CardManager.add_to_exile(controller_id, d)
		"gold":
			if is_gold and gm:
				await gm.put_gold_directly_in_pagado(controller_id, d)
			else:
				PlayerSideScript.put_in_hand(main, controller_id, d)
		"put":
			if is_gold and gm:
				await gm.put_gold_directly_in_reserva(controller_id, d)
			elif gm:
				await gm.play_card_for_free(d, controller_id)  # "ponlo en juego": entra sin pagar su coste
			else:
				PlayerSideScript.put_in_hand(main, controller_id, d)
		"play_free":
			if not is_gold and gm:
				await gm.play_card_for_free(d, controller_id)  # "y juégalo sin pagar su coste"
			else:
				PlayerSideScript.put_in_hand(main, controller_id, d)
		_:
			PlayerSideScript.put_in_hand(main, controller_id, d)


func _reveal_top(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Muestra N cartas del tope de tu Castillo, pon (hasta) K <tipo> de ahí en tu mano y baraja el resto'
	(o 'el resto en tu Destierro / mano', o 'juega un Aliado de ahí por un Oro menos'). Quien controla el
	efecto ve las N y elige; las que no se mueven vuelven barajadas."""
	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	for _i in range(int(st.count)):
		if deck.is_empty():
			break
		revealed.append(deck.pop_front())
	var title := _card_name(card)
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, title)
	var spec := {"types": st.get("pick_types", [])}
	var playing: bool = st.get("dest", "hand") == "play"
	var eligible: Array = []
	for i in range(revealed.size()):
		var d: Dictionary = revealed[i]
		if _spec_matches(spec, d) and not (playing and int(d.get("tipo", -1)) == Constants.CardType.ORO):
			eligible.append(i)
	var k: int = mini(int(st.get("pick", 1)), eligible.size())
	var chosen_idx: Array = eligible.slice(0, k)
	if not _is_bot(controller_id) and not revealed.is_empty():
		var entries: Array = []
		for i in range(revealed.size()):
			entries.append({"data": revealed[i], "eligible": i in eligible})
		var raw: Array = await ActionModule.pick_in_zones(controller_id, "%s: elige hasta %d" % [title, k] if st.get("up_to", false)
			else "%s: elige %d" % [title, k], [{"is_own": true, "zone": Constants.Zone.CASTILLO, "cards": entries, "exclusive": true}],
			0 if st.get("up_to", false) else k, k)
		chosen_idx = []
		for r in raw:
			if r is Array and r.size() == 2 and int(r[1]) in eligible and not chosen_idx.has(int(r[1])):
				chosen_idx.append(int(r[1]))
		if chosen_idx.size() < k and not st.get("up_to", false):
			for i in eligible:
				if chosen_idx.size() >= k:
					break
				if not chosen_idx.has(i):
					chosen_idx.append(i)
	var chosen: Array = chosen_idx.map(func(i): return revealed[i])
	var rest: Array = []
	for i in range(revealed.size()):
		if not chosen_idx.has(i):
			rest.append(revealed[i])
	var rest_dest: String = str(st.get("rest", "shuffle"))
	if rest_dest == "shuffle":
		for d in rest:
			deck.append(d)
		CardManager.shuffle_deck(controller_id)
		AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	for d in chosen:
		var data: Dictionary = d.duplicate()
		data["esta_oculta"] = false
		if not playing:
			PlayerSideScript.put_in_hand(main, controller_id, data)
			continue
		# "Juega un Aliado de ahí por un Oro menos": pasa por la mano con el descuento; si no se juega, queda ahí.
		var node: Node = PlayerSideScript.put_in_hand(main, controller_id, data)
		var reduce: int = int(st.get("reduce", 0))
		if node and reduce > 0:
			PaymentManager.agregar_modificador_coste(node, -reduce, func(c: Node) -> bool: return c == node, false)
		if node:
			await PlayerSideScript.play_from_hand(main, controller_id, node)
			if is_instance_valid(node) and reduce > 0:
				PaymentManager.remover_modificador_coste(node)
	if rest_dest != "shuffle":
		for d in rest:
			await _move_revealed(main, d.duplicate(), {"mano": "hand", "destierro": "exile", "cementerio": "cemetery"}.get(rest_dest, "hand"),
				controller_id)
	return not chosen.is_empty() or st.get("up_to", false)


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
	var name_not: String = str(spec.get("name_not", ""))
	if name_not != "" and name_not in ActionModule._strip_accents(str(data.get("nombre", "")).to_lower()):
		return false  # "dos Aliados Héroe que no sean Odiseo"
	var ability: String = str(data.get("habilidad", "")).strip_edges()
	match str(spec.get("ability", "")):
		"con":
			if ability.is_empty():
				return false
		"sin":
			if not ability.is_empty():
				return false
	var kw: String = str(spec.get("keyword", ""))
	if kw != "" and not KeywordParserScript.has_own(ability, KeywordParserScript.keyword_of(kw)):
		return false  # "un Aliado con Furia"
	var sval: int = int(spec.get("str_val", -1))
	if sval >= 0:
		if int(data.get("tipo", -1)) != Constants.CardType.ALIADO:
			return false
		var strength: int = int(data.get("fuerza", 0))
		match str(spec.get("str_cmp", "")):
			"menos":
				if strength > sval:
					return false
			"mas":
				if strength < sval:
					return false
			_:
				if strength != sval:
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


func _condition_holds(cond, card: Node, controller_id: int = -1) -> bool:
	if cond is Dictionary and cond.get("kind", "") == "controls":
		return _controls_holds(cond, card)
	if cond is Dictionary and cond.get("kind", "") == "searched":
		var word: String = str(cond.get("word", "")).substr(0, 5)
		return _last_found.any(func(d): return word in ActionModule._strip_accents(str(d.get("raza", "")).to_lower()) \
			or word in ActionModule._strip_accents(str(d.get("nombre", "")).to_lower()))
	match str(cond):
		"not_attacked_this_turn":
			return int(card.get_meta("declared_attacker_turn", -1)) != GameManager.turn_serial
		"opponent_turn", "own_turn":
			var mine: bool = GameManager.active_player_id == controller_id
			return mine == (str(cond) == "own_turn")
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
			if not str(cond.get("name", "")).is_empty():
				var c_name: String = EffectCompilerScript.normalize(str(c.card_data.get("nombre", ""))) if c.get("card_data") is Dictionary else ""
				if not (str(cond.name) in c_name):
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


func _hand_exile(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Cada jugador destierra N cartas de su mano': cada uno elige las suyas (el bot, las de menor coste)."""
	var all_ok := true
	var title := _card_name(card)
	for pid in [controller_id, 1 - controller_id]:
		var hand := _hand_cards(main, pid).filter(func(h): return h != card)
		var amount: int = mini(int(st.amount), hand.size())
		if amount < int(st.amount):
			all_ok = false
		if amount <= 0:
			continue
		var picked: Array = []
		if _is_bot(pid):
			hand.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
			picked = hand.slice(0, amount)
		elif main.get("_card_interaction"):
			# Elige el dueño de la mano (también el rival de quien controla el efecto), en el tablero.
			picked = await main._card_interaction.await_multi_target("%s: destierra %d carta(s) de tu mano" % [title, amount],
				hand, amount, Callable(), Callable(), false, null, pid)
		for node in picked:
			if not is_instance_valid(node):
				continue
			var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, node)
			if not data.is_empty():
				CardManager.add_to_exile(pid, data)
		if picked.size() < amount:
			all_ok = false
	return all_ok


func _apply_rule(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""Reglas con duración ("hasta tu próximo turno, ..."): se anotan en RuleState y las hace cumplir el
	punto del motor indicado en cada caso. 'Hasta tu próximo turno' = mientras no empiece el próximo turno
	de quien controla el efecto (RuleState.next_own_turn())."""
	var me := controller_id
	var opp := 1 - controller_id
	var until: int = RuleState.next_own_turn(me)
	var name := _card_name(card)
	var note := ""
	match str(st.kind):
		"ally_affect_tax":  # ProtectionRules.affect_tax (como manuel rodriguez)
			load("res://scripts/core/effects/mechanics/ProtectionRules.gd").grant_ally_affect_tax(me, until - 1)
			note = "afectar a tus Aliados cuesta un Oro adicional"
		"trigger_gold_toll":  # TriggerTollPatterns.blocks_trigger
			RuleState.set_until("trigger_gold_toll", opp, until)
			note = "tu oponente paga un Oro para usar habilidades disparadas"
		"open_hands":  # HandReveal / ActionModule.discard
			for p in [0, 1]:
				RuleState.set_until("hand_revealed", p, until)
				RuleState.set_until("no_effect_discard", p, until)
			load("res://scripts/core/effects/mechanics/HandReveal.gd").refresh()
			note = "manos descubiertas y sin descartes por efectos"
		"search_toll":  # LimitedEventTriggers (castle_searched)
			RuleState.set_until("search_toll", me, until)
			note = "al buscar en el Castillo oponente, tu oponente Destierra la carta del tope"
		"talisman_to_exile":  # CardManager._append_to_cemetery
			for p in [0, 1]:
				RuleState.set_until("talisman_to_exile", p, until)
			note = "los Talismanes van al Destierro en vez del Cementerio"
		"attack_cap_2":  # GameManager.attack_cap
			for p in [0, 1]:
				RuleState.set_until("attack_cap_2", p, until)
			note = "solo se puede atacar con hasta dos Aliados por turno"
		"two_per_type":  # GoldManagerBase._card_play_locked
			for p in [0, 1]:
				RuleState.set_until("two_per_type", p, until)
			note = "no más de dos cartas de cada tipo por turno"
		"shuffle_banish_tax":  # ProtectionRules.affect_tax (verbo Barajar/Desterrar)
			RuleState.set_until("shuffle_banish_tax", me, until)
			note = "Barajar o Desterrar tus cartas en juego le cuesta un Oro adicional a tu oponente"
		"no_hand_limit":  # PhaseFlowController._enforce_hand_limit
			RuleState.set_until("no_hand_limit", me, until)
			note = "sin límite de cartas en tu mano"
		"opp_immune_turn":  # EffectController (opp_effect_immune)
			RuleState.set_until("opp_effect_immune", me, GameManager.turn_serial + 1)
			note = "no puedes ser afectado por efectos oponentes este turno"
		"zombie":  # LimitedEventTriggers (damage)
			RuleState.set_until("zombie", me, until)
			note = "cada vez que recibas daño oponente, tu oponente Bota esa cantidad y pones en juego un Aliado de un Cementerio"
		"allies_no_leave":  # EffectController._try_consume_leave_play_prevention / StackAnnul.apply
			RuleState.set_until("allies_no_leave", me, until)
			RuleState.set_until("ally_annul_tax", me, until)
			note = "tus Aliados no pueden salir del juego y Anularlos cuesta un Oro adicional"
		"final_silence_allies":
			EffectController.schedule_next_final_phase_effect(me, func() -> void:
				for container in PlayerSideScript.ally_containers(main, me):
					for c in container.get_children():
						if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO:
							await KeywordManager.silence_card(c, null, "until_next_turn")
				main._update_debug("%s: tus Aliados pierden su habilidad hasta tu próximo turno" % name))
			note = "en tu Fase Final, tus Aliados pierden su habilidad hasta tu próximo turno"
		"castle_lock":  # ProtectionRules.mill_blocked / castle_banish_blocked, ActionModule.discard
			for p in [0, 1]:
				for key in ["no_effect_mill", "no_castle_exile", "no_effect_discard"]:
					RuleState.set_until(key, p, until)
			note = "no se puede Botar, Desterrar de los Castillos ni Descartar por efectos"
		"cemetery_shuffle_cap":  # TurnLimits.cemetery_shuffle_room
			for p in [0, 1]:
				RuleState.set_until("cemetery_shuffle_cap_3", p, 1 << 30)
			note = "por el resto del juego, hasta tres cartas de los Cementerios barajadas por turno"
		"cemetery_exile_lock":  # ActionSearch (Cementerio -> Destierro)
			RuleState.set_until("cemetery_exile_lock", me, 1 << 30)
			note = "por el resto del juego, tu oponente no puede Desterrar cartas de tu Cementerio que no sean Talismán"
		_:
			push_warning("[EffectInterpreter] Regla desconocida: %s" % st.kind)
			return false
	main._update_debug("%s: %s" % [name, note])
	return true


func _keep_shuffle(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Cada jugador elige (hasta) N Aliados que controle y baraja el resto': cada uno elige los que se
	quedan (el bot, los de mayor coste); el resto de ese tipo se baraja con el verbo normal.
	per_cost: "un Aliado de cada coste" (visión de noé). exclude_gold / silence_first: "las demás cartas que
	no sean Oro pierden su habilidad y son Barajadas" (armagedon). Anota en _each.moved cuántas se fueron."""
	var want: int = _type_enum(st.card_type) if not str(st.card_type).is_empty() else -1
	var title := _card_name(card)
	var to_shuffle: Array = []
	var by_pid := {}
	for pid in [controller_id, 1 - controller_id]:
		var mine: Array = _controlled_in_play(main, pid).filter(func(c): return ((want < 0 or c.get("card_type") == want)
			and not (st.get("exclude_gold", false) and c.get("card_type") == Constants.CardType.ORO)))
		by_pid[pid] = []
		if st.get("per_cost", false):
			by_pid[pid] = await _keep_one_per_cost(main, mine, title, pid)
			to_shuffle.append_array(by_pid[pid])
			continue
		if mine.is_empty() or (mine.size() <= int(st.amount) and not st.up_to):
			continue
		var kept: Array = []
		if _is_bot(pid):
			mine.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) > int(b.card_cost))
			kept = mine.slice(0, mini(int(st.amount), mine.size()))
		elif main.get("_card_interaction"):
			# Elegir cuáles se quedan no es afectarlas: sin el filtro de Oro adicional.
			kept = await main._card_interaction._await_multi_target_raw("%s: elige %s%d que se quedan; el resto se baraja"
				% [title, "hasta " if st.up_to else "", int(st.amount)], mine, int(st.amount), Callable(), Callable(),
				st.up_to, null, pid)
		for c in mine:
			if not (c in kept):
				to_shuffle.append(c)
				by_pid[pid].append(c)
	to_shuffle = to_shuffle.filter(func(c): return is_instance_valid(c))
	_each = {"moved": {controller_id: 0, 1 - controller_id: 0}}
	if to_shuffle.is_empty():
		return true
	# La carta del efecto pudo salir del juego mientras se elegía (si era uno de los barajados).
	var ok: bool = await _apply_verb({"verb": "shuffle", "count": to_shuffle.size(), "up_to": true,
		"silence_first": st.get("silence_first", false)}, to_shuffle, card if is_instance_valid(card) else null)
	for pid in by_pid:
		_each.moved[pid] = by_pid[pid].filter(func(c): return not is_instance_valid(c) or not c.is_in_play()).size()
	return ok


func _keep_one_per_cost(main: Node, mine: Array, title: String, pid: int) -> Array:
	"""Visión de Noé: 'pid' se queda con una carta de cada coste (el bot, la de más Fuerza); devuelve las demás."""
	var groups := {}
	for c in mine:
		var cost: int = int(c.card_cost) if c.get("card_cost") != null else 0
		if not groups.has(cost):
			groups[cost] = []
		groups[cost].append(c)
	var rest: Array = []
	for cost in groups:
		var group: Array = groups[cost]
		if group.size() <= 1:
			continue
		group.sort_custom(func(a: Node, b: Node) -> bool:
			return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
		var kept: Node = group[0]
		if not _is_bot(pid) and main.get("_card_interaction"):
			var picked: Array = await main._card_interaction._await_multi_target_raw("%s: elige el de coste %d que se queda" % [title, cost],
				group, 1, Callable(), Callable(), false, null, pid)
			if not picked.is_empty() and is_instance_valid(picked[0]):
				kept = picked[0]
		for c in group:
			if c != kept:
				rest.append(c)
	return rest


func _discard(main: Node, st: Dictionary, controller_id: int) -> bool:
	if st.who == "both":
		var mine: bool = await _discard(main, st.merged({"who": "self"}, true), controller_id)
		var theirs: bool = await _discard(main, st.merged({"who": "opponent"}, true), controller_id)
		return mine and theirs
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
