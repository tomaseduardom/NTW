extends RefCounted
## Deck170Patterns — efectos que faltaban del mazo 170 (Talisman - Control),
## 2026-10-14, ver docs/revision-mazo-170.md. Cada patrón reconoce su propio
## texto; try_execute() los prueba en orden. Se usa con preload (ver §54).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")
const TalismanSearchScript = preload("res://scripts/core/effects/triggers/TalismanSearchPatterns.gd")


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Main")


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ")
	if await _try_rey_lonolicos(card, lower, controller_id):
		return true
	if await _try_ursitoare(card, lower, controller_id):
		return true
	if await _try_mill_per_ally(card, lower, controller_id):
		return true
	if await _try_matriz_v_enter(card, lower, controller_id):
		return true
	if await _try_gran_descenso(card, lower, controller_id):
		return true
	if await _try_signo_amarillo_cancel(card, lower, controller_id):
		return true
	if await _try_hand_banish_to_annul(card, lower, controller_id):
		return true
	return false


# -----------------------------------------------------------------------------
# Diadema Celestial: "Tus Aliados bloqueadores ganan 1 de Fuerza y los Aliados
# oponentes pierden Imbloqueable. Si Botas esta carta por daño, dejas de Botar
# cartas y Destierras este Oro." / Visión de Enoc: "Cuando Botes esta carta
# por daño, puedes Barajar hasta cinco cartas de los Cementerios."
# -----------------------------------------------------------------------------
static func count_in_gold_zones(pid: int, phrase: String) -> int:
	var main := _main_node()
	if not main:
		return 0
	var n := 0
	for zone in [PlayerSideScript.gold_reserva(main, pid), PlayerSideScript.oro_pagado(main, pid)]:
		if not zone:
			continue
		for c in zone.get_children():
			if is_instance_valid(c) and c.get("card_ability") != null and c.get("is_converted") != true \
					and not KeywordManager.is_silenced(c) and phrase in str(c.card_ability).to_lower():
				n += 1
	return n


static func blocker_strength_bonus(blocker: Node) -> int:
	var pid: int = blocker.controller_id if blocker.get("controller_id") != null else 0
	return count_in_gold_zones(pid, "tus aliados bloqueadores ganan 1 de fuerza")


static func opponent_removes_unblockable(attacker: Node) -> bool:
	var pid: int = attacker.controller_id if attacker.get("controller_id") != null else 0
	return count_in_gold_zones(1 - pid, "los aliados oponentes pierden imbloqueable") > 0


static func on_milled_by_damage(pid: int, data: Dictionary, destination: int) -> bool:
	"""Una carta Botada por daño. true = dejar de Botar (Diadema Celestial)."""
	var text: String = str(data.get("habilidad", "")).to_lower()
	if "si botas esta carta por daño, dejas de botar cartas y destierras este oro" in text:
		var zone: Array = CardManager.get_cemetery(pid) if destination == Constants.Zone.CEMENTERIO else []
		var idx: int = zone.find(data)
		if idx >= 0:
			CardManager.remove_from_cemetery(pid, idx)
			CardManager.append_to_exile(pid, data)
		var main := _main_node()
		if main:
			main._update_debug("Diadema Celestial: se deja de Botar y se Destierra")
		return true
	if "cuando botes esta carta por daño, puedes barajar hasta cinco cartas de los cementerios" in text \
			and not PlayerSideScript.is_bot(pid):
		await ActionModule.search_either_owner(pid, [Constants.Zone.CEMENTERIO], {}, 5, true, null, Constants.Zone.CASTILLO)
	return false


