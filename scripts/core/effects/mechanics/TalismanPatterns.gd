extends "res://scripts/core/effects/mechanics/TalismanPatternsLote3.gd"
## TalismanPatterns — familia RespuestasLimites (ver TalismanPatternsBase.gd para la cabecera, constantes y ayudas).


# =============================================================================
# INMUNIDAD A EFECTOS OPONENTES
# =============================================================================


static func _jugando_demonio(main: Node, card: Node, pid: int) -> void:
	for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		KeywordManager.grant_keyword(c, Constants.Keyword.IMBLOQUEABLE, card, "turn")
		await _buff_turn(c, card, 1)
		c.set_meta("attack_uncancellable_turn", GameManager.turn_serial)  # ProtectionRules.attack_uncancellable


## Fuego Purificador / Rugido de Titán: "Prevén que una carta sea afectada por un efecto oponente" — en el
## momento: la carta elegida no es afectada por el efecto rival que está en la pila (meta
## "prevent_effect_of", que mira EffectController.opp_immune_card()). Sin efecto rival en la pila, no hace
## nada.
static func _protect_one(main: Node, card: Node, pid: int, filter: Callable, prompt: String) -> Node:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, true)
	var source = StackAnnulScript.card_of(obj) if not obj.is_empty() else null
	var mine := EnterScript._in_play(main, pid, filter) + EnterScript._golds(main, [pid]).filter(filter)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: %s" % [_name(card), prompt], mine, false)
	if not is_instance_valid(target):
		return null
	if source != null and is_instance_valid(source):
		target.set_meta("prevent_effect_of", {"source_id": source.get_instance_id(), "turn": GameManager.turn_serial})
		main._update_debug("%s: %s no será afectada por %s" % [_name(card), EnterScript._name(target), EnterScript._name(source)])
	else:
		main._update_debug("%s: no hay un efecto oponente en curso que prevenir" % _name(card))
	return target


static func _fuego_purificador(main: Node, card: Node, pid: int) -> void:
	await _protect_one(main, card, pid, func(_c): return true, "elige una carta que controles")


static func _rugido_titan(main: Node, card: Node, pid: int) -> void:
	var is_named := func(c) -> bool:
		var n := CemeteryTriggersScript.normalize(str(c.get("card_name")))
		return "ignis" in n or "titan" in n
	# "...sea Anulada, cancelada": si la carta Ignis o Titán está en la pila (jugándose o con su habilidad),
	# no puede ser Anulada ni cancelada este turno.
	for obj in ActionPipeline.get_stack():
		var node = StackAnnulScript.card_of(obj)
		if node != null and is_instance_valid(node) and is_named.call(node) and CardQuery.controller_of(node) == pid:
			node.set_meta("protected_from_annul_this_turn", true)
			node.set_meta("protected_from_cancel_turn", GameManager.turn_serial)
	await _protect_one(main, card, pid, is_named, "elige una carta de nombre Ignis o Titán")


## viaje temporal: "Al finalizar este turno, gana un turno extra. Ese turno tu oponente no puede recibir
## daño." GameManager.end_turn() consume el pendiente "extra_turn" y no cambia de jugador.
static func _viaje_temporal(main: Node, card: Node, pid: int) -> void:
	RuleState.set_pending("extra_turn", pid, true)
	var until: int = GameManager.turn_serial + 2  # vale hasta que termina el turno extra
	for kind in ["no_combat_damage", "no_direct_damage"]:
		RuleState.set_until(kind, 1 - pid, until)
	main._update_debug("%s: al finalizar este turno ganas un turno extra" % _name(card))

# =============================================================================
# EN RESPUESTA A ALGO
# =============================================================================


## La carta rival que se está jugando (la más cercana al tope de la pila). {} si no hay.
static func _opponent_card_on_stack(pid: int, filter: Callable = Callable()) -> Dictionary:
	return StackAnnulScript.find_target(pid, true, false, filter)


static func _expulsion(main: Node, card: Node, pid: int) -> void:
	var obj := _opponent_card_on_stack(pid)
	if obj.is_empty():
		main._update_debug("%s: no hay una carta oponente jugándose" % _name(card))
		return
	if StackAnnulScript.type_of(obj) == Constants.CardType.TALISMAN:
		TriggerSystem._totem_patterns.register_kotoku_in_talisman_fizzle(1 - pid)  # se resuelve sin efecto
	else:
		var node = StackAnnulScript.card_of(obj)
		if node != null and is_instance_valid(node):
			node.set_meta("silenced_until", GameManager.turn_serial)  # entra sin habilidad por el turno
	main._update_debug("%s: %s queda sin habilidad" % [_name(card), str(StackAnnulScript.data_of(obj).get("nombre", "esa carta"))])


