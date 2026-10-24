class_name GoldManager
extends "res://scripts/core/game/GoldManagerColocar.gd"
## GoldManager — familia Jugar (ver GoldManagerBase.gd para la cabecera, constantes y ayudas).


func play_card(card: Node) -> bool:
	# player_id = controller_id de la carta (quien la controla paga y juega; p.ej. Miguel juega del
	# Cementerio rival). Los llamadores solo pasan la carta; el Remoto llega con controller_id 1
	# (arquitectura.md §34, §38).
	var player_id: int = card.controller_id
	_mark_cemetery_exhumar(card)
	# "Si entró en juego desde tu mano" (kiyohime, ikuchi).
	if card.get("current_zone") == Constants.Zone.MANO:
		card.set_meta("entered_from_hand", true)
	# Excepciones de fase: por defecto solo se juega en Vigilia y sin ventana de prioridad abierta.
	# Excepciones: Armas habilitadas en Guerra de Talismanes (Lobo Sagrado,
	# _can_play_weapons_in_guerra_talismanes()) y Talismanes, que también se juegan en Guerra salvo los
	# de respuesta (_is_response_only_talisman(), más abajo).
	var phase_exception: bool = has_phase_exception(card.card_type, player_id)
	# Ventana de comienzo de fase: "Puedes jugarlo al comienzo de cualquier Fase" / "en la Fase Final",
	# en el turno de cualquiera (PhaseStartWindow).
	var phase_start_ok: bool = load("res://scripts/core/game/PhaseStartWindow.gd").allows_now(card, player_id)
	phase_exception = phase_exception or phase_start_ok
	# Talismanes de respuesta (Anula/Cancela, p.ej. Red de Plata, Sacrificio Solar): se juegan cuando
	# el jugador tiene la palabra, no solo en Vigilia.
	var is_instant_response: bool = card.card_type == Constants.CardType.TALISMAN and _is_response_only_talisman(card)
	# Un Talismán de Anular/Cancelar solo se juega en respuesta a algo del rival. "Sólo puedes jugarlo
	# durante tu turno" (Maldición Vudú).
	if card.card_type == Constants.CardType.TALISMAN and GameManager.active_player_id != player_id \
			and "sólo puedes jugarlo durante tu turno" in str(card.get("card_ability")).to_lower():
		_main._update_debug("%s solo se puede jugar durante tu turno" % card.card_name)
		await _return_card_rejected(card)
		return false
	if is_instant_response and not _responding_to_opponent(player_id):
		_main._update_debug("%s solo se puede jugar en respuesta a una carta o habilidad oponente" % card.card_name)
		await _return_card_rejected(card)
		return false
	# DAR abril 2026 (Respuesta): sin nada que pueda Anular/Cancelar (tipo, coste, "no puede ser Anulado/cancelada"),
	# no se puede jugar, aunque otra parte de su efecto pudiera resolverse (Red de Plata).
	if is_instant_response and not load("res://scripts/core/effects/triggers/Deck170Patterns.gd").annul_response_has_target(
			card, str(card.get("card_ability")), player_id):
		_main._update_debug("%s: no hay nada en la pila que pueda Anular o Cancelar" % card.card_name)
		await _return_card_rejected(card)
		return false

	if GameManager.current_phase != Constants.Phase.VIGILIA and not phase_exception and not is_instant_response:
		_main._update_debug(get_phase_rejection_reason(card.card_type))
		await _return_card_rejected(card)
		return false
	# Fuera de tu turno solo se juegan Talismanes de respuesta (Pila de Respuesta Universal,
	# docs/plans/2026-09-09-pila-respuesta-universal-design.md), o lo que habilite la ventana de
	# comienzo de fase. En Guerra de Talismanes juega quien tiene la prioridad, también el defensor
	# (DAR 5.C3, arquitectura.md §64).
	var in_guerra: bool = GameManager.current_phase == Constants.Phase.GUERRA_TALISMANES
	if in_guerra and PriorityManager.is_guerra_window() and not PriorityManager.can_act(player_id):
		_main._update_debug("Espera tu turno en la Guerra de Talismanes")
		await _return_card_rejected(card)
		return false
	if not in_guerra and GameManager.active_player_id != player_id and not is_instant_response and not phase_start_ok:
		_main._update_debug("No es tu turno")
		await _return_card_rejected(card)
		return false
	# Si hay una ventana de prioridad abierta (respuesta a un trigger que se
	# acaba de disparar, p.ej. 'cuando entre en juego' de la carta anterior),
	# no dejar jugar otra carta todavía — el trigger pendiente quedaba
	# pospuesto y se resolvía solo cuando pasaba OTRA acción, en el
	# momento equivocado. Hay que resolver esa ventana primero (¿Paso?).
	# Los Talismanes instantáneos SÍ pueden jugarse con la ventana abierta —
	# es justo el caso de uso real (responder a lo que la disparó).
	if PriorityManager.priority_window_active and not phase_exception and not is_instant_response:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de jugar otra carta")
		await _return_card_rejected(card)
		return false
	if _no_more_cards_violation(card):
		_main._update_debug("No puedes jugar más cartas este turno")
		await _return_card_rejected(card)
		return false
	if _quinto_sello_cap_violation():
		_main._update_debug("No se pueden jugar más de cinco cartas por turno (Quinto Sello)")
		await _return_card_rejected(card)
		return false
	if _card_play_locked(card):
		_main._update_debug("%s no puede jugarse todavía" % card.card_name)
		await _return_card_rejected(card)
		return false
	if card.card_type == Constants.CardType.ORO:
		await _place_card_as_gold(card)
		return true
	if card.card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No puedes jugar un Arma sin Aliados en juego")
		await _return_card_rejected(card)
		return false
	if _errante_violation(card):
		_main._update_debug("Ya hay una copia de %s en juego (Errante)" % card.card_name)
		await _return_card_rejected(card)
		return false
	if _play_limit_violation(card):
		_main._update_debug(_restrictions.play_limit_message(card))
		await _return_card_rejected(card)
		return false
	# Los Talismanes de respuesta siguen desde aquí el camino de cualquier Talismán (coste, objetivo,
	# _play_talisman()); si no hay objetivo, el selector se cancela con ESC.
	# "Muestra X para reducir el coste" (p.ej. El Rey y el Verdugo): se resuelve antes de calcular el
	# coste real. El modificador no se quita a mano (un Arma recalcula su coste tras elegir portador);
	# lo limpia _on_turn_started_clear_modifiers().
	var reveal_pattern: Dictionary = _get_reveal_cost_reduction_pattern(card)
	if not reveal_pattern.is_empty():
		var revealed_count: int = await _resolve_reveal_cost_reduction(card, reveal_pattern, player_id)
		if revealed_count > 0:
			var applies_to_this_card := func(c: Node) -> bool:
				return c == card
			PaymentManager.agregar_modificador_coste(card, -revealed_count, applies_to_this_card, reveal_pattern.allow_zero)

	# "Puedes Descartar / Destruir / Desterrar <qué> para reducir su coste en N Oros" (voragh el
	# devorador, colaborador titan...): igual que arriba, pero las cartas se pagan de verdad.
	var discard_pattern: Dictionary = _get_discard_cost_reduction_pattern(card)
	if not discard_pattern.is_empty():
		var reduced: int = await _resolve_discard_cost_reduction(card, player_id, discard_pattern)
		if reduced > 0:
			var applies_to_this_card_discard := func(c: Node) -> bool:
				return c == card
			PaymentManager.agregar_modificador_coste(card, -reduced, applies_to_this_card_discard, false)
			if discard_pattern.get("no_annul", false):  # corte letal: "...y no pueda ser Anulado"
				card.set_meta("protected_from_annul_this_turn", true)
				if card.get("card_data") is Dictionary:
					card.card_data["_no_annul"] = true

	# Asequibilidad ANTES de elegir portador: no ofrecer portador para un Arma que no se puede pagar
	# (p.ej. con Lobo Sagrado en Guerra de Talismanes).
	var coste_real = PaymentManager.calcular_coste_real(card)
	if not PaymentManager.puede_jugar_carta(card, player_id):
		var disponible = get_oro_disponible(player_id)
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d (gastado este turno: %d)" % [
			coste_real, disponible, PaymentManager.oro_gastado_este_turno])
		# Quitar el descuento de "muestra X" si se rechaza aquí, para que un segundo intento no lo herede.
		PaymentManager.remover_modificador_coste(card)
		await _return_card_rejected(card)
		return false
	# Elegir portador ANTES de pagar el coste — si el jugador cancela (ESC),
	# no queremos que haya perdido Oro por un Arma que no llegó a equiparse.
	var chosen_wielder: Node = null
	if card.card_type == Constants.CardType.ARMA:
		# Bloquear el Arma mientras se elige portador: un segundo click sobre ella volvía a llamar
		# play_card() y pisaba la selección pendiente (CardInteractionModule guarda un solo
		# filtro/callback).
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(player_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			PaymentManager.remover_modificador_coste(card)
			await _return_card_rejected(card)
			return false
		# Re-chequeo tras la espera async de selección de portador: el Oro
		# disponible no debería cambiar en medio del propio turno del
		# jugador, pero es una comprobación barata y evita pagar de más si
		# algo sí lo cambió mientras esperaba.
		if not PaymentManager.puede_jugar_carta(card, player_id):
			var disponible2 = get_oro_disponible(player_id)
			_main._update_debug("Oro insuficiente: necesitas %d, tienes %d (gastado este turno: %d)" % [
				coste_real, disponible2, PaymentManager.oro_gastado_este_turno])
			PaymentManager.remover_modificador_coste(card)
			await _return_card_rejected(card)
			return false
	if coste_real > 0:
		await pagar_coste(coste_real, card.card_type, card.get("card_raza") if card.get("card_raza") != null else "", card.card_cost, player_id)
		PaymentManager.registrar_pago(coste_real)
	card.set_meta("gold_paid", maxi(coste_real, 0))  # Valac: "como Oros hayas pagado por este Aliado"
	_register_play_limit(card)
	PriorityManager.begin_guerra_action(player_id)
	if card.card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card.card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	PriorityManager.end_guerra_action()
	return true


func play_card_from_exile(card_data: Dictionary, discount: int = 0, owner_id: int = 0) -> bool:
	"""Juega una carta desde el Destierro propio pagando su coste, como si estuviera en la mano
	("Puedes jugarlo de tu Destierro", p.ej. uriel, batallón de ovejas, cruzar el bosque). Espejo
	de play_card_from_cemetery(); no marca is_exhumed: al salir del juego va al Cementerio.
	discount: descuento fijo antes de calcular el coste real, mínimo 1 (p.ej. rafael). owner_id:
	quién la juega (por defecto 0; arquitectura.md §25/§34)."""
	var phase_exception: bool = has_phase_exception(card_data.get("tipo", -1), owner_id)

	if GameManager.current_phase != Constants.Phase.VIGILIA and not phase_exception:
		_main._update_debug(get_phase_rejection_reason(card_data.get("tipo", -1)))
		return false
	if GameManager.active_player_id != owner_id:
		_main._update_debug("No es tu turno")
		return false
	if PriorityManager.priority_window_active and not phase_exception:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de jugar otra carta")
		return false
	if _no_more_cards_this_turn.get(owner_id, false):
		_main._update_debug("No puedes jugar más cartas este turno")
		return false

	var card_type: int = card_data.get("tipo", -1)
	var card = _main._create_card(card_data, false)
	card.owner_id = owner_id
	_main._connect_card_signals(card)

	if discount > 0:
		var applies_to_this_card := func(c: Node) -> bool:
			return c == card
		PaymentManager.agregar_modificador_coste(card, -discount, applies_to_this_card, false)

	if card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No puedes jugar un Arma sin Aliados en juego")
		card.queue_free()
		return false
	if _errante_violation(card):
		_main._update_debug("Ya hay una copia de %s en juego (Errante)" % card.card_name)
		card.queue_free()
		return false
	if _play_limit_violation(card):
		_main._update_debug(_restrictions.play_limit_message(card))
		card.queue_free()
		return false

	var coste_real = PaymentManager.calcular_coste_real(card)
	if not PaymentManager.puede_jugar_carta(card, owner_id):
		var disponible = get_oro_disponible(owner_id)
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible])
		card.queue_free()
		return false

	var chosen_wielder: Node = null
	if card_type == Constants.CardType.ARMA:
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(owner_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			card.queue_free()
			return false
		if not PaymentManager.puede_jugar_carta(card, owner_id):
			var disponible2 = get_oro_disponible(owner_id)
			_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible2])
			card.queue_free()
			return false

	var exile: Array = CardManager.get_exile(owner_id)
	var idx: int = exile.find(card_data)
	if idx < 0:
		card.queue_free()
		return false
	exile.remove_at(idx)

	if coste_real > 0:
		await pagar_coste(coste_real, card_type, card_data.get("raza", ""), card_data.get("coste", 0), owner_id)
		PaymentManager.registrar_pago(coste_real)

	_register_play_limit(card)
	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	return true


