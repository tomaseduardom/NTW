extends CanvasLayer
class_name ActionLogDrawer
## ActionLogDrawer — Panel lateral desplegable de Estado de Juego y Efectos Activos,
## más historial de jugadas de la partida.
## Muestra en tiempo real modificadores de fuerza (+1/-1), cartas nombradas (Alicia),
## restricciones y límites activos, con letra grande y diseño diegético medieval.

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/Marcellus-Regular.ttf")

const TEX_BTN_NORMAL := preload("res://assets/ui/menu/btn_menu_normal.png")
const TEX_BTN_HOVER := preload("res://assets/ui/menu/btn_menu_hover.png")
const TEX_BTN_PRESSED := preload("res://assets/ui/menu/btn_menu_pressed.png")

const DRAWER_WIDTH: float = 490.0
const TOP_OFFSET: float = 50.0  # Justo debajo del TopBar

var _main: Node = null
var _is_open: bool = false
var _current_filter: String = "active"
var _unread_count: int = 0
var _all_entries: Array[Dictionary] = []

# Nodos de UI
var _toggle_button: Button = null
var _root_control: Control = null
var _backdrop: ColorRect = null
var _drawer_panel: PanelContainer = null
var _header_title: Label = null
var _header_count: Label = null
var _close_button: Button = null
var _filter_buttons: Dictionary = {}
var _rich_text: RichTextLabel = null
var _scroll_bottom_button: Button = null
var _clear_button: Button = null
var _tween: Tween = null


func _init() -> void:
	layer = 30  # Por encima del tablero y HUD, pero por debajo de CardInspectionLayer (layer 100)


func setup(main: Node) -> void:
	_main = main
	_build_ui()
	_setup_toggle_button()
	_connect_combat_log()
	_populate_existing_entries()


func is_open() -> bool:
	return _is_open


func _create_plaque_style(tex: Texture2D, pad_x: float = 14.0, pad_y: float = 6.0) -> StyleBoxTexture:
	var sb = StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 32.0
	sb.texture_margin_right = 32.0
	sb.texture_margin_top = 22.0
	sb.texture_margin_bottom = 22.0
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y + 2.0
	return sb


