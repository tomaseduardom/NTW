extends Node
class_name RemoteMirrorController
## RemoteMirrorController — instanciado siempre en Main.gd (Anfitrión y
## Remoto por igual), pero SOLO hace algo si esta instancia concreta es el
## Remoto de una sala de red activa (NetworkClient.room_code != "" and not
## NetworkClient.is_host). En ese caso, GameBootstrap ya se detiene solo
## después de mandar el mazo propio (ver GameBootstrap._send_own_deck_and_
## wait_for_host()) — no hay doble simulación corriendo (el Remoto nunca
## llega a GameManager.setup_game()/start_game() de forma local), pero
## tampoco hay nada más que pase: esta clase es lo que hace que después de
## esa espera, la persona real pueda seguir jugando.
##
## Escucha los mensajes {"op":"prompt","kind":...} que manda
## RemotePlayerController (scripts/core/ai/RemotePlayerController.gd) desde
## el lado del Anfitrión y muestra una UI mínima para que la persona elija,
## devolviendo {"op":"intent","kind":...} — mismo protocolo documentado ahí.
##
## Alcance de este incremento (2026-09-11, Fase B): cubre los 4 tipos de
## prompt que RemotePlayerController ya manda (mulligan/vigilia/ataque/
## response_window), CON diálogos de texto (nombre/coste, sin arte). Además
## aplica las instrucciones "move_card"/"remove_card" que manda
## GameStateBroadcaster desde el lado del Anfitrión — esto SÍ crea Nodos
## Card reales (con arte) en los contenedores correctos del tablero, para
## las 5 zonas públicas "en juego" (Reserva de Oro/Oro Pagado/Línea de
## Defensa/Ataque/Apoyo). Mano/Castillo (privados) y Cementerio/Destierro
## (públicos pero sin Nodos visibles, solo contador) quedan fuera de este
## streaming por ahora — ver GameStateBroadcaster.gd.

var _main: Node = null
var _active: bool = false
var _current_overlay: Control = null
var _card_nodes: Dictionary = {}  # card_id (String) -> Node local (ghost)
var _hand_card_nodes: Dictionary = {}  # card_id (String) -> Node local en player_hand (§45)
## Botón de paso del Remoto (2026-10-11): qué hace el botón del HUD (y el
## atajo P) según el prompt activo, y el window_id de la ventana de
## prioridad que se está respondiendo (-1 si no hay ninguna).
var _paso_action: Callable = Callable()
var _priority_window_id: int = -1
## Último prompt de Vigilia todavía sin responder: si una ventana de
## prioridad lo tapa (p.ej. el Anfitrión responde a tu carta con un
## Talismán), se vuelve a mostrar al cerrarse esa ventana.
var _pending_vigilia: Dictionary = {}
## card_id de una carta de la mano física -> intent que manda su doble clic
## (Vigilia: poner Oro/jugar carta; ventana de prioridad: Talismán de
## respuesta). Vacío = ninguna carta de la mano se puede jugar ahora.
var _hand_actions: Dictionary = {}


func setup(main: Node) -> void:
	_main = main
	_active = NetworkClient.room_code != "" and not NetworkClient.is_host
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
			# 2026-09-23, bug real reportado por el usuario: cualquier prompt
			# real que llegue (mulligan/vigilia/ataque/etc.) tiene que tapar
			# la pantalla "ESPERANDO JUGADOR" que dejó el duelo de dados — sin
			# esto, el diálogo real se construía IGUAL, pero por debajo de esa
			# pantalla de carga (otra capa, nunca se ocultaba sola), dejando
			# al jugador Remoto viéndola para siempre sin ninguna forma de
			# llegar al prompt real ni de que este vuelva a intentarlo.
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
			if not _pending_vigilia.is_empty() and not _current_overlay:
				_show_vigilia_prompt(_pending_vigilia)
		"castillo_counts":
			UIManager.sync_castillo_counts(int(data.get("own", 0)), int(data.get("rival", 0)))
		"dice_roll":
			_show_dice_roll_mirror(data)


