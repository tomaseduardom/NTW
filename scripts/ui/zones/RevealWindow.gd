extends RefCounted
## RevealWindow — visor de "mostrar" (muestra cartas del tope hasta mostrar...): solo las cartas que
## indica el efecto, con el mismo estilo y tamaño que el visor de mirar (CastleLookWindow) y la menor
## cantidad de clics:
##   mode "show":  las cartas que van a tu mano (o que se juegan) y "Listo".
##   mode "pick":  tocas la(s) que eliges (count) y se cierra solo.
##   mode "order": tocas en el orden en que se juegan; cada una muestra su número; se cierra al
##                 completar (la última va sola).
## config = {title, hint, cards: [card_data...], mode, count}. Devuelve {"picked": [índices]} (en
## "order", todos en orden; en "show", []).
## RevealWindow.run(main, chooser, config): el bot elige solo; el Remoto lo ve en su pantalla (prompt
## "reveal_window", RemoteMirrorController); si no, la ventana local.
## Se usa con preload (ver §54).

const CardScene := preload("res://scenes/cards/Card.tscn")
const MAX_SCALE := 1.7
const GAP := 20.0
const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")
const GOLD := Color(0.85, 0.72, 0.28)
const INK := Color(0.08, 0.07, 0.10)

var _main: Node
var _cfg: Dictionary
var _picked: Array = []
var _done := false
var _layer: CanvasLayer
var _row: HBoxContainer
var _hint: Label
var _undo: Button
var _scale: float = MAX_SCALE


## Punto de entrada para los efectos.
static func run(main: Node, chooser: int, config: Dictionary) -> Dictionary:
	var cards: Array = config.get("cards", [])
	if cards.is_empty():
		return {"picked": []}
	if load("res://scripts/core/game/PlayerSide.gd").is_bot(chooser):
		return auto_pick(config)
	if chooser == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		NetworkClient.send_message({"op": "prompt", "kind": "reveal_window", "config": config})
		var intent: Dictionary = await NetworkClient.await_intent(["reveal_window_choice"])
		return validate(config, intent.get("result", {}))
	var w = load("res://scripts/ui/zones/RevealWindow.gd").new()
	return await w.open(main, config)


## Atajos.
static func show_cards(main: Node, chooser: int, cards: Array, title: String, hint: String = "Van a tu mano") -> void:
	await run(main, chooser, {"title": title, "hint": hint, "cards": cards, "mode": "show"})


static func pick_one(main: Node, chooser: int, cards: Array, title: String, hint: String) -> int:
	var r: Dictionary = await run(main, chooser, {"title": title, "hint": hint, "cards": cards, "mode": "pick", "count": 1})
	return int(r.picked[0]) if not r.picked.is_empty() else 0


static func choose_order(main: Node, chooser: int, cards: Array, title: String, hint: String = "Toca las cartas en el orden en que se juegan") -> Array:
	if cards.size() < 2:
		return cards.duplicate()
	var r: Dictionary = await run(main, chooser, {"title": title, "hint": hint, "cards": cards, "mode": "order"})
	return r.picked.map(func(i): return cards[int(i)])


static func auto_pick(config: Dictionary) -> Dictionary:
	var n: int = config.get("cards", []).size()
	match str(config.get("mode", "show")):
		"pick":
			var out: Array = []
			for i in range(mini(int(config.get("count", 1)), n)):
				out.append(i)
			return {"picked": out}
		"order":
			return {"picked": range(n)}
	return {"picked": []}


static func validate(config: Dictionary, raw: Dictionary) -> Dictionary:
	var n: int = config.get("cards", []).size()
	var picked: Array = []
	for v in raw.get("picked", []):
		var i: int = int(v)
		if i < 0 or i >= n or picked.has(i):
			return auto_pick(config)
		picked.append(i)
	match str(config.get("mode", "show")):
		"pick":
			if picked.size() != mini(int(config.get("count", 1)), n):
				return auto_pick(config)
		"order":
			if picked.size() != n:
				return auto_pick(config)
		_:
			picked = []
	return {"picked": picked}


