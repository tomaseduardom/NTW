extends RefCounted
## ShuffleDrawPatterns — una de las mitades de LookAndPlayResolver.gd (fachada; ahí está la lista
## completa). Combos de Barajar/Robar sobre recursos propios: Caín (x2), vision heroica, el
## caleuche, manuel rodriguez (ataca solo), amazona desafiante, Abrazo de Maipú, Príncipe Orión,
## blanca nieves, kaitai, rafael, Escarapela Nacional, Tótem del Dragón Ancestral.

const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")

var _main: Node


func setup(main: Node) -> void:
	_main = main


func try_execute_shuffle_or_draw_choice_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Baraja hasta una carta de coste 2 o menos o Roba dos cartas' (Caín,
	myl_id cbg001, edición Angeles y Demonios: Vigilantes). Elección A/B
	entre dos efectos que no comparten nada — ActionPipeline solo resuelve
	un tipo de acción por habilidad. 'Baraja... de coste N o menos' sin
	zona ni posesivo = EN JUEGO, cualquier lado
	([[project_no_zone_means_in_play]]), 'hasta una' = opcional (ESC =
	no barajar ninguna, pero la elección A/B en sí ya se hizo)."""
	var lower := ability_text.to_lower()
	if not ("baraja hasta una carta de coste" in lower and "o roba dos cartas" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true

	var choose_shuffle: bool = await SelectionManager.await_two_choice(
		main, "Caín", "Barajar hasta una carta en juego (coste 2 o menos)", "Robar dos cartas", controller_id)

	if not choose_shuffle:
		if await TriggerSystem.open_response_window(card, "Caín", controller_id):
			return true
		await ActionModule.draw(controller_id, 2, "etb_trigger", true)
		return true

	if not main._card_interaction:
		return true
	var filter := func(c: Node) -> bool:
		if c.get("card_cost") == null or ContinuousEffectManager.get_modified_cost(c) > 2:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	var target: Node = await main._card_interaction.await_target(
		"Baraja hasta una carta en juego (coste 2 o menos) — N para no barajar ninguna", filter, true, controller_id)
	# Sin ventana genérica aquí: return_to_deck() ya consulta Prevención adentro.
	if target and is_instance_valid(target):
		var owner: int = target.owner_id if target.get("owner_id") != null else controller_id
		await ActionModule.return_to_deck(target, owner, true)
		CardManager.shuffle_deck(owner)
		AnimationQueue.queue_shuffle(owner, "Barajar mazo (Caín)")
	return true


func try_execute_cain_damage_shuffle_search_pattern(isolated_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando haga daño de combate, puedes Barajalo para buscar dos
	Aliados de coste 2 o menos en tu Castillo. Juega uno sin pagar su
	coste y pon el otro en tu mano.' (Caín). 'Puedes X (barajar a Caín
	mismo) para Y (buscar)' es atómico (project_puedes_x_para_y_atomic):
	no se ofrece la barajada si no hay al menos un Aliado de coste 2 o
	menos en el Castillo para encontrar. Si se encuentran 2, el jugador
	elige cuál de las dos se juega gratis (la otra va a la mano); si solo
	se encuentra 1, elige entre jugarla gratis o mandarla a la mano."""
	var lower := isolated_text.to_lower()
	if not ("puedes barajalo" in lower and "buscar dos aliados de coste" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not is_instance_valid(card):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var matching: Array = []
	for d in deck:
		if d.get("tipo", -1) == Constants.CardType.ALIADO and int(d.get("coste", 99)) <= 2:
			matching.append(d)
	if matching.is_empty():
		return true  # nada que buscar — la barajada ni se ofrece (atómico)

	var confirm: bool = await SelectionManager.await_two_choice(
		main, "Caín", "Barajarlo para buscar hasta 2 Aliados de coste 2 o menos", "No hacer nada", controller_id)
	if not confirm:
		return true

	var pick_amount: int = mini(2, matching.size())
	# Click directo (open_reveal_picker) en vez del modal de lista viejo.
	var found: Array = []
	if main._zone_viewer:
		found = await main._zone_viewer.open_reveal_picker(
			"Elige hasta 2 Aliados de coste 2 o menos", matching, controller_id, Callable(), pick_amount, false)
	if found.is_empty():
		return true

	# Barajar a Caín mismo AHORA (el costo ya se pagó al elegir buscar) —
	# vuelve a su Castillo y se mezcla.
	await ActionModule.return_to_deck(card, controller_id, false, card)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Caín)")

	for picked_data in found:
		deck.erase(picked_data)

	var to_play_data: Dictionary = {}
	if found.size() == 2:
		# Click directo (open_reveal_picker) en vez del modal de lista viejo.
		if main._zone_viewer:
			var picked_list: Array = await main._zone_viewer.open_reveal_picker(
				"Elige cuál de las dos jugar sin pagar su coste (la otra va a tu mano)", found, controller_id, Callable(), 1, false)
			if not picked_list.is_empty():
				to_play_data = picked_list[0]
	else:
		var play_it: bool = await SelectionManager.await_two_choice(
			main, "Caín", "Jugarla sin pagar su coste", "Ponerla en tu mano", controller_id)
		if play_it:
			to_play_data = found[0]

	if await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
		return true
	var hand_container = main.player_hand if controller_id == 0 else main._opponent_fan
	for picked_data in found:
		if picked_data == to_play_data:
			await main._gold_manager.play_card_for_free(picked_data, controller_id)
		else:
			var hand_node = main._create_card(picked_data, false)
			hand_container.add_card(hand_node)
			main._connect_card_signals(hand_node)

	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_shuffle_cost_max_three_pattern(ability_text: String, controller_id: int) -> bool:
	"""'Baraja una carta de coste 3 o menos o Anula un Talismán oponente' (vision heroica). Hoy la
	resuelve antes EffectInterpreter (elección "A o B" con Anular sobre la Pila, que solo se ofrece si
	hay un Talismán rival que Anular); esto queda de respaldo: solo Baraja."""
	var lower := ability_text.to_lower()
	if not ("baraja una carta de coste 3 o menos o anula un talismán oponente" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	# Si hay un Talismán oponente en la pila, se puede elegir Anularlo.
	var talisman_obj: Dictionary = StackAnnulScript.find_target(controller_id, true, false, func(obj: Dictionary) -> bool:
		return StackAnnulScript.type_of(obj) == Constants.CardType.TALISMAN)
	if not talisman_obj.is_empty():
		var annul_it: bool = await SelectionManager.await_two_choice(main, "Visión Heroica",
			"Anular %s" % str(StackAnnulScript.data_of(talisman_obj).get("nombre", "el Talismán")),
			"Barajar una carta de coste 3 o menos", controller_id)
		if annul_it:
			StackAnnulScript.apply(talisman_obj, null)
			return true
	var filter := func(c: Node) -> bool:
		# current_zone en vez de get_parent (ver §10.5)
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, 3)
	var target: Node = await main._card_interaction.await_target("Elige una carta de coste 3 o menos para barajar", filter, true, controller_id)
	if target and is_instance_valid(target):
		var target_owner: int = target.controller_id if target.get("controller_id") != null else controller_id
		if await ActionModule.return_to_deck(target, target_owner, true):
			CardManager.shuffle_deck(target_owner)
			AnimationQueue.queue_shuffle(target_owner, "Barajar mazo (vision heroica)")
	return true