# -----------------------------------------------------------------------------
# Envidia: "Si está en tu Cementerio y si tienes menos cartas en tu mano que tu
# oponente, puedes Desterrarlo para Robar una carta." (botón desde el
# Cementerio, AbilityButtonPatternsD; source_card es un nodo de solo vista)
# -----------------------------------------------------------------------------
static func cemetery_banish_to_draw_if_fewer_cards(source_card: Node) -> void:
	var main := _main_node()
	if not main or not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var mine: int = PlayerSideScript.hand_cards(main, owner_id).size()
	var theirs: int = PlayerSideScript.hand_cards(main, 1 - owner_id).size()
	if mine >= theirs:
		main._update_debug("%s: necesitas tener menos cartas en la mano que tu oponente (%d contra %d)" % [
			_name(source_card, "Envidia"), mine, theirs])
		return
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	var idx: int = cemetery.find(source_card.card_data)
	if idx < 0:
		return
	var data: Dictionary = CardManager.remove_from_cemetery(owner_id, idx)
	data["esta_oculta"] = false
	CardManager.append_to_exile(owner_id, data)
	await ActionModule.draw(owner_id, 1, _name(source_card, "Envidia"), true)


# -----------------------------------------------------------------------------
# Escarapela Nacional: "Al comienzo de la Vigilia oponente, si no controlas más
# Oros que él puedes ponerlo en juego como si fuera tu Vigilia y no puedes
# poner Oros en juego en tu próximo turno." (GoldManager lo llama al empezar
# cada Vigilia)
# -----------------------------------------------------------------------------
static func on_vigilia_started(active_pid: int) -> void:
	var main := _main_node()
	if not main or not main._gold_manager:
		return
	var pid: int = 1 - active_pid
	var golds := func(p: int) -> int:
		return PlayerSideScript.gold_reserva(main, p).get_child_count() + PlayerSideScript.oro_pagado(main, p).get_child_count()
	if golds.call(pid) > golds.call(active_pid):
		return
	for c in PlayerSideScript.hand_cards(main, pid):
		if not is_instance_valid(c):
			continue
		var t: String = str(c.get("card_ability")).to_lower()
		if not ("al comienzo de la vigilia oponente, si no controlas más oros que él puedes ponerlo en juego" in t
				or "puede ser puesto en juego en la vigilia oponente como si fuera tu vigilia" in t):
			continue
		var use_it: bool = PlayerSideScript.is_bot(pid)
		if not use_it:
			use_it = await SelectionManager.await_two_choice(main, str(c.card_name),
				"Ponerlo en juego ahora (no podrás poner Oros en tu próximo turno)", "No", pid)
		if not use_it or not is_instance_valid(c):
			return
		var data: Dictionary = c.card_data.duplicate()
		PlayerSideScript.remove_from_hand(main, pid, c)
		if is_instance_valid(c):
			CardManager._disconnect_card_interaction_signals(c)
			c.queue_free()
		data["esta_oculta"] = false
		main._gold_manager.block_gold_next_turn(pid)
		await main._gold_manager.put_gold_directly_in_reserva(pid, data)
		return


# -----------------------------------------------------------------------------
# Signo Amarillo: "Puedes convertir este Oro en un Oro sin habilidad para
# cancelar la habilidad de una carta fuera del juego o un Oro." (activada)
# -----------------------------------------------------------------------------
static func _try_signo_amarillo_cancel(card: Node, lower: String, controller_id: int) -> bool:
	if not ("convertir este oro en un oro sin habilidad para cancelar la habilidad de una carta fuera del juego o un oro" in lower):
		return false
	var main := _main_node()
	var obj: Dictionary = StackAnnulScript.find_target(controller_id, false, true, func(o: Dictionary) -> bool:
		if StackAnnulScript.type_of(o) == Constants.CardType.ORO:
			return true
		var node = StackAnnulScript.card_of(o)
		return node == null or not is_instance_valid(node) or not (node.get("current_zone") in Constants.ZONES_IN_PLAY))
	if obj.is_empty():
		if main:
			main._update_debug("Signo Amarillo: no hay habilidad de una carta fuera del juego o de un Oro que cancelar")
		return true
	if is_instance_valid(card):
		card.is_converted = true  # el coste: Oro sin habilidad
	StackAnnulScript.apply(obj, card)
	return true