# =============================================================================
# DUELO DE DADOS — reproduce del lado Remoto la MISMA tirada que el
# Anfitrión ya resolvió (2026-09-20, a pedido del usuario: antes cada
# pantalla tiraba sus propios dados por separado, sin relación entre sí —
# ver GameBootstrap._show_dice_roll()/DiceDuel3D.forced_result1/2).
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
	# 2026-09-23, bug real reportado por el usuario (Anfitrión): el Remoto se
	# quedaba pegado para siempre en "ESPERANDO JUGADOR" — causa real: si el
	# mensaje "prompt"/"mulligan" (el Anfitrión llama a RemotePlayerController.
	# run_mulligan() apenas termina SU PROPIO mulligan) llegaba DURANTE esta
	# animación (tarda unos segundos), _show_mulligan_prompt() ya construía
	# el diálogo real sobre inspection_layer — pero este callback, un
	# instante después, tapaba ese diálogo con la pantalla de carga
	# (MatchLoadingOverlay, otra capa por encima), dejando el prompt real
	# invisible/inaccesible sin ningún mensaje nuevo en camino que lo
	# destapara. Ahora solo se muestra la espera si ningún prompt real llegó
	# todavía mientras corría la animación.
	dice_duel.duel_completed.connect(func(_winner_id: int):
		if loading_overlay and not (_current_overlay and is_instance_valid(_current_overlay)):
			loading_overlay.show_loading(_main, "ESPERANDO JUGADOR",
				"El Anfitrión está preparando su mano...")
	)


# =============================================================================
# TABLERO — aplica move_card/remove_card creando/moviendo/liberando Nodos
# Card reales en los contenedores player_*/opponent_* correctos
# =============================================================================
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
		# can_interact queda en false a propósito (2026-09-11): la
		# inspección/targeting de cartas mirroreadas es Fase C (todavía no
		# hay forma de que un click aquí dispare nada por red) — mostrarlas
		# como no-interactivas evita clicks muertos confusos.
		node.can_interact = false
		node.owner_id = 0 if own else 1
		node.controller_id = 0 if own else 1
		_card_nodes[card_id] = node

	var container: Node = _container_for(own, zone)
	if not container:
		node.queue_free()
		_card_nodes.erase(card_id)
		return

	container.add_child(node)
	node.top_level = false
	node.set_zone(zone)

	var card_type: int = int(card_data.get("tipo", -1))
	var target_scale: Vector2 = Vector2.ONE
	if zone in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]:
		target_scale = Constants.GOLD_CARD_SCALE
	elif zone == Constants.Zone.LINEA_APOYO and card_type == Constants.CardType.TOTEM:
		target_scale = Vector2(0.8, 0.8)
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
# MANO PROPIA PERSISTENTE (GameStateBroadcaster._on_hand_card_added()/
# _on_hand_card_removed(), 2026-10-08, arquitectura.md §45) — a diferencia
# de _apply_move_card()/_apply_remove_card() (las 5 zonas públicas en
# juego), esto puebla player_hand de verdad, con Nodos que se quedan ahí
# durante TODA la partida, no solo mientras un prompt puntual está abierto.
# 2026-10-11: can_interact = true — la mano física es ahora la ÚNICA forma de
# jugar cartas desde la mano. CardInteractionModule desvía los clicks del
# cliente Remoto a on_card_double_clicked() (nunca llegan a GoldManager.
# play_card() local, que rompería todo al no pasar por el protocolo de intents).
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
	# 2026-10-07, bug real reportado por el usuario (probando online por
	# primera vez): CardInspectionLayer.tscn arranca con visible=false (solo
	# CardInspectionLayer.gd lo prende/apaga al inspeccionar una carta) — sin
	# esto, el diálogo se construía bien pero quedaba invisible, el Remoto
	# nunca veía ningún prompt (mulligan incluido) y la partida se quedaba
	# congelada esperando una respuesta que nunca podía mandar. Mismo
	# mecanismo ya usado por BernardoAbilityHandler.gd para su propio diálogo
	# ajeno a una inspección real — ver mark_inspection_layer_in_use().
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
# CARTAS REALES EN LOS PROMPTS (2026-10-07, a pedido del usuario: "no sale
# mi mulligan bonito, el abanico de cartas está todo escrito") — mismo
# patrón ya usado en popups livianos del lado del Anfitrión (p.ej.
# GoldManagerTax._open_cemetery_reveal_popup()): Nodos Card.tscn reales con
# arte, no interactivos (el click que de verdad decide pasa por los botones
# de abajo, ya armados con card_id/índice — esto solo reemplaza las listas
# de puro texto por la carta de verdad). Requiere que RemotePlayerController.
# _card_public_data() mande el card_data COMPLETO, no solo nombre/coste.
# =============================================================================
const _CardScene = preload("res://scenes/cards/Card.tscn")