static func _descubrir_zorro(main: Node, card: Node, pid: int) -> void:
	var obj := _opponent_card_on_stack(pid, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.ALIADO)
	var node = StackAnnulScript.card_of(obj) if not obj.is_empty() else null
	if node == null or not is_instance_valid(node):
		main._update_debug("%s: no hay un Aliado oponente entrando en juego" % _name(card))
		return
	node.set_meta("silenced_until", 1 << 30)  # sin habilidad (permanente)
	main._update_debug("%s: %s entra en juego sin habilidad" % [_name(card), EnterScript._name(node)])


static func _iluminar(main: Node, card: Node, pid: int) -> void:
	var obj := _opponent_card_on_stack(pid)
	var opp: int = 1 - pid
	if not obj.is_empty():
		var t: int = StackAnnulScript.type_of(obj)
		# La carta en la pila todavía no se contó: esa y una más.
		RuleState.set_turn_data("iluminar:%d" % opp, {"type": t, "allowed": RuleState.count("played_type:%d" % t, opp) + 2})
	if main._gold_manager:
		main._gold_manager.set_no_more_cards_this_turn(pid)


static func _ofrenda_abuelos(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar hasta dos cartas de distinto nombre en un Castillo y Desterrarlas",
			"Prevenir que tu oponente busque cartas en tu Castillo", pid)
	if not search:
		RuleState.set_turn_data("castle_search_block:%d" % pid, {"on": true})  # EffectController.fision_hides_zones_of
		main._update_debug("%s: tu oponente no puede buscar cartas en tu Castillo este turno" % _name(card))
		return
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	await ActionModule.search(owner, Constants.Zone.CASTILLO, {}, 2, true, false, false, card, Constants.Zone.DESTIERRO, true, pid)


static func _puertas(main: Node, card: Node, pid: int) -> void:
	DamageShieldsScript.add_next_zero(pid)
	var lines: Array = PlayerSideScript.ally_containers(main, 1 - pid)
	var n: int = lines[1].get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO).size() 		if lines.size() > 1 else 0
	if n > 0:
		await ActionModule.mill(1 - pid, 2 * n, false, _name(card))


static func _arlequin(main: Node, card: Node, pid: int) -> void:
	DamageShieldsScript.add_arlequin(pid)
	main._update_debug("%s: se previene todo el daño a tu Castillo este turno" % _name(card))

# =============================================================================
# LÍMITES Y TEXTOS NUEVOS
# =============================================================================


## Último turn_serial (exclusivo, para RuleState.set_until) de "hasta el final de tu próximo turno".
static func _end_of_next_own_turn(pid: int) -> int:
	return GameManager.turn_serial + (2 if GameManager.active_player_id == pid else 1) + 1


