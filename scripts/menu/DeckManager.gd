extends Control
## DeckManager - Pantalla de gestión de mazos y visor de la comunidad
## Construido con la identidad visual medieval oscura y dorada (GEMINI.md Regla 1)

# =============================================================================
# SEÑALES
# =============================================================================
signal deck_selected(deck_data: Dictionary)

# =============================================================================
# CONSTANTES
# =============================================================================
const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")

const RACE_TEXTURES := {
	"caballero": preload("res://assets/ui/deck_selector/card_caballero.png"),
	"bestia": preload("res://assets/ui/deck_selector/card_bestia.png"),
	"dragon": preload("res://assets/ui/deck_selector/card_dragon.png"),
	"dragón": preload("res://assets/ui/deck_selector/card_dragon.png"),
	"imp": preload("res://assets/ui/deck_selector/card_imp.png"),
	"heroe": preload("res://assets/ui/deck_selector/card_heroe.png"),
	"héroe": preload("res://assets/ui/deck_selector/card_heroe.png"),
	"guerrero": preload("res://assets/ui/deck_selector/card_guerrero.png"),
	"douglas": preload("res://assets/ui/deck_selector/card_guerrero.png"),
	"faerie": preload("res://assets/ui/deck_selector/card_faerie.png"),
	"sacerdote": preload("res://assets/ui/deck_selector/card_sacerdote.png"),
	"sombra": preload("res://assets/ui/deck_selector/card_sombra.png"),
	"eterno": preload("res://assets/ui/deck_selector/card_eterno.png"),
	"generic": preload("res://assets/ui/deck_selector/card_generic.png"),
}

const CARD_WIDTH: float = 320.0
const CARD_HEIGHT: float = 390.0
const GRID_GAP: float = 24.0

# =============================================================================
# REFERENCIAS UI
# =============================================================================
@onready var back_button: Button = find_child("BackButton", true, false)
@onready var title_label: Label = find_child("TitleLabel", true, false)
@onready var subtitle_label: Label = find_child("SubtitleLabel", true, false)
@onready var decks_container: GridContainer = find_child("DecksContainer", true, false)
@onready var loading_label: Label = find_child("LoadingLabel", true, false)
@onready var error_label: Label = find_child("ErrorLabel", true, false)
@onready var scroll_container: ScrollContainer = find_child("ScrollContainer", true, false)
@onready var top_separator: HSeparator = find_child("Separator", true, false)

# =============================================================================
# VARIABLES
# =============================================================================
var decks_data: Array = []
var is_loading: bool = false
var _pending_deck_summary: Dictionary = {}


func _ready() -> void:
	_style_ui()
	_update_grid_columns()

	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	_fetch_decks()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_grid_columns()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _update_grid_columns() -> void:
	if not is_instance_valid(decks_container):
		return
	var avail_w: float = get_viewport_rect().size.x - 120.0
	var col_slot: float = CARD_WIDTH + GRID_GAP
	var cols: int = clampi(int(avail_w / col_slot), 1, 4)
	decks_container.columns = cols


func _style_ui() -> void:
	# Barra de títulos y encabezados medievales
	if title_label:
		title_label.add_theme_font_override("font", FONT_TITLE)
		title_label.add_theme_font_size_override("font_size", 30)
		title_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.42, 1.0))
		title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		title_label.add_theme_constant_override("shadow_offset_y", 2)

	if subtitle_label:
		subtitle_label.add_theme_font_override("font", FONT_BODY)
		subtitle_label.add_theme_font_size_override("font_size", 14)
		subtitle_label.add_theme_color_override("font_color", Color(0.70, 0.75, 0.82, 0.90))

	if back_button:
		_style_medieval_button(back_button)

	if top_separator:
		var sep_style = StyleBoxLine.new()
		sep_style.color = Color(0.78, 0.65, 0.32, 0.40)
		sep_style.thickness = 1
		top_separator.add_theme_stylebox_override("separator", sep_style)

	if loading_label:
		loading_label.add_theme_font_override("font", FONT_TITLE)
		loading_label.add_theme_font_size_override("font_size", 22)
		loading_label.add_theme_color_override("font_color", Color(0.94, 0.82, 0.42, 1.0))

	if error_label:
		error_label.add_theme_font_override("font", FONT_BODY)
		error_label.add_theme_font_size_override("font_size", 17)
		error_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55, 1.0))


