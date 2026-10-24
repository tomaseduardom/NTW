extends Node
## DeckLoader - Sistema de carga de mazos para partidas
## Convierte datos JSON de la API en cartas instanciadas en el Castillo

# =============================================================================
# SEÑALES
# =============================================================================
signal deck_loaded(player_id: int, card_count: int)
signal deck_load_failed(player_id: int, error: String)
signal all_decks_ready  # Emitida cuando ambos jugadores tienen sus mazos cargados
signal loading_progress(player_id: int, current: int, total: int)

# =============================================================================
# CONFIGURACIÓN
# =============================================================================
const API_BASE_URL: String = "http://localhost:3000/api"

# =============================================================================
# ESTADO
# =============================================================================
var _decks_loaded: Dictionary = {}  # player_id -> bool
var _is_loading: bool = false
var _pending_requests: Dictionary = {}  # player_id -> HTTPRequest

# Almacén de mazos cargados (datos de cartas, no instancias)
var loaded_decks: Dictionary = {}  # player_id -> Array[Dictionary] (card data)

# =============================================================================
# INICIALIZACIÓN
# =============================================================================
func _ready() -> void:
	# ("módulos gordos" punto 1): CardDatabase/CardFactory/GameManager son autoloads garantizados — se
	# saca el cacheo redundante vía get_node_or_null (CardFactory y GameManager tampoco se usaban en
	# este archivo más allá de la asignación).
	print("[DeckLoader] Inicializado")


# =============================================================================
# API PÚBLICA
# =============================================================================
func load_deck_from_data(player_id: int, deck_data: Dictionary) -> void:
	"""Carga un mazo directamente desde datos ya obtenidos

	Args:
		player_id: ID del jugador
		deck_data: Diccionario con datos del mazo (incluyendo datos_json)
	"""
	_process_deck_data(player_id, deck_data)


func load_deck_from_external_data(player_id: int, deck_data: Dictionary) -> void:
	"""Carga un mazo de ExternalApiClient (ShadowForge). Parser más defensivo que
	load_deck_from_data(), por si la respuesta varía de forma."""
	_process_external_deck_data(player_id, deck_data)


func is_deck_loaded(player_id: int) -> bool:
	"""Verifica si el mazo de un jugador ya está cargado"""
	return _decks_loaded.get(player_id, false)


func are_all_decks_ready() -> bool:
	"""Verifica si ambos mazos están listos para jugar"""
	return _decks_loaded.get(0, false) and _decks_loaded.get(1, false)


# =============================================================================
# CARGA DE CARDDATABASE
# =============================================================================
func _ensure_card_database_loaded() -> void:
	"""Asegura que CardDatabase esté cargado antes de continuar"""
	# Si ya está cargado, continuar
	if CardDatabase.is_loaded:
		print("[DeckLoader] CardDatabase ya tiene %d cartas" % CardDatabase.cards.size())
		return

	# Si está cargando, esperar
	if CardDatabase.is_loading:
		print("[DeckLoader] Esperando a que CardDatabase termine de cargar...")
		await CardDatabase.cards_loaded
		print("[DeckLoader] CardDatabase cargado: %d cartas" % CardDatabase.cards.size())
		return

	# Si no está cargado ni cargando, iniciar carga
	print("[DeckLoader] Iniciando carga de CardDatabase...")
	CardDatabase.load_cards_from_api("all")
	await CardDatabase.cards_loaded
	print("[DeckLoader] CardDatabase cargado: %d cartas" % CardDatabase.cards.size())


