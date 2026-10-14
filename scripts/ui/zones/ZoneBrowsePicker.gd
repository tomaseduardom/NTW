extends Node
class_name ZoneBrowsePicker
## ZoneBrowsePicker — selector de cartas en zonas apiladas (Castillo,
## Cementerio, Destierro) directamente sobre el tablero (2026-10-11, a pedido
## del usuario: "el mazo y el castillo también tiene que ser un selector y no
## un popup, además si la opción es en el castillo y/o cementerio la idea es
## poder ver el castillo, luego hacer click afuera, ver el cementerio y
## después confirmar toda la acción" — ejemplo: Arturo de Bretaña).
##
## Las zonas que participan brillan en el tablero; clic en una abre un visor
## con TODAS sus cartas (las elegibles destacadas, el resto atenuadas), clic
## en una carta la marca/desmarca, clic afuera cierra el visor SIN perder lo
## elegido, y el botón de paso del HUD (o el del visor) confirma la acción
## completa. Corre siempre en la pantalla de quien elige: el Anfitrión lo usa
## directo (ActionSearch) y el Remoto lo corre al recibir el prompt
## "zone_pick" (RemoteMirrorController) — en ambos casos "own" es relativo a
## esa pantalla.

const CardScene = preload("res://scenes/cards/Card.tscn")
## Escala de las cartas del visor: se calcula con el alto de la pantalla
## (2026-10-14, a pedido del usuario: "te muestra casi todo el mazo con las
## cartas muy pequeñas"), entre estos dos topes.
const VIEWER_SCALE_MIN := 0.7
const VIEWER_SCALE_MAX := 1.05
const TYPE_FILTERS := [
	["Todas", -1],
	["Aliados", Constants.CardType.ALIADO],
	["Talismanes", Constants.CardType.TALISMAN],
	["Armas", Constants.CardType.ARMA],
	["Tótems", Constants.CardType.TOTEM],
	["Oros", Constants.CardType.ORO],
]
const ZONE_PANEL_NAMES := {
	Constants.Zone.CASTILLO: "Castillo",
	Constants.Zone.CEMENTERIO: "Cementerio",
	Constants.Zone.DESTIERRO: "Destierro",
}

var _main: Node = null
var _active: bool = false
var _done: bool = false
var _pools: Array = []  # [{is_own: bool, zone: int, cards: [{data: Dictionary, eligible: bool}]}]
var _selected: Array = []  # [[pool_idx, card_idx], ...] en orden de clic
var _min: int = 0
var _max: int = 1
var _distinct_names: bool = false
var _title: String = ""
var _panel_restores: Array = []  # Callables que devuelven cada panel del tablero a su estado previo
var _viewer: CanvasLayer = null
var _viewer_pool: int = -1
var _viewer_markers: Dictionary = {}  # card_idx -> Panel (borde de "elegida") del visor abierto
var _viewer_count_label: Label = null
var _viewer_confirm_btn: Button = null
## Cartas de la mano que también son candidatas (2026-10-12, Miguel: "juega
## una carta de tu mano o de un Cementerio"). Brillan en la mano y un clic
## en una la elige de inmediato (devuelve [-1, índice]).
var _hand_nodes: Array = []
## Un solo Castillo (2026-10-14, a pedido del usuario — Duelo Espacial /
## voragh el devorador: "en caso de escoger un castillo ya no puedo cambiar
## el castillo... pero sí puedo volver a ver los cementerios"): con más de un
## Castillo en juego, el primero que se abre es el único que se puede mirar.
var _locked_castle: int = -1
var _opened_castles: Array = []  # pools de Castillo abiertos (quien llama los baraja)
var _panel_pulses: Dictionary = {}  # pool_idx -> {panel, tween}
## Filtro del visor (tipo + nombre); se recuerda al cambiar de zona.
var _filter_type: int = -1
var _filter_text: String = ""
var _viewer_wrappers: Array = []  # [{node, data}]


func setup(main: Node) -> void:
	_main = main


func is_active() -> bool:
	return _active


func last_opened_castles() -> Array:
	"""Índices de los pools de Castillo que se miraron en la última selección."""
	return _opened_castles.duplicate()


