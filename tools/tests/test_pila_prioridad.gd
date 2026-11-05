extends Node
## Fases, prioridad y Pila, sin tablero: quién tiene la prioridad primero en cada ventana (DAR 5.C3),
## qué pasa cuando ambos jugadores pasan, la Pila LIFO de ActionPipeline (respuestas encadenadas,
## Anular, Cancelar) y needs_real_decision().
## Uso (o tools/run_tests.ps1):
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/tests/test_pila_prioridad.tscn
## Sale con código 1 si algún caso falla.

const Ctx = PriorityManager.PriorityContext

var failed := 0
var passed := 0
## Si es true, _process() pasa la prioridad de cualquier ventana abierta (los dos jugadores pasan).
var auto_pass := false
var _passes: Array = []


func _ready() -> void:
	# Los autoloads conectan sus señales con call_deferred.
	for i in 5:
		await get_tree().process_frame
	PriorityManager.priority_passed.connect(func(p): _passes.append(p))
	_starting_player()
	_pass_and_close()
	_window_opened_on_both_passed()
	_needs_real_decision()
	_phase_windows()
	await _stack_lifo()
	await _stack_annul()
	await _stack_cancel()
	await _stack_three_layers()
	_annul_targets()
	print("PilaPrioridad: %d/%d casos OK" % [passed, passed + failed])
	get_tree().quit(1 if failed > 0 else 0)


func _process(_delta: float) -> void:
	if auto_pass and PriorityManager.priority_window_active:
		PriorityManager.pass_priority()


# =============================================================================
# AYUDAS
# =============================================================================
func check(label: String, got, expected) -> void:
	if got == expected:
		passed += 1
	else:
		failed += 1
		print("FALLA: %s\n   esperado: %s\n   obtenido: %s" % [label, str(expected), str(got)])


func reset(active_player: int = 0) -> void:
	auto_pass = false
	PriorityManager.force_close()
	GameManager.active_player_id = active_player
	GameManager.current_phase = Constants.Phase.VIGILIA
	_passes.clear()


func ability(name: String) -> Dictionary:
	return {"nombre": name, "habilidad": ""}


func wait_until(cond: Callable, ms: int = 5000) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > ms:
			return false
		await get_tree().process_frame
	return true


func wait_stack_idle() -> void:
	await wait_until(func(): return ActionPipeline.is_stack_empty() and not ActionPipeline.is_stack_processing(), 10000)


func wait_window() -> bool:
	return await wait_until(func(): return PriorityManager.priority_window_active)


## Registra el orden en que la Pila resuelve/anula/cancela objetos: "nombre:resultado".
func record_stack() -> Array:
	var log: Array = []
	ActionPipeline.stack_object_resolved.connect(func(o, _r): log.append("%s:resuelto" % o.name))
	ActionPipeline.object_annulled.connect(func(o, _a): log.append("%s:anulado" % o.name))
	ActionPipeline.object_cancelled.connect(func(o): log.append("%s:cancelado" % o.name))
	return log


func disconnect_record() -> void:
	for sig in [ActionPipeline.stack_object_resolved, ActionPipeline.object_annulled, ActionPipeline.object_cancelled]:
		for c in sig.get_connections():
			if c.callable.get_object() == self:
				sig.disconnect(c.callable)


# =============================================================================
# PRIORIDAD
# =============================================================================
func _starting_player() -> void:
	for active in [0, 1]:
		reset(active)
		var got: Array = []
		for ctx in [Ctx.GUERRA_TALISMANES, Ctx.RESPONSE_WINDOW, Ctx.BLOCK_DECLARATION, Ctx.DISCARD_PHASE]:
			PriorityManager.start_priority_window(ctx)
			got.append(PriorityManager.current_priority_player)
			PriorityManager.force_close()
		# Guerra, Respuesta y Bloqueo: el defensor (inactivo) primero. Descarte: el activo.
		check("prioridad inicial con el jugador %d activo" % active, got, [1 - active, 1 - active, 1 - active, active])
	reset()
	PriorityManager.start_priority_window(Ctx.RESPONSE_WINDOW, 0, 1)
	check("prioridad inicial explícita", [PriorityManager.current_priority_player, PriorityManager.current_stack_controller], [0, 1])
	PriorityManager.force_close()


