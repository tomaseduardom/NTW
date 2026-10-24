extends Node
class_name EasyBotController
## EasyBotController — IA fácil para el jugador 1: decisiones al azar entre las jugadas legales, sin
## estrategia.
## Alcance a propósito: pone Oro y juega Aliados de la mano; Armas/Talismanes/Tótems quedan fuera
## (portador, restricciones de solo respuesta). Responde con habilidades activadas simples
## (try_respond_with_activated_ability()).
## Tiene su propia lógica de juego, más simple, sobre los contenedores opponent_*/_opponent_fan y
## GameState/CardManager (genéricos por player_id). Reusa los chequeos y registros genéricos de
## GoldManager (_no_more_cards_violation, _card_play_locked, _errante_violation,
## _play_limit_violation, _register_talisman_totem_tax, _register_talisman_second_play_tax,
## _register_gold_placed, update_gold_containers_spacing) en vez de reimplementarlos.

var _main: Node = null
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")


func _wait_until_settled() -> void:
	"""Espera a que termine lo que se está resolviendo: un efecto en curso (EffectContext), la Pila
	procesando, o el humano eligiendo una carta/búsqueda (p.ej. respondiendo con Dragón Dorado). Si
	no, el bot seguía atacando y pasando de turno."""
	var waited := 0.0
	while waited < 10.0:
		var busy: bool = not EffectContextScript._stack.is_empty() or ActionPipeline._is_resolving
		if _main._card_interaction and _main._card_interaction.is_selecting_target:
			busy = true
		if _main.get("_zone_browse_picker") and _main._zone_browse_picker.is_active():
			busy = true
		if not busy:
			return
		await get_tree().create_timer(0.2).timeout
		waited += 0.2


func setup(main: Node) -> void:
	_main = main


# =============================================================================
# VIGILIA — Oro primero (DAR), después Aliados que pueda pagar
# =============================================================================
func take_vigilia_actions() -> void:
	if not _main._opponent_fan:
		return

	await get_tree().create_timer(0.6).timeout
	await _wait_until_settled()
	_place_gold_if_possible()

	await get_tree().create_timer(0.6).timeout
	var plays := 0
	while plays < 10:
		await _wait_until_settled()
		var candidates: Array = _affordable_allies_in_hand()
		if candidates.is_empty():
			break
		candidates.shuffle()
		await _play_ally(candidates[0])
		plays += 1
		await get_tree().create_timer(0.5).timeout

	await get_tree().create_timer(0.6).timeout
	await _wait_until_settled()
	if GameManager.is_game_active and GameManager.active_player_id == 1 \
			and GameManager.current_phase == Constants.Phase.VIGILIA:
		_main._update_debug("Oponente ataca")
		GameManager.proceed_to_battle()


func _place_gold_if_possible() -> void:
	var gold_card: Node = null
	for c in _main._opponent_fan.get_cards():
		if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ORO:
			gold_card = c
			break
	if not gold_card:
		return
	# TurnManager.can_place_oro() es el gate REAL (GoldManager._place_card_
	# as_gold() lo usa, no GameManager.can_play_oro() — dos flags paralelos
	# distintos en este motor, ver [[project_pending_helper_sweep]]-adyacente;
	# hay que setear el mismo que consulta el resto del juego).
	if not TurnManager.can_place_oro(GameManager.current_phase, gold_card):
		return
	if _main._gold_manager and (_main._gold_manager._no_more_cards_violation(gold_card) \
			or _main._gold_manager._card_play_locked(gold_card)):
		return
	await _place_gold_card(gold_card)


