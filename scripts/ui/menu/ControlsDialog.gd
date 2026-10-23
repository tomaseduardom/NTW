extends CanvasLayer
class_name ControlsDialog
## ControlsDialog — Diálogo modal para reasignar atajos de teclado y controles.
## Diseñado con la estética medieval de tableta de piedra, pergamino envejecido
## y botones de piedra cincelada basada fielmente en Configuracion.jpg.

signal closed

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/Marcellus-Regular.ttf")

const TEX_BG := preload("res://assets/ui/controls/dialog_tablet_bg_1280.png")
const TEX_STONE_NORMAL := preload("res://assets/ui/controls/btn_stone_normal_305.png")
const TEX_STONE_HOVER := preload("res://assets/ui/controls/btn_stone_hover_305.png")
const TEX_STONE_PRESSED := preload("res://assets/ui/controls/btn_stone_pressed_305.png")

const MODAL_WIDTH: float = 1280.0
const MODAL_HEIGHT: float = 794.0

var _backdrop: ColorRect = null
var _modal_panel: Control = null
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
	_modal_panel.scale = Vector2(0.92, 0.92)
	_modal_panel.modulate.a = 0.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.20).set_ease(Tween.EASE_OUT)
	tween.tween_property(_modal_panel, "modulate:a", 1.0, 0.22)
	tween.tween_property(_modal_panel, "scale", Vector2.ONE, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	call_deferred("_focus_first_element")


func close_dialog() -> void:
	if _listening_action != "":
		_cancel_listening()

	var tween = create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 0.0, 0.16).set_ease(Tween.EASE_IN)
	tween.tween_property(_modal_panel, "modulate:a", 0.0, 0.16)
	tween.tween_property(_modal_panel, "scale", Vector2(0.94, 0.94), 0.16).set_ease(Tween.EASE_IN)
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

	# 2. Panel modal central (Contenedor de la tableta)
	_modal_panel = Control.new()
	_modal_panel.name = "ControlsModalPanel"
	_modal_panel.custom_minimum_size = Vector2(MODAL_WIDTH, MODAL_HEIGHT)
	_modal_panel.anchors_preset = Control.PRESET_CENTER
	_modal_panel.anchor_left = 0.5
	_modal_panel.anchor_top = 0.5
	_modal_panel.anchor_right = 0.5
	_modal_panel.anchor_bottom = 0.5
	_modal_panel.offset_left = -MODAL_WIDTH * 0.5
	_modal_panel.offset_top = -MODAL_HEIGHT * 0.5
	_modal_panel.offset_right = MODAL_WIDTH * 0.5
	_modal_panel.offset_bottom = MODAL_HEIGHT * 0.5
	_modal_panel.pivot_offset = Vector2(MODAL_WIDTH * 0.5, MODAL_HEIGHT * 0.5)
	add_child(_modal_panel)

	# 3. Fondo texturizado de la tableta de piedra con pergamino y bordes tallados
	var bg_rect = TextureRect.new()
	bg_rect.name = "TabletBackground"
	bg_rect.texture = TEX_BG
	bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_panel.add_child(bg_rect)

	# 4. Contenedor de las 5 filas de acciones sobre el pergamino
	var rows_container = VBoxContainer.new()
	rows_container.name = "ActionRowsContainer"
	rows_container.offset_left = 145.0
	rows_container.offset_top = 194.0
	rows_container.offset_right = 1123.0
	rows_container.offset_bottom = 600.0
	rows_container.add_theme_constant_override("separation", 24)
	_modal_panel.add_child(rows_container)

	for action in GameSettings.DEFAULT_KEYBINDINGS.keys():
		var row = _create_action_row(action)
		rows_container.add_child(row)

	# 5. Botones interactivos inferiores (alineados sobre la barra de piedra inferior)
	# Botón RESTAURAR DEFECTO
	_btn_reset = _create_bottom_interactive_button(
		Rect2(183.0, 678.0, 404.0, 78.0),
		_on_reset_pressed,
		"Restaurar controles por defecto",
		8
	)
	_modal_panel.add_child(_btn_reset)

	# Botón CERRAR
	_btn_close = _create_bottom_interactive_button(
		Rect2(642.0, 676.0, 459.0, 82.0),
		close_dialog,
		"Cerrar menú de controles",
		6
	)
	_modal_panel.add_child(_btn_close)


