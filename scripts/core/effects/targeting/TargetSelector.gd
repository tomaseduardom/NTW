extends Node
## TargetSelector - Sistema de Selección de Objetivos para la Pila (DAR Sección 6/8)
##
## Gestiona la selección de objetivos válidos en la pila de efectos.
## Filtra por legalidad según las condiciones de la carta fuente.
##
## Ejemplo: "Hacer el Bien" solo puede anular cartas con Coste <= 3

# =============================================================================
# SEÑALES
# =============================================================================
signal selection_mode_entered(source_card: Dictionary, valid_targets: Array)
signal selection_mode_exited
signal target_selected(target_stack_id: int, source_card: Dictionary)
signal target_confirmed(target_stack_id: int, source_card: Dictionary)
signal target_cancelled

## Vinculación de efecto (Sección 8)
signal effect_linked(response_stack_id: int, target_stack_id: int, effect_type: int)
signal effect_executed(response_stack_id: int, target_stack_id: int, success: bool)

## Derecho de arrepentimiento (antes del Paso B)
signal selection_regret(source_card: Dictionary)  # Carta devuelta a mano
signal card_returned_to_hand(card_data: Dictionary, player_id: int)

# =============================================================================
# ENUMS
# =============================================================================
enum SelectionType {
	NONE,
	ANNUL,           # Anular - Evitar que carta se resuelva
	CANCEL,          # Cancelar - Evitar que habilidad se resuelva
	GENERIC_STACK,   # Objetivo genérico en la pila
	REDIRECT         # Redirigir objetivo de otro efecto
}

enum TargetFilter {
	ANY,             # Cualquier objetivo válido
	CARD_ONLY,       # Solo cartas (no habilidades)
	ABILITY_ONLY,    # Solo habilidades
	ALLY_CARD,       # Solo cartas de Aliado
	TALISMAN_CARD,   # Solo Talismanes
	BY_COST,         # Filtrar por coste
	BY_TYPE,         # Filtrar por tipo de carta
	BY_CONTROLLER,   # Filtrar por controlador
	BY_NAME          # Filtrar por nombre específico
}

# =============================================================================
# ESTADO DE SELECCIÓN
# =============================================================================
var _is_selecting: bool = false
var _selection_type: SelectionType = SelectionType.NONE
var _source_card: Dictionary = {}
var _valid_targets: Array[int] = []  # Stack IDs válidos
var _current_hover_id: int = -1
var _selected_target_id: int = -1

## Filtros activos para la selección actual
var _active_filters: Array[Dictionary] = []

## Módulos extraídos (Fase 4 de reestructuración)
var _linked_registry: LinkedEffectRegistry
var _regret: RegretSystem

# =============================================================================
# REFERENCIAS
# =============================================================================
var _stack_visualizer: Control = null

# =============================================================================
# CONFIGURACIÓN VISUAL
# =============================================================================
const VALID_TARGET_COLOR: Color = Color(0.2, 1.0, 0.4, 0.8)
const INVALID_TARGET_COLOR: Color = Color(0.5, 0.5, 0.5, 0.4)
const HOVER_COLOR: Color = Color(1.0, 1.0, 0.3, 1.0)
const SELECTED_COLOR: Color = Color(0.0, 0.8, 1.0, 1.0)

## Cursor personalizado para modo selección
var _selection_cursor: Resource = null
var _default_cursor: Resource = null


func _ready() -> void:
	_linked_registry = LinkedEffectRegistry.new()
	_linked_registry.setup(self)
	_regret = RegretSystem.new()
	_regret.setup(self)

	call_deferred("_get_references")
	print("[TargetSelector] Inicializado")


func _get_references() -> void:
	# (2026-08-28, "módulos gordos" punto 1): ActionPipeline es autoload
	# garantizado — se saca el cacheo redundante. GameManager se cacheaba
	# pero no se usaba en este archivo. StackVisualizer NO es autoload
	# (nodo opcional de escena), se mantiene su lookup.
	_stack_visualizer = get_node_or_null("/root/StackVisualizer")

	ActionPipeline.stack_object_resolving.connect(_linked_registry._on_stack_object_resolving)
	ActionPipeline.stack_object_resolved.connect(_linked_registry._on_stack_object_resolved)
	ActionPipeline.stack_object_removed.connect(_linked_registry._on_stack_object_removed)

	if _stack_visualizer:
		# Conectar señales del visualizador
		if _stack_visualizer.has_signal("annul_target_selected"):
			_stack_visualizer.annul_target_selected.connect(_on_visualizer_annul_selected)
		if _stack_visualizer.has_signal("cancel_target_selected"):
			_stack_visualizer.cancel_target_selected.connect(_on_visualizer_cancel_selected)
		if _stack_visualizer.has_signal("stack_item_hovered"):
			_stack_visualizer.stack_item_hovered.connect(_on_visualizer_item_hovered)