## "Prevén un efecto" (Concilio de los Eternos, Camino del Guerrero): el efecto rival más cercano al tope
## de la pila no se resuelve (StackAnnul.prevent: no es Cancelar, vale aunque no pueda ser cancelado).
static func _prevent_an_effect(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_preventable(pid)
	if obj.is_empty():
		main._update_debug("%s: no hay un efecto oponente que prevenir" % _name(card))
		return
	StackAnnulScript.prevent(obj)


static func _sabiduria_oruga(main: Node, card: Node, pid: int) -> void:
	await EnterScript._peek_banish(main, card, pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and int(c.get("card_cost")) <= 2, 2)
	var until := _end_of_next_own_turn(pid)
	for p in [0, 1]:
		RuleState.set_until("attack_cap_1", p, until)  # GameManager.attack_cap
		RuleState.set_until("draw_cap_3", p, until)  # ActionModule.draw
	main._update_debug("%s: hasta el final de tu próximo turno, un solo atacante y hasta tres robos por efectos por turno" % _name(card))


static func _concilio(main: Node, card: Node, pid: int) -> void:
	await _prevent_an_effect(main, card, pid)
	RuleState.set_turn_data("attack_cap_2:%d" % (1 - pid), {"on": true})


static func _camino_guerrero(main: Node, card: Node, pid: int) -> void:
	await _prevent_an_effect(main, card, pid)
	for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		await _buff_turn(c, card, 1, true)


static func _pereza(main: Node, card: Node, pid: int) -> void:
	# "Los próximos dos turnos": el siguiente y el que le sigue (no el actual).
	var from: int = GameManager.turn_serial + 1
	var until: int = GameManager.turn_serial + 3
	for p in [0, 1]:
		RuleState.set_window("no_attacks", p, from, until)
	RuleState.set_window("one_card_turn", pid, from, until)
	main._update_debug("%s: los próximos dos turnos no se puede atacar y no puedes jugar más de una carta por turno" % _name(card))


static func _no_mas_magia(main: Node, card: Node, _pid: int) -> void:
	for p in [0, 1]:
		RuleState.set_until("no_mas_magia", p, 1 << 30)
	main._update_debug("%s: jugar Talismanes y cartas sin pagar su coste cuesta un Oro adicional por el resto del juego" % _name(card))


static func _escudo_estelar(main: Node, card: Node, pid: int) -> void:
	# Hasta tu próxima Fase Final: si es tu turno, la de este turno.
	var until: int = GameManager.turn_serial + (1 if GameManager.active_player_id == pid else 2)
	for p in [0, 1]:
		RuleState.set_until("zones_hidden", p, until)  # EffectController.fision_hides_zones_of
	main._update_debug("%s: nadie puede buscar ni mirar la mano o los Castillos por efectos hasta tu próxima Fase Final" % _name(card))


static func _a_traves_espejo(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: un Aliado de coste 2 o menos de tu Cementerio (su habilidad)" % _name(card), 1, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2 and not str(d.get("habilidad", "")).strip_edges().is_empty())
	if not allies.is_empty() and not picks.is_empty():
		var target: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado que controles" % _name(card), allies, false)
		if is_instance_valid(target):
			var base: String = str(target.get("card_ability")).strip_edges()
			EnterScript.set_ability(target, (base + " " if not base.is_empty() else "") + str(picks[0].data.get("habilidad", "")).strip_edges())
	var exhumar_or_furia := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and (KeywordManager.has_keyword(c, Constants.Keyword.FURIA) or "exhumar" in CemeteryTriggersScript.normalize(str(c.get("card_ability")))))
	if exhumar_or_furia.is_empty():
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia o Imbloqueable" % _name(card), allies, false)
	if not is_instance_valid(ally):
		return
	var kw: int = Constants.Keyword.FURIA
	if not PlayerSideScript.is_bot(pid) and not await SelectionManager.await_two_choice(main, _name(card), "Furia", "Imbloqueable", pid):
		kw = Constants.Keyword.IMBLOQUEABLE
	KeywordManager.grant_keyword(ally, kw, null, "permanent")


static func _todos_locos(main: Node, card: Node, pid: int) -> void:
	var small := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) <= 2)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado de coste 2 o menos que controles" % _name(card), small, false)
	if not is_instance_valid(target):
		return
	var cost: int = EnterScript._cost(target)
	var models := EnterScript._in_play(main, pid, func(c): return c != target and c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) == cost)
	var model: Node = await EnterScript._pick_from(main, pid, "%s: el Aliado que copia" % _name(card), models, false)
	if not is_instance_valid(model):
		return
	var data: Dictionary = model.card_data.duplicate()
	data["esta_oculta"] = false
	var owner = target.get("owner_id")
	var ctrl = target.get("controller_id")
	target.load_from_data(data)
	target.owner_id = owner
	target.controller_id = ctrl
	EnterScript.set_ability(target, str(data.get("habilidad", "")))
	main._update_debug("%s: ahora es una copia de %s" % [_name(card), EnterScript._name(model)])


static func _captura_colosal(main: Node, card: Node, pid: int) -> void:
	var mine := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var theirs := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var a: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles" % _name(card), mine, false)
	var b: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado oponente" % _name(card), theirs, false)
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var sa: int = int(ContinuousEffectManager.get_modified_strength(a))
	var sb: int = int(ContinuousEffectManager.get_modified_strength(b))
	var losers: Array = [a] if sa < sb else ([b] if sb < sa else [a, b])  # empate: los dos
	for c in losers:
		EnterScript.set_ability(c, "En tu Fase Final, Destierra las primeras dos cartas de tu Castillo.")
		for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
			ContinuousEffectManager.register_modifier({
				"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
				"restriction_type": restriction, "duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
				"description": "%s: no ataca ni bloquea" % _name(card),
			})


