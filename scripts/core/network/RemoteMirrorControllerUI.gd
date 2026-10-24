extends "res://scripts/core/network/RemoteMirrorControllerBase.gd"
## RemoteMirrorControllerUI — familia UI de RemoteMirrorController.gd (ver RemoteMirrorControllerBase.gd).


func _close_current_overlay() -> void:
	if _current_overlay and is_instance_valid(_current_overlay):
		_current_overlay.queue_free()
	_current_overlay = null
	# Contraparte de mark_inspection_layer_in_use() en _build_overlay() —
	# apaga el CanvasLayer solo si no quedó ninguna inspección real abierta
	# (su propio contador de generación ya resuelve el caso de que mientras
	# tanto se haya abierto una inspección nueva de verdad).
	if _main._card_inspector:
		_main._card_inspector.release_inspection_layer_if_unused()

# =============================================================================
# CONSTRUCCIÓN DE LA UI (overlay genérico + filas de botones)
# =============================================================================


func _build_overlay(title: String) -> VBoxContainer:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# CardInspectionLayer.tscn arranca con visible = false: hay que prenderla o el diálogo queda
	# invisible (mismo mecanismo que BernardoAbilityHandler.gd, ver mark_inspection_layer_in_use()).
	if _main._card_inspector:
		_main._card_inspector.mark_inspection_layer_in_use()
	else:
		_main.inspection_layer.visible = true
	_main.inspection_layer.add_child(overlay)
	_current_overlay = overlay

	var panel := PanelContainer.new()
	panel.set_anchor(SIDE_LEFT, 0.5); panel.set_anchor(SIDE_TOP, 0.5)
	panel.set_anchor(SIDE_RIGHT, 0.5); panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.set_offset(SIDE_LEFT, -260); panel.set_offset(SIDE_TOP, -230)
	panel.set_offset(SIDE_RIGHT, 260); panel.set_offset(SIDE_BOTTOM, 230)
	overlay.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 400)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	return vbox


func _add_row_button(container: Container, text: String, on_pressed: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(on_pressed)
	container.add_child(btn)

# =============================================================================
# CARTAS REALES EN LOS PROMPTS: Nodos Card.tscn con arte, no interactivos, en vez de listas de texto
# (como GoldManagerTax._open_cemetery_reveal_popup()). La decisión pasa por los botones de abajo
# (card_id/índice). Requiere que RemotePlayerController._card_public_data() mande el card_data
# completo.
# =============================================================================


func _build_card_display(card_data: Dictionary) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(84.0, 118.0)
	var c_node = _CardScene.instantiate()
	c_node.load_from_data(card_data, bool(card_data.get("host_hand_hidden", false)))
	c_node.can_interact = false
	c_node.drag_enabled = false
	c_node.custom_minimum_size = Vector2(150.0, 210.0)
	c_node.size = Vector2(150.0, 210.0)
	c_node.scale = Vector2(0.56, 0.56)
	c_node.base_scale = Vector2(0.56, 0.56)
	if _main and _main.has_method("_connect_card_signals"):
		_main._connect_card_signals(c_node)
	wrapper.add_child(c_node)
	return wrapper


func _build_card_row(parent: Container, cards_data: Array) -> void:
	"""Fila horizontal con scroll de Nodos Card reales — se agrega como
	cualquier otro hijo de 'parent' (normalmente el vbox que devuelve
	_build_overlay()), antes de los botones de acción correspondientes."""
	if cards_data.is_empty():
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	scroll.add_child(hbox)
	for card_data in cards_data:
		hbox.add_child(_build_card_display(card_data))


func _send_intent_and_close(intent: Dictionary) -> void:
	if intent.get("kind", "") in ["place_gold", "play_card", "end_vigilia", "activate_ability"]:
		_pending_vigilia = {}
	NetworkClient.send_message(intent)
	_close_current_overlay()
	_clear_remote_paso()
	_clear_hand_actions()
	_clear_attack_candidates()
	_clear_board_blocking()
	_clear_board_pick()


func _clear_remote_paso() -> void:
	_paso_action = Callable()
	_skip_action = Callable()
	_priority_window_id = -1
	if _main._game_hud:
		_main._game_hud.stop_paso_countdown()
		_main._game_hud.stop_paso_glow()
		_main._game_hud.hide_paso_button()


func _clear_hand_actions() -> void:
	for card_id in _hand_actions:
		var node: Node = _hand_card_nodes.get(card_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_playable")
	_hand_actions = {}


func _clear_attack_candidates() -> void:
	for card_id in _attack_candidates:
		var node: Node = _card_nodes.get(card_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_attackable")
			node.can_interact = false
			node.modulate = Color.WHITE
	_attack_candidates = {}


func _clear_board_blocking() -> void:
	for blocker_id in _block_options:
		var node: Node = _card_nodes.get(blocker_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_blocker")
			node.can_interact = false
			node.modulate = Color.WHITE
		for attacker_id in _block_options[blocker_id]:
			var a_node: Node = _card_nodes.get(attacker_id, null)
			if a_node and is_instance_valid(a_node):
				a_node.set_activatable(false, CardBadges.GLOW_COLOR_RED, &"remote_block_target")
				a_node.can_interact = false
	_block_options = {}
	_block_pairs = {}
	_block_max = {}
	_block_pending_blocker = ""


func _visible_node(card_id: String) -> Node:
	var node: Node = _card_nodes.get(card_id, null)
	if not node:
		node = _hand_card_nodes.get(card_id, null)
	return node if node and is_instance_valid(node) else null


func _clear_board_pick() -> void:
	for card_id in _pick_targets:
		var node: Node = _visible_node(card_id)
		if not node:
			continue
		node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_pick")
		node.modulate = Color.WHITE
		# La mano física siempre queda interactiva (§49); el tablero espejado no.
		node.can_interact = _hand_card_nodes.has(card_id)
	_pick_targets = {}
	_pick_multi = {}
	SelectionManager.cancel_castillo_pick()
