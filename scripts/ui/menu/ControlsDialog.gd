extends CanvasLayer
class_name ControlsDialog
## ControlsDialog — Diálogo modal para reasignar atajos de teclado y controles.
## Compatible tanto con el Menú Principal como con el Menú de Pausa en partida.

signal closed

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/Marcellus-Regular.ttf")

var _backdrop: ColorRect = null
var _modal_panel: PanelContainer = null
var _action_buttons: Dictionary = {}
var _listening_action: String = ""
var _listen_tween: Tween = null
var _btn_close: Button = null
var _btn_reset: Button = null


func _init() -> void:
	layer = 135
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()
	_refresh_buttons()


func open_dialog() -> void:
	visible = true
	_listening_action = ""
	_refresh_buttons()

	# Animación de apertura suave
	_backdrop.modulate.a = 0.0
	_modal_panel.scale = Vector2(0.9, 0.9)
	_modal_panel.modulate.a = 0.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(_modal_panel, "modulate:a", 1.0, 0.20)
	tween.tween_property(_modal_panel, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	call_deferred("_focus_first_element")


func close_dialog() -> void:
	if _listening_action != "":
		_cancel_listening()

	var tween = create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_property(_modal_panel, "modulate:a", 0.0, 0.15)
	tween.tween_property(_modal_panel, "scale", Vector2(0.92, 0.92), 0.15).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		visible = false
		closed.emit()
	)


func _focus_first_element() -> void:
	if _btn_close and is_instance_valid(_btn_close):
		_btn_close.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _listening_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()

			if event.keycode == KEY_ESCAPE:
				_cancel_listening()
			else:
				_assign_key(_listening_action, event.keycode)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()
			close_dialog()


func _assign_key(action: String, new_keycode: int) -> void:
	# Si otra acción ya usaba esta tecla, intercambiar para evitar duplicados
	for other_action in GameSettings.DEFAULT_KEYBINDINGS.keys():
		if other_action != action and GameSettings.get_key(other_action) == new_keycode:
			var current_key = GameSettings.get_key(action)
			GameSettings.set_key(other_action, current_key)
			break

	GameSettings.set_key(action, new_keycode)
	_listening_action = ""
	if _listen_tween and _listen_tween.is_valid():
		_listen_tween.kill()
	_refresh_buttons()


func _cancel_listening() -> void:
	_listening_action = ""
	if _listen_tween and _listen_tween.is_valid():
		_listen_tween.kill()
	_refresh_buttons()


func _build_ui() -> void:
	# 1. Telón oscuro de fondo
	_backdrop = ColorRect.new()
	_backdrop.name = "ControlsBackdrop"
	_backdrop.color = Color(0.02, 0.03, 0.05, 0.88)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			if _listening_action != "":
				_cancel_listening()
			else:
				close_dialog()
	)
	add_child(_backdrop)

	# 2. Panel modal central
	_modal_panel = PanelContainer.new()
	_modal_panel.name = "ControlsModalPanel"
	_modal_panel.custom_minimum_size = Vector2(560, 520)
	_modal_panel.anchors_preset = Control.PRESET_CENTER
	_modal_panel.anchor_left = 0.5
	_modal_panel.anchor_top = 0.5
	_modal_panel.anchor_right = 0.5
	_modal_panel.anchor_bottom = 0.5
	_modal_panel.offset_left = -280
	_modal_panel.offset_top = -260
	_modal_panel.offset_right = 280
	_modal_panel.offset_bottom = 260
	_modal_panel.pivot_offset = Vector2(280, 260)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	panel_style.border_color = Color(0.78, 0.65, 0.32, 0.90)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.shadow_color = Color(0, 0, 0, 0.85)
	panel_style.shadow_size = 28
	_modal_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_modal_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	_modal_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Encabezado
	var title = Label.new()
	title.text = "CONFIGURACIÓN DE CONTROLES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.92, 0.80, 0.38, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Haz clic en una tecla para reasignarla. Presiona ESC para cancelar."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", FONT_TEXT)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80, 1.0))
	vbox.add_child(subtitle)

	vbox.add_child(_create_separator())

	# Lista de acciones
	var rows_vbox = VBoxContainer.new()
	rows_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(rows_vbox)

	for action in GameSettings.DEFAULT_KEYBINDINGS.keys():
		var row = _create_action_row(action)
		rows_vbox.add_child(row)

	vbox.add_child(_create_separator())

	# Botones inferiores
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	_btn_reset = _create_bottom_button("RESTAURAR DEFECTO", _on_reset_pressed, Color(0.85, 0.75, 0.55, 1.0))
	_btn_reset.custom_minimum_size = Vector2(230, 40)
	btn_hbox.add_child(_btn_reset)

	_btn_close = _create_bottom_button("CERRAR", close_dialog, Color(1.0, 0.92, 0.65, 1.0))
	_btn_close.custom_minimum_size = Vector2(180, 40)
	btn_hbox.add_child(_btn_close)


