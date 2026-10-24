extends "res://scripts/core/effects/mechanics/EnterPatternsLote3.gd"
## EnterPatterns — familia InmunidadOros (ver EnterPatternsBase.gd para la cabecera, constantes y ayudas).


# =============================================================================
# INMUNIDAD A EFECTOS OPONENTES (EffectController.opp_immune_card / player_opp_immune)
# =============================================================================


static func _peter_pan(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	RuleState.set_until("opp_effect_immune", pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: no puedes ser afectado por efectos oponentes hasta tu próximo turno" % _name(card))
	var n := 2
	if not PlayerSideScript.is_bot(pid):
		n = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta dos cartas" % _name(card), ["Robar 0", "Robar 1", "Robar 2"], pid), 0)
	if n > 0:
		await ActionModule.draw(pid, n, _name(card), true)


## Juega una carta de tu mano o Cementerio pagando su coste menos 'discount' (mínimo 'floor'). Los Oros no
## se juegan. Devuelve true si se jugó.
static func _play_from_hand_or_cemetery(main: Node, card: Node, pid: int, discount: int, floor_cost: int, filter: Callable = Callable()) -> bool:
	if not main._gold_manager:
		return false
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - discount, floor_cost)
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) != Constants.CardType.ORO and (not filter.is_valid() or filter.call(d)) 		and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)
	var hand_nodes: Array = _hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return false
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: puedes jugar una carta de tu mano o Cementerio" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return false
	var data: Dictionary = {}
	var hand_node: Node = null
	if int(raw[0][0]) == -1:
		if int(raw[0][1]) < 0 or int(raw[0][1]) >= hand_nodes.size():
			return false
		hand_node = hand_nodes[int(raw[0][1])]
		data = hand_node.card_data
	else:
		var ci := int(raw[0][1])
		if ci < 0 or ci >= entries.size() or not entries[ci].eligible:
			return false
		data = entries[ci].data
	var cost: int = price.call(data)
	if cost > 0 and not await PlayerSideScript.pay(main, pid, cost):
		return false
	if hand_node:
		data = PlayerSideScript.take_from_hand(main, pid, hand_node)
	elif not CardManager.take_from_cemetery(pid, data):
		return false
	data["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(data, pid):
		CardManager.add_to_cemetery(pid, data)
		return false
	return true


static func _revolver_webley(main: Node, card: Node, pid: int) -> void:
	var wielder = card.get_parent()
	if await _window(card, pid):
		return
	await _play_from_hand_or_cemetery(main, card, pid, 1, 0)
	if is_instance_valid(wielder) and wielder.get("equipped_weapons") is Array:
		wielder.set_meta("opp_immune_until", _until_before_next_turn(pid))
		main._update_debug("%s: %s no puede ser afectado por efectos oponentes hasta tu próximo turno" % [_name(card), _name(wielder)])

# =============================================================================
# OROS QUE GANAN O RECIBEN UNA HABILIDAD
# =============================================================================


## Le pone 'text' como habilidad (Card.card_ability reparsea sus disparadores; las auras se leen del texto).
static func set_ability(node: Node, text: String) -> void:
	if not is_instance_valid(node):
		return
	if node.get("card_data") is Dictionary:
		node.card_data["habilidad"] = text
	node.is_converted = false
	node.card_ability = text
	KeywordManager.scan_and_apply_keywords(node)
	ContinuousEffectManager.request_strength_badge_refresh()


## tres pascualas: "puedes convertir un Oro oponente en un Oro con la habilidad "Tus Aliados pierden 1 de
## Fuerza"" (la habilidad nueva reemplaza la suya).
static func _tres_pascualas(main: Node, card: Node, pid: int) -> void:
	var rx := RegEx.create_from_string("con la habilidad [\"“”]([^\"“”]+)[\"“”]")
	var m := rx.search(str(card.get("card_ability")))
	var golds := _golds(main, [1 - pid])
	if m == null or golds.is_empty() or not await _confirm(main, pid, _name(card), "Convertir un Oro oponente"):
		return
	var gold: Node = await _pick_from(main, pid, "%s: elige un Oro oponente" % _name(card), golds, true)
	if is_instance_valid(gold) and not await _window(card, pid):
		set_ability(gold, m.get_string(1).strip_edges())
		main._update_debug("%s: %s ahora tiene \"%s\"" % [_name(card), _name(gold), m.get_string(1)])


static func _canaan(main: Node, card: Node, pid: int) -> void:
	var mine := _golds(main, [pid])
	var theirs := _golds(main, [1 - pid]).filter(func(g): return not str(g.get("card_ability")).strip_edges().is_empty() and not KeywordManager.is_silenced(g))
	var copy := not mine.is_empty() and not theirs.is_empty()
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, _name(card),
			["Un Oro tuyo gana las habilidades de un Oro oponente", "Buscar un Arma en tu Castillo", "No"], pid)
		if pick < 0 or pick > 1:
			return
		copy = pick == 0
	if await _window(card, pid):
		return
	if copy:
		var own: Node = await _pick_from(main, pid, "%s: elige un Oro que controles" % _name(card), mine, false)
		var other: Node = await _pick_from(main, pid, "%s: elige un Oro oponente (sus habilidades)" % _name(card), theirs, false)
		if is_instance_valid(own) and is_instance_valid(other):
			var base: String = str(own.get("card_ability")).strip_edges()
			set_ability(own, (base + " " if not base.is_empty() else "") + str(other.get("card_ability")).strip_edges())
		return
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ARMA}, 1, true, false, false, card)


