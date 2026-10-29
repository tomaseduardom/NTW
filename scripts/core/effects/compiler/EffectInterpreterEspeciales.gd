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
		"stat":
			if str(q.get("of", "")) == "ese aliado":  # golpe eléctrico: el que se eligió antes ("Elige un Aliado que controles")
				var chosen = _each.get("chosen_card")
				if chosen == null or not is_instance_valid(chosen):
					return 0
				return int(ContinuousEffectManager.get_modified_cost(chosen)) if q.stat == "coste" else int(ContinuousEffectManager.get_modified_strength(chosen))
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
		"choose_card":  # "Elige un Aliado que controles" (el bot, el de mayor coste)
			var own: Array = _controlled_in_play(main, me).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
			if own.is_empty():
				return false
			own.sort_custom(func(a: Node, b: Node) -> bool: return int(ContinuousEffectManager.get_modified_cost(a)) > int(ContinuousEffectManager.get_modified_cost(b)))
			var chosen: Node = own[0]
			if not _is_bot(me) and own.size() > 1 and main.get("_card_interaction"):
				var picked: Node = await main._card_interaction.await_target("%s: elige un Aliado que controles" % title,
					func(c: Node) -> bool: return c in own, false, me)
				if picked and is_instance_valid(picked):
					chosen = picked
			_each["chosen_card"] = chosen
			return true
		"choose_type":
			_each["chosen_type"] = await _choose_type(main, st, title, me)
			return true
		"silence_chosen_type":  # sibila saint germain
			var stype: int = int(_each.get("chosen_type", -1))
			if stype < 0:
				return false
			if await EffectContextScript.ensure_window():
				return false
			for pid in [0, 1]:
				for c in _controlled_in_play(main, pid):
					if int(c.get("card_type")) == stype:
						await KeywordManager.silence_card(c, card, "until_next_turn")
			return true
		"shuffle_exiles_chosen_type":  # convocar el caos: del Destierro de cada uno a su Castillo
			var etype: int = int(_each.get("chosen_type", -1))
			if etype < 0:
				return false
			if await EffectContextScript.ensure_window():
				return false
			for pid in [0, 1]:
				var exile: Array = CardManager.get_exile(pid)
				var moving: Array = exile.filter(func(d): return int(d.get("tipo", -1)) == etype)
				for d in moving:
					exile.erase(d)
					d["esta_oculta"] = true
					CardManager.add_to_deck_top(pid, d)
				if not moving.is_empty():
					CardManager.shuffle_deck(pid)
					AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % title)
			if main.get("_zone_manager"):
				main._zone_manager._update_castillo_counts()
			return true
		"draw_if_chosen":  # "Si elegiste Aliados, Roba cuatro cartas, sino Roba dos cartas"
			var n: int = int(st.yes) if int(_each.get("chosen_type", -1)) == Constants.CardType.ALIADO else int(st.no)
			await ActionModule.draw(me, n, "efecto_compilado", true)
			return true
		"envy":
			return await _envy(main, card, me)
		"envy_else":  # "De lo contrario, tú Robas dos cartas"
			if not _each.get("envy_won", false):
				await ActionModule.draw(me, int(st.get("amount", 2)), "efecto_compilado", true)
			return true
		"type_silence_shuffle":  # y vivieron felices
			var ttype: int = await _choose_type(main, st.merged({"exclude_gold": true, "bot": "play_diff"}), title, me)
			var hit: Array = []
			for pid in [0, 1]:
				hit.append_array(_controlled_in_play(main, pid).filter(func(c): return int(c.get("card_type")) == ttype))
			if hit.is_empty():
				return true
			return await _apply_verb({"verb": "shuffle", "count": hit.size(), "up_to": true, "silence_first": true}, hit, card)
		"disguise":
			return await _disguise(main, st, card, me)
		"look_both_choose":  # regresa la razón: "Elige un Aliado" (cuenta su Fuerza impresa)
			var all: Array = []
			for pid in [0, 1]:
				all.append_array(_controlled_in_play(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO))
			if all.is_empty():
				return false
			all.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_data.get("fuerza", 0)) > int(b.card_data.get("fuerza", 0)))
			var ally: Node = all[0]
			if not _is_bot(me) and all.size() > 1 and main.get("_card_interaction"):
				var p2: Node = await main._card_interaction.await_target("%s: elige un Aliado (cuenta su Fuerza impresa)" % title,
					func(c: Node) -> bool: return c in all, false, me)
				if p2 and is_instance_valid(p2):
					ally = p2
			_each["look_n"] = int(ally.card_data.get("fuerza", 0))
			return true
		"look_both_place":
			return await _look_both_place(main, card, me)
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


