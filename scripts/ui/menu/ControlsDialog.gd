extends CanvasLayer
class_name ControlsDialog
## ControlsDialog — Diálogo modal para reasignar atajos de teclado y controles,
## y configurar los niveles de audio, música y estilo sonoro medieval.
## Diseñado con la estética medieval de tableta de piedra, pergamino envejecido
## y botones de piedra cincelada basada fielmente en docs/referencias/Configuracion.jpg.

signal closed

enum Tab { CONTROLS, AUDIO }

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/Marcellus-Regular.ttf")

const TEX_BG := preload("res://assets/ui/controls/dialog_tablet_bg_1280.png")
const TEX_STONE_NORMAL := preload("res://assets/ui/controls/btn_stone_normal_305.png")
const TEX_STONE_HOVER := preload("res://assets/ui/controls/btn_stone_hover_305.png")
const TEX_STONE_PRESSED := preload("res://assets/ui/controls/btn_stone_pressed_305.png")

const TEX_BTN_RESET := preload("res://assets/ui/controls/btn_reset_1280.png")
const TEX_BTN_CLOSE := preload("res://assets/ui/controls/btn_close_1280.png")

const MODAL_WIDTH: float = 1280.0
const MODAL_HEIGHT: float = 794.0

var _backdrop: ColorRect = null
var _modal_panel: Control = null

# Pestañas y subtítulo dinámico
var _current_tab: Tab = Tab.CONTROLS
var _tab_controls_btn: Button = null
var _tab_audio_btn: Button = null
var _subtitle_lbl: Label = null

# Contenedores de contenido
var _controls_container: VBoxContainer = null
var _audio_container: VBoxContainer = null

# Controles de teclas
var _action_buttons: Dictionary = {}
var _listening_action: String = ""
var _listen_tween: Tween = null

# Controles de audio
var _master_slider: HSlider = null
var _master_val_lbl: Label = null
var _master_mute_btn: Button = null

var _music_slider: HSlider = null
var _music_val_lbl: Label = null
var _music_mute_btn: Button = null

var _sfx_slider: HSlider = null
var _sfx_val_lbl: Label = null
var _sfx_mute_btn: Button = null

var _style_buttons: Dictionary = {}

var _btn_close: Button = null
var _btn_reset: Button = null


func _init() -> void:
	layer = 135
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()
	_refresh_buttons()
	_refresh_audio_ui()
	_update_tab_view()


