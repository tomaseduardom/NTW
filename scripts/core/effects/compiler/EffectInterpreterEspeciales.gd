extends "res://scripts/core/effects/compiler/EffectInterpreterOponente.gd"
## EffectInterpreterEspeciales — familia de piezas sueltas de EffectInterpreter.gd (ver EffectInterpreterBase.gd):
## átomos special:* de una o pocas cartas, el paso "repeat" ("Por cada X, <pasos que no admiten cantidad>") y
## las cantidades que leen lo que hicieron los pasos anteriores (_each).

const EnterPatternsScript = preload("res://scripts/core/effects/mechanics/EnterPatterns.gd")


func _execute_step(main: Node, st: Dictionary, targets: Array, card: Node, controller_id: int) -> bool:
	if st.op == "special":
		return await _special_step(main, st, card, controller_id)
	if st.op == "repeat":
		# "Por cada Talismán Botado de esta forma, busca... o paga un Oro oponente" (forma de araña): la elección se
		# hace en cada vuelta.
		var times: int = await _quantity_value(main, st.q, card, controller_id)
		print("[EffectInterpreter] %s: se repite %d vez/veces" % [_card_name(card), times])
		for _i in range(times):
			var round_steps: Array = await _resolve_choices(main, st.steps, card, controller_id)
			await _execute_steps(main, round_steps, {}, card, controller_id)
		return true
	return await super(main, st, targets, card, controller_id)


func _quantity_value(main: Node, q: Dictionary, card: Node, controller_id: int) -> int:
	match str(q.get("kind", "")):
		"sum":  # "por cada A y por cada B" (orco alpino, luis carrera)
			var total := 0
			for part in q.parts:
				total += await _quantity_value(main, part, card, controller_id)
			return total
		"each_list":  # "por cada Aliado Desterrado / Talismán Botado de esta forma"
			var types: Array = q.get("types", [])
			return _each.get(str(q.key), []).filter(func(d): return d is Dictionary and _spec_matches({"types": types}, d)).size()
		"each_count":  # "por cada carta Destruida"
			return int(_each.get(str(q.key), 0))
		"paid_self":  # nguruvilu: "por cada Oro que hayas pagado por este Aliado" (GoldManager, meta "gold_paid")
			return int(card.get_meta("gold_paid", 0)) if is_instance_valid(card) else 0
		"totem_left":  # vâlve albe: "por cada Tótem que haya salido de tu Línea de Apoyo este turno, máximo dos"
			var left: int = RuleState.count("totem_left_support", controller_id)
			return mini(left, int(q.max)) if int(q.get("max", -1)) >= 0 else left
		"named_count":  # luis carrera: "una adicional por cada Carrera que controles"
			var word: String = str(q.name)
			return _controlled_in_play(main, controller_id).filter(func(c): return (c.get("card_data") is Dictionary
				and word in EffectCompilerScript.normalize(str(c.card_data.get("nombre", ""))))).size()
	return await super(main, q, card, controller_id)