func open(main: Node, config: Dictionary) -> Dictionary:
	_main = main
	_cfg = config
	_fit_scale()
	_build()
	_refresh()
	# Tiempo agotado (TurnClock): se resuelve con la elección por defecto. Desde el historial
	# ("browse") solo se mira: no cuenta como decisión ni se cierra sola.
	var browse := bool(config.get("browse", false))
	var force_gen: int = NetworkClient.force_gen
	if not browse:
		NetworkClient.local_waits += 1
	while not _done:
		if not browse and NetworkClient.ui_forced(force_gen):
			_picked = auto_pick(_cfg).picked
			NetworkClient.ui_forced_done()
			break
		await _main.get_tree().process_frame
	if not browse:
		NetworkClient.local_waits = maxi(0, NetworkClient.local_waits - 1)
	_layer.queue_free()
	return {"picked": _picked.duplicate()}


func _fit_scale() -> void:
	var vp: Vector2 = _main.get_viewport().get_visible_rect().size
	var n: int = maxi(_cfg.cards.size(), 1)
	var by_w: float = (vp.x * 0.94 - GAP * (n - 1)) / (150.0 * n)
	var by_h: float = (vp.y - 280.0) / 210.0
	_scale = clampf(minf(MAX_SCALE, minf(by_w, by_h)), 0.6, MAX_SCALE)


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
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size = vp
	_layer.add_child(vbox)

	var title := Label.new()
	title.text = str(_cfg.get("title", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_BODY)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.75, 0.72, 0.80))
	vbox.add_child(title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_override("font", FONT_TITLE)
	_hint.add_theme_font_size_override("font_size", 36)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	vbox.add_child(_hint)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(GAP))
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_row)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)
	_undo = _button("Deshacer", false)
	_undo.pressed.connect(func() -> void:
		if not _picked.is_empty():
			_picked.pop_back()
			_refresh())
	buttons.add_child(_undo)
	if str(_cfg.get("mode", "show")) == "show":
		var ok := _button("Listo", true)
		ok.pressed.connect(func() -> void: _done = true)
		buttons.add_child(ok)


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 60)
	b.add_theme_font_override("font", FONT_TITLE)
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	if primary:
		sb.bg_color = GOLD
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, INK)
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.45, 0.42, 0.52)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	return b


func _refresh() -> void:
	var mode: String = str(_cfg.get("mode", "show"))
	_hint.text = str(_cfg.get("hint", ""))
	_undo.visible = mode == "order" and not _picked.is_empty()
	for child in _row.get_children():
		child.queue_free()
	for i in range(_cfg.cards.size()):
		_row.add_child(_card_holder(i, mode))


func _card_holder(i: int, mode: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150.0 * _scale, 210.0 * _scale)
	var card = CardScene.instantiate()
	card.load_from_data(_cfg.cards[i])
	card.custom_minimum_size = Vector2(150, 210)
	card.size = Vector2(150, 210)
	card.scale = Vector2(_scale, _scale)
	card.base_scale = Vector2(_scale, _scale)
	card.can_interact = false
	card.drag_enabled = false
	_ignore_mouse(card)
	holder.add_child(card)
	var pos: int = _picked.find(i)
	if mode == "order" and pos >= 0:
		holder.add_child(_badge(str(pos + 1)))
		holder.modulate = Color(1, 1, 1, 0.75)
	if mode != "show":
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		holder.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_tap(i))
	return holder


func _badge(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.set_corner_radius_all(24)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(-12, -12)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_TITLE)
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", INK)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _on_tap(i: int) -> void:
	var mode: String = str(_cfg.get("mode", "show"))
	var n: int = _cfg.cards.size()
	if _picked.has(i):
		return
	_picked.append(i)
	if mode == "pick" and _picked.size() >= mini(int(_cfg.get("count", 1)), n):
		_done = true
		return
	if mode == "order" and _picked.size() >= n - 1:
		for k in range(n):
			if not _picked.has(k):
				_picked.append(k)
		_done = true
		return
	_refresh()


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
