extends EasyBotController
class_name RemotePlayerController
## RemotePlayerController — reemplaza a EasyBotController cuando el jugador 1
## es una PERSONA real conectada por red (NetworkClient), no una IA sin
## estrategia. Extiende EasyBotController y sobreescribe cada punto de
## DECISIÓN (Vigilia, Ataque, respuesta con habilidad activada) para que en
## vez de elegir al azar, le pregunte al Remoto por red y espere su
## respuesta — misma superficie pública que la clase base, así que ningún
## llamador existente (PhaseFlowController, ActionPipeline,
## ResponseWindowHandler, LookRevealPatternsA.gd — todos invocan
## `_main._easy_bot.<método>` sin saber qué hay del otro lado) necesitó
## cambiar una sola línea. Ver docs/plans/2026-09-09-multiplayer-remoto-
## design.md e iterative-booping-abelson.md (Fase B).
##
## Alcance de ESTE incremento (Fase B, "bucle de turno básico" — mismo techo
## que el bot hoy, pero una persona real detrás): poner Oro, jugar Aliados de
## la mano, declarar atacantes, responder ventanas con habilidades activadas
## sin costo de Descarte, y el mulligan inicial real (que hoy ni siquiera
## existe como decisión para el jugador 1). La paridad completa (cualquier
## carta, cualquier elección de SelectionManager) es Fase C, todavía no
## empezada — reset_gold()/_pay_oro_for_bot()/play_free_ally_from_data()/
## put_free_gold_in_pagado_from_data() se heredan tal cual de la clase base
## (no hay decisión real que preguntar en Agrupación, y los triggers "juega
## gratis" siguen sin alcanzar al jugador 1 por network hasta Fase C).
##
## Protocolo: cada método manda al Remoto un mensaje {"op":"prompt",
## "kind":...} con los datos que la persona necesita ver — su propia mano/
## campo NO está oculta para ella (aunque en la pantalla del Anfitrión se
## vea como 'oponente' con esta_oculta=true, eso es solo la vista LOCAL del
## Anfitrión) — y espera un {"op":"intent","kind":...} de vuelta. Las
## cartas se identifican por get_instance_id() (mismo criterio ya usado por
## turn_registry en otras partes del proyecto para distinguir copias
## físicas durante la sesión) — estable mientras el Node exista, no
## persiste entre partidas ni hace falta que persista.
##
## Decisión de alcance (2026-09-11, sin protocolo de instrucciones
## incremental completo todavía): en vez de streaming continuo de
## move_card/reveal_card por cada transición de zona (la forma "completa"
## descrita en el diseño), cada prompt de este archivo embebe un snapshot
## de los datos que el Remoto necesita en ESE momento (su propia mano/
## campo, más lo público). Esto respeta la niebla de guerra (nunca se
## manda la mano/mazo ocultos del Anfitrión) y alcanza para que el Remoto
## tome decisiones legales, pero significa que el Remoto no ve en tiempo
## real lo que el Anfitrión hace en SU PROPIO turno (solo se entera en el
## próximo prompt que le toque). El streaming incremental completo (fidelidad
## visual total) queda pendiente — ver nota en el plan.