func _style_medieval_button(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", FONT_TITLE)
	btn.add_theme_font_size_override("font_size", 14)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	style_normal.border_color = Color(0.55, 0.48, 0.35, 0.85)
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(8)
	style_normal.content_margin_left = 18
	style_normal.content_margin_right = 18
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.18, 0.24, 0.34, 1.0)
	style_hover.border_color = Color(1.0, 0.88, 0.48, 1.0)
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(8)
	style_hover.shadow_color = Color(0.88, 0.74, 0.28, 0.35)
	style_hover.shadow_size = 10
	style_hover.content_margin_left = 18
	style_hover.content_margin_right = 18
	style_hover.content_margin_top = 8
	style_hover.content_margin_bottom = 8

	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.20, 0.17, 0.10, 0.98)
	style_pressed.border_color = Color(0.88, 0.74, 0.28, 0.90)
	style_pressed.set_border_width_all(2)
	style_pressed.set_corner_radius_all(8)
	style_pressed.content_margin_left = 18
	style_pressed.content_margin_right = 18
	style_pressed.content_margin_top = 8
	style_pressed.content_margin_bottom = 8

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_hover)
	btn.add_theme_color_override("font_color", Color(0.96, 0.90, 0.75, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.48, 1.0))


func _fetch_decks() -> void:
	"""Mazos públicos de ShadowForge vía ExternalApiClient.gd"""
	if is_loading:
		return

	is_loading = true
	_show_loading(true)

	if not ExternalApiClient.public_decks_received.is_connected(_on_public_decks_received):
		ExternalApiClient.public_decks_received.connect(_on_public_decks_received, CONNECT_ONE_SHOT)
	if not ExternalApiClient.public_decks_failed.is_connected(_on_public_decks_failed):
		ExternalApiClient.public_decks_failed.connect(_on_public_decks_failed, CONNECT_ONE_SHOT)
	ExternalApiClient.fetch_public_decks("", 1, "", "", "popular")


func _on_public_decks_received(results: Array, count: int) -> void:
	is_loading = false
	_show_loading(false)
	decks_data = results
	print("[DeckManager] %d mazos públicos cargados (de %d totales)" % [decks_data.size(), count])
	_populate_decks()


func _on_public_decks_failed(reason: String) -> void:
	is_loading = false
	_show_loading(false)
	print("[DeckManager] No se pudieron cargar mazos públicos: ", reason)
	_show_error("No se pudieron cargar los mazos públicos (%s)" % reason)


func _populate_decks() -> void:
	"""Crea los items visuales para cada mazo de forma ordenada y centrada"""
	if not decks_container:
		return

	for child in decks_container.get_children():
		child.queue_free()

	if decks_data.is_empty():
		_show_error("No hay mazos disponibles en este momento")
		return

	if error_label:
		error_label.visible = false

	for deck in decks_data:
		var deck_card = _create_deck_card(deck)
		decks_container.add_child(deck_card)


func _get_race_texture(race_str: String) -> Texture2D:
	var key = race_str.to_lower().strip_edges()
	for k in RACE_TEXTURES.keys():
		if k == key or key.contains(k):
			return RACE_TEXTURES[k]
	return RACE_TEXTURES["generic"]