func play_found_card(card_data: Dictionary, original_owner: int, controller_id: int, discount: int = 0,
		allow_zero: bool = false) -> bool:
	"""Juega, como parte de un efecto, una carta ya sacada de su zona (p.ej. "busca un Talismán en un
	Castillo y juégalo"): sin chequeos de fase/turno, pagando su coste con 'discount'. Queda bajo
	'controller_id' pero sigue siendo de 'original_owner' (vuelve a SU Cementerio). Si no se puede
	pagar, vuelve al Castillo de su dueño y se baraja."""
	var card = _main._create_card(card_data, false)
	card.owner_id = original_owner
	card.controller_id = controller_id
	_main._connect_card_signals(card)
	if discount > 0:
		PaymentManager.agregar_modificador_coste(card, -discount, func(c: Node) -> bool: return c == card, allow_zero)
	var card_type: int = card_data.get("tipo", -1)
	var coste_real: int = PaymentManager.calcular_coste_real(card)
	var chosen_wielder: Node = null
	var ok: bool = PaymentManager.puede_jugar_carta(card, controller_id)
	if ok and card_type == Constants.CardType.ARMA:
		chosen_wielder = await _select_weapon_wielder(controller_id)
		ok = chosen_wielder != null and is_instance_valid(chosen_wielder)
	if not ok:
		_main._update_debug("No se pudo jugar %s: vuelve al Castillo" % str(card_data.get("nombre", "la carta")))
		if discount > 0:
			PaymentManager.remover_modificador_coste(card)
		card.queue_free()
		var back: Dictionary = card_data.duplicate()
		back["esta_oculta"] = true
		CardManager.get_deck(original_owner).append(back)
		CardManager.shuffle_deck(original_owner)
		return false
	if coste_real > 0:
		await pagar_coste(coste_real, card_type, card_data.get("raza", ""), card_data.get("coste", 0), controller_id)
		PaymentManager.registrar_pago(coste_real)
	if discount > 0:
		PaymentManager.remover_modificador_coste(card)
	_register_play_limit(card)
	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	elif card_type == Constants.CardType.ORO:
		await _place_card_as_gold(card)
	else:
		await _play_card_to_field(card)
	return true


