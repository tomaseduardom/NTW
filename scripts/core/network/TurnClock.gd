extends Node
class_name TurnClock
## TurnClock — relojes de las partidas en línea. Los lleva el Anfitrión (autoritativo) y el Remoto
## solo los muestra ({"op":"clock"}). Instanciado siempre en Main.gd; inerte sin sala.
## - Jugador activo: TURN_SECONDS por turno, +ACTION_BONUS por acción (una carta o un Oro que entra en
##   juego, un pago de Oro). Corre siempre, también durante sus efectos y búsquedas; solo se detiene
##   mientras decide el rival. El turno siguiente vuelve a empezar de TURN_SECONDS.
## - Jugador rival: OPP_SECONDS por turno para todas sus decisiones en el turno ajeno (bloqueos,
##   respuestas, elecciones de efectos). Corre solo mientras él decide.
## - Sin tiempo, todo se resuelve solo con la opción por defecto: pasar prioridad, cancelar lo
##   opcional, las primeras opciones válidas en lo obligatorio, y (jugador activo) ¿Paso? hasta
##   terminar el turno. En el Anfitrión lo hace _auto_resolve_host() (y las ventanas, con
##   NetworkClient.local_timeout); para el Remoto, NetworkClient.forced_intent devuelve el intent por
##   defecto y se le manda {"op":"force_close"} para que cierre lo que tenga abierto.
## - Mientras alguien se reconecta (NetworkClient.reconnecting_now / peer_away) los relojes no corren.
## - Fase Final del jugador activo sin tiempo: FINAL_GRACE segundos para descartar por límite de
##   mano; después se descartan las primeras cartas de la izquierda.

const TURN_SECONDS := 60.0
const OPP_SECONDS := 30.0
const ACTION_BONUS := 2.0
const FINAL_GRACE := 10.0
## Dos señales de la misma acción (el Aliado entra en juego y se paga su coste) suman una vez.
const BONUS_DEBOUNCE_MS := 600
const LOW_TIME := 10.0
const IN_PLAY_CONTAINERS := ["player_gold", "player_oro_pagado", "player_field", "player_linea_ataque",
	"player_linea_apoyo", "opponent_gold", "opponent_oro_pagado", "opponent_field",
	"opponent_linea_ataque", "opponent_linea_apoyo"]

var _main: Node = null
var _host: bool = false
var _active: bool = false

var _remaining: float = TURN_SECONDS
var _opp_remaining: float = OPP_SECONDS
var _active_pid: int = 0
var _expired: bool = false
var _grace_start_ms: int = -1
var _grace_woken: bool = false
var _last_bonus_ms: int = -100000
var _pressed_key: String = ""
var _pressed_ms: int = 0
var _last_pagado := {0: 0, 1: 0}
var _last_auto_ms: int = 0
var _poll: float = 0.0
var _last_sent: Dictionary = {}
## Jugador que está descartando por límite de mano (PhaseFlowController._enforce_hand_limit), -1 si
## ninguno.
var hand_limit_pid: int = -1


func setup(main: Node) -> void:
	_main = main
	_active = NetworkClient.room_code != ""
	if not _active:
		set_process(false)
		return
	_host = NetworkClient.is_host
	if _host:
		GameManager.turn_started.connect(_on_turn_started)
		EffectController.on_card_entered_play.connect(_on_card_entered_play)
		GameState.oro_pagado_changed.connect(_on_oro_pagado_changed)
		NetworkClient.forced_intent = _forced_intent
	else:
		NetworkClient.message_received.connect(_on_message)
		set_process(false)


func _exit_tree() -> void:
	if _host:
		NetworkClient.forced_intent = Callable()
		NetworkClient.local_timeout = false


# =============================================================================
# ANFITRIÓN — tiempo
# =============================================================================
func _on_turn_started(player_id: int, _turn_number: int) -> void:
	_active_pid = player_id
	_remaining = TURN_SECONDS
	_opp_remaining = OPP_SECONDS
	_expired = false
	_grace_start_ms = -1
	_grace_woken = false
	_pressed_key = ""
	hand_limit_pid = -1
	_broadcast(true)


func _add_bonus(player_id: int) -> void:
	if _expired or player_id != _active_pid or not GameManager.is_game_active:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bonus_ms < BONUS_DEBOUNCE_MS:
		return
	_last_bonus_ms = now
	_remaining += ACTION_BONUS
	_broadcast(true)


