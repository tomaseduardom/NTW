extends Node
## EffectController — efectos de cartas sobre el mazo, con validación "en medida de lo posible"
## (DAR, regla general).
## Lo que depende de game_board (GameBoard.gd, layout viejo sin uso) cae a CardManager, que es el
## camino vivo: draw_cards(), mill_cards(), destroy_card(), exile_card(). El resto de los efectos
## vive en ActionModule (TriggerSystem → UniversalCardParser → ActionModule). Antes de agregar un
## efecto aquí, darle el mismo fallback a CardManager, y solo si algo lo va a llamar.

# =============================================================================
# SIGNALS - Efectos
# =============================================================================
signal effect_started(effect_name: String, player_id: int)
signal effect_completed(effect_name: String, player_id: int, result: Dictionary)
signal effect_failed(effect_name: String, player_id: int, reason: String)
signal player_defeated(player_id: int, reason: String)

# =============================================================================
# SIGNALS - Triggers (DAR 7.2, 7.3, 7.4)
# =============================================================================
# Eventos de cartas individuales (para TriggerSystem)
signal on_card_drawn(player_id: int, card: Node)
signal on_card_milled(player_id: int, card: Node, destination: int)
signal on_card_discarded(player_id: int, card: Node)
signal on_card_entered_play(player_id: int, card: Node, zone: int)
signal on_card_left_play(player_id: int, card: Node, from_zone: int)
signal on_card_destroyed(player_id: int, card: Node)
signal on_card_exiled(player_id: int, card: Node)
signal on_card_returned_to_hand(player_id: int, card: Node)
signal on_card_attacks(player_id: int, card: Node)  # DAR 5.3.1 — "cuando ataque"
signal on_card_blocks(player_id: int, card: Node)  # DAR 5.3.2 — "cuando bloqueas"
signal on_card_returned_to_deck(player_id: int, card: Node, to_top: bool)

# =============================================================================
# REFERENCIAS
# =============================================================================
var game_board: Node = null


func _ready() -> void:
	if GameManager:
		GameManager.connect("game_board_ready", _on_game_board_ready)
		if GameManager.game_board:
			game_board = GameManager.game_board
	_build_prevention_registry()


func _on_game_board_ready(board: Node) -> void:
	game_board = board


# =============================================================================
# VALIDACIÓN "EN MEDIDA DE LO POSIBLE"
# =============================================================================
func _validate_board() -> bool:
	"""Verifica que el GameBoard esté disponible. Siempre devuelve false —
	game_board nunca se asigna (era el GameBoard.gd huérfano, eliminado) —
	y cada llamador ya tiene su propio fallback basado en CardManager para
	cuando esto pasa (ver draw_cards()/mill_cards()/etc). No es un error
	real: antes imprimía push_error() cada vez, como si algo hubiera
	fallado, cuando en realidad el fallback se ejecuta correctamente
	siempre — solo generaba ruido confuso en la consola."""
	return game_board != null


# =============================================================================
# 1. ROBAR CARTAS (DAR - Robo)
# =============================================================================
func draw_cards(player_id: int, amount: int) -> Dictionary:
	"""Roba cartas una a una del Castillo
	'En medida de lo posible': roba hasta que el mazo se vacíe
	DAR 2.1: Si intenta robar con mazo vacío, pierde

	Returns: {success: bool, cards_drawn: Array, deck_emptied: bool}
	"""
	var result = {
		"success": true,
		"cards_drawn": [],
		"deck_emptied": false,
		"requested": amount,
		"actual": 0
	}

	if not _validate_board():
		# El GameBoard viejo no está en la escena: usar el camino real del juego en vez de fallar en
		# silencio.
		return await _draw_cards_fallback(player_id, amount)

	emit_signal("effect_started", "draw_cards", player_id)

	for i in range(amount):
		var deck = game_board.get_cards_in_zone(Constants.Zone.CASTILLO, player_id)

		# Verificar mazo vacío ANTES de robar (condición de derrota)
		if deck.is_empty():
			print("[EffectController] Castillo vacío - Jugador %d pierde (DAR 2.1)" % (player_id + 1))
			result.deck_emptied = true
			emit_signal("player_defeated", player_id, "deck_empty")
			if GameManager:
				GameManager.player_loses(player_id, "deck_empty")
			break

		# Robar carta del tope
		var card = deck[0]
		game_board.move_card(card, Constants.Zone.MANO, player_id, true)
		result.cards_drawn.append(card)
		result.actual += 1

		# Emitir trigger para cada carta robada (DAR 7.2)
		emit_signal("on_card_drawn", player_id, card)

		# Pausa visual entre robos
		if i < amount - 1:
			await get_tree().create_timer(0.12).timeout

	print("[EffectController] Jugador %d robó %d/%d cartas" % [
		player_id + 1, result.actual, amount
	])

	emit_signal("effect_completed", "draw_cards", player_id, result)
	return result


func _draw_cards_fallback(player_id: int, amount: int) -> Dictionary:
	"""Fallback para robar cartas cuando no hay GameBoard legacy registrado.
	Usa Main/ZoneManager (el camino que realmente mueve cartas en la escena
	actual) en vez de fallar. Limitación conocida: como Main.draw_card() no
	devuelve el nodo de la carta robada, cards_drawn queda vacío y no se
	emite on_card_drawn por carta — cualquier trigger que dependa de esa
	señal específica no se disparará todavía. El conteo (actual/deck_emptied)
	sí es correcto."""
	var result = {
		"success": true,
		"cards_drawn": [],
		"deck_emptied": false,
		"requested": amount,
		"actual": 0
	}

	var main = get_node_or_null("/root/Main")
	if not main or not main.get("_zone_manager"):
		result.success = false
		emit_signal("effect_failed", "draw_cards", player_id, "no_main")
		return result

	emit_signal("effect_started", "draw_cards", player_id)

	for i in range(amount):
		var drew: bool = await main._zone_manager.draw_card(player_id)
		if not drew:
			result.deck_emptied = true
			break
		result.actual += 1
		if i < amount - 1:
			await get_tree().create_timer(0.12).timeout

	print("[EffectController] (fallback) Jugador %d robó %d/%d cartas" % [
		player_id + 1, result.actual, amount
	])

	emit_signal("effect_completed", "draw_cards", player_id, result)
	return result


# La búsqueda real es ActionModule.search().
# =============================================================================
# 3. BOTAR CARTAS - MILL (DAR Sección 8 - Botar)
# =============================================================================
func mill_cards(player_id: int, amount: int, destination: int = Constants.Zone.CEMENTERIO, log_it: bool = true) -> Dictionary:
	"""Bota cartas del tope del Castillo una a una
	'En medida de lo posible': bota hasta que el mazo se vacíe
	Nota: Botar NO causa derrota, solo robar (DAR 2.1)

	Returns: {success: bool, milled_cards: Array, actual: int}
	"""
	var result = {
		"success": true,
		"milled_cards": [],
		"requested": amount,
		"actual": 0,
		"destination": destination
	}

	if not _validate_board():
		# GameBoard legacy no disponible (docs/audit, hallazgo 2/4) — usar el
		# fallback basado en CardManager en vez de fallar en silencio.
		return await _mill_cards_fallback(player_id, amount, destination, log_it)

	# Validar destino
	if destination != Constants.Zone.CEMENTERIO and destination != Constants.Zone.DESTIERRO:
		destination = Constants.Zone.CEMENTERIO
		result.destination = destination

	emit_signal("effect_started", "mill_cards", player_id)

	var dest_name = Constants.ZONE_NAMES[destination]

	for i in range(amount):
		var deck = game_board.get_cards_in_zone(Constants.Zone.CASTILLO, player_id)

		# 'En medida de lo posible': si no hay más cartas, terminar sin error
		if deck.is_empty():
			print("[EffectController] Castillo vacío, no se pueden botar más cartas")
			break

		var card = deck[0]
		game_board.move_card(card, destination, player_id, true)
		result.milled_cards.append(card)
		result.actual += 1

		# Revelar carta botada (información pública)
		if card.has_method("flip_face_up"):
			card.flip_face_up()

		# Emitir trigger para cada carta botada (DAR 7.3)
		emit_signal("on_card_milled", player_id, card, destination)

		if Constants.VERBOSE_DIAG_LOGS:
			print("[EffectController] Botada: %s -> %s" % [
				card.card_name if card.get("card_name") else "Carta",
				dest_name
			])

		# Pausa visual
		if i < amount - 1:
			await get_tree().create_timer(0.1).timeout

	if log_it:
		print("[EffectController] Jugador %d botó %d/%d cartas al %s" % [
			player_id + 1, result.actual, amount, dest_name
		])

	emit_signal("effect_completed", "mill_cards", player_id, result)
	return result


func _mill_cards_fallback(player_id: int, amount: int, destination: int, log_it: bool = true) -> Dictionary:
	"""Fallback para botar cartas cuando no hay GameBoard legacy registrado.
	Usa CardManager (su deck/cementerio/destierro quedan sincronizados con
	Main por referencia compartida desde sync_from_main()) en vez de fallar
	en silencio. Limitación conocida: el Castillo no tiene nodos de Card
	individuales (solo un contador visual), así que milled_cards se llena
	con los Dictionary de datos crudos (mismo shape que CardManager guarda
	en Cementerio/Destierro, clave "nombre") en vez de nodos Card reales, y
	no se emite on_card_milled por carta — el conteo sí es correcto."""
	var result = {
		"success": true,
		"milled_cards": [],
		"requested": amount,
		"actual": 0,
		"destination": destination
	}

	emit_signal("effect_started", "mill_cards", player_id)

	if destination == Constants.Zone.DESTIERRO:
		var deck: Array = CardManager.get_deck(player_id)
		var exile: Array = CardManager.get_exile(player_id)
		for i in range(amount):
			if deck.is_empty():
				break
			# pop_front() = tope real (ver CardManager.add_to_deck_top()).
			var card_data: Dictionary = deck.pop_front()
			card_data["esta_oculta"] = false
			CardManager.append_to_exile(player_id, card_data)
			result.milled_cards.append(card_data)
			result.actual += 1
		CardManager._emit_exile_changed(player_id)
		CardManager._emit_deck_changed(player_id)
	else:
		var dmg_result: Dictionary = CardManager.mill_cards(player_id, amount)
		result.actual = dmg_result.get("actual", 0)
		result.milled_cards = dmg_result.get("cards", [])

	# Una línea con los nombres. El daño de combate lo resume BattleManager al final (log_it = false).
	if log_it:
		print("[EffectController] Jugador %d bota %d al %s: %s" % [
			player_id + 1, result.actual, Constants.ZONE_NAMES.get(destination, "?"),
			", ".join(result.milled_cards.map(func(c): return str(c.get("nombre", "?")) if c is Dictionary else "?"))
		])

	emit_signal("effect_completed", "mill_cards", player_id, result)
	return result