## Valac: "Destruye hasta tantas cartas oponentes de coste 2 o menos como Oros hayas pagado por este Aliado
## más uno." Lo pagado lo anota GoldManager.play_card() (meta "gold_paid"; si entró sin jugarse, 0).
static func _valac(main: Node, card: Node, pid: int) -> void:
	var n: int = int(card.get_meta("gold_paid", 0)) + 1
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return _cost(a) > _cost(b))
	var chosen: Array = await _pick_many(main, pid, "%s: Destruye hasta %d cartas oponentes de coste 2 o menos" % [_name(card), n], rivals, n, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.destroy(chosen, card, true)


## gokin: "puedes convertir una carta de coste 2 o menos en un Oro con la habilidad "Sólo puedes usar este
## Oro para pagar el coste de una carta de coste 3 o más" y ponlo en tu Reserva". La restricción la
## respeta el pago (meta "only_cost_min", GoldManager.gold_usable_for()).
static func _gokin(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO 			and ContinuousEffectManager.cost_at_most(c, 2)))
	if targets.is_empty() or not await _confirm(main, pid, _name(card), "Convertir una carta de coste 2 o menos en un Oro"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta de coste 2 o menos" % _name(card), targets, true)
	if not is_instance_valid(target) or await _window(card, pid) or not is_instance_valid(target):
		return
	var owner: int = int(target.owner_id) if target.get("owner_id") != null else CardQuery.controller_of(target)
	var weapons = target.get("equipped_weapons")
	if weapons is Array:
		for w in weapons.duplicate():
			if is_instance_valid(w):
				await CardManager.destroy_card(int(w.owner_id) if w.get("owner_id") != null else owner, w)
	var wielder = target.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(target)
	var data: Dictionary = target.card_data.duplicate()
	data["tipo"] = Constants.CardType.ORO
	data["habilidad"] = "Sólo puedes usar este Oro para pagar el coste de una carta de coste 3 o más."
	data["esta_oculta"] = false
	if target.get_parent():
		target.get_parent().remove_child(target)
	CardManager._disconnect_card_interaction_signals(target)
	target.queue_free()
	var gold: Node = await main._gold_manager.put_gold_directly_in_reserva(pid, data)
	if is_instance_valid(gold):
		gold.owner_id = owner
		gold.set_meta("only_cost_min", 3)
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)
	main._update_debug("%s: %s es ahora un Oro en tu Reserva (solo para cartas de coste 3 o más)" % [_name(card), str(data.get("nombre", ""))])

# =============================================================================
# OBLIGAR A COMBATIR, DADO, RECARGOS
# =============================================================================


