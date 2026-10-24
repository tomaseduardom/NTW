extends RefCounted
## LookRevealPatternsB — mitad B (alfabética) de LookRevealPatterns.gd (fachada; ahí está la lista
## completa y la mitad A). Desde try_execute_look_two_hand_convert_gold_pattern hasta
## try_execute_reveal_until_weapon_or_totem_and_ally_pattern: 10 patrones aquí y 6 en A, que tiene
## los try_execute_look_play_* más largos.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
var _main: Node


const RevealWindowScript = preload("res://scripts/ui/zones/RevealWindow.gd")


func setup(main: Node) -> void:
	_main = main


func try_execute_look_two_hand_convert_gold_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Detecta 'Cuando entra en juego, muestra dos cartas del tope de tu
	Castillo y ponlas en tu mano. Si mostraste un Aliado o Arma de esta
	forma, convierte un Oro en Oro sin habilidad' (Mariano Osorio,
	custom_mig_14, edición 'Ángeles y Demonios: Vigilantes - Mazo
	Guerreros' — carta custom, sin myl_id real, no está en la API externa;
	el cache local es la única fuente). Sin 'puedes': ambas partes son
	mandatorias — las 2 cartas se muestran SIEMPRE, y si entre ellas hay
	un Aliado o Arma, el Convertir también es obligatorio. 'Convierte un
	Oro' sin 'tu'/'oponente' = EN JUEGO, cualquiera de los dos lados (ver
	[[project_no_zone_means_in_play]]) — reusa TargetedEffectExecutor.
	_execute_targeted_convert() con max_cost=-1 (ya genérico, ver Capitán
	O'Brien) para que solo un Oro sea objetivo válido, nunca una carta de
	coste normal.
	Returns: true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("muestra dos cartas del tope de tu castillo" in lower and "convierte un oro en oro sin habilidad" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true

	var deck: Array = main.player_deck if controller_id == 0 else main.opponent_deck
	var shown_types: Array = []
	var shown_count: int = mini(2, deck.size())
	for i in range(shown_count):
		var card_data: Dictionary = deck.pop_front()
		shown_types.append(int(card_data.get("tipo", -1)))
		if controller_id == 0:
			var card_node: Node = main._create_card(card_data, false)
			main.player_hand.add_card(card_node)
			main._connect_card_signals(card_node)
		else:
			var opp_node: Node = main._create_card(card_data, true)
			if main._opponent_fan:
				main._opponent_fan.add_card(opp_node)
				# Conectar las señales de la carta también en la mano rival (como ZoneManager.draw_card()).
				main._connect_card_signals(opp_node)
	if shown_count > 0 and main._zone_manager:
		main._zone_manager._update_castillo_counts()

	var showed_ally_or_weapon: bool = Constants.CardType.ALIADO in shown_types or Constants.CardType.ARMA in shown_types
	if showed_ally_or_weapon and controller_id == 0:
		await _main._targeted_executor._execute_targeted_convert(card, {"params": {"max_cost": -1}})

	return true


func try_execute_name_reveal_until_match_then_gold_to_pagado_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""contra el caos: "Nombra un Aliado o Tótem. Muestra cartas de tu Castillo hasta mostrar una
	carta con ese nombre, ponla en tu mano y Baraja el resto. Pon un Oro de tu mano en tu Oro
	Pagado. Cuando este Talismán se resuelva, puedes pagar un Oro para repetir su efecto" (una vez:
	la repetición no es otra resolución del Talismán)."""
	var lower := ability_text.to_lower()
	if not ("nombra un aliado o tótem" in lower and "pon un oro de tu mano en tu oro pagado" in lower):
		return false
	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var title: String = str(card.card_name) if card else "contra el caos"
	var picked: Dictionary = await _main._card_name_search.open_and_wait("Nombra un Aliado o Tótem", controller_id)
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return true
	await _contra_el_caos_once(main, controller_id, str(picked.get("nombre", "")))
	if "puedes pagar un oro para repetir su efecto" in lower and main._gold_manager.puede_pagar(1, -1, "", -1, controller_id):
		var again: bool = PlayerSideScript.is_bot(controller_id) or await SelectionManager.await_two_choice(main, title,
			"Pagar un Oro para repetir su efecto", "No repetir", controller_id)
		if again and await PlayerSideScript.pay(main, controller_id, 1, card):
			picked = await _main._card_name_search.open_and_wait("Nombra un Aliado o Tótem", controller_id)
			await _contra_el_caos_once(main, controller_id, str(picked.get("nombre", "")))
	return true


func _contra_el_caos_once(main: Node, controller_id: int, picked_name: String) -> void:
	var hand_container_caos = main.player_hand if controller_id == 0 else main._opponent_fan
	if not picked_name.is_empty():
		var deck: Array = CardManager.get_deck(controller_id)
		var revealed: Array = []
		var found: Dictionary = {}
		while not deck.is_empty() and found.is_empty():
			var top: Dictionary = deck.pop_front()
			revealed.append(top)
			if str(top.get("nombre", "")).to_lower() == picked_name.to_lower():
				found = top
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, "contra el caos")
		if not found.is_empty():
			await RevealWindowScript.show_cards(main, controller_id, [found], "contra el caos")
			_remove_data_from_array(revealed, found)
			var card_node = main._create_card(found, false)
			card_node.owner_id = controller_id
			hand_container_caos.add_card(card_node)
			main._connect_card_signals(card_node)
		for c in revealed:
			deck.append(c)
		CardManager.shuffle_deck(controller_id)
		if main.get("_zone_manager"):
			main._zone_manager._update_castillo_counts()

	if hand_container_caos and main._card_interaction:
		# Click directo en la mano en vez del modal viejo.
		var oro_filter := func(c: Node) -> bool:
			return c.get("current_zone") == Constants.Zone.MANO and c.get("card_type") == Constants.CardType.ORO
		var gold_node: Node = await main._card_interaction.await_target(
			"Pon un Oro de tu mano en tu Oro Pagado", oro_filter, true, controller_id)
		if gold_node and is_instance_valid(gold_node):
			var gold_data: Dictionary = gold_node.card_data.duplicate()
			hand_container_caos.remove_card(gold_node, true)
			await main._gold_manager.put_gold_directly_in_pagado(controller_id, gold_data)


func try_execute_peek_hand_banish_search_castillo_cemetery_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Mira la mano de tu oponente y Destierra una carta de coste 2 o menos de ahí. Busca una carta
	en un Castillo y hasta dos cartas de un Cementerio y Destiérralas. Si Destierras dos o menos
	cartas de esta forma, Roba dos cartas' (Duelo de Dragones) — no cubre 'al comienzo de cualquier
	Fase' (solo jugable en las ventanas normales de Talismán)."""
	var lower := ability_text.to_lower()
	if not ("mira la mano de tu oponente y destierra una carta de coste 2 o menos de ahí" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var opponent_id: int = 1 - controller_id
	var opponent_hand_container = main.player_hand if opponent_id == 0 else main._opponent_fan
	if EffectController.fision_hides_zones_of(opponent_id, controller_id, Constants.Zone.MANO):  # Fisión Nuclear
		opponent_hand_container = null
	if await EffectController.offer_colapso_global(controller_id):  # Colapso Global
		opponent_hand_container = null
	if not opponent_hand_container:
		return true
	var banished_count := 0

	var opponent_hand: Array = opponent_hand_container.get_cards()
	var candidates: Array = []
	for c in opponent_hand:
		if is_instance_valid(c):
			candidates.append(c)
	# Click directo sobre la mano rival (Nodos ya visibles) en vez del modal de lista viejo.
	if not candidates.is_empty() and main._card_interaction:
		var cost_filter := func(c: Node) -> bool:
			return c in candidates and ContinuousEffectManager.data_cost_at_most(c.card_data, 2)
		var chosen: Node = await main._card_interaction.await_target(
			"Mira la mano rival: elige una carta de coste 2 o menos para desterrar", cost_filter, true, controller_id)
		if chosen and is_instance_valid(chosen):
			var chosen_data: Dictionary = chosen.card_data.duplicate()
			opponent_hand_container.remove_card(chosen, true)
			CardManager.add_to_exile(opponent_id, chosen_data)
			banished_count += 1

	var result1: Dictionary = await ActionModule.search_either_owner(controller_id, [Constants.Zone.CASTILLO], {}, 1, true, card,
		Constants.Zone.DESTIERRO)
	banished_count += result1.get("selected", []).size()

	var result2: Dictionary = await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, 2, true, card,
		Constants.Zone.DESTIERRO, false, true)
	banished_count += result2.get("selected", []).size()

	if banished_count <= 2:
		await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	return true


func try_execute_reveal_gold_to_pagado_weapon_or_totem_to_hand_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Activar Tenshi Z: "Muestra cartas del tope de tu Castillo hasta mostrar un Oro y un Arma o
	Tótem. Pon el Oro en tu Oro Pagado, la otra carta en tu mano y Baraja el resto". Estrella de
	Kirin comparte la frase ("...y ponlos en tu mano"): el destino del Oro sale del texto: "ponlos
	en tu mano" → ambos a la mano; "pon el Oro en tu Oro Pagado" → Oro Pagado."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar un oro y un arma o tótem" in lower or "hasta mostrar un oro y un arma o totem" in lower):
		return false
	var gold_to_hand: bool = "ponlos en tu mano" in lower or "ponlas en tu mano" in lower
	var gold_to_pagado: bool = "pon el oro en tu oro pagado" in lower
	if not gold_to_hand and not gold_to_pagado:
		return false  # otra variante de texto: que la resuelva otro patrón

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	# Sin objetivo real que declarar (revelado automático, orden del mazo) —
	# la ventana va antes de empezar a revelar/mover nada.
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Activar Tenshi Z", controller_id):
		return true
	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found_oro: Dictionary = {}
	var found_other: Dictionary = {}
	while not deck.is_empty() and (found_oro.is_empty() or found_other.is_empty()):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var top_type: int = top.get("tipo", -1)
		if found_oro.is_empty() and top_type == Constants.CardType.ORO:
			found_oro = top
		elif found_other.is_empty() and (top_type == Constants.CardType.ARMA or top_type == Constants.CardType.TOTEM):
			found_other = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "Activar Tenshi Z"))
	var shown_tz: Array = [found_oro, found_other].filter(func(d): return not d.is_empty())
	if not shown_tz.is_empty():
		await RevealWindowScript.show_cards(main, controller_id, shown_tz, str(card.card_name) if card else "Activar Tenshi Z",
			"Van a tu mano" if gold_to_hand else "El Oro a tu Oro Pagado · el resto a tu mano")
	var hand_container_tenshiz = main.player_hand if controller_id == 0 else main._opponent_fan
	if not found_oro.is_empty():
		_remove_data_from_array(revealed, found_oro)
		if gold_to_hand and hand_container_tenshiz:
			# Estrella de Kirin: a la mano, como la otra carta.
			var oro_node = main._create_card(found_oro, controller_id != 0)
			hand_container_tenshiz.add_card(oro_node)
			main._connect_card_signals(oro_node)
		else:
			# Activar Tenshi Z: se PONE en juego en el Oro Pagado.
			await main._gold_manager.put_gold_directly_in_pagado(controller_id, found_oro)
	if not found_other.is_empty() and hand_container_tenshiz:
		_remove_data_from_array(revealed, found_other)
		var card_node = main._create_card(found_other, controller_id != 0)
		hand_container_tenshiz.add_card(card_node)
		main._connect_card_signals(card_node)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Activar Tenshi Z)")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_reveal_gold_weapon_totem_split_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar un Oro, un Arma y un Tótem. Pon uno en tu
	mano, dos en tu Cementerio y Baraja el resto' (akari) — el jugador elige CUÁL de los tres
	encontrados va a la mano; los otros dos van al Cementerio."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar un oro, un arma y un tótem" in lower or "hasta mostrar un oro, un arma y un totem" in lower):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "akari", controller_id):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found_oro: Dictionary = {}
	var found_arma: Dictionary = {}
	var found_totem: Dictionary = {}
	while not deck.is_empty() and (found_oro.is_empty() or found_arma.is_empty() or found_totem.is_empty()):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var top_type: int = top.get("tipo", -1)
		if found_oro.is_empty() and top_type == Constants.CardType.ORO:
			found_oro = top
		elif found_arma.is_empty() and top_type == Constants.CardType.ARMA:
			found_arma = top
		elif found_totem.is_empty() and top_type == Constants.CardType.TOTEM:
			found_totem = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "akari"))
	var found: Array = []
	for f in [found_oro, found_arma, found_totem]:
		if not f.is_empty():
			found.append(f)

	var main := _main.get_node_or_null("/root/Main")
	if main and not found.is_empty():
		var to_hand: Dictionary = found[0]
		if found.size() > 1:
			to_hand = found[await RevealWindowScript.pick_one(main, controller_id, found, str(card.card_name) if card else "akari",
				"Toca la carta que va a tu mano · el resto al Cementerio")]
		else:
			await RevealWindowScript.show_cards(main, controller_id, found, str(card.card_name) if card else "akari")
		var hand_container_akari = main.player_hand if controller_id == 0 else main._opponent_fan
		if not to_hand.is_empty() and main.has_method("_create_card") and hand_container_akari:
			var card_node = main._create_card(to_hand, false)
			hand_container_akari.add_card(card_node)
			main._connect_card_signals(card_node)
			_remove_data_from_array(revealed, to_hand)
			_remove_data_from_array(found, to_hand)
		for rest_data in found:
			CardManager.add_to_cemetery(controller_id, rest_data)
			_remove_data_from_array(revealed, rest_data)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (akari)")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_reveal_until_ally_and_gold_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar un Aliado y un Oro, ponlos en tu mano y
	Baraja el resto' (p.ej. Cabeza de Mimir) — revela de a una del tope hasta encontrar AMBOS (un
	Aliado Y un Oro, en cualquier orden), pone los dos en la mano, el resto se baraja de vuelta. Si
	el Castillo se vacía sin encontrar alguno de los dos, se pone en la mano el que sí se haya
	encontrado ('en la medida de lo posible', DAR Sección 8)."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar un aliado y un oro" in lower):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Cabeza de Mimir", controller_id):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found_ally: Dictionary = {}
	var found_oro: Dictionary = {}
	while not deck.is_empty() and (found_ally.is_empty() or found_oro.is_empty()):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		if found_ally.is_empty() and top.get("tipo", -1) == Constants.CardType.ALIADO:
			found_ally = top
		elif found_oro.is_empty() and top.get("tipo", -1) == Constants.CardType.ORO:
			found_oro = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "Cabeza de Mimir"))
	var main := _main.get_node_or_null("/root/Main")
	if main:
		await RevealWindowScript.show_cards(main, controller_id, [found_ally, found_oro].filter(func(d): return not d.is_empty()), str(card.card_name) if card else "Cabeza de Mimir")
	var hand_container_mimir = (main.player_hand if controller_id == 0 else main._opponent_fan) if main else null
	if main and hand_container_mimir and main.has_method("_create_card"):
		for picked_data in [found_ally, found_oro]:
			if picked_data.is_empty():
				continue
			var card_node = main._create_card(picked_data, false)
			hand_container_mimir.add_card(card_node)
			main._connect_card_signals(card_node)
			_remove_data_from_array(revealed, picked_data)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Cabeza de Mimir)")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_reveal_until_ally_and_weapon_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar un Aliado y un Arma, ponlos en tu mano y
	Baraja el resto' (metalmorfo)."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar un aliado y un arma" in lower):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "metalmorfo", controller_id):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found_ally: Dictionary = {}
	var found_weapon: Dictionary = {}
	while not deck.is_empty() and (found_ally.is_empty() or found_weapon.is_empty()):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var top_type: int = top.get("tipo", -1)
		if found_ally.is_empty() and top_type == Constants.CardType.ALIADO:
			found_ally = top
		elif found_weapon.is_empty() and top_type == Constants.CardType.ARMA:
			found_weapon = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "metalmorfo"))
	var main := _main.get_node_or_null("/root/Main")
	if main:
		await RevealWindowScript.show_cards(main, controller_id, [found_ally, found_weapon].filter(func(d): return not d.is_empty()), str(card.card_name) if card else "metalmorfo")
	var hand_container_metalmorfo = (main.player_hand if controller_id == 0 else main._opponent_fan) if main else null
	if main and hand_container_metalmorfo and main.has_method("_create_card"):
		for picked_data in [found_ally, found_weapon]:
			if picked_data.is_empty():
				continue
			var card_node = main._create_card(picked_data, false)
			hand_container_metalmorfo.add_card(card_node)
			main._connect_card_signals(card_node)
			_remove_data_from_array(revealed, picked_data)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (metalmorfo)")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_reveal_until_ally_and_talisman_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Diadema Celestial: "Muestra cartas del tope de tu Castillo hasta mostrar un Aliado y un
	Talismán y ponlos en tu mano". Mismo molde que try_execute_reveal_until_ally_and_weapon_pattern
	(metalmorfo), con Talismán. Sus otras dos cláusulas (bloqueadores ganan Fuerza / el rival
	pierde Imbloqueable; Destierro al Botarse por daño) no van aquí."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar un aliado y un talis" in lower):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Diadema Celestial", controller_id):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found_ally: Dictionary = {}
	var found_talisman: Dictionary = {}
	while not deck.is_empty() and (found_ally.is_empty() or found_talisman.is_empty()):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var top_type: int = top.get("tipo", -1)
		if found_ally.is_empty() and top_type == Constants.CardType.ALIADO:
			found_ally = top
		elif found_talisman.is_empty() and top_type == Constants.CardType.TALISMAN:
			found_talisman = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "Diadema Celestial"))
	var main := _main.get_node_or_null("/root/Main")
	if main:
		await RevealWindowScript.show_cards(main, controller_id, [found_ally, found_talisman].filter(func(d): return not d.is_empty()), str(card.card_name) if card else "Diadema Celestial")
	var hand_container_diadema = (main.player_hand if controller_id == 0 else main._opponent_fan) if main else null
	if main and hand_container_diadema and main.has_method("_create_card"):
		for picked_data in [found_ally, found_talisman]:
			if picked_data.is_empty():
				continue
			var card_node = main._create_card(picked_data, false)
			hand_container_diadema.add_card(card_node)
			main._connect_card_signals(card_node)
			_remove_data_from_array(revealed, picked_data)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Diadema Celestial)")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