func open_dialog() -> void:
	visible = true
	_listening_action = ""
	_refresh_buttons()
	_refresh_audio_ui()
	_update_tab_view()

	# Animación de apertura suave
	_backdrop.modulate.a = 0.0
	_modal_panel.scale = Vector2(0.92, 0.92)
	_modal_panel.modulate.a = 0.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.20).set_ease(Tween.EASE_OUT)
	tween.tween_property(_modal_panel, "modulate:a", 1.0, 0.22)
	tween.tween_property(_modal_panel, "scale", Vector2.ONE, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


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


# =============================================================================
# CONSTRUCCIÓN DE INTERFAZ
# =============================================================================

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

	# 3. Fondo texturizado de la tableta de piedra con pergamino
	var bg_rect = TextureRect.new()
	bg_rect.name = "TabletBackground"
	bg_rect.texture = TEX_BG
	bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_panel.add_child(bg_rect)

	# 4. Barra de Pestañas (centrada en la viga superior de piedra, sin solapamientos)
	var tabs_hbox = HBoxContainer.new()
	tabs_hbox.name = "TabsBar"
	tabs_hbox.offset_left = 220.0
	tabs_hbox.offset_top = 126.0
	tabs_hbox.offset_right = 1060.0
	tabs_hbox.offset_bottom = 170.0
	tabs_hbox.add_theme_constant_override("separation", 24)
	tabs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_modal_panel.add_child(tabs_hbox)

	_tab_controls_btn = _create_tab_button("⌨  ATAJOS DE TECLADO", Tab.CONTROLS)
	tabs_hbox.add_child(_tab_controls_btn)

	_tab_audio_btn = _create_tab_button("🔊  AJUSTES DE AUDIO", Tab.AUDIO)
	tabs_hbox.add_child(_tab_audio_btn)

	# 5. Subtítulo dinámico sobre el pergamino
	_subtitle_lbl = Label.new()
	_subtitle_lbl.name = "SectionSubtitle"
	_subtitle_lbl.offset_left = 145.0
	_subtitle_lbl.offset_top = 184.0
	_subtitle_lbl.offset_right = 1123.0
	_subtitle_lbl.offset_bottom = 212.0
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_lbl.add_theme_font_override("font", FONT_TEXT)
	_subtitle_lbl.add_theme_font_size_override("font_size", 15)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.32, 0.26, 0.18, 1.0))
	_modal_panel.add_child(_subtitle_lbl)

	# 6. Contenedor de Atajos de Teclado
	_controls_container = VBoxContainer.new()
	_controls_container.name = "ActionRowsContainer"
	_controls_container.offset_left = 145.0
	_controls_container.offset_top = 220.0
	_controls_container.offset_right = 1123.0
	_controls_container.offset_bottom = 625.0
	_controls_container.add_theme_constant_override("separation", 18)
	_modal_panel.add_child(_controls_container)

	for action in GameSettings.DEFAULT_KEYBINDINGS.keys():
		var row = _create_action_row(action)
		_controls_container.add_child(row)

	# 7. Contenedor de Ajustes de Audio
	_audio_container = VBoxContainer.new()
	_audio_container.name = "AudioSettingsContainer"
	_audio_container.offset_left = 145.0
	_audio_container.offset_top = 220.0
	_audio_container.offset_right = 1123.0
	_audio_container.offset_bottom = 625.0
	_audio_container.add_theme_constant_override("separation", 16)
	_modal_panel.add_child(_audio_container)

	_build_audio_rows()

	# 8. Botones interactivos inferiores (RESTAURAR DEFECTO y CERRAR)
	_btn_reset = _create_bottom_interactive_button(
		Rect2(221.0, 672.0, 396.0, 107.0),
		TEX_BTN_RESET,
		_on_reset_pressed
	)
	_btn_reset.name = "BtnReset"
	_modal_panel.add_child(_btn_reset)

	_btn_close = _create_bottom_interactive_button(
		Rect2(655.0, 665.0, 450.0, 114.0),
		TEX_BTN_CLOSE,
		close_dialog
	)
	_btn_close.name = "BtnClose"
	_modal_panel.add_child(_btn_close)


# =============================================================================
# PESTAÑAS (TABS)
# =============================================================================

func _create_tab_button(text: String, tab_id: Tab) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(340, 44)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(_on_tab_pressed.bind(tab_id))
	return btn


func _on_tab_pressed(tab_id: Tab) -> void:
	if _listening_action != "":
		_cancel_listening()
	_current_tab = tab_id
	_update_tab_view()


func _update_tab_view() -> void:
	var is_ctrl = (_current_tab == Tab.CONTROLS)
	_controls_container.visible = is_ctrl
	_audio_container.visible = not is_ctrl

	if _subtitle_lbl:
		if is_ctrl:
			_subtitle_lbl.text = "Haz clic en una tecla para reasignarla. Presiona ESC para cancelar."
		else:
			_subtitle_lbl.text = "Ajusta los niveles de volumen y personaliza la respuesta sonora del juego."

	_style_tab_btn(_tab_controls_btn, is_ctrl)
	_style_tab_btn(_tab_audio_btn, not is_ctrl)


func _style_tab_btn(btn: Button, active: bool) -> void:
	if not btn:
		return
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(8)

	if active:
		sb.bg_color = Color(0.10, 0.13, 0.20, 0.98)
		sb.border_color = Color(0.88, 0.74, 0.28, 1.0)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0.88, 0.74, 0.28, 0.35)
		sb.shadow_size = 8
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
		btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.90))
		btn.add_theme_constant_override("shadow_offset_y", 1)
	else:
		sb.bg_color = Color(0.15, 0.14, 0.13, 0.85)
		sb.border_color = Color(0.48, 0.42, 0.32, 0.70)
		sb.set_border_width_all(1)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 4
		btn.add_theme_color_override("font_color", Color(0.72, 0.66, 0.56, 1.0))
		btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.50))
		btn.add_theme_constant_override("shadow_offset_y", 1)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)


