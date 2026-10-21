class_name ZoneViewerModule
extends Node

const CardScene = preload("res://scenes/cards/Card.tscn")
const TEX_CEMETERY_BG := preload("res://assets/backgrounds/cementerio_bg.jpg")
const TEX_EXILE_BG    := preload("res://assets/backgrounds/destierro_bg.jpg")
const TEX_PEDESTAL_CEM := preload("res://assets/ui/zones/pedestal_cementerio.png")
const TEX_PEDESTAL_DST := preload("res://assets/ui/zones/pedestal_destierro.png")
const SHADER_VIGNETTE := preload("res://assets/shaders/zone_modal_vignette.gdshader")

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)
const CastleTopPlay = preload("res://scripts/core/effects/mechanics/CastleTopPlay.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var _main: Node = null


func setup(main: Node) -> void:
	_main = main
	setup_public_zone_viewers()


func setup_public_zone_viewers() -> void:
	var zones = [
		[_main._panel_player_cem,  "Cementerio",  0, "cemetery"],
		[_main._panel_player_dst,  "Destierro",   0, "exile"],
		[_main._panel_opp_cem,     "Cementerio",  1, "cemetery"],
		[_main._panel_opp_dst,     "Destierro",   1, "exile"],
	]
	for z in zones:
		var panel: Panel = z[0]
		var label: String = z[1]
		var pid: int = z[2]
		var ztype: String = z[3]
		var is_cem: bool = (ztype == "cemetery")

		panel.clip_contents = false
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.pivot_offset = panel.size / 2.0

		# 1. Marco y relieve ornamental
		var pstyle := StyleBoxFlat.new()
		pstyle.set_corner_radius_all(10)
		pstyle.shadow_size = 12
		pstyle.shadow_color = Color(0, 0, 0, 0.85)
		if is_cem:
			pstyle.bg_color = Color(0.04, 0.05, 0.04, 0.20)
			pstyle.border_color = Color(0.72, 0.60, 0.35, 0.88)
			pstyle.set_border_width_all(2)
		else:
			pstyle.bg_color = Color(0.05, 0.03, 0.07, 0.20)
			pstyle.border_color = Color(0.65, 0.45, 0.88, 0.88)
			pstyle.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", pstyle)

		# 2. Contenedor interno recortado para el pedestal y cartas
		var inner := Control.new()
		inner.name = "InnerCardArea"
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.clip_contents = true
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(inner)

		# 3. Pedestal temático ilustrado de fondo
		var bg_rect := TextureRect.new()
		bg_rect.name = "PedestalBg"
		bg_rect.texture = TEX_PEDESTAL_CEM if is_cem else TEX_PEDESTAL_DST
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(bg_rect)

		# 4. Aura de respiración mística (Idle Life)
		var aura := ColorRect.new()
		aura.name = "AuraGlow"
		aura.set_anchors_preset(Control.PRESET_FULL_RECT)
		aura.color = Color(0.18, 0.85, 0.40, 0.12) if is_cem else Color(0.65, 0.30, 0.95, 0.14)
		aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(aura)

		var aura_tw := aura.create_tween().set_loops()
		aura_tw.tween_property(aura, "modulate:a", 0.45, 2.0).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_IN_OUT)
		aura_tw.tween_property(aura, "modulate:a", 1.0, 2.0).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_IN_OUT)

		# 5. Capas físicas de cartas apiladas (Underlays 3D)
		var underlay2 := TextureRect.new()
		underlay2.name = "StackUnderlay2"
		underlay2.texture = GameSettings.get_card_back_texture(0)
		underlay2.modulate = Color(0.40, 0.40, 0.48, 0.9)
		underlay2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		underlay2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		underlay2.size = Vector2(94, 134)
		underlay2.position = Vector2(3, 4)
		underlay2.pivot_offset = Vector2(47, 67)
		underlay2.rotation_degrees = -2.0
		underlay2.visible = false
		underlay2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(underlay2)

		var underlay1 := TextureRect.new()
		underlay1.name = "StackUnderlay1"
		underlay1.texture = GameSettings.get_card_back_texture(0)
		underlay1.modulate = Color(0.60, 0.60, 0.68, 0.95)
		underlay1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		underlay1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		underlay1.size = Vector2(96, 136)
		underlay1.position = Vector2(2, 2)
		underlay1.pivot_offset = Vector2(48, 68)
		underlay1.rotation_degrees = 1.5
		underlay1.visible = false
		underlay1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(underlay1)

		# 6. Previsualización de la carta del tope
		var tr := TextureRect.new()
		tr.name = "TopCardPreview"
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.visible = false
		if pid == 1:
			tr.pivot_offset = Vector2(50.0, 70.0)
			tr.rotation_degrees = 180.0
		inner.add_child(tr)

		# 7. Medallón heráldico para el contador
		var count_lbl: Label = panel.get_node_or_null("Count")
		if count_lbl:
			var badge := Panel.new()
			badge.name = "CountBadge"
			badge.custom_minimum_size = Vector2(28, 28)
			badge.size = Vector2(28, 28)
			badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			badge.anchor_left = 1.0
			badge.anchor_top = 1.0
			badge.anchor_right = 1.0
			badge.anchor_bottom = 1.0
			badge.offset_left = -32.0
			badge.offset_top = -32.0
			badge.offset_right = -4.0
			badge.offset_bottom = -4.0
			badge.pivot_offset = Vector2(14, 14)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var bstyle := StyleBoxFlat.new()
			bstyle.bg_color = Color(0.06, 0.05, 0.08, 0.94)
			bstyle.set_border_width_all(2)
			if is_cem:
				bstyle.border_color = Color(0.88, 0.75, 0.35, 1.0)
			else:
				bstyle.border_color = Color(0.78, 0.58, 0.95, 1.0)
			bstyle.set_corner_radius_all(14)
			bstyle.shadow_color = Color(0, 0, 0, 0.80)
			bstyle.shadow_size = 4
			badge.add_theme_stylebox_override("panel", bstyle)

			count_lbl.get_parent().remove_child(count_lbl)
			badge.add_child(count_lbl)
			count_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			count_lbl.offset_left = 0
			count_lbl.offset_top = 0
			count_lbl.offset_right = 0
			count_lbl.offset_bottom = 0
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			count_lbl.add_theme_font_size_override("font_size", 14)
			count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

			panel.add_child(badge)

		# 8. Feedback interactivo de hover
		panel.mouse_entered.connect(func():
			var tw := panel.create_tween()
			tw.set_parallel(true)
			tw.tween_property(panel, "scale", Vector2(1.03, 1.03), 0.12).set_ease(
				Tween.EASE_OUT
			)
			var h_col = Color(1.0, 0.88, 0.45, 1.0) if is_cem else Color(0.90, 0.72, 1.0, 1.0)
			tw.tween_property(pstyle, "border_color", h_col, 0.12)
		)
		panel.mouse_exited.connect(func():
			var tw := panel.create_tween()
			tw.set_parallel(true)
			tw.tween_property(panel, "scale", Vector2.ONE, 0.12).set_ease(
				Tween.EASE_OUT
			)
			var b_col = Color(0.72, 0.60, 0.35, 0.88) if is_cem else Color(0.65, 0.45, 0.88, 0.88)
			tw.tween_property(pstyle, "border_color", b_col, 0.12)
		)

		panel.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				# Con el selector de zonas activo (ZoneBrowsePicker), el clic en el panel abre SU visor, no
				# este.
				if _main._zone_browse_picker and _main._zone_browse_picker.is_active():
					return
				_show_zone_popup(label, pid, ztype)
		)

	# Conectar señales del CardManager para actualizar el tope en tiempo real
	CardManager.cemetery_count_changed.connect(_on_zone_cemetery_changed)
	CardManager.exile_count_changed.connect(_on_zone_exile_changed)

	# Cuando CardDatabase termina de descargar una imagen, refrescar las zonas
	CardDatabase.card_image_loaded.connect(_on_zone_card_image_loaded)

	# Revelado del tope del Castillo (La Ouija): el Castillo es zona oculta; el TopCardPreview de
	# PlayerCastillo solo se muestra mientras haya una carta propia en la Reserva con "Juega mostrando
	# la primera carta de tu Castillo" (refresh_castillo_top_reveal()). Solo se revela el TOPE, sin
	# popup del mazo.
	var castillo_tr = TextureRect.new()
	castillo_tr.name = "TopCardPreview"
	castillo_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	castillo_tr.set_offsets_preset(Control.PRESET_FULL_RECT)
	castillo_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	castillo_tr.stretch_mode = TextureRect.STRETCH_SCALE
	castillo_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	castillo_tr.visible = false
	_main._panel_player_castillo.add_child(castillo_tr)

	# Escritura Sagrada: al tocar tu Castillo se abren las dos primeras cartas, como el Cementerio.
	_main._panel_player_castillo.gui_input.connect(func(ev):
		if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
			return
		if SelectionManager._dialogs.get("_castillo_pick_active"):
			return  # está eligiendo un Castillo para otro efecto
		if CastleTopPlay.escritura_active(0):
			_show_zone_popup("Castillo", 0, "castillo_top")
	)

	CardManager.card_destroyed.connect(func(_pid, _c): refresh_castillo_top_reveal())
	CardManager.card_exiled.connect(func(_pid, _c): refresh_castillo_top_reveal())
	if not PriorityManager.priority_changed.is_connected(_on_priority_changed_refresh_castillo_top):
		PriorityManager.priority_changed.connect(_on_priority_changed_refresh_castillo_top)
	# Refrescar el revelado del tope con deck_count_changed: cubre
	# CardManager.take_damage()/mill_cards() (daño de combate y "Botar N cartas", que sacan del tope) y
	# cualquier sitio que use _emit_deck_changed(). ActionSearch.gd/ActionModule.shuffle_deck() tocan
	# el mazo sin esa señal y llaman _update_castillo_counts() directo.
	if not CardManager.deck_count_changed.is_connected(_on_deck_count_changed_refresh_castillo_top):
		CardManager.deck_count_changed.connect(_on_deck_count_changed_refresh_castillo_top)


