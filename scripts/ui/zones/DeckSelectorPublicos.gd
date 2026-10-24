extends "res://scripts/ui/zones/DeckSelectorBase.gd"
## DeckSelectorPublicos — familia Publicos de DeckSelector.gd (ver DeckSelectorBase.gd).


func _populate_options() -> void:
	_mazos_load_resolved = true
	_selected_player_idx = -1
	_player_cards.clear()

	for child in _player_row.get_children():
		_player_row.remove_child(child)
		child.queue_free()

	# Mazos "míos" (privados de ShadowForge y presets) primero y públicos después, con un separador
	# visual. El orden ya viene así de _on_external_decks_received() → _fetch_and_merge_public_decks();
	# aquí se detecta la transición por "_shadowforge_kind". El separador es un Control aparte, fuera
	# de _player_cards, así que los índices de selección no se desalinean.
	var divider_shown := false
	var any_mine := false
	for i in range(_mazos.size()):
		var mazo: Dictionary = _mazos[i]
		var is_public: bool = str(mazo.get("_shadowforge_kind", "")) == "public"
		if not is_public:
			any_mine = true
		if is_public and any_mine and not divider_shown:
			_player_row.add_child(_build_section_divider("MAZOS PÚBLICOS\nDE SHADOWFORGE"))
			divider_shown = true
		var p_card := _build_deck_card(mazo, i)
		_player_row.add_child(p_card)
		_player_cards.append(p_card)

	# Mostrar flechas circulares si hay más de 6 elementos en el carrusel
	var has_overflow = _player_cards.size() > 6 or _player_row.get_child_count() > 6
	if _btn_prev: _btn_prev.visible = has_overflow
	if _btn_next: _btn_next.visible = has_overflow

	# Auto-seleccionar el primer mazo por defecto
	if _mazos.size() > 0:
		_selected_player_idx = 0
		_refresh_selection(_player_cards, _selected_player_idx)
		_update_confirm_button()

	if _parchment_label:
		_parchment_label.text = "%d MAZOS DISPONIBLES" % _mazos.size()

	print("[DeckSelector] %d grimorios dispuestos sobre el altar." % _mazos.size())


func _build_section_divider(label_text: String) -> Control:
	"""Separador visual entre los mazos "míos" (privados de ShadowForge + presets) y los públicos,
	dentro del mismo carrusel. Un Control angosto, no un mazo: no está en _player_cards ni
	participa de la selección."""
	var holder := Control.new()
	holder.name = "SectionDivider"
	holder.custom_minimum_size = Vector2(46, CARD_SIZE.y)
	holder.size_flags_vertical = Control.SIZE_SHRINK_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true

	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	line.set_anchor(SIDE_LEFT, 0.5)
	line.set_anchor(SIDE_RIGHT, 0.5)
	line.set_anchor(SIDE_TOP, 0.0)
	line.set_anchor(SIDE_BOTTOM, 1.0)
	line.offset_left = -1
	line.offset_right = 1
	line.offset_top = 10
	line.offset_bottom = -10
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)

	var bg_pill := ColorRect.new()
	bg_pill.color = Color(0.08, 0.06, 0.04, 0.85)
	bg_pill.set_anchor(SIDE_LEFT, 0.5)
	bg_pill.set_anchor(SIDE_RIGHT, 0.5)
	bg_pill.set_anchor(SIDE_TOP, 0.5)
	bg_pill.set_anchor(SIDE_BOTTOM, 0.5)
	bg_pill.offset_left = -15
	bg_pill.offset_right = 15
	bg_pill.offset_top = -90
	bg_pill.offset_bottom = 90
	bg_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg_pill)

	var lbl_w := 170.0
	var lbl_h := 28.0
	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(lbl_w, lbl_h)
	lbl.size = Vector2(lbl_w, lbl_h)
	lbl.pivot_offset = Vector2(lbl_w / 2.0, lbl_h / 2.0)
	lbl.position = Vector2((46.0 - lbl_w) / 2.0, (CARD_SIZE.y - lbl_h) / 2.0)
	lbl.rotation_degrees = -90.0
	lbl.add_theme_font_override("font", FONT_TITLE)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", GOLD)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lbl)

	return holder


