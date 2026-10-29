extends Node
## TriggerSystem - Gestiona la cola de habilidades disparadas (DAR 7.4)
## Orden: Primero jugador activo elige orden, luego oponente

# =============================================================================
# SIGNALS
# =============================================================================
signal triggers_pending(active_player_triggers: Array, opponent_triggers: Array)
signal trigger_resolved(card: Node, trigger_type: String, result: Dictionary)
signal trigger_cancelled(card: Node, trigger_type: String, cancelled_by: Node)
signal all_triggers_resolved

# Ventana de respuesta (DAR Sección 8 - Cancelar)
signal waiting_for_responses(trigger: Dictionary, responding_player: int)
signal response_window_closed(trigger: Dictionary, was_cancelled: bool)

# =============================================================================
# ESTADO
# =============================================================================
## Cola de triggers pendientes (se resuelven en orden FIFO)
var trigger_queue: Array[Dictionary] = []

## Triggers recolectados durante un evento (antes de ordenar)
var pending_active_triggers: Array[Dictionary] = []
var pending_opponent_triggers: Array[Dictionary] = []

## Flag para saber si estamos recolectando triggers
var is_collecting: bool = false

## Flag para saber si estamos resolviendo
var is_resolving: bool = false

## Ventana de respuesta
var awaiting_response: bool = false
var current_trigger_for_response: Dictionary = {}
var response_timeout: float = 10.0  # Segundos para responder

## Señales para buffs
signal buff_applied(target: Node, buff: Dictionary)
signal buff_expired(target: Node, buff: Dictionary)
signal buffs_cleared(count: int, duration: String)

## Callback de cancelación pendiente
var pending_cancel_callback: Callable = Callable()

## Módulos extraídos (Fase 4 de reestructuración)
var _resolution: TriggerResolution
var _targeted_executor: TargetedEffectExecutor
var _restrictions: TriggerRestrictions
var _buffs: TemporaryBuffSystem
## Patrones "mira/muestra y juega" (Signo Amarillo, Tangata Manu, Presente, Perder la Razón).
var _look_and_play: LookAndPlayResolver
## Buscador de cartas por nombre para efectos "nombra una carta" (p.ej. Alicia en Wonderland, Tesoro
## de los Césares). Con preload(): un editor abierto desde antes de crear la clase no tiene
## registrado su class_name y falla con "Could not find type".
const CardNameSearchDialogScript = preload("res://scripts/ui/selection/CardNameSearchDialog.gd")
var _card_name_search: RefCounted
## Familias de patrones "try_execute_*_pattern" separadas de TargetedEffectExecutor.gd. preload() en
## vez del class_name global, por el mismo motivo que arriba.
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)
const EffectInterpreterScript = preload("res://scripts/core/effects/compiler/EffectInterpreter.gd")
const AllyEventTriggersScript = preload("res://scripts/core/effects/triggers/AllyEventTriggers.gd")
const DrawShuffleResolverScript = preload("res://scripts/core/effects/triggers/DrawShuffleResolver.gd")
const ConvertAndMiscResolverScript = preload("res://scripts/core/effects/triggers/ConvertAndMiscResolver.gd")
## Patrones de Tótems (auditoría de cartas sin cobertura, arquitectura.md). preload() por el mismo
## motivo.
const TotemAbilityPatternsScript = preload("res://scripts/core/effects/triggers/TotemAbilityPatterns.gd")
## Patrones de Armas (misma auditoría). preload() por el mismo motivo.
const WeaponAbilityPatternsScript = preload("res://scripts/core/effects/triggers/WeaponAbilityPatterns.gd")
## Patrones de Oros (misma auditoría). preload() por el mismo motivo.
const OroAbilityPatternsScript = preload("res://scripts/core/effects/triggers/OroAbilityPatterns.gd")
var _draw_shuffle_resolver: RefCounted
var _convert_misc_resolver: RefCounted
var _totem_patterns: RefCounted
var _weapon_patterns: RefCounted
var _oro_patterns: RefCounted
## Efectos compilados por piezas (EffectCompiler + EffectInterpreter, arquitectura.md §54): se
## prueban antes de la cadena de patrones en TriggerResolution._resolve_look_and_play_patterns().
var _effect_interpreter: RefCounted
## "Cuando sea puesta en tu Cementerio" (Lanza Argenta).
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
var _cemetery_triggers: RefCounted


