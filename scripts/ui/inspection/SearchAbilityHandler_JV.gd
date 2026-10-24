extends RefCounted
## SearchAbilityHandler_JV — mitad J-V (alfabético por carta) de SearchAbilityHandler.gd (fachada
## que reúne esta mitad y SearchAbilityHandler_AI.gd con los mismos nombres públicos). Opera sobre
## CardInspectionLayer vía _inspector (y sobre Main vía _inspector._main).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CastleLookScript = preload("res://scripts/core/effects/CastleLook.gd")  # "mira N cartas" (§69)

var _inspector: CardInspectionLayer


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func _activate_jinete_peste_search_banish_two(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, busca en un Castillo dos cartas de distinto nombre y Destiérralas. Si
	controlas otro Jinete, además Roba una carta' (Jinete de la Peste) — 'un Castillo' sin posesivo
	= a elección. 'Si controlas cuatro Aliados Jinete, tu oponente no puede poner cartas en su mano
	por efectos': ProtectionRules.hand_by_effects_blocked()."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	if not TriggerSystem._targeted_executor:
		return

	if await TriggerSystem.open_response_window(source_card, "Jinete de la Peste", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.search_either_owner(owner_id, [Constants.Zone.CASTILLO], {}, 2, true, source_card,
		Constants.Zone.DESTIERRO, true)

	var main := _inspector._main
	var controls_other_jinete := false
	var own_fields_jinete: Array = [main.player_field, main.player_linea_ataque] if owner_id == 0 else [main.opponent_field, main.opponent_linea_ataque]
	for field in own_fields_jinete:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and c != source_card and "jinete" in str(c.get("card_name")).to_lower():
				controls_other_jinete = true
	if controls_other_jinete:
		await ActionModule.draw(owner_id, 1, "activated_ability", true)


func _activate_kotaix_draw_and_shuffle_opponent(source_card: Node, ability: Dictionary) -> void:
	"""Espíritu Kotaix (segunda habilidad): "Una vez por turno, Roba dos cartas y Baraja una carta
	oponente que no sea Oro. Esta habilidad no puede ser cancelada." "Una carta oponente" sin zona
	= en juego, sin Oros. Sin "puedes" y unido por "y": el Robo ocurre siempre, haya o no objetivo
	(como Estaca, Espada de O'Higgins, Aho). "No puede ser cancelada" se cumple porque se resuelve
	directo aquí, sin pasar por la Pila."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	# Ventana única para toda la habilidad: sin declare real todavía aquí (el objetivo rival se elige
	# solo más abajo), mismo criterio que Estaca (HandCementerioAbilityHandler.gd).
	if await TriggerSystem.open_response_window(source_card, "Espíritu Kotaix", owner_id):
		return

	await ActionModule.draw(owner_id, 2, "activated_ability", true)

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	var opponent_id: int = 1 - owner_id
	var opp_fields: Array = [_inspector._main.opponent_field, _inspector._main.opponent_linea_ataque, _inspector._main.opponent_linea_apoyo] if owner_id == 0 \
		else [_inspector._main.player_field, _inspector._main.player_linea_ataque, _inspector._main.player_linea_apoyo]
	var candidates: Array = []
	for field in opp_fields:
		if not field:
			continue
		for c in field.get_children():
			if not is_instance_valid(c):
				continue
			if c.get("card_type") != Constants.CardType.ORO:
				candidates.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and w.get("card_type") != Constants.CardType.ORO:
						candidates.append(w)
	if candidates.is_empty():
		return

	var filter := func(c: Node) -> bool:
		return c in candidates
	var target: Node = await _inspector._main._card_interaction.await_target(
		"Elige una carta rival en juego (que no sea Oro) para barajar", filter, true, owner_id)
	if not target or not is_instance_valid(target):
		return

	await ActionModule.return_to_deck(target, opponent_id, true, source_card)
	CardManager.shuffle_deck(opponent_id)
	AnimationQueue.queue_shuffle(opponent_id, "Barajar mazo (Espíritu Kotaix)")


func _activate_kuchiku_cazador_search_and_play_discount(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez en tu turno, busca en tu Castillo o Cementerio un Aliado y
	juégalo reduciendo su coste en un Oro, hasta un mínimo de 0' (Kuchiku
	El Cazador, myl_id 20593, edición kvsm_titanes). 'Castillo o
	Cementerio' es 'y/o' entre zonas ([[project_y_o_means_choose_one_zone]])
	— el jugador elige UNA, no se combinan en un solo pool. Reusa
	ActionModule.search() para la mecánica de búsqueda/UI/barajado del
	Castillo (must_shuffle ya incluido), con may_play=false para poder
	aplicar el descuento de coste ANTES de intentar jugarla — mismo
	mecanismo puntual que Miguel (_activate_miguel_discount_play): -1 Oro,
	piso 0 (aquí con allow_zero=true porque el texto SÍ dice explícitamente
	'hasta un mínimo de 0'). La carta encontrada se identifica comparando
	la mano antes/después de la búsqueda (ActionModule.search() no
	devuelve el Card node creado, solo el Dictionary de datos)."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var hand_container_kuchiku = _inspector._main.player_hand if owner_id == 0 else _inspector._main._opponent_fan
	if not hand_container_kuchiku:
		return

	# Tu Castillo y tu Cementerio en el selector del tablero, en vez del popup "¿Dónde buscar?".
	var hand_before: Array = hand_container_kuchiku.cards.duplicate()
	var result: Dictionary = await ActionModule.search_zones(owner_id, [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO],
		{"type": Constants.CardType.ALIADO}, 1, true, false, false, source_card, Constants.Zone.MANO)
	if result.get("selected", []).is_empty():
		_inspector._main._update_debug("No se encontró ningún Aliado ahí")
		return

	var card_node: Node = null
	for c in hand_container_kuchiku.cards:
		if c not in hand_before:
			card_node = c
			break
	if not is_instance_valid(card_node):
		return

	var applies_to_this_card := func(c: Node) -> bool:
		return c == card_node
	PaymentManager.agregar_modificador_coste(card_node, -1, applies_to_this_card, true)
	if card_node.has_method("refresh_cost_badge"):
		card_node.refresh_cost_badge()

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	await _inspector._main._gold_manager.play_card(card_node)


func _activate_kuchiku_cazador_destroy_and_discard(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez en tu turno, puedes Destruir hasta una carta de coste 3 o
	menos y tu oponente Bota cartas igual a la Fuerza de este Aliado'
	(Kuchiku El Cazador). Objetivo genérico en juego (Aliado/Arma/Tótem/
	Oro, ambos jugadores) con tope de coste 3 — a diferencia de
	_select_annul_target_cost_filter() (que excluye Oro porque 'anular' un
	Oro no tiene sentido), aquí SÍ puede ser Oro (destruirlo sí tiene
	sentido). 'Hasta una carta' = el Destruir es opcional (0 o 1, cancelar
	el picker = 0), pero el descarte del oponente NO está condicionado a
	que el Destruir se concrete — son dos cláusulas independientes unidas
	por 'y', ambas dentro del mismo 'puedes' de activar la habilidad
	(clickear el botón ya es esa confirmación, mismo criterio que Espada
	de O'Higgins). Cantidad de descarte dinámica: la Fuerza ACTUAL de este
	Aliado (con modificadores continuos aplicados) — reusa
	_execute_targeted_discard() para el descarte en sí (mano del
	oponente; si el humano es quien descarta, él elige cuáles)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	if not main or not main._card_interaction:
		return

	var filter := func(c: Node) -> bool:
		if c.get("card_type") not in [Constants.CardType.ALIADO, Constants.CardType.ARMA, Constants.CardType.TOTEM, Constants.CardType.ORO]:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
				Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]:
			return false
		# get_modified_cost, no card_cost crudo: una carta en juego puede tener el coste reducido de forma
		# continua, p.ej. Samael — el filtro tiene que verlo
		return ContinuousEffectManager.cost_at_most(c, 3)
	var chosen_target: Node = await main._card_interaction.await_target(
		"Elige una carta de coste 3 o menos para destruir (opcional)", filter, true, owner_id)

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	if chosen_target and is_instance_valid(chosen_target):
		if not TriggerSystem._targeted_executor._target_text_denies(chosen_target, ["no puede ser destruid"]):
			await ActionModule.destroy([chosen_target], source_card, true, true)

	var strength: int = ContinuousEffectManager.get_modified_strength(source_card)
	if strength > 0:
		await TriggerSystem._targeted_executor._execute_targeted_discard(source_card, owner_id, strength)


func _activate_lider_del_comite_discard_look_name_lock(source_card: Node, ability: Dictionary) -> void:
	"""lider del comite: "En tu Vigilia, una vez por turno, puedes Descartar una carta para mirar la
	mano de tu oponente y nombrar una carta. Las cartas con ese nombre pierden su habilidad y tu
	oponente no puede jugarlas el próximo turno". Costo: Descartar 1 carta propia. Efecto: revelado
	informativo de la mano rival (SelectionManager.open_reveal, no interactivo; el nombre puede ser
	cualquier carta) + KeywordManager.lock_ability_by_name() (todas las copias, mientras esta carta
	siga en juego) + GoldManager.lock_card_from_playing() sobre las copias ya en la mano rival.
	Límite: las que se roben después no quedan bloqueadas para jugar."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var hand_container_lider = _inspector._main.player_hand if owner_id == 0 else _inspector._main._opponent_fan
	if not hand_container_lider or hand_container_lider.cards.is_empty():
		return  # sin mano no hay costo que pagar

	if not _inspector._main._card_interaction:
		return
	# Click directo en la mano en vez del modal de lista viejo.
	var hand_filter := func(c: Node) -> bool: return c.get("current_zone") == Constants.Zone.MANO
	var to_discard_node: Node = await _inspector._main._card_interaction.await_target(
		"Descarta 1 carta de tu mano", hand_filter, true, owner_id)
	if not to_discard_node or not is_instance_valid(to_discard_node):
		return  # canceló — no paga el costo

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.discard(owner_id, [to_discard_node], "activated_ability", true)

	var opponent_hand_container = _inspector._main._opponent_fan if owner_id == 0 else _inspector._main.player_hand
	if EffectController.fision_hides_zones_of(1 - owner_id, owner_id, Constants.Zone.MANO):  # Fisión Nuclear
		opponent_hand_container = null
	if await EffectController.offer_colapso_global(owner_id):  # Colapso Global
		opponent_hand_container = null
	var opponent_hand: Array = opponent_hand_container.cards if opponent_hand_container else []
	var opponent_hand_data: Array = []
	for c in opponent_hand:
		if is_instance_valid(c):
			opponent_hand_data.append(c.card_data)
	if not opponent_hand_data.is_empty():
		SelectionManager.open_reveal(opponent_hand_data, "Mano de tu oponente", owner_id)

	var picked_card: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
		"Nombra una carta: pierde su habilidad y tu oponente no puede jugarla el próximo turno",
		owner_id
	)
	if picked_card.is_empty():
		return
	var picked_name: String = str(picked_card.get("nombre", ""))
	if picked_name.is_empty():
		return
	if await TriggerSystem.open_response_window(source_card, "lider del comite", owner_id):
		return

	KeywordManager.lock_ability_by_name(picked_name, source_card)
	for c in opponent_hand:
		if is_instance_valid(c) and str(c.get("card_name")).to_lower() == picked_name.to_lower():
			# owner_id (activador), no el rival: lock_card_from_playing() limpia
			# el candado cuando empieza el turno de 'locking_player_id' — igual
			# que Chakram, "hasta tu próximo turno" = dura el turno rival
			# intermedio completo, se limpia al iniciar mi turno siguiente.
			_inspector._main._gold_manager.lock_card_from_playing(c, owner_id)
	_inspector._main._update_debug("'%s' pierde su habilidad y no puede jugarse el próximo turno" % picked_name)


func _activate_miguel_discount_play(source_card: Node, ability: Dictionary) -> void:
	"""Miguel: "Una vez en tu turno, juega una carta de tu mano o de un Cementerio reduciendo su coste
	en un Oro, hasta un mínimo de 0". "Un Cementerio" = propio o rival; jugarla te vuelve su
	CONTROLADOR y al salir vuelve al Cementerio/Destierro de su dueño.
	Se elige desde el tablero, igual para Anfitrión y Remoto: las cartas jugables de la mano
	brillan y los Cementerios se abren con clic (ZoneBrowsePicker vía ActionModule.pick_in_zones(),
	§53). Nunca ofrece Oros (no se juegan y no tienen coste)."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager:
		return
	var main = _inspector._main
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	# Asequible con el descuento (dato crudo de coste: las del Cementerio
	# todavía no tienen Nodo para calcular_coste_real()).
	var available_gold: int = GameState.get_oro_reserva(owner_id) + main._gold_manager.oros_virtuales.get(owner_id, 0)
	var affordable := func(data: Dictionary) -> bool:
		if int(data.get("tipo", -1)) == Constants.CardType.ORO:
			return false
		var raw_cost = data.get("coste")
		if raw_cost == null or not (raw_cost is int or raw_cost is float or (raw_cost is String and raw_cost.is_valid_int())):
			return false
		return maxi(int(raw_cost) - 1, 0) <= available_gold

	var hand_candidates: Array = []
	for c in PlayerSideScript.hand_cards(main, owner_id):
		if is_instance_valid(c) and affordable.call(c.card_data):
			hand_candidates.append(c)
	# Los dos Cementerios, con is_own relativo a quien elige (owner_id).
	var pools: Array = []
	var cem_owners: Array = []
	var any_cemetery := false
	for cem_owner in [owner_id, 1 - owner_id]:
		var entries: Array = []
		for d in CardManager.get_cemetery(cem_owner):
			var ok: bool = affordable.call(d)
			any_cemetery = any_cemetery or ok
			entries.append({"data": d, "eligible": ok})
		pools.append({"is_own": cem_owner == owner_id, "zone": Constants.Zone.CEMENTERIO, "cards": entries})
		cem_owners.append(cem_owner)
	if hand_candidates.is_empty() and not any_cemetery:
		main._update_debug("No tienes ninguna carta que puedas jugar ni con el descuento")
		return

	var picks: Array = await ActionModule.pick_in_zones(owner_id, "Miguel: juega una carta con 1 Oro de descuento",
		pools, 0, 1, false, hand_candidates)
	if picks.is_empty() or not (picks[0] is Array) or picks[0].size() != 2:
		return
	var pi: int = int(picks[0][0])
	var ci: int = int(picks[0][1])
	var card_node: Node = null
	if pi == -1:
		if ci < 0 or ci >= hand_candidates.size():
			return
		card_node = hand_candidates[ci]
	else:
		# Revalidación (por red puede llegar cualquier cosa).
		if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			return
		var picked_data: Dictionary = pools[pi].cards[ci].data
		var cemetery_owner: int = cem_owners[pi]
		if not CardManager.take_from_cemetery(cemetery_owner, picked_data):
			return
		card_node = main._create_card(picked_data, owner_id != 0)
		# Dueño = de qué Cementerio salió; controlador = quien la juega
		# (ver arquitectura.md §38).
		card_node.owner_id = cemetery_owner
		card_node.controller_id = owner_id
		PlayerSideScript.hand(main, owner_id).add_card(card_node)
		main._connect_card_signals(card_node)

	await _play_miguel_choice(source_card, ability, card_node, owner_id)


func _play_miguel_choice(source_card: Node, ability: Dictionary, card_node: Node, owner_id: int) -> void:
	"""Juega la carta elegida para Miguel con −1 Oro (piso 0). Con
	PlayerSide.play_from_hand(): GoldManager.play_card() es solo del
	Anfitrión (para el Remoto rechazaba con 'No es tu turno', §57)."""
	if not is_instance_valid(card_node):
		return

	var applies_to_this_card := func(c: Node) -> bool:
		return c == card_node
	PaymentManager.agregar_modificador_coste(card_node, -1, applies_to_this_card, true)
	if card_node.has_method("refresh_cost_badge"):
		card_node.refresh_cost_badge()

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	await PlayerSideScript.play_from_hand(_inspector._main, owner_id, card_node)


func _activate_padre_patria_gold(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez en tu turno, genera un Oro para jugar Armas o Aliados Caballero por el turno' (Padre
	de la Patria). Sin coste ni objetivo — se genera directo como Oro Virtual restringido
	(GoldManager.restricted_gold_pools) y se marca usada este turno."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	if await TriggerSystem.open_response_window(source_card, "Padre de la Patria", owner_id):
		return
	var predicate := func(card_type: int, card_race: String, _card_cost: int) -> bool:
		if card_type == Constants.CardType.ARMA:
			return true
		if card_type == Constants.CardType.ALIADO:
			return "caballero" in card_race.to_lower()
		return false
	# generar_oro_virtual_restringido ya es por jugador (ver arquitectura.md §33) — el guard que se le
	# había agregado en §27 (por el motivo documentado abajo) ya no hace falta.
	_inspector._main._gold_manager.generar_oro_virtual_restringido(1, predicate, "Armas o Aliados Caballero", owner_id)

	# instance_id, no card_data.id — cada copia física necesita su propio cupo de 'una vez por turno'.
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)


func _activate_patria_vieja_look_six(source_card: Node, ability: Dictionary) -> void:
	"""Patria Vieja: "En tu Vigilia, si no has puesto Oros en juego este turno, puedes mirar las
	primeras seis cartas de tu Castillo y poner un Oro de ahí en tu Reserva. Esta habilidad no
	puede ser cancelada". Sin ventana de respuesta. La ventana de mirar es CastleLook (§69): el Oro
	a la Reserva y las demás se ordenan en el tope. La versión IMP agrega "como un Oro sin
	habilidad"."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.controller_id if source_card.get("controller_id") != null else 0
	var main := _inspector._main
	if main._gold_manager.oros_en_juego_turno.get(owner_id, 0) > 0:
		main._update_debug("Patria Vieja: ya pusiste Oros en juego este turno")
		return
	if CardManager.get_deck(owner_id).is_empty():
		main._update_debug("Patria Vieja: tu Castillo está vacío")
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	if not await CastleLookScript.try_execute_text(source_card, str(ability.get("raw_text", "")), owner_id):
		push_warning("[Patria Vieja] CastleLook no entendió: %s" % str(ability.get("raw_text", "")))


func _activate_cemetery_granted_draw(source_card: Node, ability: Dictionary) -> void:
	"""Duelo Espacial en el Cementerio: 'gana la habilidad "En tu Vigilia, puedes Robar una carta.
	Sólo puedes utilizar esta habilidad de Duelo Espacial una vez por turno"'."""
	if not is_instance_valid(source_card):
		return
	# Datos capturados antes de cualquier await: en el Cementerio la carta es
	# un Nodo temporal que puede liberarse mientras se resuelve.
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var card_name: String = str(source_card.get("card_name"))
	# "esta habilidad de Duelo Espacial una vez por turno" = una vez por turno
	# por NOMBRE (todas las copias), no por copia — y los Nodos temporales del
	# Cementerio cambian de instance_id cada vez que se abre.
	var key: String = "cemetery_granted:%s:%d" % [card_name.to_lower(), owner_id]
	if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.turn_serial):
		_inspector._main._update_debug("%s: ya usaste esta habilidad este turno" % card_name)
		return
	UniversalCardParser.turn_registry.register(key, 0, GameManager.turn_serial)
	if await TriggerSystem.open_response_window(source_card, card_name, owner_id):
		return
	await ActionModule.draw(owner_id, 1, card_name, true)