func _build_deck_card(mazo: Dictionary, idx: int) -> Control:
	var card = Control.new()
	card.name = "Grimoire_%d" % idx
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_vertical = Control.SIZE_SHRINK_END

	# Sombra de contacto profunda en la roca (permanece sobre la piedra cuando el tomo se eleva)
	var ground_shadow = Panel.new()
	ground_shadow.name = "GroundShadow"
	ground_shadow.set_anchor(SIDE_LEFT, 0.0)
	ground_shadow.set_anchor(SIDE_RIGHT, 1.0)
	ground_shadow.set_anchor(SIDE_TOP, 1.0)
	ground_shadow.set_anchor(SIDE_BOTTOM, 1.0)
	ground_shadow.offset_left = 6
	ground_shadow.offset_right = -6
	ground_shadow.offset_top = -18
	ground_shadow.offset_bottom = 14
	ground_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_flat = StyleBoxFlat.new()
	shadow_flat.bg_color = Color(0, 0, 0, 0.75)
	shadow_flat.set_corner_radius_all(12)
	shadow_flat.shadow_color = Color(0, 0, 0, 0.90)
	shadow_flat.shadow_size = 14
	ground_shadow.add_theme_stylebox_override("panel", shadow_flat)
	card.add_child(ground_shadow)

	# visual_box aloja el libro físico encuadernado y permite la elevación mágica independiente
	var visual_box = Control.new()
	visual_box.name = "VisualBox"
	visual_box.custom_minimum_size = CARD_SIZE
	visual_box.size = CARD_SIZE
	visual_box.pivot_offset = CARD_SIZE / 2.0
	visual_box.modulate = Color(1.10, 1.07, 1.02)
	card.add_child(visual_box)

	# 1. Base del Tomo: Encuadernación de Cuero Repujado con esquinas redondeadas
	var tome_base = PanelContainer.new()
	tome_base.name = "TomeLeatherBase"
	tome_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tome_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tome_style = StyleBoxFlat.new()
	tome_style.bg_color = Color(0.20, 0.14, 0.08, 1.0)
	tome_style.border_width_left = 3
	tome_style.border_width_top = 3
	tome_style.border_width_right = 3
	tome_style.border_width_bottom = 3
	tome_style.border_color = Color(0.58, 0.40, 0.22, 0.95)
	tome_style.set_corner_radius_all(12)
	tome_style.shadow_color = Color(0, 0, 0, 0.55)
	tome_style.shadow_size = 6
	tome_base.add_theme_stylebox_override("panel", tome_style)
	visual_box.add_child(tome_base)

	# Textura de piel/cuero del tomo
	var leather_tex = TextureRect.new()
	leather_tex.name = "LeatherTexture"
	leather_tex.texture = TEX_LEATHER
	leather_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	leather_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	leather_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	leather_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tome_base.add_child(leather_tex)

	# 2. Inlay / Grabado Interior (Ventana biselada que aloja la ilustración de la raza)
	var inlay_holder = Control.new()
	inlay_holder.name = "InlayHolder"
	inlay_holder.set_anchor(SIDE_LEFT, 0.0)
	inlay_holder.set_anchor(SIDE_RIGHT, 1.0)
	inlay_holder.set_anchor(SIDE_TOP, 0.0)
	inlay_holder.set_anchor(SIDE_BOTTOM, 1.0)
	inlay_holder.offset_left = 13
	inlay_holder.offset_right = -13
	inlay_holder.offset_top = 15
	inlay_holder.offset_bottom = -15
	inlay_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_box.add_child(inlay_holder)

	var inlay_frame = PanelContainer.new()
	inlay_frame.name = "InlayFrame"
	inlay_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inlay_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inlay_style = StyleBoxFlat.new()
	inlay_style.bg_color = Color(0.16, 0.11, 0.07, 0.9)
	inlay_style.border_width_left = 2
	inlay_style.border_width_top = 2
	inlay_style.border_width_right = 2
	inlay_style.border_width_bottom = 2
	inlay_style.border_color = Color(0.32, 0.22, 0.12, 0.95)
	inlay_style.set_corner_radius_all(7)
	inlay_style.shadow_color = Color(0, 0, 0, 0.6)
	inlay_style.shadow_size = 4
	inlay_frame.add_theme_stylebox_override("panel", inlay_style)
	inlay_holder.add_child(inlay_frame)

	var raw_nombre = str(mazo.get("nombre", mazo.get("name", "Mazo")))
	var nombre_clean = _sanitize_utf8(raw_nombre)
	var race_name := _extract_race_or_archetype(mazo)
	var card_texture: Texture2D = _get_card_texture(race_name, nombre_clean, idx)

	var tex_rect = TextureRect.new()
	tex_rect.name = "DeckCoverInlay"
	tex_rect.texture = card_texture
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inlay_frame.add_child(tex_rect)

	# ("que los mazos muestren la imagen como de portada"): para mazos de ShadowForge con "image_url"
	# real (privados y públicos, ver arquitectura.md §13), se reemplaza la ilustración genérica de raza
	# por la portada real del mazo en cuanto termina de bajar — mismo mecanismo ya usado en
	# DeckManager.gd (_load_cover_image), sin duplicar: la genérica queda de placeholder mientras
	# carga, no hay hueco en blanco.
	var cover_url := str(mazo.get("image_url", ""))
	if not cover_url.is_empty():
		_load_deck_cover_image(tex_rect, cover_url)

	# 3. Remaches / Tachas Metálicas en las 4 esquinas del tomo
	var studs = StudsDrawer.new()
	studs.name = "CornerStuds"
	studs.card_size = CARD_SIZE
	studs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual_box.add_child(studs)

	# 4. Marco de Selección Dorado Cálido
	var glow_panel = PanelContainer.new()
	glow_panel.name = "SelectionGlow"
	glow_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.border_color = Color(0, 0, 0, 0)
	glow_style.set_border_width_all(0)
	glow_style.set_corner_radius_all(12)
	glow_style.shadow_color = Color(0, 0, 0, 0)
	glow_style.shadow_size = 0
	glow_panel.add_theme_stylebox_override("panel", glow_style)
	visual_box.add_child(glow_panel)

	# 5. Botón invisible de interacción táctil
	var button = Button.new()
	button.flat = true
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_card_pressed.bind(idx))
	visual_box.add_child(button)

	card.set_meta("visual_box", visual_box)
	card.set_meta("glow_style", glow_style)

	button.mouse_entered.connect(func():
		if _selected_player_idx != idx:
			var tw = visual_box.create_tween()
			tw.set_parallel(true)
			tw.tween_property(visual_box, "modulate", Color(1.26, 1.22, 1.15), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "scale", Vector2(1.012, 1.012), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "position:y", -2.5, 0.12).set_ease(Tween.EASE_OUT)
	)
	button.mouse_exited.connect(func():
		if _selected_player_idx != idx:
			var tw = visual_box.create_tween()
			tw.set_parallel(true)
			tw.tween_property(visual_box, "modulate", Color(1.10, 1.07, 1.02), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "position:y", 0.0, 0.12).set_ease(Tween.EASE_OUT)
	)

	return card


