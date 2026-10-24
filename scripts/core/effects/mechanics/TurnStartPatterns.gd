extends RefCounted
## TurnStartPatterns — Comienzo del turno, Agrupación y Ataque: la esmeralda, el Oro de Ángel Redentor,
## Carcosa, kamidana, Medalla de Santa Muerte, ambrosio ohiggins.
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")


static func on_turn_start() -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	_agrupacion_gold()
	for pid in [GameManager.active_player_id, 1 - GameManager.active_player_id]:
		var weapons: Array = CardQuery.weapons_in_play(pid)
		for w in weapons:
			if not is_instance_valid(w) or KeywordManager.is_silenced(w):
				continue
			if not ("al comienzo de cada turno, tu oponente baraja una carta de su mano" in CardQuery.ability_of(w)):
				continue
			var title: String = str(w.get("card_name"))
			if await TriggerSystem.open_response_window(w, title, pid):
				continue
			await load("res://scripts/core/effects/triggers/Deck170Patterns.gd")._shuffle_from_hand(main, 1 - pid, 1, title)
			if "si controlas otra arma, roba dos cartas" in CardQuery.ability_of(w) and CardQuery.weapons_in_play(pid).size() > 1:
				await ActionModule.draw(pid, 2, title, true)


## "En la Agrupación, genera un Oro por el turno." (Ángel Redentor) — en
## cada Agrupación, la tuya y la del oponente (sin "tu", regla del usuario).
static func _agrupacion_gold() -> void:
	var main := CardQuery.main_node()
	if not main or not main._gold_manager:
		return
	for pid in [0, 1]:
		for c in CardQuery.cards_in_play_with(pid, "en la agrupación, genera un oro por el turno"):
			main._gold_manager.generar_oros_virtuales(1, pid)
			main._update_debug("%s: genera un Oro por el turno" % str(c.get("card_name")))


# -----------------------------------------------------------------------------
# kamidana: "Al comienzo del turno de cada jugador, si no jugó Aliados en su
# turno anterior, ese jugador Bota cuatro cartas." "Ese jugador" = el del turno
# que empieza; en su primer turno no hay turno anterior.
# -----------------------------------------------------------------------------
const KAMIDANA_TEXT := "si no jugó aliados en su turno anterior, ese jugador bota cuatro cartas"


static func kamidana(card: Node, _controller_id: int) -> void:
	var pid: int = GameManager.active_player_id
	if GameManager.turn_serial < 3 or TurnManager.played_ally_in_previous_turn(pid):
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "kamidana"
	await ActionModule.mill(pid, 4, false, title, true)


# -----------------------------------------------------------------------------
# Medalla de Santa Muerte: "Al comienzo del turno, puedes Descartar una carta
# para nombrar una carta que no sea Oro. Las cartas con ese nombre no tienen
# habilidad por el turno." Las de los dos jugadores (KeywordManager.
# lock_name_this_turn con -1). El bot nombra una carta rival en juego.
# -----------------------------------------------------------------------------
const MEDALLA_TEXT := "puedes descartar una carta para nombrar una carta que no sea oro"


