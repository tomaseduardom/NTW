extends EasyBotController
class_name RemotePlayerController

const PhaseStartWindowScript = preload("res://scripts/core/game/PhaseStartWindow.gd")
const BlockScript = preload("res://scripts/core/effects/triggers/BlockPatterns.gd")  # bloquear a varios (Elías)
## RemotePlayerController — reemplaza a EasyBotController cuando el jugador 1 es una persona
## conectada por red (NetworkClient). Extiende EasyBotController y sobreescribe cada punto de
## DECISIÓN para preguntarle al Remoto por red en vez de elegir al azar. Misma superficie pública
## que la clase base: los llamadores (`_main._easy_bot.<método>`) no saben qué hay del otro lado.
## Ver docs/plans/2026-09-09-multiplayer-remoto-design.md y
## docs/plans/2026-09-20-remote-multiplayer-parity.md.
## Protocolo: cada método manda {"op":"prompt","kind":...} con lo que la persona necesita ver (su
## propia mano/campo no está oculta para ella, aunque el Anfitrión la vea con esta_oculta = true) y
## espera {"op":"intent","kind":...}. Las cartas se identifican por get_instance_id() (estable
## mientras exista el Node). Nunca se manda la mano/mazo ocultos del Anfitrión. El tablero se
## refleja aparte con GameStateBroadcaster/RemoteMirrorController.

func _await_intent(expected_kinds: Array) -> Dictionary:
	"""Lógica movida a NetworkClient.await_intent (la necesita también SelectionManager.gd para la
	Fase 3 del plan de paridad) — este wrapper se deja tal cual para no tocar los 5 llamadores
	existentes de este archivo."""
	return await NetworkClient.await_intent(expected_kinds)


func _card_ref(card: Node) -> String:
	return str(card.get_instance_id())


func _find_card_by_id(id_str: String) -> Node:
	if id_str.is_empty() or not id_str.is_valid_int():
		return null
	var obj: Object = instance_from_id(int(id_str))
	if obj is Node and is_instance_valid(obj):
		return obj as Node
	return null


func _card_public_data(card: Node) -> Dictionary:
	"""Datos de UNA carta propia del Remoto para mandarle por red (no está oculta para su dueño).
	card_data completo (el mismo dict de Card.load_from_data()), para dibujar la carta real, más
	card_id para las respuestas."""
	if not is_instance_valid(card):
		return {}
	var data: Dictionary = card.card_data.duplicate(true) if card.get("card_data") != null else {}
	data["card_id"] = _card_ref(card)
	return data


func _affordable_cards_in_hand(allowed_types: Array) -> Array:
	"""Como EasyBotController._affordable_allies_in_hand(), pero para
	cualquier tipo de carta (no solo Aliado) — el bot no juega Armas/
	Talismanes/Tótems todavía (fuera de alcance de ESE archivo), pero el
	Remoto sí necesita poder ofrecérselos a la persona real. No se tocó
	_affordable_allies_in_hand() para no darle alcance nuevo al bot sin que
	se haya pedido."""
	var result: Array = []
	if not _main._opponent_fan:
		return result
	var reserva: int = GameState.get_oro_reserva(1)
	var gm = _main._gold_manager
	for c in _main._opponent_fan.get_cards():
		if not is_instance_valid(c) or not (c.get("card_type") in allowed_types):
			continue
		if gm and (gm._no_more_cards_violation(c) or gm._card_play_locked(c) \
				or gm._errante_violation(c) or gm._play_limit_violation(c)):
			continue
		var coste: int = PaymentManager.calcular_coste_real(c)
		if coste <= reserva:
			result.append(c)
	return result


