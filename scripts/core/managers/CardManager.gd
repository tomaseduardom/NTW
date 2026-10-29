extends Node
## CardManager - Singleton que gestiona el movimiento de cartas entre zonas
## Centraliza la lógica de deck, mano, cementerio y destierro

# =============================================================================
# SEÑALES
# =============================================================================
signal card_drawn(player_id: int, card_data: Dictionary)
signal card_discarded(player_id: int, card_data: Dictionary)
signal card_destroyed(player_id: int, card: Node)
signal card_exiled(player_id: int, card: Node)
signal damage_taken(player_id: int, amount: int, cards_milled: Array)
signal deck_empty(player_id: int)
signal zone_changed(card: Node, from_zone: int, to_zone: int, player_id: int)

# Señales para actualización de UI (contadores)
signal deck_count_changed(player_id: int, new_count: int)
signal hand_count_changed(player_id: int, new_count: int)
signal cemetery_count_changed(player_id: int, new_count: int)
## Cualquier carta que entra a un Cementerio (disparadores "Cuando sea puesta en tu Cementerio", ver
## CemeteryTriggers.gd).
signal card_put_in_cemetery(player_id: int, card_data: Dictionary)
## Igual para el Destierro (fudo-myo: "un Talismán puesto en tu Cementerio o Destierro").
signal card_put_in_exile(player_id: int, card_data: Dictionary)
signal exile_count_changed(player_id: int, new_count: int)
signal field_count_changed(player_id: int, new_count: int)

# =============================================================================
# REFERENCIAS
# =============================================================================
var _main: Node = null  # Referencia a Main.gd (se obtiene dinámicamente)

# =============================================================================
# DATOS DE ZONAS (por jugador)
# =============================================================================
# Estructura: { player_id: { zone: data } }
var _zones: Dictionary = {
	0: {
		"deck": [],        # Array[Dictionary] - datos de cartas
		"hand": [],        # Array[Node] - instancias de Card
		"field": [],       # Array[Node] - aliados en juego
		"cemetery": [],    # Array[Dictionary] - datos de cartas destruidas
		"exile": [],       # Array[Dictionary] - datos de cartas desterradas
		"gold": [],        # Array[Node] - oros en reserva
		"gold_paid": []    # Array[Node] - oros pagados este turno
	},
	1: {
		"deck": [],
		"hand": [],
		"field": [],
		"cemetery": [],
		"exile": [],
		"gold": [],
		"gold_paid": []
	}
}

## "las cartas que estén o sean puestas en los Cementerios este turno pierden su habilidad hasta tu
## próximo turno" (Sable de Napoleón) — mientras esté true, cualquier carta que entre a CUALQUIER
## Cementerio (ver _append_to_cemetery) queda marcada como silenciada también. Se apaga sola al
## empezar el próximo turno (turno del rival), ver silence_all_cemetery_cards.
var _cemetery_silence_capture_active: bool = false

# =============================================================================
# INICIALIZACIÓN
# =============================================================================
func _ready() -> void:
	print("[CardManager] Inicializado")


func _get_main() -> Node:
	"""Obtiene referencia a Main.gd de forma lazy"""
	if not _main or not is_instance_valid(_main):
		_main = get_tree().current_scene if get_tree() else null
	return _main


# =============================================================================
# SINCRONIZACIÓN CON MAIN.GD
# =============================================================================
func sync_from_main() -> void:
	"""Sincroniza los datos desde Main.gd (llamar al inicio del juego)"""
	var main = _get_main()
	if not main:
		push_warning("[CardManager] Main.gd no disponible para sincronizar")
		return

	# Partida nueva: CardManager es autoload y sobrevive entre partidas, así que se reemplazan siempre
	# las zonas (con 'if main.get("player_cemetery")' un Array vacío es falso y quedaba el Cementerio
	# viejo) y se vacía el Destierro, que solo vive aquí.
	for pid in [0, 1]:
		_zones[pid].exile = []
		_zones[pid].hand = []
		_zones[pid].field = []
		_zones[pid].gold = []
		_zones[pid].gold_paid = []
	_cemetery_silence_capture_active = false

	# Sincronizar decks
	if main.get("player_deck") != null:
		_zones[0].deck = main.player_deck
	if main.get("opponent_deck") != null:
		_zones[1].deck = main.opponent_deck

	# Sincronizar cementerios
	if main.get("player_cemetery") != null:
		_zones[0].cemetery = main.player_cemetery
	if main.get("opponent_cemetery") != null:
		_zones[1].cemetery = main.opponent_cemetery

	print("[CardManager] Sincronizado - Deck P0: %d, Deck P1: %d" % [
		_zones[0].deck.size(), _zones[1].deck.size()
	])


