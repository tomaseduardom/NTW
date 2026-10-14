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
const CastleLookWindowScript = preload("res://scripts/ui/zones/CastleLookWindow.gd")

var _card_nodes: Dictionary = {}  # card_id (String) -> Node local (ghost)
var _hand_card_nodes: Dictionary = {}  # card_id (String) -> Node local en player_hand (§45)
## card_ids sin habilidad según el Anfitrión (op "disabled_cards", §63).
var _disabled_ids: Dictionary = {}
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
## card_id de un Aliado propio en juego que puede atacar -> si está marcado
## como atacante (Fase de Ataque del Remoto, 2026-10-11).
var _attack_candidates: Dictionary = {}
## Bloqueo en el tablero (2026-10-11): blocker_id -> [attacker_id válidos],
## blocker_id -> attacker_id asignado, y el bloqueador que espera que se
## elija su atacante ("" si ninguno).
var _block_options: Dictionary = {}
var _block_pairs: Dictionary = {}
var _block_pending_blocker: String = ""
## Selección genérica sobre el tablero/mano (2026-10-11): card_id -> qué hacer
## al clickearla (portador de Arma, objetivo de un efecto, habilidad de
## respuesta). _pick_multi guarda las marcadas en una selección múltiple.
var _pick_targets: Dictionary = {}
var _pick_multi: Dictionary = {}


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
			_clear_attack_candidates()
			_clear_board_blocking()
			_clear_board_pick()
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
				"zone_pick":
					_show_zone_pick_prompt(data)
				"castle_look":
					# Misma ventana que el Anfitrión (CastleLook.gd, §69):
					# repartir las cartas miradas y ordenar el resto.
					var look_window = CastleLookWindowScript.new()
					var result: Dictionary = await look_window.open(_main, data.get("config", {}))
					NetworkClient.send_message({"op": "intent", "kind": "castle_look_choice", "result": result})
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
	if intent.get("kind", "") in ["place_gold", "play_card", "end_vigilia", "activate_ability"]:
		_pending_vigilia = {}
	NetworkClient.send_message(intent)
	_close_current_overlay()
	_clear_remote_paso()
	_clear_hand_actions()
	_clear_attack_candidates()
	_clear_board_blocking()
	_clear_board_pick()


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
		# Mulligan simultáneo (2026-10-12): si el Anfitrión todavía está
		# eligiendo, se espera aquí; lo tapa el primer mensaje de partida
		# iniciada (castillo_counts, ver _on_message()).
		var loading := _main.get_node_or_null("/root/MatchLoadingOverlay")
		if loading:
			loading.show_loading(_main, "ESPERANDO JUGADOR",
				"Tu mano ya está lista — esperando a que el otro jugador elija la suya...")
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
	# Habilidades activadas de sus cartas en juego (2026-10-12): brillan en
	# dorado; clic en la carta para usarla (misma UI que en las ventanas de
	# respuesta).
	var abilities: Array = []
	for a in data.get("abilities", []):
		# Una carta de la mano que también se puede jugar (doble clic) no se
		# ofrece para habilidad aquí: el primer clic del doble clic la
		# activaría sin querer.
		if not actions.has(str(a.get("card_id", ""))):
			abilities.append(a)
	if not abilities.is_empty():
		_start_ability_pick(abilities, func(choice: Dictionary) -> void:
			_send_intent_and_close({"op": "intent", "kind": "activate_ability",
				"card_id": str(choice.get("card_id", "")), "ability_index": int(choice.get("ability_index", 0))}))
	_main._update_debug("Tu Vigilia — Oro disponible: %d. Doble clic en una carta brillante para jugarla%s." % [
		int(data.get("gold_reserva", 0)), "; clic en una carta dorada para usar su habilidad" if not abilities.is_empty() else ""])
	_set_remote_paso("Atacar [P]", false, func():
		_send_intent_and_close({"op": "intent", "kind": "end_vigilia"}))

