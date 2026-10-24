extends "res://scripts/ui/zones/DeckSelectorCarga.gd"
## DeckSelectorCarrusel — familia Carrusel de DeckSelector.gd (ver DeckSelectorBase.gd).


# =============================================================================
# CONSTRUCCIÓN DE CADA GRIMORIO EN EL CARRUSEL
# =============================================================================


func _cancel_all_cover_image_downloads() -> void:
	"""Cancela los HTTPRequest de portadas en vuelo (no solo los de la cola). Se llama al confirmar un
	mazo, para liberar la red antes del pedido de /decks/my/{id}/. Los nodos no se reusan: se
	liberan."""
	_cover_image_queue.clear()
	for http in _cover_image_active_requests.duplicate():
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	_cover_image_active_requests.clear()
	_cover_images_in_flight = 0

# =============================================================================
# NAVEGACIÓN Y CONTROL DEL CARRUSEL
# =============================================================================


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_left()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_right()


func _scroll_left() -> void:
	if not _scroll_container: return
	var stride := int(CARD_SIZE.x + 20)
	var current := _scroll_container.scroll_horizontal
	var target_scroll = max(0, int(round(float(current - stride) / float(stride))) * stride)
	var tw = create_tween()
	tw.tween_property(_scroll_container, "scroll_horizontal", target_scroll, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _scroll_right() -> void:
	if not _scroll_container: return
	var stride := int(CARD_SIZE.x + 20)
	var current := _scroll_container.scroll_horizontal
	var target_scroll = int(round(float(current + stride) / float(stride))) * stride
	var tw = create_tween()
	tw.tween_property(_scroll_container, "scroll_horizontal", target_scroll, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _unhandled_input(event: InputEvent) -> void:
	if not _overlay or not is_instance_valid(_overlay): return
	if not event.is_pressed() or event.is_echo(): return

	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.keycode == KEY_LEFT):
		_navigate_deck(-1)
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.keycode == KEY_RIGHT):
		_navigate_deck(1)
	elif event.is_action_pressed("ui_accept") or (event is InputEventKey and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE)):
		if _selected_player_idx < 0 and _mazos.size() > 0:
			_selected_player_idx = 0
		_on_confirm_pressed()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_ESCAPE):
		# Escape: si el popup de mazos públicos está abierto, lo cierra primero (un nivel por vez); si no,
		# cancela la selección y vuelve al menú principal.
		if _public_browser_overlay and is_instance_valid(_public_browser_overlay):
			_public_browser_overlay.queue_free()
			_public_browser_overlay = null
			_disconnect_public_browser_signals()
			return
		if _confirming:
			return  # ya se está confirmando/cargando — no cancelar a mitad de camino
		_close()
		emit_signal("selection_cancelled")


func _navigate_deck(direction: int) -> void:
	if _mazos.is_empty(): return
	var next_idx = _selected_player_idx + direction
	if _selected_player_idx < 0:
		next_idx = 0
	next_idx = clamp(next_idx, 0, _mazos.size() - 1)
	if next_idx != _selected_player_idx:
		_on_card_pressed(next_idx)


