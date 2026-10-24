extends RefCounted
## ConvertAndMiscResolver — patrones compuestos de Convertir/transformar cartas (Sherlock Holmes,
## Jormundgander, Jabberwocky, Biblioteca de Caballería), destierro por cantidad (Espada del
## Juicio), descarte + robo del oponente (Miguel) y silencio por nombre (Alicia en Wonderland). Cada
## uno detecta su texto por regex y resuelve lo que extract_action() (una sola acción por texto) no
## puede. Opera sobre TriggerSystem vía _executor._main (ver TargetedEffectExecutor.gd).

var _executor: TargetedEffectExecutor


func setup(executor: TargetedEffectExecutor) -> void:
	_executor = executor


# =============================================================================
# PATRÓN "CUANDO ENTRA EN JUEGO O ATAQUE, CONVIERTE HASTA N CARTAS QUE NO
# SEAN ORO DEL TOPE DE UN CASTILLO EN ALIADOS DE FUERZA F SIN HABILIDAD Y
# GANA SU CONTROL. ROBA M CARTAS Y LOS ALIADOS QUE CONTROLAS NO PUEDEN
# SALIR DEL JUEGO HASTA TU PRÓXIMO TURNO" (Sherlock Holmes)
# =============================================================================
func try_execute_mill_convert_to_ally_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Sherlock Holmes: "convierte hasta dos cartas que no sean Oro o del tope de un Castillo". Las
	cartas convertidas no se juegan ni se pagan: aparecen en juego bajo el control de quien
	resuelve. El "o" separa dos fuentes:
	- cartas en juego que no sean Oro (de cualquier lado): se eligen hasta N y se convierten en su
	lugar;
	- del tope de un Castillo: se sacan a ciegas del mazo elegido.
	Ambas fuentes quedan clickeables a la vez (una carta en juego o un Panel de Castillo) y el
	primer click decide (SelectionManager.start_castillo_pick()/cancel_castillo_pick() contra
	CardInteractionModule.start_target_selection()/cancel_target_selection()).
	Las dos ramas terminan en el Convertir de DAR Sección 8 (is_converted +
	KeywordManager.silence_card, giro de 180°) con Fuerza fija por modificador continuo
	(LAYER_7A_CHAR_SETTING, 'set', sin source: permanente), para que el badge muestre el valor
	efectivo.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("del tope de un castillo" in lower and "gana su control" in lower):
		return false
	# Viejo del Saco tiene su propio patrón (mechanics/ConvertPatterns.gd).
	if "en un aliado de fuerza 2 con la habilidad furia, imbloqueable" in lower:
		return false
	if controller_id != 0 or not is_instance_valid(card):
		return true
	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true

	var amount_rx := RegEx.new()
	amount_rx.compile("(?i)convierte hasta (\\w+) cartas?")
	var m_amount := amount_rx.search(ability_text)
	var max_amount: int = UniversalCardParser._parse_amount(m_amount.get_string(1)) if m_amount else 1

	var strength_rx := RegEx.new()
	strength_rx.compile("(?i)fuerza (\\d+) sin habilidad")
	var m_str := strength_rx.search(ability_text)
	var token_strength: int = int(m_str.get_string(1)) if m_str else 1

	var draw_rx := RegEx.new()
	draw_rx.compile("(?i)roba[s]?\\s+(\\w+)\\s+cartas?")
	var m_draw := draw_rx.search(ability_text)
	var draw_amount: int = UniversalCardParser._parse_amount(m_draw.get_string(1)) if m_draw else 0

	var grants_immunity := "no pueden salir del juego" in lower
	var converted := 0

	var _apply_conversion := func(target_node: Node) -> void:
		target_node.is_converted = true
		await KeywordManager.silence_card(target_node, card, "permanent")
		# Fuerza EFECTIVA fijada en token_strength, sin tocar el dato base
		# impreso — el badge de Fuerza (Card._apply_strength_badge_text())
		# solo se muestra cuando el valor efectivo difiere del impreso.
		ContinuousEffectManager.register_modifier({
			"source": null,
			"target": target_node,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": token_strength,
			"operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
			"description": "Sherlock Holmes: Fuerza fijada en %d" % token_strength,
		})
		target_node.refresh_strength_badge()

	if not main._card_interaction:
		return true

	var picked: Array = []
	var filter := func(c: Node) -> bool:
		# Autorreferenciable: las cartas de Imperio SÍ pueden targetear/afectarse a sí mismas salvo que
		# digan lo contrario) — Sherlock puede convertirse a sí mismo.
		return c.get("card_type") != Constants.CardType.ORO and not (c in picked)

	# Carrera: el Castillo queda activo en paralelo mientras se espera el primer click de carta; el
	# primero que resuelve cancela al otro. Estado en un Dictionary: los lambdas capturan las locales
	# por valor (arquitectura.md §13.17).
	var _state := {"race_done": false, "castillo_picked_own": true}
	SelectionManager.start_castillo_pick(main, card.card_name if card.get("card_name") else "Sherlock Holmes",
		func(picked_own: bool) -> void:
			if _state["race_done"]:
				return
			_state["race_done"] = true
			_state["castillo_picked_own"] = picked_own
			main._card_interaction.cancel_target_selection())

	var first_target: Node = null
	while not _state["race_done"]:
		var card_state := {"done": false, "chosen": null}
		main._card_interaction.start_target_selection(
			"Elige una carta en juego (no Oro) o un Castillo para Convertir", filter,
			func(c: Node) -> void:
				card_state.chosen = c
				card_state.done = true)
		while not card_state.done and not _state["race_done"]:
			await main.get_tree().process_frame
		if _state["race_done"]:
			break
		if card_state.chosen:
			first_target = card_state.chosen
			_state["race_done"] = true
			SelectionManager.cancel_castillo_pick()
		# Si card_state.chosen es null (ESC), se vuelve a armar el listener
		# de cartas mientras el Castillo sigue esperando en paralelo — la
		# habilidad no es 'puedes', tiene que resolverse por una fuente u otra.

	if first_target:
		picked.append(first_target)
		while picked.size() < max_amount:
			var target: Node = await main._card_interaction.await_target(
				"Elige otra carta en juego (no Oro) para Convertir — N para terminar", filter)
			if not target or not is_instance_valid(target):
				break
			picked.append(target)

		# Ya se declaró todo (los hasta max_amount objetivos elegidos) — aquí
		# corresponde la ventana, antes de convertir ninguno.
		if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
			return true
		var target_field: HBoxContainer = main.player_field if controller_id == 0 else main.opponent_field
		for target_node in picked:
			if not is_instance_valid(target_node):
				continue
			var old_parent = target_node.get_parent()
			if old_parent and old_parent != target_field:
				old_parent.remove_child(target_node)
				target_field.add_child(target_node)
			target_node.card_type = Constants.CardType.ALIADO
			target_node.controller_id = controller_id
			target_node.can_interact = (controller_id == 0)
			target_node.set_zone(Constants.Zone.LINEA_DEFENSA)
			await _apply_conversion.call(target_node)
			converted += 1
	else:
		# Castillo ya elegido por el propio click que ganó la carrera
		# (_state["castillo_picked_own"]) — sin preguntar aparte.
		var zone_owner: int = controller_id if _state["castillo_picked_own"] else (1 - controller_id)
		var deck: Array = CardManager.get_deck(zone_owner)
		# Sin objetivos puntuales que declarar aquí (salen del tope, en el
		# orden del mazo, no elegidos) — la ventana va antes de empezar a
		# revelar/convertir, gate de toda la secuencia.
		if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
			return true
		while converted < max_amount and not deck.is_empty():
			var top_data: Dictionary = deck.pop_front()
			var new_data: Dictionary = top_data.duplicate()
			new_data["tipo"] = Constants.CardType.ALIADO  # Puede venir de cualquier tipo no-Oro original; aquí SIEMPRE se fuerza a Aliado
			new_data["esta_oculta"] = false
			var token_node = main._create_card(new_data, false)
			token_node.owner_id = controller_id
			main._connect_card_signals(token_node)
			var target_field: HBoxContainer = main.player_field if controller_id == 0 else main.opponent_field
			target_field.add_child(token_node)
			token_node.can_interact = (controller_id == 0)
			token_node.set_zone(Constants.Zone.LINEA_DEFENSA)
			await _apply_conversion.call(token_node)

			if CardFactory and CardFactory.has_method("on_card_enters_play"):
				CardFactory.on_card_enters_play(token_node)  # enfermedad de invocación, igual que cualquier Aliado
			if token_node.has_method("play_enter_animation"):
				token_node.play_enter_animation()
			converted += 1

	if converted > 0 and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()

	if draw_amount > 0:
		await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)

	if grants_immunity:
		EffectController.add_blanket_leave_play_immunity(controller_id)

	return true


