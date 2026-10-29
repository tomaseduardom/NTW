extends Node
## ActionPipeline - Pipeline con Pila LIFO (DAR Sección 6)
## Cada carta/habilidad es un objeto en la pila con su propio Paso D
##
## Flujo:
## 1. Carta jugada → Pasos A, B, C → Añadir a Pila
## 2. Habilidades disparadas en C → Añadir al tope de la Pila
## 3. Ventana de Prioridad (D) para el tope de la Pila
## 4. Ambos pasan → Resolver tope (E) → Siguiente objeto
## 5. Pila vacía → Fin

# =============================================================================
# SEÑALES DEL PIPELINE
# =============================================================================
## Pila
signal stack_object_added(stack_object: Dictionary)
signal stack_object_resolving(stack_object: Dictionary)
signal stack_object_resolved(stack_object: Dictionary, result: Dictionary)
signal stack_object_removed(stack_object: Dictionary, reason: String)
signal stack_empty

## Pasos individuales
signal step_a_completed(stack_object: Dictionary)
signal step_b_completed(stack_object: Dictionary, cost_paid: int)
signal step_c_completed(stack_object: Dictionary, triggers_added: int)
signal step_d_waiting(stack_object: Dictionary, priority_player: int)
signal step_d_completed(stack_object: Dictionary, had_response: bool)
signal step_e_completed(stack_object: Dictionary, result: Dictionary)

## Prioridad
signal priority_window_opened(stack_object: Dictionary, player_id: int)
signal priority_passed(player_id: int)
signal both_players_passed_on_stack

## Anulación y Cancelación
signal object_annulled(stack_object: Dictionary, annuller: Dictionary)
signal object_cancelled(stack_object: Dictionary)
signal object_fizzled(stack_object: Dictionary)

## Pipeline general
signal pipeline_started
signal pipeline_idle

# =============================================================================
# ENUMS
# =============================================================================
enum StackObjectType {
	CARD_PLAYED,        # Carta siendo jugada
	TRIGGERED_ABILITY,  # Habilidad disparada
	ACTIVATED_ABILITY,  # Habilidad activada
	RESPONSE_CARD       # Carta de respuesta (talismán, anulación)
}

enum StackObjectStep {
	PENDING,           # Esperando entrar a la pila
	STEP_A,            # Declaración
	STEP_B,            # Pago de costes
	STEP_C,            # Disparar habilidades (añade más a la pila)
	ON_STACK,          # En la pila, esperando Paso D
	STEP_D,            # Ventana de respuesta activa
	STEP_E,            # Resolviendo
	RESOLVED,          # Resuelto exitosamente
	ANNULLED,          # Anulado
	FIZZLED            # Falló (objetivos inválidos)
}

const STEP_NAMES: Dictionary = {
	StackObjectStep.PENDING: "Pendiente",
	StackObjectStep.STEP_A: "A: Declaración",
	StackObjectStep.STEP_B: "B: Pago",
	StackObjectStep.STEP_C: "C: Triggers",
	StackObjectStep.ON_STACK: "En Pila",
	StackObjectStep.STEP_D: "D: Respuesta",
	StackObjectStep.STEP_E: "E: Resolución",
	StackObjectStep.RESOLVED: "Resuelto",
	StackObjectStep.ANNULLED: "Anulado",
	StackObjectStep.FIZZLED: "Falló"
}

const TYPE_NAMES: Dictionary = {
	StackObjectType.CARD_PLAYED: "Carta",
	StackObjectType.TRIGGERED_ABILITY: "Habilidad Disparada",
	StackObjectType.ACTIVATED_ABILITY: "Habilidad Activada",
	StackObjectType.RESPONSE_CARD: "Respuesta"
}

# =============================================================================
# LA PILA (THE STACK) - LIFO
# =============================================================================
## Pila principal - Array de StackObjects
## El índice 0 es el FONDO, el último índice es el TOPE
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
var _stack: Array[Dictionary] = []

## Contador de IDs únicos para objetos de la pila
var _stack_id_counter: int = 0

## Estado actual de la pila
var _is_resolving: bool = false
var _is_waiting_priority: bool = false
var _current_priority_player: int = -1

# =============================================================================
# TRACKING DE HABILIDADES ACTIVADAS ("Una vez por turno")
# =============================================================================
## Clave: "{card_id}_{ability_index}"  →  turno en que se usó por última vez
var _ability_usage: Dictionary = {}

# =============================================================================
# CONFIGURACIÓN
# =============================================================================
const PRIORITY_TIMEOUT: float = 30.0

# =============================================================================
# MÓDULOS
# =============================================================================
var _step_resolver: StackStepResolver


func _ready() -> void:
	_step_resolver = StackStepResolver.new()
	_step_resolver.setup(self)
	call_deferred("_connect_signals")
	print("[ActionPipeline] Inicializado - Sistema de Pila LIFO (DAR Sección 6)")