# Descarte real: ActionModule.discard(). Barajado real:
# CardManager.shuffle_deck()/_zone_manager/GameManager. Entrada al juego:
# GoldManager._trigger_enter_play().
# =============================================================================
# 8. DESTRUIR CARTA (DAR 7.3 - Triggers de destrucción)
# =============================================================================
func destroy_card(player_id: int, card: Node, is_being_destroyed: bool = true, source: Node = null) -> bool:
	"""Destruye una carta y la manda al Cementerio (o al Destierro si fue exhumada; lo respeta
	CardManager.destroy_card()). Emite on_card_left_play y on_card_destroyed.
	is_being_destroyed = false: GoldManager._play_talisman() reusa esta función para mandar un
	Talismán resuelto al Cementerio (mismos contadores y señales); no es una destrucción en
	términos DAR, así que solo cambia el texto del log.
	Devuelve true si se destruyó."""
	if await _try_consume_leave_play_prevention(player_id, card, source):
		return false

	# Guardar zona origen
	var from_zone = card.current_zone if card.get("current_zone") != null else -1

	# Verificar que está en juego
	if from_zone not in Constants.ZONES_IN_PLAY:
		push_warning("[EffectController] Carta no está en juego, no se puede destruir")
		return false

	# Notificar a la carta que deja el juego
	if card.has_method("on_left_play"):
		card.on_left_play()

	# Limpiar keywords temporales y cache (DAR Sección 8)
	KeywordManager.clear_all_for_card(card)

	# Limpiar datos de conversión si estaba convertida
	clear_conversion_on_leave(card)

	# Emitir trigger de salida del juego
	emit_signal("on_card_left_play", player_id, card, from_zone)

	# Mover al Cementerio
	if game_board:
		game_board.move_card(card, Constants.Zone.CEMENTERIO, player_id, true)
	else:
		# GameBoard legacy no disponible (docs/audit, hallazgo 2/4) — CardManager
		# ya respeta la regla de exhumación y mantiene los contadores de UI
		# sincronizados (a diferencia de game_board.move_card(), sí libera el
		# nodo — correcto, porque el Cementerio real solo muestra un contador).
		await CardManager.destroy_card(player_id, card)

	# Emitir trigger de destrucción
	emit_signal("on_card_destroyed", player_id, card)

	var card_name = card.card_name if card.get("card_name") else "Carta"
	if is_being_destroyed:
		print("[EffectController] %s fue destruida" % card_name)
	else:
		print("[EffectController] %s resuelve su efecto y va al Cementerio" % card_name)

	return true


## DAR (Portar): "Si en algún momento un Arma ... queda sin portador válido, esa Arma es enviada al
## Cementerio." Sale del juego al Cementerio de su dueño sin ser Destruida: ni prevención, ni
## Indestructible, ni "cuando sea Destruida" (Sariel, "No puede portar Armas").
func send_to_cemetery_by_rule(card: Node) -> void:
	if not is_instance_valid(card) or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return
	var from_zone = card.current_zone
	var owner_id: int = int(card.owner_id) if card.get("owner_id") != null else 0
	if card.has_method("on_left_play"):
		card.on_left_play()
	KeywordManager.clear_all_for_card(card)
	clear_conversion_on_leave(card)
	emit_signal("on_card_left_play", owner_id, card, from_zone)
	await CardManager.destroy_card(owner_id, card, false)


# =============================================================================
# 9. DESTERRAR CARTA (DAR - Destierro)
# =============================================================================
func exile_card(player_id: int, card: Node, bypass_prevention: bool = false, source: Node = null) -> bool:
	"""Destierra una carta. Emite on_card_left_play (si estaba en juego) y on_card_exiled.
	bypass_prevention: true cuando desterrar es el costo que el propio jugador eligió pagar (p.ej.
	"Puedes Desterrarlo para...", Legión Paladín): la Prevención protege contra el rival, no contra
	tu propio costo.
	Devuelve true si se desterró."""
	if not bypass_prevention and await _try_consume_leave_play_prevention(player_id, card, source):
		return false
	# Indesterrable, Nefandos, dulce canasta: ni un costo propio (bypass_prevention) puede Desterrar lo
	# que no puede ser Desterrado.
	if load("res://scripts/core/effects/mechanics/ProtectionRules.gd").cannot_be_banished(card):
		if get_node_or_null("/root/Main"):
			get_node("/root/Main")._update_debug("%s no puede ser Desterrada" % str(card.get("card_name")))
		return false

	var from_zone = card.current_zone if card.get("current_zone") != null else -1

	# Si estaba en juego, notificar y emitir salida
	if from_zone in Constants.ZONES_IN_PLAY:
		if card.has_method("on_left_play"):
			card.on_left_play()

		# Limpiar keywords temporales y cache (DAR Sección 8)
		KeywordManager.clear_all_for_card(card)

		# Limpiar datos de conversión si estaba convertida
		clear_conversion_on_leave(card)

		emit_signal("on_card_left_play", player_id, card, from_zone)

	# Mover al Destierro
	if game_board:
		game_board.move_card(card, Constants.Zone.DESTIERRO, player_id, true)
	else:
		# GameBoard legacy no disponible (docs/audit, hallazgo 2/4)
		await CardManager.exile_card(player_id, card)

	# Emitir trigger de destierro
	emit_signal("on_card_exiled", player_id, card)

	var card_name = card.card_name if card.get("card_name") else "Carta"
	print("[EffectController] %s fue desterrada" % card_name)

	return true


# =============================================================================
# 11. CONVERTIR TIPO DE CARTA (DAR Sección 8 - Convertir)
# =============================================================================
# clear_conversion_on_leave() (y _converted_cards) queda como punto de enganche:
# destroy_card()/exile_card() la llaman aunque hoy no haga nada. Convertir real:
# GoldManager.convert_ally_to_gold_in_pagado() y los patrones de Convertir.
var _converted_cards: Dictionary = {}


func clear_conversion_on_leave(card: Node) -> void:
	"""Limpia datos de conversión cuando una carta sale del juego"""
	if is_instance_valid(card):
		_converted_cards.erase(card.get_instance_id())


# =============================================================================
# PREVENCIÓN "SALE DEL JUEGO" (DAR - Utilizar Habilidades: Prevenir)
# =============================================================================
# Inmunidad temporal "no pueden salir del juego" para todos los Aliados de un jugador, hasta que
# vuelva a empezar su turno (p.ej. Sherlock Holmes). Es una inmunidad otorgada por otro efecto,
# distinta de una carta de Prevención (offer_prevention()/_prevention_registry).
var _blanket_leave_play_immunity: Dictionary = {0: false, 1: false}


func add_blanket_leave_play_immunity(player_id: int) -> void:
	"""Activa la inmunidad para TODOS los Aliados de player_id hasta que
	vuelva a empezar SU turno (GameManager.turn_started con ese player_id)."""
	if _blanket_leave_play_immunity.get(player_id, false):
		return  # Ya activa — no hace falta una segunda conexión
	_blanket_leave_play_immunity[player_id] = true
	print("[EffectController] Inmunidad de salida del juego activada para J%d (hasta su próximo turno)" % (player_id + 1))
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != player_id:
			return
		_blanket_leave_play_immunity[player_id] = false
		if GameManager.turn_started.is_connected(clear_it):
			GameManager.turn_started.disconnect(clear_it)
		print("[EffectController] Inmunidad de salida del juego terminó para J%d" % (player_id + 1))
	GameManager.turn_started.connect(clear_it)


## Igual que la anterior, pero solo durante el turno en curso (espada de magog: "tus Aliados no
## pueden salir del juego este turno"). {controlador: turn_serial}; vence sola al cambiar el turno.
var _leave_play_immunity_turn: Dictionary = {}


func add_leave_play_immunity_this_turn(player_id: int) -> void:
	_leave_play_immunity_turn[player_id] = GameManager.turn_serial


## Inmunidad temporal "no puede salir del juego" para una carta puntual (p.ej. Garfio Pirata: "el
## portador no puede salir del juego hasta tu próximo turno"). {card_instance_id: true}
var _single_card_leave_play_immunity: Dictionary = {}


func add_single_card_leave_play_immunity(card: Node, player_id: int) -> void:
	"""Activa la inmunidad para ESTA carta hasta que vuelva a empezar el
	turno de player_id (el controlador de la fuente, no necesariamente el
	dueño de 'card' — DAR: la protección la otorga QUIEN controla el
	efecto)."""
	if not is_instance_valid(card):
		return
	var id := card.get_instance_id()
	if _single_card_leave_play_immunity.get(id, false):
		return  # ya activa — no hace falta una segunda conexión
	_single_card_leave_play_immunity[id] = true
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Carta"
	print("[EffectController] Inmunidad de salida del juego activada para %s (hasta el próximo turno de J%d)" % [card_name, player_id + 1])
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != player_id:
			return
		_single_card_leave_play_immunity.erase(id)
		if GameManager.turn_started.is_connected(clear_it):
			GameManager.turn_started.disconnect(clear_it)
	GameManager.turn_started.connect(clear_it)


func _try_consume_leave_play_prevention(player_id: int, card: Node, source: Node = null) -> bool:
	"""Solo previene la salida de Aliados. La inmunidad temporal en bloque
	(blanket, Sherlock Holmes) y la puntual por carta (Garfio Pirata) se
	revisan PRIMERO y no consumen nada — son inmunidades OTORGADAS por otro
	efecto, no cartas de Prevención, así que no pasan por el registro
	reactivo. Si ninguna aplica, ofrece Prevención reactiva real (Legión
	Paladín — ver offer_prevention(), tag 'leave_play')."""
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ALIADO:
		return false
	var ctrl: int = int(card.controller_id) if card.get("controller_id") != null else player_id
	if _blanket_leave_play_immunity.get(player_id, false) \
			or int(_leave_play_immunity_turn.get(ctrl, -1)) == GameManager.turn_serial:
		var card_name0: String = str(card.get("card_name")) if card.get("card_name") != null else "Aliado"
		print("[EffectController] %s no sale del juego (inmunidad temporal activa para J%d)" % [card_name0, player_id + 1])
		var main0 := get_node_or_null("/root/Main")
		if main0:
			main0._update_debug("%s: no puede salir del juego este turno" % card_name0)
		return true
	# Turiel: "no pueda salir del juego este turno" (meta con el turn_serial).
	if _single_card_leave_play_immunity.get(card.get_instance_id(), false) \
			or int(card.get_meta("no_leave_turn", -1)) == GameManager.turn_serial \
			or GameManager.turn_serial <= int(card.get_meta("no_leave_until", -1)):  # Jafet, Jared
		var card_name1: String = str(card.get("card_name")) if card.get("card_name") != null else "Aliado"
		print("[EffectController] %s no sale del juego (inmunidad puntual activa)" % card_name1)
		var main1 := get_node_or_null("/root/Main")
		if main1:
			main1._update_debug("%s: no puede salir del juego este turno" % card_name1)
		return true
	return await offer_prevention(card, source, "leave_play")


