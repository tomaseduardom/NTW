extends RefCounted
## PhaseStartWindow — "Puedes jugarlo al comienzo de cualquier Fase" y "en la Fase Final":
## - Al comienzo de cada fase (Agrupación, Vigilia, Ataque, Bloqueo, Guerra de Talismanes,
## Asignación de Daño, Fase Final), en los dos turnos, se abre una ventana SOLO si algún jugador
## tiene en la mano una carta con ese permiso y la puede pagar. Si no, la fase sigue igual.
## - Empieza el jugador activo; cada uno juega una carta habilitada o pasa. Tras una carta (con su
## propia Ventana de Respuesta), la palabra vuelve al otro. Termina cuando los dos pasan seguidos. 5
## s por turno de palabra, para el Anfitrión y el Remoto.
## - Después la fase sigue con lo que haya en juego (p.ej. un atacante Barajado ya no hace daño).
## Textos:
## "al comienzo de cualquier Fase" / "cualquier Fase o Paso" → todas.
## "al comienzo de cualquier Fase Final" → Fase Final de los dos.
## "en la Fase Final oponente" → solo la del rival.
## "en tu Vigilia o Fase Final" → solo tu Fase Final.
## "en la Fase Final" (sin "tu") → la de los dos.
## minamoto no yoritomo: "Puedes jugar este y tus demás Aliados al comienzo de cualquier Fase
## Final".
## Se usa con preload / load.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const TIMEOUT := 5.0

static var _running: bool = false
static var _phase: int = -1


static func reset_match() -> void:
	"""MatchReset: una ventana de comienzo de fase que quedó abierta no bloquea la partida siguiente."""
	_running = false
	_phase = -1


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func is_running() -> bool:
	return _running


static func _text(card) -> String:
	if card is Dictionary:
		return str(card.get("habilidad", "")).to_lower().replace("\n", " ")
	return str(card.get("card_ability")).to_lower().replace("\n", " ")


const ONLY_AT_PHASES := {"agrupacion": Constants.Phase.AGRUPACION, "vigilia": Constants.Phase.VIGILIA,
	"ataque": Constants.Phase.ATAQUE, "bloqueo": Constants.Phase.BLOQUEO,
	"guerra de talismanes": Constants.Phase.GUERRA_TALISMANES, "fase final": Constants.Phase.FINAL}


## "Solo puedes jugar este Talismán al comienzo de la Vigilia" (eco de la muerte), "Solo puedes jugarlo al
## comienzo del Ataque" (ta kona): solo en la ventana de comienzo de esa fase. {"phase", "own"} o {} si el texto no
## lo limita. El Ataque es siempre el del jugador activo: cuenta como "tu".
static func only_at(text: String) -> Dictionary:
	var t: String = load("res://scripts/core/cards/CardText.gd").fold(text)
	var m := RegEx.create_from_string("solo puedes jugar(?:lo|la| este talisman| esta carta) al comienzo (?<who>de la |del |de tu )"
		+ "(?<p>agrupacion|vigilia|ataque|bloqueo|guerra de talismanes|fase final)").search(t)
	if m == null:
		return {}
	var phase: int = ONLY_AT_PHASES[m.get_string("p")]
	return {"phase": phase, "own": m.get_string("who") == "de tu " or phase == Constants.Phase.ATAQUE}


## ¿El texto de la carta permite jugarla al comienzo de 'phase'?
static func text_allows(text: String, phase: int, is_own_turn: bool) -> bool:
	var only := only_at(text)
	if not only.is_empty():
		return phase == int(only.phase) and (is_own_turn or not only.own)
	var is_final: bool = phase == Constants.Phase.FINAL
	if "al comienzo de cualquier fase final" in text:
		return is_final
	if "al comienzo de cualquier fase" in text or "cualquier fase o paso" in text:
		return true
	if not is_final:
		return false
	if "en la fase final oponente" in text or "en la fase final de tu oponente" in text:
		return not is_own_turn
	if "en tu vigilia o fase final" in text or "puedes jugarlo en tu fase final" in text \
			or "puedes jugarla en tu fase final" in text:
		return is_own_turn
	return "puedes jugarlo en la fase final" in text or "puedes jugarla en la fase final" in text


## minamoto no yoritomo en juego: tus Aliados al comienzo de cualquier Fase Final.
static func _minamoto_allows(card: Node, pid: int, phase: int) -> bool:
	if phase != Constants.Phase.FINAL or card.get("card_type") != Constants.CardType.ALIADO:
		return false
	var main := _main_node()
	if not main:
		return false
	for container in PlayerSideScript.line_containers(main, pid):
		for c in container.get_children():
			if is_instance_valid(c) and not KeywordManager.is_silenced(c) \
					and "puedes jugar este y tus demás aliados al comienzo de cualquier fase final" in _text(c):
				return true
	return false


static func card_permitted(card: Node, pid: int, phase: int) -> bool:
	if not is_instance_valid(card) or card.get("card_type") == Constants.CardType.ORO:
		return false
	var own: bool = GameManager.active_player_id == pid
	return text_allows(_text(card), phase, own) or _minamoto_allows(card, pid, phase)


## Cartas de la mano de 'pid' que puede jugar AHORA en esta ventana.
static func playable_cards(pid: int, phase: int = -1) -> Array:
	var main := _main_node()
	if not main or not main.get("_gold_manager"):
		return []
	if phase < 0:
		phase = GameManager.current_phase
	var gm = main._gold_manager
	var out: Array = []
	for c in PlayerSideScript.hand_cards(main, pid):
		if not card_permitted(c, pid, phase):
			continue
		if gm._no_more_cards_violation(c) or gm._card_play_locked(c) or gm._errante_violation(c) or gm._play_limit_violation(c):
			continue
		if c.get("card_type") == Constants.CardType.ARMA and not gm._player_has_ally_in_play():
			continue
		var cost: int = PaymentManager.calcular_coste_real(c)
		if gm.puede_pagar(cost, int(c.card_type), str(c.get("card_raza")), int(c.get("card_cost")), pid):
			out.append(c)
	return out