# =============================================================================
# ACCESO A ZONAS
# =============================================================================
func get_deck(player_id: int) -> Array:
	"""Obtiene el mazo de un jugador"""
	return _zones[player_id].deck


func get_cemetery(player_id: int) -> Array:
	"""Obtiene el cementerio de un jugador"""
	return _zones[player_id].cemetery


func get_exile(player_id: int) -> Array:
	"""Obtiene el destierro de un jugador"""
	return _zones[player_id].exile


func get_deck_count(player_id: int) -> int:
	"""Obtiene el número de cartas en el mazo"""
	return _zones[player_id].deck.size()


func get_cemetery_count(player_id: int) -> int:
	"""Obtiene el número de cartas en cementerio"""
	return _zones[player_id].cemetery.size()


func get_exile_count(player_id: int) -> int:
	"""Obtiene el número de cartas en destierro"""
	return _zones[player_id].exile.size()


# =============================================================================
# MOVIMIENTO DE CARTAS - DECK
# =============================================================================
func draw_card(player_id: int) -> Dictionary:
	"""Roba una carta del tope del mazo

	Returns: Datos de la carta robada, o {} si el mazo está vacío
	"""
	var deck = _zones[player_id].deck

	if deck.is_empty():
		emit_signal("deck_empty", player_id)
		return {}

	# Robar del tope (último elemento = tope del mazo)
	var card_data = deck.pop_back()

	emit_signal("card_drawn", player_id, card_data)
	_update_deck_visual(player_id)

	return card_data


func draw_cards(player_id: int, count: int) -> Array:
	"""Roba múltiples cartas del mazo

	Returns: Array de datos de cartas robadas
	"""
	var drawn: Array = []

	for i in range(count):
		var card_data = draw_card(player_id)
		if card_data.is_empty():
			break
		drawn.append(card_data)

	return drawn


func add_to_deck_top(player_id: int, card_data: Dictionary) -> void:
	"""Añade una carta al tope del mazo. El tope es el FRENTE del array (índice 0): el robo real es
	ZoneManager.draw_card(), con _main.player_deck.pop_front(), y _zones[player_id].deck es el
	mismo array (sync_from_main() asigna, no copia). draw_card() de este archivo usa pop_back()
	(convención vieja)."""
	_zones[player_id].deck.insert(0, card_data)
	_update_deck_visual(player_id)


func add_to_deck_bottom(player_id: int, card_data: Dictionary) -> void:
	"""Añade una carta al fondo del mazo (ver nota de convención en
	add_to_deck_top() — fondo = el otro extremo del array real de robo)."""
	_zones[player_id].deck.append(card_data)
	_update_deck_visual(player_id)


func shuffle_deck(player_id: int) -> void:
	"""Baraja el mazo de un jugador"""
	_zones[player_id].deck.shuffle()
	_note_cards_shuffled()
	print("[CardManager] Mazo de jugador %d barajado" % player_id)


## Cuatro Esposas: "si no barajaste cartas este turno". Cuenta para quien controla el efecto en curso cuando su
## texto Baraja cartas (no "baraja tu Castillo" tras buscar ni "baraja el resto" de lo mostrado).
func _note_cards_shuffled() -> void:
	var ctx: Dictionary = load("res://scripts/core/effects/EffectContext.gd").current()
	if ctx.is_empty() or not is_instance_valid(ctx.get("card")):
		return
	var data = ctx.card.get("card_data")
	var text: String = load("res://scripts/core/cards/CardText.gd").fold(str(data.get("habilidad", "")) if data is Dictionary else "").to_lower()
	var rx := RegEx.create_from_string("\\bbaraj\\w* (?!(?:tu|su|ambos|los) castillos?\\b|el resto\\b|las demas\\b|los demas\\b)")
	if rx.search(text) != null:
		RuleState.add("cards_shuffled", int(ctx.controller_id))


