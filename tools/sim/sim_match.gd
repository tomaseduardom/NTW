extends Node
## Simulador de partidas completas sin persona (2026-11-02). Juega una partida de punta a punta con
## dos mazos preset al azar y anota lo que encuentra:
##   - Invariantes (cada pocos frames, con el tablero quieto): contador de Oro contra las cartas
##     físicas, Castillo de Main contra el de CardManager, zona de cada carta contra su contenedor,
##     contadores negativos y total de cartas de cada dueño.
##   - Trabas: nada cambia en STALL_GAME_S segundos de juego (fase, prioridad, Pila, manos, mazos).
##   - Fin: quién gana, en cuántos turnos, o si se cortó (trabada, límite de turnos).
## El jugador 0 lo maneja este script por los caminos del humano (GoldManager.play_card(),
## _declare_attacker(), ¿Paso?, y las elecciones como _auto_resolve_host() de probe_parity).
## Modos:
##   offline <salida.json> <semilla>                      jugador 1 = EasyBotController
##   host    <salida.json> <semilla> <archivo_codigo> <url_relay>   jugador 1 = Remoto real por red;
##       sus decisiones las toma este script (NetworkClient.forced_intent) y cada checkpoint manda
##       {"op":"sim_check"} con el estado que el Remoto debería ver.
##   remote  <salida.json> <semilla> <archivo_codigo> <url_relay>   refleja la partida y compara cada
##       sim_check con lo que muestra su RemoteMirrorController (desincronización).
## Uso: tools/sim/run_sim.ps1 (offline) y tools/sim/run_sim_online.ps1 (en línea).

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const TurnClockScript = preload("res://scripts/core/network/TurnClock.gd")

const TIME_SCALE := 6.0
const STALL_GAME_S := 90.0
const MAX_STALLS := 3
const MAX_TURNS := 80
const MAX_REAL_MS := 15 * 60 * 1000
const CHECK_EVERY_GAME_S := 4.0

## Contenedor de Main -> [jugador, zona].
const CONTAINERS := {
	"player_gold": [0, Constants.Zone.RESERVA_ORO], "player_oro_pagado": [0, Constants.Zone.ORO_PAGADO],
	"player_field": [0, Constants.Zone.LINEA_DEFENSA], "player_linea_ataque": [0, Constants.Zone.LINEA_ATAQUE],
	"player_linea_apoyo": [0, Constants.Zone.LINEA_APOYO],
	"opponent_gold": [1, Constants.Zone.RESERVA_ORO], "opponent_oro_pagado": [1, Constants.Zone.ORO_PAGADO],
	"opponent_field": [1, Constants.Zone.LINEA_DEFENSA], "opponent_linea_ataque": [1, Constants.Zone.LINEA_ATAQUE],
	"opponent_linea_apoyo": [1, Constants.Zone.LINEA_APOYO],
}
const ZONE_KEYS := {
	Constants.Zone.RESERVA_ORO: "reserva", Constants.Zone.ORO_PAGADO: "pagado",
	Constants.Zone.LINEA_DEFENSA: "defensa", Constants.Zone.LINEA_ATAQUE: "ataque",
	Constants.Zone.LINEA_APOYO: "apoyo",
}

var mode: String = "offline"
var main: Node = null
var out_path: String = ""
var rng_seed: int = 0
var code_file: String = ""
var relay_url: String = ""

var result := {}
var _violations: Dictionary = {}  # clave -> {tipo, detalle, turno, veces}
var _stalls: Array = []
var _desyncs: Dictionary = {}  # clave -> {campo, anfitrion, remoto, turno, veces}
var _prev_diff: Dictionary = {}  # campos distintos en el checkpoint anterior
var _checks_sent: int = 0
var _checks_ok: int = 0
var _ended: bool = false
var _winner: int = -1
var _end_reason: String = ""
var _start_ms: int = 0
var _initial_totals: Dictionary = {}
var _checks_ready: bool = false
var _prev_seen: Dictionary = {}  # invariantes vistas en el chequeo anterior (se informan si se repiten)