func _show_zone_popup(title: String, player_id: int, zone_type: String) -> void:
	var cards_data: Array = CardManager.get_cemetery(player_id) if zone_type == "cemetery" else CardManager.get_exile(player_id)
	if zone_type == "castillo_top":
		cards_data = CastleTopPlay.escritura_top(player_id)

	# Limpiar popup anterior
	var existing = _main.get_node_or_null("ZoneViewerPopup")
	if existing:
		existing.queue_free()

	var vp = get_viewport().get_visible_rect().size

	var popup_canvas = CanvasLayer.new()
	popup_canvas.name = "ZoneViewerPopup"
	popup_canvas.layer = 55
	_main.add_child(popup_canvas)

	# Fondo oscuro exterior traslúcido — click fuera cierra
	var bg = ColorRect.new()
	bg.size = vp
	bg.color = Color(0.01, 0.01, 0.02, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			popup_canvas.queue_free()
	)
	popup_canvas.add_child(bg)

	var n_cards := cards_data.size()
	var is_cemetery := zone_type == "cemetery"

	# Paleta y textura ilustrada temática generada
	var bg_tex = TEX_CEMETERY_BG if is_cemetery else TEX_EXILE_BG
	var title_color = Color(1.0, 0.90, 0.60, 1.0)
	var tint_color = Color(0.01, 0.04, 0.04, 0.35) if is_cemetery else Color(0.04, 0.01, 0.05, 0.35)

	# Dimensiones dinámicas adaptadas a la proporción real de cartas 1:1.4
	var popup_w: float
	var popup_h: float
	if n_cards == 0:
		popup_w = 460.0
		popup_h = 220.0
	elif n_cards <= 4:
		var card_w := 140.0
		var sep := 18.0
		var content_w := float(n_cards) * card_w + float(n_cards - 1) * sep + 60.0
		popup_w = clampf(content_w, 460.0, vp.x * 0.88)
		popup_h = 320.0
	else:
		popup_w = minf(vp.x * 0.88, 880.0)
		popup_h = minf(vp.y * 0.84, 580.0)

	var panel = Panel.new()
	panel.size = Vector2(popup_w, popup_h)
	panel.position = (vp - panel.size) / 2.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = false

	# Estilo con borde biselado de oro envejecido y sombra profunda
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.03, 0.06, 0.98)
	pstyle.border_color = Color(0.85, 0.72, 0.28, 0.95)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(18)
	pstyle.shadow_color = Color(0, 0, 0, 0.90)
	pstyle.shadow_size = 35
	panel.add_theme_stylebox_override("panel", pstyle)
	popup_canvas.add_child(panel)

	# 1. Textura de fondo con shader de viñeta suave y esquinas redondeadas antialiased
	var bg_rect = TextureRect.new()
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.texture = bg_tex
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var smat = ShaderMaterial.new()
	smat.shader = SHADER_VIGNETTE
	smat.set_shader_parameter("panel_size", Vector2(popup_w, popup_h))
	smat.set_shader_parameter("corner_radius", 18.0)
	smat.set_shader_parameter("vignette_amount", 0.72)
	smat.set_shader_parameter("tint_color", tint_color)
	smat.set_shader_parameter("edge_shadow_color", Color(0.01, 0.01, 0.02, 0.95))
	bg_rect.material = smat
	panel.add_child(bg_rect)

	# Layout interior
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Encabezado con acabado de oro
	var header_bar = PanelContainer.new()
	var hb_style = StyleBoxFlat.new()
	hb_style.bg_color = Color(0.06, 0.05, 0.09, 0.85)
	hb_style.border_color = Color(0.80, 0.68, 0.32, 0.50)
	hb_style.border_width_bottom = 1
	hb_style.set_corner_radius_all(10)
	hb_style.content_margin_left = 14
	hb_style.content_margin_right = 14
	hb_style.content_margin_top = 8
	hb_style.content_margin_bottom = 8
	header_bar.add_theme_stylebox_override("panel", hb_style)
	vbox.add_child(header_bar)

	var header = HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 14)
	header_bar.add_child(header)

	var title_lbl = Label.new()
	title_lbl.text = "CEMENTERIO" if is_cemetery else "DESTIERRO"
	if zone_type == "castillo_top":
		title_lbl.text = "CASTILLO — DOS PRIMERAS"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", FONT_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", title_color)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	header.add_child(title_lbl)

	# Pastilla de contador heráldica con marco dorado
	var gem_panel = PanelContainer.new()
	var g_style = StyleBoxFlat.new()
	g_style.bg_color = Color(0.10, 0.09, 0.14, 0.90)
	g_style.border_color = Color(0.85, 0.72, 0.28, 0.80)
	g_style.set_border_width_all(1)
	g_style.set_corner_radius_all(8)
	g_style.content_margin_left = 10
	g_style.content_margin_right = 10
	g_style.content_margin_top = 4
	g_style.content_margin_bottom = 4
	gem_panel.add_theme_stylebox_override("panel", g_style)
	header.add_child(gem_panel)

	var count_lbl = Label.new()
	count_lbl.text = "%d %s" % [n_cards, "Carta" if n_cards == 1 else "Cartas"]
	count_lbl.add_theme_font_override("font", FONT_TITLE)
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	gem_panel.add_child(count_lbl)

	var close_btn = Button.new()
	close_btn.text = "CERRAR"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_font_override("font", FONT_TITLE)
	close_btn.add_theme_font_size_override("font_size", 11)

	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.18, 0.10, 0.10, 0.90)
	c_style.border_color = Color(0.75, 0.40, 0.40, 0.85)
	c_style.set_border_width_all(1)
	c_style.set_corner_radius_all(6)
	c_style.content_margin_left = 12
	c_style.content_margin_right = 12
	c_style.content_margin_top = 4
	c_style.content_margin_bottom = 4
	close_btn.add_theme_stylebox_override("normal", c_style)

	var c_hover = c_style.duplicate()
	c_hover.bg_color = Color(0.28, 0.14, 0.14, 1.0)
	c_hover.border_color = Color(1.0, 0.55, 0.55, 1.0)
	close_btn.add_theme_stylebox_override("hover", c_hover)

	close_btn.add_theme_color_override("font_color", Color(1.0, 0.88, 0.88))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	close_btn.pressed.connect(func(): popup_canvas.queue_free())
	header.add_child(close_btn)

	if cards_data.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Esta zona está vacía."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_override("font", FONT_BODY)
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.75, 1.0))
		vbox.add_child(empty_lbl)
		return

	var is_own_zone := player_id == 0

	if n_cards <= 4:
		var center_box = HBoxContainer.new()
		center_box.alignment = BoxContainer.ALIGNMENT_CENTER
		center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_box.add_theme_constant_override("separation", 18)
		vbox.add_child(center_box)

		for card_data in cards_data:
			_create_popup_card(card_data, player_id, zone_type, is_own_zone, popup_canvas, center_box, Vector2(0.933, 0.933))
	else:
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(scroll)

		var grid = GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 16)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		for card_data in cards_data:
			_create_popup_card(card_data, player_id, zone_type, is_own_zone, popup_canvas, grid, Vector2(0.84, 0.84))


