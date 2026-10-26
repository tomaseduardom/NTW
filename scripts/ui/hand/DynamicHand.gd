class_name DynamicHand
extends Control
## Mano con cartas en abanico profesional (arco rúnico).
## - Distribución matemática en arco cosenoidal/parabólico con rotación progresiva.
## - Hover profesional: la carta se eleva, se endereza a 0° y gana prioridad z_index.
## - Teclas Q / H: el jugador oculta o despliega su mano con animación fluida.

signal card_clicked(card: Node)
signal card_double_clicked(card: Node)

@export_group("Layout")
@export var card_overlap: float = -35.0  ## Solapamiento base entre cartas en mano
@export var animation_duration: float = 0.22
@export var max_fan_angle: float = 9.5  ## Ángulo máximo de apertura del abanico en grados
@export var max_arc_height: float = 22.0  ## Elevación vertical máxima del centro del arco
@export var hover_lift: float = 0.0  ## Inmovilidad en hover (0 = la carta no se mueve)

var cards: Array[Node] = []
var _tweens: Dictionary = {}
var _is_hidden: bool = false
var _is_docked: bool = false          ## Por defecto desplegada y visible para el jugador
var _is_temporarily_expanded: bool = false
var _undock_grace_timer: float = 0.0
const UNDOCK_GRACE_DELAY: float = 0.22  ## Retardo suave para evitar sacudidas al salir el cursor

var _count_badge: PanelContainer = null
var _count_label: Label = null
var _badge_tween: Tween = null


func _ready() -> void:
	z_as_relative = false
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_count_badge()
	if not child_exiting_tree.is_connected(_on_child_exiting_tree):
		child_exiting_tree.connect(_on_child_exiting_tree)
	if not GameSettings.keybindings_changed.is_connected(_on_keybindings_changed):
		GameSettings.keybindings_changed.connect(_on_keybindings_changed)


func _on_keybindings_changed() -> void:
	_update_count_badge(false)


func _on_child_exiting_tree(node: Node) -> void:
	var idx = cards.find(node)
	if idx >= 0:
		cards.remove_at(idx)
		if _tweens.has(node):
			if is_instance_valid(_tweens[node]):
				_tweens[node].kill()
			_tweens.erase(node)
		_arrange_cards(true)