func _ready() -> void:
	_resolution = TriggerResolution.new()
	_resolution.setup(self)
	_targeted_executor = TargetedEffectExecutor.new()
	_targeted_executor.setup(self)
	_draw_shuffle_resolver = DrawShuffleResolverScript.new()
	_draw_shuffle_resolver.setup(_targeted_executor)
	_convert_misc_resolver = ConvertAndMiscResolverScript.new()
	_convert_misc_resolver.setup(_targeted_executor)
	_totem_patterns = TotemAbilityPatternsScript.new()
	_totem_patterns.setup(self)
	_weapon_patterns = WeaponAbilityPatternsScript.new()
	_weapon_patterns.setup(self)
	_oro_patterns = OroAbilityPatternsScript.new()
	_oro_patterns.setup(self)
	_effect_interpreter = EffectInterpreterScript.new()
	_effect_interpreter.setup(self)
	_restrictions = TriggerRestrictions.new()
	_restrictions.setup(self)
	_buffs = TemporaryBuffSystem.new()
	_buffs.setup(self)
	_look_and_play = LookAndPlayResolver.new()
	_look_and_play.setup(self)
	_card_name_search = CardNameSearchDialogScript.new()
	_card_name_search.setup(self)
	_cemetery_triggers = CemeteryTriggersScript.new()
	CardManager.card_put_in_cemetery.connect(_cemetery_triggers.on_card_put_in_cemetery)
	CardManager.card_put_in_exile.connect(_cemetery_triggers.on_card_put_in_exile)
	CardManager.card_destroyed.connect(_cemetery_triggers.on_card_destroyed)

	# Conectar a señales de EffectController para recolectar triggers.
	# on_card_entered_play y on_card_attacks NO se conectan aquí — esos dos
	# los llama el código que juega/ataca directamente (GoldManager,
	# GameManager) con 'await', para que el trigger termine de resolverse
	# ANTES de que el juego siga de fase. Conectados por señal (fire-and-
	# forget, como el resto de abajo) el emisor no espera a que el handler
	# async termine, y el trigger podía resolverse varias fases después de
	# jugarse la carta (se vio con Drácula y Signo Amarillo resolviendo en
	# Bloqueo). Ver _collect_triggers_for_event(), llamado directo con await.
	if EffectController:
		EffectController.on_card_drawn.connect(_on_global_event.bind("on_card_drawn"))
		EffectController.on_card_milled.connect(_on_global_event_with_dest.bind("on_card_milled"))
		EffectController.on_card_discarded.connect(_on_global_event.bind("on_discard"))
		EffectController.on_card_left_play.connect(_on_global_event_with_zone.bind("on_leave_play"))
		EffectController.on_card_destroyed.connect(_on_global_event.bind("on_destroyed"))
		EffectController.on_card_exiled.connect(_on_global_event.bind("on_exiled"))


# =============================================================================
# RECOLECCIÓN DE TRIGGERS
# =============================================================================
func begin_collecting() -> void:
	"""Inicia la recolección de triggers para un evento"""
	is_collecting = true
	pending_active_triggers.clear()
	pending_opponent_triggers.clear()


func end_collecting_and_queue() -> void:
	"""Finaliza recolección y encola los triggers en orden correcto (DAR 7.4)"""
	is_collecting = false

	if pending_active_triggers.is_empty() and pending_opponent_triggers.is_empty():
		return

	var active_player = GameManager.active_player_id if GameManager else 0

	# Notificar que hay triggers pendientes
	emit_signal("triggers_pending", pending_active_triggers, pending_opponent_triggers)

	# Con varios triggers simultáneos del jugador activo, él elige el orden (DAR 7.4; p.ej. Espada de
	# O'Higgins y Capitán O'Brien en Fase Final: barajar el Cementerio antes de robar). Solo elige el
	# humano; el oponente resuelve en orden de llegada.
	if pending_active_triggers.size() > 1 and active_player == 0:
		pending_active_triggers = await _prompt_trigger_order(pending_active_triggers)

	# Añadir triggers del jugador activo primero
	for trigger in pending_active_triggers:
		trigger_queue.append(trigger)

	# Añadir triggers del oponente después (orden de llegada — el bot no
	# elige todavía)
	for trigger in pending_opponent_triggers:
		trigger_queue.append(trigger)

	print("[TriggerSystem] Cola de triggers: %d total" % trigger_queue.size())


func _prompt_trigger_order(triggers: Array[Dictionary]) -> Array[Dictionary]:
	"""Elegir el orden de resolución de varios triggers propios clickeando las cartas que van a
	disparar, una tras otra. Devuelve los mismos triggers en el orden elegido (o el original si
	algo falla, para no perder ninguno). Tipado Array[Dictionary] porque el llamador lo asigna a
	pending_active_triggers."""
	var main := get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return triggers
	var candidates: Array = []
	var by_card: Dictionary = {}
	for t in triggers:
		var card: Node = t.get("card")
		if not is_instance_valid(card):
			return triggers  # falta algo para armar el picker — no arriesgar el orden
		candidates.append(card)
		by_card[card] = t

	# cancellable = false (arquitectura.md §10.29): hay que elegir el orden completo; ESC a mitad
	# dejaría triggers sin resolver. Brillo dorado: son triggers propios esperando orden, no objetivos
	# (celeste/rojo).
	var chosen: Array = await main._card_interaction.await_multi_target(
		"Elige el orden en que se resuelven (clickea primero la que quieras que actúe antes)",
		candidates, candidates.size(), Callable(), Callable(), false, CardBadges.GLOW_COLOR_GOLD)

	var ordered: Array[Dictionary] = []
	for card in chosen:
		if by_card.has(card):
			ordered.append(by_card[card])
	return ordered if ordered.size() == triggers.size() else triggers