func _connect_signals() -> void:
	# ("módulos gordos" punto 1): PriorityManager/GameManager son autoloads garantizados — se saca el
	# cacheo redundante vía get_node_or_null.
	PriorityManager.both_players_passed.connect(_step_resolver._on_priority_both_passed)
	PriorityManager.action_taken.connect(_step_resolver._on_priority_action_taken)
	# Resetear el uso de habilidades al inicio de cada turno. GameManager es el único conductor de
	# turnos.
	GameManager.turn_started.connect(_reset_ability_usage)


# =============================================================================
# CREAR OBJETOS DE PILA
# =============================================================================
func _create_stack_object(type: StackObjectType, data: Dictionary, context: Dictionary) -> Dictionary:
	"""Crea un nuevo objeto para la pila con ID único"""
	_stack_id_counter += 1

	# ─────────────────────────────────────────────────────────────────────────
	# INSTANCE_X: Valor de X inyectado desde XValueSelector
	# Prioridad: data.instance_x > data.x_value > context.x_value
	# ─────────────────────────────────────────────────────────────────────────
	var instance_x = data.get("instance_x", data.get("x_value", context.get("x_value", -1)))
	var x_total_cost = data.get("x_total_cost", context.get("x_total_cost", -1))
	var has_x = instance_x >= 0

	var stack_obj = {
		# Identificación
		"id": _stack_id_counter,
		"type": type,
		"type_name": TYPE_NAMES.get(type, "Desconocido"),

		# Datos de la carta/habilidad
		"card_data": data.duplicate(true),
		"name": _get_name_from_data(data),
		"context": context.duplicate(true),

		# Estado del pipeline
		"step": StackObjectStep.PENDING,
		"step_name": STEP_NAMES[StackObjectStep.PENDING],

		# Objetivos y costes
		"targets": context.get("targets", []),
		"cost_paid": 0,
		"cost_modifiers": [],

		# ─────────────────────────────────────────────────────────────────────
		# COSTE VARIABLE X - instance_x es el valor canónico
		# ─────────────────────────────────────────────────────────────────────
		"instance_x": instance_x,       # Valor inyectado (canónico)
		"x_value": instance_x,          # Alias para compatibilidad
		"x_total_cost": x_total_cost,
		"has_x_cost": has_x,

		# Resultados
		"triggers_generated": [],
		"was_annulled": false,
		"was_cancelled": false,
		"was_fizzled": false,
		"annuller": null,
		"cancel_reason": "",
		"resolution_result": {},

		# Timestamps
		"created_at": Time.get_ticks_msec(),
		"resolved_at": 0
	}

	# Inyectar instance_x también en card_data para que EffectCommands lo vean
	if has_x:
		stack_obj.card_data["instance_x"] = instance_x

	return stack_obj


func _get_name_from_data(data: Dictionary) -> String:
	"""Extrae el nombre de los datos"""
	if data.has("nombre"):
		return str(data.nombre)
	if data.has("name"):
		return str(data.name)
	if data.has("ability_name"):
		return str(data.ability_name)
	if data.has("source_name"):
		return str(data.source_name)
	return "???"


# =============================================================================
# API PRINCIPAL
# =============================================================================
# Las cartas se juegan por GoldManager
# (_play_card_to_field/_place_card_as_gold/_equip_weapon/_play_talisman), no por aquí.
# ActionPipeline maneja habilidades disparadas/activadas:
# add_triggered_ability_to_stack()/activate_ability().


# =============================================================================
# AÑADIR OBJETOS A LA PILA
# =============================================================================
func _add_to_stack(stack_obj: Dictionary) -> void:
	"""Añade un objeto al tope de la pila"""
	stack_obj.step = StackObjectStep.ON_STACK
	stack_obj.step_name = STEP_NAMES[StackObjectStep.ON_STACK]

	_stack.append(stack_obj)

	# ─────────────────────────────────────────────────────────────────────────
	# LOG DETALLADO: Usar bloques de acción de CombatLog
	# ─────────────────────────────────────────────────────────────────────────
	var player_id = stack_obj.context.get("controller_id", 0)
	var card_data = stack_obj.card_data.duplicate(true)

	# Inyectar info de X en card_data para el bloque
	if stack_obj.has_x_cost:
		card_data["instance_x"] = stack_obj.instance_x
		card_data["x_value"] = stack_obj.instance_x
		card_data["x_total_cost"] = stack_obj.x_total_cost

	# Una habilidad (activada o disparada) no es "jugar" la carta: el log no debe decir "juega X —
	# COSTE: 0".
	if stack_obj.type in [StackObjectType.ACTIVATED_ABILITY, StackObjectType.TRIGGERED_ABILITY]:
		card_data["_log_is_ability"] = true
	# Crear bloque de acción detallado en CombatLog
	var block_id = CombatLog.log_detailed_play(card_data, player_id)
	stack_obj["log_block_id"] = block_id

	# Console log
	if stack_obj.has_x_cost and stack_obj.instance_x >= 0:
		print("[ActionPipeline] %s (X=%d, Coste=%d) va a la pila" % [
			stack_obj.name, stack_obj.instance_x, stack_obj.x_total_cost
		])
	else:
		print("[ActionPipeline] %s va a la pila" % stack_obj.name)

	if Constants.VERBOSE_DIAG_LOGS:
		_print_stack_state()

	emit_signal("stack_object_added", stack_obj)