func try_execute_shuffle_cost_max_two_draw_two_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Elige un efecto: - En respuesta a que se juegue una carta sin pagar su coste... - Baraja una
	carta de coste 2 o menos y Roba dos cartas' (el caleuche) — SOLO se implementa la segunda rama
	(la primera depende de la ventana de respuesta reactiva, que no existe); no se ofrece elección,
	se resuelve siempre como la rama B."""
	var lower := ability_text.to_lower()
	if not ("baraja una carta de coste 2 o menos y roba dos cartas" in lower and "en respuesta a que se juegue una carta sin pagar su coste" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	# Rama A (StackAnnul): en la pila, una carta oponente jugada sin pagar su coste o que no puede ser
	# Anulada: entra sin habilidad por el turno; si es Talismán, se resuelve sin efecto.
	var free_obj: Dictionary = StackAnnulScript.find_target(controller_id, true, false, func(obj: Dictionary) -> bool:
		var node = StackAnnulScript.card_of(obj)
		var free: bool = node != null and is_instance_valid(node) and node.get_meta("played_free", false)
		return free or StackAnnulScript.protected_from_annul(obj))
	if not free_obj.is_empty():
		var obj_name: String = str(StackAnnulScript.data_of(free_obj).get("nombre", "esa carta"))
		var use_a: bool = await SelectionManager.await_two_choice(main, "El Caleuche",
			"%s entra sin habilidad por el turno" % obj_name, "Barajar una carta de coste 2 o menos y Robar dos",
			controller_id)
		if use_a:
			var node_a = StackAnnulScript.card_of(free_obj)
			if StackAnnulScript.type_of(free_obj) == Constants.CardType.TALISMAN:
				free_obj["was_cancelled"] = true  # se resuelve sin efecto
				free_obj["cancel_reason"] = "el_caleuche"
			elif node_a != null and is_instance_valid(node_a):
				await KeywordManager.silence_card(node_a, card, "turn")
			main._update_debug("El Caleuche: %s queda sin habilidad" % obj_name)
			return true
	var filter := func(c: Node) -> bool:
		# current_zone en vez de get_parent (ver §10.5)
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, 2)
	var target: Node = await main._card_interaction.await_target("Elige una carta de coste 2 o menos para barajar", filter, true, controller_id)
	if await TriggerSystem.open_response_window(card, "el caleuche", controller_id):
		return true
	if target and is_instance_valid(target):
		var target_owner: int = target.controller_id if target.get("controller_id") != null else controller_id
		if await ActionModule.return_to_deck(target, target_owner, true):
			CardManager.shuffle_deck(target_owner)
			AnimationQueue.queue_shuffle(target_owner, "Barajar mazo (el caleuche)")
	await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	return true


func try_execute_attacks_alone_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""manuel rodriguez: "Cuando ataque solo, Roba una carta..." (único atacante declarado en el
	combate). "...y hasta tu próximo turno a tu oponente le cuesta un Oro adicional afectar a tus
	Aliados": ProtectionRules.grant_ally_affect_tax (se cobra al ceder el rival la prioridad) hasta el
	turno del rival inclusive."""
	var lower := ability_text.to_lower()
	if not ("cuando ataque solo" in lower and "roba una carta" in lower):
		return false
	if GameManager.attackers.size() != 1:
		return true  # condición 'solo' no cumplida
	if await TriggerSystem.open_response_window(card, "manuel rodriguez", controller_id):
		return true
	await ActionModule.draw(controller_id, 1, "on_attack_trigger", true)
	if "le cuesta un oro adicional afectar a tus aliados" in lower:
		load("res://scripts/core/effects/mechanics/ProtectionRules.gd").grant_ally_affect_tax(controller_id, GameManager.turn_serial + 1)
	return true