func play_card_from_cemetery(card_data: Dictionary, owner_id: int = 0) -> bool:
	"""Juega una carta con Exhumar desde el Cementerio propio, como si estuviera en la mano (DAR —
	Exhumar). Espejo de play_card(); la carta nunca pasa por la mano, así que
	_play_talisman()/_play_card_to_field()/_equip_weapon() lo toleran. owner_id: quién la juega
	(por defecto 0; arquitectura.md §25/§34)."""
	# Mismas excepciones de fase que play_card() (Armas en Guerra de Talismanes, Talismanes, Talismanes
	# de respuesta: exhumar uno también es jugarlo).
	var phase_exception: bool = has_phase_exception(card_data.get("tipo", -1), owner_id)
	var is_instant_response: bool = card_data.get("tipo", -1) == Constants.CardType.TALISMAN \
		and _is_response_only_talisman_data(card_data)
	if is_instant_response and not _responding_to_opponent(owner_id):
		_main._update_debug("%s solo se puede jugar en respuesta a una carta o habilidad oponente" % str(card_data.get("nombre", "")))
		return false

	if GameManager.current_phase != Constants.Phase.VIGILIA and not phase_exception and not is_instant_response:
		_main._update_debug(get_phase_rejection_reason(card_data.get("tipo", -1)))
		return false
	if GameManager.active_player_id != owner_id:
		_main._update_debug("No es tu turno")
		return false
	if PriorityManager.priority_window_active and not phase_exception and not is_instant_response:
		_main._update_debug("Resuelve la respuesta pendiente (¿Paso?) antes de jugar otra carta")
		return false
	if _no_more_cards_this_turn.get(owner_id, false):
		_main._update_debug("No puedes jugar más cartas este turno")
		return false

	var card_type: int = card_data.get("tipo", -1)
	if is_name_play_locked(owner_id, str(card_data.get("nombre", "")), card_type):
		_main._update_debug("%s no puede jugarse todavía" % str(card_data.get("nombre", "")))
		return false
	# Nota: _card_play_locked() opera sobre el Node (candado por instance_id,
	# ver lock_card_from_playing()) — play_card_from_cemetery() todavía no
	# tiene el Node aquí (se crea más abajo), así que el candado de Chakram no
	# aplica a este camino (jugar con Exhumar desde el Cementerio no es el
	# caso que esa carta describe: 'una carta de la mano rival').
	var card = _main._create_card(card_data, false)
	card.owner_id = owner_id
	# Exhumar solo destierra al salir del juego a los Talismanes (regla del usuario).
	card.is_exhumed = card_type == Constants.CardType.TALISMAN
	_main._connect_card_signals(card)

	if card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No puedes jugar un Arma sin Aliados en juego")
		card.queue_free()
		return false
	if _errante_violation(card):
		_main._update_debug("Ya hay una copia de %s en juego (Errante)" % card.card_name)
		card.queue_free()
		return false
	if _play_limit_violation(card):
		_main._update_debug(_restrictions.play_limit_message(card))
		card.queue_free()
		return false

	# Asequibilidad ANTES de elegir portador (ver play_card()).
	var coste_real = PaymentManager.calcular_coste_real(card)
	if not PaymentManager.puede_jugar_carta(card, owner_id):
		var disponible = get_oro_disponible(owner_id)
		_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible])
		card.queue_free()
		return false

	var chosen_wielder: Node = null
	if card_type == Constants.CardType.ARMA:
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(owner_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			card.queue_free()
			return false
		if not PaymentManager.puede_jugar_carta(card, owner_id):
			var disponible2 = get_oro_disponible(owner_id)
			_main._update_debug("Oro insuficiente: necesitas %d, tienes %d" % [coste_real, disponible2])
			card.queue_free()
			return false

	# Solo con todo confirmado (portador elegido, Oro alcanza) se retira
	# de verdad del Cementerio — igual que play_card() con la mano, para que
	# cancelar a mitad de camino no deje el Cementerio corrompido.
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	var idx: int = cemetery.find(card_data)
	if idx < 0:
		card.queue_free()
		return false
	CardManager.exhume_card(owner_id, idx)

	if coste_real > 0:
		await pagar_coste(coste_real, card_type, card_data.get("raza", ""), card_data.get("coste", 0), owner_id)
		PaymentManager.registrar_pago(coste_real)

	_register_play_limit(card)
	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	return true


## Decisión del usuario (2026-10-23; el DAR no aclara si Exhumar es habilidad continua o condición de
## juego): un Talismán con Exhumar que se juega desde el Cementerio se Destierra siempre, aunque se juegue
## por otro efecto (La Ouija, Miguel...), incluso si es Anulado. CardManager.remove_from_cemetery() marca
## los datos con "_from_cemetery_turn".
func _mark_cemetery_exhumar(card: Node) -> void:
	if not is_instance_valid(card) or card.get("card_data") == null:
		return
	var data: Dictionary = card.card_data
	var from_cem: bool = int(data.get("_from_cemetery_turn", -1)) == GameManager.turn_serial
	data.erase("_from_cemetery_turn")
	if from_cem and card.get("card_type") == Constants.CardType.TALISMAN and not KeywordManager.is_silenced(card) 			and PaymentManager._exhumar and PaymentManager._exhumar._card_has_exhumar(data, int(card.owner_id) if card.get("owner_id") != null else -1):
		card.is_exhumed = true


func play_card_for_free(card_data: Dictionary, owner_id: int = 0, exile_after: bool = false) -> bool:
	"""Juega una carta SIN pagar su coste ni pasar por la mano (p.ej. Tangata Manu: "juega una carta
	de coste 2 o menos sin pagar su coste"). El llamador ya sacó card_data de su zona; aquí solo se
	crea el nodo y se enruta según su tipo. owner_id: quién la juega (por defecto 0;
	arquitectura.md §25)."""
	if await EffectContextScript.ensure_window():  # ventana única por efecto (§59)
		return false
	var card_type: int = card_data.get("tipo", -1)
	# Un Oro nunca se juega, ni gratis: solo se pone en juego por efectos (regla del usuario). Si un
	# patrón manda uno aquí, se rechaza para que el error se vea.
	if card_type == Constants.CardType.ORO:
		push_warning("[GoldManager] play_card_for_free() recibió un Oro (%s): un Oro no se juega, se pone en juego" % str(
			card_data.get("nombre", "?")))
		return false
	# No Más Magia: "Por el resto del juego, jugar ... cartas sin pagar su coste cuesta un Oro adicional".
	if RuleState.active("no_mas_magia", owner_id):
		if not puede_pagar(1, -1, "", -1, owner_id):
			_main._update_debug("No Más Magia: necesitas un Oro para jugar %s sin pagar su coste" % str(card_data.get("nombre", "")))
			return false
		await pagar_coste(1, -1, "", -1, owner_id)
	var card = _main._create_card(card_data, false)
	card.owner_id = owner_id
	# "jugada sin pagar su coste este turno" (Sacrificio Solar, StackAnnul).
	card.set_meta("played_free", true)
	# "juégalo ... y Destiérralo" (haka pei): al salir del juego va al Destierro, como una carta
	# exhumada.
	if exile_after:
		card.is_exhumed = true
	_mark_cemetery_exhumar(card)
	_main._connect_card_signals(card)

	if card_type == Constants.CardType.ARMA and not _player_has_ally_in_play():
		_main._update_debug("No se pudo jugar %s: sin Aliados en juego para portar el Arma" % card.card_name)
		card.queue_free()
		return false
	if _errante_violation(card):
		_main._update_debug("No se pudo jugar %s: ya hay una copia en juego (Errante)" % card.card_name)
		card.queue_free()
		return false

	var chosen_wielder: Node = null
	if card_type == Constants.CardType.ARMA:
		card.can_interact = false
		chosen_wielder = await _select_weapon_wielder(owner_id)
		if not chosen_wielder or not is_instance_valid(chosen_wielder):
			_main._update_debug("Equipar Arma cancelado")
			card.queue_free()
			return false

	if card_type == Constants.CardType.TALISMAN:
		await _play_talisman(card)
	elif card_type == Constants.CardType.ARMA:
		await _equip_weapon(card, chosen_wielder)
	else:
		await _play_card_to_field(card)
	return true


func _select_weapon_wielder(chooser_id: int = 0, extra_filter: Callable = Callable()) -> Node:
	"""Elige qué Aliado porta el Arma que se juega: propio o rival (DAR no restringe el portador). Un
	Arma no va suelta, y un Aliado porta una (o más con "Arma adicional"). chooser_id: quién elige
	(por defecto 0; arquitectura.md §25)."""
	if not _main._card_interaction:
		return null
	# Última red de seguridad: sin candidatos, abrir la selección la dejaba colgada para siempre.
	# extra_filter: restringe quién puede portarla (Zadquiel: "sobre este Aliado o uno oponente").
	var eligible: Array = _get_eligible_weapon_wielders()
	if extra_filter.is_valid():
		eligible = eligible.filter(func(c): return extra_filter.call(c))
	if eligible.is_empty():
		_main._update_debug("No hay ningún Aliado libre en juego para portar el Arma")
		return null
	var filter := func(c: Node) -> bool:
		return c in eligible
	var prompt: String = "Elige qué Aliado porta el Arma" if extra_filter.is_valid() \
		else "Elige qué Aliado porta el Arma (propio o rival)"
	return await _main._card_interaction.await_target(prompt, filter, true, chooser_id)


func _equip_weapon(weapon: Node, ally: Node, fire_enter_play: bool = true) -> void:
	"""Ancla el Arma como hija directa del Aliado portador (no va a un contenedor de línea); se
	inspecciona por separado y sigue al portador si ataca o sale del juego
	(CardManager.destroy_card/exile_card la mueven con él).
	fire_enter_play = false al reasignar un Arma que ya estaba en juego a un portador nuevo
	(CardManager._resolve_weapon_survives_wielder()): DAR — el Arma sobrevive, no se vuelve a
	jugar, así que no se dispara su "Cuando entra en juego" ni se cuenta para Quinto Sello."""
	if fire_enter_play:
		TurnManager.on_card_played(weapon)
	_main._update_debug("Equipando %s a %s" % [weapon.card_name, ally.card_name])

	# 1. Capturar posición global inicial ANTES de quitar el arma de su contenedor
	var start_pos: Vector2 = weapon.global_position if weapon.is_inside_tree() else ally.global_position

	# 2. Desactivar interacción y arrastre residual de inmediato
	weapon.can_interact = false
	if "is_dragging" in weapon:
		weapon.is_dragging = false
	if "drag_enabled" in weapon:
		weapon.drag_enabled = false
	if "_drag_pending" in weapon:
		weapon._drag_pending = false

	# 3. Quitar de la mano cortando los tweens de DynamicHand, para que no la sigan moviendo a la mano.
	var weapon_owner: int = weapon.owner_id if weapon.get("owner_id") != null else 0
	var weapon_hand_container = _main.player_hand if weapon_owner == 0 else _main.get("_opponent_fan")
	if _main and weapon_hand_container:
		if weapon_hand_container.cards.has(weapon) or weapon.get_parent() == weapon_hand_container:
			weapon_hand_container.remove_card(weapon, false)
	if weapon.get_parent():
		weapon.get_parent().remove_child(weapon)

	# 4. Asignar estado IN_PLAY y emparentar al Aliado
	weapon.current_state = Card.CardState.IN_PLAY
	ally.add_child(weapon)

	# Detrás del Aliado, asomando por abajo: el offset (125 de 210 de alto) deja la parte inferior del
	# Arma (su texto) fuera del rect del Aliado; la parte de arriba queda tapada por el portador.
	ally.move_child(weapon, 0)
	weapon.z_index = 0
	weapon.original_z_index = 0
	weapon.top_level = false
	weapon.modulate.a = 1.0
	weapon.visible = true
	weapon.set_zone(ally.current_zone)

	# Mismo tamaño que el Aliado (ally.base_scale; scale y base_scale juntos, como en
	# _place_card_as_gold()). Varias Armas se apilan hacia abajo (+Constants.WEAPON_STACK_STEP_Y cada
	# una).
	var slot_index: int = ally.equipped_weapons.size()
	var equip_scale: Vector2 = ally.base_scale
	weapon.scale = equip_scale
	weapon.base_scale = equip_scale
	var target_local_pos := Vector2(0.0, Constants.WEAPON_OFFSET_Y + slot_index * Constants.WEAPON_STACK_STEP_Y)
	weapon.position = target_local_pos
	ally.equipped_weapons.append(weapon)
	weapon.wielder = ally
	_register_weapon_strength_bonus(weapon, ally)
	_register_wielder_leave_play_immunity(weapon, ally)
	_register_weapon_talisman_tax(weapon)
	_refresh_dynamic_strength_badges(ally.controller_id if ally.get("controller_id") != null else 0)

	# 5. Animación de equipar en el espacio local del Aliado
	await get_tree().process_frame
	if not is_instance_valid(weapon) or not is_instance_valid(ally):
		return

	# Control no tiene to_local()/to_global() (son de Node2D): equivalente para Control, como en
	# MulliganController.gd.
	var start_local_pos: Vector2 = ally.get_global_transform().affine_inverse() * start_pos
	weapon.position = start_local_pos
	weapon.top_level = false

	var tween = weapon.create_tween()
	tween.tween_property(weapon, "position", target_local_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished

	# 6. Reafirmar determinísticamente la posición, escala y estado final
	if is_instance_valid(weapon) and is_instance_valid(ally):
		weapon.position = target_local_pos
		weapon.top_level = false
		weapon.scale = ally.base_scale
		weapon.base_scale = ally.base_scale
		weapon.can_interact = true
		weapon.modulate.a = 1.0

	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
	if fire_enter_play:
		VisualManager.play_card_effect(weapon.card_cost)
		await _trigger_enter_play(weapon, ally.current_zone)


func _register_weapon_strength_bonus(weapon: Node, ally: Node) -> void:
	"""Parsea 'El portador gana N de Fuerza' del texto del Arma y registra el
	bono en ContinuousEffectManager con duración PERMANENT ('mientras la
	fuente esté en juego') — se limpia solo cuando el Arma sale de juego
	(Card._exit_tree() llama remove_modifiers_from_source() sin importar
	cómo salió: destruida, desterrada, devuelta al mazo). El combate
	(BattleManager._get_strength()) y el badge visual de la carta ya
	consultan este valor calculado, así que con solo registrar el
	modificador alcanza para que todo se refleje solo."""
	var ability_text: String = weapon.get("card_ability") if weapon.get("card_ability") != null else ""
	if ability_text.is_empty():
		return

	# el huascar: "El portador duplica su Fuerza y tus demás Aliados ganan Fuerza igual a su coste",
	# mientras esté equipada.
	if "el portador duplica su fuerza y tus demás aliados ganan fuerza igual a su coste" in ability_text.to_lower():
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(_c: Node, current: int, _mod: Dictionary) -> int: return current,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s duplica su Fuerza (%s)" % [ally.card_name, weapon.card_name],
		})
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": "ALLIES",
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(c: Node, _current: int, _mod: Dictionary) -> int:
				if c == ally or not is_instance_valid(c):
					return 0
				return int(c.get("card_cost")) if c.get("card_cost") != null else 0,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s: tus demás Aliados +Fuerza igual a su coste" % weapon.card_name,
		})
		return

	# "El portador gana Furia y 1 de Fuerza por cada Oro que controles" (skofnung): bono dinámico,
	# value es un Callable recontado en cada consulta (como Manuel Bulnes / shedo titan). Las palabras
	# clave que el Arma da al portador no se registran aquí: las lee Card.has_keyword().
	var dynamic_rx := RegEx.new()
	dynamic_rx.compile("(?i)el portador gana furia y (\\d+) de fuerza por cada oro que controles")
	var dynamic_m := dynamic_rx.search(ability_text)
	if dynamic_m:
		var per_oro: int = int(dynamic_m.get_string(1))
		var wielder_controller: int = ally.controller_id if ally.get("controller_id") != null else 0
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(_c: Node, _current: int, _mod: Dictionary) -> int:
				return GameState.get_oro_total(wielder_controller) * per_oro,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s porta %s (+Fuerza por Oro)" % [ally.card_name, weapon.card_name],
		})
		if ally.has_method("refresh_strength_badge"):
			ally.refresh_strength_badge()
		return

	# "El portador gana 2 de Fuerza por cada Azusa Yumi que controles y hace daño al Destierro" (azusa
	# yumi): mismo value Callable, contando copias equipadas. Va antes del regex genérico, que si no lo
	# tomaría como +2 fijo.
	var azusa_rx := RegEx.new()
	azusa_rx.compile("(?i)el portador gana (\\d+) de fuerza por cada azusa yumi que controles")
	var azusa_m := azusa_rx.search(ability_text)
	if azusa_m:
		var per_azusa: int = int(azusa_m.get_string(1))
		var wielder_controller_az: int = ally.controller_id if ally.get("controller_id") != null else 0
		var count_azusa := func() -> int:
			var n: int = 0
			for other in ContinuousEffectManager._get_all_cards_in_play():
				if ContinuousEffectManager._get_card_owner(other) != wielder_controller_az:
					continue
				var w = other.get("equipped_weapons")
				if w is Array:
					for weap in w:
						if is_instance_valid(weap) and str(weap.get("card_name")).to_lower() == "azusa yumi":
							n += 1
			return n
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": func(_c: Node, _current: int, _mod: Dictionary) -> int:
				return count_azusa.call() * per_azusa,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s porta %s (+Fuerza por Azusa Yumi)" % [ally.card_name, weapon.card_name],
		})
		# "...y hace daño al Destierro" — mismo mecanismo real ya usado por
		# arco del triunfo/Segundo Sello (TriggerSystem.register_continuous_
		# effect con type 'damage_to_exile', targets = el OPONENTE de quien
		# porta el Arma, porque ese registro se consulta del lado de quien
		# RECIBE el daño). Se registra una vez por copia equipada; si se
		# desequipa, TriggerSystem no tiene un "unregister por source" para
		# este tipo puntual todavía (mismo camino que arco del triunfo usa al
		# salir del juego) — limitación conocida, aceptable porque Azusa Yumi
		# rara vez se desequipa sin salir de juego (no hay Arma "cambia de
		# portador" en el catálogo auditado esta sesión).
		TriggerSystem.register_continuous_effect(weapon, {
			"type": "damage_to_exile",
			"targets": [1 - wielder_controller_az]
		})
		if ally.has_method("refresh_strength_badge"):
			ally.refresh_strength_badge()
		return

	# kabutowari ("En Guerra de Talismanes, una vez por turno, el portador gana 1 de Fuerza por cada
	# Aliado en tu Línea de Defensa..."): no es un aura permanente. Se excluye del regex genérico (que
	# daría +1 fijo); la activada es InPlayAbilities.kabutowari().
	if "gana 1 de fuerza por cada aliado en tu l" in ability_text.to_lower() \
			and "guerra de talismanes" in ability_text.to_lower():
		return

	var rx := RegEx.new()
	rx.compile("(?i)el portador gana (\\d+) de fuerza")
	var m := rx.search(ability_text)
	if not m:
		return
	var bonus := int(m.get_string(1))
	if bonus > 0:
		ContinuousEffectManager.register_modifier({
			"source": weapon,
			"target": ally,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": bonus,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s porta %s (+%d Fuerza)" % [ally.card_name, weapon.card_name, bonus],
		})
		if ally.has_method("refresh_strength_badge"):
			ally.refresh_strength_badge()