func _on_card_entered_play(player_id: int, _card: Node, _zone: int) -> void:
	_add_bonus(player_id)


func _on_oro_pagado_changed(player_id: int, amount: int) -> void:
	# Solo cuando sube (un pago): el reinicio de la Agrupación no es una acción.
	var before: int = int(_last_pagado.get(player_id, 0))
	_last_pagado[player_id] = amount
	if amount > before:
		_add_bonus(player_id)


func _host_deciding() -> bool:
	"""El jugador del Anfitrión tiene una decisión abierta (prioridad, objetivo, ventana)."""
	if PriorityManager.priority_window_active and PriorityManager.current_priority_player == 0:
		return true
	var ci = _main._card_interaction
	if (ci and ci.is_selecting_target) or SelectionManager.is_open or NetworkClient.local_waits > 0:
		return true
	if _main._zone_browse_picker and _main._zone_browse_picker.is_active():
		return true
	var dialogs = SelectionManager._dialogs
	return dialogs != null and dialogs._castillo_pick_active


func _opp_deciding() -> bool:
	"""Decide el jugador que no tiene el turno."""
	if _active_pid == 0:
		return NetworkClient.remote_waits > 0
	return NetworkClient.remote_waits == 0 and _host_deciding()


func _out_of_time(player_id: int) -> bool:
	if player_id == _active_pid:
		return _expired
	return _opp_remaining <= 0.0


func _grace_over() -> bool:
	return _grace_start_ms >= 0 and Time.get_ticks_msec() - _grace_start_ms >= int(FINAL_GRACE * 1000.0)


func _grace_left() -> int:
	if _grace_start_ms < 0:
		return -1
	return maxi(0, ceili(FINAL_GRACE - (Time.get_ticks_msec() - _grace_start_ms) / 1000.0))


func _process(delta: float) -> void:
	if not _host or not GameManager.is_game_active:
		NetworkClient.local_timeout = false
		return
	var opp_deciding := _opp_deciding()
	# Alguien se está reconectando (NetworkClient): los relojes se detienen hasta que vuelva.
	var frozen: bool = NetworkClient.reconnecting_now or NetworkClient.peer_away
	if frozen:
		pass
	elif opp_deciding:
		if _opp_remaining > 0.0:
			_opp_remaining -= delta
			if _opp_remaining <= 0.0:
				_opp_remaining = 0.0
				_main._update_debug("Se acabó el tiempo de respuesta del rival del turno")
				NetworkClient.wake_intent_waiters()
	elif not _expired:
		_remaining -= delta
		if _remaining <= 0.0:
			_remaining = 0.0
			_expired = true
			_main._update_debug("Se acabó el tiempo del turno — el turno avanza solo")
			NetworkClient.wake_intent_waiters()
	if _expired and _grace_start_ms < 0 and GameManager.current_phase == Constants.Phase.FINAL:
		_grace_start_ms = Time.get_ticks_msec()
	if _expired and not _grace_woken and _grace_over():
		_grace_woken = true
		NetworkClient.wake_intent_waiters()
	# Las ventanas del Anfitrión se cierran solas con esto (NetworkClient.ui_forced()), salvo el
	# descarte de la Fase Final mientras dura su plazo.
	NetworkClient.local_timeout = _out_of_time(0) and not (hand_limit_pid == 0 and not _grace_over())
	_poll += delta
	if _poll >= 0.25:
		_poll = 0.0
		if _out_of_time(0):
			_auto_resolve_host()
		_broadcast(false)
	_update_display(_active_pid == 0, _remaining, _expired, _grace_left(), opp_deciding, _active_pid == 1,
		_opp_remaining)


