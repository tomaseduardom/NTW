extends RefCounted
## CastleLookWindow — ventana única para "mira N cartas del tope/fondo de un Castillo"
## (arquitectura.md §69), con pasos guiados y la menor cantidad de clics: las cartas miradas
## quedan en una fila; arriba se indica qué hacer ("Toca la carta que va a tu mano") y al tocarla
## se aparta a su destino; después el siguiente destino ("...a tu Cementerio"). Al final, las que
## vuelven al Castillo se ordenan ARRASTRÁNDOLAS de izquierda a derecha (solo en horizontal;
## izquierda = más arriba). Nada se mueve en el juego hasta terminar; el motor es CastleLook.gd.
## Corre igual en el Anfitrión y en el Remoto (prompt "castle_look", resultado por red), así que
## todo lo que recibe es serializable: cartas como Dictionary y elegibilidad por zona (no
## Callables).
## config = {title: String, cards: [card_data...], boxes: [{key, label, min, max (-1 = sin tope),
## ordered: bool, eligible: [bool por carta]}], start: key de la zona (ordenada) donde empiezan
## todas}
## Devuelve {key: [índices de cards en orden]} (en una zona ordenada, el primero queda más arriba).
## Se usa con preload (sin class_name global; ver §54).

const CardScene := preload("res://scenes/cards/Card.tscn")
## Escala de las cartas: tamaño armónico optimizado para alta legibilidad sin sobrecargar la pantalla
const MAX_SCALE := 1.15
const GAP := 20.0
const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")
const GOLD := Color(0.85, 0.72, 0.28)

var _main: Node
var _cfg: Dictionary
var _where: Array = []  # por carta: key de su zona actual
var _order: Dictionary = {}  # key -> [índices en orden]
var _steps: Array = []  # boxes a repartir (todas menos la inicial), en orden
var _step: int = 0  # índice en _steps; == _steps.size(): fase de ordenar
var _history: Array = []  # [[índice de carta, key]] para Deshacer
var _done := false
var _layer: CanvasLayer
var _title: Label
var _hint: Label
var _rows_box: VBoxContainer
var _assigned_box: HBoxContainer
var _undo: Button
var _ready_btn: Button
var _drag: Dictionary = {}  # {key, i, holder, offset, row}
var _scale: float = MAX_SCALE
var _small: float = MAX_SCALE * 0.80
var CARD_W: float = 150.0 * MAX_SCALE
var CARD_H: float = 210.0 * MAX_SCALE


## Uso: var w = CastleLookWindowScript.new(); var r = await w.open(main, cfg)
## (el llamador guarda 'w' mientras espera).
func open(main: Node, config: Dictionary) -> Dictionary:
	return await _run(main, config)


static func auto_pick(config: Dictionary) -> Dictionary:
	"""Reparto automático (bot local, o respuesta inválida por red): llena
	cada zona no inicial hasta su mínimo con las primeras elegibles; el resto
	queda en la zona inicial, en el orden en que se miraron."""
	var result: Dictionary = {}
	var used: Dictionary = {}
	for box in config.boxes:
		result[box.key] = []
	for box in config.boxes:
		if box.key == config.start:
			continue
		for i in range(config.cards.size()):
			if result[box.key].size() >= int(box.min):
				break
			if not used.has(i) and box.eligible[i]:
				result[box.key].append(i)
				used[i] = true
	for i in range(config.cards.size()):
		if not used.has(i):
			result[config.start].append(i)
	return result


static func validate(config: Dictionary, raw: Dictionary) -> Dictionary:
	"""Revalida un resultado (por red puede llegar cualquier cosa): cada
	carta en exactamente una zona, elegible para ella, topes y mínimos
	respetados. Si no cuadra, reparto automático."""
	var n: int = config.cards.size()
	var seen: Dictionary = {}
	var result: Dictionary = {}
	for box in config.boxes:
		var list: Array = []
		for v in raw.get(box.key, []):
			var i: int = int(v)
			if i < 0 or i >= n or seen.has(i) or not box.eligible[i]:
				return auto_pick(config)
			seen[i] = true
			list.append(i)
		if list.size() < int(box.min) or (int(box.max) >= 0 and list.size() > int(box.max)):
			return auto_pick(config)
		result[box.key] = list
	if seen.size() != n:
		return auto_pick(config)
	return result


