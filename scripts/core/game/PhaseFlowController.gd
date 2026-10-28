extends Node
class_name PhaseFlowController
## PhaseFlowController — Gestiona el ciclo de fases DAR, prioridad y flujo de turno.
## Se instancia como hijo de Main en _ready().

var _main: Node = null
var _last_state_machine_phase: int = -1


func setup(main: Node) -> void:
	_main = main

	# BattleManager
	if not BattleManager.damage_to_castle.is_connected(_on_battle_damage_to_castle):
		BattleManager.damage_to_castle.connect(_on_battle_damage_to_castle)
	if not BattleManager.player_defeated.is_connected(_on_battle_player_defeated):
		BattleManager.player_defeated.connect(_on_battle_player_defeated)
	if not BattleManager.combat_finished.is_connected(_on_battle_combat_finished):
		BattleManager.combat_finished.connect(_on_battle_combat_finished)

	# PriorityManager
	if not PriorityManager.both_players_passed.is_connected(_on_priority_both_passed_main):
		PriorityManager.both_players_passed.connect(_on_priority_both_passed_main)
	if not PriorityManager.priority_changed.is_connected(_on_priority_changed_bot_autopass):
		PriorityManager.priority_changed.connect(_on_priority_changed_bot_autopass)
	if not PriorityManager.priority_changed.is_connected(_on_priority_changed_glow):
		PriorityManager.priority_changed.connect(_on_priority_changed_glow)
	if not PriorityManager.priority_window_closed.is_connected(_on_priority_window_closed_glow):
		PriorityManager.priority_window_closed.connect(_on_priority_window_closed_glow)

	# ActionPipeline
	if not ActionPipeline.stack_empty.is_connected(_on_stack_resolved):
		ActionPipeline.stack_empty.connect(_on_stack_resolved)

	# GameManager — fase y turno
	if not GameManager.phase_changed.is_connected(_on_phase_changed_relay):
		GameManager.phase_changed.connect(_on_phase_changed_relay)
	if not GameManager.turn_started.is_connected(_on_turn_started):
		GameManager.turn_started.connect(_on_turn_started)


# =============================================================================
# MÁQUINA DE ESTADOS DE FASES
# Punto de entrada unificado para cualquier cambio de fase,
# ya venga de GameManager o de TurnManager.
# =============================================================================
func _on_phase_changed_relay(new_phase: Constants.Phase) -> void:
	_on_phase_state_machine(new_phase)