func add_to_exile(player_id: int, card_data: Dictionary) -> void:
	"""Añade datos de una carta directo al Destierro — para efectos que la mandan ahí sin pasar por
	una carta en juego (p.ej. Rey de Amarillo: busca en un Castillo y Destiérralas directo, sin
	llevárselas a la mano primero)."""
	card_data["esta_oculta"] = false
	append_to_exile(player_id, card_data)
	_emit_exile_changed(player_id)


func banish_from_deck(deck_owner: int, amount: int, from_bottom: bool = false, actor: int = -2) -> Array:
	"""Destierra 'amount' cartas del tope (o fondo) del Castillo de 'deck_owner'. Respeta "tu oponente
	no puede Desterrar cartas de tu Castillo" (ProtectionRules.castle_banish_blocked): si está
	bloqueado no mueve nada. Devuelve los datos desterrados."""
	var moved: Array = []
	if amount <= 0 or load("res://scripts/core/effects/mechanics/ProtectionRules.gd").castle_banish_blocked(deck_owner, actor):
		return moved
	var deck: Array = get_deck(deck_owner)
	for i in range(amount):
		if deck.is_empty():
			break
		var data: Dictionary = deck.pop_back() if from_bottom else deck.pop_front()
		data["esta_oculta"] = false
		append_to_exile(deck_owner, data)
		moved.append(data)
	if not moved.is_empty():
		_emit_deck_changed(deck_owner)
		_emit_exile_changed(deck_owner)
	return moved


func append_to_exile(player_id: int, card_data: Dictionary) -> void:
	"""Punto único para agregar una entrada a un Destierro (ver card_put_in_exile)."""
	_zones[player_id].exile.append(card_data)
	card_put_in_exile.emit(player_id, card_data)


# =============================================================================
# MOVIMIENTO DE CARTAS - MANO
# =============================================================================
func remove_from_hand(player_id: int, card: Node) -> bool:
	"""Remueve una carta de la mano

	Returns: true si se removió exitosamente
	"""
	var hand = _zones[player_id].hand
	var idx = hand.find(card)

	if idx >= 0:
		hand.remove_at(idx)
		return true
	return false


# =============================================================================
# MOVIMIENTO DE CARTAS - CEMENTERIO
# =============================================================================
func _append_to_cemetery(player_id: int, card_data: Dictionary) -> void:
	"""Punto único para agregar una entrada a un Cementerio, para que la captura de Sable de Napoleón
	(silenciar lo que entra durante su ventana) no dependa de cada llamador."""
	# resistir: "hasta tu próximo turno, los Talismanes que fueran a ser puestos en el Cementerio, en vez de
	# eso son Desterrados".
	if int(card_data.get("tipo", -1)) == Constants.CardType.TALISMAN and RuleState.active("talisman_to_exile", player_id):
		append_to_exile(player_id, card_data)
		return
	if _cemetery_silence_capture_active:
		card_data["_silenced_by_cemetery_effect"] = true
	_zones[player_id].cemetery.append(card_data)
	card_put_in_cemetery.emit(player_id, card_data)


func is_cemetery_card_silenced(card_data: Dictionary) -> bool:
	"""'Pierde su habilidad' para una carta EN CEMENTERIO (Sable de Napoleón) —
	KeywordManager._silenced_cards es por instance_id de un Node vivo, no aplica a datos de
	Cementerio (Dictionary puro), así que esto vive aquí, junto con el dato mismo."""
	# Niebla de Muerte: "Las cartas que sean puestas en el Cementerio este turno pierden su habilidad por el
	# turno" (marca con el turn_serial).
	if int(card_data.get("_silenced_turn", -1)) == GameManager.turn_serial:
		return true
	# Pnyx: "...pierden su habilidad hasta tu próximo turno" (último turn_serial en que vale).
	if int(card_data.get("_silenced_until", -1)) >= GameManager.turn_serial:
		return true
	if card_data.get("_silenced_by_cemetery_effect", false):
		return true
	# Auras continuas sobre los Cementerios/Destierros (torre de cristal, Pricolici...; SilenceAuras.gd).
	for player_id in [0, 1]:
		for zone_key in ["cemetery", "exile"]:
			for d in _zones[player_id][zone_key]:
				if is_same(d, card_data):
					return load("res://scripts/core/effects/continuous/SilenceAuras.gd").zone_card_silenced(card_data, player_id, zone_key == "exile")
	return false


