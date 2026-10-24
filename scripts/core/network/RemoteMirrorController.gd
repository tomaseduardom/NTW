class_name RemoteMirrorController
extends "res://scripts/core/network/RemoteMirrorControllerPrompts.gd"
## RemoteMirrorController — familia Mensajes (ver RemoteMirrorControllerBase.gd para la cabecera, constantes y ayudas).


func skip_optional() -> bool:
	"""Tecla N en el Remoto: no hacer la acción opcional o terminar la
	selección múltiple con lo ya marcado. false si no hay nada que saltar."""
	if not _skip_action.is_valid():
		return false
	var action: Callable = _skip_action
	_skip_action = Callable()
	action.call()
	return true


func setup(main: Node) -> void:
	_main = main
	_active = NetworkClient.room_code != "" and not NetworkClient.is_host
	# El historial del Remoto es el del Anfitrión (op "log"); CombatLog es autoload: se reinicia en
	# cada partida.
	CombatLog.remote_mirror = _active
	if not _active:
		return
	NetworkClient.message_received.connect(_on_message)


func _on_message(data: Dictionary) -> void:
	if Constants.VERBOSE_DIAG_LOGS:
		print("[RemoteMirrorController] Mensaje recibido: op=%s kind=%s" % [
			str(data.get("op", "")), str(data.get("kind", ""))
		])
	match data.get("op", ""):
		"prompt":
			_close_current_overlay()
			_clear_remote_paso()
			_clear_hand_actions()
			_clear_attack_candidates()
			_clear_board_blocking()
			_clear_board_pick()
			# Cualquier prompt real tapa la pantalla "ESPERANDO JUGADOR" del duelo de dados; si no, el
			# diálogo quedaba debajo de esa capa y el Remoto no podía responder.
			var loading_overlay := _main.get_node_or_null("/root/MatchLoadingOverlay")
			if loading_overlay:
				loading_overlay.hide_loading()
			match data.get("kind", ""):
				"mulligan":
					_show_mulligan_prompt(data)
				"vigilia":
					_show_vigilia_prompt(data)
				"ataque":
					_show_ataque_prompt(data)
				"response_window":
					_show_response_window_prompt(data)
				"choose_wielder":
					_show_choose_wielder_prompt(data)
				"select_cards":
					_show_select_cards_prompt(data)
				"choose_option":
					_show_choose_option_prompt(data)
				"select_cemetery_cards":
					_show_select_cemetery_cards_prompt(data)
				"await_target":
					_show_await_target_prompt(data)
				"await_multi_target":
					_show_await_multi_target_prompt(data)
				"await_target_or_castillo":
					_show_await_target_or_castillo_prompt(data)
				"name_card":
					_show_name_card_prompt(data)
				"priority":
					_show_priority_prompt(data)
				"zone_pick":
					_show_zone_pick_prompt(data)
				"reveal_window":
					var reveal_window = load("res://scripts/ui/zones/RevealWindow.gd").new()
					var reveal_result: Dictionary = await reveal_window.open(_main, data.get("config", {}))
					NetworkClient.send_message({"op": "intent", "kind": "reveal_window_choice", "result": reveal_result})
				"castle_look":
					# Misma ventana que el Anfitrión (CastleLook.gd, §69):
					# repartir las cartas miradas y ordenar el resto.
					var look_window = CastleLookWindowScript.new()
					var result: Dictionary = await look_window.open(_main, data.get("config", {}))
					NetworkClient.send_message({"op": "intent", "kind": "castle_look_choice", "result": result})
		"reveal_log":
			RevealedCardsScript.on_network(data)
		"log":
			CombatLog.add_net_entry(data)
		"force_close":
			# Se acabó el tiempo y el Anfitrión ya respondió por ti (TurnClock): se cierra lo abierto.
			# Las ventanas que esperan solas (RevealWindow, CastleLookWindow...) se cierran con
			# NetworkClient.ui_forced() y su intent se descarta.
			_close_current_overlay()
			_clear_remote_paso()
			_clear_hand_actions()
			_clear_attack_candidates()
			_clear_board_blocking()
			_clear_board_pick()
			_pending_vigilia = {}
		"move_card":
			_apply_move_card(data)
		"remove_card":
			_apply_remove_card(data)
		"hand_card_added":
			_apply_hand_card_added(data)
		"hand_card_removed":
			_apply_hand_card_removed(data)
		"priority_closed":
			if int(data.get("window_id", -2)) == _priority_window_id:
				_close_current_overlay()
				_clear_remote_paso()
				_clear_hand_actions()
				_clear_board_blocking()
				_clear_board_pick()
			if not _pending_vigilia.is_empty() and not _current_overlay:
				_show_vigilia_prompt(_pending_vigilia)
		"castillo_counts":
			UIManager.sync_castillo_counts(int(data.get("own", 0)), int(data.get("rival", 0)))
			# Llega al empezar la partida (GameStateBroadcaster._start_hand_sync())
			# — cierra la espera del mulligan simultáneo.
			var waiting := _main.get_node_or_null("/root/MatchLoadingOverlay")
			if waiting:
				waiting.hide_loading()
		"dice_roll":
			_show_dice_roll_mirror(data)
		"idle_attack_cards":
			_apply_idle_attack_cards(data.get("card_ids", []))
		"hand_shown":
			_show_hand_shown(data)
		"disabled_cards":
			_disabled_ids.clear()
			for id in data.get("card_ids", []):
				_disabled_ids[str(id)] = true
			for nodes in [_card_nodes, _hand_card_nodes]:
				for card_id in nodes:
					var node: Node = nodes[card_id]
					if is_instance_valid(node):
						node.remote_ability_disabled = _disabled_ids.has(card_id)