func _special_step(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	var me := controller_id
	var title := _card_name(card)
	match str(st.kind):
		"castle_top_ally":
			return await _castle_top_allies(main, st, card, me)
		"draw_per_destroyed_ctrl":  # chivateo del mandinga: "su controlador Roba una carta" por cada uno
			var by_ctrl: Dictionary = _each.get("destroyed_allies_by_ctrl", {})
			for pid in by_ctrl:
				if int(by_ctrl[pid]) > 0:
					await ActionModule.draw(int(pid), int(by_ctrl[pid]), "efecto_compilado", true)
			return true
		"next_ally_discount_furia":
			# forma de araña: como corrupción del alma (el descuento) + RuleState "next_ally_furia"
			# (GoldManager._register_card_played).
			var serial: int = GameManager.turn_serial
			PaymentManager.agregar_modificador_coste(card, -1, func(c: Node) -> bool:
				return c.get("card_type") == Constants.CardType.ALIADO and c.get("owner_id") != null and int(c.owner_id) == me \
					and int(TurnManager.ally_played_serial.get(me, -1)) != serial, false)
			RuleState.set_pending("next_ally_furia", me, serial)
			main._update_debug("%s: el próximo Aliado que juegues este turno cuesta un Oro menos y gana Furia" % title)
			return true
		"name_lock_attack":
			return await _name_lock_attack(main, card, me)
		"drain_distribute":
			return await _drain_distribute(main, card, me)
		"grant_quoted":
			var m := RegEx.create_from_string("[\"“”¨]([^\"“”¨]+)[\"“”¨]").search(str(card.get("card_ability")) if is_instance_valid(card) else "")
			if m == null:
				return false
			return await _grant_text(main, st, card, me, m.get_string(1).strip_edges())
		"grant_affected":  # efigie: la habilidad del Aliado que afectó el paso anterior
			var affected: Array = _each.get("affected", [])
			var text: String = str(affected[0].habilidad).strip_edges() if not affected.is_empty() else ""
			if text.is_empty():
				main._update_debug("%s: no hay una habilidad que ganar" % title)
				return false
			return await _grant_text(main, st, card, me, text)
		"shuffle_weaker":  # soberbia: "Barajar todos los Aliados de menor Fuerza que este Aliado"
			if not _alive(card):
				return false
			var mine: int = ContinuousEffectManager.get_modified_strength(card)
			var weaker: Array = []
			for pid in [0, 1]:
				weaker.append_array(_controlled_in_play(main, pid).filter(func(c): return (c != card
					and c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.get_modified_strength(c) < mine)))
			if weaker.is_empty():
				return true
			return await _apply_verb({"verb": "shuffle", "count": weaker.size(), "up_to": true}, weaker, card)
	push_warning("[EffectInterpreter] pieza especial desconocida: %s" % st.kind)
	return false


func _castle_top_allies(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""estirpe maldita: 'pon una carta del tope de un Castillo en juego como un Aliado de Fuerza 2 sin habilidad' (la
	cantidad la multiplica "Por cada Aliado que controles"). Cada vez se elige el Castillo (el bot, el oponente);
	queda bajo tu control y sigue siendo del dueño del Castillo."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var strength: int = int(st.get("v", "2"))
	var placed := 0
	for _i in range(int(st.get("amount", 1))):
		var from: int = 1 - me
		if _is_bot(me):
			if CardManager.get_deck(from).is_empty():
				from = me
		elif not await SelectionManager.await_two_choice(main, "%s: ¿de qué Castillo? (%d de %d)" % [_card_name(card), _i + 1, int(st.amount)],
				"Castillo oponente", "Tu Castillo", me):
			from = me
		var deck: Array = CardManager.get_deck(from)
		if deck.is_empty():
			continue
		if await EffectContextScript.ensure_window():
			return false
		var data: Dictionary = (deck.pop_front() as Dictionary).duplicate()
		data["tipo"] = Constants.CardType.ALIADO
		data["fuerza"] = strength
		data["habilidad"] = ""
		data["esta_oculta"] = false
		var node: Node = main._create_card(data, false)
		node.owner_id = from
		node.controller_id = me
		main._connect_card_signals(node)
		await gm._play_card_to_field(node)
		placed += 1
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return placed >= int(st.get("amount", 1))


func _name_lock_attack(main: Node, card: Node, me: int) -> bool:
	"""mug ruith: 'un Aliado y todas sus copias no pueden atacar ni tu oponente puede utilizar sus habilidades hasta tu
	próximo turno' — como Apofis del Caos: restricción CANT_ATTACK en las copias en juego y candado por nombre
	(KeywordManager.lock_name_until_next_turn) sobre las del oponente. El bot elige el Aliado oponente más fuerte."""
	var allies: Array = []
	for pid in [0, 1]:
		allies.append_array(_controlled_in_play(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO))
	if allies.is_empty():
		return false
	var rivals: Array = allies.filter(func(c): return _controller_of(c) != me)
	var pick: Node = null
	if _is_bot(me):
		var pool: Array = rivals if not rivals.is_empty() else allies
		pool.sort_custom(func(a: Node, b: Node) -> bool: return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
		pick = pool[0]
	elif main.get("_card_interaction"):
		pick = await main._card_interaction.await_target("%s: un Aliado (y sus copias) no puede atacar hasta tu próximo turno" % _card_name(card),
			func(c: Node) -> bool: return c in allies, false, me)
	if pick == null or not is_instance_valid(pick):
		return false
	if await EffectContextScript.ensure_window():
		return false
	var name: String = str(pick.get("card_name"))
	var turns: int = 2 if GameManager.active_player_id == me else 1  # este fin de turno y el del rival
	for pid in [0, 1]:
		for c in _controlled_in_play(main, pid):
			if str(c.get("card_name")) == name:
				ContinuousEffectManager.register_modifier({"source": c, "target": c, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
					"restriction_type": "CANT_ATTACK", "duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": turns,
					"description": "%s: no puede atacar" % _card_name(card)})
	KeywordManager.lock_name_until_next_turn(name, 1 - me)
	main._update_debug("%s: %s y sus copias no pueden atacar ni tu oponente puede usar sus habilidades hasta tu próximo turno" % [_card_name(card), name])
	return true


func _drain_distribute(main: Node, card: Node, me: int) -> bool:
	"""murciélago: 'un Aliado oponente pierde tanta Fuerza como Aliados controles y distribuye esa misma cantidad de
	Fuerza entre tus Aliados permanentemente' — quien controla el efecto reparte de a 1 (el bot, en ronda)."""
	var title := _card_name(card)
	var rivals: Array = _controlled_in_play(main, 1 - me).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var mine: Array = _controlled_in_play(main, me).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var n: int = mine.size()
	if rivals.is_empty() or n <= 0:
		return false
	var target: Node = rivals[0]
	if _is_bot(me):
		rivals.sort_custom(func(a: Node, b: Node) -> bool: return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
		target = rivals[0]
	elif rivals.size() > 1 and main.get("_card_interaction"):
		var picked: Node = await main._card_interaction.await_target("%s: un Aliado oponente pierde %d de Fuerza" % [title, n],
			func(c: Node) -> bool: return c in rivals, false, me)
		if picked and is_instance_valid(picked):
			target = picked
	if await EffectContextScript.ensure_window():
		return false
	await _buff({"amount": -n, "count": 1, "permanent": true}, [target], card)
	var gains := {}
	for i in range(n):
		var to: Node = mine[i % mine.size()]
		if not _is_bot(me) and mine.size() > 1 and main.get("_card_interaction"):
			var chosen: Node = await main._card_interaction.await_target("%s: elige el Aliado que gana 1 de Fuerza (%d de %d)" % [title, i + 1, n],
				func(c: Node) -> bool: return c in mine, false, me)
			if chosen and is_instance_valid(chosen):
				to = chosen
		gains[to] = int(gains.get(to, 0)) + 1
	for ally in gains:
		if is_instance_valid(ally):
			await _buff({"amount": int(gains[ally]), "count": 1, "permanent": true}, [ally], card)
	return true


func _grant_text(main: Node, st: Dictionary, card: Node, me: int, text: String) -> bool:
	"""Un Aliado (de coste N o más, que controles) gana la habilidad 'text', sumada a la suya (como A Través del
	Espejo, EnterPatterns.set_ability). Elige quien controla el efecto (el bot, su Aliado más fuerte)."""
	var pool: Array = []
	for pid in ([me] if st.has("own") else [0, 1]):
		pool.append_array(_controlled_in_play(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO))
	if st.has("cv"):
		var cv: int = int(st.cv)
		var at_least: bool = str(st.get("cc", "mas")) == "mas"
		pool = pool.filter(func(c): return ((int(ContinuousEffectManager.get_modified_cost(c)) >= cv) == at_least
			or int(ContinuousEffectManager.get_modified_cost(c)) == cv))
	if pool.is_empty():
		main._update_debug("%s: no hay un Aliado que pueda ganar la habilidad" % _card_name(card))
		return false
	var target: Node = pool[0]
	if _is_bot(me):
		var own: Array = pool.filter(func(c): return _controller_of(c) == me)
		var choice: Array = own if not own.is_empty() else pool
		choice.sort_custom(func(a: Node, b: Node) -> bool: return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
		target = choice[0]
	elif pool.size() > 1 and main.get("_card_interaction"):
		var picked: Node = await main._card_interaction.await_target("%s: elige el Aliado que gana la habilidad" % _card_name(card),
			func(c: Node) -> bool: return c in pool, false, me)
		if picked and is_instance_valid(picked):
			target = picked
	if await EffectContextScript.ensure_window():
		return false
	var base: String = str(target.get("card_ability")).strip_edges()
	EnterPatternsScript.set_ability(target, (base + "\n" if not base.is_empty() else "") + text)
	main._update_debug("%s: %s gana la habilidad \"%s\"" % [_card_name(card), str(target.get("card_name")), text])
	return true