func _on_phase_state_machine(new_phase: Constants.Phase) -> void:
	"""Orquesta la respuesta a cada cambio de fase (DAR Sección 5).

	Ciclo completo:
	  AGRUPACION → VIGILIA → ATAQUE → BLOQUEO → GUERRA_TALISMANES
	              → ASIGNACION_DANIO → FINAL → (siguiente turno)

	Turno 1: GameManager salta AGRUPACION y emite directamente VIGILIA.
	"""
	if int(new_phase) == _last_state_machine_phase:
		return
	_last_state_machine_phase = int(new_phase)

	GameManager.current_phase = new_phase
	UIManager.announce_phase(new_phase)
	_main._update_buttons_for_phase(new_phase)
	_main._game_hud.update_paso_button_state()

	print("[PhaseFlow] === FASE: %s (jugador activo: %d) ===" % [Constants.PHASE_NAMES[new_phase], GameManager.active_player_id])

	match new_phase:

		Constants.Phase.AGRUPACION:
			GameManager.agrupacion_busy = true
			_main._game_hud.show_phase_announcement("AGRUPACIÓN")
			# Línea de Ataque → Línea de Defensa (DAR): un Aliado que atacó en
			# el turno anterior de este jugador se queda "comprometido" en
			# Ataque hasta esta Agrupación — igual que el Oro Pagado. Se lee
			# directo de los hijos del contenedor (no de GameManager.attackers,
			# que _start_batalla() ya vació al llegar el Ataque del rival).
			var atk_line: HBoxContainer = _main.player_linea_ataque if GameManager.active_player_id == 0 else _main.opponent_linea_ataque
			if _main._card_interaction and atk_line:
				# vorpal: "no pueda ser agrupado ... hasta tu próximo turno" (meta "no_regroup_turn").
				await _main._card_interaction.unmark_attackers(atk_line.get_children().filter(func(c): return is_instance_valid(c) \
					and int(c.get_meta("no_regroup_turn", -1)) != GameManager.turn_serial))
			if GameManager.active_player_id == 0:
				await _main._gold_manager._reset_gold()
			else:
				await _main._easy_bot.reset_gold()
			# "En tu Agrupación" (p.ej. Espada del Juicio): mismo patrón que resolve_turn_end_triggers().
			await TriggerSystem.resolve_agrupacion_triggers(GameManager.active_player_id)
			GameManager.agrupacion_busy = false  # recién ahora GameManager pasa a la Vigilia

		Constants.Phase.VIGILIA:
			_main._game_hud.show_phase_announcement("VIGILIA")
			TurnManager._reset_oro_tracking()
			# "En tu Vigilia" (p.ej. Mariano Osorio): mismo patrón que Agrupación/Fase Final.
			await TriggerSystem.resolve_vigilia_triggers(GameManager.active_player_id)
			if _main._card_inspector:
				_main._card_inspector.refresh_activatable_glows()
			if GameManager.active_player_id == 1:
				await _main._easy_bot.take_vigilia_actions()

		Constants.Phase.ATAQUE:
			_main._game_hud.show_phase_announcement("BATALLA MITOLÓGICA")
			# "Al comienzo del Ataque" (p.ej. almirante akari) se resuelve al confirmar atacantes
			# (GameManager.confirm_attackers()): sin ataque, no hay. Sin ningún Aliado que pueda atacar,
			# directo a la Fase Final.
			# ambrosio ohiggins (desde la mano o el Cementerio): antes de declarar atacantes.
			if _active_player_can_attack():
				await load("res://scripts/core/effects/mechanics/TurnStartPatterns.gd").ambrosio_on_ataque_start()
			if GameManager.current_phase == Constants.Phase.ATAQUE and not _active_player_can_attack():
				_main._update_debug("Ningún Aliado puede atacar — pasas a la Fase Final")
				await get_tree().create_timer(0.4).timeout
				if GameManager.current_phase == Constants.Phase.ATAQUE:
					await GameManager.confirm_attackers()
				return
			if GameManager.active_player_id == 1:
				await _main._easy_bot.take_ataque_actions()

		Constants.Phase.BLOQUEO:
			_main._game_hud.show_phase_announcement("BLOQUEO")

		Constants.Phase.GUERRA_TALISMANES:
			_main._game_hud.show_phase_announcement("GUERRA DE TALISMANES")

		Constants.Phase.ASIGNACION_DANIO:
			_main._game_hud.show_phase_announcement("ASIGNACIÓN DE DAÑO")

		Constants.Phase.FINAL:
			_main._game_hud.show_phase_announcement("FASE FINAL")
			if GameManager.active_player_id == 1:
				await _resolve_fase_final(1)


func _active_player_can_attack() -> bool:
	"""¿Tiene el jugador activo al menos un Aliado que pueda declarar ataque?"""
	return TurnManager.player_can_attack(GameManager.active_player_id)


func _on_turn_started(player_id: int, turn_number: int) -> void:
	UIManager.announce_turn(player_id, turn_number)


func _on_priority_changed_bot_autopass(player_id: int) -> void:
	"""El oponente (bot) todavía no sabe usar habilidades ni talismanes para
	responder a nada — por ahora, cada vez que le toca prioridad en CUALQUIER
	ventana activa (Guerra de Talismanes, ventana de respuesta de un trigger,
	etc.), espera un momento (el '¿Algo?' real, aunque nunca conteste que sí)
	y pasa solo. El humano sigue viendo/usando el botón ¿Paso? normalmente
	cuando la prioridad es suya. Cuando exista una IA real, este auto-pase
	se reemplaza por su lógica de decisión."""
	# Comienzo de fase: el bot juega o pasa, el Anfitrión tiene 5 s; el Remoto decide por
	# RemotePlayerController (abajo).
	if PriorityManager.priority_window_active \
			and PriorityManager.current_priority_context == PriorityManager.PriorityContext.PHASE_START \
			and not (player_id == 1 and _main._easy_bot is RemotePlayerController):
		load("res://scripts/core/game/PhaseStartWindow.gd").on_priority(player_id)
		return
	if player_id != 1:
		return
	if not PriorityManager.priority_window_active:
		return
	# Contra un Remoto real, el jugador 1 no es un bot: decide RemotePlayerController (con auto-pase no
	# alcanzaba a responder).
	if _main._easy_bot is RemotePlayerController:
		_main._easy_bot.on_priority_received()
		return
	# Se captura la generación de esta ventana (PriorityManager._window_generation) antes del await,
	# como en _human_pass_after()/_bot_pass_after().
	var scheduled_for_generation: int = PriorityManager._window_generation
	# 0.2 s: perceptible pero corto, para que las cadenas de cartas entrando seguidas no se acumulen.
	await get_tree().create_timer(0.2).timeout
	if PriorityManager._window_generation != scheduled_for_generation:
		return  # la ventana para la que se programó este timer ya no es la actual
	if PriorityManager.priority_window_active and PriorityManager.current_priority_player == 1:
		PriorityManager.pass_priority()
	else:
		if Constants.VERBOSE_DIAG_LOGS:
			print("[DIAG] bot_autopass: tras esperar, ya no aplica — priority_window_active=%s current_priority_player=%d" % [PriorityManager.priority_window_active, PriorityManager.current_priority_player])
		_try_recover_stuck_phase_priority_window()