# =============================================================================
# PREVENCIÓN REACTIVA (DAR — Utilizar Habilidades: Prevenir)
# =============================================================================
# Registro genérico de cartas de Prevención: un solo punto de entrada que pregunta al jugador en el
# momento en que el efecto va a resolverse
# (docs/plans/2026-09-02-prevention-response-window-design.md).
# Cada entrada: {name, detect: Callable(text) -> bool, effect_tags: Array[String], opponent_only:
# bool, applies: Callable(target) -> bool (Node, Dictionary o null — ver Drácula), is_available:
# Callable(card) -> bool, on_used: Callable(card) (awaitable), zones (opcional: "play", "hand",
# "play_and_hand")}.
# Sin contador de cargas: una carta está disponible si sigue sin usar en su zona. Las que se
# autoconsumen (destierro, conversión) desaparecen al usarse; las "una vez por turno" usan el
# turn_registry.
var _prevention_registry: Array[Dictionary] = []


func _build_prevention_registry() -> void:
	_prevention_registry = [
		{
			# naves de shaggai: "Cuando el portador fuera a salir del juego, puedes Destruir esta Arma para prevenirlo."
			"name": "naves de shaggai",
			"detect": func(text: String) -> bool:
				return "cuando el portador fuera a salir del juego, puedes destruir esta arma para prevenirlo" in text.to_lower(),
			"effect_tags": ["destroy", "exile", "leave_play"],
			"opponent_only": false,
			"applies": Callable(),
			"is_available": func(card: Node) -> bool:
				return is_instance_valid(_last_prevention_target) and card.get("wielder") == _last_prevention_target,
			"on_used": func(card: Node) -> bool:
				await ActionModule.destroy([card], card, false, true)
				return true,
		},
		{
			# mesa del te: "Hasta dos veces por turno, cuando un Aliado que controles fuera a ser afectado por un
			# efecto oponente, en vez de eso puedes subirlo a tu mano y Robar una carta."
			"name": "mesa del te",
			"detect": func(text: String) -> bool:
				return "fuera a ser afectado por un efecto oponente, en vez de eso puedes subirlo a tu mano y robar una carta" in text.to_lower(),
			"effect_tags": ["destroy", "exile", "leave_play", "debuff", "strength_change", "silence", "control", "convert", "cancel_attack"],
			"opponent_only": true,
			"applies": func(target) -> bool:
				return target is Node and is_instance_valid(target) and target.get("card_type") == Constants.CardType.ALIADO,
			"is_available": func(card: Node) -> bool:
				return RuleState.count("mesa_te:%d" % card.get_instance_id(), 0) < 2,
			"on_used": func(card: Node) -> bool:
				RuleState.add("mesa_te:%d" % card.get_instance_id(), 0)
				var target: Node = _last_prevention_target
				var ctrl: int = int(card.controller_id) if card.get("controller_id") != null else 0
				var main_m := get_node_or_null("/root/Main")
				if main_m and is_instance_valid(target):
					await load("res://scripts/core/effects/mechanics/EnterPatterns.gd").bounce_to_owner_hand(main_m, target, card)
				await ActionModule.draw(ctrl, 1, "mesa del te", true)
				return true,
		},
		{
			# Chestnut Hill: "...fuera a salir del juego por un efecto oponente, hasta dos veces por turno, puedes lanzar
			# un dado de seis caras. Si sale par, prevén que esa carta salga del juego. Si sale impar, tú oponente
			# Destierra las primeras dos cartas de su Castillo."
			"name": "Chestnut Hill",
			"detect": func(text: String) -> bool:
				return "fuera a salir del juego por un efecto oponente, hasta dos veces por turno, puedes lanzar un dado" in text.to_lower(),
			"effect_tags": ["destroy", "exile", "leave_play"],
			"opponent_only": true,
			"applies": Callable(),
			"is_available": func(card: Node) -> bool:
				return RuleState.count("chestnut:%d" % card.get_instance_id(), 0) < 2,
			"on_used": func(card: Node) -> bool:
				RuleState.add("chestnut:%d" % card.get_instance_id(), 0)
				var ctrl: int = int(card.controller_id) if card.get("controller_id") != null else 0
				var roll: int = randi() % 6 + 1
				var main_c := get_node_or_null("/root/Main")
				if main_c:
					main_c._update_debug("Chestnut Hill: sale %d" % roll)
				if roll % 2 == 0:
					return true
				await ActionModule.mill(1 - ctrl, 2, true, "Chestnut Hill", true)
				return false,
		},
		{
			# Romualdito (Oro): "Puedes convertirlo en un Oro sin habilidad para prevenir que un Aliado sea Destruido,
			# cambie de controlador o sea convertido, por un efecto oponente." (convertido: ConvertPatterns.conversion_prevented)
			"name": "Romualdito",
			"detect": func(text: String) -> bool:
				return "convertirlo en un oro sin habilidad para prevenir que un aliado sea destruido, cambie de controlador" in text.to_lower(),
			"effect_tags": ["destroy", "control", "convert"],
			"opponent_only": true,
			"applies": func(target) -> bool:
				return target == null or (target is Node and target.get("card_type") == Constants.CardType.ALIADO),
			"is_available": func(card: Node) -> bool: return not card.is_converted,
			"on_used": func(card: Node) -> bool:
				await load("res://scripts/core/effects/mechanics/EnterPatterns.gd")._blank(card, card)
				return true,
		},
		{
			# Polvo de Hadas (Oro): "Puedes convertirlo en un Oro sin habilidad para prevenir que Botes o Destierres
			# cartas del tope de tu Castillo por un efecto oponente." (ActionModule.mill, etiqueta "mill").
			"name": "Polvo de Hadas",
			"detect": func(text: String) -> bool:
				return "convertirlo en un oro sin habilidad para prevenir que botes o destierres cartas del tope de tu castillo" in text.to_lower(),
			"effect_tags": ["mill"],
			"opponent_only": false,
			"applies": Callable(),
			"is_available": func(card: Node) -> bool: return not card.is_converted,
			"on_used": func(card: Node) -> bool:
				await load("res://scripts/core/effects/mechanics/EnterPatterns.gd")._blank(card, card)
				return true,
		},
		{
			"name": "Estaca",
			"detect": func(text: String) -> bool:
				return "desterrarla para prevenir que una carta sea afectada por un efecto oponente" in text.to_lower(),
			# Estaca incluye "leave_play": su alcance es "cualquier efecto oponente que afecte a una carta",
			# también barajar de vuelta al mazo. No pregunta dos veces por un Destruir/Desterrar normal:
			# ActionDestroy/ActionBanish ya preguntan en su paso "destroy"/"exile" y después llaman a
			# destroy_card()/exile_card() sin 'source', así que opponent_only no se confirma ahí.
			# return_to_deck() sí pasa 'source' real, y ahí Estaca se ofrece.
			"effect_tags": ["destroy", "exile", "leave_play", "debuff", "strength_change", "silence"],
			"opponent_only": true,
			"applies": Callable(),
			"is_available": func(_card: Node) -> bool: return true,
			"on_used": func(card: Node) -> bool:
				var owner_id: int = card.owner_id if card.get("owner_id") != null else 0
				var wielder = card.get_parent()
				if wielder and wielder.get("equipped_weapons") is Array:
					wielder.equipped_weapons.erase(card)
				await exile_card(owner_id, card, true)
				return true,
		},
		{
			"name": "Legión Paladín",
			"detect": func(text: String) -> bool:
				return "desterrarlo para prevenir que un aliado que controles salga del juego" in text.to_lower(),
			"effect_tags": ["leave_play"],
			"opponent_only": false,
			# Su texto es específico de "un Aliado": el filtro vive en el registro para que aplique desde
			# cualquier llamada a offer_prevention().
			"applies": func(target) -> bool:
				if target == null:
					return true
				var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
				return tipo == null or int(tipo) == Constants.CardType.ALIADO,
			"is_available": func(_card: Node) -> bool: return true,
			"on_used": func(card: Node) -> bool:
				var owner_id: int = card.owner_id if card.get("owner_id") != null else 0
				await exile_card(owner_id, card, true)
				return true,
		},
		{
			"name": "Drácula",
			"detect": func(text: String) -> bool:
				return "convertirlo en un oro sin habilidad para prevenir que una habilidad sea cancelada" in text.to_lower(),
			# opponent_only = false: el texto de Drácula no dice "oponente" ("prevenir que una habilidad sea
			# cancelada o un Aliado de coste 1 sea Anulado"), a diferencia de Estaca.
			"effect_tags": ["cancel", "annul"],
			"opponent_only": false,
			# "un Aliado de coste 1 sea Anulado" — solo cubre coste 1 exacto.
			# 'target' puede ser Node (annul directo en juego) o Dictionary
			# (annul en la pila, LinkedEffectRegistry — card_data crudo) o
			# null (tag 'cancel', que no tiene target de carta puntual).
			"applies": func(target) -> bool:
				if target == null:
					return true  # tag "cancel" — no hay carta puntual con coste que revisar
				var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
				if tipo != null and int(tipo) != Constants.CardType.ALIADO:
					return false
				var cost = target.get("coste") if target is Dictionary else target.get("card_cost")
				return cost == null or int(cost) == 1,
			"is_available": func(card: Node) -> bool: return not card.is_converted,
			"on_used": func(card: Node) -> bool:
				card.is_converted = true
				if card.has_method("play_conversion_animation"):
					card.play_conversion_animation(true)
				await KeywordManager.silence_card(card, card, "permanent")
				var main := get_node_or_null("/root/Main")
				if main:
					# Si la carta convertida estaba en una línea de combate, trasladarla limpiamente a la Reserva de Oro
					var zone = card.get("current_zone")
					if zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
						var owner_id: int = card.owner_id if card.get("owner_id") != null else 0
						var parent = card.get_parent()
						if parent:
							parent.remove_child(card)
						var gold_cont = main.player_gold if owner_id == 0 else main.opponent_gold
						if gold_cont:
							gold_cont.add_child(card)
							card.set_zone(Constants.Zone.RESERVA_ORO)
							card.scale = Constants.GOLD_CARD_SCALE
							card.base_scale = Constants.GOLD_CARD_SCALE
							GameState.agregar_oro_reserva(owner_id, 1)
							if owner_id == 0:
								main.gold_cards.append(card)
							if main._gold_manager and main._gold_manager.has_method("update_gold_containers_spacing"):
								main._gold_manager.update_gold_containers_spacing()
					if CombatLog and CombatLog.has_method("log_action"):
						CombatLog.log_action("¡%s se convirtió en un Oro sin habilidad y previno el efecto!" % str(card.card_name))
					if main.has_method("_update_debug"):
						main._update_debug("¡%s previno la cancelación/anulación!" % str(card.card_name))
				return true,
		},
		{
			"name": "Ángel Redentor",
			"detect": func(text: String) -> bool:
				return "puedes prevenir que una carta sea anulada" in text.to_lower(),
			"effect_tags": ["annul", "cancel"],
			"opponent_only": false,
			"applies": Callable(),
			"is_available": func(card: Node) -> bool:
				return not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial),
			"on_used": func(card: Node) -> bool:
				UniversalCardParser.turn_registry.register(str(card.get_instance_id()), 0, GameManager.turn_serial)
				return true,
		},
		{
			# Almirante Akari: "Una vez por turno, puedes Barajar una carta de tu mano o que controles para
			# Anular una carta de coste 2 o menos o prevenir que un Aliado sea afectado por un efecto
			# oponente". Reactiva, sin botón: dos disparadores con un solo candado por turno y un solo costo
			# (barajar una carta propia), pagado al confirmar cuál usa. La mitad Prevenir va aquí; la de
			# Anular, en offer_counter_annul(). Comparten _pay_akari_shuffle_cost().
			"name": "Almirante Akari",
			"detect": func(text: String) -> bool:
				return "prevenir que un aliado sea afectado por un efecto oponente" in text.to_lower(),
			"effect_tags": ["destroy", "exile", "debuff", "strength_change", "silence"],
			"opponent_only": true,
			"applies": func(target) -> bool:
				if target == null:
					return true
				var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
				return tipo == null or int(tipo) == Constants.CardType.ALIADO,
			"is_available": func(card: Node) -> bool:
				return not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial),
			"on_used": func(card: Node) -> bool:
				var paid: bool = await _pay_akari_shuffle_cost(card)
				if not paid:
					return false
				UniversalCardParser.turn_registry.register(str(card.get_instance_id()), 0, GameManager.turn_serial)
				return true,
		},
		{
			# Padre Dagón: "...o prevén que uno o más Aliados sean afectados por un efecto oponente" —
			# comparte el "una vez por turno" con su habilidad activada (DagonPatterns.gd). Un uso cubre a
			# todos tus Aliados afectados por ese mismo efecto (_dagon_shield, ver offer_prevention()).
			"name": "Padre Dagón",
			"detect": func(text: String) -> bool:
				return DagonScript.PREVENTION_TEXT in text.to_lower(),
			"effect_tags": ["destroy", "exile", "debuff", "strength_change", "silence", "control"],
			"opponent_only": true,
			"applies": func(target) -> bool:
				if target == null:
					return true
				var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
				return tipo == null or int(tipo) == Constants.CardType.ALIADO,
			"is_available": func(card: Node) -> bool:
				return not KeywordManager.is_silenced(card) and not DagonScript.used_this_turn(card),
			"on_used": func(card: Node) -> bool:
				DagonScript.mark_used(card)
				var ctx: Dictionary = EffectContextScript.current()
				_dagon_shield = {"owner": card.controller_id if card.get("controller_id") != null else 0,
					"token": int(ctx.get("token", -1)), "source": _last_prevention_source_id,
					"ms": Time.get_ticks_msec()}
				var main_d := get_node_or_null("/root/Main")
				if main_d:
					main_d._update_debug("Padre Dagón: tus Aliados no son afectados por ese efecto")
				return true,
		},
		{
			# Armadura Dorada: "...para prevenir que tus Aliados sean afectados" — un uso cubre a todos los
			# afectados por ese efecto (mismo escudo que Padre Dagón).
			"name": "Armadura Dorada",
			"detect": func(text: String) -> bool:
				return PreventionCosts.ARMADURA_TEXT in text.to_lower(),
			"zones": "play_and_hand",
			"effect_tags": ["destroy", "exile", "debuff", "strength_change", "silence", "control"],
			"opponent_only": true,
			"applies": func(target) -> bool:
				if target == null:
					return true
				var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
				return tipo == null or int(tipo) == Constants.CardType.ALIADO,
			"is_available": func(card: Node) -> bool:
				return PreventionCosts.can_pay_one(card) if PreventionCosts.in_hand(card) else not KeywordManager.is_silenced(card),
			"on_used": func(card: Node) -> bool:
				var owner_a: int = card.owner_id if card.get("owner_id") != null else 0
				if not await PreventionCosts.pay_prevention_cost(card):
					return false
				var ctx: Dictionary = EffectContextScript.current()
				_dagon_shield = {"owner": owner_a, "token": int(ctx.get("token", -1)),
					"source": _last_prevention_source_id, "ms": Time.get_ticks_msec()}
				return true,
		},
		{
			# Armadura Dorada: "...o un Aliado Anulado".
			"name": "Armadura Dorada",
			"detect": func(text: String) -> bool:
				return PreventionCosts.ARMADURA_TEXT in text.to_lower(),
			"zones": "play_and_hand",
			"effect_tags": ["annul"],
			"opponent_only": false,
			"applies": func(target) -> bool:
				if target == null:
					return false
				var tipo = target.get("tipo") if target is Dictionary else target.get("card_type")
				return tipo != null and int(tipo) == Constants.CardType.ALIADO,
			"is_available": func(card: Node) -> bool:
				return PreventionCosts.can_pay_one(card) if PreventionCosts.in_hand(card) else not KeywordManager.is_silenced(card),
			"on_used": func(card: Node) -> bool:
				return await PreventionCosts.pay_prevention_cost(card),
		},
		{
			# ngenechen: "Una vez por turno, puedes Barajar carta de tu mano para prevenir un efecto."
			"name": "ngenechen",
			"detect": func(text: String) -> bool:
				var t := text.to_lower()
				return "barajar carta de tu mano para prevenir un efecto" in t \
					or "barajar una carta de tu mano para prevenir un efecto" in t,
			"effect_tags": ["destroy", "exile", "debuff", "strength_change", "silence", "control"],
			"opponent_only": true,
			"applies": Callable(),
			"is_available": func(card: Node) -> bool:
				var pid: int = card.controller_id if card.get("controller_id") != null else 0
				return not KeywordManager.is_silenced(card) \
					and not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial) \
					and not PlayerSideScript.hand_cards(get_node("/root/Main"), pid).is_empty(),
			"on_used": func(card: Node) -> bool:
				if not await PreventionCosts.shuffle_one_from_hand_cost(card):
					return false
				UniversalCardParser.turn_registry.register(str(card.get_instance_id()), 0, GameManager.turn_serial)
				return true,
		},
		{
			# Dos de Cada Uno: "hasta dos cartas de coste 1 o menos de un mismo tipo" — la segunda del mismo
			# tipo afectada por ese efecto también queda cubierta.
			"name": "Dos de Cada Uno",
			"detect": func(text: String) -> bool:
				return PreventionCosts.DOS_DE_CADA_UNO_TEXT in text.to_lower(),
			"zones": "hand",
			"effect_tags": ["destroy", "exile", "leave_play", "debuff", "strength_change", "silence", "control", "convert", "cancel_attack"],
			"opponent_only": true,
			"applies": func(target) -> bool:
				return target is Node and ContinuousEffectManager.cost_at_most(target, 1),
			"is_available": func(card: Node) -> bool:
				return PreventionCosts.can_pay_one(card),
			"on_used": func(card: Node) -> bool:
				var owner_d: int = card.owner_id if card.get("owner_id") != null else 0
				var first: Node = _last_prevention_target
				if not await PreventionCosts.pay_prevention_cost(card):
					return false
				var ctx: Dictionary = EffectContextScript.current()
				_extra_shield = {"owner": owner_d, "token": int(ctx.get("token", -1)),
					"source": _last_prevention_source_id, "ms": Time.get_ticks_msec(), "left": 1,
					"first": first, "filter": PreventionCosts.same_type_low_cost_filter(first)}
				return true,
		},
		# Al final, para que las entradas de arriba tengan prioridad (CompiledPrevention.spec() las
		# excluye): "Puedes <coste> para prevenir que un Tótem sea Anulado o su habilidad cancelada"
		# (Ángel Gadreel, Serafín, wendy, orden del águila negra).
		_compiled_prevention_entry("annul", ["annul", "cancel"], false),
		# "...para prevenir que una carta / uno o más Oros sean afectados por un efecto oponente"
		# (lucifer, ciudad subterranea).
		_compiled_prevention_entry("affect", ["destroy", "exile", "leave_play", "debuff", "strength_change", "silence", "control"], true),
	]