var _sig: String = ""
var _sig_game_s: float = 0.0
var _driver_step: String = ""
var _check_game_s: float = 0.0
var _check_seq: int = 0
var _last_check_key: String = ""
var _inv_frames: int = 0
var _p1_actions: Dictionary = {}  # turn_serial -> acciones del Remoto simulado
var _p1_gold_turn: int = -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	mode = args[0] if args.size() > 0 else "offline"
	out_path = args[1] if args.size() > 1 else "user://sim.json"
	rng_seed = int(args[2]) if args.size() > 2 else int(Time.get_unix_time_from_system())
	code_file = args[3] if args.size() > 3 else ""
	relay_url = args[4] if args.size() > 4 else "ws://localhost:8080"
	seed(rng_seed)
	_start_ms = Time.get_ticks_msec()
	result = {"modo": mode, "semilla": rng_seed}
	if mode != "offline":
		if not await _connect_online():
			_finish("sin conexión")
			return
	Engine.time_scale = TIME_SCALE
	GameManager.game_ended.connect(func(w: int):
		_winner = w
		_end("fin normal"))
	main = load("res://scenes/game/Main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	# CardManager (y otros) buscan Main en current_scene, como cuando se juega desde el menú.
	(func(): get_tree().current_scene = main).call_deferred()
	if not await _choose_decks():
		_finish("sin selector de mazos")
		return
	if mode == "remote":
		NetworkClient.message_received.connect(_on_remote_message)
		await _remote_wait_end()
		return
	if mode == "host":
		NetworkClient.forced_intent = _p1_brain
		NetworkClient.local_timeout = true  # ventanas propias: opción por defecto
	else:
		NetworkClient.sim_force_ui = true
	await _wait_mulligan_and_keep()
	if mode == "host" and main.get("_turn_clock"):
		main._turn_clock.set_process(false)
	await _settle()
	_initial_totals = _owner_totals()
	result["cartas_iniciales"] = _initial_totals.duplicate()
	_checks_ready = true
	_drive_player0()
	while not _ended:
		await get_tree().process_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	_finish(_end_reason)


# =============================================================================
# EN LÍNEA: conexión
# =============================================================================
func _connect_online() -> bool:
	NetworkClient.connect_to_relay(relay_url)
	var ok: bool = await _await_signal_or_timeout(NetworkClient.connected_to_relay, 15000)
	if not ok:
		return false
	if mode == "host":
		NetworkClient.create_room()
		var code = await NetworkClient.room_created
		var f := FileAccess.open(code_file, FileAccess.WRITE)
		f.store_string(str(code))
		f.close()
		return await _await_signal_or_timeout(NetworkClient.peer_joined, 60000)
	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(code_file) or FileAccess.get_file_as_string(code_file).strip_edges().is_empty():
		if Time.get_ticks_msec() - t0 > 60000:
			return false
		await get_tree().process_frame
	NetworkClient.join_room(FileAccess.get_file_as_string(code_file).strip_edges())
	return await _await_signal_or_timeout(NetworkClient.room_joined, 15000)


func _await_signal_or_timeout(sig: Signal, ms: int) -> bool:
	var state := {"done": false}
	var cb := func(_a = null): state.done = true
	sig.connect(cb, CONNECT_ONE_SHOT)
	var t0 := Time.get_ticks_msec()
	while not state.done and Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	if not state.done and sig.is_connected(cb):
		sig.disconnect(cb)
	return state.done


# =============================================================================
# INICIO: mazos y mulligan
# =============================================================================
func _choose_decks() -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if not is_instance_valid(main) or not main.is_inside_tree():
			continue
		for child in main.get_children():
			var s = child.get_script()
			if s and str(s.resource_path).ends_with("ui/zones/DeckSelector.gd"):
				var decks: Array = DeckLoader.get_bundled_decks()
				if decks.is_empty():
					return false
				var a: Dictionary = decks[randi() % decks.size()]
				var b: Dictionary = decks[randi() % decks.size()]
				result["mazos"] = [str(a.get("slug", "")), str(b.get("slug", ""))]
				child.queue_free()
				main._bootstrap._on_decks_selected(a, b)
				return true
	return false


func _wait_mulligan_and_keep() -> void:
	while not (main._mulligan_ctrl and main._mulligan_ctrl.is_in_mulligan):
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	await main._mulligan_ctrl._end_mulligan_phase()
	while not GameManager.is_game_active:
		await get_tree().process_frame


# =============================================================================
# JUGADOR 0: caminos del humano
# =============================================================================
func _busy() -> bool:
	if not EffectContextScript._stack.is_empty() or ActionPipeline._is_resolving or TriggerSystem.is_resolving:
		return true
	if PriorityManager.priority_window_active or GameManager.agrupacion_busy:
		return true
	if main._card_interaction and main._card_interaction.is_selecting_target:
		return true
	if main.get("_zone_browse_picker") and main._zone_browse_picker.is_active():
		return true
	return SelectionManager.is_open or NetworkClient.remote_waits > 0 or NetworkClient.local_waits > 0


func _settle(max_frames: int = 600) -> void:
	var quiet := 0
	for i in max_frames:
		await get_tree().process_frame
		quiet = quiet + 1 if not _busy() else 0
		if quiet >= 4 or _ended:
			return


func _drive_player0() -> void:
	var last_key := ""
	while not _ended:
		await get_tree().process_frame
		if not GameManager.is_game_active or GameManager.active_player_id != 0 or _busy():
			continue
		var phase: int = GameManager.current_phase
		var key := "%d:%d" % [GameManager.turn_serial, phase]
		if key == last_key:
			continue
		last_key = key
		match phase:
			Constants.Phase.VIGILIA:
				await _p0_vigilia()
			Constants.Phase.ATAQUE:
				await _p0_ataque()
			Constants.Phase.FINAL:
				_driver_step = "Fase Final: ¿Paso?"
				main._phase_flow._on_paso_pressed()
			_:
				last_key = ""  # otras fases avanzan solas; se vuelve a mirar


func _p0_vigilia() -> void:
	var tried: Array = []
	var gold_done := false
	for attempt in 8:
		await _settle()
		if _ended or GameManager.current_phase != Constants.Phase.VIGILIA or GameManager.active_player_id != 0:
			return
		var hand: Array = main.player_hand.cards.filter(func(c): return is_instance_valid(c) and not c in tried)
		var gold: Array = hand.filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
		var card: Node = null
		if not gold_done and not gold.is_empty():
			card = gold[0]
			gold_done = true
		else:
			var others: Array = hand.filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
			if others.is_empty() or randf() < 0.15:
				break
			card = others[randi() % others.size()]
		tried.append(card)
		_driver_step = "Vigilia: jugar %s" % str(card.get("card_name"))
		await main._gold_manager.play_card(card)
	await _settle()
	if GameManager.current_phase == Constants.Phase.VIGILIA and GameManager.active_player_id == 0 and not _ended:
		_driver_step = "Vigilia: ¿Paso? (atacar)"
		main._phase_flow._on_paso_pressed()


func _p0_ataque() -> void:
	await _settle()
	for ally in main.player_field.get_children().duplicate():
		if _ended or GameManager.current_phase != Constants.Phase.ATAQUE:
			return
		if is_instance_valid(ally) and TurnManager.can_attack(ally).get("can_attack", false) and randf() < 0.6:
			_driver_step = "Ataque: declarar %s" % str(ally.get("card_name"))
			await main._card_interaction._declare_attacker(ally)
	await _settle()
	if GameManager.current_phase == Constants.Phase.ATAQUE and GameManager.active_player_id == 0 and not _ended:
		_driver_step = "Ataque: confirmar"
		await main._phase_flow._on_paso_pressed()


func _sorted_for(cards: Array, chooser: int) -> Array:
	var valid: Array = cards.filter(func(c): return is_instance_valid(c) and c is Node)
	valid.shuffle()
	valid.sort_custom(func(x, y):
		var cx: int = 0 if int(x.get("controller_id") if x.get("controller_id") != null else -1) == chooser else 1
		var cy: int = 0 if int(y.get("controller_id") if y.get("controller_id") != null else -1) == chooser else 1
		return cx < cy)
	return valid


func _auto_resolve_host() -> void:
	"""Elecciones del jugador 0 (mismo criterio que probe_parity): lo opcional a veces se hace, lo
	obligatorio elige lo propio primero; la prioridad se pasa."""
	var ci = main._card_interaction
	var dialogs = SelectionManager._dialogs
	if dialogs and dialogs._castillo_pick_active:
		dialogs._resolve_castillo_pick(true)
		return
	if ci and ci.is_selecting_target:
		if ci._selection_cancellable and randf() < 0.3:
			ci.cancel_target_selection()
			return
		var pool: Array = []
		pool.append_array(main.player_hand.cards)
		pool.append_array(main._opponent_fan.get_cards())
		for prop in TurnClockScript.IN_PLAY_CONTAINERS:
			var container: Node = main.get(prop)
			if container:
				pool.append_array(container.get_children())
		pool.append_array(ci._cemetery_target_nodes)
		for c in _sorted_for(pool, 0):
			if not ci._target_filter.is_valid() or ci._target_filter.call(c):
				ci._resolve_target_selection(c)
				return
		ci.cancel_target_selection()
		return
	if SelectionManager.is_open:
		SelectionManager.force_default()
		return
	if PriorityManager.priority_window_active and PriorityManager.current_priority_player == 0:
		PriorityManager.pass_priority()


# =============================================================================
# JUGADOR 1 EN LÍNEA: decisiones del Remoto simuladas en el Anfitrión
# =============================================================================
func _p1_brain(kinds: Array) -> Dictionary:
	var prompt: Dictionary = NetworkClient.last_prompt
	var turn: int = GameManager.turn_serial
	if "play_card" in kinds or "place_gold" in kinds:
		var used: int = int(_p1_actions.get(turn, 0))
		var golds: Array = prompt.get("gold_candidates", [])
		if _p1_gold_turn != turn and not golds.is_empty():
			_p1_gold_turn = turn
			_p1_actions[turn] = used + 1
			return {"op": "intent", "kind": "place_gold", "card_id": str(golds[0].get("card_id", ""))}
		var plays: Array = []
		for k in ["ally_candidates", "weapon_candidates", "talisman_candidates", "totem_candidates"]:
			plays.append_array(prompt.get(k, []))
		if used < 7 and not plays.is_empty() and randf() < 0.85:
			_p1_actions[turn] = used + 1
			return {"op": "intent", "kind": "play_card", "card_id": str(plays[randi() % plays.size()].get("card_id", ""))}
		return {"op": "intent", "kind": "end_vigilia"}
	if "declare_attackers" in kinds:
		var ids: Array = []
		for a in prompt.get("attackable", []):
			if randf() < 0.6:
				ids.append(str(a.get("card_id", "")))
		return {"op": "intent", "kind": "declare_attackers", "card_ids": ids}
	var candidates: Array = prompt.get("candidates", []) if prompt.get("candidates") is Array else []
	var nodes_by_id := {}
	for c in candidates:
		if c is Dictionary and str(c.get("card_id", "")).is_valid_int():
			var obj = instance_from_id(int(str(c.card_id)))
			if obj is Node:
				nodes_by_id[obj] = str(c.card_id)
	if not nodes_by_id.is_empty():
		var ordered: Array = _sorted_for(nodes_by_id.keys(), 1)
		if "await_target_choice" in kinds and not bool(prompt.get("cancellable", true)):
			return {"op": "intent", "kind": "await_target_choice", "card_id": nodes_by_id[ordered[0]]}
		if "await_multi_target_choice" in kinds and not bool(prompt.get("cancellable", true)):
			var n: int = maxi(1, int(prompt.get("max_selections", 1)))
			var ids: Array = []
			for c in ordered.slice(0, n):
				ids.append(nodes_by_id[c])
			return {"op": "intent", "kind": "await_multi_target_choice", "card_ids": ids}
	if "await_target_or_castillo_choice" in kinds:
		return {"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo", "own": true}
	if main and main.get("_turn_clock"):
		return main._turn_clock._default_intent(kinds, prompt)
	return {}


# =============================================================================
# CADA FRAME: elecciones, invariantes, trabas, checkpoints
# =============================================================================
func _process(delta: float) -> void:
	if _ended:
		return
	if Time.get_ticks_msec() - _start_ms > MAX_REAL_MS:
		_end("tiempo real agotado")
		return
	if mode == "remote" or not main or not GameManager.is_game_active:
		return
	if mode == "host":
		NetworkClient.local_timeout = true  # TurnClock lo apaga al cambiar de turno
	_auto_resolve_host()
	if GameManager.current_turn > MAX_TURNS:
		_end("límite de turnos")
		return
	_watch_stall(delta)
	_inv_frames += 1
	if _checks_ready and _inv_frames % 10 == 0 and not _busy():
		_check_invariants()
	if mode == "host":
		_check_game_s += delta
		var key := "%d:%d" % [GameManager.turn_serial, GameManager.current_phase]
		if (key != _last_check_key or _check_game_s >= CHECK_EVERY_GAME_S) and not _busy():
			_last_check_key = key
			_check_game_s = 0.0
			_send_check.call_deferred()


func _signature() -> String:
	return str([GameManager.turn_serial, GameManager.current_phase, PriorityManager.priority_window_active,
		PriorityManager.current_priority_player, EffectContextScript._stack.size(), ActionPipeline._stack.size(),
		main.player_hand.cards.size(), main._opponent_fan.get_cards().size(), main.player_deck.size(),
		main.opponent_deck.size(), GameState.get_oro_reserva(0), GameState.get_oro_reserva(1),
		main.player_field.get_child_count(), main.opponent_field.get_child_count()])


func _watch_stall(delta: float) -> void:
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_sig_game_s = 0.0
		return
	_sig_game_s += delta
	if _sig_game_s < STALL_GAME_S:
		return
	_sig_game_s = 0.0
	var info := {
		"turno": GameManager.current_turn, "activo": GameManager.active_player_id,
		"fase": Constants.PHASE_NAMES.get(GameManager.current_phase, "?"),
		"prioridad": PriorityManager.priority_window_active, "prioridad_de": PriorityManager.current_priority_player,
		"pila": EffectContextScript._stack.size(), "pila_acciones": ActionPipeline._stack.size(),
		"resolviendo": ActionPipeline._is_resolving or TriggerSystem.is_resolving,
		"eligiendo": main._card_interaction.is_selecting_target if main._card_interaction else false,
		"seleccion_abierta": SelectionManager.is_open, "esperas_remoto": NetworkClient.remote_waits,
		"paso_driver": _driver_step,
		"ultimo_log": str(main.debug_label.text).left(160) if main.get("debug_label") else "",
	}
	_stalls.append(info)
	print("SIM TRABA: ", info)
	if _stalls.size() >= MAX_STALLS:
		_end("trabada")
		return
	# Intento de destrabar: lo mismo que haría una persona (¿Paso?).
	main._phase_flow._on_paso_pressed()


func _end(reason: String) -> void:
	if _ended:
		return
	_ended = true
	_end_reason = reason


# =============================================================================
# INVARIANTES
# =============================================================================
func _valid_children(container: Node) -> Array:
	if not container:
		return []
	return container.get_children().filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion() \
		and c.get("card_data") != null)