func _register_wielder_leave_play_immunity(weapon: Node, ally: Node) -> void:
	""""Cuando entra en juego, el portador no puede salir del juego hasta tu próximo turno" (p.ej.
	Garfio Pirata): se resuelve al equipar porque hace falta saber quién es el portador."""
	var ability: String = weapon.card_ability.to_lower() if weapon.get("card_ability") else ""
	if not ("el portador no puede salir del juego" in ability):
		return
	var controller_id: int = weapon.controller_id if weapon.get("controller_id") != null else 0
	EffectController.add_single_card_leave_play_immunity(ally, controller_id)


func _register_weapon_talisman_tax(weapon: Node) -> void:
	""""Los Talismanes cuestan un Oro adicional" (nodachi): sin "de tu oponente", vale para los
	Talismanes de los dos jugadores mientras esté equipada. Sube el coste impreso
	(agregar_modificador_coste; ver PaymentManager.calcular_coste_real()). Se limpia sola al salir
	(Card._exit_tree() → PaymentManager.remover_modificador_coste)."""
	var ability: String = weapon.card_ability.to_lower() if weapon.get("card_ability") else ""
	if not ("los talismanes cuestan un oro adicional" in ability):
		return
	var condition := func(c: Node) -> bool:
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.TALISMAN
	PaymentManager.agregar_modificador_coste(weapon, 1, condition, false)


