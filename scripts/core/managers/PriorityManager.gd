extends Node
## PriorityManager - Gestiona el sistema de prioridad (DAR Sección 5.C3)
## Controla quién puede actuar en la Guerra de Talismanes y ventanas de respuesta

# =============================================================================
# SIGNALS
# =============================================================================
signal priority_changed(player_id: int)
signal priority_passed(player_id: int)
signal both_players_passed  # Ambos pasaron consecutivamente → resolver pila
signal priority_window_opened(player_id: int, context: String)
signal priority_window_closed
signal action_taken(player_id: int, action: Dictionary)

# =============================================================================
# ESTADO DE PRIORIDAD
# =============================================================================
## Jugador que tiene prioridad actualmente
var current_priority_player: int = -1

## Tracking de quién ha pasado prioridad
var player_passed: Array[bool] = [false, false]

## Indica si hay una ventana de prioridad activa
var priority_window_active: bool = false

## True mientras hay un diálogo reactivo real esperando decisión del humano (p.ej. Signo Amarillo,
## ResponseWindowHandler) — el auto-pase "no hay nada que decidir aquí"
## (PhaseFlowController/ResponseWindowHandler) lo respeta para no cerrar la ventana por abajo
## mientras el diálogo sigue abierto esperando un click.
var suppress_human_autopass: bool = false

## Contexto actual de la prioridad (para UI)
var current_context: String = ""

## Acciones válidas en el contexto actual
var valid_actions: Array[String] = []

# =============================================================================
# CONSTANTES
# =============================================================================
enum PriorityContext {
	NONE,
	GUERRA_TALISMANES,    # 5.C3 - Jugar talismanes y habilidades
	RESPONSE_WINDOW,      # Respuesta a habilidad/efecto
	DISCARD_PHASE,        # Descarte en fase final
	BLOCK_DECLARATION,    # Declaración de bloqueadores
	PHASE_START           # Comienzo de fase: "Puedes jugarlo al comienzo de cualquier Fase" (PhaseStartWindow)
}

var current_priority_context: int = PriorityContext.NONE

## Guerra de Talismanes por turnos (§64). Cada Talismán/habilidad abre su propia Ventana de
## Respuesta (Paso D) sobre esta instancia, pisando la de la Guerra. Cuando la acción termina de
## resolverse, la Guerra sigue con el OTRO jugador (el que no actuó) y los pases vuelven a cero; así
## el "ambos pasaron" de la respuesta no termina la Guerra.
var _guerra_last_actor: int = -1
var _guerra_actions_running: int = 0
var _guerra_resume_scheduled: bool = false
var _guerra_resume_after_action: bool = false

## Contador que sube en cada start_priority_window(). Los timers de auto-pase
## (PhaseFlowController._human_pass_after()/_bot_pass_after()) capturan esta generación al
## programarse y no hacen nada si cambió: si su ventana ya se cerró y se abrió otra (p.ej. Guerra de
## Talismanes), le pasarían la prioridad al jugador sin que hiciera nada.
var _window_generation: int = 0

## Jugador que controla el objeto de la pila al que responde esta ventana (Paso D de
## StackStepResolver), o -1 si no responde a una carta/habilidad puntual (fase, pila recién vaciada,
## etc.). Ver needs_real_decision().
var current_stack_controller: int = -1

## Tiempo límite para responder en una Ventana de Respuesta online: "5 segundos nada más por
## ahora"). Solo aplica a RESPONSE_WINDOW — Bloqueo y Guerra de Talismanes esperan sin límite.
const ONLINE_RESPONSE_TIMEOUT: float = 5.0


func _ready() -> void:
	# GameManager es el único conductor de fases: la ventana de Bloqueo/Guerra de Talismanes se abre al
	# escuchar su phase_changed.
	if GameManager and GameManager.has_signal("phase_changed"):
		GameManager.phase_changed.connect(_on_phase_changed)


