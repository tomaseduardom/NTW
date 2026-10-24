extends "res://scripts/core/network/RemoteMirrorControllerUI.gd"
## RemoteMirrorControllerMesa — familia Mesa de RemoteMirrorController.gd (ver RemoteMirrorControllerBase.gd).


# =============================================================================
# BOTÓN DE PASO DEL REMOTO: el mismo botón del HUD que usa el Anfitrión. Como el Remoto no corre
# GameManager, el texto/visibilidad los decide el prompt activo y el click (o la tecla P, vía
# PhaseFlowController._on_paso_pressed()) ejecuta _paso_action.
# =============================================================================


func on_paso_pressed() -> void:
	if _paso_action.is_valid():
		_paso_action.call()


func _set_remote_paso(text: String, glow: bool, action: Callable) -> void:
	_paso_action = action
	_skip_action = Callable()  # quien la necesite la vuelve a poner después
	if _main._game_hud:
		_main._game_hud.show_paso_button_with_text(text, glow)

# =============================================================================
# VENTANA DE PRIORIDAD (RemotePlayerController.on_priority_received()):
# responder a una carta/habilidad del Anfitrión, Guerra de Talismanes o
# declarar bloqueadores. Toda respuesta lleva el window_id del prompt.
# =============================================================================


func _show_priority_prompt(data: Dictionary) -> void:
	var window_id: int = int(data.get("window_id", -1))
	var timeout: int = int(data.get("timeout", 0))
	var button_text: String = str(data.get("button_text", "Pasar [P]"))
	var abilities: Array = data.get("abilities", [])
	var talismans: Array = data.get("talismans", [])
	var blockers: Array = data.get("blockers", [])
	var attackers: Array = data.get("attackers", [])

	var respond := func(extra: Dictionary) -> void:
		var intent := {"op": "intent", "kind": "priority_response", "window_id": window_id}
		intent.merge(extra)
		_send_intent_and_close(intent)

	if not blockers.is_empty():
		var confirm_blocks: Callable = _start_board_blocking(attackers, blockers, respond)
		_set_remote_paso(button_text, true, confirm_blocks)
	else:
		var pass_action := func(): respond.call({"action": "pass"})
		# Talismanes: desde la mano física (brillan, doble clic). El panel solo
		# aparece si hay habilidades activadas (están en el tablero, no en la mano).
		var actions: Dictionary = {}
		for card in talismans:
			var card_id: String = str(card.get("card_id", ""))
			actions[card_id] = {"op": "intent", "kind": "priority_response", "window_id": window_id,
				"action": "play", "card_id": card_id}
		_set_hand_actions(actions)
		if not abilities.is_empty() and not _start_ability_pick(abilities, respond):
			_build_response_panel(str(data.get("context", "")), abilities, timeout, respond, pass_action)
		_set_remote_paso(button_text, true, pass_action)
	_priority_window_id = window_id
	if timeout > 0 and _main._game_hud:
		_main._game_hud.start_paso_countdown(timeout)


func _build_response_panel(context_name: String, abilities: Array, timeout: int,
		respond: Callable, pass_action: Callable) -> void:
	var title := "¿Respondes? — %s" % context_name if not context_name.is_empty() else "¿Respondes?"
	var vbox := _build_overlay(title)

	var a_lbl := Label.new()
	a_lbl.text = "Usar habilidad:"
	vbox.add_child(a_lbl)
	_build_card_row(vbox, abilities)
	for c in abilities:
		var card_id: String = str(c.get("card_id", ""))
		var ability_index: int = int(c.get("ability_index", 0))
		var label_text: String = str(c.get("effect_text", c.get("cost_text", "Usar habilidad")))
		_add_row_button(vbox, "Usar: %s" % label_text, func():
			respond.call({"action": "ability", "card_id": card_id, "ability_index": ability_index}))

	var sep := HSeparator.new()
	vbox.add_child(sep)
	var pass_btn := Button.new()
	pass_btn.text = "Pasar"
	pass_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pass_btn.pressed.connect(pass_action)
	vbox.add_child(pass_btn)
	if timeout > 0:
		_countdown_button_text(pass_btn, "Pasar", timeout)


func _countdown_button_text(btn: Button, base_text: String, seconds: int) -> void:
	"""Cuenta regresiva visible dentro del panel (el botón del HUD queda tapado
	por el overlay). Solo visual — el plazo real lo controla el Anfitrión."""
	for remaining in range(seconds, 0, -1):
		if not is_instance_valid(btn):
			return
		btn.text = "%s (%d)" % [base_text, remaining]
		await get_tree().create_timer(1.0).timeout