# =============================================================================
# MULLIGAN: MulliganController._end_mulligan_phase() llama aquí directo si hay un Remoto conectado;
# si no, sigue con draw_initial_hand().
# =============================================================================
func run_mulligan(initial_count: int) -> void:
	"""Mulligan real para el jugador 1: dibuja la mano, le pregunta al Remoto
	si la mantiene o la vuelve a barajar (con una carta menos, como cualquier
	mulligan DAR), hasta que mantenga o llegue a 0. Mulligan gratis (DAR abril 2026): una vez, con
	uno o menos Oros en la mano, la muestra al Anfitrión y Roba la misma cantidad."""
	var count := initial_count
	var free_used := false
	while true:
		for i in range(count):
			await _main._zone_manager.draw_card(1, false)
		var hand_cards: Array = _main._opponent_fan.get_cards().duplicate()
		var hand_data: Array = []
		for c in hand_cards:
			if is_instance_valid(c):
				hand_data.append(_card_public_data(c))
		var golds: int = MulliganController.gold_count(hand_data)
		var free_ok: bool = not free_used and golds <= 1 and not hand_data.is_empty()

		NetworkClient.send_message({"op": "prompt", "kind": "mulligan", "hand": hand_data,
			"free_available": free_ok, "golds": golds})
		var intent: Dictionary = await _await_intent(["mulligan_choice"])

		var free: bool = intent.get("free", false) and free_ok
		if free:
			free_used = true
			await _main._mulligan_ctrl.remote_reveal_to_host(hand_data)
			_main._update_debug("Tu oponente hace el mulligan gratis: muestra su mano (%d Oro%s)" % [golds, "" if golds == 1 else "s"])
		elif intent.get("keep", true) or count - 1 <= 0:
			return

		for c in hand_cards:
			if is_instance_valid(c):
				var data: Dictionary = c.card_data.duplicate()
				data["esta_oculta"] = true
				_main._opponent_fan.remove_card(c, true)
				_main.opponent_deck.append(data)
		_main._zone_manager.shuffle_deck(1)
		if not free:
			count -= 1


# =============================================================================
# JUGAR ARMA/TALISMÁN/TÓTEM — mismo criterio que EasyBotController._play_ally() (clase base), para
# los 3 tipos que el bot no juega (docs/plans/2026-09-20-remote-multiplayer-parity.md, Fase 1).
# =============================================================================
func _play_totem_remote(card: Node) -> void:
	if not is_instance_valid(card):
		return
	var coste: int = PaymentManager.calcular_coste_real(card)
	_main._update_debug("Oponente juega Tótem: %s" % card.card_name)

	_main._opponent_fan.remove_card(card, false)
	card.esta_oculta = false
	_pay_oro_for_bot(coste)
	TurnManager.on_card_played(card)

	card.can_interact = false
	_main.opponent_linea_apoyo.add_child(card)
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_APOYO)
	card.scale = Constants.TOTEM_CARD_SCALE
	card.base_scale = Constants.TOTEM_CARD_SCALE
	if _main._zone_manager:
		_main._zone_manager.pin_card_to_field_slot(card, _main.opponent_linea_apoyo)

	VisualManager.play_card_effect(card.card_cost)
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	await get_tree().process_frame
	card.can_interact = true

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
	EffectController.emit_signal("on_card_entered_play", 1, card, Constants.Zone.LINEA_APOYO)
	await TriggerSystem._collect_triggers_for_event("on_enter_play", {
		"player_id": 1, "card": card, "zone": Constants.Zone.LINEA_APOYO
	})
	await EffectController.offer_counter_annul(card)
	await EffectController.offer_flechar_xoon_annul(card)


func _choose_wielder_remote(weapon: Node) -> Node:
	"""Pide al Remoto que elija portador para un Arma que está jugando —
	espejo de GoldManager._select_weapon_wielder(), pero preguntando por
	red en vez de abrir CardInteractionModule local."""
	if not _main._gold_manager or not _main._gold_manager.has_method("_get_eligible_weapon_wielders"):
		return null
	var eligible: Array = _main._gold_manager._get_eligible_weapon_wielders()
	if eligible.is_empty():
		return null
	var payload: Array = []
	for w in eligible:
		payload.append(_card_public_data(w))
	NetworkClient.send_message({"op": "prompt", "kind": "choose_wielder", "weapon": _card_public_data(weapon), "candidates": payload})
	var intent: Dictionary = await _await_intent(["choose_wielder"])
	var chosen := _find_card_by_id(str(intent.get("card_id", "")))
	if chosen and chosen in eligible:
		return chosen
	return null