func _build_card_display(card_data: Dictionary) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(84.0, 118.0)
	var c_node = _CardScene.instantiate()
	c_node.load_from_data(card_data)
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
	if intent.get("kind", "") in ["place_gold", "play_card", "end_vigilia"]:
		_pending_vigilia = {}
	NetworkClient.send_message(intent)
	_close_current_overlay()
	_clear_remote_paso()
	_clear_hand_actions()


# =============================================================================
# MULLIGAN
# =============================================================================
func _show_mulligan_prompt(data: Dictionary) -> void:
	"""2026-10-08, a pedido del usuario ("construir el abanico visual real
	como el del Anfitrión" — ver arquitectura.md §44): a diferencia del
	resto de los prompts (que usan _build_overlay()/_build_card_row(), una
	fila de solo lectura + botones de texto aparte), el mulligan reusa los
	Nodos REALES que Main.tscn ya tiene para esto — mulligan_overlay/
	mulligan_hand (MulliganHand, el mismo abanico con curva/hover que ve el
	Anfitrión)/keep_hand_button/mulligan_button — en vez de construir un
	popup aparte. Esos botones ya vienen conectados a MulliganController.
	on_keep_hand_pressed()/on_mulligan_pressed() (para el flujo LOCAL del
	Anfitrión) — hay que desconectarlos antes de reusarlos, porque esos
	handlers terminan en GameManager.start_game() asumiendo una partida
	local que el Remoto nunca corrió (_dice_winner nunca seteado de este
	lado) — dispararían eso por error si se dejaran conectados."""
	var hand: Array = data.get("hand", [])
	_main.mulligan_hand.clear_cards_instant()
	for card_data in hand:
		var card_node = _main._create_card(card_data, false)
		card_node.can_interact = true
		card_node.drag_enabled = false
		_main.mulligan_hand.add_card(card_node, true)
	_main.mulligan_cards_label.text = "Mano actual: %d cartas" % hand.size()
	var next_hand_size: int = hand.size() - 1
	if next_hand_size <= 0:
		_main.mulligan_button.disabled = true
		_main.mulligan_button.text = "No puedes hacer mas mulligan"
	else:
		_main.mulligan_button.disabled = false
		_main.mulligan_button.text = "Mulligan (robar %d)" % next_hand_size
	_main.mulligan_overlay.visible = true

	if _main.keep_hand_button.pressed.is_connected(_main._mulligan_ctrl.on_keep_hand_pressed):
		_main.keep_hand_button.pressed.disconnect(_main._mulligan_ctrl.on_keep_hand_pressed)
	if _main.mulligan_button.pressed.is_connected(_main._mulligan_ctrl.on_mulligan_pressed):
		_main.mulligan_button.pressed.disconnect(_main._mulligan_ctrl.on_mulligan_pressed)
	var on_keep := func():
		_main.mulligan_overlay.visible = false
		_main.mulligan_hand.clear_cards_instant()
		NetworkClient.send_message({"op": "intent", "kind": "mulligan_choice", "keep": true})
	var on_mull := func():
		_main.mulligan_overlay.visible = false
		_main.mulligan_hand.clear_cards_instant()
		NetworkClient.send_message({"op": "intent", "kind": "mulligan_choice", "keep": false})
	_main.keep_hand_button.pressed.connect(on_keep, CONNECT_ONE_SHOT)
	_main.mulligan_button.pressed.connect(on_mull, CONNECT_ONE_SHOT)


# =============================================================================
# VIGILIA
# =============================================================================
func _show_vigilia_prompt(data: Dictionary) -> void:
	# 2026-10-11 (a pedido del usuario: "sigue saliendo el texto de la mano y
	# al mismo tiempo la mano, la idea es siempre solo usar la mano física"):
	# sin popup. Las cartas jugables de la mano real (player_hand, §45)
	# brillan y se juegan con doble clic, igual que el Anfitrión; el botón de
	# paso del HUD ("Atacar") termina la Vigilia. Ver on_card_double_clicked().
	_pending_vigilia = data
	var actions: Dictionary = {}
	for card in data.get("gold_candidates", []):
		var card_id: String = str(card.get("card_id", ""))
		actions[card_id] = {"op": "intent", "kind": "place_gold", "card_id": card_id}
	for key in ["ally_candidates", "weapon_candidates", "talisman_candidates", "totem_candidates"]:
		for card in data.get(key, []):
			var card_id: String = str(card.get("card_id", ""))
			actions[card_id] = {"op": "intent", "kind": "play_card", "card_id": card_id}
	_set_hand_actions(actions)
	_main._update_debug("Tu Vigilia — Oro disponible: %d. Doble clic en una carta brillante para jugarla." % int(
		data.get("gold_reserva", 0)))
	_set_remote_paso("Atacar [P]", false, func():
		_send_intent_and_close({"op": "intent", "kind": "end_vigilia"}))

