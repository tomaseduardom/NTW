extends RefCounted
## BoardChoice — elegir entre opciones SOBRE LA MESA, sin ventana (reemplaza el popup de
## SelectionDialogs.await_choice() para quien elige en esta pantalla; el Remoto la usa igual desde
## RemoteMirrorController). Cada opción es una ficha anclada a lo que afecta: "Roba..." junto a tu
## Castillo, "...Cementerio" junto al Cementerio, "...mano" junto a tu mano; las que no tienen dónde
## anclarse, junto a la carta que causa el efecto (o bajo la franja de arriba). Arriba, una franja
## fina dice qué se está resolviendo. El tablero queda a la vista; los clics fuera de las fichas no
## hacen nada mientras se elige.
## Uso: var idx: int = await BoardChoiceScript.choose(main, title, options, source_card, target_sets)
## target_sets (opcional) = {índice de opción: [cartas en juego]}: esas cartas brillan y tocar una elige
## esa opción Y esa carta de una vez (queda en BoardChoice.last_target; EffectInterpreter la usa como
## objetivo). La ficha de esa opción va sobre esas cartas.
## Se usa con preload (ver §54).

static var last_target: Node = null


static func reset_match() -> void:
	last_target = null

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/Marcellus-Regular.ttf")
const GOLD := Color(0.85, 0.72, 0.28)
const INK := Color(0.08, 0.07, 0.10)


static func choose(main: Node, title: String, options: Array, source_card = null, target_sets: Dictionary = {}) -> int:
	last_target = null
	var state := {"picked": -1, "target": null}
	var layer := CanvasLayer.new()
	layer.layer = 70
	main.add_child(layer)
	var vp: Vector2 = main.get_viewport().get_visible_rect().size

	# Bloquea el tablero sin taparlo.
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.18)
	blocker.size = vp
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(blocker)

	# Franja de arriba: qué se está resolviendo.
	var banner := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.06, 0.05, 0.09, 0.92)
	bsb.border_color = GOLD
	bsb.border_width_bottom = 2
	bsb.set_corner_radius_all(0)
	bsb.content_margin_left = 20
	bsb.content_margin_right = 20
	bsb.content_margin_top = 8
	bsb.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", bsb)
	var blabel := Label.new()
	blabel.text = title
	blabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blabel.add_theme_font_override("font", FONT_BODY)
	blabel.add_theme_font_size_override("font_size", 16)
	blabel.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	banner.add_child(blabel)
	banner.position = Vector2(0, 0)
	banner.custom_minimum_size = Vector2(vp.x, 0)
	layer.add_child(banner)

	# Objetivos específicos en mesa: si una opción los tiene, brillan y se pueden tocar directo
	for i in range(options.size()):
		var targets: Array = target_sets.get(i, []).filter(func(n): return n is Control and is_instance_valid(n) and n.is_visible_in_tree())
		if not targets.is_empty():
			for n in targets:
				layer.add_child(_target_button(n, func() -> void:
					state.target = n
					state.picked = i))

	# Si hay una carta fuente activa, dibujar sutil resalte
	if source_card is Control and is_instance_valid(source_card) and source_card.is_inside_tree() and source_card.is_visible_in_tree():
		layer.add_child(_outline(source_card.get_global_rect()))

	# Contenedor central unificado para los popouts de habilidades en el centro del juego
	var center_panel := PanelContainer.new()
	var cp_style := StyleBoxFlat.new()
	cp_style.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	cp_style.border_color = Color(0.78, 0.65, 0.32, 0.90)
	cp_style.set_border_width_all(2)
	cp_style.set_corner_radius_all(14)
	cp_style.shadow_color = Color(0, 0, 0, 0.85)
	cp_style.shadow_size = 24
	cp_style.shadow_offset = Vector2(0, 8)
	cp_style.content_margin_left = 24
	cp_style.content_margin_right = 24
	cp_style.content_margin_top = 16
	cp_style.content_margin_bottom = 16
	center_panel.add_theme_stylebox_override("panel", cp_style)

	var chips_container: BoxContainer
	if options.size() <= 3:
		chips_container = HBoxContainer.new()
		chips_container.add_theme_constant_override("separation", 16)
	else:
		chips_container = VBoxContainer.new()
		chips_container.add_theme_constant_override("separation", 10)
	chips_container.alignment = BoxContainer.ALIGNMENT_CENTER
	center_panel.add_child(chips_container)

	for i in range(options.size()):
		chips_container.add_child(_chip(str(options[i]), func() -> void: state.picked = i))

	layer.add_child(center_panel)

	# Centrado exacto en pantalla (en el centro del juego)
	center_panel.resized.connect(func() -> void:
		center_panel.position = (vp - center_panel.size) / 2.0
	)
	center_panel.position = (vp - Vector2(320, 80)) / 2.0

	# Tiempo agotado (TurnClock): la primera opción.
	var force_gen: int = NetworkClient.force_gen
	NetworkClient.local_waits += 1
	while state.picked < 0 and is_instance_valid(layer):
		if NetworkClient.ui_forced(force_gen):
			state.picked = 0
			NetworkClient.ui_forced_done()
			break
		await main.get_tree().process_frame
	NetworkClient.local_waits = maxi(0, NetworkClient.local_waits - 1)
	if is_instance_valid(layer):
		layer.queue_free()
	last_target = state.target if state.target is Node and is_instance_valid(state.target) else null
	return maxi(state.picked, 0)