# =============================================================================
# ANFITRIÓN — resolver solo lo que tenga abierto el jugador sin tiempo
# =============================================================================
func _auto_resolve_host() -> void:
	if NetworkClient.remote_waits > 0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_auto_ms < 300:
		return
	_last_auto_ms = now
	var ci = _main._card_interaction
	var dialogs = SelectionManager._dialogs
	# Castillo primero: si corre en carrera con una selección de carta, resolverlo cancela la otra.
	if dialogs and dialogs._castillo_pick_active:
		dialogs._resolve_castillo_pick(dialogs._castillo_pick_own_only)
		return
	if ci and ci.is_selecting_target:
		if hand_limit_pid == 0:
			if _grace_over():
				_pick_first_valid(ci, _main.player_hand.cards)
			return
		if ci._selection_cancellable:
			ci.cancel_target_selection()
		else:
			_pick_first_valid(ci, _target_pool(ci))
		return
	if SelectionManager.is_open:
		SelectionManager.force_default()
		return
	# Las ventanas (RevealWindow, CastleLookWindow, BoardChoice, ZoneBrowsePicker...) se cierran solas.
	if NetworkClient.local_waits > 0 or (_main._zone_browse_picker and _main._zone_browse_picker.is_active()):
		return
	if PriorityManager.priority_window_active:
		if PriorityManager.current_priority_player == 0:
			PriorityManager.pass_priority()
		return
	if _active_pid != 0 or not _expired:
		return
	if TriggerSystem.is_resolving or GameManager.agrupacion_busy:
		return
	var phase := GameManager.current_phase
	if phase not in [Constants.Phase.VIGILIA, Constants.Phase.ATAQUE, Constants.Phase.FINAL]:
		return
	var key := "%d:%d" % [GameManager.turn_serial, int(phase)]
	# Una vez por fase; Vigilia y Ataque se reintentan si a los 3 s la fase no avanzó (la Fase Final
	# no: dos ¿Paso? resolverían el robo dos veces).
	if key == _pressed_key and (phase == Constants.Phase.FINAL or now - _pressed_ms < 3000):
		return
	_pressed_key = key
	_pressed_ms = now
	_main._phase_flow._on_paso_pressed()


func _target_pool(ci) -> Array:
	var pool: Array = []
	pool.append_array(_main.player_hand.cards)
	if _main._opponent_fan:
		pool.append_array(_main._opponent_fan.get_cards())
	for prop in IN_PLAY_CONTAINERS:
		var container: Node = _main.get(prop)
		if container:
			pool.append_array(container.get_children())
	pool.append_array(ci._cemetery_target_nodes)
	return pool


func _pick_first_valid(ci, cards: Array) -> void:
	for card in cards:
		if is_instance_valid(card) and card is Node and (not ci._target_filter.is_valid() or ci._target_filter.call(card)):
			ci._resolve_target_selection(card)
			return


# =============================================================================
# ANFITRIÓN — respuestas por defecto del Remoto sin tiempo
# =============================================================================
func _forced_intent(expected_kinds: Array) -> Dictionary:
	"""Intent por defecto para el Remoto sin tiempo (NetworkClient.await_intent y la ventana de
	prioridad de RemotePlayerController). Se arma desde el último prompt que se le mandó."""
	if not GameManager.is_game_active or not _out_of_time(1):
		return {}
	var intent := _default_intent(expected_kinds, NetworkClient.last_prompt)
	if not intent.is_empty():
		NetworkClient.send_message({"op": "force_close"})
	return intent