# =============================================================================
# MANO FÍSICA COMO ÚNICA FORMA DE JUGAR
# =============================================================================


func on_card_double_clicked(card: Node) -> void:
	"""Llamado por CardInteractionModule en el cliente Remoto en vez de su
	lógica local de jugar cartas."""
	var card_id: String = ""
	for id in _hand_card_nodes:
		if _hand_card_nodes[id] == card:
			card_id = id
			break
	if card_id.is_empty():
		return  # carta del tablero espejado — no se juega con doble clic
	if _hand_actions.is_empty():
		return  # ninguna jugada abierta (p.ej. el eco del clic que eligió un objetivo)
	if not _hand_actions.has(card_id):
		_main._update_debug("No puedes jugar esa carta ahora")
		return
	_send_intent_and_close(_hand_actions[card_id])


func _set_hand_actions(actions: Dictionary) -> void:
	_clear_hand_actions()
	_hand_actions = actions
	for card_id in _hand_actions:
		var node: Node = _hand_card_nodes.get(card_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(true, CardBadges.GLOW_COLOR_CELESTE, &"remote_playable")


func on_card_clicked(card: Node) -> void:
	"""Clic simple en el cliente Remoto: marcar/desmarcar atacante, o elegir
	bloqueador y a quién bloquea."""
	var card_id: String = _visible_id_of(card)
	if card_id.is_empty():
		return
	if _pick_targets.has(card_id):
		_pick_targets[card_id].call(card_id)
		return
	if not _block_options.is_empty():
		_on_board_block_click(card_id)
		return
	if not _attack_candidates.has(card_id):
		return
	var selected: bool = not _attack_candidates[card_id]
	_attack_candidates[card_id] = selected
	card.modulate = Color(1.0, 0.62, 0.32, 1.0) if selected else Color.WHITE
	var count: int = 0
	for id in _attack_candidates:
		if _attack_candidates[id]:
			count += 1
	_main._update_debug("Atacantes elegidos: %d" % count)

# =============================================================================
# BLOQUEO EN EL TABLERO — mismo gesto que el Anfitrión (CardInteractionModule._declare_blocker):
# clic en tu Aliado brillante; si puede bloquear a un solo atacante libre se asigna directo, si no
# los atacantes posibles brillan en rojo y eliges con otro clic. Clic en un bloqueador ya asignado
# lo libera, salvo que pueda bloquear a otro atacante libre (Elías): entonces suma ese bloqueo. El
# botón de paso confirma.
# =============================================================================


func _start_board_blocking(attackers: Array, blockers: Array, respond: Callable) -> Callable:
	for b in blockers:
		var blocker_id: String = str(b.get("card_id", ""))
		var node: Node = _card_nodes.get(blocker_id, null)
		if not node or not is_instance_valid(node):
			continue
		var valid: Array = []
		for attacker_id in b.get("can_block", []):
			valid.append(str(attacker_id))
		_block_options[blocker_id] = valid
		_block_max[blocker_id] = int(b.get("max_blocks", 1))
	_refresh_block_glows()
	_main._update_debug("Te atacan %d Aliado(s). Clic en tus Aliados brillantes para bloquear, luego Confirmar." % (
		attackers.size()))
	return func():
		var pairs: Array = []
		for blocker_id in _block_pairs:
			for attacker_id in _block_pairs[blocker_id]:
				pairs.append({"blocker_id": blocker_id, "attacker_id": attacker_id})
		respond.call({"action": "blocks", "pairs": pairs})


func _can_add_block(blocker_id: String) -> bool:
	return _block_pairs.get(blocker_id, []).size() < int(_block_max.get(blocker_id, 1)) \
		and not _free_attackers_for(blocker_id).is_empty()


func _on_board_block_click(card_id: String) -> void:
	if _block_options.has(card_id):
		var was_pending := _block_pending_blocker == card_id
		_block_pending_blocker = ""
		if _block_pairs.has(card_id) and (was_pending or not _can_add_block(card_id)):
			_block_pairs.erase(card_id)
			_main._update_debug("%s ya no bloquea" % _mirror_name(card_id))
			_refresh_block_glows()
			return
		var free: Array = _free_attackers_for(card_id)
		if free.is_empty():
			_main._update_debug("%s no puede bloquear a ningún atacante libre" % _mirror_name(card_id))
		elif free.size() == 1:
			_assign_block(card_id, free[0])
		else:
			_block_pending_blocker = card_id
			_main._update_debug("%s bloquea — elige a qué atacante rival" % _mirror_name(card_id))
		_refresh_block_glows()
		return
	if not _block_pending_blocker.is_empty() and card_id in _free_attackers_for(_block_pending_blocker):
		_assign_block(_block_pending_blocker, card_id)
		_block_pending_blocker = ""
		_refresh_block_glows()


func _free_attackers_for(blocker_id: String) -> Array:
	var free: Array = []
	var taken: Array = []
	for assigned in _block_pairs.values():
		taken.append_array(assigned)
	for attacker_id in _block_options.get(blocker_id, []):
		if not (attacker_id in taken):
			free.append(attacker_id)
	return free


func _assign_block(blocker_id: String, attacker_id: String) -> void:
	if not _block_pairs.has(blocker_id):
		_block_pairs[blocker_id] = []
	_block_pairs[blocker_id].append(attacker_id)
	_main._update_debug("%s bloquea a %s" % [_mirror_name(blocker_id), _mirror_name(attacker_id)])


func _mirror_name(card_id: String) -> String:
	var node: Node = _card_nodes.get(card_id, null)
	if node and is_instance_valid(node) and node.get("card_name") != null:
		return str(node.card_name)
	return "Aliado"


func _refresh_block_glows() -> void:
	"""Celeste: tus Aliados que pueden bloquear (sin asignar); tinte azul: ya
	asignados; rojo: los atacantes elegibles para el bloqueador pendiente."""
	var targets: Array = [] if _block_pending_blocker.is_empty() else _free_attackers_for(_block_pending_blocker)
	for blocker_id in _block_options:
		var node: Node = _card_nodes.get(blocker_id, null)
		if not node or not is_instance_valid(node):
			continue
		node.can_interact = true
		var assigned: bool = _block_pairs.has(blocker_id)
		node.modulate = Color(0.4, 0.7, 1.0, 1.0) if assigned else Color.WHITE
		node.set_activatable(not assigned or _can_add_block(blocker_id), CardBadges.GLOW_COLOR_CELESTE, &"remote_blocker")
		for attacker_id in _block_options[blocker_id]:
			var a_node: Node = _card_nodes.get(attacker_id, null)
			if not a_node or not is_instance_valid(a_node):
				continue
			var is_target: bool = attacker_id in targets
			a_node.can_interact = is_target
			a_node.set_activatable(is_target, CardBadges.GLOW_COLOR_RED, &"remote_block_target")

# =============================================================================
# SELECCIÓN SOBRE EL TABLERO/MANO: portador de Arma, objetivos de efectos y habilidades de respuesta
# se eligen con clic sobre la carta real (celeste si es tuya, rojo si es del rival). Si algún
# candidato no tiene Nodo en esta pantalla (p.ej. una carta de la mano del Anfitrión), se usa el
# popup para no esconder una opción válida.
# =============================================================================


func _visible_id_of(card: Node) -> String:
	for id in _card_nodes:
		if _card_nodes[id] == card:
			return id
	for id in _hand_card_nodes:
		if _hand_card_nodes[id] == card:
			return id
	return ""


func _ids_of(cards_data: Array) -> Array:
	var ids: Array = []
	for c in cards_data:
		var card_id: String = str(c.get("card_id", ""))
		if not card_id.is_empty() and not (card_id in ids):
			ids.append(card_id)
	return ids


func _start_board_pick(card_ids: Array, on_pick: Callable) -> bool:
	for card_id in card_ids:
		if not _visible_node(card_id):
			return false
	for card_id in card_ids:
		var node: Node = _visible_node(card_id)
		node.can_interact = true
		var color: Color = CardBadges.GLOW_COLOR_CELESTE if node.get("owner_id") == 0 else CardBadges.GLOW_COLOR_RED
		node.set_activatable(true, color, &"remote_pick")
		_pick_targets[card_id] = on_pick
	return true


func _toggle_multi_pick(card_id: String, max_sel: int) -> void:
	var node: Node = _visible_node(card_id)
	if _pick_multi.has(card_id):
		_pick_multi.erase(card_id)
		if node:
			node.modulate = Color.WHITE
	elif max_sel < 0 or _pick_multi.size() < max_sel:
		_pick_multi[card_id] = true
		if node:
			node.modulate = Color(1.0, 0.88, 0.45, 1.0)
	else:
		_main._update_debug("Ya elegiste el máximo (%d)" % max_sel)
		return
	_main._update_debug("Elegidas: %d" % _pick_multi.size())


func _start_remote_castillo_pick(castillo_title: String, own_only: bool) -> void:
	"""Reusa la UI de Castillos clickeables del motor (SelectionManager.
	start_castillo_pick(), solo visual en esta pantalla)."""
	SelectionManager.start_castillo_pick(_main, castillo_title, func(picked_own: bool) -> void:
		if own_only and not picked_own:
			_main._update_debug("Solo puedes elegir tu propio Castillo")
			_start_remote_castillo_pick(castillo_title, own_only)
			return
		_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo",
			"own": picked_own}))