func register_trigger(card: Node, trigger_type: String, event_data: Dictionary) -> void:
	"""Registra un trigger disparado por una carta"""
	var trigger_data = {
		"card": card,
		"trigger_type": trigger_type,
		"event_data": event_data,
		"controller_id": card.controller_id if card.get("controller_id") != null else 0
	}
	# "Cuando salga del juego": la carta puede liberarse antes de que se resuelva (carcosa se Destierra
	# con su propio efecto); con sus datos, TriggerResolution lo resuelve sobre un sustituto.
	if trigger_type == "on_leave_play" and card.get("card_data") is Dictionary:
		trigger_data["card_data"] = card.card_data.duplicate()
		trigger_data["owner_id"] = card.owner_id if card.get("owner_id") != null else trigger_data.controller_id

	var active_player = GameManager.active_player_id if GameManager else 0

	if is_collecting:
		# Durante recolección, separar por jugador
		if trigger_data.controller_id == active_player:
			pending_active_triggers.append(trigger_data)
		else:
			pending_opponent_triggers.append(trigger_data)
	else:
		# Fuera de recolección, añadir directo a la cola
		trigger_queue.append(trigger_data)


# =============================================================================
# RESOLUCIÓN DE TRIGGERS (implementación en TriggerResolution.gd, con
# ejecución de efectos con objetivo en TargetedEffectExecutor.gd)
# =============================================================================
func resolve_next_trigger() -> Dictionary:
	return await _resolution.resolve_next_trigger()


func cancel_current_trigger(cancelling_card: Node = null) -> bool:
	return _resolution.cancel_current_trigger(cancelling_card)


func pass_response() -> void:
	_resolution.pass_response()


func resolve_all_triggers() -> void:
	await _resolution.resolve_all_triggers()


func has_pending_triggers() -> bool:
	return _resolution.has_pending_triggers()


func clear_triggers() -> void:
	_resolution.clear_triggers()


func resolve_talisman(card: Node) -> bool:
	"""Envoltorio (§56): marca el contexto de efecto (quién controla el Talismán) para el detector de
	paridad mientras resuelve. La lógica está en _resolve_talisman_impl()."""
	var controller: int = int(card.get("owner_id")) if is_instance_valid(card) and card.get("owner_id") != null else 0
	var ctx_token: int = EffectContextScript.push(card, controller, "Talismán", "pending")
	var annulled: bool = await _resolve_talisman_impl(card)
	EffectContextScript.pop(ctx_token)
	return annulled


func _resolve_talisman_impl(card: Node) -> bool:
	"""Resuelve el efecto impreso de un Talismán al jugarlo (DAR Sección 8). Un Talismán no dispara:
	su texto es el efecto y se resuelve directo, sin has_trigger()/register_trigger() ni la cola de
	triggers. Lo llama GoldManager._trigger_enter_play().
	Para un Talismán, jugarlo y resolverlo son el mismo momento, así que este es el único punto que
	hace falta para darle a cualquier Talismán su ventana de respuesta (Pila de Respuesta
	Universal); los patrones no abren una propia.
	Devuelve true si fue anulado/cancelado en la ventana (no se resuelve; el llamador lo manda al
	Cementerio)."""
	if not is_instance_valid(card):
		return false
	var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return false
	var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
	if await open_response_window(card, str(card.card_name) if card.get("card_name") else "", controller_id):
		return true
	# kotoku-in: "el próximo Talismán que juegue tu oponente este turno se resuelva sin efecto" — se
	# consume antes de resolver; true = al Cementerio sin efecto, como Anular/Cancelar.
	if _totem_patterns.consume_kotoku_in_talisman_fizzle(controller_id, int(card.get("card_cost")) if card.get("card_cost") != null else 0):
		return true
	await _resolution._resolve_look_and_play_patterns(card, ability_text, ability_text, controller_id, {"card": card})
	return false


# =============================================================================
# HANDLERS DE EVENTOS GLOBALES
# =============================================================================
func _on_global_event(player_id: int, card: Node, event_type: String) -> void:
	"""Handler genérico para eventos de 2 parámetros"""
	_collect_triggers_for_event(event_type, {
		"player_id": player_id,
		"card": card
	})


func _on_global_event_with_zone(player_id: int, card: Node, zone: int, event_type: String) -> void:
	"""Handler para eventos con zona. Al salir del juego se anota por qué (efecto/daño de quién), que
	se pierde en cuanto la cola resuelve (kato tsune: "por un efecto oponente")."""
	var data := {"player_id": player_id, "card": card, "zone": zone}
	if event_type == "on_leave_play":
		data["cause"] = CemeteryTriggersScript._cause(player_id)
	_collect_triggers_for_event(event_type, data)


func _on_global_event_with_dest(player_id: int, card: Node, destination: int, event_type: String) -> void:
	"""Handler para eventos con destino"""
	_collect_triggers_for_event(event_type, {
		"player_id": player_id,
		"card": card,
		"destination": destination
	})