func _await_intent(expected_kinds: Array) -> Dictionary:
	"""2026-09-30: lógica movida a NetworkClient.await_intent() (la necesita
	también SelectionManager.gd para la Fase 3 del plan de paridad) — este
	wrapper se deja tal cual para no tocar los 5 llamadores existentes de
	este archivo."""
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
	"""Datos de UNA carta propia del Remoto para mandarle por red — no está
	oculta para su propio dueño, aunque en la pantalla del Anfitrión se vea
	con esta_oculta=true (eso es solo la vista LOCAL del Anfitrión, no un
	límite real de información para la persona a la que pertenece).
	2026-10-07, a pedido del usuario ("no sale mi mulligan bonito, el
	abanico de cartas está todo escrito"): antes mandaba solo 5 campos
	curados (nombre/coste/tipo/habilidad), suficientes para los prompts de
	puro texto pero no para dibujar la carta real — ahora manda el
	card_data COMPLETO (mismo dict que usa Card.load_from_data() en
	cualquier otro popup del proyecto, p.ej. GoldManagerTax._open_cemetery_
	reveal_popup()), con card_id agregado encima para las respuestas por
	red (no es un campo nativo de card_data)."""
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
# MULLIGAN (2026-09-11 — no existe llamador base: MulliganController._end_
# mulligan_phase() llama aquí directo, con chequeo de tipo, solo si hay un
# Remoto conectado; si no, sigue con draw_initial_hand() como siempre)
# =============================================================================
func run_mulligan(initial_count: int) -> void:
	"""Mulligan real para el jugador 1: dibuja la mano, le pregunta al Remoto
	si la mantiene o la vuelve a barajar (con una carta menos, como cualquier
	mulligan DAR), hasta que mantenga o llegue a 0."""
	var count := initial_count
	while true:
		for i in range(count):
			await _main._zone_manager.draw_card(1, false)
		var hand_cards: Array = _main._opponent_fan.get_cards().duplicate()
		var hand_data: Array = []
		for c in hand_cards:
			if is_instance_valid(c):
				hand_data.append(_card_public_data(c))

		NetworkClient.send_message({"op": "prompt", "kind": "mulligan", "hand": hand_data})
		var intent: Dictionary = await _await_intent(["mulligan_choice"])

		if intent.get("keep", true) or count - 1 <= 0:
			return

		for c in hand_cards:
			if is_instance_valid(c):
				var data: Dictionary = c.card_data.duplicate()
				data["esta_oculta"] = true
				_main._opponent_fan.remove_card(c, true)
				_main.opponent_deck.append(data)
		_main._zone_manager.shuffle_deck(1)
		count -= 1


# =============================================================================
# JUGAR ARMA/TALISMÁN/TÓTEM — mismo criterio que EasyBotController._play_ally()
# (heredado tal cual, arriba en este archivo no — vive en la clase base), pero
# para los 3 tipos de carta que el bot todavía no juega. Task 1.1-1.4,
# docs/plans/2026-09-20-remote-multiplayer-parity.md, Fase 1.
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
	card.scale = Vector2(0.8, 0.8)
	card.base_scale = Vector2(0.8, 0.8)
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


func _play_weapon_remote(card: Node) -> void:
	if not is_instance_valid(card):
		return
	if not _main._gold_manager or not _main._gold_manager._player_has_ally_in_play():
		NetworkClient.send_message({"op": "prompt", "kind": "error", "message": "Sin Aliados en juego para portar el Arma"})
		return
	var coste: int = PaymentManager.calcular_coste_real(card)
	var wielder := await _choose_wielder_remote(card)
	if not wielder or not is_instance_valid(wielder):
		return

	_main._opponent_fan.remove_card(card, false)
	card.esta_oculta = false
	_pay_oro_for_bot(coste)
	TurnManager.on_card_played(card)
	card.owner_id = 1
	card.controller_id = 1

	if _main._gold_manager.has_method("_equip_weapon"):
		await _main._gold_manager._equip_weapon(card, wielder)


func _play_talisman_remote(card: Node) -> void:
	if not is_instance_valid(card):
		return
	var coste: int = PaymentManager.calcular_coste_real(card)
	_main._update_debug("Oponente juega talismán: %s" % card.card_name)

	_main._opponent_fan.remove_card(card, false)
	card.esta_oculta = false
	_pay_oro_for_bot(coste)
	# GoldManager._play_talisman() (2026-10-13, §64): el mismo camino que el
	# Anfitrión — antes este resolvía el efecto pero el Talismán se quedaba
	# en la Línea de Apoyo (nunca iba al Cementerio/Destierro/Castillo).
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
		# Habilidades activadas en su propia Vigilia (2026-10-12): antes el
		# Remoto solo podía activarlas en ventanas de respuesta, así que las
		# de "una vez en tu turno" (p.ej. Miguel) nunca le aparecían.
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
	"""Camino viejo de respuesta (prompt 'response_window'). Desde 2026-10-11
	ya no lo usa ResponseWindowHandler contra un Remoto (ver
	on_priority_received()), pero se conserva por si algún otro llamador de
	la clase base lo invoca."""
	var candidates: Array = _collect_activatable_abilities()
	var candidate_payload: Array = _abilities_payload(candidates)
	NetworkClient.send_message({"op": "prompt", "kind": "response_window", "candidates": candidate_payload})
	var intent: Dictionary = await _await_intent(["activate_ability", "pass"])
	if intent.get("kind", "") != "activate_ability":
		return false
	return await _activate_chosen_ability(str(intent.get("card_id", "")), int(intent.get("ability_index", -1)), candidates)


