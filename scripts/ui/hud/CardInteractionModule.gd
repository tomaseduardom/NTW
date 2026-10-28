extends Node
class_name CardInteractionModule
## CardInteractionModule — Gestiona clicks, hover y arrastre de cartas.
## Se instancia como hijo de Main en _ready().

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const BlockScript = preload("res://scripts/core/effects/triggers/BlockPatterns.gd")  # bloquear a varios (Elías)
const _Rules = preload("res://scripts/core/effects/mechanics/ProtectionRules.gd")  # Oro adicional por afectar

var _main: Node = null

var selected_card: Node = null
var is_placing_gold: bool = false
var _card_clicked_this_frame: bool = false
var _opponent_card_original_pos: Dictionary = {}
## Traba de reentrada por carta para _declare_attacker(): es async con varios await antes de
## GameManager.attackers.append(), y un segundo click (p.ej. el eco de card_double_clicked) podía
## entrar en paralelo y quedar rechazado con "no puede atacar todavía".
var _declaring_attackers: Dictionary = {}

# =============================================================================
# SELECCIÓN DE OBJETIVO — usado por efectos que apuntan a UNA carta en juego
# (dar fuerza, silenciar, anular/destruir dirigido). Mismo patrón que
# is_placing_gold: se activa un "modo", y el próximo click en una carta que
# pase el filtro resuelve la acción pendiente en vez de abrir la selección
# normal de carta.
# =============================================================================
var is_selecting_target: bool = false
var _target_filter: Callable = Callable()
var _target_callback: Callable = Callable()
## Si es false, ESC no cancela la selección en curso: una selección obligatoria (p.ej. "Descarta N
## cartas" sin "puedes") no se esquiva como un costo opcional (arquitectura.md §10.29).
var _selection_cancellable: bool = true
## "Seleccionar todo" para await_multi_target() (p.ej. Abrazo de Maipú) — ver request_select_all().
var _select_all_requested: bool = false
## Debounce del eco de doble-click (ver _resolve_target_selection): un
## double-click real dispara PRIMERO card_clicked (press 1) y LUEGO
## card_double_clicked (press 2, mismo gesto) — si press 1 ya resolvió la
## selección, press 2 no debe caer en "Solo puedes jugar cartas de la mano".
var _last_resolved_target: Node = null
var _last_resolved_at_ms: int = -100000
## Cartas a las que start_target_selection() les forzó can_interact = true. Card.on_gui_input()
## corta el click izquierdo si can_interact es false, así que una carta rival no interactiva no
## llegaba nunca a _on_card_clicked() (ni filtro ni mensaje). Se guardan para devolverlas a su
## estado al cerrar la selección (nunca se toca una que ya estaba en true).
var _forced_interact_cards: Array = []
## Cartas con el brillo de "objetivo válido" de una selección de un solo objetivo, para distinguir a
## simple vista "no hay objetivo válido" de un fallo de targeting. Ver
## _glow_valid_targets()/_unglow_target_cards().
var _glowing_target_cards: Array = []
## Puente para selecciones cuyos candidatos del Cementerio no viven en un contenedor real (nodos
## temporales, p.ej. Lobo Sagrado en
## WeaponSearchShuffleExecutor._execute_play_weapon_discount_draw()).
## ZoneViewerModule._on_exhumar_card_clicked() los consulta antes de intentar Exhumar: si el
## card_data clickeado coincide, resuelve la selección pendiente.
var _cemetery_target_nodes: Array = []


func try_resolve_cemetery_click(card_data: Dictionary) -> bool:
	"""Ver _cemetery_target_nodes arriba. Devuelve true si el click se
	resolvió como parte de una selección de objetivo pendiente (el
	llamador no debe seguir con su propia lógica de Exhumar/etc.)."""
	if not is_selecting_target or _cemetery_target_nodes.is_empty():
		return false
	for c in _cemetery_target_nodes:
		if is_instance_valid(c) and c.get("card_data") == card_data:
			_resolve_target_selection(c)
			return true
	return false


func setup(main: Node) -> void:
	_main = main
	_watch_attack_lines.call_deferred()


# -----------------------------------------------------------------------------
# Aliados en la Línea de Ataque que no están atacando (movidos por un efecto: akashi, Batallón de
# Ovejas; meta "idle_attack_line"): tono azul hielo. Los que atacaron siguen ahí hasta su Agrupación
# y no cuentan. Lo calcula el Anfitrión (o la partida local) y el Remoto recibe la lista
# (GameStateBroadcaster, op "idle_attack_cards").
# -----------------------------------------------------------------------------
const IDLE_ATTACK_TINT := Color(0.78, 0.93, 1.0, 1.0)
signal idle_attack_changed(card_ids: Array)
var _idle_tinted: Dictionary = {}
var _idle_refresh_queued: bool = false


func _watch_attack_lines() -> void:
	if not _main or (NetworkClient.room_code != "" and not NetworkClient.is_host):
		return  # Remoto: aplica la lista del Anfitrión (RemoteMirrorController)
	for line in [_main.get("player_linea_ataque"), _main.get("opponent_linea_ataque")]:
		if line:
			line.child_entered_tree.connect(func(_n): queue_idle_attack_refresh())
			line.child_exiting_tree.connect(func(_n): queue_idle_attack_refresh())
	BattleManager.combat_finished.connect(func(_r) -> void:
		# después del tween de "dejar de bloquear" (0.2 s), que deja el color en blanco
		await get_tree().create_timer(0.3).timeout
		queue_idle_attack_refresh())


func queue_idle_attack_refresh() -> void:
	if _idle_refresh_queued:
		return
	_idle_refresh_queued = true
	_refresh_idle_attack_tint.call_deferred()


func _refresh_idle_attack_tint() -> void:
	_idle_refresh_queued = false
	if not _main:
		return
	var now: Dictionary = {}
	for line in [_main.get("player_linea_ataque"), _main.get("opponent_linea_ataque")]:
		if not line:
			continue
		for c in line.get_children():
			if is_instance_valid(c) and c.get_meta("idle_attack_line", false) and c.get("card_type") == Constants.CardType.ALIADO 					and not (c in GameManager.attackers) and not (c in GameManager.blockers.values()):
				now[c] = true
	for c in _idle_tinted:
		if not now.has(c) and is_instance_valid(c):
			if c.modulate == IDLE_ATTACK_TINT:
				c.modulate = Color.WHITE
			if c.get("current_zone") != Constants.Zone.LINEA_ATAQUE or c in GameManager.attackers:
				c.remove_meta("idle_attack_line")  # salió de la Línea de Ataque o pasó a atacar
	for c in now:
		c.modulate = IDLE_ATTACK_TINT
	_idle_tinted = now
	idle_attack_changed.emit(now.keys().map(func(c): return str(c.get_instance_id())))


