extends Node
## ActionModule - Funciones modulares para acciones de cartas (DAR Sección 8)
## Emite señales para AnimationQueue y maneja triggers simultáneos (DAR 7.4)
## Cada verbo (Draw/Search/Mill/Destroy/Banish/ReturnDeck+Discard) vive en su
## propio módulo extraído (Fase 4 de reestructuración, "módulos gordos") —
## ActionModule.gd se queda con las señales, las referencias compartidas
## (game board, validador, filtro de cartas, recolección de triggers) y
## forwarders finos con el nombre/firma exactos de antes, así que ningún
## llamador externo (65x draw, 36x search, 23x return_to_deck, 19x destroy,
## 18x discard, 15x banish, 12x mill en todo el proyecto) necesita cambiar.

# =============================================================================
# SEÑALES PARA ANIMATIONQUEUE
# =============================================================================
## Robar
signal action_draw_started(player_id: int, amount: int, source: String)
signal action_draw_card(player_id: int, card: Node, index: int, total: int)
signal action_draw_completed(player_id: int, cards: Array, actual: int)

## Buscar
signal action_search_started(player_id: int, zone: int, filter: Dictionary)
signal action_search_revealed(player_id: int, matching_cards: Array)
signal action_search_selected(player_id: int, selected: Array)
signal action_search_completed(player_id: int, result: Dictionary)

## Moler (Mill)
signal action_mill_started(player_id: int, amount: int, to_exile: bool)
signal action_mill_card(player_id: int, card: Node, destination: int, index: int)
signal action_mill_completed(player_id: int, cards: Array)

## Destruir
signal action_destroy_started(targets: Array, source: Node)
signal action_destroy_card(card: Node, by_source: Node)
signal action_destroy_completed(destroyed: Array, survived: Array)

## Desterrar (Banish/Exile)
signal action_banish_started(targets: Array, source: Node)
signal action_banish_card(card: Node, from_zone: int)
signal action_banish_completed(banished: Array)

## Descartar
signal action_discard_started(player_id: int, cards: Array)
signal action_discard_card(player_id: int, card: Node, index: int)
signal action_discard_completed(player_id: int, discarded: Array)

## Triggers
signal triggers_collected(active_triggers: Array, opponent_triggers: Array)
signal trigger_resolution_started(trigger: Dictionary)
signal trigger_resolution_completed(trigger: Dictionary, result: Dictionary)

## Validación (DAR Sección 6)
signal action_validation_failed(action_type: String, reason: String, context: Dictionary)
signal action_validation_passed(action_type: String, can_resolve_percent: float)

# =============================================================================
# REFERENCIAS
# =============================================================================
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
var _game_board: Node = null

## Módulos extraídos (Fase 4 de reestructuración)
var _validator: ActionValidator
var _action_draw: RefCounted
var _action_search: RefCounted
var _action_mill: RefCounted
var _action_destroy: RefCounted
var _action_banish: RefCounted
var _action_return_discard: RefCounted


func _ready() -> void:
	_validator = ActionValidator.new()
	_validator.setup(self)

	_action_draw = preload("res://scripts/core/effects/actions/ActionDraw.gd").new()
	_action_draw.setup(self)
	_action_search = preload("res://scripts/core/effects/actions/ActionSearch.gd").new()
	_action_search.setup(self)
	_action_mill = preload("res://scripts/core/effects/actions/ActionMill.gd").new()
	_action_mill.setup(self)
	_action_destroy = preload("res://scripts/core/effects/actions/ActionDestroy.gd").new()
	_action_destroy.setup(self)
	_action_banish = preload("res://scripts/core/effects/actions/ActionBanish.gd").new()
	_action_banish.setup(self)
	_action_return_discard = preload("res://scripts/core/effects/actions/ActionReturnDiscard.gd").new()
	_action_return_discard.setup(self)

	# Obtener referencias diferidas (por orden de autoloads)
	call_deferred("_get_references")
	print("[ActionModule] Inicializado")


