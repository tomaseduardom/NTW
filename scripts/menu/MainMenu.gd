extends Control
## MainMenu - Pantalla de inicio del juego con temática de fantasía medieval
## Mitos y Leyendas: Arena de Leyendas

# =============================================================================
# REFERENCIAS UI
# =============================================================================
@onready var menu_panel: PanelContainer = get_node_or_null("%MenuPanel")
@onready var play_button: Button = get_node_or_null("%PlayButton") if has_node("%PlayButton") else $VBoxContainer/PlayButton
@onready var shadowforge_button: Button = get_node_or_null("%ShadowForgeButton") if has_node("%ShadowForgeButton") else $VBoxContainer/ShadowForgeButton
@onready var decks_button: Button = get_node_or_null("%DecksButton") if has_node("%DecksButton") else $VBoxContainer/DecksButton
@onready var backs_button: Button = get_node_or_null("%BacksButton") if has_node("%BacksButton") else $VBoxContainer/BacksButton
@onready var controls_button: Button = get_node_or_null("%ControlsButton") if has_node("%ControlsButton") else $VBoxContainer/ControlsButton
@onready var exit_button: Button = get_node_or_null("%ExitButton") if has_node("%ExitButton") else $VBoxContainer/ExitButton

var _controls_dialog: ControlsDialog = null

const GAME_SCENE := "res://scenes/game/Main.tscn"


func _ready() -> void:
	# Carga de la partida en segundo plano: load() de Main.tscn tarda unos 4,5 s (casi todo compilar
	# scripts); mientras se mira el menú ya se va cargando.
	if ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(GAME_SCENE)
	# Conectar botones y aplicar estilos interactivos
	var buttons = [play_button, shadowforge_button, decks_button, backs_button, controls_button, exit_button]
	for btn in buttons:
		if btn:
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			_setup_button_hover(btn)

	# ("intenté jugar contra el bot y no me cargó el mazo"): al salir de una partida online la sala de
	# red quedaba abierta (NetworkClient.room_code seguía seteado), así que "Jugar" contra el bot
	# entraba al flujo online y esperaba para siempre el mazo del otro jugador. Volver al menú = no hay
	# partida online en curso; OnlineConnect va directo a Main sin pasar por aquí.
	if NetworkClient.room_code != "":
		NetworkClient.disconnect_from_relay()

	play_button.pressed.connect(_on_play_pressed)
	shadowforge_button.pressed.connect(_on_shadowforge_pressed)
	decks_button.pressed.connect(_on_decks_pressed)
	backs_button.pressed.connect(_on_backs_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	# El botón muestra si ya hay una sesión de ShadowForge
	if ExternalApiClient.is_authenticated():
		shadowforge_button.text = "SHADOWFORGE (CONECTADO)"
	else:
		shadowforge_button.text = "SHADOWFORGE"

	# Focus inicial en Play
	play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _controls_dialog and _controls_dialog.visible:
				_controls_dialog.close_dialog()
				var vp := get_viewport()
				if vp:
					vp.set_input_as_handled()
				return
			var overlay = get_node_or_null("PlayModeSelection")
			if overlay:
				var vp := get_viewport()
				if vp:
					vp.set_input_as_handled()
				if overlay.has_meta("close_action"):
					var close_cb: Callable = overlay.get_meta("close_action")
					close_cb.call()
				else:
					overlay.queue_free()
					play_button.grab_focus()


func _setup_button_hover(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "modulate", Color(1.15, 1.15, 1.15, 1.0), 0.12)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween()
		tw.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
	)


func _on_play_pressed() -> void:
	_open_play_mode_popup()