# =============================================================================
# APARTADO DE AJUSTES DE AUDIO
# =============================================================================

func _build_audio_rows() -> void:
	# Fila 1: Música de Fondo
	var music_data = _create_audio_slider_row(
		"MÚSICA DE FONDO",
		"Banda sonora ambiental medieval y temas de batalla",
		GameSettings.music_volume,
		_on_music_slider_changed,
		_on_music_mute_toggled
	)
	_music_slider = music_data.slider
	_music_val_lbl = music_data.label
	_music_mute_btn = music_data.mute_btn
	_audio_container.add_child(music_data.row)

	# Fila 2: Efectos de Sonido SFX
	var sfx_data = _create_audio_slider_row(
		"EFECTOS DE SONIDO (SFX)",
		"Respuesta sonora de botones, cartas y acciones de combate",
		GameSettings.sfx_volume,
		_on_sfx_slider_changed,
		_on_sfx_mute_toggled
	)
	_sfx_slider = sfx_data.slider
	_sfx_val_lbl = sfx_data.label
	_sfx_mute_btn = sfx_data.mute_btn
	_audio_container.add_child(sfx_data.row)

	# Fila 3: Volumen General Master (con botón Silenciar Todo)
	var master_data = _create_audio_slider_row(
		"VOLUMEN GENERAL (MASTER)",
		"Nivel general de volumen para toda la aplicación",
		GameSettings.master_volume,
		_on_master_slider_changed,
		_on_master_mute_toggled
	)
	_master_slider = master_data.slider
	_master_val_lbl = master_data.label
	_master_mute_btn = master_data.mute_btn
	_audio_container.add_child(master_data.row)

	# Fila 4: Estilo de Sonido de los Botones (Age of Empires II / Piedra / Monedas)
	var style_row = _create_sound_style_selector_row()
	_audio_container.add_child(style_row)