func _try_recover_stuck_phase_priority_window() -> bool:
	"""Reabre la ventana de prioridad de fase (Guerra de Talismanes/Bloqueo) si quedó pisada: una
	ventana anidada de Paso D (StackStepResolver._execute_step_d(), que abre su propia
	RESPONSE_WINDOW sobre el mismo PriorityManager) a veces no la restaura al cerrar y queda
	priority_window_active = false sin nada que reaccione. Se llama desde el auto-pase del bot y
	desde el botón ¿Paso?. Devuelve true si reabrió una ventana."""
	var phase = GameManager.current_phase
	if GameManager.is_game_active and not PriorityManager.priority_window_active \
			and not ActionPipeline.is_stack_processing() and not TriggerSystem.awaiting_response \
			and phase in [Constants.Phase.GUERRA_TALISMANES, Constants.Phase.BLOQUEO]:
		if Constants.VERBOSE_DIAG_LOGS:
			print("[DIAG] recuperación: reabriendo ventana de prioridad para %s" % Constants.PHASE_NAMES.get(phase, "?"))
		PriorityManager.start_priority_window(
			PriorityManager.PriorityContext.GUERRA_TALISMANES if phase == Constants.Phase.GUERRA_TALISMANES
			else PriorityManager.PriorityContext.BLOCK_DECLARATION
		)
		return true
	return false


func _on_priority_changed_glow(player_id: int) -> void:
	"""Hace brillar el botón ¿Paso? cuando el humano tiene prioridad en
	CUALQUIER ventana activa, no solo después de declarar un atacante.

	Antes _start_paso_glow() solo se llamaba desde CardInteractionModule
	tras declarar un ataque — cuando una carta abría su propia ventana de
	respuesta al entrar en juego (p.ej. Mariano Osorio), el botón ¿Paso?
	seguía visible pero sin ninguna señal de que había algo pendiente. El
	jugador no tenía forma de saber que debía presionarlo para continuar y
	el juego parecía trabado. Si la prioridad pasa al oponente (bot) dentro
	de la misma ventana, el brillo se apaga hasta que vuelva a ser el turno
	del humano de actuar."""
	# La visibilidad del botón depende de quién tiene la prioridad ahora (update_paso_button_state()):
	# se refresca en cada cambio de prioridad dentro de la fase, no solo al cambiar de fase.
	_main._game_hud.update_paso_button_state()
	if player_id == 0:
		_main._game_hud.start_paso_glow()
		# Punto único de auto-pase del humano en RESPONSE_WINDOW, arranque la ventana contigo o te llegue
		# a mitad (priority_changed se emite en ambos casos). La única decisión real aquí es Signo
		# Amarillo (ResponseWindowHandler._offer_signo_amarillo_for_step_d()), que lo suprime con
		# PriorityManager.suppress_human_autopass. Solo RESPONSE_WINDOW: la Guerra de Talismanes y el
		# Bloqueo de fase esperan tu decisión.
		if PriorityManager.current_priority_context == PriorityManager.PriorityContext.RESPONSE_WINDOW \
				and not (_main._easy_bot is RemotePlayerController):
			# Contra el bot local, pase rápido (0.2 s): no tiene sentido esperar 5 s por una decisión del
			# bot. refresh_activatable_glows() igual marca qué carta podría responder (§10.51/§10.52). El
			# Remoto va por la rama de abajo.
			if _main._card_inspector:
				_main._card_inspector.refresh_activatable_glows()
			# Si la ventana es sobre algo del rival y tienes un Talismán de respuesta que puedes pagar, se
			# espera como online (5 s con cuenta regresiva); si no, el pase rápido.
			if PriorityManager.needs_real_decision(0) and _human_has_instant_response_talisman_in_hand():
				_main._game_hud.start_paso_countdown(int(PriorityManager.ONLINE_RESPONSE_TIMEOUT))
				_human_pass_after(PriorityManager.ONLINE_RESPONSE_TIMEOUT, PriorityManager._window_generation)
				return
			# Se captura la generación de esta ventana para que el timer no actúe sobre una ventana nueva si
			# esta ya cerró.
			_human_pass_after(0.2, PriorityManager._window_generation)
		elif _main._easy_bot is RemotePlayerController:
			# Botón de paso simétrico online (PriorityManager.needs_real_decision()): si la ventana no te
			# pide nada (respuesta a TU carta, o eres el atacante en Bloqueo), se pasa sola; en una Ventana
			# de Respuesta real tienes 5 s; Bloqueo y Guerra de Talismanes esperan tu click sin límite.
			var gen: int = PriorityManager._window_generation
			if not PriorityManager.needs_real_decision(0):
				_main._game_hud.stop_paso_glow()
				_human_pass_after(0.2, gen)
			elif PriorityManager.current_priority_context == PriorityManager.PriorityContext.RESPONSE_WINDOW:
				if _main._card_inspector:
					_main._card_inspector.refresh_activatable_glows()
				_main._game_hud.start_paso_countdown(int(PriorityManager.ONLINE_RESPONSE_TIMEOUT))
				_human_pass_after(PriorityManager.ONLINE_RESPONSE_TIMEOUT, gen)
	else:
		_main._game_hud.stop_paso_glow()
		_main._game_hud.stop_paso_countdown()
		if _main._card_inspector:
			_main._card_inspector._clear_all_activatable_glows()


