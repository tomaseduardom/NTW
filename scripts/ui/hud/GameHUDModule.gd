extends Node
class_name GameHUDModule
## GameHUDModule — Interfaz visual del HUD en juego: anuncio de fases y botón de acción/prioridad.

const FONT_MEDIEVAL := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")

const TEX_BTN_NORMAL := preload("res://assets/ui/hud/btn_paso_normal.png")
const TEX_BTN_HOVER := preload("res://assets/ui/hud/btn_paso_hover.png")
const TEX_BTN_PRESSED := preload("res://assets/ui/hud/btn_paso_pressed.png")
const TEX_BTN_DISABLED := preload("res://assets/ui/hud/btn_paso_disabled.png")

var _main: Node = null
var _paso_button: Button = null
var _style_normal: StyleBoxTexture = null
var _style_hover: StyleBoxTexture = null
var _style_pressed: StyleBoxTexture = null
var _style_disabled: StyleBoxTexture = null
var _paso_glow_tween: Tween = null
## Generación de la cuenta regresiva del botón: sube en cada start/stop para que un bucle viejo deje
## de escribir el texto.
var _countdown_generation: int = 0
var _phase_announcer_label: Label = null
var _phase_announcer_tween: Tween = null


func setup(main: Node) -> void:
	_main = main
	_setup_phase_announcer()
	_setup_paso_button()


# =============================================================================
# ANUNCIADOR DE FASES
# =============================================================================
func _setup_phase_announcer() -> void:
	"""Crea el Label central para animar el cambio de fase."""
	_phase_announcer_label = Label.new()
	_phase_announcer_label.name = "PhaseAnnouncerLabel"
	_phase_announcer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_announcer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_announcer_label.anchor_left = 0.5
	_phase_announcer_label.anchor_top = 0.5
	_phase_announcer_label.anchor_right = 0.5
	_phase_announcer_label.anchor_bottom = 0.5
	_phase_announcer_label.offset_left = -350
	_phase_announcer_label.offset_top = -45
	_phase_announcer_label.offset_right = 350
	_phase_announcer_label.offset_bottom = 45
	_phase_announcer_label.pivot_offset = Vector2(350, 45)
	_phase_announcer_label.add_theme_font_override("font", FONT_TITLE)
	_phase_announcer_label.add_theme_font_size_override("font_size", 38)
	_phase_announcer_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
	_phase_announcer_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_phase_announcer_label.add_theme_constant_override("shadow_offset_x", 2)
	_phase_announcer_label.add_theme_constant_override("shadow_offset_y", 2)
	_phase_announcer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_announcer_label.modulate.a = 0.0
	_phase_announcer_label.z_index = 200
	_main.add_child(_phase_announcer_label)