func _real_cards(container: Node) -> Array:
	"""Sin las fichas de Oro Virtual (GoldManagerVisuals._spawn_gold_token): son visuales, no cuentan en
	GameState ni son cartas de nadie."""
	return _valid_children(container).filter(func(c): return not "virtual_gold" in c.card_data.get("keywords", []))


func _violation(tipo: String, detalle: String) -> void:
	"""Se informa si sigue igual en el chequeo siguiente (lo pasajero, a mitad de un movimiento, no)."""
	var key := tipo + "|" + detalle
	_seen_now[key] = true
	if not _prev_seen.has(key):
		return
	if _violations.has(key):
		_violations[key].veces += 1
		return
	_violations[key] = {"tipo": tipo, "detalle": detalle, "turno": GameManager.current_turn, "veces": 1,
		"fase": Constants.PHASE_NAMES.get(GameManager.current_phase, "?"), "estado": "J0 %s · J1 %s" % [_where(0), _where(1)],
		"paso_driver": _driver_step}
	print("SIM INVARIANTE [%s] %s (turno %d)" % [tipo, detalle, GameManager.current_turn])


var _seen_now: Dictionary = {}


func _check_invariants() -> void:
	_seen_now = {}
	for p in 2:
		var pre := "player_" if p == 0 else "opponent_"
		var gold: int = _real_cards(main.get(pre + "gold")).size()
		var paid: int = _real_cards(main.get(pre + "oro_pagado")).size()
		if GameState.get_oro_reserva(p) != gold:
			_violation("oro_reserva", "J%d: contador %d, cartas %d" % [p, GameState.get_oro_reserva(p), gold])
		if GameState.get_oro_pagado(p) != paid:
			_violation("oro_pagado", "J%d: contador %d, cartas %d" % [p, GameState.get_oro_pagado(p), paid])
		if GameState.get_oro_reserva(p) < 0 or GameState.get_oro_pagado(p) < 0:
			_violation("negativo", "J%d: Oro negativo" % p)
		var deck_main: int = (main.player_deck if p == 0 else main.opponent_deck).size()
		if deck_main != CardManager.get_deck(p).size():
			_violation("castillo", "J%d: Main %d, CardManager %d" % [p, deck_main, CardManager.get_deck(p).size()])
	for prop in CONTAINERS:
		var zone: int = CONTAINERS[prop][1]
		for c in _valid_children(main.get(prop)):
			if c.get("current_zone") != null and int(c.current_zone) != zone:
				_violation("zona", "%s en %s dice zona %s" % [str(c.get("card_name")), prop,
					Constants.ZONE_NAMES.get(int(c.current_zone), str(c.current_zone))])
	var totals := _owner_totals()
	for p in 2:
		if int(totals[p]) != int(_initial_totals.get(p, -1)):
			_violation("conteo", "J%d: %d cartas en total (empezó con %d)%s" % [p, int(totals[p]),
				int(_initial_totals.get(p, 0)), _foreign_cards()])