func _pass_and_close() -> void:
	reset()
	var events: Array = []
	var on_both := func(): events.append("ambos")
	var on_closed := func(): events.append("cerrada")
	PriorityManager.both_players_passed.connect(on_both)
	PriorityManager.priority_window_closed.connect(on_closed)
	PriorityManager.start_priority_window(Ctx.GUERRA_TALISMANES)
	PriorityManager.pass_priority()
	check("un pase: la ventana sigue abierta y cambia la prioridad",
		[PriorityManager.priority_window_active, PriorityManager.current_priority_player], [true, 0])
	PriorityManager.pass_priority()
	check("dos pases: la ventana se cierra", PriorityManager.priority_window_active, false)
	check("dos pases: 'ambos pasaron' una sola vez, antes del cierre", events, ["ambos", "cerrada"])
	check("pases registrados en orden", _passes, [1, 0])
	PriorityManager.pass_priority()
	check("pasar sin ventana no hace nada", events.size(), 2)
	PriorityManager.both_players_passed.disconnect(on_both)
	PriorityManager.priority_window_closed.disconnect(on_closed)


func _window_opened_on_both_passed() -> void:
	# Bloqueo → Guerra de Talismanes: quien escucha 'ambos pasaron' abre la ventana siguiente en el acto.
	# pass_priority() cerraba esa ventana nueva (la Guerra arrancaba sin ventana).
	reset()
	var open_guerra := func(): PriorityManager.start_priority_window(Ctx.GUERRA_TALISMANES)
	PriorityManager.start_priority_window(Ctx.BLOCK_DECLARATION)
	PriorityManager.both_players_passed.connect(open_guerra, CONNECT_ONE_SHOT)
	PriorityManager.pass_priority()
	PriorityManager.pass_priority()
	check("la ventana que se abre al pasar ambos queda abierta",
		[PriorityManager.priority_window_active, PriorityManager.is_guerra_window()], [true, true])
	check("la ventana nueva empieza sin pases", PriorityManager.player_passed, [false, false])
	PriorityManager.force_close()


func _needs_real_decision() -> void:
	reset()
	PriorityManager.start_priority_window(Ctx.RESPONSE_WINDOW, 1, 0)
	check("Respuesta: decide solo el rival de quien jugó",
		[PriorityManager.needs_real_decision(0), PriorityManager.needs_real_decision(1)], [false, true])
	PriorityManager.start_priority_window(Ctx.RESPONSE_WINDOW, 1, -1)
	check("Respuesta sin objeto en la Pila: nadie decide",
		[PriorityManager.needs_real_decision(0), PriorityManager.needs_real_decision(1)], [false, false])
	PriorityManager.start_priority_window(Ctx.BLOCK_DECLARATION)
	check("Bloqueo: decide solo el defensor",
		[PriorityManager.needs_real_decision(0), PriorityManager.needs_real_decision(1)], [false, true])
	PriorityManager.start_priority_window(Ctx.GUERRA_TALISMANES)
	check("Guerra de Talismanes: deciden ambos",
		[PriorityManager.needs_real_decision(0), PriorityManager.needs_real_decision(1)], [true, true])
	PriorityManager.force_close()


func _phase_windows() -> void:
	reset()
	PriorityManager.start_priority_window(Ctx.RESPONSE_WINDOW, 1, 0)
	var gen: int = PriorityManager._window_generation
	PriorityManager._on_phase_changed(Constants.Phase.BLOQUEO)
	check("cambio a Bloqueo: cierra la anterior y abre la de Bloqueo",
		[PriorityManager.current_priority_context, PriorityManager.current_priority_player, PriorityManager._window_generation > gen],
		[Ctx.BLOCK_DECLARATION, 1, true])
	PriorityManager._on_phase_changed(Constants.Phase.GUERRA_TALISMANES)
	check("cambio a Guerra: abre la de Guerra con el defensor", [PriorityManager.is_guerra_window(), PriorityManager.current_priority_player], [true, 1])
	PriorityManager._on_phase_changed(Constants.Phase.FINAL)
	check("cambio a Fase Final: sin ventana", PriorityManager.priority_window_active, false)


