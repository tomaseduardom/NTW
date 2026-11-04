extends "res://scripts/ui/zones/DeckSelectorCarrusel.gd"
## DeckSelector — familia Construccion (ver DeckSelectorBase.gd para la cabecera, constantes y ayudas).


func show_selector(parent: Node) -> void:
	"""Muestra el altar diegético de selección. Emite decks_selected al confirmar."""
	_build_ui(parent)
	_fetch_mazos()

# =============================================================================
# CONSTRUCCIÓN DE UI DIEGÉTICA
# =============================================================================


func _build_ui(parent: Node) -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "DeckSelectorCanvasLayer"
	_canvas_layer.layer = 25
	parent.add_child(_canvas_layer)

	_overlay = Control.new()
	_overlay.name = "AltarDeckSelectorOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas_layer.add_child(_overlay)

	# 1. Escenario de Fondo: Altar rúnico ancestral en alta definición
	var bg_texture = TextureRect.new()
	bg_texture.name = "AltarBackground"
	bg_texture.texture = BACKGROUND_TEXTURE
	bg_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg_texture)

	# 2. Contenedor del Carrusel sobre la meseta de piedra del altar
	# Ancho exacto de 1308px con márgenes de 16px para 6 grimorios enteros sin asomo del 7mo libro
	var carousel_wrapper = Control.new()
	carousel_wrapper.name = "AltarCarouselWrapper"
	carousel_wrapper.set_anchor(SIDE_LEFT, 0.5)
	carousel_wrapper.set_anchor(SIDE_RIGHT, 0.5)
	carousel_wrapper.set_anchor(SIDE_TOP, 0.5)
	carousel_wrapper.set_anchor(SIDE_BOTTOM, 0.5)
	carousel_wrapper.set_offset(SIDE_LEFT, -654)
	carousel_wrapper.set_offset(SIDE_RIGHT, 654)
	carousel_wrapper.set_offset(SIDE_TOP, -255)
	carousel_wrapper.set_offset(SIDE_BOTTOM, 85)
	carousel_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(carousel_wrapper)

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "AltarScroll"
	_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Ocultar la barra gris para máxima inmersión
	var h_bar = _scroll_container.get_h_scroll_bar()
	if h_bar:
		h_bar.modulate = Color(1, 1, 1, 0)
	_scroll_container.gui_input.connect(_on_scroll_gui_input)
	carousel_wrapper.add_child(_scroll_container)

	# Margen simétrico de 16px para que Card 7 quede 4px afuera del límite y no se asome ni 1 pixel
	var scroll_margin = MarginContainer.new()
	scroll_margin.name = "ScrollMargin"
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_left", 16)
	scroll_margin.add_theme_constant_override("margin_right", 16)
	scroll_margin.add_theme_constant_override("margin_top", 28)
	scroll_margin.add_theme_constant_override("margin_bottom", 16)
	_scroll_container.add_child(scroll_margin)

	_player_row = HBoxContainer.new()
	_player_row.name = "GrimoriosRow"
	_player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_player_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player_row.custom_minimum_size = Vector2(0, 290)
	_player_row.add_theme_constant_override("separation", 20)
	scroll_margin.add_child(_player_row)

	# Placeholder de carga místico con runas giratorias
	_loading_box = _build_loading_placeholder()
	_player_row.add_child(_loading_box)

	# 3. Botones Rúnicos Circulares de Navegación Lateral (◄ y ►) centrados según los mazos (Y=-84)
	_btn_prev = _build_circular_nav_button("◄", Vector2(-712, -84))
	_btn_prev.pressed.connect(_scroll_left)
	_overlay.add_child(_btn_prev)

	_btn_next = _build_circular_nav_button("►", Vector2(664, -84))
	_btn_next.pressed.connect(_scroll_right)
	_overlay.add_child(_btn_next)

	# 4. Cartel Central de Mazo Activo (sobre el grabado de piedra "ELIGE TU MAZO")
	_build_center_banner()

	# 5. Pedestal de Mazos Disponibles (esquina inferior izquierda)
	_build_available_decks_pedestal()

	# 6. Pedestal de Temporizador / Reloj de Turno (esquina inferior derecha)
	_build_timer_pedestal()

	# 7. Botones de Pedestal Orgánicos (100% limpios, sin cajas de colores)
	_build_clean_action_buttons()

	# Escuchar configuración de partida online si estamos en sala
	if NetworkClient.room_code != "":
		if not NetworkClient.message_received.is_connected(_on_network_message_deck_selector):
			NetworkClient.message_received.connect(_on_network_message_deck_selector)


