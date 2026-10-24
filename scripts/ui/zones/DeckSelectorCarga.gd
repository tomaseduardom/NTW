extends "res://scripts/ui/zones/DeckSelectorPublicos.gd"
## DeckSelectorCarga — familia Carga de DeckSelector.gd (ver DeckSelectorBase.gd).


func _get_autoload(node_name: String) -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/" + node_name)
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null(node_name)
	return null

# =============================================================================
# CARGA DE MAZOS
# =============================================================================


func _fetch_mazos() -> void:
	_mazos_load_resolved = false
	if is_inside_tree():
		# 65s: por encima del timeout HTTP real de 60s (ver ExternalApiClient
		# ._authed_request()) para no forzar el fallback local mientras una
		# respuesta todavía podría llegar a tiempo.
		get_tree().create_timer(65.0).timeout.connect(_on_mazos_load_watchdog_timeout)

	var api_client = _get_autoload("ExternalApiClient")
	if api_client:
		if not api_client.decks_received.is_connected(_on_external_decks_received):
			api_client.decks_received.connect(_on_external_decks_received, CONNECT_ONE_SHOT)
		if not api_client.decks_failed.is_connected(_on_external_decks_failed):
			api_client.decks_failed.connect(_on_external_decks_failed, CONNECT_ONE_SHOT)
		api_client.fetch_my_decks()
	else:
		_load_local_fallback()


func _on_mazos_load_watchdog_timeout() -> void:
	"""Se ejecuta 65s después de empezar a cargar, sin importar qué haya
	pasado con la cadena real de fetches. Si para entonces ya se resolvió
	solo (camino normal), no hace nada. Si no, fuerza el fallback local en
	vez de dejar el 'Invocando grimorios ancestrales...' para siempre."""
	if _mazos_load_resolved:
		return
	push_warning("[DeckSelector] La carga de mazos no resolvió en 65s — forzando mazos locales")
	_load_local_fallback()


func _on_external_decks_received(decks: Array) -> void:
	if _mazos_load_resolved:
		return
	_mazos = []
	for d in decks:
		d["_is_external"] = true
		d["_shadowforge_kind"] = "my"
		_mazos.append(d)
	_mazos.append_array(_get_preset_decks())
	if _mazos.is_empty():
		push_warning("[DeckSelector] Sin mazos propios ni presets — probando mazos locales")
		_load_local_fallback()
		return
	_fetch_and_merge_public_decks()


func _on_external_decks_failed(reason: String) -> void:
	if _mazos_load_resolved:
		return
	push_warning("[DeckSelector] No se pudieron cargar tus mazos (%s) — probando mazos locales" % reason)
	_load_local_fallback()

# =============================================================================
# FUSIÓN DE MAZOS PRIVADOS + PÚBLICOS: "Mis mazos" muestra los privados y la primera página de
# públicos. El popup de búsqueda (_open_public_deck_browser) sigue para buscar algo puntual.
# =============================================================================


func _fetch_and_merge_public_decks() -> void:
	"""Trae una primera página de mazos públicos (orden 'popular') y la
	fusiona en _mazos junto a los privados/preset ya armados, antes de
	poblar el carrusel. Si falla (sin conexión, API caída), no bloquea la
	pantalla — se sigue igual con lo que ya hay."""
	var api_client = _get_autoload("ExternalApiClient")
	if not api_client:
		_populate_options()
		return
	if not api_client.public_decks_received.is_connected(_on_initial_public_decks_received):
		api_client.public_decks_received.connect(_on_initial_public_decks_received, CONNECT_ONE_SHOT)
	if not api_client.public_decks_failed.is_connected(_on_initial_public_decks_failed):
		api_client.public_decks_failed.connect(_on_initial_public_decks_failed, CONNECT_ONE_SHOT)
	api_client.fetch_public_decks("", 1, "", "", "popular")


func _on_initial_public_decks_received(results: Array, _count: int) -> void:
	if _mazos_load_resolved:
		return
	# Solo datos resumidos aquí (sin "entries") — se resuelven de verdad solo
	# al confirmar (_on_confirm_pressed() -> _resolve_deck_entries()), no
	# tiene sentido bajar las cartas de mazos que el jugador quizás nunca
	# elija.
	for r in results:
		if not r is Dictionary:
			continue
		var owner := str(r.get("owner_username", "?"))
		var mazo := {
			"slug": "public-%d" % int(r.get("id", 0)),
			"nombre": "%s — por %s" % [str(r.get("name", "Mazo sin nombre")), owner],
			"arquetipo": str(r.get("race", "")),
			"raza": str(r.get("race", "")),
			"formato": str(r.get("format", "")),
			"entries": [],
			"id": int(r.get("id", 0)),
			"image_url": str(r.get("image_url", "")),
			"_is_external": true,
			"_shadowforge_kind": "public",
		}
		_mazos.append(mazo)
	_populate_options()


func _on_initial_public_decks_failed(_reason: String) -> void:
	if _mazos_load_resolved:
		return
	_populate_options()


func _get_preset_decks() -> Array:
	"""Presets: los embebidos en el .exe (res://data/decks/*.json, get_bundled_decks();
	arquitectura.md §12.1/§12), siempre disponibles, más los locales de user://decks/ (por máquina,
	vacíos en una instalación nueva) como extra. Se deduplican por slug."""
	var result: Array = []
	var seen_slugs: Dictionary = {}
	var loader = _get_autoload("DeckLoader")
	if not loader:
		return result

	if loader.has_method("get_bundled_decks"):
		for m in loader.get_bundled_decks():
			var slug := str(m.get("slug", ""))
			if slug.begins_with("preset-") and not seen_slugs.has(slug):
				m["_is_external"] = false
				result.append(m)
				seen_slugs[slug] = true

	if loader.has_method("get_local_decks"):
		for m in loader.get_local_decks():
			var slug := str(m.get("slug", ""))
			if slug.begins_with("preset-") and not seen_slugs.has(slug):
				m["_is_external"] = false
				result.append(m)
				seen_slugs[slug] = true

	return result


func _load_local_fallback() -> void:
	var loader = _get_autoload("DeckLoader")
	if loader:
		_mazos = loader.get_bundled_decks()
		if _mazos.is_empty():
			_mazos = loader.get_local_decks()
	else:
		_mazos = []

	for m in _mazos:
		m["_is_external"] = false

	if _mazos.is_empty():
		push_warning("[DeckSelector] Sin mazos disponibles. Usa 'Mazos aleatorios'.")
		_populate_with_error()
	else:
		print("[DeckSelector] Usando %d mazos offline" % _mazos.size())
		_populate_options()


func _populate_with_error() -> void:
	_mazos_load_resolved = true
	for child in _player_row.get_children():
		_player_row.remove_child(child)
		child.queue_free()
	var err = Label.new()
	err.text = "No se encontraron grimorios disponibles"
	err.add_theme_font_override("font", FONT_TITLE)
	err.add_theme_font_size_override("font_size", 16)
	err.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4, 1.0))
	_player_row.add_child(err)
	if _parchment_label:
		_parchment_label.text = "SIN MAZOS DISPONIBLES"