func _create_action_row(action: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(text_vbox)

	var action_name = Label.new()
	action_name.text = GameSettings.ACTION_LABELS.get(action, action.capitalize())
	action_name.add_theme_font_override("font", FONT_TITLE)
	action_name.add_theme_font_size_override("font_size", 14)
	action_name.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 1.0))
	text_vbox.add_child(action_name)

	var action_desc = Label.new()
	action_desc.text = GameSettings.ACTION_DESCRIPTIONS.get(action, "")
	action_desc.add_theme_font_override("font", FONT_TEXT)
	action_desc.add_theme_font_size_override("font_size", 11)
	action_desc.add_theme_color_override("font_color", Color(0.60, 0.65, 0.75, 0.90))
	text_vbox.add_child(action_desc)

	var key_btn = Button.new()
	key_btn.custom_minimum_size = Vector2(170, 36)
	key_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	key_btn.add_theme_font_override("font", FONT_TITLE)
	key_btn.add_theme_font_size_override("font_size", 13)

	var style_n = StyleBoxFlat.new()
	style_n.bg_color = Color(0.12, 0.16, 0.22, 0.96)
	style_n.border_color = Color(0.72, 0.60, 0.32, 0.85)
	style_n.set_border_width_all(1)
	style_n.set_corner_radius_all(4)

	var style_h = style_n.duplicate() as StyleBoxFlat
	style_h.bg_color = Color(0.18, 0.25, 0.35, 1.0)
	style_h.border_color = Color(1.0, 0.88, 0.45, 1.0)
	style_h.set_border_width_all(2)

	key_btn.add_theme_stylebox_override("normal", style_n)
	key_btn.add_theme_stylebox_override("hover", style_h)
	key_btn.add_theme_stylebox_override("pressed", style_h)
	key_btn.add_theme_stylebox_override("focus", style_h)
	key_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82, 1.0))
	key_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.95, 1.0))
	key_btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	key_btn.add_theme_constant_override("outline_size", 1)

	key_btn.pressed.connect(_on_action_button_pressed.bind(action))
	hbox.add_child(key_btn)
	_action_buttons[action] = key_btn

	return hbox


func _on_action_button_pressed(action: String) -> void:
	if _listening_action == action:
		_cancel_listening()
		return

	if _listening_action != "":
		_cancel_listening()

	_listening_action = action
	_start_listening_visuals(action)


func _start_listening_visuals(action: String) -> void:
	if not _action_buttons.has(action):
		return
	var btn: Button = _action_buttons[action]
	btn.text = "[ PULSA TECLA ]"
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))

	if _listen_tween and _listen_tween.is_valid():
		_listen_tween.kill()

	_listen_tween = btn.create_tween().set_loops()
	_listen_tween.tween_property(btn, "modulate:a", 0.5, 0.35).set_ease(Tween.EASE_IN_OUT)
	_listen_tween.tween_property(btn, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_IN_OUT)


func _refresh_buttons() -> void:
	for action in _action_buttons.keys():
		var btn: Button = _action_buttons[action]
		if not is_instance_valid(btn):
			continue
		btn.modulate.a = 1.0
		var keycode: int = GameSettings.get_key(action)
		var key_name: String = GameSettings.get_key_display_string(keycode)
		btn.text = "[ %s ]" % key_name
		btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82, 1.0))


func _on_reset_pressed() -> void:
	_listening_action = ""
	if _listen_tween and _listen_tween.is_valid():
		_listen_tween.kill()
	GameSettings.reset_keybindings_to_default()
	_refresh_buttons()


func _create_bottom_button(label_text: String, callback: Callable, accent_color: Color) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", 13)

	var style_n = StyleBoxFlat.new()
	style_n.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	style_n.border_color = accent_color * 0.8
	style_n.set_border_width_all(1)
	style_n.set_corner_radius_all(6)

	var style_h = style_n.duplicate() as StyleBoxFlat
	style_h.bg_color = Color(0.18, 0.24, 0.34, 1.0)
	style_h.border_color = accent_color
	style_h.set_border_width_all(2)

	btn.add_theme_stylebox_override("normal", style_n)
	btn.add_theme_stylebox_override("hover", style_h)
	btn.add_theme_stylebox_override("pressed", style_h)
	btn.add_theme_stylebox_override("focus", style_h)
	btn.add_theme_color_override("font_color", accent_color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	btn.add_theme_constant_override("outline_size", 1)

	btn.pressed.connect(callback)
	return btn


func _create_separator() -> HSeparator:
	var sep = HSeparator.new()
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(0.78, 0.65, 0.32, 0.35)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep
