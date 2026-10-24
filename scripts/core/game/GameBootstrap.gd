extends Node
class_name GameBootstrap
## GameBootstrap — Carga de cartas, selección de mazos, dados y preparación de partida.
## Se instancia como hijo de Main en _ready().

var _main: Node = null
const DeckValidatorScript = preload("res://scripts/core/cards/DeckValidator.gd")

var _match_cancelled := false
## Partida en línea: el "hello" del otro lado llegó y coincide con esta versión.
var _peer_hello_ok := false
## Sube cuando cambia el protocolo de red aunque no cambie la versión del juego.
const NET_PROTOCOL := 1


func setup(main: Node) -> void:
	_main = main


func start() -> void:
	"""Punto de entrada: carga cartas y arranca el flujo de inicio."""
	_load_cards()


# =============================================================================
# CARGA DE CARTAS
# =============================================================================
func _load_cards() -> void:
	"""Carga las cartas: bundled (res://) → cache (user://) → API externa.
	La API vieja (load_cards_from_api, localhost:3000) ya no está disponible —
	ver ExternalApiClient.gd. Bundled/cache normalmente cubren esto (5607
	cartas ya incluidas), así que este último paso rara vez se ejecuta."""
	if CardDatabase.load_cards_from_bundled():
		_main._update_debug("Cartas bundled: %d. Iniciando juego..." % CardDatabase.cards.size())
		_show_deck_selector()
		return
	if CardDatabase.load_cards_from_cache():
		_main._update_debug("Cartas desde cache: %d. Iniciando juego..." % CardDatabase.cards.size())
		_show_deck_selector()
		return
	if not CardDatabase.cards_loaded.is_connected(_on_cards_loaded):
		CardDatabase.cards_loaded.connect(_on_cards_loaded)
	if not CardDatabase.cards_load_failed.is_connected(_on_cards_load_failed):
		CardDatabase.cards_load_failed.connect(_on_cards_load_failed)
	_main._update_debug("Cargando cartas desde la API externa...")
	CardDatabase.load_cards_from_external_api()


func _on_cards_loaded(count: int) -> void:
	_main._update_debug("Cartas cargadas: %d" % count)
	CardDatabase.save_cards_to_cache()
	CardDatabase.export_for_bundling()
	_show_deck_selector()


func _on_cards_load_failed(error: String) -> void:
	_main._update_debug("Error cargando cartas: %s. Usando cartas de prueba." % error)
	_show_deck_selector()


# =============================================================================
# SELECCIÓN DE MAZOS
# =============================================================================
func _show_deck_selector() -> void:
	"""Muestra el popup de selección de mazos antes del sorteo de dados."""
	var script = load("res://scripts/ui/zones/DeckSelector.gd")
	if not script:
		push_warning("[Bootstrap] DeckSelector.gd no encontrado — saltando al sorteo")
		_show_dice_roll()
		return
	var selector = script.new()
	_main.add_child(selector)
	selector.decks_selected.connect(_on_decks_selected)
	selector.selection_cancelled.connect(_on_deck_selection_cancelled)
	selector.show_selector(_main)


func _on_deck_selection_cancelled() -> void:
	"""Escape en DeckSelector cancela la elección de mazo: vuelve al menú principal (mismo destino que
	el botón "Volver" de OnlineConnect/DeckManager/BackSelector)."""
	if NetworkClient.room_code != "":
		NetworkClient.disconnect_from_relay()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")