## Cartas en juego del lado del otro jugador (control cambiado, Armas en un Aliado rival): la primera pista
## cuando el conteo por dueño no cierra.
func _foreign_cards() -> String:
	var out: Array = []
	for prop in CONTAINERS:
		var side: int = int(CONTAINERS[prop][0])
		for c in _real_cards(main.get(prop)):
			var cards: Array = [c]
			if c.get("equipped_weapons") is Array:
				cards.append_array(c.equipped_weapons.filter(func(w): return is_instance_valid(w)))
			for x in cards:
				var o = x.get("owner_id")
				if o == null or int(o) != side:
					out.append("%s (dueño %s) en %s" % [str(x.get("card_name")), str(o), prop])
	return "" if out.is_empty() else " · ajenas: " + ", ".join(out)
	_prev_seen = _seen_now


func _owner_totals() -> Dictionary:
	var out := {0: 0, 1: 0}
	for p in 2:
		out[p] += CardManager.get_deck(p).size() + CardManager.get_cemetery(p).size() + CardManager.get_exile(p).size()
	for c in main.player_hand.cards:
		if is_instance_valid(c):
			out[0] += 1
	for c in main._opponent_fan.get_cards():
		if is_instance_valid(c):
			out[1] += 1
	for prop in CONTAINERS:
		for c in _real_cards(main.get(prop)):
			var o: int = int(c.get("owner_id")) if c.get("owner_id") != null else int(CONTAINERS[prop][0])
			out[clampi(o, 0, 1)] += 1
			var w = c.get("equipped_weapons")
			if w is Array:
				for weapon in w:
					if is_instance_valid(weapon) and weapon.get_parent() != main.get(prop):
						var wo: int = int(weapon.get("owner_id")) if weapon.get("owner_id") != null else o
						out[clampi(wo, 0, 1)] += 1
	return out