func _start_ability_pick(abilities: Array, respond: Callable) -> bool:
	"""Las cartas con una habilidad activada disponible brillan; clic en una:
	si tiene una sola habilidad se usa directo, si tiene varias se elige cuál."""
	var by_card: Dictionary = {}  # card_id -> [ability entries]
	for a in abilities:
		var card_id: String = str(a.get("card_id", ""))
		if not by_card.has(card_id):
			by_card[card_id] = []
		by_card[card_id].append(a)
	var on_card := func(card_id: String) -> void:
		var options: Array = by_card.get(card_id, [])
		if options.size() == 1:
			respond.call({"action": "ability", "card_id": card_id,
				"ability_index": int(options[0].get("ability_index", 0))})
			return
		var vbox := _build_overlay("¿Qué habilidad usas?")
		for opt in options:
			var ability_index: int = int(opt.get("ability_index", 0))
			_add_row_button(vbox, str(opt.get("effect_text", opt.get("cost_text", "Usar habilidad"))), func():
				respond.call({"action": "ability", "card_id": card_id, "ability_index": ability_index}))
		_add_row_button(vbox, "Volver", func(): _close_current_overlay())
	if not _start_board_pick(by_card.keys(), on_card):
		return false
	for card_id in by_card:
		var node: Node = _visible_node(card_id)
		if node:
			node.set_activatable(true, CardBadges.GLOW_COLOR_GOLD, &"remote_pick")
	return true