const TYPE_CHOICES := [["Aliado", Constants.CardType.ALIADO], ["Arma", Constants.CardType.ARMA], ["Tótem", Constants.CardType.TOTEM],
	["Talismán", Constants.CardType.TALISMAN], ["Oro", Constants.CardType.ORO]]


func _choose_type(main: Node, st: Dictionary, title: String, me: int) -> int:
	"""'Elige un tipo de carta' (sin Oro si exclude_gold). El bot elige según st.bot: "play_diff" (más cartas rivales
	que propias en juego), "own_exile" (más cartas propias en el Destierro) o "hand_diff" (más en la mano rival que en
	la propia)."""
	var choices: Array = TYPE_CHOICES.filter(func(c): return not (st.get("exclude_gold", false) and c[1] == Constants.CardType.ORO))
	if not _is_bot(me):
		var idx: int = await SelectionManager.await_choice(main, "%s: elige un tipo de carta" % title, choices.map(func(c): return c[0]), me)
		return int(choices[clampi(idx, 0, choices.size() - 1)][1])
	var mode: String = str(st.get("bot", "play_diff"))
	var best: int = int(choices[0][1])
	var best_score: int = -1000000
	for c in choices:
		var ctype: int = int(c[1])
		var s: int = 0
		match mode:
			"own_exile":
				s = CardManager.get_exile(me).filter(func(d): return int(d.get("tipo", -1)) == ctype).size()
			"hand_diff":
				s = _hand_cards(main, 1 - me).filter(func(h): return int(h.get("card_type")) == ctype).size() \
					- _hand_cards(main, me).filter(func(h): return int(h.get("card_type")) == ctype).size()
			_:
				s = _controlled_in_play(main, 1 - me).filter(func(x): return int(x.get("card_type")) == ctype).size() \
					- _controlled_in_play(main, me).filter(func(x): return int(x.get("card_type")) == ctype).size()
		if s > best_score:
			best_score = s
			best = ctype
	return best


func _envy(main: Node, card: Node, me: int) -> bool:
	"""envidia mortal: cada jugador muestra su mano; si tu oponente tiene más cartas del tipo elegido, buscas una carta
	en tu Castillo y él Destierra una de ese tipo de su mano (la elige él). Si no, la oración siguiente (envy_else)
	te hace Robar."""
	var opp := 1 - me
	var title := _card_name(card)
	var ctype: int = int(_each.get("chosen_type", -1))
	_each["envy_won"] = false
	if ctype < 0:
		return false
	for pid in [me, opp]:
		var shown: Array = _hand_cards(main, pid).map(func(c): return c.card_data)
		if not shown.is_empty() and not _is_bot(1 - pid):
			SelectionManager.open_reveal(shown, "%s: la mano de tu oponente" % title, 1 - pid)
	var mine: int = _hand_cards(main, me).filter(func(c): return int(c.get("card_type")) == ctype).size()
	var theirs: int = _hand_cards(main, opp).filter(func(c): return int(c.get("card_type")) == ctype).size()
	if theirs <= mine:
		return true
	_each["envy_won"] = true
	await ActionModule.search(me, Constants.Zone.CASTILLO, {}, 1, true, false, false, card)
	var victim: Node = await PlayerSideScript.pick_from_hand(main, opp, "%s: Destierra una carta de ese tipo de tu mano" % title,
		func(c: Node) -> bool: return int(c.get("card_type")) == ctype, false)
	if victim and is_instance_valid(victim):
		CardManager.add_to_exile(opp, PlayerSideScript.take_from_hand(main, opp, victim))
	return true


func _deck_copies(pid: int, nm: String) -> Array:
	return CardManager.get_deck(pid).filter(func(d): return str(d.get("nombre", "")).to_lower() == nm)