# -----------------------------------------------------------------------------
# Espada Vikinga: "Puedes pagar un Oro y Desterrar esta carta de tu mano para
# Anular una carta de coste 1." (desde la mano)
# -----------------------------------------------------------------------------
static func _try_hand_banish_to_annul(card: Node, lower: String, controller_id: int) -> bool:
	var m := RegEx.create_from_string("puedes pagar un oro y desterrar esta carta de tu mano para anular una carta de coste (\\w+)").search(lower)
	if not m:
		return false
	var main := _main_node()
	if not main or not main._gold_manager:
		return true
	var cost_n: int = UniversalCardParser._parse_amount(m.get_string(1))
	var obj: Dictionary = StackAnnulScript.find_target(controller_id, true, false, func(o: Dictionary) -> bool:
		return StackAnnulScript.cost_of(o) == cost_n)
	if obj.is_empty():
		main._update_debug("%s: no hay una carta de coste %d en la pila que Anular" % [_name(card, "Espada Vikinga"), cost_n])
		return true
	if not main._gold_manager.puede_pagar(1, -1, "", -1, controller_id):
		main._update_debug("Oro insuficiente (necesitas 1)")
		return true
	await main._gold_manager.pagar_coste(1, -1, "", -1, controller_id)
	if is_instance_valid(card) and card.get("current_zone") == Constants.Zone.MANO:
		var data: Dictionary = card.card_data.duplicate()
		PlayerSideScript.remove_from_hand(main, controller_id, card)
		CardManager._disconnect_card_interaction_signals(card)
		card.queue_free()
		data["esta_oculta"] = false
		CardManager.append_to_exile(controller_id, data)
	StackAnnulScript.apply(obj, null)
	return true


# -----------------------------------------------------------------------------
# El Gran Descenso: "Tu oponente Descarta tres cartas al azar de su mano. Por
# cada carta Descartada de esta forma, tu oponente puede Desterrar cuatro
# cartas del tope de su Castillo para subir esa carta del Cementerio a su
# mano y tú Robas una carta."
# -----------------------------------------------------------------------------
static func _try_gran_descenso(card: Node, lower: String, controller_id: int) -> bool:
	if not ("tu oponente descarta tres cartas al azar de su mano" in lower):
		return false
	var main := _main_node()
	if not main:
		return true
	var opp: int = 1 - controller_id
	var hand: Array = PlayerSideScript.hand_cards(main, opp).filter(func(c): return is_instance_valid(c))
	hand.shuffle()
	var to_discard: Array = hand.slice(0, mini(3, hand.size()))
	if to_discard.is_empty():
		return true
	var datas: Array = to_discard.map(func(c): return c.card_data)
	var res: Dictionary = await ActionModule.discard(opp, to_discard, _name(card, "El Gran Descenso"), true)
	if res.get("prevented", false) or res.get("cancelled", false):
		return true
	for d in datas:
		var deck: Array = CardManager.get_deck(opp)
		if deck.size() < 4:
			break
		var cem: Array = CardManager.get_cemetery(opp)
		var idx: int = cem.find(d)
		if idx < 0:
			continue
		var recover := false
		if PlayerSideScript.is_bot(opp):
			recover = deck.size() > 20
		else:
			recover = await SelectionManager.await_two_choice(main, "El Gran Descenso",
				"Desterrar cuatro del tope de tu Castillo para subir %s a tu mano" % str(d.get("nombre", "la carta")),
				"No", opp)
		if not recover:
			continue
		for i in range(4):
			var top: Dictionary = deck.pop_front()
			top["esta_oculta"] = false
			CardManager.append_to_exile(opp, top)
		var back: Dictionary = CardManager.remove_from_cemetery(opp, CardManager.get_cemetery(opp).find(d))
		if not back.is_empty():
			var node = main._create_card(back, opp != 0)
			if opp == 0:
				main.player_hand.add_card(node)
			else:
				main._opponent_fan.add_card(node)
			main._connect_card_signals(node)
		await ActionModule.draw(controller_id, 1, _name(card, "El Gran Descenso"), true)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