func _build_circular_nav_button(glyph: String, pos_offset: Vector2) -> Button:
	var btn = Button.new()
	btn.text = glyph
	btn.custom_minimum_size = Vector2(48, 48)
	btn.set_anchor(SIDE_LEFT, 0.5)
	btn.set_anchor(SIDE_RIGHT, 0.5)
	btn.set_anchor(SIDE_TOP, 0.5)
	btn.set_anchor(SIDE_BOTTOM, 0.5)
	btn.set_offset(SIDE_LEFT, pos_offset.x)
	btn.set_offset(SIDE_RIGHT, pos_offset.x + 48)
	btn.set_offset(SIDE_TOP, pos_offset.y)
	btn.set_offset(SIDE_BOTTOM, pos_offset.y + 48)
	btn.pivot_offset = Vector2(24, 24)

	# Estilo de piedra rúnica circular
	var style_norm = StyleBoxFlat.new()
	style_norm.bg_color = Color(0.08, 0.10, 0.12, 0.85)
	style_norm.border_color = Color(0.83, 0.69, 0.22, 0.6)
	style_norm.set_border_width_all(2)
	style_norm.set_corner_radius_all(24)
	style_norm.shadow_color = Color(0, 0, 0, 0.6)
	style_norm.shadow_size = 6
	btn.add_theme_stylebox_override("normal", style_norm)

	var style_hov = StyleBoxFlat.new()
	style_hov.bg_color = Color(0.12, 0.16, 0.20, 0.95)
	style_hov.border_color = GOLD_HOVER
	style_hov.set_border_width_all(2)
	style_hov.set_corner_radius_all(24)
	style_hov.shadow_color = Color(0.83, 0.69, 0.22, 0.4)
	style_hov.shadow_size = 10
	btn.add_theme_stylebox_override("hover", style_hov)

	var style_press = StyleBoxFlat.new()
	style_press.bg_color = Color(0.05, 0.07, 0.09, 0.95)
	style_press.border_color = GOLD_SELECTION
	style_press.set_border_width_all(2)
	style_press.set_corner_radius_all(24)
	btn.add_theme_stylebox_override("pressed", style_press)

	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.visible = false

	btn.mouse_entered.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.12)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12)
	)
	btn.button_down.connect(func():
		btn.scale = Vector2(0.95, 0.95)
	)
	btn.button_up.connect(func():
		btn.scale = Vector2(1.0, 1.0)
	)
	return btn