func _force_board_interactable() -> void:
	"""Fuerza can_interact=true en toda carta de campo (ambos jugadores,
	Línea de Defensa/Ataque/Apoyo + Reserva/Pagado de Oro) que no lo tuviera
	ya, mientras dura una selección de objetivo. Barrido amplio a propósito
	(no evalúa el filtro aquí): el filtro real se sigue aplicando en
	_resolve_target_selection() al clickear, así que forzar de más solo
	habilita el click en cartas que de todos modos van a ser rechazadas con
	el mensaje normal — evita mantener una lista paralela de contenedores
	por cada llamador distinto de await_target()/await_multi_target()."""
	if not _main:
		return
	var containers: Array = []
	for name in ["player_field", "player_linea_ataque", "player_linea_apoyo",
			"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo",
			"player_gold", "opponent_gold", "player_oro_pagado", "opponent_oro_pagado"]:
		var container = _main.get(name)
		if container:
			containers.append(container)
	for container in containers:
		for c in container.get_children():
			if is_instance_valid(c) and c.get("can_interact") == false:
				c.can_interact = true
				_forced_interact_cards.append(c)


func _restore_board_interactable() -> void:
	"""Contraparte de _force_board_interactable() — se llama al cerrar la
	selección (objetivo resuelto, cancelado, o 'seleccionar todo')."""
	for c in _forced_interact_cards:
		if is_instance_valid(c):
			c.can_interact = false
	_forced_interact_cards.clear()


func _glow_color_for_owner(c: Node) -> Color:
	"""Celeste para tus cartas, rojo para las del rival: el color dice de quién es el objetivo de un
	vistazo."""
	if c.get("owner_id") == 0:
		return CardBadges.GLOW_COLOR_CELESTE
	return CardBadges.GLOW_COLOR_RED


func _glow_valid_targets(filter: Callable) -> void:
	"""Prende el brillo de "objetivo válido" (CardBadges.set_activatable(), como await_multi_target())
	en cada candidato real de una selección de un solo objetivo. Color según dueño
	(_glow_color_for_owner()).
	A diferencia de _force_board_interactable(), aquí sí se evalúa el filtro; es solo visual. Barre
	las 10 zonas del tablero más la mano/abanico rival (await_target() también elige cartas de la
	mano, p.ej. Golpe Solar)."""
	if not filter.is_valid() or not _main:
		return
	for name in ["player_field", "player_linea_ataque", "player_linea_apoyo",
			"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo",
			"player_gold", "opponent_gold", "player_oro_pagado", "opponent_oro_pagado"]:
		var container = _main.get(name)
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and c.has_method("set_activatable") and filter.call(c):
				c.set_activatable(true, _glow_color_for_owner(c), &"target_select")
				_glowing_target_cards.append(c)
	for hand_name in ["player_hand", "_opponent_fan"]:
		var hand = _main.get(hand_name)
		if not hand or not hand.get("cards"):
			continue
		for c in hand.cards:
			if is_instance_valid(c) and c.has_method("set_activatable") and filter.call(c):
				c.set_activatable(true, _glow_color_for_owner(c), &"target_select")
				_glowing_target_cards.append(c)


func _unglow_target_cards() -> void:
	"""Contraparte de _glow_valid_targets() — apaga el brillo de todo lo que
	se prendió, sin importar si el objetivo se resolvió o se canceló."""
	for c in _glowing_target_cards:
		if is_instance_valid(c) and c.has_method("set_activatable"):
			c.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
	_glowing_target_cards.clear()


func request_select_all() -> void:
	"""Llamar desde un botón "Seleccionar todo" mientras await_multi_target()
	está esperando un click — en el próximo frame, todo lo que quede
	elegible (respetando lock_group_key/dynamic_filter si están activos)
	se toma de una sola vez. No hace nada si no hay una selección múltiple
	en curso (la próxima vuelta del while de await_multi_target() consume
	el flag; si nadie lo hace, se pierde en silencio, sin efecto)."""
	_select_all_requested = true


func start_target_selection(prompt: String, filter: Callable, on_selected: Callable, cancellable: bool = true) -> void:
	"""Activa el modo de selección de objetivo. filter: Callable(card) -> bool (objetivo legal).
	on_selected: Callable(card), se llama con la carta elegida. cancellable: false para selecciones
	obligatorias (ESC no hace nada).
	Suprime el auto-pase de prioridad (PriorityManager.suppress_human_autopass) mientras hay una
	selección pendiente: si no, PhaseFlowController._human_pass_after() pasaba la prioridad por
	debajo y la ventana quedaba colgada."""
	is_selecting_target = true
	_target_filter = filter
	_target_callback = on_selected
	_selection_cancellable = cancellable
	_force_board_interactable()
	PriorityManager.suppress_human_autopass = true
	_main._update_debug(prompt)


func await_target(prompt: String, filter: Callable, cancellable: bool = true, chooser_id: int = 0) -> Node:
	"""Elige un objetivo (ver _await_target_raw()). Oro adicional por afectar cartas del rival
	(ProtectionRules.affect_tax: manuel rodriguez, Sake): lo que no se puede pagar no es elegible, y
	se paga recién cuando el rival cede su prioridad (_pay_affect_tax())."""
	var verb: String = _Rules.verb_of(prompt)
	var taxed := _affordable_filter(filter, chooser_id, verb)
	var chosen: Node = await _await_target_raw(prompt, taxed, cancellable, chooser_id)
	if chosen and not await _pay_affect_tax([chosen], chooser_id, verb):
		return null
	return chosen


func _affordable_filter(filter: Callable, chooser_id: int, verb: String = "") -> Callable:
	return func(c: Node) -> bool:
		if not filter.call(c):
			return false
		var tax: int = _Rules.affect_tax(c, chooser_id, verb)
		return tax <= 0 or (_main and _main._gold_manager and _main._gold_manager.puede_pagar(tax, -1, "", -1, chooser_id))


func _pay_affect_tax(cards: Array, chooser_id: int, verb: String = "") -> bool:
	"""Elegir el objetivo (Pasos A-B) todavía no lo afecta: el Oro adicional se paga cuando el rival
	cede su prioridad sin responder. Por eso abre antes la ventana de respuesta del efecto en curso
	(EffectContext.ensure_window(); si ya pasó, como en las activadas, no abre otra). false si el
	efecto quedó anulado/cancelado o no se pudo pagar: la carta no se ve afectada."""
	var tax := 0
	for c in cards:
		tax += _Rules.affect_tax(c, chooser_id, verb)
	if tax <= 0:
		return true
	if await EffectContextScript.ensure_window():
		return false
	tax = 0
	for c in cards:
		if is_instance_valid(c):
			tax += _Rules.affect_tax(c, chooser_id, verb)
	if tax <= 0:
		return true
	var ok: bool = await PlayerSideScript.pay(_main, chooser_id, tax)
	if ok and _main and _main.has_method("_update_debug"):
		_main._update_debug("Oro adicional por afectar: %d" % tax)
	return ok