func _open_play_mode_popup() -> void:
	if has_node("PlayModeSelection"):
		return

	var font_title: Font = load("res://assets/fonts/Cinzel-Bold.ttf")
	var font_sub: Font = load("res://assets/fonts/Marcellus-Regular.ttf")
	var tex_card_bot: Texture2D = load("res://assets/ui/menu/play_mode/card_bot.png")
	var tex_card_bot_hover: Texture2D = load("res://assets/ui/menu/play_mode/card_bot_hover.png")
	var tex_card_online: Texture2D = load("res://assets/ui/menu/play_mode/card_online.png")
	var tex_card_online_hover: Texture2D = load("res://assets/ui/menu/play_mode/card_online_hover.png")
	var tex_btn_back: Texture2D = load("res://assets/ui/menu/play_mode/btn_back.png")
	var tex_btn_back_hover: Texture2D = load("res://assets/ui/menu/play_mode/btn_back_hover.png")

	var overlay := Control.new()
	overlay.name = "PlayModeSelection"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Fondo oscuro cinematográfico con fade-in
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.01, 0.01, 0.03, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	var title_container = get_node_or_null("TitleContainer")
	var menu_box: Control = menu_panel if is_instance_valid(menu_panel) else get_node_or_null("VBoxContainer")
	if title_container:
		var tw_t := create_tween()
		tw_t.tween_property(title_container, "modulate:a", 0.0, 0.16)
	if menu_box:
		var tw_v := create_tween()
		tw_v.tween_property(menu_box, "modulate:a", 0.0, 0.16)
		menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	overlay.modulate.a = 0.0
	var fade_tw := overlay.create_tween()
	fade_tw.tween_property(overlay, "modulate:a", 1.0, 0.20).set_ease(Tween.EASE_OUT)

	var close_action = func():
		var close_tw := overlay.create_tween()
		close_tw.tween_property(overlay, "modulate:a", 0.0, 0.16).set_ease(Tween.EASE_IN)
		if is_instance_valid(title_container):
			var tw_t2 := create_tween()
			tw_t2.tween_property(title_container, "modulate:a", 1.0, 0.20)
		if is_instance_valid(menu_box):
			menu_box.mouse_filter = Control.MOUSE_FILTER_STOP
			var tw_v2 := create_tween()
			tw_v2.tween_property(menu_box, "modulate:a", 1.0, 0.20)
		close_tw.tween_callback(func():
			if is_instance_valid(overlay):
				overlay.queue_free()
			play_button.grab_focus()
		)

	overlay.set_meta("close_action", close_action)

	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_action.call()
	)

	# Contenedor central (Vertical)
	var center_box := VBoxContainer.new()
	center_box.set_anchors_preset(Control.PRESET_CENTER)
	center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_box.add_theme_constant_override("separation", 24)
	overlay.add_child(center_box)

	# 1. Encabezado limpio sin recuadro de fondo ("MODO DE JUEGO")
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	header_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_child(header_box)

	var header_title := Label.new()
	header_title.text = "MODO DE JUEGO"
	header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_title.add_theme_font_override("font", font_title)
	header_title.add_theme_font_size_override("font_size", 44)
	header_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	header_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	header_title.add_theme_constant_override("shadow_offset_x", 3)
	header_title.add_theme_constant_override("shadow_offset_y", 3)
	header_box.add_child(header_title)

	var header_sub := Label.new()
	header_sub.text = "— SELECCIONA TU MODALIDAD DE BATALLA —"
	header_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_sub.add_theme_font_override("font", font_sub)
	header_sub.add_theme_font_size_override("font_size", 20)
	header_sub.add_theme_color_override("font_color", Color(0.88, 0.78, 0.52, 1.0))
	header_sub.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	header_sub.add_theme_constant_override("shadow_offset_x", 2)
	header_sub.add_theme_constant_override("shadow_offset_y", 2)
	header_box.add_child(header_sub)

	# 2. Fila con las dos tarjetas heroicas
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 40)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_child(cards_row)

	var card_size := Vector2(360, 486)

	# --- Tarjeta CONTRA EL BOT ---
	var bot_action = func():
		overlay.queue_free()
		print("[MainMenu] Iniciando juego contra el bot...")
		_go_to_game()

	var card_bot_node := _build_interactive_mode_card(
		tex_card_bot,
		tex_card_bot_hover,
		card_size,
		bot_action
	)
	cards_row.add_child(card_bot_node)

	# --- Tarjeta JUGAR ONLINE ---
	var online_action = func():
		overlay.queue_free()
		print("[MainMenu] Abriendo Jugar Online...")
		get_tree().change_scene_to_file("res://scenes/menu/OnlineConnect.tscn")

	var card_online_node := _build_interactive_mode_card(
		tex_card_online,
		tex_card_online_hover,
		card_size,
		online_action
	)
	cards_row.add_child(card_online_node)

	# 3. Botón inferior VOLVER AL MENÚ [ESC]
	var footer_box := HBoxContainer.new()
	footer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_child(footer_box)

	var back_btn := TextureButton.new()
	back_btn.texture_normal = tex_btn_back
	back_btn.texture_hover = tex_btn_back_hover
	back_btn.texture_focused = tex_btn_back_hover
	back_btn.ignore_texture_size = true
	back_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	back_btn.custom_minimum_size = Vector2(280, 54)
	back_btn.pivot_offset = Vector2(140, 27)
	back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	back_btn.mouse_entered.connect(func():
		var tw := back_btn.create_tween()
		tw.tween_property(back_btn, "scale", Vector2(1.04, 1.04), 0.12).set_ease(Tween.EASE_OUT)
	)
	back_btn.mouse_exited.connect(func():
		var tw := back_btn.create_tween()
		tw.tween_property(back_btn, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	)
	back_btn.pressed.connect(close_action)
	footer_box.add_child(back_btn)

	# Foco inicial
	var bot_btn_sub = card_bot_node.get_node_or_null("Btn")
	if bot_btn_sub:
		bot_btn_sub.grab_focus()


func _build_interactive_mode_card(
	card_tex: Texture2D,
	card_hover_tex: Texture2D,
	target_size: Vector2,
	on_select: Callable
) -> Control:
	var container := Control.new()
	container.custom_minimum_size = target_size
	container.pivot_offset = target_size / 2.0
	container.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Imagen de la carta íntegra con recorte poligonal limpio (sin parches superpuestos)
	var card_rect := TextureRect.new()
	card_rect.texture = card_tex
	card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(card_rect)

	# Área de botón interactiva transparente para foco de teclado y clic directo
	var action_btn := Button.new()
	action_btn.name = "Btn"
	action_btn.flat = true
	action_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	action_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	container.add_child(action_btn)

	var set_highlight = func(active: bool):
		var tw := container.create_tween()
		if active:
			tw.tween_property(container, "scale", Vector2(1.028, 1.028), 0.14).set_ease(Tween.EASE_OUT)
			card_rect.texture = card_hover_tex
		else:
			tw.tween_property(container, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_OUT)
			card_rect.texture = card_tex

	container.mouse_entered.connect(func(): set_highlight.call(true))
	container.mouse_exited.connect(func(): set_highlight.call(false))
	action_btn.mouse_entered.connect(func(): set_highlight.call(true))
	action_btn.mouse_exited.connect(func(): set_highlight.call(false))

	# Clic tanto en el botón como en cualquier parte de la tarjeta activa la selección
	action_btn.pressed.connect(on_select)
	container.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_select.call()
	)

	return container