# -----------------------------------------------------------------------------
# Yomiel: "Cuando sea Barajado desde tu mano, puedes buscar un Talismán de
# coste 1 o más en tu Castillo, jugarlo pagando su coste y Barajar una carta
# de tu mano." Lo llaman los efectos que Barajan cartas de la mano
# (players_shuffle_one_from_hand, _shuffle_from_hand).
# -----------------------------------------------------------------------------
static func on_shuffled_from_hand(main: Node, pid: int, data: Dictionary) -> void:
	var text: String = str(data.get("habilidad", "")).to_lower()
	if not ("cuando sea barajado desde tu mano" in text):
		return
	var i: int = text.find("puedes buscar un talismán")
	if i < 0:
		return
	if await TalismanSearchScript.try_execute(null, text.substr(i), pid):
		if "y barajar una carta de tu mano" in text:
			await _shuffle_from_hand(main, pid, 1, str(data.get("nombre", "Yomiel")))


# -----------------------------------------------------------------------------
# Matriz V: "Cuando entra en juego, Roba una carta y hasta dos cartas que
# controles ganan Indesterrable mientras estén en juego." / "Si está en tu
# Reserva, tu oponente no puede disparar habilidades de cartas de coste 0 o 1
# a menos que Destierre una carta de su mano."
# -----------------------------------------------------------------------------
static func _try_matriz_v_enter(card: Node, lower: String, controller_id: int) -> bool:
	if not ("hasta dos cartas que controles ganan indesterrable mientras estén en juego" in lower):
		return false
	var main := _main_node()
	if not main:
		return true
	var title := _name(card, "Matriz V")
	var own: Array = _in_play_cards(main, controller_id)
	for zone in [PlayerSideScript.gold_reserva(main, controller_id), PlayerSideScript.oro_pagado(main, controller_id)]:
		if zone:
			for c in zone.get_children():
				if is_instance_valid(c):
					own.append(c)
	var picked: Array = []
	if not own.is_empty() and main._card_interaction:
		if PlayerSideScript.is_bot(controller_id):
			own.shuffle()
			picked = own.slice(0, 2)
		else:
			picked = await main._card_interaction.await_multi_target(
				"%s: hasta dos cartas que controles ganan Indesterrable (ESC para terminar)" % title,
				own, 2, Callable(), Callable(), true, null, controller_id)
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return true
	await ActionModule.draw(controller_id, 1, title, true)
	for c in picked:
		if is_instance_valid(c):
			KeywordManager.grant_keyword(c, Constants.Keyword.INDESTERRABLE, card, "permanent")
	return true


static func matriz_v_blocks_trigger(card: Node, controller_id: int) -> bool:
	"""true si la habilidad disparada de 'card' no se dispara por Matriz V
	(el controlador eligió no pagar o no pudo)."""
	if not is_instance_valid(card) or int(ContinuousEffectManager.get_modified_cost(card)) > 1:
		return false
	var main := _main_node()
	if not main:
		return false
	var reserva = PlayerSideScript.gold_reserva(main, 1 - controller_id)
	if not reserva:
		return false
	var has_matriz := false
	for c in reserva.get_children():
		if is_instance_valid(c) and c.get("card_ability") != null and not KeywordManager.is_silenced(c) \
				and "no puede disparar habilidades de cartas de coste 0 o 1 a menos que destierre una carta de su mano" \
				in str(c.card_ability).to_lower():
			has_matriz = true
			break
	if not has_matriz:
		return false
	var paid: bool = await banish_from_hand_toll(main, controller_id,
		"Matriz V: Destierra una carta de tu mano para disparar la habilidad de %s (ESC: no dispararla)" % _name(card, "esa carta"))
	if not paid:
		main._update_debug("Matriz V: la habilidad de %s no se dispara" % _name(card, "esa carta"))
	return not paid