func _input(event: InputEvent) -> void:
	# ESC cancela la selección (con arrepentimiento si está disponible)
	if event.is_action_pressed("ui_cancel"):
		if _is_selecting:
			# Cancelar selección en curso (devuelve carta si aún no pagó)
			if _regret.can_regret():
				cancel_selection_with_regret()
			else:
				cancel_selection()
			get_viewport().set_input_as_handled()
			return

	if not _is_selecting:
		return

	# Click izquierdo confirma selección si hay hover válido
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _current_hover_id >= 0 and _current_hover_id in _valid_targets:
				confirm_selection(_current_hover_id)
				get_viewport().set_input_as_handled()

		# Click derecho también puede cancelar con arrepentimiento
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _regret.can_regret():
				cancel_selection_with_regret()
			else:
				cancel_selection()
			get_viewport().set_input_as_handled()


# =============================================================================
# ANÁLISIS DE CARTA FUENTE
# =============================================================================
func _text_contains_annul(text: String) -> bool:
	"""Detecta si el texto indica anulación"""
	var annul_keywords = ["anula", "anular", "anulado", "no se resuelve", "evita que"]
	for kw in annul_keywords:
		if kw in text:
			return true
	return false


func _text_contains_cancel(text: String) -> bool:
	"""Detecta si el texto indica cancelación"""
	var cancel_keywords = ["cancela", "cancelar", "cancelado", "interrumpe"]
	for kw in cancel_keywords:
		if kw in text:
			return true
	return false


# =============================================================================
# MODO DE SELECCIÓN
# =============================================================================
func exit_selection_mode() -> void:
	"""Sale del modo de selección

	Nota: No deshabilita arrepentimiento aquí porque el jugador aún puede
	arrepentirse hasta que empiece el Paso B (pago de costes).
	"""
	if not _is_selecting:
		return

	_is_selecting = false
	_source_card = {}
	_valid_targets.clear()
	_selected_target_id = -1
	_current_hover_id = -1
	_selection_type = SelectionType.NONE

	# Restaurar cursor
	_set_selection_cursor(false)

	# Limpiar resaltados del visualizador
	_clear_visualizer_highlights()

	emit_signal("selection_mode_exited")
	print("[TargetSelector] Modo selección desactivado")


func confirm_selection(stack_id: int) -> void:
	"""Confirma la selección del objetivo y crea la vinculación de efecto"""
	if not _is_selecting:
		return

	if stack_id not in _valid_targets:
		print("[TargetSelector] ERROR: Objetivo #%d no es válido" % stack_id)
		return

	_selected_target_id = stack_id

	# Guardar datos para vinculación (antes de limpiar estado)
	var source_card_copy = _source_card.duplicate(true)
	var selection_type_copy = _selection_type

	print("[TargetSelector] ✓ Objetivo confirmado: #%d" % stack_id)
	emit_signal("target_confirmed", stack_id, _source_card)

	# Habilitar arrepentimiento antes de Paso B
	_regret._enable_regret(source_card_copy)

	# Salir del modo selección (pero mantener datos para vinculación)
	exit_selection_mode()

	# La vinculación se completa cuando la carta de respuesta entre a la pila
	# El caller debe llamar a link_effect() después de añadir la carta a la pila


func cancel_selection() -> void:
	"""Cancela la selección actual"""
	print("[TargetSelector] Selección cancelada por usuario")
	emit_signal("target_cancelled")
	exit_selection_mode()


func cancel_selection_with_regret() -> void:
	"""Cancela la selección y devuelve la carta a la mano (Derecho de Arrepentimiento)

	Solo válido antes del Paso B (pago de costes).
	DAR Sección 6: El jugador puede arrepentirse antes de pagar.
	"""
	if not _regret.can_regret():
		print("[TargetSelector] No se puede ejercer arrepentimiento en este momento")
		return

	var regret_card = _regret.get_regret_card()
	if regret_card.is_empty():
		print("[TargetSelector] No hay carta para devolver")
		return

	var regret_player_id = _regret.get_regret_player_id()

	print("[TargetSelector] ═══ DERECHO DE ARREPENTIMIENTO ═══")
	print("[TargetSelector] Carta '%s' devuelta a mano del Jugador %d" % [
		regret_card.get("nombre", regret_card.get("name", "???")),
		regret_player_id + 1
	])

	# Devolver carta a la mano
	_regret._return_card_to_hand(regret_card, regret_player_id)

	# Emitir señales
	emit_signal("selection_regret", regret_card)
	emit_signal("card_returned_to_hand", regret_card, regret_player_id)
	emit_signal("target_cancelled")

	# Limpiar estado de arrepentimiento
	_regret._disable_regret()

	# Salir del modo selección
	exit_selection_mode()