static func _dia_muertos(main: Node, card: Node, _pid: int) -> void:
	for c in EnterScript._all_allies(main):
		EnterScript.set_ability(c, "No puede portar Armas.")  # GoldManagerRestrictions._max_weapons_for
		ContinuousEffectManager.register_modifier({
			"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 1, "operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "%s: Fuerza 1" % _name(card),
		})
		if c.has_method("refresh_strength_badge"):
			c.refresh_strength_badge()


static func _identidad_secreta(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		return StackAnnulScript.type_of(o) in [Constants.CardType.ARMA, Constants.CardType.TOTEM] and StackAnnulScript.cost_of(o) <= 3)
	var annul := not obj.is_empty()
	if annul and not PlayerSideScript.is_bot(pid):
		annul = await SelectionManager.await_two_choice(main, _name(card), "Anular %s y Desterrarla" % str(StackAnnulScript.data_of(obj).get("nombre", "")),
			"Desterrar las Armas en juego o un Tótem", pid)
	if annul:
		# "...y Destierra esa carta": la Anulada va al Destierro y no al Cementerio (meta annul_to_exile,
		# la misma de Red de Plata, que mira GoldManager al recibir la anulación).
		var node = StackAnnulScript.card_of(obj)
		if node != null and is_instance_valid(node) and not StackAnnulScript.protected_from_annul(obj):
			node.set_meta("annul_to_exile", true)
		StackAnnulScript.apply(obj, card)
		return
	var weapons: Array = CardQuery.weapons_in_play(0) + CardQuery.weapons_in_play(1)
	var totems := _in_play_both(main, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	var all_weapons := not weapons.is_empty()
	if not PlayerSideScript.is_bot(pid) and not weapons.is_empty() and not totems.is_empty():
		all_weapons = await SelectionManager.await_two_choice(main, _name(card), "Desterrar las Armas en juego", "Desterrar un Tótem", pid)
	if all_weapons:
		await ActionModule.banish(weapons, card, true)
	else:
		var t: Node = await EnterScript._pick_from(main, pid, "%s: Destierra un Tótem" % _name(card),
			totems.filter(func(c): return CardQuery.controller_of(c) != pid) if PlayerSideScript.is_bot(pid) else totems, false)
		if is_instance_valid(t):
			await ActionModule.banish([t], card, true)


## julio verne: "Sube cualquier cantidad de Aliados que controles a tu mano. Al comienzo de tu próximo
## turno juégalos sin pagar su coste, y ganan 1 de Fuerza permanentemente."
static func _julio_verne(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: Aliados que suben a tu mano" % _name(card), allies, allies.size(), true)
	var names: Array = []
	for c in chosen:
		if is_instance_valid(c):
			names.append(EnterScript._name(c))
			await EnterScript.bounce_to_owner_hand(main, c, card)
	if names.is_empty():
		return
	var replay: Callable
	replay = func(started: int, _turn: int) -> void:
		if started != pid:
			return
		GameManager.turn_started.disconnect(replay)
		for n in names:
			var node: Node = null
			for h in PlayerSideScript.hand_cards(main, pid):
				if is_instance_valid(h) and EnterScript._name(h) == n:
					node = h
					break
			if node == null:
				continue
			var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, node)
			if await main._gold_manager.play_card_for_free(data, pid):
				for c in EnterScript._in_play(main, pid, func(x): return EnterScript._name(x) == n):
					await _buff_turn(c, null, 1, true)
					break
	GameManager.turn_started.connect(replay)


## Marca de los Justos: ContinuousEffectManager.register_modifier() duplica las ganancias de Fuerza que
## vengan después (máximo 4 por vez) e ignora cualquier otra modificación, por el turno.
static func _marca_justos(main: Node, card: Node, _pid: int) -> void:
	RuleState.set_turn_data("marca_justos", {"on": true})
	main._update_debug("%s: este turno, cada ganancia de Fuerza es el doble (máximo 4)" % _name(card))

# =============================================================================
# CUARTO LOTE
# =============================================================================


static func _niebla_muerte(main: Node, card: Node, pid: int) -> void:
	# "Las cartas que sean puestas en el Cementerio este turno pierden su habilidad por el turno."
	var serial: int = GameManager.turn_serial
	var mark: Callable
	mark = func(_owner: int, data: Dictionary) -> void:
		if GameManager.turn_serial != serial:
			CardManager.card_put_in_cemetery.disconnect(mark)
			return
		data["_silenced_turn"] = serial  # CardManager.is_cemetery_card_silenced
	CardManager.card_put_in_cemetery.connect(mark)
	var small := _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3))
	if PlayerSideScript.is_bot(pid):
		small = small.filter(func(c): return CardQuery.controller_of(c) != pid)
	var one: Array = await EnterScript._pick_many(main, pid, "%s: Destruye hasta una carta de coste 3 o menos" % _name(card), small, 1, true)
	if not one.is_empty():
		await ActionModule.destroy(one, card, true)
	await ActionModule.mill(1 - pid, 7, false, _name(card))