func _collect_triggers_for_event(event_type: String, event_data: Dictionary) -> void:
	"""Recolecta todos los triggers que responden a un evento.
	Guardia de reentrada: se llama con await desde varios sitios y trigger_queue/pending_* son
	compartidos. Si llegaba un segundo evento (p.ej. declarar un ataque) mientras la ventana del
	trigger anterior seguía abierta, dos bucles competían por la misma cola. Se espera a que
	termine la recolección/resolución anterior: todo queda serializado."""
	# Reentrada anidada: si esta llamada ocurre dentro de la resolución de otro trigger (p.ej. Lobo
	# Sagrado equipa un Arma con "cuando entra en juego"), esperar a is_resolving = false es un
	# deadlock (no baja hasta que esta llamada retorne). is_collecting solo es true en un tramo
	# síncrono, así que se espera solo si hay una recolección concurrente real, nunca por estar
	# anidada.
	# iga ryu: el primer Aliado que entra bajo el control de su oponente cada turno pierde su
	# habilidad, antes de recolectar sus "cuando entra en juego".
	if event_type == "on_enter_play":
		load("res://scripts/core/effects/mechanics/InPlayAbilities.gd").iga_ryu_on_ally_enters(event_data.get("card", null))
	var is_nested_reentry := is_resolving and not is_collecting
	if not is_nested_reentry:
		# Salvaguarda: esta espera debería durar pocos frames. Si un error deja is_collecting trabado en
		# true, a los 3 s fuerza el reset y avisa por consola en vez de colgar todos los triggers de la
		# partida.
		var waited := 0.0
		while (is_collecting or is_resolving) and waited < 3.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		if is_collecting or is_resolving:
			push_warning("[TriggerSystem] is_collecting/is_resolving atascado >3s — forzando reset (ver causa raíz pendiente)")
			is_collecting = false
			is_resolving = false
	begin_collecting()

	var event_card = event_data.get("card", null)

	# ── Camino directo: el propio disparador de la carta del evento ────────
	# (p.ej. "Cuando entra en juego" de la carta recién jugada). No depende de GameManager.game_board
	# (GameBoard viejo, siempre null).
	# "Cuando sea Destruido" de la propia carta: no por aquí (su Nodo se libera antes de que la cola lo
	# resuelva), sino por CemeteryTriggers.on_card_destroyed().
	if event_card and is_instance_valid(event_card) and event_card.has_method("has_trigger") \
			and event_type != "on_destroyed" \
			and not (event_type == "on_enter_play" and event_card.get_meta("skip_enter_triggers", false)):  # Manicomio
		if event_card.has_trigger(event_type):
			if _check_trigger_conditions(event_card, event_type, event_data):
				register_trigger(event_card, event_type, event_data)

	# ── Camino completo: triggers de OTRAS cartas que reaccionan a este evento ──
	# (p.ej. "Cuando otro Aliado entre al juego..."), sobre el campo real de Main. Solo se revisan los
	# related_triggers (p.ej. on_ally_enters): los triggers de mismo event_type ("cuando ESTA carta
	# entra en juego") son propios de cada carta; si se compartieran, todas las cartas del campo
	# volverían a dispararse con cada carta nueva.
	var main = get_node_or_null("/root/Main")
	if main:
		# event_card puede llegar ya liberada (una carta que salió de juego). Pasarla a
		# _get_related_triggers() (tipado Node) tira "previously freed" y corta la función antes de
		# end_collecting_and_queue(), dejando is_collecting trabado.
		var safe_event_card: Node = event_card if is_instance_valid(event_card) else null
		var related_triggers = _get_related_triggers(event_type, safe_event_card)

		if not related_triggers.is_empty():
			for player_id in [0, 1]:
				var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if player_id == 0 \
					else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
				for field in fields:
					if not field:
						continue
					for card in field.get_children():
						if card == event_card:
							continue  # ya se registró arriba
						if not card.has_method("has_trigger"):
							continue
						for related in related_triggers:
							if card.has_trigger(related):
								if _check_trigger_conditions(card, related, event_data):
									register_trigger(card, related, event_data)

	await end_collecting_and_queue()

	# Si hay triggers, resolverlos — con 'await': sin esto, esta función
	# volvía a quien la llamó apenas EMPEZABA a resolver, no cuando terminaba
	# (ese era el resto del bug de Drácula/Signo Amarillo resolviendo fases
	# después de jugarse — la cadena de espera se cortaba justo aquí).
	#
	# EXCEPTO si esta recolección fue anidada (ver guardia de reentrada más
	# arriba): en ese caso NO se llama a resolve_all_triggers() de nuevo —
	# el bucle externo que nos contiene (TriggerResolution.resolve_all_
	# triggers, un 'while not trigger_queue.is_empty()') ya sigue drenando
	# la cola sola y va a recoger lo que acabamos de encolar en su próxima
	# vuelta, apenas esta cadena de await retorne. Lanzar OTRO
	# resolve_all_triggers() aquí competiría por la misma cola compartida.
	if not is_nested_reentry and has_pending_triggers():
		await resolve_all_triggers()