static func banish_from_hand_toll(main: Node, payer: int, prompt: String) -> bool:
	"""El jugador elige si Destierra una carta de su mano (peaje). El bot paga
	si tiene 3 cartas o más. true = pagó."""
	var hand: Array = PlayerSideScript.hand_cards(main, payer).filter(func(c): return is_instance_valid(c))
	if hand.is_empty():
		return false
	var paid: Node = null
	if PlayerSideScript.is_bot(payer):
		if hand.size() >= 3:
			paid = hand.pick_random()
	elif main._card_interaction:
		paid = await main._card_interaction.await_target(prompt, func(c: Node) -> bool: return c in hand, true, payer)
	if paid == null or not is_instance_valid(paid):
		return false
	var data: Dictionary = paid.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, payer, paid)
	if is_instance_valid(paid):
		CardManager._disconnect_card_interaction_signals(paid)
		paid.queue_free()
	data["esta_oculta"] = false
	CardManager.append_to_exile(payer, data)
	return true


# -----------------------------------------------------------------------------
# Anular / Cancelar en la pila (StackAnnul). Se llama al principio de la
# cadena de resolución, con el texto COMPLETO de la carta.
# -----------------------------------------------------------------------------
static func try_annul_on_stack(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ")
	var main := _main_node()
	if not main:
		return false
	# Culto a la Muerte: "Elige un efecto: - Anula una carta de coste 2 o
	# menos que no sea Aliado y Destierra esa carta. - Cancela la habilidad
	# de una carta y tu oponente no puede utilizar más habilidades de cartas
	# con ese nombre este turno."
	if "anula una carta de coste 2 o menos que no sea aliado y destierra esa carta" in lower:
		return await _culto_a_la_muerte(card, controller_id)
	if "elige un efecto" in lower:
		return false
	# Visión de Enoc: "Anula un Talismán de coste 2 o menos o prevén que un
	# Aliado sea afectado por un efecto oponente."
	if "o prevén que un aliado sea afectado por un efecto oponente" in lower:
		return await _vision_de_enoc(card, lower, controller_id)
	# Primera oración que empieza con Anula/Cancela (saltando "Única.",
	# "Cuando lo juegues, Destiérralo.", "No puede ser Anulado.").
	var sentence := ""
	for raw in lower.split("."):
		var s: String = raw.strip_edges()
		if s.begins_with("anula") or s.begins_with("cancela"):
			sentence = s
			break
	if sentence.is_empty() or " o prevén" in sentence:
		return false
	var res: Dictionary = StackAnnulScript.try_from_text(card, sentence, controller_id)
	if res.is_empty():
		main._update_debug("%s: no hay nada en la pila que pueda Anular o Cancelar" % _name(card, "Anular"))
		return true
	var obj: Dictionary = res.obj
	if not res.applied:
		return true
	var target_cost: int = StackAnnulScript.cost_of(obj)
	var node = StackAnnulScript.card_of(obj)
	# Red de Plata: "Si tenía coste 2 o menos, Destierra ese Aliado."
	var m := RegEx.create_from_string("si tenía coste (\\w+) o menos, destierra ese aliado").search(lower)
	if m and target_cost <= UniversalCardParser._parse_amount(m.get_string(1)) and node != null and is_instance_valid(node):
		if StackAnnulScript.is_card_play(obj):
			node.set_meta("annul_to_exile", true)
		elif node.get("current_zone") in Constants.ZONES_IN_PLAY and node.get("card_type") == Constants.CardType.ALIADO:
			await ActionModule.banish([node], card, true)
	# Envidia: "Juega esa carta bajo tu control sin pagar su coste."
	if "juega esa carta bajo tu control sin pagar su coste" in lower and StackAnnulScript.is_card_play(obj):
		await _play_annulled_under_control(main, obj, controller_id)
	# Dragón Dorado: "Luego, Baraja tantas cartas de tu mano como coste tenga."
	if "luego, baraja tantas cartas de tu mano como coste tenga" in lower and StackAnnulScript.is_card_play(obj):
		await _shuffle_from_hand(main, controller_id, target_cost, _name(card, "Dragón Dorado"))
	return true


static func _play_annulled_under_control(main: Node, obj: Dictionary, controller_id: int) -> void:
	"""Envidia (2026-10-14): espera a que la carta Anulada llegue al
	Cementerio de su dueño y la juega bajo tu control sin pagar su coste
	(sigue siendo de su dueño). Si es un Talismán, elige objetivos de nuevo
	al resolverse."""
	var owner_id: int = int(obj.get("context", {}).get("controller_id", 1 - controller_id))
	var data: Dictionary = StackAnnulScript.data_of(obj)
	var card_name: String = str(data.get("nombre", ""))
	# La pila lo maneja cuando vuelve a tocarle: hasta ~6 s.
	for i in range(60):
		if not ActionPipeline.get_stack().has(obj):
			break
		await main.get_tree().create_timer(0.1).timeout
	await main.get_tree().create_timer(0.3).timeout
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	for i in range(cemetery.size() - 1, -1, -1):
		if str(cemetery[i].get("nombre", "")) == card_name:
			var found: Dictionary = cemetery[i]
			CardManager.remove_from_cemetery(owner_id, i)
			found["esta_oculta"] = false
			await main._gold_manager.play_found_card(found, owner_id, controller_id, 99, true)
			return
	main._update_debug("Envidia: %s no llegó al Cementerio, no se puede jugar" % card_name)


static func _vision_de_enoc(card: Node, lower: String, controller_id: int) -> bool:
	var main := _main_node()
	var title := _name(card, "Visión de Enoc")
	var m := RegEx.create_from_string("anula un talismán de coste (\\w+) o menos").search(lower)
	var max_cost: int = UniversalCardParser._parse_amount(m.get_string(1)) if m else 2
	var obj: Dictionary = StackAnnulScript.find_target(controller_id, true, false, func(o: Dictionary) -> bool:
		return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN and StackAnnulScript.cost_of(o) <= max_cost)
	var own_allies: Array = _in_play_cards(main, controller_id).filter(
		func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var annul_it: bool = not obj.is_empty()
	if not obj.is_empty() and not own_allies.is_empty():
		annul_it = await SelectionManager.await_two_choice(main, title,
			"Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "el Talismán")),
			"Prevenir que un Aliado tuyo sea afectado", controller_id)
	if annul_it:
		StackAnnulScript.apply(obj, card)
		return true
	if own_allies.is_empty() or not main._card_interaction:
		main._update_debug("%s: no hay nada que Anular ni Aliados que proteger" % title)
		return true
	var ally: Node = await main._card_interaction.await_target(
		"%s: elige un Aliado tuyo: el próximo efecto oponente no lo afecta" % title,
		func(c: Node) -> bool: return c in own_allies, true, controller_id)
	if ally and is_instance_valid(ally):
		EffectController.add_legacy_targeted_prevention(ally, 1)
	return true


static func _culto_a_la_muerte(card: Node, controller_id: int) -> bool:
	var main := _main_node()
	var annul_obj: Dictionary = StackAnnulScript.find_target(controller_id, true, false, func(obj: Dictionary) -> bool:
		return StackAnnulScript.type_of(obj) != Constants.CardType.ALIADO and StackAnnulScript.cost_of(obj) <= 2)
	var cancel_obj: Dictionary = StackAnnulScript.find_target(controller_id, false, true)
	var title := _name(card, "Culto a la Muerte")
	var use_annul: bool = not annul_obj.is_empty()
	if not annul_obj.is_empty() and not cancel_obj.is_empty():
		use_annul = await SelectionManager.await_two_choice(main, title,
			"Anular y Desterrar %s" % str(StackAnnulScript.data_of(annul_obj).get("nombre", "la carta")),
			"Cancelar la habilidad de %s" % str(StackAnnulScript.data_of(cancel_obj).get("nombre", "la carta")),
			controller_id)
	elif annul_obj.is_empty() and cancel_obj.is_empty():
		main._update_debug("%s: no hay nada en la pila que pueda Anular o Cancelar" % title)
		return true
	if use_annul:
		if StackAnnulScript.apply(annul_obj, card):
			var node = StackAnnulScript.card_of(annul_obj)
			if node != null and is_instance_valid(node):
				node.set_meta("annul_to_exile", true)
	else:
		if StackAnnulScript.apply(cancel_obj, card):
			var src_name: String = str(StackAnnulScript.data_of(cancel_obj).get("nombre", ""))
			if not src_name.is_empty():
				KeywordManager.lock_name_this_turn(src_name, int(cancel_obj.get("context", {}).get("controller_id", 1 - controller_id)))
	return true


static func _shuffle_from_hand(main: Node, controller_id: int, amount: int, title: String) -> void:
	"""Baraja 'amount' cartas de tu mano (todas o nada, como antes)."""
	var hand: Array = PlayerSideScript.hand_cards(main, controller_id).filter(func(c): return is_instance_valid(c))
	amount = mini(amount, hand.size())
	if amount <= 0 or not main._card_interaction:
		return
	var picked: Array = []
	if PlayerSideScript.is_bot(controller_id):
		hand.shuffle()
		picked = hand.slice(0, amount)
	else:
		picked = await main._card_interaction.await_multi_target(
			"%s: Baraja %d carta(s) de tu mano" % [title, amount], hand, amount, Callable(), Callable(), false, null, controller_id)
	var shuffled: Array = []
	for node in picked:
		if not is_instance_valid(node):
			continue
		var data: Dictionary = node.card_data.duplicate()
		shuffled.append(data)
		data["esta_oculta"] = true
		PlayerSideScript.remove_from_hand(main, controller_id, node)
		if is_instance_valid(node):
			CardManager._disconnect_card_interaction_signals(node)
			node.queue_free()
		CardManager.get_deck(controller_id).append(data)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)
	for d in shuffled:
		await on_shuffled_from_hand(main, controller_id, d)


# -----------------------------------------------------------------------------
# Comunes
# -----------------------------------------------------------------------------
static func players_shuffle_one_from_hand(main: Node, controller_id: int, title: String) -> void:
	"""'Los jugadores Barajan una carta de su mano': cada uno elige una de su
	propia mano y va a su Castillo (barajado). El bot elige al azar. Fisión
	Nuclear: el rival protegido no lo hace (afecta su mano)."""
	for pid in [controller_id, 1 - controller_id]:
		if pid != controller_id and EffectController.fision_hides_zones_of(pid, controller_id, Constants.Zone.MANO):
			continue
		var hand: Array = PlayerSideScript.hand_cards(main, pid).filter(func(c): return is_instance_valid(c))
		if hand.is_empty():
			continue
		var chosen: Node = null
		if PlayerSideScript.is_bot(pid) or not main._card_interaction:
			chosen = hand.pick_random()
		else:
			chosen = await main._card_interaction.await_target(
				"%s: Baraja una carta de tu mano en tu Castillo" % title,
				func(c: Node) -> bool: return c in hand, false, pid)
		if not chosen or not is_instance_valid(chosen):
			chosen = hand[0]
		var data: Dictionary = chosen.card_data.duplicate()
		data["esta_oculta"] = true
		PlayerSideScript.remove_from_hand(main, pid, chosen)
		if is_instance_valid(chosen):
			CardManager._disconnect_card_interaction_signals(chosen)
			chosen.queue_free()
		CardManager.get_deck(pid).append(data)
		CardManager.shuffle_deck(pid)
		AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % title)
		await on_shuffled_from_hand(main, pid, data)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _name(card: Node, fallback: String) -> String:
	return str(card.get("card_name")) if is_instance_valid(card) and card.get("card_name") != null else fallback