# =============================================================================
# PATRÓN "MUESTRA CARTAS... HASTA MOSTRAR DOS ALIADOS DE DISTINTO COSTE Y
# PONLOS EN TU MANO" (revelado hasta cumplir condición, p.ej. Alicia en
# Wonderland)
# =============================================================================
func try_execute_reveal_until_distinct_cost_allies_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Alicia en Wonderland: "Muestra cartas del tope de tu Castillo hasta mostrar dos Aliados de
	distinto coste y ponlos en tu mano". Se revela de a una hasta encontrar dos Aliados de coste
	distinto (o vaciar el Castillo). Lo demás revelado se baraja de vuelta ("muestra" sin orden
	obliga a barajar). Si no se encuentran, no se pone nada en la mano ("en medida de lo posible",
	DAR Sección 8) y todo se baraja.
	Devuelve true si el patrón aplicaba (se haya podido resolver o no)."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar" in lower and "distinto coste" in lower and "aliados" in lower):
		return false

	var rx := RegEx.new()
	rx.compile("(?i)muestra[s]?\\s+cartas?\\s+del\\s+\\S+\\s+de\\s+tu\\s+castillo")
	if not rx.search(ability_text):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Alicia en Wonderland", controller_id):
		return true

	var cm = CardManager
	var deck: Array = cm.get_deck(controller_id)

	var revealed: Array = []
	var first_ally: Dictionary = {}
	var second_ally: Dictionary = {}
	while not deck.is_empty():
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		if top.get("tipo", -1) != Constants.CardType.ALIADO:
			continue
		if first_ally.is_empty():
			first_ally = top
		elif second_ally.is_empty() and int(top.get("coste", -1)) != int(first_ally.get("coste", -2)):
			second_ally = top
			break

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "Alicia en Wonderland"))
	var to_hand: Array = []
	if not first_ally.is_empty() and not second_ally.is_empty():
		to_hand = [first_ally, second_ally]

	var main2 = _main.get_node_or_null("/root/Main")
	if main2 and not to_hand.is_empty():
		await RevealWindowScript.show_cards(main2, controller_id, to_hand, str(card.card_name) if card else "Alicia en Wonderland")
	var hand_container_alicia = (main2.player_hand if controller_id == 0 else main2._opponent_fan) if main2 else null
	if main2 and hand_container_alicia and main2.has_method("_create_card"):
		for picked_data in to_hand:
			var card_node = main2._create_card(picked_data)
			hand_container_alicia.add_card(card_node)
			main2._connect_card_signals(card_node)

	for picked_data in to_hand:
		_remove_data_from_array(revealed, picked_data)
	for c in revealed:
		deck.append(c)
	cm.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Alicia en Wonderland)")

	if main2 and main2.get("_zone_manager"):
		main2._zone_manager._update_castillo_counts()

	return true


