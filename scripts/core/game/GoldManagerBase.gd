extends Node
## GoldManagerBase — base de GoldManager.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: GoldManagerBase <- GoldManagerPago <- GoldManagerColocar <- GoldManager. Lo de afuera usa solo GoldManager.gd (hereda todo).

## GoldManager — pago de costes y gestión de Oro (DAR Secciones 6 y 8). Hijo de Main; accede a sus
## nodos vía _main.
## Partes separadas: GoldManagerVisuals.gd (fichas y conteo de Oro), GoldManagerTax.gd (impuestos y
## descuentos de coste) y GoldManagerRestrictions.gd (elegibilidad para jugar una carta). Las
## funciones de una línea de abajo reenvían a esos módulos.
## Historia de cada decisión: docs/bitacora-codigo.md.

const GoldManagerVisualsScript = preload("res://scripts/core/game/GoldManagerVisuals.gd")

const GoldManagerTaxScript = preload("res://scripts/core/game/GoldManagerTax.gd")

const GoldManagerRestrictionsScript = preload("res://scripts/core/game/GoldManagerRestrictions.gd")

## Emitida cuando un jugador coloca un Oro de la mano en su Reserva (_place_card_as_gold; no el Oro
## que llega por efectos). count_this_turn = cuántos colocó ese jugador este turno (p.ej. Don de
## Amma: "su segundo Oro en juego este turno").
signal gold_placed(player_id: int, count_this_turn: int)

## Conteo de Oros colocados este turno, por jugador — se resetea en cada
## turno nuevo (_on_turn_started_clear_virtual_gold), sea de quien sea el
## turno, porque el conteo es "este turno", no "en mi turno".
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var oro_colocado_conteo: Dictionary = {0: 0, 1: 0}

## Oros puestos en juego este turno por cualquier vía (mano o efectos) — "si no has puesto Oros en
## juego este turno" (Patria Vieja). oro_colocado_conteo solo cuenta los de la mano.
var oros_en_juego_turno: Dictionary = {0: 0, 1: 0}

## Armería del Guerrero: "no pueden poner Oros en juego por efectos si ya lo hicieron durante esta
## partida". Vale toda la partida (no se reinicia por turno): una vez por jugador.
var _oro_por_efecto_used_game: Dictionary = {0: false, 1: false}

var _main: Node = null

## Oro Virtual por jugador ("genera un Oro por el turno", p.ej. Lobo Sagrado). Usar siempre
## oros_virtuales[id]; ver arquitectura.md §33.
var oros_virtuales: Dictionary = {0: 0, 1: 0}

## Fichas visuales del Oro Virtual en la Reserva, una por unidad, para que la Reserva muestre
## exactamente el Oro disponible. Por jugador.
var virtual_gold_tokens: Dictionary = {0: [], 1: []}

## Oro Virtual RESTRINGIDO por jugador ("genera un Oro para jugar Armas o Aliados Caballero", p.ej.
## Padre de la Patria, Legión Paladín): cada unidad solo paga cartas que cumplan su 'predicate'.
## Pueden coexistir varias fuentes, por eso cada valor es un Array de pools {amount, tokens,
## predicate, label}; predicate(card_type, card_race, card_cost) -> bool.
var restricted_gold_pools: Dictionary = {0: [], 1: []}

## "No puedes jugar más cartas este turno" (p.ej. Tempilcahue): bloquea toda jugada del jugador, Oro
## incluido, hasta que empieza un turno nuevo.
var _no_more_cards_this_turn: Dictionary = {0: false, 1: false}

var _visuals: RefCounted = null

var _tax: RefCounted = null

var _restrictions: RefCounted = null


