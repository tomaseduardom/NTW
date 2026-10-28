extends CanvasLayer
class_name ActionLogDrawer
## ActionLogDrawer — Panel lateral desplegable de Efectos Activos del juego.
## Muestra en tiempo real las cartas con efectos continuos activos en juego (Tótems,
## armas equipadas, modificadores de fuerza, cartas nombradas y auras), con la imagen
## de la carta y el efecto resumido.

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/Marcellus-Regular.ttf")

const DRAWER_WIDTH: float = 490.0
const TOP_OFFSET: float = 50.0  # Justo debajo del TopBar

var _main: Node = null
var _is_open: bool = false
var _active_effects_count: int = 0

# Nodos de UI
var _toggle_button: Button = null
var _root_control: Control = null
var _backdrop: ColorRect = null
var _drawer_panel: PanelContainer = null
var _header_title: Label = null
var _header_count: Label = null
var _close_button: Button = null
var _scroll_container: ScrollContainer = null
var _effects_vbox: VBoxContainer = null
var _clear_button: Button = null
var _tween: Tween = null


func _init() -> void:
	layer = 30  # Por encima del tablero y HUD, pero por debajo de CardInspectionLayer (layer 100)


func setup(main: Node) -> void:
	_main = main
	_build_ui()
	_setup_toggle_button()
	_connect_game_signals()
	_refresh_feed()