func _load_deck_cover_image(tex_rect: TextureRect, url: String) -> void:
	"""Baja la portada real de un mazo de ShadowForge y reemplaza la ilustración genérica de raza al
	terminar. En cola con tope MAX_CONCURRENT_COVER_DOWNLOADS: con ~20 mazos públicos, 20
	HTTPRequest simultáneos a Cloudinary parecían saturar las conexiones y dejar sin respuesta el
	pedido de /decks/my/{id}/ al confirmar."""
	_cover_image_queue.append({"tex_rect": tex_rect, "url": url})
	_process_cover_image_queue()


func _process_cover_image_queue() -> void:
	while _cover_images_in_flight < MAX_CONCURRENT_COVER_DOWNLOADS and not _cover_image_queue.is_empty():
		var item: Dictionary = _cover_image_queue.pop_front()
		var tex_rect: TextureRect = item.get("tex_rect")
		var url: String = item.get("url", "")
		if not is_instance_valid(tex_rect):
			continue  # el carrusel se repobló antes de que le tocara el turno
		_cover_images_in_flight += 1
		var http := HTTPRequest.new()
		add_child(http)
		_cover_image_active_requests.append(http)
		http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			_cover_image_active_requests.erase(http)
			http.queue_free()
			_cover_images_in_flight -= 1
			_process_cover_image_queue()
			if not is_instance_valid(tex_rect):
				return
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var image: Image = CardDatabase.decode_image_buffer(body)
			if image == null:
				return
			tex_rect.texture = ImageTexture.create_from_image(image)
		)
		var request_err := http.request(url)
		if request_err != OK:
			_cover_image_active_requests.erase(http)
			http.queue_free()
			_cover_images_in_flight -= 1
			_process_cover_image_queue()


