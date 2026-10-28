extends Node
## GameManager — singleton que controla el estado global: turnos, fases, jugadores y el flujo de la
## partida.
## `game_board` y `game_board_ready` quedan declarados pero siempre null / sin emitirse (el
## GameBoard.gd viejo no existe en Main.tscn). Varios archivos todavía los leen, todos con respaldo
## vía CardManager/Main. Las cartas se mueven con CardManager + Main.
signal game_started
signal game_ended(winner: int)
signal game_board_ready(board: Node)  # nunca se emite — ver nota de arriba
signal player_lost(player_id: int, reason: String)
signal turn_started(player_id: int, turn_number: int)
signal turn_ended(player_id: int)
signal phase_changed(new_phase: Constants.Phase)
signal card_played(card: Node, player_id: int)
signal card_destroyed(card: Node)
signal damage_dealt(amount: int, target_player: int)

# =============================================================================
# ESTADO DEL JUEGO
# =============================================================================
var is_game_active: bool = false
var current_turn: int = 0  # OJO: sube una vez por RONDA (cuando vuelve a jugar el jugador 0)
## Número de turno de jugador: sube en CADA turno, de los dos jugadores. Es el que hay que usar para
## "este turno" / "hasta tu próximo turno" (RuleState). current_turn se comparte entre tu turno y el
## del rival.
var turn_serial: int = 0
var active_player_id: int = 0  # 0 o 1
var current_phase: Constants.Phase = Constants.Phase.AGRUPACION

# Referencias a los jugadores
var players: Array[Node] = []

# Legacy — siempre null, ver nota al inicio del archivo
var game_board: Node = null

# Flag para el primer turno (no se roba carta, no hay agrupación)
var is_first_turn: bool = true

# Prioridad en Guerra de Talismanes
var priority_player_id: int = 0
var players_passed_priority: Array[bool] = [false, false]

# =============================================================================
# INICIALIZACIÓN
# =============================================================================
func _ready() -> void:
	print("[GameManager] Inicializado")


func setup_game(player1: Node, player2: Node) -> void:
	"""Configura una nueva partida con dos jugadores"""
	players = [player1, player2]
	is_game_active = false
	current_turn = 0
	turn_serial = 0
	is_first_turn = true
	print("[GameManager] Partida configurada")


func start_game(starting_player: int = 0) -> void:
	"""Inicializa el estado global de la partida, emite game_started y arranca
	el Turno 1. Seguro llamar _start_turn() directamente aquí: PhaseFlowController
	ya conectó GameManager.phase_changed/turn_started en Main._ready(), mucho
	antes de que termine el mulligan y se llegue a este punto.
	"""
	if players.size() != 2:
		push_error("[GameManager] Se necesitan 2 jugadores para iniciar")
		return

	active_player_id = clampi(starting_player, 0, 1)
	is_game_active = true
	agrupacion_busy = false
	current_turn = 1
	turn_serial = 1
	TurnManager.ally_played_serial.clear()
	load("res://scripts/core/effects/mechanics/ProtectionRules.gd").reset_game_state()

	print("[GameManager] Partida iniciada. Jugador %d comienza." % (active_player_id + 1))
	emit_signal("game_started")

	_start_turn()


# =============================================================================
# FLUJO DE TURNOS
# =============================================================================
func _start_turn() -> void:
	"""Inicia un nuevo turno para el jugador activo"""
	print("[GameManager] === TURNO %d - Jugador %d ===" % [current_turn, active_player_id + 1])
	emit_signal("turn_started", active_player_id, current_turn)

	if is_first_turn:
		# Primer turno: saltar agrupación
		_change_phase(Constants.Phase.VIGILIA)
	else:
		_change_phase(Constants.Phase.AGRUPACION)