func _on_decks_selected(player_data: Dictionary, opponent_data: Dictionary, player_is_external: bool = false, opponent_is_external: bool = false) -> void:
	# get_node_or_null("/root/...") en vez del identificador global: aunque MatchLoadingOverlay es
	# autoload, un editor que aún no lo indexó da "Identifier not found". La búsqueda por ruta se
	# resuelve en ejecución.
	var _loading_overlay := get_node_or_null("/root/MatchLoadingOverlay")
	if _loading_overlay:
		_loading_overlay.show_loading(_main, "PREPARANDO PARTIDA", "Barajando los grimorios...")

	if player_data.is_empty() or opponent_data.is_empty():
		_show_dice_roll()
		return
	if not DeckLoader.all_decks_ready.is_connected(_show_dice_roll):
		DeckLoader.all_decks_ready.connect(_show_dice_roll, CONNECT_ONE_SHOT)
	# Escuchar deck_load_failed: si un mazo no tiene ninguna carta encontrable en CardDatabase, sin
	# esto el juego esperaba para siempre un all_decks_ready que no llega.
	if not DeckLoader.deck_load_failed.is_connected(_on_deck_load_failed):
		DeckLoader.deck_load_failed.connect(_on_deck_load_failed)
	# Jugador y oponente pueden venir de orígenes distintos ahora: tu propio mazo (externo) para uno,
	# un preset por raza (local) para el otro — cada lado se enruta según SU propio origen, no uno
	# compartido.
	if player_is_external:
		DeckLoader.load_deck_from_external_data(0, player_data)
	else:
		DeckLoader.load_deck_from_data(0, player_data)

	# Multijugador remoto (docs/plans/2026-09-09-multiplayer-remoto-design.md): con una sala activa, el
	# mazo del jugador 1 no sale de aquí. En el Anfitrión llega por red (el mazo real del Remoto). El
	# Remoto no corre su propia partida: manda su mazo (cargado arriba como jugador 0) y espera;
	# RemoteMirrorController refleja la partida.
	if NetworkClient.room_code != "":
		if not NetworkClient.message_received.is_connected(_on_network_match_cancelled):
			NetworkClient.message_received.connect(_on_network_match_cancelled)
		var early_cancel: Dictionary = NetworkClient.last_message_by_op.get("match_cancelled", {})
		if not early_cancel.is_empty():
			_on_network_match_cancelled(early_cancel)
			return
		# Versión: los dos se mandan su "hello" antes del mazo (llega antes, mismo canal).
		if not NetworkClient.message_received.is_connected(_on_network_hello):
			NetworkClient.message_received.connect(_on_network_hello)
		NetworkClient.send_message(_local_hello())
		var early_hello: Dictionary = NetworkClient.last_message_by_op.get("hello", {})
		if not early_hello.is_empty():
			_on_network_hello(early_hello)
		if _match_cancelled:
			return
		if NetworkClient.is_host:
			_load_opponent_deck_from_network()
		else:
			_send_own_deck_and_wait_for_host()
		return

	if opponent_is_external:
		DeckLoader.load_deck_from_external_data(1, opponent_data)
	else:
		DeckLoader.load_deck_from_data(1, opponent_data)


func _load_opponent_deck_from_network() -> void:
	"""Modo Anfitrión conectado: el mazo del jugador 1 llega por el mensaje
	{"op":"deck","card_ids":[...]} que manda el Remoto — puede haber llegado
	antes de que esta instancia empezara a escuchar (el Remoto suele
	confirmar su propio mazo antes de que el Anfitrión confirme el suyo), por
	eso se revisa primero el último mensaje guardado en NetworkClient."""
	var pending: Dictionary = NetworkClient.last_message_by_op.get("deck", {})
	if not pending.is_empty():
		_apply_network_opponent_deck(pending)
		return
	# Si el Anfitrión ya eligió y el Remoto todavía no mandó su mazo, se muestra "esperando jugador"
	# (mismo overlay que _send_deck_to_host() del lado Remoto).
	var _loading_overlay := get_node_or_null("/root/MatchLoadingOverlay")
	if _loading_overlay:
		_loading_overlay.show_loading(_main, "ESPERANDO JUGADOR",
			"Tu mazo ya está listo — esperando a que el otro jugador elija el suyo...")
	if not NetworkClient.message_received.is_connected(_on_network_message_while_waiting_deck):
		NetworkClient.message_received.connect(_on_network_message_while_waiting_deck)