func _create_deck_card(deck: Dictionary) -> Control:
	"""Crea una tarjeta de mazo elegante con base medieval oscura y dorada"""
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.pivot_offset = Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5)

	# 1. Base Panel: Obsidiana (#0B0E14) con borde dorado y sombra suave
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	panel_style.border_color = Color(0.78, 0.65, 0.32, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_color = Color(0, 0, 0, 0.75)
	panel_style.shadow_size = 16
	card.add_theme_stylebox_override("panel", panel_style)

	# 2. Contenedor de contenido
	var clip_margin = MarginContainer.new()
	clip_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_margin.clip_contents = true
	card.add_child(clip_margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	clip_margin.add_child(main_vbox)

	# 3. Mitad superior: Banner ilustrado de la Raza / Portada
	var cover_container = Control.new()
	cover_container.custom_minimum_size = Vector2(CARD_WIDTH, 175)
	cover_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cover_container.clip_contents = true
	main_vbox.add_child(cover_container)

	var race_name = str(deck.get("race", "")).strip_edges()
	if race_name.is_empty():
		race_name = "Sin Raza"
	var default_tex = _get_race_texture(race_name)

	var cover_rect = TextureRect.new()
	cover_rect.name = "CoverImage"
	cover_rect.texture = default_tex
	cover_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cover_container.add_child(cover_rect)

	# Carga de portada externa de ShadowForge si existe
	var portada_url = deck.get("image_url", null)
	if portada_url != null and typeof(portada_url) == TYPE_STRING and not portada_url.is_empty():
		_load_cover_image_into(cover_rect, portada_url)

	# Gradiente de desvanecimiento hacia abajo para fusionar la imagen con el fondo de obsidiana
	var gradient_rect = TextureRect.new()
	gradient_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	gradient_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var grad = Gradient.new()
	grad.set_color(0, Color(0.07, 0.09, 0.13, 0.0))
	grad.set_color(1, Color(0.07, 0.09, 0.13, 0.98))
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.5, 0.3)
	grad_tex.fill_to = Vector2(0.5, 1.0)
	gradient_rect.texture = grad_tex
	cover_container.add_child(gradient_rect)

	# Badge de Raza en la esquina superior izquierda
	var badge_margin = MarginContainer.new()
	badge_margin.offset_left = 12.0
	badge_margin.offset_top = 12.0
	cover_container.add_child(badge_margin)

	var badge_panel = PanelContainer.new()
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.08, 0.10, 0.15, 0.92)
	badge_style.border_color = Color(0.85, 0.70, 0.30, 0.90)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(6)
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 4
	badge_style.content_margin_bottom = 4
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	badge_margin.add_child(badge_panel)

	var badge_label = Label.new()
	badge_label.text = race_name.to_upper()
	badge_label.add_theme_font_override("font", FONT_TITLE)
	badge_label.add_theme_font_size_override("font_size", 11)
	badge_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.50, 1.0))
	badge_panel.add_child(badge_label)

	# Formato en la esquina superior derecha si está disponible
	var deck_format = str(deck.get("format", "")).strip_edges()
	if not deck_format.is_empty():
		var format_margin = MarginContainer.new()
		format_margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		format_margin.offset_right = -12.0
		format_margin.offset_top = 12.0
		format_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cover_container.add_child(format_margin)

		var format_panel = PanelContainer.new()
		var format_style = StyleBoxFlat.new()
		format_style.bg_color = Color(0.08, 0.10, 0.15, 0.85)
		format_style.border_color = Color(0.55, 0.50, 0.40, 0.75)
		format_style.set_border_width_all(1)
		format_style.set_corner_radius_all(6)
		format_style.content_margin_left = 8
		format_style.content_margin_right = 8
		format_style.content_margin_top = 4
		format_style.content_margin_bottom = 4
		format_panel.add_theme_stylebox_override("panel", format_style)
		format_margin.add_child(format_panel)

		var format_label = Label.new()
		format_label.text = deck_format.to_upper()
		format_label.add_theme_font_override("font", FONT_BODY)
		format_label.add_theme_font_size_override("font_size", 10)
		format_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.90))
		format_panel.add_child(format_label)

	# 4. Mitad inferior: Título, autor, curva y estadísticas
	var body_margin = MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.add_theme_constant_override("margin_right", 16)
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	main_vbox.add_child(body_margin)

	var body_vbox = VBoxContainer.new()
	body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_vbox.add_theme_constant_override("separation", 6)
	body_margin.add_child(body_vbox)

	# Título del mazo
	var title_lbl = Label.new()
	title_lbl.text = deck.get("name", "Mazo Desconocido")
	title_lbl.add_theme_font_override("font", FONT_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.max_lines_visible = 2
	body_vbox.add_child(title_lbl)

	# Autor
	var autor = str(deck.get("owner_username", "")).strip_edges()
	if autor.is_empty():
		autor = "Anónimo"
	var author_lbl = Label.new()
	author_lbl.text = "por %s" % autor
	author_lbl.add_theme_font_override("font", FONT_BODY)
	author_lbl.add_theme_font_size_override("font_size", 13)
	author_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.82, 0.90))
	body_vbox.add_child(author_lbl)

	# Separador dorado fino
	var sep = HSeparator.new()
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(0.78, 0.65, 0.32, 0.35)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	body_vbox.add_child(sep)

	# Curva de mana / coste si está disponible
	var curve_costs := _compute_cost_curve(deck)
	if not curve_costs.is_empty():
		body_vbox.add_child(_build_mana_curve_row(curve_costs))

	# Spacer expansor
	var sp = Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_vbox.add_child(sp)

	# Footer: Stats de Cartas y Votos (números enteros limpios sin decimales)
	var footer_hbox = HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 18)
	body_vbox.add_child(footer_hbox)

	var card_count: int = int(deck.get("card_count", 0))
	var like_count: int = int(deck.get("like_count", 0))

	# Cantidad de cartas
	var cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 4)
	footer_hbox.add_child(cards_box)

	var cards_tag = Label.new()
	cards_tag.text = "Cartas:"
	cards_tag.add_theme_font_override("font", FONT_BODY)
	cards_tag.add_theme_font_size_override("font_size", 13)
	cards_tag.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 1.0))
	cards_box.add_child(cards_tag)

	var cards_val = Label.new()
	cards_val.text = "%d" % card_count
	cards_val.add_theme_font_override("font", FONT_TITLE)
	cards_val.add_theme_font_size_override("font_size", 13)
	cards_val.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	cards_box.add_child(cards_val)

	# Votos / Likes
	var likes_box = HBoxContainer.new()
	likes_box.add_theme_constant_override("separation", 4)
	footer_hbox.add_child(likes_box)

	var likes_tag = Label.new()
	likes_tag.text = "Votos:"
	likes_tag.add_theme_font_override("font", FONT_BODY)
	likes_tag.add_theme_font_size_override("font_size", 13)
	likes_tag.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 1.0))
	likes_box.add_child(likes_tag)

	var likes_val = Label.new()
	likes_val.text = "%d" % like_count
	likes_val.add_theme_font_override("font", FONT_TITLE)
	likes_val.add_theme_font_size_override("font_size", 13)
	likes_val.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	likes_box.add_child(likes_val)

	# 5. Botón interactivo transparente que cubre toda la tarjeta
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_ALL
	card.add_child(btn)

	# Animación táctil fluida al pasar el ratón o ganar foco
	var base_y: float = card.position.y
	btn.mouse_entered.connect(func():
		var tw = card.create_tween().set_parallel(true)
		tw.tween_property(panel_style, "border_color", Color(1.0, 0.88, 0.48, 1.0), 0.14)
		tw.tween_property(panel_style, "shadow_color", Color(0.88, 0.74, 0.28, 0.40), 0.14)
		tw.tween_property(panel_style, "shadow_size", 22, 0.14)
		tw.tween_property(card, "position:y", base_y - 6.0, 0.14).set_ease(Tween.EASE_OUT)
		tw.tween_property(cover_rect, "modulate", Color(1.15, 1.15, 1.15), 0.14)
	)
	btn.mouse_exited.connect(func():
		var tw = card.create_tween().set_parallel(true)
		tw.tween_property(panel_style, "border_color", Color(0.78, 0.65, 0.32, 0.85), 0.16)
		tw.tween_property(panel_style, "shadow_color", Color(0, 0, 0, 0.75), 0.16)
		tw.tween_property(panel_style, "shadow_size", 16, 0.16)
		tw.tween_property(card, "position:y", base_y, 0.16).set_ease(Tween.EASE_OUT)
		tw.tween_property(cover_rect, "modulate", Color.WHITE, 0.16)
	)
	btn.button_down.connect(func():
		var tw = card.create_tween().set_parallel(true)
		tw.tween_property(card, "modulate", Color(0.9, 0.9, 0.9), 0.05)
		tw.tween_property(card, "position:y", base_y + 2.0, 0.05)
	)
	btn.button_up.connect(func():
		var tw = card.create_tween().set_parallel(true)
		tw.tween_property(card, "modulate", Color.WHITE, 0.08)
		tw.tween_property(card, "position:y", base_y - 6.0, 0.08)
	)

	btn.pressed.connect(_on_deck_selected.bind(deck))
	return card