## Objetivo del ofrecimiento en curso (offer_prevention_for_player()): las entradas de
## CompiledPrevention lo necesitan junto con la carta, que 'applies' no recibe.
var _last_applies_arg = null


func _compiled_prevention_entry(kind: String, tags: Array, opponent_only: bool) -> Dictionary:
	var spec_of := func(card: Node) -> Dictionary:
		var sp: Dictionary = CompiledPrevention.spec(str(card.get("card_ability")), _prevention_registry)
		return sp if sp.get("kind", "") == kind else {}
	return {
		"name": "Prevención compilada (%s)" % kind,
		"detect": func(text: String) -> bool:
			return CompiledPrevention.spec(text, _prevention_registry).get("kind", "") == kind,
		"zones": "play_and_hand",
		"effect_tags": tags,
		"opponent_only": opponent_only,
		"applies": Callable(),
		"is_available": func(card: Node) -> bool:
			var sp: Dictionary = spec_of.call(card)
			return not sp.is_empty() and CompiledPrevention.applies(sp, _last_applies_arg, card) \
				and CompiledPrevention.is_available(sp, card),
		"on_used": func(card: Node) -> bool:
			return await CompiledPrevention.pay(spec_of.call(card), card),
	}


## Dos de Cada Uno: {owner, token, source, ms, left, first, filter}.
var _extra_shield: Dictionary = {}
var _last_prevention_target: Node = null


