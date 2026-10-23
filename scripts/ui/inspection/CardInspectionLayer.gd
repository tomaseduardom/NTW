class_name CardInspectionLayer
extends Node

const CardScene = preload("res://scenes/cards/Card.tscn")
const TurnLimits = preload("res://scripts/core/effects/mechanics/TurnLimits.gd")
const TriggerTollScript = preload("res://scripts/core/effects/triggers/TriggerTollPatterns.gd")  # jose miguel carrera, capitan daisuke

# Manejadores de patrones especiales separados de este archivo (como
# BernardoAbilityHandler/ResponseWindowHandler). preload() en vez del class_name global: un editor
# abierto desde antes de crear la clase falla con "Could not find type".
const SearchAbilityHandlerScript = preload("res://scripts/ui/inspection/SearchAbilityHandler.gd")
const PreventionAbilityHandlerScript = preload("res://scripts/ui/inspection/PreventionAbilityHandler.gd")
const HandCementerioAbilityHandlerScript = preload("res://scripts/ui/inspection/HandCementerioAbilityHandler.gd")

# Validación de habilidades activadas + ciclo de vida del botón superpuesto, y los 4 grupos del
# if-chain de patrones especiales de _build_ability_buttons(). preload() por el mismo motivo.
const AbilityButtonSupportScript = preload("res://scripts/ui/inspection/AbilityButtonSupport.gd")
const AbilityButtonPatternsAScript = preload("res://scripts/ui/inspection/AbilityButtonPatternsA.gd")
const AbilityButtonPatternsBScript = preload("res://scripts/ui/inspection/AbilityButtonPatternsB.gd")
const AbilityButtonPatternsCScript = preload("res://scripts/ui/inspection/AbilityButtonPatternsC.gd")
const AbilityButtonPatternsDScript = preload("res://scripts/ui/inspection/AbilityButtonPatternsD.gd")

# Caja de texto de habilidades en el arte impreso de la carta:
# Margen lateral simétrico para centrar perfectamente el botón cubriendo todo el ancho de texto (sin recortar ni esquivar sellos).
const ABILITY_TEXT_SIDE_MARGIN := 9.5  ## Margen lateral simétrico para centrar perfectamente el botón cubriendo todo el texto
const ABILITY_TEXT_TOP_RATIO := 0.758  ## Ratio base del inicio del texto en la carta física (desplazado hacia arriba para dar respiro sobre la primera línea)
const ABILITY_TEXT_BOTTOM_RATIO := 0.932  ## Base inferior de la caja de texto en la carta física
const ABILITY_SEPARATION_GAP := 2.0  ## Separación vertical limpia (en unidades de carta) entre botones contiguos para evitar solapamientos
const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")


var _main: Node = null

var inspected_card: Node = null
var _ability_buttons_panel: Control = null
var _gained_abilities_panel: Control = null
var _inspected_source_card: Node = null
## Se incrementa cada vez que algo agrega contenido visible a _main.inspection_layer
## (una inspección nueva, el diálogo de elección de Bernardo, etc.) — ver
## close_card_inspection() y mark_inspection_layer_in_use().
var _inspection_layer_generation: int = 0
var _bernardo: BernardoAbilityHandler
var _response_window: ResponseWindowHandler
var _search_handler: RefCounted
var _prevention_handler: RefCounted
var _hand_cementerio_handler: RefCounted
var _button_support: RefCounted
var _pattern_group_a: RefCounted
var _pattern_group_b: RefCounted
var _pattern_group_c: RefCounted
var _pattern_group_d: RefCounted


func setup(main: Node) -> void:
	_main = main
	_bernardo = BernardoAbilityHandler.new()
	_bernardo.setup(self)
	_response_window = ResponseWindowHandler.new()
	_response_window.setup(self)
	_search_handler = SearchAbilityHandlerScript.new()
	_search_handler.setup(self)
	_prevention_handler = PreventionAbilityHandlerScript.new()
	_prevention_handler.setup(self)
	_hand_cementerio_handler = HandCementerioAbilityHandlerScript.new()
	_hand_cementerio_handler.setup(self)
	_button_support = AbilityButtonSupportScript.new()
	_button_support.setup(self)
	_pattern_group_a = AbilityButtonPatternsAScript.new()
	_pattern_group_a.setup(self)
	_pattern_group_b = AbilityButtonPatternsBScript.new()
	_pattern_group_b.setup(self)
	_pattern_group_c = AbilityButtonPatternsCScript.new()
	_pattern_group_c.setup(self)
	_pattern_group_d = AbilityButtonPatternsDScript.new()
	_pattern_group_d.setup(self)
	if not ActionPipeline.step_d_waiting.is_connected(_response_window._on_step_d_waiting):
		ActionPipeline.step_d_waiting.connect(_response_window._on_step_d_waiting)
	if not ActionPipeline.stack_object_resolved.is_connected(_button_support._on_ability_glow_resolved):
		ActionPipeline.stack_object_resolved.connect(_button_support._on_ability_glow_resolved)

	if not PriorityManager.priority_changed.is_connected(_on_priority_changed_refresh_glows):
		PriorityManager.priority_changed.connect(_on_priority_changed_refresh_glows)

	# Signo Amarillo: ventana de respuesta para triggers de entrada de Oro / fuera del juego, separada
	# de step_d_waiting (la Pila de habilidades activadas y cartas jugadas).
	if not TriggerSystem.waiting_for_responses.is_connected(_response_window._on_trigger_waiting_for_responses):
		TriggerSystem.waiting_for_responses.connect(_response_window._on_trigger_waiting_for_responses)


func _on_priority_changed_refresh_glows(_player_id: int) -> void:
	refresh_activatable_glows()


