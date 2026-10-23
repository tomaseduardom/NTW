extends Node
class_name GoldManager
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
				attacker.set_meta("combat_damage_turn", GameManager.turn_serial))
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


func _place_card_as_gold(card: Node) -> void:
	# controller_id, no owner_id: el lado del tablero lo decide quién controla la carta
	# (arquitectura.md §38).
	var player_id: int = card.controller_id
	var hand_container = _main.player_hand if player_id == 0 else _main._opponent_fan
	var gold_container = _main.player_gold if player_id == 0 else _main.opponent_gold
	if card.get_parent() != hand_container:
		_main._update_debug("Solo puedes colocar cartas de la mano como Oro")
		return
	if card.card_type != Constants.CardType.ORO:
		_main._update_debug("Solo puedes colocar cartas de tipo Oro")
		return
	if _no_gold_turn.get(player_id, "") == "active":
		_main._update_debug("No puedes poner Oros en juego este turno (Escarapela Nacional)")
		if _main._card_interaction: _main._card_interaction.is_placing_gold = false
		return
	if not TurnManager.can_place_oro(GameManager.current_phase, card):
		_main._update_debug("No puedes colocar Oro ahora")
		if _main._card_interaction: _main._card_interaction.is_placing_gold = false
		return
	if PriorityManager.priority_window_active:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de colocar otro Oro")
		if _main._card_interaction: _main._card_interaction.is_placing_gold = false
		return
	var start_pos = card.global_position
	var idx = hand_container.cards.find(card)
	if idx >= 0:
		hand_container.cards.remove_at(idx)
	hand_container.remove_child(card)
	hand_container._arrange_cards()
	card.can_interact = false
	gold_container.add_child(card)
	update_gold_containers_spacing()
	card.top_level = false
	card.set_zone(Constants.Zone.RESERVA_ORO)
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	# Oro más chico en la Reserva para ganar espacio. Constants.GOLD_CARD_SCALE es el único valor
	# (también lo usan GameBootstrap, las fichas virtuales y el Oro Pagado directo);
	# _mover_oro_a_pagado()/_mover_oro_a_reserva() no tocan la escala.
	card.scale = Constants.GOLD_CARD_SCALE
	# base_scale ANTES del tween: CardInteraction calcula el tamaño de reposo con base_scale; si llega
	# tarde, un hover durante la animación la devuelve a tamaño completo.
	card.base_scale = Constants.GOLD_CARD_SCALE
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	card.can_interact = true
	TurnManager.oro_placed_this_turn = true
	TurnManager.any_card_played_this_turn = true
	if player_id == 0:
		_main.gold_cards.append(card)
	GameState.agregar_oro_reserva(player_id, 1)
	_register_gold_placed(player_id)
	var oro_actual = GameState.get_oro_reserva(player_id)
	_main._update_debug("%s colocado como Oro (Reserva: %d)" % [card.card_name, oro_actual])
	if _main._card_interaction: _main._card_interaction.is_placing_gold = false
	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
	# Corazón de Dragón ("entra en juego como una copia de un Oro que controle tu oponente"): es una
	# condición de juego, se resuelve aquí antes del ETB genérico. load_from_data() reemplaza
	# nombre/habilidad, así que el ETB del Oro copiado (p.ej. Drácula: Roba dos) dispara normal.
	if _is_become_opponent_gold_copy_text(card):
		await _resolve_become_opponent_gold_copy(card)
	# Los Oros también pueden tener habilidades "Al entrar" (p.ej. Signo
	# Amarillo: "mira 4 cartas del tope") — este camino nunca las disparaba,
	# a diferencia de _play_card_to_field()/_play_talisman() que sí lo hacen.
	await _trigger_enter_play(card, Constants.Zone.RESERVA_ORO)


func _is_become_opponent_gold_copy_text(card: Node) -> bool:
	var habilidad: String = str(card.get("card_ability")) if card.get("card_ability") != null else ""
	return "entra en juego como una copia de un oro que controle tu oponente" in habilidad.to_lower()


func _resolve_become_opponent_gold_copy(card: Node) -> void:
	"""Convierte 'card' (Corazón de Dragón, ya colocado en su Reserva) en una
	copia completa (nombre, habilidad, keywords, fuerza, imagen — todo lo
	que load_from_data() carga) de un Oro elegido en la Reserva rival.
	instance_id sigue siendo el propio de 'card' (Card.gd no lo toca), así
	que ninguna referencia externa (contenedor, señales ya conectadas) se
	rompe — solo cambia QUÉ carta representa visualmente y funcionalmente."""
	var player_id: int = card.controller_id
	if not _main._card_interaction:
		return
	# Reserva y Oro Pagado del rival ("un Oro que controle tu oponente" incluye los pagados), sin las
	# fichas de Oro Virtual.
	var rival_id: int = 1 - player_id
	var token_nodes: Array = virtual_gold_tokens.get(rival_id, []).duplicate()
	for pool in restricted_gold_pools.get(rival_id, []):
		token_nodes.append_array(pool.tokens)
	var candidates: Array = []
	for rival_zone in [PlayerSideScript.gold_reserva(_main, rival_id), PlayerSideScript.oro_pagado(_main, rival_id)]:
		if not rival_zone:
			continue
		for c in rival_zone.get_children():
			if is_instance_valid(c) and c != card and not (c in token_nodes) and c.get("card_data") is Dictionary:
				candidates.append(c)
	if candidates.is_empty():
		_main._update_debug("No hay ningún Oro rival para copiar — %s se queda sin habilidad" % card.card_name)
		return
	var filter := func(c: Node) -> bool:
		return c in candidates
	# Condición de juego: no se puede rechazar. El bot elige solo (sin popup en la pantalla del
	# Anfitrión).
	var target: Node = null
	if PlayerSideScript.is_bot(player_id):
		target = candidates[0]
	else:
		target = await _main._card_interaction.await_target("Elige un Oro rival para copiar", filter, false, player_id)
	if not target or not is_instance_valid(target):
		return
	var copied_data: Dictionary = target.card_data.duplicate(true)
	card.load_from_data(copied_data, false)
	_main._update_debug("%s entra en juego como copia de %s" % [card.card_name, target.card_name])


func _has_card_named_in_play(name_lower: String) -> bool:
	"""Busca por nombre (sin distinguir mayúsculas) en las zonas de campo y Oro de ambos jugadores —
	para restricciones "mientras X esté en juego" (p.ej. Armería del Guerrero)."""
	for field in [_main.player_field, _main.opponent_field, _main.player_linea_ataque, _main.opponent_linea_ataque,
			_main.player_linea_apoyo, _main.opponent_linea_apoyo,
			_main.player_gold, _main.opponent_gold, _main.player_oro_pagado, _main.opponent_oro_pagado]:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and str(c.get("card_name")).to_lower() == name_lower:
				return true
	return false


func _register_armeria_opponent_turn_trigger(card: Node) -> void:
	"""Armería del Guerrero: "al comienzo del turno oponente, Baraja y/o Destierra hasta dos cartas de
	los Cementerios". El Oro Inicial no pasa por _trigger_enter_play() (lo coloca GameBootstrap),
	por eso se conecta aquí; se reevalúa en cada turn_started."""
	var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	if not ("al comienzo del turno oponente" in ability_text.to_lower()):
		return
	var handler: Callable
	handler = func(new_active_player: int, _turn: int) -> void:
		if not is_instance_valid(card) or not card.is_in_play():
			if GameManager.turn_started.is_connected(handler):
				GameManager.turn_started.disconnect(handler)
			return
		var owner: int = card.owner_id if card.get("owner_id") != null else 0
		if new_active_player == owner:
			return  # es el turno DE ella, no el del oponente
		if owner != 0:
			return  # el bot todavía no resuelve esta elección interactiva
		await _resolve_armeria_barajar_desterrar()
	GameManager.turn_started.connect(handler)


func _resolve_armeria_barajar_desterrar(max_amount: int = 2, title: String = "Armería del Guerrero", chooser_id: int = 0) -> Array:
	"""Elige hasta 'max_amount' cartas de los dos Cementerios y, por cada una, Barajarla en el
	Castillo de su dueño o Desterrarla. Genérica: Armería del Guerrero, Belta, Perla de Sangre,
	Uriel, Torre de Babel, y el compilador ("Baraja y/o Destierra hasta N..."). La elección de
	cartas es con click en el Cementerio; Barajar/Desterrar por carta es un diálogo de dos botones
	(arquitectura.md §10.16/§10.18). Devuelve los datos de las cartas movidas (Ofrendas al Dragón cuenta
	sus tipos)."""
	var moved: Array = []
	if not _main._zone_viewer:
		return moved
	var no_filter := func(_c: Node) -> bool: return true
	var card_w := "carta" if max_amount == 1 else "cartas"
	var picked: Array = await _main._zone_viewer.open_cemetery_target_picker(
		"%s — elige hasta %d %s de los Cementerios" % [title, max_amount, card_w], no_filter, max_amount,
		"cemetery", false, false, chooser_id)
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		var idx: int = CardManager.get_cemetery(owner_of_picked).find(picked_data)
		if idx < 0:
			continue
		var shuffle_it: bool = await SelectionManager.await_two_choice(
			_main, "¿Qué hacer con esa carta?", "Barajarla (vuelve a su Castillo)", "Desterrarla", chooser_id)
		CardManager.remove_from_cemetery(owner_of_picked, idx)
		if shuffle_it:
			CardManager.get_deck(owner_of_picked).append(picked_data)
			CardManager.shuffle_deck(owner_of_picked)
			# Animación de barajado para que se vea.
			AnimationQueue.queue_shuffle(owner_of_picked, "Barajar mazo (%s)" % title)
		else:
			CardManager.add_to_exile(owner_of_picked, picked_data)
		moved.append(picked_data)
	return moved


func put_gold_directly_in_reserva(player_id: int, card_data: Dictionary) -> Node:
	"""Pone un Oro directo en la Reserva de un jugador sin pasar por la mano ("busca un Oro en tu
	Castillo y ponlo en tu Reserva", p.ej. Don de Amma). Mismo aspecto que el Oro Inicial.
	Es el punto real de "poner un Oro en juego por efectos": aplica Armería del Guerrero ("no
	pueden poner Oros en juego por efectos si ya lo hicieron esta partida") a los dos jugadores,
	solo si hay una en juego."""
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return null
	if _has_card_named_in_play("armería del guerrero") and _oro_por_efecto_used_game.get(player_id, false):
		_main._update_debug("Ya pusiste un Oro en juego por efectos esta partida (Armería del Guerrero)")
		return null
	_oro_por_efecto_used_game[player_id] = true
	oros_en_juego_turno[player_id] = oros_en_juego_turno.get(player_id, 0) + 1
	_note_gold_event(player_id)

	var card_node = _main._create_card(card_data, false)  # Oro es información pública (DAR), boca arriba siempre
	card_node.owner_id = player_id
	card_node.can_interact = true
	card_node.scale = Constants.GOLD_CARD_SCALE
	card_node.base_scale = Constants.GOLD_CARD_SCALE
	_main._connect_card_signals(card_node)
	var target_container: HBoxContainer = _main.player_gold if player_id == 0 else _main.opponent_gold
	target_container.add_child(card_node)
	card_node.set_zone(Constants.Zone.RESERVA_ORO)
	card_node._refresh_disabled_rotation()
	if player_id == 0:
		_main.gold_cards.append(card_node)
	GameState.agregar_oro_reserva(player_id, 1)
	if player_id == 0:
		_update_gold_display()
	await _trigger_enter_play(card_node, Constants.Zone.RESERVA_ORO)
	return card_node


