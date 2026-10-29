extends RefCounted
## SelectionDialogs — Los 5 diálogos modales de SelectionManager
## (await_single_pick/await_two_choice/await_choice/await_castillo_pick/
## await_multi_pick), la API externa dominante de SelectionManager (54x/52x/
## 33x/4x/2x llamadas en todo el proyecto). Construyen su PROPIA UI
## descartable (CanvasLayer/Panel/etc.), independiente del panel de
## selección de cartas (open()/open_selection()/_create_selection_card(),
## que se quedan en SelectionManager.gd). Opera sobre SelectionManager via
## _main (señales card_selected/selection_completed/selection_cancelled,
## open_selection(), constantes de assets).
## Extraído de SelectionManager.gd (Fase 4 de reestructuración, "módulos gordos").

const CardScene = preload("res://scenes/cards/Card.tscn")

var _main: CanvasLayer


func setup(main: CanvasLayer) -> void:
	_main = main


func await_single_pick(candidates: Array, title: String, can_cancel: bool = true, min_selections: int = 1, filter: Callable = Callable(), chooser_id: int = 0) -> Dictionary:
	"""Abre un panel de una sola elección y espera la respuesta: open_selection() + Dictionary de
	estado (los lambdas capturan las locales por valor) + conectar
	card_selected/selection_completed/selection_cancelled + esperar + desconectar.
	max_selections = 1 siempre; min_selections = 1 por defecto (card_selected llega con la primera
	elección). Con min_selections = 0 (costo opcional, p.ej. Bernardo O'Higgins) puede terminar en
	selection_completed con array vacío; se escuchan las dos señales.
	'chooser_id' (arquitectura.md §39): open_selection()/_delegate_selection_to_remote() lo mandan
	por red y emiten las mismas 3 señales.
	Devuelve el card_data elegido, o {} si se canceló o se confirmó vacío."""
	_main.open_selection(candidates, _main.SelectionMode.CUSTOM, {
		"title": title,
		"max_selections": 1,
		"min_selections": min_selections,
		"can_cancel": can_cancel,
		"filter": filter,
	}, chooser_id)
	var state := {"resolved": false, "picked": {}}
	var on_single := func(d: Dictionary):
		state.picked = d
		state.resolved = true
	var on_completed := func(cards: Array):
		if not cards.is_empty():
			state.picked = cards[0]
		state.resolved = true
	var on_cancelled := func():
		state.resolved = true
	_main.card_selected.connect(on_single, CONNECT_ONE_SHOT)
	_main.selection_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_main.selection_cancelled.connect(on_cancelled, CONNECT_ONE_SHOT)
	while not state.resolved:
		await _main.get_tree().process_frame
	if _main.card_selected.is_connected(on_single):
		_main.card_selected.disconnect(on_single)
	if _main.selection_completed.is_connected(on_completed):
		_main.selection_completed.disconnect(on_completed)
	if _main.selection_cancelled.is_connected(on_cancelled):
		_main.selection_cancelled.disconnect(on_cancelled)
	return state.picked


func await_two_choice(main: Node, title: String, option_a: String, option_b: String, chooser_id: int = 0) -> bool:
	"""Popup de 2 botones estilizado con estética Fantasy TCG.
	Returns: true si se eligió option_a, false si option_b."""
	var picked_idx: int = await await_choice(main, title, [option_a, option_b], chooser_id)
	return picked_idx == 0