# =============================================================================
# INDICADOR PASIVO DE HABILIDAD ACTIVABLE (brillo celeste)
# =============================================================================
func refresh_activatable_glows() -> bool:
	"""Prende/apaga el brillo celeste de "tiene una habilidad activable ahora" en cada carta del
	humano en juego, sin abrir la inspección. Misma detección y validación que
	_build_ability_buttons()/_validate_ability(). Devuelve true si quedó al menos una carta
	brillando (§10.52)."""
	if not _main:
		return false

	# Mismo criterio que _build_ability_buttons() (§10.11 caso 4 / §10.51): en turno rival el brillo
	# solo aplica a Anular/Cancelar.
	var is_own_turn: bool = GameManager.active_player_id == 0
	if not GameManager.is_game_active:
		_clear_all_activatable_glows()
		return false
	if not is_own_turn and not (PriorityManager.priority_window_active and PriorityManager.can_act(0)):
		_clear_all_activatable_glows()
		return false

	var in_vigilia = GameManager.current_phase == Constants.Phase.VIGILIA
	var has_priority_window = PriorityManager.priority_window_active and PriorityManager.can_act(0)
	if not in_vigilia and not has_priority_window:
		_clear_all_activatable_glows()
		return false

	var candidates: Array = []
	if _main.player_field:
		candidates.append_array(_main.player_field.get_children())
	if _main.player_linea_ataque:
		candidates.append_array(_main.player_linea_ataque.get_children())
	if _main.player_gold:
		candidates.append_array(_main.player_gold.get_children())

	# Armas equipadas: son hijas del Aliado portador (no de player_field/player_linea_ataque), así que
	# se recorren aparte. Su habilidad vive en el nodo del Arma, ajena al silencio del portador.
	var weapon_candidates: Array = []
	for ally in candidates:
		if not is_instance_valid(ally):
			continue
		var weapons = ally.get("equipped_weapons")
		if weapons is Array:
			for w in weapons:
				if is_instance_valid(w):
					weapon_candidates.append(w)
	candidates.append_array(weapon_candidates)

	var any_glowing := false
	for card in candidates:
		if not (card is Card) or not is_instance_valid(card):
			continue
		if card.get("card_data") == null:
			continue
		var habilidad_text: String = card.card_data.get("habilidad", "")
		if habilidad_text.is_empty():
			card.set_activatable(false)
			continue
		var card_id: String = str(card.card_data.get("id", ""))
		var all_parsed := UniversalCardParser.parse_abilities(habilidad_text, card_id)
		var abilities: Array = all_parsed.filter(func(a): return a.get("ability_type", "") == "ACTIVATED")
		var can_activate_any := false
		for ability in abilities:
			var ability_raw_text: String = str(ability.get("raw_text", ""))
			# Turno rival (§10.51, mismo criterio que _build_ability_buttons()):
			# solo Anular/Cancelar sin restricción de 'en tu turno' cuenta como
			# respuesta instantánea real aquí.
			if not is_own_turn:
				var ability_lower := ability_raw_text.to_lower()
				if "en tu turno" in ability_lower or not _button_support._is_annul_or_cancel_ability(ability_raw_text):
					continue
			# Estas cartas están en juego: una habilidad "de tu mano" / "de tu Cementerio" sin "en juego" no
			# aplica aquí (mismo filtro que _build_ability_buttons()).
			if _ability_is_hand_or_cementerio_only(ability_raw_text):
				continue
			if _button_support._validate_ability(ability, card).get("can", false):
				can_activate_any = true
				break
		card.set_activatable(can_activate_any)
		if can_activate_any:
			any_glowing = true
	return any_glowing


func _clear_all_activatable_glows() -> void:
	if not _main:
		return
	for container in [_main.player_field, _main.player_linea_ataque, _main.player_gold]:
		if not container:
			continue
		for card in container.get_children():
			if card is Card:
				card.set_activatable(false)


func on_card_right_clicked(card: Node) -> void:
	if card.esta_oculta:
		return
	_open_card_inspection(card)