func try_execute_reveal_until_three_cost1_allies_play_one_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar tres Aliados de coste 1, juega uno de
	ellos sin pagar su coste y Baraja el resto' (gran kraken) — dispara tanto en 'entra en juego'
	como en 'ataca' (mismo dispatcher compartido para el primero; registrado también en la rama
	on_attack, ver TriggerResolution.gd)."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar tres aliados de coste 1" in lower):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "gran kraken", controller_id):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found: Array = []
	while not deck.is_empty() and found.size() < 3:
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		if top.get("tipo", -1) == Constants.CardType.ALIADO and int(top.get("coste", -1)) == 1:
			found.append(top)

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "gran kraken"))
	var main := _main.get_node_or_null("/root/Main")
	if not found.is_empty() and main and main._gold_manager:
		var picked_idx: int = await RevealWindowScript.pick_one(main, controller_id, found, str(card.card_name) if card else "gran kraken",
			"Toca el Aliado que juegas sin pagar su coste")
		if picked_idx >= 0 and picked_idx < found.size():
			var picked: Dictionary = found[picked_idx]
			_remove_data_from_array(revealed, picked)
			await main._gold_manager.play_card_for_free(picked, controller_id)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (gran kraken)")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_reveal_until_weapon_or_totem_and_ally_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar un Arma o Tótem y un Aliado y ponlos en
	tu mano' (atenea en wonderland) — mismo patrón que
	try_execute_reveal_until_ally_and_gold_pattern, pero el segundo tipo buscado es Arma O Tótem
	(cualquiera de los dos) en vez de Oro. Dispara tanto en 'entra' como en 'sale del juego' (mismo
	dispatcher compartido, ver _resolve_look_and_play_patterns)."""
	var lower := ability_text.to_lower()
	if not ("hasta mostrar un arma o tótem y un aliado" in lower or "hasta mostrar un arma o totem y un aliado" in lower):
		return false
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "atenea en wonderland", controller_id):
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found_weapon_totem: Dictionary = {}
	var found_ally: Dictionary = {}
	while not deck.is_empty() and (found_weapon_totem.is_empty() or found_ally.is_empty()):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var top_type: int = top.get("tipo", -1)
		if found_weapon_totem.is_empty() and (top_type == Constants.CardType.ARMA or top_type == Constants.CardType.TOTEM):
			found_weapon_totem = top
		elif found_ally.is_empty() and top_type == Constants.CardType.ALIADO:
			found_ally = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "atenea en wonderland"))
	var main := _main.get_node_or_null("/root/Main")
	if main:
		await RevealWindowScript.show_cards(main, controller_id, [found_weapon_totem, found_ally].filter(func(d): return not d.is_empty()), str(card.card_name) if card else "atenea en wonderland")
	var hand_container_atenea = (main.player_hand if controller_id == 0 else main._opponent_fan) if main else null
	if main and hand_container_atenea and main.has_method("_create_card"):
		for picked_data in [found_weapon_totem, found_ally]:
			if picked_data.is_empty():
				continue
			var card_node = main._create_card(picked_data, false)
			hand_container_atenea.add_card(card_node)
			main._connect_card_signals(card_node)
			_remove_data_from_array(revealed, picked_data)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (atenea en wonderland)")
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func _remove_data_from_array(array: Array, data: Dictionary) -> void:
	"""Quita de 'array' el diccionario de carta que coincide por id/uuid con 'data'.
	Duplicado idéntico en LookRevealPatternsA.gd — helper trivial (11
	líneas) usado por funciones de ambas mitades del split alfabético."""
	if data.is_empty():
		return
	var search_id = data.get("id", "")
	var search_uuid = data.get("uuid", "")
	for i in range(array.size()):
		var item = array[i]
		if (search_id and item.get("id") == search_id) or (search_uuid and item.get("uuid") == search_uuid):
			array.remove_at(i)
			return