func play_card(card: Node) -> bool:
	# player_id = controller_id de la carta (quien la controla paga y juega; p.ej. Miguel juega del
	# Cementerio rival). Los llamadores solo pasan la carta; el Remoto llega con controller_id 1
	# (arquitectura.md §34, §38).
	var player_id: int = card.controller_id
	_mark_cemetery_exhumar(card)
	# "Si entró en juego desde tu mano" (kiyohime, ikuchi).
	if card.get("current_zone") == Constants.Zone.MANO:
		card.set_meta("entered_from_hand", true)
	# Excepciones de fase: por defecto solo se juega en Vigilia y sin ventana de prioridad abierta.
	# Excepciones: Armas habilitadas en Guerra de Talismanes (Lobo Sagrado,
	# _can_play_weapons_in_guerra_talismanes()) y Talismanes, que también se juegan en Guerra salvo los
	# de respuesta (_is_response_only_talisman(), más abajo).
	var phase_exception: bool = has_phase_exception(card.card_type, player_id)
	# Ventana de comienzo de fase: "Puedes jugarlo al comienzo de cualquier Fase" / "en la Fase Final",
	# en el turno de cualquiera (PhaseStartWindow).
	var phase_start_ok: bool = load("res://scripts/core/game/PhaseStartWindow.gd").allows_now(card, player_id)
	phase_exception = phase_exception or phase_start_ok
	# Talismanes de respuesta (Anula/Cancela, p.ej. Red de Plata, Sacrificio Solar): se juegan cuando
	# el jugador tiene la palabra, no solo en Vigilia.
	var is_instant_response: bool = card.card_type == Constants.CardType.TALISMAN and _is_response_only_talisman(card)
	# Un Talismán de Anular/Cancelar solo se juega en respuesta a algo del rival. "Sólo puedes jugarlo
	# durante tu turno" (Maldición Vudú).
	if card.card_type == Constants.CardType.TALISMAN and GameManager.active_player_id != player_id \
			and "sólo puedes jugarlo durante tu turno" in str(card.get("card_ability")).to_lower():
		_main._update_debug("%s solo se puede jugar durante tu turno" % card.card_name)
		await _return_card_rejected(card)
		return false
	if is_instant_response and not _responding_to_opponent(player_id):
		_main._update_debug("%s solo se puede jugar en respuesta a una carta o habilidad oponente" % card.card_name)
		await _return_card_rejected(card)
		return false

	if GameManager.current_phase != Constants.Phase.VIGILIA and not phase_exception and not is_instant_response:
		_main._update_debug(get_phase_rejection_reason(card.card_type))
		await _return_card_rejected(card)
		return false
	# Fuera de tu turno solo se juegan Talismanes de respuesta (Pila de Respuesta Universal,
	# docs/plans/2026-09-09-pila-respuesta-universal-design.md), o lo que habilite la ventana de
	# comienzo de fase. En Guerra de Talismanes juega quien tiene la prioridad, también el defensor
	# (DAR 5.C3, arquitectura.md §64).
	var in_guerra: bool = GameManager.current_phase == Constants.Phase.GUERRA_TALISMANES
	if in_guerra and PriorityManager.is_guerra_window() and not PriorityManager.can_act(player_id):
		_main._update_debug("Espera tu turno en la Guerra de Talismanes")
		await _return_card_rejected(card)
		return false
	if not in_guerra and GameManager.active_player_id != player_id and not is_instant_response and not phase_start_ok:
		_main._update_debug("No es tu turno")
		await _return_card_rejected(card)
		return false
	# Si hay una ventana de prioridad abierta (respuesta a un trigger que se
	# acaba de disparar, p.ej. 'cuando entre en juego' de la carta anterior),
	# no dejar jugar otra carta todavía — el trigger pendiente quedaba
	# pospuesto y se resolvía solo cuando pasaba OTRA acción, en el
	# momento equivocado. Hay que resolver esa ventana primero (¿Paso?).
	# Los Talismanes instantáneos SÍ pueden jugarse con la ventana abierta —
	# es justo el caso de uso real (responder a lo que la disparó).
	if PriorityManager.priority_window_active and not phase_exception and not is_instant_response:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de jugar otra carta")
		await _return_card_rejected(card)
		return false
	if _no_more_cards_violation(card):
		_main._update_debug("No puedes jugar más cartas este turno")
		await _return_card_rejected(card)
		return false
	if _quinto_sello_cap_violation():
		_main._update_debug("No se pueden jugar más de cinco cartas por turno (Quinto Sello)")
		await _return_card_rejected(card)
		return false
	if _card_play_locked(card):
		_main._update_debug("%s no puede jugarse todavía" % card.card_name)
		await _return_card_rejected(card)
		return false
	if card.card_type == Constants.CardType.ORO:
		await _place_card_as_gold(card)
		return true
	if card.card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No puedes jugar un Arma sin Aliados en juego")
		await _return_card_rejected(card)
		return false
	if _errante_violation(card):
		_main._update_debug("Ya hay una copia de %s en juego (Errante)" % card.card_name)
		await _return_card_rejected(card)
		return false
	if _play_limit_violation(card):
		_main._update_debug(_restrictions.play_limit_message(card))
		await _return_card_rejected(card)
		return false
	# Los Talismanes de respuesta siguen desde aquí el camino de cualquier Talismán (coste, objetivo,
	# _play_talisman()); si no hay objetivo, el selector se cancela con ESC.
	# "Muestra X para reducir el coste" (p.ej. El Rey y el Verdugo): se resuelve antes de calcular el
	# coste real. El modificador no se quita a mano (un Arma recalcula su coste tras elegir portador);
	# lo limpia _on_turn_started_clear_modifiers().
	var reveal_pattern: Dictionary = _get_reveal_cost_reduction_pattern(card)
	if not reveal_pattern.is_empty():
		var revealed_count: int = await _resolve_reveal_cost_reduction(card, reveal_pattern, player_id)
		if revealed_count > 0:
			var applies_to_this_card := func(c: Node) -> bool:
				return c == card
			PaymentManager.agregar_modificador_coste(card, -revealed_count, applies_to_this_card, reveal_pattern.allow_zero)

	# "Puedes Descartar / Destruir / Desterrar <qué> para reducir su coste en N Oros" (voragh el
	# devorador, colaborador titan...): igual que arriba, pero las cartas se pagan de verdad.
	var discard_pattern: Dictionary = _get_discard_cost_reduction_pattern(card)
	if not discard_pattern.is_empty():
		var reduced: int = await _resolve_discard_cost_reduction(card, player_id, discard_pattern)
		if reduced > 0:
			var applies_to_this_card_discard := func(c: Node) -> bool:
				return c == card
			PaymentManager.agregar_modificador_coste(card, -reduced, applies_to_this_card_discard, false)
			if discard_pattern.get("no_annul", false):  # corte letal: "...y no pueda ser Anulado"
				card.set_meta("protected_from_annul_this_turn", true)
				if card.get("card_data") is Dictionary:
					card.card_data["_no_annul"] = true

	# Asequibilidad ANTES de elegir portador: no ofrecer portador para un Arma que no se puede pagar
	# (p.ej. con Lobo Sagrado en Guerra de Talismanes).
	var coste_real = PaymentManager.calcular_coste_real(card)
	if not PaymentManager.puede_jugar_carta(card, player_id):
		var disponible = get_oro_disponible(player_id)
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d (gastado este turno: %d)" % [
			coste_real, disponible, PaymentManager.oro_gastado_este_turno])
		# Quitar el descuento de "muestra X" si se rechaza aquí, para que un segundo intento no lo herede.
		PaymentManager.remover_modificador_coste(card)
		await _return_card_rejected(card)
		return false
	# Elegir portador ANTES de pagar el coste — si el jugador cancela (ESC),
	# no queremos que haya perdido Oro por un Arma que no llegó a equiparse.
	var chosen_wielder: Node = null
	if card.card_type == Constants.CardType.ARMA:
		# Bloquear el Arma mientras se elige portador: un segundo click sobre ella volvía a llamar
		# play_card() y pisaba la selección pendiente (CardInteractionModule guarda un solo
		# filtro/callback).
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(player_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			PaymentManager.remover_modificador_coste(card)
			await _return_card_rejected(card)
			return false
		# Re-chequeo tras la espera async de selección de portador: el Oro
		# disponible no debería cambiar en medio del propio turno del
		# jugador, pero es una comprobación barata y evita pagar de más si
		# algo sí lo cambió mientras esperaba.
		if not PaymentManager.puede_jugar_carta(card, player_id):
			var disponible2 = get_oro_disponible(player_id)
			_main._update_debug("Oro insuficiente: necesitas %d, tienes %d (gastado este turno: %d)" % [
				coste_real, disponible2, PaymentManager.oro_gastado_este_turno])
			PaymentManager.remover_modificador_coste(card)
			await _return_card_rejected(card)
			return false
	if coste_real > 0:
		await pagar_coste(coste_real, card.card_type, card.get("card_raza") if card.get("card_raza") != null else "", card.card_cost, player_id)
		PaymentManager.registrar_pago(coste_real)
	card.set_meta("gold_paid", maxi(coste_real, 0))  # Valac: "como Oros hayas pagado por este Aliado"
	_register_play_limit(card)
	PriorityManager.begin_guerra_action(player_id)
	if card.card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card.card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	PriorityManager.end_guerra_action()
	return true


func play_card_from_exile(card_data: Dictionary, discount: int = 0, owner_id: int = 0) -> bool:
	"""Juega una carta desde el Destierro propio pagando su coste, como si estuviera en la mano
	("Puedes jugarlo de tu Destierro", p.ej. uriel, batallón de ovejas, cruzar el bosque). Espejo
	de play_card_from_cemetery(); no marca is_exhumed: al salir del juego va al Cementerio.
	discount: descuento fijo antes de calcular el coste real, mínimo 1 (p.ej. rafael). owner_id:
	quién la juega (por defecto 0; arquitectura.md §25/§34)."""
	var phase_exception: bool = has_phase_exception(card_data.get("tipo", -1), owner_id)

	if GameManager.current_phase != Constants.Phase.VIGILIA and not phase_exception:
		_main._update_debug(get_phase_rejection_reason(card_data.get("tipo", -1)))
		return false
	if GameManager.active_player_id != owner_id:
		_main._update_debug("No es tu turno")
		return false
	if PriorityManager.priority_window_active and not phase_exception:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de jugar otra carta")
		return false
	if _no_more_cards_this_turn.get(owner_id, false):
		_main._update_debug("No puedes jugar más cartas este turno")
		return false

	var card_type: int = card_data.get("tipo", -1)
	var card = _main._create_card(card_data, false)
	card.owner_id = owner_id
	_main._connect_card_signals(card)

	if discount > 0:
		var applies_to_this_card := func(c: Node) -> bool:
			return c == card
		PaymentManager.agregar_modificador_coste(card, -discount, applies_to_this_card, false)

	if card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No puedes jugar un Arma sin Aliados en juego")
		card.queue_free()
		return false
	if _errante_violation(card):
		_main._update_debug("Ya hay una copia de %s en juego (Errante)" % card.card_name)
		card.queue_free()
		return false
	if _play_limit_violation(card):
		_main._update_debug(_restrictions.play_limit_message(card))
		card.queue_free()
		return false

	var coste_real = PaymentManager.calcular_coste_real(card)
	if not PaymentManager.puede_jugar_carta(card, owner_id):
		var disponible = get_oro_disponible(owner_id)
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible])
		card.queue_free()
		return false

	var chosen_wielder: Node = null
	if card_type == Constants.CardType.ARMA:
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(owner_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			card.queue_free()
			return false
		if not PaymentManager.puede_jugar_carta(card, owner_id):
			var disponible2 = get_oro_disponible(owner_id)
			_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible2])
			card.queue_free()
			return false

	var exile: Array = CardManager.get_exile(owner_id)
	var idx: int = exile.find(card_data)
	if idx < 0:
		card.queue_free()
		return false
	exile.remove_at(idx)

	if coste_real > 0:
		await pagar_coste(coste_real, card_type, card_data.get("raza", ""), card_data.get("coste", 0), owner_id)
		PaymentManager.registrar_pago(coste_real)

	_register_play_limit(card)
	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	return true