func _get_reveal_cost_reduction_pattern(card: Node) -> Dictionary:
	return _tax._get_reveal_cost_reduction_pattern(card)


func _resolve_reveal_cost_reduction(card: Node, pattern: Dictionary, player_id: int = 0) -> int:
	return await _tax._resolve_reveal_cost_reduction(card, pattern, player_id)


func _get_discard_cost_reduction_pattern(card: Node) -> Dictionary:
	return _tax._get_discard_cost_reduction_pattern(card)


func _resolve_discard_cost_reduction(card: Node, player_id: int = 0, pattern: Dictionary = {}) -> int:
	return await _tax._resolve_discard_cost_reduction(card, player_id, pattern)


## Elegibilidad para jugar una carta: el cuerpo está en GoldManagerRestrictions.gd. Reenvíos de una
## línea; _is_response_only_talisman, has_phase_exception, get_phase_rejection_reason,
## _get_eligible_weapon_wielders y _player_has_ally_in_play tienen llamadores fuera de este archivo.
func _errante_violation(card: Node) -> bool:
	return _restrictions._errante_violation(card)


func _play_limit_violation(card: Node) -> bool:
	return _restrictions._play_limit_violation(card)


func _register_play_limit(card: Node) -> void:
	_restrictions._register_play_limit(card)