func _run(main: Node, config: Dictionary) -> Dictionary:
	_main = main
	_cfg = config
	for box in _cfg.boxes:
		_order[box.key] = []
		if box.key != _cfg.start:
			_steps.append(box)
	for i in range(_cfg.cards.size()):
		_where.append(_cfg.start)
		_order[_cfg.start].append(i)
	_fit_scale()
	_build()
	_skip_finished_steps()
	_refresh()
	# Tiempo agotado (TurnClock): reparto automático.
	var force_gen: int = NetworkClient.force_gen
	NetworkClient.local_waits += 1
	while not _done:
		if NetworkClient.ui_forced(force_gen):
			_order = auto_pick(_cfg)
			NetworkClient.ui_forced_done()
			break
		await _main.get_tree().process_frame
	NetworkClient.local_waits = maxi(0, NetworkClient.local_waits - 1)
	_layer.queue_free()
	return _order.duplicate(true)


## Cartas lo más grandes posible (hasta MAX_SCALE) sin salirse: a lo ancho entra la fila completa y a
## lo alto la fila, la de las ya repartidas, los textos y los botones.
func _fit_scale() -> void:
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size
	var n: int = maxi(_cfg.cards.size(), 1)
	var by_w: float = (vp.x * 0.90 - GAP * (n - 1)) / (150.0 * n)
	var by_h: float = (vp.y - 280.0) / (210.0 * 1.80)  # fila grande + fila destino (0.80) + textos/botones
	_scale = clampf(minf(MAX_SCALE, minf(by_w, by_h)), 0.65, MAX_SCALE)
	_small = _scale * 0.80
	CARD_W = 150.0 * _scale
	CARD_H = 210.0 * _scale


func _box(key: String) -> Dictionary:
	for b in _cfg.boxes:
		if b.key == key:
			return b
	return {}


# --- Pasos -------------------------------------------------------------------------------
func _in_ordering_phase() -> bool:
	return _step >= _steps.size()


func _eligible_left(box: Dictionary) -> bool:
	for i in _order[_cfg.start]:
		if box.eligible[i]:
			return true
	return false


func _step_full(box: Dictionary) -> bool:
	return int(box.max) >= 0 and _order[box.key].size() >= int(box.max)


## Pasa solo los pasos ya completos (o sin cartas posibles); en la fase de ordenar, si no hay nada
## que ordenar, termina.
func _skip_finished_steps() -> void:
	while not _in_ordering_phase():
		var box: Dictionary = _steps[_step]
		if _step_full(box) or (not _eligible_left(box) and _order[box.key].size() >= int(box.min)):
			_step += 1
		else:
			break
	if _in_ordering_phase() and not _anything_to_order():
		_done = true


func _anything_to_order() -> bool:
	for box in _cfg.boxes:
		if box.ordered and _order[box.key].size() > 1:
			return true
	return false


func _instruction() -> String:
	if _in_ordering_phase():
		return "Arrastra las cartas para ordenarlas · izquierda = más arriba"
	var box: Dictionary = _steps[_step]
	var need: int = int(box.max) if int(box.max) >= 0 else -1
	var have: int = _order[box.key].size()
	var label: String = str(box.label)
	if need > 1:
		return "%s · toca %d cartas (%d de %d)" % [label, need, have, need]
	if need == 1:
		return "%s · toca una carta" % label
	return "%s · toca las cartas que quieras" % label