func _where(p: int) -> String:
	var hand: int = main.player_hand.cards.size() if p == 0 else main._opponent_fan.get_cards().size()
	return "mano %d, castillo %d, cementerio %d, destierro %d" % [hand, CardManager.get_deck(p).size(),
		CardManager.get_cemetery(p).size(), CardManager.get_exile(p).size()]


# =============================================================================
# DESINCRONIZACIÓN: estado que el Remoto debería ver ("propio" = jugador 1 del Anfitrión)
# =============================================================================
func _host_snapshot() -> Dictionary:
	var snap := {}
	var names := {}
	for prop in CONTAINERS:
		var info: Array = CONTAINERS[prop]
		var rel := "propio" if info[0] == 1 else "rival"
		var ids: Array = []
		for c in _valid_children(main.get(prop)):
			ids.append(str(c.get_instance_id()))
			names[str(c.get_instance_id())] = str(c.get("card_name"))
			if c.get("card_type") == Constants.CardType.ALIADO and c.has_method("get_strength"):
				snap["fuerza." + str(c.get_instance_id())] = int(c.get_strength())
		ids.sort()
		snap[rel + "." + ZONE_KEYS[info[1]]] = ids
	var hand: Array = []
	for c in main._opponent_fan.get_cards():
		if is_instance_valid(c):
			hand.append(str(c.get_instance_id()))
	hand.sort()
	snap["propio.mano"] = hand
	snap["propio.castillo"] = main.opponent_deck.size()
	snap["rival.castillo"] = main.player_deck.size()
	snap["propio.cementerio"] = CardManager.get_cemetery_count(1)
	snap["rival.cementerio"] = CardManager.get_cemetery_count(0)
	snap["propio.destierro"] = CardManager.get_exile_count(1)
	snap["rival.destierro"] = CardManager.get_exile_count(0)
	snap["rival.mano_n"] = main.player_hand.cards.size()
	snap["_nombres"] = names
	return snap