# =============================================================================
# PROCESAMIENTO DEL MAZO
# =============================================================================
func _process_deck_data(player_id: int, deck_data: Dictionary) -> void:
	"""Procesa los datos del mazo y crea las cartas

	Args:
		player_id: ID del jugador
		deck_data: Datos completos del mazo desde la API
	"""
	var deck_name = deck_data.get("nombre", "Mazo sin nombre")
	print("[DeckLoader] Procesando mazo: %s" % deck_name)

	# Asegurar que CardDatabase esté cargado
	await _ensure_card_database_loaded()

	# Extraer datos_json (contiene main y side)
	var datos_json = deck_data.get("datos_json", {})

	# Normalizar: puede venir como string o como diccionario
	if datos_json is String:
		datos_json = JSON.parse_string(datos_json)
		if datos_json == null:
			datos_json = {}

	var main_deck: Dictionary = datos_json.get("main", {})
	var side_deck: Dictionary = datos_json.get("side", {})

	# Alternativa: {"entries": [{"card_detail": {"myl_id": ...}, "quantity"}, ...]} (mazos de
	# /decks/public/{id}/ y presets, ver DeckSelector._get_preset_decks()), además de datos_json.main.
	# El "id" de cada entry es la fila de ShadowForge (DeckEntry.id), NO la carta: el myl_id está en
	# entry.card_detail.myl_id.
	if main_deck.is_empty() and deck_data.get("entries") is Array:
		var main_dict := {}
		for entry in deck_data.entries:
			if not entry is Dictionary:
				continue
			var card_detail = entry.get("card_detail", {})
			var cid: String
			if card_detail is Dictionary and card_detail.get("myl_id") != null:
				cid = str(card_detail.get("myl_id", ""))
			else:
				cid = str(entry.get("myl_id", entry.get("card_id", entry.get("id", ""))))
			if cid.is_empty():
				continue
			var qty = int(entry.get("quantity", entry.get("qty", 1)))
			main_dict[cid] = main_dict.get(cid, 0) + qty
		main_deck = main_dict

	if main_deck.is_empty():
		emit_signal("deck_load_failed", player_id, "El mazo no tiene cartas en el main deck")
		return

	# Calcular total de cartas para el progreso
	var total_cards = 0
	for uuid in main_deck:
		total_cards += int(main_deck[uuid])

	print("[DeckLoader] Main deck: %d cartas únicas, %d total" % [main_deck.size(), total_cards])

	# Recopilar datos de cartas (no instancias aún)
	var deck_card_data = await _collect_deck_card_data(player_id, main_deck, total_cards)

	if deck_card_data.is_empty():
		emit_signal("deck_load_failed", player_id, "No se pudieron encontrar cartas (CardDatabase tiene %d cartas)" % CardDatabase.cards.size())
		return

	# Guardar datos del mazo (se instanciarán cuando Main.gd lo solicite)
	loaded_decks[player_id] = deck_card_data

	# Barajar los datos
	loaded_decks[player_id].shuffle()

	# Marcar como cargado
	_decks_loaded[player_id] = true
	emit_signal("deck_loaded", player_id, deck_card_data.size())

	print("[DeckLoader] Mazo de jugador %d cargado: %d cartas" % [player_id, deck_card_data.size()])

	# Verificar si ambos mazos están listos
	if are_all_decks_ready():
		emit_signal("all_decks_ready")
		print("[DeckLoader] ¡Ambos mazos listos para la partida!")