## "Cuando ataques" es del jugador, no de la carta: también dispara en las cartas que no atacan
## (Oros como bullnax o amuleto de oso, Armas como espada colmillo, Aliados que se quedan). Una vez por
## ataque, después del "cuando ataque" de cada atacante (que ya cubre a los atacantes con este texto).
## Sable de Napoleón y Estación Fantasma tienen su propio camino (GameManager / InPlayAbilities).
const PLAYER_ATTACK_SKIP := ["cuando ataques con tres o mas aliados", "cuando ataques, elige hasta dos aliados con furia"]


func resolve_player_attack_triggers(player_id: int, attackers: Array) -> void:
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	var waited := 0.0
	while (is_collecting or is_resolving) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var candidates: Array = []
	var containers: Array = PlayerSideScript.line_containers(main, player_id)
	containers.append(PlayerSideScript.gold_reserva(main, player_id))
	containers.append(PlayerSideScript.oro_pagado(main, player_id))
	for container in containers:
		if not container:
			continue
		for c in container.get_children():
			if not is_instance_valid(c):
				continue
			candidates.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w):
						candidates.append(w)
	var event_data := {"player_id": player_id}
	begin_collecting()
	for c in candidates:
		if c in attackers or not c.has_method("has_trigger") or not c.has_trigger("on_attack"):
			continue
		var t := CemeteryTriggersScript.normalize(str(c.get("card_ability")))
		if not ("cuando ataques" in t) or PLAYER_ATTACK_SKIP.any(func(p): return p in t):
			continue
		if _check_trigger_conditions(c, "on_attack", event_data):
			register_trigger(c, "on_attack", event_data)
	await end_collecting_and_queue()
	if has_pending_triggers():
		await resolve_all_triggers()


func resolve_turn_end_triggers(player_id: int) -> void:
	"""Dispara "En tu Fase Final" / "Al final del turno" (on_turn_end) en cada carta del jugador que
	lo tenga (p.ej. Espada de O'Higgins). Llamar al entrar a Fase Final, antes del robo/límite de
	mano (PhaseFlowController._resolve_fase_final()). Es un evento de fase (varias cartas a la
	vez), no un event_card puntual, así que no pasa por _collect_triggers_for_event(); reusa
	begin_collecting/register_trigger/end_collecting_and_queue/resolve_all_triggers."""
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	# Incluye la Reserva y el Oro Pagado: un Oro también puede tener "En tu Fase Final" (p.ej.
	# Tamales).
	var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
			main.player_gold, main.player_oro_pagado] if player_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo,
			main.opponent_gold, main.opponent_oro_pagado]

	var waited := 0.0
	while (is_collecting or is_resolving) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if is_collecting or is_resolving:
		push_warning("[TriggerSystem] is_collecting/is_resolving atascado >3s en resolve_turn_end_triggers — forzando reset")
		is_collecting = false
		is_resolving = false

	begin_collecting()
	var event_data := {"player_id": player_id}
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or not card.has_method("has_trigger"):
				continue
			if card.has_trigger("on_turn_end") and _check_trigger_conditions(card, "on_turn_end", event_data):
				register_trigger(card, "on_turn_end", event_data)
			var weapons = card.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and w.has_method("has_trigger") and w.has_trigger("on_turn_end") \
							and _check_trigger_conditions(w, "on_turn_end", event_data):
						register_trigger(w, "on_turn_end", event_data)

	# "En la Fase Final oponente" (p.ej. Biblioteca de Caballería): dispara sobre las cartas del otro
	# jugador, para quien esta es la Fase Final de su oponente.
	var opponent_id: int = 1 - player_id
	var opponent_fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
			main.player_gold, main.player_oro_pagado] if opponent_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo,
			main.opponent_gold, main.opponent_oro_pagado]
	var opponent_event_data := {"player_id": opponent_id}
	for field in opponent_fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or not card.has_method("has_trigger"):
				continue
			if card.has_trigger("on_opponent_turn_end") and _check_trigger_conditions(card, "on_opponent_turn_end", opponent_event_data):
				register_trigger(card, "on_opponent_turn_end", opponent_event_data)

	await end_collecting_and_queue()

	if has_pending_triggers():
		await resolve_all_triggers()
	# miroku (Destierro) y Los Señalados ("En la Fase Final").
	await load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").turn_end_extras(main, player_id)