func _on_confirm_pressed() -> void:
	if _mazos.is_empty() or _selected_player_idx < 0 or _selected_player_idx >= _mazos.size():
		return
	# Guarda de re-entrada (ver comentario en la declaración de _confirming
	# más arriba) — sin esto, clickear varias veces mientras ya está
	# cargando mandaba pedidos duplicados al mismo mazo, saturando la API.
	if _confirming:
		return
	_confirming = true
	if _btn_confirm_clicker:
		_btn_confirm_clicker.disabled = true

	# Cortar las descargas de portada pendientes al confirmar: ya no hacen falta y liberan la red para
	# bajar las cartas del mazo elegido.
	_cancel_all_cover_image_downloads()

	# Destello esmeralda de confirmación
	if _confirm_flash and is_instance_valid(_confirm_flash):
		var tw = _confirm_flash.create_tween()
		tw.tween_property(_confirm_flash, "color:a", 0.65, 0.08)
		tw.tween_property(_confirm_flash, "color:a", 0.0, 0.14)
		await tw.finished

	var player_deck: Dictionary = _mazos[_selected_player_idx]
	# Mazo del bot: al azar entre los presets completos (no entre todos, que incluyen mazos personales
	# incompletos); si no hay ninguno, entre todos.
	var bot_pool: Array = _mazos.filter(func(m: Dictionary) -> bool:
		if not str(m.get("slug", "")).begins_with("preset-"):
			return false
		var total := 0
		for e in m.get("entries", []):
			total += int(e.get("quantity", 1))
		return total >= 40)
	var opponent_deck: Dictionary = {}
	if not bot_pool.is_empty():
		opponent_deck = bot_pool[randi() % bot_pool.size()]
	elif not _mazos.is_empty():
		opponent_deck = _mazos[randi() % _mazos.size()]

	# Los mazos de ShadowForge de la lista resumida (privados o públicos) no traen "entries": se bajan
	# solo al confirmar uno.
	if _needs_entries_fetch(player_deck):
		if _deck_sub_banner:
			_deck_sub_banner.text = "Cargando cartas del mazo..."
		var resolved_player := await _resolve_deck_entries(player_deck)
		if resolved_player.is_empty():
			if _deck_sub_banner:
				_deck_sub_banner.text = "No se pudo cargar este mazo (revisa tu conexión) — inténtalo de nuevo"
			else:
				push_warning("[DeckSelector] No se pudo cargar '%s' — sin conexión con ShadowForge" % str(player_deck.get("nombre", "")))
			_confirming = false
			if _btn_confirm_clicker:
				_btn_confirm_clicker.disabled = false
			return
		player_deck = resolved_player
		_mazos[_selected_player_idx] = resolved_player

	if _needs_entries_fetch(opponent_deck):
		var resolved_opponent := await _resolve_deck_entries(opponent_deck)
		if resolved_opponent.is_empty():
			# El mazo aleatorio del oponente no cargó — en vez de arrancar la
			# partida con un mazo vacío en silencio, se usa el primer mazo
			# que YA tenga entries (preset/local) como respaldo.
			opponent_deck = {}
			for m: Dictionary in _mazos:
				if not _needs_entries_fetch(m):
					opponent_deck = m
					break
		else:
			opponent_deck = resolved_opponent

	if opponent_deck.is_empty():
		# Ninguna de las dos resoluciones anteriores dejó un mazo rival con
		# entries (ni el aleatorio ni el respaldo) — abortar en vez de
		# arrancar la partida con decks_selected emitiendo un mazo vacío en
		# silencio (reintroducía el bug de "mazo vacío" ya arreglado para
		# _on_random_pressed()).
		if _deck_sub_banner:
			_deck_sub_banner.text = "No se pudo cargar un mazo rival (revisa tu conexión) — inténtalo de nuevo"
		else:
			push_warning("[DeckSelector] No se pudo resolver ningún mazo rival con entries — abortando confirmación")
		_confirming = false
		if _btn_confirm_clicker:
			_btn_confirm_clicker.disabled = false
		return

	_close()
	emit_signal("decks_selected", player_deck, opponent_deck,
		player_deck.get("_is_external", false), opponent_deck.get("_is_external", false))


func _needs_entries_fetch(mazo: Dictionary) -> bool:
	"""Un mazo de ShadowForge (privado o público) recién agregado a _mazos
	desde la lista resumida (_on_external_decks_received()/
	_on_initial_public_decks_received()) todavía no tiene 'entries' reales —
	los mazos preset/locales y los públicos elegidos desde el popup de
	búsqueda (_import_public_deck()) SÍ las traen desde que se agregan, así
	que no necesitan este fetch extra."""
	if not mazo.get("_is_external", false):
		return false
	var entries = mazo.get("entries", [])
	return not (entries is Array and not entries.is_empty())