func _play_weapon_remote(card: Node) -> bool:
	"""true si el Arma quedó equipada (false: sin portador o cancelado)."""
	if not is_instance_valid(card):
		return false
	if not _main._gold_manager or not _main._gold_manager._player_has_ally_in_play():
		NetworkClient.send_message({"op": "prompt", "kind": "error", "message": "Sin Aliados en juego para portar el Arma"})
		return false
	var coste: int = PaymentManager.calcular_coste_real(card)
	var wielder := await _choose_wielder_remote(card)
	if not wielder or not is_instance_valid(wielder):
		return false
	# En la Guerra de Talismanes (Lobo Sagrado): turno alternado, §64.
	PriorityManager.begin_guerra_action(1)

	_main._opponent_fan.remove_card(card, false)
	card.esta_oculta = false
	_pay_oro_for_bot(coste)
	TurnManager.on_card_played(card)
	card.owner_id = 1
	card.controller_id = 1

	if _main._gold_manager.has_method("_equip_weapon"):
		await _main._gold_manager._equip_weapon(card, wielder)
	PriorityManager.end_guerra_action()
	return true


func _play_talisman_remote(card: Node) -> void:
	if not is_instance_valid(card):
		return
	var coste: int = PaymentManager.calcular_coste_real(card)
	_main._update_debug("Oponente juega talismán: %s" % card.card_name)

	_main._opponent_fan.remove_card(card, false)
	card.esta_oculta = false
	_pay_oro_for_bot(coste)
	# GoldManager._play_talisman() (§64): el mismo camino que el Anfitrión, que manda el Talismán a su
	# destino al resolver.
	PriorityManager.begin_guerra_action(1)
	await _main._gold_manager._play_talisman(card)
	PriorityManager.end_guerra_action()


