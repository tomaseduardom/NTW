extends RefCounted
class_name CardInteraction
## CardInteraction — Hover, click, drag & drop de una carta.
## Opera sobre el nodo Card via _card. Card.gd reenvía las señales de mouse/gui
## y expone return_to_hand()/_can_declare_attack_drag() como wrappers públicos
## porque otros sistemas (DropZone, GoldManager, CardInteractionModule) los
## llaman directamente sobre la carta.
## Extraído de Card.gd (Fase 4 de reestructuración).

var _card: Card

## Timestamp del último press simple (double_click=false) de ESTA carta —
## distingue el eco genuino (ver on_gui_input) de un doble-click real sobre
## la misma carta, para no emitir card_clicked de más en ese segundo caso.
var _last_plain_click_ms: int = -100000
const DOUBLE_CLICK_ECHO_WINDOW_MS: int = 700


func setup(card: Card) -> void:
	_card = card


func process(_delta: float) -> void:
	"""Red de seguridad contra hover perdido: mouse_entered/mouse_exited de Godot a veces no se
	disparan para estas cartas — reparentado entre contenedores al declarar ataque/agrupar, reflow
	del HBoxContainer de la mano al jugar/robar cartas, o movimiento rápido del mouse — dejando una
	carta con la que 'no se puede targetear ni hacer zoom' aunque el mouse esté encima. Se corrige
	el estado cada frame comparando contra la posición real del mouse."""
	if _card.is_dragging or not _card.can_interact or _card.get("hover_enabled") == false:
		return
	# get_global_rect() no tiene en cuenta la escala: con pivot_offset != (0,0), al escalar en hover la
	# carta se mueve pero el rect no, y cerca de un borde entraba en un loop entra/sale.
	# get_local_mouse_position() invierte la transformación completa (posición, escala, pivote).
	# _has_point() además respeta _click_clip_right con cartas solapadas (mano o escalera de Oros).
	var local_mouse = _card.get_local_mouse_position()
	var mouse_over := _card._has_point(local_mouse)
	# Si esta carta es un Arma equipada a un Aliado (wielder), el Aliado que está encima
	# tiene prioridad absoluta sobre el mouse. El Arma solo se activa si el mouse está
	# sobre la parte expuesta del arma (fuera del área del Aliado).
	if mouse_over and _card.wielder != null and is_instance_valid(_card.wielder):
		var mouse_over_wielder := Rect2(Vector2.ZERO, _card.wielder.size).has_point(_card.wielder.get_local_mouse_position())
		if mouse_over_wielder:
			mouse_over = false

	if mouse_over and not _card.is_hovered:
		_on_mouse_entered()
	elif not mouse_over and _card.is_hovered:
		_on_mouse_exited()


func _get_hand_card_under_mouse() -> Node:
	if not _card or not is_instance_valid(_card):
		return null
	var tree := _card.get_tree()
	if not tree:
		return null
	var main = tree.get_root().get_node_or_null("Main")
	if not main or not main.get("player_hand"):
		return null
	var hand = main.player_hand
	if not hand or not is_instance_valid(hand) or not hand.visible or hand.get("_is_hidden") == true:
		return null
	var m_pos: Vector2 = _card.get_global_mouse_position()
	for i in range(hand.cards.size() - 1, -1, -1):
		var c = hand.cards[i]
		if is_instance_valid(c) and c.is_visible_in_tree() and not c.is_dragging:
			var c_local: Vector2 = c.get_global_transform().affine_inverse() * m_pos
			if c._has_point(c_local):
				return c
	return null


func _on_mouse_entered() -> void:
	if not _card.can_interact or _card.is_dragging or _card.get("hover_enabled") == false:
		return

	# Si la carta está en la mesa y el cursor está sobre una carta de la mano, ceder prioridad a la mano
	if _card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
		var hand_c = _get_hand_card_under_mouse()
		if hand_c != null and hand_c != _card:
			return

	_card.is_hovered = true
	if _card.hover_effect:
		_card.hover_effect.visible = true

	# Guardar z_index original (si no estaba ya elevado) y ponerlo encima de las demás
	# (Las armas equipadas deben permanecer detrás de su portador en z_index = 0)
	if _card.wielder == null:
		var parent = _card.get_parent()
		var is_in_hand: bool = (parent is DynamicHand) or (parent != null and parent.name == "PlayerHand")
		if is_in_hand:
			if _card.z_index < 80:
				_card.original_z_index = _card.z_index
			_card.z_index = 80
		else:
			if _card.z_index < 25:
				_card.original_z_index = _card.z_index
			_card.z_index = 25

	# Quitar temporalmente el recorte de click en hover para que responda completa
	if _card.has_method("set_click_clip_right"):
		_card.set_click_clip_right(-1.0)

	_card.emit_signal("card_hovered", _card)

	# Animación de hover (proporcional a base_scale, omitida si hover_scale es 1.0)
	if _card.card_scale_hover != 1.0:
		var tween = _card.create_tween()
		tween.tween_property(_card, "scale", _card.base_scale * _card.card_scale_hover, _card.animation_speed)