func play_found_card(card_data: Dictionary, original_owner: int, controller_id: int, discount: int = 0,
		allow_zero: bool = false) -> bool:
	"""Juega, como parte de un efecto, una carta ya sacada de su zona (p.ej. "busca un Talismán en un
	Castillo y juégalo"): sin chequeos de fase/turno, pagando su coste con 'discount'. Queda bajo
	'controller_id' pero sigue siendo de 'original_owner' (vuelve a SU Cementerio). Si no se puede
	pagar, vuelve al Castillo de su dueño y se baraja."""
	var card = _main._create_card(card_data, false)
	card.owner_id = original_owner
	card.controller_id = controller_id
	_main._connect_card_signals(card)
	if discount > 0:
		PaymentManager.agregar_modificador_coste(card, -discount, func(c: Node) -> bool: return c == card, allow_zero)
	var card_type: int = card_data.get("tipo", -1)
	var coste_real: int = PaymentManager.calcular_coste_real(card)
	var chosen_wielder: Node = null
	var ok: bool = PaymentManager.puede_jugar_carta(card, controller_id)
	if ok and card_type == Constants.CardType.ARMA:
		chosen_wielder = await _select_weapon_wielder(controller_id)
		ok = chosen_wielder != null and is_instance_valid(chosen_wielder)
	if not ok:
		_main._update_debug("No se pudo jugar %s: vuelve al Castillo" % str(card_data.get("nombre", "la carta")))
		if discount > 0:
			PaymentManager.remover_modificador_coste(card)
		card.queue_free()
		var back: Dictionary = card_data.duplicate()
		back["esta_oculta"] = true
		CardManager.get_deck(original_owner).append(back)
		CardManager.shuffle_deck(original_owner)
		return false
	if coste_real > 0:
		await pagar_coste(coste_real, card_type, card_data.get("raza", ""), card_data.get("coste", 0), controller_id)
		PaymentManager.registrar_pago(coste_real)
	if discount > 0:
		PaymentManager.remover_modificador_coste(card)
	_register_play_limit(card)
	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	elif card_type == Constants.CardType.ORO:
		await _place_card_as_gold(card)
	else:
		await _play_card_to_field(card)
	return true


func play_card_from_cemetery(card_data: Dictionary, owner_id: int = 0) -> bool:
	"""Juega una carta con Exhumar desde el Cementerio propio, como si estuviera en la mano (DAR —
	Exhumar). Espejo de play_card(); la carta nunca pasa por la mano, así que
	_play_talisman()/_play_card_to_field()/_equip_weapon() lo toleran. owner_id: quién la juega
	(por defecto 0; arquitectura.md §25/§34)."""
	# Mismas excepciones de fase que play_card() (Armas en Guerra de Talismanes, Talismanes, Talismanes
	# de respuesta: exhumar uno también es jugarlo).
	var phase_exception: bool = has_phase_exception(card_data.get("tipo", -1), owner_id)
	var is_instant_response: bool = card_data.get("tipo", -1) == Constants.CardType.TALISMAN \
		and _is_response_only_talisman_data(card_data)
	if is_instant_response and not _responding_to_opponent(owner_id):
		_main._update_debug("%s solo se puede jugar en respuesta a una carta o habilidad oponente" % str(card_data.get("nombre", "")))
		return false

	if GameManager.current_phase != Constants.Phase.VIGILIA and not phase_exception and not is_instant_response:
		_main._update_debug(get_phase_rejection_reason(card_data.get("tipo", -1)))
		return false
	if GameManager.active_player_id != owner_id:
		_main._update_debug("No es tu turno")
		return false
	if PriorityManager.priority_window_active and not phase_exception and not is_instant_response:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de jugar otra carta")
		return false
	if _no_more_cards_this_turn.get(owner_id, false):
		_main._update_debug("No puedes jugar más cartas este turno")
		return false

	var card_type: int = card_data.get("tipo", -1)
	if is_name_play_locked(owner_id, str(card_data.get("nombre", "")), card_type):
		_main._update_debug("%s no puede jugarse todavía" % str(card_data.get("nombre", "")))
		return false
	# Nota: _card_play_locked() opera sobre el Node (candado por instance_id,
	# ver lock_card_from_playing()) — play_card_from_cemetery() todavía no
	# tiene el Node aquí (se crea más abajo), así que el candado de Chakram no
	# aplica a este camino (jugar con Exhumar desde el Cementerio no es el
	# caso que esa carta describe: 'una carta de la mano rival').
	var card = _main._create_card(card_data, false)
	card.owner_id = owner_id
	# Exhumar solo destierra al salir del juego a los Talismanes (regla del usuario).
	card.is_exhumed = card_type == Constants.CardType.TALISMAN
	_main._connect_card_signals(card)

	if card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No puedes jugar un Arma sin Aliados en juego")
		card.queue_free()
		return false
	if _errante_violation(card):
		_main._update_debug("Ya hay una copia de %s en juego (Errante)" % card.card_name)
		card.queue_free()
		return false
	if _play_limit_violation(card):
		_main._update_debug(_restrictions.play_limit_message(card))
		card.queue_free()
		return false

	# Asequibilidad ANTES de elegir portador (ver play_card()).
	var coste_real = PaymentManager.calcular_coste_real(card)
	if not PaymentManager.puede_jugar_carta(card, owner_id):
		var disponible = get_oro_disponible(owner_id)
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible])
		card.queue_free()
		return false

	var chosen_wielder: Node = null
	if card_type == Constants.CardType.ARMA:
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(owner_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			card.queue_free()
			return false
		if not PaymentManager.puede_jugar_carta(card, owner_id):
			var disponible2 = get_oro_disponible(owner_id)
			_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible2])
			card.queue_free()
			return false

	# Solo con todo confirmado (portador elegido, Oro alcanza) se retira
	# de verdad del Cementerio — igual que play_card() con la mano, para que
	# cancelar a mitad de camino no deje el Cementerio corrompido.
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	var idx: int = cemetery.find(card_data)
	if idx < 0:
		card.queue_free()
		return false
	CardManager.exhume_card(owner_id, idx)

	if coste_real > 0:
		await pagar_coste(coste_real, card_type, card_data.get("raza", ""), card_data.get("coste", 0), owner_id)
		PaymentManager.registrar_pago(coste_real)

	_register_play_limit(card)
	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	return true


## Decisión del usuario (2026-10-23; el DAR no aclara si Exhumar es habilidad continua o condición de
## juego): un Talismán con Exhumar que se juega desde el Cementerio se Destierra siempre, aunque se juegue
## por otro efecto (La Ouija, Miguel...), incluso si es Anulado. CardManager.remove_from_cemetery() marca
## los datos con "_from_cemetery_turn".
func _mark_cemetery_exhumar(card: Node) -> void:
	if not is_instance_valid(card) or card.get("card_data") == null:
		return
	var data: Dictionary = card.card_data
	var from_cem: bool = int(data.get("_from_cemetery_turn", -1)) == GameManager.turn_serial
	data.erase("_from_cemetery_turn")
	if from_cem and card.get("card_type") == Constants.CardType.TALISMAN and not KeywordManager.is_silenced(card) 			and PaymentManager._exhumar and PaymentManager._exhumar._card_has_exhumar(data, int(card.owner_id) if card.get("owner_id") != null else -1):
		card.is_exhumed = true