static func medalla(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Medalla de Santa Muerte"
	var hand: Array = PlayerSideScript.hand_cards(main, controller_id).filter(func(c): return is_instance_valid(c))
	if hand.is_empty():
		return
	var named := ""
	var to_discard: Array = []
	if PlayerSideScript.is_bot(controller_id):
		var rivals: Array = []
		for line in PlayerSideScript.line_containers(main, 1 - controller_id):
			for c in line.get_children():
				if is_instance_valid(c) and c.get("card_type") != Constants.CardType.ORO \
						and not KeywordManager.is_silenced(c):
					rivals.append(c)
		if rivals.is_empty():
			return
		rivals.sort_custom(func(a, b): return int(a.get("card_cost")) > int(b.get("card_cost")))
		named = str(rivals[0].get("card_name"))
		hand.sort_custom(func(a, b): return int(a.get("card_cost")) < int(b.get("card_cost")))
		to_discard = [hand[0]]
	else:
		if not await SelectionManager.await_two_choice(main, title,
				"Descartar una carta para nombrar una carta", "No usarla", controller_id):
			return
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"Nombra una carta que no sea Oro: no tendrá habilidad por el turno", controller_id)
		if picked.is_empty():
			return
		if int(picked.get("tipo", -1)) == Constants.CardType.ORO:
			main._update_debug("%s: no puedes nombrar un Oro" % title)
			return
		named = str(picked.get("nombre", ""))
		to_discard = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, 1, controller_id)
	if named.is_empty() or to_discard.is_empty():
		return
	# Descartar abre la ventana de respuesta del efecto (una sola, §59), ya con el nombre declarado.
	var paid: Dictionary = await ActionModule.discard(controller_id, to_discard, "coste", true)
	if paid.get("cancelled", false) or paid.get("prevented", false):
		return
	KeywordManager.lock_name_this_turn(named, -1)
	main._update_debug("%s: las cartas llamadas '%s' no tienen habilidad por el turno" % [title, named])


# -----------------------------------------------------------------------------
# ambrosio ohiggins: "Al comienzo del Ataque, puedes Desterrarlo de tu mano o
# Cementerio para que un Aliado no pueda ser declarado atacante este turno."
# No es un disparador en juego (on_ataque_start se resuelve después de declarar
# los atacantes): PhaseFlowController lo ofrece al entrar al Ataque, antes de
# declarar. Primero el defensor; el bot lo usa solo como defensor. Se paga desde
# el Cementerio si está ahí (la mano vale más).
# -----------------------------------------------------------------------------
const AMBROSIO_TEXT := "puedes desterrarlo de tu mano o cementerio para que un aliado no pueda ser declarado atacante"


static func ambrosio_on_ataque_start() -> void:
	var main := CardQuery.main_node()
	if not main or not GameManager.is_game_active:
		return
	var attacker_id: int = GameManager.active_player_id
	for pid in [1 - attacker_id, attacker_id]:
		var candidates: Array = []
		for line in PlayerSideScript.ally_containers(main, attacker_id):
			for a in line.get_children():
				if is_instance_valid(a) and a.get("card_type") == Constants.CardType.ALIADO \
						and CardQuery.controller_of(a) == attacker_id and TurnManager.can_attack(a).can_attack:
					candidates.append(a)
		if candidates.is_empty():
			return
		await _ambrosio_offer(main, pid, candidates)


static func _ambrosio_offer(main: Node, pid: int, candidates: Array) -> void:
	var from_cemetery: Dictionary = {}
	for d in CardManager.get_cemetery(pid):
		if AMBROSIO_TEXT in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))) \
				and not CardManager.is_cemetery_card_silenced(d) and not KeywordManager.is_name_locked(str(d.get("nombre", ""))):
			from_cemetery = d
			break
	var from_hand: Node = null
	if from_cemetery.is_empty():
		for c in PlayerSideScript.hand_cards(main, pid):
			if is_instance_valid(c) and AMBROSIO_TEXT in CemeteryTriggersScript.normalize(str(c.get("card_ability"))) \
					and not KeywordManager.is_silenced(c):
				from_hand = c
				break
	if from_cemetery.is_empty() and from_hand == null:
		return
	var data: Dictionary = from_cemetery if not from_cemetery.is_empty() else from_hand.card_data
	var title: String = str(data.get("nombre", "ambrosio ohiggins"))
	var target: Node = null
	if PlayerSideScript.is_bot(pid):
		if pid == GameManager.active_player_id:
			return
		candidates.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) \
			> ContinuousEffectManager.get_modified_strength(b))
		target = candidates[0]
	else:
		var where := "tu Cementerio" if not from_cemetery.is_empty() else "tu mano"
		if not await SelectionManager.await_two_choice(main, "%s: comienzo del Ataque" % title,
				"Desterrarlo de %s para que un Aliado no pueda atacar" % where, "No usarlo", pid):
			return
		target = await PlayerSideScript.pick_in_play(main, pid,
			"%s: elige un Aliado que no podrá ser declarado atacante este turno" % title,
			func(c: Node) -> bool: return c in candidates, true)
	if not is_instance_valid(target):
		return
	# Coste: Desterrarlo (antes de la ventana).
	if not from_cemetery.is_empty():
		var idx: int = CardManager.get_cemetery(pid).find(from_cemetery)
		if idx < 0:
			return
		var removed: Dictionary = CardManager.remove_from_cemetery(pid, idx)
		removed["esta_oculta"] = false
		CardManager.append_to_exile(pid, removed)
	else:
		var hand_data: Dictionary = PlayerSideScript.take_from_hand(main, pid, from_hand)
		if hand_data.is_empty():
			return
		CardManager.add_to_exile(pid, hand_data)
	# Ventana de respuesta del rival con una carta temporal (la real ya está en el Destierro).
	var proxy: Node = main._create_card(data, false)
	proxy.visible = false
	main.add_child(proxy)
	proxy.owner_id = pid
	proxy.current_zone = Constants.Zone.DESTIERRO
	var cancelled: bool = await TriggerSystem.open_response_window(proxy, title, pid)
	proxy.queue_free()
	if cancelled or not is_instance_valid(target):
		return
	target.set_meta("no_attack_turn", GameManager.turn_serial)
	main._update_debug("%s: %s no puede ser declarado atacante este turno" % [title, str(target.get("card_name"))])