func _create_audio_slider_row(
	title_text: String,
	desc_text: String,
	current_val: float,
	slider_callback: Callable,
	mute_callback: Variant
) -> Dictionary:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.custom_minimum_size = Vector2(0, 72)
	hbox.add_theme_constant_override("separation", 28)

	# Columna izquierda: Título y descripción (anchura fija equilibrada)
	var text_vbox = VBoxContainer.new()
	text_vbox.custom_minimum_size = Vector2(440, 0)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(text_vbox)

	var title_lbl = Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_override("font", FONT_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 17)
	# Tinta oscura profunda y nítida sobre pergamino, SIN sombras que emborronen
	title_lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.08, 1.0))
	text_vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = desc_text
	desc_lbl.add_theme_font_override("font", FONT_TEXT)
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.36, 0.30, 0.24, 0.95))
	text_vbox.add_child(desc_lbl)

	# Columna derecha: Controles interactivos (ancho exactamente alineado de 480 px)
	var controls_hbox = HBoxContainer.new()
	controls_hbox.custom_minimum_size = Vector2(480, 0)
	controls_hbox.add_theme_constant_override("separation", 16)
	controls_hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(controls_hbox)

	var mute_btn: Button = null
	if mute_callback != null and mute_callback is Callable:
		mute_btn = Button.new()
		mute_btn.custom_minimum_size = Vector2(130, 42)
		mute_btn.text = "SILENCIAR"
		mute_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mute_btn.add_theme_font_override("font", FONT_TITLE)
		mute_btn.add_theme_font_size_override("font_size", 13)
		_style_action_button(mute_btn, false)
		mute_btn.pressed.connect(mute_callback)
		controls_hbox.add_child(mute_btn)
	else:
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(130, 42)
		controls_hbox.add_child(spacer)

	var slider = HSlider.new()
	slider.custom_minimum_size = Vector2(240, 24)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = current_val * 100.0
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.value_changed.connect(slider_callback)
	_style_medieval_slider(slider)
	controls_hbox.add_child(slider)

	var val_lbl = Label.new()
	val_lbl.text = "%d%%" % int(slider.value)
	val_lbl.custom_minimum_size = Vector2(50, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val_lbl.add_theme_font_override("font", FONT_TITLE)
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", Color(0.18, 0.14, 0.10, 1.0))
	controls_hbox.add_child(val_lbl)

	return {
		"row": hbox,
		"slider": slider,
		"label": val_lbl,
		"mute_btn": mute_btn
	}


func _create_sound_style_selector_row() -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.custom_minimum_size = Vector2(0, 72)
	hbox.add_theme_constant_override("separation", 28)

	var text_vbox = VBoxContainer.new()
	text_vbox.custom_minimum_size = Vector2(440, 0)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(text_vbox)

	var title_lbl = Label.new()
	title_lbl.text = "ESTILO DE CLICK DE BOTONES"
	title_lbl.add_theme_font_override("font", FONT_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.08, 1.0))
	text_vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = "Textura acústica profunda al pulsar botones e interactuar"
	desc_lbl.add_theme_font_override("font", FONT_TEXT)
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.36, 0.30, 0.24, 0.95))
	text_vbox.add_child(desc_lbl)

	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.custom_minimum_size = Vector2(480, 0)
	buttons_hbox.add_theme_constant_override("separation", 14)
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(buttons_hbox)

	var styles = [
		{"id": "wood", "label": "MADERA (AOE II)"},
		{"id": "stone", "label": "PIEDRA"},
		{"id": "coin", "label": "MONEDAS"}
	]

	for s in styles:
		var btn = Button.new()
		btn.text = s.label
		btn.custom_minimum_size = Vector2(148, 42)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", FONT_TITLE)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_sound_style_selected.bind(s.id))
		buttons_hbox.add_child(btn)
		_style_buttons[s.id] = btn

	return hbox


func _style_action_button(btn: Button, is_active: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(6)

	var sb_hov = StyleBoxFlat.new()
	sb_hov.set_corner_radius_all(6)
	sb_hov.bg_color = Color(0.18, 0.24, 0.35, 1.0)
	sb_hov.border_color = Color(1.0, 0.88, 0.48, 1.0)
	sb_hov.set_border_width_all(2)
	sb_hov.shadow_color = Color(0.88, 0.74, 0.28, 0.35)
	sb_hov.shadow_size = 8

	if is_active:
		sb.bg_color = Color(0.16, 0.14, 0.10, 0.98)
		sb.border_color = Color(0.88, 0.74, 0.28, 1.0)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0.88, 0.74, 0.28, 0.40)
		sb.shadow_size = 8
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
		btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.90))
		btn.add_theme_constant_override("shadow_offset_y", 1)
	else:
		sb.bg_color = Color(0.12, 0.15, 0.22, 0.95)
		sb.border_color = Color(0.55, 0.48, 0.35, 0.85)
		sb.set_border_width_all(1.5)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 4
		btn.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
		btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.80))
		btn.add_theme_constant_override("shadow_offset_y", 1)

	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hov)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb_hov)


func _style_medieval_slider(slider: HSlider) -> void:
	var track_sb = StyleBoxFlat.new()
	track_sb.bg_color = Color(0.22, 0.18, 0.14, 0.95)
	track_sb.border_color = Color(0.55, 0.45, 0.30, 0.90)
	track_sb.set_border_width_all(1)
	track_sb.set_corner_radius_all(4)
	track_sb.content_margin_top = 4.0
	track_sb.content_margin_bottom = 4.0

	var fill_sb = StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.82, 0.68, 0.30, 1.0)
	fill_sb.set_corner_radius_all(4)
	fill_sb.content_margin_top = 4.0
	fill_sb.content_margin_bottom = 4.0

	slider.add_theme_stylebox_override("slider", track_sb)
	slider.add_theme_stylebox_override("grabber_area", fill_sb)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_sb)