func add_triggered_ability_to_stack(ability_data: Dictionary, source_card: Dictionary, context: Dictionary = {}) -> int:
	"""Añade una habilidad disparada al tope de la pila

	Llamado durante Paso C o cuando se disparan habilidades por eventos.

	Returns: ID del objeto en la pila
	"""
	var ctx = context.duplicate(true)
	ctx["source_card"] = source_card
	ctx["source_name"] = _get_name_from_data(source_card)

	var stack_obj = _create_stack_object(StackObjectType.TRIGGERED_ABILITY, ability_data, ctx)

	# Las habilidades disparadas saltan A y B, van directo a la pila
	stack_obj.step = StackObjectStep.ON_STACK
	stack_obj.step_name = STEP_NAMES[StackObjectStep.ON_STACK]

	_stack.append(stack_obj)

	print("[ActionPipeline] Ventana de respuesta: %s — el rival puede responder" % stack_obj.name)

	emit_signal("stack_object_added", stack_obj)

	# Arranca _process_stack() si no está corriendo (como activate_ability()); si no, el llamador
	# esperaba un stack_object_resolved que no llegaba.
	if not _is_resolving:
		_process_stack()

	return stack_obj.id


func add_triggered_ability_to_stack_and_await(ability_data: Dictionary, source_card: Dictionary, context: Dictionary = {}) -> Dictionary:
	"""Como add_triggered_ability_to_stack(), pero espera a que ESE objeto
	puntual (no la pila entera — puede haber respuestas anidadas encima que
	tarden más) termine de resolver/anularse/cancelarse/fizzlear, para que el
	llamador (un patrón de trigger en TriggerSystem/LookAndPlayResolver/etc.,
	Sección "Pila de Respuesta Universal") sepa si debe seguir ejecutando su
	propio efecto o abortar. Filtra las señales por stack_id — si mientras
	tanto se apilan respuestas encima, esas resuelven primero y esta función
	sigue esperando hasta que le toque el turno a ESTE objeto en particular.

	Returns: {resolved: bool, annulled: bool, cancelled: bool, fizzled: bool}
	— como máximo uno de los cuatro es true."""
	var stack_id: int = add_triggered_ability_to_stack(ability_data, source_card, context)

	# Las lambdas de GDScript capturan las variables locales por valor: un "done = true" dentro del
	# closure no se ve afuera. Por eso "done" vive en el mismo Dictionary compartido (outcome), que se
	# comparte por referencia.
	var outcome: Dictionary = {"resolved": false, "annulled": false, "cancelled": false, "fizzled": false, "done": false}

	var on_resolved := func(obj: Dictionary, _result: Dictionary) -> void:
		if obj.get("id", -1) == stack_id:
			outcome.resolved = true
			outcome.done = true
	var on_annulled := func(obj: Dictionary, _annuller) -> void:
		if obj.get("id", -1) == stack_id:
			outcome.annulled = true
			outcome.done = true
	var on_cancelled := func(obj: Dictionary) -> void:
		if obj.get("id", -1) == stack_id:
			outcome.cancelled = true
			outcome.done = true
	var on_fizzled := func(obj: Dictionary) -> void:
		if obj.get("id", -1) == stack_id:
			outcome.fizzled = true
			outcome.done = true

	stack_object_resolved.connect(on_resolved)
	object_annulled.connect(on_annulled)
	object_cancelled.connect(on_cancelled)
	object_fizzled.connect(on_fizzled)

	# Salvaguarda con timeout: si este objeto nunca recibe su Paso D/E (p.ej. _process_stack() no se
	# relanzó), el juego no queda congelado. Si se dispara, el push_warning deja rastro de un problema
	# más profundo.
	# Mientras este objeto siga en la Pila con alguien decidiendo (ventana de prioridad abierta o la Pila
	# resolviendo), se espera lo que haga falta: un jugador puede tardar más de 8 s en decidir si responde y
	# el efecto no debe seguir sin él. Solo si el objeto quedó huérfano (nadie procesa la Pila) se relanza
	# _process_stack() una vez y, si tampoco, se sigue.
	var waited := 0.0
	var relaunched := false
	while not outcome.done:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited < 8.0:
			continue
		var still_there: bool = _stack.any(func(o): return o.get("id", -1) == stack_id)
		if still_there and (_is_resolving or PriorityManager.priority_window_active):
			continue
		if still_there and not relaunched:
			relaunched = true
			waited = 0.0
			_process_stack()
			continue
		break
	if not outcome.done:
		push_warning("[ActionPipeline] add_triggered_ability_to_stack_and_await() atascado >8s para stack_id=%d (_is_resolving=%s, tamaño de pila=%d) — forzando continuación sin anular/cancelar" % [
			stack_id, str(_is_resolving), _stack.size()
		])

	stack_object_resolved.disconnect(on_resolved)
	object_annulled.disconnect(on_annulled)
	object_cancelled.disconnect(on_cancelled)
	object_fizzled.disconnect(on_fizzled)

	return outcome