# =============================================================================
# ATAQUE
# =============================================================================
func _show_ataque_prompt(data: Dictionary) -> void:
	# 2026-10-11 (a pedido del usuario): sin popup — los Aliados que pueden
	# atacar brillan en tu Línea de Defensa (los Nodos espejados de
	# _card_nodes, mismo card_id que manda el Anfitrión). Un clic los marca/
	# desmarca como atacantes (tinte naranja, como en la pantalla del
	# Anfitrión) y el botón de paso del HUD confirma. Ver on_card_clicked().
	var attackable: Array = data.get("attackable", [])
	if attackable.is_empty():
		_main._update_debug("No tienes ningún Aliado que pueda atacar.")
		_set_remote_paso("Pasar [P]", false, func():
			_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": []}))
		return

	for card in attackable:
		var card_id: String = str(card.get("card_id", ""))
		var node: Node = _card_nodes.get(card_id, null)
		if not node or not is_instance_valid(node):
			continue
		_attack_candidates[card_id] = false
		node.can_interact = true
		node.set_activatable(true, CardBadges.GLOW_COLOR_CELESTE, &"remote_attackable")
	_main._update_debug("Clic en tus Aliados brillantes para elegir atacantes, luego Confirmar ataque.")
	_set_remote_paso("Confirmar ataque [P]", false, func():
		var chosen_ids: Array = []
		for card_id in _attack_candidates:
			if _attack_candidates[card_id]:
				chosen_ids.append(card_id)
		_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": chosen_ids}))

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
	var on_wielder := func(card_id: String) -> void:
		_send_intent_and_close({"op": "intent", "kind": "choose_wielder", "card_id": card_id})
	if not candidates.is_empty() and _start_board_pick(_ids_of(candidates), on_wielder):
		_main._update_debug("Elige quién porta %s: clic en uno de tus Aliados brillantes" % str(
			weapon.get("nombre", "el Arma")))
		return
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
	var on_target := func(card_id: String) -> void:
		_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "card_id": card_id})
	if not candidates.is_empty() and _start_board_pick(_ids_of(candidates), on_target):
		_main._update_debug("%s: clic en una carta brillante" % title)
		if cancellable:
			_set_remote_paso("Cancelar [P]", false, func():
				_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "cancelled": true}))
		return
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
	if not candidates.is_empty() and _start_board_pick(_ids_of(candidates), _toggle_multi_pick.bind(max_sel)):
		_main._update_debug("%s: clic en las cartas brillantes para marcarlas, luego Confirmar" % title)
		_set_remote_paso("Confirmar [P]", false, func():
			var chosen_ids: Array = []
			for id in _pick_multi:
				chosen_ids.append(id)
			_send_intent_and_close({"op": "intent", "kind": "await_multi_target_choice", "card_ids": chosen_ids}))
		return
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
	var on_card := func(card_id: String) -> void:
		_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "card",
			"card_id": card_id})
	if candidates.is_empty() or _start_board_pick(_ids_of(candidates), on_card):
		_start_remote_castillo_pick(castillo_title, castillo_own_only)
		_main._update_debug("%s: clic en una carta brillante o en un Castillo" % title)
		if cancellable:
			_set_remote_paso("Cancelar [P]", false, func():
				_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "none"}))
		return
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


func _clear_hand_actions() -> void:
	for card_id in _hand_actions:
		var node: Node = _hand_card_nodes.get(card_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_playable")
	_hand_actions = {}


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


func _clear_attack_candidates() -> void:
	for card_id in _attack_candidates:
		var node: Node = _card_nodes.get(card_id, null)
		if node and is_instance_valid(node):
			node.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"remote_attackable")
			node.can_interact = false
			node.modulate = Color.WHITE
	_attack_candidates = {}