func _create_popup_card(card_data: Dictionary, player_id: int, zone_type: String, is_own_zone: bool, popup_canvas: CanvasLayer, container: Control, base_scale_val: Vector2) -> void:
	# Wrapper con dimensiones fijas para evitar deformación por contenedores de Godot
	var target_w := 150.0 * base_scale_val.x
	var target_h := 210.0 * base_scale_val.y
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(target_w, target_h)
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var card = CardScene.instantiate()
	card.load_from_data(card_data)
	card.set_zone(Constants.Zone.CEMENTERIO if zone_type == "cemetery" else Constants.Zone.DESTIERRO)
	if zone_type == "castillo_top":
		card.set_zone(Constants.Zone.CASTILLO)
	card.owner_id = player_id
	card.can_interact = false
	card.drag_enabled = false
	card.custom_minimum_size = Vector2(150.0, 210.0)
	card.size = Vector2(150.0, 210.0)
	card.scale = base_scale_val
	card.base_scale = base_scale_val
	card.position = Vector2.ZERO
	card.pivot_offset = Vector2.ZERO

	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_main._card_inspector.on_card_right_clicked(card)
	)

	var is_exhumable := is_own_zone and zone_type == "cemetery" and PaymentManager.card_has_exhumar(card_data, player_id)
	var is_exile_playable := is_own_zone and zone_type == "exile" and PaymentManager.card_playable_from_exile(card_data)
	var is_top_playable := is_own_zone and zone_type == "castillo_top" and CastleTopPlay.escritura_can_play(card_data, player_id)

	if is_exhumable or is_exile_playable or is_top_playable:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# Borde pulsante esmeralda de acción legal disponible
		var glow_panel = Panel.new()
		glow_panel.name = "LegalActionGlow"
		glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		var gstyle = StyleBoxFlat.new()
		gstyle.bg_color = Color(0, 0, 0, 0)
		gstyle.border_color = Color(0.35, 1.0, 0.55, 0.95)
		gstyle.set_border_width_all(3)
		gstyle.set_corner_radius_all(8)
		gstyle.shadow_color = Color(0.20, 0.90, 0.40, 0.55)
		gstyle.shadow_size = 8
		glow_panel.add_theme_stylebox_override("panel", gstyle)
		card.add_child(glow_panel)

		var ptw = card.create_tween().set_loops()
		ptw.tween_property(glow_panel, "modulate:a", 0.35, 0.6).set_ease(Tween.EASE_IN_OUT)
		ptw.tween_property(glow_panel, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_IN_OUT)

		# Pastilla heráldica inferior con texto limpio (sin emojis)
		var action_badge = PanelContainer.new()
		action_badge.name = "ActionBadge"
		action_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_badge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		action_badge.offset_top = -28
		action_badge.offset_bottom = -6
		action_badge.offset_left = -48
		action_badge.offset_right = 48
		var ab_style = StyleBoxFlat.new()
		ab_style.bg_color = Color(0.06, 0.22, 0.12, 0.95)
		ab_style.border_color = Color(0.40, 1.0, 0.60, 1.0)
		ab_style.set_border_width_all(1)
		ab_style.set_corner_radius_all(6)
		ab_style.content_margin_left = 6
		ab_style.content_margin_right = 6
		action_badge.add_theme_stylebox_override("panel", ab_style)

		var action_lbl = Label.new()
		action_lbl.text = "EXHUMAR" if is_exhumable else "JUGAR"
		action_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action_lbl.add_theme_font_override("font", FONT_TITLE)
		action_lbl.add_theme_font_size_override("font_size", 10)
		action_lbl.add_theme_color_override("font_color", Color(0.90, 1.0, 0.90, 1.0))
		action_badge.add_child(action_lbl)
		card.add_child(action_badge)

		if is_exhumable:
			card.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
					_on_exhumar_card_clicked(card_data, popup_canvas)
			)
		elif is_exile_playable:
			card.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
					_on_exile_card_clicked(card_data, popup_canvas)
			)
		elif is_top_playable:
			card.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
					if popup_canvas and is_instance_valid(popup_canvas):
						popup_canvas.queue_free()
					await CastleTopPlay.escritura_play_data(card_data, player_id)
			)

	wrapper.add_child(card)
	container.add_child(wrapper)