static func zone_label(is_own: bool, zone: int) -> String:
	var zone_name: String = ZONE_PANEL_NAMES.get(zone, "Zona")
	return "Tu %s" % zone_name if is_own else "%s rival" % zone_name


func pick(title: String, pools: Array, min_count: int, max_count: int, distinct_names: bool = false,
		hand_nodes: Array = []) -> Array:
	"""Abre el selector y espera la confirmación. 'pools': [{is_own, zone,
	cards: [{data, eligible}]}]. Devuelve [[pool_idx, card_idx], ...] en el
	orden en que se eligieron (vacío si se confirmó sin elegir nada).
	'hand_nodes' (opcional, 2026-10-12): cartas de la mano que también son
	elegibles — brillan y un clic en una termina la selección con
	[[-1, índice_en_hand_nodes]] (pensado para elegir UNA carta, p.ej.
	Miguel). El clic llega por try_hand_click(); en el Remoto los Nodos son
	los de su mano espejo (ver ActionSearch.pick_in_zones())."""
	if _active:
		push_warning("[ZoneBrowsePicker] Ya hay una selección en curso")
		return []
	_active = true
	_done = false
	_selected = []
	_pools = pools
	_min = maxi(min_count, 0)
	_max = max_count if max_count > 0 else 999
	_distinct_names = distinct_names
	_title = title
	_locked_castle = -1
	_opened_castles = []
	_panel_pulses = {}
	_filter_type = -1
	_filter_text = ""

	var labels: Array = []
	for i in range(_pools.size()):
		_arm_panel(i)
		labels.append(zone_label(_pools[i].is_own, _pools[i].zone))
	_main._update_debug("%s — clic en %s para ver sus cartas; confirma con el botón de paso" % [
		title, " / ".join(labels)])
	_refresh_paso()
	_hand_nodes = hand_nodes.duplicate()
	if _castle_pool_count() > 1:
		# Con varios Castillos no se abre ninguno solo: abrir uno ya es
		# elegirlo (ver _locked_castle).
		pass
	elif _hand_nodes.is_empty():
		_open_viewer(_first_pool_with_eligible())
	else:
		# Con candidatas en la mano no se abre el visor solo (taparía la
		# mano): los Cementerios brillan y se abren con clic.
		_arm_hand_pick()
	while not _done:
		await get_tree().process_frame
	_disarm_hand_pick()
	_close_viewer()
	for restore in _panel_restores:
		restore.call()
	_panel_restores = []
	_active = false
	if _main._game_hud:
		_main._game_hud.stop_paso_glow()
		_main._game_hud.update_paso_button_state()
	return _selected.duplicate()


func _arm_hand_pick() -> void:
	for c in _hand_nodes:
		if is_instance_valid(c):
			c.set_activatable(true, CardBadges.GLOW_COLOR_CELESTE, &"zone_pick")
	_main._update_debug("%s — clic en una carta brillante de tu mano, o abre un Cementerio" % _title)


func try_hand_click(card: Node) -> bool:
	"""Lo llama CardInteractionModule ANTES de cualquier otro manejo del
	clic (en el Anfitrión y en el Remoto, donde los clics van al espejo):
	si es una carta candidata de la mano, la elige y termina la selección."""
	if not _active or _done or _hand_nodes.is_empty() or not (card in _hand_nodes):
		return false
	_selected = [[-1, _hand_nodes.find(card)]]
	_done = true
	return true


func _disarm_hand_pick() -> void:
	if _hand_nodes.is_empty():
		return
	_unglow_hand()
	_hand_nodes = []


func _unglow_hand() -> void:
	for c in _hand_nodes:
		if is_instance_valid(c):
			c.set_activatable(false, CardBadges.GLOW_COLOR_CELESTE, &"zone_pick")


func on_paso_pressed() -> void:
	"""Botón de paso del HUD (y tecla P) mientras el selector está activo."""
	_try_confirm()


func _try_confirm() -> void:
	if _selected.size() < _min:
		_main._update_debug("Elige al menos %d carta(s)" % _min)
		return
	_done = true


func _castle_pool_count() -> int:
	var n := 0
	for pool in _pools:
		if pool.zone == Constants.Zone.CASTILLO:
			n += 1
	return n


