extends RefCounted
## SearchAbilityHandler_AI — mitad A-I (alfabético por carta) de SearchAbilityHandler.gd (fachada
## que reúne esta mitad y SearchAbilityHandler_JV.gd con los mismos nombres públicos). Opera sobre
## CardInspectionLayer vía _inspector (y sobre Main vía _inspector._main).

var _inspector: CardInspectionLayer


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func _activate_aho_banish_ally_and_deck(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, Destierra un Aliado o Tótem y cinco cartas del tope de un Castillo' (Aho).
	Sin 'puedes': mandatorio una vez activada — clickear el botón ya es la confirmación de uso,
	mismo criterio que el resto de ACTIVATED. 'Un Aliado o Tótem'/'un Castillo' sin posesivo =
	cualquiera de los dos jugadores, a elección (mismo criterio ya confirmado para 'un Cementerio'
	de Miguel). Dos destierros independientes unidos por 'y' (no 'Luego'): ambos ocurren sin
	condicionarse entre sí, aunque el objetivo elegido no exista."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	var target: Node = await TriggerSystem._targeted_executor._select_ally_or_totem_target(
		"Elige un Aliado o Tótem para desterrar", owner_id)

	var look_own: bool = await SelectionManager.await_castillo_pick(_inspector._main, "Aho — destierra 5 del tope", owner_id)
	var deck_owner: int = owner_id if look_own else (1 - owner_id)

	if await TriggerSystem.open_response_window(source_card, "Aho", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	if target and is_instance_valid(target):
		await ActionModule.banish([target], source_card, true)

	var amount: int = CardManager.banish_from_deck(deck_owner, 5, false, owner_id).size()
	# El contador visual del Castillo no se refresca solo al vaciar el Array del mazo a mano:
	# 'destierro 5 del tope pero el contador del castillo sigue igual') — mismo llamado que ya usan el
	# resto de patrones que tocan el mazo directo (ver LookAndPlayResolver/DrawShuffleResolver,
	# _update_castillo_counts.
	if amount > 0 and _inspector._main.get("_zone_manager"):
		_inspector._main._zone_manager._update_castillo_counts()


func _activate_asmodeus_gold_and_banish_bottom(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez en tu turno, genera un Oro y Destierra hasta dos cartas del fondo de un Castillo'
	(Asmodeus) — 'del fondo' (no del tope): se sacan desde el FINAL del array del mazo (pop_back),
	no el inicio. 'un Castillo' sin posesivo = a elección."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager or not TriggerSystem._targeted_executor:
		return
	var controller_id: int = source_card.controller_id if source_card.get("controller_id") != null else 0

	if await TriggerSystem.open_response_window(source_card, "Asmodeus", controller_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	# generar_oros_virtuales ya es por jugador (ver arquitectura.md §33).
	_inspector._main._gold_manager.generar_oros_virtuales(1, controller_id)
	var zone_owner: int = await TriggerSystem._targeted_executor._choose_search_zone_owner(controller_id, Constants.Zone.CASTILLO)
	CardManager.banish_from_deck(zone_owner, 2, true, controller_id)


func _activate_belcebu_banish_bottom_and_steal(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, Destierra tres cartas del fondo de un Castillo y gana el control de hasta
	una carta de coste 3 o menos. En la Fase Final, Ponla en el fondo del Castillo y Roba una
	carta' (Belcebú). 'ganar el control' reusa ContinuousEffectManager. gain_control_of_card
	(primer uso: shedo titan); el retorno al fondo del mazo + Robo se agenda como efecto de un solo
	uso para la PRÓXIMA Fase Final propia (EffectController.schedule_next_final_phase_effect,
	mecanismo de Fisión Nuclear)."""
	if not is_instance_valid(source_card) or not _inspector._main._card_interaction or not TriggerSystem._targeted_executor:
		return
	var controller_id: int = source_card.controller_id if source_card.get("controller_id") != null else 0

	if await TriggerSystem.open_response_window(source_card, "Belcebú", controller_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	var zone_owner: int = await TriggerSystem._targeted_executor._choose_search_zone_owner(controller_id, Constants.Zone.CASTILLO)
	CardManager.banish_from_deck(zone_owner, 3, true, controller_id)

	var main := _inspector._main
	var filter := func(c: Node) -> bool:
		# current_zone en vez de get_parent (ver §10.5)
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, 3)
	var target: Node = await main._card_interaction.await_target("Elige una carta de coste 3 o menos para ganar su control (opcional)", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return
	if await EffectController.offer_prevention(target, source_card, "control"):
		return
	ContinuousEffectManager.gain_control_of_card(target, controller_id)

	EffectController.schedule_next_final_phase_effect(controller_id, func():
		if not is_instance_valid(target):
			return
		var owner_id: int = target.owner_id if target.get("owner_id") != null else controller_id
		var data: Dictionary = target.card_data.duplicate()
		data["esta_oculta"] = true
		var parent = target.get_parent()
		if parent:
			parent.remove_child(target)
		target.queue_free()
		CardManager.get_deck(owner_id).append(data)
		await ActionModule.draw(controller_id, 1, "activated_ability", true)
	)


func _activate_cetro_demoniaco_gold_and_banish(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, genera un Oro y Destierra cuatro cartas del tope de un Castillo' (Cetro
	Demoniaco). 'Un Castillo' sin posesivo = a elección (_choose_search_zone_owner). Oro sin
	restringir (genera_oros_virtuales), no genérico como Padre de la Patria — el texto no dice
	'para jugar X'."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager or not TriggerSystem._targeted_executor:
		return
	var controller_id: int = source_card.controller_id if source_card.get("controller_id") != null else 0

	if await TriggerSystem.open_response_window(source_card, "Cetro Demoniaco", controller_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	# generar_oros_virtuales ya es por jugador (ver arquitectura.md §33).
	_inspector._main._gold_manager.generar_oros_virtuales(1, controller_id)
	var zone_owner: int = await TriggerSystem._targeted_executor._choose_search_zone_owner(controller_id, Constants.Zone.CASTILLO)
	await ActionModule.mill(zone_owner, 4, true, "activated_ability", true)


func _activate_chakram_look_and_lock(source_card: Node, ability: Dictionary) -> void:
	"""Chakram: "Una vez por turno, puedes mirar la mano de tu oponente y elegir una carta de ahí que
	no sea Oro para que no pueda ser jugada hasta tu próximo turno y Roba una carta". El picker ya
	muestra el arte de cada carta, así que sirve para "mirar". main._opponent_fan.get_cards() son
	Nodos reales: el candado es por Nodo (GoldManager.lock_card_from_playing()).
	Se muestra la mano completa, Oros incluidos (visibles pero no clickeables por el filtro de
	await_single_pick())."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var opponent_hand_container = _inspector._main._opponent_fan if owner_id == 0 else _inspector._main.player_hand
	if EffectController.fision_hides_zones_of(1 - owner_id, owner_id, Constants.Zone.MANO):  # Fisión Nuclear
		opponent_hand_container = null
	if await EffectController.offer_colapso_global(owner_id):  # Colapso Global
		opponent_hand_container = null
	var opponent_hand: Array = opponent_hand_container.cards if opponent_hand_container else []
	var candidates: Array = []
	for c in opponent_hand:
		if is_instance_valid(c):
			candidates.append(c)
	if candidates.is_empty():
		_inspector._main._update_debug("Tu oponente no tiene cartas en la mano")
		return
	if not candidates.any(func(c): return c.get("card_type") != Constants.CardType.ORO):
		_inspector._main._update_debug("Tu oponente no tiene ninguna carta (que no sea Oro) en la mano")
		return

	var candidate_data: Array = candidates.map(func(c): return c.card_data)
	var not_oro_filter := func(d: Dictionary) -> bool:
		return d.get("tipo") != Constants.CardType.ORO
	var picked: Dictionary = await SelectionManager.await_single_pick(
		candidate_data, "Mira la mano rival: elige una carta que no sea Oro", true, 0, not_oro_filter, owner_id)
	if picked.is_empty():
		return  # canceló — no se marca 'una vez por turno'

	var chosen: Node = null
	for c in candidates:
		if is_instance_valid(c) and c.card_data == picked:
			chosen = c
			break
	if not chosen:
		return
	if await TriggerSystem.open_response_window(source_card, "Chakram", owner_id):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	if _inspector._main._gold_manager:
		_inspector._main._gold_manager.lock_card_from_playing(chosen, owner_id)

	await ActionModule.draw(owner_id, 1, "activated_ability", true)


func _activate_cuerno_titan_discard_search_cost_adjust(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, puedes Descartar una carta de tu mano para busca una carta Titán en tu
	Castillo, ponerla en tu mano y aumentar o disminuir el coste de hasta una carta en juego en un
	Oro' (Cuerno de Titán) — costo: Descartar UNA carta de la mano elegida por el jugador; efecto:
	buscar un Titán (cualquier tipo con raza 'Titán', no solo Aliado) + ajustar el coste de una
	carta en juego (elegida) en ±1 de forma PERMANENTE mientras Cuerno de Titán siga en juego."""
	if not is_instance_valid(source_card) or not _inspector._main._card_interaction:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	var hand_container_cuerno = main.player_hand if owner_id == 0 else main._opponent_fan
	if not hand_container_cuerno or hand_container_cuerno.cards.is_empty():
		return

	# Click directo en la mano, filtrado por owner_id (como gran kraken,
	# PreventionAbilityHandler_EP.gd).
	var hand_filter := func(c: Node) -> bool:
		return c.get("current_zone") == Constants.Zone.MANO and c.get("owner_id") == owner_id
	var hand_node: Node = await main._card_interaction.await_target(
		"Descarta una carta de tu mano para pagar la habilidad", hand_filter, true, owner_id)
	if not hand_node or not is_instance_valid(hand_node):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.discard(owner_id, [hand_node], "activated_ability", true)
	# Ventana para la búsqueda (automática, sin más objetivo que declarar) —
	# el ajuste de coste de más abajo tiene la suya propia, más adelante.
	if await TriggerSystem.open_response_window(source_card, "Cuerno de Titán", owner_id):
		return

	var deck: Array = CardManager.get_deck(owner_id)
	var found_idx: int = -1
	for i in range(deck.size()):
		if "tit" in str(deck[i].get("raza", "")).to_lower():
			found_idx = i
			break
	if found_idx != -1:
		var found_data: Dictionary = deck[found_idx]
		deck.remove_at(found_idx)
		CardManager.shuffle_deck(owner_id)
		AnimationQueue.queue_shuffle(owner_id, "Barajar mazo (Cuerno de Titán)")
		var card_node = main._create_card(found_data, false)
		hand_container_cuerno.add_card(card_node)
		main._connect_card_signals(card_node)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()

	var filter := func(c: Node) -> bool:
		# current_zone en vez de get_parent (ver §10.5)
		return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
			Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]
	var target: Node = await main._card_interaction.await_target("Elige una carta en juego para aumentar o disminuir su coste en 1 (opcional)", filter, true, owner_id)
	if not target or not is_instance_valid(target):
		return
	var choose_increase: bool = await SelectionManager.await_two_choice(
		main, "Cuerno de Titán", "Aumentar su coste en 1", "Disminuir su coste en 1", owner_id)
	if await TriggerSystem.open_response_window(source_card, "Cuerno de Titán", owner_id):
		return
	# ContinuousEffectManager, no PaymentManager: PaymentManager.cost_modifiers se vacía en cada turno
	# (descuentos de un uso). Este ajuste no dice "por el turno": dura mientras Cuerno de Titán siga en
	# juego, como las demás auras de coste (Asmodeus/Belcebú).
	ContinuousEffectManager.register_modifier({
		"source": source_card,
		"target": target,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "cost",
		"value": 1 if choose_increase else -1,
		"operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
		"description": "Cuerno de Titán: coste %s 1" % ("+" if choose_increase else "-"),
	})
	if target.has_method("refresh_cost_badge"):
		target.refresh_cost_badge()


func _activate_don_de_amma(source_card: Node, ability: Dictionary) -> void:
	"""Don de Amma: "Una vez por turno, puedes Desterrar un Oro con habilidad de tu Reserva. Luego,
	busca un Oro en tu Castillo y ponlo en tu Reserva". El Oro a Desterrar puede ser cualquier Oro
	con habilidad de la Reserva; si hay uno solo (normalmente esta carta) no se pregunta. La
	búsqueda usa _execute_targeted_search(), que entiende "ponlo en tu Reserva" como destino
	RESERVA_ORO."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var reserva_container = _inspector._main.player_gold if owner_id == 0 else _inspector._main.opponent_gold
	if not reserva_container:
		return
	var ability_oros: Array = []
	for c in reserva_container.get_children():
		if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ORO \
				and str(c.get("card_ability")) != "":
			ability_oros.append(c)
	if ability_oros.is_empty():
		return

	var to_exile: Node = ability_oros[0]
	if ability_oros.size() > 1 and owner_id == 0 and _inspector._main._card_interaction:
		# Click directo en la Reserva en vez del modal de lista viejo.
		var oro_filter := func(c: Node) -> bool: return c in ability_oros
		var picked_node: Node = await _inspector._main._card_interaction.await_target(
			"Elige qué Oro con habilidad Desterrar de tu Reserva", oro_filter)
		if not picked_node or not is_instance_valid(picked_node):
			return  # Canceló — no paga el costo, no hay búsqueda
		to_exile = picked_node

	# Registrar ANTES de Desterrar: to_exile suele ser la propia source_card y tras exile_card() el
	# Node puede quedar inválido. Por lo mismo la ventana de respuesta va aquí y no antes del search().
	if await TriggerSystem.open_response_window(source_card, "Don de Amma", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	await EffectController.exile_card(owner_id, to_exile, true)

	# Búsqueda directa (no _execute_targeted_search(), que relee card_ability
	# desde el Node — puede haber quedado inválido si to_exile == source_card):
	# 'busca un Oro en tu Castillo y ponlo en tu Reserva', ya soportado por
	# ActionModule.search() con destination=RESERVA_ORO (agregado para esta
	# misma carta).
	await ActionModule.search(owner_id, Constants.Zone.CASTILLO, {"type": Constants.CardType.ORO}, 1, true, false, false, null, Constants.Zone.RESERVA_ORO, false)


func _activate_dyyavol_titan_draw_discard_mill(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, Roba una carta y Descarta una carta.... Si la carta Descartada es un Ignis
	o Titán cada jugador Bota tres cartas' (dyyavol titan) — solo Robar+Descartar+el Bote
	condicional por raza; 'Aumenta el coste de hasta dos Aliados Titán en juego en dos Oros
	mientras estén en juego' (targeting aparte, modificador de coste persistente por carta) NO
	implementado."""
	if not is_instance_valid(source_card) or not _inspector._main.player_hand:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	if await TriggerSystem.open_response_window(source_card, "dyyavol titan", owner_id):
		return
	await ActionModule.draw(owner_id, 1, "activated_ability", true)

	# Mano según owner_id: player_hand para el jugador 0, _opponent_fan para el jugador 1 (bot/Remoto).
	var hand_cards: Array = (_inspector._main.player_hand.cards if owner_id == 0 else _inspector._main._opponent_fan.get_cards()).duplicate()
	if hand_cards.is_empty():
		return
	var to_discard: Array = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand_cards, 1, owner_id)
	if to_discard.is_empty():
		return
	var discarded_race: String = str(to_discard[0].get("card_raza") if to_discard[0].get("card_raza") != null else "").to_lower()
	await ActionModule.discard(owner_id, to_discard, "activated_ability", true)

	if "ignis" in discarded_race or "tit" in discarded_race:
		for player_id in [0, 1]:
			await ActionModule.mill(player_id, 3, false, "activated_ability", true)


func _activate_espada_ohiggins_vigilia_choice(source_card: Node, ability: Dictionary) -> void:
	"""Espada de O'Higgins: "En tu Vigilia, una vez por turno, puedes Barajar una carta que no sea Oro
	o buscar un Oro en tu Castillo y ponerlo en tu mano". Elección A/B entre dos efectos
	(ActionPipeline solo resuelve una acción por habilidad). La fase la valida _validate_ability().
	El uso se registra al resolver la elección, aunque la rama elegida no encuentre objetivos."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	var choose_shuffle: bool = await SelectionManager.await_two_choice(
		_inspector._main, "Espada de O'Higgins",
		"Barajar una carta (no Oro) en juego", "Buscar un Oro en tu Castillo", owner_id)

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	if choose_shuffle:
		# "Barajar una carta que no sea Oro", sin "que controles" ni "oponente": cualquier carta en juego
		# de los dos jugadores (como Aho/Miguel). Campo, Línea de Ataque y Línea de Apoyo de ambos, más
		# las Armas equipadas; Reserva y Oro Pagado quedan fuera (solo tienen Oro).
		var in_play_containers: Array = [
			_inspector._main.player_field, _inspector._main.player_linea_ataque, _inspector._main.player_linea_apoyo,
			_inspector._main.opponent_field, _inspector._main.opponent_linea_ataque, _inspector._main.opponent_linea_apoyo,
		]
		if not _inspector._main._card_interaction:
			return
		# Click directo sobre las cartas reales en juego en vez del modal de lista viejo.
		var not_oro_filter := func(c: Node) -> bool:
			if not (c is Card) or c.get("card_type") == Constants.CardType.ORO:
				return false
			return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
		var to_shuffle_node: Node = await _inspector._main._card_interaction.await_target(
			"Baraja una carta (que no sea Oro) en juego", not_oro_filter, true, owner_id)
		if not to_shuffle_node or not is_instance_valid(to_shuffle_node):
			return
		# Vuelve al Castillo del DUEÑO de la carta elegida, no del que activó la habilidad.
		var shuffle_owner: int = to_shuffle_node.owner_id if to_shuffle_node.get("owner_id") != null else owner_id
		await ActionModule.return_to_deck(to_shuffle_node, shuffle_owner, true, source_card)
		ActionModule.shuffle_deck(shuffle_owner)
	else:
		if await TriggerSystem.open_response_window(source_card, "Espada de O'Higgins", owner_id):
			return
		await ActionModule.search(owner_id, Constants.Zone.CASTILLO, {"type": Constants.CardType.ORO}, 1, true, false, false, null, Constants.Zone.MANO, false)


func _activate_infernum_vox_look_reorder(source_card: Node, ability: Dictionary) -> void:
	"""Infernum Vox: "Una vez por turno, puedes mirar seis cartas del tope de un Castillo y
	devolverlas en cualquier orden en el tope y/o fondo del Castillo". "Un Castillo" sin posesivo =
	propio o rival, a elección. El orden se arma con dos await_multi_pick(), que preservan el orden
	de click:
	1) cuáles van al FONDO, en orden (0 a todas; primero clickeado = más arriba dentro del grupo
	del fondo);
	2) las que quedan van al TOPE; una segunda selección de todas (min = max) solo para capturar su
	orden."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	# await_castillo_pick/await_multi_pick ya tienen puente de red. Límite conocido para el Remoto
	# específicamente en ESTA carta: la UI remota de multi-selección usa checkboxes, no orden de click,
	# así que el reordenamiento en sí no se respeta de su lado (siempre vuelve en el orden que ya
	# tenía) — "mirar y elegir cuáles van al fondo" sí funciona igual para los dos lados.
	var look_own: bool = await SelectionManager.await_castillo_pick(_inspector._main, "Infernum Vox — mira 6 cartas", owner_id)
	var target_player: int = owner_id if look_own else (1 - owner_id)

	var deck: Array = CardManager.get_deck(target_player)
	var amount: int = mini(6, deck.size())
	if amount <= 0:
		return
	# Una sola ventana para todo el reordenamiento: no hay objetivo puntual que declarar (las 6 salen
	# del tope), como el resto de "mira/revela N... reordena".
	if await TriggerSystem.open_response_window(source_card, "Infernum Vox", owner_id):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	# pop_front() = tope real (el robo usa ZoneManager.draw_card(), que hace pop_front() sobre este
	# array). La primera carta sacada es la de más arriba.
	var peeked: Array = []
	for i in range(amount):
		peeked.append(deck.pop_front())

	var result_bottom: Dictionary = await SelectionManager.await_multi_pick(
		peeked, "Elige, EN ORDEN, las cartas que van al FONDO del Castillo (puedes no elegir ninguna)",
		amount, 0, false, Callable(), owner_id)
	var ordered_bottom: Array = result_bottom.picked

	var ordered_top: Array = peeked.duplicate()
	for card_data in ordered_bottom:
		ordered_top.erase(card_data)

	if ordered_top.size() > 1:
		var result_top: Dictionary = await SelectionManager.await_multi_pick(
			ordered_top, "Ordena las cartas que quedan en el TOPE (elegilas de arriba hacia abajo)",
			ordered_top.size(), ordered_top.size(), false, Callable(), owner_id)
		ordered_top = result_top.picked

	# add_to_deck_bottom() = append: el último en agregarse queda como fondo absoluto. Pasando
	# ordered_bottom en su orden (primero = más arriba del grupo), ordered_bottom.back() termina al
	# fondo.
	for card_data in ordered_bottom:
		CardManager.add_to_deck_bottom(target_player, card_data)

	# add_to_deck_top() = insert(0, ...): el ÚLTIMO en agregarse queda como
	# tope absoluto — hay que recorrer ordered_top AL REVÉS (el que va más
	# abajo del grupo primero) para que ordered_top[0] (el que el jugador
	# quiere más arriba) termine siendo el último en agregarse.
	for i in range(ordered_top.size() - 1, -1, -1):
		CardManager.add_to_deck_top(target_player, ordered_top[i])