func end_turn() -> void:
	"""Finaliza el turno actual y pasa al siguiente jugador"""
	if not is_game_active:
		return

	emit_signal("turn_ended", active_player_id)

	# Cambiar jugador activo. viaje temporal: "Al finalizar este turno, gana un turno extra" — el mismo
	# jugador vuelve a jugar (RuleState "extra_turn", pendiente para ese jugador).
	if RuleState.has_pending("extra_turn", active_player_id):
		RuleState.take_pending("extra_turn", active_player_id)
		print("[GameManager] Turno extra para el jugador %d" % (active_player_id + 1))
	else:
		active_player_id = 1 - active_player_id  # Alterna entre 0 y 1

	# Si volvemos al jugador inicial, incrementar número de turno
	if active_player_id == 0:
		current_turn += 1
	turn_serial += 1

	is_first_turn = false
	_start_turn()


func advance_to_phase(new_phase: Constants.Phase) -> void:
	"""Método público para que sistemas externos avancen la fase."""
	_change_phase(new_phase)


func _change_phase(new_phase: Constants.Phase) -> void:
	"""Cambia a una nueva fase del turno"""
	current_phase = new_phase
	print("[GameManager] Fase: %s" % Constants.PHASE_NAMES[new_phase])
	# Comienzo de fase: "Puedes jugarlo al comienzo de cualquier Fase" / "en la Fase Final". Solo
	# espera si alguien puede jugar algo; si no, esto no llega a ningún await y la fase sigue igual que
	# siempre.
	var phase_window = load("res://scripts/core/game/PhaseStartWindow.gd")
	if not phase_window.is_running() and (not phase_window.playable_cards(0, new_phase).is_empty()
			or not phase_window.playable_cards(1, new_phase).is_empty()):
		await phase_window.run(new_phase)
		if current_phase != new_phase or not is_game_active:
			return
	emit_signal("phase_changed", new_phase)

	# Lógica específica de cada fase
	match new_phase:
		Constants.Phase.AGRUPACION:
			_process_agrupacion()
		Constants.Phase.VIGILIA:
			_process_vigilia()
		Constants.Phase.ATAQUE:
			_start_batalla()
		Constants.Phase.FINAL:
			_process_fase_final()


# =============================================================================
# FASE DE AGRUPACIÓN
# =============================================================================
## true mientras PhaseFlowController resuelve la Agrupación (no se pasa a la Vigilia hasta que termine).
var agrupacion_busy: bool = false


func _process_agrupacion() -> void:
	"""
	Fase de Agrupación (DAR 5.1):
	1. Aliados de Línea de Ataque → Línea de Defensa  (vía PhaseFlowController,
	   caso AGRUPACION de _on_phase_state_machine() — llama unmark_attackers())
	2. Oros Pagados → Reserva de Oro                   (vía PhaseFlowController._reset_gold())
	3. Limpiar enfermedad de invocación (DAR 3.1) — a partir de aquí los
	   Aliados del jugador activo pueden atacar sin necesitar Furia.
	La fase avanza automáticamente a VIGILIA tras un breve delay para que el
	título visual sea visible.

	NOTA: el comentario original decía que TurnManager aplicaba esta lógica
	por señales propias — eso nunca pasa en la partida real (TurnManager.
	phase_changed casi no se dispara, ver docs/audit hallazgo 1/3). Por eso
	la enfermedad de invocación nunca se limpiaba y ningún Aliado sin Furia
	podía atacar después del turno en que se jugó.
	"""
	print("[GameManager] Procesando agrupación...")

	CardFactory.on_turn_start_clear_summon_sickness(active_player_id)

	# Dar tiempo a que el anunciador de AGRUPACIÓN sea visible antes de avanzar.
	await get_tree().create_timer(1.5).timeout
	# Y a que termine todo lo de la Agrupación (agrupar, "Al comienzo del turno"/"En tu Agrupación" con sus
	# elecciones y ventanas de respuesta): si no, la Vigilia del bot arrancaba encima de la elección del
	# jugador y abría otra ventana de respuesta por detrás (Armería del Guerrero).
	while agrupacion_busy:
		await get_tree().process_frame

	_change_phase(Constants.Phase.VIGILIA)


# =============================================================================
# FASE DE VIGILIA
# =============================================================================
var oro_played_this_turn: bool = false