func _collect_activatable_abilities() -> Array:
	"""Habilidades activadas que el Remoto puede usar ahora mismo: [{card, ability}].
	2026-10-12: mismo filtro que los botones del Anfitrión
	(CardInspectionLayer.usable_abilities_for(card, 1)) — turno, prioridad,
	zona, costo, una vez por turno, Anular/Cancelar en turno rival. Incluye
	cartas de su mano con habilidades usables desde ahí."""
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
	for card in cards:
		# usable_abilities_for() ya descarta las que no controla el jugador 1
		# (controller_id), así que las del lado del Anfitrión solo entran si
		# el Remoto las controla (p.ej. jugadas con Miguel).
		for entry in _main._card_inspector.usable_abilities_for(card, 1):
			candidates.append({"card": card, "ability": entry.ability})
	return candidates


func _abilities_payload(candidates: Array) -> Array:
	var payload: Array = []
	for c in candidates:
		# 2026-10-07: card_data completo (no solo nombre/coste curados) para
		# que RemoteMirrorController pueda mostrar la carta real, mismo
		# criterio que el resto de los prompts (ver _card_public_data()).
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
	# Misma lógica que el botón del Anfitrión (patrones especiales incluidos,
	# p.ej. Miguel) — 2026-10-12.
	if _main._card_inspector:
		await _main._card_inspector.activate_ability_for(chosen_card, chosen_ability, 1)
		return true
	var context := {"controller_id": 1, "source_card_node": chosen_card}
	var result: Dictionary = await ActionPipeline.activate_ability(chosen_card.card_data, chosen_ability, context)
	return result.get("success", false)


# =============================================================================
# BOTÓN DE PASO SIMÉTRICO ONLINE (2026-10-11, a pedido del usuario)
# =============================================================================
# Cada vez que el J2 (el Remoto) recibe la prioridad en CUALQUIER ventana, el
# Anfitrión decide aquí qué hacer, con la misma regla que usa para el J1
# (PriorityManager.needs_real_decision()):
#   - sin decisión real (respuesta a su propia carta, atacante en Bloqueo,
#     pila recién vaciada) → pasa solo;
#   - Ventana de Respuesta real → el Remoto ve su botón de paso con cuenta
#     regresiva de 5s y puede responder con un Talismán instantáneo o una
#     habilidad activada; al vencer el plazo, el Anfitrión pasa por él;
#   - Guerra de Talismanes → puede jugar Talismanes/habilidades, sin plazo;
#   - Bloqueo (defensor) → elige bloqueadores, sin plazo.
# El prompt viaja con window_id (= PriorityManager._window_generation) y la
# respuesta debe traer el mismo id: una respuesta tardía de una ventana que
# ya cerró se descarta sola, nunca se aplica sobre la ventana siguiente.
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
			if card and card in talisman_cards:
				await _play_talisman_remote(card)
				return
		"blocks":
			_apply_remote_blocks(intent.get("pairs", []))
	_pass_if_still_current(window_id)


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
	"""[{card_data..., card_id, can_block: [attacker_id...]}] para cada Aliado
	del Remoto en Línea de Defensa que puede bloquear a algún atacante."""
	var options: Array = []
	if not _main.opponent_field:
		return options
	for blocker in _main.opponent_field.get_children():
		if not is_instance_valid(blocker) or blocker.get("card_type") != Constants.CardType.ALIADO:
			continue
		if blocker in GameManager.blockers.values() or not ContinuousEffectManager.can_block(blocker):
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
		if blocker.get_parent() != _main.opponent_field or blocker in GameManager.blockers.values():
			continue
		if GameManager.blockers.has(attacker) or not ContinuousEffectManager.can_block(blocker):
			continue
		if not BattleManager.is_valid_block(attacker, blocker).get("valid", false):
			continue
		GameManager.declare_blocker(blocker, attacker)
		var tween = create_tween()
		tween.tween_property(blocker, "modulate", Color(0.4, 0.7, 1.0, 1.0), 0.2)
		_main._update_debug("Oponente: %s bloquea a %s" % [str(blocker.get("card_name")), str(attacker.get("card_name"))])