# =============================================================================
# DUELO DE DADOS — el Remoto reproduce la misma tirada que ya resolvió el Anfitrión
# (GameBootstrap._show_dice_roll()/DiceDuel3D.forced_result1/2).
# =============================================================================


func _show_dice_roll_mirror(data: Dictionary) -> void:
	var r1: int = int(data.get("result1", 0))
	var r2: int = int(data.get("result2", 0))
	if r1 <= 0 or r2 <= 0:
		return
	var loading_overlay := _main.get_node_or_null("/root/MatchLoadingOverlay")
	if loading_overlay:
		loading_overlay.hide_loading()
	var dice_duel = DiceDuel3D.new()
	dice_duel.forced_result1 = r1
	dice_duel.forced_result2 = r2
	# El dado izquierdo (result1) siempre es el del Anfitrión — mismo
	# convenio fijo que usa GameBootstrap._show_dice_roll() del otro lado,
	# no "el tuyo siempre a la izquierda". Aquí solo cambia el texto de "quién
	# parte": "TÚ"/"OPONENTE" no tendría sentido en esta vista espejo, que no
	# corre su propio GameManager.
	dice_duel.winner_text_p0 = "¡EMPIEZA EL ANFITRIÓN!"
	dice_duel.winner_text_p1 = "¡EMPIEZAS TÚ!"
	_main.add_child(dice_duel)
	# Solo muestra la espera si no llegó ningún prompt real mientras corría la animación: el mulligan
	# puede llegar durante los dados y la pantalla de carga (MatchLoadingOverlay, una capa encima) lo
	# dejaba tapado.
	dice_duel.duel_completed.connect(func(_winner_id: int):
		if loading_overlay and not (_current_overlay and is_instance_valid(_current_overlay)):
			loading_overlay.show_loading(_main, "ESPERANDO JUGADOR",
				"El Anfitrión está preparando su mano...")
	)

# =============================================================================
# TABLERO — aplica move_card/remove_card creando/moviendo/liberando Nodos
# Card reales en los contenedores player_*/opponent_* correctos
# =============================================================================


func _apply_idle_attack_cards(card_ids: Array) -> void:
	var tint: Color = _main._card_interaction.IDLE_ATTACK_TINT
	for card_id in _idle_attack_ids:
		var old: Node = _card_nodes.get(card_id, null)
		if not (card_id in card_ids) and is_instance_valid(old) and old.modulate == tint:
			old.modulate = Color.WHITE
	_idle_attack_ids.clear()
	for id in card_ids:
		_idle_attack_ids[str(id)] = true
		var node: Node = _card_nodes.get(str(id), null)
		if is_instance_valid(node):
			node.modulate = tint