func setup(main: Node) -> void:
	_main = main
	_visuals = GoldManagerVisualsScript.new()
	_visuals.setup(main)
	_tax = GoldManagerTaxScript.new()
	_tax.setup(main)
	_restrictions = GoldManagerRestrictionsScript.new()
	_restrictions.setup(main)
	# El Oro Virtual "por el turno" se limpia al empezar cada turno.
	if GameManager and GameManager.has_signal("turn_started"):
		if not GameManager.turn_started.is_connected(_on_turn_started_clear_virtual_gold):
			GameManager.turn_started.connect(_on_turn_started_clear_virtual_gold)
	if not GameManager.phase_changed.is_connected(_on_phase_changed_deck170):
		GameManager.phase_changed.connect(_on_phase_changed_deck170)
	if not GameManager.turn_started.is_connected(_on_turn_started_gold_events):
		GameManager.turn_started.connect(_on_turn_started_gold_events)  # Trono del Cielo
	if not GameManager.turn_started.is_connected(_on_turn_started_revert_converted):
		GameManager.turn_started.connect(_on_turn_started_revert_converted)  # Azi del Abismo
	# Reina Nyssara: Aliado oponente que sale del juego por un Talismán.
	if not _deck170_left_play_connected:
		_deck170_left_play_connected = true
		var deck170 = load("res://scripts/core/effects/triggers/Deck170Patterns.gd")
		CardManager.card_destroyed.connect(func(pid: int, card) -> void: deck170.on_card_left_play(pid, card))
		CardManager.card_exiled.connect(func(pid: int, card) -> void: deck170.on_card_left_play(pid, card))
		EffectController.on_card_returned_to_deck.connect(func(pid: int, card, _top: bool) -> void:
			deck170.on_card_left_play(pid, card))
		# Vlad el Empalador: "cuando este u otro de tus Aliados salga del juego".
		var vampire = load("res://scripts/core/effects/triggers/VampirePatterns.gd")
		CardManager.card_destroyed.connect(func(pid: int, card) -> void: vampire.on_card_left_play(pid, card))
		CardManager.card_exiled.connect(func(pid: int, card) -> void: vampire.on_card_left_play(pid, card))
		EffectController.on_card_returned_to_deck.connect(func(pid: int, card, _top: bool) -> void:
			vampire.on_card_left_play(pid, card))
		# ogun: "cuando este u otro Aliado entra en juego bajo tu control".
		var ally_events = load("res://scripts/core/effects/triggers/AllyEventTriggers.gd")
		EffectController.on_card_entered_play.connect(func(pid: int, card, _zone: int) -> void:
			ally_events.on_card_entered(pid, card))
		# Caos: "Cuando haga daño, convierte este Aliado en un Oro y ponlo a tu Oro Pagado".
		var caos_hit: Array = []
		var mark_caos := func(ally) -> void:
			if is_instance_valid(ally) and ally.get_meta("caos_ally", false) and int(ContinuousEffectManager.get_modified_strength(ally)) > 0:
				caos_hit.append(ally)
		BattleManager.unblocked_damage.connect(func(attacker, damage: int) -> void:
			if damage > 0:
				mark_caos.call(attacker))
		BattleManager.combat_pair_resolved.connect(func(attacker, blocker, _result) -> void:
			mark_caos.call(attacker)
			mark_caos.call(blocker))
		# martillo mjlnir: "si el portador hizo daño de combate este turno" (meta con el turno).
		var mark_combat_damage := func(ally) -> void:
			if is_instance_valid(ally) and int(ContinuousEffectManager.get_modified_strength(ally)) > 0 \
					and int(ally.get_meta("no_damage_turn", -1)) != GameManager.turn_serial:
				ally.set_meta("combat_damage_turn", GameManager.turn_serial)
		BattleManager.unblocked_damage.connect(func(attacker, damage: int) -> void:
			if damage > 0 and is_instance_valid(attacker):
				attacker.set_meta("combat_damage_turn", GameManager.turn_serial)
				attacker.set_meta("castle_damage_turn", GameManager.turn_serial))  # Los Señalados
		# nagaraja (robar el primer Aliado o Tótem que juegue el rival) y trapezoedro (tercera carta del rival).
		var ap8 = load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd")
		EffectController.on_card_entered_play.connect(func(pid: int, card, _zone: int) -> void:
			ap8.nagaraja_on_entered(pid, card)
			ap8.trapezoedro_on_put(_main, pid))
		GameManager.turn_started.connect(func(_p: int, _t: int) -> void: ap8.trapezoedro_turn_start())
		BattleManager.combat_pair_resolved.connect(func(attacker, blocker, _result) -> void:
			mark_combat_damage.call(attacker)
			mark_combat_damage.call(blocker))
		BattleManager.combat_finished.connect(func(_result) -> void:
			var hit: Array = caos_hit.duplicate()
			caos_hit.clear()
			for a in hit:
				load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").caos_back_to_gold(_main, a))
		# "(Hasta N veces) por turno, cuando ..." (LimitedEventTriggers).
		var limited = load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd")
		EffectController.on_card_entered_play.connect(func(pid: int, card, _zone: int) -> void:
			limited.on_card_entered(pid, card))
		CardManager.card_put_in_cemetery.connect(func(pid: int, data: Dictionary) -> void:
			limited.on_card_to_zone(pid, data, "cemetery"))
		CardManager.card_put_in_exile.connect(func(pid: int, data: Dictionary) -> void:
			limited.on_card_to_zone(pid, data, "exile"))
		CardManager.card_destroyed.connect(func(pid: int, card) -> void:
			if is_instance_valid(card) and card.get("card_type") == Constants.CardType.ARMA \
					and (card.get("controller_id") == null or int(card.controller_id) == pid):
				limited.fire("weapon_destroyed", {"pid": pid, "name": str(card.card_name)}))
		DamageManager.damage_dealt.connect(func(target_id: int, _amount: int, actual: int, _type: String) -> void:
			if target_id >= 0 and actual > 0:
				limited.fire("damage", {"pid": target_id, "amount": actual}))


func _on_phase_changed_deck170(new_phase) -> void:
	"""Escarapela Nacional: al comienzo de cada Vigilia, el rival del jugador activo puede ponerla en
	juego. Solo corre donde está la lógica (no en el Remoto)."""
	if new_phase != Constants.Phase.VIGILIA or not GameManager.is_game_active:
		return
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		return
	await load("res://scripts/core/effects/triggers/Deck170Patterns.gd").on_vigilia_started(GameManager.active_player_id)

var _deck170_left_play_connected := false

## "No puedes poner Oros en juego en tu próximo turno" (Escarapela Nacional):
## {player_id: "pending" | "active"}.
var _no_gold_turn: Dictionary = {}


func block_gold_next_turn(player_id: int) -> void:
	_no_gold_turn[player_id] = "pending"

## Armas de más: si un Aliado porta más Armas de las que hoy puede (Levisterio pierde la habilidad o
## sale del juego, Carro Szgany deja de apuntarle), se destruyen las que entraron primero
## (equipped_weapons está en orden de entrada). Se revisa cada 0.3 s, solo donde corre la lógica.
var _weapon_check_accum := 0.0

var _weapon_check_busy := false


func _process(delta: float) -> void:
	_weapon_check_accum += delta
	if _weapon_check_accum < 0.3 or _weapon_check_busy or not _main or not GameManager.is_game_active:
		return
	_weapon_check_accum = 0.0
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		return
	_enforce_weapon_capacity()


func _enforce_weapon_capacity() -> void:
	_weapon_check_busy = true
	for field in [_main.player_field, _main.player_linea_ataque, _main.opponent_field, _main.opponent_linea_ataque]:
		if not field:
			continue
		for ally in field.get_children():
			if not is_instance_valid(ally) or ally.get("card_type") != Constants.CardType.ALIADO:
				continue
			var weapons = ally.get("equipped_weapons")
			if not (weapons is Array):
				continue
			var live: Array = weapons.filter(func(w): return is_instance_valid(w))
			var extra: int = live.size() - _restrictions._max_weapons_for(ally, false)
			for i in range(maxi(extra, 0)):
				var w: Node = live[i]
				# DAR (Portar): un Arma sin portador válido es enviada al Cementerio (no es Destruida).
				_main._update_debug("%s no puede portar %s: va al Cementerio" % [
					str(ally.get("card_name")), str(w.get("card_name"))])
				await EffectController.send_to_cemetery_by_rule(w)
	_weapon_check_busy = false


func _on_turn_started_clear_virtual_gold(_player_id: int, _turn: int) -> void:
	for pid in _no_gold_turn.keys():
		if _no_gold_turn[pid] == "pending" and _player_id == pid:
			_no_gold_turn[pid] = "active"
		elif _no_gold_turn[pid] == "active" and _player_id != pid:
			_no_gold_turn.erase(pid)
	limpiar_oros_virtuales()
	limpiar_oro_restringido(_player_id)
	for pid in [0, 1]:
		_clear_next_talisman_buff(pid)  # Rey de los Loñolicos: "este turno"
	oro_colocado_conteo = {0: 0, 1: 0}
	oros_en_juego_turno = {0: 0, 1: 0}
	_no_more_cards_this_turn = {0: false, 1: false}


func set_no_more_cards_this_turn(player_id: int) -> void:
	_no_more_cards_this_turn[player_id] = true
	print("[GoldManager] J%d ya no puede jugar más cartas este turno" % (player_id + 1))


func _no_more_cards_violation(card: Node) -> bool:
	var player_id: int = card.controller_id if card.get("controller_id") != null else 0
	return _no_more_cards_this_turn.get(player_id, false)


func _quinto_sello_cap_violation() -> bool:
	"""Quinto Sello ("si está en tu Cementerio, no se pueden jugar más de cinco cartas por turno"):
	tope global, mira los dos Cementerios. Solo se aplica a play_card() (mano); jugar desde el
	Destierro, el Cementerio o gratis no lo revisa todavía (arquitectura.md §12.5)."""
	if TurnManager.cards_played_count_this_turn < 5:
		return false
	for pid in [0, 1]:
		var cemetery: Array = CardManager.get_cemetery(pid)
		if cemetery.any(func(d): return String(d.get("nombre", "")).to_lower() == "quinto sello"):
			return true
	return false

## Candado por carta (instance_id) — "elige una carta de ahí que no sea Oro para que no pueda ser
## jugada hasta tu próximo turno" (p.ej. Chakram). Se limpia al empezar el próximo turno de quien lo
## puso.
var _play_locked_cards: Dictionary = {}


func lock_card_from_playing(card: Node, locking_player_id: int) -> void:
	if not is_instance_valid(card):
		return
	var id := card.get_instance_id()
	_play_locked_cards[id] = true
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Carta"
	print("[GoldManager] %s no puede jugarse hasta el próximo turno de J%d" % [card_name, locking_player_id + 1])
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != locking_player_id:
			return
		_play_locked_cards.erase(id)
		if GameManager.turn_started.is_connected(clear_it):
			GameManager.turn_started.disconnect(clear_it)
	GameManager.turn_started.connect(clear_it)


func _responding_to_opponent(player_id: int) -> bool:
	"""¿Hay ahora una ventana de respuesta abierta sobre algo que jugó o
	activó el rival de 'player_id'? (Talismanes de Anular/Cancelar.)"""
	return PriorityManager.priority_window_active \
		and PriorityManager.current_priority_context == PriorityManager.PriorityContext.RESPONSE_WINDOW \
		and PriorityManager.current_stack_controller == 1 - player_id


func _card_play_locked(card: Node) -> bool:
	if _play_locked_cards.get(card.get_instance_id(), false):
		return true
	var pid: int = card.owner_id if card.get("owner_id") != null else 0
	# Perugia: "durante los próximos dos turnos, los jugadores sólo pueden jugar una carta de cada tipo por turno".
	# trofeo de cazador: "tu oponente sólo puede jugar un Talismán en esta Vigilia".
	if card.get("card_type") == Constants.CardType.TALISMAN and not RuleState.turn_data("one_talisman:%d" % pid).is_empty() \
			and RuleState.count("played_type:%d" % Constants.CardType.TALISMAN, pid) >= 1:
		return true
	# anillo de tierra: "Tu oponente sólo puede jugar una carta más o utilizar una habilidad más por el turno".
	if card.get("card_type") != Constants.CardType.ORO and not one_more_action_left(pid):
		return true
	# Pereza: "no puedes jugar más de una carta por turno" (los próximos dos turnos).
	if card.get("card_type") != Constants.CardType.ORO and RuleState.active("one_card_turn", pid) \
			and RuleState.count("played_any", pid) >= 1:
		return true
	# Iluminar el Camino: "Tu oponente sólo puede jugar una carta más de ese mismo tipo este turno".
	var iluminar: Dictionary = RuleState.turn_data("iluminar:%d" % pid)
	if not iluminar.is_empty() and card.get("card_type") != Constants.CardType.ORO:
		if int(card.get("card_type")) != int(iluminar.type) 				or RuleState.count("played_type:%d" % int(iluminar.type), pid) >= int(iluminar.allowed):
			return true
	# aklo sabaoth: "...sólo se puede jugar hasta dos cartas de cada tipo por turno".
	if card.get("card_type") != Constants.CardType.ORO:
		var played_same: int = RuleState.count("played_type:%d" % int(card.get("card_type")), pid)
		if (RuleState.active("one_per_type", pid) and played_same >= 1) or (RuleState.active("two_per_type", pid) and played_same >= 2):
			return true
	# huaso bueras: "no se puede jugar cartas de ese coste hasta tu próximo turno" (los Oros no se juegan).
	if card.get("card_type") != Constants.CardType.ORO and card.get("card_cost") != null \
			and RuleState.active("cost_play_lock:%d" % int(card.card_cost), pid):
		return true
	return is_name_play_locked(pid, str(card.get("card_name")), int(card.get("card_type")))

## Candado por nombre (Zadquiel: "nombra una carta. Esa carta no puede ser jugada hasta tu próximo
## turno"): toda copia con ese nombre del jugador afectado, en cualquier zona. Los Oros no se juegan
## (se ponen en juego), así que no les aplica. Clave "jugador|nombre"; se limpia al empezar el
## próximo turno de quien lo puso.
var _play_locked_names: Dictionary = {}


func lock_name_from_playing(card_name: String, target_player_id: int, locking_player_id: int) -> void:
	var key := "%d|%s" % [target_player_id, card_name.strip_edges().to_lower()]
	_play_locked_names[key] = true
	print("[GoldManager] '%s' no puede jugarse (J%d) hasta el próximo turno de J%d" % [card_name, target_player_id + 1, locking_player_id + 1])
	var clear_it: Callable
	clear_it = func(started_player_id: int, _turn: int) -> void:
		if started_player_id != locking_player_id:
			return
		_play_locked_names.erase(key)
		if GameManager.turn_started.is_connected(clear_it):
			GameManager.turn_started.disconnect(clear_it)
	GameManager.turn_started.connect(clear_it)


func is_name_play_locked(player_id: int, card_name: String, card_type: int = -1) -> bool:
	if card_type == Constants.CardType.ORO or _play_locked_names.is_empty():
		return false
	return _play_locked_names.has("%d|%s" % [player_id, card_name.strip_edges().to_lower()])

## Trono del Cielo: Oros puestos en juego o generados por cada jugador en su turno; al empezar el
## turno siguiente pasan a "_prev".
var _gold_events_turn: Dictionary = {0: 0, 1: 0}

var _gold_events_prev: Dictionary = {0: 0, 1: 0}


func _note_gold_event(player_id: int, amount: int = 1) -> void:
	if GameManager.active_player_id == player_id:
		_gold_events_turn[player_id] = int(_gold_events_turn.get(player_id, 0)) + amount


func _on_turn_started_gold_events(started_player_id: int, _turn: int) -> void:
	var prev: int = 1 - started_player_id
	_gold_events_prev[prev] = int(_gold_events_turn.get(prev, 0))
	_gold_events_turn[prev] = 0


func _register_gold_placed(player_id: int) -> void:
	"""Punto único de conteo para gold_placed — llamar SOLO desde la acción
	real de 'Colocar un Oro' (_place_card_as_gold, DAR: un Oro de la mano
	a la Reserva, la acción que Don de Amma cuenta), no desde Oro que
	llega por búsqueda/efecto (put_gold_directly_in_reserva/_en_pagado —
	esos son otro verbo del DAR, no 'poner en juego' el Oro del turno).
	Dispara el chequeo reactivo de 'cuando tu oponente ponga su segundo
	Oro' contra el OTRO jugador."""
	oro_colocado_conteo[player_id] = oro_colocado_conteo.get(player_id, 0) + 1
	oros_en_juego_turno[player_id] = oros_en_juego_turno.get(player_id, 0) + 1
	_note_gold_event(player_id)
	gold_placed.emit(player_id, oro_colocado_conteo[player_id])
	_check_reactive_second_gold_triggers(player_id)


func _check_reactive_second_gold_triggers(placer_id: int) -> void:
	"""Don de Amma: "cuando tu oponente ponga su segundo Oro en juego este turno, puedes poner este
	Oro desde tu mano o Cementerio en tu Oro Pagado". Solo cuenta el segundo Oro exacto de
	placer_id. Solo se le pregunta al jugador humano (reactor_id == 0). Límite: solo
	_place_card_as_gold() registra Oros colocados."""
	var reactor_id: int = 1 - placer_id
	if oro_colocado_conteo.get(placer_id, 0) != 2:
		return
	if reactor_id != 0:
		return
	var candidates: Array = []
	for card_data in _main.player_hand.cards.map(func(c): return c.card_data):
		candidates.append({"data": card_data, "from": "mano"})
	for card_data in CardManager.get_cemetery(reactor_id):
		candidates.append({"data": card_data, "from": "cementerio"})
	for entry in candidates:
		var card_data: Dictionary = entry.data
		if card_data.get("tipo", -1) != Constants.CardType.ORO:
			continue
		var ability_lower := _fix_mojibake(str(card_data.get("habilidad", ""))).to_lower()
		if not ("segundo oro" in ability_lower and "oro pagado" in ability_lower):
			continue
		_offer_reactive_second_gold_to_pagado(reactor_id, card_data, entry.from)


func _offer_reactive_second_gold_to_pagado(reactor_id: int, card_data: Dictionary, from_zone: String) -> void:
	"""Ofrece mover UNA carta específica (ya confirmada como el patrón de
	Don de Amma) desde mano/Cementerio directo a Oro Pagado — reutiliza
	SelectionManager con un solo candidato como diálogo sí/no (clickearla =
	aceptar, Cancelar = declinar; mismo patrón 'puedes' que el resto de
	esta familia)."""
	# Sin botón Confirmar: con un solo candidato, clickear la carta ya acepta. min_selections = 0 para
	# que confirmar sin elegir no deje el panel colgado.
	var confirm_btn = SelectionManager.get("_confirm_button")
	if confirm_btn:
		confirm_btn.visible = false
	var accepted: Dictionary = await SelectionManager.await_single_pick(
		[card_data], "%s: puedes ponerlo en tu Oro Pagado (tu oponente ya puso su 2do Oro)" % card_data.get("nombre", "Oro"), true, 0)
	if confirm_btn:
		confirm_btn.visible = true
	if accepted.is_empty():
		return

	if from_zone == "mano":
		var hand_card: Node = null
		for c in _main.player_hand.cards:
			if c.card_data == card_data:
				hand_card = c
				break
		if hand_card:
			var idx = _main.player_hand.cards.find(hand_card)
			if idx >= 0:
				_main.player_hand.cards.remove_at(idx)
			_main.player_hand.remove_child(hand_card)
			_main.player_hand._arrange_cards()
			hand_card.queue_free()
	else:
		var cemetery: Array = CardManager.get_cemetery(reactor_id)
		var idx: int = cemetery.find(card_data)
		if idx >= 0:
			CardManager.remove_from_cemetery(reactor_id, idx)

	await put_gold_directly_in_pagado(reactor_id, card_data)


func put_gold_directly_in_pagado(player_id: int, card_data: Dictionary) -> Node:
	"""Pone un Oro directo en el Oro Pagado de un jugador (entra ya gastado; p.ej. Don de Amma)."""
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return null
	oros_en_juego_turno[player_id] = oros_en_juego_turno.get(player_id, 0) + 1
	_note_gold_event(player_id)
	var data: Dictionary = card_data.duplicate()
	data["esta_oculta"] = false
	var card_node = _main._create_card(data)
	card_node.owner_id = player_id
	card_node.can_interact = true
	card_node.scale = Constants.GOLD_CARD_SCALE
	card_node.base_scale = Constants.GOLD_CARD_SCALE
	_main._connect_card_signals(card_node)
	var target_container: HBoxContainer = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	target_container.add_child(card_node)
	card_node.top_level = false
	card_node.modulate = Color(0.6, 0.6, 0.6, 1.0)
	card_node.set_zone(Constants.Zone.ORO_PAGADO)
	GameState.agregar_oro_pagado(player_id, 1)
	if player_id == 0:
		_main.gold_cards.append(card_node)
	await _trigger_enter_play(card_node, Constants.Zone.ORO_PAGADO)
	return card_node


func _refresh_dynamic_strength_badges(player_id: int) -> void:
	"""Invalida el caché de ContinuousEffectManager y refresca el badge de Fuerza de los Aliados de
	player_id. Hace falta para bonos dinámicos (Manuel Bulnes: "N de Fuerza por cada Arma que
	controles"): equipar un Arma en otro Aliado no toca su modificador, y el caché no se enteraba.
	Llamar cuando puede cambiar la cantidad de Armas equipadas."""
	if ContinuousEffectManager.has_method("_invalidate_cache"):
		ContinuousEffectManager._invalidate_cache()
	var fields = [_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo] if player_id == 0 \
		else [_main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo]
	for field in fields:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and c.has_method("refresh_strength_badge"):
				c.refresh_strength_badge()


func _fix_mojibake(text: String) -> String:
	"""Corrige la doble codificación UTF-8→Latin-1→UTF-8 que trae la API para algunas cartas
	('TalismÃ¡n' → 'Talismán'). Solo vocales con tilde y ñ. El orden importa: los reemplazos de dos
	caracteres antes que la 'Ã' suelta."""
	var fixed := text
	fixed = fixed.replace("Ã¡", "á")
	fixed = fixed.replace("Ã©", "é")
	fixed = fixed.replace("Ã­", "í")
	fixed = fixed.replace("Ã³", "ó")
	fixed = fixed.replace("Ãº", "ú")
	fixed = fixed.replace("Ã±", "ñ")
	fixed = fixed.replace("Ã¼", "ü")
	fixed = fixed.replace("Ã‰", "É")
	fixed = fixed.replace("Ã", "Á")
	return fixed


## Impuestos de coste y descuento por "muestra X": el cuerpo está en GoldManagerTax.gd. Reenvíos de
## una línea (se llaman desde play_card()/_trigger_enter_play()).
func _register_talisman_totem_tax(card: Node) -> void:
	_tax._register_talisman_totem_tax(card)


func _register_talisman_second_play_tax(card: Node) -> void:
	_tax._register_talisman_second_play_tax(card)


func _check_primer_sello_cemetery_trigger(card: Node, controller_id: int) -> void:
	"""Primer Sello ("si está en tu Cementerio, una vez por turno, cuando juegues una carta Sello, tu
	oponente Bota una carta"): habilidad desde el Cementerio; se engancha aquí porque toda carta
	jugada pasa por este punto antes de su "Cuando entra en juego" (arquitectura.md §1). "Sello" se
	reconoce por el nombre (no es una Raza). Cuenta también otra copia de Primer Sello."""
	if not is_instance_valid(card):
		return
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else ""
	if not ("sello" in card_name.to_lower()):
		return
	var cemetery: Array = CardManager.get_cemetery(controller_id)
	var has_primer_sello: bool = cemetery.any(func(d): return String(d.get("nombre", "")).to_lower() == "primer sello")
	if not has_primer_sello:
		return
	var registry_key: String = "primer_sello_cemetery:%d" % controller_id
	if UniversalCardParser.turn_registry.was_used(registry_key, 0, GameManager.turn_serial):
		return
	UniversalCardParser.turn_registry.register(registry_key, 0, GameManager.turn_serial)
	await ActionModule.mill(1 - controller_id, 1, false, "Primer Sello (Cementerio)", true)


func _check_los_siete_sellos_trigger(card: Node, controller_id: int) -> void:
	"""Los Siete Sellos (Oro): "Hasta dos veces por turno, cuando se resuelva el efecto de uno de tus
	Talismanes Sello, tu oponente Bota dos cartas". Se llama solo cuando un Talismán terminó de
	resolverse; Los Siete Sellos tiene que estar en la Reserva del mismo jugador. "No puede ser
	convertido" lo cubre la protección genérica de Convertir. "No pagas costes adicionales..." no
	está implementado (arquitectura.md §12.5)."""
	if not is_instance_valid(card):
		return
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else ""
	if not ("sello" in card_name.to_lower()):
		return
	var reserva: Array = _main.gold_cards if controller_id == 0 else _main.opponent_gold.get_children() if _main.get("opponent_gold") else []
	var has_los_siete_sellos: bool = false
	for g in reserva:
		if is_instance_valid(g) and g.get("owner_id") == controller_id and g.get("current_zone") == Constants.Zone.RESERVA_ORO:
			var g_name: String = str(g.get("card_name")) if g.get("card_name") != null else ""
			if g_name.to_lower() == "los siete sellos":
				has_los_siete_sellos = true
				break
	if not has_los_siete_sellos:
		return
	# "Hasta dos veces por turno" — turn_registry.was_used()/register() solo
	# soportan un booleano "una vez por turno" (ver su propia definición en
	# UniversalCardParser.gd), así que el tope de 2 usa DOS claves separadas
	# en vez de extender la clase compartida para un único caso.
	var key_1: String = "los_siete_sellos_1:%d" % controller_id
	var key_2: String = "los_siete_sellos_2:%d" % controller_id
	if not UniversalCardParser.turn_registry.was_used(key_1, 0, GameManager.turn_serial):
		UniversalCardParser.turn_registry.register(key_1, 0, GameManager.turn_serial)
	elif not UniversalCardParser.turn_registry.was_used(key_2, 0, GameManager.turn_serial):
		UniversalCardParser.turn_registry.register(key_2, 0, GameManager.turn_serial)
	else:
		return
	await ActionModule.mill(1 - controller_id, 2, false, "Los Siete Sellos", true)


func _check_llave_del_abismo_enter_aura(card: Node, controller_id: int) -> void:
	"""Llave del Abismo: "Tus Aliados ganan 1 de Fuerza e Indestructible" — aura permanente mientras
	esté en juego, como arco del triunfo. Se engancha aquí porque no tiene un "Cuando entra en
	juego" propio. Se limpia sola al salir (Card._exit_tree())."""
	if not is_instance_valid(card):
		return
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else ""
	if card_name.to_lower() != "llave del abismo":
		return
	ContinuousEffectManager.register_modifier({
		"source": card, "target": "ALLIES",
		"filter": {"type": Constants.CardType.ALIADO},
		"type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
		"value": 1, "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"static_ability": true,
		"description": "Llave del Abismo: +1 Fuerza a tus Aliados"
	})
	ContinuousEffectManager.register_modifier({
		"source": card, "target": "ALLIES",
		"filter": {"type": Constants.CardType.ALIADO},
		"type": ContinuousEffectManager.ModifierType.KEYWORDS, "stat": "",
		"value": 0, "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"static_ability": true,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_6_ABILITIES,
		"keywords_add": [Constants.Keyword.INDESTRUCTIBLE],
		"description": "Llave del Abismo: Indestructible a tus Aliados"
	})


func _check_llave_del_abismo_reactive(card: Node, controller_id: int) -> void:
	"""Llave del Abismo: "Cuando un Aliado con Furia entra en juego bajo tu control, tu oponente Bota
	una carta. Puedes utilizar esta habilidad más de una vez por turno". Chequeo directo sobre la
	carta recién jugada (el texto "con Furia ... bajo tu control" no calza con
	Card.TRIGGER_KEYWORDS). Sin tope por turno."""
	if not is_instance_valid(card):
		return
	if card.get("card_type") != Constants.CardType.ALIADO:
		return
	if not KeywordManager.has_keyword(card, Constants.Keyword.FURIA):
		return
	var ally_controller: int = card.get("owner_id") if card.get("owner_id") != null else controller_id
	var reserva: Array = _main.gold_cards if ally_controller == 0 else (_main.opponent_gold.get_children() if _main.get("opponent_gold") else [])
	var pagado: Array = _main.player_oro_pagado.get_children() if ally_controller == 0 and _main.get("player_oro_pagado") else \
		(_main.opponent_oro_pagado.get_children() if ally_controller == 1 and _main.get("opponent_oro_pagado") else [])
	var has_llave: bool = false
	for g in reserva + pagado:
		if is_instance_valid(g) and str(g.get("card_name")).to_lower() == "llave del abismo":
			has_llave = true
			break
	if not has_llave:
		return
	await ActionModule.mill(1 - ally_controller, 1, false, "Llave del Abismo", true)


## Manicomio: "Para jugar un Aliado de coste 2 o menos, debe lanzarse un dado de seis caras. Si sale
## impar, no dispara sus habilidades al entrar en juego." (meta "skip_enter_triggers", que mira
## TriggerSystem). Con un Manicomio en juego de cualquier jugador.
func _roll_manicomio_die(card: Node) -> void:
	if card.get("card_type") != Constants.CardType.ALIADO or card.get("card_cost") == null or int(card.card_cost) > 2:
		return
	var CardQuery = load("res://scripts/core/effects/mechanics/CardQuery.gd")
	var phrase := "para jugar un aliado de coste 2 o menos, debe lanzarse un dado de seis caras"
	if CardQuery.cards_in_play_with(0, phrase).is_empty() and CardQuery.cards_in_play_with(1, phrase).is_empty():
		return
	var roll: int = randi_range(1, 6)
	_main._update_debug("Manicomio: dado para %s → %d%s" % [str(card.get("card_name")), roll,
		" (impar: no dispara sus habilidades al entrar)" if roll % 2 == 1 else ""])
	if CombatLog and CombatLog.has_method("log_action"):
		CombatLog.log_action("Manicomio: dado para %s → %d" % [str(card.get("card_name")), roll])
	if roll % 2 == 1:
		card.set_meta("skip_enter_triggers", true)


func _trigger_enter_play(card: Node, zone: int = Constants.Zone.LINEA_DEFENSA) -> bool:
	"""Entrada al juego (DAR 7.4): dispara los "Cuando entra en juego" de Aliados, Armas, Oros y
	Tótems. Los Talismanes no disparan: se resuelven directo con TriggerSystem.resolve_talisman()
	(ver la rama de abajo), y no pasan por CardFactory.on_card_enters_play() ni
	Card.on_entered_play() (no entran en juego, DAR Sección 8).
	El trigger se llama directo con await (no por señal) para que el juego no avance de fase
	mientras se resuelve. CardEffectSystem sigue escuchando la señal solo para recalcular efectos
	continuos. No usa EffectController.play_card_to_zone() (depende de un GameBoard que ya no
	existe)."""
	var _sello_controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
	await _check_primer_sello_cemetery_trigger(card, _sello_controller_id)
	# Llave del Abismo: registra su aura al entrar ella y reacciona cuando otro Aliado con Furia entra
	# bajo el mismo controlador (ver ambas funciones).
	_check_llave_del_abismo_enter_aura(card, _sello_controller_id)
	await _check_llave_del_abismo_reactive(card, _sello_controller_id)
	# Quinto Sello ("no se pueden jugar más de cinco cartas por turno", ver
	# TurnManager.cards_played_count_this_turn) — se cuenta aquí, el único
	# choke point real por el que pasa TODA carta jugada, para que el gateo
	# en play_card() (que corre ANTES de llegar aquí) siempre vea el conteo
	# de las cartas ya jugadas, sin contar la que se está resolviendo ahora.
	TurnManager.cards_played_count_this_turn += 1
	PaymentManager.consume_next_card_surcharge(_sello_controller_id, card)  # fuma kotaro
	_roll_manicomio_die(card)
	# Perugia ("una carta de cada tipo por turno") y argos ("la primera carta de coste 1 o menos que
	# ponga en juego cada jugador en cada turno"): contadores del turno en RuleState.
	if card.get("card_type") != Constants.CardType.ORO:
		RuleState.add("played_type:%d" % int(card.get("card_type")), _sello_controller_id)
		if card.get("card_type") == Constants.CardType.ALIADO and int(card.get("card_cost")) >= 2:
			RuleState.add("ally2_played", _sello_controller_id)  # fusil patriota
		RuleState.add("played_any", _sello_controller_id)
		if card.get("card_cost") != null and int(card.card_cost) <= 1:
			RuleState.add("cheap_put", _sello_controller_id)
	if card.get("card_type") == Constants.CardType.ALIADO and _sello_controller_id == GameManager.active_player_id:
		TurnManager.ally_played_serial[_sello_controller_id] = GameManager.turn_serial

	if card.get("card_type") == Constants.CardType.TALISMAN:
		_register_talisman_totem_tax(card)
		_register_talisman_second_play_tax(card)
		var origin: String = "Exhumar (Cementerio → Destierro)" if card.get("is_exhumed") == true else "mano"
		print("[GoldManager] %s resuelve su efecto (Talismán, jugado desde %s)" % [
			card.card_name if card.get("card_name") else "Carta", origin
		])
		# Un Talismán no dispara: su texto ES el efecto de jugarlo y se resuelve directo (DAR Sección 8).
		# resolve_talisman() abre antes su ventana de respuesta y devuelve true si lo anularon/cancelaron,
		# para que _play_talisman() lo mande al Cementerio.
		var limited_t = load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd")
		limited_t.fire("card_played", {"card": card, "pid": _sello_controller_id})  # jane eyre
		var talisman_name: String = str(card.card_name)
		var talisman_owner: int = int(card.owner_id) if card.get("owner_id") != null else _sello_controller_id
		var _was_annulled_or_cancelled: bool = await TriggerSystem.resolve_talisman(card)
		# Los Siete Sellos: solo si el efecto del Sello se resolvió de verdad (no si lo
		# anularon/cancelaron).
		if not _was_annulled_or_cancelled:
			await _check_los_siete_sellos_trigger(card, _sello_controller_id)
			limited_t.fire("talisman_resolved", {"pid": _sello_controller_id, "name": talisman_name, "owner": talisman_owner})  # baron de gossler
		return _was_annulled_or_cancelled

	# CARD_PLAYED para Aliado/Arma/Tótem/Oro (Pila de Respuesta Universal): la carta ya está en una
	# zona de juego cuando se abre la ventana. Aproximación acordada con el usuario: si la anulan aquí,
	# su "Cuando entra en juego" nunca dispara y va al Cementerio.
	var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
	# Dhampir ("Cuando tu oponente juegue una carta"): los Oros se ponen en juego, no se juegan.
	if card.get("card_type") != Constants.CardType.ORO:
		load("res://scripts/core/effects/triggers/VampirePatterns.gd").on_card_played(card, controller_id)
		load("res://scripts/core/effects/triggers/AllyEventTriggers.gd").on_card_played(card, controller_id)  # troll soberano
		load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("card_played", {"card": card, "pid": controller_id})  # yaldabaoth
	if _alicanto_paid_pending.get(controller_id, false):
		_alicanto_paid_pending.erase(controller_id)
		if card.get("card_type") == Constants.CardType.ALIADO:
			card.set_meta("protected_from_annul_this_turn", true)  # Alicanto
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card.get("card_name") else "", controller_id):
		if card.get_meta("annul_to_exile", false):  # p.ej. Red de Plata, Culto a la Muerte
			await EffectController.exile_card(card.owner_id if card.get("owner_id") != null else controller_id, card, true)
		else:
			await EffectController.destroy_card(controller_id, card, false)
		_update_gold_display()
		_main._update_buttons_for_phase(GameManager.current_phase)
		return true

	CardFactory.on_card_enters_play(card)
	if card.has_method("on_entered_play"):
		card.on_entered_play()
	_register_talisman_totem_tax(card)
	_register_talisman_second_play_tax(card)
	# controller_id (no 0 fijo): GameStateBroadcaster decide "propia"/"rival" con este player_id; con 0
	# fijo, un Arma del Remoto se mostraba como del Anfitrión.
	EffectController.emit_signal("on_card_entered_play", controller_id, card, zone)
	_refresh_dynamic_strength_badges(controller_id)

	await TriggerSystem._collect_triggers_for_event("on_enter_play", {
		"player_id": controller_id, "card": card, "zone": zone
	})

	# Almirante Akari ("cuando tu oponente juegue cartas, puedes Anular"): se ofrece después del ETB,
	# por si Akari no estuvo en la ventana genérica de arriba; offer_counter_annul() no pregunta dos
	# veces.
	await EffectController.offer_counter_annul(card)
	await EffectController.offer_flechar_xoon_annul(card)
	return false

