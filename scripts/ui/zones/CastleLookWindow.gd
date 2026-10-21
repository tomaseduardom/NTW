extends RefCounted
## CastleLookWindow — ventana única para "mira N cartas del tope/fondo de un Castillo"
## (arquitectura.md §69): en la misma ventana se reparten las cartas a sus destinos (mano,
## Cementerio, Reserva...) y se ordenan las que vuelven al Castillo. Nada se mueve hasta confirmar;
## el motor es CastleLook.gd.
## Corre igual en el Anfitrión y en el Remoto (prompt "castle_look", resultado por red), así que
## todo lo que recibe es serializable: cartas como Dictionary y elegibilidad por zona (no
## Callables).
## config = {title: String, cards: [card_data...], boxes: [{key, label, min, max (-1 = sin tope),
## ordered: bool, eligible: [bool por carta]}], start: key de la zona (ordenada) donde empiezan
## todas}
## Devuelve {key: [índices de cards en orden]} (en una zona ordenada, el primero queda más arriba).
## Se usa con preload (sin class_name global; ver §54).

const CardScene := preload("res://scenes/cards/Card.tscn")
const CARD_SCALE := 0.85
const CARD_W := 150.0 * CARD_SCALE
const CARD_H := 210.0 * CARD_SCALE
const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")

var _main: Node
var _cfg: Dictionary
var _where: Array = []  # por carta: key de su zona actual
var _order: Dictionary = {}  # key -> [índices en orden]
var _selected: int = -1
var _done := false
var _layer: CanvasLayer
var _rows: Dictionary = {}  # key -> HBoxContainer
var _headers: Dictionary = {}  # key -> Button
var _hint: Label
var _confirm: Button


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
	for i in range(_cfg.cards.size()):
		_where.append(_cfg.start)
		_order[_cfg.start].append(i)
	_build()
	_refresh()
	while not _done:
		await _main.get_tree().process_frame
	_layer.queue_free()
	return _order.duplicate(true)


func _box(key: String) -> Dictionary:
	for b in _cfg.boxes:
		if b.key == key:
			return b
	return {}


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 60
	_main.add_child(_layer)
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.size = vp
	bg.color = Color(0.01, 0.01, 0.02, 0.80)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(bg)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.06, 0.98)
	style.border_color = Color(0.85, 0.72, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(minf(vp.x * 0.92, 1100.0), 0)
	_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = str(_cfg.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60))
	vbox.add_child(title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Sin autowrap: un Label con autowrap dentro del VBox pedía un alto enorme y el panel quedaba fuera
	# de pantalla.
	_hint.clip_text = true
	_hint.add_theme_font_override("font", FONT_BODY)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(_hint)

	for box in _cfg.boxes:
		var header := Button.new()
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_override("font", FONT_TITLE)
		header.add_theme_font_size_override("font_size", 14)
		header.pressed.connect(_on_header_pressed.bind(box.key))
		vbox.add_child(header)
		_headers[box.key] = header
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, CARD_H + (34.0 if box.ordered else 8.0))
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(scroll)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		scroll.add_child(row)
		_rows[box.key] = row

	_confirm = Button.new()
	_confirm.text = "Confirmar"
	_confirm.custom_minimum_size = Vector2(220, 40)
	_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_confirm.add_theme_font_override("font", FONT_TITLE)
	_confirm.add_theme_font_size_override("font_size", 15)
	_confirm.pressed.connect(func(): _done = true)
	vbox.add_child(_confirm)

	# Centrado cuando ya tiene tamaño.
	panel.resized.connect(func(): panel.position = (vp - panel.size) / 2.0)
	panel.position = (vp - panel.custom_minimum_size) / 2.0


func _refresh() -> void:
	var all_ok := true
	for box in _cfg.boxes:
		var count: int = _order[box.key].size()
		var cap: String = "" if int(box.max) < 0 else "/%d" % int(box.max)
		var need: String = "" if int(box.min) <= 0 or count >= int(box.min) else "  — faltan %d" % (int(box.min) - count)
		var order_note: String = "  (izquierda = más arriba)" if box.ordered and count > 1 else ""
		_headers[box.key].text = "%s  %d%s%s%s" % [box.label, count, cap, need, order_note]
		if count < int(box.min) or (int(box.max) >= 0 and count > int(box.max)):
			all_ok = false
		var row: HBoxContainer = _rows[box.key]
		for child in row.get_children():
			child.queue_free()
		for pos in range(count):
			row.add_child(_card_widget(_order[box.key][pos], box, pos, count))
	_confirm.disabled = not all_ok
	if _selected >= 0:
		_hint.text = "Ahora haz clic en la zona a la que va %s." % str(_cfg.cards[_selected].get("nombre", "la carta"))
	else:
		_hint.text = "Haz clic en una carta y luego en el nombre de la zona a la que va. ◀ ▶ cambian el orden."


func _card_widget(i: int, box: Dictionary, pos: int, count: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W + 6, CARD_H + 6)
	btn.flat = true
	btn.toggle_mode = false
	if i == _selected:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color(1.0, 0.85, 0.3, 0.35)
		sel.set_border_width_all(3)
		sel.border_color = Color(1.0, 0.85, 0.3)
		sel.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", sel)
		btn.add_theme_stylebox_override("hover", sel)
	btn.pressed.connect(_on_card_pressed.bind(i))
	var card = CardScene.instantiate()
	card.load_from_data(_cfg.cards[i])
	card.custom_minimum_size = Vector2(150, 210)
	card.size = Vector2(150, 210)
	card.position = Vector2(3, 3)
	# base_scale también (como ZoneBrowsePicker): Card vuelve a su base_scale
	# y la carta quedaba corrida sobre las flechas.
	card.scale = Vector2(CARD_SCALE, CARD_SCALE)
	card.base_scale = Vector2(CARD_SCALE, CARD_SCALE)
	card.can_interact = false
	card.drag_enabled = false
	_ignore_mouse(card)
	btn.add_child(card)
	col.add_child(btn)
	if box.ordered and count > 1:
		var arrows := HBoxContainer.new()
		arrows.alignment = BoxContainer.ALIGNMENT_CENTER
		var left := Button.new()
		left.text = "◀"
		left.disabled = pos == 0
		left.pressed.connect(_move.bind(box.key, pos, -1))
		var right := Button.new()
		right.text = "▶"
		right.disabled = pos == count - 1
		right.pressed.connect(_move.bind(box.key, pos, 1))
		arrows.add_child(left)
		arrows.add_child(right)
		col.add_child(arrows)
	return col


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _on_card_pressed(i: int) -> void:
	_selected = -1 if _selected == i else i
	_refresh()


func _on_header_pressed(key: String) -> void:
	if _selected < 0:
		return
	var box: Dictionary = _box(key)
	var i: int = _selected
	if _where[i] == key:
		_selected = -1
		_refresh()
		return
	if not box.eligible[i]:
		_hint.text = "%s no puede ir a %s." % [str(_cfg.cards[i].get("nombre", "Esa carta")), box.label]
		return
	if int(box.max) >= 0 and _order[key].size() >= int(box.max):
		_hint.text = "%s ya está completa." % box.label
		return
	_order[_where[i]].erase(i)
	_order[key].append(i)
	_where[i] = key
	_selected = -1
	_refresh()


func _move(key: String, pos: int, delta: int) -> void:
	var list: Array = _order[key]
	var to: int = pos + delta
	if to < 0 or to >= list.size():
		return
	var tmp = list[pos]
	list[pos] = list[to]
	list[to] = tmp
	_refresh()