func _create_action_row(action: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.custom_minimum_size = Vector2(0, 59)

	# Columna izquierda: Título y descripción de la acción
	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(text_vbox)

	var action_name = Label.new()
	var raw_name: String = GameSettings.ACTION_LABELS.get(action, action.capitalize())
	action_name.text = raw_name.to_upper()
	action_name.add_theme_font_override("font", FONT_TITLE)
	action_name.add_theme_font_size_override("font_size", 18)
	action_name.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08, 1.0))
	action_name.add_theme_color_override("font_shadow_color", Color(1.0, 0.95, 0.85, 0.50))
	action_name.add_theme_constant_override("shadow_offset_y", 1)
	text_vbox.add_child(action_name)

	var action_desc = Label.new()
	action_desc.text = GameSettings.ACTION_DESCRIPTIONS.get(action, "")
	action_desc.add_theme_font_override("font", FONT_TEXT)
	action_desc.add_theme_font_size_override("font_size", 14)
	action_desc.add_theme_color_override("font_color", Color(0.26, 0.22, 0.18, 0.95))
	text_vbox.add_child(action_desc)

	# Columna derecha: Botón de piedra cincelada
	var key_btn = Button.new()
	key_btn.custom_minimum_size = Vector2(305, 59)
	key_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	key_btn.add_theme_font_override("font", FONT_TITLE)
	key_btn.add_theme_font_size_override("font_size", 17)

	var style_n = StyleBoxTexture.new()
	style_n.texture = TEX_STONE_NORMAL
	style_n.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style_n.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

	var style_h = StyleBoxTexture.new()
	style_h.texture = TEX_STONE_HOVER
	style_h.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style_h.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

	var style_p = StyleBoxTexture.new()
	style_p.texture = TEX_STONE_PRESSED
	style_p.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style_p.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

	key_btn.add_theme_stylebox_override("normal", style_n)
	key_btn.add_theme_stylebox_override("hover", style_h)
	key_btn.add_theme_stylebox_override("pressed", style_p)
	key_btn.add_theme_stylebox_override("focus", style_h)

	# Letras talladas en piedra: carbón oscuro con bisel de luz superior
	key_btn.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08, 1.0))
	key_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))
	key_btn.add_theme_color_override("font_pressed_color", Color(0.90, 0.75, 0.35, 1.0))
	key_btn.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.82, 1.0))
	key_btn.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.35))
	key_btn.add_theme_constant_override("shadow_offset_y", 1)

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
	btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))

	if _listen_tween and _listen_tween.is_valid():
		_listen_tween.kill()

	_listen_tween = btn.create_tween().set_loops()
	_listen_tween.tween_property(btn, "modulate:a", 0.45, 0.32).set_ease(Tween.EASE_IN_OUT)
	_listen_tween.tween_property(btn, "modulate:a", 1.0, 0.32).set_ease(Tween.EASE_IN_OUT)


func _refresh_buttons() -> void:
	for action in _action_buttons.keys():
		var btn: Button = _action_buttons[action]
		if not is_instance_valid(btn):
			continue
		btn.modulate.a = 1.0
		var keycode: int = GameSettings.get_key(action)
		var key_name: String = GameSettings.get_key_display_string(keycode)
		btn.text = "[ %s ]" % key_name
		btn.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08, 1.0))
		btn.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.35))


func _on_reset_pressed() -> void:
	_listening_action = ""
	if _listen_tween and _listen_tween.is_valid():
		_listen_tween.kill()
	GameSettings.reset_keybindings_to_default()
	_refresh_buttons()


func _create_bottom_interactive_button(
	rect: Rect2,
	callback: Callable,
	tooltip: String,
	corner_rad: int
) -> Button:
	var btn = Button.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_ALL

	# Normal: transparente para lucir el botón pintado con fidelidad 100%
	var style_n = StyleBoxEmpty.new()

	# Hover: borde dorado radiante y halo resplandeciente
	var style_h = StyleBoxFlat.new()
	style_h.draw_center = true
	style_h.bg_color = Color(1.0, 0.90, 0.45, 0.08)
	style_h.border_color = Color(1.0, 0.88, 0.45, 0.95)
	style_h.set_border_width_all(2)
	style_h.set_corner_radius_all(corner_rad)
	style_h.shadow_color = Color(0.92, 0.78, 0.28, 0.45)
	style_h.shadow_size = 12

	# Pressed: tinte oscuro sutil para dar sensación táctil de hundimiento
	var style_p = StyleBoxFlat.new()
	style_p.draw_center = true
	style_p.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	style_p.border_color = Color(0.85, 0.70, 0.25, 0.90)
	style_p.set_border_width_all(2)
	style_p.set_corner_radius_all(corner_rad)

	btn.add_theme_stylebox_override("normal", style_n)
	btn.add_theme_stylebox_override("hover", style_h)
	btn.add_theme_stylebox_override("pressed", style_p)
	btn.add_theme_stylebox_override("focus", style_h)

	btn.pressed.connect(callback)
	return btn
