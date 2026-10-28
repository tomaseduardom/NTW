extends Node
class_name ZoneManager
## ZoneManager — Gestiona el Castillo (mazo), robo de cartas y movimientos entre zonas.
## Se instancia como hijo de Main en _ready().

## Emitida desde _update_castillo_counts() — único punto de verdad para
## "el Castillo cambió". GameStateBroadcaster la reenvía al Remoto (§47).
signal castillo_counts_changed(player_deck_size: int, opponent_deck_size: int)

const CardScene = preload("res://scenes/cards/Card.tscn")
## Tamaño inicial estándar del Castillo (DAR 4.1)
const CASTILLO_INITIAL_SIZE: int = 42

var _main: Node = null


func setup(main: Node) -> void:
	_main = main
	if EffectController and EffectController.has_signal("on_card_left_play"):
		if not EffectController.on_card_left_play.is_connected(_on_card_left_play):
			EffectController.on_card_left_play.connect(_on_card_left_play)
	for prop in ["player_field", "player_linea_apoyo", "opponent_field", "opponent_linea_apoyo"]:
		var container: Node = main.get(prop)
		if container:
			container.child_entered_tree.connect(_on_field_child_entered.bind(container))


func _on_field_child_entered(node: Node, container: Control) -> void:
	"""Carta que entra a la Línea de Defensa/Apoyo sin pasar por pin_card_to_field_slot() (p.ej. la
	que pone en juego quimera voragh). Jugar normal la acomoda en su casilla al frame siguiente; si
	sigue sin casilla, se compacta la línea."""
	if node.get("card_data") == null:
		return
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(node) and node.get_parent() == container and not node.has_meta("field_slot_x"):
		compact_field_slots(container, true)


func _on_card_left_play(_player_id: int, _card: Node, from_zone: int) -> void:
	if from_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
		call_deferred("compact_all_fields", true)


# =============================================================================
# SISTEMA DE MAZO (CASTILLO)
# =============================================================================
func draw_card(player_id: int = 0, animated: bool = true) -> bool:
	"""Roba una carta del Castillo con animación cinemática en arco parabólico y revelado 3D (Opción 1)."""
	if player_id == 0:
		if _main.player_deck.is_empty():
			_main._update_debug("Tu Castillo está vacío!")
			GameManager.check_victory()
			return false
		var card_data = _main.player_deck.pop_front()
		var card = _main._create_card(card_data, true)  # Empieza oculta para mostrar dorso al despegar
		card.owner_id = 0
		card.controller_id = 0
		_main.player_hand.add_card(card)
		_main._connect_card_signals(card)
		_update_castillo_counts()
		_main._update_debug("Robas: %s" % card_data.get("nombre", "Carta"))
		if animated:
			await _animate_player_card_draw(card)
		else:
			card.esta_oculta = false
			card.actualizar_aspecto()
			_main.player_hand._arrange_cards(false)
		return true
	else:
		if _main.opponent_deck.is_empty():
			GameManager.check_victory()
			return false
		var card_data = _main.opponent_deck.pop_front()
		var card = _main._create_card(card_data, true)
		card.owner_id = 1
		card.controller_id = 1
		_main._opponent_fan.add_card(card)
		# Conectar las señales de la carta también para el jugador 1: sin listeners, sus cartas brillaban
		# como objetivo válido pero el click no hacía nada en ninguna habilidad. La conexión se mantiene
		# cuando la carta pasa de la mano al campo (mismo Node).
		_main._connect_card_signals(card)
		_update_castillo_counts()
		if animated:
			await _animate_opponent_card_draw(card)
		else:
			_main._opponent_fan._arrange()
		return true


func draw_initial_hand(player_id: int, count: int = 7) -> void:
	"""Roba la mano inicial en una elegante cascada cinemática escalonada."""
	for i in range(count):
		draw_card(player_id, true)
		await get_tree().create_timer(0.09).timeout
	await get_tree().create_timer(0.35).timeout