func _process_vigilia() -> void:
	"""
	Fase de Vigilia:
	- Poner un Oro (debe ser la primera acción)
	- Jugar Aliados, Armas, Tótems, Talismanes
	- Usar habilidades
	"""
	oro_played_this_turn = false
	# Limpiar atacantes/bloqueadores de la ÚLTIMA batalla real: si un turno termina SIN atacar,
	# PhaseFlowController salta directo de VIGILIA a FINAL (ver 'Paso: omitiendo batalla → Fase Final')
	# y jamás pasa por _start_batalla, que era el único lugar que vaciaba 'attackers' — un Aliado que
	# atacó quedaba en esa lista para siempre hasta que OTRO Aliado forzara la fase de Ataque de
	# rebote. Aquí se limpia sí o sí al empezar cada Vigilia, haya habido batalla o no.
	attackers.clear()
	blockers.clear()
	print("[GameManager] Vigilia activa - Jugador puede jugar cartas")
	# El jugador tiene el control ahora


func proceed_to_battle() -> void:
	"""Pasa de Vigilia a Batalla Mitológica (botón "Atacar"). Si nadie ataca, confirm_attackers() con
	la lista vacía va a Fase Final (_end_batalla())."""
	if current_phase == Constants.Phase.VIGILIA:
		_change_phase(Constants.Phase.ATAQUE)


# =============================================================================
# BATALLA MITOLÓGICA
# NOTA: La lógica detallada de batalla está en TurnManager.gd
# GameManager mantiene funciones básicas para compatibilidad
# =============================================================================
var attackers: Array[Node] = []
var blockers: Dictionary = {}  # {atacante: bloqueador}
## Atacantes que entran durante los "cuando ataque" (andras: "jugar ... un Aliado ... atacando"; hombre
## invisible: "declarar ataque con otro Aliado en su lugar"). confirm_attackers() los suma y dispara su
## "cuando ataque".
var replacement_attackers: Array = []

func _start_batalla() -> void:
	"""Inicia la Batalla Mitológica (proceed_to_battle()). No se limpian 'attackers'/'blockers': están
	vacíos porque solo se declaran ya en fase Ataque (_process_vigilia() los vacía al empezar cada
	Vigilia)."""
	print("[GameManager] Batalla Mitológica iniciada - Paso de Ataque")


func declare_attacker(ally: Node) -> bool:  # coroutine — el llamador debe usar 'await'
	"""Declara un Aliado como atacante (DAR 5.3.1). Punto de entrada:
	CardInteractionModule._declare_attacker(). Valida enfermedad de invocación (Furia la evita).
	Devuelve true/false: el llamador aplica el aspecto de "atacando" solo si se aceptó."""
	# No acepta VIGILIA: para declarar atacantes hay que pasar antes por el botón "Atacar"
	# (proceed_to_battle()).
	if current_phase != Constants.Phase.ATAQUE:
		return false
	if ally in attackers:
		return false
	var validation = TurnManager.can_attack(ally)
	if not validation.get("can_attack", true):
		print("[GameManager] %s no puede atacar: %s" % [ally.name, validation.get("reason", "")])
		return false
	var cap: int = attack_cap(active_player_id)
	if cap >= 0 and attackers.size() >= cap:
		var main_c := get_node_or_null("/root/Main")
		if main_c:
			main_c._update_debug("No puedes atacar con más de %d Aliado%s este turno" % [cap, "" if cap == 1 else "s"])
		return false
	attackers.append(ally)
	print("[GameManager] Atacante declarado: %s" % ally.name)

	# "Cuando ataque" (DAR 5.3.1) no se dispara aquí sino una vez por Aliado en confirm_attackers():
	# declarar/desdeclarar varias veces lo dispararía de más (p.ej. Lobo Sagrado generaría Oro
	# infinito).
	return true