func _process_external_deck_data(player_id: int, deck_data: Dictionary) -> void:
	"""Variante de _process_deck_data() para la API nueva (ExternalApiClient).
	Prueba varias formas razonables de mazo antes de rendirse, porque no se
	pudo confirmar la forma exacta de /external/my-decks/ sin credenciales
	reales. Si nada calza, falla con un mensaje claro (y el JSON crudo en
	consola) en vez de romper algo silenciosamente."""
	var deck_name = str(deck_data.get("nombre", deck_data.get("name", "Mazo sin nombre")))
	print("[DeckLoader] Procesando mazo externo: %s" % deck_name)

	await _ensure_card_database_loaded()

	var datos_json = deck_data.get("datos_json", deck_data.get("data", deck_data))
	if datos_json is String:
		datos_json = JSON.parse_string(datos_json)
		if datos_json == null:
			datos_json = {}
	if not datos_json is Dictionary:
		datos_json = {}

	var main_deck = datos_json.get("main", datos_json.get("main_deck", datos_json.get("maindeck", {})))
	if not main_deck is Dictionary:
		main_deck = {}

	# Forma real confirmada con curl contra /decks/my/{id}/ y /decks/public/{id}/:
	# {"entries": [{"id": <DeckEntry.id, NO es la carta>, "card_detail": {"myl_id": "..."}, "quantity"}]}
	if main_deck.is_empty() and deck_data.get("entries") is Array:
		var main_dict := {}
		for entry in deck_data.entries:
			if not entry is Dictionary:
				continue
			var card_detail = entry.get("card_detail", {})
			var cid: String
			if card_detail is Dictionary and card_detail.get("myl_id") != null:
				cid = str(card_detail.get("myl_id", ""))
			else:
				cid = str(entry.get("myl_id", entry.get("card_id", entry.get("id", ""))))
			if cid.is_empty():
				continue
			var qty = int(entry.get("quantity", entry.get("qty", 1)))
			main_dict[cid] = main_dict.get(cid, 0) + qty
		main_deck = main_dict

	# Alternativa: lista plana de {myl_id/card_id/id, quantity, is_side}
	if main_deck.is_empty() and datos_json.get("cards") is Array:
		var main_dict := {}
		for entry in datos_json.cards:
			if not entry is Dictionary or entry.get("is_side", false):
				continue
			var cid = str(entry.get("myl_id", entry.get("card_id", entry.get("id", ""))))
			if cid.is_empty():
				continue
			var qty = int(entry.get("quantity", entry.get("qty", 1)))
			main_dict[cid] = main_dict.get(cid, 0) + qty
		main_deck = main_dict

	if main_deck.is_empty():
		push_warning("[DeckLoader] No se reconoció la forma del mazo externo '%s'. JSON crudo (primeros 600 chars): %s" % [
			deck_name, JSON.stringify(deck_data).substr(0, 600)
		])
		emit_signal("deck_load_failed", player_id, "Formato de mazo externo no reconocido (ver Output/consola)")
		return

	var total_cards = 0
	for cid in main_deck:
		total_cards += int(main_deck[cid])

	print("[DeckLoader] Mazo externo '%s': %d cartas únicas, %d total" % [deck_name, main_deck.size(), total_cards])

	var deck_card_data = await _collect_deck_card_data(player_id, main_deck, total_cards)

	if deck_card_data.is_empty():
		emit_signal("deck_load_failed", player_id, "No se encontraron cartas del mazo '%s' en CardDatabase (%d cartas cargadas)" % [
			deck_name, CardDatabase.cards.size()
		])
		return

	loaded_decks[player_id] = deck_card_data
	loaded_decks[player_id].shuffle()

	_decks_loaded[player_id] = true
	emit_signal("deck_loaded", player_id, deck_card_data.size())
	print("[DeckLoader] Mazo externo de jugador %d cargado: %d cartas" % [player_id, deck_card_data.size()])

	if are_all_decks_ready():
		emit_signal("all_decks_ready")
		print("[DeckLoader] ¡Ambos mazos listos para la partida!")


func _collect_deck_card_data(player_id: int, deck_list: Dictionary, total: int) -> Array:
	"""Recopila los datos de cartas del mazo (sin instanciar)

	Args:
		player_id: ID del jugador (para progreso)
		deck_list: {uuid: quantity}
		total: Total de cartas para reportar progreso

	Returns: Array de Dictionaries con datos de cartas
	"""
	var card_data_list: Array = []
	var current = 0
	var not_found: Array = []

	for uuid in deck_list:
		var quantity = int(deck_list[uuid])
		var card_data = _get_card_data(uuid)

		if card_data.is_empty():
			not_found.append(uuid)
			continue

		# Añadir N copias de los datos de esta carta
		for i in range(quantity):
			card_data_list.append(card_data.duplicate())
			current += 1
			emit_signal("loading_progress", player_id, current, total)

	if not_found.size() > 0:
		push_warning("[DeckLoader] %d cartas no encontradas: %s" % [not_found.size(), str(not_found).substr(0, 200)])

	return card_data_list


func _get_card_data(uuid: String) -> Dictionary:
	"""Obtiene los datos de una carta por su UUID o ID"""
	if not CardDatabase.is_loaded:
		return {}

	# CardDatabase.get_card() ahora busca por ID y UUID
	return CardDatabase.get_card(uuid)


# =============================================================================
# ACCESO A DATOS DE MAZOS
# =============================================================================
func get_deck_data(player_id: int) -> Array:
	"""Obtiene los datos de cartas del mazo cargado (para que Main.gd los instancie)"""
	return loaded_decks.get(player_id, [])


func clear_deck_data(player_id: int) -> void:
	"""Limpia los datos del mazo después de usarlos"""
	loaded_decks.erase(player_id)
	_decks_loaded.erase(player_id)


# =============================================================================
# MAZOS BUNDLED — res://data/decks/ (incluidos en el proyecto exportado)
# =============================================================================
const BUNDLED_DECKS_PATH: String = "res://data/decks/"