# =============================================================================
# VIGILIA — igual que la base, pero cada acción la elige el Remoto por red
# =============================================================================
func take_vigilia_actions() -> void:
	if Constants.VERBOSE_DIAG_LOGS:
		print("[RemotePlayerController] take_vigilia_actions() llamada — opponent_fan=%s activo=%s jugador=%d fase=%s" % [
			str(_main._opponent_fan), str(GameManager.is_game_active), GameManager.active_player_id,
			Constants.PHASE_NAMES.get(GameManager.current_phase, "?")
		])
	if not _main._opponent_fan:
		return
	while true:
		if not (GameManager.is_game_active and GameManager.active_player_id == 1 \
				and GameManager.current_phase == Constants.Phase.VIGILIA):
			return

		var gold_candidates: Array = []
		for c in _main._opponent_fan.get_cards():
			if not is_instance_valid(c) or c.get("card_type") != Constants.CardType.ORO:
				continue
			if not TurnManager.can_place_oro(GameManager.current_phase, c):
				continue
			if _main._gold_manager and (_main._gold_manager._no_more_cards_violation(c) \
					or _main._gold_manager._card_play_locked(c)):
				continue
			gold_candidates.append(_card_public_data(c))

		var ally_candidates: Array = []
		for c in _affordable_allies_in_hand():
			ally_candidates.append(_card_public_data(c))
		var weapon_candidates: Array = []
		for c in _affordable_cards_in_hand([Constants.CardType.ARMA]):
			weapon_candidates.append(_card_public_data(c))
		var talisman_candidates: Array = []
		for c in _affordable_cards_in_hand([Constants.CardType.TALISMAN]):
			talisman_candidates.append(_card_public_data(c))
		var totem_candidates: Array = []
		for c in _affordable_cards_in_hand([Constants.CardType.TOTEM]):
			totem_candidates.append(_card_public_data(c))

		var hand_data: Array = []
		for c in _main._opponent_fan.get_cards():
			if is_instance_valid(c):
				hand_data.append(_card_public_data(c))
		# Habilidades activadas en su propia Vigilia, también las de "una vez en tu turno" (p.ej. Miguel).
		var ability_candidates: Array = _collect_activatable_abilities()

		if Constants.VERBOSE_DIAG_LOGS:
			print("[RemotePlayerController] Mandando prompt de vigilia — mano=%d oro=%d aliados=%d armas=%d talismanes=%d totems=%d" % [
				hand_data.size(), gold_candidates.size(), ally_candidates.size(),
				weapon_candidates.size(), talisman_candidates.size(), totem_candidates.size()
			])
		NetworkClient.send_message({
			"op": "prompt", "kind": "vigilia",
			"hand": hand_data,
			"gold_candidates": gold_candidates,
			"ally_candidates": ally_candidates,
			"weapon_candidates": weapon_candidates,
			"talisman_candidates": talisman_candidates,
			"totem_candidates": totem_candidates,
			"abilities": _abilities_payload(ability_candidates),
			"gold_reserva": GameState.get_oro_reserva(1),
			"can_attack": TurnManager.player_can_attack(1),
		})
		var intent: Dictionary = await _await_intent(["place_gold", "play_card", "end_vigilia", "activate_ability"])

		match intent.get("kind", ""):
			"place_gold":
				var card := _find_card_by_id(str(intent.get("card_id", "")))
				if card and is_instance_valid(card) and card.get("card_type") == Constants.CardType.ORO:
					await _place_gold_card(card)
			"play_card":
				var card := _find_card_by_id(str(intent.get("card_id", "")))
				if card and is_instance_valid(card):
					match card.get("card_type"):
						Constants.CardType.ALIADO:
							await _play_ally(card)
						Constants.CardType.ARMA:
							await _play_weapon_remote(card)
						Constants.CardType.TALISMAN:
							await _play_talisman_remote(card)
						Constants.CardType.TOTEM:
							await _play_totem_remote(card)
			"activate_ability":
				await _activate_chosen_ability(str(intent.get("card_id", "")), int(intent.get("ability_index", 0)),
					ability_candidates)
			"end_vigilia":
				if GameManager.is_game_active and GameManager.active_player_id == 1 \
						and GameManager.current_phase == Constants.Phase.VIGILIA:
					if not TurnManager.player_can_attack(1):
						_main._update_debug("Oponente pasa a la Fase Final")
						GameManager._end_batalla()
					else:
						_main._update_debug("Oponente ataca")
						GameManager.proceed_to_battle()
				return
			_:
				return


# =============================================================================
# ATAQUE — el Remoto elige QUIÉNES atacan (en vez del 50% al azar del bot)
# =============================================================================
func take_ataque_actions() -> void:
	if not (GameManager.is_game_active and GameManager.active_player_id == 1 \
			and GameManager.current_phase == Constants.Phase.ATAQUE):
		return

	var attackable: Array = []
	if _main.opponent_field:
		for ally in _main.opponent_field.get_children():
			if not is_instance_valid(ally):
				continue
			var check: Dictionary = TurnManager.can_attack(ally)
			if check.get("can_attack", false):
				attackable.append(ally)

	var payload: Array = []
	for a in attackable:
		payload.append(_card_public_data(a))
	NetworkClient.send_message({"op": "prompt", "kind": "ataque", "attackable": payload})
	var intent: Dictionary = await _await_intent(["declare_attackers"])

	if _main._card_interaction:
		var chosen_ids: Array = intent.get("card_ids", [])
		for id_str in chosen_ids:
			var ally := _find_card_by_id(str(id_str))
			if ally and ally in attackable:
				await _main._card_interaction._declare_attacker(ally)

	if GameManager.is_game_active and GameManager.active_player_id == 1 \
			and GameManager.current_phase == Constants.Phase.ATAQUE:
		_main._update_debug("Oponente confirma atacantes")
		await GameManager.confirm_attackers()