func _animate_player_card_draw(card: Node) -> void:
	if not is_instance_valid(card) or not _main:
		return

	var start_pos: Vector2 = Vector2(1685.0, 680.0)
	var castillo_panel = _main.get_node_or_null("GameBoard/PlayerArea/PlayerCastillo")
	if castillo_panel:
		start_pos = castillo_panel.global_position + Vector2(
			castillo_panel.size.x / 2.0 - 75.0,
			castillo_panel.size.y / 2.0 - 105.0
		)

	card.top_level = true
	card.global_position = start_pos
	card.scale = Vector2(0.66, 0.66)
	card.base_scale = Vector2.ONE
	card.z_index = 250
	card.esta_oculta = true
	card.actualizar_aspecto()

	var duration: float = 0.38
	var tw = card.create_tween()

	tw.tween_method(func(t: float):
		if not is_instance_valid(card) or not _main or not _main.player_hand:
			return
		var live_target_local = _main.player_hand.get_card_target_position(card)
		var live_end_pos = _main.player_hand.global_position + live_target_local

		# Curva ease out cúbica para avance horizontal
		var ease_t = 1.0 - pow(1.0 - t, 3.0)
		var current_x = lerpf(start_pos.x, live_end_pos.x, ease_t)
		var base_y = lerpf(start_pos.y, live_end_pos.y, ease_t)
		var arc_lift = -sin(t * PI) * 110.0  # Elevación parabólica hacia el centro
		var current_y = base_y + arc_lift
		card.global_position = Vector2(current_x, current_y)

		# Escala 2.5D con elevación
		var scale_y = lerpf(0.66, 1.0, t) + sin(t * PI) * 0.22

		# Volteo 3D horizontal a mitad de recorrido
		var flip_factor: float = 1.0
		if t >= 0.35 and t <= 0.65:
			var phase = (t - 0.35) / 0.30
			flip_factor = absf(cos(phase * PI))
			if t >= 0.50 and card.esta_oculta:
				card.esta_oculta = false
				card.actualizar_aspecto()
		elif t > 0.65:
			if card.esta_oculta:
				card.esta_oculta = false
				card.actualizar_aspecto()

		card.scale = Vector2(scale_y * flip_factor, scale_y)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	await tw.finished
	if is_instance_valid(card) and _main and _main.player_hand:
		card.top_level = false
		card.scale = Vector2.ONE
		card.z_index = _main.player_hand.cards.find(card)
		_main.player_hand._arrange_cards(false)


func _animate_opponent_card_draw(card: Node) -> void:
	if not is_instance_valid(card) or not _main or not _main._opponent_fan:
		return

	var start_pos: Vector2 = Vector2(1685.0, 210.0)
	var opp_castillo = _main.get_node_or_null("GameBoard/OpponentArea/OpponentCastillo")
	if opp_castillo:
		start_pos = opp_castillo.global_position + Vector2(
			opp_castillo.size.x / 2.0 - (150.0 * 0.50) / 2.0,
			opp_castillo.size.y / 2.0 - (210.0 * 0.50) / 2.0
		)

	card.top_level = true
	card.global_position = start_pos
	card.scale = Vector2(0.50, 0.50)
	card.base_scale = Vector2(0.50, 0.50)
	card.z_index = 250
	card.esta_oculta = true
	card.owner_id = 1
	card.controller_id = 1
	card.actualizar_aspecto()
	if card.has_method("_refresh_disabled_rotation"):
		card._refresh_disabled_rotation()

	var duration: float = 0.34
	var tw = card.create_tween()

	tw.tween_method(func(t: float):
		if not is_instance_valid(card) or not _main or not _main._opponent_fan:
			return
		var live_target_local = _main._opponent_fan.get_card_target_position(card)
		var live_end_pos = _main._opponent_fan.global_position + live_target_local

		var ease_t = 1.0 - pow(1.0 - t, 3.0)
		var current_x = lerpf(start_pos.x, live_end_pos.x, ease_t)
		var base_y = lerpf(start_pos.y, live_end_pos.y, ease_t)
		var arc_lift = sin(t * PI) * 50.0  # Desciende ligeramente en arco
		var current_y = base_y + arc_lift
		card.global_position = Vector2(current_x, current_y)

		var scale_val = 0.50 + sin(t * PI) * 0.10
		card.scale = Vector2(scale_val, scale_val)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	await tw.finished
	if is_instance_valid(card) and _main and _main._opponent_fan:
		card.top_level = false
		card.scale = Vector2(0.50, 0.50)
		_main._opponent_fan._arrange()


func _update_castillo_counts() -> void:
	"""Actualiza los contadores de cartas en los Castillos."""
	UIManager.sync_castillo_counts(_main.player_deck.size(), _main.opponent_deck.size())
	castillo_counts_changed.emit(_main.player_deck.size(), _main.opponent_deck.size())
	# Único punto de verdad para "el Castillo cambió" (robo normal, Destierra N del tope de Aho, la
	# habilidad de La Ouija, etc.) — refrescar aquí el revelado del tope evita tener que llamarlo a
	# mano en cada sitio que toca player_deck directo. Ver ZoneViewerModule.
	# refresh_castillo_top_reveal.
	if _main._zone_viewer:
		_main._zone_viewer.refresh_castillo_top_reveal()
	# Chequeo de victoria por Castillo vacío (DAR 2.1) en cada cambio del contador, no solo al robar
	# con el mazo vacío (p.ej. desterrar el Castillo rival a 0 con Aho). GameManager.check_victory()
	# tiene su propio guard is_game_active.
	GameManager.check_victory()


func shuffle_deck(player_id: int = 0) -> void:
	"""Baraja el mazo de un jugador."""
	if player_id == 0:
		_main.player_deck.shuffle()
	else:
		_main.opponent_deck.shuffle()


# =============================================================================
# ANIMACIONES CINEMÁTICAS DE SALIDA DE CARTAS
# =============================================================================
func get_zone_panel(zone_name: String, player_id: int) -> Control:
	"""Devuelve el panel de la zona correspondiente (Castillo, Cementerio, Destierro)."""
	if not _main:
		return null
	var area_name = "PlayerArea" if player_id == 0 else "OpponentArea"
	var prefix = "Player" if player_id == 0 else "Opponent"
	return _main.get_node_or_null("GameBoard/%s/%s%s" % [area_name, prefix, zone_name])


func _pulse_zone_panel(panel: Control, color: Color) -> void:
	"""Produce un pulso cinemático de escala y brillo en el pedestal de destino."""
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size / 2.0
	var tw = panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate", color, 0.10)
	tw.tween_property(panel, "scale", Vector2(1.10, 1.10), 0.10)
	tw.chain().set_parallel(true)
	tw.tween_property(panel, "modulate", Color.WHITE, 0.20)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.20)


func _detach_for_flight(card: Node) -> void:
	"""Saca la carta de la mano/abanico/campo y la deja colgando del tablero para animar su vuelo.
	Debe quedar dentro del árbol: un tween de un nodo fuera del árbol nunca termina y el 'await
	tw.finished' colgaba (p.ej. el descarte por límite de mano en Fase Final). Lo usan Cementerio,
	Destierro y Castillo."""
	var gpos: Vector2 = card.global_position
	var from_field := true
	if _main.player_hand and _main.player_hand.cards.has(card):
		_main.player_hand.remove_card(card, false)
		from_field = false
	elif _main.get("_opponent_fan") and _main._opponent_fan and _main._opponent_fan.has_method("get_cards") and _main._opponent_fan.get_cards().has(card):
		_main._opponent_fan.remove_card(card, false)
		from_field = false
	var gb = _main.game_board if _main.get("game_board") else _main.get_node_or_null("GameBoard")
	if not gb or card.get_parent() == gb:
		return
	if card.get_parent():
		card.get_parent().remove_child(card)
	gb.add_child(card)
	card.global_position = gpos
	if from_field:
		compact_all_fields(true)


func animate_card_return_to_deck(card: Node, player_id: int = 0) -> void:
	"""Trayectoria parabólica 3D de vuelta al Castillo con giro sobre su eje (ocultando cara)."""
	if not is_instance_valid(card) or not card.is_inside_tree() or not card.visible:
		return
	if not _main:
		return

	# Desactivar interacción durante el trayecto
	if card.get("can_interact") != null:
		card.can_interact = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_detach_for_flight(card)

	var target_panel = get_zone_panel("Castillo", player_id)
	var end_scale = Vector2(0.66, 0.66)
	var fallback_y = 680.0 if player_id == 0 else 260.0
	var target_pos = Vector2(1685.0, fallback_y)
	if target_panel:
		target_pos = target_panel.global_position + Vector2(
			(target_panel.size.x - 150.0 * end_scale.x) / 2.0,
			(target_panel.size.y - 210.0 * end_scale.y) / 2.0
		)

	var start_pos: Vector2 = card.global_position
	var start_scale: Vector2 = card.scale

	card.top_level = true
	card.z_index = 500

	var duration: float = 0.40
	var arc_dir: float = -1.0 if player_id == 0 else 1.0
	var tw = card.create_tween()

	tw.tween_method(func(t: float):
		if not is_instance_valid(card):
			return
		var ease_t = 1.0 - pow(1.0 - t, 2.8)
		var current_x = lerpf(start_pos.x, target_pos.x, ease_t)
		var base_y = lerpf(start_pos.y, target_pos.y, ease_t)
		var arc_lift = arc_dir * sin(t * PI) * 110.0
		card.global_position = Vector2(current_x, base_y + arc_lift)

		var cur_scale_y = lerpf(start_scale.y, end_scale.y, t) + sin(t * PI) * 0.15

		var flip_factor: float = 1.0
		if t >= 0.35 and t <= 0.65:
			var phase = (t - 0.35) / 0.30
			flip_factor = absf(cos(phase * PI))
			if t >= 0.50 and not card.esta_oculta:
				card.esta_oculta = true
				card.actualizar_aspecto()
		elif t > 0.65:
			if not card.esta_oculta:
				card.esta_oculta = true
				card.actualizar_aspecto()

		card.scale = Vector2(cur_scale_y * flip_factor, cur_scale_y)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	await tw.finished

	if is_instance_valid(card):
		var sink_tw = card.create_tween().set_parallel(true)
		sink_tw.tween_property(card, "scale", end_scale * 0.85, 0.08)
		sink_tw.tween_property(card, "modulate:a", 0.0, 0.08)
		await sink_tw.finished

	if target_panel:
		_pulse_zone_panel(target_panel, Color(1.0, 0.85, 0.3, 1.0))
	_update_castillo_counts()


func animate_card_exile(card: Node, player_id: int = 0) -> void:
	"""Vuelo cósmico con aura mística púrpura/cian y desmaterialización astral hacia el Destierro."""
	if not is_instance_valid(card) or not card.is_inside_tree() or not card.visible:
		return
	if not _main:
		return

	if card.get("can_interact") != null:
		card.can_interact = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_detach_for_flight(card)

	var target_panel = get_zone_panel("Destierro", player_id)
	var end_scale = Vector2(0.35, 0.35)
	var fallback_y = 850.0 if player_id == 0 else 90.0
	var target_pos = Vector2(1805.0, fallback_y)
	if target_panel:
		target_pos = target_panel.global_position + Vector2(
			(target_panel.size.x - 150.0 * end_scale.x) / 2.0,
			(target_panel.size.y - 210.0 * end_scale.y) / 2.0
		)

	var start_pos: Vector2 = card.global_position
	var start_scale: Vector2 = card.scale

	card.top_level = true
	card.z_index = 500

	var duration: float = 0.44
	var target_rotation: float = deg_to_rad(15.0 if player_id == 0 else -15.0)
	var arc_dir: float = -1.0 if player_id == 0 else 1.0
	var tw = card.create_tween()

	tw.tween_method(func(t: float):
		if not is_instance_valid(card):
			return
		var ease_t = 1.0 - pow(1.0 - t, 2.5)
		var current_x = lerpf(start_pos.x, target_pos.x, ease_t)
		var base_y = lerpf(start_pos.y, target_pos.y, ease_t)
		var arc_lift = arc_dir * sin(t * PI) * 85.0
		card.global_position = Vector2(current_x, base_y + arc_lift)

		var s = lerpf(start_scale.x, end_scale.x, ease_t)
		card.scale = Vector2(s, s)
		card.rotation = lerpf(0.0, target_rotation, ease_t)

		var alpha = 1.0
		if t > 0.40:
			alpha = clampf(1.0 - (t - 0.40) / 0.60, 0.0, 1.0)
		var cosmic_glow = Color(1.2, 0.7, 1.8, alpha)
		card.modulate = cosmic_glow
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	await tw.finished

	if target_panel:
		_pulse_zone_panel(target_panel, Color(0.85, 0.45, 1.0, 1.0))
	UIManager.update_destierro_count(player_id, CardManager.get_exile_count(player_id))


func animate_card_to_cemetery(card: Node, player_id: int = 0) -> void:
	"""Sacudida de impacto sombrío y vuelo en arco directo hacia el Cementerio descendiendo a la cripta."""
	if not is_instance_valid(card) or not card.is_inside_tree() or not card.visible:
		return
	if not _main:
		return

	if card.get("can_interact") != null:
		card.can_interact = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_detach_for_flight(card)

	var target_panel = get_zone_panel("Cementerio", player_id)
	var end_scale = Vector2(0.66, 0.66)
	var fallback_y = 680.0 if player_id == 0 else 260.0
	var target_pos = Vector2(1805.0, fallback_y)
	if target_panel:
		target_pos = target_panel.global_position + Vector2(
			(target_panel.size.x - 150.0 * end_scale.x) / 2.0,
			(target_panel.size.y - 210.0 * end_scale.y) / 2.0
		)

	var start_pos: Vector2 = card.global_position
	var start_scale: Vector2 = card.scale

	card.top_level = true
	card.z_index = 500

	# 1. Sacudida de impacto sombrío
	var shudder_tw = card.create_tween()
	var shake_offset = Vector2(randf_range(-5.0, 5.0), randf_range(-4.0, 4.0))
	shudder_tw.tween_property(card, "global_position", start_pos + shake_offset, 0.04)
	shudder_tw.parallel().tween_property(card, "modulate", Color(0.6, 0.58, 0.65, 1.0), 0.04)
	shudder_tw.chain().tween_property(card, "global_position", start_pos, 0.03)
	await shudder_tw.finished

	if not is_instance_valid(card):
		return

	# 2. Vuelo en arco y hundimiento en la cripta
	var duration: float = 0.36
	var arc_dir: float = -1.0 if player_id == 0 else 1.0
	var tw = card.create_tween()

	tw.tween_method(func(t: float):
		if not is_instance_valid(card):
			return
		var ease_t = 1.0 - pow(1.0 - t, 2.6)
		var current_x = lerpf(start_pos.x, target_pos.x, ease_t)
		var base_y = lerpf(start_pos.y, target_pos.y, ease_t)
		var arc_lift = arc_dir * sin(t * PI) * 90.0
		card.global_position = Vector2(current_x, base_y + arc_lift)

		var s = lerpf(start_scale.x, end_scale.x, ease_t)
		card.scale = Vector2(s, s)

		if t > 0.75:
			card.modulate.a = clampf(1.0 - (t - 0.75) / 0.25, 0.0, 1.0)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)

	await tw.finished

	if target_panel:
		_pulse_zone_panel(target_panel, Color(0.75, 0.75, 0.85, 1.0))
	UIManager.update_cementerio_count(player_id, CardManager.get_cemetery_count(player_id))


func move_card(from_zone: Constants.Zone, to_zone: Constants.Zone, amount: int = 1) -> void:
	"""Mueve 'amount' cartas de from_zone a to_zone (jugador 0).
	   Actualiza contadores de Castillo, Cementerio y Destierro en tiempo real."""
	for _i in range(amount):
		match [from_zone, to_zone]:

			[Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO]:
				if _main.player_deck.is_empty():
					_main._update_debug("Castillo vacío"); return
				var data = _main.player_deck.pop_front()
				data["esta_oculta"] = false
				CardManager.add_to_cemetery(0, data)
				_update_castillo_counts()

			[Constants.Zone.CASTILLO, Constants.Zone.DESTIERRO]:
				if _main.player_deck.is_empty():
					_main._update_debug("Castillo vacío"); return
				var data = _main.player_deck.pop_front()
				data["esta_oculta"] = false
				CardManager.append_to_exile(0, data)
				CardManager._emit_exile_changed(0)
				_update_castillo_counts()

			[Constants.Zone.MANO, Constants.Zone.CEMENTERIO]:
				var hand_cards = _main.player_hand.cards if _main.player_hand.get("cards") != null else _main.player_hand.get_children()
				if hand_cards.is_empty():
					_main._update_debug("Mano vacía"); return
				var card = hand_cards[randi() % hand_cards.size()]
				var data = card.card_data.duplicate() if card.get("card_data") else {}
				data["esta_oculta"] = false
				CardManager.add_to_cemetery(0, data)
				_main.player_hand.remove_card(card)

			_:
				push_warning("[ZoneManager] move_card: combinación de zonas no implementada")


# =============================================================================
# SLOTS FIJOS DE LÍNEA DE DEFENSA/APOYO
# =============================================================================
# Con el HBoxContainer puro, sacar un hijo reordenaba a todos ("cuando uno ataca, el otro toma su
# =============================================================================
# SLOTS DINÁMICOS DE LÍNEA DE DEFENSA / ATAQUE (ALIADOS) Y APOYO (TÓTEMS)
# =============================================================================
# - Aliados: Tienen prioridad en el terreno de juego (sector celeste). Maximizan el espacio
#   completo del campo cuando no hay tótems.
# - Tótems: Se ubican en el sector derecho del campo (sector rojo sobre las columnas),
#   con un espaciado más compacto/pegado (_TOTEM_SLOT_WIDTH = 110px).
# - Dinámica: Al entrar un tótem, los aliados se desplazan suavemente hacia la izquierda
#   dejando libre el santuario de tótems en la derecha. Si los tótems salen, los aliados
#   vuelven a centrarse en el terreno completo.
const _FIELD_SLOT_WIDTH: float = 170.0  # Espaciado amplio entre Aliados
const _TOTEM_SLOT_WIDTH: float = 110.0  # Espaciado más compacto/pegado entre Tótems
var _field_slot_occupants: Dictionary = {}  # {container: Array[Node]}


func _get_base_field_container(container: Control) -> Control:
	if not _main:
		return container
	if container == _main.player_field or container == _main.player_linea_ataque:
		return _main.player_field
	if container == _main.opponent_field or container == _main.opponent_linea_ataque:
		return _main.opponent_field
	return container


func _get_associated_attack_container(container: Control) -> Control:
	if not _main:
		return null
	if container == _main.player_field:
		return _main.player_linea_ataque
	if container == _main.opponent_field:
		return _main.opponent_linea_ataque
	return null


func pin_card_to_field_slot(card: Node, container: Control) -> Vector2:
	"""Asigna a 'card' su slot en 'container' (Línea de Defensa o de Apoyo),
	desacoplándola del layout del HBoxContainer (top_level=true), compactando
	y separando limpiamente a todas las cartas de la mesa con espacio positivo."""
	if not is_instance_valid(card) or not container:
		return card.global_position if is_instance_valid(card) else Vector2.ZERO

	var target_pos: Vector2 = compact_field_slots(container, true, card)

	# Si es un tótem, los aliados deben correrse a la izquierda de inmediato para darle espacio
	if container == _main.player_linea_apoyo and _main.player_field:
		compact_field_slots(_main.player_field, true)
	elif container == _main.opponent_linea_apoyo and _main.opponent_field:
		compact_field_slots(_main.opponent_field, true)
	# Si es un aliado, asegurar sincronización con la zona de apoyo
	elif (container == _main.player_field or container == _main.player_linea_ataque) and _main.player_linea_apoyo:
		compact_field_slots(_main.player_linea_apoyo, true)
	elif (container == _main.opponent_field or container == _main.opponent_linea_ataque) and _main.opponent_linea_apoyo:
		compact_field_slots(_main.opponent_linea_apoyo, true)

	return target_pos


func compact_field_slots(container: Control, animate: bool = true, exclude_anim_card: Node = null) -> Vector2:
	"""Reordena y compacta dinámicamente aliados y tótems:
	- Tótems: Sector derecho, más pegados entre sí (_TOTEM_SLOT_WIDTH).
	- Aliados: Sector izquierdo/centro maximizando el terreno. Si hay tótems, se corren a la izquierda."""
	if not container or not _main:
		return Vector2.ZERO
	var base_container: Control = _get_base_field_container(container)
	var atk_container: Control = _get_associated_attack_container(base_container)

	var is_player: bool = (base_container == _main.player_field or base_container == _main.player_linea_apoyo)
	var is_totem_zone: bool = (base_container == _main.player_linea_apoyo or base_container == _main.opponent_linea_apoyo)

	# 1. Obtener cartas activas en esta zona
	var active_cards: Array = []
	for child in base_container.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			active_cards.append(child)
	if atk_container:
		for child in atk_container.get_children():
			if is_instance_valid(child) and not child.is_queued_for_deletion():
				active_cards.append(child)

	if exclude_anim_card and is_instance_valid(exclude_anim_card) and exclude_anim_card not in active_cards:
		active_cards.append(exclude_anim_card)

	if active_cards.is_empty():
		_field_slot_occupants[base_container] = []
		if is_totem_zone:
			# Si salieron todos los tótems, re-centrar los aliados para maximizar el terreno
			var allies_cont: Control = _main.player_field if is_player else _main.opponent_field
			if allies_cont and allies_cont != base_container:
				compact_field_slots(allies_cont, animate)
		return Vector2.ZERO

	# 2. Ordenar de izquierda a derecha según su posición X asignada o actual
	active_cards.sort_custom(func(a, b):
		var pos_a: float = a.get_meta("field_slot_x", a.global_position.x if is_instance_valid(a) else 0.0)
		var pos_b: float = b.get_meta("field_slot_x", b.global_position.x if is_instance_valid(b) else 0.0)
		return pos_a < pos_b
	)

	# 3. Detectar presencia de tótems en el campo del mismo jugador/oponente
	var apoyo_container: Control = _main.player_linea_apoyo if is_player else _main.opponent_linea_apoyo
	var totem_cards: Array = []
	if is_instance_valid(apoyo_container):
		for ch in apoyo_container.get_children():
			if is_instance_valid(ch) and not ch.is_queued_for_deletion():
				totem_cards.append(ch)
	if is_totem_zone and exclude_anim_card and is_instance_valid(exclude_anim_card) and exclude_anim_card not in totem_cards:
		totem_cards.append(exclude_anim_card)

	var totem_count: int = totem_cards.size()
	var has_totems: bool = (totem_count > 0)

	# 4. Determinar límites horizontales del terreno de juego
	var gold_c: Control = _main.player_gold if is_player else _main.opponent_gold
	var gold_right: float = 370.0
	if is_instance_valid(gold_c) and gold_c.size.x > 0:
		gold_right = gold_c.global_position.x + gold_c.size.x + 20.0

	var cast_p: Control = _main._panel_player_castillo if is_player else _main._panel_opp_castillo
	var cast_left: float = 1660.0
	if is_instance_valid(cast_p) and cast_p.size.x > 0:
		cast_left = cast_p.global_position.x - 24.0
	elif base_container.is_inside_tree():
		cast_left = base_container.get_viewport_rect().size.x - 260.0

	# 5. Cálculo del ancho y posición del área de Tótems (Sector Rojo a la derecha)
	var totems_visual_width: float = 132.0 if totem_count <= 1 else (float(totem_count - 1) * _TOTEM_SLOT_WIDTH + 132.0)
	var totem_zone_margin: float = 24.0
	var totem_zone_width: float = clampf(totems_visual_width + totem_zone_margin * 2.0, 260.0, 420.0)
	var totem_zone_start_x: float = cast_left - totem_zone_width
	var totem_center_x: float = cast_left - (totem_zone_width / 2.0)

	# 6. Cálculo del área de Aliados (Sector Celeste)
	# Si hay tótems, los aliados se corren a la izquierda dejando libre el área del tótem
	# Si no hay tótems, los aliados maximizan el terreno completo de juego
	var ally_zone_left: float = gold_right
	var ally_zone_right: float = (totem_zone_start_x - 24.0) if has_totems else cast_left
	var ally_span_width: float = maxf(ally_zone_right - ally_zone_left, 300.0)
	var ally_center_x: float = ally_zone_left + (ally_span_width / 2.0)

	var count: int = active_cards.size()
	var new_occupants: Array = []
	new_occupants.resize(count)
	var returned_target_pos: Vector2 = Vector2.ZERO

	if is_totem_zone:
		# Posicionamiento de TÓTEMS (Zona Roja a la derecha, más pegados entre sí)
		var start_totem_x: float = totem_center_x - (float(count - 1) * _TOTEM_SLOT_WIDTH / 2.0)
		for i in range(count):
			var card: Node = active_cards[i]
			var target_scale: Vector2 = Constants.TOTEM_CARD_SCALE
			var card_size: Vector2 = (card.custom_minimum_size if card.custom_minimum_size != Vector2.ZERO else Vector2(150.0, 210.0)) * target_scale
			var target_x: float = start_totem_x + float(i) * _TOTEM_SLOT_WIDTH - (card_size.x / 2.0)

			var card_parent: Control = card.get_parent() as Control
			var current_container: Control = card_parent if card_parent else base_container
			var target_y: float = current_container.global_position.y + (current_container.size.y - card_size.y) / 2.0
			var target_pos: Vector2 = Vector2(target_x, target_y)

			_apply_card_field_placement(card, target_pos, target_scale, i, animate, exclude_anim_card)
			new_occupants[i] = card
			if card == exclude_anim_card:
				returned_target_pos = target_pos
	else:
		# Posicionamiento de ALIADOS (Zona Celeste, espaciado amplio, corriendo a la izquierda si hay tótems)
		var effective_slot_width: float = _FIELD_SLOT_WIDTH
		if float(count) * _FIELD_SLOT_WIDTH > ally_span_width:
			effective_slot_width = maxf(80.0, ally_span_width / float(count))

		var start_ally_x: float = ally_center_x - (float(count - 1) * effective_slot_width / 2.0)
		for i in range(count):
			var card: Node = active_cards[i]
			var target_scale: Vector2 = Vector2.ONE
			var card_size: Vector2 = (card.custom_minimum_size if card.custom_minimum_size != Vector2.ZERO else Vector2(150.0, 210.0)) * target_scale
			var target_x: float = start_ally_x + float(i) * effective_slot_width - (card_size.x / 2.0)

			var card_parent: Control = card.get_parent() as Control
			var current_container: Control = card_parent if (card_parent == atk_container or card_parent == base_container) else base_container
			var target_y: float = current_container.global_position.y + (current_container.size.y - card_size.y) / 2.0
			var target_pos: Vector2 = Vector2(target_x, target_y)

			_apply_card_field_placement(card, target_pos, target_scale, i, animate, exclude_anim_card)
			new_occupants[i] = card
			if card == exclude_anim_card:
				returned_target_pos = target_pos

	_field_slot_occupants[base_container] = new_occupants
	_update_zone_labels(is_player, has_totems, ally_center_x, totem_center_x, animate)
	return returned_target_pos


func _apply_card_field_placement(
	card: Node,
	target_pos: Vector2,
	target_scale: Vector2,
	slot_index: int,
	animate: bool,
	exclude_anim_card: Node
) -> void:
	card.top_level = true
	card.z_index = 0
	card.set("original_z_index", 0)
	card.set_meta("hand_base_z_index", 0)
	card.scale = target_scale
	card.base_scale = target_scale
	card.set_meta("field_slot_index", slot_index)
	card.set_meta("field_slot_x", target_pos.x)
	card.set_meta("field_slot_pos", target_pos)

	if card.has_method("set_click_clip_right"):
		card.set_click_clip_right(-1.0)
	if card.has_method("_refresh_disabled_rotation"):
		card._refresh_disabled_rotation()

	# Revalidar posición de armas equipadas en el Aliado
	if "equipped_weapons" in card and card.equipped_weapons is Array:
		for w_idx in range(card.equipped_weapons.size() - 1, -1, -1):
			if not is_instance_valid(card.equipped_weapons[w_idx]):
				card.equipped_weapons.remove_at(w_idx)
		for w_idx in range(card.equipped_weapons.size()):
			var w = card.equipped_weapons[w_idx]
			if is_instance_valid(w):
				w.top_level = false
				w.position = Vector2(0.0, Constants.WEAPON_OFFSET_Y + w_idx * Constants.WEAPON_STACK_STEP_Y)
				if "base_scale" in card and "base_scale" in w:
					w.scale = card.base_scale
					w.base_scale = card.base_scale

	if card == exclude_anim_card:
		card.global_position = target_pos
	else:
		var current_pos: Vector2 = card.global_position
		if animate and (absf(current_pos.x - target_pos.x) > 1.0 or absf(current_pos.y - target_pos.y) > 1.0):
			var tw = card.create_tween()
			tw.set_parallel(true)
			tw.tween_property(card, "global_position:x", target_pos.x, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(card, "global_position:y", target_pos.y, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif not animate:
			card.global_position = target_pos


func _update_zone_labels(is_player: bool, has_totems: bool, ally_center_x: float, totem_center_x: float, animate: bool = true) -> void:
	if not _main:
		return
	var prefix: String = "Player" if is_player else "Opponent"
	var area_name: String = "PlayerArea" if is_player else "OpponentArea"

	var apoyo_lbl = _main.get_node_or_null("GameBoard/%s/%sLineaApoyoLabel" % [area_name, prefix])
	if is_instance_valid(apoyo_lbl):
		apoyo_lbl.visible = has_totems
		if has_totems and apoyo_lbl.size.x > 0:
			var target_apoyo_x = totem_center_x - (apoyo_lbl.size.x / 2.0)
			if animate and absf(apoyo_lbl.global_position.x - target_apoyo_x) > 2.0:
				var tw = apoyo_lbl.create_tween()
				tw.tween_property(apoyo_lbl, "global_position:x", target_apoyo_x, 0.28).set_ease(Tween.EASE_OUT)
			else:
				apoyo_lbl.global_position.x = target_apoyo_x

	var def_lbl = _main.get_node_or_null("GameBoard/%s/%sFieldLabel" % [area_name, prefix])
	if is_instance_valid(def_lbl) and def_lbl.size.x > 0:
		var target_def_x = ally_center_x - (def_lbl.size.x / 2.0)
		if animate and absf(def_lbl.global_position.x - target_def_x) > 2.0:
			var tw = def_lbl.create_tween()
			tw.tween_property(def_lbl, "global_position:x", target_def_x, 0.28).set_ease(Tween.EASE_OUT)
		else:
			def_lbl.global_position.x = target_def_x

	var atk_lbl = _main.get_node_or_null("GameBoard/%s/%sLineaAtaqueLabel" % [area_name, prefix])
	if is_instance_valid(atk_lbl) and atk_lbl.size.x > 0:
		var target_atk_x = ally_center_x - (atk_lbl.size.x / 2.0)
		if animate and absf(atk_lbl.global_position.x - target_atk_x) > 2.0:
			var tw = atk_lbl.create_tween()
			tw.tween_property(atk_lbl, "global_position:x", target_atk_x, 0.28).set_ease(Tween.EASE_OUT)
		else:
			atk_lbl.global_position.x = target_atk_x


func compact_all_fields(animate: bool = true) -> void:
	"""Compacta y reordena todas las zonas del campo (Líneas de Defensa y Apoyo de ambos jugadores)"""
	if not _main:
		return
	if _main.player_linea_apoyo:
		compact_field_slots(_main.player_linea_apoyo, animate)
	if _main.player_field:
		compact_field_slots(_main.player_field, animate)
	if _main.opponent_linea_apoyo:
		compact_field_slots(_main.opponent_linea_apoyo, animate)
	if _main.opponent_field:
		compact_field_slots(_main.opponent_field, animate)