static func _in_play_cards(main: Node, pid: int) -> Array:
	var out: Array = []
	for field in PlayerSideScript.line_containers(main, pid):
		if not field:
			continue
		for c in field.get_children():
			if not is_instance_valid(c):
				continue
			out.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w):
						out.append(w)
	return out


# -----------------------------------------------------------------------------
# Rey de los Loñolicos: "Cuando entra en juego, el próximo Talismán que juegues
# este turno reduce su coste en un Oro, hasta un mínimo de 1 y no puede ser
# Anulado. Roba una carta y los jugadores Barajan una carta de su mano."
# -----------------------------------------------------------------------------
static func _try_rey_lonolicos(card: Node, lower: String, controller_id: int) -> bool:
	if not ("el próximo talismán que juegues este turno reduce su coste en un oro" in lower):
		return false
	var main := _main_node()
	if not main or not main._gold_manager:
		return true
	if await TriggerSystem.open_response_window(card, _name(card, "Rey de los Loñolicos"), controller_id):
		return true
	main._gold_manager.buff_next_talisman(controller_id, 1, false, "no puede ser anulado" in lower)
	await ActionModule.draw(controller_id, 1, _name(card, "Rey de los Loñolicos"), true)
	if "los jugadores barajan una carta de su mano" in lower:
		await players_shuffle_one_from_hand(main, controller_id, _name(card, "Rey de los Loñolicos"))
	return true