func _get_card_texture(race: String, deck_name: String, idx: int) -> Texture2D:
	var r := (race + " " + deck_name).to_lower()
	if "caballero" in r or "paladin" in r or "paladín" in r:
		return TEX_CABALLERO
	elif "bestia" in r or "lobo" in r:
		return TEX_BESTIA
	elif "dragon" in r or "dragón" in r:
		return TEX_DRAGON
	elif "imp" in r or "demonio" in r:
		return TEX_IMP
	elif "heroe" in r or "héroe" in r or "defensor" in r:
		return TEX_HEROE
	elif "guerrero" in r or "barbaro" in r or "bárbaro" in r:
		return TEX_GUERRERO
	elif "faerie" in r or "hada" in r or "mago" in r:
		return TEX_FAERIE
	elif "sacerdote" in r or "santo" in r or "luz" in r:
		return TEX_SACERDOTE
	elif "sombra" in r or "undead" in r or "no-muerto" in r:
		return TEX_SOMBRA

	var all_textures := [
		TEX_CABALLERO, TEX_BESTIA, TEX_DRAGON, TEX_IMP,
		TEX_HEROE, TEX_GUERRERO, TEX_FAERIE, TEX_SACERDOTE, TEX_SOMBRA
	]
	return all_textures[idx % all_textures.size()]


func _extract_race_or_archetype(mazo: Dictionary) -> String:
	var val: String = str(mazo.get("raza", mazo.get("race", mazo.get("arquetipo", mazo.get("archetype", "")))))
	val = _sanitize_utf8(val)
	if val.is_empty():
		var nombre_lower := _sanitize_utf8(str(mazo.get("nombre", mazo.get("name", "")))).to_lower()
		for r in ["caballero", "bestia", "dragon", "dragón", "sombra", "faerie", "sacerdote", "eterno", "heroe", "héroe", "guerrero", "imp"]:
			if r in nombre_lower:
				return r
	return val


func _sanitize_utf8(text: String) -> String:
	var s = text
	s = s.replace("Ã¡", "á").replace("Ã©", "é").replace("Ã­", "í").replace("Ã³", "ó").replace("Ãº", "ú")
	s = s.replace("Ã±", "ñ").replace("Ã", "Á").replace("Ã‰", "É").replace("Ã", "Í").replace("Ã“", "Ó").replace("Ãš", "Ú").replace("Ã‘", "Ñ")
	s = s.replace("DragÃ³n", "Dragón").replace("DragÃ¡", "Dragá")
	return s