func _place_gold_card(gold_card: Node) -> void:
	"""Coloca 'gold_card' (ya validada) como Oro del jugador 1. Separada de _place_gold_if_possible()
	para que RemotePlayerController la reuse con una carta elegida por la persona."""
	_main._opponent_fan.remove_card(gold_card, false)
	# Las cartas en _opponent_fan están esta_oculta=true (dorso, mano oculta del rival) — hay que
	# voltearla al entrar en juego, igual que cualquier Oro en Reserva es visible cara arriba para
	# ambos jugadores: no se veían las cartas del bot.
	gold_card.esta_oculta = false
	gold_card.can_interact = false
	_main.opponent_gold.add_child(gold_card)
	gold_card.top_level = false
	gold_card.scale = Constants.GOLD_CARD_SCALE
	gold_card.base_scale = Constants.GOLD_CARD_SCALE
	gold_card.set_zone(Constants.Zone.RESERVA_ORO)
	if _main._gold_manager:
		_main._gold_manager.update_gold_containers_spacing()
	await get_tree().process_frame
	gold_card.can_interact = true
	TurnManager.oro_placed_this_turn = true
	TurnManager.any_card_played_this_turn = true
	GameState.agregar_oro_reserva(1, 1)
	if _main._gold_manager:
		_main._gold_manager._register_gold_placed(1)
	_main._update_debug("Oponente pone un Oro (Reserva: %d)" % GameState.get_oro_reserva(1))
	# Consistente con _play_ally/play_free_ally_from_data/put_free_gold_in_pagado_from_data (las 3 SÍ
	# lo emiten) — sin esto, GameStateBroadcaster (multiplayer remoto) no se enteraba de que el Oro del
	# jugador 1 entró en juego, y ContinuousEffectManager/CardEffectSystem tampoco recalculaban nada
	# para él.
	EffectController.emit_signal("on_card_entered_play", 1, gold_card, Constants.Zone.RESERVA_ORO)


func _pay_oro_for_bot(coste: int) -> void:
	"""Paga 'coste' con Oro físico del bot: mueve las cartas de la Reserva al Oro Pagado
	(GameState.pagar_oro() solo actualiza el contador). El bot no elige cuál Oro gastar (no tiene
	cartas que dependan de eso, como Monitor Araucano): toma los primeros."""
	if coste <= 0:
		GameState.pagar_oro(1, coste)
		return
	if not GameState.pagar_oro(1, coste):
		return
	if not _main.opponent_gold or not _main.opponent_oro_pagado:
		return
	var moved := 0
	for c in _main.opponent_gold.get_children().duplicate():
		if moved >= coste:
			break
		if not is_instance_valid(c):
			continue
		_main.opponent_gold.remove_child(c)
		c.can_interact = false
		_main.opponent_oro_pagado.add_child(c)
		c.top_level = false
		c.set_zone(Constants.Zone.ORO_PAGADO)
		moved += 1
	if _main._gold_manager:
		_main._gold_manager.update_gold_containers_spacing()


func _affordable_allies_in_hand() -> Array:
	var result: Array = []
	if not _main._opponent_fan:
		return result
	var reserva: int = GameState.get_oro_reserva(1)
	var gm = _main._gold_manager
	for c in _main._opponent_fan.get_cards():
		if not is_instance_valid(c) or c.get("card_type") != Constants.CardType.ALIADO:
			continue
		if gm and (gm._no_more_cards_violation(c) or gm._card_play_locked(c) \
				or gm._errante_violation(c) or gm._play_limit_violation(c)):
			continue
		var coste: int = PaymentManager.calcular_coste_real(c)
		if coste <= reserva:
			result.append(c)
	return result


