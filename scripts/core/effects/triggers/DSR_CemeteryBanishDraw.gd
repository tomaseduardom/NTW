extends RefCounted
## DSR_CemeteryBanishDraw — parte de DrawShuffleResolver.gd (fachada con reenvíos de una línea;
## hermanos: DSR_ShuffleDrawCombos.gd, DSR_SearchGoldCombos.gd, DSR_DiscardChoicePatterns.gd).
## Patrones sobre uno o ambos Cementerios (Desterrar, Barajar al Castillo o subir a la mano), a
## veces con Robo (aku aku, Espada de O'Higgins, Campanita, Tamales, Quantum Megumi, Hanta el
## Samurai, Mariano Osorio, Capitán O'Brien). Opera sobre TriggerSystem vía _executor._main (ver
## TargetedEffectExecutor.gd).

var _executor: TargetedEffectExecutor


func setup(executor: TargetedEffectExecutor) -> void:
	_executor = executor


func try_execute_banish_cemeteries_equal_to_own_strength_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando hagas daño de combate, Destierra tantas cartas de los Cementerios como Fuerza tenga un
	Aliado' (aku aku) — 'un Aliado' sin más calificador se interpreta como la propia carta (la que
	hizo el daño), autoreferencial como el resto de disparadores 'cuando hagas/haga daño' de una
	sola carta. También cubre 'puedes Desterrar hasta tantas cartas de los Cementerios como Fuerza
	tenga este Aliado' (kaitai, En tu Fase Final — autoreferencial explícito con 'este')."""
	var lower := ability_text.to_lower()
	if not ("destierra tantas cartas de los cementerios como fuerza tenga un aliado" in lower
			or "desterrar hasta tantas cartas de los cementerios como fuerza tenga este aliado" in lower):
		return false

	var amount: int = ContinuousEffectManager.get_modified_strength(card)
	if amount <= 0:
		return true

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true
	# Click directo con ambos Cementerios visibles en vez del modal de lista viejo — pool combinado,
	# sin lock (mismo caso que Espada de O'Higgins, arquitectura.md §10.14/§10.27).
	var no_filter := func(_c: Node) -> bool: return true
	var card_w := "carta" if amount == 1 else "cartas"
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Destierra hasta %d %s de los Cementerios" % [amount, card_w], no_filter, amount, "cemetery", false, false, controller_id)
	if not picked.is_empty() and await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		if not CardManager.take_from_cemetery(owner_of_picked, picked_data):
			continue
		CardManager.add_to_exile(owner_of_picked, picked_data)
	return true


## "Destierra hasta N cartas de los Cementerios y Roba M cartas" (Espada de O'Higgins) lo resuelve
## try_execute_banish_from_cemeteries_and_draw_pattern() (más abajo), que ejecuta
## MiscTargetedPatterns._resolve_banish_from_both_cemeteries() (arquitectura.md §10.21).


func try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Puedes Barajar hasta cuatro cartas de los Cementerios o subir un Aliado o Tótem de tu
	Cementerio a tu mano' (Campanita) — elección A/B."""
	var lower := ability_text.to_lower()
	if not ("barajar hasta cuatro cartas de los cementerios o subir un aliado o tótem de tu cementerio" in lower
			or "barajar hasta cuatro cartas de los cementerios o subir un aliado o totem de tu cementerio" in lower):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true
	# La elección A/B ("Barajar" vs "Subir") es un modal de dos botones (son dos efectos, no dos
	# cartas; arquitectura.md §10.16). La carta se elige después con
	# ZoneViewerModule.open_cemetery_target_picker().
	var choose_shuffle: bool = await SelectionManager.await_two_choice(
		main, "Campanita", "Barajar hasta cuatro cartas de los Cementerios", "Subir un Aliado o Tótem de tu Cementerio a tu mano", controller_id)

	if choose_shuffle:
		var no_filter := func(_c: Node) -> bool: return true
		var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"Baraja hasta cuatro carta(s) de los Cementerios", no_filter, 4, "cemetery", false, false, controller_id)
		if picked.is_empty():
			return true
		if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Campanita", controller_id):
			return true
		for entry in picked:
			var owner_of_picked: int = entry.owner_id
			var picked_data: Dictionary = entry.data
			var idx: int = CardManager.get_cemetery(owner_of_picked).find(picked_data)
			if idx < 0:
				continue
			CardManager.remove_from_cemetery(owner_of_picked, idx)
			CardManager.get_deck(owner_of_picked).append(picked_data)
			CardManager.shuffle_deck(owner_of_picked)
			AnimationQueue.queue_shuffle(owner_of_picked, "Barajar mazo (Campanita)")
	else:
		# 'de TU Cementerio' (posesivo, solo propio) + filtrado por tipo —
		# el filtro rechaza tanto el lado rival como Armas/Talismanes/Oro;
		# esas cartas se ven en el popup pero no brillan ni son clickeables.
		var eligible_filter := func(c: Node) -> bool:
			return c.owner_id == controller_id and c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM]
		var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"Sube un Aliado o Tótem de tu Cementerio a tu mano", eligible_filter, 1, "cemetery", false, false, controller_id)
		if picked.is_empty():
			return true
		if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Campanita", controller_id):
			return true
		var picked_data: Dictionary = picked[0].data
		if not CardManager.take_from_cemetery(controller_id, picked_data):
			return true
		var card_node = main._create_card(picked_data, false)
		var hand_container_campanita = main.player_hand if controller_id == 0 else main._opponent_fan
		hand_container_campanita.add_card(card_node)
		main._connect_card_signals(card_node)
	return true