func _send_check() -> void:
	if _ended or _busy():
		return
	for i in 3:
		await get_tree().process_frame
	if _ended or _busy():
		return
	_check_seq += 1
	_checks_sent += 1
	NetworkClient.send_message({"op": "sim_check", "seq": _check_seq, "turn": GameManager.current_turn,
		"phase": Constants.PHASE_NAMES.get(GameManager.current_phase, "?"), "snap": _host_snapshot()})


func _remote_snapshot() -> Dictionary:
	var mirror = main._remote_mirror
	var id_of := {}
	for id in mirror._card_nodes:
		var n = mirror._card_nodes[id]
		if is_instance_valid(n):
			id_of[n] = str(id)
	var snap := {}
	for prop in CONTAINERS:
		var info: Array = CONTAINERS[prop]
		var rel := "propio" if info[0] == 0 else "rival"
		var ids: Array = []
		for c in _valid_children(main.get(prop)):
			var id: String = id_of.get(c, "?" + str(c.get("card_name")))
			ids.append(id)
			if c.get("card_type") == Constants.CardType.ALIADO and c.has_method("get_strength"):
				snap["fuerza." + id] = int(c.get_strength())
		ids.sort()
		snap[rel + "." + ZONE_KEYS[info[1]]] = ids
	var hand: Array = []
	for id in mirror._hand_card_nodes:
		var n = mirror._hand_card_nodes[id]
		if is_instance_valid(n) and n in main.player_hand.cards:
			hand.append(str(id))
	hand.sort()
	snap["propio.mano"] = hand
	snap["propio.castillo"] = _label_int("player_castillo_count")
	snap["rival.castillo"] = _label_int("opponent_castillo_count")
	snap["propio.cementerio"] = _label_int("player_cementerio_count")
	snap["rival.cementerio"] = _label_int("opponent_cementerio_count")
	snap["propio.destierro"] = _label_int("player_destierro_count")
	snap["rival.destierro"] = _label_int("opponent_destierro_count")
	snap["rival.mano_n"] = main._opponent_fan.get_cards().size() if main.get("_opponent_fan") else -1
	return snap