## Cuántos Aliados puede declarar atacantes 'pid' este turno (-1 = sin tope): Pereza ("no se puede
## atacar", RuleState "no_attacks"), sabiduría de la oruga ("sólo pueden atacar con un Aliado",
## "attack_cap_1"), Concilio de los Eternos ("sólo puede atacar con hasta dos Aliados este turno",
## turn_data "attack_cap_2:<jugador>").
func attack_cap(pid: int) -> int:
	if RuleState.active("no_attacks", pid):
		return 0
	if RuleState.active("attack_cap_1", pid):
		return 1
	var cap := -1
	# huida de marte: "hasta tu próximo turno, sólo se puede atacar con hasta dos Aliados por turno".
	if not RuleState.turn_data("attack_cap_2:%d" % pid).is_empty() or RuleState.active("attack_cap_2", pid):
		cap = 2
	# Báculo de los Eternos (en juego de cualquiera): hasta tantos Aliados como Oros controle.
	var main := get_node_or_null("/root/Main")
	if main:
		var cq = load("res://scripts/core/effects/mechanics/CardQuery.gd")
		var phrase := "los jugadores sólo pueden atacar con hasta tantos aliados como oros controlen"
		if not (cq.cards_in_play_with(0, phrase).is_empty() and cq.cards_in_play_with(1, phrase).is_empty()):
			var golds: int = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")._golds(main, [pid]).size()
			cap = golds if cap < 0 else mini(cap, golds)
	return cap


## terremoto: "Hasta tu próximo turno, un Aliado duplica su Fuerza y si ataca o bloquea debes Botar tantas
## cartas como Fuerza tenga. Si ese Aliado porta Anticucho, en vez de eso ... Botas su Fuerza impresa."
## Meta "terremoto" = {until, pid, printed}.
func _terremoto_mill(ally: Node) -> void:
	if not is_instance_valid(ally):
		return
	var t: Dictionary = ally.get_meta("terremoto", {})
	if t.is_empty() or turn_serial > int(t.until):
		return
	var n: int = int(ally.get("card_strength")) if t.get("printed", false) else int(ContinuousEffectManager.get_modified_strength(ally))
	if n > 0:
		await ActionModule.mill(int(t.pid), n, false, "terremoto")


## furia de titán: "tu oponente no puede atacar con Aliados de mayor Fuerza que ese Aliado" (hasta tu próximo
## turno). {jugador que no puede: {node, until}}; lo mira TurnManager.can_attack().
var attack_strength_caps: Dictionary = {}


func attack_strength_cap_blocks(ally: Node) -> bool:
	var pid: int = int(ally.controller_id) if ally.get("controller_id") != null else active_player_id
	var cap: Dictionary = attack_strength_caps.get(pid, {})
	if cap.is_empty() or turn_serial > int(cap.until) or not is_instance_valid(cap.node) 			or not (cap.node.get("current_zone") in Constants.ZONES_IN_PLAY):
		return false
	return ContinuousEffectManager.get_modified_strength(ally) > ContinuousEffectManager.get_modified_strength(cap.node)


## juzumaru tsunetsugu / Marca de la Bestia: "deba atacar (o bloquear) este turno si puede" — meta
## "must_fight_turn". Al confirmar, los Aliados del jugador activo con la marca que pueden atacar y no se
## declararon atacan igual (con el mismo aspecto que un click).
func _declare_forced_attackers() -> void:
	var main := get_node_or_null("/root/Main")
	if not main or not main.get("_card_interaction"):
		return
	var lines: Array = load("res://scripts/core/game/PlayerSide.gd").ally_containers(main, active_player_id)
	for line in lines:
		for ally in line.get_children():
			if not is_instance_valid(ally) or ally in attackers or ally.get("card_type") != Constants.CardType.ALIADO:
				continue
			if int(ally.get_meta("must_fight_turn", -1)) != turn_serial:
				continue
			if not TurnManager.can_attack(ally).get("can_attack", true):
				continue
			main._update_debug("%s debe atacar este turno" % str(ally.get("card_name")))
			await main._card_interaction._declare_attacker(ally)