func _on_exhumar_card_clicked(card_data: Dictionary, popup_canvas: CanvasLayer) -> void:
	"""Click en una carta con Exhumar dentro del popup del Cementerio propio: valida Oro disponible,
	cierra el popup y la juega vía GoldManager.play_card_from_cemetery — mismo camino real que
	jugar desde la mano, no el ActionPipeline/ExhumarSystem huérfanos."""
	if not _main._gold_manager:
		return
	# ("con lobo sagrado no me permite jugar armas del cementerio"): si hay una selección de objetivo
	# real esperando esta misma carta (p.ej. Lobo Sagrado eligiendo un Arma del Cementerio), resolverla
	# ahí en vez de intentar Exhumar — el jugador clickea el visor de Cementerio de siempre, no un
	# popup nuevo que no conoce. Ver CardInteractionModule.try_resolve_cemetery_click.
	if _main._card_interaction and _main._card_interaction.try_resolve_cemetery_click(card_data):
		if popup_canvas and is_instance_valid(popup_canvas):
			popup_canvas.queue_free()
		return
	var cost: int = PaymentManager.get_exhumar_cost(card_data)
	var card_name: String = card_data.get("nombre", "???")
	if _main._gold_manager.get_oro_disponible() < cost:
		_main._update_debug("Oro insuficiente para Exhumar %s (necesitas %d)" % [card_name, cost])
		return
	if popup_canvas and is_instance_valid(popup_canvas):
		popup_canvas.queue_free()
	await _main._gold_manager.play_card_from_cemetery(card_data)