func _lock_castle(pool_idx: int) -> void:
	"""Ata la selección a este Castillo: los demás dejan de brillar."""
	_locked_castle = pool_idx
	for i in _panel_pulses:
		if i == pool_idx or _pools[i].zone != Constants.Zone.CASTILLO:
			continue
		var entry: Dictionary = _panel_pulses[i]
		entry.tween.kill()
		entry.panel.modulate = Color(0.55, 0.55, 0.55, 1.0)
		entry.panel.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN


func _first_pool_with_eligible() -> int:
	for i in range(_pools.size()):
		for c in _pools[i].cards:
			if c.eligible:
				return i
	return 0 if not _pools.is_empty() else -1


# =============================================================================
# PANELES DEL TABLERO
# =============================================================================
func _panel_for(pool: Dictionary) -> Control:
	if not _main or not _main.get("_zone_manager") or not _main._zone_manager:
		return null
	return _main._zone_manager.get_zone_panel(ZONE_PANEL_NAMES.get(pool.zone, ""), 0 if pool.is_own else 1)


func _arm_panel(pool_idx: int) -> void:
	var panel: Control = _panel_for(_pools[pool_idx])
	if not panel:
		return
	var prev_filter := panel.mouse_filter
	var prev_cursor := panel.mouse_default_cursor_shape
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pulse := panel.create_tween().set_loops()
	pulse.tween_property(panel, "modulate", Color(1.35, 1.25, 0.95, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(panel, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	_panel_pulses[pool_idx] = {"panel": panel, "tween": pulse}
	var on_input := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_open_viewer(pool_idx)
	panel.gui_input.connect(on_input)
	_panel_restores.append(func() -> void:
		if panel.gui_input.is_connected(on_input):
			panel.gui_input.disconnect(on_input)
		pulse.kill()
		panel.modulate = Color.WHITE
		panel.mouse_filter = prev_filter
		panel.mouse_default_cursor_shape = prev_cursor)


# =============================================================================
# VISOR DE UNA ZONA
# =============================================================================
func _open_viewer(pool_idx: int) -> void:
	if pool_idx < 0 or pool_idx >= _pools.size():
		return
	var pool: Dictionary = _pools[pool_idx]
	if pool.zone == Constants.Zone.CASTILLO:
		if _locked_castle >= 0 and _locked_castle != pool_idx:
			_main._update_debug("Ya miraste %s: solo puedes buscar en ese Castillo (los Cementerios sí se pueden ver)" \
				% zone_label(_pools[_locked_castle].is_own, Constants.Zone.CASTILLO))
			return
		if _locked_castle < 0 and _castle_pool_count() > 1:
			_lock_castle(pool_idx)
		if not _opened_castles.has(pool_idx):
			_opened_castles.append(pool_idx)
	_close_viewer()
	_viewer_pool = pool_idx

	_viewer = CanvasLayer.new()
	_viewer.layer = 60
	add_child(_viewer)

	# Clic afuera (en el fondo) cierra el visor sin perder lo elegido.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_viewer())
	_viewer.add_child(bg)

	var frame := PanelContainer.new()
	frame.anchor_left = 0.03
	frame.anchor_right = 0.97
	frame.anchor_top = 0.04
	frame.anchor_bottom = 0.96
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.97)
	style.border_color = Color(0.78, 0.65, 0.35, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	frame.add_theme_stylebox_override("panel", style)
	_viewer.add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "%s — %s" % [_title, zone_label(pool.is_own, pool.zone)]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	vbox.add_child(title_lbl)

	var hint := Label.new()
	hint.text = "Clic en las cartas brillantes para elegirlas · clic derecho para ampliar · clic afuera para cerrar y ver otra zona"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65, 0.85))
	vbox.add_child(hint)

	if pool.cards.size() > 8:
		vbox.add_child(_build_filter_bar(pool))

	# Tamaño de carta según la pantalla, y tantas columnas como entren.
	var vp: Vector2 = _viewer.get_viewport().get_visible_rect().size
	var card_scale: float = clampf(vp.y * 0.00095, VIEWER_SCALE_MIN, VIEWER_SCALE_MAX)
	var cell_w: float = 150.0 * card_scale
	var avail_w: float = vp.x * 0.94 - 36.0 - 16.0
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var grid := GridContainer.new()
	grid.columns = maxi(3, int((avail_w + 12.0) / (cell_w + 12.0)))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	center.add_child(grid)

	_viewer_markers = {}
	_viewer_wrappers = []
	for card_idx in _display_order(pool):
		var wrapper := _build_viewer_card(pool_idx, card_idx, card_scale)
		grid.add_child(wrapper)
		_viewer_wrappers.append({"node": wrapper, "data": pool.cards[card_idx].data})
	_apply_filter()
	if pool.cards.is_empty():
		var empty := Label.new()
		empty.text = "No hay cartas en esta zona."
		grid.add_child(empty)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)
	_viewer_count_label = Label.new()
	_viewer_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_viewer_count_label)
	var close_btn := Button.new()
	close_btn.text = "Cerrar"
	close_btn.pressed.connect(_close_viewer)
	footer.add_child(close_btn)
	_viewer_confirm_btn = Button.new()
	_viewer_confirm_btn.pressed.connect(_try_confirm)
	footer.add_child(_viewer_confirm_btn)
	_refresh_paso()