func _apply_move_card(data: Dictionary) -> void:
	var card_id: String = str(data.get("card_id", ""))
	var zone: int = int(data.get("zone", -1))
	if card_id.is_empty() or zone == -1:
		return
	var own: bool = data.get("own", false)
	var card_data: Dictionary = data.get("data", {})

	var node: Node = _card_nodes.get(card_id, null)
	if node and is_instance_valid(node):
		var old_parent = node.get_parent()
		if old_parent:
			old_parent.remove_child(node)
	else:
		node = _main._create_card(card_data, false)
		# can_interact = false: las cartas reflejadas no se inspeccionan ni se targetean por aquí, y así
		# no hay clicks muertos.
		node.can_interact = false
		node.drag_enabled = false
		node.owner_id = 0 if own else 1
		node.controller_id = 0 if own else 1
		_main._connect_card_signals(node)
		_card_nodes[card_id] = node

	var container: Node = _container_for(own, zone)
	if not container:
		node.queue_free()
		_card_nodes.erase(card_id)
		return

	container.add_child(node)
	node.top_level = false
	node.set_zone(zone)
	node.remote_ability_disabled = _disabled_ids.has(card_id)
	if _idle_attack_ids.has(card_id) and zone == Constants.Zone.LINEA_ATAQUE:
		node.modulate = _main._card_interaction.IDLE_ATTACK_TINT

	var card_type: int = int(card_data.get("tipo", -1))
	var target_scale: Vector2 = Vector2.ONE
	if zone in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]:
		target_scale = Constants.GOLD_CARD_SCALE
	elif zone == Constants.Zone.LINEA_APOYO and card_type == Constants.CardType.TOTEM:
		target_scale = Constants.TOTEM_CARD_SCALE
	node.scale = target_scale
	node.base_scale = target_scale


func _apply_remove_card(data: Dictionary) -> void:
	var card_id: String = str(data.get("card_id", ""))
	if card_id.is_empty():
		return
	var node: Node = _card_nodes.get(card_id, null)
	if node and is_instance_valid(node):
		var parent = node.get_parent()
		if parent:
			parent.remove_child(node)
		node.queue_free()
	_card_nodes.erase(card_id)

# =============================================================================
# MANO PROPIA PERSISTENTE (GameStateBroadcaster._on_hand_card_added()/_on_hand_card_removed();
# arquitectura.md §45): a diferencia de _apply_move_card()/_apply_remove_card(), puebla player_hand
# con Nodos que quedan toda la partida.
# can_interact = true: la mano física es la forma de jugar desde la mano. CardInteractionModule
# desvía los clicks del Remoto a on_card_double_clicked() (nunca a GoldManager.play_card() local,
# que se saltaría el protocolo de intents).
# =============================================================================


func _apply_hand_card_added(data: Dictionary) -> void:
	var card_data: Dictionary = data.get("data", {})
	var card_id: String = str(card_data.get("card_id", ""))
	if card_id.is_empty() or _hand_card_nodes.has(card_id):
		return
	var node: Node = _main._create_card(card_data, false)
	node.owner_id = 0
	node.controller_id = 0
	node.can_interact = true
	node.drag_enabled = false
	_main._connect_card_signals(node)
	_main.player_hand.add_card(node)
	_hand_card_nodes[card_id] = node
	node.remote_ability_disabled = _disabled_ids.has(card_id)


func _apply_hand_card_removed(data: Dictionary) -> void:
	var card_id: String = str(data.get("card_id", ""))
	var node: Node = _hand_card_nodes.get(card_id, null)
	if node and is_instance_valid(node) and node in _main.player_hand.cards:
		_main.player_hand.remove_card(node, true)
	_hand_card_nodes.erase(card_id)


func _container_for(own: bool, zone: int) -> Node:
	match zone:
		Constants.Zone.RESERVA_ORO:
			return _main.player_gold if own else _main.opponent_gold
		Constants.Zone.ORO_PAGADO:
			return _main.player_oro_pagado if own else _main.opponent_oro_pagado
		Constants.Zone.LINEA_DEFENSA:
			return _main.player_field if own else _main.opponent_field
		Constants.Zone.LINEA_ATAQUE:
			return _main.player_linea_ataque if own else _main.opponent_linea_ataque
		Constants.Zone.LINEA_APOYO:
			return _main.player_linea_apoyo if own else _main.opponent_linea_apoyo
		_:
			return null