func is_open() -> bool:
	return _is_open


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
	_backdrop.color = Color(0.02, 0.03, 0.05, 0.65)
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
	panel_style.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	panel_style.border_color = Color(0.78, 0.65, 0.32, 0.90)  # Oro antiguo medieval
	panel_style.border_width_left = 3
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_bottom_left = 14
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
	_header_title.text = "EFECTOS ACTIVOS"
	_header_title.add_theme_font_override("font", FONT_TITLE)
	_header_title.add_theme_font_size_override("font_size", 18)
	_header_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
	_header_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_header_title.add_theme_constant_override("shadow_offset_y", 2)
	header_hbox.add_child(_header_title)

	_header_count = Label.new()
	_header_count.text = " (0)"
	_header_count.add_theme_font_override("font", FONT_TEXT)
	_header_count.add_theme_font_size_override("font_size", 14)
	_header_count.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80, 1.0))
	header_hbox.add_child(_header_count)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_close_button = Button.new()
	_close_button.text = " ✕ "
	_close_button.tooltip_text = "Cerrar panel [ESC]"
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

	# Separador dorado sutil
	var sep = HSeparator.new()
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(0.78, 0.65, 0.32, 0.40)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# 5. Contenedor de Lista de Efectos (ScrollContainer)
	var list_panel = PanelContainer.new()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner_style = StyleBoxFlat.new()
	inner_style.bg_color = Color(0.04, 0.05, 0.08, 0.95)
	inner_style.border_color = Color(0.35, 0.38, 0.45, 0.45)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(8)
	list_panel.add_theme_stylebox_override("panel", inner_style)
	vbox.add_child(list_panel)

	var list_margin = MarginContainer.new()
	list_margin.add_theme_constant_override("margin_top", 10)
	list_margin.add_theme_constant_override("margin_left", 10)
	list_margin.add_theme_constant_override("margin_right", 10)
	list_margin.add_theme_constant_override("margin_bottom", 10)
	list_panel.add_child(list_margin)

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "EffectsScroll"
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_margin.add_child(_scroll_container)

	_effects_vbox = VBoxContainer.new()
	_effects_vbox.name = "EffectsVBox"
	_effects_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_vbox.add_theme_constant_override("separation", 8)
	_scroll_container.add_child(_effects_vbox)

	# 6. Footer Bar
	var footer_hbox = HBoxContainer.new()
	vbox.add_child(footer_hbox)

	var hint_label = Label.new()
	hint_label.text = "Clic en cualquier carta para inspeccionar"
	hint_label.add_theme_font_override("font", FONT_TEXT)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80, 0.90))
	footer_hbox.add_child(hint_label)

	var footer_spacer = Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

	_clear_button = Button.new()
	_clear_button.text = "Actualizar"
	_clear_button.tooltip_text = "Actualizar efectos activos en juego"
	_clear_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_clear_button.add_theme_font_override("font", FONT_TITLE)
	_clear_button.add_theme_font_size_override("font_size", 12)
	_clear_button.pressed.connect(_refresh_feed)

	var b_style = StyleBoxFlat.new()
	b_style.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	b_style.border_color = Color(0.60, 0.52, 0.32, 0.80)
	b_style.set_border_width_all(1)
	b_style.set_corner_radius_all(5)
	b_style.content_margin_left = 12
	b_style.content_margin_right = 12
	b_style.content_margin_top = 4
	b_style.content_margin_bottom = 4

	var b_hover = b_style.duplicate() as StyleBoxFlat
	b_hover.bg_color = Color(0.16, 0.22, 0.30, 1.0)
	b_hover.border_color = Color(1.0, 0.88, 0.45, 1.0)

	_clear_button.add_theme_stylebox_override("normal", b_style)
	_clear_button.add_theme_stylebox_override("hover", b_hover)
	_clear_button.add_theme_stylebox_override("pressed", b_style)
	_clear_button.add_theme_color_override("font_color", Color(0.92, 0.88, 0.75, 1.0))
	footer_hbox.add_child(_clear_button)


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
	_toggle_button.text = "EFECTOS [L]"
	_toggle_button.tooltip_text = "Abrir panel de Efectos Activos [L]"
	_toggle_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_toggle_button.add_theme_font_override("font", FONT_TITLE)
	_toggle_button.add_theme_font_size_override("font_size", 13)

	# Ubicación entre PlayerInfo (X: 20..200) y TurnLabel (X: 810..1110)
	_toggle_button.offset_left = 205.0
	_toggle_button.offset_top = 8.0
	_toggle_button.offset_right = 385.0
	_toggle_button.offset_bottom = 42.0

	var style_n = StyleBoxFlat.new()
	style_n.bg_color = Color(0.08, 0.10, 0.14, 0.94)
	style_n.border_color = Color(0.70, 0.58, 0.35, 0.85)
	style_n.set_border_width_all(1)
	style_n.set_corner_radius_all(6)
	style_n.content_margin_left = 12.0
	style_n.content_margin_right = 12.0
	style_n.content_margin_top = 4.0
	style_n.content_margin_bottom = 4.0

	var style_h = style_n.duplicate() as StyleBoxFlat
	style_h.bg_color = Color(0.14, 0.18, 0.24, 0.98)
	style_h.border_color = Color(1.0, 0.88, 0.45, 1.0)
	style_h.shadow_color = Color(0.88, 0.74, 0.28, 0.35)
	style_h.shadow_size = 8

	var style_p = style_n.duplicate() as StyleBoxFlat
	style_p.bg_color = Color(0.05, 0.06, 0.08, 0.98)
	style_p.border_color = Color(0.55, 0.45, 0.25, 0.85)

	_toggle_button.add_theme_stylebox_override("normal", style_n)
	_toggle_button.add_theme_stylebox_override("hover", style_h)
	_toggle_button.add_theme_stylebox_override("pressed", style_p)
	_toggle_button.add_theme_stylebox_override("focus", style_h)
	_toggle_button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.80, 1.0))
	_toggle_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.92, 1.0))
	_toggle_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	_toggle_button.add_theme_constant_override("outline_size", 1)
	_toggle_button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_toggle_button.add_theme_constant_override("shadow_offset_x", 1)
	_toggle_button.add_theme_constant_override("shadow_offset_y", 1)

	_toggle_button.pressed.connect(toggle_drawer)
	top_bar.add_child(_toggle_button)

	if not GameSettings.keybindings_changed.is_connected(_update_toggle_button_text):
		GameSettings.keybindings_changed.connect(_update_toggle_button_text)
	_update_toggle_button_text()