# =============================================================================
# ATAQUE
# =============================================================================
func _show_ataque_prompt(data: Dictionary) -> void:
	var attackable: Array = data.get("attackable", [])
	var vbox := _build_overlay("Declara atacantes")
	if attackable.is_empty():
		var lbl := Label.new()
		lbl.text = "No tienes ningún Aliado que pueda atacar."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": []}))
		_set_remote_paso("Pasar [P]", false, func():
			_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": []}))
		return

	_build_card_row(vbox, attackable)
	var checkboxes: Dictionary = {}  # card_id -> CheckBox
	for card in attackable:
		var card_id: String = str(card.get("card_id", ""))
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes[card_id] = cb
		var lbl := Label.new()
		lbl.text = "%s (Fuerza/coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))]
		row.add_child(lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)
	var confirm_attack := func():
		var chosen_ids: Array = []
		for card_id in checkboxes:
			if checkboxes[card_id].button_pressed:
				chosen_ids.append(card_id)
		_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": chosen_ids})
	_add_row_button(vbox, "Confirmar ataque", confirm_attack)
	_set_remote_paso("Confirmar ataque [P]", false, confirm_attack)


# =============================================================================
# VENTANA DE RESPUESTA (habilidades activadas — Capa 2 de la Pila de
# Respuesta Universal)
# =============================================================================
func _show_response_window_prompt(data: Dictionary) -> void:
	var candidates: Array = data.get("candidates", [])
	var vbox := _build_overlay("¿Quieres responder?")
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No tienes ninguna habilidad activada disponible."
		vbox.add_child(lbl)

	_build_card_row(vbox, candidates)
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		var ability_index: int = int(c.get("ability_index", 0))
		var label_text: String = str(c.get("effect_text", c.get("cost_text", "Usar habilidad")))
		_add_row_button(vbox, "Usar: %s" % label_text, func():
			_send_intent_and_close({
				"op": "intent", "kind": "activate_ability",
				"card_id": card_id, "ability_index": ability_index,
			}))

	var sep := HSeparator.new()
	vbox.add_child(sep)
	_add_row_button(vbox, "Pasar", func():
		_send_intent_and_close({"op": "intent", "kind": "pass"}))


# =============================================================================
# ELEGIR PORTADOR DE ARMA (RemotePlayerController._choose_wielder_remote())
# =============================================================================
func _show_choose_wielder_prompt(data: Dictionary) -> void:
	var weapon: Dictionary = data.get("weapon", {})
	var candidates: Array = data.get("candidates", [])
	var vbox := _build_overlay("Elige quién porta %s" % str(weapon.get("nombre", "el Arma")))
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ningún Aliado en juego que pueda portarla."
		vbox.add_child(lbl)
		return

	_build_card_row(vbox, [weapon] if not weapon.is_empty() else [])
	_build_card_row(vbox, candidates)
	for card in candidates:
		var card_id: String = str(card.get("card_id", ""))
		_add_row_button(vbox, str(card.get("nombre", "?")), func():
			_send_intent_and_close({"op": "intent", "kind": "choose_wielder", "card_id": card_id}))


# =============================================================================
# SELECCIÓN DE CARTAS GENÉRICA (SelectionManager._delegate_selection_to_
# remote(), Fase 3 del plan de paridad remota) — cubre de taquito cualquier
# "busca una carta"/"elige del cementerio"/etc. que ya use SelectionManager
# del lado del motor de efectos, sin que cada patrón nuevo necesite su propio
# caso de prompt acá. Las cartas se identifican por ÍNDICE en 'candidates'
# (son Dictionary de datos crudos, no nodos Card con instance_id).
# =============================================================================
func _show_select_cards_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige carta(s)"))
	var candidates: Array = data.get("candidates", [])
	var max_sel: int = int(data.get("max_selections", 1))
	var min_sel: int = int(data.get("min_selections", 0))
	var can_cancel: bool = bool(data.get("can_cancel", true))
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ninguna carta para elegir."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": []}))
		return

	_build_card_row(vbox, candidates)
	if max_sel <= 0:
		# Solo mostrar (SelectionMode.REVEAL) — sin elección real; la fila de
		# cartas reales de arriba ya es la "lista", no hace falta texto.
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": []}))
		return

	if max_sel == 1:
		# Un clic elige y cierra — mismo criterio que el panel local
		# (SelectionManager._on_card_clicked() con max_selections == 1).
		for i in range(candidates.size()):
			var card: Dictionary = candidates[i]
			var idx: int = i
			_add_row_button(vbox, "%s (coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))], func():
				_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": [idx]}))
		if can_cancel:
			var sep := HSeparator.new()
			vbox.add_child(sep)
			_add_row_button(vbox, "Cancelar", func():
				_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "cancelled": true, "indices": []}))
		return

	# Multi-selección: checkboxes + Confirmar, mismo criterio que _show_ataque_prompt().
	var checkboxes: Dictionary = {}  # índice (int) -> CheckBox
	for i in range(candidates.size()):
		var card: Dictionary = candidates[i]
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes[i] = cb
		var lbl := Label.new()
		lbl.text = "%s (coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))]
		row.add_child(lbl)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)
	_add_row_button(button_row, "Confirmar", func():
		var chosen: Array = []
		for i in checkboxes:
			if checkboxes[i].button_pressed:
				chosen.append(i)
		if chosen.size() > max_sel:
			chosen = chosen.slice(0, max_sel)
		if chosen.size() < min_sel:
			return  # mismo criterio que el panel local: no confirma bajo el mínimo
		_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": chosen}))
	if can_cancel:
		_add_row_button(button_row, "Cancelar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "cancelled": true, "indices": []}))


# =============================================================================
# SELECCIÓN DE CARTAS DE CEMENTERIO/DESTIERRO/CASTILLO REVELADO
# (ZoneViewerModule._delegate_cemetery_picker_to_remote()/_delegate_reveal_
# picker_to_remote(), Fase 3 del plan de paridad remota) — mismo protocolo
# que "select_cards" pero con etiquetas extra de zona/lado cuando vienen
# (el picker de Cementerios las manda, el de revelado del Castillo no, al
# ser un solo pool sin "lado rival").
# =============================================================================
func _show_select_cemetery_cards_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige carta(s)"))
	var candidates: Array = data.get("candidates", [])
	var max_sel: int = int(data.get("max_selections", 1))
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ninguna carta para elegir."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cemetery_cards_choice", "indices": []}))
		return

	_build_card_row(vbox, candidates)
	var zone_words := {"cemetery": "Cementerio", "exile": "Destierro"}
	var side_words := {"own": "tuyo", "opponent": "rival"}
	var label_for := func(card: Dictionary) -> String:
		var base: String = "%s (coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))]
		var extra := ""
		if card.has("zone_type"):
			extra += str(zone_words.get(str(card.get("zone_type", "")), str(card.get("zone_type", ""))))
		if card.has("side"):
			extra += (" · " if not extra.is_empty() else "") + str(side_words.get(str(card.get("side", "")), str(card.get("side", ""))))
		return "%s [%s]" % [base, extra] if not extra.is_empty() else base

	if max_sel == 1:
		for i in range(candidates.size()):
			var idx: int = i
			_add_row_button(vbox, label_for.call(candidates[i]), func():
				_send_intent_and_close({"op": "intent", "kind": "select_cemetery_cards_choice", "indices": [idx]}))
		return

	var checkboxes2: Dictionary = {}  # índice (int) -> CheckBox
	for i in range(candidates.size()):
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes2[i] = cb
		var lbl2 := Label.new()
		lbl2.text = label_for.call(candidates[i])
		row.add_child(lbl2)

	_add_row_button(vbox, "Confirmar", func():
		var chosen: Array = []
		for i in checkboxes2:
			if checkboxes2[i].button_pressed:
				chosen.append(i)
		if chosen.size() > max_sel:
			chosen = chosen.slice(0, max_sel)
		_send_intent_and_close({"op": "intent", "kind": "select_cemetery_cards_choice", "indices": chosen}))