# =============================================================================
# INICIALIZACIÓN DE PRIORIDAD
# =============================================================================
func start_priority_window(context: int, starting_player: int = -1, stack_controller: int = -1) -> void:
	"""Inicia una ventana de prioridad
	context: PriorityContext enum
	starting_player: -1 para usar regla por defecto según contexto
	stack_controller: dueño del objeto de la pila al que se responde (-1 si no hay)
	"""
	current_priority_context = context
	current_stack_controller = stack_controller
	player_passed = [false, false]
	priority_window_active = true
	_window_generation += 1

	# Determinar quién empieza según contexto
	if starting_player >= 0:
		current_priority_player = starting_player
	else:
		current_priority_player = _get_starting_priority_player(context)

	# Configurar acciones válidas según contexto
	valid_actions = _get_valid_actions_for_context(context)
	current_context = _get_context_name(context)

	if Constants.VERBOSE_DIAG_LOGS:
		print("[PriorityManager] Ventana de prioridad: %s - Jugador %d" % [
			current_context, current_priority_player + 1
		])

	emit_signal("priority_window_opened", current_priority_player, current_context)
	emit_signal("priority_changed", current_priority_player)


func _get_starting_priority_player(context: int) -> int:
	"""Determina quién tiene prioridad inicial según el contexto"""
	var active_player = GameManager.active_player_id if GameManager else 0
	var inactive_player = 1 - active_player

	match context:
		PriorityContext.GUERRA_TALISMANES:
			# "Tu tienes la prioridad en Guerra de Talismanes" (p.ej. Garfio Pirata) — anula la regla DAR
			# 5.C3 por defecto (defensor primero) si algún jugador controla una carta que se la otorgue.
			var override_player := _player_with_guerra_talismanes_priority()
			if override_player >= 0:
				return override_player
			# DAR 5.C3: El defensor (jugador inactivo) tiene prioridad primero
			return inactive_player
		PriorityContext.RESPONSE_WINDOW:
			# El oponente del que activó el efecto
			return inactive_player
		PriorityContext.BLOCK_DECLARATION:
			# El defensor declara bloqueadores
			return inactive_player
		PriorityContext.DISCARD_PHASE:
			# El jugador activo descarta
			return active_player
		_:
			return active_player


func _player_with_guerra_talismanes_priority() -> int:
	"""Busca, entre ambos jugadores, si alguno controla una carta (o Arma equipada) cuyo texto le
	otorga la prioridad en Guerra de Talismanes (p.ej. Garfio Pirata: 'tu tienes la prioridad en
	Guerra de Talismanes'). Devuelve el player_id o -1 si nadie la tiene."""
	var main := get_node_or_null("/root/Main")
	if not main:
		return -1
	for player_id in [0, 1]:
		var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if player_id == 0 \
			else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
		for field in fields:
			if not field:
				continue
			for card in field.get_children():
				if not is_instance_valid(card):
					continue
				if _card_grants_guerra_talismanes_priority(card):
					return player_id
				var weapons = card.get("equipped_weapons")
				if weapons is Array:
					for w in weapons:
						if is_instance_valid(w) and _card_grants_guerra_talismanes_priority(w):
							return player_id
	return -1


func _card_grants_guerra_talismanes_priority(card: Node) -> bool:
	var text: String = str(card.get("card_ability")) if card.get("card_ability") != null else ""
	return "prioridad en guerra de talismanes" in text.to_lower()


func _get_valid_actions_for_context(context: int) -> Array[String]:
	"""Retorna las acciones válidas para un contexto"""
	match context:
		PriorityContext.GUERRA_TALISMANES:
			return ["play_talisman", "activate_ability", "pass"]
		PriorityContext.RESPONSE_WINDOW:
			return ["play_instant", "activate_ability", "cancel", "pass"]
		PriorityContext.BLOCK_DECLARATION:
			return ["declare_blocker", "pass"]
		PriorityContext.DISCARD_PHASE:
			return ["discard", "pass"]
		_:
			return ["pass"]