# =============================================================================
# CONEXIÓN CON SEÑALES DEL JUEGO
# =============================================================================
func _connect_game_signals() -> void:
	if GameManager:
		if GameManager.has_signal("phase_changed") and not GameManager.phase_changed.is_connected(_on_state_changed_event):
			GameManager.phase_changed.connect(_on_state_changed_event)
		if GameManager.has_signal("turn_started") and not GameManager.turn_started.is_connected(_on_state_changed_event):
			GameManager.turn_started.connect(_on_state_changed_event)

	var km = get_node_or_null("/root/KeywordManager")
	if km and km.has_signal("abilities_changed") and not km.abilities_changed.is_connected(_on_state_changed_event):
		km.abilities_changed.connect(_on_state_changed_event)

	var cem = get_node_or_null("/root/ContinuousEffectManager")
	if cem and cem.has_signal("recalculation_completed") and not cem.recalculation_completed.is_connected(_on_state_changed_event):
		cem.recalculation_completed.connect(_on_state_changed_event)

	if EffectController:
		if EffectController.has_signal("on_card_entered_play") and not EffectController.on_card_entered_play.is_connected(_on_state_changed_event):
			EffectController.on_card_entered_play.connect(_on_state_changed_event)
		if EffectController.has_signal("on_card_left_play") and not EffectController.on_card_left_play.is_connected(_on_state_changed_event):
			EffectController.on_card_left_play.connect(_on_state_changed_event)

	if CardManager and CardManager.has_signal("field_count_changed"):
		if not CardManager.field_count_changed.is_connected(_on_state_changed_event):
			CardManager.field_count_changed.connect(_on_state_changed_event)


func _on_state_changed_event(_arg1 = null, _arg2 = null, _arg3 = null) -> void:
	call_deferred("_refresh_feed")