func try_execute_shuffle_up_to_n_cemeteries_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	""""Puedes Barajar hasta N cartas de los Cementerios" (p.ej. Tamales: "En tu Fase Final, puedes
	Barajar hasta tres cartas de los Cementerios"), sin Desterrar (a diferencia de Armería del
	Guerrero/Colmillo de Vampiro). "Los Cementerios" = ambos; "puedes" = opcional (cancelar = 0
	elegidas).
	'and not "desterrar" in lower': "puedes Barajar y/o Desterrar..." (Capitán O'Brien) contiene
	"puedes barajar" y va a try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern()."""
	var lower := ability_text.to_lower()
	if not ("puedes barajar" in lower and "cartas de los cementerios" in lower) or "desterrar" in lower:
		return false

	var amount_rx := RegEx.new()
	amount_rx.compile("barajar hasta (\\w+) cartas? de los cementerios")
	var m := amount_rx.search(lower)
	var max_amount: int = UniversalCardParser._parse_amount(m.get_string(1)) if m else 1

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true
	# Click directo con ambos Cementerios visibles en vez del modal de lista viejo.
	var no_filter := func(_c: Node) -> bool: return true
	var card_w := "carta" if max_amount == 1 else "cartas"
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Baraja hasta %d %s de los Cementerios" % [max_amount, card_w], no_filter, max_amount, "cemetery", false, false, controller_id)
	if picked.is_empty() or await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Tamales", controller_id):
		return true
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		if not CardManager.take_from_cemetery(owner_of_picked, picked_data):
			continue
		CardManager.get_deck(owner_of_picked).append(picked_data)
		CardManager.shuffle_deck(owner_of_picked)
		AnimationQueue.queue_shuffle(owner_of_picked, "Barajar mazo (Tamales)")
	return true


func try_execute_banish_up_to_n_cemeteries_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	""""Puedes Desterrar hasta N cartas de los Cementerios" (p.ej. Quantum Megumi: "En tu Fase Final,
	puedes Desterrar hasta dos cartas de los Cementerios"): versión Desterrar de
	try_execute_shuffle_up_to_n_cemeteries_pattern. "Los Cementerios" = ambos; "puedes" = opcional.
	'and not "barajar" in lower': evita el falso positivo simétrico con "Desterrar y/o Barajar"."""
	var lower := ability_text.to_lower()
	if not ("puedes desterrar" in lower and "cartas de los cementerios" in lower) or "barajar" in lower:
		return false

	var amount_rx := RegEx.new()
	amount_rx.compile("desterrar hasta (\\w+) cartas? de los cementerios")
	var m := amount_rx.search(lower)
	var max_amount: int = UniversalCardParser._parse_amount(m.get_string(1)) if m else 1

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true
	# Click directo con ambos Cementerios visibles en vez del modal de lista viejo.
	var no_filter := func(_c: Node) -> bool: return true
	var card_w := "carta" if max_amount == 1 else "cartas"
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Destierra hasta %d %s de los Cementerios" % [max_amount, card_w], no_filter, max_amount, "cemetery", false, false, controller_id)
	if picked.is_empty() or await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Quantum Megumi", controller_id):
		return true
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		if not CardManager.take_from_cemetery(owner_of_picked, picked_data):
			continue
		CardManager.add_to_exile(owner_of_picked, picked_data)
	return true