func silence_all_cemetery_cards(activator_player_id: int) -> void:
	"""Sable de Napoleón: "Las cartas que estén o sean puestas en los Cementerios este turno pierden
	su habilidad hasta tu próximo turno". "los Cementerios" = ambos. Dos ventanas distintas:
	1) La CAPTURA de nuevas entradas dura "este turno": se apaga al empezar cualquier otro turno
	(CONNECT_ONE_SHOT).
	2) El SILENCIO dura "hasta tu próximo turno" (el de activator_player_id): se levanta cuando
	vuelve a empezar su turno."""
	for player_id in [0, 1]:
		for card_data in _zones[player_id].cemetery:
			card_data["_silenced_by_cemetery_effect"] = true
	_cemetery_silence_capture_active = true

	GameManager.turn_started.connect(
		func(_p, _t): _cemetery_silence_capture_active = false,
		CONNECT_ONE_SHOT
	)

	var clear_silence: Callable
	clear_silence = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != activator_player_id:
			return
		for player_id in [0, 1]:
			for card_data in _zones[player_id].cemetery:
				card_data.erase("_silenced_by_cemetery_effect")
		if GameManager.turn_started.is_connected(clear_silence):
			GameManager.turn_started.disconnect(clear_silence)
	GameManager.turn_started.connect(clear_silence)


func add_to_cemetery(player_id: int, card_data: Dictionary) -> void:
	"""Añade datos de carta al cementerio (desde mazo o efecto)"""
	card_data["esta_oculta"] = false
	_append_to_cemetery(player_id, card_data)
	_update_cemetery_visual(player_id)


func add_card_to_cemetery(player_id: int, card: Node) -> void:
	"""Mueve una instancia de carta al cementerio (la destruye)
	NOTA: Usar destroy_card() para respetar la regla de exhumación
	"""
	var card_data = card.card_data.duplicate() if card.get("card_data") else {}
	card_data["esta_oculta"] = false
	_append_to_cemetery(player_id, card_data)

	emit_signal("card_destroyed", player_id, card)
	_update_cemetery_visual(player_id)

	_disconnect_card_interaction_signals(card)
	card.queue_free()


func _unequip_from_wielder(card: Node) -> void:
	"""Cuando el ARMA misma sale del juego (su portador sigue), hay que sacarla de
	wielder.equipped_weapons antes de queue_free(): si no, ZoneManager.compact_field_slots() (que
	lee `var w: Node = card.equipped_weapons[w_idx]`, tipado) falla con "previously freed" en la
	próxima recompactación. _move_equipped_weapons_with() cubre la dirección contraria. Llamar
	antes de queue_free() en destroy_card()/exile_card()."""
	if not is_instance_valid(card):
		return
	var wielder: Node = card.get("wielder")
	if wielder and is_instance_valid(wielder):
		var weapons = wielder.get("equipped_weapons")
		if weapons is Array:
			weapons.erase(card)


func _move_equipped_weapons_with(player_id: int, card: Node, mover: Callable) -> void:
	"""El Arma sigue a su portador al mismo destino (DAR: no queda suelta). Se llama antes de
	queue_free() en destroy_card()/exile_card(), pasando la función de mover. Excepción: un Arma
	con "Cuando el portador fuera a salir del juego, súbela a tu mano o cámbiala de portador"
	(p.ej. Aho), donde el jugador elige."""
	if not card.get("equipped_weapons"):
		return
	for weapon in card.equipped_weapons.duplicate():
		if not is_instance_valid(weapon):
			continue
		if player_id == 0 and _weapon_survives_wielder_death(weapon):
			await _resolve_weapon_survives_wielder(weapon)
			continue
		await mover.call(player_id, weapon)


func _weapon_survives_wielder_death(weapon: Node) -> bool:
	"""Se ancla también en "bela a tu mano" (sin "sú"): la API puede traer el acento con mojibake
	(UTF-8→Latin-1→UTF-8, ver GoldManager._fix_mojibake()), y con "súbela" exacto Aho seguía a su
	portador en vez de ofrecer la elección."""
	var text: String = str(weapon.get("card_ability")) if weapon.get("card_ability") != null else ""
	var lower := text.to_lower()
	return "portador fuera a salir del juego" in lower and "bela a tu mano" in lower