## Lo mismo para bloquear: el primer atacante libre al que puede bloquear.
func _declare_forced_blockers() -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var lines: Array = load("res://scripts/core/game/PlayerSide.gd").ally_containers(main, 1 - active_player_id)
	for blocker in lines[0].get_children() if not lines.is_empty() else []:
		if not is_instance_valid(blocker) or int(blocker.get_meta("must_fight_turn", -1)) != turn_serial or blocker in blockers.values():
			continue
		if not ContinuousEffectManager.can_block(blocker):
			continue
		for attacker in attackers:
			if is_instance_valid(attacker) and not blockers.has(attacker) and BattleManager.is_valid_block(attacker, blocker).get("valid", false):
				declare_blocker(blocker, attacker)
				main._update_debug("%s debe bloquear: bloquea a %s" % [str(blocker.get("card_name")), str(attacker.get("card_name"))])
				break


func undeclare_attacker(ally: Node) -> bool:
	"""Retira un Aliado de los atacantes antes de confirmar (otro clic, mientras siga el paso de
	Ataque). Como "cuando ataque" se dispara recién al confirmar, no hay trigger que deshacer. Solo
	en fase Ataque, como declare_attacker()."""
	if current_phase != Constants.Phase.ATAQUE:
		return false
	if ally not in attackers:
		return false
	attackers.erase(ally)
	print("[GameManager] Atacante retirado: %s" % ally.name)
	return true


func confirm_attackers() -> void:  # coroutine — el llamador debe usar 'await'
	"""Confirma los atacantes y pasa al paso de Bloqueo — o directo a Guerra
	de Talismanes si el defensor no tiene ningún Aliado con el que bloquear
	(hoy es siempre el caso mientras el oponente-bot no juegue Aliados)."""
	await _declare_forced_attackers()
	if attackers.is_empty():
		# Sin atacantes, terminar batalla
		_end_batalla()
		return
	# "Al comienzo del Ataque" (p.ej. Almirante Akari) se resuelve aquí, con atacantes declarados: sin
	# ataque, no hay.
	await TriggerSystem.resolve_ataque_triggers(active_player_id)

	# "Cuando ataque" (DAR 5.3.1) se dispara aquí, una vez por Aliado. 'attackers' ya es la lista final
	# sin duplicados (declare_attacker() los rechaza y undeclare_attacker() los saca).
	# Sobre una copia: un "cuando ataque" puede sacar a su Aliado (hombre invisible) o sumar otro atacante
	# (andras, hombre invisible: replacement_attackers), que dispara después.
	var to_fire: Array = attackers.duplicate()
	while not to_fire.is_empty():
		var ally = to_fire.pop_front()
		if is_instance_valid(ally) and ally in attackers:
			# "si no fue declarado atacante este turno" (p.ej. Guardia Real) — EffectInterpreter consulta
			# esta marca.
			ally.set_meta("declared_attacker_turn", turn_serial)
			await _terremoto_mill(ally)
			EffectController.emit_signal("on_card_attacks", active_player_id, ally)
			await TriggerSystem._collect_triggers_for_event("on_attack", {
				"player_id": active_player_id, "card": ally
			})
			await _check_wielder_attack_triggers(ally, active_player_id)
		while not replacement_attackers.is_empty():
			var extra = replacement_attackers.pop_front()
			if is_instance_valid(extra) and not (extra in attackers):
				attackers.append(extra)
				var main_x := get_node_or_null("/root/Main")
				if main_x and main_x.get("_card_interaction") and main_x._card_interaction.has_method("mark_attacker_visual"):
					await main_x._card_interaction.mark_attacker_visual(extra)
				to_fire.append(extra)

	# "Cuando ataques con tres o más Aliados..." (p.ej. Sable de Napoleón) — condición sobre la
	# CANTIDAD TOTAL de atacantes confirmados, no un trigger por Aliado individual (el loop de arriba
	# dispara "cuando ataque" una vez por cada uno; esto es aparte, una sola vez).
	# "Cuando ataques" en las cartas que no atacan (Oros, Armas, Aliados que se quedan).
	await TriggerSystem.resolve_player_attack_triggers(active_player_id, attackers)
	_check_attack_count_triggers(active_player_id, attackers.size())
	await load("res://scripts/core/effects/mechanics/InPlayAbilities.gd").estacion_fantasma_on_attack(active_player_id)

	if not _defender_has_blockers():
		print("[GameManager] Defensor sin Aliados para bloquear — saltando Bloqueo")
		forced_blocks.clear()
		_change_phase(Constants.Phase.GUERRA_TALISMANES)
	else:
		_change_phase(Constants.Phase.BLOQUEO)
		_apply_forced_blocks()