func _play_ally(card: Node) -> void:
	"""Versión reducida (solo Aliados) de GoldManager._play_card_to_field()
	+ _trigger_enter_play(), con player_id=1 en vez de hardcodeado a 0."""
	if not is_instance_valid(card):
		return
	var coste: int = PaymentManager.calcular_coste_real(card)
	_main._update_debug("Oponente juega: %s" % card.card_name)

	_main._opponent_fan.remove_card(card, false)
	# Ver _place_gold_if_possible() — mismo volteo, un Aliado en juego es
	# visible cara arriba para ambos jugadores, a diferencia de la mano.
	card.esta_oculta = false
	_pay_oro_for_bot(coste)
	TurnManager.on_card_played(card)

	card.can_interact = false
	_main.opponent_field.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	if _main._zone_manager:
		_main._zone_manager.pin_card_to_field_slot(card, _main.opponent_field)

	VisualManager.play_card_effect(card.card_cost)
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	await get_tree().process_frame
	card.can_interact = true

	# Pila de Respuesta Universal (arquitectura.md §10.53): como GoldManager.play_card() para el
	# humano, se abre la ventana para el rival antes del "Cuando entra en juego". Si se anula/cancela,
	# va al Cementerio sin disparar su ETB.
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card.get("card_name") else "", 1):
		await EffectController.destroy_card(1, card, false)
		if _main._gold_manager:
			_main._gold_manager._update_gold_display()
		return

	CardFactory.on_card_enters_play(card)
	if card.has_method("on_entered_play"):
		card.on_entered_play()
	if _main._gold_manager:
		_main._gold_manager._register_talisman_totem_tax(card)
		_main._gold_manager._register_talisman_second_play_tax(card)
	EffectController.emit_signal("on_card_entered_play", 1, card, Constants.Zone.LINEA_DEFENSA)
	await TriggerSystem._collect_triggers_for_event("on_enter_play", {
		"player_id": 1, "card": card, "zone": Constants.Zone.LINEA_DEFENSA
	})

	# Almirante Akari — "cuando tu oponente juegue cartas, puedes Anular": el bot juega esta carta, así
	# que el HUMANO (su rival) es quien puede responder con Akari — ver
	# EffectController.offer_counter_annul.
	await EffectController.offer_counter_annul(card)
	await EffectController.offer_flechar_xoon_annul(card)


func play_free_ally_from_data(card_data: Dictionary) -> void:
	"""Variante de _play_ally() para triggers que juegan un Aliado del bot sin pasar por la mano ni
	pagar (p.ej. Tangata Manu/Perder la Razón revelando el propio Castillo). El llamador
	(LookRevealPatternsA.gd) ya sacó card_data; aquí se crea el nodo y se pone en juego del lado
	del bot. Solo Aliados."""
	if card_data.get("tipo", -1) != Constants.CardType.ALIADO:
		return
	var card = _main._create_card(card_data, false)
	card.owner_id = 1
	card.controller_id = 1
	_main._connect_card_signals(card)
	_main._update_debug("Oponente juega gratis: %s" % card.card_name)

	card.can_interact = false
	_main.opponent_field.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	if _main._zone_manager:
		_main._zone_manager.pin_card_to_field_slot(card, _main.opponent_field)

	VisualManager.play_card_effect(card.card_cost)
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	await get_tree().process_frame
	card.can_interact = true

	# Misma ventana de respuesta que _play_ally() (§10.53).
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card.get("card_name") else "", 1):
		await EffectController.destroy_card(1, card, false)
		return

	CardFactory.on_card_enters_play(card)
	if card.has_method("on_entered_play"):
		card.on_entered_play()
	EffectController.emit_signal("on_card_entered_play", 1, card, Constants.Zone.LINEA_DEFENSA)
	await TriggerSystem._collect_triggers_for_event("on_enter_play", {
		"player_id": 1, "card": card, "zone": Constants.Zone.LINEA_DEFENSA
	})
	await EffectController.offer_counter_annul(card)
	await EffectController.offer_flechar_xoon_annul(card)