func _label_int(prop: String) -> int:
	var l = main.get(prop)
	if not l:
		return -1
	var t := str(l.text).strip_edges()
	return int(t) if t.is_valid_int() else -1


func _on_remote_message(data: Dictionary) -> void:
	match str(data.get("op", "")):
		"sim_check":
			# Sin esperar: los mensajes siguientes pueden llegar en el mismo frame y cambiarían el estado.
			_checks_sent += 1
			_compare(data)
		"sim_end":
			result["anfitrion"] = data.get("result", {})
			_end("fin (aviso del Anfitrión)")


func _compare(data: Dictionary) -> void:
	var host: Dictionary = data.get("snap", {})
	var mine := _remote_snapshot()
	var keys := {}
	for k in host:
		keys[k] = true
	for k in mine:
		keys[k] = true
	var ok := true
	var diff_now := {}
	var names: Dictionary = host.get("_nombres", {})
	for id in main._remote_mirror._card_nodes:
		var n = main._remote_mirror._card_nodes[id]
		if is_instance_valid(n) and not names.has(id):
			names[id] = str(n.get("card_name"))
	for k in keys:
		if str(k).begins_with("_"):
			continue
		var hv = _norm(host.get(k, null))
		var mv = _norm(mine.get(k, null))
		if str(hv) == str(mv):
			continue
		ok = false
		var field: String = "fuerza" if str(k).begins_with("fuerza.") else k
		var key: String = field + "|" + (str(k) if field == "fuerza" else "")
		# Un checkpoint que llega justo antes del próximo envío del Anfitrión (zone_counts va cada 0.25 s) no es
		# desincronización: solo cuenta si sigue distinto en el checkpoint siguiente.
		diff_now[key] = true
		if not _prev_diff.has(key):
			continue
		if _desyncs.has(key):
			_desyncs[key].veces += 1
			continue
		var name := ""
		if field == "fuerza":
			name = str(names.get(str(k).trim_prefix("fuerza."), "?"))
		elif hv is Array and mv is Array:
			# Qué sobra o falta en el Remoto, con nombre.
			var extra: Array = mv.filter(func(x): return not x in hv).map(func(x): return "+" + str(names.get(x, x)))
			var missing: Array = hv.filter(func(x): return not x in mv).map(func(x): return "-" + str(names.get(x, x)))
			name = ", ".join(extra + missing)
		_desyncs[key] = {"campo": field, "carta": name, "anfitrion": str(hv).left(200), "remoto": str(mv).left(200),
			"turno": int(data.get("turn", 0)), "fase": str(data.get("phase", "")), "veces": 1}
		print("SIM DESYNC [%s] %s anfitrión=%s remoto=%s" % [field, name, str(hv).left(80), str(mv).left(80)])
	_prev_diff = diff_now
	if ok:
		_checks_ok += 1