func resolve_agrupacion_triggers(player_id: int) -> void:
	"""Dispara "En tu Agrupación" (on_agrupacion) en cada carta del jugador que lo tenga (p.ej. Espada
	del Juicio). Llamar al entrar a Agrupación (PhaseFlowController). Mismo patrón que
	resolve_turn_end_triggers(): evento de fase."""
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if player_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]

	var waited := 0.0
	while (is_collecting or is_resolving) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if is_collecting or is_resolving:
		push_warning("[TriggerSystem] is_collecting/is_resolving atascado >3s en resolve_agrupacion_triggers — forzando reset")
		is_collecting = false
		is_resolving = false

	begin_collecting()
	var event_data := {"player_id": player_id}
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or not card.has_method("has_trigger"):
				continue
			if card.has_trigger("on_agrupacion") and _check_trigger_conditions(card, "on_agrupacion", event_data):
				register_trigger(card, "on_agrupacion", event_data)
			# "Al comienzo del turno" (on_turn_start, p.ej. manuel rodriguez): mismo momento que Agrupación,
			# así que se dispara desde aquí. El turno 1 salta Agrupación, así que el on_turn_start del primer
			# jugador no dispara ese turno. Solo si alguna oración vale en este turno ("al comienzo del turno
			# oponente" de ngenechen no dispara en el tuyo).
			if card.has_trigger("on_turn_start") \
					and not CardQuery.turn_start_clause(str(card.get("card_ability")), true).is_empty() \
					and _check_trigger_conditions(card, "on_turn_start", event_data):
				register_trigger(card, "on_turn_start", event_data)
			var weapons = card.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and w.has_method("has_trigger") and w.has_trigger("on_agrupacion") \
							and _check_trigger_conditions(w, "on_agrupacion", event_data):
						register_trigger(w, "on_agrupacion", event_data)
	# "Al comienzo del turno" sin "tu" (manuel rodriguez): también dispara al comienzo del turno del
	# oponente.
	var other_fields = [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo] if player_id == 0 \
		else [main.player_field, main.player_linea_ataque, main.player_linea_apoyo]
	for field in other_fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or not card.has_method("has_trigger") or not card.has_trigger("on_turn_start"):
				continue
			# "al comienzo del turno" a secas o "del turno oponente" (Carcosa tiene las dos en oraciones
			# distintas).
			if CardQuery.turn_start_clause(str(card.get("card_ability")), false).is_empty():
				continue
			if _check_trigger_conditions(card, "on_turn_start", event_data):
				register_trigger(card, "on_turn_start", event_data)
	# Oros (Reserva y Oro Pagado): los recorridos de arriba solo miran las líneas. "Al comienzo del turno"
	# de los dos jugadores (Medalla de Santa Muerte, kamidana, kagura suzu) y "En tu Agrupación" del
	# jugador del turno (torii).
	for gold_owner in [player_id, 1 - player_id]:
		for gold_field in [PlayerSide.gold_reserva(main, gold_owner), PlayerSide.oro_pagado(main, gold_owner)]:
			if not gold_field:
				continue
			for card in gold_field.get_children():
				if not is_instance_valid(card) or not card.has_method("has_trigger"):
					continue
				if gold_owner == player_id and card.has_trigger("on_agrupacion") \
						and _check_trigger_conditions(card, "on_agrupacion", event_data):
					register_trigger(card, "on_agrupacion", event_data)
				if card.has_trigger("on_turn_start") \
						and not CardQuery.turn_start_clause(str(card.get("card_ability")), gold_owner == player_id).is_empty() \
						and _check_trigger_conditions(card, "on_turn_start", event_data):
					register_trigger(card, "on_turn_start", event_data)
	await end_collecting_and_queue()

	if has_pending_triggers():
		await resolve_all_triggers()
	# origenes: "En tu Agrupación, puedes Descartar una carta para subirlo de tu Cementerio a tu mano".
	await load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").agrupacion_cemetery_extras(main, player_id)
	# la esmeralda: "Al comienzo de cada turno" — Arma equipada, en los dos turnos.
	await load("res://scripts/core/effects/mechanics/TurnStartPatterns.gd").on_turn_start()


func resolve_ataque_triggers(player_id: int) -> void:
	"""Dispara "Al comienzo del Ataque" (on_ataque_start, p.ej. almirante akari). Llamar al entrar a
	la fase de Ataque (PhaseFlowController). Mismo patrón que resolve_agrupacion_triggers()."""
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if player_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]

	var waited := 0.0
	while (is_collecting or is_resolving) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if is_collecting or is_resolving:
		push_warning("[TriggerSystem] is_collecting/is_resolving atascado >3s en resolve_ataque_triggers — forzando reset")
		is_collecting = false
		is_resolving = false

	begin_collecting()
	var event_data := {"player_id": player_id}
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or not card.has_method("has_trigger"):
				continue
			if card.has_trigger("on_ataque_start") and _check_trigger_conditions(card, "on_ataque_start", event_data):
				register_trigger(card, "on_ataque_start", event_data)
	await end_collecting_and_queue()

	if has_pending_triggers():
		await resolve_all_triggers()