func _display_order(pool: Dictionary) -> Array:
	"""El Castillo se muestra ordenado (elegibles primero, luego por tipo/
	coste/nombre) para no revelar el orden real del mazo; el resto de las
	zonas, en su orden de siempre."""
	var order: Array = range(pool.cards.size())
	if pool.zone == Constants.Zone.CASTILLO:
		var cards: Array = pool.cards
		order.sort_custom(func(a: int, b: int) -> bool:
			var ca: Dictionary = cards[a]
			var cb: Dictionary = cards[b]
			if ca.eligible != cb.eligible:
				return ca.eligible
			var ka := [int(ca.data.get("tipo", 0)), int(ca.data.get("coste", 0)), str(ca.data.get("nombre", ""))]
			var kb := [int(cb.data.get("tipo", 0)), int(cb.data.get("coste", 0)), str(cb.data.get("nombre", ""))]
			for i in range(3):
				if ka[i] != kb[i]:
					return ka[i] < kb[i]
			return a < b)
	return order


func _build_filter_bar(pool: Dictionary) -> Control:
	"""Botones por tipo (con cuántas hay de cada uno) y búsqueda por nombre."""
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	var counts: Dictionary = {}
	for c in pool.cards:
		var t := int(c.data.get("tipo", -1))
		counts[t] = int(counts.get(t, 0)) + 1
	var group := ButtonGroup.new()
	for f in TYPE_FILTERS:
		var n: int = pool.cards.size() if f[1] == -1 else int(counts.get(f[1], 0))
		if n == 0 and f[1] != -1:
			continue
		var b := Button.new()
		b.text = "%s (%d)" % [f[0], n]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = f[1] == _filter_type
		var t: int = f[1]
		b.pressed.connect(func() -> void:
			_filter_type = t
			_apply_filter())
		bar.add_child(b)
	var search := LineEdit.new()
	search.placeholder_text = "Buscar por nombre"
	search.custom_minimum_size = Vector2(220, 0)
	search.text = _filter_text
	search.clear_button_enabled = true
	search.text_changed.connect(func(txt: String) -> void:
		_filter_text = txt
		_apply_filter())
	bar.add_child(search)
	return bar


func _apply_filter() -> void:
	var needle := _filter_text.strip_edges().to_lower()
	for w in _viewer_wrappers:
		if not is_instance_valid(w.node):
			continue
		var ok_type: bool = _filter_type == -1 or int(w.data.get("tipo", -1)) == _filter_type
		var ok_name: bool = needle == "" or needle in str(w.data.get("nombre", "")).to_lower()
		w.node.visible = ok_type and ok_name