func _on_mouse_exited() -> void:
	if _card.is_dragging:
		return

	# Si no puede interactuar o tiene hover desactivado, no hacer nada
	if not _card.can_interact or _card.get("hover_enabled") == false:
		return

	_card.is_hovered = false
	if _card.hover_effect:
		_card.hover_effect.visible = false

	# Restaurar z_index y recorte de solapamiento si pertenece a un contenedor con recorte (mano o fila de oros)
	var parent = _card.get_parent()
	if parent and parent.has_method("get_card_clip_right"):
		_card.z_index = _card.get_meta("hand_base_z_index", _card.original_z_index)
		if _card.has_method("set_click_clip_right"):
			_card.set_click_clip_right(parent.get_card_clip_right(_card))
	elif _card.has_meta("gold_click_clip"):
		_card.z_index = _card.original_z_index
		if _card.has_method("set_click_clip_right"):
			_card.set_click_clip_right(_card.get_meta("gold_click_clip", -1.0))
	elif _card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
		_card.z_index = 0
		_card.original_z_index = 0
	else:
		_card.z_index = _card.original_z_index

	_card.emit_signal("card_unhovered", _card)

	# Volver a escala normal si había cambiado
	if _card.card_scale_hover != 1.0 or _card.is_selected:
		var tween = _card.create_tween()
		var target_scale_val = _card.base_scale * (_card.card_scale_selected if _card.is_selected else _card.card_scale_normal)
		tween.tween_property(_card, "scale", target_scale_val, _card.animation_speed)


func on_gui_input(event: InputEvent) -> void:
	# Si la carta está en mesa pero el cursor está sobre una carta de la mano, ceder el input a la mano
	if _card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
		var hand_c = _get_hand_card_under_mouse()
		if hand_c != null and hand_c != _card:
			if hand_c.get("_interaction") != null:
				hand_c._interaction.on_gui_input(event)
			return

	# Si es un arma equipada y el mouse está dentro del área del Aliado, ceder el input al Aliado
	if _card.wielder != null and is_instance_valid(_card.wielder):
		var mouse_over_wielder := Rect2(Vector2.ZERO, _card.wielder.size).has_point(_card.wielder.get_local_mouse_position())
		if mouse_over_wielder:
			if _card.wielder._interaction:
				_card.wielder._interaction.on_gui_input(event)
			return
	if event is InputEventMouseButton:
		# Right-click siempre funciona para inspección
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if Constants.VERBOSE_DIAG_LOGS:
				print("[DIAG] gui_input RIGHT-CLICK llegó a: %s (zona=%s, equipada_en=%s)" % [
					_card.card_name if _card.get("card_name") else "?",
					_card.current_zone if _card.get("current_zone") != null else "?",
					_card.get_parent().name if _card.get_parent() else "sin padre"
				])
			_card.emit_signal("card_right_clicked", _card)
			return

		# Diagnóstico de clicks (como el DIAG de click derecho, §10.7): se imprime ANTES del corte por
		# can_interact, para distinguir "no llegó", "llegó con can_interact = false" o "lo rechazó el
		# filtro" (este último ya avisa en CardInteractionModule._resolve_target_selection()).
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Constants.VERBOSE_DIAG_LOGS:
				print("[DIAG] gui_input LEFT-CLICK llegó a: %s (owner=%s, controller=%s, can_interact=%s, zona=%s)" % [
					_card.card_name if _card.get("card_name") else "?",
					_card.owner_id if _card.get("owner_id") != null else "?",
					_card.controller_id if _card.get("controller_id") != null else "?",
					str(_card.can_interact),
					_card.current_zone if _card.get("current_zone") != null else "?"
				])

		# Otras interacciones requieren can_interact
		if not _card.can_interact:
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					# Godot decide 'double_click' por tiempo y posición GLOBAL del mouse, no por nodo: tras
					# doble-clickear otra carta, un solo click en ésta puede llegar ya como double_click = true, y
					# quien solo escucha card_clicked (selección de objetivo) no se enteraría. Por eso se emite
					# también card_clicked, salvo que haya habido un press simple reciente de esta misma carta: en
					# un doble click real ya se emitió y duplicarlo dispararía handlers como _declare_attacker()
					# dos veces.
					var is_orphan_double_click := Time.get_ticks_msec() - _last_plain_click_ms > DOUBLE_CLICK_ECHO_WINDOW_MS
					if is_orphan_double_click:
						_card.emit_signal("card_clicked", _card)
					_card.emit_signal("card_double_clicked", _card)
				else:
					# NO llamar _start_drag() inmediatamente -- esperar movimiento
					_card._drag_pending = true
					_card._drag_start_pos = event.position
					_last_plain_click_ms = Time.get_ticks_msec()
					_card.emit_signal("card_clicked", _card)
			else:
				if _card._drag_pending:
					# El usuario soltó sin arrastrar — solo fue un click
					_card._drag_pending = false
				elif _card.is_dragging:
					_end_drag()

	elif event is InputEventMouseMotion:
		if not _card.can_interact:
			return
		if _card._drag_pending:
			var distance = event.position.distance_to(_card._drag_start_pos)
			if distance >= _card.DRAG_THRESHOLD:
				_card._drag_pending = false
				_start_drag(_card._drag_start_pos)
		elif _card.is_dragging:
			_update_drag(event.position)