func _on_network_message_while_waiting_deck(data: Dictionary) -> void:
	if data.get("op", "") != "deck":
		return
	if NetworkClient.message_received.is_connected(_on_network_message_while_waiting_deck):
		NetworkClient.message_received.disconnect(_on_network_message_while_waiting_deck)
	_apply_network_opponent_deck(data)


func _apply_network_opponent_deck(data: Dictionary) -> void:
	if _match_cancelled:
		return
	if not _peer_hello_ok:
		_cancel_online_match("version", ["El rival usa una versión del juego sin chequeo de versión."])
		return
	var card_ids: Array = data.get("card_ids", []) if data.get("card_ids") is Array else []
	var errors: Array = DeckValidatorScript.validate_ids(card_ids)
	if not errors.is_empty():
		_cancel_online_match("remote", errors)
		return
	DeckLoader.load_test_deck(1, card_ids)


# =============================================================================
# VERSIÓN (hello) Y CANCELACIÓN DE PARTIDA EN LÍNEA (mazo inválido, DeckValidator)
# =============================================================================
func _local_hello() -> Dictionary:
	return {
		"op": "hello",
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"protocol": NET_PROTOCOL,
		"cards": FileAccess.get_md5(CardDatabase.BUNDLED_CARDS_PATH),
	}


func _on_network_hello(data: Dictionary) -> void:
	if data.get("op", "") != "hello" or _peer_hello_ok or _match_cancelled:
		return
	var own := _local_hello()
	var peer_version := str(data.get("version", "?")).left(32)
	var errors: Array = []
	if peer_version != own.version or int(data.get("protocol", -1)) != NET_PROTOCOL:
		errors.append("Tu versión: %s — versión del rival: %s." % [own.version, peer_version])
	elif str(data.get("cards", "")) != own.cards:
		errors.append("La base de cartas del rival es distinta a la tuya.")
	if not errors.is_empty():
		_cancel_online_match("version", errors)
		return
	_peer_hello_ok = true


func _cancel_online_match(who: String, errors: Array) -> void:
	"""Cancela la partida en línea: el mazo de `who` ("host"/"remote") no cumple las reglas, o
	`who` == "version" (versiones distintas). Avisa al otro lado ({"op":"match_cancelled"}) y
	muestra el motivo."""
	if _match_cancelled:
		return
	_match_cancelled = true
	NetworkClient.send_message({"op": "match_cancelled", "who": who, "errors": errors})
	_show_match_cancelled(who, errors)


func _on_network_match_cancelled(data: Dictionary) -> void:
	if data.get("op", "") != "match_cancelled" or _match_cancelled:
		return
	_match_cancelled = true
	var errors: Array = []
	if data.get("errors") is Array:
		for e in data.get("errors"):
			errors.append(str(e).left(200))
	_show_match_cancelled(str(data.get("who", "")), errors.slice(0, 12))


func _show_match_cancelled(who: String, errors: Array) -> void:
	var own := (who == "host") == NetworkClient.is_host
	var loading_overlay := get_node_or_null("/root/MatchLoadingOverlay")
	if loading_overlay:
		loading_overlay.hide_loading()
	var dialog := AcceptDialog.new()
	dialog.title = "Partida cancelada"
	if who == "version":
		dialog.dialog_text = "Los dos jugadores deben tener la misma versión del juego.\n\n%s" % \
			"\n".join(PackedStringArray(errors))
	else:
		dialog.dialog_text = "%s no cumple las reglas de construcción:\n\n%s" % [
			"Tu mazo" if own else "El mazo del rival", "\n".join(PackedStringArray(errors))]
	dialog.ok_button_text = "Volver al menú"
	dialog.exclusive = true
	dialog.confirmed.connect(_leave_cancelled_match)
	dialog.canceled.connect(_leave_cancelled_match)
	_main.add_child(dialog)
	dialog.popup_centered()


func _leave_cancelled_match() -> void:
	NetworkClient.disconnect_from_relay()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")