func _ensure_card_database_ready() -> bool:
	if CardDatabase.is_loaded and not CardDatabase.cards.is_empty():
		return true
	if CardDatabase.load_cards_from_bundled():
		return true
	if CardDatabase.load_cards_from_cache():
		return true
	return false


func _compute_cost_curve(deck: Dictionary) -> Array:
	if not _ensure_card_database_ready():
		return []

	var datos_json = deck.get("datos_json", deck.get("data", {}))
	if datos_json is String:
		datos_json = JSON.parse_string(datos_json)
	if not datos_json is Dictionary:
		datos_json = {}

	var main_deck: Dictionary = datos_json.get("main", datos_json.get("main_deck", datos_json.get("maindeck", {})))
	if not main_deck is Dictionary:
		main_deck = {}

	if main_deck.is_empty() and deck.get("entries") is Array:
		for entry in deck.entries:
			if not entry is Dictionary:
				continue
			var cid = str(entry.get("myl_id", entry.get("card_id", entry.get("id", ""))))
			if cid.is_empty():
				continue
			var qty = int(entry.get("quantity", entry.get("qty", 1)))
			main_deck[cid] = main_deck.get(cid, 0) + qty

	if main_deck.is_empty() and datos_json.get("cards") is Array:
		for entry in datos_json.cards:
			if not entry is Dictionary or entry.get("is_side", false):
				continue
			var cid = str(entry.get("myl_id", entry.get("card_id", entry.get("id", ""))))
			if cid.is_empty():
				continue
			var qty = int(entry.get("quantity", entry.get("qty", 1)))
			main_deck[cid] = main_deck.get(cid, 0) + qty

	if main_deck.is_empty():
		return []

	var buckets: Array = [0, 0, 0, 0, 0, 0, 0]
	var any_resolved := false
	for cid in main_deck:
		var card_data: Dictionary = CardDatabase.get_card(str(cid))
		if card_data.is_empty():
			continue
		if card_data.get("tipo", -1) == Constants.CardType.ORO:
			continue
		any_resolved = true
		var coste: int = int(card_data.get("coste", 0))
		var idx: int = clampi(coste, 0, 6)
		buckets[idx] += int(main_deck[cid])

	return buckets if any_resolved else []