func play_card_for_free(card_data: Dictionary, owner_id: int = 0, exile_after: bool = false) -> bool:
	"""Juega una carta SIN pagar su coste ni pasar por la mano (p.ej. Tangata Manu: "juega una carta
	de coste 2 o menos sin pagar su coste"). El llamador ya sacó card_data de su zona; aquí solo se
	crea el nodo y se enruta según su tipo. owner_id: quién la juega (por defecto 0;
	arquitectura.md §25)."""
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return false
	var card_type: int = card_data.get("tipo", -1)
	# Un Oro nunca se juega, ni gratis: solo se pone en juego por efectos (regla del usuario). Si un
	# patrón manda uno aquí, se rechaza para que el error se vea.
	if card_type == Constants.CardType.ORO:
		push_warning("[GoldManager] play_card_for_free() recibió un Oro (%s): un Oro no se juega, se pone en juego" % str(
			card_data.get("nombre", "?")))
		return false
	# No Más Magia: "Por el resto del juego, jugar ... cartas sin pagar su coste cuesta un Oro adicional".
	if RuleState.active("no_mas_magia", owner_id):
		if not puede_pagar(1, -1, "", -1, owner_id):
			_main._update_debug("No Más Magia: necesitas un Oro para jugar %s sin pagar su coste" % str(card_data.get("nombre", "")))
			return false
		await pagar_coste(1, -1, "", -1, owner_id)
	var card = _main._create_card(card_data, false)
	card.owner_id = owner_id
	# "jugada sin pagar su coste este turno" (Sacrificio Solar, StackAnnul).
	card.set_meta("played_free", true)
	# "juégalo ... y Destiérralo" (haka pei): al salir del juego va al Destierro, como una carta
	# exhumada.
	if exile_after:
		card.is_exhumed = true
	_mark_cemetery_exhumar(card)
	_main._connect_card_signals(card)

	if card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No se pudo jugar %s: sin Aliados en juego para portar el Arma" % card.card_name)
		card.queue_free()
		return false
	if _errante_violation(card):
		_main._update_debug("No se pudo jugar %s: ya hay una copia en juego (Errante)" % card.card_name)
		card.queue_free()
		return false

	var chosen_wielder: Node = null
	if card_type == Constants.CardType.ARMA:
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(owner_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			card.queue_free()
			return false

	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	return true


func _select_weapon_wielder(chooser_id: int = 0, extra_filter: Callable = Callable()) -> Node:
	"""Elige qué Aliado porta el Arma que se juega: propio o rival (DAR no restringe el portador). Un
	Arma no va suelta, y un Aliado porta una (o más con "Arma adicional"). chooser_id: quién elige
	(por defecto 0; arquitectura.md §25)."""
	if not _main._card_interaction:
		return null
	# Última red de seguridad: sin candidatos, abrir la selección la dejaba colgada para siempre.
	# extra_filter: restringe quién puede portarla (Zadquiel: "sobre este Aliado o uno oponente").
	var eligible: Array = _get_eligible_weapon_wielders()
	if extra_filter.is_valid():
		eligible = eligible.filter(func(c): return extra_filter.call(c))
	if eligible.is_empty():
		_main._update_debug("No hay ningún Aliado libre en juego para portar el Arma")
		return null
	var filter := func(c: Node) -> bool:
		return c in eligible
	var prompt: String = "Elige qué Aliado porta el Arma" if extra_filter.is_valid() \
		else "Elige qué Aliado porta el Arma (propio o rival)"
	return await _main._card_interaction.await_target(prompt, filter, true, chooser_id)


func _equip_weapon(weapon: Node, ally: Node, fire_enter_play: bool = true) -> void:
	"""Ancla el Arma como hija directa del Aliado portador (no va a un contenedor de línea); se
	inspecciona por separado y sigue al portador si ataca o sale del juego
	(CardManager.destroy_card/exile_card la mueven con él).
	fire_enter_play = false al reasignar un Arma que ya estaba en juego a un portador nuevo
	(CardManager._resolve_weapon_survives_wielder()): DAR — el Arma sobrevive, no se vuelve a
	jugar, así que no se dispara su "Cuando entra en juego" ni se cuenta para Quinto Sello."""
	if fire_enter_play:
		TurnManager.on_card_played(weapon)
	_main._update_debug("Equipando %s a %s" % [weapon.card_name, ally.card_name])

	# 1. Capturar posición global inicial ANTES de quitar el arma de su contenedor
	var start_pos: Vector2 = weapon.global_position if weapon.is_inside_tree() else ally.global_position

	# 2. Desactivar interacción y arrastre residual de inmediato
	weapon.can_interact = false
	if "is_dragging" in weapon:
		weapon.is_dragging = false
	if "drag_enabled" in weapon:
		weapon.drag_enabled = false
	if "_drag_pending" in weapon:
		weapon._drag_pending = false

	# 3. Quitar de la mano cortando los tweens de DynamicHand, para que no la sigan moviendo a la mano.
	var weapon_owner: int = weapon.owner_id if weapon.get("owner_id") != null else 0
	var weapon_hand_container = _main.player_hand if weapon_owner == 0 else _main.get("_opponent_fan")
	if _main and weapon_hand_container:
		if weapon_hand_container.cards.has(weapon) or weapon.get_parent() == weapon_hand_container:
			weapon_hand_container.remove_card(weapon, false)
	if weapon.get_parent():
		weapon.get_parent().remove_child(weapon)

	# 4. Asignar estado IN_PLAY y emparentar al Aliado
	weapon.current_state = Card.CardState.IN_PLAY
	ally.add_child(weapon)

	# Detrás del Aliado, asomando por abajo: el offset (125 de 210 de alto) deja la parte inferior del
	# Arma (su texto) fuera del rect del Aliado; la parte de arriba queda tapada por el portador.
	ally.move_child(weapon, 0)
	weapon.z_index = 0
	weapon.original_z_index = 0
	weapon.top_level = false
	weapon.modulate.a = 1.0
	weapon.visible = true
	weapon.set_zone(ally.current_zone)

	# Mismo tamaño que el Aliado (ally.base_scale; scale y base_scale juntos, como en
	# _place_card_as_gold()). Varias Armas se apilan hacia abajo (+Constants.WEAPON_STACK_STEP_Y cada
	# una).
	var slot_index: int = ally.equipped_weapons.size()
	var equip_scale: Vector2 = ally.base_scale
	weapon.scale = equip_scale
	weapon.base_scale = equip_scale
	var target_local_pos := Vector2(0.0, Constants.WEAPON_OFFSET_Y + slot_index * Constants.WEAPON_STACK_STEP_Y)
	weapon.position = target_local_pos
	ally.equipped_weapons.append(weapon)
	weapon.wielder = ally
	_register_weapon_strength_bonus(weapon, ally)
	_register_wielder_leave_play_immunity(weapon, ally)
	_register_weapon_talisman_tax(weapon)
	_refresh_dynamic_strength_badges(ally.controller_id if ally.get("controller_id") != null else 0)

	# 5. Animación de equipar en el espacio local del Aliado
	await get_tree().process_frame
	if not is_instance_valid(weapon) or not is_instance_valid(ally):
		return

	# Control no tiene to_local()/to_global() (son de Node2D): equivalente para Control, como en
	# MulliganController.gd.
	var start_local_pos: Vector2 = ally.get_global_transform().affine_inverse() * start_pos
	weapon.position = start_local_pos
	weapon.top_level = false

	var tween = weapon.create_tween()
	tween.tween_property(weapon, "position", target_local_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished

	# 6. Reafirmar determinísticamente la posición, escala y estado final
	if is_instance_valid(weapon) and is_instance_valid(ally):
		weapon.position = target_local_pos
		weapon.top_level = false
		weapon.scale = ally.base_scale
		weapon.base_scale = ally.base_scale
		weapon.can_interact = true
		weapon.modulate.a = 1.0

	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
	if fire_enter_play:
		VisualManager.play_card_effect(weapon.card_cost)
		await _trigger_enter_play(weapon, ally.current_zone)


func _register_weapon_strength_bonus(weapon: Node, ally: Node) -> void:
	"""Parsea 'El portador gana N de Fuerza' del texto del Arma y registra el
	bono en ContinuousEffectManager con duración PERMANENT ('mientras la
	fuente esté en juego') — se limpia solo cuando el Arma sale de juego
	(Card._exit_tree() llama remove_modifiers_from_source() sin importar
	cómo salió: destruida, desterrada, devuelta al mazo). El combate
	(BattleManager._get_strength()) y el badge visual de la carta ya
	consultan este valor calculado, así que con solo registrar el
	modificador alcanza para que todo se refleje solo."""
	var ability_text: String = weapon.get("card_ability") if weapon.get("card_ability") != null else ""
	if ability_text.is_empty():
		return

	# el huascar: "El portador duplica su Fuerza y tus demás Aliados ganan Fuerza igual a su coste",
	# mientras esté equipada.
	if "el portador duplica su fuerza y tus demás aliados ganan fuerza igual a su coste" in ability_text.to_lower():
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(_c: Node, current: int, _mod: Dictionary) -> int: return current,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s duplica su Fuerza (%s)" % [ally.card_name, weapon.card_name],
		})
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": "ALLIES",
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(c: Node, _current: int, _mod: Dictionary) -> int:
				if c == ally or not is_instance_valid(c):
					return 0
				return int(c.get("card_cost")) if c.get("card_cost") != null else 0,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s: tus demás Aliados +Fuerza igual a su coste" % weapon.card_name,
		})
		return

	# "El portador gana Furia y 1 de Fuerza por cada Oro que controles" (skofnung): bono dinámico,
	# value es un Callable recontado en cada consulta (como Manuel Bulnes / shedo titan). Las palabras
	# clave que el Arma da al portador no se registran aquí: las lee Card.has_keyword().
	var dynamic_rx := RegEx.new()
	dynamic_rx.compile("(?i)el portador gana furia y (\\d+) de fuerza por cada oro que controles")
	var dynamic_m := dynamic_rx.search(ability_text)
	if dynamic_m:
		var per_oro: int = int(dynamic_m.get_string(1))
		var wielder_controller: int = ally.controller_id if ally.get("controller_id") != null else 0
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(_c: Node, _current: int, _mod: Dictionary) -> int:
				return GameState.get_oro_total(wielder_controller) * per_oro,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s porta %s (+Fuerza por Oro)" % [ally.card_name, weapon.card_name],
		})
		if ally.has_method("refresh_strength_badge"):
			ally.refresh_strength_badge()
		return

	# "El portador gana 2 de Fuerza por cada Azusa Yumi que controles y hace daño al Destierro" (azusa
	# yumi): mismo value Callable, contando copias equipadas. Va antes del regex genérico, que si no lo
	# tomaría como +2 fijo.
	var azusa_rx := RegEx.new()
	azusa_rx.compile("(?i)el portador gana (\\d+) de fuerza por cada azusa yumi que controles")
	var azusa_m := azusa_rx.search(ability_text)
	if azusa_m:
		var per_azusa: int = int(azusa_m.get_string(1))
		var wielder_controller_az: int = ally.controller_id if ally.get("controller_id") != null else 0
		var count_azusa := func() -> int:
			var n: int = 0
			for other in ContinuousEffectManager._get_all_cards_in_play():
				if ContinuousEffectManager._get_card_owner(other) != wielder_controller_az:
					continue
				var w = other.get("equipped_weapons")
				if w is Array:
					for weap in w:
						if is_instance_valid(weap) and str(weap.get("card_name")).to_lower() == "azusa yumi":
							n += 1
			return n
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(_c: Node, _current: int, _mod: Dictionary) -> int:
				return count_azusa.call() * per_azusa,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s porta %s (+Fuerza por Azusa Yumi)" % [ally.card_name, weapon.card_name],
		})
		# "...y hace daño al Destierro" — mismo mecanismo real ya usado por
		# arco del triunfo/Segundo Sello (TriggerSystem.register_continuous_
		# effect con type 'damage_to_exile', targets = el OPONENTE de quien
		# porta el Arma, porque ese registro se consulta del lado de quien
		# RECIBE el daño). Se registra una vez por copia equipada; si se
		# desequipa, TriggerSystem no tiene un "unregister por source" para
		# este tipo puntual todavía (mismo camino que arco del triunfo usa al
		# salir del juego) — limitación conocida, aceptable porque Azusa Yumi
		# rara vez se desequipa sin salir de juego (no hay Arma "cambia de
		# portador" en el catálogo auditado esta sesión).
		TriggerSystem.register_continuous_effect(weapon, {
			"type": "damage_to_exile",
			"targets": [1 - wielder_controller_az]
		})
		if ally.has_method("refresh_strength_badge"):
			ally.refresh_strength_badge()
		return

	# kabutowari ("En Guerra de Talismanes, una vez por turno, el portador gana 1 de Fuerza por cada
	# Aliado en tu Línea de Defensa..."): no es un aura permanente. Se excluye del regex genérico (que
	# daría +1 fijo); la activada es InPlayAbilities.kabutowari().
	if "gana 1 de fuerza por cada aliado en tu l" in ability_text.to_lower() \
			and "guerra de talismanes" in ability_text.to_lower():
		return

	var rx := RegEx.new()
	rx.compile("(?i)el portador gana (\\d+) de fuerza")
	var m := rx.search(ability_text)
	if not m:
		return
	var bonus := int(m.get_string(1))
	if bonus > 0:
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": bonus,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s porta %s (+%d Fuerza)" % [ally.card_name, weapon.card_name, bonus],
		})
		if ally.has_method("refresh_strength_badge"):
			ally.refresh_strength_badge()


func _register_wielder_leave_play_immunity(weapon: Node, ally: Node) -> void:
	""""Cuando entra en juego, el portador no puede salir del juego hasta tu próximo turno" (p.ej.
	Garfio Pirata): se resuelve al equipar porque hace falta saber quién es el portador."""
	var ability: String = weapon.card_ability.to_lower() if weapon.get("card_ability") else ""
	if not ("el portador no puede salir del juego" in ability):
		return
	var controller_id: int = weapon.controller_id if weapon.get("controller_id") != null else 0
	EffectController.add_single_card_leave_play_immunity(ally, controller_id)


func _register_weapon_talisman_tax(weapon: Node) -> void:
	""""Los Talismanes cuestan un Oro adicional" (nodachi): sin "de tu oponente", vale para los
	Talismanes de los dos jugadores mientras esté equipada. Sube el coste impreso
	(agregar_modificador_coste; ver PaymentManager.calcular_coste_real()). Se limpia sola al salir
	(Card._exit_tree() → PaymentManager.remover_modificador_coste)."""
	var ability: String = weapon.card_ability.to_lower() if weapon.get("card_ability") else ""
	if not ("los talismanes cuestan un oro adicional" in ability):
		return
	var condition := func(c: Node) -> bool:
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.TALISMAN
	PaymentManager.agregar_modificador_coste(weapon, 1, condition, false)


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


func _get_reveal_cost_reduction_pattern(card: Node) -> Dictionary:
	return _tax._get_reveal_cost_reduction_pattern(card)


func _resolve_reveal_cost_reduction(card: Node, pattern: Dictionary, player_id: int = 0) -> int:
	return await _tax._resolve_reveal_cost_reduction(card, pattern, player_id)


func _get_discard_cost_reduction_pattern(card: Node) -> Dictionary:
	return _tax._get_discard_cost_reduction_pattern(card)


func _resolve_discard_cost_reduction(card: Node, player_id: int = 0, pattern: Dictionary = {}) -> int:
	return await _tax._resolve_discard_cost_reduction(card, player_id, pattern)


## Elegibilidad para jugar una carta: el cuerpo está en GoldManagerRestrictions.gd. Reenvíos de una
## línea; _is_response_only_talisman, has_phase_exception, get_phase_rejection_reason,
## _get_eligible_weapon_wielders y _player_has_ally_in_play tienen llamadores fuera de este archivo.
func _errante_violation(card: Node) -> bool:
	return _restrictions._errante_violation(card)


func _play_limit_violation(card: Node) -> bool:
	return _restrictions._play_limit_violation(card)


func _register_play_limit(card: Node) -> void:
	_restrictions._register_play_limit(card)


func _is_response_only_talisman(card: Node) -> bool:
	return _restrictions._is_response_only_talisman(card)


func _is_response_only_talisman_data(card_data: Dictionary) -> bool:
	return _restrictions._is_response_only_talisman_data(card_data)


func _player_has_ally_in_play() -> bool:
	return _restrictions._player_has_ally_in_play()


func _get_eligible_weapon_wielders() -> Array:
	return _restrictions._get_eligible_weapon_wielders()


func has_phase_exception(card_type: int, player_id: int = 0) -> bool:
	return _restrictions.has_phase_exception(card_type, player_id)


func get_phase_rejection_reason(card_type: int) -> String:
	return _restrictions.get_phase_rejection_reason(card_type)


func _return_card_rejected(card: Node) -> void:
	if not card or not is_instance_valid(card):
		return
	# Restaurar la interactividad: el Arma se deshabilita al elegir portador; si se cancela o el pago
	# falla, vuelve a ser clickeable.
	card.can_interact = true
	# Si la carta nunca fue arrastrada (doble click), original_position es Vector2.ZERO — corregirlo
	# antes de llamar return_to_hand(), que usa esa propiedad para animar el regreso.
	if card.get("original_position") != null and card.original_position == Vector2.ZERO:
		card.original_position = card.global_position
	# Flash rojo — sin tweenear global_position para no pelear con el layout del contenedor
	var tween = create_tween()
	tween.tween_property(card, "modulate", Color(1.5, 0.3, 0.3, 1.0), 0.08)
	await tween.finished
	var tween2 = create_tween()
	tween2.tween_property(card, "modulate", Color.WHITE, 0.2)
	await tween2.finished
	card.return_to_hand()


func _play_card_to_field(card: Node) -> void:
	TurnManager.on_card_played(card)
	# El lado del tablero lo decide controller_id (quién la controla), no owner_id (a quién vuelve si
	# muere): solo difieren en casos como Miguel. Vale para los tres caminos (play_card /
	# play_card_from_cemetery / play_card_for_free) y para el jugador 1 (arquitectura.md §25, §38).
	var owner_id: int = card.controller_id
	# Crono Diamante ("si jugaste un Aliado de coste 2 o más este turno"): se registra aquí porque todo
	# Aliado jugado pasa por esta función, venga de donde venga.
	if card.card_type == Constants.CardType.ALIADO and int(card.card_cost) >= 2:
		UniversalCardParser.turn_registry.register("played_ally_cost2plus:%d" % owner_id, 0, GameManager.turn_serial)
	if card.card_type in [Constants.CardType.ALIADO, Constants.CardType.TOTEM] and int(card.card_cost) >= 2:
		_apply_crono_diamante_annul_protection(card)
	_main._update_debug("Jugando: %s" % card.card_name)
	var start_pos = card.global_position
	var hand_container: Control = _main.player_hand if owner_id == 0 else _main._opponent_fan  # HandManager/OpponentFan son Control
	var idx = hand_container.cards.find(card) if hand_container else -1
	if idx >= 0:
		hand_container.cards.remove_at(idx)
	# Solo si sigue en la mano: un Aliado/Tótem exhumado nunca estuvo ahí.
	if hand_container and card.get_parent() == hand_container:
		hand_container.remove_child(card)
		hand_container._arrange_cards()
	card.can_interact = false
	# Tótems a la Línea de Apoyo; Aliados y Armas a la Línea de Defensa (DAR: tres zonas dentro del
	# campo).
	var own_linea_apoyo: HBoxContainer = _main.player_linea_apoyo if owner_id == 0 else _main.opponent_linea_apoyo
	var own_field: HBoxContainer = _main.player_field if owner_id == 0 else _main.opponent_field
	var target_container: HBoxContainer = own_linea_apoyo if card.card_type == Constants.CardType.TOTEM else own_field
	var target_zone: int = Constants.Zone.LINEA_APOYO if card.card_type == Constants.CardType.TOTEM else Constants.Zone.LINEA_DEFENSA
	target_container.add_child(card)
	# Si la carta llegó por arrastre (drag), top_level seguía en true (modo
	# 'posición global libre' que usa Card._update_drag()). Sin resetearlo,
	# el contenedor no puede posicionarla de verdad, y el 'end_pos' leído
	# más abajo terminaba siendo la última posición del arrastre en vez de
	# la casilla real del campo — la carta se animaba hacia un lugar sin
	# relación con el campo, dando la sensación de que desaparecía.
	card.top_level = false
	card.z_index = 0
	card.set("original_z_index", 0)
	card.set_meta("hand_base_z_index", 0)
	card.set_zone(target_zone)
	await get_tree().process_frame
	# Escala del campo: Aliados a 1.0; Tótems a Constants.TOTEM_CARD_SCALE
	var field_scale: Vector2 = Constants.TOTEM_CARD_SCALE if card.card_type == Constants.CardType.TOTEM else Vector2.ONE
	card.scale = field_scale
	# Slot fijo en vez de la posición que calcula el HBoxContainer, para que los demás no se corran
	# cuando uno ataca (ZoneManager.pin_card_to_field_slot()).
	var end_pos: Vector2 = _main._zone_manager.pin_card_to_field_slot(card, target_container)
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	card.base_scale = field_scale
	card.can_interact = true
	VisualManager.play_card_effect(card.card_cost)
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
	await _trigger_enter_play(card, target_zone)


func _apply_crono_diamante_annul_protection(card: Node) -> void:
	"""Crono Diamante: "tu primer Aliado o Tótem de coste 2 o más (este turno) no puede ser Anulado" —
	solo si su controlador tiene un Crono Diamante en la Reserva, la primera vez por turno
	(turn_registry). Marca la carta con set_meta(), que lee
	TargetedEffectExecutor._execute_targeted_annul().
	La otra mitad ("la primera habilidad de Oro que utilices cada turno no puede ser cancelada"):
	ProtectionRules.note_gold_ability_use / first_gold_ability_protected."""
	var controller_id: int = card.controller_id if card.get("controller_id") != null else 0
	# También para el jugador 1 (su Reserva es opponent_gold).
	var gold_container = PlayerSideScript.gold_reserva(_main, controller_id)
	if not gold_container:
		return
	var has_crono_diamante := false
	for c in gold_container.get_children():
		if is_instance_valid(c) and str(c.get("card_name")).to_lower() == "crono diamante":
			has_crono_diamante = true
			break
	if not has_crono_diamante:
		return
	var key := "crono_diamante_annul_protection:%d" % controller_id
	if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.turn_serial):
		return
	UniversalCardParser.turn_registry.register(key, 0, GameManager.turn_serial)
	card.set_meta("protected_from_annul_this_turn", true)


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


func check_libro_de_thoth_block(blocker: Node, blocker_owner: int) -> void:
	"""libro de thoth (Oro): "Cuando bloquees, genera un Oro por el turno" — reacciona a que cualquier
	Aliado tuyo bloquee. Se llama desde GameManager.confirm_blockers_and_collect_triggers(), una
	vez por bloqueador; un trigger normal solo llega a la carta que dispara el evento, no a un Oro
	en la Reserva. El Oro generado no tiene restricción."""
	if not is_instance_valid(blocker):
		return
	var reserva: Array = _main.gold_cards if blocker_owner == 0 else (_main.opponent_gold.get_children() if _main.get("opponent_gold") else [])
	var pagado: Array = _main.player_oro_pagado.get_children() if blocker_owner == 0 and _main.get("player_oro_pagado") else \
		(_main.opponent_oro_pagado.get_children() if blocker_owner == 1 and _main.get("opponent_oro_pagado") else [])
	var has_libro: bool = false
	for g in reserva + pagado:
		if is_instance_valid(g) and str(g.get("card_name")).to_lower() == "libro de thoth":
			has_libro = true
			break
	if not has_libro:
		return
	var always_true := func(_t, _r, _c) -> bool: return true
	generar_oro_virtual_restringido(1, always_true, "libro de thoth")


func _discard_oro_from_reserva(oro_card: Node, controller_id: int) -> void:
	"""Descarta (al Cementerio) un Oro físico de la Reserva: no hay otro camino para esto (discard()
	es solo desde la mano). Costo de Cuarto Sello ("Puedes pagar un Oro y Descartarlo..."). Limpia
	como ActionReturnDiscard.return_to_deck(): señales, Reserva/gold_cards y GameState."""
	if not is_instance_valid(oro_card):
		return
	var data: Dictionary = oro_card.card_data.duplicate() if oro_card.get("card_data") else {}
	CardManager.add_to_cemetery(controller_id, data)
	GameState.agregar_oro_reserva(controller_id, -1)
	if controller_id == 0:
		_main.gold_cards.erase(oro_card)
	CardManager._disconnect_card_interaction_signals(oro_card)
	var parent = oro_card.get_parent()
	if parent:
		parent.remove_child(oro_card)
	oro_card.queue_free()
	if controller_id == 0:
		_update_gold_display()


func _take_gold_out_of_play(oro_card: Node) -> Dictionary:
	"""Saca un Oro de la Reserva o del Oro Pagado (contadores incluidos) y devuelve sus datos; el
	llamador decide el destino."""
	var pid: int = oro_card.controller_id if oro_card.get("controller_id") != null else 0
	var parent = oro_card.get_parent()
	if parent == (_main.player_gold if pid == 0 else _main.opponent_gold):
		GameState.agregar_oro_reserva(pid, -1)
	elif parent == (_main.player_oro_pagado if pid == 0 else _main.opponent_oro_pagado):
		GameState.agregar_oro_pagado(pid, -1)
	if pid == 0:
		_main.gold_cards.erase(oro_card)
	var data: Dictionary = oro_card.card_data.duplicate() if oro_card.get("card_data") else {}
	CardManager._disconnect_card_interaction_signals(oro_card)
	if parent:
		parent.remove_child(oro_card)
	oro_card.queue_free()
	update_gold_containers_spacing()
	_update_gold_display()
	return data


func exile_gold_from_play(oro_card: Node) -> void:
	if not is_instance_valid(oro_card):
		return
	var owner_id: int = oro_card.owner_id if oro_card.get("owner_id") != null else 0
	var data: Dictionary = _take_gold_out_of_play(oro_card)
	data["esta_oculta"] = false
	CardManager.append_to_exile(owner_id, data)


func return_gold_to_hand(oro_card: Node) -> void:
	if not is_instance_valid(oro_card):
		return
	var owner_id: int = oro_card.owner_id if oro_card.get("owner_id") != null else 0
	var data: Dictionary = _take_gold_out_of_play(oro_card)
	var node = _main._create_card(data, owner_id != 0)
	if owner_id == 0:
		_main.player_hand.add_card(node)
	else:
		_main._opponent_fan.add_card(node)
	_main._connect_card_signals(node)


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


func buff_next_talisman(player_id: int, discount: int, allow_zero: bool, no_annul: bool) -> void:
	_clear_next_talisman_buff(player_id)
	var token := Node.new()
	add_child(token)
	var turn: int = GameManager.turn_serial
	PaymentManager.agregar_modificador_coste(token, -discount, func(c: Node) -> bool:
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.TALISMAN \
			and c.get("controller_id") == player_id, allow_zero)
	_next_talisman_buffs[player_id] = {"token": token, "no_annul": no_annul, "turn": turn,
		"active_player": GameManager.active_player_id}


func _clear_next_talisman_buff(player_id: int) -> void:
	var buff: Dictionary = _next_talisman_buffs.get(player_id, {})
	if buff.is_empty():
		return
	_next_talisman_buffs.erase(player_id)
	PaymentManager.remover_modificador_coste(buff.token)
	if is_instance_valid(buff.token):
		buff.token.queue_free()


func _consume_next_talisman_buff(card: Node) -> void:
	var pid: int = card.controller_id
	var buff: Dictionary = _next_talisman_buffs.get(pid, {})
	if buff.is_empty():
		return
	if buff.turn != GameManager.turn_serial or buff.active_player != GameManager.active_player_id:
		_clear_next_talisman_buff(pid)  # "este turno": ya venció
		return
	if buff.no_annul:
		card.set_meta("protected_from_annul_this_turn", true)
		if card.get("card_data") is Dictionary:
			card.card_data["_no_annul"] = true
	_clear_next_talisman_buff(pid)


func _play_talisman(card: Node) -> void:
	"""Los Talismanes se resuelven al jugarse y no se quedan en el campo
	como un Aliado ni como un Tótem (DAR Sección 8): disparan su habilidad y
	van al Cementerio por defecto — al Destierro si su propio texto dice
	'destiérralo', o de vuelta al Mazo (barajado) si dice 'barájala'. Si fue
	jugado via Exhumar (card.is_exhumed), el Destierro manda siempre, sin
	importar lo que diga el propio texto (regla de Exhumar, DAR)."""
	TurnManager.on_card_played(card)
	_main._update_debug("Jugando talismán: %s" % card.card_name)
	_consume_next_talisman_buff(card)

	# Por jugador, "ya jugó un Talismán este turno" (Fuente de la Juventud: "les cuesta un Oro
	# adicional jugar Talismanes si han jugado Talismanes este turno"; lo consulta
	# _register_talisman_second_play_tax()). Cuenta quien lo controla (arquitectura.md §38).
	var talisman_owner: int = card.controller_id
	UniversalCardParser.turn_registry.register("talisman_played:%d" % talisman_owner, 0, GameManager.turn_serial)

	# Se enruta por talisman_owner (no siempre el Anfitrión): Talismanes jugados por el jugador 1 vía
	# play_card_for_free()/play_card_from_cemetery() (arquitectura.md §25).
	var hand_container: Control = _main.player_hand if talisman_owner == 0 else _main._opponent_fan  # HandManager/OpponentFan son Control
	var field_container: HBoxContainer = _main.player_field if talisman_owner == 0 else _main.opponent_field
	var idx = hand_container.cards.find(card) if hand_container else -1
	if idx >= 0:
		hand_container.cards.remove_at(idx)
	# Ver GoldManager._play_card_to_field() — misma corrección (Exhumar: la
	# carta nunca estuvo en la mano).
	if hand_container and card.get_parent() == hand_container:
		hand_container.remove_child(card)
		hand_container._arrange_cards()
	card.can_interact = false
	field_container.add_child(card)
	# Ver GoldManager._play_card_to_field() — misma corrección.
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_APOYO)
	await get_tree().create_timer(0.3).timeout

	# _trigger_enter_play() se espera hasta el final (incluye las elecciones del jugador), así que no
	# hace falta una espera fija: el Talismán va al Cementerio apenas se resuelve.
	var was_annulled: bool = await _trigger_enter_play(card, Constants.Zone.LINEA_APOYO)

	if was_annulled:
		# Anulado/cancelado en su ventana de respuesta: el efecto no ocurrió, así que no se mira su texto
		# ("destiérralo", "barájala") — va al Cementerio, como cualquier Anular.
		var true_owner_annulled: int = card.owner_id if card.get("owner_id") != null else 0
		if card.get_meta("annul_to_pagado_gold", false):
			# asalto estelar: "Si es Anulado, conviértelo en un Oro sin habilidad y ponlo en tu Oro Pagado".
			var gold_data: Dictionary = card.card_data.duplicate(true)
			gold_data["tipo"] = Constants.CardType.ORO
			gold_data["habilidad"] = ""
			gold_data["keywords"] = []
			if card.get_parent():
				card.get_parent().remove_child(card)
			card.queue_free()
			await put_gold_directly_in_pagado(true_owner_annulled, gold_data)
		elif card.get_meta("annul_to_exile", false):
			await EffectController.exile_card(true_owner_annulled, card, true)
		else:
			await EffectController.destroy_card(true_owner_annulled, card, false)
		_update_gold_display()
		_main._update_buttons_for_phase(GameManager.current_phase)
		return

	var habilidad: String = card.card_ability.to_lower() if card.get("card_ability") else ""
	# "Destiérralo"/"Destiérrala" llevan tilde (el pronombre mueve el acento), por eso no basta buscar
	# "destierr". Solo si se destierra a sí mismo (Cuervo Nocturno dice "Destierra seis cartas del tope
	# del Castillo oponente" y no se va al Destierro).
	var self_exile := false
	for phrase in ["destiérralo", "destiérrala", "destierralo", "destierrala", "destierra esta carta",
			"destierra este talismán", "destierra este talisman"]:
		if phrase in habilidad:
			self_exile = true
	# "barájala"/"barájalo" (se baraja a sí mismo; Visión de Enoc). No basta "baraj": Aaru dice "Baraja
	# cualquier cantidad de cartas de tu mano" y va al Cementerio.
	var self_shuffle := "barájala" in habilidad or "barajala" in habilidad \
		or "barájalo en tu castillo" in habilidad or "barajalo en tu castillo" in habilidad

	# Vuelve a SU dueño (card.owner_id): con Miguel se puede jugar un Talismán del Cementerio rival, y
	# debe volver al Cementerio/Destierro de ese jugador.
	var true_owner: int = card.owner_id if card.get("owner_id") != null else 0

	if card.get("is_exhumed") == true:
		# Exhumar manda siempre al Destierro, sin importar el propio texto
		# de la carta (ni "barájala" ni el Cementerio por defecto aplican).
		await EffectController.exile_card(true_owner, card)
	elif self_shuffle:
		await ActionModule.return_to_deck(card, true_owner, false, card)
		ActionModule.shuffle_deck(true_owner)
	else:
		# self_exile respeta el texto de la carta sea cual sea el camino: si dice "destiérralo", se
		# destierra. La única regla que fuerza el Destierro, diga lo que diga, es Exhumar (is_exhumed,
		# arriba); jugarla del Cementerio por otro efecto (Miguel) no agrega nada.
		if self_exile:
			await EffectController.exile_card(true_owner, card)
		else:
			# is_being_destroyed = false: un Talismán que va al Cementerio tras resolverse no es una
			# destrucción (solo cambia el texto del log).
			await EffectController.destroy_card(true_owner, card, false)

	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)


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


## gokin: "Sólo puedes usar este Oro para pagar el coste de una carta de coste 3 o más" — meta
## "only_cost_min" en el Oro de la Reserva. ¿Puede pagar 'card_cost' (-1 = una habilidad)?
static func gold_usable_for(gold: Node, card_cost: int) -> bool:
	var min_cost: int = int(gold.get_meta("only_cost_min", -1))
	return min_cost < 0 or card_cost >= min_cost


## Oros físicos de la Reserva que no sirven para pagar 'card_cost' (gokin).
func unusable_physical_golds(card_cost: int, player_id: int) -> int:
	var reserva: Node = _main.player_gold if player_id == 0 else _main.opponent_gold
	if not reserva:
		return 0
	var n := 0
	for g in reserva.get_children():
		if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO and not gold_usable_for(g, card_cost):
			n += 1
	return n


func puede_pagar(cantidad: int, card_type: int = -1, card_race: String = "", card_cost: int = -1, player_id: int = 0) -> bool:
	var oro_fisico = GameState.get_oro_reserva(player_id) - unusable_physical_golds(card_cost, player_id)
	var restringido = _restricted_gold_available_for(card_type, card_race, card_cost, player_id)
	var disponible = oros_virtuales.get(player_id, 0) + restringido + oro_fisico
	return disponible >= cantidad


func pagar_coste(cantidad: int, card_type: int = -1, card_race: String = "", card_cost: int = -1, player_id: int = 0) -> bool:
	"""card_type/card_race/card_cost identifican qué se paga, para saber si aplica el Oro Virtual
	restringido (p.ej. Padre de la Patria: "para jugar Armas o Aliados Caballero"). Pasar -1/"" si
	no corresponde (p.ej. una habilidad activada) y los pools restringidos se ignoran. player_id:
	de qué jugador se paga (arquitectura.md §33)."""
	EffectContextScript.check_payment(player_id, cantidad)
	var reserva_container: HBoxContainer = _main.player_gold if player_id == 0 else _main.opponent_gold
	if not puede_pagar(cantidad, card_type, card_race, card_cost, player_id):
		# reserva_container.get_child_count() incluye los tokens visuales de
		# Oro Virtual (genérico + restringido) — se restan para no contarlos
		# dos veces en el mensaje.
		var restricted_token_count := 0
		for pool in restricted_gold_pools.get(player_id, []):
			restricted_token_count += pool.tokens.size()
		var oro_fisico_visible = reserva_container.get_child_count() - virtual_gold_tokens.get(player_id, []).size() - restricted_token_count
		var restringido_disp = _restricted_gold_available_for(card_type, card_race, card_cost, player_id)
		var disponible = oros_virtuales.get(player_id, 0) + restringido_disp + oro_fisico_visible
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d (V:%d + R:%d + F:%d)" % [
			cantidad, disponible, oros_virtuales.get(player_id, 0), restringido_disp, oro_fisico_visible])
		return false
	if cantidad <= 0:
		return true
	var restante = cantidad

	# 1. Oro Virtual RESTRINGIDO primero — es el más específico: si no se usa
	# ahora que sí aplica, se pierde igual al pasar de turno, mientras que el
	# genérico y el físico se pueden guardar para otra compra.
	if restante > 0:
		var restr_usados = await _consume_restricted_gold_for(card_type, card_race, card_cost, restante, player_id)
		if restr_usados > 0:
			restante -= restr_usados
			_main._update_debug("Consumido %d Oro Virtual restringido (quedan %d por pagar)" % [restr_usados, restante])

	if restante > 0 and oros_virtuales.get(player_id, 0) > 0:
		var virtuales_usados = mini(oros_virtuales[player_id], restante)
		oros_virtuales[player_id] -= virtuales_usados
		restante -= virtuales_usados
		for i in range(virtuales_usados):
			await _despawn_virtual_gold_token(player_id)
		_main._update_debug("Consumido %d Oro Virtual (quedan %d)" % [virtuales_usados, oros_virtuales[player_id]])
	if restante > 0:
		_main._update_debug("Pagando %d Oro físico..." % restante)
		# El jugador elige CUÁLES Oros físicos gasta (p.ej. Monitor Araucano: "este Oro genera un Oro
		# adicional cuando sea usado para pagar Armas de coste 2 o más" — hay que saber qué Oro pagó). El
		# Oro Virtual (genérico y restringido) se gasta siempre primero.
		# El orden se elige una sola vez (_choose_physical_gold_to_spend() ya junta los que hagan falta) y
		# solo entre Oros físicos (las fichas de Oro Virtual de la Reserva no se pagan así).
		var token_nodes: Array = virtual_gold_tokens.get(player_id, []).duplicate()
		for pool in restricted_gold_pools.get(player_id, []):
			token_nodes.append_array(pool.tokens)
		var oros_reserva: Array = reserva_container.get_children().filter(func(c): return not (c in token_nodes) 			and gold_usable_for(c, card_cost))  # gokin
		var chosen_oros: Array = await _choose_physical_gold_to_spend(oros_reserva, restante, player_id)
		var chosen_idx := 0

		# Se gasta un Oro físico a la vez: el Oro adicional de Monitor Araucano cuenta para ESTA compra,
		# así que antes del siguiente se revisa si apareció Oro Virtual nuevo.
		var diverted := 0
		var physical_spent := 0
		while restante > 0:
			if oros_virtuales.get(player_id, 0) > 0:
				var v_now: int = mini(oros_virtuales[player_id], restante)
				oros_virtuales[player_id] -= v_now
				restante -= v_now
				for i in range(v_now):
					await _despawn_virtual_gold_token(player_id)
				if restante <= 0:
					break
			if chosen_idx >= chosen_oros.size():
				break  # no debería pasar (puede_pagar() ya validó), pero no colgarse si pasa
			var oro_card = chosen_oros[chosen_idx]
			chosen_idx += 1
			if not is_instance_valid(oro_card):
				continue
			# diverted = unidades que no terminaron en el Oro Pagado (p.ej. Jormundgander vuelve a ser
			# Aliado): se restan después de GameState.pagar_oro() para no regalar Oro en el próximo
			# Reagrupamiento.
			var was_diverted: bool = await _mover_oro_a_pagado(oro_card)
			if was_diverted:
				diverted += 1
			physical_spent += 1
			restante -= 1
			_resolve_gold_paid_reaction(oro_card, card_type, card_race, card_cost, player_id)
		GameState.pagar_oro(player_id, physical_spent)
		if diverted > 0:
			GameState.agregar_oro_pagado(player_id, -diverted)
	TurnManager.any_card_played_this_turn = true
	var oro_restante = GameState.get_oro_reserva(player_id)
	_main._update_debug("Pagado %d Oro total (Reserva: %d, Virtual: %d)" % [cantidad, oro_restante, oros_virtuales.get(player_id, 0)])
	_update_gold_display()
	return true


func _choose_physical_gold_to_spend(oros_reserva: Array, restante: int, player_id: int = 0) -> Array:
	"""Elige qué Oros físicos de la Reserva se gastan para 'restante' unidades. Si no hay elección
	real (hay que gastar todos, o queda uno), no pregunta."""
	if restante >= oros_reserva.size() or oros_reserva.size() <= 1:
		return oros_reserva.slice(0, mini(restante, oros_reserva.size()))
	if not _main._card_interaction:
		return oros_reserva.slice(0, restante)

	# Click directo sobre las cartas (CardInteractionModule.await_target(), como el resto del juego),
	# con el brillo de "activable" en los Oros válidos.
	var chosen: Array = []
	var remaining_candidates: Array = oros_reserva.duplicate()
	for c in remaining_candidates:
		if is_instance_valid(c):
			c.set_activatable(true, CardBadges.GLOW_COLOR_GOLD, &"target_select")

	while chosen.size() < restante and not remaining_candidates.is_empty():
		var filter := func(c: Node) -> bool:
			return c in remaining_candidates
		var picked: Node = await _main._card_interaction.await_target(
			"Elige qué Oro gastar (%d de %d)" % [chosen.size() + 1, restante], filter, true, player_id)
		if not picked or not is_instance_valid(picked):
			break  # cancelado (ESC) — se completa abajo con el orden mecánico de siempre
		remaining_candidates.erase(picked)
		picked.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
		chosen.append(picked)

	for c in remaining_candidates:
		if is_instance_valid(c):
			c.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")

	if chosen.size() < restante:
		# Cancelado a mitad de camino (ESC) — completar con las que falten
		# en el orden mecánico de siempre, para no dejar el pago sin
		# resolver a medio camino.
		for c in oros_reserva:
			if chosen.size() >= restante:
				break
			if c not in chosen:
				chosen.append(c)

	return chosen


var _alicanto_paid_pending: Dictionary = {}


func _resolve_gold_paid_reaction(oro_card: Node, card_type: int, card_race: String, card_cost: int, player_id: int = 0) -> void:
	""""Este Oro genera un Oro adicional cuando sea usado para pagar X (de coste N o más)" (p.ej.
	Monitor Araucano), sobre el Oro que efectivamente pagó."""
	if not is_instance_valid(oro_card):
		return
	var ability_text: String = oro_card.get("card_ability") if oro_card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return
	var lower := _fix_mojibake(ability_text).to_lower()
	# Trono del Cielo: "Si en su turno anterior tu oponente generó o puso en juego más de un Oro,
	# cuenta como dos Oros para pagar el coste de una carta."
	if "cuenta como dos oros para pagar el coste de una carta" in lower and card_type >= 0 \
			and not KeywordManager.is_silenced(oro_card) and int(_gold_events_prev.get(1 - player_id, 0)) > 1:
		generar_oros_virtuales(1, player_id)
		_main._update_debug("%s cuenta como dos Oros" % str(oro_card.get("card_name")))
	# Alicanto: "Los Aliados de coste 2 o más pagados con este Oro no pueden ser Anulados" — se marca y
	# lo toma el próximo Aliado que entra (_trigger_enter_play), antes de su ventana de respuesta.
	if "aliados de coste 2 o más pagados con este oro no pueden ser anulados" in lower \
			and card_type == Constants.CardType.ALIADO and card_cost >= 2 and not KeywordManager.is_silenced(oro_card):
		_alicanto_paid_pending[player_id] = true
	if not ("este oro genera un oro adicional cuando sea usado para pagar" in lower):
		return

	var wanted_type: int = -1
	if "armas" in lower:
		wanted_type = Constants.CardType.ARMA
	elif "aliados" in lower:
		wanted_type = Constants.CardType.ALIADO
	elif "talismanes" in lower:
		wanted_type = Constants.CardType.TALISMAN
	elif "tótems" in lower or "totems" in lower:
		wanted_type = Constants.CardType.TOTEM
	if wanted_type != -1 and card_type != wanted_type:
		return

	var cost_rx := RegEx.new()
	cost_rx.compile("(?i)coste\\s+(\\w+)\\s+o\\s+m[aá]s")
	var m_cost := cost_rx.search(ability_text)
	if m_cost:
		var min_cost: int = UniversalCardParser._parse_amount(m_cost.get_string(1))
		if card_cost < min_cost:
			return

	generar_oros_virtuales(1, player_id)
	_main._update_debug("%s generó 1 Oro adicional" % str(oro_card.get("card_name")))


func generar_oros_virtuales(cantidad: int, player_id: int = 0) -> void:
	oros_virtuales[player_id] = oros_virtuales.get(player_id, 0) + cantidad
	_note_gold_event(player_id, cantidad)
	var tokens: Array = virtual_gold_tokens.get(player_id, [])
	for i in range(cantidad):
		_spawn_gold_token("Oro Virtual Libre", "Libre", tokens, player_id)
	virtual_gold_tokens[player_id] = tokens
	_main._update_debug("Generado %d Oro Virtual (total: %d)" % [cantidad, oros_virtuales[player_id]])
	_update_gold_display()


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


func generar_oro_virtual_restringido(cantidad: int, predicate: Callable, label: String, player_id: int = 0,
		until_own_next_turn: bool = false) -> void:
	_note_gold_event(player_id, cantidad)
	"""Oro Virtual que SOLO paga cartas que cumplan 'predicate(card_type,
	card_race) -> bool' (p.ej. Padre de la Patria: 'para jugar Armas o
	Aliados Caballero'). A diferencia de generar_oros_virtuales(), queda
	guardado en restricted_gold_pools[player_id] como su propia entrada —
	varias fuentes con distintas restricciones pueden coexistir sin
	mezclarse."""
	var tokens: Array = []
	for i in range(cantidad):
		_spawn_gold_token("Oro Virtual (%s)" % label, label, tokens, player_id)
	var pools: Array = restricted_gold_pools.get(player_id, [])
	# until_own_next_turn (Sariel: "Puedes usar ese Oro hasta el comienzo de tu próximo turno"):
	# sobrevive al comienzo del turno rival.
	pools.append({"amount": cantidad, "tokens": tokens, "predicate": predicate, "label": label,
		"until_player": player_id if until_own_next_turn else -1})
	restricted_gold_pools[player_id] = pools
	_main._update_debug("Generado %d Oro Virtual restringido (%s)" % [cantidad, label])
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


func _restricted_gold_available_for(card_type: int, card_race: String, card_cost: int = -1, player_id: int = 0) -> int:
	if card_type < 0:
		return 0
	var total := 0
	for pool in restricted_gold_pools.get(player_id, []):
		if pool.predicate.call(card_type, card_race, card_cost):
			total += pool.amount
	return total


func _consume_restricted_gold_for(card_type: int, card_race: String, card_cost: int, needed: int, player_id: int = 0) -> int:
	var pools: Array = restricted_gold_pools.get(player_id, [])
	if card_type < 0 or needed <= 0 or pools.is_empty():
		return 0
	var consumed := 0
	var empty_indices: Array = []
	for i in range(pools.size()):
		if consumed >= needed:
			break
		var pool: Dictionary = pools[i]
		if not pool.predicate.call(card_type, card_race, card_cost):
			continue
		var usa: int = mini(pool.amount, needed - consumed)
		pool.amount -= usa
		consumed += usa
		for j in range(usa):
			await _despawn_gold_token(pool.tokens, player_id)
		if pool.amount <= 0:
			empty_indices.append(i)
	for i in range(empty_indices.size() - 1, -1, -1):
		pools.remove_at(empty_indices[i])
	restricted_gold_pools[player_id] = pools
	return consumed


func _spawn_gold_token(nombre: String, label: String, target_list: Array, player_id: int = 0) -> void:
	_visuals._spawn_gold_token(nombre, label, target_list, player_id)


func _despawn_virtual_gold_token(player_id: int = 0) -> void:
	var tokens: Array = virtual_gold_tokens.get(player_id, [])
	await _despawn_gold_token(tokens, player_id)
	virtual_gold_tokens[player_id] = tokens


func _despawn_gold_token(target_list: Array, player_id: int = 0) -> void:
	await _visuals._despawn_gold_token(target_list, player_id)


func _mover_oro_a_pagado(card: Node) -> bool:
	"""Devuelve true si la carta se desvió del movimiento normal (Jormundgander: vuelve a ser el
	Aliado original), false si fue al Oro Pagado. pagar_coste() lo usa para no contar de más en
	GameState."""
	if card.get("revert_to_data") != null and not (card.revert_to_data as Dictionary).is_empty():
		await _revert_gold_to_ally(card)
		return true
	# Caos: "Cuando lo pagues, conviértelo en un Aliado de Fuerza 3".
	if card.get_meta("caos_gold", false) and not KeywordManager.is_silenced(card):
		load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").caos_to_ally(_main, card)
		return true
	# controller_id (no siempre el Anfitrión): el Oro puede ser del rival (Tyet: "Puedes pagar este Oro
	# para que un Oro pierda su habilidad este turno y muévelo al Oro Pagado").
	var controller_id: int = card.controller_id if card.get("controller_id") != null else 0
	var reserva_container: HBoxContainer = _main.player_gold if controller_id == 0 else _main.opponent_gold
	var pagado_container: HBoxContainer = _main.player_oro_pagado if controller_id == 0 else _main.opponent_oro_pagado
	var start_pos = card.global_position
	reserva_container.remove_child(card)
	card.can_interact = false
	pagado_container.add_child(card)
	update_gold_containers_spacing()
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.25)
	await tween.finished
	card.can_interact = true
	return false


func _revert_gold_to_ally(card: Node) -> void:
	"""Jormundgander: "Si esta carta es un Oro, cuando lo pagues para jugar un Aliado, convierte este
	Oro en un Aliado y muévelo a tu Línea de Defensa" — la otra mitad de
	convert_ally_to_gold_in_pagado()."""
	var original_data: Dictionary = card.revert_to_data.duplicate()
	card.revert_to_data = {}
	var start_pos = card.global_position
	_main.player_gold.remove_child(card)
	card.can_interact = false
	card.load_from_data(original_data)
	_main.player_field.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	await get_tree().process_frame
	# Slot fijo (ZoneManager.pin_card_to_field_slot(), igual que _play_card_to_field()).
	var end_pos: Vector2 = _main._zone_manager.pin_card_to_field_slot(card, _main.player_field)
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), 0.3)
	await tween.finished
	card.can_interact = true
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	_update_gold_display()
	await _trigger_enter_play(card, Constants.Zone.LINEA_DEFENSA)


## Azi del Abismo: "convertir este Aliado hasta tu próximo turno en un Oro con la habilidad ...".
## Queda en tu Oro Pagado con esa habilidad y, al empezar tu próximo turno, vuelve a ser el Aliado
## original (revert_converted_golds()).
func convert_ally_to_gold_until_next_turn(card: Node, gold_ability: String) -> void:
	if not is_instance_valid(card):
		return
	var pid: int = card.controller_id if card.get("controller_id") != null else 0
	var pagado: Node = PlayerSideScript.oro_pagado(_main, pid)
	var field = card.get_parent()
	var start_pos: Vector2 = card.global_position
	card.set_meta("converted_until_turn_of", pid)
	card.set_meta("converted_original_data", card.card_data.duplicate())
	if field:
		field.remove_child(card)
		if field is Control and _main._zone_manager:
			_main._zone_manager.compact_field_slots(field)
	card.can_interact = false
	var new_data: Dictionary = card.card_data.duplicate()
	new_data["tipo"] = Constants.CardType.ORO
	new_data["habilidad"] = gold_ability
	# Sus efectos continuos de Aliado ("Tus demás Aliados ganan 1 de
	# Fuerza") no siguen mientras es un Oro.
	ContinuousEffectManager.remove_modifiers_from_source(card)
	ContinuousEffectManager._invalidate_cache()
	card.load_from_data(new_data)
	pagado.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.ORO_PAGADO)
	card.scale = Constants.GOLD_CARD_SCALE
	card.base_scale = Constants.GOLD_CARD_SCALE
	GameState.agregar_oro_pagado(pid, 1)
	update_gold_containers_spacing()
	_update_gold_display()
	await get_tree().process_frame
	var end_pos: Vector2 = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.3)
	await tween.finished
	card.can_interact = true
	_main._update_debug("%s se convierte en un Oro en tu Oro Pagado hasta tu próximo turno" % str(card.card_name))


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


func convert_ally_to_gold_in_pagado(card: Node) -> void:
	"""Jormundgander: "Cuando haga daño, puedes convertirlo en un Oro y moverlo a tu Oro Pagado" —
	queda gastado hasta el próximo Reagrupamiento. Guarda los datos originales en
	card.revert_to_data para reconvertirlo si se lo paga (_mover_oro_a_pagado())."""
	if not is_instance_valid(card):
		return
	var owner_id: int = card.owner_id if card.get("owner_id") != null else 0
	# También para el jugador 1 (su Oro Pagado).
	var pagado_container: Node = PlayerSideScript.oro_pagado(_main, owner_id)

	card.revert_to_data = card.card_data.duplicate()

	var start_pos = card.global_position
	var parent = card.get_parent()
	if parent:
		parent.remove_child(card)
	card.can_interact = false

	# Re-tipar como Oro: card_data y las propiedades derivadas que el resto
	# del motor lee (PaymentManager.calcular_coste_real, filtros de
	# búsqueda/selección, etc.) leen card_type/card_cost, no re-parsean el
	# texto de la carta.
	var new_data: Dictionary = card.card_data.duplicate()
	new_data["tipo"] = Constants.CardType.ORO
	card.load_from_data(new_data)

	pagado_container.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.ORO_PAGADO)
	card.scale = Constants.GOLD_CARD_SCALE
	card.base_scale = Constants.GOLD_CARD_SCALE
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(0.6, 0.6, 0.6, 1.0), 0.3)
	await tween.finished
	card.can_interact = true
	GameState.agregar_oro_pagado(owner_id, 1)
	if owner_id == 0:
		_main.gold_cards.append(card)  # gold_cards es solo la Reserva del Anfitrión
	_update_gold_display()


func _mover_oro_a_reserva(card: Node) -> void:
	var start_pos = card.global_position
	_main.player_oro_pagado.remove_child(card)
	card.can_interact = false
	_main.player_gold.add_child(card)
	update_gold_containers_spacing()
	await get_tree().process_frame
	var end_pos = card.global_position
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), 0.25)
	await tween.finished
	card.can_interact = true


func agrupar_oros(player_id: int, amount: int) -> int:
	"""'Agrupa un Oro': hasta 'amount' Oros del Oro Pagado de 'player_id' vuelven a su Reserva (como
	en la Agrupación). Si hay más que 'amount', el jugador elige (el Remoto por red, el bot los
	primeros). Devuelve cuántos agrupó."""
	var pagado: Node = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	if not pagado:
		return 0
	var candidates: Array = pagado.get_children().filter(func(c): return is_instance_valid(c))
	if candidates.is_empty():
		return 0
	var chosen: Array = candidates
	if candidates.size() > amount:
		if PlayerSideScript.is_bot(player_id):
			chosen = candidates.slice(0, amount)
		else:
			chosen = await _main._card_interaction.await_multi_target(
				"Agrupa %d Oro%s de tu Oro Pagado" % [amount, "" if amount == 1 else "s"],
				candidates, amount, Callable(), Callable(), false, null, player_id)
	var moved := 0
	for card in chosen.slice(0, amount):
		if await _agrupar_oro(player_id, card):
			moved += 1
	_update_gold_display()
	_main._update_debug("%d Oro%s agrupado%s" % [moved, "" if moved == 1 else "s", "" if moved == 1 else "s"])
	return moved


func _agrupar_oro(player_id: int, card: Node) -> bool:
	var pagado: Node = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	if not is_instance_valid(card) or not pagado or card.get_parent() != pagado:
		return false
	GameState.agregar_oro_pagado(player_id, -1)
	GameState.agregar_oro_reserva(player_id, 1)
	if player_id == 0:
		await _mover_oro_a_reserva(card)
	else:
		pagado.remove_child(card)
		card.can_interact = false
		_main.opponent_gold.add_child(card)
		update_gold_containers_spacing()
	card.set_zone(Constants.Zone.RESERVA_ORO)
	return true


func agrupar_cartas(player_id: int, amount: int) -> int:
	"""'Agrupa dos cartas' (iga ryu): hasta 'amount' cartas propias hacen lo de la Agrupación (DAR
	5.1): un Oro Pagado vuelve a la Reserva, un Aliado de Línea de Ataque vuelve a Defensa. El bot
	agrupa primero Oros. Devuelve cuántas agrupó."""
	var pagado: Node = _main.player_oro_pagado if player_id == 0 else _main.opponent_oro_pagado
	var atk: Node = _main.player_linea_ataque if player_id == 0 else _main.opponent_linea_ataque
	var golds: Array = pagado.get_children().filter(func(c): return is_instance_valid(c)) if pagado else []
	var attackers: Array = atk.get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO) if atk else []
	var candidates: Array = golds + attackers
	if candidates.is_empty():
		return 0
	var chosen: Array = candidates
	if candidates.size() > amount:
		if PlayerSideScript.is_bot(player_id):
			chosen = candidates.slice(0, amount)
		else:
			chosen = await _main._card_interaction.await_multi_target(
				"Agrupa %d carta%s (Oro Pagado o Línea de Ataque)" % [amount, "" if amount == 1 else "s"],
				candidates, amount, Callable(), Callable(), false, null, player_id)
	var moved := 0
	for card in chosen.slice(0, amount):
		if card in golds:
			if await _agrupar_oro(player_id, card):
				moved += 1
		elif is_instance_valid(card) and card.get_parent() == atk and _main._card_interaction:
			await _main._card_interaction.unmark_attackers([card])
			moved += 1
	_update_gold_display()
	_main._update_debug("%d carta%s agrupada%s" % [moved, "" if moved == 1 else "s", "" if moved == 1 else "s"])
	return moved


func _reset_gold() -> void:
	"""Reagrupamiento del Oro (DAR, Agrupación): el Oro Pagado propio vuelve a la Reserva al empezar
	el turno. Lo llama PhaseFlowController. GameState.reagrupar_oro() resetea los contadores
	primero y después se mueven las cartas una a una con _mover_oro_a_reserva() (que no toca
	GameState)."""
	GameState.reagrupar_oro(0)
	# uriko-hime: "tu oponente sólo pueda agrupar hasta cuatro Oros en su próxima Agrupación".
	var cap: int = int(RuleState.take_pending("regroup_cap", 0)) if RuleState.has_pending("regroup_cap", 0) else -1
	var regrouped := 0
	if _main.player_oro_pagado:
		for card in _main.player_oro_pagado.get_children().duplicate():
			if is_instance_valid(card):
				# el huascar: "no puede ser agrupado el próximo turno".
				if int(card.get_meta("no_regroup_turn", -1)) == GameManager.turn_serial or card.get_meta("never_regroup", false) \
						or (cap >= 0 and regrouped >= cap):  # alma del viento, uriko-hime
					GameState.agregar_oro_reserva(0, -1)
					GameState.agregar_oro_pagado(0, 1)
					continue
				await _mover_oro_a_reserva(card)
				regrouped += 1
	_update_gold_display()


func get_oro_disponible(player_id: int = 0) -> int:
	return GameState.get_oro_reserva(player_id)


func get_oro_pagado(player_id: int = 0) -> int:
	return GameState.get_oro_pagado(player_id)


func get_oro_total(player_id: int = 0) -> int:
	return GameState.get_oro_total(player_id)