func _send_own_deck_and_wait_for_host() -> void:
	"""Modo Remoto conectado: junta el mazo propio (ya cargado como jugador 0
	arriba) y lo manda al Anfitrión como lista plana de IDs (con repetidos
	según cantidad — mismo formato que espera DeckLoader.load_test_deck() del
	otro lado)."""
	if DeckLoader.is_deck_loaded(0):
		_send_deck_to_host()
	else:
		DeckLoader.deck_loaded.connect(_on_own_deck_loaded_for_network, CONNECT_ONE_SHOT)


func _on_own_deck_loaded_for_network(player_id: int, _card_count: int) -> void:
	if player_id != 0:
		return
	_send_deck_to_host()


func _send_deck_to_host() -> void:
	if _match_cancelled:
		return
	var deck_data: Array = DeckLoader.get_deck_data(0)
	# El Anfitrión lo vuelve a validar; validarlo aquí le muestra el motivo al Remoto sin ida y vuelta.
	var errors: Array = DeckValidatorScript.validate(deck_data)
	if not errors.is_empty():
		_cancel_online_match("remote", errors)
		return
	var card_ids: Array = []
	for card in deck_data:
		card_ids.append(str(card.get("id", card.get("uuid", ""))))
	NetworkClient.send_message({"op": "deck", "card_ids": card_ids})
	var _loading_overlay := get_node_or_null("/root/MatchLoadingOverlay")
	if _loading_overlay:
		_loading_overlay.show_loading(_main, "ESPERANDO JUGADOR",
			"Tu mazo ya se envió — esperando a que el Anfitrión termine de preparar la partida...")


func _on_deck_load_failed(player_id: int, error: String) -> void:
	"""Si un mazo falla, no dejar el juego colgado esperando all_decks_ready
	para siempre — avisar y usar un mazo aleatorio de respaldo para ese
	jugador, que sí calza con las cartas realmente disponibles."""
	_main._update_debug("Mazo del jugador %d falló (%s) — usando mazo aleatorio" % [player_id + 1, error])
	push_warning("[Bootstrap] Mazo de jugador %d falló: %s — cargando mazo aleatorio de respaldo" % [player_id, error])
	DeckLoader.load_random_deck(player_id)


# =============================================================================
# INICIO DE PARTIDA
# =============================================================================
func _prepare_game() -> void:
	"""Prepara mazos, jugadores y GameManager (sin mulligan)."""
	print("[Bootstrap] Preparando partida...")
	if DeckLoader.is_deck_loaded(0):
		print("[Bootstrap] Usando mazo del DeckLoader")
		_sync_decks_from_loader()
	if _main.player_deck.size() < 10:
		print("[Bootstrap] Mazo insuficiente (%d cartas), usando mazo de prueba" % _main.player_deck.size())
		_build_test_decks()
	print("[Bootstrap] Mazos listos — jugador: %d, oponente: %d cartas" % [_main.player_deck.size(), _main.opponent_deck.size()])
	if not _main.get_node_or_null("Player1"):
		var p1 = Node.new(); p1.name = "Player1"; _main.add_child(p1)
	if not _main.get_node_or_null("Player2"):
		var p2 = Node.new(); p2.name = "Player2"; _main.add_child(p2)
	GameManager.setup_game(_main.get_node("Player1"), _main.get_node("Player2"))
	_main._zone_manager.shuffle_deck(0)
	_main._zone_manager.shuffle_deck(1)
	CardDatabase.preload_deck_images(_main.player_deck + _main.opponent_deck)