# =============================================================================
# OBJETIVO SOBRE CARTAS YA EN JUEGO (CardInteractionModule.await_target()/
# await_multi_target(), Fase 3 del plan de paridad remota, cuarto sistema) —
# a diferencia de los otros 3 prompts de elegir cartas, acá 'card_id' es un
# get_instance_id() real (Nodos persistentes del tablero), no un índice.
# =============================================================================
func _show_await_target_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige un objetivo"))
	var candidates: Array = data.get("candidates", [])
	var cancellable: bool = bool(data.get("cancellable", true))
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ningún objetivo válido ahora mismo."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "cancelled": true}))
		return

	_build_card_row(vbox, candidates)
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		_add_row_button(vbox, "%s (coste %s)" % [str(c.get("nombre", "?")), str(c.get("coste", "?"))], func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "card_id": card_id}))
	if cancellable:
		var sep := HSeparator.new()
		vbox.add_child(sep)
		_add_row_button(vbox, "Cancelar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "cancelled": true}))


func _show_await_multi_target_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige objetivo(s)"))
	var candidates: Array = data.get("candidates", [])
	var max_sel: int = int(data.get("max_selections", -1))
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ningún objetivo válido ahora mismo."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_multi_target_choice", "card_ids": []}))
		return

	_build_card_row(vbox, candidates)
	var checkboxes3: Dictionary = {}  # card_id (String) -> CheckBox
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes3[card_id] = cb
		var lbl2 := Label.new()
		lbl2.text = "%s (coste %s)" % [str(c.get("nombre", "?")), str(c.get("coste", "?"))]
		row.add_child(lbl2)

	_add_row_button(vbox, "Confirmar", func():
		var chosen_ids: Array = []
		for card_id in checkboxes3:
			if checkboxes3[card_id].button_pressed:
				chosen_ids.append(card_id)
		if max_sel >= 0 and chosen_ids.size() > max_sel:
			chosen_ids = chosen_ids.slice(0, max_sel)
		_send_intent_and_close({"op": "intent", "kind": "await_multi_target_choice", "card_ids": chosen_ids}))