func _on_exile_card_clicked(card_data: Dictionary, popup_canvas: CanvasLayer) -> void:
	"""Click en una carta jugable desde el Destierro propio dentro de su popup — cierra el popup y la
	juega vía GoldManager. play_card_from_exile (paga el coste real, no un pago especial como
	Exhumar). GoldManager.play_card_from_exile ya valida fase/prioridad/Oro disponible y avisa por
	_update_debug si algo falla, así que aquí no hace falta duplicar esos chequeos."""
	if not _main._gold_manager:
		return
	if popup_canvas and is_instance_valid(popup_canvas):
		popup_canvas.queue_free()
	var discount: int = PaymentManager.get_exile_play_discount(card_data)
	await _main._gold_manager.play_card_from_exile(card_data, discount)


func _bot_cemetery_pick(prompt: String, filter: Callable, max_count: int, lock_to_one_side: bool,
		own_data: Array, opp_data: Array, chooser_id: int) -> Array:
	"""El bot local elige solo (sin popup en la pantalla del Anfitrión): las del rival primero si el
	efecto perjudica (Desterrar, Barajar...), las propias primero si no. Mismo criterio que
	CardInteractionModule._bot_pick()."""
	var sides: Array = [[own_data, 0], [opp_data, 1]]
	var picked: Array = []
	for side in sides:
		for entry in side[0]:
			var probe: Node = _main._create_card(entry.data, false)
			probe.owner_id = side[1]
			var ok: bool = filter.call(probe)
			probe.free()
			if ok:
				picked.append({"data": entry.data, "owner_id": side[1], "zone_type": entry.zone_type})
	var harmful := false
	for w in _main._card_interaction._BOT_HARMFUL:
		if w in prompt.to_lower():
			harmful = true
	var rival: Array = picked.filter(func(p): return p.owner_id != chooser_id)
	var own: Array = picked.filter(func(p): return p.owner_id == chooser_id)
	var ordered: Array = (rival + own) if harmful else (own + rival)
	if lock_to_one_side and not ordered.is_empty():
		var side_id: int = ordered[0].owner_id
		ordered = ordered.filter(func(p): return p.owner_id == side_id)
	return ordered.slice(0, max_count) if max_count >= 0 else ordered


func open_cemetery_target_picker(prompt: String, filter: Callable, max_count: int = 1, zone_type: String = "cemetery", lock_to_one_side: bool = false, show_select_all: bool = false, chooser_id: int = 0) -> Array:
	"""Popup de selección con AMBOS Cementerios (o Destierros, o las dos zonas) lado a lado y click
	directo sobre las cartas (p.ej. Espada de O'Higgins, Hanta el Samurai). Usa
	CardInteractionModule.await_multi_target(); las cartas son Nodos temporales mientras el popup
	está abierto y su card_data es la fuente de verdad ('filter' recibe esos Nodos).
	'zone_type': "cemetery", "exile" o "cemetery_and_exile" (las dos zonas en el mismo pool; Abrazo
	de Maipú).
	'show_select_all': botón que llama a CardInteractionModule.request_select_all() (ver la
	advertencia sobre lock_to_one_side + select_all en await_multi_target()).
	Devuelve un Array de {data, owner_id, zone_type: "cemetery"/"exile"} en orden de click (o de
	lista con select-all); vacío si no había candidatos o se canceló."""
	var combine_zones: bool = zone_type == "cemetery_and_exile"
	var own_data: Array = []
	var opp_data: Array = []
	if combine_zones:
		for d in CardManager.get_cemetery(0):
			own_data.append({"data": d, "zone_type": "cemetery"})
		for d in CardManager.get_exile(0):
			own_data.append({"data": d, "zone_type": "exile"})
		for d in CardManager.get_cemetery(1):
			opp_data.append({"data": d, "zone_type": "cemetery"})
		for d in CardManager.get_exile(1):
			opp_data.append({"data": d, "zone_type": "exile"})
	else:
		var raw_own: Array = CardManager.get_cemetery(0) if zone_type == "cemetery" else CardManager.get_exile(0)
		var raw_opp: Array = CardManager.get_cemetery(1) if zone_type == "cemetery" else CardManager.get_exile(1)
		for d in raw_own:
			own_data.append({"data": d, "zone_type": zone_type})
		for d in raw_opp:
			opp_data.append({"data": d, "zone_type": zone_type})
	if own_data.is_empty() and opp_data.is_empty():
		return []

	# Paridad remota (docs/plans/2026-09-20-remote-multiplayer-parity.md), como
	# SelectionManager._delegate_selection_to_remote(): si elige el jugador 1 con un Remoto conectado,
	# se delega por red (esta UI asume jugador 0 = propio).
	EffectContextScript.check_chooser(chooser_id, prompt)
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		return await _delegate_cemetery_picker_to_remote(prompt, filter, max_count, own_data, opp_data)
	if PlayerSideScript.is_bot(chooser_id):
		return _bot_cemetery_pick(prompt, filter, max_count, lock_to_one_side, own_data, opp_data, chooser_id)

	if not _main._card_interaction:
		return []

	var existing = _main.get_node_or_null("ZoneViewerPopup")
	if existing:
		existing.queue_free()

	var vp = get_viewport().get_visible_rect().size
	var popup_canvas = CanvasLayer.new()
	popup_canvas.name = "ZoneViewerPopup"
	popup_canvas.layer = 55
	_main.add_child(popup_canvas)

	var bg = ColorRect.new()
	bg.size = vp
	bg.color = Color(0.01, 0.01, 0.02, 0.78)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and _main._card_interaction.is_selecting_target:
			_main._card_interaction.cancel_target_selection()
	)
	popup_canvas.add_child(bg)

	var panel = Panel.new()
	panel.size = Vector2(minf(vp.x * 0.92, 1000.0), minf(vp.y * 0.86, 620.0))
	panel.position = (vp - panel.size) / 2.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.03, 0.06, 0.98)
	pstyle.border_color = Color(0.85, 0.72, 0.28, 0.95)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(18)
	pstyle.shadow_color = Color(0, 0, 0, 0.90)
	pstyle.shadow_size = 30
	panel.add_theme_stylebox_override("panel", pstyle)
	popup_canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var prompt_lbl = Label.new()
	prompt_lbl.text = prompt
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_font_override("font", FONT_TITLE)
	prompt_lbl.add_theme_font_size_override("font_size", 16)
	prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60, 1.0))
	vbox.add_child(prompt_lbl)

	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	vbox.add_child(columns)

	var zone_word: String
	match zone_type:
		"cemetery": zone_word = "Cementerio"
		"exile": zone_word = "Destierro"
		_: zone_word = "Cementerio + Destierro"
	var sides: Array = [
		{"pid": 0, "label": "Tu %s" % zone_word, "data": own_data},
		{"pid": 1, "label": "%s Rival" % zone_word, "data": opp_data},
	]
	var candidates: Array = []
	for side in sides:
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8)
		columns.add_child(col)
		var lbl = Label.new()
		lbl.text = "%s (%d)" % [side.label, side.data.size()]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", FONT_TITLE)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.75, 1.0))
		col.add_child(lbl)
		if side.data.is_empty():
			var empty_lbl = Label.new()
			empty_lbl.text = "(vacío)"
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_font_override("font", FONT_BODY)
			empty_lbl.add_theme_font_size_override("font_size", 12)
			empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
			col.add_child(empty_lbl)
			continue
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		scroll.add_child(grid)
		for entry in side.data:
			var node: Node = _create_selectable_popup_card(entry.data, side.pid, entry.zone_type, grid)
			node.set_meta("source_zone_type", entry.zone_type)
			if filter.call(node):
				candidates.append(node)

	if show_select_all:
		var select_all_btn = Button.new()
		select_all_btn.text = "Seleccionar todo"
		select_all_btn.focus_mode = Control.FOCUS_NONE
		select_all_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		select_all_btn.add_theme_font_override("font", FONT_TITLE)
		select_all_btn.add_theme_font_size_override("font_size", 13)
		select_all_btn.pressed.connect(func(): _main._card_interaction.request_select_all())
		vbox.add_child(select_all_btn)

	var lock_key: Callable = (func(c: Node) -> Variant: return c.owner_id) if lock_to_one_side else Callable()
	var chosen: Array = await _main._card_interaction.await_multi_target(prompt, candidates, max_count, lock_key)

	if is_instance_valid(popup_canvas):
		popup_canvas.queue_free()

	var result: Array = []
	for node in chosen:
		if is_instance_valid(node):
			result.append({"data": node.card_data, "owner_id": node.owner_id, "zone_type": node.get_meta("source_zone_type", "cemetery")})
	return result