## Rey de los Loñolicos: "El próximo Talismán que juegues este turno reduce su coste en un Oro,
## hasta un mínimo de 1 y no puede ser Anulado". Por jugador: {token (fuente del modificador de
## coste), no_annul, turn}. Se consume en _play_talisman() y vence al cambiar de turno.
var _next_talisman_buffs: Dictionary = {}


func _clear_next_talisman_buff(player_id: int) -> void:
	var buff: Dictionary = _next_talisman_buffs.get(player_id, {})
	if buff.is_empty():
		return
	_next_talisman_buffs.erase(player_id)
	PaymentManager.remover_modificador_coste(buff.token)
	if is_instance_valid(buff.token):
		buff.token.queue_free()


func _update_gold_display() -> void:
	_visuals._update_gold_display()


func update_gold_containers_spacing() -> void:
	_visuals.update_gold_containers_spacing()


## anillo de tierra: turn_data "one_more_action:<jugador>" = {cards, abilities} contados al jugarlo; queda
## una acción más (jugar una carta o utilizar una habilidad).
static func one_more_action_left(pid: int) -> bool:
	var base: Dictionary = RuleState.turn_data("one_more_action:%d" % pid)
	if base.is_empty():
		return true
	var used: int = (RuleState.count("played_any", pid) - int(base.cards)) + (RuleState.count("abilities_used", pid) - int(base.abilities))
	return used < 1