# =============================================================================
# CARRERA "OBJETIVO O CASTILLO" (CardInteractionModule.await_target_or_
# castillo_pick(), 2026-10-07, arquitectura.md §41) — junta cartas
# candidatas + Castillo propio/rival en un solo prompt, ya que del lado del
# Remoto no hay carrera real entre dos interacciones simultáneas de UI.
# =============================================================================
func _show_await_target_or_castillo_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige un objetivo"))
	var candidates: Array = data.get("candidates", [])
	var castillo_title: String = str(data.get("castillo_title", "Castillo"))
	var castillo_own_only: bool = bool(data.get("castillo_own_only", false))
	var cancellable: bool = bool(data.get("cancellable", true))
	var vbox := _build_overlay(title)

	_build_card_row(vbox, candidates)
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		_add_row_button(vbox, "%s (coste %s)" % [str(c.get("nombre", "?")), str(c.get("coste", "?"))], func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "card", "card_id": card_id}))

	var sep := HSeparator.new()
	vbox.add_child(sep)
	_add_row_button(vbox, "%s — Tu Castillo" % castillo_title, func():
		_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo", "own": true}))
	if not castillo_own_only:
		_add_row_button(vbox, "%s — Castillo rival" % castillo_title, func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo", "own": false}))
	if cancellable:
		_add_row_button(vbox, "Cancelar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "none"}))


# =============================================================================
# ELECCIÓN DE OPCIÓN DE TEXTO (SelectionDialogs.await_choice()/await_two_
# choice(), Fase 3 del plan de paridad remota) — la otra familia de UI
# aparte de "elegir cartas": popups de botones de texto (A/B, o N opciones),
# sin cartas de por medio. Mismo criterio de bajo pulido que el resto.
# =============================================================================
func _show_choose_option_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige una opción"))
	var options: Array = data.get("options", [])
	var vbox := _build_overlay(title)
	for i in range(options.size()):
		var idx: int = i
		_add_row_button(vbox, str(options[i]), func():
			_send_intent_and_close({"op": "intent", "kind": "choose_option_choice", "index": idx}))


# =============================================================================
# NOMBRAR UNA CARTA (CardNameSearchDialog.open_and_wait(), 2026-10-07,
# arquitectura.md §42) — a diferencia de los otros 6 puentes, este no manda
# ninguna lista de candidatas: el Remoto ya tiene su propia CardDatabase
# cargada (mismo catálogo que el Anfitrión), así que corre el MISMO
# buscador en vivo con arte real, enteramente local a su pantalla — solo
# el resultado final viaja por red. No usa _build_overlay()/_current_
# overlay (CardNameSearchDialog ya administra su propio CanvasLayer y se
# autodestruye sola al resolverse).
# =============================================================================
func _show_name_card_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Nombra una carta"))
	var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(title)
	NetworkClient.send_message({"op": "intent", "kind": "name_card_choice", "card_data": picked})


# =============================================================================
# BOTÓN DE PASO DEL REMOTO (2026-10-11, a pedido del usuario: "el botón de
# paso tiene que funcionar para el jugador 1 y el jugador 2") — el mismo
# botón del HUD que usa el Anfitrión. Como este cliente no corre GameManager
# propio, el texto/visibilidad los decide el prompt activo y el click (o la
# tecla P, vía PhaseFlowController._on_paso_pressed()) ejecuta _paso_action.
# =============================================================================
func on_paso_pressed() -> void:
	if _paso_action.is_valid():
		_paso_action.call()


func _set_remote_paso(text: String, glow: bool, action: Callable) -> void:
	_paso_action = action
	if _main._game_hud:
		_main._game_hud.show_paso_button_with_text(text, glow)


func _clear_remote_paso() -> void:
	_paso_action = Callable()
	_priority_window_id = -1
	if _main._game_hud:
		_main._game_hud.stop_paso_countdown()
		_main._game_hud.stop_paso_glow()
		_main._game_hud.hide_paso_button()


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
		var confirm_blocks: Callable = _build_blockers_panel(attackers, blockers, respond)
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
		if not abilities.is_empty():
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


func _build_blockers_panel(attackers: Array, blockers: Array, respond: Callable) -> Callable:
	"""Un selector por cada Aliado propio que puede bloquear: 'No bloquea' o
	el atacante al que bloquea. Devuelve la acción de confirmar (la usan el
	botón del panel y el botón de paso del HUD)."""
	var vbox := _build_overlay("Bloqueo — elige tus bloqueadores")
	var attacker_names: Dictionary = {}
	for a in attackers:
		attacker_names[str(a.get("card_id", ""))] = str(a.get("nombre", "?"))
	if not attackers.is_empty():
		var a_lbl := Label.new()
		a_lbl.text = "Atacan:"
		vbox.add_child(a_lbl)
		_build_card_row(vbox, attackers)

	var selectors: Dictionary = {}  # blocker_id -> {option: OptionButton, ids: Array}
	for b in blockers:
		var blocker_id: String = str(b.get("card_id", ""))
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var lbl := Label.new()
		lbl.text = "%s →" % str(b.get("nombre", "?"))
		lbl.custom_minimum_size = Vector2(200, 0)
		row.add_child(lbl)
		var option := OptionButton.new()
		option.add_item("No bloquea")
		var ids: Array = [""]
		for attacker_id in b.get("can_block", []):
			option.add_item("Bloquea a %s" % attacker_names.get(str(attacker_id), "?"))
			ids.append(str(attacker_id))
		row.add_child(option)
		selectors[blocker_id] = {"option": option, "ids": ids}

	var confirm := func():
		var pairs: Array = []
		var used_attackers: Dictionary = {}
		for blocker_id in selectors:
			var sel: Dictionary = selectors[blocker_id]
			var attacker_id: String = sel.ids[sel.option.selected]
			if attacker_id.is_empty() or used_attackers.has(attacker_id):
				continue  # un atacante solo puede tener un bloqueador
			used_attackers[attacker_id] = true
			pairs.append({"blocker_id": blocker_id, "attacker_id": attacker_id})
		respond.call({"action": "blocks", "pairs": pairs})

	var sep := HSeparator.new()
	vbox.add_child(sep)
	_add_row_button(vbox, "Confirmar bloqueos", confirm)
	return confirm


# =============================================================================
# MANO FÍSICA COMO ÚNICA FORMA DE JUGAR (2026-10-11)
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


func _clear_hand_actions() -> void:
	for card_id in _hand_actions:
		var node: Node = _hand_card_nodes.get(card_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_playable")
	_hand_actions = {}
