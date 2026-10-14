extends Control
## ShadowForgeLogin — Pantalla de vinculación con la cuenta de ShadowForge.
## Permite sincronizar los mazos creados en la nube con feedback visual,
## spinner animado de carga y estados limpios.

var _spinner_rotation: float = 0.0
var _pulse_tween: Tween = null

@onready var loading_box: VBoxContainer = %LoadingBox
@onready var loading_spinner: Control = %LoadingSpinner
@onready var loading_text: Label = %LoadingText
@onready var connected_box: VBoxContainer = %ConnectedBox
@onready var account_name_label: Label = %AccountNameLabel
@onready var logout_button: Button = %LogoutButton
@onready var login_box: VBoxContainer = %LoginBox
@onready var username_edit: LineEdit = %UsernameEdit
@onready var password_edit: LineEdit = %PasswordEdit
@onready var login_button: Button = %LoginButton
@onready var status_label: Label = %StatusLabel
@onready var back_button: TextureButton = %BackButton


func _ready() -> void:
	_setup_button_hover(login_button)
	_setup_button_hover(logout_button)
	_setup_texture_button_hover(back_button)

	login_button.pressed.connect(_on_login_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	back_button.pressed.connect(_on_back_pressed)

	username_edit.text_submitted.connect(func(_text: String): password_edit.grab_focus())
	password_edit.text_submitted.connect(func(_text: String): _on_login_pressed())

	loading_spinner.draw.connect(_on_spinner_draw)

	ExternalApiClient.login_succeeded.connect(_on_login_succeeded)
	ExternalApiClient.login_failed.connect(_on_login_failed)
	ExternalApiClient.profile_received.connect(_on_profile_received)
	ExternalApiClient.profile_failed.connect(_on_profile_failed)

	_refresh_connected_state()


func _process(delta: float) -> void:
	if loading_box.visible:
		_spinner_rotation += delta * 4.5
		loading_spinner.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()
			_on_back_pressed()


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


func _on_spinner_draw() -> void:
	# Dibuja un arco esmeralda arcano giratorio con estela de luz
	var center = Vector2.ZERO
	var radius = 22.0
	var arc_len = TAU * 0.72

	# Anillo base tenue
	loading_spinner.draw_arc(center, radius, 0.0, TAU, 32, Color(0.15, 0.35, 0.2, 0.4), 2.5, true)
	# Arco giratorio brillante
	loading_spinner.draw_arc(
		center,
		radius,
		_spinner_rotation,
		_spinner_rotation + arc_len,
		28,
		Color(0.4, 0.95, 0.55, 0.95),
		3.2,
		true
	)
	# Núcleo interior místico
	loading_spinner.draw_circle(center, 4.0, Color(0.6, 1.0, 0.7, 0.9))


func _show_loading(message: String) -> void:
	loading_text.text = message
	loading_box.visible = true
	connected_box.visible = false
	login_box.visible = false

	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(loading_text, "modulate:a", 0.45, 0.75).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(loading_text, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE)


func _show_connected(display_name: String) -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	loading_box.visible = false
	login_box.visible = false
	connected_box.visible = true
	account_name_label.text = display_name


func _show_login_form(error_msg: String = "") -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	loading_box.visible = false
	connected_box.visible = false
	login_box.visible = true
	status_label.text = error_msg
	if error_msg.is_empty():
		username_edit.grab_focus()


func _refresh_connected_state() -> void:
	if ExternalApiClient.is_authenticated():
		_show_loading("Verificando sesión...")
		ExternalApiClient.fetch_my_profile()
	else:
		_show_login_form()


func _on_login_pressed() -> void:
	var username := username_edit.text.strip_edges()
	var password := password_edit.text
	if username.is_empty() or password.is_empty():
		status_label.text = "Ingresa usuario y contraseña."
		return

	_show_loading("Conectando con ShadowForge...")
	ExternalApiClient.save_credentials(username, password)
	ExternalApiClient.login()


func _on_login_succeeded() -> void:
	password_edit.text = ""
	_show_loading("Cargando perfil...")
	ExternalApiClient.fetch_my_profile()


func _on_login_failed(reason: String) -> void:
	_show_login_form("Error de conexión: %s" % reason)


func _on_profile_received(profile: Dictionary) -> void:
	var display_name := str(profile.get("username", profile.get("email", "Cuenta Vinculada")))
	_show_connected(display_name)


func _on_profile_failed(_reason: String) -> void:
	# Si ya hay token pero falló el perfil, permanece conectado con nombre por defecto
	_show_connected("Cuenta Vinculada")


func _on_logout_pressed() -> void:
	ExternalApiClient.logout()
	username_edit.text = ""
	password_edit.text = ""
	_show_login_form()


func _on_back_pressed() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