func _await_target_raw(prompt: String, filter: Callable, cancellable: bool = true, chooser_id: int = 0) -> Node:
	"""Envoltorio de start_target_selection() que espera la respuesta. Devuelve la carta elegida, o
	null si se canceló (ESC) o no se pudo abrir. Estado en un Dictionary porque los lambdas de
	GDScript capturan las variables locales por valor.
	chooser_id: si elige el jugador 1 y hay un Remoto conectado, se delega por red (paridad remota,
	docs/plans/2026-09-20-remote-multiplayer-parity.md)."""
	if not is_instance_valid(self):
		return null
	EffectContextScript.check_chooser(chooser_id, prompt)
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		return await _delegate_target_to_remote(prompt, filter, cancellable)
	if PlayerSideScript.is_bot(chooser_id):
		var picks := _bot_pick(prompt, _board_and_hand_cards().filter(func(c): return filter.call(c)), 1, chooser_id)
		return null if picks.is_empty() else picks[0]
	var state := {"done": false, "chosen": null}
	var on_selected := func(c: Node) -> void:
		state.chosen = c
		state.done = true
	start_target_selection(prompt, filter, on_selected, cancellable)
	# Brillo en cada candidato real (_glow_valid_targets()). Solo aquí y no en
	# start_target_selection(): await_multi_target() la usa por dentro con su propio brillo por
	# lock_group_key/dynamic_filter.
	_glow_valid_targets(filter)
	while not state.done:
		await get_tree().process_frame
	return state.chosen


## Verbos que perjudican a la carta elegida: el bot elige primero las del rival. Si no, las propias.
const _BOT_HARMFUL := ["destru", "destierr", "desterr", "baraj", "descart", "anul", "pierd", "pierde", "bota",
	"sube", "devuelv", "convier", "fuerza 0", "no pueda", "silenc", "ganar el control"]


func _bot_pick(prompt: String, candidates: Array, count: int, chooser_id: int) -> Array:
	"""Elección del bot local (jugador 1 sin sala) en await_target()/await_multi_target(): en vez de
	esperar un clic del Anfitrión, ordena los candidatos (del rival primero si el efecto perjudica,
	los propios primero si beneficia) y toma los primeros 'count'."""
	var lower := prompt.to_lower()
	var harmful := false
	for w in _BOT_HARMFUL:
		if w in lower:
			harmful = true
			break
	var rival: Array = []
	var own: Array = []
	for c in candidates:
		var ctrl: int = int(c.controller_id) if c.get("controller_id") != null else (int(c.owner_id) if c.get("owner_id") != null else 0)
		(own if ctrl == chooser_id else rival).append(c)
	var ordered: Array = (rival + own) if harmful else (own + rival)
	return ordered.slice(0, maxi(count, 0))


func _board_and_hand_cards() -> Array:
	var out: Array = []
	for prop in ["player_field", "player_linea_ataque", "player_linea_apoyo", "player_gold", "player_oro_pagado",
			"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo", "opponent_gold", "opponent_oro_pagado"]:
		var zone = _main.get(prop)
		if zone:
			for c in zone.get_children():
				if is_instance_valid(c):
					out.append(c)
					var weapons = c.get("equipped_weapons")
					if weapons is Array:
						for w in weapons:
							if is_instance_valid(w):
								out.append(w)
	for h in [_main.player_hand, _main.get("_opponent_fan")]:
		if h and h.get("cards") != null:
			out.append_array(h.cards.filter(func(c): return is_instance_valid(c)))
	return out


func await_multi_target(prompt_prefix: String, candidates: Array, max_count: int = -1, lock_group_key: Callable = Callable(), dynamic_filter: Callable = Callable(), cancellable: bool = true, glow_color_override = null, chooser_id: int = 0) -> Array:
	"""Ver _await_multi_target_raw(). Con Oro adicional por afectar (ver await_target()): quedan
	afuera las que no se pueden pagar y, si al final no alcanza, las gravadas."""
	var verb: String = _Rules.verb_of(prompt_prefix)
	var affordable := _affordable_filter(func(_x): return true, chooser_id, verb)
	var pool: Array = candidates.filter(func(c): return not is_instance_valid(c) or affordable.call(c))
	var chosen: Array = await _await_multi_target_raw(prompt_prefix, pool, max_count, lock_group_key, dynamic_filter,
		cancellable, glow_color_override, chooser_id)
	if not await _pay_affect_tax(chosen, chooser_id, verb):
		chosen = chosen.filter(func(c): return _Rules.affect_tax(c, chooser_id, verb) <= 0)
	return chosen