func _process(delta: float) -> void:
	if _is_hidden or cards.is_empty():
		return

	# Si la mano está en su posición normal desplegada, se mantiene visible sin esconderse sola
	if not _is_docked and not _is_temporarily_expanded:
		return

	# No replegar mientras se esté arrastrando una carta
	if _is_any_card_dragging():
		_undock_grace_timer = UNDOCK_GRACE_DELAY
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var hand_rect: Rect2 = get_global_rect()

	var in_h_bounds: bool = mouse_pos.x >= (hand_rect.position.x - 20.0) and mouse_pos.x <= (hand_rect.end.x + 20.0)
	var in_expanded_v_bounds: bool = mouse_pos.y >= (hand_rect.position.y - 40.0) and mouse_pos.y <= (hand_rect.end.y + 20.0)
	var is_mouse_over_hand: bool = in_h_bounds and in_expanded_v_bounds

	if _is_docked:
		# En modo reposo: si el cursor entra a la franja de la mano, se eleva temporalmente
		if is_mouse_over_hand or _has_any_card_hovered():
			_is_docked = false
			_is_temporarily_expanded = true
			_undock_grace_timer = UNDOCK_GRACE_DELAY
			_arrange_cards(true)
	elif _is_temporarily_expanded:
		# Si se expandió temporalmente por hover en reposo, regresa a reposo al salir el cursor
		if is_mouse_over_hand or _has_any_card_hovered():
			_undock_grace_timer = UNDOCK_GRACE_DELAY
		else:
			if _undock_grace_timer > 0.0:
				_undock_grace_timer -= delta
			else:
				_is_docked = true
				_is_temporarily_expanded = false
				_arrange_cards(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_toggle: int = GameSettings.get_key("toggle_mano")
		var key_hide: int = GameSettings.get_key("ocultar_mano")
		if event.keycode == key_toggle:
			toggle_space_lock()
			get_viewport().set_input_as_handled()
		elif event.keycode == key_hide or event.keycode == KEY_Q:
			toggle_hidden()
			get_viewport().set_input_as_handled()


func toggle_space_lock() -> void:
	"""Alterna la mano entre reposo (abajo) y desplegada (arriba) con la tecla Espacio."""
	if _is_hidden:
		_is_hidden = false
	_is_temporarily_expanded = false
	if _is_docked:
		expand_hand()
	else:
		dock_hand()


func toggle_hidden() -> void:
	"""Alterna entre ocultar la mano completamente fuera de pantalla y restaurarla."""
	_is_hidden = not _is_hidden
	_is_temporarily_expanded = false
	_arrange_cards(true)


func expand_hand() -> void:
	"""Despliega la mano hacia arriba en abanico completo."""
	if _is_hidden:
		return
	_is_docked = false
	_is_temporarily_expanded = false
	_arrange_cards(true)


func dock_hand() -> void:
	"""Baja la mano a reposo inferior para despejar el campo si el jugador lo desea."""
	if _is_hidden:
		return
	_is_docked = true
	_is_temporarily_expanded = false
	_arrange_cards(true)


func _is_any_card_dragging() -> bool:
	for c in cards:
		if is_instance_valid(c) and c.get("is_dragging") == true:
			return true
	return false


func _has_any_card_hovered() -> bool:
	for c in cards:
		if is_instance_valid(c) and c.get("is_hovered") == true:
			return true
	return false


func add_card(card: Node) -> void:
	"""Añade una carta a la mano configurando pivote para abanico y señales de hover."""
	if card in cards:
		return
	cards.append(card)
	if card.get_parent() != self:
		add_child(card)

	# Pivote en centro-inferior de la carta (150x210) para giro de abanico natural
	var card_width = 150.0
	var card_height = 210.0
	card.pivot_offset = Vector2(card_width / 2.0, card_height)

	if not card.card_clicked.is_connected(_forward_card_clicked):
		card.card_clicked.connect(_forward_card_clicked)
	if not card.card_double_clicked.is_connected(_forward_card_double_clicked):
		card.card_double_clicked.connect(_forward_card_double_clicked)
	if card.has_signal("card_hovered") and not card.card_hovered.is_connected(_on_card_hovered):
		card.card_hovered.connect(_on_card_hovered)
	if card.has_signal("card_unhovered") and not card.card_unhovered.is_connected(_on_card_unhovered):
		card.card_unhovered.connect(_on_card_unhovered)

	_arrange_cards(true)


func _forward_card_clicked(c: Node) -> void:
	card_clicked.emit(c)


func _forward_card_double_clicked(c: Node) -> void:
	card_double_clicked.emit(c)


func remove_card(card: Node, destroy: bool = true) -> void:
	"""Remueve una carta de la mano y reordena el abanico."""
	var idx = cards.find(card)
	if idx >= 0:
		cards.remove_at(idx)
	if _tweens.has(card):
		if is_instance_valid(_tweens[card]):
			_tweens[card].kill()
		_tweens.erase(card)

	if card.has_signal("card_hovered") and card.card_hovered.is_connected(_on_card_hovered):
		card.card_hovered.disconnect(_on_card_hovered)
	if card.has_signal("card_unhovered") and card.card_unhovered.is_connected(_on_card_unhovered):
		card.card_unhovered.disconnect(_on_card_unhovered)

	if destroy:
		card.queue_free()
	elif card.get_parent() == self:
		remove_child(card)
	_arrange_cards(true)


## Mismo nombre que OpponentFan.get_cards(): varios patrones lo llaman sobre "la mano del oponente" sin
## saber cuál de las dos es (fallaba cuando el oponente era el Anfitrión).
func get_cards() -> Array[Node]:
	return cards


func get_card_count() -> int:
	return cards.size()


func clear_hand() -> void:
	"""Limpia todas las cartas de la mano."""
	for card in cards:
		if is_instance_valid(card):
			card.queue_free()
	cards.clear()
	_tweens.clear()
	_update_count_badge(false)


func get_card_target_rotation(card: Node) -> float:
	"""Calcula la inclinación angular en grados para una carta según su posición en el abanico."""
	var idx = cards.find(card)
	if idx < 0:
		return 0.0
	var n = cards.size()
	if n <= 1 or _is_hidden:
		return 0.0

	var center_idx = (n - 1) / 2.0
	var d = float(idx) - center_idx
	var t = d / maxf(center_idx, 1.0)
	var max_tilt = max_fan_angle
	if _is_docked:
		# En reposo: inclinación casi nula (máx 2.5°) para lectura horizontal limpia de cabezales
		max_tilt = minf(max_fan_angle * 0.3, 2.5)
	var dynamic_max_tilt = clampf((n - 1) * 2.2, 0.0, max_tilt)
	return t * dynamic_max_tilt


func get_card_target_position(card: Node) -> Vector2:
	"""Calcula la posición local (X, Y en arco) de destino para una carta en la mano."""
	var idx = cards.find(card)
	if idx < 0:
		idx = cards.size() - 1
	if idx < 0:
		idx = 0

	var card_width = 150.0
	var n = maxi(1, cards.size())
	var effective_overlap = card_overlap
	if n > 1:
		var available_w = size.x if size.x > 100.0 else 1160.0
		var natural_total = card_width + (n - 1) * (card_width + card_overlap)
		if natural_total > available_w:
			var max_step = (available_w - card_width) / float(n - 1)
			effective_overlap = max_step - card_width

	var step_x = card_width + effective_overlap
	var total_width = card_width + (n - 1) * step_x if n > 1 else card_width
	var start_x = (size.x - total_width) / 2.0
	var center_y = size.y / 2.0
	var target_x = start_x + idx * step_x

	var base_y = _get_vertical_target_y(center_y)
	var target_y = base_y
	if not _is_hidden and not _is_docked and n > 1:
		var center_idx = (n - 1) / 2.0
		var d = float(idx) - center_idx
		var t = d / maxf(center_idx, 1.0)
		var dynamic_arc = clampf((n - 1) * 3.5, 0.0, max_arc_height)
		var curve_lift = (1.0 - (t * t)) * dynamic_arc
		target_y = base_y - curve_lift
	elif not _is_hidden and _is_docked and n > 1:
		var center_idx = (n - 1) / 2.0
		var d = float(idx) - center_idx
		var t = d / maxf(center_idx, 1.0)
		var curve_lift = (1.0 - (t * t)) * 5.0
		target_y = base_y - curve_lift

	return Vector2(target_x, target_y)


func _get_vertical_target_y(center_y: float) -> float:
	"""Calcula la posición Y base según si la mano está desplegada, en reposo u oculta."""
	if _is_hidden:
		return center_y + 160.0  # Oculta completamente bajo la pantalla
	elif _is_docked:
		return center_y - 25.0   # En reposo: cartas asoman ampliamente (~130px visibles, nunca escondidas)
	else:
		return center_y - 100.0  # Desplegada completa (abanico interactivo elevado, cartas 100% legibles)


func _arrange_cards(animated: bool = true) -> void:
	"""Organiza las cartas en un abanico simétrico con elevación en arco y rotación armónica."""
	var valid_cards: Array[Node] = []
	for c in cards:
		if is_instance_valid(c) and c.get_parent() == self:
			valid_cards.append(c)
	if valid_cards.size() != cards.size():
		cards = valid_cards

	if cards.is_empty():
		_update_count_badge(animated)
		return

	var card_width = 150.0
	var card_height = 210.0
	var n = cards.size()

	var effective_overlap = card_overlap
	if n > 1:
		var available_w = size.x if size.x > 100.0 else 1160.0
		var natural_total = card_width + (n - 1) * (card_width + card_overlap)
		if natural_total > available_w:
			var max_step = (available_w - card_width) / float(n - 1)
			effective_overlap = max_step - card_width

	var step_x = card_width + effective_overlap

	for i in range(cards.size()):
		var card = cards[i]
		card.pivot_offset = Vector2(card_width / 2.0, card_height)

		var target_pos: Vector2 = get_card_target_position(card)
		var target_rot: float = get_card_target_rotation(card)

		card.set_meta("hand_base_z_index", i)
		card.set("target_rotation", target_rot)
		card.set("original_position", get_global_transform() * target_pos)
		card.set_meta("hand_target_pos", target_pos)

		var is_card_hovered: bool = card.get("is_hovered") == true
		if is_card_hovered:
			card.z_index = 80
		else:
			card.z_index = i
		card.set("original_z_index", i)

		# Recorte de click para cartas tapadas por la siguiente a la derecha
		if card.has_method("set_click_clip_right"):
			if not is_card_hovered and i < n - 1 and step_x < card_width:
				card.set_click_clip_right(step_x)
			else:
				card.set_click_clip_right(-1.0)

		if animated and _tweens.has(card):
			if is_instance_valid(_tweens[card]):
				_tweens[card].kill()
			_tweens.erase(card)

		if animated:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(card, "position", target_pos, animation_duration).set_ease(Tween.EASE_OUT).set_trans(
				Tween.TRANS_CUBIC
			)
			(
				tween
				. tween_property(card, "rotation_degrees", target_rot, animation_duration)
				. set_ease(Tween.EASE_OUT)
				. set_trans(Tween.TRANS_CUBIC)
			)
			if not is_card_hovered:
				tween.tween_property(card, "scale", Vector2.ONE, animation_duration).set_ease(Tween.EASE_OUT)
			_tweens[card] = tween
		else:
			card.position = target_pos
			card.rotation_degrees = target_rot
			if not is_card_hovered:
				card.scale = Vector2.ONE

	_update_count_badge(animated)


func _on_card_hovered(card: Node) -> void:
	"""Al hacer hover: si está en reposo se eleva automáticamente, y la carta gana prioridad z_index."""
	if not is_instance_valid(card) or card.get_parent() != self:
		return
	if _is_hidden or card.get("is_dragging") == true:
		return

	if _is_docked:
		_is_docked = false
		_is_temporarily_expanded = true
		_arrange_cards(true)

	_undock_grace_timer = UNDOCK_GRACE_DELAY
	card.z_index = 80
	if card.has_method("set_click_clip_right"):
		card.set_click_clip_right(-1.0)


func _on_card_unhovered(card: Node) -> void:
	"""Al salir el mouse: restaura su z_index original y recorte sin desplazar la carta."""
	if not is_instance_valid(card) or card.get_parent() != self:
		return
	if card.get("is_dragging") == true:
		return

	var base_z: int = card.get_meta("hand_base_z_index", cards.find(card))
	card.z_index = base_z
	if card.has_method("set_click_clip_right"):
		card.set_click_clip_right(get_card_clip_right(card))


func get_card_clip_right(card: Node) -> float:
	"""Devuelve el ancho expuesto para recorte de clic en cartas solapadas."""
	var idx = cards.find(card)
	if idx < 0 or idx >= cards.size() - 1:
		return -1.0
	var card_width = 150.0
	var n = cards.size()
	var effective_overlap = card_overlap
	if n > 1:
		var available_w = size.x if size.x > 100.0 else 1160.0
		var natural_total = card_width + (n - 1) * (card_width + card_overlap)
		if natural_total > available_w:
			var max_step = (available_w - card_width) / float(n - 1)
			effective_overlap = max_step - card_width
	var step_x = card_width + effective_overlap
	return step_x if step_x < card_width else -1.0


# =============================================================================
# CONTADOR DE CARTAS EN MANO
# =============================================================================
func _setup_count_badge() -> void:
	if _count_badge != null:
		return
	_count_badge = PanelContainer.new()
	_count_badge.name = "HandCountBadge"
	_count_badge.mouse_filter = Control.MOUSE_FILTER_PASS
	_count_badge.z_index = 50
	_count_badge.custom_minimum_size = Vector2(26, 26)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.border_color = Color(0.82, 0.70, 0.35, 0.95)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 4
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_count_badge.add_theme_stylebox_override("panel", style)

	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font_cinzel: Font = load("res://assets/fonts/Cinzel-Bold.ttf")
	if font_cinzel:
		_count_label.add_theme_font_override("font", font_cinzel)
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_count_badge.add_child(_count_label)

	add_child(_count_badge)
	_count_badge.visible = false


func _update_count_badge(animated: bool = true) -> void:
	if _count_badge == null:
		return
	if cards.is_empty() or _is_hidden:
		_count_badge.visible = false
		return

	_count_badge.visible = true
	_count_label.text = str(cards.size())
	var k_toggle = GameSettings.get_key_display_string(GameSettings.get_key("toggle_mano"))
	var k_hide = GameSettings.get_key_display_string(GameSettings.get_key("ocultar_mano"))
	_count_badge.tooltip_text = "Mano: %d cartas\n[%s] Fijar / Reposar mano\n[%s/Q] Ocultar mano" % [cards.size(), k_toggle, k_hide]

	var last_card = cards[cards.size() - 1]
	var last_pos: Vector2 = get_card_target_position(last_card)
	var card_width = 150.0
	var badge_size = Vector2(26.0, 26.0)

	var target_x = last_pos.x + card_width + 12.0
	if size.x > 100.0:
		target_x = minf(target_x, size.x - badge_size.x - 4.0)

	var target_y = last_pos.y + 105.0 - (badge_size.y / 2.0)
	var target_pos = Vector2(target_x, target_y)

	if is_instance_valid(_badge_tween):
		_badge_tween.kill()

	if animated:
		_badge_tween = create_tween()
		_badge_tween.tween_property(_count_badge, "position", target_pos, animation_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		_count_badge.position = target_pos