func show_phase_announcement(phase_name: String) -> void:
	"""Anima el texto de la fase en el centro de la pantalla."""
	if not _phase_announcer_label:
		return
	if _phase_announcer_tween and _phase_announcer_tween.is_valid():
		_phase_announcer_tween.kill()

	_phase_announcer_label.text = phase_name
	_phase_announcer_label.scale = Vector2(1.2, 1.2)
	_phase_announcer_label.modulate.a = 0.0

	_phase_announcer_tween = _main.create_tween()
	_phase_announcer_tween.tween_property(_phase_announcer_label, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_phase_announcer_tween.parallel().tween_property(_phase_announcer_label, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_phase_announcer_tween.tween_interval(1.1)
	_phase_announcer_tween.tween_property(_phase_announcer_label, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_phase_announcer_tween.parallel().tween_property(_phase_announcer_label, "scale", Vector2(0.9, 0.9), 0.30).set_ease(Tween.EASE_IN)


# =============================================================================
# BOTÓN DE ACCIÓN / PASO FANTASÍA
# =============================================================================
func _create_paso_style(tex: Texture2D) -> StyleBoxTexture:
	var sb = StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 75.0
	sb.texture_margin_right = 75.0
	sb.texture_margin_top = 10.0
	sb.texture_margin_bottom = 10.0
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 6.0
	return sb


func _setup_paso_button() -> void:
	"""Crea el botón ornamental de acción a la derecha de la pantalla."""
	# Ocultar el contador de tiempo (TurnTimer) por ahora a petición del usuario
	var turn_timer = _main.get_node_or_null("TurnTimer")
	if turn_timer:
		turn_timer.visible = false

	_style_normal = _create_paso_style(TEX_BTN_NORMAL)
	_style_hover = _create_paso_style(TEX_BTN_HOVER)
	_style_pressed = _create_paso_style(TEX_BTN_PRESSED)
	_style_disabled = _create_paso_style(TEX_BTN_DISABLED)

	_paso_button = Button.new()
	_paso_button.text = _get_paso_label("Pasar")
	_paso_button.name = "PasoButton"
	_paso_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_paso_button.add_theme_font_override("font", FONT_TITLE)
	_paso_button.add_theme_font_size_override("font_size", 15)

	_paso_button.add_theme_stylebox_override("normal", _style_normal)
	_paso_button.add_theme_stylebox_override("hover", _style_hover)
	_paso_button.add_theme_stylebox_override("pressed", _style_pressed)
	_paso_button.add_theme_stylebox_override("focus", _style_hover)
	_paso_button.add_theme_stylebox_override("disabled", _style_disabled)
	_paso_button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84, 1.0))
	_paso_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.95, 1.0))
	_paso_button.add_theme_color_override("font_pressed_color", Color(0.85, 0.76, 0.55, 1.0))
	_paso_button.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.48, 0.75))
	_paso_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	_paso_button.add_theme_constant_override("outline_size", 2)
	_paso_button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.98))
	_paso_button.add_theme_constant_override("shadow_offset_x", 1)
	_paso_button.add_theme_constant_override("shadow_offset_y", 2)

	# Posición: alineado al margen derecho de la pantalla (290x46 px diegético de hierro forjado y bronce)
	_paso_button.anchor_left = 1.0
	_paso_button.anchor_top = 0.5
	_paso_button.anchor_right = 1.0
	_paso_button.anchor_bottom = 0.5
	_paso_button.offset_right = -20
	_paso_button.offset_left = -310
	_paso_button.offset_top = -23
	_paso_button.offset_bottom = 23
	_paso_button.pivot_offset = Vector2(145, 23)
	_paso_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_paso_button.visible = false

	# Sombra 3D proyectada bajo el botón de paso para despegarlo físicamente del tablero
	var shadow := Panel.new()
	shadow.name = "PasoButtonShadow"
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.offset_left = 6.0
	shadow.offset_top = 6.0
	shadow.offset_right = -6.0
	shadow.offset_bottom = -2.0

	var sb_shadow := StyleBoxFlat.new()
	sb_shadow.bg_color = Color(0, 0, 0, 0)
	sb_shadow.set_corner_radius_all(12)
	sb_shadow.shadow_color = Color(0, 0, 0, 0.88)
	sb_shadow.shadow_size = 18
	sb_shadow.shadow_offset = Vector2(0, 8)
	shadow.add_theme_stylebox_override("panel", sb_shadow)
	_paso_button.add_child(shadow)

	_main.add_child(_paso_button)
	_paso_button.pressed.connect(func(): _main._phase_flow._on_paso_pressed())

	# Respuesta táctil y elevación 3D al interactuar con el cursor
	_paso_button.mouse_entered.connect(func():
		var tw = _paso_button.create_tween().set_parallel(true)
		tw.tween_property(_paso_button, "scale", Vector2(1.025, 1.025), 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(sb_shadow, "shadow_size", 22, 0.12)
		tw.tween_property(sb_shadow, "shadow_offset", Vector2(0, 10), 0.12)
	)
	_paso_button.mouse_exited.connect(func():
		var tw = _paso_button.create_tween().set_parallel(true)
		tw.tween_property(_paso_button, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(sb_shadow, "shadow_size", 18, 0.12)
		tw.tween_property(sb_shadow, "shadow_offset", Vector2(0, 8), 0.12)
	)
	_paso_button.button_down.connect(func():
		var tw = _paso_button.create_tween().set_parallel(true)
		tw.tween_property(_paso_button, "scale", Vector2(0.985, 0.985), 0.06).set_ease(Tween.EASE_OUT)
		tw.tween_property(sb_shadow, "shadow_size", 8, 0.06)
		tw.tween_property(sb_shadow, "shadow_offset", Vector2(0, 3), 0.06)
	)
	_paso_button.button_up.connect(func():
		var tw = _paso_button.create_tween().set_parallel(true)
		var is_hov = _paso_button.is_hovered()
		var target_scale = Vector2(1.025, 1.025) if is_hov else Vector2.ONE
		var target_size = 22 if is_hov else 18
		var target_offset = Vector2(0, 10) if is_hov else Vector2(0, 8)
		tw.tween_property(_paso_button, "scale", target_scale, 0.10).set_ease(Tween.EASE_OUT)
		tw.tween_property(sb_shadow, "shadow_size", target_size, 0.10)
		tw.tween_property(sb_shadow, "shadow_offset", target_offset, 0.10)
	)

	if not GameSettings.keybindings_changed.is_connected(_on_keybindings_changed):
		GameSettings.keybindings_changed.connect(_on_keybindings_changed)


func _get_paso_label(prefix: String) -> String:
	var key_code: int = GameSettings.get_key("pasar")
	var key_str: String = GameSettings.get_key_display_string(key_code)
	return "%s [%s]" % [prefix, key_str]


func _on_keybindings_changed() -> void:
	update_paso_button_state()


func update_paso_button_state() -> void:
	"""Muestra/oculta el botón según si es el turno del jugador en una fase accionable."""
	if not _paso_button:
		return
	var phase = GameManager.current_phase

	# Con ventana de prioridad activa (Bloqueo, Guerra de Talismanes, respuesta) actúa quien TIENE la
	# prioridad, no el dueño del turno (p.ej. el defensor recibe la prioridad primero en Guerra de
	# Talismanes, DAR 5.C3).
	if PriorityManager.priority_window_active:
		# Con una ventana de prioridad activa, _on_paso_pressed() solo pasa prioridad
		# (PriorityManager.pass_priority()) en cualquier fase, así que el texto dice eso aunque sea tu
		# Vigilia: el botón dice lo que el click va a hacer.
		_paso_button.text = _get_paso_label("Pasar")
		_paso_button.visible = GameManager.is_game_active and PriorityManager.current_priority_player == 0
		# Diagnóstico: imprime el estado detrás de mostrar/ocultar el botón.
		if Constants.VERBOSE_DIAG_LOGS:
			print("[DIAG] update_paso_button_state (con ventana activa): visible=%s is_game_active=%s priority_player=%d fase=%s" % [
				str(_paso_button.visible), str(GameManager.is_game_active), PriorityManager.current_priority_player,
				Constants.PHASE_NAMES.get(phase, "?")
			])
		return

	# En Guerra de Talismanes/Bloqueo el botón queda visible sea de quien sea el turno: sin ventana
	# activa, _on_paso_pressed() llama _try_recover_stuck_phase_priority_window()
	# (PhaseFlowController.gd); si no hay nada que recuperar, avisa "Sin ventana de prioridad activa".
	# active_player_id no sirve aquí: al defender, la prioridad te toca primero (DAR 5.C3).
	# En Guerra de Talismanes (5.3.3) el botón dice "Daño": que ambos pasen seguido lleva a Asignación
	# de Daño (5.3.4), como en Vigilia dice "Atacar".
	if phase == Constants.Phase.GUERRA_TALISMANES:
		_paso_button.text = _get_paso_label("Daño")
	else:
		_paso_button.text = _get_paso_label("Pasar")
		if phase == Constants.Phase.VIGILIA:
			# Sin ningún Aliado que pueda atacar: "Fase Final".
			_paso_button.text = _get_paso_label("Atacar") if TurnManager.player_can_attack(GameManager.active_player_id) \
				else _get_paso_label("Fase Final")

	var is_player_turn = (GameManager.active_player_id == 0)
	var relevant_phase = phase in [
		Constants.Phase.VIGILIA,
		Constants.Phase.ATAQUE,
		Constants.Phase.FINAL
	]
	var recoverable_stuck_phase = phase in [
		Constants.Phase.GUERRA_TALISMANES,
		Constants.Phase.BLOQUEO
	]
	_paso_button.visible = GameManager.is_game_active and \
		((is_player_turn and relevant_phase) or recoverable_stuck_phase)
	if Constants.VERBOSE_DIAG_LOGS:
		print("[DIAG] update_paso_button_state (sin ventana activa): visible=%s is_game_active=%s is_player_turn=%s fase=%s relevant_phase=%s recoverable_stuck_phase=%s" % [
			str(_paso_button.visible), str(GameManager.is_game_active), str(is_player_turn),
			Constants.PHASE_NAMES.get(phase, "?"), str(relevant_phase), str(recoverable_stuck_phase)
		])


func hide_paso_button() -> void:
	if _paso_button:
		_paso_button.visible = false


func is_paso_button_ready() -> bool:
	"""¿El botón ¿Paso?/Atacar está visible y puede clickearse ahora?: atajo de teclado Q — simula el
	mismo click que el mouse, así que solo debe actuar cuando el botón real haría algo"""
	return _paso_button != null and _paso_button.visible


func start_paso_glow() -> void:
	"""Activa el estilo hover para indicar ventana de respuesta activa sin destellos ni cambios de color molestos."""
	if not _paso_button:
		return
	if _paso_glow_tween and _paso_glow_tween.is_valid():
		_paso_glow_tween.kill()
	_paso_glow_tween = null
	_paso_button.modulate = Color.WHITE

	if _style_hover:
		_paso_button.add_theme_stylebox_override("normal", _style_hover)
	_paso_button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.95, 1.0))