func _resolve_weapon_survives_wielder(weapon: Node) -> void:
	""""Cuando el portador fuera a salir del juego, súbela a tu mano o cámbiala de portador" (p.ej.
	Aho): reemplaza la regla de que el Arma sigue a su portador. Solo elige el humano; para el
	rival se aplica la regla por defecto."""
	var main := get_node_or_null("/root/Main")
	if not main:
		return

	# Popup mínimo de 2 botones (mismo patrón que TargetedEffectExecutor.
	# _choose_search_zone_owner()) — si no hay otro Aliado libre para
	# portarla (GoldManager._get_eligible_weapon_wielders(), ya excluye
	# solo el portador que se está muriendo porque ÉL SÍ 'tiene un Arma' en
	# este instante — todavía no se soltó — y a cualquier otro que ya porte
	# una distinta), la única alternativa real es subirla a la mano.
	var other_wielders: Array = []
	if main._gold_manager and main._gold_manager.has_method("_get_eligible_weapon_wielders"):
		other_wielders = main._gold_manager._get_eligible_weapon_wielders()

	var to_hand := true
	if not other_wielders.is_empty():
		to_hand = await SelectionManager.await_two_choice(
			main, "%s: ¿Subir a tu mano o cambiar de portador?" % str(weapon.get("card_name")),
			"Subir a la mano", "Cambiar de portador")

	if to_hand:
		var weapon_parent = weapon.get_parent()
		if weapon_parent:
			weapon_parent.remove_child(weapon)
		weapon.can_interact = true
		weapon.scale = Vector2.ONE
		weapon.base_scale = Vector2.ONE
		weapon.z_index = 0
		weapon.original_z_index = 0
		weapon.set_zone(Constants.Zone.MANO)
		main.player_hand.add_card(weapon)
		return

	var new_wielder: Node = null
	if main._card_interaction:
		var filter := func(c: Node) -> bool:
			return c in other_wielders
		new_wielder = await main._card_interaction.await_target(
			"Elige qué Aliado porta %s ahora" % str(weapon.get("card_name")), filter)
	if not new_wielder or not is_instance_valid(new_wielder):
		# Canceló sin elegir — no queda otra que subirla a la mano igual,
		# no puede quedar suelta en juego sin portador (DAR).
		await _resolve_weapon_survives_wielder(weapon)
		return
	if main._gold_manager and main._gold_manager.has_method("_equip_weapon"):
		# fire_enter_play=false (ver comentario en _equip_weapon): el Arma ya estaba en juego, solo cambia
		# de portador porque el anterior murió — no es un juego nuevo, no debe re-disparar 'Cuando entra
		# en juego' ni sumar al conteo de cartas jugadas este turno.
		await main._gold_manager._equip_weapon(weapon, new_wielder, false)


func _disconnect_card_interaction_signals(card: Node) -> void:
	"""Desconecta todas las conexiones de las señales de interacción de una carta antes de
	queue_free(): un hover/click que sigue apuntando al nodo liberado falla con "Invalid access...
	previously freed" al tocar .modulate. destroy_card()/exile_card() son el camino de toda
	destrucción/destierro (Reserva, Oro Pagado, líneas). Desconecta cualquier conexión sin asumir
	quién la hizo (Main, DynamicHand, MulliganHand, SelectionManager conectan las mismas 4
	señales)."""
	if not is_instance_valid(card):
		return
	for signal_name in ["card_hovered", "card_unhovered", "card_clicked", "card_double_clicked"]:
		if not card.has_signal(signal_name):
			continue
		for conn in card.get_signal_connection_list(signal_name):
			card.disconnect(signal_name, conn.callable)