# =============================================================================
# CONSTRUCCIÓN DE LA INTERFAZ
# =============================================================================
func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "DrawerRoot"
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)

	# 1. Telón semitransparente (Backdrop)
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.anchor_left = 0.0
	_backdrop.anchor_top = 0.0
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.offset_top = TOP_OFFSET
	_backdrop.offset_left = 0.0
	_backdrop.offset_right = 0.0
	_backdrop.offset_bottom = 0.0
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	_backdrop.modulate.a = 0.0
	_backdrop.visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.gui_input.connect(_on_backdrop_input)
	_root_control.add_child(_backdrop)

	# 2. Panel lateral deslizante (anclado al borde derecho de la pantalla)
	_drawer_panel = PanelContainer.new()
	_drawer_panel.name = "DrawerPanel"
	_drawer_panel.anchor_left = 1.0
	_drawer_panel.anchor_top = 0.0
	_drawer_panel.anchor_right = 1.0
	_drawer_panel.anchor_bottom = 1.0
	_drawer_panel.offset_left = 0.0
	_drawer_panel.offset_top = TOP_OFFSET
	_drawer_panel.offset_right = DRAWER_WIDTH
	_drawer_panel.offset_bottom = 0.0

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.11, 0.98)
	panel_style.border_color = Color(0.82, 0.68, 0.30, 0.90)
	panel_style.border_width_left = 3
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_bottom_left = 12
	panel_style.shadow_color = Color(0, 0, 0, 0.85)
	panel_style.shadow_size = 28
	_drawer_panel.add_theme_stylebox_override("panel", panel_style)
	_root_control.add_child(_drawer_panel)

	# 3. Contenedor con márgenes interiores
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 14)
	margin_container.add_theme_constant_override("margin_left", 16)
	margin_container.add_theme_constant_override("margin_right", 16)
	margin_container.add_theme_constant_override("margin_bottom", 14)
	_drawer_panel.add_child(margin_container)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin_container.add_child(vbox)

	# 4. Header Bar
	var header_hbox = HBoxContainer.new()
	header_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(header_hbox)

	_header_title = Label.new()
	_header_title.text = "ESTADO Y EFECTOS"
	_header_title.add_theme_font_override("font", FONT_TITLE)
	_header_title.add_theme_font_size_override("font_size", 19)
	_header_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
	header_hbox.add_child(_header_title)

	_header_count = Label.new()
	_header_count.text = " (0)"
	_header_count.add_theme_font_override("font", FONT_TEXT)
	_header_count.add_theme_font_size_override("font_size", 14)
	_header_count.add_theme_color_override("font_color", Color(0.60, 0.65, 0.75, 1.0))
	header_hbox.add_child(_header_count)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_close_button = Button.new()
	_close_button.text = " ✕ "
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.add_theme_font_override("font", FONT_TITLE)
	_close_button.add_theme_font_size_override("font_size", 16)

	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.12, 0.14, 0.18, 0.90)
	close_style.border_color = Color(0.65, 0.55, 0.30, 0.70)
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(6)
	_close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover = StyleBoxFlat.new()
	close_hover.bg_color = Color(0.25, 0.10, 0.10, 0.95)
	close_hover.border_color = Color(1.0, 0.40, 0.40, 1.0)
	close_hover.set_border_width_all(1)
	close_hover.set_corner_radius_all(6)
	_close_button.add_theme_stylebox_override("hover", close_hover)
	_close_button.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70, 1.0))
	_close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.85, 1.0))
	_close_button.pressed.connect(close_drawer)
	header_hbox.add_child(_close_button)

	# Separador sutil
	var sep = HSeparator.new()
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(0.78, 0.65, 0.32, 0.40)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# 5. Barra de Filtros / Pestañas
	var filter_hbox = HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(filter_hbox)

	var filters = [
		{"id": "active", "label": "Efectos Activos"},
		{"id": "all", "label": "Historial"},
		{"id": "combat", "label": "Combate"},
		{"id": "cards", "label": "Jugadas"}
	]

	for f in filters:
		var btn = Button.new()
		btn.text = f.label
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", FONT_TITLE)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_filter_button_pressed.bind(f.id))
		filter_hbox.add_child(btn)
		_filter_buttons[f.id] = btn

	_update_filter_button_styles()

	# 6. Contenedor de Texto del Feed (RichTextLabel)
	var text_panel = PanelContainer.new()
	text_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner_style = StyleBoxFlat.new()
	inner_style.bg_color = Color(0.03, 0.04, 0.06, 0.92)
	inner_style.border_color = Color(0.35, 0.38, 0.45, 0.50)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(8)
	text_panel.add_theme_stylebox_override("panel", inner_style)
	vbox.add_child(text_panel)

	var text_margin = MarginContainer.new()
	text_margin.add_theme_constant_override("margin_top", 12)
	text_margin.add_theme_constant_override("margin_left", 14)
	text_margin.add_theme_constant_override("margin_right", 14)
	text_margin.add_theme_constant_override("margin_bottom", 12)
	text_panel.add_child(text_margin)

	_rich_text = RichTextLabel.new()
	_rich_text.name = "FeedRichText"
	_rich_text.bbcode_enabled = true
	_rich_text.scroll_active = true
	_rich_text.scroll_following = true
	_rich_text.selection_enabled = true
	_rich_text.context_menu_enabled = false
	_rich_text.add_theme_font_override("normal_font", FONT_TEXT)
	_rich_text.add_theme_font_override("bold_font", FONT_TITLE)
	_rich_text.add_theme_font_size_override("normal_font_size", 16)
	_rich_text.add_theme_font_size_override("bold_font_size", 16)
	_rich_text.add_theme_constant_override("line_separation", 6)
	_rich_text.meta_clicked.connect(_on_meta_clicked)
	_rich_text.meta_hover_started.connect(_on_meta_hover_started)
	_rich_text.meta_hover_ended.connect(_on_meta_hover_ended)
	text_margin.add_child(_rich_text)

	# 7. Footer Bar
	var footer_hbox = HBoxContainer.new()
	vbox.add_child(footer_hbox)

	var hint_label = Label.new()
	hint_label.text = "Clic en cualquier carta para inspeccionar"
	hint_label.add_theme_font_override("font", FONT_TEXT)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80, 1.0))
	footer_hbox.add_child(hint_label)

	var footer_spacer = Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

	_scroll_bottom_button = Button.new()
	_scroll_bottom_button.text = "Al final"
	_scroll_bottom_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_scroll_bottom_button.add_theme_font_override("font", FONT_TITLE)
	_scroll_bottom_button.add_theme_font_size_override("font_size", 12)
	_scroll_bottom_button.pressed.connect(_scroll_to_bottom)
	footer_hbox.add_child(_scroll_bottom_button)

	_clear_button = Button.new()
	_clear_button.text = "Actualizar"
	_clear_button.tooltip_text = "Actualizar estado de juego y efectos activos"
	_clear_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_clear_button.add_theme_font_override("font", FONT_TITLE)
	_clear_button.add_theme_font_size_override("font_size", 12)
	_clear_button.pressed.connect(_on_clear_or_refresh_pressed)
	footer_hbox.add_child(_clear_button)

	# Estilo sutil para botones del footer
	for btn in [_scroll_bottom_button, _clear_button]:
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = Color(0.09, 0.12, 0.16, 0.90)
		b_style.border_color = Color(0.55, 0.50, 0.35, 0.65)
		b_style.set_border_width_all(1)
		b_style.set_corner_radius_all(5)
		btn.add_theme_stylebox_override("normal", b_style)
		btn.add_theme_stylebox_override("hover", b_style)
		btn.add_theme_stylebox_override("pressed", b_style)
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.78, 1.0))