func _activate_quimera_voragh_mill_and_revive(source_card: Node, ability: Dictionary) -> void:
	"""quimera voragh: "Una vez en tu turno, cada jugador Bota tres cartas. Si se Botaron Aliados u
	Oros, pon en juego una carta de un Cementerio como un Aliado de Fuerza 2 con la habilidad
	'Furia'". Botar se hace directo sobre CardManager (no ActionModule.mill(), que no informa el
	tipo de cada carta; ver ea poe) porque hace falta saber si cayó un Aliado/Oro. La conversión es
	como leon indiferente/Sherlock Holmes (Fuerza fijada + KeywordManager.silence_card + Furia)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main

	if await TriggerSystem.open_response_window(source_card, "quimera voragh", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	var ally_or_gold_milled := false
	for player_id in [0, 1]:
		var deck: Array = CardManager.get_deck(player_id)
		var cemetery: Array = CardManager.get_cemetery(player_id)
		for i in range(3):
			if deck.is_empty():
				break
			var card_data: Dictionary = deck.pop_front()
			card_data["esta_oculta"] = false
			var tipo: int = card_data.get("tipo", -1)
			if tipo == Constants.CardType.ALIADO or tipo == Constants.CardType.ORO:
				ally_or_gold_milled = true
			cemetery.append(card_data)
		CardManager._emit_deck_changed(player_id)
		CardManager._emit_cemetery_changed(player_id)

	if not ally_or_gold_milled:
		return

	if not main._zone_viewer:
		return
	# Click directo con ambos Cementerios visibles en vez del modal de lista viejo.
	var no_filter := func(_c: Node) -> bool: return true
	var picked_list: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Elige una carta de un Cementerio para poner en juego como Aliado de Fuerza 2 con Furia", no_filter, 1, "cemetery", false, false, owner_id)
	if picked_list.is_empty():
		return
	var chosen_owner: int = picked_list[0].owner_id
	var picked: Dictionary = picked_list[0].data

	if not CardManager.take_from_cemetery(chosen_owner, picked):
		return

	var new_data: Dictionary = picked.duplicate()
	new_data["tipo"] = Constants.CardType.ALIADO
	new_data["esta_oculta"] = false
	var token_node = main._create_card(new_data, false)
	token_node.owner_id = owner_id
	main._connect_card_signals(token_node)
	var target_field: HBoxContainer = main.player_field if owner_id == 0 else main.opponent_field
	target_field.add_child(token_node)
	token_node.can_interact = (owner_id == 0)
	token_node.top_level = false
	token_node.set_zone(Constants.Zone.LINEA_DEFENSA)
	token_node.is_converted = true
	await KeywordManager.silence_card(token_node, source_card, "permanent")
	ContinuousEffectManager.register_modifier({
		"source": source_card,
		"target": token_node,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": 2,
		"operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "Convertido por quimera voragh (Fuerza fija 2)",
	})
	ContinuousEffectManager.register_modifier({
		"source": source_card,
		"target": token_node,
		"type": ContinuousEffectManager.ModifierType.KEYWORDS,
		"stat": "",
		"value": 0,
		"operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_6_ABILITIES,
		"keywords_add": [Constants.Keyword.FURIA],
		"description": "Convertido por quimera voragh (Furia)",
	})
	if token_node.has_method("refresh_strength_badge"):
		token_node.refresh_strength_badge()


func _activate_tenshi_z_shuffle_hand_to_annul(source_card: Node, ability: Dictionary) -> void:
	"""Tenshi Z: "Una vez por turno, puedes Barajar una carta de tu mano para Anular una carta".
	Costo: barajar una carta elegida de la mano al mazo; efecto: Anular (≈ destruir) cualquier
	carta en juego. Se confirma que hay objetivo antes de cobrar el costo."""
	if not is_instance_valid(source_card) or not _inspector._main._card_interaction:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var main := _inspector._main
	var hand_container = main.player_hand if owner_id == 0 else main._opponent_fan
	if not hand_container or hand_container.cards.is_empty():
		return

	var target: Node = await TriggerSystem._targeted_executor._select_annul_target_cost_filter(
		"Elige una carta para anular", 999, owner_id)
	if not target or not is_instance_valid(target):
		return
	if TriggerSystem._targeted_executor._target_text_denies(target, ["no puede ser anulad"]):
		main._update_debug("%s no puede ser anulada" % str(target.get("card_name")))
		return

	# Click directo en la mano. Filtrado por owner_id (como gran kraken,
	# PreventionAbilityHandler_EP.gd).
	var hand_filter := func(c: Node) -> bool:
		return c.get("current_zone") == Constants.Zone.MANO and c.get("owner_id") == owner_id
	var hand_node: Node = await main._card_interaction.await_target(
		"Baraja una carta de tu mano para pagar la habilidad", hand_filter, true, owner_id)
	if not hand_node or not is_instance_valid(hand_node):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	var data: Dictionary = hand_node.card_data.duplicate()
	hand_container.remove_card(hand_node, true)
	CardManager.get_deck(owner_id).append(data)
	CardManager.shuffle_deck(owner_id)
	AnimationQueue.queue_shuffle(owner_id, "Barajar mazo (Tenshi Z)")

	await ActionModule.destroy([target], source_card, true, true)


func _activate_tesoro_cesares_name_tax(source_card: Node, ability: Dictionary) -> void:
	"""Tesoro de los Césares: "Una vez por turno, puedes Barajar una carta de tu mano para nombrar una
	carta. Esa carta cuesta un Oro adicional el próximo turno". Costo: barajar (no descartar) 1
	carta de la mano. Efecto: nombrar cualquier carta (CardNameSearchDialog, como Alicia en
	Wonderland) con +1 Oro desde el turno siguiente
	(PaymentManager.add_named_surcharge_next_turn(), aparte de oros_mas_modifiers, que se vacía en
	cada turno)."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	var hand_container_tesoro = _inspector._main.player_hand if owner_id == 0 else _inspector._main._opponent_fan
	if not hand_container_tesoro or hand_container_tesoro.cards.is_empty() or not _inspector._main._card_interaction:
		return  # sin mano no hay costo que pagar

	# Click directo en la mano en vez del modal de lista viejo.
	var hand_filter := func(c: Node) -> bool: return c.get("current_zone") == Constants.Zone.MANO
	var to_shuffle_node: Node = await _inspector._main._card_interaction.await_target(
		"Baraja 1 carta de tu mano en tu mazo", hand_filter, true, owner_id)
	if not to_shuffle_node or not is_instance_valid(to_shuffle_node):
		return  # canceló — no paga el costo, no nombra nada

	# remove_card(card, true) de la mano (no remove_child() + queue_free() a mano): desconecta las
	# señales de la carta antes de liberarla, si no un hover posterior falla con "previously freed".
	var shuffled_data: Dictionary = to_shuffle_node.card_data
	hand_container_tesoro.remove_card(to_shuffle_node, true)
	CardManager.get_deck(owner_id).append(shuffled_data)
	ActionModule.shuffle_deck(owner_id)

	var picked_card: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
		"Nombra una carta: cuesta 1 Oro adicional el próximo turno", owner_id
	)

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	if picked_card.is_empty():
		return
	var picked_name: String = str(picked_card.get("nombre", ""))
	if picked_name.is_empty():
		return
	if await TriggerSystem.open_response_window(source_card, "Tesoro de los Césares", owner_id):
		return

	PaymentManager.add_named_surcharge_next_turn(picked_name, GameManager.turn_serial + 1)
	_inspector._main._update_debug("'%s' cuesta 1 Oro adicional el próximo turno" % picked_name)