# =============================================================================
# CAPA 2 DE LA PILA DE RESPUESTA UNIVERSAL — responder con una habilidad
# activada, elegida por el Remoto en vez de al azar
# =============================================================================
func try_respond_with_activated_ability() -> bool:
	"""Camino viejo de respuesta (prompt 'response_window'). ResponseWindowHandler ya no lo usa contra
	un Remoto (ver on_priority_received()); se conserva por si otro llamador de la clase base lo
	invoca."""
	var candidates: Array = _collect_activatable_abilities()
	var candidate_payload: Array = _abilities_payload(candidates)
	NetworkClient.send_message({"op": "prompt", "kind": "response_window", "candidates": candidate_payload})
	var intent: Dictionary = await _await_intent(["activate_ability", "pass"])
	if intent.get("kind", "") != "activate_ability":
		return false
	return await _activate_chosen_ability(str(intent.get("card_id", "")), int(intent.get("ability_index", -1)), candidates)


func _collect_activatable_abilities() -> Array:
	"""Habilidades activadas que el Remoto puede usar ahora: [{card, ability}]. Mismo filtro que los
	botones del Anfitrión (CardInspectionLayer.usable_abilities_for(card, 1)), incluidas las cartas
	de su mano con habilidades usables desde ahí."""
	var candidates: Array = []
	if not _main._card_inspector:
		return candidates
	var cards: Array = []
	for field in [_main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo,
			_main.opponent_gold, _main.opponent_oro_pagado,
			_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo]:
		if not field:
			continue
		for card in field.get_children():
			if is_instance_valid(card):
				cards.append(card)
	if _main._opponent_fan:
		cards.append_array(_main._opponent_fan.get_cards())
	cards.append_array(_cemetery_proxies())
	cards.append_array(_exile_proxies())
	for card in cards:
		# usable_abilities_for() ya descarta las que no controla el jugador 1
		# (controller_id), así que las del lado del Anfitrión solo entran si
		# el Remoto las controla (p.ej. jugadas con Miguel).
		for entry in _main._card_inspector.usable_abilities_for(card, 1):
			candidates.append({"card": card, "ability": entry.ability})
	return candidates


## Cartas del Cementerio del Remoto con habilidad usable desde ahí (Duelo Espacial; también Espada
## del Juicio, Visión Heroica, Drácula): el Cementerio no tiene Nodos, así que se crean Nodos
## temporales (fuera del árbol, igual que el visor del Cementerio del Anfitrión). Viven hasta la
## próxima consulta para que el intent pueda ubicarlos por card_id.
var _cemetery_proxy_nodes: Array = []

func _cemetery_proxies() -> Array:
	for n in _cemetery_proxy_nodes:
		if is_instance_valid(n) and not n.is_inside_tree():
			n.queue_free()
	_cemetery_proxy_nodes.clear()
	if not _main._card_inspector:
		return []
	for data in CardManager.get_cemetery(1):
		if not _main._card_inspector._ability_is_cementerio_usable(str(data.get("habilidad", ""))):
			continue
		var node = _main._create_card(data, false)
		node.owner_id = 1
		node.controller_id = 1
		node.set_zone(Constants.Zone.CEMENTERIO)
		_cemetery_proxy_nodes.append(node)
	return _cemetery_proxy_nodes.duplicate()


## Igual que _cemetery_proxies(), para el Destierro (sandraudiga).
var _exile_proxy_nodes: Array = []

func _exile_proxies() -> Array:
	for n in _exile_proxy_nodes:
		if is_instance_valid(n) and not n.is_inside_tree():
			n.queue_free()
	_exile_proxy_nodes.clear()
	if not _main._card_inspector:
		return []
	for data in CardManager.get_exile(1):
		if not _main._card_inspector._ability_is_destierro_usable(str(data.get("habilidad", ""))):
			continue
		var node = _main._create_card(data, false)
		node.owner_id = 1
		node.controller_id = 1
		node.set_zone(Constants.Zone.DESTIERRO)
		_exile_proxy_nodes.append(node)
	return _exile_proxy_nodes.duplicate()