func _on_card_pressed(idx: int) -> void:
	_selected_player_idx = idx
	_refresh_selection(_player_cards, idx)
	_update_confirm_button()

	# Desplazar suavemente solo si el grimorio seleccionado está fuera del área visible
	if _scroll_container and idx >= 0 and idx < _player_cards.size():
		var card_node = _player_cards[idx]
		var card_left: float = card_node.position.x + 16.0
		var card_right: float = card_left + card_node.size.x
		var current_scroll: float = float(_scroll_container.scroll_horizontal)
		var view_w: float = _scroll_container.size.x if _scroll_container.size.x > 0 else 1308.0

		var desired_scroll: int = -1
		if card_left < current_scroll + 16.0:
			desired_scroll = max(0, int(card_node.position.x))
		elif card_right > current_scroll + view_w - 16.0:
			desired_scroll = max(0, int(card_node.position.x + 16.0 + card_node.size.x + 16.0 - view_w))

		if desired_scroll >= 0 and desired_scroll != int(current_scroll):
			var tw = create_tween()
			tw.tween_property(_scroll_container, "scroll_horizontal", desired_scroll, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _update_confirm_button() -> void:
	var can_confirm := (_selected_player_idx >= 0 and _selected_player_idx < _mazos.size())
	if _btn_confirm:
		_btn_confirm.modulate = Color(1.0, 1.0, 1.0, 1.0) if can_confirm else Color(0.65, 0.65, 0.65, 0.8)


func _refresh_selection(cards: Array, selected_idx: int) -> void:
	for i in range(cards.size()):
		var card: Control = cards[i]
		var visual_box: Control = card.get_meta("visual_box")
		var glow_style: StyleBoxFlat = card.get_meta("glow_style")
		var is_sel: bool = (i == selected_idx)

		var tw = visual_box.create_tween()
		tw.set_parallel(true)

		if is_sel:
			# Tomo seleccionado: iluminación cálida integrada al altar y sutil aura dorada
			glow_style.border_color = Color(0.85, 0.72, 0.35, 0.60)
			glow_style.set_border_width_all(2)
			glow_style.shadow_color = Color(0.92, 0.78, 0.38, 0.40)
			glow_style.shadow_size = 10
			card.z_index = 10
			tw.tween_property(visual_box, "modulate", Color(1.45, 1.36, 1.22), 0.16).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "scale", Vector2(1.025, 1.025), 0.16).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "position:y", -6.0, 0.16).set_ease(Tween.EASE_OUT)
		else:
			# Tomo en reposo sobre la roca del altar
			glow_style.border_color = Color(0, 0, 0, 0)
			glow_style.set_border_width_all(0)
			glow_style.shadow_color = Color(0, 0, 0, 0)
			glow_style.shadow_size = 0
			card.z_index = 0
			tw.tween_property(visual_box, "modulate", Color(1.10, 1.07, 1.02), 0.16).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "scale", Vector2(1.0, 1.0), 0.16).set_ease(Tween.EASE_OUT)
			tw.tween_property(visual_box, "position:y", 0.0, 0.16).set_ease(Tween.EASE_OUT)

	# Actualizar el cartel central de mazo seleccionado
	if selected_idx >= 0 and selected_idx < _mazos.size():
		var mazo: Dictionary = _mazos[selected_idx]
		var nombre_clean = _sanitize_utf8(str(mazo.get("nombre", mazo.get("name", "Mazo"))))
		var is_preset: bool = str(mazo.get("slug", "")).begins_with("preset-")
		var is_public: bool = mazo.get("_shadowforge_kind", "") == "public" or nombre_clean.to_lower().contains("(publico)") or nombre_clean.to_lower().contains("(público)")

		# Título limpio en mayúsculas sin paréntesis redundantes
		var title_text := nombre_clean.to_upper()
		title_text = title_text.replacen("(PUBLICO)", "").replacen("(PÚBLICO)", "").strip_edges()

		# Formato estilizado
		var fmt_str := str(mazo.get("formato", mazo.get("format", "Imperio"))).strip_edges().to_lower()
		var fmt_display := "IMPERIO"
		match fmt_str:
			"imp", "imperio":
				fmt_display = "IMPERIO"
			"pb", "primer bloque", "primer_bloque":
				fmt_display = "PRIMER BLOQUE"
			"fur", "furia":
				fmt_display = "FURIA"
			"cronicas", "crónicas":
				fmt_display = "CRÓNICAS"
			"libre":
				fmt_display = "LIBRE"
			_:
				fmt_display = fmt_str.to_upper() if not fmt_str.is_empty() else "ESTÁNDAR"

		# Conteo de cartas exacto considerando 'entries', 'cartas' y 'cards'
		var cant_cartas := 0
		if mazo.has("entries") and mazo["entries"] is Array:
			for e in mazo["entries"]:
				cant_cartas += int(e.get("quantity", 1))
		elif mazo.has("cartas") and mazo["cartas"] is Array:
			cant_cartas = mazo["cartas"].size()
		elif mazo.has("cards") and mazo["cards"] is Array:
			cant_cartas = mazo["cards"].size()

		# Raza / Arquetipo
		var raza := str(mazo.get("arquetipo", mazo.get("raza", mazo.get("race", "")))).strip_edges().to_upper()

		# Fila secundaria con glifos rúnicos
		var sub_parts: Array[String] = []
		sub_parts.append("FORMATO: %s" % fmt_display)
		if cant_cartas > 0:
			sub_parts.append("%d CARTAS" % cant_cartas)
		if not raza.is_empty() and raza != "GENERIC" and raza != "GENÉRICO":
			sub_parts.append("RAZA: %s" % raza)
		if is_public:
			sub_parts.append("PÚBLICO")
		elif is_preset:
			sub_parts.append("OFICIAL")

		if _deck_banner:
			_deck_banner.text = title_text
		if _deck_sub_banner:
			_deck_sub_banner.text = "   ✦   ".join(sub_parts)

		if _deck_banner and _deck_banner.get_parent() and _deck_banner.get_parent().get_parent():
			var plate_node = _deck_banner.get_parent().get_parent()
			if is_instance_valid(plate_node):
				var tw_plate = plate_node.create_tween()
				tw_plate.tween_property(plate_node, "modulate:a", 1.0, 0.12).from(0.75)

