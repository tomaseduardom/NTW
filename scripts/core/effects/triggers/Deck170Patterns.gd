extends RefCounted
## Deck170Patterns — efectos que faltaban del mazo 170 (Talisman - Control),
## 2026-10-14, ver docs/revision-mazo-170.md. Cada patrón reconoce su propio
## texto; try_execute() los prueba en orden. Se usa con preload (ver §54).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")


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
	return false


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
	# Dragón Dorado: "Luego, Baraja tantas cartas de tu mano como coste tenga."
	if "luego, baraja tantas cartas de tu mano como coste tenga" in lower and StackAnnulScript.is_card_play(obj):
		await _shuffle_from_hand(main, controller_id, target_cost, _name(card, "Dragón Dorado"))
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
	for node in picked:
		if not is_instance_valid(node):
			continue
		var data: Dictionary = node.card_data.duplicate()
		data["esta_oculta"] = true
		PlayerSideScript.remove_from_hand(main, controller_id, node)
		if is_instance_valid(node):
			CardManager._disconnect_card_interaction_signals(node)
			node.queue_free()
		CardManager.get_deck(controller_id).append(data)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)


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