static func _comer_insectos(main: Node, card: Node, pid: int) -> void:
	var mine := _in_play_both(main, func(c): return CardQuery.controller_of(c) == pid and c.get("card_type") != Constants.CardType.ORO \
		and not str(c.get("card_ability")).strip_edges().is_empty() and not KeywordManager.is_silenced(c) and EnterScript._cost(c) >= 1)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: Destruye hasta dos cartas con habilidad de coste 1 o más que controles" % _name(card),
		mine, 2, true)
	var destroyed := 0
	if not chosen.is_empty():
		var res: Dictionary = await ActionModule.destroy(chosen, card, true)
		destroyed = chosen.filter(func(c): return not is_instance_valid(c) or not (c.get("current_zone") in Constants.ZONES_IN_PLAY)).size() \
			if res.get("success", true) else 0
	if destroyed > 0:
		for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
			await _buff_turn(c, card, destroyed)
	RuleState.set_turn_data("unpreventable_damage:%d" % pid, {"on": true})  # BattleManager._apply_castle_damage


static func _anillo_tierra(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	RuleState.set_turn_data("one_more_action:%d" % opp, {"cards": RuleState.count("played_any", opp), "abilities": RuleState.count("abilities_used", opp)})
	var next_turn: int = RuleState.next_own_turn(pid)
	RuleState.set_window("one_card_turn", pid, next_turn, next_turn + 1)  # "Sólo puedes jugar una carta el próximo turno"
	main._update_debug("%s: tu oponente solo puede jugar una carta más o utilizar una habilidad más este turno" % _name(card))


static func _duelo_magico(main: Node, card: Node, pid: int) -> void:
	var totals: Array = [0, 0]
	for p in [0, 1]:
		var hand: Array = EnterScript._hand(main, p)
		for c in hand:
			totals[p] += int(c.get("card_cost")) if c.get("card_cost") != null else 0
		main._update_debug("%s: mano del jugador %d: %s (coste total %d)" % [_name(card), p + 1,
			", ".join(hand.map(func(c): return EnterScript._name(c))), totals[p]])
	var losers: Array = [0] if totals[0] > totals[1] else ([1] if totals[1] > totals[0] else [0, 1])
	for p in losers:
		RuleState.set_until("mill_cap_10", p, 1 << 30)  # ActionModule.mill
		RuleState.set_until("hand_loss_cap_1", p, 1 << 30)  # ActionModule.discard / EnterPatterns._exile_from_hand


## Sesión Espiritista: la reducción del daño de combate (DamageShields) y, hasta tu próximo turno, cuando tu
## oponente Roba por un efecto, puedes poner la misma cantidad del tope de tu Castillo en tu mano
## (ActionModule.draw → on_opponent_effect_draw). Otras formas de "poner cartas en su mano" no se cuentan.
static func _sesion_espiritista(main: Node, card: Node, pid: int) -> void:
	DamageShieldsScript.add_permanent_reduction(pid)
	RuleState.set_until("sesion_espiritista", pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: el daño de combate a tu Castillo se reduce en dos por el resto del juego" % _name(card))


static func on_opponent_effect_draw(drawer: int, amount: int) -> void:
	var watcher: int = 1 - drawer
	if amount <= 0 or not RuleState.active("sesion_espiritista", watcher):
		return
	var main := CardQuery.main_node()
	if not main or not await EnterScript._confirm(main, watcher, "Sesión Espiritista", "Poner %d carta(s) del tope de tu Castillo en tu mano" % amount):
		return
	var deck: Array = CardManager.get_deck(watcher)
	for _i in mini(amount, deck.size()):
		PlayerSideScript.put_in_hand(main, watcher, deck.pop_front())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _terremoto(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._all_allies(main)
	if PlayerSideScript.is_bot(pid):
		allies = allies.filter(func(c): return CardQuery.controller_of(c) == pid)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado duplica su Fuerza hasta tu próximo turno" % _name(card), allies, false)
	if not is_instance_valid(target):
		return
	var anticucho: bool = false
	var weapons = target.get("equipped_weapons")
	if weapons is Array:
		anticucho = weapons.any(func(w): return is_instance_valid(w) and "anticucho" in CemeteryTriggersScript.normalize(str(w.get("card_name"))))
	var strength: int = int(ContinuousEffectManager.get_modified_strength(target))
	var turns: int = 2 if GameManager.active_player_id == pid else 1  # fines de turno hasta tu próximo turno
	ContinuousEffectManager.register_modifier({
		"source": null, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": strength * (2 if anticucho else 1), "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": turns,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY, "description": "%s: Fuerza %s" % [_name(card), "triple" if anticucho else "doble"],
	})
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()
	target.set_meta("terremoto", {"until": RuleState.next_own_turn(pid) - 1, "pid": pid, "printed": anticucho})  # GameManager._terremoto_mill


static func _furia_titan(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado que controles" % _name(card), allies, false)
	if not is_instance_valid(target):
		return
	var lines: Array = PlayerSideScript.ally_containers(main, pid)
	var until: int = RuleState.next_own_turn(pid) - 1
	if lines.size() > 1 and target.get_parent() == lines[1]:
		EffectController.add_single_card_leave_play_immunity(target, pid)
		target.set_meta("damage_to_exile_turn", GameManager.turn_serial)
		main._update_debug("%s: %s no puede salir del juego por efectos y su daño va al Destierro" % [_name(card), EnterScript._name(target)])
	else:
		GameManager.attack_strength_caps[1 - pid] = {"node": target, "until": until}  # TurnManager.can_attack
		main._update_debug("%s: tu oponente no puede atacar con Aliados de mayor Fuerza que %s" % [_name(card), EnterScript._name(target)])


static func _marca_bestia(main: Node, card: Node, pid: int) -> void:
	var small := EnterScript._all_allies(main, func(c): return EnterScript._cost(c) <= 2)
	if PlayerSideScript.is_bot(pid):
		small = small.filter(func(c): return CardQuery.controller_of(c) == pid)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado de coste 2 o menos" % _name(card), small, false)
	if not is_instance_valid(target):
		return
	for kw in [Constants.Keyword.FURIA, Constants.Keyword.INDESTRUCTIBLE]:
		KeywordManager.grant_keyword(target, kw, null, "until_next_turn")
	target.set_meta("must_fight_turn", GameManager.turn_serial)  # GameManager._declare_forced_attackers
	var until: int = RuleState.next_own_turn(pid) - 1
	target.set_meta("no_control_change_until", until)  # ContinuousEffectManager.gain_control_of_card
	target.set_meta("no_convert_until", until)


static func _ta_kona(main: Node, card: Node, pid: int) -> void:
	RuleState.set_pending("extra_battle", pid, true)  # PhaseFlowController._on_battle_combat_finished
	main._update_debug("%s: al final de esta Batalla Mitológica ganas una adicional" % _name(card))


## nuevas tierras: tus Oros pasan a ser Aliados de Fuerza 3 sin habilidad que no pueden salir del juego este
## turno; en la Fase Final vuelven a ser Oros, en tu Oro Pagado.
static func _nuevas_tierras(main: Node, card: Node, pid: int) -> void:
	var golds: Array = EnterScript._golds(main, [pid])
	if golds.is_empty():
		return
	var field: Node = PlayerSideScript.ally_containers(main, pid)[0]
	var converted: Array = []
	for g in golds:
		var was_paid: bool = g.get_parent() == PlayerSideScript.oro_pagado(main, pid)
		if was_paid:
			GameState.agregar_oro_pagado(pid, -1)
		else:
			GameState.agregar_oro_reserva(pid, -1)
		g.get_parent().remove_child(g)
		g.card_type = Constants.CardType.ALIADO
		g.scale = Vector2.ONE
		g.base_scale = Vector2.ONE
		g.modulate = Color.WHITE
		field.add_child(g)
		g.set_zone(Constants.Zone.LINEA_DEFENSA)
		await ConvertScript._finish_conversion(g, card, pid, 3, [], false)
		g.set_meta("no_leave_turn", GameManager.turn_serial)
		converted.append(g)
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	EffectController.schedule_next_final_phase_effect(pid, func() -> void:
		for g in converted:
			if is_instance_valid(g) and g.get("current_zone") in Constants.ZONES_IN_PLAY:
				ContinuousEffectManager.remove_modifiers_from_source(g)
				g.get_parent().remove_child(g)
				g.card_type = Constants.CardType.ORO
				g.is_converted = false
				KeywordManager.clear_all_for_card(g)  # vuelve a tener su habilidad de Oro
				PlayerSideScript.oro_pagado(main, pid).add_child(g)
				g.set_zone(Constants.Zone.ORO_PAGADO)
				g.scale = Constants.GOLD_CARD_SCALE
				g.base_scale = Constants.GOLD_CARD_SCALE
				g.modulate = Color(0.6, 0.6, 0.6, 1.0)
				GameState.agregar_oro_pagado(pid, 1)
		if main._gold_manager:
			main._gold_manager._update_gold_display()
		main._update_debug("nuevas tierras: los Aliados vuelven a ser Oros en tu Oro Pagado"))


static func _alma_viento(main: Node, card: Node, pid: int) -> void:
	await _raise_one(main, pid, "%s: sube una carta de tu Cementerio a tu mano" % _name(card), false)
	# "Cuando este Talismán se resuelva, conviértelo en un Oro con la habilidad ... y ponlo en el Oro Pagado
	# oponente": cuando llega al Cementerio después de resolverse, sale de ahí como ese Oro.
	var data: Dictionary = card.card_data if is_instance_valid(card) else {}
	var name := str(data.get("nombre", ""))
	var once: Callable
	once = func(owner_id: int, d: Dictionary) -> void:
		if str(d.get("nombre", "")) != name:
			return
		CardManager.card_put_in_cemetery.disconnect(once)
		if not CardManager.take_from_cemetery(owner_id, d) or not main._gold_manager:
			return
		var gold_data: Dictionary = d.duplicate()
		gold_data["tipo"] = Constants.CardType.ORO
		gold_data["habilidad"] = "No puede ser agrupado. Los Aliados oponentes ganan 1 de Fuerza y tus Aliados pierden 1 de Fuerza."
		var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(1 - pid, gold_data)
		if is_instance_valid(gold):
			gold.owner_id = owner_id
			gold.set_meta("never_regroup", true)  # GoldManager._reset_gold / EasyBot.reset_gold
	CardManager.card_put_in_cemetery.connect(once)


static func _estaca(main: Node, card: Node, pid: int) -> void:
	# "Utiliza una habilidad activada de una carta de coste 2 o menos en un Cementerio o Destierro como si la
	# controlaras": una que el compilador entiende entera, sobre un Nodo temporal (como los farsarios).
	var pools: Array = []
	var clauses: Array = []
	for p in [pid, 1 - pid]:
		for zone in [Constants.Zone.CEMENTERIO, Constants.Zone.DESTIERRO]:
			var arr: Array = CardManager.get_cemetery(p) if zone == Constants.Zone.CEMENTERIO else CardManager.get_exile(p)
			var entries: Array = []
			for d in arr:
				var clause: String = LeavePlayScript._activated_clause(d) if int(d.get("coste", 0)) <= 2 and int(d.get("tipo", -1)) != Constants.CardType.ORO else ""
				entries.append({"data": d, "eligible": not clause.is_empty()})
				clauses.append(clause)
			pools.append({"is_own": p == pid, "zone": zone, "cards": entries, "exclusive": true})
	if pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		var raw: Array = await ActionModule.pick_in_zones(pid, "%s: una habilidad activada de una carta de coste 2 o menos" % _name(card), pools, 0, 1)
		if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2:
			var pi := int(raw[0][0])
			var ci := int(raw[0][1])
			if pi >= 0 and pi < pools.size() and ci >= 0 and ci < pools[pi].cards.size() and pools[pi].cards[ci].eligible:
				var offset := 0
				for k in pi:
					offset += pools[k].cards.size()
				var d: Dictionary = pools[pi].cards[ci].data
				var proxy: Node = main._create_card(d, false)
				proxy.visible = false
				main.add_child(proxy)
				proxy.owner_id = pid
				proxy.controller_id = pid
				await TriggerSystem._effect_interpreter.try_execute(proxy, clauses[offset + ci], pid)
				if is_instance_valid(proxy):
					proxy.queue_free()
	# "Los jugadores ganan el control de las cartas en juego que no sean Oro de las que sean dueños."
	for c in _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO and c.get("owner_id") != null \
			and int(c.owner_id) != CardQuery.controller_of(c)):
		ContinuousEffectManager.gain_control_of_card(c, int(c.owner_id))


static func _corromper(main: Node, card: Node, pid: int) -> void:
	# "Ambos jugadores muestran su mano, comenzando por ti cada jugador elige una carta de la mano oponente y la
	# coloca en su mano."
	for chooser in [pid, 1 - pid]:
		var from: int = 1 - chooser
		var hand: Array = EnterScript._hand(main, from)
		if hand.is_empty():
			continue
		if not PlayerSideScript.is_bot(chooser):
			SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), chooser)
		var idx := 0
		if PlayerSideScript.is_bot(chooser):
			hand.sort_custom(func(a, b): return int(a.get("card_cost")) > int(b.get("card_cost")))
		elif hand.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: elige una carta de la mano oponente" % _name(card),
				hand.map(func(c): return EnterScript._name(c)), chooser), 0, hand.size() - 1)
		var data: Dictionary = PlayerSideScript.take_from_hand(main, from, hand[idx])
		if not data.is_empty():
			PlayerSideScript.put_in_hand(main, chooser, data)