func _is_response_only_talisman(card: Node) -> bool:
	return _restrictions._is_response_only_talisman(card)


func _is_response_only_talisman_data(card_data: Dictionary) -> bool:
	return _restrictions._is_response_only_talisman_data(card_data)


func _player_has_ally_in_play() -> bool:
	return _restrictions._player_has_ally_in_play()


func _get_eligible_weapon_wielders() -> Array:
	return _restrictions._get_eligible_weapon_wielders()


func has_phase_exception(card_type: int, player_id: int = 0) -> bool:
	return _restrictions.has_phase_exception(card_type, player_id)


func get_phase_rejection_reason(card_type: int) -> String:
	return _restrictions.get_phase_rejection_reason(card_type)


func _return_card_rejected(card: Node) -> void:
	if not card or not is_instance_valid(card):
		return
	# Restaurar la interactividad: el Arma se deshabilita al elegir portador; si se cancela o el pago
	# falla, vuelve a ser clickeable.
	card.can_interact = true
	# Si la carta nunca fue arrastrada (doble click), original_position es Vector2.ZERO — corregirlo
	# antes de llamar return_to_hand(), que usa esa propiedad para animar el regreso.
	if card.get("original_position") != null and card.original_position == Vector2.ZERO:
		card.original_position = card.global_position
	# Flash rojo — sin tweenear global_position para no pelear con el layout del contenedor
	var tween = create_tween()
	tween.tween_property(card, "modulate", Color(1.5, 0.3, 0.3, 1.0), 0.08)
	await tween.finished
	var tween2 = create_tween()
	tween2.tween_property(card, "modulate", Color.WHITE, 0.2)
	await tween2.finished
	card.return_to_hand()