## Para los gateos de jugar carta (GoldManager, doble click, arrastre).
static func allows_now(card: Node, pid: int) -> bool:
	return _running and PriorityManager.priority_window_active \
		and PriorityManager.current_priority_context == PriorityManager.PriorityContext.PHASE_START \
		and PriorityManager.current_priority_player == pid and card_permitted(card, pid, _phase)


# =============================================================================
# LA VENTANA
# =============================================================================
static func run(phase: int) -> void:
	if _running or not GameManager.is_game_active:
		return
	if playable_cards(0, phase).is_empty() and playable_cards(1, phase).is_empty():
		return
	var main := _main_node()
	_running = true
	_phase = phase
	UIManager.announce_phase(phase)
	var start_player: int = GameManager.active_player_id
	var state := {"both_passed": false}
	var on_both := func() -> void:
		if PriorityManager.current_priority_context in [PriorityManager.PriorityContext.PHASE_START,
				PriorityManager.PriorityContext.NONE]:
			state.both_passed = true
	PriorityManager.both_players_passed.connect(on_both)
	var tree := Engine.get_main_loop() as SceneTree
	for _round in 20:
		if not GameManager.is_game_active or GameManager.current_phase != phase:
			break
		if playable_cards(0, phase).is_empty() and playable_cards(1, phase).is_empty():
			break
		state.both_passed = false
		PriorityManager.start_priority_window(PriorityManager.PriorityContext.PHASE_START, start_player)
		if main:
			main._update_debug("Comienzo de %s: puedes jugar una carta que lo permita (¿Paso? para seguir)" %
				Constants.PHASE_NAMES.get(phase, ""))
		# Espera: ambos pasan, o alguien juega (la ventana cambia de contexto).
		var actor: int = -1
		while true:
			await tree.process_frame
			if state.both_passed or not GameManager.is_game_active:
				break
			if not PriorityManager.priority_window_active \
					or PriorityManager.current_priority_context != PriorityManager.PriorityContext.PHASE_START:
				actor = PriorityManager.current_stack_controller if PriorityManager.current_stack_controller >= 0 \
					else PriorityManager.current_priority_player
				break
		if state.both_passed or actor < 0:
			break
		# Alguien jugó: esperar a que termine de resolverse todo.
		for _i in 6000:
			await tree.create_timer(0.1).timeout
			if not GameManager.is_game_active:
				break
			if not ActionPipeline.is_stack_processing() and not TriggerSystem.awaiting_response \
					and not TriggerSystem.is_resolving and not PriorityManager.priority_window_active \
					and not SelectionManager.is_open:
				break
		start_player = 1 - actor
	if PriorityManager.both_players_passed.is_connected(on_both):
		PriorityManager.both_players_passed.disconnect(on_both)
	if PriorityManager.priority_window_active \
			and PriorityManager.current_priority_context == PriorityManager.PriorityContext.PHASE_START:
		PriorityManager.force_close()
	_running = false
	_phase = -1


## Quién decide en la ventana (PriorityManager.priority_changed): el bot juega
## una carta si puede, si no pasa; el Anfitrión tiene 5 s.
static func on_priority(pid: int) -> void:
	if not _running or PriorityManager.current_priority_context != PriorityManager.PriorityContext.PHASE_START:
		return
	var main := _main_node()
	var generation: int = PriorityManager._window_generation
	var tree := Engine.get_main_loop() as SceneTree
	if PlayerSideScript.is_bot(pid):
		await tree.create_timer(0.3).timeout
		if PriorityManager._window_generation != generation or PriorityManager.current_priority_player != pid:
			return
		var cards: Array = playable_cards(pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
		if not cards.is_empty() and main and main.get("_easy_bot"):
			await main._easy_bot._play_ally(cards[0])
			# Si jugar no abrió ninguna Ventana de Respuesta, la palabra pasa
			# igual al otro jugador.
			if _running and PriorityManager.priority_window_active \
					and PriorityManager.current_priority_context == PriorityManager.PriorityContext.PHASE_START \
					and PriorityManager.current_priority_player == pid:
				PriorityManager.start_priority_window(PriorityManager.PriorityContext.PHASE_START, 1 - pid)
			return
		PriorityManager.pass_priority()
		return
	if pid != 0:
		return  # el Remoto: RemotePlayerController.on_priority_received()
	if playable_cards(0).is_empty():
		await tree.create_timer(0.2).timeout
		if PriorityManager._window_generation == generation and PriorityManager.current_priority_player == 0 \
				and PriorityManager.current_priority_context == PriorityManager.PriorityContext.PHASE_START:
			PriorityManager.pass_priority()
		return
	var waited := 0.0
	while waited < TIMEOUT:
		await tree.create_timer(0.1).timeout
		waited += 0.1
		if PriorityManager._window_generation != generation or PriorityManager.current_priority_player != 0 \
				or PriorityManager.current_priority_context != PriorityManager.PriorityContext.PHASE_START:
			return
		# Eligiendo un objetivo o con un diálogo abierto: no corre el reloj.
		if (main and main._card_interaction and main._card_interaction.is_selecting_target) or SelectionManager.is_open:
			waited = 0.0
	if PriorityManager._window_generation == generation and PriorityManager.current_priority_player == 0 \
			and PriorityManager.current_priority_context == PriorityManager.PriorityContext.PHASE_START:
		PriorityManager.pass_priority()
