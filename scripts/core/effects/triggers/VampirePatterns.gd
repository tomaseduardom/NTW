extends RefCounted
## Vlad el Empalador y Dhampir (2026-10-17, a pedido del usuario). Se usa con
## preload.
##
## Vlad el Empalador:
##   "Cuando entra en juego o ataca, muestra cartas del tope de tu Castillo
##   hasta mostrar un Aliado de coste 1 y juégalo sin pagar su coste."
##   "Una vez en tu turno, cuando este u otro de tus Aliados salga del juego,
##   Baraja hasta una carta de coste 3 o menos y tu oponente Bota tres
##   cartas." — disparada (on_card_left_play), no un botón.
## Dhampir:
##   "Cuando ataca, entra o sale del juego, muestra un Aliado de tu mano y
##   Destierra hasta una carta de coste 3 o menos o Roba dos cartas."
##   "Cuando tu oponente juegue una carta, hasta tres veces por turno, él Bota
##   dos cartas. Si es tu turno, en vez de eso las Destierra." (on_card_played)

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const VLAD_REVEAL := "hasta mostrar un aliado de coste 1 y juégalo sin pagar su coste"
const VLAD_LEAVE := "cuando este u otro de tus aliados salga del juego, baraja hasta una carta de coste 3 o menos y tu oponente bota tres cartas"
const DHAMPIR_SHOW := "muestra un aliado de tu mano y destierra hasta una carta de coste 3 o menos o roba dos cartas"
const DHAMPIR_PLAY := "cuando tu oponente juegue una carta, hasta tres veces por turno, él bota dos cartas"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func _is_logic_side() -> bool:
	return NetworkClient.room_code == "" or NetworkClient.is_host


static func _name(c, fallback: String) -> String:
	return str(c.get("card_name")) if c != null and is_instance_valid(c) and c.get("card_name") != null else fallback


static func _in_play_non_gold_max_cost(max_cost: int) -> Callable:
	return func(c: Node) -> bool:
		return c.get("card_type") != Constants.CardType.ORO and c.get("current_zone") in Constants.ZONES_IN_PLAY \
			and int(ContinuousEffectManager.get_modified_cost(c)) <= max_cost


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var lower := text.to_lower().replace("\n", " ")
	if VLAD_REVEAL in lower:
		await _vlad_reveal_and_play(card, controller_id)
		return true
	if DHAMPIR_SHOW in lower:
		await _dhampir_show(card, controller_id)
		return true
	return false


# -----------------------------------------------------------------------------
# Vlad el Empalador
# -----------------------------------------------------------------------------
static func _vlad_reveal_and_play(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main or not main._gold_manager:
		return
	if await TriggerSystem.open_response_window(card, _name(card, "Vlad el Empalador"), controller_id):
		return
	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found: Dictionary = {}
	while not deck.is_empty():
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		if int(top.get("tipo", -1)) == Constants.CardType.ALIADO and int(top.get("coste", -1)) == 1:
			found = top
			break
	if not revealed.is_empty():
		SelectionManager.open_reveal(revealed.duplicate(), "%s: cartas mostradas" % _name(card, "Vlad el Empalador"), controller_id)
	if not found.is_empty():
		revealed.erase(found)
	# Las demás vuelven al Castillo y se Baraja (mismo criterio que el resto de
	# "muestra hasta mostrar").
	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if found.is_empty():
		main._update_debug("%s: no había Aliados de coste 1 en tu Castillo" % _name(card, "Vlad el Empalador"))
		return
	await main._gold_manager.play_card_for_free(found, controller_id)


static func on_card_left_play(_pid: int, left) -> void:  # sin tipo: puede llegar liberada
	if left == null or not is_instance_valid(left) or left.get("card_type") != Constants.CardType.ALIADO:
		return
	if not _is_logic_side() or not GameManager.is_game_active:
		return
	var ctrl: int = int(left.controller_id) if left.get("controller_id") != null else 0
	if GameManager.active_player_id != ctrl:
		return  # "Una vez en tu turno"
	var main := _main_node()
	if not main:
		return
	var vlads: Array = []
	if VLAD_LEAVE in str(left.get("card_ability")).to_lower():
		vlads.append(left)
	for container in PlayerSideScript.line_containers(main, ctrl):
		for c in container.get_children():
			if is_instance_valid(c) and c != left and VLAD_LEAVE in str(c.get("card_ability")).to_lower() \
					and not KeywordManager.is_silenced(c):
				vlads.append(c)
	for v in vlads:
		var key := "vlad_leave:%d" % v.get_instance_id()
		if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.current_turn):
			continue
		UniversalCardParser.turn_registry.register(key, 0, GameManager.current_turn)
		await _vlad_leave_effect(main, v, ctrl)