func get_bundled_decks() -> Array:
	"""Devuelve lista de mazos bundleados en res://data/decks/*.json"""
	var result: Array = []
	var dir = DirAccess.open(BUNDLED_DECKS_PATH)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var file = FileAccess.open(BUNDLED_DECKS_PATH + fname, FileAccess.READ)
			if file:
				var data = JSON.parse_string(file.get_as_text())
				file.close()
				if data is Dictionary and data.has("slug"):
					result.append({
						"slug":      data.get("slug", ""),
						"nombre":    data.get("nombre", fname.get_basename()),
						"arquetipo": data.get("arquetipo", ""),
						"formato":   data.get("formato", ""),
						"datos_json": data.get("datos_json", {}),
						"entries":   data.get("entries", []),
					})
		fname = dir.get_next()
	print("[DeckLoader] %d mazos bundled encontrados" % result.size())
	return result


# =============================================================================
# MAZOS LOCALES — Guardar y cargar desde user://decks/
# =============================================================================
const LOCAL_DECKS_PATH: String = "user://decks/"

func get_local_decks() -> Array:
	"""Devuelve lista de mazos guardados localmente [{slug, nombre, arquetipo, formato}]."""
	var result: Array = []
	var dir = DirAccess.open(LOCAL_DECKS_PATH)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var file = FileAccess.open(LOCAL_DECKS_PATH + fname, FileAccess.READ)
			if file:
				var data = JSON.parse_string(file.get_as_text())
				file.close()
				if data is Dictionary and data.has("slug"):
					result.append({
						"slug":     data.get("slug", ""),
						"nombre":   data.get("nombre", fname.get_basename()),
						"arquetipo": data.get("arquetipo", ""),
						"formato":  data.get("formato", ""),
						"datos_json": data.get("datos_json", {}),
						"entries":   data.get("entries", []),
					})
		fname = dir.get_next()
	print("[DeckLoader] %d mazos locales encontrados" % result.size())
	return result


# =============================================================================
# CARGA OFFLINE / TESTING
# =============================================================================
func load_test_deck(player_id: int, card_ids: Array) -> void:
	"""Carga un mazo de prueba con IDs específicos (para testing)

	Args:
		player_id: ID del jugador
		card_ids: Array de IDs de cartas (pueden repetirse)
	"""
	await _ensure_card_database_loaded()
	print("[DeckLoader] Cargando mazo de prueba para jugador %d..." % player_id)

	var deck_data: Array = []

	for card_id in card_ids:
		var card_data = _get_card_data(str(card_id))
		if not card_data.is_empty():
			deck_data.append(card_data.duplicate())

	if deck_data.is_empty():
		emit_signal("deck_load_failed", player_id, "No se encontraron cartas de prueba")
		return

	loaded_decks[player_id] = deck_data
	loaded_decks[player_id].shuffle()

	_decks_loaded[player_id] = true
	emit_signal("deck_loaded", player_id, deck_data.size())

	if are_all_decks_ready():
		emit_signal("all_decks_ready")


func load_random_deck(player_id: int, count: int = 40) -> void:
	"""Genera un mazo aleatorio desde las cartas disponibles (para testing)

	Args:
		player_id: ID del jugador
		count: Número de cartas en el mazo
	"""
	await _ensure_card_database_loaded()

	if not CardDatabase.is_loaded:
		emit_signal("deck_load_failed", player_id, "CardDatabase no está cargado")
		return

	print("[DeckLoader] Generando mazo aleatorio de %d cartas para jugador %d..." % [count, player_id])

	var all_cards = CardDatabase.get_all_cards()
	if all_cards.is_empty():
		emit_signal("deck_load_failed", player_id, "No hay cartas disponibles")
		return

	var deck_data: Array = []

	for i in range(count):
		var random_data = all_cards[randi() % all_cards.size()]
		deck_data.append(random_data.duplicate())

	loaded_decks[player_id] = deck_data
	loaded_decks[player_id].shuffle()

	_decks_loaded[player_id] = true
	emit_signal("deck_loaded", player_id, deck_data.size())

	if are_all_decks_ready():
		emit_signal("all_decks_ready")


# =============================================================================
# UTILIDADES
# =============================================================================
func get_deck_count(player_id: int) -> int:
	"""Obtiene el número de cartas en el mazo cargado"""
	return loaded_decks.get(player_id, []).size()