func _check_wielder_attack_triggers(ally: Node, player_id: int) -> void:
	"""'Cuando el portador ataque, si es de coste 1 o más, genera un Oro o Roba una carta' (p.ej.
	Garfio Pirata) — trigger propio de un Arma equipada sobre el ataque de SU portador. El camino
	genérico (TriggerSystem._collect_triggers_for_event) solo revisa el texto de la carta que
	ataca, no el de sus Armas equipadas (mismo motivo por el que _check_attack_count_triggers
	existe aparte para Sable de Napoleón) — se resuelve aquí, directo, con el mismo criterio."""
	if not is_instance_valid(ally):
		return
	var weapons = ally.get("equipped_weapons")
	if not (weapons is Array):
		return
	for w in weapons:
		if is_instance_valid(w) and _card_has_wielder_attack_choice(w):
			await _resolve_wielder_attack_choice(w, ally, player_id)
		# Cañón Helios: "Cuando el portador ataca, puedes elegir un Aliado oponente para que lo bloquee."
		# hacha de perun: "...y cuando ataca puedes elegir un Aliado que lo bloquee."
		var w_text: String = str(w.get("card_ability")).to_lower() if is_instance_valid(w) else ""
		if is_instance_valid(w) and not KeywordManager.is_silenced(w) \
				and ("cuando el portador ataca, puedes elegir un aliado oponente para que lo bloquee" in w_text
					or "cuando ataca puedes elegir un aliado que lo bloquee" in w_text):
			await _choose_forced_blocker(w, ally, player_id)


## Bloqueos elegidos por el atacante (Cañón Helios): {atacante: bloqueador}.
## Se aplican al entrar a Bloqueo; el defensor ya no puede mover a ese Aliado.
var forced_blocks: Dictionary = {}


func _choose_forced_blocker(weapon: Node, ally: Node, player_id: int) -> void:
	var main := get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return
	var defense = main.opponent_field if player_id == 0 else main.player_field
	var filter := func(c: Node) -> bool:
		return is_instance_valid(c) and c.get_parent() == defense and c.get("card_type") == Constants.CardType.ALIADO \
			and not (c in forced_blocks.values()) and ContinuousEffectManager.can_block(c) \
			and BattleManager.is_valid_block(ally, c).get("valid", false)
	if not defense.get_children().any(func(c): return filter.call(c)):
		return
	var picked: Node = await load("res://scripts/core/game/PlayerSide.gd").pick_in_play(main, player_id,
		"%s: elige un Aliado oponente para que bloquee a %s (N: no)" % [str(weapon.get("card_name")), str(ally.get("card_name"))],
		filter, true, [1 - player_id])
	if picked and is_instance_valid(picked):
		forced_blocks[ally] = picked
		main._update_debug("%s deberá bloquear a %s" % [str(picked.get("card_name")), str(ally.get("card_name"))])


func _apply_forced_blocks() -> void:
	var main := get_node_or_null("/root/Main")
	for attacker in forced_blocks:
		var blocker: Node = forced_blocks[attacker]
		if not is_instance_valid(attacker) or not is_instance_valid(blocker) or not (attacker in attackers):
			continue
		declare_blocker(blocker, attacker)
		blocker.set_meta("forced_block_turn", turn_serial)  # el defensor no puede quitarlo
		blocker.create_tween().tween_property(blocker, "modulate", Color(0.4, 0.7, 1.0, 1.0), 0.2)
		if main:
			main._update_debug("%s bloquea a %s" % [str(blocker.get("card_name")), str(attacker.get("card_name"))])
	forced_blocks.clear()


func _card_has_wielder_attack_choice(card: Node) -> bool:
	var text: String = str(card.get("card_ability")) if card.get("card_ability") != null else ""
	var lower := text.to_lower()
	return ("cuando el portador ataque" in lower and "genera un oro" in lower and "roba una carta" in lower)