func put_free_gold_in_pagado_from_data(card_data: Dictionary) -> void:
	"""Variante de la rama Oro de GoldManager._trigger_enter_play para el bot (Perder la Razón: 'pon
	un Oro de ahí en tu Oro Pagado') — _trigger_enter_play está hardcodeado a jugador 0
	(emit_signal/evento con player_id=0 fijo, ver comentario en play_free_ally_from_data), así que
	no se puede reusar directo para el bot."""
	var data: Dictionary = card_data.duplicate()
	data["esta_oculta"] = false
	var gold_node = _main._create_card(data, false)
	gold_node.owner_id = 1
	gold_node.controller_id = 1
	gold_node.can_interact = true
	gold_node.scale = Constants.GOLD_CARD_SCALE
	gold_node.base_scale = Constants.GOLD_CARD_SCALE
	_main._connect_card_signals(gold_node)
	_main.opponent_oro_pagado.add_child(gold_node)
	gold_node.top_level = false
	gold_node.modulate = Color(0.6, 0.6, 0.6, 1.0)
	gold_node.set_zone(Constants.Zone.ORO_PAGADO)

	# §10.53 — mismo motivo que _play_ally/play_free_ally_from_data: la carta ya está colocada
	# visualmente (mismo criterio que GoldManager. _trigger_enter_play con el humano — la ventana no
	# bloquea la colocación física, solo los efectos de estado que siguen), pero agregar_oro_pagado
	# queda DESPUÉS de la ventana para no tener que revertirlo si se anula/cancela aquí.
	if await TriggerSystem.open_response_window(gold_node, str(gold_node.card_name) if gold_node.get("card_name") else "", 1):
		await EffectController.destroy_card(1, gold_node, false)
		return

	GameState.agregar_oro_pagado(1, 1)

	CardFactory.on_card_enters_play(gold_node)
	if gold_node.has_method("on_entered_play"):
		gold_node.on_entered_play()
	EffectController.emit_signal("on_card_entered_play", 1, gold_node, Constants.Zone.ORO_PAGADO)
	await TriggerSystem._collect_triggers_for_event("on_enter_play", {
		"player_id": 1, "card": gold_node, "zone": Constants.Zone.ORO_PAGADO
	})


func try_respond_with_activated_ability() -> bool:
	"""Capa 2 de la Pila de Respuesta Universal: dentro de la ventana de respuesta
	(ResponseWindowHandler._bot_pass_after()), el bot busca una habilidad ACTIVADA legal en sus
	cartas en juego y decide al azar si la usa. Devuelve true si activó algo (ActionPipeline lo
	detecta como respuesta y abre su propia ventana al rival).
	Alcance: habilidades sin coste, "una vez por turno", Oro o Girar. Pagar Oro va por
	GoldManager.pagar_coste() por jugador; Girar actúa sobre el Node. Los costos de descarte los
	resuelve ActionPipeline (el bot descarta la de menor coste)."""
	var fields: Array = [_main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo,
		_main.opponent_gold, _main.opponent_oro_pagado]
	var candidates: Array = []  # [{card, ability}]
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card) or KeywordManager.is_silenced(card):
				continue
			var ability_text: String = str(card.card_ability) if card.get("card_ability") != null else ""
			if ability_text.is_empty():
				continue
			var abilities: Array[Dictionary] = UniversalCardParser.parse_abilities(ability_text, str(card.get_instance_id()))
			for ability in abilities:
				if ability.get("ability_type", "") != "ACTIVATED":
					continue
				var cost_type = ability.get("cost_type", UniversalCardParser.CostType.NONE)
				if cost_type not in [UniversalCardParser.CostType.NONE, UniversalCardParser.CostType.ONCE_PER_TURN,
						UniversalCardParser.CostType.GOLD, UniversalCardParser.CostType.TAP]:
					continue
				if cost_type == UniversalCardParser.CostType.GOLD and not GameState.puede_pagar(1, ability.get("cost_amount", 0)):
					continue
				if cost_type == UniversalCardParser.CostType.TAP and card.get("is_tapped") == true:
					continue
				# "Una vez EN tu turno" (arquitectura.md §10.11) nunca vale dentro de una ventana de respuesta,
				# que es donde corre esta función.
				if ability.get("once_per_turn_own_turn_only", false):
					continue
				if ability.get("once_per_turn", false) or cost_type == UniversalCardParser.CostType.ONCE_PER_TURN:
					var card_id: String = str(card.get_instance_id())
					if UniversalCardParser.turn_registry.was_used(card_id, ability.get("ability_index", 0), GameManager.turn_serial):
						continue
				candidates.append({"card": card, "ability": ability})

	if candidates.is_empty() or randf() < 0.5:
		return false

	var chosen: Dictionary = candidates[randi() % candidates.size()]

	# Don de Amma necesita su manejador especial (_activate_don_de_amma(), SearchAbilityHandler_AI.gd,
	# que soporta owner_id 1): por el camino genérico (ONCE_PER_TURN → _execute_targeted_banish())
	# apuntaba a un Aliado en vez de a un Oro con habilidad de la Reserva.
	var raw_lower: String = str(chosen.ability.get("raw_text", "")).to_lower()
	var is_don_de_amma_pattern: bool = ("desterrar un oro" in raw_lower
		and "con habilidad" in raw_lower and "busca un oro" in raw_lower)
	if is_don_de_amma_pattern:
		if not _main._card_inspector or not _main._card_inspector._search_handler:
			return false
		await _main._card_inspector._search_handler._activate_don_de_amma(chosen.card, chosen.ability)
		return true

	var context := {"controller_id": 1, "source_card_node": chosen.card}
	var result: Dictionary = await ActionPipeline.activate_ability(chosen.card.card_data, chosen.ability, context)
	return result.get("success", false)