func _build_center_banner() -> void:
	"""Muestra la placa informativa del mazo activo cubriendo por completo la inscripción
	'ELIGE TU MAZO' del fondo, utilizando el diseño del contenedor de piedra 'Mazos Disponibles'"""
	var banner_box = Control.new()
	banner_box.name = "ActiveDeckBanner"
	banner_box.set_anchor(SIDE_LEFT, 0.5)
	banner_box.set_anchor(SIDE_RIGHT, 0.5)
	banner_box.set_anchor(SIDE_TOP, 0.5)
	banner_box.set_anchor(SIDE_BOTTOM, 0.5)
	banner_box.set_offset(SIDE_LEFT, -260)
	banner_box.set_offset(SIDE_RIGHT, 260)
	banner_box.set_offset(SIDE_TOP, 130)
	banner_box.set_offset(SIDE_BOTTOM, 208)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(banner_box)

	# Placa base de piedra idéntica al contenedor 'Mazos Disponibles'
	var plate_bg = NinePatchRect.new()
	plate_bg.name = "BannerPlateBg"
	plate_bg.texture = TEX_BTN_PLAQUE_BLANK
	plate_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate_bg.patch_margin_left = 34
	plate_bg.patch_margin_right = 34
	plate_bg.patch_margin_top = 26
	plate_bg.patch_margin_bottom = 26
	plate_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.add_child(plate_bg)

	var text_vbox = VBoxContainer.new()
	text_vbox.name = "TextVBox"
	text_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.add_theme_constant_override("separation", 2)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.add_child(text_vbox)

	_deck_banner = Label.new()
	_deck_banner.text = "ELIGE TU GRIMORIO"
	_deck_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_deck_banner.add_theme_font_override("font", FONT_TITLE)
	_deck_banner.add_theme_font_size_override("font_size", 18)
	_deck_banner.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75, 1.0))
	_deck_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.98))
	_deck_banner.add_theme_constant_override("shadow_offset_x", 1)
	_deck_banner.add_theme_constant_override("shadow_offset_y", 2)
	text_vbox.add_child(_deck_banner)

	_deck_sub_banner = Label.new()
	_deck_sub_banner.text = "Toca un libro para seleccionarlo"
	_deck_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_sub_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_deck_sub_banner.add_theme_font_override("font", FONT_MEDIEVAL)
	_deck_sub_banner.add_theme_font_size_override("font_size", 12)
	_deck_sub_banner.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65, 0.95))
	_deck_sub_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_deck_sub_banner.add_theme_constant_override("shadow_offset_x", 1)
	_deck_sub_banner.add_theme_constant_override("shadow_offset_y", 1)
	text_vbox.add_child(_deck_sub_banner)


func _build_available_decks_pedestal() -> void:
	"""Crea el pedestal diegético estático de 'Mazos Disponibles' en la meseta izquierda del altar.
	Cubre el fondo original con una placa de piedra que muestra la cantidad de mazos cargados."""

	# Pedestal Plaque Control estático (sin interactividad de ratón)
	_btn_available_decks = Control.new()
	_btn_available_decks.name = "PedestalMazosDisponibles"
	_btn_available_decks.set_anchor(SIDE_LEFT, 0.5)
	_btn_available_decks.set_anchor(SIDE_RIGHT, 0.5)
	_btn_available_decks.set_anchor(SIDE_TOP, 0.5)
	_btn_available_decks.set_anchor(SIDE_BOTTOM, 0.5)
	_btn_available_decks.set_offset(SIDE_LEFT, -550)
	_btn_available_decks.set_offset(SIDE_RIGHT, -230)
	_btn_available_decks.set_offset(SIDE_TOP, 224)
	_btn_available_decks.set_offset(SIDE_BOTTOM, 331)
	_btn_available_decks.pivot_offset = Vector2(160.0, 53.5)
	_btn_available_decks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_btn_available_decks)

	# Placa base de piedra
	var plaque_tex = TextureRect.new()
	plaque_tex.name = "ButtonTexture"
	plaque_tex.texture = TEX_BTN_PLAQUE_BLANK
	plaque_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plaque_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plaque_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	plaque_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_available_decks.add_child(plaque_tex)

	# Etiqueta con tipografía grande, nítida y en alto contraste
	_parchment_label = Label.new()
	_parchment_label.name = "LabelDisponibles"
	_parchment_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_parchment_label.text = "CARGANDO MAZOS..."
	_parchment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parchment_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_parchment_label.add_theme_font_override("font", FONT_TITLE)
	_parchment_label.add_theme_font_size_override("font_size", 18)
	_parchment_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75, 1.0))
	_parchment_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.98))
	_parchment_label.add_theme_constant_override("shadow_offset_x", 1)
	_parchment_label.add_theme_constant_override("shadow_offset_y", 2)
	_parchment_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_available_decks.add_child(_parchment_label)