# =============================================================================
# HABILIDADES ACTIVADAS (DAR Sección 6 — Paso A→B→C→Pila→D→E)
# =============================================================================
func activate_ability(source_card_data: Dictionary, ability_data: Dictionary, context: Dictionary = {}) -> Dictionary:
	"""Activa una habilidad activada y la mete en la Pila LIFO.

	Args:
		source_card_data: Datos de la carta que contiene la habilidad
		ability_data: Dict devuelto por UniversalCardParser.get_activated_abilities()
		context: {controller_id, ...}

	Returns: {success: bool, reason: String}
	"""
	var controller_id: int = context.get("controller_id", 0)
	# instance_id, no source_card_data.id (compartido por todas las copias): cada copia tiene su propio
	# cupo.
	var card_node = context.get("source_card_node")
	var card_id: String    = load("res://scripts/core/effects/mechanics/RayoGaia.gd").usage_key(card_node) if card_node and is_instance_valid(card_node) else str(source_card_data.get("id", ""))
	var ability_index: int = ability_data.get("ability_index", 0)
	var cost_type: int     = ability_data.get("cost_type", UniversalCardParser.CostType.NONE)
	var cost_amount: int   = ability_data.get("cost_amount", 0)

	# Para habilidades ACTIVADAS no hay confirmación "Puedes": clickear el botón ya lo es. Los triggers
	# ofrecen su propio declinar (can_cancel del SelectionManager que abren) y no pasan por aquí.

	# ── Paso A: Validar activación ────────────────────────────────────────────
	var check = can_activate_ability(source_card_data, ability_data, context)
	if not check.can:
		push_warning("[ActionPipeline] No se puede activar habilidad: %s" % check.reason)
		return {"success": false, "reason": check.reason}

	# ── Paso B: Pagar el costo ────────────────────────────────────────────────
	# El Oro vive en GoldManager (hijo de Main).
	var main_ref := get_node_or_null("/root/Main")
	var source_card_node = context.get("source_card_node")
	match cost_type:
		UniversalCardParser.CostType.GOLD:
			# GoldManager.pagar_coste() es por jugador (Oro Virtual/restringido + elegir Oro físico;
			# arquitectura.md §33): un solo camino para los dos jugadores.
			if not main_ref or not main_ref._gold_manager:
				return {"success": false, "reason": "GoldManager no disponible"}
			var paid: bool = await main_ref._gold_manager.pagar_coste(cost_amount, -1, "", -1, controller_id)
			if not paid:
				return {"success": false, "reason": "Oro insuficiente"}
		UniversalCardParser.CostType.DISCARD:
			# La mano del jugador 1 existe como Nodos (_opponent_fan) (§57). El Remoto elige por red; el bot
			# descarta la de menor coste.
			if not main_ref or not PlayerSideScript.hand(main_ref, controller_id):
				return {"success": false, "reason": "No se pudo descartar"}
			var hand_cards: Array = PlayerSideScript.hand_cards(main_ref, controller_id)
			if hand_cards.is_empty():
				return {"success": false, "reason": "Mano vacía"}
			var chosen: Array = []
			if PlayerSideScript.is_bot(controller_id):
				hand_cards.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
				chosen = [hand_cards[0]]
			else:
				chosen = await TriggerSystem._select_hand_cards_for_discard(hand_cards, 1, controller_id)
			if chosen.is_empty():
				return {"success": false, "reason": "Descarte cancelado"}
			await ActionModule.discard(controller_id, chosen, "activated_ability", true)
		UniversalCardParser.CostType.TAP:
			if source_card_node and is_instance_valid(source_card_node):
				source_card_node.is_tapped = true
		# ONCE_PER_TURN no tiene costo de recurso, solo la restricción de uso

	# ── Marcar como usada (para "una vez por turno") ──────────────────────────
	if cost_type == UniversalCardParser.CostType.ONCE_PER_TURN or ability_data.get("once_per_turn", false):
		var turn: int = GameManager.turn_serial
		_ability_usage["%s_%d" % [card_id, ability_index]] = turn
		# Registrar también en TurnRegistry del parser para coherencia
		UniversalCardParser.turn_registry.register(card_id, ability_index, turn)

	# ── Crear objeto de pila: la habilidad activada ───────────────────────────
	# Presentamos la habilidad como una "carta" con habilidad = efecto_text
	var ability_as_data = source_card_data.duplicate(true)
	ability_as_data["habilidad"]             = ability_data.get("effect_text", "")
	ability_as_data["coste"]                 = 0      # ya pagado arriba
	ability_as_data["_is_activated_ability"] = true
	ability_as_data["_ability_meta"]         = ability_data.duplicate()

	var ctx = context.duplicate(true)
	ctx["source_card"]           = source_card_data
	ctx["source_name"]           = source_card_data.get("nombre", "???")
	ctx["is_activated_ability"]  = true
	ctx["ability_cost_paid"]     = cost_amount
	# Crono Diamante: "La primera habilidad de Oro que utilices cada turno no puede ser cancelada".
	if load("res://scripts/core/effects/mechanics/ProtectionRules.gd").note_gold_ability_use(card_node, controller_id):
		ctx["_first_gold_ability"] = true

	var stack_obj = _create_stack_object(StackObjectType.ACTIVATED_ABILITY, ability_as_data, ctx)

	# ── Paso C: Triggers ──────────────────────────────────────────────────────
	await _step_resolver._execute_step_c(stack_obj)

	# ── Añadir al tope de la Pila ─────────────────────────────────────────────
	_add_to_stack(stack_obj)

	print("[ActionPipeline] ✦ Habilidad activada: '%s' de '%s'" % [
		ability_data.get("cost_text", "?"), source_card_data.get("nombre", "?")
	])

	# ── Iniciar procesamiento si la pila no está activa ───────────────────────
	if not _is_resolving:
		_process_stack()

	return {"success": true, "stack_id": stack_obj.id}