func _update_toggle_button_text() -> void:
	if not _toggle_button:
		return
	var key_code = GameSettings.get_key("historial")
	var key_str = GameSettings.get_key_display_string(key_code)
	_toggle_button.tooltip_text = "Abrir panel de Efectos Activos [%s]" % key_str

	if _active_effects_count > 0:
		_toggle_button.text = "EFECTOS [%s] (%d)" % [key_str, _active_effects_count]
		_toggle_button.add_theme_color_override("font_color", Color(1.0, 0.90, 0.40, 1.0))
	else:
		_toggle_button.text = "EFECTOS [%s]" % key_str
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
	_backdrop.visible = true
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	_refresh_feed()

	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.20)
	_tween.tween_property(_drawer_panel, "offset_left", -DRAWER_WIDTH, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_drawer_panel, "offset_right", 0.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


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
# RECOLECCIÓN DE EFECTOS ACTIVOS
# =============================================================================
func _collect_active_effects() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if not _main:
		return list

	# 1. TÓTEMS EN LÍNEA DE APOYO (Tuyo y Rival)
	for side_id in [0, 1]:
		var apoyo_container = _main.player_linea_apoyo if side_id == 0 else _main.opponent_linea_apoyo
		if is_instance_valid(apoyo_container):
			for card in apoyo_container.get_children():
				if is_instance_valid(card) and not card.is_queued_for_deletion():
					var ctype = card.get("card_type")
					if ctype == Constants.CardType.TOTEM:
						var c_name = card.get("card_name") if "card_name" in card else "Tótem"
						var c_id = card.get("card_id") if "card_id" in card else ""
						var c_ability = card.get("card_habilidad") if "card_habilidad" in card else ""
						list.append({
							"card_node": card,
							"card_id": c_id,
							"card_name": c_name,
							"controller_id": side_id,
							"category": "TÓTEM",
							"badge_color": Color(0.72, 0.55, 0.98), # Violeta Místico
							"summary": _summarize_effect_text(c_ability),
							"details": []
						})

	# 2. ARMAS EQUIPADAS EN EL CAMPO
	for side_id in [0, 1]:
		var field_containers = [
			_main.player_field if side_id == 0 else _main.opponent_field,
			_main.player_linea_ataque if side_id == 0 else _main.opponent_linea_ataque
		]
		for cont in field_containers:
			if is_instance_valid(cont):
				for ally in cont.get_children():
					if is_instance_valid(ally) and not ally.is_queued_for_deletion():
						if "equipped_weapons" in ally and ally.equipped_weapons is Array:
							for weapon in ally.equipped_weapons:
								if is_instance_valid(weapon) and not weapon.is_queued_for_deletion():
									var w_name = weapon.get("card_name") if "card_name" in weapon else "Arma"
									var w_id = weapon.get("card_id") if "card_id" in weapon else ""
									var w_ability = weapon.get("card_habilidad") if "card_habilidad" in weapon else ""
									var ally_name = ally.get("card_name") if "card_name" in ally else "Aliado"
									var w_summary = "Portada por %s: %s" % [ally_name, _summarize_effect_text(w_ability, 100)]
									list.append({
										"card_node": weapon,
										"card_id": w_id,
										"card_name": w_name,
										"controller_id": side_id,
										"category": "ARMA",
										"badge_color": Color(0.96, 0.65, 0.30), # Ámbar/Bronce
										"summary": w_summary,
										"details": []
									})

	# 3. ALIADOS CON MODIFICADORES DE FUERZA (BUFFS / DEBUFFS)
	var cem = get_node_or_null("/root/ContinuousEffectManager")
	if cem:
		for side_id in [0, 1]:
			var field_containers = [
				_main.player_field if side_id == 0 else _main.opponent_field,
				_main.player_linea_ataque if side_id == 0 else _main.opponent_linea_ataque
			]
			for cont in field_containers:
				if is_instance_valid(cont):
					for ally in cont.get_children():
						if is_instance_valid(ally) and not ally.is_queued_for_deletion():
							if ally.get("card_type") == Constants.CardType.ALIADO:
								var breakdown: Dictionary = {}
								if cem.has_method("get_strength_breakdown"):
									breakdown = cem.get_strength_breakdown(ally)
								var base_str: int = int(breakdown.get("base", ally.get("card_fuerza") if "card_fuerza" in ally else 0))
								var total_str: int = int(breakdown.get("total", base_str))
								var diff := total_str - base_str
								var modifiers: Array = breakdown.get("modifiers", [])

								if diff != 0 or modifiers.size() > 0:
									var ally_name = ally.get("card_name") if "card_name" in ally else "Aliado"
									var ally_id = ally.get("card_id") if "card_id" in ally else ""
									var sign_str = "+%d" % diff if diff > 0 else "%d" % diff
									var summary = "Fuerza actual: %d (%s) [Base: %d]" % [total_str, sign_str, base_str]
									var details: Array = []
									for mod in modifiers:
										var m_val = int(mod.get("value", 0))
										var m_src = str(mod.get("source", "Efecto"))
										var m_sign = "+%d" % m_val if m_val > 0 else "%d" % m_val
										details.append("└ %s: %s" % [m_src, m_sign])
									list.append({
										"card_node": ally,
										"card_id": ally_id,
										"card_name": ally_name,
										"controller_id": side_id,
										"category": "FUERZA",
										"badge_color": Color(0.30, 0.85, 0.50) if diff > 0 else Color(0.95, 0.40, 0.40),
										"summary": summary,
										"details": details
									})

	# 4. CARTAS NOMBRADAS Y BLOQUEOS DE HABILIDAD (KeywordManager)
	var km = get_node_or_null("/root/KeywordManager")
	if km:
		# Bloqueo por nombre (Alicia, etc.)
		var named_locks = km.get("_named_ability_locks")
		if named_locks is Dictionary:
			for name_key in named_locks.keys():
				var sources = named_locks[name_key]
				if sources is Array:
					for src in sources:
						if is_instance_valid(src) and src.is_inside_tree():
							var src_name = src.get("card_name") if "card_name" in src else "Fuente"
							var src_id = src.get("card_id") if "card_id" in src else ""
							var target_display = str(name_key).capitalize()
							var side_id = src.get("controller_id") if "controller_id" in src else 0
							list.append({
								"card_node": src,
								"card_id": src_id,
								"card_name": src_name,
								"controller_id": side_id,
								"category": "NOMBRADA",
								"badge_color": Color(0.96, 0.65, 0.15),
								"summary": "Nombró a \"%s\": Pierde sus habilidades en todas las zonas." % target_display,
								"details": []
							})

		# Bloqueo por instancia
		var instance_locks = km.get("_instance_ability_locks")
		if instance_locks is Dictionary:
			for cid in instance_locks.keys():
				var sources = instance_locks[cid]
				if sources is Array:
					for src in sources:
						if is_instance_valid(src) and src.is_inside_tree():
							var target_card = instance_from_id(cid) if cid is int else null
							var target_name = target_card.get("card_name") if (target_card and "card_name" in target_card) else "Carta"
							var target_id = target_card.get("card_id") if (target_card and "card_id" in target_card) else ""
							var src_name = src.get("card_name") if "card_name" in src else "Efecto"
							var side_id = target_card.get("controller_id") if (target_card and "controller_id" in target_card) else 0
							list.append({
								"card_node": target_card if target_card else src,
								"card_id": target_id if target_card else (src.get("card_id") if "card_id" in src else ""),
								"card_name": target_name,
								"controller_id": side_id,
								"category": "SILENCIADA",
								"badge_color": Color(0.95, 0.35, 0.35),
								"summary": "Silenciada por %s: No tiene habilidades activas." % src_name,
								"details": []
							})

		# Inmunidades activas
		var silence_imm_sources = km.get("_weapon_wielder_silence_immunity_sources")
		if silence_imm_sources is Array:
			for src in silence_imm_sources:
				if is_instance_valid(src) and src.is_inside_tree():
					var s_name = src.get("card_name") if "card_name" in src else "Carta"
					var s_id = src.get("card_id") if "card_id" in src else ""
					var side_id = src.get("controller_id") if "controller_id" in src else 0
					list.append({
						"card_node": src,
						"card_id": s_id,
						"card_name": s_name,
						"controller_id": side_id,
						"category": "INMUNIDAD",
						"badge_color": Color(0.35, 0.75, 0.95),
						"summary": "Protección activa: Aliados con Arma no pueden perder habilidades.",
						"details": []
					})

	# 5. REGLAS Y RESTRICCIONES DE ESTE TURNO (RuleState)
	var rs = get_node_or_null("/root/RuleState")
	if rs:
		for side_id in [0, 1]:
			var side_label = "Tomás" if side_id == 0 else "Rival"
			if rs.active("no_combat_damage", side_id):
				list.append({
					"card_node": null,
					"card_id": "",
					"card_name": "Inmunidad Combate",
					"controller_id": side_id,
					"category": "REGLA",
					"badge_color": Color(0.90, 0.75, 0.30),
					"summary": "%s es inmune al daño de combate hasta su próximo turno." % side_label,
					"details": []
				})
			if rs.active("no_direct_damage", side_id):
				list.append({
					"card_node": null,
					"card_id": "",
					"card_name": "Inmunidad Directa",
					"controller_id": side_id,
					"category": "REGLA",
					"badge_color": Color(0.90, 0.75, 0.30),
					"summary": "%s es inmune al daño directo hasta su próximo turno." % side_label,
					"details": []
				})
			if rs.active("trigger_gold_toll", side_id):
				list.append({
					"card_node": null,
					"card_id": "",
					"card_name": "Peaje de Habilidad",
					"controller_id": side_id,
					"category": "RESTRICCIÓN",
					"badge_color": Color(0.95, 0.55, 0.20),
					"summary": "%s debe pagar 1 Oro para disparar habilidades." % side_label,
					"details": []
				})
			if rs.has_pending("next_gold_silenced", side_id):
				list.append({
					"card_node": null,
					"card_id": "",
					"card_name": "Oro Silenciado",
					"controller_id": side_id,
					"category": "RESTRICCIÓN",
					"badge_color": Color(0.95, 0.40, 0.40),
					"summary": "El próximo Oro jugado por %s entrará sin habilidad." % side_label,
					"details": []
				})

	return list


# =============================================================================
# RENDERIZADO VISUAL DE ELEMENTOS
# =============================================================================
func _refresh_feed() -> void:
	if not _effects_vbox:
		return

	# Limpiar hijos anteriores
	for child in _effects_vbox.get_children():
		child.queue_free()

	var active_effects = _collect_active_effects()
	_active_effects_count = active_effects.size()
	_header_count.text = " (%d)" % _active_effects_count
	_update_toggle_button_text()

	if active_effects.is_empty():
		# Estado vacío
		var empty_container = VBoxContainer.new()
		empty_container.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_container.add_theme_constant_override("separation", 8)

		var spacer_top = Control.new()
		spacer_top.custom_minimum_size = Vector2(0, 40)
		empty_container.add_child(spacer_top)

		var empty_icon = Label.new()
		empty_icon.text = "🏛️"
		empty_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_icon.add_theme_font_size_override("font_size", 32)
		empty_container.add_child(empty_icon)

		var empty_title = Label.new()
		empty_title.text = "Sin Efectos Activos"
		empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_title.add_theme_font_override("font", FONT_TITLE)
		empty_title.add_theme_font_size_override("font_size", 15)
		empty_title.add_theme_color_override("font_color", Color(0.65, 0.60, 0.50, 0.85))
		empty_container.add_child(empty_title)

		var empty_sub = Label.new()
		empty_sub.text = "Los Tótems, armas, cartas nombradas y modificadores de fuerza en juego aparecerán aquí."
		empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_sub.add_theme_font_override("font", FONT_TEXT)
		empty_sub.add_theme_font_size_override("font_size", 12)
		empty_sub.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 0.85))
		empty_container.add_child(empty_sub)

		_effects_vbox.add_child(empty_container)
		return

	# Crear tarjeta visual para cada efecto activo
	for effect_data in active_effects:
		var item = _create_effect_item(effect_data)
		_effects_vbox.add_child(item)