func _on_priority_window_closed_glow() -> void:
	"""Al cerrarse la ventana de prioridad: apaga el brillo del botón ¿Paso? y recalcula su
	visibilidad. Si la última vez se calculó con la prioridad en el bot, el botón quedaba oculto
	aunque siguiera siendo tu Vigilia."""
	_main._game_hud.stop_paso_glow()
	_main._game_hud.stop_paso_countdown()
	_main._game_hud.update_paso_button_state()


# =============================================================================
# CALLBACKS DE COMBATE (BattleManager)
# =============================================================================
func _on_battle_damage_to_castle(player_id: int, total_damage: int, _sources: Array) -> void:
	"""BattleManager calculó y aplicó daño al Castillo — solo feedback visual."""
	var target = "tu Castillo" if player_id == 0 else "Castillo oponente"
	_main._update_debug("%d daño hacia %s" % [total_damage, target])
	_main._zone_manager._update_castillo_counts()


func _on_battle_player_defeated(player_id: int) -> void:
	_main._update_debug("¡Jugador %d derrotado!" % (player_id + 1))


func _on_battle_combat_finished(result: Dictionary) -> void:
	if result.get("game_ended", false):
		return

	# No se desmarca a los atacantes aquí (DAR): un Aliado que atacó queda en Línea de Ataque hasta la
	# Agrupación del próximo turno de su controlador (como el Oro Pagado). Lo hace el caso AGRUPACION
	# de _on_phase_state_machine().
	_main._zone_manager._update_castillo_counts()

	# DAR: tras Asignación de Daño, las habilidades 'cuando inflija daño'/
	# 'si hizo daño' pueden resolverse antes de pasar a Fase Final. Antes
	# nada disparaba este evento — DamageManager.gd lo intentaba pero es
	# código muerto que nadie llama (el daño real lo aplica BattleManager,
	# que no disparaba ningún trigger al terminar).
	await _fire_damage_dealt_triggers(result.get("damage_sources", []))

	# ta kona: "Al final de esta Batalla Mitológica agrupa tus Aliados y ganas una Batalla Mitológica
	# adicional." Los atacantes vuelven a la Línea de Defensa y se vuelve al paso de Ataque.
	var active: int = GameManager.active_player_id
	if RuleState.has_pending("extra_battle", active):
		RuleState.take_pending("extra_battle", active)
		var fought: Array = GameManager.attackers.filter(func(a): return is_instance_valid(a))
		GameManager.attackers.clear()
		GameManager.blockers.clear()
		if _main._card_interaction and _main._card_interaction.has_method("unmark_attackers") and not fought.is_empty():
			await _main._card_interaction.unmark_attackers(fought)
		_main._update_debug("ta kona: tus Aliados se agrupan y ganas una Batalla Mitológica adicional")
		GameManager.advance_to_phase(Constants.Phase.ATAQUE)
		return

	GameManager.advance_to_phase(Constants.Phase.FINAL)


func _fire_damage_dealt_triggers(damage_sources: Array) -> void:
	"""Dispara 'on_damage_dealt' para cada carta que infligió daño al
	Castillo este combate (DAR — 'cuando inflija daño'/'si hizo daño')."""
	for source_info in damage_sources:
		var card = source_info.get("source")
		if not is_instance_valid(card):
			continue
		var controller_id = card.controller_id if card.get("controller_id") != null else 0
		await TriggerSystem._collect_triggers_for_event("on_damage_dealt", {
			"player_id": controller_id, "card": card, "amount": source_info.get("damage", 0)
		})


# =============================================================================
# PASO D — PRIORIDAD Y PILA
# =============================================================================
func _on_priority_both_passed_main() -> void:
	"""Ambos jugadores pasaron con la pila vacía: avanza la fase según contexto (DAR 5.C3).
	Guardia: si TriggerSystem sigue esperando una respuesta (awaiting_response), la ventana es del
	trigger, no un fin de fase. Si no, resolver un "cuando entra en juego" en Vigilia saltaba a
	Fase Final."""
	# La ventana de comienzo de fase no termina la fase: la maneja PhaseStartWindow.run().
	if load("res://scripts/core/game/PhaseStartWindow.gd").is_running():
		return
	if TriggerSystem.awaiting_response:
		if Constants.VERBOSE_DIAG_LOGS:
			print("[DIAG] _on_priority_both_passed_main: BLOQUEADO por awaiting_response=true (fase=%s, is_collecting=%s, is_resolving=%s)" % [
				Constants.PHASE_NAMES.get(GameManager.current_phase, "?"), TriggerSystem.is_collecting, TriggerSystem.is_resolving
			])
		return

	var phase = GameManager.current_phase
	# §64: en la Guerra, ambos pasando la Ventana de Respuesta de un Talismán
	# o una habilidad solo deja resolver esa acción — la Guerra termina
	# cuando ambos pasan en la ventana de la propia Guerra.
	if phase == Constants.Phase.GUERRA_TALISMANES \
			and PriorityManager.current_priority_context != PriorityManager.PriorityContext.GUERRA_TALISMANES:
		return
	match phase:
		Constants.Phase.ATAQUE:
			_main._game_hud.stop_paso_glow()
			_main._update_debug("Paso D confirmado — pasando a Bloqueo")
			await GameManager.confirm_attackers()

		Constants.Phase.GUERRA_TALISMANES:
			_main._update_debug("Paso D completado — calculando daño de combate")
			# DAR 5.C4: la Guerra de Talismanes termina en el paso de
			# Asignación de Daño, no directo en el cálculo — antes
			# GameManager nunca fijaba esta fase (no se disparaba su título
			# ni daba pie a que triggers 'cuando inflija daño' resolvieran
			# antes de Fase Final).
			GameManager.advance_to_phase(Constants.Phase.ASIGNACION_DANIO)
			await BattleManager.calculate_combat_damage()

		Constants.Phase.BLOQUEO:
			_main._update_debug("Bloqueadores confirmados → GT")
			# Bloqueo: GameManager.confirm_blockers_and_collect_triggers() recolecta los "cuando bloquee"
			# (libro de thoth) antes de avanzar, como ATAQUE espera confirm_attackers().
			await GameManager.confirm_blockers_and_collect_triggers()

		# Sin caso VIGILIA a propósito: este handler reacciona a cualquier ventana que se cierre con ambos
		# pasados (también las anidadas de un trigger o la de _on_stack_resolved()), y saltaba la batalla
		# sin declarar atacantes. Vigilia termina con el botón "Atacar" (_on_paso_pressed() →
		# GameManager.proceed_to_battle()).
		_:
			_main._update_debug("Ambos pasaron en %s" % Constants.PHASE_NAMES.get(phase, "?"))


