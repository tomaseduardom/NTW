extends RefCounted
## PreventionAbilityHandler_AE — mitad A-E (alfabético por carta) de PreventionAbilityHandler.gd
## (fachada que reúne esta parte con PreventionAbilityHandler_EP.gd y _PV.gd bajo los mismos nombres
## públicos). Opera sobre CardInspectionLayer vía _inspector (y sobre Main vía _inspector._main).

var _inspector: CardInspectionLayer


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func _activate_akari_banish_annul_non_ally(source_card: Node, ability: Dictionary) -> void:
	"""'Puedes Desterrarlo para Anular una carta de coste 1 o menos que no sea Aliado' (akari) —
	'Anular' ~ destruir (misma simplificación usada en todo el proyecto), objetivo Arma/Tótem (no
	Aliado, no Oro) de coste efectivo ≤1."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	if not main._card_interaction:
		return

	var filter := func(c: Node) -> bool:
		if c.get("card_type") not in [Constants.CardType.ARMA, Constants.CardType.TOTEM]:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, 1)
	var target: Node = await main._card_interaction.await_target("Elige un Arma o Tótem de coste 1 o menos para anular", filter, true, owner_id)
	if not target or not is_instance_valid(target):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.banish([source_card], source_card, true)

	if TriggerSystem._targeted_executor._target_text_denies(target, ["no puede ser anulad"]):
		main._update_debug("%s no puede ser anulada" % str(target.get("card_name")))
	else:
		await ActionModule.destroy([target], source_card, true, true)


func _activate_akuma_banish_or_draw(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, puedes Desterrar hasta dos cartas de los Cementerio o Roba una carta'
	(akuma el terrible) — elección A/B; 'los Cementerios' = ambos jugadores
	([[project_no_zone_means_in_play]])."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	var choose_banish: bool = await SelectionManager.await_two_choice(
		_inspector._main, "akuma el terrible", "Desterrar hasta dos cartas de los Cementerios", "Robar una carta", owner_id)

	if choose_banish:
		# Click directo sobre los dos Cementerios: pool combinado, sin lock (como Espada de O'Higgins,
		# arquitectura.md §10.14/§10.19).
		if not _inspector._main._zone_viewer:
			return
		var no_filter := func(_c: Node) -> bool: return true
		var picked: Array = await _inspector._main._zone_viewer.open_cemetery_target_picker(
			"Destierra hasta dos carta(s) de los Cementerios", no_filter, 2, "cemetery", false, false, owner_id)
		if picked.is_empty():
			return
		if await TriggerSystem.open_response_window(source_card, "akuma el terrible", owner_id):
			return
		UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
		for entry in picked:
			var owner_of_picked: int = entry.owner_id
			var picked_data: Dictionary = entry.data
			if not CardManager.take_from_cemetery(owner_of_picked, picked_data):
				continue
			CardManager.add_to_exile(owner_of_picked, picked_data)
	else:
		if await TriggerSystem.open_response_window(source_card, "akuma el terrible", owner_id):
			return
		UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
		await ActionModule.draw(owner_id, 1, "activated_ability", true)


## Almirante Akari no tiene botón: son dos disparadores reactivos. "Prevenir" está en
## EffectController._prevention_registry y "Anular cuando el rival juega una carta" en
## EffectController.offer_counter_annul(); comparten el costo vía
## EffectController._pay_akari_shuffle_cost().


## Ángel Redentor no tiene botón: EffectController.offer_prevention() lo ofrece reactivamente (tags
## "annul"/"cancel"), con su cupo de una vez por turno en el 'is_available' del registro.


func _activate_atenea_grant_double_damage_exile(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, un Aliado hace doble daño de combate al Destierro este turno' (atenea en
	wonderland) — meta 'double_exile_damage_turn' con el turno en que vale (BattleManager
	._accumulate_castle_damage), a un Aliado elegido (propio o rival, el texto no lo restringe)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	if not main._card_interaction:
		return

	var filter := func(c: Node) -> bool:
		if c.get("card_type") != Constants.CardType.ALIADO:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	var target: Node = await main._card_interaction.await_target("Elige un Aliado que haga doble daño de combate al Destierro este turno", filter, true, owner_id)
	if not target or not is_instance_valid(target):
		return
	if await TriggerSystem.open_response_window(source_card, "atenea en wonderland", owner_id):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	target.set_meta("double_exile_damage_turn", GameManager.turn_serial)


func _activate_belta_barajar_desterrar(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, Baraja y/o Destierra hasta dos cartas de los Cementerios' (Belta) — reusa
	GoldManager._resolve_armeria_barajar_desterrar genérica, sin costo (a diferencia de Armería,
	aquí no hay condición previa)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	# _resolve_armeria_barajar_desterrar() resuelve elección intercalada
	# carta-por-carta sin un punto limpio de "declarar todo antes de
	# ejecutar" (mismo motivo por el que quedó diferida en el barrido de
	# triggers) — se gatea con UNA ventana ANTES de arrancar toda la
	# resolución en vez de reescribir el helper compartido.
	if await TriggerSystem.open_response_window(source_card, "Belta", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await _inspector._main._gold_manager._resolve_armeria_barajar_desterrar(2, "Belta", owner_id)


func _activate_belta_self_banish_revive(source_card: Node, ability: Dictionary) -> void:
	"""'Puedes Desterrar dos cartas de tu Cementerio para ponerlo en juego desde tu Cementerio como un
	Aliado sin habilidad de Fuerza 2' (Belta) — costo: desterrar 2 cartas CUALQUIERA de tu
	Cementerio (no incluye a Belta misma, que está siendo jugada desde ahí). Efecto: Belta deja de
	ser el Oro y pasa a ser un Aliado Fuerza 2 sin habilidad, en juego."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	if source_card.get("current_zone") != Constants.Zone.CEMENTERIO:
		main._update_debug("Belta ya no está en tu Cementerio")
		return

	var cemetery: Array = CardManager.get_cemetery(owner_id)
	var others: Array = cemetery.filter(func(d): return d != source_card.card_data)
	if others.size() < 2:
		main._update_debug("Necesitas otras 2 cartas en tu Cementerio para desterrar")
		return
	if not main._zone_viewer:
		return
	# Click directo: "tu Cementerio" (lock_to_one_side = true restringe al lado propio) y se excluye a
	# la propia Belta. Costo todo o nada: si cancela antes de elegir las 2, no se mueve nada.
	var filter := func(c: Node) -> bool:
		return c.owner_id == owner_id and c.card_data != source_card.card_data
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Destierra 2 cartas de tu Cementerio para poner a Belta en juego", filter, 2, "cemetery", true, false, owner_id)
	if picked.size() < 2:
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	for entry in picked:
		var idx: int = CardManager.get_cemetery(owner_id).find(entry.data)
		if idx >= 0:
			CardManager.remove_from_cemetery(owner_id, idx)
			CardManager.add_to_exile(owner_id, entry.data)

	var self_idx: int = CardManager.get_cemetery(owner_id).find(source_card.card_data)
	if self_idx >= 0:
		CardManager.remove_from_cemetery(owner_id, self_idx)

	var ally_data: Dictionary = source_card.card_data.duplicate()
	ally_data["tipo"] = Constants.CardType.ALIADO
	ally_data["fuerza"] = 2
	ally_data["habilidad"] = ""
	var ally_node = main._create_card(ally_data, false)
	ally_node.owner_id = owner_id
	main._connect_card_signals(ally_node)
	await main._gold_manager._play_card_to_field(ally_node)


