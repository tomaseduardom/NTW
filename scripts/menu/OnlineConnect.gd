extends Control
## OnlineConnect — Pantalla de conexión multijugador en línea (Fase A).
## Permite crear una sala privada (Anfitrión) o unirse con código (Invitado)
## a través del relay de WebSockets antes de entrar al duelo.

const DEFAULT_RELAY_URL := "wss://mitos-relay-server-production.up.railway.app"

var _pending_action: String = ""
var _current_room_code: String = ""
var _pulse_tween: Tween = null
var _copy_timer: SceneTreeTimer = null

@onready var create_room_button: Button = %CreateRoomButton
@onready var code_display_box: PanelContainer = %CodeDisplayBox
@onready var room_code_label: Label = %RoomCodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var waiting_peer_label: Label = %WaitingPeerLabel
@onready var code_edit: LineEdit = %CodeEdit
@onready var join_room_button: Button = %JoinRoomButton
@onready var status_label: Label = %StatusLabel
@onready var back_button: TextureButton = %BackButton
@onready var relay_toggle_btn: Button = %RelayToggleBtn
@onready var relay_box: PanelContainer = %RelayBox
@onready var relay_url_edit: LineEdit = %RelayUrlEdit


func _ready() -> void:
	relay_url_edit.text = DEFAULT_RELAY_URL
	relay_box.visible = false
	code_display_box.visible = false
	status_label.text = ""

	_setup_button_hover(create_room_button)
	_setup_button_hover(join_room_button)
	_setup_button_hover(copy_code_button)
	_setup_texture_button_hover(back_button)

	create_room_button.pressed.connect(_on_create_room_pressed)
	join_room_button.pressed.connect(_on_join_room_pressed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	back_button.pressed.connect(_on_back_pressed)
	relay_toggle_btn.pressed.connect(_on_relay_toggle_pressed)

	code_edit.text_changed.connect(_on_code_edit_text_changed)
	code_edit.text_submitted.connect(_on_code_edit_submitted)

	NetworkClient.connected_to_relay.connect(_on_connected_to_relay)
	NetworkClient.connection_failed.connect(_on_connection_failed)
	NetworkClient.room_created.connect(_on_room_created)
	NetworkClient.room_joined.connect(_on_room_joined)
	NetworkClient.peer_joined.connect(_on_peer_ready)
	NetworkClient.peer_disconnected.connect(_on_peer_disconnected)
	NetworkClient.relay_error.connect(_on_relay_error)

	# Foco inicial en crear sala
	create_room_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_back_pressed()
			get_viewport().set_input_as_handled()


func _setup_button_hover(btn: Button) -> void:
	if not btn:
		return
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_entered.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "modulate", Color(1.15, 1.15, 1.15, 1.0), 0.12)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
	)


func _setup_texture_button_hover(btn: TextureButton) -> void:
	if not btn:
		return
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_entered.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.12).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	)


func _on_code_edit_text_changed(new_text: String) -> void:
	var upper = new_text.to_upper().strip_edges()
	if new_text != upper:
		code_edit.text = upper
		code_edit.caret_column = upper.length()


func _on_code_edit_submitted(_text: String) -> void:
	_on_join_room_pressed()


func _on_relay_toggle_pressed() -> void:
	relay_box.visible = not relay_box.visible
	if relay_box.visible:
		relay_url_edit.grab_focus()


func _on_create_room_pressed() -> void:
	_set_busy("Conectando al servidor del reino...")
	_pending_action = "create"
	NetworkClient.connect_to_relay(relay_url_edit.text.strip_edges())


func _on_join_room_pressed() -> void:
	var code = code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Por favor ingresa el código de sala."
		code_edit.grab_focus()
		return
	_set_busy("Conectando al servidor del reino...")
	_pending_action = "join"
	NetworkClient.connect_to_relay(relay_url_edit.text.strip_edges())


func _on_connected_to_relay() -> void:
	if _pending_action == "create":
		status_label.text = "Conectado. Generando sala de batalla..."
		NetworkClient.create_room()
	elif _pending_action == "join":
		status_label.text = "Conectado. Accediendo a la sala..."
		NetworkClient.join_room(code_edit.text.strip_edges().to_upper())


func _on_connection_failed(reason: String) -> void:
	status_label.text = "No se pudo conectar al servidor: %s" % reason
	_set_busy_done()


func _on_room_created(code: String) -> void:
	_current_room_code = code
	# Formatear el código con espacios entre letras para máximo impacto visual
	var formatted_code = ""
	for i in range(code.length()):
		formatted_code += code[i]
		if i < code.length() - 1:
			formatted_code += "  "

	room_code_label.text = formatted_code
	create_room_button.visible = false
	code_display_box.visible = true
	code_display_box.modulate.a = 0.0

	var tw = code_display_box.create_tween()
	tw.tween_property(code_display_box, "modulate:a", 1.0, 0.25)

	# Iniciar suave pulso de espera
	_start_waiting_pulse()

	status_label.text = "¡Sala creada con éxito! Comparte el código con tu rival."
	_set_busy_done()


func _start_waiting_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(waiting_peer_label, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(waiting_peer_label, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)


func _on_copy_code_pressed() -> void:
	if _current_room_code.is_empty():
		return
	DisplayServer.clipboard_set(_current_room_code)
	copy_code_button.text = "¡CÓDIGO COPIADO!"
	var tw = copy_code_button.create_tween()
	tw.tween_property(copy_code_button, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.1)
	tw.tween_property(copy_code_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

	_copy_timer = get_tree().create_timer(1.8)
	_copy_timer.timeout.connect(func():
		if is_instance_valid(copy_code_button):
			copy_code_button.text = "COPIAR CÓDIGO"
	)


func _on_room_joined(_code: String) -> void:
	status_label.text = "¡Conectado! Entrando a la partida..."
	_enter_match()


func _on_peer_ready() -> void:
	status_label.text = "¡Rival encontrado! Iniciando duelo..."
	_enter_match()


func _on_peer_disconnected() -> void:
	status_label.text = "El contrincante se ha desconectado."


func _on_relay_error(message: String) -> void:
	status_label.text = "Aviso: %s" % message
	_set_busy_done()


func _enter_match() -> void:
	get_tree().change_scene_to_file("res://scenes/game/Main.tscn")


func _on_back_pressed() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	NetworkClient.disconnect_from_relay()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")


func _set_busy(text: String) -> void:
	status_label.text = text
	create_room_button.disabled = true
	join_room_button.disabled = true
	code_edit.editable = false


func _set_busy_done() -> void:
	create_room_button.disabled = false
	join_room_button.disabled = false
	code_edit.editable = true