func _activate_voragh_devorador_search_to_cemetery(source_card: Node, ability: Dictionary) -> void:
	"""'En tu Vigilia, una vez por turno, busca en un Castillo dos cartas y ponlas en el Cementerio'
	(voragh el devorador) — 'un Castillo' sin posesivo = a elección."""
	if not is_instance_valid(source_card):
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0
	if not TriggerSystem._targeted_executor:
		return

	if await TriggerSystem.open_response_window(source_card, "voragh el devorador", owner_id):
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	# Elige siempre quien activa, en el selector con los dos Castillos (también al buscar en el
	# Castillo rival).
	await ActionModule.search_either_owner(owner_id, [Constants.Zone.CASTILLO], {}, 2, true, source_card,
		Constants.Zone.CEMENTERIO)


func _activate_voragh_devorador_destroy_own_for_gold(source_card: Node, ability: Dictionary) -> void:
	"""'Una vez por turno, puedes Destruir una de tus cartas para generar un Oro para jugar Aliados'
	(voragh el devorador) — costo de Destruir una carta PROPIA (elegida, cualquier zona de
	campo/Oro), efecto: Oro Virtual restringido a Aliados (mismo mecanismo que Padre de la Patria)."""
	if not is_instance_valid(source_card) or not _inspector._main._gold_manager or not _inspector._main._card_interaction:
		return
	var owner_id: int = source_card.owner_id if source_card.get("owner_id") != null else 0

	var main := _inspector._main
	var filter := func(c: Node) -> bool:
		if c.get("owner_id") != owner_id and c.get("controller_id") != owner_id:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
			Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]
	var target: Node = await main._card_interaction.await_target("Elige una de tus cartas para Destruir", filter, true, owner_id)
	if not target or not is_instance_valid(target):
		return

	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await ActionModule.destroy([target], source_card, true, true)
	if await TriggerSystem.open_response_window(source_card, "voragh el devorador", owner_id):
		return
	var predicate := func(card_type: int, _card_race: String, _card_cost: int) -> bool:
		return card_type == Constants.CardType.ALIADO
	# generar_oro_virtual_restringido ya es por jugador (ver arquitectura.md §33).
	main._gold_manager.generar_oro_virtual_restringido(1, predicate, "Aliados", owner_id)