func _get_references() -> void:
	# TriggerSystem/AnimationQueue/DamageManager son autoloads: se referencian directo.
	if GameManager:
		_game_board = GameManager.game_board


func _get_game_board() -> Node:
	if _game_board and is_instance_valid(_game_board):
		return _game_board
	if GameManager and GameManager.game_board:
		_game_board = GameManager.game_board
	return _game_board


# =============================================================================
# VALIDACIÓN DE ESTADO DE JUEGO (implementación en ActionValidator.gd)
# =============================================================================
func validate_action(action_type: String, params: Dictionary, context: Dictionary = {}) -> Dictionary:
	return _validator.validate_action(action_type, params, context)


# =============================================================================
# DRAW - Robar cartas (implementación en ActionDraw.gd)
# =============================================================================
func draw(player_id: int, amount: int, source: String = "", skip_validation: bool = false) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	# creación de temaukel: "tu oponente no puede ... Robar cartas por efectos" (el robo del turno no pasa por aquí).
	if RuleState.active("no_effect_draw", player_id):
		return {"success": false, "prevented": true}
	# sabiduría de la oruga: "sólo pueden Robar hasta tres cartas por efectos por turno".
	if RuleState.active("draw_cap_3", player_id):
		amount = mini(amount, maxi(0, 3 - RuleState.count("effect_draws", player_id)))
		RuleState.add("effect_draws", player_id, amount)
		if amount <= 0:
			return {"success": false, "prevented": true}
	var drawn: Dictionary = await _action_draw.draw(player_id, amount, source, skip_validation)
	# Sesión Espiritista: "cada vez que tu oponente ponga cartas en su mano por un efecto, puedes poner esa
	# misma cantidad de cartas del tope de tu Castillo en tu mano".
	await load("res://scripts/core/effects/mechanics/TalismanPatterns.gd").on_opponent_effect_draw(player_id, amount)
	load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("effect_draw", {"pid": player_id, "amount": amount})  # berserker z
	return drawn


func draw_up_to(player_id: int, max_amount: int, source: String = "", skip_validation: bool = false) -> Dictionary:
	""""Roba hasta N cartas" (p.ej. Mecha-Daikaiju): tu Castillo brilla y cada clic roba una carta; N
	(o ESC) para no robar más. El bot roba todas. El Remoto usa el mismo prompt "carta o Castillo"
	de await_target_or_castillo_pick()."""
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	var main: Node = get_tree().root.get_node_or_null("Main")
	if max_amount <= 0 or PlayerSideScript.is_bot(player_id) or not main or not main._card_interaction:
		return await _action_draw.draw(player_id, max_amount, source, skip_validation)
	var drawn := 0
	while drawn < max_amount and CardManager.get_deck_count(player_id) > 0:
		var pick: Dictionary = await main._card_interaction.await_target_or_castillo_pick(
			"Roba hasta %d cartas (%d robadas): clic en tu Castillo para robar una — N para no robar más" % [max_amount, drawn],
			func(_c: Node) -> bool: return false, "Robar una carta", true, true, player_id)
		if str(pick.get("type", "none")) != "castillo":
			break
		await _action_draw.draw(player_id, 1, source, skip_validation)
		drawn += 1
	return {"success": true, "drawn": drawn}


# =============================================================================
# SEARCH - Buscar en zona (implementación en ActionSearch.gd)
# =============================================================================
func shuffle_deck(player_id: int) -> void:
	"""Baraja el Castillo de un jugador vía CardManager (sincronizado por referencia con
	Main.player_deck/opponent_deck, ver sync_from_main). Barajar cambia qué carta queda en el tope
	(índice 0): refresca ZoneManager._update_castillo_counts() (p.ej. el revelado de La Ouija) para
	todos los llamadores."""
	CardManager.shuffle_deck(player_id)
	var main := get_node_or_null("/root/Main")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


func search(player_id: int, zone: int, filter: Dictionary, amount: int = 1, can_fail: bool = true, skip_validation: bool = false, may_play: bool = false, source_card = null, destination: int = Constants.Zone.MANO, distinct_names: bool = false, chooser_id: int = -1) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	return await _action_search.search(player_id, zone, filter, amount, can_fail, skip_validation, may_play, _live(source_card), destination, distinct_names, chooser_id)


## La carta fuente puede haber salido del juego (y liberarse) mientras el efecto esperaba: los
## parámetros 'source' de la fachada van sin tipo (un Nodo liberado en un parámetro Node rompe la
## llamada: "previously freed") y aquí se pasan como null.
static func _live(node) -> Node:
	return node if is_instance_valid(node) and node is Node else null


## Búsqueda en varias zonas a la vez con el selector del tablero (ver ActionSearch.search_zones).
func search_zones(player_id: int, zones: Array, filter: Dictionary, amount: int = 1, can_fail: bool = true,
		skip_validation: bool = false, may_play: bool = false, source_card = null,
		destination: int = Constants.Zone.MANO, distinct_names: bool = false, chooser_id: int = -1,
		cost_reduction: int = 0, cost_floor_zero: bool = false) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	return await _action_search.search_zones(player_id, zones, filter, amount, can_fail, skip_validation, may_play,
		_live(source_card), destination, distinct_names, chooser_id, cost_reduction, cost_floor_zero)


## 'Busca en UN Castillo/Cementerio' (sin posesivo): selector con las zonas de los dos jugadores,
## atado al primer Castillo que se mira (ver ActionSearch.search_either_owner).
func search_either_owner(chooser: int, zones: Array, filter: Dictionary, amount: int, can_fail: bool = true,
		source_card = null, destination: int = Constants.Zone.MANO, distinct_names: bool = false,
		one_zone: bool = false) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true, "selected": []}
	return await _action_search.search_either_owner(chooser, zones, filter, amount, can_fail, _live(source_card),
		destination, distinct_names, one_zone)


## Selector de zonas (+ cartas de la mano) para quien elige: Anfitrión, Remoto o bot (ver
## ActionSearch.pick_in_zones).
func pick_in_zones(chooser: int, title: String, pools: Array, min_count: int, max_count: int,
		distinct_names: bool = false, hand_nodes: Array = [], out_info: Dictionary = {}) -> Array:
	return await _action_search.pick_in_zones(chooser, title, pools, min_count, max_count, distinct_names, hand_nodes, out_info)


## BanishOpponentPatterns ya llamaba a esto vía ActionModule, pero la fachada no existía.
func _put_found_card_into_play(main: Node, player_id: int, card_data: Dictionary, may_play: bool) -> Node:
	return await _action_search._put_found_card_into_play(main, player_id, card_data, may_play)


# =============================================================================
# MILL - Moler cartas (implementación en ActionMill.gd)
# =============================================================================
func mill(player_id: int, amount: int, to_exile: bool = false, source: String = "", skip_validation: bool = false) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	if EffectController.fision_blocks_player_effect(player_id):  # Fisión Nuclear
		return {"success": false, "prevented": true}
	# Polvo de Hadas: "prevenir que Botes o Destierres cartas del tope de tu Castillo por un efecto oponente".
	if EffectController._current_effect_controller(null) == 1 - player_id \
			and await EffectController.offer_prevention_for_player(player_id, null, "mill"):
		return {"success": false, "prevented": true}
	# duelo mágico: "por el resto del juego no puede Botar más de diez cartas por turno".
	if RuleState.active("mill_cap_10", player_id):
		amount = mini(amount, maxi(0, 10 - RuleState.count("milled_cards", player_id)))
		RuleState.add("milled_cards", player_id, amount)
		if amount <= 0:
			return {"success": false, "prevented": true}
	# Pan de Muerto: hasta quince por Castillo por turno.
	var limits = load("res://scripts/core/effects/mechanics/TurnLimits.gd")
	var room: int = limits.castle_removal_room(player_id)
	if room >= 0:
		amount = mini(amount, room)
		if amount <= 0:
			return {"success": false, "prevented": true}
		limits.note_castle_removed(player_id, amount)
	var ctx_card = EffectContextScript.current().get("card")
	var out: Dictionary = await _action_mill.mill(player_id, amount, to_exile, source, skip_validation)
	# Caos: "Cuando haga daño" incluye el daño directo (DAR: Botar) de un efecto del propio Aliado al rival.
	if int(out.get("actual", 0)) > 0 and is_instance_valid(ctx_card) and ctx_card is Node and ctx_card.get_meta("caos_ally", false) \
			and int(ctx_card.get("controller_id")) == 1 - player_id and get_node_or_null("/root/Main"):
		load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").caos_back_to_gold(get_node_or_null("/root/Main"), ctx_card)
	return out


# =============================================================================
# DESTROY - Destruir cartas (implementación en ActionDestroy.gd)
# =============================================================================
func destroy(targets: Array, source = null, can_be_prevented: bool = true, skip_validation: bool = false) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	return await _action_destroy.destroy(targets, _live(source), can_be_prevented, skip_validation)


# =============================================================================
# BANISH - Desterrar cartas (implementación en ActionBanish.gd)
# =============================================================================
func banish(targets: Array, source = null, skip_validation: bool = false, can_be_prevented: bool = true) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	return await _action_banish.banish(targets, _live(source), skip_validation, can_be_prevented)


# =============================================================================
# RETURN TO DECK + DISCARD (implementación en ActionReturnDiscard.gd)
# =============================================================================
func return_to_deck(card: Node, player_id: int, to_top: bool = true, source = null) -> bool:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return false
	return await _action_return_discard.return_to_deck(card, player_id, to_top, _live(source))


func discard(player_id: int, cards: Array, source: String = "", skip_validation: bool = false) -> Dictionary:
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return {"success": false, "cancelled": true}
	if EffectController.fision_blocks_player_effect(player_id):  # Fisión Nuclear
		return {"success": false, "prevented": true}
	# forma de leopardo / guardia varega: "no pueden descartar cartas por efectos" (un coste no es un efecto,
	# el límite de mano tampoco).
	if RuleState.active("no_effect_discard", player_id) and source != "coste" \
			and not EffectContextScript.current().is_empty():
		var lock_main := get_node_or_null("/root/Main")
		if lock_main:
			lock_main._update_debug("No se pueden descartar cartas por efectos")
		return {"success": false, "prevented": true}
	# duelo mágico: "ni Descartar y/o Desterrar más de una carta de su mano por turno".
	if RuleState.active("hand_loss_cap_1", player_id):
		var room: int = maxi(0, 1 - RuleState.count("hand_cards_lost", player_id))
		cards = cards.slice(0, room)
		RuleState.add("hand_cards_lost", player_id, cards.size())
		if cards.is_empty():
			return {"success": false, "prevented": true}
	var lost_cost: int = int(cards[0].get("card_cost")) if not cards.is_empty() and is_instance_valid(cards[0]) and cards[0].get("card_cost") != null else 0
	var by_effect: bool = not EffectContextScript.current().is_empty()
	var out: Dictionary = await _action_return_discard.discard(player_id, cards, source, skip_validation)
	if not cards.is_empty():
		load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("hand_loss", {"pid": player_id, "cost": lost_cost, "by_effect": by_effect})  # inari
	return out


# =============================================================================
# SISTEMA DE TRIGGERS SIMULTÁNEOS (DAR 7.4)
# =============================================================================
## Se queda aquí (no extraído): dependencia interna compartida por los 6
## módulos de verbo de arriba — cada uno la llama vía _main._X().
var _collecting_triggers: bool = false
var _collected_triggers: Array[Dictionary] = []


func _begin_trigger_collection() -> void:
	"""Inicia la recolección de triggers para una acción"""
	_collecting_triggers = true
	_collected_triggers.clear()
	# No toca TriggerSystem.begin_collecting(): marcaba is_collecting y, sin nada que recolectar (casi
	# siempre: GameManager.game_board no se asigna), nadie lo bajaba. La siguiente carta que entraba en
	# juego esperaba 3 s y TriggerSystem forzaba un reset que también apagaba is_resolving (un efecto
	# podía resolverse encima de otro). También borraba los pendientes de una recolección real en curso.


func _notify_trigger(trigger_type: String, event_data: Dictionary) -> void:
	"""Notifica un trigger al sistema"""
	if not _collecting_triggers:
		return

	# Buscar cartas que reaccionen a este trigger
	var board = _get_game_board()
	if not board:
		return

	# Revisar cartas en juego de ambos jugadores
	for player_id in [0, 1]:
		for zone in Constants.ZONES_IN_PLAY:
			var cards = board.get_cards_in_zone(zone, player_id)
			for card in cards:
				if card.has_method("has_trigger") and card.has_trigger(trigger_type):
					# Verificar condiciones del trigger
					if card.has_method("_trigger_conditions_met"):
						if not card._trigger_conditions_met(trigger_type, event_data):
							continue

					var trigger_data = {
						"card": card,
						"trigger_type": trigger_type,
						"event_data": event_data,
						"controller_id": card.controller_id if card.get("controller_id") != null else player_id
					}

					_collected_triggers.append(trigger_data)

					TriggerSystem.register_trigger(card, trigger_type, event_data)


func _end_trigger_collection_and_resolve() -> void:
	"""Finaliza recolección y resuelve triggers en orden (DAR 7.4)"""
	_collecting_triggers = false

	if _collected_triggers.is_empty():
		return

	# Ordenar triggers: primero jugador activo, luego oponente
	var active_player = 0
	if GameManager:
		active_player = GameManager.active_player_id

	var active_triggers: Array = []
	var opponent_triggers: Array = []

	for trigger in _collected_triggers:
		if trigger.controller_id == active_player:
			active_triggers.append(trigger)
		else:
			opponent_triggers.append(trigger)

	emit_signal("triggers_collected", active_triggers, opponent_triggers)

	# Resolver triggers
	await _resolve_collected_triggers(active_triggers + opponent_triggers)

	_collected_triggers.clear()


func _resolve_collected_triggers(triggers: Array) -> void:
	"""Resuelve la cola de triggers recolectados"""
	for trigger in triggers:
		emit_signal("trigger_resolution_started", trigger)

		var result = {"success": true}
		var card = trigger.get("card")

		if is_instance_valid(card) and card.has_method("_on_trigger_event"):
			result = await card._on_trigger_event(trigger.trigger_type, trigger.event_data)

		emit_signal("trigger_resolution_completed", trigger, result)

		# Pequeña pausa entre triggers para animaciones
		await AnimationQueue.wait_until_empty()


# =============================================================================
# UTILIDADES
# =============================================================================
func _apply_card_filter(cards: Array, filter: Dictionary) -> Array:
	"""Aplica un filtro a un array de datos de carta (Dictionary, claves en
	español — 'tipo'/'coste'/'raza'/'fuerza'/'nombre'/'keywords'). El Castillo
	y el Cementerio se guardan como datos, no como nodos Card (ver CardManager),
	así que el filtro lee las mismas claves que usa CardFactory/GameBootstrap
	al construir esos diccionarios. Compartida por ActionSearch.gd y
	ActionValidator.gd — se queda aquí, no extraída."""
	if filter.is_empty():
		return cards.duplicate()

	var matching: Array = []

	for card_data in cards:
		var matches = true

		# Filtro por tipo — admite un tipo único o una lista ("busca un Arma o un Oro", p.ej. Tyet)
		if filter.has("type"):
			var card_type = card_data.get("tipo", -1)
			if filter.type is Array:
				# Int: el tipo de los datos viene de JSON como float (2.0) y `2.0 in [2]` es false — "busca un
				# Arma o un Oro" no encontraba nada.
				if not (int(card_type) in filter.type.map(func(t): return int(t))):
					matches = false
			elif int(card_type) != int(filter.type):
				matches = false

		# Filtro por raza — admite una raza única o una lista ("busca... una carta Ignis o Titán", p.ej.
		# ignis desatado)
		if matches and filter.has("raza"):
			var card_raza: String = card_data.get("raza", "")
			if filter.raza is Array:
				var raza_list: Array = filter.raza
				if not raza_list.any(func(r): return card_raza.to_lower() == String(r).to_lower()):
					matches = false
			elif card_raza.to_lower() != String(filter.raza).to_lower():
				matches = false

		# Filtro por coste máximo Un Oro no tiene coste: no cumple filtros de coste.
		if matches and (filter.has("cost_max") or filter.has("cost_min")) and int(card_data.get("tipo", -1)) == Constants.CardType.ORO:
			matches = false
		if matches and filter.has("cost_max"):
			var card_cost = card_data.get("coste", 0)
			if card_cost > filter.cost_max:
				matches = false

		# Filtro por coste mínimo
		if matches and filter.has("cost_min"):
			var card_cost = card_data.get("coste", 0)
			if card_cost < filter.cost_min:
				matches = false

		# Filtro por fuerza
		if matches and filter.has("strength_min"):
			var strength = card_data.get("fuerza", 0)
			if strength < filter.strength_min:
				matches = false
		if matches and filter.has("strength_max"):
			if int(card_data.get("fuerza", 0)) > int(filter.strength_max):
				matches = false

		# Filtro por nombre (contiene)
		if matches and filter.has("name_contains"):
			var card_name: String = card_data.get("nombre", "")
			if not String(filter.name_contains).to_lower() in card_name.to_lower():
				matches = false

		# Filtro de exclusión por nombre exacto (p.ej. Aurora de Chile: "busca... dos Oros que no sean
		# Aurora de Chile" — evita que la propia carta buscadora, si hay otra copia en el Castillo, se
		# encuentre a sí misma)
		if matches and filter.has("name_not"):
			var card_name_exact: String = card_data.get("nombre", "")
			if card_name_exact.to_lower() == String(filter.name_not).to_lower():
				matches = false

		# Alternativas tipo + raza (EffectCompiler._object_groups(): "un Ángel, Eterno o Tótem", "un Aliado
		# Dragón"): [{type: int (-1 = cualquiera), race: "dragon"}], sin tildes; basta con una.
		if matches and filter.has("alts"):
			var raza_norm: String = _strip_accents(str(card_data.get("raza", "")).to_lower())
			var tipo_c := int(card_data.get("tipo", -1))
			matches = filter.alts.any(func(alt) -> bool:
				if int(alt.get("type", -1)) >= 0 and int(alt.type) != tipo_c:
					return false
				var race: String = str(alt.get("race", ""))
				return race == "" or race.substr(0, 5) in raza_norm)

		# Tipos excluidos: "una carta que no sea Aliado ni Talismán".
		if matches and filter.has("types_not"):
			if int(card_data.get("tipo", -1)) in filter.types_not.map(func(t): return int(t)):
				matches = false

		# "un Oro sin habilidad" (fuerza de titan).
		if matches and filter.get("no_ability", false):
			if str(card_data.get("habilidad", "")).strip_edges() != "":
				matches = false

		# Nombre exacto dentro de una lista (Dos de Cada Uno).
		if matches and filter.has("names_in"):
			if not (str(card_data.get("nombre", "")).to_lower() in filter.names_in):
				matches = false

		# Filtro por keyword (lista cruda del dato — sin instanciar la carta
		# no hay acceso a KeywordManager, así que solo se ve lo impreso)
		if matches and filter.has("keyword"):
			var keywords: Array = card_data.get("keywords", [])
			if filter.keyword not in keywords:
				matches = false

		if matches:
			matching.append(card_data)

	return matching


static func _strip_accents(s: String) -> String:
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		s = s.replace(pair[0], pair[1])
	return s