func can_declare_attack_drag() -> bool:
	"""¿Un Aliado en el campo puede declararse atacante? Solo en fase Ataque (Vigilia termina con el
	botón "Atacar"). Furia evita la enfermedad de invocación (TurnManager.can_attack()), no salta
	la fase."""
	if _card.card_type != Constants.CardType.ALIADO:
		return false
	if _card.current_zone != Constants.Zone.LINEA_DEFENSA:
		return false
	return GameManager.current_phase == Constants.Phase.ATAQUE


func _start_drag(mouse_pos: Vector2) -> void:
	"""Inicia el arrastre de la carta"""
	if not _card.drag_enabled:
		return
	if _card.wielder != null:
		return
	if _card.current_state != Card.CardState.IN_HAND:
		if not can_declare_attack_drag():
			return

	_card.is_dragging = true
	_card.current_state = Card.CardState.DRAGGING
	_card.drag_offset = mouse_pos
	_card.original_position = _card.global_position  # Guardar posición global antes de top_level
	_card.original_z_index = _card.z_index
	_card.z_index = 300
	# Desacoplar del Container para que global_position no sea sobreescrita por el layout
	_card.top_level = true
	# Godot NO preserva la posición visual al activar top_level: 'position'
	# pasaba a interpretarse como absoluta de pantalla sin ningún ajuste, así
	# que la carta saltaba de inmediato a donde sea que ese valor apuntara
	# (por eso 'se iba a la esquina inferior derecha' apenas se la tomaba).
	# Hay que reaplicar la posición global recién guardada para que el
	# arrastre empiece exactamente donde la carta ya estaba.
	_card.global_position = _card.original_position

	var tween = _card.create_tween()
	tween.tween_property(_card, "scale", Vector2.ONE * _card.card_scale_selected, _card.animation_speed)


func _update_drag(mouse_pos: Vector2) -> void:
	"""Actualiza la posición durante el arrastre"""
	if not _card.is_dragging:
		return

	_card.global_position = _card.get_global_mouse_position() - _card.drag_offset
	_card.emit_signal("card_dragged", _card, _card.global_position)


func _end_drag() -> void:
	"""Finaliza el arrastre"""
	if not _card.is_dragging:
		return

	_card.is_dragging = false
	_card.emit_signal("card_dropped", _card, _card.global_position)

	# Verificar si hay zona de drop válida debajo
	var drop_zone = _get_drop_zone_under_mouse()
	if drop_zone and drop_zone.has_method("on_card_dropped"):
		# La zona de drop maneja la carta
		drop_zone.on_card_dropped(_card)
	else:
		# Regresar a la posición original con animación
		await return_to_hand()