func _resolve_wielder_attack_choice(weapon: Node, ally: Node, player_id: int) -> void:
	if int(ally.get("card_cost")) < 1:
		return
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	var choose_gold: bool = await SelectionManager.await_two_choice(
		main, weapon.card_name if weapon.get("card_name") else "Arma", "Generar un Oro", "Robar una carta", player_id)
	if choose_gold:
		if main._gold_manager:
			main._gold_manager.generar_oros_virtuales(1, player_id)
	else:
		await ActionModule.draw(player_id, 1, "weapon_attack_trigger", true)


func _check_attack_count_triggers(player_id: int, attacker_count: int) -> void:
	"""'Cuando ataques con tres o más Aliados, las cartas que estén o sean puestas en los Cementerios
	este turno pierden su habilidad hasta tu próximo turno' (p.ej. Sable de Napoleón). Se resuelve
	UNA SOLA VEZ aquí (no es un trigger por Aliado, es una condición sobre el total de atacantes
	confirmados) — apenas se encuentra una fuente con este texto, se aplica y se corta (no tiene
	sentido aplicar dos veces aunque hubiera dos copias)."""
	if attacker_count < 3:
		return
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if player_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			var weapons = card.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and _card_has_attack_count_cemetery_silence(w):
						CardManager.silence_all_cemetery_cards(player_id)
						return
			if _card_has_attack_count_cemetery_silence(card):
				CardManager.silence_all_cemetery_cards(player_id)
				return


func _card_has_attack_count_cemetery_silence(card: Node) -> bool:
	var text: String = str(card.get("card_ability")) if card.get("card_ability") != null else ""
	var lower := text.to_lower()
	return ("cuando ataques con tres o" in lower and "aliados" in lower
		and "pierden su habilidad" in lower and "cementerio" in lower)


func _defender_has_blockers() -> bool:
	"""Verifica si el jugador defensor tiene al menos un Aliado en juego."""
	var defender_id = 1 - active_player_id
	var main = get_node_or_null("/root/Main")
	if not main:
		return false
	var field = main.player_field if defender_id == 0 else main.opponent_field
	if not field:
		return false
	for card in field.get_children():
		if card.get("card_type") == Constants.CardType.ALIADO:
			return true
	return false


func declare_blocker(blocker: Node, attacker: Node) -> void:
	"""Declara un Aliado como bloqueador de un atacante"""
	if current_phase == Constants.Phase.BLOQUEO:
		# Los Marcados: "tu oponente no puede declarar más de dos Aliados bloqueadores este turno".
		var cap: Dictionary = RuleState.turn_data("block_cap:%d" % (int(blocker.controller_id) if blocker.get("controller_id") != null else 0))
		if not cap.is_empty() and not (blocker in blockers.values()):
			var distinct: Dictionary = {}
			for a in blockers:
				if a != attacker and is_instance_valid(blockers[a]):
					distinct[blockers[a]] = true
			if distinct.size() >= int(cap.n):
				var m := get_node_or_null("/root/Main")
				if m:
					m._update_debug("No puedes declarar más de %d bloqueadores este turno" % int(cap.n))
				return
		blockers[attacker] = blocker
		print("[GameManager] %s bloquea a %s" % [blocker.name, attacker.name])