func _play_card_to_field(card: Node) -> void:
	TurnManager.on_card_played(card)
	# El lado del tablero lo decide controller_id (quién la controla), no owner_id (a quién vuelve si
	# muere): solo difieren en casos como Miguel. Vale para los tres caminos (play_card /
	# play_card_from_cemetery / play_card_for_free) y para el jugador 1 (arquitectura.md §25, §38).
	var owner_id: int = card.controller_id
	# Crono Diamante ("si jugaste un Aliado de coste 2 o más este turno"): se registra aquí porque todo
	# Aliado jugado pasa por esta función, venga de donde venga.
	if card.card_type == Constants.CardType.ALIADO and int(card.card_cost) >= 2:
		UniversalCardParser.turn_registry.register("played_ally_cost2plus:%d" % owner_id, 0, GameManager.turn_serial)
	if card.card_type in [Constants.CardType.ALIADO, Constants.CardType.TOTEM] and int(card.card_cost) >= 2:
		_apply_crono_diamante_annul_protection(card)
	_main._update_debug("Jugando: %s" % card.card_name)
	var start_pos = card.global_position
	var hand_container: Control = _main.player_hand if owner_id == 0 else _main._opponent_fan  # HandManager/OpponentFan son Control
	var idx = hand_container.cards.find(card) if hand_container else -1
	if idx >= 0:
		hand_container.cards.remove_at(idx)
	# Solo si sigue en la mano: un Aliado/Tótem exhumado nunca estuvo ahí.
	if hand_container and card.get_parent() == hand_container:
		hand_container.remove_child(card)
		hand_container._arrange_cards()
	card.can_interact = false
	# Tótems a la Línea de Apoyo; Aliados y Armas a la Línea de Defensa (DAR: tres zonas dentro del
	# campo).
	var own_linea_apoyo: HBoxContainer = _main.player_linea_apoyo if owner_id == 0 else _main.opponent_linea_apoyo
	var own_field: HBoxContainer = _main.player_field if owner_id == 0 else _main.opponent_field
	var target_container: HBoxContainer = own_linea_apoyo if card.card_type == Constants.CardType.TOTEM else own_field
	var target_zone: int = Constants.Zone.LINEA_APOYO if card.card_type == Constants.CardType.TOTEM else Constants.Zone.LINEA_DEFENSA
	target_container.add_child(card)
	# Si la carta llegó por arrastre (drag), top_level seguía en true (modo
	# 'posición global libre' que usa Card._update_drag()). Sin resetearlo,
	# el contenedor no puede posicionarla de verdad, y el 'end_pos' leído
	# más abajo terminaba siendo la última posición del arrastre en vez de
	# la casilla real del campo — la carta se animaba hacia un lugar sin
	# relación con el campo, dando la sensación de que desaparecía.
	card.top_level = false
	card.z_index = 0
	card.set("original_z_index", 0)
	card.set_meta("hand_base_z_index", 0)
	card.set_zone(target_zone)
	await get_tree().process_frame
	# Escala del campo: Aliados a 1.0; Tótems a Constants.TOTEM_CARD_SCALE
	var field_scale: Vector2 = Constants.TOTEM_CARD_SCALE if card.card_type == Constants.CardType.TOTEM else Vector2.ONE
	card.scale = field_scale
	# Slot fijo en vez de la posición que calcula el HBoxContainer, para que los demás no se corran
	# cuando uno ataca (ZoneManager.pin_card_to_field_slot()).
	var end_pos: Vector2 = _main._zone_manager.pin_card_to_field_slot(card, target_container)
	card.global_position = start_pos
	var tween = create_tween()
	tween.tween_property(card, "global_position", end_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	card.base_scale = field_scale
	card.can_interact = true
	VisualManager.play_card_effect(card.card_cost)
	if card.has_method("play_enter_animation"):
		card.play_enter_animation()
	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
	await _trigger_enter_play(card, target_zone)


func _apply_crono_diamante_annul_protection(card: Node) -> void:
	"""Crono Diamante: "tu primer Aliado o Tótem de coste 2 o más (este turno) no puede ser Anulado" —
	solo si su controlador tiene un Crono Diamante en la Reserva, la primera vez por turno
	(turn_registry). Marca la carta con set_meta(), que lee
	TargetedEffectExecutor._execute_targeted_annul().
	La otra mitad ("la primera habilidad de Oro que utilices cada turno no puede ser cancelada"):
	ProtectionRules.note_gold_ability_use / first_gold_ability_protected."""
	var controller_id: int = card.controller_id if card.get("controller_id") != null else 0
	# También para el jugador 1 (su Reserva es opponent_gold).
	var gold_container = PlayerSideScript.gold_reserva(_main, controller_id)
	if not gold_container:
		return
	var has_crono_diamante := false
	for c in gold_container.get_children():
		if is_instance_valid(c) and str(c.get("card_name")).to_lower() == "crono diamante":
			has_crono_diamante = true
			break
	if not has_crono_diamante:
		return
	var key := "crono_diamante_annul_protection:%d" % controller_id
	if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.turn_serial):
		return
	UniversalCardParser.turn_registry.register(key, 0, GameManager.turn_serial)
	card.set_meta("protected_from_annul_this_turn", true)


func check_libro_de_thoth_block(blocker: Node, blocker_owner: int) -> void:
	"""libro de thoth (Oro): "Cuando bloquees, genera un Oro por el turno" — reacciona a que cualquier
	Aliado tuyo bloquee. Se llama desde GameManager.confirm_blockers_and_collect_triggers(), una
	vez por bloqueador; un trigger normal solo llega a la carta que dispara el evento, no a un Oro
	en la Reserva. El Oro generado no tiene restricción."""
	if not is_instance_valid(blocker):
		return
	var reserva: Array = _main.gold_cards if blocker_owner == 0 else (_main.opponent_gold.get_children() if _main.get("opponent_gold") else [])
	var pagado: Array = _main.player_oro_pagado.get_children() if blocker_owner == 0 and _main.get("player_oro_pagado") else \
		(_main.opponent_oro_pagado.get_children() if blocker_owner == 1 and _main.get("opponent_oro_pagado") else [])
	var has_libro: bool = false
	for g in reserva + pagado:
		if is_instance_valid(g) and str(g.get("card_name")).to_lower() == "libro de thoth":
			has_libro = true
			break
	if not has_libro:
		return
	var always_true := func(_t, _r, _c) -> bool: return true
	generar_oro_virtual_restringido(1, always_true, "libro de thoth")


func _discard_oro_from_reserva(oro_card: Node, controller_id: int) -> void:
	"""Descarta (al Cementerio) un Oro físico de la Reserva: no hay otro camino para esto (discard()
	es solo desde la mano). Costo de Cuarto Sello ("Puedes pagar un Oro y Descartarlo..."). Limpia
	como ActionReturnDiscard.return_to_deck(): señales, Reserva/gold_cards y GameState."""
	if not is_instance_valid(oro_card):
		return
	var data: Dictionary = oro_card.card_data.duplicate() if oro_card.get("card_data") else {}
	CardManager.add_to_cemetery(controller_id, data)
	GameState.agregar_oro_reserva(controller_id, -1)
	if controller_id == 0:
		_main.gold_cards.erase(oro_card)
	CardManager._disconnect_card_interaction_signals(oro_card)
	var parent = oro_card.get_parent()
	if parent:
		parent.remove_child(oro_card)
	oro_card.queue_free()
	if controller_id == 0:
		_update_gold_display()


func _take_gold_out_of_play(oro_card: Node) -> Dictionary:
	"""Saca un Oro de la Reserva o del Oro Pagado (contadores incluidos) y devuelve sus datos; el
	llamador decide el destino."""
	var pid: int = oro_card.controller_id if oro_card.get("controller_id") != null else 0
	var parent = oro_card.get_parent()
	if parent == (_main.player_gold if pid == 0 else _main.opponent_gold):
		GameState.agregar_oro_reserva(pid, -1)
	elif parent == (_main.player_oro_pagado if pid == 0 else _main.opponent_oro_pagado):
		GameState.agregar_oro_pagado(pid, -1)
	if pid == 0:
		_main.gold_cards.erase(oro_card)
	var data: Dictionary = oro_card.card_data.duplicate() if oro_card.get("card_data") else {}
	CardManager._disconnect_card_interaction_signals(oro_card)
	if parent:
		parent.remove_child(oro_card)
	oro_card.queue_free()
	update_gold_containers_spacing()
	_update_gold_display()
	return data


func exile_gold_from_play(oro_card: Node) -> void:
	if not is_instance_valid(oro_card):
		return
	var owner_id: int = oro_card.owner_id if oro_card.get("owner_id") != null else 0
	var data: Dictionary = _take_gold_out_of_play(oro_card)
	data["esta_oculta"] = false
	CardManager.append_to_exile(owner_id, data)


func return_gold_to_hand(oro_card: Node) -> void:
	if not is_instance_valid(oro_card):
		return
	var owner_id: int = oro_card.owner_id if oro_card.get("owner_id") != null else 0
	var data: Dictionary = _take_gold_out_of_play(oro_card)
	var node = _main._create_card(data, owner_id != 0)
	if owner_id == 0:
		_main.player_hand.add_card(node)
	else:
		_main._opponent_fan.add_card(node)
	_main._connect_card_signals(node)