# =============================================================================
# BOTÓN DE ACCESO EN TOPBAR
# =============================================================================
func _setup_toggle_button() -> void:
	if not _main:
		return
	var top_bar = _main.get_node_or_null("TopBar")
	if not top_bar:
		return

	_toggle_button = Button.new()
	_toggle_button.name = "ActionLogButton"
	_toggle_button.text = "ESTADO DE JUEGO [L]"
	_toggle_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_toggle_button.add_theme_font_override("font", FONT_TITLE)
	_toggle_button.add_theme_font_size_override("font_size", 13)

	# Ubicación entre PlayerInfo (X: 20..200) y TurnLabel (X: 810..1110)
	_toggle_button.offset_left = 210.0
	_toggle_button.offset_top = 7.0
	_toggle_button.offset_right = 410.0
	_toggle_button.offset_bottom = 43.0

	var style_n = _create_plaque_style(TEX_BTN_NORMAL, 12.0, 4.0)
	var style_h = _create_plaque_style(TEX_BTN_HOVER, 12.0, 4.0)
	var style_p = _create_plaque_style(TEX_BTN_PRESSED, 12.0, 4.0)

	_toggle_button.add_theme_stylebox_override("normal", style_n)
	_toggle_button.add_theme_stylebox_override("hover", style_h)
	_toggle_button.add_theme_stylebox_override("pressed", style_p)
	_toggle_button.add_theme_stylebox_override("focus", style_h)
	_toggle_button.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78, 1.0))
	_toggle_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.90, 1.0))
	_toggle_button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_toggle_button.add_theme_constant_override("shadow_offset_x", 1)
	_toggle_button.add_theme_constant_override("shadow_offset_y", 1)

	_toggle_button.pressed.connect(toggle_drawer)
	top_bar.add_child(_toggle_button)


func _get_combat_log() -> Node:
	if is_inside_tree() and get_tree().root.has_node("CombatLog"):
		return get_tree().root.get_node("CombatLog")
	return null