# =============================================================================
# MAZOS PÚBLICOS DE SHADOWFORGE
# =============================================================================


func _open_public_deck_browser() -> void:
	if _public_browser_overlay and is_instance_valid(_public_browser_overlay):
		_public_browser_overlay.queue_free()

	if not _public_signals_connected:
		_public_signals_connected = true
		ExternalApiClient.public_decks_received.connect(_on_public_decks_received)
		ExternalApiClient.public_decks_failed.connect(_on_public_decks_failed)
		ExternalApiClient.public_deck_detail_received.connect(_on_public_deck_detail_received)
		ExternalApiClient.public_deck_detail_failed.connect(_on_public_deck_detail_failed)


func _disconnect_public_browser_signals() -> void:
	# El popup de búsqueda deja estas conexiones permanentes mientras está
	# abierto; si quedan conectadas después de cerrarlo, colisionan con los
	# listeners CONNECT_ONE_SHOT que usan _fetch_and_merge_public_decks() y
	# _resolve_deck_entries() sobre las MISMAS señales (ver hallazgo de
	# revisión: ambos handlers podían dispararse con una sola respuesta).
	if not _public_signals_connected:
		return
	_public_signals_connected = false
	if ExternalApiClient.public_decks_received.is_connected(_on_public_decks_received):
		ExternalApiClient.public_decks_received.disconnect(_on_public_decks_received)
	if ExternalApiClient.public_decks_failed.is_connected(_on_public_decks_failed):
		ExternalApiClient.public_decks_failed.disconnect(_on_public_decks_failed)
	if ExternalApiClient.public_deck_detail_received.is_connected(_on_public_deck_detail_received):
		ExternalApiClient.public_deck_detail_received.disconnect(_on_public_deck_detail_received)
	if ExternalApiClient.public_deck_detail_failed.is_connected(_on_public_deck_detail_failed):
		ExternalApiClient.public_deck_detail_failed.disconnect(_on_public_deck_detail_failed)

	_public_browser_overlay = Control.new()
	_public_browser_overlay.name = "PublicDeckBrowser"
	_public_browser_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_public_browser_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_public_browser_overlay)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_public_browser_overlay.add_child(dim)

	var panel = PanelContainer.new()
	panel.set_anchor(SIDE_LEFT, 0.5)
	panel.set_anchor(SIDE_RIGHT, 0.5)
	panel.set_anchor(SIDE_TOP, 0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.set_offset(SIDE_LEFT, -320)
	panel.set_offset(SIDE_RIGHT, 320)
	panel.set_offset(SIDE_TOP, -260)
	panel.set_offset(SIDE_BOTTOM, 260)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.10, 0.97)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = GOLD
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	_public_browser_overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Mazos públicos de ShadowForge"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GOLD)
	vbox.add_child(title)

	var search_row = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	vbox.add_child(search_row)

	_public_search_edit = LineEdit.new()
	_public_search_edit.placeholder_text = "Buscar por nombre..."
	_public_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_public_search_edit.add_theme_font_override("font", FONT_MEDIEVAL)
	_public_search_edit.add_theme_font_size_override("font_size", 14)
	_public_search_edit.text_submitted.connect(func(_t): _search_public_decks(1))
	search_row.add_child(_public_search_edit)

	var search_btn = Button.new()
	search_btn.text = "Buscar"
	search_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	search_btn.add_theme_font_override("font", FONT_TITLE)
	search_btn.add_theme_font_size_override("font_size", 13)
	search_btn.pressed.connect(func(): _search_public_decks(1))
	search_row.add_child(search_btn)

	_public_status_label = Label.new()
	_public_status_label.text = "Buscando mazos públicos..."
	_public_status_label.add_theme_font_override("font", FONT_MEDIEVAL)
	_public_status_label.add_theme_font_size_override("font_size", 13)
	_public_status_label.add_theme_color_override("font_color", RUNIC_CYAN)
	_public_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_public_status_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_public_results_box = VBoxContainer.new()
	_public_results_box.add_theme_constant_override("separation", 4)
	_public_results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_public_results_box)

	var page_row = HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	page_row.add_theme_constant_override("separation", 14)
	vbox.add_child(page_row)

	var prev_btn = Button.new()
	prev_btn.text = "◄ Anterior"
	prev_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	prev_btn.add_theme_font_override("font", FONT_TITLE)
	prev_btn.add_theme_font_size_override("font_size", 13)
	prev_btn.pressed.connect(func():
		if _public_page > 1:
			_search_public_decks(_public_page - 1)
	)
	page_row.add_child(prev_btn)

	_public_page_label = Label.new()
	_public_page_label.text = "Página 1"
	_public_page_label.add_theme_font_override("font", FONT_TITLE)
	_public_page_label.add_theme_font_size_override("font_size", 13)
	page_row.add_child(_public_page_label)

	var next_btn = Button.new()
	next_btn.text = "Siguiente ►"
	next_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	next_btn.add_theme_font_override("font", FONT_TITLE)
	next_btn.add_theme_font_size_override("font_size", 13)
	next_btn.pressed.connect(func(): _search_public_decks(_public_page + 1))
	page_row.add_child(next_btn)

	var close_btn = Button.new()
	close_btn.text = "Cerrar"
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_font_override("font", FONT_TITLE)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func():
		if _public_browser_overlay and is_instance_valid(_public_browser_overlay):
			_public_browser_overlay.queue_free()
			_public_browser_overlay = null
		_disconnect_public_browser_signals()
	)
	vbox.add_child(close_btn)

	_search_public_decks(1)