func _on_stack_resolved() -> void:
	"""La pila (ActionPipeline) quedó vacía: abrir una ventana de prioridad si no hay una activa.
	start_priority_window() emite priority_changed, que _on_priority_changed_glow() ya escucha para
	mostrar el botón ¿Paso?/Atacar cuando le toca al humano."""
	if not PriorityManager.priority_window_active:
		PriorityManager.start_priority_window(
			PriorityManager.PriorityContext.RESPONSE_WINDOW,
			GameManager.active_player_id
		)
		# Si arranca contigo (jugador 0), _on_priority_changed_glow() hace el auto-pase: esta ventana no
		# tiene un objeto puntual que cancelar (a diferencia del Paso D, ver ResponseWindowHandler), así
		# que no hay nada que decidir.


func _human_has_instant_response_talisman_in_hand() -> bool:
	"""¿Hay en tu mano un Talismán de respuesta instantánea (Red de Plata, Sacrificio Solar...;
	GoldManagerRestrictions._is_response_only_talisman(), §10.50) que puedas pagar ahora? Contra el
	bot, decide si la ventana espera 5 s o pasa rápido (_on_priority_changed_glow())."""
	if not _main.player_hand or not _main._gold_manager:
		return false
	for card in _main.player_hand.cards:
		if not is_instance_valid(card):
			continue
		if card.get("card_type") != Constants.CardType.TALISMAN:
			continue
		if not _main._gold_manager._is_response_only_talisman(card):
			continue
		var coste_real = PaymentManager.calcular_coste_real(card)
		if _main._gold_manager.puede_pagar(coste_real):
			return true
	return false


func _human_pass_after(delay: float, scheduled_for_generation: int) -> void:
	await get_tree().create_timer(delay).timeout
	if PriorityManager.suppress_human_autopass:
		# Hay una decisión real en curso (Signo Amarillo, elegir un objetivo).
		# Con un objeto en la pila al que responder, no se pasa por abajo.
		if PriorityManager.current_stack_controller >= 0:
			return
		# Sin nada a qué responder, si estás eligiendo (p.ej. la carta del Cementerio de quimera voragh),
		# se espera a que termine la elección y se pasa igual; si no, la ventana vacía de
		# _on_stack_resolved() quedaba abierta bloqueando la siguiente carta.
		while PriorityManager.suppress_human_autopass:
			if PriorityManager._window_generation != scheduled_for_generation or not PriorityManager.priority_window_active:
				return
			await get_tree().create_timer(0.1).timeout
	# Si la ventana para la que se programó este timer ya cerró y se abrió otra (p.ej. Guerra de
	# Talismanes), _window_generation cambió: el timer viejo no toca la ventana nueva.
	if PriorityManager._window_generation != scheduled_for_generation:
		return
	# Plazo largo (5 s online): si al vencer estás eligiendo el objetivo de tu respuesta, no se te pasa
	# por abajo.
	if delay > 1.0 and _main._card_interaction and _main._card_interaction.is_selecting_target:
		return
	if PriorityManager.priority_window_active and PriorityManager.current_priority_player == 0:
		PriorityManager.pass_priority()


# =============================================================================
# BOTÓN ¿PASO?
# =============================================================================
func _on_paso_pressed() -> void:
	"""El jugador presiona ¿Paso? — pasa prioridad o avanza fase."""
	# Con el selector de zonas abierto, el botón confirma la selección (en las dos pantallas; el Remoto
	# también lo corre localmente).
	if _main._zone_browse_picker and _main._zone_browse_picker.is_active():
		_main._zone_browse_picker.on_paso_pressed()
		return
	# En el cliente Remoto no hay GameManager propio: el botón (y el atajo P) manda la decisión al
	# Anfitrión por red.
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		if _main._remote_mirror:
			_main._remote_mirror.on_paso_pressed()
		return
	# Con una selección de objetivo pendiente (is_selecting_target) no se puede avanzar: el
	# await_target() esperaría para siempre y TriggerSystem.awaiting_response/is_resolving quedarían
	# trabados, bloqueando el fin de cualquier fase. Hay que elegir (o cancelar con ESC, si se
	# permite).
	if _main._card_interaction and _main._card_interaction.is_selecting_target:
		_main._update_debug("Resuelve la selección de objetivo pendiente antes de pasar (N para no hacerlo si es opcional)")
		return

	var phase = GameManager.current_phase

	if PriorityManager.priority_window_active:
		_main._update_debug("Paso: pasando prioridad en %s" % Constants.PHASE_NAMES.get(phase, "?"))
		PriorityManager.pass_priority()
		return

	match phase:
		Constants.Phase.VIGILIA:
			# En Vigilia el botón dice "Atacar": termina Vigilia y empieza la Batalla Mitológica. Los
			# atacantes se declaran en la fase de Ataque; si nadie ataca, un segundo ¿Paso? va a Fase Final
			# (confirm_attackers() con la lista vacía llama a _end_batalla()). Sin ningún Aliado que pueda
			# atacar, el botón dice "Fase Final" y va directo ahí.
			if not _active_player_can_attack():
				_main._update_debug("Ningún Aliado puede atacar — pasas a la Fase Final")
				GameManager._end_batalla()
				return
			_main._update_debug("Atacar: empieza la Batalla Mitológica")
			GameManager.proceed_to_battle()

		Constants.Phase.ATAQUE:
			_main._update_debug("Paso: confirmando atacantes")
			await GameManager.confirm_attackers()

		Constants.Phase.FINAL:
			_do_fase_final()

		Constants.Phase.GUERRA_TALISMANES, Constants.Phase.BLOQUEO:
			push_warning("[PhaseFlow] ¿Paso? en %s sin ventana activa" % Constants.PHASE_NAMES.get(phase, "?"))
			if _try_recover_stuck_phase_priority_window():
				_main._update_debug("Ventana de prioridad recuperada — pulsa ¿Paso? de nuevo")
			else:
				_main._update_debug("Sin ventana de prioridad activa")

		_:
			_main._update_debug("Paso presionado en fase %s" % Constants.PHASE_NAMES.get(phase, "?"))