func try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Capitán O'Brien: "En tu Fase Final, puedes Barajar y/o Desterrar tantas cartas de los
	Cementerios como Fuerza tenga este Aliado". Cantidad dinámica (Fuerza efectiva). Usa
	GoldManager._resolve_armeria_barajar_desterrar() con esa cantidad; la ventana de respuesta se
	abre antes de arrancar (el helper elige carta por carta, sin un punto de declaración previo)."""
	var lower := ability_text.to_lower()
	if not ("barajar y/o desterrar" in lower and "cartas de los cementerios" in lower and "fuerza tenga" in lower):
		return false
	if not is_instance_valid(card):
		return true

	var amount: int = ContinuousEffectManager.get_modified_strength(card)
	if amount <= 0:
		return true

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	await main._gold_manager._resolve_armeria_barajar_desterrar(amount, str(card.card_name), controller_id)
	return true


func try_execute_banish_from_cemeteries_and_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Espada de O'Higgins: "Destierra hasta N cartas de los Cementerios y Roba M cartas". "los
	Cementerios" = ambos, en un solo pool. Unido por "y" (sin "Luego"): el Robo ocurre siempre,
	aunque se destierren cero.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("de los cementerios" in lower and "destierra" in lower):
		return false

	var banish_rx := RegEx.new()
	banish_rx.compile("(?i)destierra\\s+hasta\\s+(\\w+)\\s+cartas?\\s+de\\s+los\\s+cementerios")
	var m_banish := banish_rx.search(ability_text)
	var banish_amount: int = UniversalCardParser._parse_amount(m_banish.get_string(1)) if m_banish else 0

	var draw_rx := RegEx.new()
	draw_rx.compile("(?i)roba\\s+(\\w+)\\s+cartas?")
	var m_draw := draw_rx.search(ability_text)
	var draw_amount: int = UniversalCardParser._parse_amount(m_draw.get_string(1)) if m_draw else 0

	if banish_amount > 0:
		await _executor._resolve_banish_from_both_cemeteries(banish_amount, card, controller_id)

	if draw_amount > 0:
		await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)

	return true


func try_execute_weapon_count_banish_cemetery_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Hanta el Samurai: "En tu Fase Final, Destierra hasta tantas cartas de un Cementerio como Armas
	controles, más uno". "Un Cementerio" = eliges cuál (no un pool combinado como "los
	Cementerios"). Cantidad dinámica: Armas equipadas en los Aliados del controlador + 1. Sin
	patrón propio, el extractor genérico desterraba cartas en juego.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("tantas cartas de un cementerio" in lower and "armas controles" in lower):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true

	var weapon_count: int = 0
	var own_fields_hanta: Array = [main.player_field, main.player_linea_ataque] if controller_id == 0 else [main.opponent_field, main.opponent_linea_ataque]
	for field in own_fields_hanta:
		if not field:
			continue
		for c in field.get_children():
			if not is_instance_valid(c):
				continue
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				weapon_count += weapons.size()
	var amount: int = weapon_count + 1

	if CardManager.get_cemetery(0).is_empty() and CardManager.get_cemetery(1).is_empty():
		return true
	if not main._zone_viewer:
		return true

	# Ver ambos Cementerios lado a lado y elegir con click directo, en vez de preguntar primero 'de
	# cuál Cementerio' con un modal — 'un Cementerio' (sin posesivo, singular) en el texto real sigue
	# significando UN SOLO Cementerio para toda esta habilidad, no un pool combinado (a diferencia de
	# Espada de O'Higgins, 'los Cementerios' en plural) — lock_to_one_side=true lo hace cumplir: tras
	# el primer click, el otro Cementerio deja de ser elegible.
	var no_filter := func(_c: Node) -> bool: return true
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Destierra hasta %d carta(s) de UN Cementerio (tuyo o rival)" % amount,
		no_filter, amount, "cemetery", true, false, controller_id)
	if picked.is_empty():
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Hanta el Samurai", controller_id):
		return true
	for entry in picked:
		var target_owner: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		var idx: int = CardManager.get_cemetery(target_owner).find(picked_data)
		if idx >= 0:
			CardManager.remove_from_cemetery(target_owner, idx)
			CardManager.add_to_exile(target_owner, picked_data)

	return true


func try_execute_vigilia_or_final_banish_opponent_cemetery_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Mariano Osorio (custom_mig_14, carta custom: el caché local es la única fuente): "En tu Vigilia
	o Fase Final, Destierra hasta tres cartas del Cementerio oponente". Dispara en los dos momentos
	(resolve_vigilia_triggers()/resolve_turn_end_triggers()). "Cementerio oponente" = siempre el
	del rival.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("destierra hasta tres cartas del cementerio oponente" in lower):
		return false

	var opponent_id: int = 1 - controller_id
	if CardManager.get_cemetery(opponent_id).is_empty():
		return true
	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true

	# Click directo en el Cementerio rival en vez del modal de lista viejo.
	var opp_only := func(c: Node) -> bool: return c.owner_id == opponent_id
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"Destierra hasta 3 carta(s) del Cementerio rival", opp_only, 3, "cemetery", false, false, controller_id)
	if picked.is_empty() or await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Mariano Osorio", controller_id):
		return true
	for entry in picked:
		var idx: int = CardManager.get_cemetery(opponent_id).find(entry.data)
		if idx >= 0:
			CardManager.remove_from_cemetery(opponent_id, idx)
			CardManager.add_to_exile(opponent_id, entry.data)
	return true