func _await_multi_target_raw(prompt_prefix: String, candidates: Array, max_count: int = -1, lock_group_key: Callable = Callable(), dynamic_filter: Callable = Callable(), cancellable: bool = true, glow_color_override = null, chooser_id: int = 0) -> Array:
	"""Selección de 0 a max_count objetivos (-1 = sin tope) clickeando las cartas reales, sin modal de
	lista. candidates puede mezclar zonas (mano, Cementerio, en juego): el jugador ve dónde está
	cada una.
	lock_group_key: Callable(Node) -> Variant; tras el primer pick, solo candidatos con la misma
	clave (p.ej. Hanta el Samurai: "de UN Cementerio", clave = owner_id).
	dynamic_filter: Callable(chosen, candidate) -> bool, reevaluado en cada click (p.ej.
	Tempilcahue: costes que sumen hasta 4).
	ESC termina con lo ya elegido (no cancela todo). request_select_all() toma de una vez todo lo
	que quede elegible (Abrazo de Maipú: "cualquier cantidad").
	glow_color_override: fuerza un color para todos (p.ej. dorado al elegir el orden de tus
	triggers en TriggerSystem._prompt_trigger_order()); por defecto, celeste/rojo según dueño."""
	var chosen: Array = []
	if not is_instance_valid(self):
		return chosen
	# Remoto: igual que await_target(). lock_group_key/dynamic_filter se aplican al recibir la
	# respuesta (ver _delegate_multi_target_to_remote(); arquitectura.md §43).
	EffectContextScript.check_chooser(chooser_id, prompt_prefix)
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		return await _delegate_multi_target_to_remote(prompt_prefix, candidates, max_count, cancellable, lock_group_key, dynamic_filter)
	if PlayerSideScript.is_bot(chooser_id):
		var ordered := _bot_pick(prompt_prefix, candidates.filter(func(c): return is_instance_valid(c)), candidates.size(), chooser_id)
		for c in ordered:
			if max_count >= 0 and chosen.size() >= max_count:
				break
			if lock_group_key.is_valid() and not chosen.is_empty() and lock_group_key.call(c) != lock_group_key.call(chosen[0]):
				continue
			if dynamic_filter.is_valid() and not dynamic_filter.call(chosen, c):
				continue
			chosen.append(c)
		return chosen
	var glow_of := func(c: Node) -> Color:
		return glow_color_override if glow_color_override != null else _glow_color_for_owner(c)
	var remaining: Array = candidates.duplicate()
	for c in remaining:
		if is_instance_valid(c) and c.has_method("set_activatable"):
			c.set_activatable(true, glow_of.call(c), &"target_select")
	var locked_key = null
	var has_lock: bool = lock_group_key.is_valid()
	var has_dynamic: bool = dynamic_filter.is_valid()
	while (max_count < 0 or chosen.size() < max_count) and not remaining.is_empty():
		var filter := func(c: Node) -> bool:
			if c not in remaining:
				return false
			if has_lock and chosen.size() > 0 and lock_group_key.call(c) != locked_key:
				return false
			if has_dynamic and not dynamic_filter.call(chosen, c):
				return false
			return true
		var count_label: String = " (%d elegidas)" % chosen.size() if chosen.size() > 0 else ""
		var prompt: String = "%s%s%s" % [prompt_prefix, count_label, " — N para terminar" if cancellable else ""]

		var card_state := {"done": false, "chosen": null}
		var on_selected := func(c: Node) -> void:
			card_state.chosen = c
			card_state.done = true
		start_target_selection(prompt, filter, on_selected, cancellable)
		var select_all_triggered := false
		while not card_state.done:
			if _select_all_requested:
				_select_all_requested = false
				select_all_triggered = true
				# Resolver el pick pendiente directo (NO vía cancel_target_
				# selection() — "seleccionar todo" es una acción de UI
				# distinta de "cancelar con ESC" y debe funcionar incluso
				# si esta selección es no-cancelable, ver cancellable arriba).
				is_selecting_target = false
				PriorityManager.suppress_human_autopass = false
				_target_filter = Callable()
				_target_callback = Callable()
				_restore_board_interactable()
				break
			await get_tree().process_frame

		if select_all_triggered:
			for c in remaining.duplicate():
				if max_count >= 0 and chosen.size() >= max_count:
					break
				if not filter.call(c):
					continue  # un candidato que el lock ya había excluido
				if is_instance_valid(c) and c.has_method("set_activatable"):
					c.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
				chosen.append(c)
				remaining.erase(c)
			break

		var picked: Node = card_state.chosen
		if not picked or not is_instance_valid(picked):
			break
		if has_lock and chosen.is_empty():
			locked_key = lock_group_key.call(picked)
			# Apagar el brillo de los candidatos que el lock acaba de excluir.
			for c in remaining:
				if is_instance_valid(c) and c.has_method("set_activatable") and lock_group_key.call(c) != locked_key:
					c.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
		remaining.erase(picked)
		picked.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
		chosen.append(picked)
		if has_dynamic:
			# Re-evaluar el brillo de lo que queda contra el presupuesto YA
			# reducido por este pick — una carta que calzaba antes puede
			# haber dejado de calzar ahora.
			for c in remaining:
				if is_instance_valid(c) and c.has_method("set_activatable"):
					c.set_activatable(dynamic_filter.call(chosen, c), glow_of.call(c), &"target_select")
	for c in remaining:
		if is_instance_valid(c) and c.has_method("set_activatable"):
			c.set_activatable(false, CardBadges.GLOW_COLOR_GOLD, &"target_select")
	return chosen


## Una candidata para un prompt del Remoto: card_data completo, salvo las cartas de la mano del Anfitrión
## (privada): solo su id, boca abajo.
func _remote_candidate_entry(c: Node) -> Dictionary:
	var host_hand = _main.get("player_hand")
	if host_hand and host_hand.get("cards") and c in host_hand.cards:
		return {"card_id": str(c.get_instance_id()), "host_hand_hidden": true, "nombre": "Carta en la mano"}
	var entry: Dictionary = c.card_data.duplicate(true) if c.get("card_data") != null else {}
	entry["card_id"] = str(c.get_instance_id())
	return entry


func _delegate_target_to_remote(prompt: String, filter: Callable, cancellable: bool) -> Node:
	"""Contraparte en red de await_target() — ver _glow_valid_targets() para
	el mismo barrido de las 10 zonas de tablero + mano/abanico rival. A
	diferencia de SelectionManager/ZoneViewerModule, acá las cartas YA son
	Nodos reales y persistentes del tablero (no datos ni Nodos temporales)
	— se identifican por get_instance_id(), mismo criterio que
	RemotePlayerController._card_ref()/_find_card_by_id()."""
	if not filter.is_valid() or not _main:
		return null
	var candidates: Array = []
	for name in ["player_field", "player_linea_ataque", "player_linea_apoyo",
			"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo",
			"player_gold", "opponent_gold", "player_oro_pagado", "opponent_oro_pagado"]:
		var container = _main.get(name)
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and filter.call(c):
				candidates.append(c)
	for hand_name in ["player_hand", "_opponent_fan"]:
		var hand = _main.get(hand_name)
		if not hand or not hand.get("cards"):
			continue
		for c in hand.cards:
			if is_instance_valid(c) and filter.call(c):
				candidates.append(c)
	# Nodos temporales de un popup de Cementerio (p.ej. Lobo Sagrado jugado por el Remoto): no están en
	# el tablero del Remoto, así que se muestran dibujados en el popup
	# (RemoteMirrorController._show_await_target_prompt()).
	for c in _cemetery_target_nodes:
		if is_instance_valid(c) and filter.call(c) and c not in candidates:
			candidates.append(c)
	if candidates.is_empty():
		return null

	# Se manda el card_data completo para que RemoteMirrorController dibuje la carta en vez de un botón
	# de solo texto.
	var payload: Array = []
	for c in candidates:
		var entry: Dictionary = _remote_candidate_entry(c)
		payload.append(entry)
	NetworkClient.send_message({
		"op": "prompt", "kind": "await_target",
		"title": prompt,
		"candidates": payload,
		"cancellable": cancellable,
	})
	var intent: Dictionary = await NetworkClient.await_intent(["await_target_choice"])
	if bool(intent.get("cancelled", false)):
		return null
	var id_str: String = str(intent.get("card_id", ""))
	if id_str.is_empty() or not id_str.is_valid_int():
		return null
	var obj: Object = instance_from_id(int(id_str))
	if obj is Node and is_instance_valid(obj) and obj in candidates:
		return obj
	return null