func await_card_pair_choice(
	main: Node,
	title: String,
	card_data_a: Dictionary,
	card_data_b: Dictionary,
	label_a: String = "Tope",
	label_b: String = "Fondo",
	face_down_b: bool = true,
	face_down_a: bool = false,
	chooser_id: int = 0
) -> bool:
	"""Modal de Selección Visual entre 2 Cartas (p.ej. La Ouija: tope vs fondo de Castillo). Presenta
	las dos cartas niveladas en pantalla con estética de Altar Catedralicio limpia y directa.
	'chooser_id' (ver arquitectura.md §41): mismo criterio que await_castillo_pick — esto es un
	modal visual con Nodos reales de ESTA pantalla, no tiene sentido tal cual para el Remoto. Se
	delega a await_choice (ya con puente de red) con label_a/label_b como texto en vez de construir
	un sistema nuevo — se pierde el arte de las cartas en la pantalla del Remoto, pero la elección
	en sí es la misma."""
	if load("res://scripts/core/game/PlayerSide.gd").is_bot(chooser_id):
		await main.get_tree().process_frame
		return true
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		var picked_idx: int = await await_choice(main, title, [label_a, label_b], chooser_id)
		return picked_idx == 0
	var canvas := CanvasLayer.new()
	canvas.layer = 75
	main.add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.size = main.get_viewport().get_visible_rect().size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(bg)

	var panel_w: float = 520.0
	var panel_h: float = 340.0

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -panel_w / 2.0
	panel.offset_top = -panel_h / 2.0
	panel.offset_right = panel_w / 2.0
	panel.offset_bottom = panel_h / 2.0

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.04, 0.04, 0.06, 0.98)
	p_style.border_color = Color(0.85, 0.72, 0.35, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(14)
	p_style.shadow_color = Color(0, 0, 0, 0.85)
	p_style.shadow_size = 28
	panel.add_theme_stylebox_override("panel", p_style)
	canvas.add_child(panel)

	# Fondo Altar Catedralicio con Viñeta Suave
	var bg_rect := TextureRect.new()
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.texture = _main.TEX_ALTAR_BG
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var smat := ShaderMaterial.new()
	smat.shader = _main.SHADER_VIGNETTE
	smat.set_shader_parameter("panel_size", Vector2(panel_w, panel_h))
	smat.set_shader_parameter("corner_radius", 14.0)
	smat.set_shader_parameter("vignette_amount", 0.72)
	smat.set_shader_parameter("tint_color", Color(0.02, 0.02, 0.03, 0.35))
	smat.set_shader_parameter("edge_shadow_color", Color(0.01, 0.01, 0.02, 0.95))
	bg_rect.material = smat
	panel.add_child(bg_rect)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 24
	main_vbox.offset_top = 18
	main_vbox.offset_right = -24
	main_vbox.offset_bottom = -18
	main_vbox.add_theme_constant_override("separation", 14)
	panel.add_child(main_vbox)

	# Título en Cinzel-Bold noble y limpio (sin párrafos redundantes)
	var title_lbl := Label.new()
	title_lbl.text = title.to_upper()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", _main.FONT_CINZEL_BOLD)
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	main_vbox.add_child(title_lbl)

	# Contenedor horizontal para las dos cartas
	var cards_hbox := HBoxContainer.new()
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 48)
	cards_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(cards_hbox)

	var state := {"done": false, "picked_top": true}

	# Helper para construir slot de carta nivelado
	var build_slot := func(data: Dictionary, raw_label: String, is_face_down: bool, pick_val: bool) -> Button:
		var slot_vbox := VBoxContainer.new()
		slot_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		slot_vbox.custom_minimum_size = Vector2(150, 246)
		slot_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_vbox.add_theme_constant_override("separation", 8)
		cards_hbox.add_child(slot_vbox)

		# Normalizar etiqueta a insignia concisa
		var clean_lbl: String = raw_label.strip_edges().to_upper()
		if "TOPE" in clean_lbl:
			clean_lbl = "TOPE"
		elif "FONDO" in clean_lbl:
			clean_lbl = "FONDO"

		# Insignia gótica de altura fija uniforme
		var badge_panel := PanelContainer.new()
		badge_panel.custom_minimum_size = Vector2(110, 24)
		badge_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var b_style := StyleBoxFlat.new()
		b_style.bg_color = Color(0.08, 0.08, 0.10, 0.85)
		b_style.border_color = Color(0.78, 0.65, 0.35, 0.70)
		b_style.set_border_width_all(1)
		b_style.set_corner_radius_all(5)
		badge_panel.add_theme_stylebox_override("panel", b_style)

		var badge := Label.new()
		badge.text = clean_lbl
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_override("font", _main.FONT_CINZEL_BOLD)
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65, 1.0))
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("shadow_offset_x", 1)
		badge.add_theme_constant_override("shadow_offset_y", 1)
		badge_panel.add_child(badge)
		slot_vbox.add_child(badge_panel)

		# Caja contenedora de la carta (150x210 fijo)
		var card_box := Control.new()
		card_box.custom_minimum_size = Vector2(150, 210)
		card_box.size = Vector2(150, 210)
		card_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot_vbox.add_child(card_box)

		var card_inst: Node = CardScene.instantiate()
		card_inst.load_from_data(data)
		card_inst.esta_oculta = is_face_down
		card_inst.set_zone(Constants.Zone.CEMENTERIO)
		card_inst.position = Vector2.ZERO
		card_inst.pivot_offset = Vector2(75, 105)
		card_inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_box.add_child(card_inst)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 210)
		btn.size = Vector2(150, 210)
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.offset_left = 0
		btn.offset_top = 0
		btn.offset_right = 0
		btn.offset_bottom = 0
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var s_norm := StyleBoxFlat.new()
		s_norm.bg_color = Color(0, 0, 0, 0)
		s_norm.set_border_width_all(0)
		btn.add_theme_stylebox_override("normal", s_norm)

		var s_hov := StyleBoxFlat.new()
		s_hov.bg_color = Color(0.95, 0.85, 0.50, 0.06)
		s_hov.set_border_width_all(2)
		s_hov.border_color = Color(0.95, 0.85, 0.50, 0.90)
		s_hov.set_corner_radius_all(8)
		s_hov.shadow_color = Color(0.95, 0.85, 0.40, 0.25)
		s_hov.shadow_size = 6
		btn.add_theme_stylebox_override("hover", s_hov)

		var s_focus := StyleBoxFlat.new()
		s_focus.bg_color = Color(0.95, 0.85, 0.50, 0.04)
		s_focus.set_border_width_all(2)
		s_focus.border_color = Color(0.95, 0.85, 0.50, 0.60)
		s_focus.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("focus", s_focus)

		var s_press := StyleBoxFlat.new()
		s_press.bg_color = Color(1.0, 1.0, 1.0, 0.12)
		s_press.set_border_width_all(2)
		s_press.border_color = Color(1.0, 1.0, 1.0, 0.95)
		s_press.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("pressed", s_press)

		# Hover sutil de elevación y escala
		var on_hover_enter := func():
			var tw = card_inst.create_tween()
			tw.set_parallel(true)
			tw.tween_property(card_inst, "scale", Vector2(1.03, 1.03), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(badge_panel, "modulate", Color(1.15, 1.15, 1.0, 1.0), 0.12)
		var on_hover_exit := func():
			var tw = card_inst.create_tween()
			tw.set_parallel(true)
			tw.tween_property(card_inst, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(badge_panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)

		btn.mouse_entered.connect(on_hover_enter)
		btn.mouse_exited.connect(on_hover_exit)
		btn.focus_entered.connect(on_hover_enter)
		btn.focus_exited.connect(on_hover_exit)

		btn.pressed.connect(func():
			if not state.done:
				state.picked_top = pick_val
				state.done = true
		)

		if not is_face_down:
			btn.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					if main and main.get("_card_inspector"):
						main._card_inspector.on_card_right_clicked(card_inst)
			)

		card_box.add_child(btn)
		return btn

	var btn_top: Button = build_slot.call(card_data_a, label_a, face_down_a, true)
	var btn_bottom: Button = build_slot.call(card_data_b, label_b, face_down_b, false)

	btn_top.focus_next = btn_bottom.get_path()
	btn_top.focus_previous = btn_bottom.get_path()
	btn_bottom.focus_next = btn_top.get_path()
	btn_bottom.focus_previous = btn_top.get_path()

	btn_top.grab_focus()

	# Tiempo agotado (TurnClock): la primera opción.
	var force_gen: int = NetworkClient.force_gen
	NetworkClient.local_waits += 1
	while not state.done:
		if NetworkClient.ui_forced(force_gen):
			state.picked_top = true
			NetworkClient.ui_forced_done()
			break
		await main.get_tree().process_frame
	NetworkClient.local_waits = maxi(0, NetworkClient.local_waits - 1)

	canvas.queue_free()
	return state.picked_top


func await_choice(main: Node, title: String, options: Array, chooser_id: int = 0) -> int:
	"""Elegir entre opciones sobre la mesa (BoardChoice: fichas ancladas, sin ventana). Devuelve el
	índice (0-based) de la opción elegida.
	'chooser_id': si elige el jugador 1 con un Remoto conectado, se le pregunta por red (el Remoto usa
	las mismas fichas sobre su tablero, ancladas a la misma carta); el bot elige solo."""
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		var src = load("res://scripts/core/effects/EffectContext.gd").current().get("card")
		NetworkClient.send_message({"op": "prompt", "kind": "choose_option", "title": title, "options": options,
			"source_id": str(src.get_instance_id()) if src is Node and is_instance_valid(src) else ""})
		var intent: Dictionary = await NetworkClient.await_intent(["choose_option_choice"])
		return clampi(int(intent.get("index", 0)), 0, maxi(options.size() - 1, 0))
	# El bot elige solo (la primera opción): nunca se le abre al Anfitrión una elección del bot.
	if load("res://scripts/core/game/PlayerSide.gd").is_bot(chooser_id):
		await main.get_tree().process_frame
		return 0

	# En la mesa, sin ventana: fichas ancladas a lo que afecta cada opción (BoardChoice).
	var ctx_card = load("res://scripts/core/effects/EffectContext.gd").current().get("card")
	return await load("res://scripts/ui/hud/BoardChoice.gd").choose(main, title, options, ctx_card)


var _castillo_pick_active: bool = false
var _castillo_pick_own_only: bool = false
var _castillo_pick_callback: Callable = Callable()
var _castillo_pick_cleanup: Callable = Callable()


func start_castillo_pick(main: Node, title: String, callback: Callable, own_only: bool = false) -> void:
	"""Versión 'start' de await_castillo_pick(), para correr en carrera contra otra selección (p.ej.
	CardInteractionModule.start_target_selection() con Sherlock Holmes: "cartas en juego" o "un
	Castillo" con el primer click). El que resuelve primero cancela al otro
	(cancel_castillo_pick()). callback recibe true/false (propio/rival)."""
	var player_castillo: Panel = main.get_node_or_null("GameBoard/PlayerArea/PlayerCastillo")
	var opponent_castillo: Panel = main.get_node_or_null("GameBoard/OpponentArea/OpponentCastillo")
	if not player_castillo or not opponent_castillo:
		# No debería pasar (nodos fijos de Main.tscn) — fallback al popup viejo.
		callback.call(await await_two_choice(main, title, "Tu Castillo", "Castillo del oponente"))
		return

	if main.has_method("_update_debug") and not own_only:
		main._update_debug("%s — clickea tu Castillo o el del rival" % title)

	_castillo_pick_active = true
	_castillo_pick_own_only = own_only
	_castillo_pick_callback = callback

	_set_castillo_pick_glow(player_castillo, true)
	_set_castillo_pick_glow(opponent_castillo, true)
	var prev_player_filter := player_castillo.mouse_filter
	var prev_opponent_filter := opponent_castillo.mouse_filter
	player_castillo.mouse_filter = Control.MOUSE_FILTER_STOP
	opponent_castillo.mouse_filter = Control.MOUSE_FILTER_STOP

	# Cursor de mano + pulso suave de brillo, para que el Castillo se sienta clickeable. Se para al
	# resolver.
	var prev_player_cursor := player_castillo.mouse_default_cursor_shape
	var prev_opponent_cursor := opponent_castillo.mouse_default_cursor_shape
	player_castillo.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	opponent_castillo.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var pulse_player := player_castillo.create_tween()
	pulse_player.set_loops()
	pulse_player.tween_property(player_castillo, "modulate", Color(1.25, 1.25, 1.25, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	pulse_player.tween_property(player_castillo, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	var pulse_opponent := opponent_castillo.create_tween()
	pulse_opponent.set_loops()
	pulse_opponent.tween_property(opponent_castillo, "modulate", Color(1.25, 1.25, 1.25, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	pulse_opponent.tween_property(opponent_castillo, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)

	var on_player_input_box: Array = []  # la lambda captura por valor: se desconecta por aquí
	var on_player_input: Callable
	var on_opponent_input_box: Array = []  # la lambda captura por valor: se desconecta por aquí
	var on_opponent_input: Callable
	_castillo_pick_cleanup = func() -> void:
		if player_castillo.gui_input.is_connected(on_player_input_box[0]):
			player_castillo.gui_input.disconnect(on_player_input_box[0])
		if opponent_castillo.gui_input.is_connected(on_opponent_input_box[0]):
			opponent_castillo.gui_input.disconnect(on_opponent_input_box[0])
		player_castillo.mouse_filter = prev_player_filter
		opponent_castillo.mouse_filter = prev_opponent_filter
		player_castillo.mouse_default_cursor_shape = prev_player_cursor
		opponent_castillo.mouse_default_cursor_shape = prev_opponent_cursor
		pulse_player.kill()
		pulse_opponent.kill()
		player_castillo.modulate = Color(1.0, 1.0, 1.0, 1.0)
		opponent_castillo.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_castillo_pick_glow(player_castillo, false)
		_set_castillo_pick_glow(opponent_castillo, false)

	on_player_input = func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_resolve_castillo_pick(true)
	on_player_input_box.append(on_player_input)
	on_opponent_input = func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_resolve_castillo_pick(false)
	on_opponent_input_box.append(on_opponent_input)
	player_castillo.gui_input.connect(on_player_input)
	if own_only:
		# Solo tu Castillo (p.ej. "Roba hasta N"): el rival no brilla ni se puede clickear.
		pulse_opponent.kill()
		opponent_castillo.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_set_castillo_pick_glow(opponent_castillo, false)
		opponent_castillo.mouse_filter = prev_opponent_filter
		opponent_castillo.mouse_default_cursor_shape = prev_opponent_cursor
	else:
		opponent_castillo.gui_input.connect(on_opponent_input)


func _resolve_castillo_pick(picked_own: bool) -> void:
	if not _castillo_pick_active:
		return
	_castillo_pick_active = false
	var callback := _castillo_pick_callback
	var cleanup := _castillo_pick_cleanup
	_castillo_pick_callback = Callable()
	_castillo_pick_cleanup = Callable()
	if cleanup.is_valid():
		cleanup.call()
	if callback.is_valid():
		callback.call(picked_own)


func cancel_castillo_pick() -> void:
	"""Cancela una selección de Castillo en curso SIN invocar el callback —
	usado cuando otra selección en carrera (p.ej. una carta en juego) ganó
	primero (ver start_castillo_pick())."""
	if not _castillo_pick_active:
		return
	_castillo_pick_active = false
	var cleanup := _castillo_pick_cleanup
	_castillo_pick_callback = Callable()
	_castillo_pick_cleanup = Callable()
	if cleanup.is_valid():
		cleanup.call()


func await_castillo_pick(main: Node, title: String, chooser_id: int = 0) -> bool:
	"""Espera un click sobre el Panel del Castillo propio o rival (p.ej. Infernum Vox, Aho, Espada del
	Juicio), con ambos resaltados en celeste. Sin cancelar: es una elección obligatoria entre dos
	zonas, como await_two_choice(). Envoltorio de start_castillo_pick().
	'chooser_id' (arquitectura.md §40): el Remoto no ve el tablero del Anfitrión, así que se delega
	a await_choice() (con puente de red, "choose_option") con las dos opciones en texto.
	Devuelve true si se eligió el Castillo propio, false si el rival."""
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		var picked_idx: int = await await_choice(main, title, ["Tu Castillo", "Castillo rival"], chooser_id)
		return picked_idx == 0
	if load("res://scripts/core/game/PlayerSide.gd").is_bot(chooser_id):
		await main.get_tree().process_frame
		return false  # el bot apunta al Castillo rival
	var state := {"done": false, "picked_own": true}
	start_castillo_pick(main, title, func(v: bool) -> void:
		state.picked_own = v
		state.done = true)
	while not state.done:
		await main.get_tree().process_frame
	return state.picked_own


func _set_castillo_pick_glow(panel: Panel, on: bool) -> void:
	if not on:
		panel.remove_theme_stylebox_override("panel")
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1.0, 0.85, 0.38, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(1.0, 0.78, 0.25, 0.55)
	style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", style)


func await_multi_pick(candidates: Array, title: String, max_selections: int, min_selections: int = 0, can_cancel: bool = true, filter: Callable = Callable(), chooser_id: int = 0) -> Dictionary:
	"""Selección múltiple (0 a max_selections) que espera la respuesta. A diferencia de
	await_single_pick(), "canceló" y "confirmó sin elegir nada" son resultados distintos (declinar
	el "puedes" vs. aceptarlo sin elegir), por eso devuelve un Dictionary.
	'chooser_id' (arquitectura.md §40): el puente está en open_selection(). Límite del Remoto:
	RemoteMirrorController._show_select_cards_prompt() usa checkboxes, así que no preserva el orden
	de click (p.ej. Infernum Vox, que reordena el tope); "mirar y elegir cuáles" funciona igual.
	Devuelve {"cancelled": bool, "picked": Array[Dictionary]}."""
	_main.open_selection(candidates, _main.SelectionMode.CUSTOM, {
		"title": title,
		"max_selections": max_selections,
		"min_selections": min_selections,
		"can_cancel": can_cancel,
		"filter": filter,
	}, chooser_id)
	var state := {"resolved": false, "picked": [], "cancelled": false}
	var on_single := func(d: Dictionary):
		state.picked = [d]
		state.resolved = true
	var on_completed := func(cards: Array):
		state.picked = cards
		state.resolved = true
	var on_cancelled := func():
		state.cancelled = true
		state.resolved = true
	_main.card_selected.connect(on_single, CONNECT_ONE_SHOT)
	_main.selection_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_main.selection_cancelled.connect(on_cancelled, CONNECT_ONE_SHOT)
	while not state.resolved:
		await _main.get_tree().process_frame
	if _main.card_selected.is_connected(on_single):
		_main.card_selected.disconnect(on_single)
	if _main.selection_completed.is_connected(on_completed):
		_main.selection_completed.disconnect(on_completed)
	if _main.selection_cancelled.is_connected(on_cancelled):
		_main.selection_cancelled.disconnect(on_cancelled)
	return {"cancelled": state.cancelled, "picked": state.picked}