func _norm(v):
	"""JSON trae los enteros como float."""
	if v is float and v == floorf(v):
		return int(v)
	return v


func _remote_wait_end() -> void:
	while not _ended:
		await get_tree().process_frame
		if Time.get_ticks_msec() - _start_ms > MAX_REAL_MS:
			_end("tiempo real agotado")
		if NetworkClient.room_code == "" and not _ended:
			_end("sala cerrada")
	_finish(_end_reason)


# =============================================================================
# SALIDA
# =============================================================================
func _finish(reason: String) -> void:
	Engine.time_scale = 1.0
	result["fin"] = reason
	result["ganador"] = _winner
	result["turnos"] = GameManager.current_turn
	result["segundos_reales"] = (Time.get_ticks_msec() - _start_ms) / 1000.0
	result["invariantes"] = _violations.values()
	result["trabas"] = _stalls
	if mode != "offline":
		result["checks"] = _checks_sent
		result["checks_ok"] = _checks_ok
		result["desync"] = _desyncs.values()
	if mode == "host":
		NetworkClient.send_message({"op": "sim_end", "result": {"fin": reason, "ganador": _winner}})
		await get_tree().create_timer(1.5, true, false, true).timeout
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	print("SIM FIN: %s ganador=%d turnos=%d" % [reason, _winner, GameManager.current_turn])
	get_tree().quit(0)