# =============================================================================
# INTEGRACIÓN CON COMBATLOG Y ESTADO DE JUEGO
# =============================================================================
func _connect_combat_log() -> void:
	var combat_log = _get_combat_log()
	if combat_log:
		if not combat_log.log_entry_added.is_connected(_on_log_entry_added):
			combat_log.log_entry_added.connect(_on_log_entry_added)
		if not combat_log.log_cleared.is_connected(_on_log_cleared):
			combat_log.log_cleared.connect(_on_log_cleared)

	# Escuchar eventos de fase y habilidades para mantener estado activo actualizado
	if GameManager and GameManager.has_signal("phase_changed"):
		if not GameManager.phase_changed.is_connected(_on_state_changed_event):
			GameManager.phase_changed.connect(_on_state_changed_event)
	var km = get_node_or_null("/root/KeywordManager")
	if km and km.has_signal("abilities_changed"):
		if not km.abilities_changed.is_connected(_on_state_changed_event):
			km.abilities_changed.connect(_on_state_changed_event)
	var cem = get_node_or_null("/root/ContinuousEffectManager")
	if cem and cem.has_signal("recalculation_completed"):
		if not cem.recalculation_completed.is_connected(_on_state_changed_event):
			cem.recalculation_completed.connect(_on_state_changed_event)


func _on_state_changed_event(_arg = null) -> void:
	if _is_open and _current_filter == "active":
		_refresh_feed()


func _populate_existing_entries() -> void:
	var combat_log = _get_combat_log()
	if not combat_log:
		return
	var existing = combat_log.get_entries()
	for entry in existing:
		_all_entries.append(entry)
	_refresh_feed()


func _on_log_entry_added(entry: Dictionary) -> void:
	_all_entries.append(entry)

	# Actualizar contador
	_header_count.text = " (%d)" % _all_entries.size()

	# Si está cerrado, incrementar contador no leído
	if not _is_open and not _is_decorative_header(entry):
		_unread_count += 1
		_update_toggle_button_text()

	# Si está abierto en vista activa, refrescar estado
	if _is_open and _current_filter == "active":
		_refresh_feed()
	elif _matches_filter(entry, _current_filter):
		var formatted = _format_entry_bbcode(entry)
		if not formatted.is_empty():
			_rich_text.append_text(formatted + "\n")


func _on_log_cleared() -> void:
	_all_entries.clear()
	_unread_count = 0
	_header_count.text = " (0)"
	_update_toggle_button_text()
	_rich_text.clear()
	if _current_filter == "active":
		_refresh_feed()


func _update_toggle_button_text() -> void:
	if not _toggle_button:
		return
	if _unread_count > 0:
		_toggle_button.text = "ESTADO DE JUEGO [L] (%d)" % _unread_count
		_toggle_button.add_theme_color_override("font_color", Color(1.0, 0.90, 0.40, 1.0))
	else:
		_toggle_button.text = "ESTADO DE JUEGO [L]"
		_toggle_button.remove_theme_color_override("font_color")


# =============================================================================
# APERTURA Y CIERRE (ANIMACIÓN)
# =============================================================================
func toggle_drawer() -> void:
	if _is_open:
		close_drawer()
	else:
		open_drawer()