func _default_intent(kinds: Array, prompt: Dictionary) -> Dictionary:
	var candidates: Array = prompt.get("candidates", []) if prompt.get("candidates") is Array else []
	var first_ids := func(n: int) -> Array:
		var ids: Array = []
		for c in candidates:
			if ids.size() >= n:
				break
			if c is Dictionary and c.has("card_id"):
				ids.append(str(c.card_id))
		return ids
	if "end_vigilia" in kinds:
		return _intent("end_vigilia")
	if "declare_attackers" in kinds:
		return _intent("declare_attackers", {"card_ids": []})
	if "pass" in kinds or "priority_response" in kinds:
		return _intent("pass")
	if "mulligan_choice" in kinds:
		return _intent("mulligan_choice", {"keep": true})
	if "hand_shown_closed" in kinds:
		return _intent("hand_shown_closed")
	if "choose_wielder" in kinds:
		return _intent("choose_wielder", {"card_id": ""})
	if "choose_option_choice" in kinds:
		return _intent("choose_option_choice", {"index": 0})
	if "name_card_choice" in kinds:
		return _intent("name_card_choice", {"card_data": {}})
	if "select_cemetery_cards_choice" in kinds:
		return _intent("select_cemetery_cards_choice", {"indices": []})
	if "reveal_window_choice" in kinds:
		return _intent("reveal_window_choice",
			{"result": load("res://scripts/ui/zones/RevealWindow.gd").auto_pick(prompt.get("config", {}))})
	if "castle_look_choice" in kinds:
		return _intent("castle_look_choice",
			{"result": load("res://scripts/ui/zones/CastleLookWindow.gd").auto_pick(prompt.get("config", {}))})
	if "zone_pick_choice" in kinds:
		var picks: Array = load("res://scripts/ui/zones/ZoneBrowsePicker.gd").default_picks(
			prompt.get("pools", []), int(prompt.get("min_selections", 0)), bool(prompt.get("distinct_names", false)))
		return _intent("zone_pick_choice", {"picks": picks, "opened_castles": []})
	if "select_cards_choice" in kinds:
		if bool(prompt.get("can_cancel", true)):
			return _intent("select_cards_choice", {"cancelled": true, "indices": []})
		var need: int = mini(maxi(int(prompt.get("min_selections", 0)), 1), candidates.size())
		return _intent("select_cards_choice", {"indices": range(need)})
	if "await_target_choice" in kinds:
		var ids: Array = first_ids.call(1)
		if bool(prompt.get("cancellable", true)) or ids.is_empty():
			return _intent("await_target_choice", {"cancelled": true})
		return _intent("await_target_choice", {"card_id": ids[0]})
	if "await_target_or_castillo_choice" in kinds:
		var ids: Array = first_ids.call(1)
		if bool(prompt.get("cancellable", true)):
			return _intent("await_target_or_castillo_choice", {"type": "none"})
		if not ids.is_empty():
			return _intent("await_target_or_castillo_choice", {"type": "card", "card_id": ids[0]})
		return _intent("await_target_or_castillo_choice", {"type": "castillo", "own": true})
	if "await_multi_target_choice" in kinds:
		# Descarte de la Fase Final: espera su plazo y descarta las primeras de la izquierda.
		if hand_limit_pid == 1 and _active_pid == 1:
			if not _grace_over():
				return {}
		elif bool(prompt.get("cancellable", true)):
			return _intent("await_multi_target_choice", {"card_ids": []})
		var max_sel: int = int(prompt.get("max_selections", 1))
		return _intent("await_multi_target_choice", {"card_ids": first_ids.call(max_sel if max_sel > 0 else 1)})
	return {}


func _intent(kind: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"op": "intent", "kind": kind}
	d.merge(extra)
	return d


func _broadcast(force: bool) -> void:
	var state := {
		"op": "clock",
		"remote_turn": _active_pid == 1,
		"remaining": ceili(_remaining),
		"expired": _expired,
		"grace": _grace_left(),
		"opp_deciding": _opp_deciding(),
		"opp_remaining": ceili(_opp_remaining),
	}
	if not force and state == _last_sent:
		return
	_last_sent = state
	NetworkClient.send_message(state)


# =============================================================================
# REMOTO
# =============================================================================
func _on_message(data: Dictionary) -> void:
	if data.get("op", "") != "clock":
		return
	var remote_turn := bool(data.get("remote_turn", false))
	_update_display(remote_turn, float(data.get("remaining", 0)), bool(data.get("expired", false)),
		int(data.get("grace", -1)), bool(data.get("opp_deciding", false)), not remote_turn,
		float(data.get("opp_remaining", 0)))


# =============================================================================
# PANEL (TurnTimer de Main.tscn)
# =============================================================================
func _update_display(own_turn: bool, remaining: float, expired: bool, grace: int, opp_deciding: bool,
		own_is_opp: bool, opp_remaining: float) -> void:
	"""own_turn: el turno es de quien mira. Mientras decide el rival del turno se muestra su reloj
	de respuesta (own_is_opp: ese rival es quien mira)."""
	var panel := _main.get_node_or_null("TurnTimer")
	if not panel:
		return
	panel.visible = true
	var icon: Label = panel.get_node_or_null("VBox/TimerIcon")
	var label: Label = panel.get_node_or_null("VBox/TimerLabel")
	var sub: Label = panel.get_node_or_null("VBox/TimerSub")
	var shown: float = remaining
	var out := expired
	if opp_deciding:
		shown = opp_remaining
		out = opp_remaining <= 0.0
		if icon:
			icon.text = "TU RESPUESTA" if own_is_opp else "RESPUESTA RIVAL"
	elif icon:
		icon.text = "TU TURNO" if own_turn else "TURNO RIVAL"
	if label:
		label.text = str(grace) if expired and grace >= 0 and not opp_deciding else str(ceili(shown))
		var low := out or shown <= LOW_TIME
		label.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if low else Color(1, 0.95, 0.75))
	if sub:
		if expired and grace >= 0 and not opp_deciding:
			sub.text = "para descartar"
		elif out:
			sub.text = "tiempo agotado"
		else:
			sub.text = "segundos"