func _setup_oro_inicial() -> void:
	"""Extrae el Oro Inicial de ambos mazos y lo coloca en la Reserva antes del mulligan. Resetea
	GameState.oro_reserva/oro_pagado ANTES: GameState es autoload y sin reset una partida nueva
	sumaba el Oro de la anterior."""
	GameState.reset_oro(0)
	GameState.reset_oro(1)
	for player_id in [0, 1]:
		var deck: Array = _main.player_deck if player_id == 0 else _main.opponent_deck
		var found_idx: int = -1
		for i in range(deck.size()):
			var texto: String = (deck[i].get("habilidad", "") + " " + deck[i].get("nombre", "")).to_lower()
			if "oro inicial" in texto:
				found_idx = i
				break
		var oro_data: Dictionary
		if found_idx != -1:
			oro_data = deck[found_idx]
			deck.remove_at(found_idx)
			print("[Bootstrap] Oro Inicial extraído (J%d): %s — mazo: %d cartas" % [player_id, oro_data.get("nombre", "?"), deck.size()])
		else:
			oro_data = {
				"id": "oro_inicial_fallback_%d" % player_id,
				"nombre": "Oro Inicial",
				"tipo": Constants.CardType.ORO,
				"coste": 0,
				"fuerza": 0,
				"habilidad": "",
				"raza": "",
				"imagen": "/dorso_default.webp",
				"keywords": []
			}
			print("[Bootstrap] Sin Oro Inicial en mazo J%d — carta sintética generada" % player_id)
		if player_id == 0:
			var card = _main._create_card(oro_data)
			card.can_interact = true
			card.scale = Constants.GOLD_CARD_SCALE
			card.base_scale = Constants.GOLD_CARD_SCALE
			_main._connect_card_signals(card)
			_main.player_gold.add_child(card)
			# set_zone(): este camino no pasa por _place_card_as_gold(), y sin current_zone = RESERVA_ORO los
			# efectos que miran la zona (p.ej. Convertir de Capitán O'Brien) rechazaban el Oro Inicial.
			card.set_zone(Constants.Zone.RESERVA_ORO)
			_main.gold_cards.append(card)
			GameState.agregar_oro_reserva(0, 1)
			_main._gold_manager._update_gold_display()
			# El Oro Inicial no pasa por _trigger_enter_play(): sus auras continuas (p.ej. Armería del
			# Guerrero: "Tus Aliados de coste 1 o más ganan 1 de Fuerza") se registran aquí.
			ContinuousEffectManager._register_card_continuous_effects(card)
			_main._gold_manager._register_armeria_opponent_turn_trigger(card)
		else:
			# El Oro Inicial del oponente también es una carta real en OpponentReservaOro, boca arriba (el
			# Oro es información pública, DAR).
			var card = _main._create_card(oro_data, false)
			card.owner_id = 1
			# can_interact = true: se puede inspeccionar como cualquier carta propia (con false,
			# CardInteraction.process() la ignora).
			card.can_interact = true
			card.scale = Constants.GOLD_CARD_SCALE
			card.base_scale = Constants.GOLD_CARD_SCALE
			card.pivot_offset = Vector2(75.0, 105.0)
			_main._connect_card_signals(card)
			_main.opponent_gold.add_child(card)
			card.set_zone(Constants.Zone.RESERVA_ORO)  # ver comentario arriba, mismo bug en el lado rival
			card._refresh_disabled_rotation()
			GameState.agregar_oro_reserva(1, 1)
			ContinuousEffectManager._register_card_continuous_effects(card)
			_main._gold_manager._register_armeria_opponent_turn_trigger(card)
	_main._zone_manager._update_castillo_counts()


func _sync_decks_from_loader() -> void:
	_main.player_deck.clear()
	_main.opponent_deck.clear()
	for card_data in DeckLoader.get_deck_data(0):
		_main.player_deck.append(card_data)
	for card_data in DeckLoader.get_deck_data(1):
		_main.opponent_deck.append(card_data)
	DeckLoader.clear_deck_data(0)
	DeckLoader.clear_deck_data(1)
	print("[Bootstrap] Mazos sincronizados: Jugador=%d, Oponente=%d" % [_main.player_deck.size(), _main.opponent_deck.size()])