func open_drawer() -> void:
	if _is_open:
		return
	_is_open = true
	_unread_count = 0
	_update_toggle_button_text()

	_backdrop.visible = true
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	_refresh_feed()

	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.20)
	_tween.tween_property(_drawer_panel, "offset_left", -DRAWER_WIDTH, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_drawer_panel, "offset_right", 0.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	if _current_filter != "active":
		call_deferred("_scroll_to_bottom")


func close_drawer() -> void:
	if not _is_open:
		return
	_is_open = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.18)
	_tween.tween_property(_drawer_panel, "offset_left", 0.0, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_drawer_panel, "offset_right", DRAWER_WIDTH, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.chain().tween_callback(func():
		if not _is_open:
			_backdrop.visible = false
	)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_drawer()


# =============================================================================
# FILTRADO Y FORMATEO
# =============================================================================
func _on_filter_button_pressed(filter_id: String) -> void:
	_current_filter = filter_id
	_update_filter_button_styles()
	_refresh_feed()


func _update_filter_button_styles() -> void:
	for id in _filter_buttons:
		var btn: Button = _filter_buttons[id]
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(6)
		if id == _current_filter:
			style.bg_color = Color(0.24, 0.17, 0.08, 0.96)
			style.border_color = Color(1.0, 0.85, 0.35, 1.0)
			style.set_border_width_all(2)
			style.shadow_color = Color(0.88, 0.74, 0.28, 0.35)
			style.shadow_size = 6
			btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.65, 1.0))
		else:
			style.bg_color = Color(0.07, 0.09, 0.12, 0.85)
			style.border_color = Color(0.35, 0.38, 0.46, 0.55)
			style.set_border_width_all(1)
			btn.add_theme_color_override("font_color", Color(0.70, 0.75, 0.82, 1.0))
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)


func _matches_filter(entry: Dictionary, filter_id: String) -> bool:
	if filter_id == "active":
		return false

	var t = entry.get("type", "").to_lower()

	# Los encabezados de turno y fase siempre se muestran para mantener el contexto
	if t in ["turn_header", "phase_header"]:
		return true

	match filter_id:
		"all":
			return true
		"combat":
			return t in ["attack", "atacar", "block", "bloquear", "damage", "daño", "destroy", "destruir"]
		"cards":
			return t in ["play", "jugar", "gold", "oro", "discard", "descartar"]
		_:
			return true


func _is_decorative_header(entry: Dictionary) -> bool:
	var t = entry.get("type", "")
	var m = entry.get("message", "")
	if t == "turn_header" and ("╔" in m or "╚" in m or m.is_empty()):
		return true
	if t == "phase_header" and ("━" in m or m.is_empty()):
		return true
	return false


func _format_entry_bbcode(entry: Dictionary) -> String:
	var t = entry.get("type", "")
	var m = entry.get("message", "")
	var time_str = entry.get("time_string", "")

	# 1. Encabezado de Turno
	if t == "turn_header":
		if "TURNO" in m:
			var clean = m.replace("║", "").replace("╔", "").replace("╗", "").replace("╚", "").replace("╝", "").replace("═", "").strip_edges()
			return "\n[center][color=#E0BC47]═══════ [b]%s[/b] ═══════[/color][/center]" % clean
		return ""

	# 2. Encabezado de Fase (limpiando duplicaciones accidentales)
	if t == "phase_header":
		var clean = m.replace("━", "").strip_edges()
		if clean.is_empty():
			return ""
		clean = clean.replace("FASE DE FASE DE", "FASE DE").replace("FASE DE FASE", "FASE")
		return "[center][color=#90A4CE]── [b]%s[/b] ──[/color][/center]" % clean

	# 3. Entrada estándar
	if m.is_empty():
		return ""

	if not time_str.is_empty():
		return "[color=#566275][%s][/color] %s" % [time_str, m]
	return m