func _activate_campanita_banish_cancel_or_draw(source_card: Node, ability: Dictionary) -> void:
	"""'Puedes Desterrarlo para cancelar una habilidad o Robar dos cartas' (Campanita) — elección A/B.
	'Cancelar la habilidad' ~ silenciar (misma simplificación de Frankenstein/Red de Plata/Sheut),
	sin restricción de coste ni tipo (a diferencia de Frankenstein, que sí las tiene en su propio
	texto)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main

	var choose_cancel: bool = await SelectionManager.await_two_choice(
		main, "Campanita", "Desterrarla para cancelar una habilidad", "Desterrarla para Robar dos cartas", owner_id)

	var target: Node = null
	if choose_cancel:
		if not main._card_interaction:
			return
		var filter := func(c: Node) -> bool:
			# current_zone en vez de get_parent (ver §10.5)
			return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
				Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]
		target = await main._card_interaction.await_target("Elige una carta para cancelar su habilidad", filter, true, owner_id)
		if not target or not is_instance_valid(target):
			return

	# Rama "roba dos": el Robo no tiene cobertura propia (la de cancelar la tiene en silence_card()),
	# así que la ventana va aquí, antes del autodestierro: después source_card queda inválida para
	# open_response_window().
	if not choose_cancel and await TriggerSystem.open_response_window(source_card, "Campanita", owner_id):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.banish([source_card], source_card, true)

	if choose_cancel and target:
		if TriggerSystem._targeted_executor._target_text_denies(target, ["no puede perder su habilidad", "no pierde su habilidad"]):
			main._update_debug("%s no pierde su habilidad" % str(target.get("card_name")))
		else:
			await KeywordManager.silence_card(target, source_card, "permanent")
	else:
		await ActionModule.draw(owner_id, 2, "activated_ability", true)


func _activate_crono_diamante_discard_ally_discount(source_card: Node, ability: Dictionary) -> void:
	"""Crono Diamante: "Una vez por turno, si jugaste un Aliado de coste 2 o más este turno puedes
	Descartar una carta para jugar un Aliado reduciendo su coste en un Oro, hasta un mínimo de 1".
	Condición: GoldManager._play_card_to_field() registra 'played_ally_cost2plus:0' con cada Aliado
	de coste ≥2 jugado (de cualquier origen). Costo: descartar 1 carta cualquiera de la mano.
	Efecto: jugar otro Aliado de la mano a -1 Oro, piso 1 (allow_zero = false, a diferencia de
	Paladín Bestiarium). "Puedes X para Y" es atómico: solo se ofrecen Aliados que ya son pagables
	con el descuento, antes de preguntar qué descartar."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var hand_container_crono = _inspector._main.player_hand if owner_id == 0 else _inspector._main._opponent_fan
	if not hand_container_crono or hand_container_crono.cards.is_empty():
		return

	if not UniversalCardParser.turn_registry.was_used("played_ally_cost2plus:%d" % owner_id, 0, GameManager.turn_serial):
		_inspector._main._update_debug("Necesitas haber jugado un Aliado de coste 2 o más este turno")
		return

	var hand_cards: Array = hand_container_crono.cards.duplicate()
	var gold_manager: GoldManager = _inspector._main._gold_manager

	var ally_candidates: Array = []
	for c in hand_cards:
		if not is_instance_valid(c) or c.get("card_type") != Constants.CardType.ALIADO:
			continue
		var base_cost: int = int(c.card_cost) if c.get("card_cost") != null else 0
		var discounted_cost: int = maxi(base_cost - 1, 1)
		if gold_manager.puede_pagar(discounted_cost, c.card_type, c.card_raza, base_cost, owner_id):
			ally_candidates.append(c)
	if ally_candidates.is_empty():
		_inspector._main._update_debug("No tienes ningún Aliado que puedas pagar en la mano, ni con el descuento")
		return

	if not _inspector._main._card_interaction:
		return
	# Click directo en la mano en vez de los dos modales de lista viejos.
	var ally_filter := func(c: Node) -> bool: return c in ally_candidates
	var ally_node: Node = await _inspector._main._card_interaction.await_target(
		"Elige el Aliado a jugar con 1 Oro de descuento", ally_filter, true, owner_id)
	if not ally_node or not is_instance_valid(ally_node):
		return

	var discard_filter := func(c: Node) -> bool:
		return c.get("current_zone") == Constants.Zone.MANO and c != ally_node
	if not hand_cards.any(func(c): return discard_filter.call(c)):
		_inspector._main._update_debug("Necesitas otra carta en tu mano para descartar como costo")
		return

	var discard_node: Node = await _inspector._main._card_interaction.await_target(
		"Descarta 1 carta para jugar %s con 1 Oro de descuento" % str(ally_node.card_name), discard_filter, true, owner_id)
	if not discard_node or not is_instance_valid(discard_node):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	await ActionModule.discard(owner_id, [discard_node], "ability_cost", true)

	var applies_to_this_card := func(c: Node) -> bool:
		return c == ally_node
	PaymentManager.agregar_modificador_coste(ally_node, -1, applies_to_this_card, false)
	await gold_manager.play_card(ally_node)