func _create_effect_item(data: Dictionary) -> Control:
	var item_panel = PanelContainer.new()
	item_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	normal_style.border_color = Color(0.60, 0.50, 0.30, 0.70)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(8)
	normal_style.shadow_color = Color(0, 0, 0, 0.50)
	normal_style.shadow_size = 4
	normal_style.content_margin_left = 10
	normal_style.content_margin_right = 10
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.14, 0.18, 0.25, 0.98)
	hover_style.border_color = Color(1.0, 0.88, 0.45, 0.95)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(8)
	hover_style.shadow_color = Color(0.88, 0.74, 0.28, 0.25)
	hover_style.shadow_size = 6
	hover_style.content_margin_left = 10
	hover_style.content_margin_right = 10
	hover_style.content_margin_top = 8
	hover_style.content_margin_bottom = 8

	item_panel.add_theme_stylebox_override("panel", normal_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_panel.add_child(hbox)

	# 1. Miniatura de la Carta (Thumbnail 52x74)
	var thumb_frame = PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(52, 74)
	thumb_frame.size = Vector2(52, 74)
	thumb_frame.clip_contents = true
	thumb_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var thumb_border = StyleBoxFlat.new()
	thumb_border.bg_color = Color(0.04, 0.05, 0.07, 1.0)
	thumb_border.border_color = Color(0.78, 0.65, 0.32, 0.85)
	thumb_border.set_border_width_all(1)
	thumb_border.set_corner_radius_all(4)
	thumb_frame.add_theme_stylebox_override("panel", thumb_border)

	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(52, 74)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_frame.add_child(tex_rect)

	# Cargar textura de la carta
	var card_node = data.get("card_node")
	var card_id = str(data.get("card_id", ""))
	var card_name = str(data.get("card_name", ""))
	var controller_id = int(data.get("controller_id", 0))

	var tex: Texture2D = null
	if card_node and is_instance_valid(card_node) and "card_art" in card_node and card_node.card_art and card_node.card_art.texture:
		tex = card_node.card_art.texture
	elif not card_id.is_empty():
		tex = CardDatabase.get_card_image(card_id)
	elif not card_name.is_empty():
		var cdata = CardDatabase.get_card_by_name(card_name)
		if not cdata.is_empty():
			card_id = str(cdata.get("id", ""))
			tex = CardDatabase.get_card_image(card_id)

	if tex:
		tex_rect.texture = tex
	else:
		var back_tex = GameSettings.get_card_back_texture(controller_id)
		if back_tex:
			tex_rect.texture = back_tex
		if not card_id.is_empty():
			var on_load_cb: Callable
			on_load_cb = func(loaded_id: String, loaded_tex: Texture2D):
				if loaded_id == card_id and is_instance_valid(tex_rect) and loaded_tex != null:
					tex_rect.texture = loaded_tex
			CardDatabase.card_image_loaded.connect(on_load_cb)

	hbox.add_child(thumb_frame)

	# 2. Información del Efecto y Carta (VBox)
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 3)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_vbox)

	# Fila Superior: Nombre + Badges
	var header_row = HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 6)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(header_row)

	var name_lbl = Label.new()
	name_lbl.text = card_name
	name_lbl.add_theme_font_override("font", FONT_TITLE)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.48, 1.0))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(name_lbl)

	# Badge Categoría
	var cat_label = Label.new()
	cat_label.text = str(data.get("category", "EFECTO"))
	cat_label.add_theme_font_override("font", FONT_TITLE)
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.add_theme_color_override("font_color", data.get("badge_color", Color(0.8, 0.8, 0.8)))
	cat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(cat_label)

	# Badge Bando (Tuyo / Rival)
	var side_label = Label.new()
	side_label.text = "TUYO" if controller_id == 0 else "RIVAL"
	side_label.add_theme_font_override("font", FONT_TITLE)
	side_label.add_theme_font_size_override("font_size", 10)
	var side_color = Color(0.30, 0.85, 0.55, 1.0) if controller_id == 0 else Color(0.95, 0.45, 0.45, 1.0)
	side_label.add_theme_color_override("font_color", side_color)
	side_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(side_label)

	# Fila Central: Efecto Resumido
	var summary_lbl = Label.new()
	summary_lbl.text = str(data.get("summary", ""))
	summary_lbl.add_theme_font_override("font", FONT_TEXT)
	summary_lbl.add_theme_font_size_override("font_size", 12)
	summary_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94, 1.0))
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(summary_lbl)

	# Detalles adicionales si existen
	var details: Array = data.get("details", [])
	for det in details:
		var det_lbl = Label.new()
		det_lbl.text = str(det)
		det_lbl.add_theme_font_override("font", FONT_TEXT)
		det_lbl.add_theme_font_size_override("font_size", 11)
		det_lbl.add_theme_color_override("font_color", Color(0.68, 0.72, 0.80, 1.0))
		det_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_vbox.add_child(det_lbl)

	# Comprobar si la carta es inspeccionable
	var can_inspect: bool = (
		is_instance_valid(card_node)
		or (not card_id.is_empty() and not CardDatabase.get_card(card_id).is_empty())
		or (not card_name.is_empty() and not CardDatabase.get_card_by_name(card_name).is_empty())
	)

	# Botón invisible interactivo con cursor Pointer
	var click_btn = Button.new()
	click_btn.flat = true
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_inspect else Control.CURSOR_ARROW
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if can_inspect:
		click_btn.mouse_entered.connect(func():
			item_panel.add_theme_stylebox_override("panel", hover_style)
		)
		click_btn.mouse_exited.connect(func():
			item_panel.add_theme_stylebox_override("panel", normal_style)
		)
		click_btn.pressed.connect(func():
			_inspect_card_from_log(card_name, card_node)
		)
	else:
		click_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	item_panel.add_child(click_btn)

	return item_panel


# =============================================================================
# UTILIDADES Y FORMATO
# =============================================================================
func _summarize_effect_text(text: String, max_chars: int = 140) -> String:
	if text.strip_edges().is_empty():
		return "Efecto continuo activo en juego."
	var clean = text.replace("\r\n", " ").replace("\n", " ").replace("  ", " ").strip_edges()
	clean = clean.replace("“", "\"").replace("”", "\"")
	if clean.length() <= max_chars:
		return clean

	# Cortar en el primer punto si es suficientemente informativo
	var dot_pos = clean.find(".")
	if dot_pos > 30 and dot_pos <= max_chars:
		return clean.substr(0, dot_pos + 1)

	# Cortar en límite de palabra
	var cut = clean.substr(0, max_chars)
	var last_space = cut.rfind(" ")
	if last_space > 40:
		cut = cut.substr(0, last_space)
	return cut.strip_edges() + "..."


func _inspect_card_from_log(card_name: String, card_node: Node = null) -> void:
	if not _main:
		return
	if "_card_inspector" in _main and _main._card_inspector:
		if is_instance_valid(card_node):
			_main._card_inspector.inspect_card(card_node)
		elif not card_name.is_empty():
			_main._card_inspector.inspect_card_by_name(card_name)