# =============================================================================
# GESTIÓN DE CURSOR
# =============================================================================
func _set_selection_cursor(selecting: bool) -> void:
	"""Cambia el cursor del mouse para indicar modo selección"""
	if selecting:
		# Cursor de crosshair/target
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	else:
		# Restaurar cursor normal
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# =============================================================================
# INTEGRACIÓN CON STACKVISUALIZER
# =============================================================================
func _highlight_visualizer_item(stack_id: int, is_valid: bool) -> void:
	"""Resalta un item específico en el visualizador"""
	if not _stack_visualizer:
		return

	if _stack_visualizer.has_method("highlight_target"):
		var color = VALID_TARGET_COLOR if is_valid else INVALID_TARGET_COLOR
		_stack_visualizer.highlight_target(stack_id, color, is_valid)
	elif _stack_visualizer.has_method("_highlight_item"):
		# Fallback al método interno
		var items = _stack_visualizer.get("_stack_items")
		if items and items.has(stack_id):
			var item = items[stack_id]
			if is_instance_valid(item):
				_apply_highlight_style(item, is_valid)


func _apply_highlight_style(item: Control, is_valid: bool) -> void:
	"""Aplica estilo de resaltado a un item"""
	var style = item.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return

	if is_valid:
		# Objetivo válido: borde verde brillante + pulso
		style.border_color = VALID_TARGET_COLOR
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_width_top = 4
		style.border_width_bottom = 4

		# Animación de pulso
		var tween = item.create_tween()
		tween.set_loops()
		tween.tween_property(item, "modulate", Color(1.2, 1.2, 1.0), 0.5)
		tween.tween_property(item, "modulate", Color.WHITE, 0.5)
	else:
		# Objetivo inválido: atenuado
		style.border_color = INVALID_TARGET_COLOR
		item.modulate = Color(0.6, 0.6, 0.6, 0.7)


func _clear_visualizer_highlights() -> void:
	"""Limpia todos los resaltados del visualizador"""
	if not _stack_visualizer:
		return

	if _stack_visualizer.has_method("clear_all_highlights"):
		_stack_visualizer.clear_all_highlights()
	elif _stack_visualizer.has_method("refresh"):
		_stack_visualizer.refresh()


func _on_visualizer_item_hovered(stack_id: int, is_hovered: bool) -> void:
	"""Callback cuando el mouse entra/sale de un item del visualizador"""
	if not _is_selecting:
		return

	if is_hovered:
		_current_hover_id = stack_id

		# Resaltar más si es válido
		if stack_id in _valid_targets:
			_highlight_visualizer_item(stack_id, true)
			if _stack_visualizer:
				var items = _stack_visualizer.get("_stack_items")
				if items and items.has(stack_id):
					var item = items[stack_id]
					if is_instance_valid(item):
						var style = item.get_theme_stylebox("panel") as StyleBoxFlat
						if style:
							style.border_color = HOVER_COLOR
	else:
		if _current_hover_id == stack_id:
			_current_hover_id = -1
		# Restaurar resaltado normal
		if stack_id in _valid_targets:
			_highlight_visualizer_item(stack_id, true)


func _on_visualizer_annul_selected(stack_id: int) -> void:
	"""Callback cuando se selecciona un objetivo para anular desde el visualizador"""
	if _is_selecting and _selection_type == SelectionType.ANNUL:
		if stack_id in _valid_targets:
			confirm_selection(stack_id)
		else:
			print("[TargetSelector] Objetivo #%d no es válido para anular" % stack_id)


func _on_visualizer_cancel_selected(stack_id: int) -> void:
	"""Callback cuando se selecciona un objetivo para cancelar desde el visualizador"""
	if _is_selecting and _selection_type == SelectionType.CANCEL:
		if stack_id in _valid_targets:
			confirm_selection(stack_id)
		else:
			print("[TargetSelector] Objetivo #%d no es válido para cancelar" % stack_id)


# =============================================================================
# VINCULACIÓN DE EFECTO (implementación en LinkedEffectRegistry.gd)
# =============================================================================
func link_effect(response_stack_id: int, target_stack_id: int,
				  effect_type: SelectionType, source_card: Dictionary) -> bool:
	return _linked_registry.link_effect(response_stack_id, target_stack_id, effect_type, source_card)


func get_linked_effect(response_stack_id: int) -> LinkedEffect:
	return _linked_registry.get_linked_effect(response_stack_id)


func has_linked_effect(response_stack_id: int) -> bool:
	return _linked_registry.has_linked_effect(response_stack_id)


func execute_linked_effect(response_stack_id: int) -> bool:
	return await _linked_registry.execute_linked_effect(response_stack_id)


func remove_linked_effect(response_stack_id: int) -> void:
	_linked_registry.remove_linked_effect(response_stack_id)


func clear_all_linked_effects() -> void:
	_linked_registry.clear_all_linked_effects()


# =============================================================================
# DERECHO DE ARREPENTIMIENTO (implementación en RegretSystem.gd)
# =============================================================================
func can_regret() -> bool:
	return _regret.can_regret()


func get_regret_card() -> Dictionary:
	return _regret.get_regret_card()


func notify_step_b_started() -> void:
	_regret.notify_step_b_started()