func can_activate_ability(source_card_data: Dictionary, ability_data: Dictionary, context: Dictionary = {}) -> Dictionary:
	"""Comprueba si una habilidad puede activarse ahora.

	Returns: {can: bool, reason: String}
	"""
	# instance_id de la carta viva cuando existe, no source_card_data.id (compartido por todas las
	# copias, que entonces compartían el cupo de "una vez por turno"). Cae a source_card_data.id solo
	# si no hay Nodo.
	var context_node = context.get("source_card_node")
	var card_id        = load("res://scripts/core/effects/mechanics/RayoGaia.gd").usage_key(context_node) if context_node and is_instance_valid(context_node) else str(source_card_data.get("id", ""))
	var ability_index  = ability_data.get("ability_index", 0)
	var cost_type      = ability_data.get("cost_type", UniversalCardParser.CostType.NONE)
	var cost_amount    = ability_data.get("cost_amount", 0)
	var controller_id  = context.get("controller_id", 0)

	# Fase: Vigilia + Guerra de Talismanes por defecto (DAR) — solo se
	# restringe a Vigilia si el propio texto de la habilidad lo dice ("en
	# Vigilia"). Sin esa mención, cualquier habilidad activada se puede usar
	# en cualquiera de las dos ventanas.
	var phase = GameManager.current_phase
	var ability_text: String = ability_data.get("raw_text", ability_data.get("effect_text", "")).to_lower()
	var vigilia_only: bool = "en vigilia" in ability_text
	var phase_ok: bool = phase == Constants.Phase.VIGILIA or (phase == Constants.Phase.GUERRA_TALISMANES and not vigilia_only)
	if not phase_ok:
		return {"can": false, "reason": "Fuera de fase Vigilia" if vigilia_only else "Solo en Vigilia o Guerra de Talismanes"}
	# No se exige active_player_id == controller_id: el DAR permite habilidades instantáneas en
	# Vigilia/Guerra de Talismanes seas o no el jugador activo (hace falta para responder en el turno
	# rival).

	# Una vez por turno: verificar en _ability_usage y en TurnRegistry del parser
	if cost_type == UniversalCardParser.CostType.ONCE_PER_TURN or ability_data.get("once_per_turn", false):
		var turn: int = GameManager.turn_serial
		var key: String = "%s_%d" % [card_id, ability_index]
		var limit: int = int(ability_data.get("uses_per_turn", 1))
		# El registro local solo guarda "se usó"; con más de un uso por turno
		# ("Hasta dos veces por turno") manda el contador del TurnRegistry.
		var in_local:    bool = limit <= 1 and _ability_usage.get(key, -1) == turn
		var in_registry: bool = UniversalCardParser.turn_registry.is_exhausted(card_id, ability_index, turn, limit)
		if in_local or in_registry:
			return {"can": false, "reason": "Ya usada este turno"}

	# Oro: verificar si el jugador tiene suficiente — vía GoldManager, que ya
	# es por jugador (Oro físico + Virtual + restringido, ver arquitectura.md
	# §33). Antes el jugador 1 pasaba por GameState.puede_pagar() sola (solo
	# Oro físico, sin considerar sus propios pools de Oro Virtual/restringido,
	# que hoy sí puede tener).
	if cost_type == UniversalCardParser.CostType.GOLD and cost_amount > 0:
		var main_check := get_node_or_null("/root/Main")
		if main_check and main_check._gold_manager:
			var available: int = main_check._gold_manager.get_oro_disponible(controller_id)
			if not main_check._gold_manager.puede_pagar(cost_amount, -1, "", -1, controller_id):
				return {"can": false, "reason": "Necesitas %d Oro (tienes %d)" % [cost_amount, available]}
		else:
			return {"can": false, "reason": "GoldManager no disponible"}

	return {"can": true, "reason": ""}


func _reset_ability_usage(_player_id = null, _turn_number = null) -> void:
	"""Resetea el tracking de habilidades al inicio de cada turno."""
	_ability_usage.clear()
	print("[ActionPipeline] Usos de habilidades reseteados para el nuevo turno")