func destroy_card(player_id: int, card: Node, as_destroy: bool = true) -> void:
	"""Destruye una carta respetando la regla de exhumación (DAR)

	Si la carta fue exhumada (is_exhumed = true), va al destierro.
	Si no fue exhumada, va al cementerio normalmente.
	"""
	await _move_equipped_weapons_with(player_id, card, destroy_card)

	var card_data = card.card_data.duplicate() if card.get("card_data") else {}

	# Cartas exhumadas van al destierro, no al cementerio
	card_data["esta_oculta"] = false
	var is_exhumed = card.get("is_exhumed") == true
	if is_exhumed:
		append_to_exile(player_id, card_data)
		emit_signal("card_exiled", player_id, card)
		_emit_exile_changed(player_id)
		print("[CardManager] Carta exhumada '%s' desterrada (no vuelve al cementerio)" % card_data.get("nombre", "?"))
	else:
		_append_to_cemetery(player_id, card_data)
		if as_destroy:  # false: va al Cementerio por regla (Arma sin portador válido), no es Destruida
			emit_signal("card_destroyed", player_id, card)
		_update_cemetery_visual(player_id)

	# Desequipar ANTES de animar: compact_field_slots() corre de forma
	# síncrona dentro de animate_card_exile()/animate_card_to_cemetery()
	# (al reparentar la carta) y todavía mira equipped_weapons del portador
	# — si el Arma sigue ahí, le pisa la posición recién calculada y se ve
	# un salto visual antes de volar al cementerio/destierro.
	_unequip_from_wielder(card)

	var main_node = Engine.get_main_loop().root.get_node_or_null("Main") if Engine.get_main_loop() else null
	if main_node and main_node.get("_zone_manager") != null and is_instance_valid(card) and card.is_inside_tree() and card.visible:
		if is_exhumed:
			await main_node._zone_manager.animate_card_exile(card, player_id)
		else:
			await main_node._zone_manager.animate_card_to_cemetery(card, player_id)

	_disconnect_card_interaction_signals(card)
	card.queue_free()
	if main_node and main_node.get("_zone_manager") != null:
		main_node._zone_manager.call_deferred("compact_all_fields", true)


func take_from_cemetery(player_id: int, card_data: Dictionary) -> bool:
	"""Saca esa carta (por referencia) del Cementerio de player_id. Devuelve false si ya no estaba —
	atajo del bloque find/if idx < 0/remove que se repetía en los patrones (§62)."""
	var idx: int = get_cemetery(player_id).find(card_data)
	if idx < 0:
		return false
	remove_from_cemetery(player_id, idx)
	return true


func remove_from_cemetery(player_id: int, index: int = -1) -> Dictionary:
	"""Remueve una carta del cementerio (para Exhumar)

	Args:
		player_id: ID del jugador
		index: Índice de la carta (-1 = última/tope)

	Returns: Datos de la carta removida
	"""
	var cemetery = _zones[player_id].cemetery

	if cemetery.is_empty():
		return {}

	if index < 0:
		index = cemetery.size() - 1

	if index >= 0 and index < cemetery.size():
		var card_data = cemetery[index]
		cemetery.remove_at(index)
		_update_cemetery_visual(player_id)
		# Un Talismán con Exhumar jugado desde el Cementerio se Destierra por cualquier vía (usuario;
		# GoldManager._mark_cemetery_exhumar()). Si pasa por la mano, PlayerSide.put_in_hand() lo borra.
		card_data["_from_cemetery_turn"] = GameManager.turn_serial
		return card_data

	return {}


# =============================================================================
# MOVIMIENTO DE CARTAS - DESTIERRO
# =============================================================================
func exile_card(player_id: int, card: Node) -> void:
	"""Destierra una carta (la remueve del juego)"""
	await _move_equipped_weapons_with(player_id, card, exile_card)

	var card_data = card.card_data.duplicate() if card.get("card_data") else {}
	card_data["esta_oculta"] = false
	append_to_exile(player_id, card_data)

	emit_signal("card_exiled", player_id, card)
	_emit_exile_changed(player_id)

	# Ver comentario equivalente en destroy_card(): desequipar ANTES de
	# animar para que compact_field_slots() no le pise la posición al Arma
	# mientras aún aparece en equipped_weapons del portador.
	_unequip_from_wielder(card)

	var main_node = Engine.get_main_loop().root.get_node_or_null("Main") if Engine.get_main_loop() else null
	if main_node and main_node.get("_zone_manager") != null and is_instance_valid(card) and card.is_inside_tree() and card.visible:
		await main_node._zone_manager.animate_card_exile(card, player_id)

	_disconnect_card_interaction_signals(card)
	card.queue_free()
	if main_node and main_node.get("_zone_manager") != null:
		main_node._zone_manager.call_deferred("compact_all_fields", true)