func _search_public_decks(page: int) -> void:
	_public_page = page
	if _public_status_label:
		_public_status_label.text = "Buscando..."
	if _public_results_box:
		for child in _public_results_box.get_children():
			child.queue_free()
	var search := _public_search_edit.text.strip_edges() if _public_search_edit else ""
	ExternalApiClient.fetch_public_decks(search, page)


func _on_public_decks_received(results: Array, count: int) -> void:
	if not _public_browser_overlay or not is_instance_valid(_public_browser_overlay):
		return  # el popup se cerró mientras la petición estaba en vuelo
	_public_total = count
	if _public_page_label:
		var total_pages: int = max(1, ceili(float(count) / 20.0))
		_public_page_label.text = "Página %d de %d" % [_public_page, total_pages]
	if _public_status_label:
		_public_status_label.text = "%d mazos públicos encontrados." % count if count > 0 else "Sin resultados."
	if not _public_results_box:
		return
	for child in _public_results_box.get_children():
		child.queue_free()
	for deck in results:
		if not deck is Dictionary:
			continue
		_public_results_box.add_child(_build_public_deck_row(deck))


func _build_public_deck_row(deck: Dictionary) -> Control:
	var row_btn = Button.new()
	row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row_btn.add_theme_font_override("font", FONT_MEDIEVAL)
	row_btn.add_theme_font_size_override("font_size", 14)
	var nombre := str(deck.get("name", "Mazo sin nombre"))
	var raza := str(deck.get("race", ""))
	var owner := str(deck.get("owner_username", "?"))
	var card_count := int(deck.get("card_count", 0))
	row_btn.text = "%s — %s — por %s (%d cartas)" % [nombre, raza.capitalize(), owner, card_count]
	row_btn.pressed.connect(func(): _import_public_deck(deck))
	return row_btn