func _on_sound_style_selected(style_id: String) -> void:
	GameSettings.set_button_sound_style(style_id)
	_refresh_style_buttons()
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play_ui_click()


func _refresh_style_buttons() -> void:
	var current = GameSettings.button_sound_style
	for style_id in _style_buttons.keys():
		var btn: Button = _style_buttons[style_id]
		var is_active = (style_id == current)
		_style_action_button(btn, is_active)


func _refresh_audio_ui() -> void:
	if _master_slider:
		_master_slider.value = GameSettings.master_volume * 100.0
		_master_val_lbl.text = "%d%%" % int(_master_slider.value)

	if _music_slider:
		_music_slider.value = GameSettings.music_volume * 100.0
		_music_val_lbl.text = "%d%%" % int(_music_slider.value)

	if _sfx_slider:
		_sfx_slider.value = GameSettings.sfx_volume * 100.0
		_sfx_val_lbl.text = "%d%%" % int(_sfx_slider.value)

	if _master_mute_btn:
		var is_muted = GameSettings.master_volume <= 0.01
		_master_mute_btn.text = "ACTIVAR" if is_muted else "SILENCIAR"
		_style_action_button(_master_mute_btn, is_muted)

	if _music_mute_btn:
		var is_muted = GameSettings.music_volume <= 0.01
		_music_mute_btn.text = "ACTIVAR" if is_muted else "SILENCIAR"
		_style_action_button(_music_mute_btn, is_muted)

	if _sfx_mute_btn:
		var is_muted = GameSettings.sfx_volume <= 0.01
		_sfx_mute_btn.text = "ACTIVAR" if is_muted else "SILENCIAR"
		_style_action_button(_sfx_mute_btn, is_muted)

	_refresh_style_buttons()


func _on_master_slider_changed(val: float) -> void:
	if _master_val_lbl:
		_master_val_lbl.text = "%d%%" % int(val)
	GameSettings.set_master_volume(val / 100.0)
	if _master_mute_btn:
		var is_muted = val <= 1.0
		_master_mute_btn.text = "ACTIVAR" if is_muted else "SILENCIAR"
		_style_action_button(_master_mute_btn, is_muted)


func _on_music_slider_changed(val: float) -> void:
	if _music_val_lbl:
		_music_val_lbl.text = "%d%%" % int(val)
	GameSettings.set_music_volume(val / 100.0)
	if _music_mute_btn:
		var is_muted = val <= 1.0
		_music_mute_btn.text = "ACTIVAR" if is_muted else "SILENCIAR"
		_style_action_button(_music_mute_btn, is_muted)


func _on_sfx_slider_changed(val: float) -> void:
	if _sfx_val_lbl:
		_sfx_val_lbl.text = "%d%%" % int(val)
	GameSettings.set_sfx_volume(val / 100.0)
	if _sfx_mute_btn:
		var is_muted = val <= 1.0
		_sfx_mute_btn.text = "ACTIVAR" if is_muted else "SILENCIAR"
		_style_action_button(_sfx_mute_btn, is_muted)


func _on_master_mute_toggled() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("toggle_mute_master"):
		am.toggle_mute_master()
	else:
		if GameSettings.master_volume > 0.01:
			GameSettings.set_meta(&"prev_master_vol", GameSettings.master_volume)
			GameSettings.set_master_volume(0.0)
		else:
			var prev = 1.0
			if GameSettings.has_meta(&"prev_master_vol"):
				prev = float(GameSettings.get_meta(&"prev_master_vol"))
			GameSettings.set_master_volume(maxf(prev, 1.0))
	_refresh_audio_ui()


func _on_music_mute_toggled() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("toggle_mute_music"):
		am.toggle_mute_music()
	else:
		if GameSettings.music_volume > 0.01:
			GameSettings.set_meta(&"prev_music_vol", GameSettings.music_volume)
			GameSettings.set_music_volume(0.0)
		else:
			var prev = 0.8
			if GameSettings.has_meta(&"prev_music_vol"):
				prev = float(GameSettings.get_meta(&"prev_music_vol"))
			GameSettings.set_music_volume(maxf(prev, 0.8))
	_refresh_audio_ui()