static func _vlad_leave_effect(main: Node, vlad, ctrl: int) -> void:
	var vlad_name: String = _name(vlad, "Vlad el Empalador")
	var source: Node = vlad if is_instance_valid(vlad) else null
	var target: Node = null
	var filter := _in_play_non_gold_max_cost(3)
	if PlayerSideScript.is_bot(ctrl):
		for container in PlayerSideScript.line_containers(main, 1 - ctrl):
			for c in container.get_children():
				if is_instance_valid(c) and filter.call(c):
					target = c
					break
			if target:
				break
	elif main._card_interaction:
		target = await main._card_interaction.await_target(
			"%s: Baraja hasta una carta de coste 3 o menos (N: ninguna)" % vlad_name, filter, true, ctrl)
	if target and is_instance_valid(target):
		var owner_id: int = target.owner_id if target.get("owner_id") != null else 1 - ctrl
		if await ActionModule.return_to_deck(target, owner_id, true, source):
			CardManager.shuffle_deck(owner_id)
	await ActionModule.mill(1 - ctrl, 3, false, vlad_name)
	main._update_debug("%s: tu oponente Bota tres cartas" % vlad_name)


# -----------------------------------------------------------------------------
# Dhampir
# -----------------------------------------------------------------------------
static func _dhampir_show(card: Node, controller_id: int) -> void:
	var main := _main_node()
	if not main:
		return
	var card_name := _name(card, "Dhampir")
	var hand_allies: Array = PlayerSideScript.hand_cards(main, controller_id).filter(func(c):
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	if hand_allies.is_empty():
		main._update_debug("%s: no tienes un Aliado en tu mano para mostrar" % card_name)
		return
	var bot: bool = PlayerSideScript.is_bot(controller_id)
	var shown: Node = hand_allies[0] if bot else null
	if not bot and main._card_interaction:
		shown = await main._card_interaction.await_target("%s: muestra un Aliado de tu mano (N: no usar la habilidad)" % card_name,
			func(c: Node) -> bool: return c in hand_allies, true, controller_id)
	if not shown or not is_instance_valid(shown):
		return
	main._update_debug("%s: muestra %s" % [card_name, _name(shown, "un Aliado")])
	if bot:
		await ActionModule.draw(controller_id, 2, card_name, true)
		return
	var filter := _in_play_non_gold_max_cost(3)
	var pick: Dictionary = await main._card_interaction.await_target_or_castillo_pick(
		"%s: Destierra hasta una carta de coste 3 o menos, o clic en tu Castillo para Robar dos (N: nada)" % card_name,
		filter, "Robar dos cartas", true, true, controller_id)
	match str(pick.get("type", "none")):
		"card":
			if is_instance_valid(pick.card):
				await ActionModule.banish([pick.card], card)
		"castillo":
			await ActionModule.draw(controller_id, 2, card_name, true)


static func on_card_played(played: Node, player_id: int) -> void:
	"""GoldManager._trigger_enter_play() lo llama con cada carta jugada que no
	es Oro (los Oros se ponen en juego, no se juegan)."""
	if not is_instance_valid(played) or played.get("card_type") == Constants.CardType.ORO:
		return
	if not _is_logic_side() or not GameManager.is_game_active:
		return
	var main := _main_node()
	if not main:
		return
	var dhampir_ctrl: int = 1 - player_id
	for container in PlayerSideScript.line_containers(main, dhampir_ctrl):
		for c in container.get_children():
			if not is_instance_valid(c) or c == played or KeywordManager.is_silenced(c):
				continue
			if not (DHAMPIR_PLAY in str(c.get("card_ability")).to_lower()):
				continue
			var used := 0
			while used < 3 and UniversalCardParser.turn_registry.was_used("dhampir:%d" % c.get_instance_id(), used, GameManager.current_turn):
				used += 1
			if used >= 3:
				continue
			UniversalCardParser.turn_registry.register("dhampir:%d" % c.get_instance_id(), used, GameManager.current_turn)
			var to_exile: bool = GameManager.active_player_id == dhampir_ctrl
			await ActionModule.mill(player_id, 2, to_exile, _name(c, "Dhampir"))
			main._update_debug("%s: tu oponente %s dos cartas" % [_name(c, "Dhampir"), "Destierra" if to_exile else "Bota"])