## Drácula no tiene botón para prevenir:
## EffectController.offer_prevention()/offer_prevention_for_player() lo ofrece reactivamente (tags
## "cancel"/"annul") y su 'on_used' hace el auto-convertir + silenciar.


func _activate_dulce_canasta(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, un Aliado gana o pierde 2 de Fuerza permanentemente' (Dulce Canasta). Sin
	costo. Cualquier Aliado en juego, propio o rival (sin calificador de dueño en el texto).
	'permanentemente' = mismo molde que Espada del Juicio: source=target, sobrevive aunque Dulce
	Canasta salga de juego."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var target: Node = await TriggerSystem._targeted_executor._select_ally_target(
		"Elige un Aliado que gane o pierda 2 de Fuerza permanentemente", source_card, owner_id)
	if not target or not is_instance_valid(target):
		return
	var gains: bool = await SelectionManager.await_two_choice(
		_inspector._main, "Dulce Canasta", "Gana 2 de Fuerza", "Pierde 2 de Fuerza", owner_id)
	# Solo el debuff es prevenible (Estaca, tag "strength_change"): un buff no es un efecto hostil.
	if not gains and await EffectController.offer_prevention(target, source_card, "strength_change"):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	ContinuousEffectManager.register_modifier({
		"source": target,
		"target": target,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": 2 if gains else -2,
		"operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
		"description": "%s de Dulce Canasta" % ("Buff" if gains else "Debuff"),
	})