# -----------------------------------------------------------------------------
# Ursitoare: "Cuando entra en juego, puedes Barajar un Aliado que controles y
# una carta oponente de igual o menor coste. Roba dos cartas y los jugadores
# Barajan una carta de su mano."
# -----------------------------------------------------------------------------
static func _try_ursitoare(card: Node, lower: String, controller_id: int) -> bool:
	if not ("puedes barajar un aliado que controles y una carta oponente de igual o menor coste" in lower):
		return false
	var main := _main_node()
	if not main:
		return true
	var title := _name(card, "Ursitoare")
	var own_allies: Array = _in_play_cards(main, controller_id).filter(
		func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var mine: Node = null
	var theirs: Node = null
	if not own_allies.is_empty() and main._card_interaction and not PlayerSideScript.is_bot(controller_id):
		mine = await main._card_interaction.await_target(
			"%s: elige un Aliado que controles para Barajar (ESC: no barajar)" % title,
			func(c: Node) -> bool: return c in own_allies, true, controller_id)
		if mine and is_instance_valid(mine):
			var max_cost: int = int(ContinuousEffectManager.get_modified_cost(mine))
			var opp_cards: Array = _in_play_cards(main, 1 - controller_id).filter(
				func(c): return int(ContinuousEffectManager.get_modified_cost(c)) <= max_cost)
			if opp_cards.is_empty():
				mine = null  # "y": sin carta oponente válida no se baraja ninguna
			else:
				theirs = await main._card_interaction.await_target(
					"%s: elige una carta oponente de coste %d o menos" % [title, max_cost],
					func(c: Node) -> bool: return c in opp_cards, true, controller_id)
				if not theirs or not is_instance_valid(theirs):
					mine = null
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return true
	for target in [mine, theirs]:
		if target and is_instance_valid(target):
			var owner_id: int = target.owner_id if target.get("owner_id") != null else controller_id
			if await ActionModule.return_to_deck(target, owner_id, true, card):
				CardManager.shuffle_deck(owner_id)
	await ActionModule.draw(controller_id, 2, title, true)
	if "los jugadores barajan una carta de su mano" in lower:
		await players_shuffle_one_from_hand(main, controller_id, title)
	return true


# -----------------------------------------------------------------------------
# Nyssara Cautiva: "En tu Vigilia, Una vez por turno, tu oponente Bota una
# carta por cada Aliado que controles."
# -----------------------------------------------------------------------------
static func _try_mill_per_ally(card: Node, lower: String, controller_id: int) -> bool:
	if not ("tu oponente bota una carta por cada aliado que controles" in lower):
		return false
	var main := _main_node()
	if not main:
		return true
	var allies: int = _in_play_cards(main, controller_id).filter(
		func(c): return c.get("card_type") == Constants.CardType.ALIADO).size()
	if allies > 0:
		await ActionModule.mill(1 - controller_id, allies, false, _name(card, "Nyssara Cautiva"), true)
	return true