func resolve_vigilia_triggers(player_id: int) -> void:
	"""Dispara "En tu Vigilia" (on_vigilia) en cada carta del jugador que lo tenga (p.ej. Mariano
	Osorio: "En tu Vigilia o Fase Final, Destierra hasta tres cartas del Cementerio oponente").
	Llamar al entrar a Vigilia (PhaseFlowController). Mismo patrón que
	resolve_agrupacion_triggers()."""
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	# Con los Oros: "Al comienzo de tu Vigilia" de un Oro (salmon del saber, shakuhachi, armadura imperial...).
	var fields = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo, main.player_gold, main.player_oro_pagado] if player_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo, main.opponent_gold, main.opponent_oro_pagado]

	var waited := 0.0
	while (is_collecting or is_resolving) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if is_collecting or is_resolving:
		push_warning("[TriggerSystem] is_collecting/is_resolving atascado >3s en resolve_vigilia_triggers — forzando reset")
		is_collecting = false
		is_resolving = false

	begin_collecting()
	var event_data := {"player_id": player_id}
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or not card.has_method("has_trigger"):
				continue
			if card.has_trigger("on_vigilia") and _check_trigger_conditions(card, "on_vigilia", event_data):
				register_trigger(card, "on_vigilia", event_data)
			var weapons = card.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and w.has_method("has_trigger") and w.has_trigger("on_vigilia") \
							and _check_trigger_conditions(w, "on_vigilia", event_data):
						register_trigger(w, "on_vigilia", event_data)
	await end_collecting_and_queue()

	if has_pending_triggers():
		await resolve_all_triggers()
	# pulsera de energia (Cementerio) y París (Vigilia oponente): fuera del campo del jugador activo.
	await load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").vigilia_start_extras(main, player_id)
	# compendium maleficarum, gumyocho (Cementerio), veinte mil leguas (cualquier Vigilia).
	await load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").vigilia_cemetery_extras(main, player_id)


func _get_related_triggers(event_type: String, event_card: Node) -> Array:
	"""Retorna triggers relacionados que se activan con un evento"""
	var related: Array = []

	# Si una carta entra al juego y es un aliado
	if event_type == "on_enter_play":
		if event_card and event_card.get("card_type") == Constants.CardType.ALIADO:
			related.append("on_ally_enters")

	# Si una carta es destruida y es un aliado
	if event_type == "on_destroyed":
		if event_card and event_card.get("card_type") == Constants.CardType.ALIADO:
			related.append("on_ally_dies")

	return related


func _check_trigger_conditions(card: Node, trigger_type: String, event_data: Dictionary) -> bool:
	"""Verifica las condiciones del trigger"""
	if KeywordManager.is_silenced(card):
		return false
	if _named_trigger_already_used_this_turn(card):
		return false
	# Tamales ("tu oponente... ni disparar"): el mismo chequeo que _validate_ability() hace para
	# habilidades activadas, aquí para disparadas. No bloquea auras ni efectos continuos.
	if not ContinuousEffectManager.tamales_ability_restriction_reason(card).is_empty():
		return false
	if card.has_method("_trigger_conditions_met"):
		return card._trigger_conditions_met(trigger_type, event_data)
	return true


func _named_trigger_already_used_this_turn(card: Node) -> bool:
	""""Solo puedes utilizar la habilidad de X una vez por turno" aplicado a un trigger (p.ej. Tangata
	Manu: su "Cuando entra en juego" puede jugar otra copia de sí mismo, que volvería a
	dispararse). El límite es por nombre, compartido entre todas las copias. Todo trigger pasa por
	aquí antes de encolarse (register_trigger()), así que basta con chequear y registrar aquí."""
	if card.get("card_data") == null:
		return false
	var habilidad_text: String = card.card_data.get("habilidad", "")
	if habilidad_text.is_empty():
		return false
	var card_id: String = str(card.card_data.get("id", ""))
	var all_parsed := UniversalCardParser.parse_abilities(habilidad_text, card_id)
	var has_named_once_trigger := false
	for entry in all_parsed:
		if entry.get("ability_type", "") == "TRIGGER" and entry.get("once_per_turn", false):
			has_named_once_trigger = true
			break
	if not has_named_once_trigger:
		return false

	var card_name: String = str(card.card_data.get("nombre", "")).to_lower()
	if card_name.is_empty():
		return false
	# Prefijo 'trigger_once:' para no mezclarse con las claves de habilidades activadas
	# (card_id/ability_index).
	var name_key: String = "trigger_once:%s" % card_name
	var turn: int = GameManager.turn_serial
	if UniversalCardParser.turn_registry.was_used(name_key, 0, turn):
		return true
	UniversalCardParser.turn_registry.register(name_key, 0, turn)
	return false


# =============================================================================
# EFECTOS CONTINUOS Y PRIORIDAD NEGATIVA (implementación en
# TriggerRestrictions.gd)
# =============================================================================
func register_continuous_effect(source_card: Node, effect: Dictionary) -> void:
	_restrictions.register_continuous_effect(source_card, effect)


func unregister_continuous_effect(source_card: Node) -> void:
	_restrictions.unregister_continuous_effect(source_card)


func get_active_continuous_effects(filter_type: String = "") -> Array:
	return _restrictions.get_active_continuous_effects(filter_type)


func check_continuous_prevention(action_type: String, target: Node = null) -> Dictionary:
	return _restrictions.check_continuous_prevention(action_type, target)