func _delegate_target_or_castillo_to_remote(prompt: String, filter: Callable, castillo_title: String, allow_cancel: bool, castillo_own_only: bool) -> Dictionary:
	"""Contraparte en red de await_target_or_castillo_pick() (arquitectura.md §41): junta cartas
	candidatas y Castillo propio/rival en un solo prompt, porque del lado del Remoto no hay carrera
	entre dos interacciones. Mismo criterio de identificar candidatas que
	_delegate_target_to_remote()."""
	var candidates: Array = []
	for zone_name in ["player_field", "player_linea_ataque", "player_linea_apoyo",
			"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo",
			"player_gold", "opponent_gold", "player_oro_pagado", "opponent_oro_pagado"]:
		var container = _main.get(zone_name)
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and filter.call(c):
				candidates.append(c)
	for hand_name in ["player_hand", "_opponent_fan"]:
		var hand = _main.get(hand_name)
		if not hand or not hand.get("cards"):
			continue
		for c in hand.cards:
			if is_instance_valid(c) and filter.call(c):
				candidates.append(c)

	var payload: Array = []
	for c in candidates:
		var entry: Dictionary = _remote_candidate_entry(c)
		payload.append(entry)
	NetworkClient.send_message({
		"op": "prompt", "kind": "await_target_or_castillo",
		"title": prompt,
		"candidates": payload,
		"castillo_title": castillo_title,
		"castillo_own_only": castillo_own_only,
		"cancellable": allow_cancel,
	})
	var intent: Dictionary = await NetworkClient.await_intent(["await_target_or_castillo_choice"])
	var kind: String = str(intent.get("type", "none"))
	if kind == "card":
		var id_str: String = str(intent.get("card_id", ""))
		if id_str.is_valid_int():
			var obj: Object = instance_from_id(int(id_str))
			if obj is Node and is_instance_valid(obj) and obj in candidates:
				return {"type": "card", "card": obj}
		return {"type": "none"}
	if kind == "castillo":
		return {"type": "castillo", "own": bool(intent.get("own", true))}
	return {"type": "none"}


func _delegate_multi_target_to_remote(prompt_prefix: String, candidates: Array, max_count: int, cancellable: bool, lock_group_key: Callable = Callable(), dynamic_filter: Callable = Callable()) -> Array:
	"""Contraparte en red de await_multi_target() (identifica por get_instance_id()).
	lock_group_key/dynamic_filter se aplican en el Anfitrión al recibir la respuesta
	(arquitectura.md §43): se recorren los card_ids en orden y se acepta cada uno solo si pasa el
	filtro dado lo ya aceptado. Un pick inválido se descarta sin truncar el resto."""
	var live_candidates: Array = candidates.filter(func(c): return is_instance_valid(c))
	if live_candidates.is_empty():
		return []
	# card_data completo, igual que _delegate_target_to_remote().
	var payload: Array = []
	for c in live_candidates:
		var entry: Dictionary = _remote_candidate_entry(c)
		payload.append(entry)
	NetworkClient.send_message({
		"op": "prompt", "kind": "await_multi_target",
		"title": prompt_prefix,
		"candidates": payload,
		"max_selections": max_count,
		"cancellable": cancellable,
	})
	var intent: Dictionary = await NetworkClient.await_intent(["await_multi_target_choice"])
	var has_lock: bool = lock_group_key.is_valid()
	var has_dynamic: bool = dynamic_filter.is_valid()
	var locked_key = null
	var result: Array = []
	for id_str in intent.get("card_ids", []):
		if not str(id_str).is_valid_int():
			continue
		var obj: Object = instance_from_id(int(str(id_str)))
		if not (obj is Node and is_instance_valid(obj) and obj in live_candidates):
			continue
		if max_count >= 0 and result.size() >= max_count:
			break
		if has_lock and result.size() > 0 and lock_group_key.call(obj) != locked_key:
			continue
		if has_dynamic and not dynamic_filter.call(result, obj):
			continue
		result.append(obj)
		if has_lock and result.size() == 1:
			locked_key = lock_group_key.call(obj)
	return result


func await_target_or_castillo_pick(prompt: String, filter: Callable, castillo_title: String, allow_cancel: bool = true, castillo_own_only: bool = false, chooser_id: int = 0) -> Dictionary:
	"""Carrera entre clickear una carta real (que pase filter) y clickear un Panel de Castillo entero
	(propio o rival), para habilidades que ofrecen "una carta ... o el tope de un Castillo"
	(Sherlock Holmes, La Ouija; arquitectura.md §10.14). El primer click decide la fuente.
	allow_cancel: true ("puedes") → ESC cancela todo y devuelve {type: "none"}; false → ESC solo
	reintenta el picker de cartas.
	castillo_own_only: "TU Castillo" (La Ouija); un click en el Castillo rival se ignora y se sigue
	esperando.
	Devuelve {type: "card", card}, {type: "castillo", own} o {type: "none"}.
	chooser_id: el jugador 1 con Remoto se delega a _delegate_target_or_castillo_to_remote()
	(arquitectura.md §41)."""
	EffectContextScript.check_chooser(chooser_id, prompt)
	if chooser_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		return await _delegate_target_or_castillo_to_remote(prompt, filter, castillo_title, allow_cancel, castillo_own_only)
	if not is_instance_valid(self):
		return {"type": "none"}
	# El bot: el primer objetivo que pase el filtro; si no hay, el Castillo rival (o el propio si solo puede ese).
	if PlayerSideScript.is_bot(chooser_id):
		await get_tree().process_frame
		for side in [0, 1]:
			for c in PlayerSideScript.line_containers(_main, side):
				for n in c.get_children():
					if is_instance_valid(n) and filter.is_valid() and filter.call(n):
						return {"type": "card", "card": n}
		return {"type": "castillo", "own": castillo_own_only}
	# Estado en un Dictionary (_state): los lambdas de GDScript capturan las variables locales por
	# valor, así que un lambda que se llama a sí mismo o reasigna flags no se ve desde afuera
	# (arquitectura.md §13.17). El Dictionary se comparte por referencia y el lambda se reinvoca vía
	# _state["arm"].
	var _state := {"race_done": false, "castillo_own": true, "castillo_chosen": false, "arm": Callable()}
	_state["arm"] = func() -> void:
		SelectionManager.start_castillo_pick(_main, castillo_title,
			func(picked_own: bool) -> void:
				if _state["race_done"]:
					return
				if castillo_own_only and not picked_own:
					_main._update_debug("%s: solo tu propio Castillo es válido aquí" % castillo_title)
					_state["arm"].call()
					return
				_state["race_done"] = true
				_state["castillo_own"] = picked_own
				_state["castillo_chosen"] = true
				cancel_target_selection(), castillo_own_only)
	_state["arm"].call()

	var chosen_card: Node = null
	while not _state["race_done"]:
		var card_state := {"done": false, "chosen": null}
		start_target_selection(prompt, filter, func(c: Node) -> void:
			card_state.chosen = c
			card_state.done = true)
		# Las cartas válidas brillan junto con el Castillo (p.ej. Espada de O'Higgins), para mostrar qué
		# se puede elegir.
		_glow_valid_targets(filter)
		while not card_state.done and not _state["race_done"]:
			await get_tree().process_frame
		if _state["race_done"]:
			break
		if card_state.chosen:
			chosen_card = card_state.chosen
			_state["race_done"] = true
			SelectionManager.cancel_castillo_pick()
		elif allow_cancel:
			_state["race_done"] = true
			SelectionManager.cancel_castillo_pick()
		# else: ESC sin elegir carta en una habilidad OBLIGATORIA — se
		# vuelve a armar el listener de cartas, el Castillo sigue
		# esperando en paralelo.

	if chosen_card:
		return {"type": "card", "card": chosen_card}
	if _state["castillo_chosen"]:
		return {"type": "castillo", "own": _state["castillo_own"]}
	return {"type": "none"}