func _get_context_name(context: int) -> String:
	"""Retorna nombre legible del contexto"""
	match context:
		PriorityContext.GUERRA_TALISMANES:
			return "Guerra de Talismanes"
		PriorityContext.RESPONSE_WINDOW:
			return "Ventana de Respuesta"
		PriorityContext.BLOCK_DECLARATION:
			return "Declarar Bloqueadores"
		PriorityContext.DISCARD_PHASE:
			return "Fase de Descarte"
		PriorityContext.PHASE_START:
			return "Comienzo de Fase"
		_:
			return "Prioridad"


# =============================================================================
# PASO DE PRIORIDAD (DAR 5.C3)
# =============================================================================
func pass_priority() -> void:
	"""El jugador actual pasa su prioridad
	Si ambos pasan consecutivamente, la ventana se cierra y se resuelve
	"""
	if not priority_window_active:
		return

	var passing_player = current_priority_player
	player_passed[passing_player] = true

	if Constants.VERBOSE_DIAG_LOGS:
		print("[PriorityManager] Jugador %d pasa prioridad" % (passing_player + 1))
	emit_signal("priority_passed", passing_player)

	# Verificar si ambos han pasado consecutivamente (DAR 5.C3: pila vacía →
	# la fase termina — este motor no usa una pila de efectos real en
	# PriorityManager, ver ActionPipeline para la pila LIFO que sí se usa).
	if player_passed[0] and player_passed[1]:
		if Constants.VERBOSE_DIAG_LOGS:
			print("[PriorityManager] Ambos jugadores pasaron consecutivamente → Fase termina")
		emit_signal("both_players_passed")
		_close_priority_window(false)  # false: señal ya emitida arriba, evitar doble disparo
		return

	# Pasar prioridad al otro jugador
	_switch_priority()


func _switch_priority() -> void:
	"""Cambia la prioridad al otro jugador"""
	var old_player = current_priority_player
	current_priority_player = 1 - current_priority_player

	if Constants.VERBOSE_DIAG_LOGS:
		print("[PriorityManager] Prioridad: Jugador %d → Jugador %d" % [
			old_player + 1, current_priority_player + 1
		])

	emit_signal("priority_changed", current_priority_player)


func _close_priority_window(both_passed: bool) -> void:
	"""Cierra la ventana de prioridad actual"""
	# La Ventana de Respuesta de una acción hecha en la Guerra (§64): quien
	# controlaba el objeto de la pila es quien actuó.
	if current_priority_context == PriorityContext.RESPONSE_WINDOW \
			and GameManager.current_phase == Constants.Phase.GUERRA_TALISMANES:
		if current_stack_controller >= 0:
			_guerra_last_actor = current_stack_controller
		_schedule_guerra_resume(false)
	priority_window_active = false
	current_priority_context = PriorityContext.NONE
	current_context = ""
	valid_actions.clear()

	emit_signal("priority_window_closed")

	if both_passed:
		emit_signal("both_players_passed")


# =============================================================================
# INTEGRACIÓN CON FASES
# =============================================================================
func _on_phase_changed(new_phase: int) -> void:
	"""Responde a cambios de fase del TurnManager"""
	# Cerrar cualquier ventana de prioridad activa al cambiar de fase
	if priority_window_active:
		_close_priority_window(false)
	_guerra_last_actor = -1
	_guerra_actions_running = 0

	# Iniciar ventana de prioridad según la fase
	match new_phase:
		Constants.Phase.GUERRA_TALISMANES:
			start_priority_window(PriorityContext.GUERRA_TALISMANES)
		Constants.Phase.BLOQUEO:
			start_priority_window(PriorityContext.BLOCK_DECLARATION)