# =============================================================================
# UTILIDADES PARA CALLABLE EN CARTAS
# =============================================================================
func bind_card_to_triggers(card: Node) -> void:
	"""Vincula una carta al sistema de triggers cuando entra al juego
	Llama a _on_trigger_event de la carta con Callable
	"""
	if not card.has_method("_on_trigger_event"):
		return

	# Parsear triggers del texto de habilidad
	if card.has_method("parse_triggers_from_ability"):
		card.parse_triggers_from_ability()

	if Constants.VERBOSE_DIAG_LOGS:
		print("[TriggerSystem] Carta %s vinculada al sistema de triggers" % card.card_name)


# =============================================================================
# SISTEMA DE BUFFS/DEBUFFS TEMPORALES (implementación en
# TemporaryBuffSystem.gd)
# =============================================================================
func apply_buff(source: Node, target: Node, buff_type: String, value: int, duration: String = "this_turn") -> Dictionary:
	return _buffs.apply_buff(source, target, buff_type, value, duration)


func remove_buff(buff_id: String) -> bool:
	return _buffs.remove_buff(buff_id)


func remove_buffs_from_source(source: Node) -> int:
	return _buffs.remove_buffs_from_source(source)


func remove_buffs_from_target(target: Node) -> int:
	return _buffs.remove_buffs_from_target(target)


func clear_expired_buffs(duration: String) -> int:
	return _buffs.clear_expired_buffs(duration)


func get_buffs_on_target(target: Node) -> Array[Dictionary]:
	return _buffs.get_buffs_on_target(target)


func get_total_modifier(target: Node, buff_type: String) -> int:
	return _buffs.get_total_modifier(target, buff_type)


func has_buff_type(target: Node, buff_type: String) -> bool:
	return _buffs.has_buff_type(target, buff_type)


# =============================================================================
# FORWARDERS - TargetedEffectExecutor
# =============================================================================


func open_response_window(source_card: Node, description: String, controller_id: int) -> bool:
	"""Punto de entrada de la Pila de Respuesta Universal
	(docs/plans/2026-09-09-pila-respuesta-universal-design.md) para los patrones de trigger: se
	llama cuando ya se declaró todo (objetivos/modo) y falta ejecutar el efecto.
	Empuja a ActionPipeline un objeto sin texto de habilidad resoluble a propósito: si lo tuviera,
	el Paso E llamaría a resolve_ability_effect() y volvería a calzar el mismo patrón (recursión
	infinita). El Paso E es un no-op; lo que importa es el Paso D (ventana de prioridad para el
	rival).
	Devuelve true si el llamador debe abortar su efecto (anulado/cancelado); false si sigue."""
	if not is_instance_valid(source_card):
		return false
	# Una sola ventana por efecto (§59): si la pide la carta del efecto en curso y el rival ya tuvo su
	# ventana, no se abre otra. Si estaba pendiente, esta es la ventana (después de declarar
	# objetivos).
	var ctx: Dictionary = EffectContextScript.current()
	var tracked: bool = not ctx.is_empty() and ctx.get("card") == source_card
	if tracked:
		if ctx.window == "done":
			return false
		if ctx.window == "cancelled":
			return true
		description = "efecto de %s (%s)" % [ctx.card_name, ctx.kind]
	var ability_data: Dictionary = {"name": description}
	var source_data: Dictionary = source_card.card_data if source_card.get("card_data") else {}
	var context: Dictionary = {
		"controller_id": controller_id,
		"source_card_node": source_card,
		# Qué es esta ventana (StackAnnul): "carta" = carta jugada (Aliado/Arma/Tótem/Oro, se Anula),
		# "Talismán" (se Anula), "disparada"/"activada" (habilidades, se Cancelan).
		"window_kind": str(ctx.kind) if tracked else "carta",
	}
	# Crono Diamante cuenta también las disparadas de Oros (las activadas: ActionPipeline.activate_ability()).
	if tracked and str(ctx.kind) == "disparada" \
			and load("res://scripts/core/effects/mechanics/ProtectionRules.gd").note_gold_ability_use(source_card, controller_id):
		context["_first_gold_ability"] = true
	var outcome: Dictionary = await ActionPipeline.add_triggered_ability_to_stack_and_await(ability_data, source_data, context)
	var stopped: bool = outcome.get("annulled", false) or outcome.get("cancelled", false)
	if tracked:
		ctx.window = "cancelled" if stopped else "done"
	if stopped:
		await AllyEventTriggersScript.on_stopped(source_card, controller_id, str(context.window_kind))  # "Si es Anulado, ..."
	return stopped


func resolve_ability_effect(card: Node, effect_text: String, controller_id: int) -> bool:
	"""Resuelve el texto de efecto de una habilidad, disparada o activada.
	StackStepResolver._resolve_ability() (habilidades activadas vía ActionPipeline) lo usa para que
	las activadas tengan los mismos patrones compuestos ("mira/muestra N...") que las disparadas:
	las dos comparten _resolve_look_and_play_patterns(). Devuelve true si se ejecutó algo."""
	return await _resolution._resolve_look_and_play_patterns(card, effect_text, effect_text, controller_id, {})


func _select_hand_cards_for_discard(hand_cards: Array, amount: int, chooser_id: int = 0) -> Array:
	return await _targeted_executor._select_hand_cards_for_discard(hand_cards, amount, chooser_id)