func cancel_target_selection() -> void:
	"""Cancela con ESC llamando al callback con null, para que quien espera 'while not done' no se
	cuelgue. No hace nada si la selección es obligatoria (_selection_cancellable): p.ej. "Descarta
	N cartas" sin "puedes"."""
	if not is_selecting_target or not _selection_cancellable:
		return
	is_selecting_target = false
	PriorityManager.suppress_human_autopass = false
	var callback = _target_callback
	_target_filter = Callable()
	_target_callback = Callable()
	_cemetery_target_nodes.clear()
	_restore_board_interactable()
	_unglow_target_cards()
	_main._update_debug("Selección de objetivo cancelada")
	if callback.is_valid():
		callback.call(null)


func _resolve_target_selection(card: Node) -> void:
	if _target_filter.is_valid() and not _target_filter.call(card):
		# El mensaje dice explícitamente que ESC cancela, para no quedar clickeando la mano sin salida
		# (p.ej. Golpe Solar: "Baraja hasta una carta... ESC para no barajar ninguna").
		_main._update_debug("Objetivo no válido — elige otra carta o presiona N si es opcional")
		return
	var callback = _target_callback
	is_selecting_target = false
	PriorityManager.suppress_human_autopass = false
	_target_filter = Callable()
	_target_callback = Callable()
	_cemetery_target_nodes.clear()
	_restore_board_interactable()
	_unglow_target_cards()
	_last_resolved_target = card
	_last_resolved_at_ms = Time.get_ticks_msec()
	if callback.is_valid():
		callback.call(card)


func check_deselect() -> void:
	"""Deselecciona la carta si el click fue fuera de cualquier carta."""
	if _card_clicked_this_frame:
		_card_clicked_this_frame = false
		return
	if selected_card:
		selected_card.deselect()
		selected_card = null


# =============================================================================
# CLICKS EN CARTAS DEL JUGADOR
# =============================================================================
func _on_card_clicked(card: Node) -> void:
	_card_clicked_this_frame = true
	# Selector de zonas con candidatas en la mano (Miguel): antes que el desvío del Remoto y que
	# cualquier otro modo.
	if _main.get("_zone_browse_picker") and _main._zone_browse_picker.try_hand_click(card):
		return
	# El cliente Remoto no corre la partida: un click nunca llega a la lógica local (atacar, bloquear,
	# jugar). Ver _on_card_double_clicked().
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		if _main._remote_mirror:
			_main._remote_mirror.on_card_clicked(card)
		return
	if is_selecting_target:
		_resolve_target_selection(card)
		return
	if is_placing_gold:
		await _main._gold_manager._place_card_as_gold(card)
		return
	# Declarar bloqueador con un clic (GameManager.declare_blocker()): solo un Aliado propio en Línea
	# de Defensa del humano. Si el humano ataca, sus Aliados están en Línea de Ataque y esto no
	# interfiere.
	if GameManager.current_phase == Constants.Phase.BLOQUEO and card.card_type == Constants.CardType.ALIADO \
			and card.current_zone == Constants.Zone.LINEA_DEFENSA and card.controller_id == 0:
		await _declare_blocker(card)
		return
	# Declarar atacante con un clic (el arrastre está desactivado por problemas de posicionamiento).
	# Reusa Card._can_declare_attack_drag() para saber cuándo tiene sentido (fase de Ataque).
	# Acepta Defensa (declarar) o Ataque (desdeclarar con un segundo clic), porque declarar mueve la
	# carta a la Línea de Ataque.
	if card.card_type == Constants.CardType.ALIADO and card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE]:
		# Si ya ataca, un segundo clic lo retira del combate, para corregir antes de confirmar con ¿Paso?.
		if card in GameManager.attackers:
			if GameManager.current_phase in [Constants.Phase.VIGILIA, Constants.Phase.ATAQUE]:
				var undeclared = GameManager.undeclare_attacker(card)
				if undeclared:
					unmark_attackers([card])
					var name_undeclared = card.get("card_name") if card.get("card_name") else "Aliado"
					_main._update_debug("%s ya no está atacando" % name_undeclared)
			return
		if card.has_method("_can_declare_attack_drag") and card._can_declare_attack_drag():
			await _declare_attacker(card)
			return
		# No puede atacar todavía pero la fase es la correcta: dar la razón real (normalmente enfermedad
		# de invocación) en vez del mensaje genérico.
		if GameManager.current_phase in [Constants.Phase.VIGILIA, Constants.Phase.ATAQUE]:
			var validation_reason = TurnManager.can_attack(card)
			if not validation_reason.get("can_attack", true):
				var reason_name = card.get("card_name") if card.get("card_name") else "Aliado"
				_main._update_debug("%s: %s" % [reason_name, validation_reason.get("reason", "no puede atacar todavía")])
				return

	if selected_card and selected_card != card:
		selected_card.deselect()
	card.toggle_selection()
	selected_card = card if card.is_selected else null
	if card.card_type == Constants.CardType.ORO:
		_main._update_debug("Oro: %s" % card.card_name)
	elif card.card_type == Constants.CardType.ALIADO:
		_main._update_debug("Carta: %s (Coste: %d, Fuerza: %d)" % [card.card_name, card.card_cost, card.card_strength])
	else:
		_main._update_debug("Carta: %s (Coste: %d)" % [card.card_name, card.card_cost])