func _delegate_cemetery_picker_to_remote(prompt: String, filter: Callable, max_count: int, own_data: Array, opp_data: Array) -> Array:
	"""Contraparte en red de open_cemetery_target_picker() — ver el
	comentario ahí. El filtro espera un Node (lee .owner_id/.card_type/
	etc.), no un Dictionary, así que SÍ hace falta construir los Nodos
	temporales para evaluarlo correctamente — pero nunca se agregan al
	árbol real ni se muestran: se descartan apenas se junta la lista de
	candidatos que de verdad pasan el filtro. 'own_data'/'opp_data' ya
	vienen con pid 0/1 fijo (mismo criterio que el resto de la función);
	acá 'own' para el Remoto es pid 1, así que se etiqueta así en el
	payload que se manda."""
	var temp_container := Control.new()
	var sides := [{"pid": 0, "data": own_data}, {"pid": 1, "data": opp_data}]
	var candidates_payload: Array = []  # {data, owner_id, zone_type} — mismo shape que el resultado final
	for side in sides:
		for entry in side.data:
			var node: Node = _create_selectable_popup_card(entry.data, side.pid, entry.zone_type, temp_container)
			if filter.call(node):
				candidates_payload.append({"data": entry.data, "owner_id": side.pid, "zone_type": entry.zone_type})
	temp_container.queue_free()

	if candidates_payload.is_empty():
		return []

	var display_payload: Array = []
	for c in candidates_payload:
		var d: Dictionary = c.data
		display_payload.append({
			"nombre": str(d.get("nombre", d.get("name", "?"))),
			"coste": d.get("coste", d.get("cost", "?")),
			"zone_type": c.zone_type,
			"side": "own" if c.owner_id == 1 else "opponent",
		})

	NetworkClient.send_message({
		"op": "prompt", "kind": "select_cemetery_cards",
		"title": prompt,
		"candidates": display_payload,
		"max_selections": max_count,
	})
	var intent: Dictionary = await NetworkClient.await_intent(["select_cemetery_cards_choice"])
	var result: Array = []
	for pos in intent.get("indices", []):
		var p: int = int(pos)
		if p >= 0 and p < candidates_payload.size():
			result.append(candidates_payload[p])
	return result


func _create_selectable_popup_card(card_data: Dictionary, player_id: int, zone_type: String, container: Control) -> Node:
	"""Igual que _create_popup_card() pero interactiva (can_interact=true,
	conectada vía _main._connect_card_signals() como cualquier carta del
	campo) — usada por open_cemetery_target_picker() para que el mecanismo
	genérico de selección de objetivo (is_selecting_target/await_target())
	funcione igual sobre estos Nodos temporales."""
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(110.0, 154.0)
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var card = CardScene.instantiate()
	card.load_from_data(card_data)
	card.set_zone(Constants.Zone.CEMENTERIO if zone_type == "cemetery" else Constants.Zone.DESTIERRO)
	card.owner_id = player_id
	card.controller_id = player_id
	card.can_interact = true
	card.drag_enabled = false
	card.custom_minimum_size = Vector2(150.0, 210.0)
	card.size = Vector2(150.0, 210.0)
	card.scale = Vector2(0.733, 0.733)
	card.base_scale = Vector2(0.733, 0.733)
	card.position = Vector2.ZERO
	card.pivot_offset = Vector2.ZERO
	_main._connect_card_signals(card)

	wrapper.add_child(card)
	container.add_child(wrapper)
	return card