var _alicanto_paid_pending: Dictionary = {}


func limpiar_oros_virtuales() -> void:
	# Limpia a los dos jugadores: el "Oro por el turno" vence al empezar cualquier turno, sea de quien
	# sea.
	for player_id in [0, 1]:
		if oros_virtuales.get(player_id, 0) <= 0:
			continue
		_main._update_debug("Oros Virtuales expirados: %d" % oros_virtuales[player_id])
		oros_virtuales[player_id] = 0
		var reserva_container: HBoxContainer = _main.player_gold if player_id == 0 else _main.opponent_gold
		var tokens_to_clear = virtual_gold_tokens.get(player_id, []).duplicate()
		virtual_gold_tokens[player_id] = []
		for token in tokens_to_clear:
			if is_instance_valid(token):
				var tw = create_tween()
				tw.set_parallel(true)
				tw.tween_property(token, "modulate:a", 0.0, 0.20)
				tw.tween_property(token, "position:y", token.position.y - 15.0, 0.20)
				tw.finished.connect(func():
					if is_instance_valid(token):
						if token.get_parent() == reserva_container:
							reserva_container.remove_child(token)
						token.queue_free()
						update_gold_containers_spacing()
				)
	_update_gold_display()


func limpiar_oro_restringido(started_player_id: int = -1) -> void:
	# Limpia AMBOS jugadores siempre — mismo motivo que limpiar_oros_virtuales().
	# Excepción: los pools "hasta tu próximo turno" (until_player) solo
	# expiran cuando empieza el turno de ese jugador.
	for player_id in [0, 1]:
		var all_pools: Array = restricted_gold_pools.get(player_id, [])
		var pools_to_clear: Array = []
		var kept: Array = []
		for pool in all_pools:
			var until: int = int(pool.get("until_player", -1))
			if until >= 0 and until != started_player_id:
				kept.append(pool)
			else:
				pools_to_clear.append(pool)
		if pools_to_clear.is_empty():
			continue
		restricted_gold_pools[player_id] = kept
		var reserva_container: HBoxContainer = _main.player_gold if player_id == 0 else _main.opponent_gold
		_main._update_debug("Oro Virtual restringido expirado (%d pool(s))" % pools_to_clear.size())
		for pool in pools_to_clear:
			for token in pool.tokens:
				if is_instance_valid(token):
					var tw = create_tween()
					tw.set_parallel(true)
					tw.tween_property(token, "modulate:a", 0.0, 0.20)
					tw.tween_property(token, "position:y", token.position.y - 15.0, 0.20)
					tw.finished.connect(func():
						if is_instance_valid(token):
							if token.get_parent() == reserva_container:
								reserva_container.remove_child(token)
							token.queue_free()
							update_gold_containers_spacing()
					)
	_update_gold_display()