func _build_timer_pedestal() -> void:
	"""Crea el pedestal diegético interactivo de 'Temporizador' en la meseta derecha del altar.
	Permite al anfitrión (o jugador local) activar o desactivar el límite de tiempo de turno."""
	_btn_timer_pedestal = Control.new()
	_btn_timer_pedestal.name = "PedestalTemporizador"
	_btn_timer_pedestal.set_anchor(SIDE_LEFT, 0.5)
	_btn_timer_pedestal.set_anchor(SIDE_RIGHT, 0.5)
	_btn_timer_pedestal.set_anchor(SIDE_TOP, 0.5)
	_btn_timer_pedestal.set_anchor(SIDE_BOTTOM, 0.5)
	_btn_timer_pedestal.set_offset(SIDE_LEFT, 230)
	_btn_timer_pedestal.set_offset(SIDE_RIGHT, 550)
	_btn_timer_pedestal.set_offset(SIDE_TOP, 224)
	_btn_timer_pedestal.set_offset(SIDE_BOTTOM, 331)
	_btn_timer_pedestal.pivot_offset = Vector2(160.0, 53.5)
	_btn_timer_pedestal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_btn_timer_pedestal)

	# Contenedor para micro-animación táctil al interactuar
	var timer_fx = Control.new()
	timer_fx.name = "TimerFX"
	timer_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timer_fx.pivot_offset = Vector2(160.0, 53.5)
	timer_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_timer_pedestal.add_child(timer_fx)

	# Placa base de piedra idéntica a la meseta izquierda
	var plaque_tex = TextureRect.new()
	plaque_tex.name = "ButtonTexture"
	plaque_tex.texture = TEX_BTN_PLAQUE_BLANK
	plaque_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plaque_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plaque_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	plaque_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_fx.add_child(plaque_tex)

	# VBoxContainer de textos informativos centrados
	var text_vbox = VBoxContainer.new()
	text_vbox.name = "TimerVBox"
	text_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.add_theme_constant_override("separation", 1)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_fx.add_child(text_vbox)

	var title_lbl = Label.new()
	title_lbl.name = "TimerTitle"
	title_lbl.text = "TEMPORIZADOR"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", FONT_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.76, 0.45, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.98))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title_lbl)

	_timer_status_label = Label.new()
	_timer_status_label.name = "TimerStatus"
	_timer_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_status_label.pivot_offset = Vector2(160.0, 12.0)
	_timer_status_label.add_theme_font_override("font", FONT_TITLE)
	_timer_status_label.add_theme_font_size_override("font_size", 17)
	_timer_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.98))
	_timer_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_timer_status_label.add_theme_constant_override("shadow_offset_y", 2)
	_timer_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(_timer_status_label)

	_timer_hint_label = Label.new()
	_timer_hint_label.name = "TimerHint"
	_timer_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_hint_label.add_theme_font_override("font", FONT_MEDIEVAL)
	_timer_hint_label.add_theme_font_size_override("font_size", 11)
	_timer_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_timer_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_timer_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_timer_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(_timer_hint_label)

	# Botón invisible táctil
	var is_remote_guest: bool = (NetworkClient.room_code != "" and not NetworkClient.is_host)
	_btn_timer_clicker = Button.new()
	_btn_timer_clicker.name = "TimerClicker"
	_btn_timer_clicker.flat = true
	_btn_timer_clicker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not is_remote_guest:
		_btn_timer_clicker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_btn_timer_clicker.pressed.connect(_on_timer_pedestal_pressed)
		_btn_timer_clicker.mouse_entered.connect(func():
			var tw = timer_fx.create_tween()
			tw.tween_property(timer_fx, "scale", Vector2(1.025, 1.025), 0.12).set_ease(Tween.EASE_OUT)
		)
		_btn_timer_clicker.mouse_exited.connect(func():
			var tw = timer_fx.create_tween()
			tw.tween_property(timer_fx, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
		)
		_btn_timer_clicker.button_down.connect(func():
			var tw = timer_fx.create_tween()
			tw.tween_property(timer_fx, "scale", Vector2(0.975, 0.975), 0.06).set_ease(Tween.EASE_OUT)
		)
		_btn_timer_clicker.button_up.connect(func():
			var tw = timer_fx.create_tween()
			tw.tween_property(timer_fx, "scale", Vector2(1.025, 1.025), 0.1).set_ease(Tween.EASE_OUT)
		)
	else:
		_btn_timer_clicker.mouse_default_cursor_shape = Control.CURSOR_ARROW

	_btn_timer_pedestal.add_child(_btn_timer_clicker)

	# Si es invitado en sala, revisar si ya se recibió la configuración del anfitrión
	if is_remote_guest:
		var cfg: Dictionary = NetworkClient.last_message_by_op.get("match_config", {})
		if not cfg.is_empty() and cfg.has("timer_enabled"):
			NetworkClient.match_timer_enabled = bool(cfg.get("timer_enabled", true))

	_update_timer_pedestal_ui()


func _on_timer_pedestal_pressed() -> void:
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		return
	
	var new_val: bool = not GameSettings.match_timer_enabled
	GameSettings.set_match_timer_enabled(new_val)
	_update_timer_pedestal_ui()

	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_ui_click"):
		am.play_ui_click()

	if NetworkClient.room_code != "" and NetworkClient.is_host:
		NetworkClient.send_message({
			"op": "match_config",
			"timer_enabled": new_val
		})


func _update_timer_pedestal_ui() -> void:
	if not is_instance_valid(_timer_status_label):
		return
	
	var is_remote_guest: bool = (NetworkClient.room_code != "" and not NetworkClient.is_host)
	var timer_enabled: bool = NetworkClient.match_timer_enabled if is_remote_guest else GameSettings.match_timer_enabled

	if timer_enabled:
		_timer_status_label.text = "SÍ  (60s)"
		_timer_status_label.add_theme_color_override("font_color", Color(0.35, 0.92, 0.65, 1.0))
	else:
		_timer_status_label.text = "NO  (Sin tiempo)"
		_timer_status_label.add_theme_color_override("font_color", Color(0.96, 0.68, 0.38, 1.0))

	if is_instance_valid(_timer_hint_label):
		if is_remote_guest:
			_timer_hint_label.text = "(Fijado por el Anfitrión)"
			_timer_hint_label.add_theme_color_override("font_color", Color(0.60, 0.56, 0.48, 0.75))
		else:
			_timer_hint_label.text = "(Toca para cambiar)"
			_timer_hint_label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58, 0.85))

	var tw = _timer_status_label.create_tween()
	tw.tween_property(_timer_status_label, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_timer_status_label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD)