# =============================================================================
# PROCESAR LA PILA (LOOP PRINCIPAL) - Resolución por Capas (DAR 5.C3)
# =============================================================================
func _process_stack() -> void:
	"""Procesa la pila con resolución por capas (DAR Sección 5.C3)

	RESOLUCIÓN POR CAPAS:
	1. Abrir ventana de prioridad para el tope
	2. Si alguien responde → añadir al tope, volver a 1
	3. Ambos pasan consecutivamente → resolver SOLO el tope
	4. Tras resolver, abrir NUEVA ventana de prioridad para el siguiente
	5. Repetir hasta pila vacía

	DETECCIÓN DE OBJETIVOS:
	- Si una habilidad pierde todos sus objetivos → fizzle (eliminar sin resolver)
	- Si es cancelada → eliminar sin ejecutar efectos
	"""
	if _is_resolving:
		push_warning("[ActionPipeline] Ya hay un proceso de pila activo")
		return

	_is_resolving = true
	emit_signal("pipeline_started")

	if Constants.VERBOSE_DIAG_LOGS:
		print("[ActionPipeline] Procesando pila — resolución por capas (5.C3)")

	var layer_count = 0

	while not _stack.is_empty():
		layer_count += 1
		var top = _get_stack_top()

		if top.is_empty():
			break

		if Constants.VERBOSE_DIAG_LOGS:
			_print_stack_state()

		# PRE-CHECK: ¿el objeto fue cancelado o perdió objetivos? (el handler
		# correspondiente ya imprime su propio mensaje claro, ver más abajo)
		var pre_check = _pre_resolution_check(top)
		if pre_check.should_remove:
			await _handle_removed_object(top, pre_check.reason)
			continue
		# Anulado mientras esperaba (StackAnnul): no abre otra ventana.
		if top.get("was_annulled", false):
			await _handle_annulled_object(top)
			continue

		# PASO D: Ventana de Prioridad (Sección 6.D) — ambos jugadores deben
		# pasar consecutivamente para resolver.
		var step_d_result = await _step_resolver._execute_step_d(top)

		# Si hubo respuesta, se añadió al tope — nueva capa.
		if step_d_result.had_response:
			continue

		# POST-CHECK: anulación/cancelación después de Paso D (cada handler
		# ya imprime su propio mensaje claro).
		if top.was_annulled:
			await _handle_annulled_object(top)
			continue

		if top.was_cancelled:
			await _handle_cancelled_object(top)
			continue

		# Fizzle si perdió todos los objetivos.
		if _should_fizzle(top):
			await _handle_fizzled_object(top)
			continue

		# PASO E: resolver el tope (ambos pasaron consecutivamente).
		await _step_resolver._execute_step_e(top)

		# Remover del tope después de resolver.
		_remove_from_stack(top, "resolved")

		print("[ActionPipeline] %s: resuelta" % top.name)
		# Si queda algo en la pila, el loop sigue y abre Paso D para el
		# nuevo tope (nueva ventana de prioridad, 5.C3).

	emit_signal("stack_empty")
	_is_resolving = false
	emit_signal("pipeline_idle")


# =============================================================================
# DETECCIÓN DE OBJETIVOS Y CANCELACIÓN
# =============================================================================
func _pre_resolution_check(stack_obj: Dictionary) -> Dictionary:
	"""Verifica si el objeto debe removerse antes de abrir prioridad

	Returns: {should_remove: bool, reason: String}
	"""
	var result = {"should_remove": false, "reason": ""}

	# Verificar si ya fue marcado como cancelado
	if stack_obj.get("was_cancelled", false):
		result.should_remove = true
		result.reason = "cancelled"
		return result

	# Verificar si perdió todos sus objetivos obligatorios
	if _has_required_targets(stack_obj) and not _has_valid_targets(stack_obj):
		result.should_remove = true
		result.reason = "no_targets"
		return result

	# Verificar si la fuente ya no existe (para habilidades)
	if stack_obj.type in [StackObjectType.TRIGGERED_ABILITY, StackObjectType.ACTIVATED_ABILITY]:
		var source = stack_obj.context.get("source_card", null)
		if source is Node and not is_instance_valid(source):
			# Algunas habilidades aún se resuelven si la fuente salió
			# Solo cancelar si la habilidad lo requiere
			if stack_obj.card_data.get("requires_source", false):
				result.should_remove = true
				result.reason = "source_removed"

	return result


func _has_required_targets(stack_obj: Dictionary) -> bool:
	"""Determina si el objeto requiere objetivos obligatorios"""
	var card_data = stack_obj.card_data
	var ability_blocks = card_data.get("hability_blocks", [])

	for block in ability_blocks:
		var effects = block.get("effect", [])
		for effect in effects:
			var target = effect.get("target", {})
			var target_type = target.get("type", "")
			# "targeted" = requiere objetivo, "all"/"self" = no requiere selección
			if target_type == "targeted" or target_type == "choose":
				return true

	# También verificar objetivos directos
	return not stack_obj.targets.is_empty()


func _has_valid_targets(stack_obj: Dictionary) -> bool:
	"""Verifica si al menos un objetivo sigue siendo válido"""
	if stack_obj.targets.is_empty():
		return false

	for target in stack_obj.targets:
		if _is_target_valid(target, stack_obj):
			return true

	return false