func _extra_shield_covers(affected_card: Node, effect_source: Node) -> bool:
	if _extra_shield.is_empty() or int(_extra_shield.left) <= 0 or affected_card == _extra_shield.first:
		return false
	var owner_id: int = affected_card.controller_id if affected_card.get("controller_id") != null else 0
	if owner_id != int(_extra_shield.owner) or not _extra_shield.filter.call(affected_card):
		return false
	var source_id: int = effect_source.get_instance_id() if is_instance_valid(effect_source) else 0
	if source_id != int(_extra_shield.source):
		return false
	var token: int = int(EffectContextScript.current().get("token", -1))
	var same: bool = token == int(_extra_shield.token) if token >= 0 else Time.get_ticks_msec() - int(_extra_shield.ms) <= 3000
	if same:
		_extra_shield.left = int(_extra_shield.left) - 1
	return same


## Padre Dagón: el efecto oponente del que ya protegió a tus Aliados.
var _dagon_shield: Dictionary = {}


var _last_prevention_source_id: int = 0


func _dagon_shield_covers(affected_card: Node, effect_source: Node) -> bool:
	if _dagon_shield.is_empty() or affected_card.get("card_type") != Constants.CardType.ALIADO:
		return false
	var owner_id: int = affected_card.controller_id if affected_card.get("controller_id") != null else 0
	if owner_id != int(_dagon_shield.owner):
		return false
	var source_id: int = effect_source.get_instance_id() if is_instance_valid(effect_source) else 0
	if source_id != int(_dagon_shield.source):
		return false
	var token: int = int(EffectContextScript.current().get("token", -1))
	if token >= 0:
		return token == int(_dagon_shield.token)
	# Sin contexto de efecto: el mismo lote (mismo origen, pocos segundos).
	return Time.get_ticks_msec() - int(_dagon_shield.ms) <= 3000


## Costo compartido de Almirante Akari (barajar 1 carta propia, de la mano o
## en juego) — pagado solo al confirmar cuál de sus 2 respuestas usa
## (Prevenir u offer_counter_annul()). Returns false si el jugador canceló
## la selección (no se paga nada, la respuesta de Akari se aborta entera).
func _pay_akari_shuffle_cost(source_card: Node) -> bool:
	var main := get_node_or_null("/root/Main")
	if not main:
		return false
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	var cost_candidates: Array = []
	if main.player_hand:
		for c in main.player_hand.cards:
			cost_candidates.append(c)
	for field in [main.player_field, main.player_linea_ataque, main.player_linea_apoyo]:
		if field:
			cost_candidates.append_array(field.get_children())
	if cost_candidates.is_empty():
		main._update_debug("Almirante Akari: no tienes ninguna carta en tu mano o en juego para Barajar")
		return false

	if not main._card_interaction:
		return false
	# Click directo sobre la mano/campo, sin modal de lista.
	var cost_filter := func(c: Node) -> bool: return c in cost_candidates
	var cost_node: Node = await main._card_interaction.await_target(
		"Almirante Akari: elige una carta de tu mano o que controles para Barajar (costo)", cost_filter)
	if not cost_node or not is_instance_valid(cost_node):
		return false

	if main.player_hand and main.player_hand.cards.has(cost_node):
		var cost_data: Dictionary = cost_node.card_data.duplicate()
		main.player_hand.remove_card(cost_node, true)
		CardManager.get_deck(owner_id).append(cost_data)
	else:
		var cost_owner: int = cost_node.controller_id if cost_node.get("controller_id") != null else owner_id
		await ActionModule.return_to_deck(cost_node, cost_owner, true, source_card)
	CardManager.shuffle_deck(owner_id)
	return true


## Mitad "Anular" de Almirante Akari — disparador DISTINTO al registro de
## arriba (reacciona a "tu oponente juega una carta", no a "un efecto
## oponente afecta a un Aliado"). Llamar justo después de que 'played_card'
## termine de entrar en juego, del lado de QUIEN LA JUGÓ (ver GoldManager.
## _trigger_enter_play()/EasyBotController._play_ally()) — comprueba si el
## RIVAL de quien jugó controla un Akari disponible y la carta jugada cuesta
## 2 o menos; si el jugador confirma, paga el mismo costo compartido
## (_pay_akari_shuffle_cost) y Anula (destruye) la carta recién jugada.
func offer_counter_annul(played_card) -> void:  # sin tipo: puede llegar ya liberada
	if not is_instance_valid(played_card):
		return
	var played_owner: int = played_card.controller_id if played_card.get("controller_id") != null else 0
	var defender_id: int = 1 - played_owner
	if defender_id != 0:
		return  # el bot no responde todavía
	var cost = played_card.get("card_cost")
	if cost == null or int(cost) > 2:
		return

	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
		main.player_gold, main.player_oro_pagado]
	var akari: Node = null
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			var ability_text: String = str(card.card_ability) if card.get("card_ability") != null else ""
			if "anular una carta de coste 2 o menos" in ability_text.to_lower() \
					and not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial):
				akari = card
				break
		if akari:
			break
	if not akari:
		return

	var use_it: bool = await SelectionManager.await_two_choice(
		main, "¿Usar Almirante Akari para Anular a %s?" % str(played_card.get("card_name")), "Sí", "No")
	if not use_it:
		return
	var paid: bool = await _pay_akari_shuffle_cost(akari)
	if not paid:
		return
	UniversalCardParser.turn_registry.register(str(akari.get_instance_id()), 0, GameManager.turn_serial)
	if not is_instance_valid(played_card):
		return
	await ActionModule.destroy([played_card], akari, true, true)


## flechar xoon: "Una vez por turno, puedes subir una carta que controles a la mano de su dueño para
## Anular un Talismán o Tótem de coste 2 o menos". Mismo mecanismo que offer_counter_annul()
## (Almirante Akari): "Anular X de coste N" se implementa como "cuando esa carta termina de
## entrar/resolver, puedes Destruirla". Llamar desde el mismo punto que offer_counter_annul(), del
## lado de quien la jugó.
func offer_flechar_xoon_annul(played_card) -> void:  # sin tipo: puede llegar ya liberada
	if not is_instance_valid(played_card):
		return
	var played_type = played_card.get("card_type")
	if played_type != Constants.CardType.TALISMAN and played_type != Constants.CardType.TOTEM:
		return
	var played_owner: int = played_card.controller_id if played_card.get("controller_id") != null else 0
	var defender_id: int = 1 - played_owner
	if defender_id != 0:
		return  # el bot no responde todavía
	var cost = played_card.get("card_cost")
	if cost == null or int(cost) > 2:
		return

	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo]
	var xoon: Node = null
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			var ability_text: String = str(card.card_ability) if card.get("card_ability") != null else ""
			if "para anular un talism" in ability_text.to_lower() \
					and not UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial):
				xoon = card
				break
		if xoon:
			break
	if not xoon:
		return

	var use_it: bool = await SelectionManager.await_two_choice(
		main, "¿Usar %s para Anular a %s?" % [str(xoon.get("card_name")), str(played_card.get("card_name"))], "Sí", "No")
	if not use_it:
		return

	# Costo: subir una carta que controles a la mano de su dueño (mismo
	# criterio de picker que _pay_akari_shuffle_cost(), pero el destino es la
	# MANO, no el Mazo — "subir a la mano" es literal, no "Barajar").
	if not main._card_interaction:
		return
	var own_cards: Array = []
	for field in fields:
		if field:
			own_cards.append_array(field.get_children())
	if own_cards.is_empty():
		main._update_debug("%s: no controlas ninguna carta para subir a la mano" % str(xoon.get("card_name")))
		return
	var cost_filter := func(c: Node) -> bool: return c in own_cards
	var cost_node: Node = await main._card_interaction.await_target(
		"Elige una carta que controles para subir a la mano de su dueño (costo)", cost_filter)
	if not cost_node or not is_instance_valid(cost_node):
		return

	UniversalCardParser.turn_registry.register(str(xoon.get_instance_id()), 0, GameManager.turn_serial)
	var owner_id: int = cost_node.get("owner_id") if cost_node.get("owner_id") != null else 0
	var target_hand = main.player_hand if owner_id == 0 else null
	if target_hand and cost_node.get("card_data") != null:
		var data: Dictionary = cost_node.card_data.duplicate()
		var old_parent := cost_node.get_parent()
		if old_parent:
			old_parent.remove_child(cost_node)
		cost_node.queue_free()
		var new_node = main._create_card(data, false)
		target_hand.add_card(new_node)
		main._connect_card_signals(new_node)
	else:
		# Dueño es el rival (bot/remoto) — su mano real vive en _opponent_fan
		# (mismo camino que hangar de la ciudadela, arquitectura.md §12.8),
		# no en un 'opponent_hand' que no existe.
		if cost_node.get("card_data") != null and main._opponent_fan and main.has_method("_create_card"):
			var data2: Dictionary = cost_node.card_data.duplicate()
			var old_parent2 := cost_node.get_parent()
			if old_parent2:
				old_parent2.remove_child(cost_node)
			cost_node.queue_free()
			var opp_node = main._create_card(data2, false)
			main._opponent_fan.add_card(opp_node)

	if not is_instance_valid(played_card):
		return
	await ActionModule.destroy([played_card], xoon, true, true)