func _resolve_deck_entries(mazo: Dictionary) -> Dictionary:
	"""Baja las 'entries' de un mazo de ShadowForge (privado o público) que no las tiene (ver
	_needs_entries_fetch()). Devuelve el Dictionary con 'entries', o {} si falló (HTTP, desconexión
	o timeout).
	Estado en un Dictionary ("_state"): los lambdas de GDScript capturan las variables locales por
	valor, así que "done = true" dentro de on_ok/on_fail no se veía afuera y el bucle esperaba
	siempre los 60 s (arquitectura.md §13.17)."""
	var deck_id := int(mazo.get("id", -1))
	if Constants.VERBOSE_DIAG_LOGS:
		print("[DeckSelector] _resolve_deck_entries: nombre='%s' id=%d kind='%s'" % [
			str(mazo.get("nombre", mazo.get("name", "?"))), deck_id, str(mazo.get("_shadowforge_kind", "?"))
		])
	if deck_id < 0:
		return {}
	var api_client = _get_autoload("ExternalApiClient")
	if not api_client:
		return {}
	var kind := str(mazo.get("_shadowforge_kind", "public"))

	var _state := {"done": false, "result": {}}
	var on_ok := func(deck_data: Dictionary):
		var r: Dictionary = mazo.duplicate(true)
		r["entries"] = deck_data.get("entries", [])
		_state["result"] = r
		_state["done"] = true
	var on_fail := func(_reason: String):
		_state["done"] = true

	if kind == "my":
		api_client.my_deck_detail_received.connect(on_ok, CONNECT_ONE_SHOT)
		api_client.my_deck_detail_failed.connect(on_fail, CONNECT_ONE_SHOT)
		api_client.fetch_my_deck_entries(deck_id)
	else:
		api_client.public_deck_detail_received.connect(on_ok, CONNECT_ONE_SHOT)
		api_client.public_deck_detail_failed.connect(on_fail, CONNECT_ONE_SHOT)
		api_client.fetch_public_deck_entries(deck_id)

	# Salvaguarda: si por algún motivo ninguna señal llega, no colgar la
	# pantalla para siempre. 60s calza con el timeout real de HTTPRequest en
	# ExternalApiClient.
	var waited := 0.0
	while not _state["done"] and waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	if Constants.VERBOSE_DIAG_LOGS:
		print("[DeckSelector] _resolve_deck_entries: done=%s waited=%.1fs" % [str(_state["done"]), waited])

	if not _state["done"]:
		if api_client.my_deck_detail_received.is_connected(on_ok):
			api_client.my_deck_detail_received.disconnect(on_ok)
		if api_client.my_deck_detail_failed.is_connected(on_fail):
			api_client.my_deck_detail_failed.disconnect(on_fail)
		if api_client.public_deck_detail_received.is_connected(on_ok):
			api_client.public_deck_detail_received.disconnect(on_ok)
		if api_client.public_deck_detail_failed.is_connected(on_fail):
			api_client.public_deck_detail_failed.disconnect(on_fail)
		return {}

	return _state["result"]


func _on_random_pressed() -> void:
	# En sala online, "Mazos aleatorios" = elegir un mazo al azar para mi lado y seguir como un
	# Confirmar, para pasar por el intercambio de mazos por red. Emitir {}/{} hacía que
	# GameBootstrap._on_decks_selected() usara el flujo de prueba local y arrancara sin esperar al otro
	# jugador.
	if NetworkClient.room_code != "" and not _mazos.is_empty():
		_selected_player_idx = randi() % _mazos.size()
		_on_confirm_pressed()
		return
	_close()
	emit_signal("decks_selected", {}, {}, false, false)


func _close() -> void:
	if _canvas_layer and is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()
		_canvas_layer = null
	elif _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