func _is_target_valid(target, stack_obj: Dictionary) -> bool:
	"""Verifica si un objetivo específico sigue siendo válido"""
	# Nodos deben existir
	if target is Node:
		if not is_instance_valid(target):
			return false
		# Verificar que siga en una zona válida
		var zone = target.get("current_zone")
		if zone != null and zone in [Constants.Zone.CEMENTERIO, Constants.Zone.DESTIERRO]:
			return false

	# Diccionarios (datos de carta) - verificar si fue removido del juego
	if target is Dictionary:
		var target_id = target.get("id", "")
		if target_id.is_empty():
			return false
		# TODO: Verificar contra GameManager si la carta sigue en juego

	return true


func _should_fizzle(stack_obj: Dictionary) -> bool:
	"""Determina si el objeto debe hacer fizzle (perder todos los objetivos)

	Regla: Si TODOS los objetivos de un hechizo/habilidad son inválidos
	cuando intenta resolver, el hechizo hace fizzle y no hace nada.
	"""
	# Si no requiere objetivos, no puede fizzle por esto
	if not _has_required_targets(stack_obj):
		return false

	# Si tiene al menos un objetivo válido, no fizzle
	if _has_valid_targets(stack_obj):
		return false

	# Todos los objetivos son inválidos
	return true


# =============================================================================
# MANEJO DE OBJETOS REMOVIDOS
# =============================================================================
func _handle_removed_object(stack_obj: Dictionary, reason: String) -> void:
	"""Maneja un objeto que debe removerse antes de resolver"""
	match reason:
		"cancelled":
			await _handle_cancelled_object(stack_obj)
		"no_targets":
			await _handle_fizzled_object(stack_obj)
		"source_removed":
			await _handle_source_removed(stack_obj)
		_:
			_remove_from_stack(stack_obj, reason)


func _handle_cancelled_object(stack_obj: Dictionary) -> void:
	"""Maneja un objeto que fue CANCELADO (eliminar sin ejecutar efectos)

	Cancelar ≠ Anular:
	- Anular: La carta/habilidad va al cementerio
	- Cancelar: El efecto simplemente no ocurre
	"""
	stack_obj.step = StackObjectStep.FIZZLED
	stack_obj.step_name = STEP_NAMES[StackObjectStep.FIZZLED]

	var controller_id = stack_obj.context.get("controller_id", 0)

	print("[ActionPipeline] [%s] ✗ CANCELADA - efectos no ejecutados" % stack_obj.name)

	emit_signal("object_cancelled", stack_obj)

	# Para habilidades, simplemente se remueven
	# Para cartas, van al cementerio sin resolver
	if stack_obj.type in [StackObjectType.CARD_PLAYED, StackObjectType.RESPONSE_CARD]:
		# La API para mover una carta (Dictionary) al Cementerio es CardManager.add_to_cemetery(player_id,
		# card_data).
		CardManager.add_to_cemetery(controller_id, stack_obj.card_data)

	_remove_from_stack(stack_obj, "cancelled")


func _handle_fizzled_object(stack_obj: Dictionary) -> void:
	"""Maneja un objeto que hizo FIZZLE (perdió todos los objetivos)"""
	stack_obj.step = StackObjectStep.FIZZLED
	stack_obj.step_name = STEP_NAMES[StackObjectStep.FIZZLED]

	var controller_id = stack_obj.context.get("controller_id", 0)

	print("[ActionPipeline] [%s] ✗ FIZZLED - sin objetivos válidos" % stack_obj.name)

	emit_signal("object_fizzled", stack_obj)

	# Cartas van al cementerio, habilidades simplemente desaparecen
	if stack_obj.type in [StackObjectType.CARD_PLAYED, StackObjectType.RESPONSE_CARD]:
		# La API para mover una carta (Dictionary) al Cementerio es CardManager.add_to_cemetery(player_id,
		# card_data).
		CardManager.add_to_cemetery(controller_id, stack_obj.card_data)

	_remove_from_stack(stack_obj, "fizzled")


func _handle_source_removed(stack_obj: Dictionary) -> void:
	"""Maneja cuando la fuente de una habilidad fue removida del juego"""
	stack_obj.step = StackObjectStep.FIZZLED
	stack_obj.step_name = STEP_NAMES[StackObjectStep.FIZZLED]

	print("[ActionPipeline] [%s] ✗ Fuente removida del juego" % stack_obj.name)

	emit_signal("object_fizzled", stack_obj)
	_remove_from_stack(stack_obj, "source_removed")


func cancel_stack_object(stack_id: int) -> bool:
	"""Cancela un objeto específico de la pila por su ID

	Llamar esto marca el objeto como cancelado.
	Será removido cuando sea su turno de resolver.

	Returns: true si se encontró y marcó
	"""
	for obj in _stack:
		if obj.id == stack_id:
			obj["was_cancelled"] = true
			print("[ActionPipeline] Objeto #%d marcado para cancelación" % stack_id)
			return true
	return false


func _get_stack_top() -> Dictionary:
	"""Obtiene el objeto en el tope de la pila (sin remover)"""
	if _stack.is_empty():
		return {}
	return _stack[_stack.size() - 1]