## Versión "por player_id" — algunos choke points (LinkedEffectRegistry,
## que opera sobre OBJETOS DE LA PILA de ActionPipeline, card_data
## Dictionary, no un Aliado ya en juego) no tienen un Node afectado real
## para leer su controller_id. 'applies_arg' se le pasa tal cual a cada
## entry.applies() — puede ser un Node, un Dictionary, o null.
func offer_prevention_for_player(target_owner_id: int, effect_source: Node, effect_tag: String, applies_arg = null) -> bool:
	var main := get_node_or_null("/root/Main")
	if not main:
		return false

	var source_owner: int = -2
	if effect_source and is_instance_valid(effect_source):
		source_owner = effect_source.controller_id if effect_source.get("controller_id") != null else -2

	var fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
		main.player_gold, main.player_oro_pagado] if target_owner_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo,
			main.opponent_gold, main.opponent_oro_pagado]

	# Cartas en juego (y Armas equipadas) y, para las entradas cuyo "zones" incluye la mano, las de la
	# mano.
	var pool: Array = []  # [carta, desde_la_mano]
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			pool.append([card, false])
			var weapons = card.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and w.get_parent() != field:
						pool.append([w, false])
	for card in PlayerSideScript.hand_cards(main, target_owner_id):
		if is_instance_valid(card):
			pool.append([card, true])

	var candidates: Array = []  # [{entry, card}]
	_last_applies_arg = applies_arg
	for item in pool:
		var card: Node = item[0]
		var from_hand: bool = item[1]
		if not from_hand:
			var card_controller: int = card.controller_id if card.get("controller_id") != null else -1
			if card_controller != target_owner_id:
				continue
		var ability_text: String = str(card.card_ability) if card.get("card_ability") != null else ""
		if ability_text.is_empty():
			continue
		for entry in _prevention_registry:
			var zones: String = str(entry.get("zones", "play"))
			if from_hand and zones == "play":
				continue
			if not from_hand and zones == "hand":
				continue
			if not (effect_tag in entry.effect_tags):
				continue
			if entry.opponent_only and source_owner != 1 - target_owner_id:
				continue
			if not entry.detect.call(ability_text):
				continue
			if entry.applies.is_valid() and not entry.applies.call(applies_arg):
				continue
			if not entry.is_available.call(card):
				continue
			candidates.append({"entry": entry, "card": card})

	if candidates.is_empty():
		return false
	# Una sola respuesta por efecto (DAR): aunque tengas 3 Estacas, contra un mismo efecto previenes
	# con una; las demás cartas quedan afectadas.
	var effect_ctx: Dictionary = EffectContextScript.current()
	if not effect_ctx.is_empty() and target_owner_id in effect_ctx.get("prevented_by", []):
		return false
	var prevented: bool = await _offer_prevention_choice(target_owner_id, candidates)
	if prevented and not effect_ctx.is_empty():
		var by: Array = effect_ctx.get("prevented_by", [])
		by.append(target_owner_id)
		effect_ctx["prevented_by"] = by
	return prevented


func _offer_prevention_choice(target_owner_id: int, candidates: Array) -> bool:
	# Remoto: elige él, por red.
	if PlayerSideScript.is_remote(target_owner_id):
		var main_r := get_node_or_null("/root/Main")
		var options: Array = ["Pasar"]
		for c in candidates:
			options.append("Usar %s" % str(c.card.get("card_name")))
		var idx: int = await SelectionManager.await_choice(main_r, "¿Deseas prevenir este efecto?", options, target_owner_id)
		if idx <= 0 or idx > candidates.size():
			return false
		var remote_chosen: Dictionary = candidates[idx - 1]
		return await remote_chosen.entry.on_used.call(remote_chosen.card)
	if target_owner_id != 0:
		# Bot: decide solo, al azar entre usar una candidata o ninguna (mismo criterio simple que
		# EasyBotController).
		if randf() < 0.5:
			return false
		var bot_chosen: Dictionary = candidates[randi() % candidates.size()]
		return await bot_chosen.entry.on_used.call(bot_chosen.card)

	# Mismo panel que la ventana genérica de respuesta (título, timer, "Pasar" de
	# ResponseWindowHandler), para que responder se vea igual en todo el juego. No pasa por
	# ActionPipeline: es una pregunta puntual con N candidatas, no un objeto de pila anulable.
	var chosen: Dictionary = await _ask_prevention_panel(candidates)
	if chosen.is_empty():
		return false

	return await chosen.entry.on_used.call(chosen.card)


func _ask_prevention_panel(candidates: Array) -> Dictionary:
	"""Panel de "ventana de respuesta" para Prevención — mismo estilo visual
	que ResponseWindowHandler._on_step_d_waiting() (título, tamaño, timer de
	5 segundos, "Pasar" clickeable desde el instante 0), pero construido aquí
	directo porque EffectController no tiene una referencia al
	CardInspectionLayer/ResponseWindowHandler del humano (son módulos de UI
	separados, ver arquitectura). Un botón por candidata + "Pasar".
	Returns: {} si pasó o venció el tiempo, {entry, card} si usó una."""
	var main := get_node_or_null("/root/Main")
	if not main:
		return {}

	var layer := CanvasLayer.new()
	layer.layer = 90
	main.add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchor(SIDE_LEFT, 0.5)
	panel.set_anchor(SIDE_TOP, 0.0)
	panel.set_anchor(SIDE_RIGHT, 0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.0)
	panel.set_offset(SIDE_LEFT, -210)
	panel.set_offset(SIDE_TOP, 8)
	panel.set_offset(SIDE_RIGHT, 210)
	panel.set_offset(SIDE_BOTTOM, 88)
	layer.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Ventana de Respuesta"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)
	var status_lbl := Label.new()
	if candidates.size() == 1:
		var single_name: String = str(candidates[0].card.card_name) if (candidates[0].card and "card_name" in candidates[0].card and not str(candidates[0].card.card_name).is_empty()) else str(candidates[0].entry.name)
		status_lbl.text = "¿Usar %s para prevenir? (5s)" % single_name
	else:
		status_lbl.text = "¿Deseas prevenir este efecto? (5s)"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(status_lbl)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var state := {"done": false, "chosen": {}}
	var btn_pass := Button.new()
	btn_pass.text = "Pasar ▶"
	btn_pass.pressed.connect(func(): state.done = true)
	btn_row.add_child(btn_pass)

	for c in candidates:
		var btn := Button.new()
		var card_name: String = str(c.card.card_name) if (c.card and "card_name" in c.card and not str(c.card.card_name).is_empty()) else str(c.entry.name)
		btn.text = "Usar %s" % card_name
		btn.pressed.connect(func():
			state.chosen = c
			state.done = true
		)
		btn_row.add_child(btn)

	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)

	var elapsed := 0.0
	while not state.done and elapsed < 5.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	layer.queue_free()
	return state.chosen


## Wrapper para los choke points que sí tienen un Node afectado real (la
## mayoría — destroy/exile/silence/debuff/leave_play/annul directo).
func offer_prevention(affected_card: Node, effect_source: Node, effect_tag: String) -> bool:
	if not is_instance_valid(affected_card):
		return false
	if try_consume_legacy_targeted_prevention(affected_card):
		return true
	if _dagon_shield_covers(affected_card, effect_source):
		return true
	if _extra_shield_covers(affected_card, effect_source):
		return true
	_last_prevention_source_id = effect_source.get_instance_id() if is_instance_valid(effect_source) else 0
	_last_prevention_target = affected_card
	if effect_tag != "annul" and affected_card.get("card_type") == Constants.CardType.ALIADO \
			and affected_card.get("current_zone") in Constants.ZONES_IN_PLAY:
		var affected_ctrl: int = int(affected_card.controller_id) if affected_card.get("controller_id") != null else 0
		if _current_effect_controller(effect_source) == 1 - affected_ctrl:
			load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("ally_affected", {"pid": affected_ctrl})
	if affected_card.get("current_zone") == null or not (affected_card.current_zone in Constants.ZONES_IN_PLAY):
		return false
	var owner_id: int = affected_card.controller_id if affected_card.get("controller_id") != null else 0
	if effect_tag != "annul" and await _fision_toll_prevents(affected_card, owner_id, effect_source):
		return true
	if effect_tag != "annul" and opp_immune_card(affected_card, effect_source):
		return true
	# corazón de muerte: "a tu oponente le cueste un Oro adicional afectarla hasta tu próximo turno".
	if effect_tag != "annul" and GameManager.turn_serial <= int(affected_card.get_meta("affect_toll_until", -1)):
		var payer: int = _current_effect_controller(effect_source)
		if payer == 1 - owner_id and not opp_cost_waived(payer, owner_id) \
				and not await load("res://scripts/core/effects/triggers/TriggerTollPatterns.gd").pay_toll(affected_card, payer, 1):
			return true
	return await offer_prevention_for_player(owner_id, effect_source, effect_tag, affected_card)


## "No puede ser afectado por efectos oponentes" de una carta por un tiempo (Revólver Webley, Fuego
## Purificador, Rugido de Titán): meta "opp_immune_until" = último turn_serial en que vale. Anular no
## es afectar la carta.
func opp_immune_card(affected_card: Node, effect_source) -> bool:
	if not is_instance_valid(affected_card):
		return false
	# Fuego Purificador / Rugido de Titán: "Prevén que una carta sea afectada por un efecto oponente" — ese
	# efecto puntual (la carta de la que sale), no todos.
	var prevented: Dictionary = affected_card.get_meta("prevent_effect_of", {})
	if not prevented.is_empty() and int(prevented.get("turn", -1)) == GameManager.turn_serial:
		var ctx: Dictionary = EffectContextScript.current()
		var source_id: int = effect_source.get_instance_id() if effect_source != null and is_instance_valid(effect_source) else 0
		var ctx_id: int = ctx.card.get_instance_id() if not ctx.is_empty() and is_instance_valid(ctx.get("card")) else 0
		if int(prevented.source_id) in [source_id, ctx_id]:
			var main_p := get_node_or_null("/root/Main")
			if main_p:
				main_p._update_debug("%s no es afectada por ese efecto (se previno)" % str(affected_card.get("card_name")))
			return true
	var in_battle: bool = GameManager.current_phase in [Constants.Phase.ATAQUE, Constants.Phase.BLOQUEO,
		Constants.Phase.GUERRA_TALISMANES, Constants.Phase.ASIGNACION_DANIO]
	var battle_immune: bool = in_battle and int(affected_card.get_meta("opp_immune_battle_turn", -1)) == GameManager.turn_serial  # Dhampir Feroce
	if not battle_immune and GameManager.turn_serial > int(affected_card.get_meta("opp_immune_until", -1)):
		return false
	var owner_id: int = affected_card.controller_id if affected_card.get("controller_id") != null else 0
	if _current_effect_controller(effect_source) != 1 - owner_id:
		return false
	var main := get_node_or_null("/root/Main")
	if main:
		main._update_debug("%s no puede ser afectado por efectos oponentes" % str(affected_card.get("card_name")))
	return true


## "No puedes ser afectado por efectos oponentes" del jugador (peter pan, Jugando con el Demonio):
## RuleState "opp_effect_immune". Cubre lo mismo que el escudo de Fisión Nuclear para el jugador
## (Descartar/Botar, buscar o mirar su mano y su Castillo, daño por efecto), sin el peaje sobre sus
## cartas en juego.
func player_opp_immune(player_id: int) -> bool:
	return RuleState.active("opp_effect_immune", player_id)


## Modelo de carga previa (sin pregunta reactiva) para las cartas que no encajan en
## _prevention_registry (Fisión Nuclear/Transformación, MiscUniquePatterns.gd: protección repartida
## con una carga por carta). Se consulta primero en offer_prevention(). {card_instance_id: count}
var _legacy_targeted_preventions: Dictionary = {}


func add_legacy_targeted_prevention(card: Node, amount: int = 1) -> void:
	if not is_instance_valid(card):
		return
	var id := card.get_instance_id()
	_legacy_targeted_preventions[id] = _legacy_targeted_preventions.get(id, 0) + amount