func _on_shadowforge_pressed() -> void:
	"""Abre la pantalla de login real de ShadowForge: conectar tu cuenta para ver tus mazos privados
	en el selector, en vez de editar un archivo a mano"""
	print("[MainMenu] Abriendo ShadowForge...")
	get_tree().change_scene_to_file("res://scenes/menu/ShadowForgeLogin.tscn")


func _on_decks_pressed() -> void:
	"""Abre el gestor de mazos"""
	print("[MainMenu] Abriendo mazos...")
	get_tree().change_scene_to_file("res://scenes/menu/DeckManager.tscn")


func _on_backs_pressed() -> void:
	"""Abre el selector de dorsos"""
	print("[MainMenu] Abriendo dorsos...")
	get_tree().change_scene_to_file("res://scenes/menu/BackSelector.tscn")


func _on_controls_pressed() -> void:
	"""Abre el diálogo modal de configuración de controles"""
	if not _controls_dialog:
		_controls_dialog = ControlsDialog.new()
		add_child(_controls_dialog)
		_controls_dialog.closed.connect(func():
			if controls_button and is_instance_valid(controls_button):
				controls_button.grab_focus()
		)
	_controls_dialog.open_dialog()


func _on_exit_pressed() -> void:
	"""Sale del juego"""
	print("[MainMenu] Saliendo...")
	get_tree().quit()


func _go_to_game() -> void:
	"""Usa la escena ya cargada en segundo plano (ver _ready()); si todavía
	está cargando, espera a que termine en vez de empezar de nuevo."""
	var tree := get_tree()
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
		status = ResourceLoader.load_threaded_get_status(GAME_SCENE)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
		if packed:
			tree.change_scene_to_packed(packed)
			return
	tree.change_scene_to_file(GAME_SCENE)