func _build_test_decks() -> void:
	print("[Bootstrap] Usando cartas de prueba")
	for i in range(15):
		_main.player_deck.append({
			"id": "oro_%d" % i, "nombre": "Oro",
			"tipo": Constants.CardType.ORO, "coste": 0, "fuerza": 0,
			"habilidad": "", "raza": "", "keywords": []
		})
	var test_allies = [
		{"nombre": "Guerrero Vikingo", "coste": 3, "fuerza": 4, "raza": "Vikingo", "habilidad": "Furia."},
		{"nombre": "Arquero Elfico", "coste": 2, "fuerza": 2, "raza": "Elfo", "habilidad": "Al entrar, haz 1 de daño."},
		{"nombre": "Jinete del Norte", "coste": 4, "fuerza": 5, "raza": "Vikingo", "habilidad": ""},
		{"nombre": "Mago Oscuro", "coste": 3, "fuerza": 2, "raza": "Hechicero", "habilidad": "Al entrar, roba una carta."},
		{"nombre": "Golem de Piedra", "coste": 5, "fuerza": 7, "raza": "Constructo", "habilidad": "Indestructible."},
		{"nombre": "Espadachin Real", "coste": 2, "fuerza": 3, "raza": "Humano", "habilidad": ""},
		{"nombre": "Dragon Menor", "coste": 6, "fuerza": 6, "raza": "Dragon", "habilidad": "Imbloqueable."},
		{"nombre": "Sacerdotisa", "coste": 3, "fuerza": 2, "raza": "Clerigo", "habilidad": "Al entrar, gana 2 vida."},
	]
	for i in range(25):
		var base = test_allies[i % test_allies.size()].duplicate()
		base["id"] = "ally_%d" % i
		base["tipo"] = Constants.CardType.ALIADO
		base["keywords"] = []
		_main.player_deck.append(base)
	for i in range(5):
		_main.player_deck.append({
			"id": "arma_%d" % i, "nombre": "Espada Ancestral",
			"tipo": Constants.CardType.ARMA, "coste": 2, "fuerza": 0,
			"habilidad": "El portador gana +2 Fuerza.", "raza": "", "keywords": []
		})
	for i in range(5):
		_main.player_deck.append({
			"id": "talisman_%d" % i, "nombre": "Bola de Fuego",
			"tipo": Constants.CardType.TALISMAN, "coste": 3, "fuerza": 0,
			"habilidad": "Destruye un Aliado con Fuerza 3 o menos.", "raza": "", "keywords": []
		})
	_main.opponent_deck = _main.player_deck.duplicate(true)
	print("[Bootstrap] Mazos de prueba: %d cartas" % _main.player_deck.size())


# =============================================================================
# DUELO DE DADOS D20 EN 3D
# =============================================================================
func _show_dice_roll() -> void:
	"""Lanza el Duelo de Dados D20 en 3D en tiempo real — al terminar llama _start_mulligan_phase()."""
	if _match_cancelled:
		return
	# En línea el Anfitrión también valida su propio mazo (mismas reglas que el del Remoto).
	if NetworkClient.room_code != "" and NetworkClient.is_host:
		var own_errors: Array = DeckValidatorScript.validate(DeckLoader.get_deck_data(0))
		if not own_errors.is_empty():
			_cancel_online_match("host", own_errors)
			return
	print("[Bootstrap] _show_dice_roll: iniciando duelo D20 en 3D")
	var loading_overlay := get_node_or_null("/root/MatchLoadingOverlay")
	if loading_overlay:
		loading_overlay.hide_loading()
	UIManager.set_phase_text("Sorteo D20")

	var dice_duel = DiceDuel3D.new()
	# En sala online el Anfitrión manda el resultado real de los dados apenas lo decide
	# (result_decided, antes de la animación), y RemoteMirrorController reproduce la misma tirada
	# ("dice_roll").
	if NetworkClient.room_code != "" and NetworkClient.is_host:
		dice_duel.result_decided.connect(func(r1: int, r2: int, _w: int):
			NetworkClient.send_message({"op": "dice_roll", "result1": r1, "result2": r2})
		)
	_main.add_child(dice_duel)

	dice_duel.duel_completed.connect(func(winner_id: int):
		_main._dice_winner = winner_id
		print("[Bootstrap] Duelo D20 3D finalizado. Ganador: Jugador %d. Iniciando juego..." % (winner_id + 1))
		_prepare_game()
		await _main._mulligan_ctrl.start_mulligan_phase()
	)