func _activate_ereshkigal_banish_cost1_or_cemeteries(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, puedes Desterrar una carta de coste 1 o menos o Barajar y/o Desterrar dos
	cartas de los Cementerios' (ereshkigal) — elección A/B; B reusa
	GoldManager._resolve_armeria_barajar_desterrar genérica (ya generalizada para Belta/Perla de
	Sangre)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	var choose_banish: bool = await SelectionManager.await_two_choice(
		_inspector._main, "ereshkigal", "Desterrar una carta de coste 1 o menos", "Barajar y/o Desterrar hasta dos cartas de los Cementerios", owner_id)

	if choose_banish:
		var target: Node = await TriggerSystem._targeted_executor._select_banish_target_cost_filter(
			"Elige una carta de coste 1 o menos para desterrar", 1, owner_id)
		if not target or not is_instance_valid(target):
			return
		UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
		await ActionModule.banish([target], source_card, true)
	else:
		if await TriggerSystem.open_response_window(source_card, "ereshkigal", owner_id):
			return
		UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
		await _inspector._main._gold_manager._resolve_armeria_barajar_desterrar(2, "ereshkigal", owner_id)


func _activate_espada_ohiggins_shuffle_or_search_gold(source_card: Node, ability: Dictionary) -> void:
	"""Espada de O'Higgins: "En tu Vigilia, una vez por turno, puedes Barajar una carta que no sea Oro
	o buscar un Oro en tu Castillo y ponerlo en tu mano" — elección A/B como carrera de click
	(CardInteractionModule.await_target_or_castillo_pick(), como Sherlock Holmes/La Ouija;
	arquitectura.md §10.14): brillan a la vez tu Castillo (buscar un Oro) y las cartas en juego que
	no son Oro (barajar); el primer click decide. castillo_own_only = true por "tu Castillo"."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	if not main._card_interaction:
		return

	# current_zone (no get_parent()): un Arma equipada es hija de su portador, no de la línea, y el
	# chequeo por parent no aceptaba cartas cuya jerarquía no calza con la zona lógica.
	var valid_zone_ids = [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	var filter := func(c: Node) -> bool:
		if c.get("card_type") == Constants.CardType.ORO:
			return false
		return c.get("current_zone") in valid_zone_ids
	var result: Dictionary = await main._card_interaction.await_target_or_castillo_pick(
		"Elige una carta que no sea Oro para barajar, o clickea tu Castillo para buscar un Oro",
		filter, "Espada de O'Higgins", true, true, owner_id)

	if result.type == "card":
		var target: Node = result.card
		if not is_instance_valid(target):
			return
		UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
		var target_owner: int = target.controller_id if target.get("controller_id") != null else owner_id
		if await ActionModule.return_to_deck(target, target_owner, true, source_card):
			CardManager.shuffle_deck(target_owner)
	elif result.type == "castillo":
		if await TriggerSystem.open_response_window(source_card, "Espada de O'Higgins", owner_id):
			return
		UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
		await ActionModule.search(owner_id, Constants.Zone.CASTILLO, {"type": Constants.CardType.ORO}, 1, true, false, false, source_card, Constants.Zone.MANO)
	# result.type == "none": ESC sin elegir nada (habilidad opcional, allow_cancel=true) — no hacer nada.


func _activate_espiritu_maquina_shuffle_or_banish_cemetery(source_card: Node, ability: Dictionary) -> void:
	"""Espíritu de la Máquina: "Una vez por turno, puedes Barajar o Desterrar una carta de un
	Cementerio" — "un Cementerio" = elige cuál (propio o rival). Macu comparte el texto ("Una vez
	en tu turno, ...") y este handler; el título usa el nombre real de la carta."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	if not main._zone_viewer:
		return
	# Click directo con los dos Cementerios visibles; "un Cementerio" se resuelve con lock_to_one_side
	# = true, como Hanta el Samurai.
	var no_filter := func(_c: Node) -> bool: return true
	var picked_list: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Elige una carta de un Cementerio", no_filter, 1, "cemetery", true, false, owner_id)
	if picked_list.is_empty():
		return
	var target_owner: int = picked_list[0].owner_id
	var picked_data: Dictionary = picked_list[0].data
	var barajar: bool = await SelectionManager.await_two_choice(
		main, source_card.card_name if source_card.get("card_name") else "Esa carta", "Barajarla", "Desterrarla", owner_id)
	var idx: int = CardManager.get_cemetery(target_owner).find(picked_data)
	if idx < 0:
		return
	if await TriggerSystem.open_response_window(source_card, str(source_card.card_name) if source_card.get("card_name") else "Espíritu de la Máquina", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	CardManager.remove_from_cemetery(target_owner, idx)
	if barajar:
		CardManager.get_deck(target_owner).append(picked_data)
		CardManager.shuffle_deck(target_owner)
		AnimationQueue.queue_shuffle(target_owner, "Barajar mazo (Espíritu de la Máquina)")
	else:
		CardManager.add_to_exile(target_owner, picked_data)