func try_execute_shuffle_one_in_play_and_four_cemetery_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""amazona desafiante: "Cuando entra en juego o en tu Fase Final, Baraja hasta una carta de coste
	2 o menos y hasta cuatro cartas de los Cementerios". Entrada y cada Fase Final ("en tu fase
	final" es on_turn_end, TriggerSystem.resolve_turn_end_triggers())."""
	var lower := ability_text.to_lower()
	if not ("baraja hasta una carta de coste 2 o menos y hasta cuatro cartas de los cementerios" in lower):
		return false
	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	if await TriggerSystem.open_response_window(card, "amazona desafiante", controller_id):
		return true

	# Parte 1: hasta una carta EN JUEGO de coste ≤2 (sin zona = en juego).
	var in_play_candidates: Array = []
	for field in [main.player_field, main.opponent_field, main.player_linea_ataque,
			main.opponent_linea_ataque, main.player_linea_apoyo, main.opponent_linea_apoyo,
			main.player_gold, main.opponent_gold]:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and ContinuousEffectManager.cost_at_most(c, 2):
				in_play_candidates.append(c)
	# Click directo en vez de los modales de lista viejos.
	if not in_play_candidates.is_empty() and main._card_interaction:
		var in_play_filter := func(c: Node) -> bool: return c in in_play_candidates
		var picked1_node: Node = await main._card_interaction.await_target(
			"Elige hasta una carta de coste 2 o menos para Barajar (N para omitir)", in_play_filter, true, controller_id)
		if picked1_node and is_instance_valid(picked1_node):
			var owner_id: int = picked1_node.owner_id if picked1_node.get("owner_id") != null else 0
			var data: Dictionary = picked1_node.card_data.duplicate()
			data["esta_oculta"] = true
			var parent = picked1_node.get_parent()
			if parent:
				parent.remove_child(picked1_node)
			picked1_node.queue_free()
			CardManager.get_deck(owner_id).append(data)
			CardManager.shuffle_deck(owner_id)
			AnimationQueue.queue_shuffle(owner_id, "Barajar mazo (amazona desafiante)")

	# Parte 2: hasta cuatro cartas de los Cementerios (barajar, no desterrar
	# — a diferencia de Ofrendas al Dragón, esta carta no ofrece la opción
	# de Destierro).
	if main._zone_viewer:
		var no_filter := func(_c: Node) -> bool: return true
		var picked2: Array = await main._zone_viewer.open_cemetery_target_picker(
			"Elige hasta cuatro cartas de los Cementerios para Barajar", no_filter, 4, "cemetery", false, false, controller_id)
		for entry in picked2:
			var idx: int = CardManager.get_cemetery(entry.owner_id).find(entry.data)
			if idx >= 0:
				CardManager.remove_from_cemetery(entry.owner_id, idx)
				var data2: Dictionary = entry.data.duplicate()
				data2["esta_oculta"] = true
				CardManager.get_deck(entry.owner_id).append(data2)
				CardManager.shuffle_deck(entry.owner_id)
				AnimationQueue.queue_shuffle(entry.owner_id, "Barajar mazo (amazona desafiante)")
	return true