func open_reveal_picker(prompt: String, data_list: Array, owner_id: int, filter: Callable = Callable(), max_count: int = 1, cancellable: bool = true, chooser_id: int = -1) -> Array:
	"""Popup de una fila con cartas ya reveladas (Dictionaries sueltos de "Mira"/"Muestra" del tope) y
	click directo. Mismo mecanismo que open_cemetery_target_picker(), con un solo pool.
	'filter' (opcional): Callable(Node) -> bool sobre el Nodo temporal.
	'max_count' == 1 usa await_target(); >1 o -1 usa await_multi_target() (cancellable = false para
	forzar exactamente max_count).
	Devuelve un Array de card_data en orden de click (vacío si no había candidatos o se canceló)."""
	if data_list.is_empty():
		return []

	# Fase 3 del plan de paridad remota, mismo criterio que
	# open_cemetery_target_picker()/SelectionManager._delegate_selection_
	# to_remote() — default -1 usa 'owner_id' (todo llamador existente ya
	# pasa su propio controller_id ahí, así que ninguno necesita cambiar).
	var effective_chooser: int = chooser_id if chooser_id >= 0 else owner_id
	if effective_chooser == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		return await _delegate_reveal_picker_to_remote(prompt, data_list, filter, max_count)

	if not _main._card_interaction:
		return []

	var existing = _main.get_node_or_null("RevealPickerPopup")
	if existing:
		existing.queue_free()

	var vp = get_viewport().get_visible_rect().size
	var popup_canvas = CanvasLayer.new()
	popup_canvas.name = "RevealPickerPopup"
	popup_canvas.layer = 55
	_main.add_child(popup_canvas)

	var bg = ColorRect.new()
	bg.size = vp
	bg.color = Color(0.01, 0.01, 0.02, 0.78)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and _main._card_interaction.is_selecting_target:
			_main._card_interaction.cancel_target_selection()
	)
	popup_canvas.add_child(bg)

	var panel = Panel.new()
	panel.size = Vector2(minf(vp.x * 0.92, 960.0), 300.0)
	panel.position = (vp - panel.size) / 2.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.03, 0.06, 0.98)
	pstyle.border_color = Color(0.85, 0.72, 0.28, 0.95)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(18)
	pstyle.shadow_color = Color(0, 0, 0, 0.90)
	pstyle.shadow_size = 30
	panel.add_theme_stylebox_override("panel", pstyle)
	popup_canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var prompt_lbl = Label.new()
	prompt_lbl.text = prompt
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_font_override("font", FONT_TITLE)
	prompt_lbl.add_theme_font_size_override("font_size", 15)
	prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60, 1.0))
	vbox.add_child(prompt_lbl)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hbox)

	var candidates: Array = []
	for data in data_list:
		var card = CardScene.instantiate()
		card.load_from_data(data)
		card.set_zone(Constants.Zone.CASTILLO)
		card.owner_id = owner_id
		card.controller_id = owner_id
		card.can_interact = true
		card.drag_enabled = false
		card.custom_minimum_size = Vector2(150.0, 210.0)
		card.size = Vector2(150.0, 210.0)
		card.pivot_offset = Vector2.ZERO
		_main._connect_card_signals(card)
		var wrapper = Control.new()
		wrapper.custom_minimum_size = Vector2(150.0, 210.0)
		wrapper.add_child(card)
		hbox.add_child(wrapper)
		var is_eligible: bool = not filter.is_valid() or filter.call(card)
		if is_eligible:
			candidates.append(card)
		else:
			# Las cartas que el filtro excluye se ven atenuadas y con can_interact = false (sin hover ni
			# cursor de mano), para que se note cuáles no se pueden elegir (p.ej. Oros o coste 3+ con Tangata
			# Manu).
			card.can_interact = false
			card.modulate = Color(0.5, 0.5, 0.5, 0.7)

	var chosen: Array = []
	if max_count == 1:
		var node_filter := func(c: Node) -> bool: return c in candidates
		var picked_node: Node = await _main._card_interaction.await_target(prompt, node_filter, cancellable)
		if picked_node and is_instance_valid(picked_node):
			chosen = [picked_node]
	else:
		chosen = await _main._card_interaction.await_multi_target(prompt, candidates, max_count, Callable(), Callable(), cancellable)

	if is_instance_valid(popup_canvas):
		popup_canvas.queue_free()

	var result: Array = []
	for node in chosen:
		if is_instance_valid(node):
			result.append(node.card_data)
	return result


func _delegate_reveal_picker_to_remote(prompt: String, data_list: Array, filter: Callable, max_count: int) -> Array:
	"""Contraparte en red de open_reveal_picker() — mismo criterio que
	_delegate_cemetery_picker_to_remote() (hace falta un Node temporal
	para evaluar 'filter', nunca se agrega al árbol real ni se muestra).
	Reusa el mismo prompt/intent 'select_cemetery_cards' del lado del
	Remoto — el payload no necesita 'zone_type'/'side' acá (un solo pool,
	sin lado rival), RemoteMirrorController los trata como opcionales."""
	var temp_container := Control.new()
	var candidates_data: Array = []
	for data in data_list:
		var card = CardScene.instantiate()
		card.load_from_data(data)
		card.set_zone(Constants.Zone.CASTILLO)
		temp_container.add_child(card)
		if not filter.is_valid() or filter.call(card):
			candidates_data.append(data)
	temp_container.queue_free()

	if candidates_data.is_empty():
		return []

	var display_payload: Array = []
	for d in candidates_data:
		display_payload.append({
			"nombre": str(d.get("nombre", d.get("name", "?"))),
			"coste": d.get("coste", d.get("cost", "?")),
		})

	NetworkClient.send_message({
		"op": "prompt", "kind": "select_cemetery_cards",
		"title": prompt,
		"candidates": display_payload,
		"max_selections": max_count,
	})
	var intent: Dictionary = await NetworkClient.await_intent(["select_cemetery_cards_choice"])
	var result2: Array = []
	for pos in intent.get("indices", []):
		var p: int = int(pos)
		if p >= 0 and p < candidates_data.size():
			result2.append(candidates_data[p])
	return result2