# =============================================================================
# ATAQUE — cada Aliado elegible ataca con 50% de probabilidad
# =============================================================================
func take_ataque_actions() -> void:
	await get_tree().create_timer(0.8).timeout
	await _wait_until_settled()
	if not (GameManager.is_game_active and GameManager.active_player_id == 1 \
			and GameManager.current_phase == Constants.Phase.ATAQUE):
		return
	if _main.opponent_field and _main._card_interaction:
		for ally in _main.opponent_field.get_children().duplicate():
			if not is_instance_valid(ally):
				continue
			var check: Dictionary = TurnManager.can_attack(ally)
			if check.get("can_attack", false) and randf() < 0.5:
				# _declare_attacker() es agnóstico de jugador (controller_id decide el contenedor) y hace todo:
				# valida, reparenta a la Línea de Ataque (set_zone incluido) y marca el tinte de "atacando".
				# Reusarlo evita desincronizar zona y visual.
				await _main._card_interaction._declare_attacker(ally)

	await get_tree().create_timer(0.6).timeout
	await _wait_until_settled()
	if GameManager.is_game_active and GameManager.active_player_id == 1 \
			and GameManager.current_phase == Constants.Phase.ATAQUE:
		_main._update_debug("Oponente confirma atacantes")
		await GameManager.confirm_attackers()


# =============================================================================
# AGRUPACIÓN — reagrupamiento de Oro (espejo de GoldManager._reset_gold())
# =============================================================================
func reset_gold() -> void:
	GameState.reagrupar_oro(1)
	# uriko-hime: "tu oponente sólo pueda agrupar hasta cuatro Oros en su próxima Agrupación".
	var cap: int = int(RuleState.take_pending("regroup_cap", 1)) if RuleState.has_pending("regroup_cap", 1) else -1
	var regrouped := 0
	if _main.opponent_oro_pagado:
		for card in _main.opponent_oro_pagado.get_children().duplicate():
			if is_instance_valid(card):
				# El huascar: "no puede ser agrupado el próximo turno"
				if int(card.get_meta("no_regroup_turn", -1)) == GameManager.turn_serial or card.get_meta("never_regroup", false) \
						or (cap >= 0 and regrouped >= cap):  # alma del viento, uriko-hime
					GameState.agregar_oro_reserva(1, -1)
					GameState.agregar_oro_pagado(1, 1)
					continue
				regrouped += 1
				_main.opponent_oro_pagado.remove_child(card)
				card.can_interact = false
				_main.opponent_gold.add_child(card)
				card.set_zone(Constants.Zone.RESERVA_ORO)
				if _main._gold_manager:
					_main._gold_manager.update_gold_containers_spacing()
				await get_tree().process_frame
				card.can_interact = true