# =============================================================================
# SELECTOR DE ZONAS (ActionSearch._delegate_zone_pick_to_remote) — el Remoto corre el mismo
# ZoneBrowsePicker que el Anfitrión, en su propia pantalla ('is_own' ya viene relativo a él), y
# devuelve los índices elegidos.
# =============================================================================


func _show_zone_pick_prompt(data: Dictionary) -> void:
	var pools: Array = []
	for p in data.get("pools", []):
		var cards: Array = []
		for c in p.get("cards", []):
			cards.append({"data": c.get("data", {}), "eligible": bool(c.get("eligible", false))})
		# JSON trae los números como float — la zona se usa como clave de Dictionary.
		pools.append({"is_own": bool(p.get("is_own", true)), "zone": int(p.get("zone", 0)), "cards": cards,
			"exclusive": bool(p.get("exclusive", false))})
	if not _main._zone_browse_picker:
		NetworkClient.send_message({"op": "intent", "kind": "zone_pick_choice", "picks": []})
		return
	# Cartas de la mano candidatas (p.ej. Miguel): los ids son los de la mano espejo
	# (_hand_card_nodes). Se guarda el índice original para devolverle al Anfitrión la posición en SU
	# lista.
	var hand_ids: Array = data.get("hand_card_ids", [])
	var hand_nodes: Array = []
	var hand_index_map: Array = []
	for i in range(hand_ids.size()):
		var node: Node = _hand_card_nodes.get(str(hand_ids[i]), null)
		if node and is_instance_valid(node):
			hand_nodes.append(node)
			hand_index_map.append(i)
	var picks: Array = await _main._zone_browse_picker.pick(str(data.get("title", "Buscar")), pools,
		int(data.get("min_selections", 0)), int(data.get("max_selections", 1)), bool(data.get("distinct_names", false)),
		hand_nodes)
	for p in picks:
		if int(p[0]) == -1 and int(p[1]) < hand_index_map.size():
			p[1] = hand_index_map[int(p[1])]
	NetworkClient.send_message({"op": "intent", "kind": "zone_pick_choice", "picks": picks,
		"opened_castles": _main._zone_browse_picker.last_opened_castles()})