func _build_mana_curve_row(costs: Array) -> Control:
	const BAR_MAX_HEIGHT := 28.0
	const BAR_WIDTH := 12.0
	const GOLD := Color(0.83, 0.69, 0.22, 1.0)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)

	var max_count: int = 1
	for c in costs:
		max_count = maxi(max_count, int(c))

	var cost_labels := ["0", "1", "2", "3", "4", "5", "6+"]
	for i in range(costs.size()):
		var col = VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.alignment = BoxContainer.ALIGNMENT_END
		col.custom_minimum_size = Vector2(BAR_WIDTH, BAR_MAX_HEIGHT + 14)

		var count: int = int(costs[i])
		var bar_height: float = 3.0 if count == 0 else max(3.0, BAR_MAX_HEIGHT * (float(count) / float(max_count)))

		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(BAR_WIDTH, BAR_MAX_HEIGHT - bar_height)
		col.add_child(spacer)

		var bar = ColorRect.new()
		bar.custom_minimum_size = Vector2(BAR_WIDTH, bar_height)
		bar.color = GOLD if count > 0 else Color(1, 1, 1, 0.12)
		bar.tooltip_text = "%d carta(s) de coste %s" % [count, cost_labels[i]]
		col.add_child(bar)

		var lbl = Label.new()
		lbl.text = cost_labels[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", FONT_BODY)
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.8))
		col.add_child(lbl)

		row.add_child(col)

	return row