func _abilities_payload(candidates: Array) -> Array:
	var payload: Array = []
	for c in candidates:
		# card_data completo (no solo nombre/coste curados) para que RemoteMirrorController pueda mostrar
		# la carta real, mismo criterio que el resto de los prompts (ver _card_public_data).
		var entry: Dictionary = c.card.card_data.duplicate(true) if c.card.get("card_data") != null else {}
		entry["card_id"] = _card_ref(c.card)
		entry["ability_index"] = c.ability.get("ability_index", 0)
		entry["cost_text"] = c.ability.get("cost_text", "")
		entry["effect_text"] = c.ability.get("effect_text", "")
		payload.append(entry)
	return payload


func _activate_chosen_ability(card_id: String, ability_index: int, candidates: Array) -> bool:
	var chosen_card := _find_card_by_id(card_id)
	if not chosen_card:
		return false
	var chosen_ability: Dictionary = {}
	for c in candidates:
		if c.card == chosen_card and int(c.ability.get("ability_index", -1)) == ability_index:
			chosen_ability = c.ability
			break
	if chosen_ability.is_empty():
		return false
	# Misma lógica que el botón del Anfitrión (patrones especiales incluidos, p.ej. Miguel).
	if _main._card_inspector:
		await _main._card_inspector.activate_ability_for(chosen_card, chosen_ability, 1)
		return true
	var context := {"controller_id": 1, "source_card_node": chosen_card}
	var result: Dictionary = await ActionPipeline.activate_ability(chosen_card.card_data, chosen_ability, context)
	return result.get("success", false)