func _on_card_double_clicked(card: Node) -> void:
	if _main.get("_zone_browse_picker") and _main._zone_browse_picker.try_hand_click(card):
		return
	# En el cliente Remoto, jugar desde la mano manda la jugada al Anfitrión (RemoteMirrorController),
	# nunca al GoldManager local.
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		if _main._remote_mirror:
			_main._remote_mirror.on_card_double_clicked(card)
		return
	# Un click real dispara primero card_clicked y luego card_double_clicked (mismo gesto). Si el
	# primero ya resolvió una selección (p.ej. portador de un Arma), el eco llega con
	# is_selecting_target en false: se ignora en silencio (mismo objetivo, <700 ms).
	if card == _last_resolved_target and Time.get_ticks_msec() - _last_resolved_at_ms < 700:
		return
	# Si la selección sigue pendiente (el objetivo de este double-click no es
	# el que se acaba de resolver), resolverla igual que un click simple —
	# evita que reentre en play_card() y pise el filtro/callback en curso.
	if is_selecting_target:
		_resolve_target_selection(card)
		return
	# Doble click sobre un Aliado ya en juego (Defensa/Ataque) = el click simple de
	# declarar/desdeclarar ataque, en vez del rechazo genérico "Solo puedes jugar cartas de la mano".
	if card.card_type == Constants.CardType.ALIADO and card.current_zone in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE]:
		_on_card_clicked(card)
		return
	# No solo VIGILIA: este filtro de UI corre antes de GoldManager.play_card(), así que debe repetir
	# sus excepciones (Armas con Lobo Sagrado y Talismanes en Guerra de Talismanes; Talismanes de
	# respuesta en cualquier fase).
	var is_instant_response_talisman: bool = card.card_type == Constants.CardType.TALISMAN \
		and _main._gold_manager._is_response_only_talisman(card)
	# Ventana de comienzo de fase (PhaseStartWindow).
	var phase_start_ok: bool = load("res://scripts/core/game/PhaseStartWindow.gd").allows_now(card, 0)
	if GameManager.current_phase != Constants.Phase.VIGILIA and not _main._gold_manager.has_phase_exception(card.card_type) \
			and not is_instant_response_talisman and not phase_start_ok:
		_main._update_debug(_main._gold_manager.get_phase_rejection_reason(card.card_type))
		return
	# Talismanes de respuesta fuera de tu turno: mismo criterio que GoldManager.play_card(), que este
	# filtro precede. En Guerra de Talismanes decide la prioridad, no el turno (§64); lo valida
	# GoldManager.play_card().
	if GameManager.active_player_id != 0 and not is_instant_response_talisman and not phase_start_ok \
			and GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
		_main._update_debug("No es tu turno")
		return
	if card.get_parent() != _main.player_hand:
		_main._update_debug("Solo puedes jugar cartas de la mano (%s)" % card.get("card_name"))
		return
	if card.card_type == Constants.CardType.ORO:
		await _main._gold_manager._place_card_as_gold(card)
		return
	await _main._gold_manager.play_card(card)


func _on_card_hovered(_card: Node) -> void:
	pass


func _on_card_unhovered(_card: Node) -> void:
	pass


# =============================================================================
# HOVER EN CARTAS DEL OPONENTE
# =============================================================================
func _on_card_dropped(card: Node, pos: Vector2) -> void:
	if card.has_method("move_to"):
		card.move_to(card.original_position)


# =============================================================================
# BATALLA — DECLARAR ATACANTE
# =============================================================================
## Aspecto de "atacando" (a la Línea de Ataque y marcado). También para Aliados que entran atacando sin
## pasar por la declaración (andras, hombre invisible: GameManager.replacement_attackers).
func mark_attacker_visual(card: Node) -> void:
	if not is_instance_valid(card):
		return
	var ataque_container: HBoxContainer = _main.player_linea_ataque if card.controller_id == 0 else _main.opponent_linea_ataque
	await _advance_card_to_attack_line(card, ataque_container)
	_mark_card_as_attacker(card)


func _declare_attacker(card: Node) -> void:
	"""Declara un Aliado como atacante (DAR 5.3.1). GameManager.declare_attacker() valida enfermedad
	de invocación (Furia la evita).
	No abre su propia ventana de prioridad: el jugador sigue declarando más atacantes y confirma
	todos con ¿Paso? (GameManager.confirm_attackers(), vía PhaseFlowController._on_paso_pressed());
	esa transición abre la ventana real (Guerra de Talismanes o Bloqueo). Abrirla aquí arrancaba el
	combate con un solo atacante."""
	if not card or not is_instance_valid(card):
		return
	# Traba de reentrada: un segundo click/eco sobre la misma carta mientras su declaración sigue en
	# vuelo se ignora (ver _declaring_attackers).
	if _declaring_attackers.has(card):
		return
	_declaring_attackers[card] = true
	# Con el clic reemplazando al arrastre, es fácil volver a clickear un
	# Aliado que ya está atacando (por error, o para revisarlo). Antes esto
	# caía en GameManager.declare_attacker(), que lo rechaza en silencio
	# (ally in attackers), y el mensaje genérico de más abajo ('no puede
	# atacar todavía') daba a entender que el ataque había fallado, cuando
	# en realidad ya estaba registrado y el combate seguía su curso normal.
	if card in GameManager.attackers:
		_main._update_debug("%s ya está atacando" % (card.get("card_name") if card.get("card_name") else "Aliado"))
		_declaring_attackers.erase(card)
		return
	# Si hay una ventana de prioridad abierta (p.ej. respuesta a un 'cuando
	# entre en juego' que se acaba de disparar), no dejar declarar un nuevo
	# atacante todavía — eso hacía que el efecto pendiente (p.ej. el 'roba 2'
	# de un oro) quedara pospuesto y se resolviera solo al momento de
	# atacar, en vez de cuando se jugó la carta. Hay que resolver esa
	# ventana primero (presionando ¿Paso?).
	if PriorityManager.priority_window_active:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de declarar otro atacante")
		card.return_to_hand()
		_declaring_attackers.erase(card)
		return
	var card_name = card.get("card_name") if card.get("card_name") else "Aliado"
	# KeywordManager.can_attack_immediately() (no card.has_keyword()): respeta silencios/remociones
	# temporales y es la misma función que usa TurnManager.can_attack(), así que el mensaje no se
	# desincroniza.
	var has_furia = KeywordManager.can_attack_immediately(card)
	await get_tree().process_frame
	var declared = await GameManager.declare_attacker(card)
	if not declared:
		var reason = TurnManager.can_attack(card).get("reason", "")
		_main._update_debug("%s no puede atacar%s" % [card_name, (": " + reason) if not reason.is_empty() else " todavía"])
		_declaring_attackers.erase(card)
		return

	await mark_attacker_visual(card)
	_main._game_hud.start_paso_glow()
	_main._update_debug("%s declara ataque%s! Puedes seguir declarando o presionar ¿Paso?" % [card_name, " con Furia" if has_furia else ""])
	print("[CardInteraction] '%s' declaró ataque%s" % [card_name, " (Furia)" if has_furia else ""])
	_declaring_attackers.erase(card)