## Contorno dorado tocable sobre una carta en juego (elige la opción y esa carta).
static func _target_button(node: Control, on_press: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	var rect: Rect2 = node.get_global_rect()
	b.position = rect.position - Vector2(4, 4)
	b.size = rect.size + Vector2(8, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.10)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	var hover := sb.duplicate()
	hover.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(on_press)
	return b


static func _place(rect: Rect2, size: Vector2, vp: Vector2) -> Vector2:
	var x: float = clampf(rect.get_center().x - size.x / 2.0, 12.0, vp.x - size.x - 12.0)
	var y: float = rect.position.y - size.y - 12.0
	if y < 56.0:
		y = rect.end.y + 12.0
	y = clampf(y, 56.0, vp.y - size.y - 12.0)
	return Vector2(x, y)


static func _chip(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 48)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_TITLE)
	b.add_theme_font_size_override("font_size", 15)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.14, 0.10, 0.96)
	sb.border_color = Color(0.88, 0.74, 0.28, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 8

	var hover := sb.duplicate()
	hover.bg_color = Color(0.22, 0.20, 0.12, 1.0)
	hover.border_color = Color(1.0, 0.88, 0.48, 1.0)
	hover.shadow_color = Color(0.88, 0.74, 0.28, 0.40)
	hover.shadow_size = 12

	var pressed := sb.duplicate()
	pressed.bg_color = Color(0.28, 0.24, 0.12, 1.0)
	pressed.border_color = Color(0.88, 0.74, 0.28, 1.0)

	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(0.96, 0.90, 0.75, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.96, 0.90, 0.75, 1.0))

	b.pressed.connect(on_press)
	return b


static func _outline(rect: Rect2) -> Control:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.08)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position - Vector2(6, 6)
	p.size = rect.size + Vector2(12, 12)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _fallback_rect(main: Node, source_card, vp: Vector2) -> Rect2:
	if source_card is Control and is_instance_valid(source_card) and source_card.is_inside_tree() and source_card.is_visible_in_tree():
		return source_card.get_global_rect()
	return Rect2(Vector2(vp.x / 2.0 - 60.0, 70.0), Vector2(120, 10))


## Ancla de una opción según lo que dice (siempre desde quien elige: "tu" = el lado de abajo).
static func _anchor_for(text: String, main: Node) -> Dictionary:
	var t := text.to_lower()
	var rival: bool = "oponente" in t or "rival" in t
	var side := "OpponentArea/Opponent" if rival else "PlayerArea/Player"
	var key := ""
	var path := ""
	if "cementerio" in t:
		key = "cem_r" if rival else "cem"
		path = "GameBoard/%sCementerio" % side
	elif "destierro" in t:
		key = "exile_r" if rival else "exile"
		path = "GameBoard/%sDestierro" % side
	elif "roba" in t or "castillo" in t or "tope" in t or "fondo" in t or "bota" in t or "baraj" in t:
		key = "castle_r" if rival else "castle"
		path = "GameBoard/%sCastillo" % side
	elif "mano" in t and not rival:
		key = "hand"
		path = "GameBoard/PlayerArea/PlayerHand"
	if path.is_empty():
		return {}
	var node = main.get_node_or_null(path)
	if not (node is Control) or not node.is_visible_in_tree():
		return {}
	return {"key": key, "rect": node.get_global_rect()}