func _do_fase_final() -> void:
	"""Disparado por el botón ¿Paso? del jugador humano en Fase Final."""
	_main._game_hud.hide_paso_button()  # sin delegate — método único de GameHUDModule
	await _resolve_fase_final(GameManager.active_player_id)


func _resolve_fase_final(player_id: int) -> void:
	"""Robo de fin de turno + límite de mano (DAR 5.D.3/5.D.4) + fin de turno.
	Camino único compartido por jugador humano (vía _do_fase_final) y oponente
	(vía _opponent_auto_pass), para que ambos apliquen exactamente las mismas reglas."""
	# "En tu Fase Final" (p.ej. Espada de O'Higgins): al entrar a la fase, antes del robo/límite de
	# mano.
	await TriggerSystem.resolve_turn_end_triggers(player_id)

	# Efectos suspendidos agendados para esta Fase Final (p.ej. Fisión Nuclear: "En la próxima Fase
	# Final oponente, Baraja una carta de coste 2 o menos o Roba dos cartas"): quedaron pendientes de
	# un Talismán ya Desterrado, no de cartas en juego.
	await EffectController.consume_scheduled_final_phase_effects(player_id)

	# torii: "Si lo haces, no Robas al finalizar tu turno" — bandera de una vez, consumida antes del
	# robo normal (OroAbilityPatterns.gd, try_execute_torii_agrupacion_pattern()).
	if TriggerSystem._oro_patterns.should_skip_final_draw(player_id):
		_main._update_debug("Fase Final: jugador %d no roba (torii)" % (player_id + 1))
	elif GameManager.is_first_turn:
		_main._update_debug("Fase Final: primer turno — sin robo")
	else:
		_main._update_debug("Fase Final: jugador %d roba %d carta(s)" % [player_id + 1, Constants.CARDS_DRAWN_PER_TURN])
		for i in range(Constants.CARDS_DRAWN_PER_TURN):
			if not await _main._zone_manager.draw_card(player_id):
				break

	await _enforce_hand_limit(player_id)

	_main._game_hud.show_phase_announcement("FIN DEL TURNO")
	await get_tree().create_timer(1.2).timeout

	# (El CombatLog ya dice "── Fin del turno de Jugador N ──".)
	GameManager.end_turn()


# =============================================================================
# LÍMITE DE MANO (DAR 5.D.4) — 8 cartas, se aplica en todos los turnos
# =============================================================================
func _enforce_hand_limit(player_id: int) -> void:
	"""Verifica el límite de mano al final del turno y fuerza el descarte del
	exceso. El jugador humano elige qué descartar (UI); el oponente descarta
	automáticamente sus cartas más caras."""
	# Lujuria: "hasta tu próximo turno no tienes límite de cartas en tu mano".
	if RuleState.active("no_hand_limit", player_id):
		return
	var hand_count = _main.player_hand.get_card_count() if player_id == 0 else _main._opponent_fan.get_card_count()
	var excess = hand_count - Constants.MAX_HAND_SIZE
	if excess <= 0:
		return

	_main._update_debug("Jugador %d excede el límite de mano (%d/%d) — debe descartar %d" % [
		player_id + 1, hand_count, Constants.MAX_HAND_SIZE, excess
	])

	# TurnClock (en línea): con el tiempo agotado, el descarte tiene su plazo de Fase Final.
	if _main.get("_turn_clock") and _main._turn_clock:
		_main._turn_clock.hand_limit_pid = player_id
	if player_id == 0:
		await _discard_excess_by_click(excess)
	elif NetworkClient.room_code != "" and NetworkClient.is_host:
		await _remote_discard_excess(excess)
	else:
		_opponent_auto_discard(excess)
	if _main.get("_turn_clock") and _main._turn_clock:
		_main._turn_clock.hand_limit_pid = -1


