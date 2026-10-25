extends Control
## OnlineConnect — Pantalla de conexión multijugador en línea (Fase A).
## Permite crear una sala privada (Anfitrión) o unirse con código (Invitado)
## usando cartas medievales ilustradas con ranuras interactivas para el código.

# Relay en producción (Railway, plan Hobby, 2026-10-25). Para probar en local: ws://localhost:8080.
const DEFAULT_RELAY_URL := "wss://mitos-relay-server-production.up.railway.app"
const TEX_HOST := preload("res://assets/ui/menu/online/card_host.png")
const TEX_HOST_HOVER := preload("res://assets/ui/menu/online/card_host_hover.png")
const TEX_HOST_CREATED := preload("res://assets/ui/menu/online/card_host_created.png")
const TEX_HOST_CREATED_HOVER := preload("res://assets/ui/menu/online/card_host_created_hover.png")
const TEX_JOIN := preload("res://assets/ui/menu/online/card_join.png")
const TEX_JOIN_HOVER := preload("res://assets/ui/menu/online/card_join_hover.png")

var _pending_action: String = ""
var _current_room_code: String = ""
var _pulse_tween: Tween = null
var _copy_timer: SceneTreeTimer = null

@onready var host_card: Control = %HostCard
@onready var host_card_art: TextureRect = %HostCardArt
@onready var create_room_button: Button = %CreateRoomButton
@onready var code_display_box: PanelContainer = %CodeDisplayBox
@onready var room_code_label: Label = %RoomCodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var waiting_peer_label: Label = %WaitingPeerLabel
@onready var join_card: Control = %JoinCard
@onready var join_card_art: TextureRect = %JoinCardArt
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
	code_display_box.visible = true
	copy_code_button.visible = false
	status_label.text = ""

	_setup_host_card_hover()
	_setup_join_card_hover()
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
	NetworkClient.connection_lost.connect(_on_connection_lost)
	NetworkClient.relay_error.connect(_on_relay_error)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()
			_on_back_pressed()


func _setup_host_card_hover() -> void:
	host_card.pivot_offset = host_card.custom_minimum_size / 2.0
	for btn in [create_room_button, copy_code_button]:
		btn.mouse_entered.connect(_on_host_hover.bind(true))
		btn.mouse_exited.connect(_on_host_hover.bind(false))


func _on_host_hover(hovered: bool) -> void:
	var has_room := not _current_room_code.is_empty()
	if has_room:
		host_card_art.texture = TEX_HOST_CREATED_HOVER if hovered else TEX_HOST_CREATED
	else:
		host_card_art.texture = TEX_HOST_HOVER if hovered else TEX_HOST
	var target_scale := Vector2(1.025, 1.025) if hovered else Vector2.ONE
	var tw = host_card.create_tween()
	tw.tween_property(host_card, "scale", target_scale, 0.14).set_ease(Tween.EASE_OUT)


func _setup_join_card_hover() -> void:
	join_card.pivot_offset = join_card.custom_minimum_size / 2.0
	for ctrl in [join_room_button, code_edit]:
		ctrl.mouse_entered.connect(_on_join_hover.bind(true))
		ctrl.mouse_exited.connect(_on_join_hover.bind(false))


func _on_join_hover(hovered: bool) -> void:
	join_card_art.texture = TEX_JOIN_HOVER if hovered else TEX_JOIN
	var target_scale := Vector2(1.025, 1.025) if hovered else Vector2.ONE
	var tw = join_card.create_tween()
	tw.tween_property(join_card, "scale", target_scale, 0.14).set_ease(Tween.EASE_OUT)


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
	waiting_peer_label.text = "CREANDO SALA..."
	_set_busy("Conectando al servidor...")
	_pending_action = "create"
	NetworkClient.connect_to_relay(relay_url_edit.text.strip_edges())


func _on_join_room_pressed() -> void:
	var code = code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Ingresa el código de 4 letras en la carta de Invitado."
		code_edit.grab_focus()
		return
	_set_busy("Conectando a la sala %s..." % code)
	_pending_action = "join"
	NetworkClient.connect_to_relay(relay_url_edit.text.strip_edges())


func _on_connected_to_relay() -> void:
	if _pending_action == "create":
		status_label.text = "Generando código de sala..."
		NetworkClient.create_room()
	elif _pending_action == "join":
		status_label.text = "Entrando a la sala..."
		NetworkClient.join_room(code_edit.text.strip_edges().to_upper())


func _on_connection_failed(reason: String) -> void:
	waiting_peer_label.text = ""
	status_label.text = "No se pudo conectar al servidor: %s" % reason
	_set_busy_done()


func _on_room_created(code: String) -> void:
	_current_room_code = code
	var formatted_code = ""
	for i in range(code.length()):
		formatted_code += code[i]
		if i < code.length() - 1:
			formatted_code += "  "

	room_code_label.text = formatted_code
	room_code_label.add_theme_color_override("font_color", Color(0.35, 0.92, 1.0, 1.0))

	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.04, 0.08, 0.14, 0.96)
	box_style.border_color = Color(0.35, 0.88, 1.0, 0.95)
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(10)
	box_style.shadow_color = Color(0.2, 0.75, 1.0, 0.35)
	box_style.shadow_size = 10
	code_display_box.add_theme_stylebox_override("panel", box_style)

	create_room_button.visible = false
	copy_code_button.visible = true
	host_card_art.texture = TEX_HOST_CREATED
	waiting_peer_label.text = "ESPERANDO RIVAL..."

	_start_waiting_pulse()

	status_label.text = "¡Sala creada! Comparte el código con tu rival."
	_set_busy_done()


func _start_waiting_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(waiting_peer_label, "modulate:a", 0.45, 0.85).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(waiting_peer_label, "modulate:a", 1.0, 0.85).set_trans(Tween.TRANS_SINE)


func _on_copy_code_pressed() -> void:
	if _current_room_code.is_empty():
		return
	DisplayServer.clipboard_set(_current_room_code)
	waiting_peer_label.text = "¡CÓDIGO COPIADO!"
	status_label.text = "Código %s copiado al portapapeles." % _current_room_code
	var tw = host_card.create_tween()
	tw.tween_property(host_card, "modulate", Color(1.18, 1.18, 1.18, 1.0), 0.1)
	tw.tween_property(host_card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

	_copy_timer = get_tree().create_timer(1.8)
	_copy_timer.timeout.connect(func():
		if is_instance_valid(waiting_peer_label):
			waiting_peer_label.text = "ESPERANDO RIVAL..."
	)


func _on_room_joined(_code: String) -> void:
	status_label.text = "¡Conectado! Entrando a la partida..."
	_enter_match()


func _on_peer_ready() -> void:
	status_label.text = "¡Rival encontrado! Iniciando duelo..."
	_enter_match()


func _on_peer_disconnected() -> void:
	status_label.text = "El contrincante se ha desconectado."


func _on_connection_lost() -> void:
	waiting_peer_label.text = ""
	status_label.text = "Se perdió la conexión con el servidor."
	_set_busy_done()


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