# =============================================================================
# PILA (ActionPipeline, DAR Sección 6)
# =============================================================================
func _stack_lifo() -> void:
	# A va a la Pila; mientras el rival tiene su ventana, responde con B: B resuelve primero.
	reset()
	var log := record_stack()
	ActionPipeline.add_triggered_ability_to_stack(ability("A"), {}, {"controller_id": 0})
	check("A en la Pila: ventana de respuesta para el rival",
		[await wait_window(), PriorityManager.current_priority_context, PriorityManager.current_priority_player],
		[true, Ctx.RESPONSE_WINDOW, 1])
	ActionPipeline.add_triggered_ability_to_stack(ability("B"), {}, {"controller_id": 1})
	auto_pass = true
	await wait_stack_idle()
	disconnect_record()
	check("respuesta encadenada: resuelve primero la última", log, ["B:resuelto", "A:resuelto"])
	check("Pila vacía al final", [ActionPipeline.is_stack_empty(), ActionPipeline.is_stack_processing()], [true, false])


func _stack_annul() -> void:
	reset()
	var log := record_stack()
	var id: int = ActionPipeline.add_triggered_ability_to_stack(ability("Anulable"), {}, {"controller_id": 0})
	await wait_window()
	PriorityManager.action_taken.emit(1, {"type": "nullify", "target_stack_id": id, "source_card": {"nombre": "Anulador"}})
	auto_pass = true
	await wait_stack_idle()
	disconnect_record()
	check("Anular en la ventana de respuesta: no resuelve", log, ["Anulable:anulado"])
	CardManager.get_cemetery(0).clear()


func _stack_cancel() -> void:
	reset()
	var log := record_stack()
	var id: int = ActionPipeline.add_triggered_ability_to_stack(ability("Cancelable"), {}, {"controller_id": 0})
	await wait_window()
	check("cancelar un objeto que está en la Pila", ActionPipeline.cancel_stack_object(id), true)
	auto_pass = true
	await wait_stack_idle()
	disconnect_record()
	check("Cancelar: el efecto no ocurre", log, ["Cancelable:cancelado"])


func _stack_three_layers() -> void:
	# A ← B ← C, y C anula a B: resuelve C, B queda anulado y A resuelve igual.
	reset()
	var log := record_stack()
	ActionPipeline.add_triggered_ability_to_stack(ability("A"), {}, {"controller_id": 0})
	await wait_window()
	var b: int = ActionPipeline.add_triggered_ability_to_stack(ability("B"), {}, {"controller_id": 1})
	await wait_until(func(): return PriorityManager.priority_window_active and PriorityManager.current_stack_controller == 1)
	check("B en el tope: la ventana es para el jugador 0", PriorityManager.current_priority_player, 0)
	ActionPipeline.add_triggered_ability_to_stack(ability("C"), {}, {"controller_id": 0})
	ActionPipeline.get_object_by_id(b).was_annulled = true
	auto_pass = true
	await wait_stack_idle()
	disconnect_record()
	check("tres capas: C, B anulado, A", log, ["C:resuelto", "B:anulado", "A:resuelto"])
	CardManager.get_cemetery(1).clear()


func _annul_targets() -> void:
	# Un Oro no se juega: su ventana no es una jugada que se pueda Anular (StackAnnul.find_target).
	var StackAnnulScript = load("res://scripts/core/effects/StackAnnul.gd")
	var oro := {"id": 9001, "name": "Oro", "card_data": {"nombre": "Oro", "tipo": Constants.CardType.ORO},
		"context": {"controller_id": 0, "window_kind": "carta"}}
	var aliado := {"id": 9002, "name": "Aliado", "card_data": {"nombre": "Aliado", "tipo": Constants.CardType.ALIADO},
		"context": {"controller_id": 0, "window_kind": "carta"}}
	ActionPipeline._stack.append(oro)
	check("Anular: un Oro puesto en juego no se puede Anular", StackAnnulScript.find_target(1, true, false).is_empty(), true)
	ActionPipeline._stack.append(aliado)
	check("Anular: un Aliado jugado sí", StackAnnulScript.find_target(1, true, false).get("id", -1), 9002)
	ActionPipeline._stack.clear()