func try_execute_shuffle_any_cemetery_or_exile_into_castillo_then_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Baraja cualquier cantidad de cartas de tu Cementerio y Destierro en tu Castillo y Roba tres
	cartas' (Abrazo de Maipú) — 'tu' restringe el pool al propio Cementerio+Destierro (a diferencia
	de 'los Cementerios'), cada carta vuelve a SU Castillo (siempre el mismo, propio, aquí)."""
	var lower := ability_text.to_lower()
	if not ("baraja cualquier cantidad de cartas de tu cementerio y destierro en tu castillo" in lower):
		return false
	if await TriggerSystem.open_response_window(card, "Abrazo de Maipú", controller_id):
		return true

	# Click directo combinando Cementerio Y Destierro propios en un solo popup
	# (zone_type="cemetery_and_exile", nuevo en ZoneViewerModule.open_cemetery_target_picker), con
	# botón "Seleccionar todo" — el texto real es 'cualquier cantidad', sin tope, y clickear una por
	# una sería tedioso con muchas cartas acumuladas.
	var main := _main.get_node_or_null("/root/Main")
	if main and main._zone_viewer:
		var own_only := func(c: Node) -> bool: return c.owner_id == controller_id
		var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"Baraja cualquier cantidad de cartas de tu Cementerio y Destierro en tu Castillo",
			own_only, -1, "cemetery_and_exile", false, true, controller_id)
		for entry in picked:
			if entry.zone_type == "cemetery":
				var idx: int = CardManager.get_cemetery(controller_id).find(entry.data)
				if idx >= 0:
					CardManager.remove_from_cemetery(controller_id, idx)
			else:
				CardManager.get_exile(controller_id).erase(entry.data)
			CardManager.get_deck(controller_id).append(entry.data)
		if not picked.is_empty():
			CardManager.shuffle_deck(controller_id)
			AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Abrazo de Maipú)")

	await ActionModule.draw(controller_id, 3, "etb_trigger", true)
	return true


func try_execute_shuffle_banish_four_cemeteries_pattern(ability_text: String, controller_id: int) -> bool:
	"""'Baraja y/o Destierra hasta cuatro cartas de los Cementerios. Si Barajaste y/o Desterraste
	cuatro cartas de distinto tipo, genera un Oro por el turno' (Ofrendas al Dragón)."""
	var lower := ability_text.to_lower()
	if not ("baraja y/o destierra hasta cuatro cartas de los cementerios" in lower):
		return false
	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var moved: Array = await main._gold_manager._resolve_armeria_barajar_desterrar(4, "Ofrendas al Dragón", controller_id)
	if "cuatro cartas de distinto tipo, genera un oro por el turno" in lower:
		var types := {}
		for d in moved:
			types[int(d.get("tipo", -1))] = true
		if moved.size() >= 4 and types.size() >= 4:
			main._gold_manager.generar_oros_virtuales(1, controller_id)
			main._update_debug("Ofrendas al Dragón: cuatro tipos distintos, genera un Oro por el turno")
	return true