func try_consume_legacy_targeted_prevention(card: Node) -> bool:
	if not is_instance_valid(card):
		return false
	var id := card.get_instance_id()
	var charges: int = _legacy_targeted_preventions.get(id, 0)
	if charges <= 0:
		return false
	_legacy_targeted_preventions[id] = charges - 1
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Carta"
	var main := get_node_or_null("/root/Main")
	if main:
		main._update_debug("%s: protegida (Almirante Akari)" % card_name)
	return true


## Fisión Nuclear: "Hasta tu próximo turno, no puedes ser afectado por efectos oponentes y para
## afectar tus cartas en juego tu oponente debe Desterrar una carta de su mano":
## - el jugador protegido: no le afectan Descartar ni Botar del rival
## (fision_blocks_player_effect(), en ActionModule.discard/mill);
## - su Castillo y su mano (no el Cementerio): el rival no puede buscar ni mirar
## (fision_hides_zones_of(), en ActionSearch y CastleLook) ni hacerle daño por efecto
## (DamageManager); en combate, el daño "al Destierro" de habilidades rivales va como daño normal
## (BattleManager);
## - sus cartas en juego (también las que entren después): el rival elige si Destierra una carta de
## su mano para afectarla; si no, no la afecta (offer_prevention(): destruir, desterrar,
## barajar/devolver, debilitar, silenciar, ganar el control). Anular no es afectar la carta.
## Quién controla el efecto: EffectContext o, si no hay, el controlador de la fuente. Dura hasta el
## siguiente turno del protegido.
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const DagonScript = preload("res://scripts/core/effects/triggers/DagonPatterns.gd")
const PreventionCosts = preload("res://scripts/core/effects/mechanics/PreventionCosts.gd")
const TurnLimits = preload("res://scripts/core/effects/mechanics/TurnLimits.gd")
const CompiledPrevention = preload("res://scripts/core/effects/mechanics/CompiledPrevention.gd")
var _fision_shields: Dictionary = {}  # player_id -> true


func activate_fision_shield(player_id: int) -> void:
	_fision_shields[player_id] = true
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != player_id:
			return
		_fision_shields.erase(player_id)
		if GameManager.turn_started.is_connected(clear_it):
			GameManager.turn_started.disconnect(clear_it)
	GameManager.turn_started.connect(clear_it)


## DAR abril 2026 (Coste Adicional): "Los costes adicionales no hacen objetivo pero afectan a los jugadores,
## por lo que los efectos que hagan que los jugadores no puedan ser afectados pueden evitar pagar costes
## adicionales." true = 'payer' no paga el recargo que puso 'source_pid' (-1: se asume del rival, como casi
## todos los "a tu oponente le cuesta...").
func opp_cost_waived(payer: int, source_pid: int) -> bool:
	if source_pid == payer or not (is_fision_shielded(payer) or player_opp_immune(payer)):
		return false
	return true


## DAR abril 2026 (Afectar): "Los efectos que cancelen ataque afectan a los Aliados" (las restricciones de
## ataque afectan al jugador). Deja solo los atacantes cuyo ataque sí se cancela: "no puede ser afectado
## por efectos oponentes" y las prevenciones del Aliado (etiqueta "cancel_attack") lo evitan.
func filter_attack_cancel(attackers_in: Array, source: Node) -> Array:
	var out: Array = []
	for a in attackers_in:
		if is_instance_valid(a) and not await offer_prevention(a, source, "cancel_attack"):
			out.append(a)
	return out


## Lo mismo para una clave de RuleState puesta sobre 'payer' (PaymentManager, TriggerTollPatterns).
func rule_cost_waived(key: String, payer: int) -> bool:
	return opp_cost_waived(payer, RuleState.source_of(key, payer))


func is_fision_shielded(player_id: int) -> bool:
	return _fision_shields.get(player_id, false)


func _current_effect_controller(effect_source) -> int:
	var ctx: Dictionary = EffectContextScript.current()
	if not ctx.is_empty():
		return int(ctx.controller_id)
	if effect_source != null and is_instance_valid(effect_source) and effect_source.get("controller_id") != null:
		return int(effect_source.controller_id)
	return -1


func fision_blocks_player_effect(player_id: int) -> bool:
	"""true si 'player_id' está protegido por Fisión Nuclear y el efecto en
	curso es de su rival (Descartar/Botar no ocurren)."""
	if not (is_fision_shielded(player_id) or player_opp_immune(player_id)) or _current_effect_controller(null) != 1 - player_id:
		return false
	var main := get_node_or_null("/root/Main")
	if main:
		main._update_debug("Fisión Nuclear: el jugador %d no puede ser afectado por efectos oponentes" % (player_id + 1))
	return true


func fision_hides_zones_of(zone_owner: int, chooser_id: int, zone: int = Constants.Zone.CASTILLO) -> bool:
	"""true si 'chooser_id' (el rival) no puede buscar/mirar en el Castillo
	(o la mano) de 'zone_owner' por Fisión Nuclear. El Cementerio no cuenta."""
	if zone not in [Constants.Zone.CASTILLO, Constants.Zone.MANO]:
		return false
	# Escudo Estelar: "Los jugadores no pueden buscar, mirar, ni mostrar cartas de la mano ni los Castillos
	# por efectos hasta tu próxima Fase Final" (también las propias).
	if RuleState.active("zones_hidden", zone_owner):
		var main_e := get_node_or_null("/root/Main")
		if main_e:
			main_e._update_debug("Escudo Estelar: no se puede buscar ni mirar en la mano ni en los Castillos")
		return true
	if chooser_id < 0 or chooser_id == zone_owner:
		return false
	# Terminal P-12: "Si está en tu Reserva, ... él no puede mirar tu mano ni tu Castillo."
	if TurnLimits.terminal_in_reserva(zone_owner):
		var main_t := get_node_or_null("/root/Main")
		if main_t:
			main_t._update_debug("Terminal P-12: no puedes mirar la mano ni el Castillo del jugador %d" % (zone_owner + 1))
		return true
	# Ofrenda a los Abuelos: "prevén que tu oponente busque cartas en tu Castillo" (este turno).
	if zone == Constants.Zone.CASTILLO and not RuleState.turn_data("castle_search_block:%d" % zone_owner).is_empty():
		var main_o := get_node_or_null("/root/Main")
		if main_o:
			main_o._update_debug("Ofrenda a los Abuelos: no puedes buscar cartas en el Castillo del jugador %d" % (zone_owner + 1))
		return true
	if not is_fision_shielded(zone_owner) and not player_opp_immune(zone_owner):
		return false
	var main := get_node_or_null("/root/Main")
	if main:
		main._update_debug("No puedes buscar ni elegir en las zonas del jugador %d (no puede ser afectado por efectos oponentes)" % (zone_owner + 1))
	return true


func _fision_toll_prevents(affected_card, owner_id: int, effect_source) -> bool:
	"""Peaje de Fisión Nuclear: true = la carta NO es afectada."""
	if not is_fision_shielded(owner_id):
		return false
	var payer: int = _current_effect_controller(effect_source)
	if payer != 1 - owner_id:
		return false
	var main := get_node_or_null("/root/Main")
	if not main:
		return true
	var card_name: String = str(affected_card.get("card_name")) if affected_card.get("card_name") != null else "esa carta"
	var hand: Array = PlayerSideScript.hand_cards(main, payer).filter(func(c): return is_instance_valid(c))
	var paid: Node = null
	if not hand.is_empty():
		if PlayerSideScript.is_bot(payer):
			# El bot paga si le sobran cartas en la mano.
			if hand.size() >= 3:
				paid = hand.pick_random()
		elif main._card_interaction:
			paid = await main._card_interaction.await_target(
				"Fisión Nuclear: Destierra una carta de tu mano para afectar a %s (N: no afectarla)" % card_name,
				func(c: Node) -> bool: return c in hand, true, payer)
	if paid == null or not is_instance_valid(paid):
		main._update_debug("Fisión Nuclear: %s no es afectada" % card_name)
		return true
	var data: Dictionary = paid.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, payer, paid)
	if is_instance_valid(paid):
		CardManager._disconnect_card_interaction_signals(paid)
		paid.queue_free()
	data["esta_oculta"] = false
	CardManager.append_to_exile(payer, data)
	main._update_debug("Fisión Nuclear: el jugador %d Destierra %s de su mano para afectar a %s" % [
		payer + 1, str(data.get("nombre", "una carta")), card_name])
	return false


## Colapso Global: "En respuesta a que tu oponente fuera a mirar tu mano o buscar cartas en un
## Castillo, puedes Desterrar una carta de tu mano para jugarlo sin pagar su coste. Prevén que tu
## oponente mire tu mano o busque cartas y tú Robas una carta." Se ofrece en las búsquedas
## (ActionSearch) y al mirar la mano rival; true = no ocurre. Se paga su coste o se Destierra una
## carta de la mano; va al Cementerio.
## Sidhes del Bosque: "Puedes jugarlo en respuesta a que tu oponente fuera a buscar cartas en un
## Castillo. Nombra dos cartas...". ActionSearch lo ofrece antes de buscar y aplica el candado
## (sidhes_blocked_names) y el mostrar (sidhes_reveal_to).
func offer_sidhes(searcher_id: int) -> void:
	if searcher_id < 0:
		return
	var main := get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return
	var victim: int = 1 - searcher_id
	var sidhes: Node = null
	for c in PlayerSideScript.hand_cards(main, victim):
		if is_instance_valid(c) and "puedes jugarlo en respuesta a que tu oponente fuera a buscar cartas en un castillo" \
				in str(c.get("card_ability")).to_lower():
			sidhes = c
			break
	if sidhes == null:
		return
	var cost: int = int(PaymentManager.calcular_coste_real(sidhes))
	if not main._gold_manager.puede_pagar(cost, Constants.CardType.TALISMAN, "", int(sidhes.get("card_cost")), victim):
		return
	var card_name: String = str(sidhes.get("card_name"))
	if not PlayerSideScript.is_bot(victim):
		if not await SelectionManager.await_two_choice(main, "Tu oponente va a buscar en un Castillo",
				"Jugar %s (%d Oro)" % [card_name, cost], "No responder", victim):
			return
	if cost > 0:
		await main._gold_manager.pagar_coste(cost, Constants.CardType.TALISMAN, "", int(sidhes.get("card_cost")), victim)
	var sdata: Dictionary = sidhes.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, victim, sidhes)
	if is_instance_valid(sidhes):
		CardManager._disconnect_card_interaction_signals(sidhes)
		sidhes.queue_free()
	await resolve_sidhes_effect(victim, card_name)
	sdata["esta_oculta"] = false
	CardManager.add_to_cemetery(victim, sdata)