static func _juzumaru(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var target: Node = await _pick_from(main, pid, "%s: un Aliado oponente debe atacar o bloquear este turno si puede" % _name(card), rivals, false)
	if is_instance_valid(target) and not await _window(card, pid):
		target.set_meta("must_fight_turn", GameManager.turn_serial)  # GameManager._declare_forced_attackers/_blockers
		main._update_debug("%s: %s debe atacar o bloquear este turno si puede" % [_name(card), _name(target)])


## Manicomio: su regla la aplica GoldManager._roll_manicomio_die(); al entrar no hace nada.
static func _manicomio(_main: Node, _card: Node, _pid: int) -> void:
	pass


static func _corazon_muerte(main: Node, card: Node, pid: int) -> void:
	if not card.get_meta("entered_from_hand", false):
		return
	var all: Array = _in_play(main, pid) + _golds(main, [pid])
	var target: Node = await _pick_from(main, pid, "%s: a tu oponente le cuesta un Oro más afectar esta carta" % _name(card), all, false)
	if is_instance_valid(target) and not await _window(card, pid):
		target.set_meta("affect_toll_until", _until_before_next_turn(pid))  # EffectController.offer_prevention


static func _amuleto_serpiente(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not await _confirm(main, pid, _name(card), "Mostrar las tres primeras cartas de tu Castillo") or await _window(card, pid):
		return
	var shown: Array = []
	for _i in mini(3, deck.size()):
		shown.append(deck.pop_front())
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	var ok: Array = shown.filter(func(d):
		var t := int(d.get("tipo", -1))
		return t == Constants.CardType.ARMA or (t == Constants.CardType.ALIADO and (int(d.get("coste", 0)) <= 1 \
			or "furia" in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))))))
	var idx := await _choose_data(main, pid, "%s: un Aliado de coste 1 o menos o con Furia, o un Arma, a tu mano" % _name(card), ok, true)
	if idx >= 0:
		shown.erase(ok[idx])
		PlayerSideScript.put_in_hand(main, pid, ok[idx])
		# "Si lo haces, hasta tu próximo turno jugar Talismanes cuesta un Oro adicional si ese jugador ha
		# jugado Talismanes en el turno." (PaymentManager._static_type_and_cheap_surcharge)
		for p in [0, 1]:
			RuleState.set_until("talisman_repeat_tax", p, RuleState.next_own_turn(pid))
	# Las demás mostradas vuelven al Castillo y se Baraja.
	RevealedCardsScript.shuffle_back(main, pid, shown, _name(card))


static func _lanza_juramento(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var next_turn: int = GameManager.turn_serial + 1
	var golds := _golds(main, [1 - pid])
	var gold: Node = await _pick_from(main, pid, "%s: un Oro oponente no puede ser agrupado el próximo turno" % _name(card), golds, false)
	if is_instance_valid(gold):
		gold.set_meta("no_regroup_turn", next_turn)  # GoldManager._reset_gold / EasyBot.reset_gold
	var all: Array = _in_play(main, 1 - pid) + _in_play(main, pid) + _golds(main, [0, 1])
	var bot_pool: Array = _in_play(main, 1 - pid) + _golds(main, [1 - pid])
	var target: Node = await _pick_from(main, pid, "%s: una carta no puede utilizar sus habilidades el próximo turno" % _name(card),
		bot_pool if PlayerSideScript.is_bot(pid) else all, false)
	if is_instance_valid(target):
		target.set_meta("silenced_on_turn", next_turn)  # KeywordManager.is_silenced


static func _trofeo_cazador(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Oto en tu Castillo",
			"Mostrar tu mano (si no tienes más de un Talismán, tu oponente solo juega un Talismán en esta Vigilia)", pid)
	if await _window(card, pid):
		return
	if search:
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"name_contains": "oto"}, 1, true, false, false, card)
		return
	var hand := _hand(main, pid)
	main._update_debug("%s: muestra su mano: %s" % [_name(card), ", ".join(hand.map(func(c): return _name(c)))])
	if hand.filter(func(c): return c.get("card_type") == Constants.CardType.TALISMAN).size() <= 1:
		RuleState.set_turn_data("one_talisman:%d" % (1 - pid), {"on": true})  # GoldManager._card_play_locked