func _on_network_message_deck_selector(data: Dictionary) -> void:
	if data.get("op", "") == "match_config":
		if data.has("timer_enabled"):
			NetworkClient.match_timer_enabled = bool(data.get("timer_enabled", true))
			_update_timer_pedestal_ui()


func _exit_tree() -> void:
	if NetworkClient.message_received.is_connected(_on_network_message_deck_selector):
		NetworkClient.message_received.disconnect(_on_network_message_deck_selector)


func _build_clean_action_buttons() -> void:
	"""Crea botones interactivos en el pedestal que calzan al milímetro sobre los botones
	del fondo original, tapándolos por completo con versiones 3D táctiles y vivas."""

	# =========================================================================
	# 1. PEDESTAL CENTRAL: COMENZAR PARTIDA (Calce 100% exacto sobre el altar)
	# =========================================================================
	_btn_confirm = Control.new()
	_btn_confirm.name = "PedestalComenzarPartida"
	_btn_confirm.set_anchor(SIDE_LEFT, 0.5)
	_btn_confirm.set_anchor(SIDE_RIGHT, 0.5)
	_btn_confirm.set_anchor(SIDE_TOP, 0.5)
	_btn_confirm.set_anchor(SIDE_BOTTOM, 0.5)
	_btn_confirm.set_offset(SIDE_LEFT, -189)
	_btn_confirm.set_offset(SIDE_RIGHT, 221)
	_btn_confirm.set_offset(SIDE_TOP, 235)
	_btn_confirm.set_offset(SIDE_BOTTOM, 407)
	_btn_confirm.pivot_offset = Vector2(205.0, 86.0)
	_btn_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_btn_confirm)

	# Contenedor para animación táctil (escala y elevación 3D limpia)
	var confirm_fx = Control.new()
	confirm_fx.name = "ConfirmFX"
	confirm_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_fx.pivot_offset = Vector2(205.0, 86.0)
	confirm_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_confirm.add_child(confirm_fx)

	# Textura HD exacta que cubre ("tapa") el botón del fondo original a la perfección
	var confirm_tex = TextureRect.new()
	confirm_tex.name = "ButtonTexture"
	confirm_tex.texture = TEX_BTN_CONFIRM
	confirm_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	confirm_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	confirm_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_fx.add_child(confirm_tex)

	# Capa de Gemas Turquesas Rúnicas Vivas (ubicadas al píxel sobre las 4 gemas del pedestal)
	var confirm_gems = GemGlowDrawer.new()
	confirm_gems.name = "RunicGems"
	confirm_gems.gem_color = Color(0.05, 0.95, 0.85)
	confirm_gems.gem_positions = [
		Vector2(25.5, 85.5),   # Gema ala izquierda
		Vector2(384.0, 85.5),  # Gema ala derecha
		Vector2(205.5, 27.0),  # Gema diamante superior
		Vector2(205.0, 142.5)  # Gema diamante inferior
	]
	confirm_fx.add_child(confirm_gems)
	_start_gem_pulse(confirm_gems)

	# Pastilla Esmeralda Diegética para brillo interior y Shimmer (sin paneles verdes artificiales)
	var pill_fx = Control.new()
	pill_fx.name = "EmeraldPillFX"
	pill_fx.set_anchor(SIDE_LEFT, 0.5)
	pill_fx.set_anchor(SIDE_RIGHT, 0.5)
	pill_fx.set_anchor(SIDE_TOP, 0.5)
	pill_fx.set_anchor(SIDE_BOTTOM, 0.5)
	pill_fx.set_offset(SIDE_LEFT, -155)
	pill_fx.set_offset(SIDE_RIGHT, 155)
	pill_fx.set_offset(SIDE_TOP, -36)
	pill_fx.set_offset(SIDE_BOTTOM, 36)
	pill_fx.pivot_offset = Vector2(155.0, 36.0)
	pill_fx.clip_contents = true
	pill_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_fx.add_child(pill_fx)

	# Haz de luz Shimmer diagonal confinado a la pastilla esmeralda
	var confirm_shimmer_beam = ShimmerBeam.new()
	confirm_shimmer_beam.name = "ShimmerBeam"
	confirm_shimmer_beam.size = Vector2(36, 72)
	confirm_shimmer_beam.position = Vector2(-70, 0)
	pill_fx.add_child(confirm_shimmer_beam)

	# Destello de confirmación al presionar el botón
	_confirm_flash = ColorRect.new()
	_confirm_flash.name = "EmeraldFlash"
	_confirm_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_flash.color = Color(1.0, 0.95, 0.8, 0.0)
	_confirm_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_fx.add_child(_confirm_flash)

	# Botón invisible de interacción táctil
	_btn_confirm_clicker = Button.new()
	_btn_confirm_clicker.name = "Clicker"
	_btn_confirm_clicker.flat = true
	_btn_confirm_clicker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn_confirm_clicker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_btn_confirm_clicker.pressed.connect(_on_confirm_pressed)
	_btn_confirm.add_child(_btn_confirm_clicker)

	_btn_confirm_clicker.mouse_entered.connect(func():
		if _selected_player_idx >= 0:
			var tw = confirm_fx.create_tween()
			tw.set_parallel(true)
			tw.tween_property(confirm_fx, "scale", Vector2(1.008, 1.008), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(confirm_fx, "position:y", -1.0, 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(confirm_gems, "pulse_alpha", 0.85, 0.12)
			_trigger_shimmer(confirm_shimmer_beam, 380.0)
	)
	_btn_confirm_clicker.mouse_exited.connect(func():
		var tw = confirm_fx.create_tween()
		tw.set_parallel(true)
		tw.tween_property(confirm_fx, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(confirm_fx, "position:y", 0.0, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(confirm_gems, "pulse_alpha", 0.45, 0.12)
	)
	_btn_confirm_clicker.button_down.connect(func():
		if _selected_player_idx >= 0:
			var tw = confirm_fx.create_tween()
			tw.set_parallel(true)
			tw.tween_property(confirm_fx, "scale", Vector2(0.992, 0.992), 0.06).set_ease(Tween.EASE_OUT)
			tw.tween_property(confirm_fx, "position:y", 1.0, 0.06).set_ease(Tween.EASE_OUT)
	)
	_btn_confirm_clicker.button_up.connect(func():
		var tw = confirm_fx.create_tween()
		tw.set_parallel(true)
		tw.tween_property(confirm_fx, "scale", Vector2(1.008, 1.008), 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(confirm_fx, "position:y", -1.0, 0.1).set_ease(Tween.EASE_OUT)
	)

	# =========================================================================
	# 3. BOTÓN "MAZOS PÚBLICOS": buscar y jugar mazos públicos de ShadowForge. Botón plano (no hay
	# textura de pedestal); abre un popup de búsqueda encima del altar.
	# =========================================================================
	var public_decks_btn = Button.new()
	public_decks_btn.name = "PublicDecksButton"
	public_decks_btn.text = "Mazos públicos de ShadowForge"
	public_decks_btn.set_anchor(SIDE_LEFT, 1.0)
	public_decks_btn.set_anchor(SIDE_RIGHT, 1.0)
	public_decks_btn.set_anchor(SIDE_TOP, 0.0)
	public_decks_btn.set_anchor(SIDE_BOTTOM, 0.0)
	public_decks_btn.set_offset(SIDE_LEFT, -260)
	public_decks_btn.set_offset(SIDE_RIGHT, -16)
	public_decks_btn.set_offset(SIDE_TOP, 16)
	public_decks_btn.set_offset(SIDE_BOTTOM, 52)
	public_decks_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	public_decks_btn.add_theme_font_override("font", FONT_MEDIEVAL)
	public_decks_btn.add_theme_font_size_override("font_size", 14)
	public_decks_btn.pressed.connect(_open_public_deck_browser)
	_overlay.add_child(public_decks_btn)


func _start_gem_pulse(drawer: GemGlowDrawer) -> void:
	if not is_instance_valid(drawer): return
	var tw = drawer.create_tween().set_loops()
	tw.tween_property(drawer, "pulse_alpha", 1.0, 1.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(drawer, "pulse_alpha", 0.45, 1.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _trigger_shimmer(beam: ShimmerBeam, target_x: float) -> void:
	if not is_instance_valid(beam): return
	beam.position.x = -70.0
	var tw = beam.create_tween()
	tw.tween_property(beam, "position:x", target_x, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _build_loading_placeholder() -> Control:
	var box = CenterContainer.new()
	box.custom_minimum_size = Vector2(800, CARD_SIZE.y)
	box.size_flags_vertical = Control.SIZE_SHRINK_END

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)

	var spin_holder = Control.new()
	spin_holder.custom_minimum_size = Vector2(64, 64)
	vbox.add_child(spin_holder)

	var spinner = Node2D.new()
	spinner.set_script(SpinnerDrawerScript)
	spinner.position = Vector2(32, 32)
	spin_holder.add_child(spinner)

	var tw = spinner.create_tween().set_loops()
	tw.tween_property(spinner, "rotation", TAU, 1.8).from(0.0)

	var lbl = Label.new()
	lbl.text = "Invocando grimorios ancestrales..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", FONT_TITLE)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", RUNIC_CYAN)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(lbl)

	var tw_txt = lbl.create_tween().set_loops()
	tw_txt.tween_property(lbl, "modulate:a", 0.4, 0.8).set_trans(Tween.TRANS_SINE)
	tw_txt.tween_property(lbl, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	return box