func revert_converted_golds(pid: int) -> void:
	"""Al empezar el turno de 'pid': sus Oros convertidos "hasta tu próximo
	turno" vuelven a ser el Aliado original en su Línea de Defensa."""
	for container in [PlayerSideScript.gold_reserva(_main, pid), PlayerSideScript.oro_pagado(_main, pid)]:
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and int(c.get_meta("converted_until_turn_of", -1)) == pid:
				await _revert_converted_gold(c, pid)


func _revert_converted_gold(card: Node, pid: int) -> void:
	var original: Dictionary = card.get_meta("converted_original_data", {})
	card.remove_meta("converted_until_turn_of")
	card.remove_meta("converted_original_data")
	if original.is_empty():
		return
	var parent = card.get_parent()
	if parent == PlayerSideScript.gold_reserva(_main, pid):
		GameState.agregar_oro_reserva(pid, -1)
	elif parent == PlayerSideScript.oro_pagado(_main, pid):
		GameState.agregar_oro_pagado(pid, -1)
	if pid == 0:
		_main.gold_cards.erase(card)
	var start_pos: Vector2 = card.global_position
	if parent:
		parent.remove_child(card)
	card.can_interact = false
	card.load_from_data(original)
	var field: Node = _main.player_field if pid == 0 else _main.opponent_field
	field.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	card.modulate = Color(1, 1, 1, 1)
	ContinuousEffectManager._register_card_continuous_effects(card)
	ContinuousEffectManager._invalidate_cache()
	update_gold_containers_spacing()
	_update_gold_display()
	await get_tree().process_frame
	var end_pos: Vector2 = _main._zone_manager.pin_card_to_field_slot(card, field)
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	card.can_interact = true
	_main._update_debug("%s vuelve a ser un Aliado" % str(card.card_name))


func _on_turn_started_revert_converted(player_id: int, _turn: int) -> void:
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		return  # la lógica corre en el Anfitrión
	await revert_converted_golds(player_id)