func try_execute_shuffle_banish_cemeteries_then_destroy_or_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, Baraja y/o Destierra hasta tres cartas de los Cementerios y elige entre
	Destruir una carta de coste 2 o menos o Robar dos cartas' (Tótem del Dragón Ancestral)."""
	var lower := ability_text.to_lower()
	if not ("baraja y/o destierra hasta tres cartas de los cementerios y elige entre destruir una carta de coste 2 o menos o robar dos cartas" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager or not main._card_interaction:
		return true
	await main._gold_manager._resolve_armeria_barajar_desterrar(3, str(card.get("card_name")), controller_id)

	var choose_destroy: bool = await SelectionManager.await_two_choice(
		main, str(card.get("card_name")), "Destruir una carta de coste 2 o menos", "Robar dos cartas", controller_id)
	if choose_destroy:
		var target: Node = await TriggerSystem._targeted_executor._select_destroy_target_cost_filter(
			"Elige una carta de coste 2 o menos para destruir", 2, controller_id)
		if target and is_instance_valid(target):
			await ActionModule.destroy([target], card, true, true)
	else:
		if await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			return true
		await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	return true


func try_execute_draw_or_raise_cemetery_ally_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Cuando entra en juego, Roba una carta o sube un Aliado de tu Cementerio a tu mano' (Príncipe
	Orión) — elección A/B."""
	var lower := ability_text.to_lower()
	if not ("roba una carta o sube un aliado de tu cementerio a tu mano" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var choose_draw: bool = await SelectionManager.await_two_choice(
		main, "Príncipe Orión", "Robar una carta", "Subir un Aliado de tu Cementerio a tu mano", controller_id)
	if await TriggerSystem.open_response_window(card, "Príncipe Orión", controller_id):
		return true
	if choose_draw:
		await ActionModule.draw(controller_id, 1, "etb_trigger", true)
	elif main._zone_viewer:
		# Click directo en el propio Cementerio en vez del modal de lista viejo.
		var eligible_filter := func(c: Node) -> bool:
			return c.owner_id == controller_id and c.get("card_type") == Constants.CardType.ALIADO
		var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"Sube un Aliado de tu Cementerio a tu mano", eligible_filter, 1, "cemetery", false, false, controller_id)
		if picked.is_empty():
			return true
		var picked_data: Dictionary = picked[0].data
		if not CardManager.take_from_cemetery(controller_id, picked_data):
			return true
		var card_node = main._create_card(picked_data, false)
		var hand_container_orion = main.player_hand if controller_id == 0 else main._opponent_fan
		hand_container_orion.add_card(card_node)
		main._connect_card_signals(card_node)
	return true


func try_execute_shuffle_up_to_one_ally_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, Baraja hasta un Aliado' (blanca nieves) — objetivo opcional (0 o 1),
	cualquier Aliado en juego."""
	var lower := ability_text.to_lower()
	if not ("cuando entra en juego, baraja hasta un aliado" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var target: Node = await main._card_interaction.await_target(
		"Elige un Aliado para barajar (opcional)", func(c: Node) -> bool:
			if c.get("card_type") != Constants.CardType.ALIADO:
				return false
			# current_zone en vez de get_parent (ver §10.5)
			return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO], true, controller_id)
	# Sin ventana genérica aquí: return_to_deck ya consulta Prevención adentro por su cuenta.
	if target and is_instance_valid(target):
		var target_owner: int = target.controller_id if target.get("controller_id") != null else controller_id
		if await ActionModule.return_to_deck(target, target_owner, true, card):
			CardManager.shuffle_deck(target_owner)
			AnimationQueue.queue_shuffle(target_owner, "Barajar mazo (blanca nieves)")
	return true