func _build_viewer_card(pool_idx: int, card_idx: int, card_scale: float) -> Control:
	var pool: Dictionary = _pools[pool_idx]
	var entry: Dictionary = pool.cards[card_idx]
	var wrapper := Control.new()
	var scale_v := Vector2(card_scale, card_scale)
	wrapper.custom_minimum_size = Vector2(150.0, 210.0) * scale_v

	var card = CardScene.instantiate()
	var shown: Dictionary = entry.data.duplicate()
	shown["esta_oculta"] = false
	card.load_from_data(shown)
	# Zona real ANTES del dueño (2026-10-14, bug real: las cartas del
	# Castillo rival salían giradas 180° — current_zone arranca en MANO y
	# Card gira toda carta rival "en la mano o en juego").
	card.current_zone = pool.zone
	card.owner_id = 0 if pool.is_own else 1
	card.can_interact = false
	card.drag_enabled = false
	card.custom_minimum_size = Vector2(150.0, 210.0)
	card.size = Vector2(150.0, 210.0)
	card.scale = scale_v
	card.base_scale = scale_v
	wrapper.add_child(card)

	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT \
				and _main._card_inspector:
			_main._card_inspector.on_card_right_clicked(card))

	if not entry.eligible:
		card.modulate = Color(0.42, 0.42, 0.42, 1.0)
		return wrapper

	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var marker := Panel.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(1.0, 0.85, 0.35, 0.18)
	mstyle.border_color = Color(1.0, 0.85, 0.35, 1.0)
	mstyle.set_border_width_all(5)
	mstyle.set_corner_radius_all(8)
	mstyle.shadow_color = Color(1.0, 0.8, 0.3, 0.6)
	mstyle.shadow_size = 10
	marker.add_theme_stylebox_override("panel", mstyle)
	marker.visible = _selected_pos(pool_idx, card_idx) >= 0
	card.add_child(marker)
	_viewer_markers[card_idx] = marker
	if not marker.visible:
		card.set_activatable(true, CardBadges.GLOW_COLOR_CELESTE, &"zone_pick")

	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_toggle(pool_idx, card_idx, card))
	return wrapper


func _close_viewer() -> void:
	if _viewer and is_instance_valid(_viewer):
		_viewer.queue_free()
	_viewer = null
	_viewer_pool = -1
	_viewer_markers = {}
	_viewer_count_label = null
	_viewer_confirm_btn = null
	_viewer_wrappers = []


# =============================================================================
# SELECCIÓN
# =============================================================================
func _selected_pos(pool_idx: int, card_idx: int) -> int:
	for i in range(_selected.size()):
		if _selected[i][0] == pool_idx and _selected[i][1] == card_idx:
			return i
	return -1


func _toggle(pool_idx: int, card_idx: int, card: Node) -> void:
	var pos := _selected_pos(pool_idx, card_idx)
	if pos >= 0:
		_selected.remove_at(pos)
	else:
		if _selected.size() >= _max:
			_main._update_debug("Ya elegiste el máximo (%d)" % _max)
			return
		if _distinct_names:
			var card_name := str(_pools[pool_idx].cards[card_idx].data.get("nombre", ""))
			for s in _selected:
				if str(_pools[s[0]].cards[s[1]].data.get("nombre", "")) == card_name:
					_main._update_debug("Ya elegiste una carta con ese nombre")
					return
		if not _selected.is_empty() and _selected[0][0] != pool_idx \
				and (_pools[pool_idx].get("exclusive", false) or _pools[_selected[0][0]].get("exclusive", false)):
			# "de un Cementerio" (2026-10-14, Lanza Argenta): todas de la misma zona.
			_main._update_debug("Todas tienen que ser de %s" % zone_label(_pools[_selected[0][0]].is_own,
				_pools[_selected[0][0]].zone))
			return
		_selected.append([pool_idx, card_idx])
	var is_selected := pos < 0
	var marker: Panel = _viewer_markers.get(card_idx, null)
	if marker:
		marker.visible = is_selected
	if is_instance_valid(card):
		card.set_activatable(not is_selected, CardBadges.GLOW_COLOR_CELESTE, &"zone_pick")
	_refresh_paso()


func _refresh_paso() -> void:
	var n := _selected.size()
	var ready := n >= _min
	var text := "Confirmar (%d) [P]" % n if ready else "Elige %d más [P]" % (_min - n)
	if _main._game_hud:
		_main._game_hud.show_paso_button_with_text(text, ready)
	if _viewer_count_label:
		var limit := "" if _max >= 999 else "/%d" % _max
		_viewer_count_label.text = "Elegidas: %d%s" % [n, limit]
	if _viewer_confirm_btn:
		_viewer_confirm_btn.text = "Confirmar (%d)" % n
		_viewer_confirm_btn.disabled = not ready