# -----------------------------------------------------------------------------
# Carcosa: "Cuando entra en juego y al comienzo del turno oponente, Destierra
# una carta que no sea Oro o mira la mano de tu oponente y Destierra un
# Talismán de ahí. Roba una carta."
# -----------------------------------------------------------------------------
static func carcosa(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Carcosa"
	var opponent_id: int = 1 - controller_id
	var in_play_filter := func(c: Node) -> bool:
		return c.get("current_zone") in Constants.ZONES_IN_PLAY and c.get("card_type") != Constants.CardType.ORO
	var look_hand: bool = false
	if PlayerSideScript.is_bot(controller_id):
		look_hand = PlayerSideScript.hand_cards(main, opponent_id).any(func(c):
			return is_instance_valid(c) and c.get("card_type") == Constants.CardType.TALISMAN)
	else:
		look_hand = not await SelectionManager.await_two_choice(main, title,
			"Desterrar una carta en juego que no sea Oro", "Mirar la mano de tu oponente y Desterrar un Talismán", controller_id)
	var target: Node = null
	if not look_hand:
		target = await PlayerSideScript.pick_in_play(main, controller_id,
			"%s: Destierra una carta en juego que no sea Oro" % title, in_play_filter, true, [opponent_id])
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	if look_hand:
		var hidden: bool = EffectController.fision_hides_zones_of(opponent_id, controller_id, Constants.Zone.MANO) \
			or await EffectController.offer_colapso_global(controller_id)
		var hand: Array = [] if hidden else PlayerSideScript.hand_cards(main, opponent_id).filter(func(c): return is_instance_valid(c))
		if not hand.is_empty():
			if not PlayerSideScript.is_bot(controller_id):
				SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % title, controller_id)
			var talismans: Array = hand.filter(func(c): return c.get("card_type") == Constants.CardType.TALISMAN)
			if not talismans.is_empty():
				var idx := 0
				if not PlayerSideScript.is_bot(controller_id) and talismans.size() > 1:
					idx = await SelectionManager.await_choice(main, "%s: Destierra un Talismán de su mano" % title,
						talismans.map(func(c): return str(c.get("card_name"))), controller_id)
				var chosen: Node = talismans[clampi(idx, 0, talismans.size() - 1)]
				var data: Dictionary = PlayerSideScript.take_from_hand(main, opponent_id, chosen)
				CardManager.add_to_exile(opponent_id, data)
				main._update_debug("%s: Destierra %s de la mano de tu oponente" % [title, str(data.get("nombre", ""))])
	elif target and is_instance_valid(target):
		await ActionModule.banish([target], card)
	await ActionModule.draw(controller_id, 1, title, true)