func exhume_card(player_id: int, index: int = -1) -> Dictionary:
	"""Exhuma una carta del cementerio (DAR - Exhumar)

	La carta exhumada debe marcarse con is_exhumed = true al instanciarla.
	Cuando la carta deje el campo, irá al destierro en lugar de al cementerio.

	Returns: Datos de la carta exhumada (marcar is_exhumed al instanciar)
	"""
	var card_data = remove_from_cemetery(player_id, index)
	if not card_data.is_empty():
		# Marcar en los datos que fue exhumada (para referencia)
		card_data["_was_exhumed"] = true
		print("[CardManager] Carta '%s' exhumada del cementerio" % card_data.get("nombre", "?"))
	return card_data


# =============================================================================
# SISTEMA DE DAÑO (DAR 2025)
# =============================================================================
func take_damage(player_id: int, amount: int) -> Dictionary:
	"""Aplica daño a un jugador moviendo cartas del mazo al cementerio

	Args:
		player_id: ID del jugador que recibe daño
		amount: Cantidad de daño (cartas a mover)

	Returns: {
		requested: int,      # Daño solicitado
		actual: int,         # Daño real aplicado
		cards: Array,        # Cartas movidas al cementerio
		deck_empty: bool,    # Si el mazo quedó vacío
		defeated: bool       # Si el jugador perdió (mazo vacío después del daño)
	}
	"""
	var deck = _zones[player_id].deck
	var result = {
		"requested": amount,
		"actual": 0,
		"cards": [],
		"deck_empty": false,
		"defeated": false
	}

	if amount <= 0:
		return result

	# Mover cartas del tope del mazo al cementerio
	for i in range(amount):
		if deck.is_empty():
			result.deck_empty = true
			break

		# pop_front() = tope real (como ZoneManager.draw_card()): el daño de combate consume cartas del
		# tope del Castillo.
		var card_data = deck.pop_front()
		card_data["esta_oculta"] = false
		_append_to_cemetery(player_id, card_data)
		result.cards.append(card_data)
		result.actual += 1

	# Actualizar visuales
	_update_deck_visual(player_id)
	_update_cemetery_visual(player_id)

	# Verificar derrota
	if deck.is_empty():
		result.defeated = true
		emit_signal("deck_empty", player_id)

	# Emitir señal de daño
	emit_signal("damage_taken", player_id, result.actual, result.cards)

	# Log
	if Constants.VERBOSE_DIAG_LOGS:
		var card_names = result.cards.map(func(c): return c.get("nombre", "?"))
		print("[CardManager] Jugador %d recibe %d daño: %s" % [
			player_id, result.actual, card_names
		])

	# Log parcial si no se pudo hacer todo el daño. log_partial_damage espera target_name: String como
	# 3er parámetro (mismo formato que DamageManager._log_partial_damage()).
	if result.actual < result.requested:
		CombatLog.log_partial_damage(result.requested, result.actual, "Jugador %d" % (player_id + 1))

	return result


func mill_cards(player_id: int, amount: int) -> Dictionary:
	"""Muele cartas del mazo al cementerio (alias para take_damage sin ser daño)

	Usado para efectos que mueven cartas sin ser considerado daño
	"""
	return take_damage(player_id, amount)


# =============================================================================
# ACTUALIZACIÓN VISUAL (vía señales)
# =============================================================================
func _emit_deck_changed(player_id: int) -> void:
	"""Emite señal de cambio en el mazo"""
	var count = _zones[player_id].deck.size()
	emit_signal("deck_count_changed", player_id, count)


func _emit_cemetery_changed(player_id: int) -> void:
	"""Emite señal de cambio en el cementerio"""
	var count = _zones[player_id].cemetery.size()
	emit_signal("cemetery_count_changed", player_id, count)


func _emit_exile_changed(player_id: int) -> void:
	"""Emite señal de cambio en el destierro"""
	var count = _zones[player_id].exile.size()
	emit_signal("exile_count_changed", player_id, count)


# Aliases para compatibilidad
func _update_deck_visual(player_id: int) -> void:
	_emit_deck_changed(player_id)


func _update_cemetery_visual(player_id: int) -> void:
	_emit_cemetery_changed(player_id)