func _remove_from_stack(stack_obj: Dictionary, reason: String) -> void:
	"""Remueve un objeto de la pila"""
	var idx = _stack.find(stack_obj)
	if idx >= 0:
		_stack.remove_at(idx)
		emit_signal("stack_object_removed", stack_obj, reason)


# =============================================================================
# MANEJO DE ANULACIÓN
# =============================================================================
func _handle_annulled_object(stack_obj: Dictionary) -> void:
	"""Maneja un objeto que fue anulado"""
	stack_obj.step = StackObjectStep.ANNULLED
	stack_obj.step_name = STEP_NAMES[StackObjectStep.ANNULLED]

	var controller_id = stack_obj.context.get("controller_id", 0)

	print("[ActionPipeline] [%s] ✗ ANULADO" % stack_obj.name)

	# ─────────────────────────────────────────────────────────────────────────
	# MARCAR BLOQUE COMO ANULADO EN COMBATLOG
	# ─────────────────────────────────────────────────────────────────────────
	var block_id = stack_obj.get("log_block_id", -1)
	var annuller_data = stack_obj.get("annuller", {})
	var annuller_name = annuller_data.get("nombre", annuller_data.get("name", "carta"))

	if block_id >= 0:
		CombatLog.annul_block(block_id, annuller_name, "")
		CombatLog.complete_block(block_id, false, {"annulled": true})

	emit_signal("object_annulled", stack_obj, stack_obj.annuller)

	# Al Cementerio sin resolver (CardManager.add_to_cemetery()). Si la ventana es de una carta real
	# (source_card_node), quien la abrió la manda a su destino al recibir object_annulled
	# (GoldManager._trigger_enter_play/_play_talisman); agregarla aquí la duplicaba.
	if stack_obj.context.get("source_card_node") == null:
		CardManager.add_to_cemetery(controller_id, stack_obj.card_data)

	# 'trigger_event' no existe en TriggerSystem.gd — este disparo de on_card_annulled nunca ocurrió
	# realmente. Documentado, no se inventa un trigger nuevo fuera del alcance de esta limpieza.

	_remove_from_stack(stack_obj, "annulled")


# =============================================================================
# LOGGING Y UTILIDADES
# =============================================================================
func _log_action(action_type: String, message: String, data: Dictionary = {}) -> void:
	"""Envía una entrada al CombatLog"""
	CombatLog.add_entry(action_type, message, data)


func _get_player_name(player_id: int) -> String:
	"""Obtiene el nombre del jugador (GameManager no expone get_player_name())."""
	return "Jugador %d" % (player_id + 1)


func _print_stack_state() -> void:
	"""Imprime el estado actual de la pila"""
	if _stack.is_empty():
		print("[ActionPipeline] │  (vacía)")
		return

	for i in range(_stack.size() - 1, -1, -1):
		var obj = _stack[i]
		var prefix = "│  TOPE → " if i == _stack.size() - 1 else "│       "
		var x_info = " [X=%d]" % obj.x_value if obj.get("has_x_cost", false) else ""
		print("[ActionPipeline] %s[%d] %s (%s)%s" % [
			prefix, obj.id, obj.name, obj.step_name, x_info
		])


# =============================================================================
# API PÚBLICA
# =============================================================================
func get_stack() -> Array[Dictionary]:
	"""Retorna copia de la pila actual"""
	return _stack.duplicate()


func is_stack_empty() -> bool:
	"""Retorna si la pila está vacía"""
	return _stack.is_empty()


func is_stack_processing() -> bool:
	"""Retorna si se está procesando la pila"""
	return _is_resolving


func get_object_by_id(stack_id: int) -> Dictionary:
	"""Busca un objeto en la pila por ID"""
	for obj in _stack:
		if obj.id == stack_id:
			return obj
	return {}


# =============================================================================
# API DE COSTE VARIABLE X - Acceso para Annul/EffectCommands
# =============================================================================
func get_instance_x(stack_id: int) -> int:
	"""Obtiene instance_x de un objeto en la pila (valor canónico)

	Usado por:
	- EffectCommands para resolver efectos que usan X
	- Cualquier sistema que necesite el valor de X elegido

	Returns: Valor de X, o -1 si no tiene coste variable
	"""
	var obj = get_object_by_id(stack_id)
	if obj.is_empty():
		return -1

	# instance_x es el valor canónico
	return obj.get("instance_x", obj.get("x_value", -1))


func get_x_value(stack_id: int) -> int:
	"""Alias de get_instance_x para compatibilidad"""
	return get_instance_x(stack_id)


func get_x_total_cost(stack_id: int) -> int:
	"""Obtiene el coste total (incluyendo X) de un objeto en la pila

	Returns: Coste total pagado, o -1 si no tiene coste variable
	"""
	var obj = get_object_by_id(stack_id)
	if obj.is_empty():
		return -1

	return obj.get("x_total_cost", -1)


func has_x_cost(stack_id: int) -> bool:
	"""Verifica si un objeto tiene coste variable X"""
	var obj = get_object_by_id(stack_id)
	if obj.is_empty():
		return false

	return obj.get("has_x_cost", false)