func _on_public_decks_failed(reason: String) -> void:
	if _public_status_label and is_instance_valid(_public_status_label):
		_public_status_label.text = "No se pudieron buscar mazos públicos: %s" % reason


func _import_public_deck(deck: Dictionary) -> void:
	var deck_id := int(deck.get("id", -1))
	if deck_id < 0:
		return
	if _public_status_label and is_instance_valid(_public_status_label):
		_public_status_label.text = "Cargando '%s'..." % str(deck.get("name", ""))
	ExternalApiClient.fetch_public_deck_entries(deck_id)


func _on_public_deck_detail_received(deck_data: Dictionary) -> void:
	# deck_data ya trae "entries" (ver ExternalApiClient.fetch_public_deck_
	# entries()) — misma forma exacta que DeckLoader._process_external_deck_
	# data()/_process_deck_data() ya saben leer, así que solo hace falta
	# completar los campos que _build_deck_card()/_populate_options() leen
	# para mostrarlo en el carrusel (nombre, raza, formato).
	var mazo := {
		"slug": "public-%d" % int(deck_data.get("id", 0)),
		"nombre": str(deck_data.get("name", "Mazo público")),
		"arquetipo": str(deck_data.get("race", "")),
		"raza": str(deck_data.get("race", "")),
		"formato": str(deck_data.get("format", "")),
		"entries": deck_data.get("entries", []),
		"id": int(deck_data.get("id", 0)),
		"image_url": str(deck_data.get("image_url", "")),
		"_is_external": true,
		"_shadowforge_kind": "public",
	}
	_mazos.append(mazo)
	if _public_browser_overlay and is_instance_valid(_public_browser_overlay):
		_public_browser_overlay.queue_free()
		_public_browser_overlay = null
	_disconnect_public_browser_signals()
	_populate_options()
	_selected_player_idx = _mazos.size() - 1
	_refresh_selection(_player_cards, _selected_player_idx)
	_update_confirm_button()


func _on_public_deck_detail_failed(reason: String) -> void:
	if _public_status_label and is_instance_valid(_public_status_label):
		_public_status_label.text = "No se pudo cargar ese mazo: %s" % reason