func _remote_discard_excess(amount: int) -> void:
	"""Límite de mano del Remoto en línea: elige él qué descartar, igual que el Anfitrión."""
	var fan = _main._opponent_fan
	if not fan:
		return
	var hand_cards: Array = fan.get_cards().duplicate()
	amount = mini(amount, hand_cards.size())
	var to_discard: Array = await TriggerSystem._select_hand_cards_for_discard(hand_cards, amount, 1)
	if to_discard.size() < amount:
		# Respuesta incompleta: las primeras de la izquierda.
		to_discard = hand_cards.filter(func(c): return is_instance_valid(c)).slice(0, amount)
	await _discard_opponent_cards(to_discard)
	_main._update_debug("Oponente descarta %d carta(s) por límite de mano" % to_discard.size())


func _discard_excess_by_click(amount: int) -> void:
	"""Descarte por límite de mano (DAR 5.D.4) con click directo sobre las cartas de la mano
	(arquitectura.md §10.16/§10.29). Usa el helper compartido de TargetedEffectExecutor
	(obligatorio, cancellable = false)."""
	var hand_cards: Array = _main.player_hand.cards.duplicate()
	if hand_cards.is_empty():
		return
	amount = mini(amount, hand_cards.size())
	var to_discard: Array = await TriggerSystem._select_hand_cards_for_discard(hand_cards, amount)
	for card in to_discard:
		var discard_data: Dictionary = card.card_data.duplicate()
		discard_data["esta_oculta"] = false
		CardManager.add_to_cemetery(0, discard_data)
		# animate_card_to_cemetery() hace ella misma el remove_card() de la
		# mano como parte de la animación (ver ZoneManager.gd) y se niega a
		# animar si la carta ya no está en el árbol — por eso NO se saca de
		# la mano antes de llamarla; solo en el camino sin animación hace
		# falta sacarla a mano.
		if _main._zone_manager and is_instance_valid(card) and card.is_inside_tree() and card.visible:
			await _main._zone_manager.animate_card_to_cemetery(card, 0)
		else:
			_main.player_hand.remove_card(card, false)
		CardManager._disconnect_card_interaction_signals(card)
		card.queue_free()
	_main._update_debug("Descarte por límite de mano completado (%d carta(s))" % to_discard.size())
	_main._zone_manager._update_castillo_counts()


func _opponent_auto_discard(amount: int) -> void:
	"""Descarta automáticamente las cartas más caras de la mano del oponente."""
	var fan = _main._opponent_fan
	if not fan:
		return
	var hand_cards: Array = fan.get_cards().duplicate()
	hand_cards.sort_custom(func(a, b): return a.card_cost > b.card_cost)
	var to_discard: Array = hand_cards.slice(0, mini(amount, hand_cards.size()))
	await _discard_opponent_cards(to_discard)
	_main._update_debug("Oponente descarta %d carta(s) por límite de mano" % to_discard.size())


func _discard_opponent_cards(to_discard: Array) -> void:
	var fan = _main._opponent_fan
	for card in to_discard:
		var data: Dictionary = card.card_data.duplicate() if card.get("card_data") else {}
		data["esta_oculta"] = false
		CardManager.add_to_cemetery(1, data)
		# Ver comentario equivalente en _discard_excess_by_click(): la
		# animación hace su propio fan.remove_card() y se niega a animar si
		# la carta ya se sacó del árbol antes de llamarla.
		if _main._zone_manager and is_instance_valid(card) and card.is_inside_tree() and card.visible:
			await _main._zone_manager.animate_card_to_cemetery(card, 1)
		else:
			fan.remove_card(card, false)
		CardManager._disconnect_card_interaction_signals(card)
		card.queue_free()