func try_execute_draw_then_discard_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Roba N carta(s) y Descarta M carta(s)' (p.ej. kaitai: 'Cuando entra en juego, Roba tres cartas
	y Descarta dos cartas') — el genérico extract_action solo reconoce la PRIMERA acción de una
	oración compuesta, así que sin esto el Descarte se perdía siempre."""
	var lower := ability_text.to_lower()
	var rx := RegEx.new()
	rx.compile("roba (\\w+) cartas? y descarta (\\w+) cartas?")
	var m := rx.search(lower)
	if not m:
		return false

	var draw_amount: int = UniversalCardParser._parse_amount(m.get_string(1))
	var discard_amount: int = UniversalCardParser._parse_amount(m.get_string(2))
	if await TriggerSystem.open_response_window(card, str(card.get("card_name")) if card else "kaitai", controller_id):
		return true
	if draw_amount > 0:
		await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)
	if discard_amount > 0:
		var main := _main.get_node_or_null("/root/Main")
		var hand_container_kaitai = (main.player_hand if controller_id == 0 else main._opponent_fan) if main else null
		if main and hand_container_kaitai:
			var hand_cards: Array = hand_container_kaitai.cards.duplicate()
			discard_amount = mini(discard_amount, hand_cards.size())
			if discard_amount > 0:
				var to_discard: Array = await _main._targeted_executor._select_hand_cards_for_discard(hand_cards, discard_amount, controller_id)
				if not to_discard.is_empty():
					await ActionModule.discard(controller_id, to_discard, "etb_trigger", true)
	return true


func try_execute_shuffle_non_gold_or_draw_two_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, Baraja hasta una carta que no sea Oro o Roba dos cartas' (rafael) —
	elección A/B; 'hasta una' = el Barajar es opcional (cancelar el picker = 0 elegidas)."""
	var lower := ability_text.to_lower()
	if not ("baraja hasta una carta que no sea oro o roba dos cartas" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var choose_shuffle: bool = await SelectionManager.await_two_choice(
		main, "rafael", "Barajar hasta una carta que no sea Oro", "Robar dos cartas", controller_id)

	if choose_shuffle:
		var filter := func(c: Node) -> bool:
			if c.get("card_type") == Constants.CardType.ORO:
				return false
			# current_zone en vez de get_parent (ver §10.5)
			return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
		var target: Node = await main._card_interaction.await_target("Elige una carta que no sea Oro para barajar (opcional)", filter, true, controller_id)
		# Sin ventana genérica aquí: return_to_deck ya consulta Prevención adentro por su cuenta.
		if target and is_instance_valid(target):
			var target_owner: int = target.controller_id if target.get("controller_id") != null else controller_id
			if await ActionModule.return_to_deck(target, target_owner, true, card):
				CardManager.shuffle_deck(target_owner)
				AnimationQueue.queue_shuffle(target_owner, "Barajar mazo (rafael)")
	elif not await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	return true


func try_execute_draw_or_search_ally_or_gold_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Roba dos cartas o busca un Aliado u Oro en tu Castillo y ponlo en tu mano' (p.ej. Escarapela
	Nacional) — elección A/B."""
	var lower := ability_text.to_lower()
	if not ("roba dos cartas o busca un aliado u oro en tu castillo" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var choose_draw: bool = await SelectionManager.await_two_choice(
		main, "Escarapela Nacional", "Robar dos cartas", "Buscar un Aliado u Oro en tu Castillo", controller_id)
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	if choose_draw:
		await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	else:
		await ActionModule.search(controller_id, Constants.Zone.CASTILLO,
			{"type": [Constants.CardType.ALIADO, Constants.CardType.ORO]}, 1, true, false, false, card, Constants.Zone.MANO)
	return true