# =============================================================================
# PATRÓN "CUANDO HAGA DAÑO, PUEDES CONVERTIRLO EN UN ORO Y MOVERLO A TU ORO
# PAGADO" (Jormundgander)
# =============================================================================
func try_execute_convert_ally_to_gold_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Jormundgander: "puedes convertirlo en un Oro y moverlo a tu Oro Pagado" — el Aliado se
	transforma en Oro y va directo al Oro Pagado. La otra mitad ("si esta carta es un Oro, cuando
	lo pagues para jugar un Aliado, conviértela en un Aliado...") la resuelve
	GoldManager._mover_oro_a_pagado() con card.revert_to_data.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("convertirlo en un oro" in lower and "oro pagado" in lower):
		return false
	if controller_id != 0 or not is_instance_valid(card):
		return true
	# _executor._main es TriggerSystem, no Main (arquitectura.md §2): se busca Main antes de usar
	# _gold_manager/_card_interaction, como try_execute_jabberwocky_convert_opponent_top_pattern().
	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true

	# En vez de un modal de confirmación con un solo candidato, clickear la carta misma (ya está en
	# juego, visible) confirma; ESC declina — mismo mecanismo que cualquier otro await_target, sin
	# necesidad de un panel aparte para un "sí/no" de una sola carta conocida de antemano.
	if not main._card_interaction:
		return true
	var self_filter := func(c: Node) -> bool: return c == card
	var accepted: Node = await main._card_interaction.await_target(
		"%s: clickéala para convertirla en un Oro y moverla a tu Oro Pagado (N para declinar)" % card.card_name, self_filter)
	if not accepted or not is_instance_valid(accepted):
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true

	await main._gold_manager.convert_ally_to_gold_in_pagado(card)
	return true


# =============================================================================
# PATRÓN "CUANDO ENTRA EN JUEGO O ATACA, CONVIERTE LA PRIMERA CARTA DEL
# CASTILLO OPONENTE EN UN ORO SIN HABILIDAD..." (Jabberwocky)
# =============================================================================
func try_execute_jabberwocky_convert_opponent_top_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Jabberwocky: "Cuando entra en juego o ataca, convierte la primera carta del Castillo oponente
	en un Oro sin habilidad y ponlo en tu Oro Pagado". Misma conversión a Oro que Biblioteca de
	Caballería y convert_ally_to_gold_in_pagado() (Jormundgander), pero sobre el Castillo rival y
	al Oro Pagado. 'tipo'/'habilidad' se pisan en los datos antes de crear el Node, así que "sin
	habilidad" no necesita silence_card(). "cuando entra en juego o ataca" (con "ataca") está en
	Card.TRIGGER_KEYWORDS."""
	var lower := ability_text.to_lower()
	if not ("convierte la primera carta del castillo oponente en un oro sin habilidad" in lower):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var opponent_id: int = 1 - controller_id
	var deck: Array = CardManager.get_deck(opponent_id)
	if deck.is_empty():
		return true
	if await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
		return true

	var top_data: Dictionary = deck.pop_front()
	var new_data: Dictionary = top_data.duplicate()
	new_data["tipo"] = Constants.CardType.ORO
	new_data["habilidad"] = ""
	await main._gold_manager.put_gold_directly_in_pagado(controller_id, new_data)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_no_allies_convert_castillo_top_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Biblioteca de Caballería: "En la Fase Final oponente, si no controlas Aliados o si en tu turno
	anterior un Aliado fue Anulado o su habilidad fue cancelada, Roba una carta y pon bajo tu
	control la primera carta de un Castillo como un Aliado de Fuerza 2 sin habilidad".
	Límite: solo la mitad "si no controlas Aliados". La otra necesitaría un historial de
	anulaciones/cancelaciones por turno que el motor no tiene.
	Usa la conversión de Sherlock Holmes: is_converted + KeywordManager.silence_card + Fuerza
	fijada por modificador continuo (LAYER_7A_CHAR_SETTING, 'set')."""
	var lower := ability_text.to_lower()
	if not ("si no controlas aliados" in lower and "pon bajo tu control la primera carta de un castillo" in lower):
		return false
	if controller_id != 0 or not is_instance_valid(card):
		return true

	if _executor._count_allies_in_play(controller_id) > 0:
		return true  # condición no cumplida (falta la otra mitad del 'o', ver docstring)

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true
	# Ventana única para todo el efecto (robar + convertir) — sin objetivo
	# puntual que declarar antes (la carta convertida sale del tope, en el
	# orden del mazo).
	if await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
		return true

	await ActionModule.draw(controller_id, 1, "final_phase_trigger", true)

	var zone_owner: int = await _executor._choose_search_zone_owner(controller_id, Constants.Zone.CASTILLO, "convertir")
	var deck: Array = CardManager.get_deck(zone_owner)
	if deck.is_empty():
		return true
	# Sin ventana genérica aquí: silence_card (más abajo) ya consulta Prevención adentro por su cuenta.
	var top_data: Dictionary = deck.pop_front()
	var new_data: Dictionary = top_data.duplicate()
	new_data["tipo"] = Constants.CardType.ALIADO
	new_data["esta_oculta"] = false
	var token_node = main._create_card(new_data, false)
	token_node.owner_id = controller_id
	main._connect_card_signals(token_node)
	var target_field: HBoxContainer = main.player_field if controller_id == 0 else main.opponent_field
	target_field.add_child(token_node)
	token_node.can_interact = (controller_id == 0)
	token_node.set_zone(Constants.Zone.LINEA_DEFENSA)

	token_node.is_converted = true
	await KeywordManager.silence_card(token_node, card, "permanent")

	ContinuousEffectManager.register_modifier({
		"source": null,
		"target": token_node,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": 2,
		"operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "Biblioteca de Caballería: Fuerza fijada en 2",
	})
	token_node.refresh_strength_badge()

	if CardFactory and CardFactory.has_method("on_card_enters_play"):
		CardFactory.on_card_enters_play(token_node)
	if token_node.has_method("play_enter_animation"):
		token_node.play_enter_animation()
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_banish_top_by_ally_count_and_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Espada del Juicio: "Destierra N cartas del tope de un Castillo y Roba una carta" (en "Cuando
	entra en juego" y "en tu Agrupación"). Cantidad fija, parseada del texto: la carta dice
	"tantas... como Aliados controles", pero se simplificó a propósito. "un Castillo" = a elección.
	El Robo siempre ocurre.
	Devuelve true si el patrón aplicaba."""
	var amount_rx := RegEx.new()
	amount_rx.compile("(?i)destierra (\\w+) cartas? del tope de un castillo")
	var m_amount := amount_rx.search(ability_text)
	if not m_amount:
		return false
	var banish_amount: int = UniversalCardParser._parse_amount(m_amount.get_string(1))

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true

	var draw_rx := RegEx.new()
	draw_rx.compile("(?i)roba[s]?\\s+(\\w+)\\s+cartas?")
	var m_draw := draw_rx.search(ability_text)
	var draw_amount: int = UniversalCardParser._parse_amount(m_draw.get_string(1)) if m_draw else 0

	var deck_owner: int = controller_id
	if banish_amount > 0:
		# await_castillo_pick() tiene puente de red (arquitectura.md §40): el Remoto también elige el
		# Castillo.
		var look_own: bool = await SelectionManager.await_castillo_pick(main, "Espada del Juicio — destierra del tope", controller_id)
		deck_owner = controller_id if look_own else (1 - controller_id)

	if await TriggerSystem.open_response_window(card, "Espada del Juicio", controller_id):
		return true

	if banish_amount > 0:
		CardManager.banish_from_deck(deck_owner, banish_amount, false, controller_id)

	if draw_amount > 0:
		await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)

	return true


func try_execute_opponent_discard_and_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Detecta 'tu oponente Descarta N cartas y tú Robas [hasta] M cartas' (p.ej. Miguel) — dos
	acciones en una sola oración que extract_action no puede encadenar (solo reconoce UNA acción
	por texto, la primera que matchea). Reusa _execute_targeted_discard tal cual (ya resuelve
	'oponente' y le da a elegir al jugador humano si es su propia mano la que descarta) seguido de
	un robo directo. Returns: true si el patrón aplicaba (se haya podido resolver o no)."""
	var lower := ability_text.to_lower()
	if not ("tu oponente descarta" in lower and "robas" in lower):
		return false

	var discard_rx := RegEx.new()
	discard_rx.compile("(?i)tu oponente descarta\\s+(\\d+|una|dos|tres|cuatro|cinco)\\s+cartas?")
	var m_discard := discard_rx.search(ability_text)
	if not m_discard:
		return false
	var discard_amount: int = UniversalCardParser._parse_amount(m_discard.get_string(1))

	var draw_rx := RegEx.new()
	draw_rx.compile("(?i)robas?\\s+(?:hasta\\s+)?(\\d+|una|dos|tres|cuatro|cinco)\\s+cartas?")
	var m_draw := draw_rx.search(ability_text)
	var draw_amount: int = UniversalCardParser._parse_amount(m_draw.get_string(1)) if m_draw else 0

	await _executor._execute_targeted_discard(card, controller_id, discard_amount)
	# El descarte ya abrió su propia ventana adentro (_execute_targeted_
	# discard) — el Robo es un efecto aparte, sin cobertura propia todavía.
	if draw_amount > 0:
		if await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			return true
		await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)
	return true


func try_execute_name_a_card_pattern(ability_text: String, card: Node, _controller_id: int) -> bool:
	"""Alicia en Wonderland: "nombra una carta para que pierda(n) su habilidad en todas las Zonas
	mientras esta carta esté en juego". Se bloquea un NOMBRE, no una carta: afecta cualquier copia
	en cualquier zona, también las que aparezcan después
	(KeywordManager.lock_ability_by_name()/is_name_locked(), consultado desde is_silenced()). El
	"nombra una carta" de Tesoro de los Césares es otro efecto (sube el coste; habilidad activada).
	Devuelve true si el patrón aplicaba (se haya podido resolver o no)."""
	var lower := ability_text.to_lower()
	if not ("nombra una carta" in lower and ("pierda" in lower or "pierdan" in lower) and "habilidad" in lower):
		return false

	var picked: Dictionary = await _executor._main._card_name_search.open_and_wait(
		"Escribe el nombre de una carta"
	)
	if picked.is_empty():
		return true  # el jugador canceló la búsqueda — el 'nombra' no se declinaba, pero sin nombre no hay nada que hacer

	var picked_name: String = str(picked.get("nombre", ""))
	if picked_name.is_empty():
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name), _controller_id):
		return true

	KeywordManager.lock_ability_by_name(picked_name, card)

	var main := _executor._main.get_node_or_null("/root/Main")
	if main:
		_executor._refresh_rotation_for_name(main, picked_name)

	if main:
		main._update_debug("%s: '%s' pierde su habilidad en todas las Zonas" % [
			str(card.get("card_name")), picked_name
		])
	return true