# --- Construcción ------------------------------------------------------------------------
func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 60
	_main.add_child(_layer)
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.size = vp
	bg.color = Color(0.01, 0.01, 0.02, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size = vp
	_layer.add_child(vbox)

	_title = Label.new()
	_title.text = str(_cfg.title)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", FONT_BODY)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(0.75, 0.72, 0.80))
	vbox.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(minf(vp.x * 0.85, 1400.0), 0)
	_hint.add_theme_font_override("font", FONT_TITLE)
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(_hint)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 10)
	_rows_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_rows_box)

	_assigned_box = HBoxContainer.new()
	_assigned_box.add_theme_constant_override("separation", 32)
	_assigned_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_assigned_box)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)
	_undo = _button("Deshacer", false)
	_undo.pressed.connect(_on_undo)
	buttons.add_child(_undo)
	_ready_btn = _button("Listo", true)
	_ready_btn.pressed.connect(_on_ready)
	buttons.add_child(_ready_btn)


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 48)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_TITLE)
	b.add_theme_font_size_override("font_size", 16)

	if primary:
		var sb_norm := StyleBoxFlat.new()
		sb_norm.bg_color = Color(0.16, 0.14, 0.10, 0.96)
		sb_norm.border_color = Color(0.88, 0.74, 0.28, 0.95)
		sb_norm.set_border_width_all(2)
		sb_norm.set_corner_radius_all(8)
		sb_norm.shadow_color = Color(0, 0, 0, 0.7)
		sb_norm.shadow_size = 8

		var sb_hov := sb_norm.duplicate()
		sb_hov.bg_color = Color(0.22, 0.20, 0.12, 1.0)
		sb_hov.border_color = Color(1.0, 0.88, 0.48, 1.0)
		sb_hov.shadow_color = Color(0.88, 0.74, 0.28, 0.40)
		sb_hov.shadow_size = 12

		var sb_press := sb_norm.duplicate()
		sb_press.bg_color = Color(0.28, 0.24, 0.12, 1.0)
		sb_press.border_color = Color(0.88, 0.74, 0.28, 1.0)

		b.add_theme_stylebox_override("normal", sb_norm)
		b.add_theme_stylebox_override("hover", sb_hov)
		b.add_theme_stylebox_override("pressed", sb_press)
		b.add_theme_stylebox_override("focus", sb_hov)
		b.add_theme_color_override("font_color", Color(0.96, 0.90, 0.75, 1.0))
		b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		b.add_theme_color_override("font_pressed_color", Color(0.96, 0.90, 0.75, 1.0))
	else:
		var sb_norm := StyleBoxFlat.new()
		sb_norm.bg_color = Color(0.10, 0.12, 0.16, 0.90)
		sb_norm.border_color = Color(0.50, 0.45, 0.35, 0.80)
		sb_norm.set_border_width_all(1)
		sb_norm.set_corner_radius_all(8)
		sb_norm.shadow_color = Color(0, 0, 0, 0.5)
		sb_norm.shadow_size = 6

		var sb_hov := sb_norm.duplicate()
		sb_hov.bg_color = Color(0.16, 0.20, 0.28, 1.0)
		sb_hov.border_color = Color(0.88, 0.75, 0.40, 1.0)
		sb_hov.shadow_color = Color(0.88, 0.75, 0.40, 0.25)
		sb_hov.shadow_size = 10

		b.add_theme_stylebox_override("normal", sb_norm)
		b.add_theme_stylebox_override("hover", sb_hov)
		b.add_theme_stylebox_override("pressed", sb_hov)
		b.add_theme_stylebox_override("focus", sb_hov)
		b.add_theme_color_override("font_color", Color(0.80, 0.78, 0.72, 1.0))
		b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	return b


# --- Refresco ----------------------------------------------------------------------------
func _refresh() -> void:
	if _done:
		return
	_hint.text = _instruction()
	for child in _rows_box.get_children():
		child.queue_free()
	for child in _assigned_box.get_children():
		child.queue_free()

	if _in_ordering_phase():
		for box in _cfg.boxes:
			if box.ordered and _order[box.key].size() > 0:
				_rows_box.add_child(_ordering_row(box))
	else:
		_rows_box.add_child(_picking_row(_steps[_step]))
	# Las ya repartidas, chicas, con su destino (tocar una la devuelve).
	for box in _steps:
		if _order[box.key].is_empty() or (_in_ordering_phase() and box.ordered):
			continue
		_assigned_box.add_child(_assigned_group(box))

	_undo.visible = not _history.is_empty()
	var show_ready := _in_ordering_phase()
	if not _in_ordering_phase():
		var box: Dictionary = _steps[_step]
		show_ready = int(box.max) != int(box.min) and _order[box.key].size() >= int(box.min)
	_ready_btn.visible = show_ready
	_ready_btn.text = "Listo" if _in_ordering_phase() else "Siguiente"


func _card_node(i: int, scale: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150.0 * scale, 210.0 * scale)
	holder.size = holder.custom_minimum_size
	var card = CardScene.instantiate()
	card.load_from_data(_cfg.cards[i])
	card.custom_minimum_size = Vector2(150, 210)
	card.size = Vector2(150, 210)
	card.scale = Vector2(scale, scale)
	card.base_scale = Vector2(scale, scale)
	card.can_interact = false
	card.drag_enabled = false
	_ignore_mouse(card)
	holder.add_child(card)
	return holder