# =============================================================================
# BOTÓN DE PASO SIMÉTRICO ONLINE
# =============================================================================
# Cada vez que el jugador 1 (Remoto) recibe la prioridad, el Anfitrión decide con la misma regla que
# para el jugador 0 (PriorityManager.needs_real_decision()):
# - sin decisión real (respuesta a su propia carta, atacante en Bloqueo, pila recién vaciada) → pasa
# solo;
# - Ventana de Respuesta real → botón de paso con cuenta regresiva de 5 s; puede responder con un
# Talismán instantáneo o una habilidad activada; al vencer, el Anfitrión pasa por él;
# - Guerra de Talismanes → puede jugar Talismanes/habilidades, sin plazo;
# - Bloqueo (defensor) → elige bloqueadores, sin plazo.
# El prompt viaja con window_id (= PriorityManager._window_generation) y la respuesta debe traer el
# mismo: una respuesta tardía de una ventana ya cerrada se descarta.
func on_priority_received() -> void:
	if not (PriorityManager.priority_window_active and PriorityManager.current_priority_player == 1):
		return
	var window_id: int = PriorityManager._window_generation
	var context: int = PriorityManager.current_priority_context

	if not PriorityManager.needs_real_decision(1):
		await get_tree().create_timer(0.2).timeout
		_pass_if_still_current(window_id)
		return

	var ability_candidates: Array = []
	var talisman_cards: Array = []
	var block_options: Array = []
	var attackers_payload: Array = []
	var timeout: float = 0.0
	var button_text: String = "Pasar [P]"
	match context:
		PriorityManager.PriorityContext.RESPONSE_WINDOW:
			timeout = PriorityManager.ONLINE_RESPONSE_TIMEOUT
			ability_candidates = _collect_activatable_abilities()
			talisman_cards = _playable_talismans_now(true)
		PriorityManager.PriorityContext.GUERRA_TALISMANES:
			button_text = "Daño [P]"
			ability_candidates = _collect_activatable_abilities()
			talisman_cards = _playable_talismans_now(false)
			# Armas con "Puedes jugar Armas en Guerra de Talismanes" (Lobo
			# Sagrado) en el lado del Remoto — igual que el Anfitrión (§65).
			var gm = _main._gold_manager
			if gm and gm.has_phase_exception(Constants.CardType.ARMA, 1) and gm._player_has_ally_in_play():
				talisman_cards.append_array(_affordable_cards_in_hand([Constants.CardType.ARMA]))
		PriorityManager.PriorityContext.PHASE_START:
			# Comienzo de fase: las cartas que su texto deja jugar ahora (PhaseStartWindow), cualquier tipo.
			# 5 s, como el Anfitrión.
			timeout = PhaseStartWindowScript.TIMEOUT
			talisman_cards = PhaseStartWindowScript.playable_cards(1)
		PriorityManager.PriorityContext.BLOCK_DECLARATION:
			button_text = "Confirmar bloqueos [P]"
			for a in GameManager.attackers:
				if is_instance_valid(a):
					attackers_payload.append(_card_public_data(a))
			block_options = _block_options()
			if block_options.is_empty():
				# Nada que bloquear (información pública) — no hace falta
				# hacer esperar al Remoto por un click sin opciones.
				await get_tree().create_timer(0.4).timeout
				_pass_if_still_current(window_id)
				return

	var talisman_payload: Array = []
	for c in talisman_cards:
		talisman_payload.append(_card_public_data(c))
	NetworkClient.send_message({
		"op": "prompt", "kind": "priority",
		"window_id": window_id,
		"context": PriorityManager.current_context,
		"button_text": button_text,
		"timeout": timeout,
		"abilities": _abilities_payload(ability_candidates),
		"talismans": talisman_payload,
		"attackers": attackers_payload,
		"blockers": block_options,
	})

	var intent: Dictionary = await _await_priority_intent(window_id, timeout)
	NetworkClient.send_message({"op": "priority_closed", "window_id": window_id})
	if not _is_current_window(window_id):
		return  # la ventana cerró por otro camino mientras se esperaba

	match str(intent.get("action", "pass")):
		"ability":
			var used: bool = await _activate_chosen_ability(
				str(intent.get("card_id", "")), int(intent.get("ability_index", -1)), ability_candidates)
			if used:
				return  # la habilidad quedó en la pila — el Paso D la detecta como respuesta
		"play":
			var card := _find_card_by_id(str(intent.get("card_id", "")))
			if card and card in talisman_cards and context == PriorityManager.PriorityContext.PHASE_START:
				await _play_phase_start_card(card, window_id)
				return
			if card and card in talisman_cards:
				if card.get("card_type") != Constants.CardType.ARMA:
					await _play_talisman_remote(card)
					return
				if await _play_weapon_remote(card):
					return
				# Canceló el portador: sigue siendo su prioridad en la Guerra.
				if _is_current_window(window_id):
					on_priority_received()
					return
		"blocks":
			_apply_remote_blocks(intent.get("pairs", []))
	_pass_if_still_current(window_id)


func _play_phase_start_card(card: Node, window_id: int) -> void:
	"""Juega una carta en la ventana de comienzo de fase (PhaseStartWindow).
	Si jugarla no abrió ninguna Ventana de Respuesta, la palabra pasa al
	Anfitrión igual."""
	match int(card.get("card_type")):
		Constants.CardType.ALIADO:
			await _play_ally(card)
		Constants.CardType.TOTEM:
			await _play_totem_remote(card)
		Constants.CardType.ARMA:
			if not await _play_weapon_remote(card):
				_pass_if_still_current(window_id)
				return
		_:
			await _play_talisman_remote(card)
	if _is_current_window(window_id):
		PriorityManager.start_priority_window(PriorityManager.PriorityContext.PHASE_START, 0)


func _is_current_window(window_id: int) -> bool:
	return PriorityManager._window_generation == window_id and PriorityManager.priority_window_active \
		and PriorityManager.current_priority_player == 1


func _pass_if_still_current(window_id: int) -> void:
	if _is_current_window(window_id):
		PriorityManager.pass_priority()


