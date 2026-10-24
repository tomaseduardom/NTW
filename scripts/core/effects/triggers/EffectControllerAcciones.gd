extends "res://scripts/core/effects/triggers/EffectControllerBase.gd"
## EffectControllerAcciones — familia Acciones de EffectController.gd (ver EffectControllerBase.gd).


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

# =============================================================================
# 11. CONVERTIR TIPO DE CARTA (DAR Sección 8 - Convertir)
# =============================================================================