func return_to_hand() -> void:
	"""Regresa la carta a su posición original (mano o campo) con animación"""
	if _card.wielder != null and is_instance_valid(_card.wielder):
		# Arma equipada: anclada a su portador sin top_level
		_card.current_state = Card.CardState.IN_PLAY
		_card.top_level = false
		var slot_idx: int = _card.wielder.equipped_weapons.find(_card) if "equipped_weapons" in _card.wielder else 0
		if slot_idx < 0:
			slot_idx = 0
		var target_pos := Vector2(0.0, Constants.WEAPON_OFFSET_Y + slot_idx * Constants.WEAPON_STACK_STEP_Y)
		var tween = _card.create_tween()
		tween.set_parallel(true)
		tween.tween_property(_card, "position", target_pos, 0.2).set_ease(Tween.EASE_OUT)
		tween.tween_property(_card, "rotation_degrees", 0.0, 0.2).set_ease(Tween.EASE_OUT)
		tween.tween_property(_card, "scale", _card.base_scale, 0.2).set_ease(Tween.EASE_OUT)
		await tween.finished
		_card.position = target_pos
		_card.top_level = false
		_card.z_index = _card.original_z_index
		return

	# Rotación de destino real: _card.target_rotation es siempre 0.0 (la inclinación de descanso en la
	# mano), pero si la carta está Convertida o Silenciada debe seguir mostrando el giro de 180° — sin
	# esto, cualquier llamada a return_to_hand (p.ej. el 'soltar' genérico que usa _declare_attacker al
	# declarar un atacante) pisaba ese giro y la carta 'se enderezaba' sola aunque siguiera
	# convertida/silenciada."""
	var is_opp: bool = (_card.owner_id == 1 or _card.controller_id == 1)
	var is_opp_in_play: bool = is_opp and _card.current_zone in [
		Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO,
		Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO
	]
	if _card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
		# Carta del campo: mantener top_level=true y regresar a su posición guardada en su slot
		_card.current_state = Card.CardState.IN_PLAY
		_card.top_level = true
		var return_pos: Vector2 = _card.get_meta("field_slot_pos", _card.global_position)
		var tween = _card.create_tween()
		tween.set_parallel(true)
		tween.tween_property(_card, "global_position", return_pos, 0.2).set_ease(Tween.EASE_OUT)
		tween.tween_property(_card, "rotation_degrees", 0.0, 0.2).set_ease(Tween.EASE_OUT)
		tween.tween_property(_card, "scale", _card.base_scale, 0.2).set_ease(Tween.EASE_OUT)
		await tween.finished
		_card._refresh_disabled_rotation()
	else:
		# Carta de la mano: animar de vuelta a la posición guardada
		_card.current_state = Card.CardState.IN_HAND
		var parent = _card.get_parent()
		var target_global_pos: Vector2 = _card.original_position
		var target_rot: float = _card.target_rotation
		var local_target_pos: Vector2 = Vector2.ZERO
		var has_local_target: bool = false

		if parent and parent.has_method("get_card_target_position"):
			local_target_pos = parent.get_card_target_position(_card)
			target_global_pos = parent.get_global_transform() * local_target_pos  # Control no tiene to_global()
			has_local_target = true
			if parent.has_method("get_card_target_rotation"):
				target_rot = parent.get_card_target_rotation(_card)
		elif parent:
			local_target_pos = parent.get_global_transform().affine_inverse() * target_global_pos  # Control no tiene to_local()
			has_local_target = true

		# Si no estuvo en drag (top_level == false) y ya está en reposo en la mano, no mover
		if not _card.top_level and has_local_target and _card.position.distance_to(local_target_pos) < 3.0:
			_card._refresh_disabled_rotation()
			_card.z_index = _card.original_z_index
			return

		var tween = _card.create_tween()
		tween.set_parallel(true)
		tween.tween_property(_card, "global_position", target_global_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(_card, "rotation_degrees", target_rot, 0.25).set_ease(Tween.EASE_OUT)
		tween.tween_property(_card, "scale", _card.base_scale, 0.25).set_ease(Tween.EASE_OUT)
		await tween.finished
		_card.top_level = false
		if has_local_target:
			_card.position = local_target_pos
		_card.rotation_degrees = target_rot
	if _card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
		_card.z_index = 0
		_card.original_z_index = 0
	else:
		_card.z_index = _card.original_z_index


func _get_drop_zone_under_mouse() -> Node:
	"""Detecta la zona de drop más específica bajo el mouse.

	La zona de batalla (LINEA_ATAQUE, ~700x96) está geométricamente contenida
	dentro de la zona de campo (LINEA_DEFENSA, ~800x240) — ver
	SceneSetupModule._setup_drop_zones(). Antes se devolvía la primera zona
	del grupo "drop_zones" que contuviera el mouse, y como field_drop se
	registra antes que battle_drop, soltar una carta cerca del centro del
	tablero (para declarar un atacante) siempre caía en field_drop → volvía
	a pagarse el coste como si se jugara de nuevo. Ahora gana la zona de
	área más chica entre todas las que contienen el punto (la más
	específica), sin depender del orden de registro."""
	var mouse_pos = _card.get_global_mouse_position()
	var best_zone: Node = null
	var best_area := INF

	for zone in _card.get_tree().get_nodes_in_group("drop_zones"):
		if zone is Control:
			var rect: Rect2 = zone.get_global_rect()
			if rect.has_point(mouse_pos):
				var area: float = rect.size.x * rect.size.y
				if area < best_area:
					best_area = area
					best_zone = zone

	return best_zone