func _on_sfx_mute_toggled() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("toggle_mute_sfx"):
		am.toggle_mute_sfx()
	else:
		if GameSettings.sfx_volume > 0.01:
			GameSettings.set_meta(&"prev_sfx_vol", GameSettings.sfx_volume)
			GameSettings.set_sfx_volume(0.0)
		else:
			var prev = 1.0
			if GameSettings.has_meta(&"prev_sfx_vol"):
				prev = float(GameSettings.get_meta(&"prev_sfx_vol"))
			GameSettings.set_sfx_volume(maxf(prev, 1.0))
	_refresh_audio_ui()


# =============================================================================
# FILAS DE ATAJOS DE TECLADO (CONTROLES)
# =============================================================================

func _create_action_row(action: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.custom_minimum_size = Vector2(0, 59)
	hbox.add_theme_constant_override("separation", 28)

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
	action_name.add_theme_color_override("font_color", Color(0.16, 0.12, 0.08, 1.0))
	text_vbox.add_child(action_name)

	var action_desc = Label.new()
	action_desc.text = GameSettings.ACTION_DESCRIPTIONS.get(action, "")
	action_desc.add_theme_font_override("font", FONT_TEXT)
	action_desc.add_theme_font_size_override("font_size", 14)
	action_desc.add_theme_color_override("font_color", Color(0.36, 0.30, 0.24, 0.95))
	text_vbox.add_child(action_desc)

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

	key_btn.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08, 1.0))
	key_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))
	key_btn.add_theme_color_override("font_pressed_color", Color(0.90, 0.75, 0.35, 1.0))
	key_btn.add_theme_color_override("font_focus_color", Color(1.0, 0.95, 0.82, 1.0))

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


func _on_reset_pressed() -> void:
	if _current_tab == Tab.CONTROLS:
		_listening_action = ""
		if _listen_tween and _listen_tween.is_valid():
			_listen_tween.kill()
		GameSettings.reset_keybindings_to_default()
		_refresh_buttons()
	elif _current_tab == Tab.AUDIO:
		GameSettings.set_master_volume(1.0)
		GameSettings.set_music_volume(0.8)
		GameSettings.set_sfx_volume(1.0)
		GameSettings.set_button_sound_style("wood")
		_refresh_audio_ui()


func _create_bottom_interactive_button(
	rect: Rect2,
	texture: Texture2D,
	callback: Callable
) -> Button:
	var btn = Button.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.custom_minimum_size = rect.size
	btn.pivot_offset = rect.size * 0.5
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE

	var style_tex = StyleBoxTexture.new()
	style_tex.texture = texture
	style_tex.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style_tex.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

	btn.add_theme_stylebox_override("normal", style_tex)
	btn.add_theme_stylebox_override("hover", style_tex)
	btn.add_theme_stylebox_override("pressed", style_tex)
	btn.add_theme_stylebox_override("focus", style_tex)

	var base_pos: Vector2 = rect.position
	btn.mouse_entered.connect(func():
		var tw = btn.create_tween().set_parallel(true)
		tw.tween_property(btn, "modulate", Color(1.22, 1.18, 1.08), 0.12).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween().set_parallel(true)
		tw.tween_property(btn, "modulate", Color.WHITE, 0.14).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "position", base_pos, 0.14).set_ease(Tween.EASE_OUT)
	)
	btn.button_down.connect(func():
		var tw = btn.create_tween().set_parallel(true)
		tw.tween_property(btn, "modulate", Color(0.88, 0.85, 0.80), 0.05)
		tw.tween_property(btn, "position", base_pos + Vector2(0, 1.5), 0.05)
	)
	btn.button_up.connect(func():
		var tw = btn.create_tween().set_parallel(true)
		tw.tween_property(btn, "modulate", Color(1.22, 1.18, 1.08), 0.08)
		tw.tween_property(btn, "position", base_pos, 0.08)
	)

	btn.pressed.connect(callback)
	return btn