func _disguise(main: Node, st: Dictionary, card: Node, me: int) -> bool:
	"""descubrir disfraz: elige un Aliado en juego y busca en un Castillo una copia (mismo nombre); se juega bajo tu
	control pagando su coste con N Oros menos (hasta 0) y no puede ser Anulado. Sigue siendo del dueño del Castillo.
	Si no se puede pagar, vuelve barajada a su Castillo."""
	var title := _card_name(card)
	var allies: Array = []
	for pid in [0, 1]:
		allies.append_array(_controlled_in_play(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO))
	if allies.is_empty():
		return false
	var model: Node = null
	var from := -1
	if _is_bot(me):
		for a in allies:
			for pid in [1 - me, me]:
				if from < 0 and not _deck_copies(pid, str(a.get("card_name")).to_lower()).is_empty():
					model = a
					from = pid
		if model == null:
			return false
	else:
		model = allies[0]
		if allies.size() > 1 and main.get("_card_interaction"):
			model = await main._card_interaction.await_target("%s: elige un Aliado (se busca una copia)" % title,
				func(c: Node) -> bool: return c in allies, false, me)
		if model == null or not is_instance_valid(model):
			return false
		from = me if await SelectionManager.await_two_choice(main, title, "Buscar en tu Castillo", "Buscar en el Castillo oponente", me) else 1 - me
	if EffectController.fision_hides_zones_of(from, me, Constants.Zone.CASTILLO) or await EffectController.offer_colapso_global(me):
		return false
	var found: Array = _deck_copies(from, str(model.get("card_name")).to_lower())
	if found.is_empty():
		main._update_debug("%s: no hay una copia de %s en ese Castillo" % [title, str(model.get("card_name"))])
		CardManager.shuffle_deck(from)
		return false
	if await EffectContextScript.ensure_window():
		return false
	var data: Dictionary = found[0]
	CardManager.get_deck(from).erase(data)
	CardManager.shuffle_deck(from)
	data = data.duplicate()
	data["esta_oculta"] = false
	var node: Node = PlayerSideScript.put_in_hand(main, me, data)
	if node == null:
		return false
	node.owner_id = from
	node.set_meta("protected_from_annul_this_turn", true)  # "no puede ser Anulado"
	PaymentManager.agregar_modificador_coste(node, -int(st.get("amount", 2)), func(c: Node) -> bool: return c == node, true)
	if PaymentManager.puede_jugar_carta(node, me):
		await PlayerSideScript.play_from_hand(main, me, node)
	if is_instance_valid(node):
		PaymentManager.remover_modificador_coste(node)
		if node.get("current_zone") == Constants.Zone.MANO:
			# No se pudo jugar: vuelve barajada al Castillo de su dueño.
			var back: Dictionary = PlayerSideScript.take_from_hand(main, me, node)
			back["esta_oculta"] = true
			CardManager.add_to_deck_top(from, back)
			CardManager.shuffle_deck(from)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func _look_both_place(main: Node, card: Node, me: int) -> bool:
	"""regresa la razón: mira N cartas del tope de cada Castillo (N = la Fuerza impresa del Aliado elegido). Pones las
	tuyas en tu mano o las del oponente en su Cementerio; el resto se ordena (CastleLook). El bot: las suyas a la mano."""
	var n: int = int(_each.get("look_n", 0))
	if n <= 0:
		return true
	var title := _card_name(card)
	var mine_to_hand := true
	if not _is_bot(me):
		mine_to_hand = await SelectionManager.await_two_choice(main, title, "Tus cartas a tu mano", "Las oponentes a su Cementerio", me)
	var look_script = load("res://scripts/core/effects/CastleLook.gd")
	if mine_to_hand:
		await look_script.look(me, me, n, true, [{"key": "hand", "label": "A tu mano", "dest": "hand", "start": true, "min": n, "max": n}],
			"%s: tus cartas a tu mano" % title)
		await look_script.look(me, 1 - me, n, true, look_script.rest_box(true), "%s: ordena las del Castillo oponente" % title)
	else:
		await look_script.look(me, 1 - me, n, true, [{"key": "cemetery", "label": "A su Cementerio", "dest": "cemetery", "start": true,
			"min": n, "max": n}], "%s: al Cementerio oponente" % title)
		await look_script.look(me, me, n, true, look_script.rest_box(true), "%s: ordena las de tu Castillo" % title)
	return true