func _declare_blocker(card: Node) -> void:
	"""Declara card como bloqueador (fase de Bloqueo, DAR 5.3.2). Con un solo atacante sin bloquear se
	asigna directo; con varios, se clickea el atacante rival en el tablero. Clickear un bloqueador ya
	declarado lo quita (mismo criterio que el Remoto, RemoteMirrorController._on_board_block_click());
	para reasignarlo se vuelve a clickear. Un bloqueo forzado (Cañón Helios) no se quita.
	Un bloqueador que puede bloquear a varios (Elías, BlockPatterns.max_blocks()) suma otro atacante
	con cada clic mientras tenga lugar y atacantes libres; después, el clic quita todos sus bloqueos."""
	if not card or not is_instance_valid(card):
		return
	var unblocked_attackers: Array = []
	for attacker in GameManager.attackers:
		if is_instance_valid(attacker) and not GameManager.blockers.has(attacker):
			unblocked_attackers.append(attacker)
	var current_blocks: Array = BlockScript.blocks_of(card)
	if not current_blocks.is_empty() and (not BlockScript.can_block_more(card) or unblocked_attackers.is_empty()):
		var blocking_name: String = card.get("card_name") if card.get("card_name") else "Aliado"
		if int(card.get_meta("forced_block_turn", -1)) == GameManager.turn_serial:
			_main._update_debug("%s está obligado a bloquear" % blocking_name)
			return
		for atk in current_blocks:
			GameManager.blockers.erase(atk)
		var untween = create_tween()
		untween.tween_property(card, "modulate", Color.WHITE, 0.2)
		_main._update_debug("%s ya no bloquea" % blocking_name)
		return

	if unblocked_attackers.is_empty():
		_main._update_debug("No hay atacantes sin bloquear")
		return

	var attacker: Node = unblocked_attackers[0]
	if unblocked_attackers.size() > 1:
		# Click directo sobre el atacante en el tablero (await_target), como el resto de las elecciones de
		# objetivo.
		var filter := func(c: Node) -> bool:
			return c in unblocked_attackers
		var clicked_attacker: Node = await await_target(
			"%s bloquea — elige a qué atacante rival" % (card.get("card_name") if card.get("card_name") else "Tu Aliado"),
			filter)
		if not clicked_attacker or not is_instance_valid(clicked_attacker):
			_main._update_debug("Bloqueo cancelado")
			return
		attacker = clicked_attacker

	GameManager.declare_blocker(card, attacker)
	var card_name: String = card.get("card_name") if card.get("card_name") else "Aliado"
	var attacker_name: String = attacker.get("card_name") if attacker.get("card_name") else "Aliado"
	var tween = create_tween()
	tween.tween_property(card, "modulate", Color(0.4, 0.7, 1.0, 1.0), 0.2)
	_main._update_debug("%s bloquea a %s" % [card_name, attacker_name])
	print("[CardInteraction] '%s' bloquea a '%s'" % [card_name, attacker_name])


func _mark_card_as_attacker(card: Node) -> void:
	"""Aspecto visual de 'atacando': tinte naranja."""
	queue_idle_attack_refresh()
	if not card or not is_instance_valid(card):
		return
	var tween = create_tween()
	tween.tween_property(card, "modulate", Color(1.0, 0.55, 0.35, 1.0), 0.2)


func unmark_attackers(cards: Array) -> void:
	"""Revierte el aspecto visual de 'atacando' y mueve al sobreviviente
	de vuelta a Línea de Defensa en línea recta por el eje Y."""
	for card in cards:
		if not card or not is_instance_valid(card):
			continue
		var tween = create_tween()
		tween.tween_property(card, "modulate", Color.WHITE, 0.2)
		var defensa_container: HBoxContainer = _main.player_field if card.controller_id == 0 else _main.opponent_field
		await _move_card_to_line(card, defensa_container, Constants.Zone.LINEA_DEFENSA)
	if _main and _main.get("_zone_manager") != null:
		_main._zone_manager.compact_all_fields(true)


func _advance_card_to_attack_line(card: Node, ataque_container: HBoxContainer) -> void:
	"""Avanza el Aliado en línea recta exclusivamente sobre el eje vertical Y,
	manteniendo su coordenada X fija en su carril sin recentrar ni desviar."""
	if not card or not is_instance_valid(card) or not ataque_container:
		return
	var start_pos: Vector2 = card.global_position
	var slot_x: float = card.get_meta("field_slot_x", start_pos.x)

	var previous_parent: Node = card.get_parent()
	if previous_parent and previous_parent != ataque_container:
		previous_parent.remove_child(card)
	if card.get_parent() != ataque_container:
		ataque_container.add_child(card)

	card.set_zone(Constants.Zone.LINEA_ATAQUE)
	card.top_level = true
	card.global_position = start_pos

	var card_height: float = (card.size.y * card.scale.y) if card.size.y > 0 else 210.0
	var target_y: float = ataque_container.global_position.y + (ataque_container.size.y - card_height) / 2.0
	var target_pos: Vector2 = Vector2(slot_x, target_y)
	card.set_meta("field_slot_pos", target_pos)

	var tween = create_tween()
	tween.tween_method(
		func(y: float): card.global_position = Vector2(slot_x, y),
		start_pos.y, target_y, 0.25
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	if is_instance_valid(card) and "equipped_weapons" in card and card.equipped_weapons is Array:
		for w_idx in range(card.equipped_weapons.size()):
			var w = card.equipped_weapons[w_idx]
			if is_instance_valid(w):
				w.top_level = false
				w.position = Vector2(0.0, Constants.WEAPON_OFFSET_Y + w_idx * Constants.WEAPON_STACK_STEP_Y)
				w.set_zone(card.current_zone)
				if "base_scale" in card and "base_scale" in w:
					w.scale = card.base_scale
					w.base_scale = card.base_scale


func _move_card_to_line(card: Node, target_container: HBoxContainer, zone: int) -> void:
	"""Regresa un Aliado a Línea de Defensa en línea recta vertical sobre el eje Y
	hacia su slot de columna X reservado."""
	if not card or not is_instance_valid(card) or not target_container:
		return
	var start_pos: Vector2 = card.global_position
	var previous_parent: Node = card.get_parent()
	if previous_parent and previous_parent != target_container:
		previous_parent.remove_child(card)
	if card.get_parent() != target_container:
		target_container.add_child(card)

	card.set_zone(zone)
	card.top_level = true
	var end_pos: Vector2 = _main._zone_manager.pin_card_to_field_slot(card, target_container)
	var slot_x: float = card.get_meta("field_slot_x", end_pos.x)
	card.global_position = Vector2(slot_x, start_pos.y)

	var tween = create_tween()
	tween.tween_method(
		func(y: float): card.global_position = Vector2(slot_x, y),
		start_pos.y, end_pos.y, 0.25
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	if is_instance_valid(card) and "equipped_weapons" in card and card.equipped_weapons is Array:
		for w_idx in range(card.equipped_weapons.size()):
			var w = card.equipped_weapons[w_idx]
			if is_instance_valid(w):
				w.top_level = false
				w.position = Vector2(0.0, Constants.WEAPON_OFFSET_Y + w_idx * Constants.WEAPON_STACK_STEP_Y)
				w.set_zone(card.current_zone)
				if "base_scale" in card and "base_scale" in w:
					w.scale = card.base_scale
					w.base_scale = card.base_scale