# =============================================================================
# GENERADOR DE ESTADO DE JUEGO ACTIVO
# =============================================================================
func _render_active_game_state() -> String:
	var out: Array[String] = []

	var turn_num := 1
	var active_pid := 0
	if GameManager:
		turn_num = GameManager.current_turn
		active_pid = GameManager.active_player_id
	var phase_name := ""
	if Constants and Constants.get("PHASE_NAMES"):
		phase_name = Constants.PHASE_NAMES.get(GameManager.current_phase, "")

	var active_player_name = "Tomás (Tuyo)" if active_pid == 0 else "Oponente"

	out.append("[center][color=#FFD700]══════ [b]ESTADO DE JUEGO ACTIVO[/b] ══════[/color][/center]")
	out.append("[center][color=#A0AEC0]Turno %d • %s • %s[/color][/center]\n" % [turn_num, active_player_name, phase_name])

	# -------------------------------------------------------------------------
	# 1. CARTAS NOMBRADAS Y ANULACIONES
	# -------------------------------------------------------------------------
	out.append("[color=#E0BC47]◆ [b]CARTAS NOMBRADAS Y ANULACIONES[/b][/color]")
	var km = get_node_or_null("/root/KeywordManager")
	var has_locks := false
	if km:
		# Bloqueo por nombre (Alicia, etc.)
		var named_locks = km.get("_named_ability_locks")
		if named_locks is Dictionary:
			for name_key in named_locks.keys():
				var sources = named_locks[name_key]
				if sources is Array:
					for src in sources:
						if is_instance_valid(src) and src.is_inside_tree():
							has_locks = true
							var src_name = src.get("card_name") if "card_name" in src else "Fuente"
							var target_display = str(name_key).capitalize()
							out.append(" [color=#F59E0B]👑[/color] [b]%s[/b] nombró a [url=card:%s][b][color=#FFD700]%s[/color][/b][/url]" % [
								src_name, target_display, target_display
							])
							out.append("   [color=#94A3B8]└ Pierde sus habilidades en todas las zonas.[/color]")

		# Bloqueo por instancia (Kuchiku Kan, etc.)
		var instance_locks = km.get("_instance_ability_locks")
		if instance_locks is Dictionary:
			for cid in instance_locks.keys():
				var sources = instance_locks[cid]
				if sources is Array:
					for src in sources:
						if is_instance_valid(src) and src.is_inside_tree():
							has_locks = true
							var src_name = src.get("card_name") if "card_name" in src else "Efecto"
							var target_card = instance_from_id(cid) if cid is int else null
							var target_name = target_card.get("card_name") if (target_card and "card_name" in target_card) else "Carta"
							out.append(" [color=#EF4444]🚫[/color] [url=card:%s][b][color=#FFD700]%s[/color][/b][/url] silenciada por [b]%s[/b]" % [
								target_name, target_name, src_name
							])

		# Inmunidades de silencio activas
		for src in km.get("_weapon_wielder_silence_immunity_sources", []):
			if is_instance_valid(src) and src.is_inside_tree():
				has_locks = true
				var src_name = src.get("card_name") if "card_name" in src else "Carta"
				out.append(" [color=#38BDF8]🛡️[/color] [b]%s[/b]: Aliados con Arma protegidos contra perder habilidad." % src_name)

		for src in km.get("_all_allies_silence_immunity_sources", []):
			if is_instance_valid(src) and src.is_inside_tree():
				has_locks = true
				var src_name = src.get("card_name") if "card_name" in src else "Carta"
				out.append(" [color=#38BDF8]🛡️[/color] [b]%s[/b]: Aliados protegidos contra perder habilidad." % src_name)

		for src in km.get("_reserva_conditional_full_silence_immunity_sources", []):
			if is_instance_valid(src) and src.is_inside_tree():
				has_locks = true
				var src_name = src.get("card_name") if "card_name" in src else "Carta"
				out.append(" [color=#38BDF8]🛡️[/color] [b]%s[/b] en Reserva: Tus cartas no pueden perder habilidad." % src_name)

	if not has_locks:
		out.append(" [color=#64748B]Ninguna carta nombrada ni anulada actualmente.[/color]")

	out.append("")

	# -------------------------------------------------------------------------
	# 2. MODIFICADORES DE FUERZA ACTIVOS (BUFFS / DEBUFFS)
	# -------------------------------------------------------------------------
	out.append("[color=#E0BC47]◆ [b]MODIFICADORES DE FUERZA (ALIADOS)[/b][/color]")
	var cem = get_node_or_null("/root/ContinuousEffectManager")
	var has_mods := false
	if cem and _main:
		var in_play: Array = []
		for field in [_main.get("player_field"), _main.get("player_linea_ataque"), _main.get("player_linea_apoyo"),
					  _main.get("opponent_field"), _main.get("opponent_linea_ataque"), _main.get("opponent_linea_apoyo")]:
			if field:
				for card in field.get_children():
					in_play.append(card)

		for card in in_play:
			if not is_instance_valid(card):
				continue
			if card.get("card_type") != Constants.CardType.ALIADO:
				continue

			var card_name: String = card.get("card_name") if "card_name" in card else "Aliado"
			var side_str = "Tuyo" if card.get("controller_id") == 0 else "Rival"

			var breakdown: Dictionary = {}
			if cem.has_method("get_strength_breakdown"):
				breakdown = cem.get_strength_breakdown(card)

			var base_str: int = int(breakdown.get("base", card.get("card_fuerza") if "card_fuerza" in card else 0))
			var total_str: int = int(breakdown.get("total", base_str))
			var diff := total_str - base_str

			if diff != 0 or breakdown.get("modifiers", []).size() > 0:
				has_mods = true
				var color_tag = "#4ADE80" if diff > 0 else "#F87171"
				var sign_str = "+%d" % diff if diff > 0 else "%d" % diff
				out.append(" [color=%s]⚔️[/color] [url=card:%s][b][color=#FFD700]%s[/color][/b][/url] [color=#94A3B8](%s)[/color]: Fuerza [b]%d[/b] [color=%s](%s)[/color] [color=#64748B][Base: %d][/color]" % [
					color_tag, card_name, card_name, side_str, total_str, color_tag, sign_str, base_str
				])
				for mod in breakdown.get("modifiers", []):
					var mod_val = int(mod.get("value", 0))
					var mod_src = str(mod.get("source", "Efecto"))
					var mod_sign = "+%d" % mod_val if mod_val > 0 else "%d" % mod_val
					out.append("   [color=#CBD5E1]└ %s: %s[/color]" % [mod_src, mod_sign])

	if not has_mods:
		out.append(" [color=#64748B]Todos los Aliados en juego conservan su Fuerza base.[/color]")

	out.append("")

	# -------------------------------------------------------------------------
	# 3. REGLAS, LÍMITES Y RESTRICCIONES ACTIVAS
	# -------------------------------------------------------------------------
	out.append("[color=#E0BC47]◆ [b]RESTRICCIONES Y LÍMITES DE ESTE TURNO[/b][/color]")
	var rs = get_node_or_null("/root/RuleState")
	if rs:
		var p0_searches = rs.count("searched", 0)
		var p1_searches = rs.count("searched", 1)
		out.append(" [color=#FCD34D]📜[/color] Búsquedas en Castillo este turno: Tomás [b]%d[/b] • Rival [b]%d[/b]" % [
			p0_searches, p1_searches
		])

		if rs.active("no_combat_damage", 0):
			out.append(" [color=#38BDF8]🛡️[/color] [b]Tomás[/b] es inmune a daño de combate hasta su próximo turno.")
		if rs.active("no_combat_damage", 1):
			out.append(" [color=#38BDF8]🛡️[/color] [b]Rival[/b] es inmune a daño de combate hasta su próximo turno.")

		if rs.active("no_direct_damage", 0):
			out.append(" [color=#38BDF8]🛡️[/color] [b]Tomás[/b] es inmune a daño directo hasta su próximo turno.")
		if rs.active("no_direct_damage", 1):
			out.append(" [color=#38BDF8]🛡️[/color] [b]Rival[/b] es inmune a daño directo hasta su próximo turno.")

		if rs.active("trigger_gold_toll", 0):
			out.append(" [color=#F59E0B]💰[/color] [b]Tomás[/b] debe pagar 1 Oro para disparar habilidades.")
		if rs.active("trigger_gold_toll", 1):
			out.append(" [color=#F59E0B]💰[/color] [b]Rival[/b] debe pagar 1 Oro para disparar habilidades.")

		if rs.has_pending("next_gold_silenced", 0):
			out.append(" [color=#F87171]⚠[/color] El próximo Oro que juegue Tomás entrará sin habilidad.")
		if rs.has_pending("next_gold_silenced", 1):
			out.append(" [color=#F87171]⚠[/color] El próximo Oro que juegue el Rival entrará sin habilidad.")

	out.append("")

	# -------------------------------------------------------------------------
	# 4. TÓTEMS EN JUEGO
	# -------------------------------------------------------------------------
	out.append("[color=#E0BC47]◆ [b]TÓTEMS EN LÍNEA DE APOYO[/b][/color]")
	var has_totems := false
	if _main:
		for field in [_main.get("player_linea_apoyo"), _main.get("opponent_linea_apoyo")]:
			if field:
				for card in field.get_children():
					if is_instance_valid(card) and card.get("card_type") == Constants.CardType.TOTEM:
						has_totems = true
						var t_name: String = card.get("card_name") if "card_name" in card else "Tótem"
						var t_side = "Tomás" if card.get("controller_id") == 0 else "Rival"
						var t_ability: String = card.get("card_habilidad") if "card_habilidad" in card else ""
						if t_ability.length() > 60:
							t_ability = t_ability.substr(0, 58) + "..."
						out.append(" [color=#A78BFA]🏛️[/color] [url=card:%s][b][color=#FFD700]%s[/color][/b][/url] [color=#94A3B8](%s)[/color]" % [
							t_name, t_name, t_side
						])
						if not t_ability.is_empty():
							out.append("   [color=#CBD5E1]└ %s[/color]" % t_ability)

	if not has_totems:
		out.append(" [color=#64748B]No hay tótems activos en juego.[/color]")

	return "\n".join(out)