func _open_card_inspection(card: Node) -> void:
	# Si ya hay otra inspección abierta, se cierra en vez de ignorar el click nuevo.
	if inspected_card:
		close_card_inspection()
	_inspected_source_card = card
	inspected_card = CardScene.instantiate()
	# Habilidades ganadas (Reina Nyssara): la carta se ve con su texto
	# impreso; lo ganado va en el panel de la derecha.
	var shown_data: Dictionary = card.card_data
	if card.card_data.has("_base_habilidad"):
		shown_data = card.card_data.duplicate()
		shown_data["habilidad"] = card.card_data["_base_habilidad"]
	inspected_card.load_from_data(shown_data)
	inspected_card.can_interact = false
	inspected_card.esta_oculta = card.esta_oculta
	inspected_card.current_state = Card.CardState.IN_PLAY
	inspected_card.scale = Vector2(0.1, 0.1)
	inspected_card.modulate.a = 0.0
	_main.inspection_container.add_child(inspected_card)
	inspected_card.pivot_offset = inspected_card.custom_minimum_size / 2.0
	inspected_card.rotation_degrees = 0.0
	# El clon no tiene la zona/dueño reales de 'card', así que sus badges quedan con el valor base: se
	# recalculan con el contexto de la carta real (p.ej. Manuel Bulnes).
	inspected_card.refresh_strength_badge(card)
	inspected_card.refresh_cost_badge(card)
	mark_inspection_layer_in_use()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(inspected_card, "scale", Vector2(3.2, 3.2), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(inspected_card, "modulate:a", 1.0, 0.2)
	tween.chain().tween_callback(_build_ability_buttons.bind(card))
	tween.chain().tween_callback(_build_gained_abilities_panel.bind(card))
	if not _main.inspection_blur.gui_input.is_connected(_on_inspection_blur_input):
		_main.inspection_blur.gui_input.connect(_on_inspection_blur_input)
	if not inspected_card.gui_input.is_connected(_on_inspection_blur_input):
		inspected_card.gui_input.connect(_on_inspection_blur_input)


func _build_gained_abilities_panel(source_card: Node) -> void:
	"""Habilidades ganadas de otras cartas (Reina Nyssara: 'gana las habilidades de esa carta'),
	mostradas a la derecha de la carta inspeccionada con resolución nativa HD y diseño medieval diegético."""
	if not is_instance_valid(inspected_card) or not is_instance_valid(source_card):
		return
	if _gained_abilities_panel and is_instance_valid(_gained_abilities_panel):
		_gained_abilities_panel.queue_free()
		_gained_abilities_panel = null

	var gained: Array = source_card.card_data.get("_gained_abilities", [])
	if gained.is_empty():
		return

	# Calcular posición en coordenadas de pantalla relativas a la carta inspeccionada
	var center: Vector2 = inspected_card.global_position + inspected_card.pivot_offset
	var visual_right: float = center.x + (inspected_card.size.x * inspected_card.scale.x) * 0.5
	var visual_top: float = center.y - (inspected_card.size.y * inspected_card.scale.y) * 0.5

	var viewport_w: float = 1920.0
	if _main and _main.inspection_layer and _main.inspection_layer.get_viewport():
		viewport_w = _main.inspection_layer.get_viewport().get_visible_rect().size.x

	var target_x: float = visual_right + 24.0
	var panel_w: float = minf(460.0, maxf(280.0, viewport_w - target_x - 30.0))

	var container := VBoxContainer.new()
	container.name = "GainedAbilitiesContainer"
	container.position = Vector2(target_x + 16.0, visual_top)
	container.custom_minimum_size = Vector2(panel_w, 0.0)
	container.add_theme_constant_override("separation", 14)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.modulate.a = 0.0

	_main.inspection_layer.add_child(container)
	_gained_abilities_panel = container

	var base_lower: String = str(source_card.card_data.get("_base_habilidad", "")).to_lower()
	var usable: Array = usable_abilities_for(source_card, 0)

	for g in gained:
		var text: String = str(g.get("text", "")).strip_edges()
		var card_source_name: String = str(g.get("from", "otra carta")).strip_edges()

		var block := PanelContainer.new()
		block.mouse_filter = Control.MOUSE_FILTER_STOP

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.08, 0.12, 0.96)
		sb.border_color = Color(0.85, 0.72, 0.36, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.8)
		sb.shadow_size = 20
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 16.0
		sb.content_margin_bottom = 16.0
		block.add_theme_stylebox_override("panel", sb)
		container.add_child(block)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		block.add_child(col)

		var title := Label.new()
		title.text = "HABILIDAD DE %s" % card_source_name.to_upper()
		title.add_theme_font_override("font", FONT_TITLE)
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
		title.add_theme_constant_override("outline_size", 2)
		title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		title.add_theme_constant_override("shadow_offset_x", 1)
		title.add_theme_constant_override("shadow_offset_y", 2)
		col.add_child(title)

		var divider := ColorRect.new()
		divider.custom_minimum_size = Vector2(0.0, 1.5)
		divider.color = Color(0.85, 0.72, 0.36, 0.4)
		col.add_child(divider)

		var body := Label.new()
		body.text = text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(panel_w - 36.0, 0.0)
		body.add_theme_font_override("font", FONT_BODY)
		body.add_theme_font_size_override("font_size", 15)
		body.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90, 1.0))
		body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		body.add_theme_constant_override("shadow_offset_x", 1)
		body.add_theme_constant_override("shadow_offset_y", 1)
		body.add_theme_constant_override("line_spacing", 4)
		col.add_child(body)

		var text_lower := text.to_lower()
		for entry in usable:
			var ability: Dictionary = entry.ability
			var raw: String = str(ability.get("raw_text", "")).to_lower().strip_edges()
			var probe: String = raw.substr(0, 24)
			if probe.is_empty() or not (probe in text_lower) or probe in base_lower:
				continue
			var btn := Button.new()
			btn.text = "USAR HABILIDAD"
			btn.custom_minimum_size = Vector2(0.0, 36.0)
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			btn.add_theme_font_override("font", FONT_TITLE)
			btn.add_theme_font_size_override("font_size", 13)

			var btn_n := StyleBoxFlat.new()
			btn_n.bg_color = Color(0.12, 0.16, 0.22, 0.96)
			btn_n.border_color = Color(0.75, 0.62, 0.35, 0.90)
			btn_n.set_border_width_all(1)
			btn_n.set_corner_radius_all(4)
			btn_n.content_margin_left = 12.0
			btn_n.content_margin_right = 12.0
			btn_n.content_margin_top = 4.0
			btn_n.content_margin_bottom = 4.0

			var btn_h := btn_n.duplicate() as StyleBoxFlat
			btn_h.bg_color = Color(0.18, 0.25, 0.35, 1.0)
			btn_h.border_color = Color(1.0, 0.88, 0.45, 1.0)
			btn_h.set_border_width_all(2)

			var btn_p := btn_n.duplicate() as StyleBoxFlat
			btn_p.bg_color = Color(0.08, 0.10, 0.14, 1.0)
			btn_p.border_color = Color(0.60, 0.50, 0.25, 1.0)

			btn.add_theme_stylebox_override("normal", btn_n)
			btn.add_theme_stylebox_override("hover", btn_h)
			btn.add_theme_stylebox_override("pressed", btn_p)
			btn.add_theme_stylebox_override("focus", btn_h)
			btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.95, 1.0))
			btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
			btn.add_theme_constant_override("outline_size", 1)
			btn.tooltip_text = str(ability.get("raw_text", ""))

			var captured: Dictionary = ability.duplicate()
			btn.pressed.connect(func():
				close_card_inspection()
				if not await TriggerTollScript.pay_toll(source_card, 0, TriggerTollScript.ability_toll(source_card, 0)):
					return
				RuleState.add("abilities_used", 0)  # anillo de tierra
				await _button_support._activate_ability_via_pipeline(source_card, source_card.card_data.duplicate(), captured,
					{"controller_id": 0, "source_card_node": source_card}))
			col.add_child(btn)

	var tw = container.create_tween().set_parallel(true)
	tw.tween_property(container, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(container, "position:x", target_x, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_inspection_blur_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_card_inspection()


func inspect_card_data(card_data: Dictionary) -> void:
	"""Abre la ventana de inspección de una carta a partir de sus datos (p. ej. desde el Action Log)."""
	if card_data.is_empty():
		return
	if inspected_card:
		close_card_inspection()
	_inspected_source_card = null
	inspected_card = CardScene.instantiate()
	inspected_card.load_from_data(card_data)
	inspected_card.can_interact = false
	inspected_card.esta_oculta = false
	inspected_card.current_state = Card.CardState.IN_PLAY
	inspected_card.scale = Vector2(0.1, 0.1)
	inspected_card.modulate.a = 0.0
	_main.inspection_container.add_child(inspected_card)
	inspected_card.pivot_offset = inspected_card.custom_minimum_size / 2.0
	inspected_card.rotation_degrees = 0.0
	mark_inspection_layer_in_use()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(inspected_card, "scale", Vector2(3.2, 3.2), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(inspected_card, "modulate:a", 1.0, 0.2)
	if not _main.inspection_blur.gui_input.is_connected(_on_inspection_blur_input):
		_main.inspection_blur.gui_input.connect(_on_inspection_blur_input)
	if not inspected_card.gui_input.is_connected(_on_inspection_blur_input):
		inspected_card.gui_input.connect(_on_inspection_blur_input)


func inspect_card_by_name(card_name: String) -> bool:
	"""Busca una carta por nombre en CardDatabase e inicia su inspección si existe."""
	var clean_name = card_name.strip_edges()
	var data = CardDatabase.get_card_by_name(clean_name)
	if data.is_empty():
		for k in CardDatabase.cards_by_name.keys():
			if str(k).to_lower() == clean_name.to_lower():
				data = CardDatabase.cards_by_name[k]
				break
	if not data.is_empty():
		inspect_card_data(data)
		return true
	print("[CardInspectionLayer] No se encontró carta con nombre: '%s'" % clean_name)
	return false


func mark_inspection_layer_in_use() -> void:
	"""Llamar siempre que algo agregue contenido visible a _main.inspection_layer (una inspección, el
	diálogo de Bernardo en BernardoAbilityHandler.gd, cualquier overlay que la reuse). El cierre
	diferido de close_card_inspection() (~0.2 s de tween) puede apagar la capa después de agregado
	el diálogo: visible = true aquí cubre el apagón ya ocurrido y el contador de generación de
	close_card_inspection() el posterior."""
	_inspection_layer_generation += 1
	_main.inspection_layer.visible = true


func release_inspection_layer_if_unused() -> void:
	"""Contraparte de mark_inspection_layer_in_use(): llamar cuando el contenido que forzó visible =
	true ya se usó y no queda una inspección real abierta. Si no, el blur de pantalla completa
	(mouse_filter STOP) queda tapando y tragándose los clicks (p.ej. Bernardo al elegir Desterrar).
	No apaga la capa si se abrió una inspección nueva (inspected_card != null), como
	close_card_inspection()."""
	if not inspected_card:
		_main.inspection_layer.visible = false


func close_card_inspection() -> void:
	if not inspected_card:
		return
	if _ability_buttons_panel and is_instance_valid(_ability_buttons_panel):
		_ability_buttons_panel.queue_free()
		_ability_buttons_panel = null
	if _gained_abilities_panel and is_instance_valid(_gained_abilities_panel):
		var panel_to_remove = _gained_abilities_panel
		_gained_abilities_panel = null
		var p_tween = create_tween()
		p_tween.tween_property(panel_to_remove, "modulate:a", 0.0, 0.15)
		p_tween.tween_callback(panel_to_remove.queue_free)
	_inspected_source_card = null
	var card_to_remove = inspected_card
	inspected_card = null
	var my_generation: int = _inspection_layer_generation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_to_remove, "scale", Vector2(0.1, 0.1), 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card_to_remove, "modulate:a", 0.0, 0.15)
	await tween.finished
	card_to_remove.queue_free()
	# No apagar la capa si mientras tanto se abrió una inspección NUEVA
	# (llamada sin await desde _open_card_inspection(), ver comentario de
	# arriba) O cualquier otro contenido que haya llamado a
	# mark_inspection_layer_in_use() (p.ej. el diálogo de Bernardo) —
	# apagarla incondicionalmente ocultaba ese contenido nuevo ~0.2s
	# después de agregado.
	if not inspected_card and _inspection_layer_generation == my_generation:
		_main.inspection_layer.visible = false


func _ability_is_hand_usable(full_text: String) -> bool:
	"""Lista chica y explícita de habilidades usables desde la mano: la sola presencia de "tu mano" en
	el texto no basta (ver _build_ability_buttons())."""
	var lower := full_text.to_lower()
	if "desterrarlo de tu mano o en juego" in lower:
		return true  # Ramón Freire
	if "esta y otra carta de tu mano" in lower and "fondo de tu castillo" in lower:
		return true  # Tyet
	if "desterrarlo de tu mano o cementerio" in lower:
		return true  # Drácula
	if "desterrar esta carta de tu mano para anular" in lower:
		return true  # Espada Vikinga
	if "barajar esta carta desde tu mano" in lower:
		return true  # Sacrificio Solar
	if "ponerlo en el fondo de tu castillo para reducir a cero el próximo daño" in lower:
		return true  # Piruquina
	if "puedes barajarla de tu mano para buscar un oro en tu castillo" in lower:
		return true  # skofnung
	if "puedes pagar un oro para desterrar este y otro aliado sacerdote de tu mano" in lower:
		return true  # sandraudiga
	# Coste = descartar esta carta / desterrarla de la mano (basan, lurulu, Jafet, pablo pincheira):
	# EffectCompiler.COST_PIECES self_discard / self_banish.
	if "puedes descartarlo para" in lower or "puedes descartarla para" in lower \
			or "desterrarlo de tu mano" in lower or "desterrarla de tu mano" in lower:
		return true
	return false


func _ability_is_cementerio_usable(full_text: String) -> bool:
	"""Lista chica y explícita de habilidades usables desde el Cementerio (p.ej. Espada del Juicio:
	"Puedes Desterrarla de tu Cementerio para que un Aliado gane o pierda 2 de Fuerza
	permanentemente"). Mismo criterio que _ability_is_hand_usable()."""
	var lower := full_text.to_lower()
	if "desterrarla de tu cementerio" in lower or "desterrarlo de tu cementerio" in lower \
			or "desterrarlo desde tu cementerio" in lower or "desterrarla desde tu cementerio" in lower:
		return true  # Espada del Juicio, wani
	if "si está en tu cementerio y si tienes menos cartas en tu mano que tu oponente" in lower:
		return true  # Envidia
	if "en juego desde tu cementerio como un aliado sin habilidad" in lower:
		return true  # Alto Prime, Belta
	if "si está en tu cementerio, puedes desterrarlo para que un aliado gane" in lower:
		return true  # Ira
	if "para subir esta carta de tu cementerio a tu mano" in lower:
		return true  # vision heroica
	if "para subirlo de tu cementerio a tu mano" in lower or "para subirla de tu cementerio a tu mano" in lower \
			or "para subir esta arma de tu cementerio a tu mano" in lower:
		return true  # Belial, voces de hielo, sai (EffectCompiler self_raise)
	if "desterrarlo de tu mano o cementerio" in lower:
		return true  # Drácula
	if "en tu cementerio" in lower and "gana la habilidad" in lower:
		return true  # Duelo Espacial (habilidad que gana en el Cementerio)
	return false


func _ability_is_destierro_usable(full_text: String) -> bool:
	"""Habilidades usables desde el Destierro propio (mismo criterio que _ability_is_cementerio_usable())."""
	return "si está en tu destierro, puedes desterrar una carta de tu mano para barajarlo en tu castillo" in full_text.to_lower()  # sandraudiga


func _ability_is_hand_or_cementerio_only(full_text: String) -> bool:
	"""true si la habilidad está en _ability_is_hand_usable()/_ability_is_cementerio_usable() pero su
	texto no dice también "en juego": no aplica con la carta ya en juego. P.ej. Tyet ("esta y otra
	carta de tu mano en el fondo de tu Castillo": solo desde la mano) o la de cancelar ataque de
	Drácula ("de tu mano o Cementerio"). Ramón Freire dice "de tu mano o en juego", así que vale en
	ambas."""
	if not (_ability_is_hand_usable(full_text) or _ability_is_cementerio_usable(full_text) or _ability_is_destierro_usable(full_text)):
		return false
	return not ("en juego" in full_text.to_lower())


func activate_ability_for(source_card: Node, ability: Dictionary, controller_id: int) -> void:
	"""Activa una habilidad con la misma lógica que su botón en la inspección: los patrones especiales
	de AbilityButtonPatternsA-D (p.ej. Miguel) y, si ninguno aplica, la Pila genérica. Lo usa
	RemotePlayerController para que el Remoto vaya por el mismo camino. Los patrones conectan su
	lógica al 'pressed' de un botón: aquí se arma un botón sin mostrar y se espera esa función."""
	if not is_instance_valid(source_card):
		return
	# Recargo por utilizar la habilidad (jose miguel carrera, capitan daisuke): se paga antes.
	if not await TriggerTollScript.pay_toll(source_card, controller_id, TriggerTollScript.ability_toll(source_card, controller_id)):
		return
	RuleState.add("abilities_used", controller_id)  # anillo de tierra
	if not is_instance_valid(source_card):
		return
	if not (source_card.get("current_zone") in Constants.ZONES_IN_PLAY):
		TurnLimits.note_outside_ability(controller_id)  # Terminal P-12
	var captured: Dictionary = ability.duplicate()
	var captured_card_data: Dictionary = source_card.card_data.duplicate()
	var ability_lower: String = str(captured.get("raw_text", "")).to_lower()
	var btn := Button.new()
	var panel := Control.new()
	var handled := false
	for group in [_pattern_group_a, _pattern_group_b, _pattern_group_c, _pattern_group_d]:
		if group.try_build(ability_lower, btn, panel, source_card, captured):
			handled = true
			for conn in btn.pressed.get_connections():
				await conn.callable.call()
			break
	panel.queue_free()
	if not handled:
		var context := {"controller_id": controller_id, "source_card_node": source_card}
		await _button_support._activate_ability_via_pipeline(source_card, captured_card_data, captured, context)


func _is_response_only_ability(raw_text: String) -> bool:
	var lower := raw_text.to_lower()
	var at := lower.find(" para ")
	var effect: String = lower.substr(at + 6) if at >= 0 else lower
	# Cancelar un ataque (Drácula): no responde a nada de la pila, se usa en Guerra de Talismanes
	# mientras los Aliados atacan.
	if "cancelar el ataque" in effect:
		return false
	if not ("anular" in effect or "cancelar" in effect or "prevenir" in effect or "prevén" in effect):
		return false
	for other in ["destru", "desterr", "roba", "baraj", "busca", "gana", "pierd", "genera", "juega", "jugar", "pon "]:
		if other in effect:
			return false
	return true


func _responding_to_opponent(player_id: int) -> bool:
	return PriorityManager.priority_window_active and PriorityManager.current_priority_context == PriorityManager.PriorityContext.RESPONSE_WINDOW and PriorityManager.current_stack_controller == 1 - player_id


func usable_abilities_for(source_card: Node, player_id: int) -> Array:
	"""Habilidades activadas de esta carta que player_id puede usar ahora: [{ability, validation}].
	Mismo filtro que los botones de la inspección (turno, prioridad, zona, Anular/Cancelar en turno
	rival, costo, una vez por turno), parametrizado por jugador para que el Remoto vea las mismas
	opciones que el Anfitrión."""
	if not is_instance_valid(source_card):
		return []
	if not GameManager.is_game_active:
		return []
	# §10.11 caso 4: en tu turno cualquier habilidad activada puede mostrarse (validate_ability filtra
	# fase/costo). En turno rival, solo si hay una ventana de prioridad donde puedes actuar
	# (PriorityManager.can_act(player_id)); qué habilidad se filtra en el loop (is_own_turn).
	var is_own_turn: bool = GameManager.active_player_id == player_id
	if not is_own_turn and not (PriorityManager.priority_window_active and PriorityManager.can_act(player_id)):
		return []
	# controller_id, no owner_id: activa quien controla la carta (p.ej. una jugada por Miguel desde el
	# Cementerio rival).
	var source_controller_id: int = source_card.controller_id if source_card.get("controller_id") != null else -1
	if source_controller_id != player_id:
		return []

	# Solo cartas en juego activan habilidades (DAR), con excepciones explícitas por habilidad desde la
	# mano o el Cementerio (Ramón Freire, Tyet, Espada del Juicio). Aquí solo se decide si la zona es
	# una de las permitidas; cuál habilidad aplica se filtra en el loop con el raw_text de cada una
	# (Tyet tiene una usable desde la mano y otra solo desde la Reserva).
	var source_zone = source_card.get("current_zone")
	if source_zone == null:
		return []
	var in_play: bool = source_zone in Constants.ZONES_IN_PLAY
	if not in_play and not (source_zone in [Constants.Zone.MANO, Constants.Zone.CEMENTERIO, Constants.Zone.DESTIERRO]):
		return []
	# Terminal P-12: hasta dos habilidades de cartas fuera del juego por turno.
	if not in_play and not TurnLimits.outside_ability_allowed(player_id):
		return []
	# Silencio de Cementerio (Sable de Napoleón): "pierde su habilidad" bloquea también las habilidades
	# usables desde el Cementerio (p.ej. Espada del Juicio). Solo a cartas marcadas mientras están en
	# el Cementerio.
	if source_zone == Constants.Zone.CEMENTERIO and source_card.get("card_data") != null \
			and CardManager.is_cemetery_card_silenced(source_card.card_data):
		return []

	# Permitir en Vigilia O cuando hay ventana de prioridad activa
	var in_vigilia = GameManager.current_phase == Constants.Phase.VIGILIA
	var has_priority_window = PriorityManager.priority_window_active and PriorityManager.can_act(player_id)
	if not in_vigilia and not has_priority_window:
		return []

	# parse_abilities() es el Compilador Fase 1: detecta TRIGGER y ACTIVATED por Regex.
	# Solo mostramos botones para habilidades ACTIVATED (las que el jugador activa manualmente).
	var card_id: String = str(source_card.card_data.get("id", ""))
	var habilidad_text: String = source_card.card_data.get("habilidad", "")
	var all_parsed := UniversalCardParser.parse_abilities(habilidad_text, card_id)
	var abilities: Array = all_parsed.filter(func(a): return a.get("ability_type", "") == "ACTIVATED")

	# Solo se muestran las habilidades usables ahora mismo — las bloqueadas
	# (sin oro, ya usadas este turno, etc.) se ocultan en vez de listarse en gris.
	var usable_abilities: Array = []
	# Escritura Sagrada: jugar desde las dos primeras del Castillo.
	var escritura: Dictionary = load("res://scripts/core/effects/mechanics/CastleTopPlay.gd").escritura_synthetic_ability(
		source_card, player_id, all_parsed)
	if not escritura.is_empty():
		usable_abilities.append({"ability": escritura, "validation": {"can": true}})

	if abilities.is_empty():
		return usable_abilities
	for ability in abilities:
		var ability_raw_text: String = str(ability.get("raw_text", ""))
		# Turno rival (§10.11 caso 4): solo Anular/Cancelar son respuesta instantánea; el resto (p.ej.
		# "Paga 1 Oro: roba una carta") no tiene sentido como reacción. Excepción: "en tu turno,
		# puedes..." (Tótem Dragón Ancestral) es Anular/Cancelar pero solo en tu turno; el parser solo
		# marca once_per_turn_own_turn_only con "UNA VEZ en tu turno", así que se chequea aquí.
		# Guerra de Talismanes: los dos jugadores juegan Talismanes y usan habilidades (p.ej. Tyet,
		# Estaca), mientras la palabra sea de la Guerra y no de una ventana de respuesta puntual.
		var in_guerra: bool = GameManager.current_phase == Constants.Phase.GUERRA_TALISMANES and PriorityManager.current_priority_context == PriorityManager.PriorityContext.GUERRA_TALISMANES
		if not is_own_turn:
			var ability_lower := ability_raw_text.to_lower()
			if "en tu turno" in ability_lower or not (in_guerra or _button_support._is_annul_or_cancel_ability(ability_raw_text)):
				continue
		# Solo de respuesta (p.ej. Almirante Akari): si todo lo que hace es Anular/Cancelar/prevenir, el
		# botón aparece solo mientras respondes a algo del oponente (la prevención la ofrece el juego solo
		# cuando corresponde).
		if _is_response_only_ability(ability_raw_text) and not _responding_to_opponent(player_id):
			continue
		if not in_play:
			var zone_ok: bool = (source_zone == Constants.Zone.MANO and _ability_is_hand_usable(ability_raw_text)) \
				or (source_zone == Constants.Zone.CEMENTERIO and _ability_is_cementerio_usable(ability_raw_text)) \
				or (source_zone == Constants.Zone.DESTIERRO and _ability_is_destierro_usable(ability_raw_text))
			if not zone_ok:
				continue
		elif _ability_is_hand_or_cementerio_only(ability_raw_text):
			# Con la carta ya en juego, una habilidad que dice "de tu mano" / "de tu Cementerio" sin "o en
			# juego" (la primera de Tyet, cancelar ataque de Drácula) no aplica.
			continue
		var validation = _button_support._validate_ability(ability, source_card, player_id)
		if validation.get("can", false):
			usable_abilities.append({"ability": ability, "validation": validation})

	return usable_abilities


func _calculate_ability_line_offsets(habilidad_text: String, all_parsed: Array, card_size: Vector2, has_gained: bool) -> Dictionary:
	var paragraphs: PackedStringArray = habilidad_text.strip_edges().split("\n")
	var wrapped_lines: Array[String] = []
	var line_char_ranges: Array[Vector2i] = []
	var normalized_full: String = ""

	const MAX_CHARS_PER_LINE: int = 43

	for p in paragraphs:
		var p_str: String = p.strip_edges()
		if p_str.is_empty():
			continue
		var words: PackedStringArray = p_str.split(" ", false)
		var curr_line: Array[String] = []
		var curr_len: int = 0
		for w in words:
			var add_len: int = w.length() if curr_len == 0 else w.length() + 1
			if curr_len + add_len <= MAX_CHARS_PER_LINE:
				curr_line.append(w)
				curr_len += add_len
			else:
				var line_str: String = " ".join(curr_line)
				var start_c: int = normalized_full.length()
				normalized_full += line_str + "\n"
				var end_c: int = normalized_full.length()
				wrapped_lines.append(line_str)
				line_char_ranges.append(Vector2i(start_c, end_c))
				curr_line = [w]
				curr_len = w.length()
		if not curr_line.is_empty():
			var line_str: String = " ".join(curr_line)
			var start_c: int = normalized_full.length()
			normalized_full += line_str + "\n"
			var end_c: int = normalized_full.length()
			wrapped_lines.append(line_str)
			line_char_ranges.append(Vector2i(start_c, end_c))

	var total_lines: int = wrapped_lines.size()
	if total_lines <= 0:
		total_lines = 1

	# Ajuste adaptativo del inicio vertical de la caja de texto según cantidad total de líneas
	# Desplazado ligeramente hacia arriba para dar respiro visual exacto sobre la primera línea
	var top_ratio: float = 0.758
	if total_lines >= 8:
		top_ratio = 0.750
	elif total_lines >= 6:
		top_ratio = 0.758
	elif total_lines >= 4:
		top_ratio = 0.770
	else:
		top_ratio = 0.782

	var zone_top: float = card_size.y * top_ratio
	var zone_bottom: float = card_size.y * ABILITY_TEXT_BOTTOM_RATIO
	var zone_height: float = zone_bottom - zone_top
	var line_height_px: float = zone_height / float(total_lines)

	var norm_lower: String = normalized_full.to_lower()
	var offsets_by_index: Dictionary = {}

	for a in all_parsed:
		var raw_t: String = a.get("raw_text", "").strip_edges()
		var idx: int = a.get("ability_index", -1)
		var raw_lower: String = raw_t.to_lower()

		var chunk_start: String = raw_lower.substr(0, mini(24, raw_lower.length())).strip_edges()
		if has_gained and not (chunk_start in habilidad_text.to_lower()):
			continue

		var pos_start: int = norm_lower.find(chunk_start) if not chunk_start.is_empty() else -1
		if pos_start == -1 and raw_lower.length() > 12:
			chunk_start = raw_lower.substr(0, 14)
			pos_start = norm_lower.find(chunk_start)

		var chunk_end_len: int = mini(24, raw_lower.length())
		var chunk_end: String = raw_lower.substr(raw_lower.length() - chunk_end_len).strip_edges()
		var pos_end: int = -1
		if not chunk_end.is_empty() and pos_start != -1:
			pos_end = norm_lower.find(chunk_end, pos_start)
		if pos_end != -1:
			pos_end += chunk_end.length()
		elif pos_start != -1:
			pos_end = pos_start + raw_lower.length()

		var start_line: int = -1
		var end_line: int = -1

		if pos_start != -1 and pos_end != -1:
			for l_idx in range(line_char_ranges.size()):
				var sc: int = line_char_ranges[l_idx].x
				var ec: int = line_char_ranges[l_idx].y
				if ec > pos_start and sc < pos_end:
					if start_line == -1:
						start_line = l_idx
					end_line = l_idx

		if start_line == -1:
			# Fallback proporcional robusto
			var spos: int = habilidad_text.to_lower().find(chunk_start) if not chunk_start.is_empty() else 0
			if spos < 0:
				spos = 0
			var full_len: float = float(maxi(habilidad_text.length(), 1))
			start_line = int(floor((float(spos) / full_len) * float(total_lines)))
			var lines_count: int = maxi(1, int(round((float(raw_t.length()) / full_len) * float(total_lines))))
			end_line = mini(total_lines - 1, start_line + lines_count - 1)

		var y0: float = zone_top + float(start_line) * line_height_px
		var y1: float = zone_top + float(end_line + 1) * line_height_px
		y0 = clampf(y0, zone_top - 2.0, zone_bottom - 8.0)
		y1 = clampf(y1, y0 + 10.0, zone_bottom + 2.0)
		offsets_by_index[idx] = Vector2(y0, y1)

	return offsets_by_index


func _build_ability_buttons(source_card: Node) -> void:
	var usable_abilities: Array = usable_abilities_for(source_card, 0)
	if usable_abilities.is_empty():
		return
	var card_id: String = str(source_card.card_data.get("id", ""))
	var habilidad_text: String = source_card.card_data.get("habilidad", "")
	var all_parsed := UniversalCardParser.parse_abilities(habilidad_text, card_id)
	# Habilidades ganadas (Reina Nyssara): el texto impreso es el original;
	# las ganadas tienen su botón en el panel de la derecha.
	var has_gained: bool = source_card.card_data.has("_base_habilidad")
	if has_gained:
		habilidad_text = str(source_card.card_data["_base_habilidad"])

	if not is_instance_valid(inspected_card):
		return

	# Ubica cada botón exactamente sobre las líneas donde está impresa esa habilidad
	# en la carta, calculando las líneas visuales ocupadas por cada párrafo/palabra clave.
	var card_size: Vector2 = inspected_card.custom_minimum_size

	var offsets_by_index: Dictionary = _calculate_ability_line_offsets(
		habilidad_text, all_parsed, card_size, has_gained
	)

	var panel = Control.new()
	panel.name = "AbilityOverlayButtons"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspected_card.add_child(panel)
	_ability_buttons_panel = panel

	# Respiración sutil del aura mística (entre 0.85 y 1.0 para mantener presencia y nitidez)
	var pulse_tw = panel.create_tween().set_loops()
	pulse_tw.tween_property(panel, "modulate:a", 0.85, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse_tw.tween_property(panel, "modulate:a", 1.0, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# source_card_node: se necesita la carta VIVA (no solo sus datos) para que
	# ActionPipeline._resolve_ability() pueda ejecutar el efecto real vía
	# TriggerSystem._execute_parsed_action() (requiere un Node, no un Dictionary).
	var context = {"controller_id": 0, "source_card_node": source_card}
	var valid_entries: Array[Dictionary] = []
	for entry in usable_abilities:
		var ability = entry.ability
		var validation = entry.validation
		var idx = ability.get("ability_index", -1)
		if not offsets_by_index.has(idx):
			continue
		var y_range: Vector2 = offsets_by_index[idx]
		valid_entries.append({
			"ability": ability,
			"validation": validation,
			"idx": idx,
			"y0": y_range.x,
			"y1": y_range.y,
			"corner_top": true,
			"corner_bottom": true
		})

	if valid_entries.is_empty():
		return

	# Ordenar verticalmente por posición en la carta
	valid_entries.sort_custom(func(a, b): return a["y0"] < b["y0"])

	# Separación limpia entre habilidades múltiples (2 o 3 habilidades activadas) para que nunca se solapen
	if valid_entries.size() > 1:
		for i in range(valid_entries.size() - 1):
			var curr = valid_entries[i]
			var next = valid_entries[i + 1]
			if next["y0"] - curr["y1"] < ABILITY_SEPARATION_GAP:
				var mid_seam: float = (curr["y1"] + next["y0"]) * 0.5
				curr["y1"] = mid_seam - (ABILITY_SEPARATION_GAP * 0.5)
				next["y0"] = mid_seam + (ABILITY_SEPARATION_GAP * 0.5)
			curr["corner_top"] = true
			curr["corner_bottom"] = true
			next["corner_top"] = true
			next["corner_bottom"] = true

	var btn_w: float = card_size.x - (ABILITY_TEXT_SIDE_MARGIN * 2.0)

	for item in valid_entries:
		var ability = item["ability"]
		var validation = item["validation"]
		var btn = _button_support._create_ability_overlay_button(
			ability, validation, item["corner_top"], item["corner_bottom"]
		)
		var btn_y: float = item["y0"]
		var btn_h: float = maxf(12.0, item["y1"] - item["y0"])
		btn.position = Vector2(ABILITY_TEXT_SIDE_MARGIN, btn_y)
		btn.size = Vector2(btn_w, btn_h)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var captured           = ability.duplicate()
		var captured_card_data = source_card.card_data.duplicate()
		var card_for_glow      = source_card  # capturado antes del cierre
		# Terminal P-12: cuenta las habilidades usadas desde fuera del juego.
		if not (source_card.get("current_zone") in Constants.ZONES_IN_PLAY):
			btn.pressed.connect(func(): TurnLimits.note_outside_ability(0))

		var ability_lower: String = str(captured.get("raw_text", "")).to_lower()
		# Con recargo por utilizarla (jose miguel carrera, capitan daisuke): por activate_ability_for(),
		# que lo cobra y después sigue el mismo camino que este botón.
		if TriggerTollScript.ability_toll(source_card, 0) > 0:
			btn.pressed.connect(func():
				close_card_inspection()
				await activate_ability_for(card_for_glow, captured, 0))
			panel.add_child(btn)
			continue
		btn.pressed.connect(func(): RuleState.add("abilities_used", 0))  # anillo de tierra
		# Patrones especiales de habilidades activadas, en 4 archivos
		# (AbilityButtonPatternsA.gd/_B.gd/_C.gd/_D.gd) que se revisan en orden A, B, C, D: el primer
		# match gana.
		if _pattern_group_a.try_build(ability_lower, btn, panel, card_for_glow, captured):
			continue
		if _pattern_group_b.try_build(ability_lower, btn, panel, card_for_glow, captured):
			continue
		if _pattern_group_c.try_build(ability_lower, btn, panel, card_for_glow, captured):
			continue
		if _pattern_group_d.try_build(ability_lower, btn, panel, card_for_glow, captured):
			continue

		# Un solo click: cerrar inspección → empujar a la Pila → Paso D automático
		btn.pressed.connect(func():
			close_card_inspection()
			await _button_support._activate_ability_via_pipeline(card_for_glow, captured_card_data, captured, context)
		)
		panel.add_child(btn)

# Validación de habilidades activadas y ciclo de vida del botón superpuesto (creación, activación
# vía ActionPipeline, brillo de "habilidad en la pila"): AbilityButtonSupport.gd (_button_support,
# montado en setup()).

# Bernardo O'Higgins (coste alternativo + elección de efecto con objetivo):
# BernardoAbilityHandler.gd (_bernardo, montado en setup()).

# Ventanas de respuesta (Paso D genérico + Signo Amarillo): ResponseWindowHandler.gd
# (_response_window, montado en setup()).