func _load_cover_image_into(texture_rect: TextureRect, url: String) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var image: Image = CardDatabase.decode_image_buffer(body)
			if image != null and is_instance_valid(texture_rect):
				var texture = ImageTexture.create_from_image(image)
				texture_rect.texture = texture
				print("[DeckManager] Portada remota cargada con éxito")
		http.queue_free()
	)
	var err = http.request(url)
	if err != OK:
		http.queue_free()


func _on_deck_selected(deck: Dictionary) -> void:
	var deck_name = str(deck.get("name", ""))
	var deck_id = int(deck.get("id", 0))
	print("[DeckManager] Mazo elegido: %s (id: %d)" % [deck_name, deck_id])

	deck_selected.emit(deck)

	if deck_id <= 0:
		_show_error("El mazo seleccionado no tiene un identificador válido")
		return

	if not DeckLoader.deck_loaded.is_connected(_on_deck_loaded):
		DeckLoader.deck_loaded.connect(_on_deck_loaded)
	if not DeckLoader.deck_load_failed.is_connected(_on_deck_load_failed):
		DeckLoader.deck_load_failed.connect(_on_deck_load_failed)
	if not DeckLoader.all_decks_ready.is_connected(_on_all_decks_ready):
		DeckLoader.all_decks_ready.connect(_on_all_decks_ready)

	_show_loading(true)
	_pending_deck_summary = deck
	if not ExternalApiClient.public_deck_detail_received.is_connected(_on_deck_entries_received):
		ExternalApiClient.public_deck_detail_received.connect(_on_deck_entries_received, CONNECT_ONE_SHOT)
	if not ExternalApiClient.public_deck_detail_failed.is_connected(_on_deck_entries_failed):
		ExternalApiClient.public_deck_detail_failed.connect(_on_deck_entries_failed, CONNECT_ONE_SHOT)
	ExternalApiClient.fetch_public_deck_entries(deck_id)


func _on_deck_entries_received(deck_data: Dictionary) -> void:
	var mazo := {
		"nombre": str(deck_data.get("name", _pending_deck_summary.get("name", "Mazo público"))),
		"arquetipo": str(deck_data.get("race", "")),
		"formato": str(deck_data.get("format", "")),
		"entries": deck_data.get("entries", []),
	}
	DeckLoader.load_deck_from_external_data(0, mazo)


func _on_deck_entries_failed(reason: String) -> void:
	_show_loading(false)
	_show_error("No se pudieron descargar las cartas de ese mazo: %s" % reason)


func _on_deck_loaded(player_id: int, card_count: int) -> void:
	if not is_inside_tree():
		return
	_show_loading(false)
	print("[DeckManager] Mazo cargado: %d cartas para jugador %d" % [card_count, player_id])

	if not DeckLoader.is_deck_loaded(1):
		DeckLoader.load_random_deck(1, 50)
		return

	_go_to_game()


func _on_deck_load_failed(player_id: int, error: String) -> void:
	if not is_inside_tree():
		return
	_show_loading(false)
	_show_error("Error cargando mazo: %s" % error)


func _on_all_decks_ready() -> void:
	print("[DeckManager] Ambos mazos listos, iniciando partida...")
	_go_to_game()


func _go_to_game() -> void:
	var tree = get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.change_scene_to_file("res://scenes/game/Main.tscn")
	else:
		push_error("[DeckManager] No se pudo obtener el SceneTree")


func _show_loading(show: bool) -> void:
	if loading_label:
		loading_label.visible = show
	if scroll_container:
		scroll_container.visible = not show
	if error_label:
		error_label.visible = false


func _show_error(message: String) -> void:
	if error_label:
		error_label.text = message
		error_label.visible = true
	if loading_label:
		loading_label.visible = false


func _on_back_pressed() -> void:
	print("[DeckManager] Returning to main menu...")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