## Efecto de Sidhes del Bosque, jugado en respuesta (offer_sidhes) o como Talismán normal en tu
## Vigilia / Guerra de Talismanes ("puedes jugarlo en respuesta" no impide jugarlo normal). victim =
## quien juega Sidhes; el candado es para su oponente.
func resolve_sidhes_effect(victim: int, card_name: String) -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var searcher_id: int = 1 - victim
	# Nombrar dos cartas.
	var names: Array = []
	if PlayerSideScript.is_bot(victim):
		var deck: Array = CardManager.get_deck(searcher_id).duplicate()
		deck.shuffle()
		for d in deck:
			var n: String = str(d.get("nombre", "")).to_lower()
			if not n.is_empty() and not (n in names):
				names.append(n)
			if names.size() >= 2:
				break
	else:
		for i in range(2):
			var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
				"%s: nombra una carta que tu oponente no podrá buscar (%d de 2)" % [card_name, i + 1], victim)
			var n: String = str(picked.get("nombre", "")).to_lower()
			if not n.is_empty() and not (n in names):
				names.append(n)
	RuleState.set_turn_data("sidhes_lock", {"searcher": searcher_id, "names": names, "reveal_to": victim})
	main._update_debug("%s: este turno tu oponente muestra lo que busca y no puede buscar %s" % [card_name,
		" ni ".join(names) if not names.is_empty() else "nada nombrado"])
	# Roba una carta o sube un Aliado de tu Cementerio a tu mano.
	var has_ally_in_cemetery: bool = CardManager.get_cemetery(victim).any(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO)
	var draw_it := true
	if has_ally_in_cemetery and not PlayerSideScript.is_bot(victim):
		draw_it = await SelectionManager.await_two_choice(main, card_name, "Robar una carta", "Subir un Aliado de tu Cementerio a tu mano", victim)
	if draw_it:
		await ActionModule.draw(victim, 1, card_name, true)
	else:
		await ActionModule.search(victim, Constants.Zone.CEMENTERIO, {"type": Constants.CardType.ALIADO}, 1, true, false, false,
			null, Constants.Zone.MANO, false, victim)


func _sidhes_lock_for(searcher_id: int) -> Dictionary:
	var lock: Dictionary = RuleState.turn_data("sidhes_lock")
	if lock.is_empty() or int(lock.get("searcher", -1)) != searcher_id:
		return {}
	return lock


func sidhes_blocked_names(searcher_id: int) -> Array:
	return _sidhes_lock_for(searcher_id).get("names", [])


func sidhes_reveal_to(searcher_id: int) -> int:
	return int(_sidhes_lock_for(searcher_id).get("reveal_to", -1))


func offer_colapso_global(searcher_id: int) -> bool:
	if searcher_id < 0:
		return false
	var main := get_node_or_null("/root/Main")
	if not main:
		return false
	var victim: int = 1 - searcher_id
	var hand: Array = PlayerSideScript.hand_cards(main, victim).filter(func(c): return is_instance_valid(c))
	var colapso: Node = null
	for c in hand:
		if "prevén que tu oponente mire tu mano o busque cartas" in str(c.get("card_ability")).to_lower():
			colapso = c
			break
	if colapso == null:
		return false
	var others: Array = hand.filter(func(c): return c != colapso)
	var can_pay: bool = main._gold_manager.puede_pagar(int(colapso.get("card_cost")), Constants.CardType.TALISMAN, "", -1, victim)
	if others.is_empty() and not can_pay:
		return false
	var use_banish: bool = not others.is_empty()
	if PlayerSideScript.is_bot(victim):
		pass  # el bot lo usa siempre que puede
	else:
		var label_banish := "Jugar Colapso Global Desterrando una carta de tu mano"
		var label_pay := "Jugar Colapso Global pagando %d Oro" % int(colapso.get("card_cost"))
		if not await SelectionManager.await_two_choice(main, "Tu oponente va a mirar tu mano o buscar cartas",
				label_banish if use_banish else label_pay, "No responder", victim):
			return false
		if use_banish and can_pay:
			use_banish = await SelectionManager.await_two_choice(main, "Colapso Global", label_banish, label_pay, victim)
	if use_banish:
		var paid: Node = others.pick_random() if PlayerSideScript.is_bot(victim) else null
		if paid == null and main._card_interaction:
			paid = await main._card_interaction.await_target("Colapso Global: Destierra una carta de tu mano",
				func(c: Node) -> bool: return c in others, false, victim)
		if paid == null or not is_instance_valid(paid):
			return false
		var pdata: Dictionary = paid.card_data.duplicate()
		PlayerSideScript.remove_from_hand(main, victim, paid)
		if is_instance_valid(paid):
			CardManager._disconnect_card_interaction_signals(paid)
			paid.queue_free()
		pdata["esta_oculta"] = false
		CardManager.append_to_exile(victim, pdata)
	else:
		await main._gold_manager.pagar_coste(int(colapso.get("card_cost")), Constants.CardType.TALISMAN, "", -1, victim)
	var cdata: Dictionary = colapso.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, victim, colapso)
	if is_instance_valid(colapso):
		CardManager._disconnect_card_interaction_signals(colapso)
		colapso.queue_free()
	cdata["esta_oculta"] = false
	CardManager.add_to_cemetery(victim, cdata)
	main._update_debug("Colapso Global: se previene la búsqueda o mirada del oponente")
	await ActionModule.draw(victim, 1, "Colapso Global", true)
	return true


## Prevenir daño al Castillo con un Oro:
## - Alicanto: "En respuesta a que fueras a recibir daño, puedes Desterrar este Oro para prevenirlo.
## Luego, puedes convertir una carta de tu mano en un Oro sin habilidad y ponerla en tu Oro Pagado."
## - Escritura Sagrada: "Puedes subirlo a tu mano o convertirlo en un Oro sin habilidad para
## prevenir recibir daño."
## Se ofrece en BattleManager antes del daño de combate y previene todo ese daño.
func offer_castle_damage_prevention(defender_id: int, damage: int) -> bool:
	var main := get_node_or_null("/root/Main")
	if not main or damage <= 0:
		return false
	var candidates: Array = []
	for zone in [PlayerSideScript.gold_reserva(main, defender_id), PlayerSideScript.oro_pagado(main, defender_id)]:
		if not zone:
			continue
		for c in zone.get_children():
			if not is_instance_valid(c) or c.get("card_ability") == null or KeywordManager.is_silenced(c) \
					or c.get("is_converted") == true:
				continue
			var t: String = str(c.card_ability).to_lower()
			if "en respuesta a que fueras a recibir daño, puedes desterrar este oro para prevenirlo" in t:
				candidates.append({"card": c, "kind": "alicanto"})
			elif "puedes subirlo a tu mano o convertirlo en un oro sin habilidad para prevenir recibir daño" in t:
				candidates.append({"card": c, "kind": "escritura"})
	if candidates.is_empty():
		return false
	var chosen: Dictionary = {}
	if PlayerSideScript.is_bot(defender_id):
		if damage >= 2:
			chosen = candidates[0]
	else:
		for cand in candidates:
			if await SelectionManager.await_two_choice(main,
					"Vas a recibir %d de daño" % damage, "Usar %s para prevenirlo" % str(cand.card.card_name), "No",
					defender_id):
				chosen = cand
				break
	if chosen.is_empty() or not is_instance_valid(chosen.card):
		return false
	var oro: Node = chosen.card
	var oro_name: String = str(oro.card_name)
	if chosen.kind == "alicanto":
		main._gold_manager.exile_gold_from_play(oro)
		main._update_debug("%s: se previene el daño" % oro_name)
		await _alicanto_convert_hand_card(main, defender_id)
	else:
		var to_hand: bool = true
		if not PlayerSideScript.is_bot(defender_id):
			to_hand = await SelectionManager.await_two_choice(main, oro_name, "Subirlo a tu mano",
				"Convertirlo en un Oro sin habilidad", defender_id)
		if to_hand:
			main._gold_manager.return_gold_to_hand(oro)
		else:
			oro.is_converted = true
		main._update_debug("%s: se previene el daño" % oro_name)
	return true


func _alicanto_convert_hand_card(main: Node, pid: int) -> void:
	var hand: Array = PlayerSideScript.hand_cards(main, pid).filter(func(c): return is_instance_valid(c))
	if hand.is_empty() or PlayerSideScript.is_bot(pid) or not main._card_interaction:
		return
	var picked: Node = await main._card_interaction.await_target(
		"Alicanto: puedes convertir una carta de tu mano en un Oro sin habilidad en tu Oro Pagado (N: no)",
		func(c: Node) -> bool: return c in hand, true, pid)
	if not picked or not is_instance_valid(picked):
		return
	var data: Dictionary = picked.card_data.duplicate()
	PlayerSideScript.remove_from_hand(main, pid, picked)
	if is_instance_valid(picked):
		CardManager._disconnect_card_interaction_signals(picked)
		picked.queue_free()
	data["esta_oculta"] = false
	var gold_node: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, data)
	if is_instance_valid(gold_node):
		gold_node.card_type = Constants.CardType.ORO
		gold_node.is_converted = true


## Efectos suspendidos que resuelven una vez en la próxima Fase Final de un jugador (p.ej. Fisión
## Nuclear: "En la próxima Fase Final oponente, Baraja una carta de coste 2 o menos o Roba dos
## cartas"). No es un trigger en juego: el Talismán ya se resolvió y no hay carta a la que
## consultar. No se puede responder: se resuelve directo, sin prevención.
var _scheduled_next_final_phase_effects: Dictionary = {}


func schedule_next_final_phase_effect(player_id: int, effect: Callable) -> void:
	if not _scheduled_next_final_phase_effects.has(player_id):
		_scheduled_next_final_phase_effects[player_id] = []
	_scheduled_next_final_phase_effects[player_id].append(effect)


func consume_scheduled_final_phase_effects(player_id: int) -> void:
	"""Llamar al ENTRAR a la Fase Final de player_id (PhaseFlowController.
	_resolve_fase_final()) — ejecuta y limpia (una sola vez) los efectos
	suspendidos agendados para esta Fase Final puntual."""
	var effects: Array = _scheduled_next_final_phase_effects.get(player_id, [])
	if effects.is_empty():
		return
	_scheduled_next_final_phase_effects[player_id] = []
	for effect: Callable in effects:
		if effect.is_valid():
			await effect.call()