func confirm_blockers_and_collect_triggers() -> void:  # coroutine — el llamador debe usar 'await'
	"""Recolecta "cuando bloqueas" (on_block, DAR 7.2/7.3) para cada bloqueador declarado y avanza a
	Guerra de Talismanes. Como confirm_attackers(): la lista ya es definitiva (declare_blocker()
	reescribe la clave del atacante), así que cada Aliado dispara una sola vez. También libro de
	thoth (GoldManager.check_libro_de_thoth_block()). Lo llama PhaseFlowController al terminar el
	Bloqueo."""
	var main := get_node_or_null("/root/Main")
	_declare_forced_blockers()  # juzumaru tsunetsugu / Marca de la Bestia
	for b in blockers.values():
		await _terremoto_mill(b)
	# Pan de Muerto: "tus Aliados son Indestructibles mientras bloquean".
	load("res://scripts/core/effects/mechanics/ProtectionRules.gd").on_blockers_confirmed(blockers.values())
	# {bloqueador: [atacantes que bloquea]}: un Aliado que bloquea a varios dispara una sola vez, y
	# su "Cuando bloquee" sabe a quiénes bloquea (BlockPatterns.gd).
	var blocks: Dictionary = {}
	for attacker in blockers:
		var b: Node = blockers[attacker]
		if is_instance_valid(b):
			if not blocks.has(b):
				blocks[b] = []
			blocks[b].append(attacker)
	load("res://scripts/core/effects/triggers/BlockPatterns.gd").apply_static_on_blockers(blocks)
	for blocker in blocks:
		if is_instance_valid(blocker):
			var blocker_owner: int = blocker.get("controller_id") if blocker.get("controller_id") != null else (1 - active_player_id)
			EffectController.emit_signal("on_card_blocks", blocker_owner, blocker)
			await TriggerSystem._collect_triggers_for_event("on_block", {
				"player_id": blocker_owner, "card": blocker, "blocked": blocks[blocker]
			})
			# Libro de thoth (Oro) — carta pasiva ajena al bloqueador, no llega por el camino de trigger_type
			# de arriba (ver docstring de GoldManager.check_libro_de_thoth_block).
			if main and main.get("_gold_manager"):
				main._gold_manager.check_libro_de_thoth_block(blocker, blocker_owner)
	advance_to_phase(Constants.Phase.GUERRA_TALISMANES)


func pass_priority() -> void:
	"""
	DEPRECATED: El flujo de prioridad ahora pasa por PriorityManager.pass_priority().
	Esta función queda por compatibilidad pero no debe ser usada directamente.
	"""
	push_warning("[GameManager] pass_priority() llamada directamente — usar PriorityManager.pass_priority()")
	PriorityManager.pass_priority()


func _end_batalla() -> void:
	"""Finaliza la Batalla Mitológica"""
	attackers.clear()
	blockers.clear()
	_change_phase(Constants.Phase.FINAL)


# =============================================================================
# FASE FINAL
# =============================================================================
func _process_fase_final() -> void:
	"""Fase Final: solo anuncia el cambio de fase. El robo de fin de turno y el descarte por límite de
	mano (DAR 5.D.3/5.D.4) están en PhaseFlowController._resolve_fase_final(), para ambos
	jugadores. No duplicar esa lógica aquí."""
	print("[GameManager] Fase Final")


# =============================================================================
# CONDICIONES DE VICTORIA
# =============================================================================
func check_victory() -> void:
	"""Verifica si algún jugador se quedó sin cartas en el Castillo (DAR 2.1). Lee el tamaño real de
	player_deck/opponent_deck en Main: los 'players' son Node.new() vacíos sin get_deck_count(). Lo
	llama ZoneManager.draw_card() al robar con el mazo vacío; la derrota por daño de combate la
	decide BattleManager (GameManager.player_loses())."""
	if not is_game_active:
		return
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	if main.player_deck.is_empty():
		player_loses(0, "deck_empty")
	elif main.opponent_deck.is_empty():
		player_loses(1, "deck_empty")


func _end_game(winner_id: int) -> void:
	"""Termina la partida"""
	is_game_active = false
	print("[GameManager] ¡Jugador %d GANA!" % (winner_id + 1))
	emit_signal("game_ended", winner_id)


# =============================================================================
# GAME BOARD MANAGEMENT
# =============================================================================
func player_loses(player_id: int, reason: String) -> void:
	"""Marca que un jugador ha perdido la partida (DAR 2.1)
	reason puede ser: "deck_empty", "castle_destroyed", "concede"
	"""
	if not is_game_active:
		return  # ya terminó por otro camino (p.ej. combate y check_victory casi a la vez)
	var winner_id = 1 - player_id
	print("[GameManager] Jugador %d pierde por: %s" % [player_id + 1, reason])
	emit_signal("player_lost", player_id, reason)
	_end_game(winner_id)