func _on_zone_cemetery_changed(player_id: int, _count: int) -> void:
	var panel = _main._panel_player_cem if player_id == 0 else _main._panel_opp_cem
	_refresh_zone_top_card(panel, CardManager.get_cemetery(player_id))


func _on_zone_exile_changed(player_id: int, _count: int) -> void:
	var panel = _main._panel_player_dst if player_id == 0 else _main._panel_opp_dst
	_refresh_zone_top_card(panel, CardManager.get_exile(player_id))


func _on_zone_card_image_loaded(_card_id: String, _texture: Texture2D) -> void:
	_refresh_zone_top_card(_main._panel_player_cem, CardManager.get_cemetery(0))
	_refresh_zone_top_card(_main._panel_player_dst, CardManager.get_exile(0))
	_refresh_zone_top_card(_main._panel_opp_cem,    CardManager.get_cemetery(1))
	_refresh_zone_top_card(_main._panel_opp_dst,    CardManager.get_exile(1))
	refresh_castillo_top_reveal()


func _refresh_zone_top_card(panel: Panel, cards_data: Array) -> void:
	var tr: TextureRect = panel.find_child("TopCardPreview", true, false) as TextureRect
	var underlay1: CanvasItem = panel.find_child("StackUnderlay1", true, false) as CanvasItem
	var underlay2: CanvasItem = panel.find_child("StackUnderlay2", true, false) as CanvasItem
	var badge: Control = panel.find_child("CountBadge", true, false) as Control

	if not tr:
		return

	if badge:
		var tw_b = badge.create_tween()
		tw_b.tween_property(badge, "scale", Vector2(1.22, 1.22), 0.08).set_ease(Tween.EASE_OUT)
		tw_b.tween_property(badge, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_IN)

	var n_cards: int = cards_data.size()
	if n_cards == 0:
		tr.texture = null
		tr.visible = false
		if underlay1:
			underlay1.visible = false
		if underlay2:
			underlay2.visible = false
		return

	tr.visible = true
	if underlay1:
		underlay1.visible = (n_cards >= 2)
	if underlay2:
		underlay2.visible = (n_cards >= 5)

	var top_card = cards_data.back()
	var card_id = str(top_card.get("id", ""))

	if not card_id.is_empty():
		var tex = CardDatabase.image_cache.get(card_id)
		if tex:
			tr.texture = tex
			return

	# Fallback: mostrar dorso mientras la imagen no está lista
	tr.texture = GameSettings.get_card_back_texture(0)


func _on_priority_changed_refresh_castillo_top(_player_id: int) -> void:
	refresh_castillo_top_reveal()


func _on_deck_count_changed_refresh_castillo_top(_player_id: int, _new_count: int) -> void:
	refresh_castillo_top_reveal()


func _refresh_castillo_clickable() -> void:
	"""Escritura Sagrada: tu Castillo se puede tocar mientras dure su efecto.
	No toca nada mientras se está eligiendo un Castillo para otro efecto
	(SelectionDialogs guarda y restaura el mouse_filter por su cuenta)."""
	var panel: Control = _main._panel_player_castillo
	if SelectionManager._dialogs.get("_castillo_pick_active"):
		return
	if not panel.has_meta("base_mouse_filter"):
		panel.set_meta("base_mouse_filter", panel.mouse_filter)
		panel.set_meta("base_cursor", panel.mouse_default_cursor_shape)
	if CastleTopPlay.escritura_active(0):
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		panel.mouse_filter = panel.get_meta("base_mouse_filter")
		panel.mouse_default_cursor_shape = panel.get_meta("base_cursor")


func refresh_castillo_top_reveal() -> void:
	"""Muestra la carta del tope del Castillo propio (índice 0, ver CardManager.add_to_deck_top()) en
	vez del dorso, mientras haya en la Reserva una carta propia con "Juega mostrando la primera
	carta de tu Castillo" (La Ouija). Llamar tras cualquier cambio al Castillo y cuando una carta
	puede haber salido de la Reserva. Solo jugador 0."""
	if not _main or not _main._panel_player_castillo:
		return
	var tr: TextureRect = _main._panel_player_castillo.get_node_or_null("TopCardPreview")
	var dorso = _main._panel_player_castillo.get_node_or_null("DorsoImage")
	if not tr:
		return
	_refresh_castillo_clickable()

	var revealed: bool = false
	if _main.player_gold:
		for c in _main.player_gold.get_children():
			if not is_instance_valid(c):
				continue
			var ability_text: String = c.get("card_ability") if c.get("card_ability") != null else ""
			if ability_text.is_empty():
				continue
			if "juega mostrando la primera carta de tu castillo" in ability_text.to_lower():
				revealed = true
				break

	if not revealed or _main.player_deck.is_empty():
		tr.visible = false
		if dorso:
			dorso.visible = true
		return

	var top_card: Dictionary = _main.player_deck[0]
	var card_id := str(top_card.get("id", ""))
	var tex = CardDatabase.image_cache.get(card_id) if not card_id.is_empty() else null
	if not tex:
		tr.visible = false
		if dorso:
			dorso.visible = true
		return

	tr.texture = tex
	tr.visible = true
	if dorso:
		dorso.visible = false