func stop_paso_glow() -> void:
	"""Restaura el estilo normal del botón."""
	if _paso_glow_tween and _paso_glow_tween.is_valid():
		_paso_glow_tween.kill()
	_paso_glow_tween = null
	if not _paso_button:
		return
	_paso_button.modulate = Color.WHITE

	if _style_normal:
		_paso_button.add_theme_stylebox_override("normal", _style_normal)
	_paso_button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84, 1.0))


# =============================================================================
# CUENTA REGRESIVA Y CONTROL EXTERNO DEL BOTÓN (online)
# =============================================================================
func start_paso_countdown(_seconds: int) -> void:
	"""Muestra los segundos que quedan para responder en el texto del botón.
	Desactivado temporalmente a petición del usuario."""
	return


func stop_paso_countdown() -> void:
	_countdown_generation += 1


func show_paso_button_with_text(text: String, glow: bool) -> void:
	"""Para el cliente Remoto, que no corre GameManager propio y por lo tanto
	nunca pasa por update_paso_button_state(): RemoteMirrorController decide
	el texto y la visibilidad según lo que le manda el Anfitrión."""
	if not _paso_button:
		return
	stop_paso_countdown()
	_paso_button.text = text
	_paso_button.visible = true
	if glow:
		start_paso_glow()
	else:
		stop_paso_glow()