# =============================================================================
# ACTUALIZACIÓN DE CONTENIDO Y FOOTER
# =============================================================================
func _refresh_feed() -> void:
	if not _rich_text:
		return
	_rich_text.clear()
	_header_count.text = " (%d)" % _all_entries.size()

	if _current_filter == "active":
		_rich_text.text = _render_active_game_state()
		if _scroll_bottom_button:
			_scroll_bottom_button.visible = false
		if _clear_button:
			_clear_button.text = "Actualizar"
			_clear_button.tooltip_text = "Actualizar estado de juego y efectos activos"
		return

	if _scroll_bottom_button:
		_scroll_bottom_button.visible = true
	if _clear_button:
		_clear_button.text = "Limpiar"
		_clear_button.tooltip_text = "Limpiar visualmente el historial"

	var lines: Array[String] = []
	for entry in _all_entries:
		if _matches_filter(entry, _current_filter):
			var formatted = _format_entry_bbcode(entry)
			if not formatted.is_empty():
				lines.append(formatted)

	_rich_text.text = "\n".join(lines)
	call_deferred("_scroll_to_bottom")


func _scroll_to_bottom() -> void:
	if not _rich_text:
		return
	_rich_text.scroll_following = true
	var vbar = _rich_text.get_v_scroll_bar()
	if vbar:
		vbar.value = vbar.max_value


func _on_clear_or_refresh_pressed() -> void:
	if _current_filter == "active":
		_refresh_feed()
	else:
		_clear_feed()


func _clear_feed() -> void:
	_all_entries.clear()
	_header_count.text = " (0)"
	_rich_text.clear()


# =============================================================================
# INTERACCIÓN CON HIPERVÍNCULOS DE CARTAS (META CLICKED)
# =============================================================================
func _on_meta_clicked(meta: Variant) -> void:
	var meta_str = str(meta)
	if meta_str.begins_with("card:"):
		var card_name = meta_str.substr(5).strip_edges()
		_inspect_card_from_log(card_name)


func _inspect_card_from_log(card_name: String) -> void:
	if not _main:
		return
	if "_card_inspector" in _main and _main._card_inspector:
		_main._card_inspector.inspect_card_by_name(card_name)


func _on_meta_hover_started(_meta: Variant) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_meta_hover_ended(_meta: Variant) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