# =============================================================================
# BLOQUEO EN EL TABLERO (2026-10-11, a pedido del usuario) — mismo gesto que
# el Anfitrión (CardInteractionModule._declare_blocker()): clic en tu Aliado
# brillante; si puede bloquear a un solo atacante libre se asigna directo,
# si no los atacantes posibles brillan en rojo y eliges con otro clic. Clic
# en un bloqueador ya asignado lo libera. El botón de paso confirma.
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
	_refresh_block_glows()
	_main._update_debug("Te atacan %d Aliado(s). Clic en tus Aliados brillantes para bloquear, luego Confirmar." % (
		attackers.size()))
	return func():
		var pairs: Array = []
		for blocker_id in _block_pairs:
			pairs.append({"blocker_id": blocker_id, "attacker_id": _block_pairs[blocker_id]})
		respond.call({"action": "blocks", "pairs": pairs})


func _on_board_block_click(card_id: String) -> void:
	if _block_options.has(card_id):
		_block_pending_blocker = ""
		if _block_pairs.has(card_id):
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
	for attacker_id in _block_options.get(blocker_id, []):
		if not (attacker_id in _block_pairs.values()):
			free.append(attacker_id)
	return free


func _assign_block(blocker_id: String, attacker_id: String) -> void:
	_block_pairs[blocker_id] = attacker_id
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
		node.set_activatable(not assigned, CardBadges.GLOW_COLOR_CELESTE, &"remote_blocker")
		for attacker_id in _block_options[blocker_id]:
			var a_node: Node = _card_nodes.get(attacker_id, null)
			if not a_node or not is_instance_valid(a_node):
				continue
			var is_target: bool = attacker_id in targets
			a_node.can_interact = is_target
			a_node.set_activatable(is_target, CardBadges.GLOW_COLOR_RED, &"remote_block_target")


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
	_block_pending_blocker = ""


# =============================================================================
# SELECCIÓN SOBRE EL TABLERO/MANO (2026-10-11, a pedido del usuario: "sigamos
# con los demás popups") — portador de Arma, objetivos de efectos y
# habilidades de respuesta se eligen con clic sobre la carta real (brillo
# celeste si es tuya, rojo si es del rival). Si algún candidato no tiene
# Nodo visible en esta pantalla (p.ej. una carta de la mano del Anfitrión),
# se cae al popup de siempre para no esconder una opción válida.
# =============================================================================
func _visible_id_of(card: Node) -> String:
	for id in _card_nodes:
		if _card_nodes[id] == card:
			return id
	for id in _hand_card_nodes:
		if _hand_card_nodes[id] == card:
			return id
	return ""


func _visible_node(card_id: String) -> Node:
	var node: Node = _card_nodes.get(card_id, null)
	if not node:
		node = _hand_card_nodes.get(card_id, null)
	return node if node and is_instance_valid(node) else null


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


# =============================================================================
# SELECTOR DE ZONAS (ActionSearch._delegate_zone_pick_to_remote(), 2026-10-11)
# — el Remoto corre el mismo ZoneBrowsePicker que el Anfitrión, en su propia
# pantalla ('is_own' ya viene relativo a él), y devuelve los índices elegidos.
# =============================================================================
func _show_zone_pick_prompt(data: Dictionary) -> void:
	var pools: Array = []
	for p in data.get("pools", []):
		var cards: Array = []
		for c in p.get("cards", []):
			cards.append({"data": c.get("data", {}), "eligible": bool(c.get("eligible", false))})
		# JSON trae los números como float — la zona se usa como clave de Dictionary.
		pools.append({"is_own": bool(p.get("is_own", true)), "zone": int(p.get("zone", 0)), "cards": cards})
	if not _main._zone_browse_picker:
		NetworkClient.send_message({"op": "intent", "kind": "zone_pick_choice", "picks": []})
		return
	# Cartas de la mano candidatas (2026-10-12, p.ej. Miguel): los ids son los
	# de la mano espejo (_hand_card_nodes). Se guarda el índice original para
	# devolverle al Anfitrión la posición en SU lista.
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