func _await_priority_intent(window_id: int, timeout: float) -> Dictionary:
	"""Espera {"op":"intent","kind":"priority_response","window_id":window_id}.
	Devuelve {} si vence el plazo (timeout > 0, con 0.5s de gracia por la
	latencia de red) o si la ventana deja de ser la actual."""
	var state := {"done": false, "intent": {}}
	var on_message := func(data: Dictionary) -> void:
		if state.done or data.get("op", "") != "intent" or data.get("kind", "") != "priority_response":
			return
		if int(data.get("window_id", -1)) != window_id:
			return
		state.intent = data
		state.done = true
	NetworkClient.message_received.connect(on_message)
	var elapsed: float = 0.0
	while not state.done:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
		if timeout > 0.0 and elapsed >= timeout + 0.5:
			break
		if not _is_current_window(window_id):
			break
	NetworkClient.message_received.disconnect(on_message)
	return state.intent


func _playable_talismans_now(response_only: bool) -> Array:
	"""Talismanes de la mano del Remoto que puede pagar y jugar en esta
	ventana: solo los de respuesta instantánea (Red de Plata, Sacrificio
	Solar...) en una Ventana de Respuesta; cualquiera en Guerra de Talismanes."""
	var result: Array = []
	var gm = _main._gold_manager
	for c in _affordable_cards_in_hand([Constants.CardType.TALISMAN]):
		if response_only and not (gm and gm._is_response_only_talisman(c)):
			continue
		result.append(c)
	return result


func _block_options() -> Array:
	"""[{card_data..., card_id, can_block: [attacker_id...], max_blocks}] para cada Aliado
	del Remoto en Línea de Defensa que puede bloquear a algún atacante. max_blocks: a cuántos
	atacantes puede bloquear a la vez (Elías: 2, BlockPatterns.max_blocks())."""
	var options: Array = []
	if not _main.opponent_field:
		return options
	for blocker in _main.opponent_field.get_children():
		if not is_instance_valid(blocker) or blocker.get("card_type") != Constants.CardType.ALIADO:
			continue
		if not BlockScript.can_block_more(blocker) or not ContinuousEffectManager.can_block(blocker):
			continue
		var valid_attackers: Array = []
		for attacker in GameManager.attackers:
			if not is_instance_valid(attacker) or GameManager.blockers.has(attacker):
				continue
			if BattleManager.is_valid_block(attacker, blocker).get("valid", false):
				valid_attackers.append(_card_ref(attacker))
		if valid_attackers.is_empty():
			continue
		var entry: Dictionary = _card_public_data(blocker)
		entry["can_block"] = valid_attackers
		entry["max_blocks"] = BlockScript.max_blocks(blocker)
		options.append(entry)
	return options


func _apply_remote_blocks(pairs: Array) -> void:
	"""Mismo efecto que CardInteractionModule._declare_blocker() del humano,
	pero validando cada par contra las reglas del lado del Anfitrión."""
	for pair in pairs:
		if not (pair is Dictionary):
			continue
		var blocker := _find_card_by_id(str(pair.get("blocker_id", "")))
		var attacker := _find_card_by_id(str(pair.get("attacker_id", "")))
		if not blocker or not attacker or not (attacker in GameManager.attackers):
			continue
		if blocker.get_parent() != _main.opponent_field or not BlockScript.can_block_more(blocker):
			continue
		if GameManager.blockers.has(attacker) or not ContinuousEffectManager.can_block(blocker):
			continue
		if not BattleManager.is_valid_block(attacker, blocker).get("valid", false):
			continue
		GameManager.declare_blocker(blocker, attacker)
		var tween = create_tween()
		tween.tween_property(blocker, "modulate", Color(0.4, 0.7, 1.0, 1.0), 0.2)
		_main._update_debug("Oponente: %s bloquea a %s" % [str(blocker.get("card_name")), str(attacker.get("card_name"))])