# =============================================================================
# CONSULTAS
# =============================================================================
func needs_real_decision(player_id: int) -> bool:
	"""¿Tiene este jugador una decisión real en la ventana actual, o puede pasar solo? El jugador
	activo pasa para ir a la Guerra o terminar el turno; el otro, cada vez que el oponente juega
	una carta o usa una habilidad:
	- Ventana de Respuesta: decide solo el rival de quien controla el objeto de la pila. Sin objeto
	puntual (pila recién vaciada), nadie.
	- Bloqueo: decide solo el defensor.
	- Guerra de Talismanes (y el resto): deciden ambos."""
	match current_priority_context:
		PriorityContext.RESPONSE_WINDOW:
			return current_stack_controller >= 0 and player_id != current_stack_controller
		PriorityContext.BLOCK_DECLARATION:
			var active_player: int = GameManager.active_player_id if GameManager else 0
			return player_id != active_player
		PriorityContext.PHASE_START:
			return not load("res://scripts/core/game/PhaseStartWindow.gd").playable_cards(player_id).is_empty()
		_:
			return true


func has_priority(player_id: int) -> bool:
	"""Verifica si un jugador tiene prioridad actualmente"""
	return priority_window_active and current_priority_player == player_id


func can_act(player_id: int) -> bool:
	"""Verifica si un jugador puede tomar acciones"""
	return has_priority(player_id)


# =============================================================================
# UTILIDADES PARA GUERRA DE TALISMANES
# =============================================================================
func force_close() -> void:
	"""Fuerza el cierre de la ventana de prioridad"""
	if priority_window_active:
		_close_priority_window(false)


func is_guerra_window() -> bool:
	return priority_window_active and current_priority_context == PriorityContext.GUERRA_TALISMANES


func begin_guerra_action(player_id: int) -> void:
	"""Un jugador juega una carta en la Guerra de Talismanes (§64). Mientras
	se resuelve, la Guerra no se reabre aunque se cierren ventanas anidadas."""
	if GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
		return
	_guerra_actions_running += 1
	_guerra_last_actor = player_id


func end_guerra_action() -> void:
	if _guerra_actions_running <= 0:
		return
	_guerra_actions_running -= 1
	_schedule_guerra_resume(true)


func _schedule_guerra_resume(after_action: bool) -> void:
	_guerra_resume_after_action = _guerra_resume_after_action or after_action
	if _guerra_resume_scheduled:
		return
	_guerra_resume_scheduled = true
	_resume_guerra.call_deferred()


func _resume_guerra() -> void:
	"""Reabre la ventana de la Guerra cuando ya no queda nada resolviéndose,
	con la prioridad para el jugador que no hizo la última acción. Si la
	acción no abrió ninguna ventana anidada (la de la Guerra sigue abierta),
	igual pasa la prioridad al otro y reinicia los pases."""
	for _i in 600:  # hasta 60s: un efecto puede esperar elecciones del jugador
		if not GameManager.is_game_active or GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
			break
		var idle: bool = _guerra_actions_running == 0 and not ActionPipeline.is_stack_processing() \
			and not TriggerSystem.awaiting_response
		if idle and (not priority_window_active or (current_priority_context == PriorityContext.GUERRA_TALISMANES
				and _guerra_resume_after_action)):
			var next_player: int = 1 - _guerra_last_actor if _guerra_last_actor >= 0 else -1
			if Constants.VERBOSE_DIAG_LOGS:
				print("[PriorityManager] Guerra de Talismanes continúa — prioridad: Jugador %d" % (
					(next_player if next_player >= 0 else _get_starting_priority_player(PriorityContext.GUERRA_TALISMANES)) + 1))
			start_priority_window(PriorityContext.GUERRA_TALISMANES, next_player)
			break
		if idle and current_priority_context == PriorityContext.GUERRA_TALISMANES:
			break  # ya está abierta y no hubo acción nueva
		await get_tree().create_timer(0.1).timeout
	_guerra_resume_scheduled = false
	_guerra_resume_after_action = false
