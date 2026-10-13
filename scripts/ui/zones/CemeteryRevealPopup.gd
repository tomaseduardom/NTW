extends RefCounted
## CemeteryRevealPopup — popup liviano con cartas del Cementerio como Nodos
## temporales clickeables, en una esquina de la pantalla y SIN oscurecer el
## resto (la mano y el campo siguen clickeables al mismo tiempo). Los Nodos
## se usan como candidatos de CardInteractionModule.await_target()/
## await_multi_target() junto con las cartas de la mano.
##
## 2026-10-13 (§62): era un bloque de ~44 líneas copiado casi idéntico en 6
## lugares (Golpe Solar, Shiji, la búsqueda Aliado/Tótem del Cementerio,
## Lobo Sagrado, GoldManagerTax y Prevención con Oro). La posición usa el
## arreglo de Lobo Sagrado (2026-09-25, "el popup del Cementerio ni
## aparece"): coordenadas absolutas del viewport, no anchors, que con el
## panel todavía sin tamaño podían dejarlo fuera de pantalla.
## Se usa con preload (sin class_name global), ver §54.

const CardScene := preload("res://scenes/cards/Card.tscn")


static func open(main: Node, cards_data: Array, owner_id: int, visible: bool = true,
		title: String = "Tu Cementerio") -> Dictionary:
	"""Devuelve {popup: CanvasLayer (o null si no hay cartas), nodes: Array}.
	El llamador libera 'popup' (queue_free) al terminar la elección.
	'visible' = false arma los Nodos sin mostrar el popup (p.ej. cuando elige
	el Remoto por red y el Anfitrión no tiene que verlo)."""
	var nodes: Array = []
	if cards_data.is_empty():
		return {"popup": null, "nodes": nodes}

	var popup := CanvasLayer.new()
	popup.layer = 40
	popup.visible = visible
	main.add_child(popup)
	var panel := PanelContainer.new()
	var viewport_size: Vector2 = main.get_viewport().get_visible_rect().size
	panel.position = Vector2(20, viewport_size.y - 260)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.03, 0.06, 0.92)
	pstyle.border_color = Color(0.85, 0.72, 0.28, 0.85)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(12)
	pstyle.content_margin_left = 10
	pstyle.content_margin_right = 10
	pstyle.content_margin_top = 8
	pstyle.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", pstyle)
	popup.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	scroll.add_child(hbox)

	for data in cards_data:
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(80.0, 112.0)
		var c_node = CardScene.instantiate()
		c_node.load_from_data(data)
		c_node.set_zone(Constants.Zone.CEMENTERIO)
		c_node.owner_id = owner_id
		c_node.controller_id = owner_id
		c_node.can_interact = true
		c_node.drag_enabled = false
		c_node.custom_minimum_size = Vector2(150.0, 210.0)
		c_node.size = Vector2(150.0, 210.0)
		c_node.scale = Vector2(0.533, 0.533)
		c_node.base_scale = Vector2(0.533, 0.533)
		main._connect_card_signals(c_node)
		wrapper.add_child(c_node)
		hbox.add_child(wrapper)
		nodes.append(c_node)
	return {"popup": popup, "nodes": nodes}