func buff_next_talisman(player_id: int, discount: int, allow_zero: bool, no_annul: bool) -> void:
	_clear_next_talisman_buff(player_id)
	var token := Node.new()
	add_child(token)
	var turn: int = GameManager.turn_serial
	PaymentManager.agregar_modificador_coste(token, -discount, func(c: Node) -> bool:
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.TALISMAN \
			and c.get("controller_id") == player_id, allow_zero)
	_next_talisman_buffs[player_id] = {"token": token, "no_annul": no_annul, "turn": turn,
		"active_player": GameManager.active_player_id}


func _consume_next_talisman_buff(card: Node) -> void:
	var pid: int = card.controller_id
	var buff: Dictionary = _next_talisman_buffs.get(pid, {})
	if buff.is_empty():
		return
	if buff.turn != GameManager.turn_serial or buff.active_player != GameManager.active_player_id:
		_clear_next_talisman_buff(pid)  # "este turno": ya venció
		return
	if buff.no_annul:
		card.set_meta("protected_from_annul_this_turn", true)
		if card.get("card_data") is Dictionary:
			card.card_data["_no_annul"] = true
	_clear_next_talisman_buff(pid)


func _play_talisman(card: Node) -> void:
	"""Los Talismanes se resuelven al jugarse y no se quedan en el campo
	como un Aliado ni como un Tótem (DAR Sección 8): disparan su habilidad y
	van al Cementerio por defecto — al Destierro si su propio texto dice
	'destiérralo', o de vuelta al Mazo (barajado) si dice 'barájala'. Si fue
	jugado via Exhumar (card.is_exhumed), el Destierro manda siempre, sin
	importar lo que diga el propio texto (regla de Exhumar, DAR)."""
	TurnManager.on_card_played(card)
	_main._update_debug("Jugando talismán: %s" % card.card_name)
	_consume_next_talisman_buff(card)

	# Por jugador, "ya jugó un Talismán este turno" (Fuente de la Juventud: "les cuesta un Oro
	# adicional jugar Talismanes si han jugado Talismanes este turno"; lo consulta
	# _register_talisman_second_play_tax()). Cuenta quien lo controla (arquitectura.md §38).
	var talisman_owner: int = card.controller_id
	UniversalCardParser.turn_registry.register("talisman_played:%d" % talisman_owner, 0, GameManager.turn_serial)

	# Se enruta por talisman_owner (no siempre el Anfitrión): Talismanes jugados por el jugador 1 vía
	# play_card_for_free()/play_card_from_cemetery() (arquitectura.md §25).
	var hand_container: Control = _main.player_hand if talisman_owner == 0 else _main._opponent_fan  # HandManager/OpponentFan son Control
	var field_container: HBoxContainer = _main.player_field if talisman_owner == 0 else _main.opponent_field
	var idx = hand_container.cards.find(card) if hand_container else -1
	if idx >= 0:
		hand_container.cards.remove_at(idx)
	# Ver GoldManager._play_card_to_field() — misma corrección (Exhumar: la
	# carta nunca estuvo en la mano).
	if hand_container and card.get_parent() == hand_container:
		hand_container.remove_child(card)
		hand_container._arrange_cards()
	card.can_interact = false
	field_container.add_child(card)
	# Ver GoldManager._play_card_to_field() — misma corrección.
	card.top_level = false
	card.set_zone(Constants.Zone.LINEA_APOYO)
	await get_tree().create_timer(0.3).timeout

	# _trigger_enter_play() se espera hasta el final (incluye las elecciones del jugador), así que no
	# hace falta una espera fija: el Talismán va al Cementerio apenas se resuelve.
	var was_annulled: bool = await _trigger_enter_play(card, Constants.Zone.LINEA_APOYO)

	if was_annulled:
		# Anulado/cancelado en su ventana de respuesta: el efecto no ocurrió, así que no se mira su texto
		# ("destiérralo", "barájala") — va al Cementerio, como cualquier Anular.
		var true_owner_annulled: int = card.owner_id if card.get("owner_id") != null else 0
		if card.get_meta("annul_to_pagado_gold", false):
			# asalto estelar: "Si es Anulado, conviértelo en un Oro sin habilidad y ponlo en tu Oro Pagado".
			var gold_data: Dictionary = card.card_data.duplicate(true)
			gold_data["tipo"] = Constants.CardType.ORO
			gold_data["habilidad"] = ""
			gold_data["keywords"] = []
			if card.get_parent():
				card.get_parent().remove_child(card)
			card.queue_free()
			await put_gold_directly_in_pagado(true_owner_annulled, gold_data)
		elif card.get_meta("annul_to_exile", false):
			await EffectController.exile_card(true_owner_annulled, card, true)
		else:
			await EffectController.destroy_card(true_owner_annulled, card, false)
		_update_gold_display()
		_main._update_buttons_for_phase(GameManager.current_phase)
		return

	var habilidad: String = card.card_ability.to_lower() if card.get("card_ability") else ""
	# "Destiérralo"/"Destiérrala" llevan tilde (el pronombre mueve el acento), por eso no basta buscar
	# "destierr". Solo si se destierra a sí mismo (Cuervo Nocturno dice "Destierra seis cartas del tope
	# del Castillo oponente" y no se va al Destierro).
	var self_exile := false
	for phrase in ["destiérralo", "destiérrala", "destierralo", "destierrala", "destierra esta carta",
			"destierra este talismán", "destierra este talisman"]:
		if phrase in habilidad:
			self_exile = true
	# "barájala"/"barájalo" (se baraja a sí mismo; Visión de Enoc). No basta "baraj": Aaru dice "Baraja
	# cualquier cantidad de cartas de tu mano" y va al Cementerio.
	var self_shuffle := "barájala" in habilidad or "barajala" in habilidad \
		or "barájalo en tu castillo" in habilidad or "barajalo en tu castillo" in habilidad

	# Vuelve a SU dueño (card.owner_id): con Miguel se puede jugar un Talismán del Cementerio rival, y
	# debe volver al Cementerio/Destierro de ese jugador.
	var true_owner: int = card.owner_id if card.get("owner_id") != null else 0

	if card.get("is_exhumed") == true:
		# Exhumar manda siempre al Destierro, sin importar el propio texto
		# de la carta (ni "barájala" ni el Cementerio por defecto aplican).
		await EffectController.exile_card(true_owner, card)
	elif self_shuffle:
		await ActionModule.return_to_deck(card, true_owner, false, card)
		ActionModule.shuffle_deck(true_owner)
	else:
		# self_exile respeta el texto de la carta sea cual sea el camino: si dice "destiérralo", se
		# destierra. La única regla que fuerza el Destierro, diga lo que diga, es Exhumar (is_exhumed,
		# arriba); jugarla del Cementerio por otro efecto (Miguel) no agrega nada.
		if self_exile:
			await EffectController.exile_card(true_owner, card)
		else:
			# is_being_destroyed = false: un Talismán que va al Cementerio tras resolverse no es una
			# destrucción (solo cambia el texto del log).
			await EffectController.destroy_card(true_owner, card, false)

	_update_gold_display()
	_main._update_buttons_for_phase(GameManager.current_phase)