## Fila del paso actual: tocar una carta elegible la manda a ese destino.
func _picking_row(box: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in _order[_cfg.start]:
		var holder := _card_node(i, _scale)
		var ok: bool = box.eligible[i]
		holder.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.35)
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ok else Control.CURSOR_ARROW
		holder.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and ok:
				_assign(i, box.key))
		row.add_child(holder)
	return row


func _assigned_group(box: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := Label.new()
	cap.text = str(box.label)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_override("font", FONT_BODY)
	cap.add_theme_font_size_override("font_size", 20)
	cap.add_theme_color_override("font_color", GOLD)
	col.add_child(cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in _order[box.key]:
		var holder := _card_node(i, _small)
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		holder.tooltip_text = "Toca para devolverla"
		holder.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_unassign(i))
		row.add_child(holder)
	col.add_child(row)
	return col


## Fila de una zona ordenada: las cartas se arrastran solo en horizontal; al soltar, toman el lugar
## más cercano.
func _ordering_row(box: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	if _count_ordered_boxes() > 1:
		var cap := Label.new()
		cap.text = str(box.label)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_override("font", FONT_BODY)
		cap.add_theme_font_size_override("font_size", 20)
		cap.add_theme_color_override("font_color", GOLD)
		col.add_child(cap)
	var list: Array = _order[box.key]
	var row := Control.new()
	var step_w: float = CARD_W + GAP
	row.custom_minimum_size = Vector2(maxf(step_w * list.size() - GAP, CARD_W), CARD_H)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(row)
	for pos in range(list.size()):
		var i: int = list[pos]
		var holder := _card_node(i, _scale)
		holder.position = Vector2(pos * step_w, 0)
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_default_cursor_shape = Control.CURSOR_DRAG if list.size() > 1 else Control.CURSOR_ARROW
		holder.gui_input.connect(_on_drag_input.bind(box.key, i, holder, row))
		row.add_child(holder)
	return col


func _count_ordered_boxes() -> int:
	var n := 0
	for box in _cfg.boxes:
		if box.ordered and _order[box.key].size() > 0:
			n += 1
	return n


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


# --- Acciones ----------------------------------------------------------------------------
func _assign(i: int, key: String) -> void:
	_order[_where[i]].erase(i)
	_order[key].append(i)
	_where[i] = key
	_history.append([i, key])
	_skip_finished_steps()
	_refresh()


func _unassign(i: int) -> void:
	var key: String = _where[i]
	if key == _cfg.start:
		return
	_order[key].erase(i)
	_order[_cfg.start].append(i)
	_where[i] = _cfg.start
	for h in range(_history.size() - 1, -1, -1):
		if int(_history[h][0]) == i:
			_history.remove_at(h)
			break
	# Vuelve al paso de esa zona.
	for s in range(_steps.size()):
		if _steps[s].key == key:
			_step = mini(_step, s)
	_refresh()


func _on_undo() -> void:
	if not _history.is_empty():
		_unassign(int(_history[-1][0]))


func _on_ready() -> void:
	if _in_ordering_phase():
		_done = true
		return
	_step += 1
	_skip_finished_steps()
	_refresh()


func _on_drag_input(ev: InputEvent, key: String, i: int, holder: Control, row: Control) -> void:
	var list: Array = _order[key]
	if list.size() < 2:
		return
	var step_w: float = CARD_W + GAP
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_drag = {"key": key, "i": i, "holder": holder, "offset": ev.position.x}
			holder.z_index = 10
			holder.scale = Vector2(1.06, 1.06)
		elif not _drag.is_empty():
			var target: int = clampi(int(round(holder.position.x / step_w)), 0, list.size() - 1)
			list.erase(i)
			list.insert(target, i)
			_drag = {}
			_refresh()
	elif ev is InputEventMouseMotion and not _drag.is_empty() and _drag.i == i:
		var x: float = clampf(holder.position.x + ev.position.x - float(_drag.offset), 0.0, step_w * (list.size() - 1))
		holder.position.x = x
		# Las demás se corren para mostrar dónde caería.
		var target: int = clampi(int(round(x / step_w)), 0, list.size() - 1)
		var others: Array = list.filter(func(v): return v != i)
		others.insert(target, -1)
		for child in row.get_children():
			if child == holder:
				continue
			var idx: int = row.get_children().find(child)
			var card_i: int = list[idx] if idx < list.size() else -1
			var slot: int = others.find(card_i)
			if slot >= 0:
				child.position.x = slot * step_w