static func _invocar_angeles(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: puedes jugar un Aliado Ángel de tu Cementerio por un Oro menos" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and "angel" in CemeteryTriggersScript.normalize(str(d.get("raza", ""))) 				and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid))
		for pk in picks:
			if CardManager.take_from_cemetery(pid, pk.data) and not await _play_paying(main, pid, pk.data, price.call(pk.data)):
				CardManager.add_to_cemetery(pid, pk.data)
	RuleState.set_until("hand_revealed", 1 - pid, 1 << 30)  # HandReveal: por el resto del juego
	load("res://scripts/core/effects/mechanics/HandReveal.gd").refresh()
	main._update_debug("%s: tu oponente juega mostrando su mano por el resto del juego" % _name(card))


## koi dragon: "Convierte todos los Oros en juego en Oros sin habilidad. Busca en el Castillo oponente una
## carta y juégala bajo tu control por un Oro menos". Elige quien juega el Talismán (antes caía en el
## analizador viejo, que le preguntaba al rival). Un Oro no se juega: se pone en tu Reserva.
static func _koi_dragon(main: Node, card: Node, pid: int) -> void:
	for p in [0, 1]:
		for cont in [PlayerSideScript.gold_reserva(main, p), PlayerSideScript.oro_pagado(main, p)]:
			if not cont:
				continue
			for g in cont.get_children():
				if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO and not KeywordManager.is_silenced(g):
					await KeywordManager.silence_card(g, card, "permanent")
	var opp: int = 1 - pid
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty() or not main.get("_gold_manager"):
		return
	var entries: Array = deck.map(func(d): return {"data": d, "eligible": true})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: busca una carta en el Castillo oponente" % _name(card),
		[{"is_own": false, "zone": Constants.Zone.CASTILLO, "cards": entries, "exclusive": true}], 1, 1)
	var d: Dictionary = {}
	if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2 and int(raw[0][1]) >= 0 and int(raw[0][1]) < entries.size():
		d = entries[int(raw[0][1])].data
	CardManager.shuffle_deck(opp)
	AnimationQueue.queue_shuffle(opp, "Barajar mazo (%s)" % _name(card))
	if d.is_empty():
		return
	deck.erase(d)
	d["esta_oculta"] = false
	if int(d.get("tipo", -1)) == Constants.CardType.ORO:
		await main._gold_manager.put_gold_directly_in_reserva(pid, d)
	elif not await _play_paying(main, pid, d, maxi(0, int(d.get("coste", 0)) - 1)):
		# No se pudo pagar: queda en tu mano.
		PlayerSideScript.put_in_hand(main, pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
