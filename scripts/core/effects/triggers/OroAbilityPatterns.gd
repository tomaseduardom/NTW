extends RefCounted
## OroAbilityPatterns — patrones "try_execute_*_pattern" para Oros (auditoría de cartas sin
## cobertura, arquitectura.md). Mismo criterio que TotemAbilityPatterns.gd/WeaponAbilityPatterns.gd
## (detección por substring). Instanciado en TriggerSystem._ready() como _oro_patterns. Las
## cláusulas de una sola fase (on_agrupacion/on_turn_end) se llaman explícitamente desde
## TriggerResolution.gd con la cláusula ya aislada: en el despachador compartido
## _resolve_look_and_play_patterns() (texto completo) se dispararían donde no corresponde.

const CastleLookScript = preload("res://scripts/core/effects/CastleLook.gd")

var _main: Node

## torii: "Si lo haces, no Robas al finalizar tu turno" — bandera de un uso por jugador que consume
## PhaseFlowController._resolve_fase_final() antes del robo. Se guarda con el número de turno (como
## kotoku-in) para que no sobreviva al turno siguiente.
var _torii_skip_final_draw: Dictionary = {}


func setup(main: Node) -> void:
	_main = main


func register_torii_skip_final_draw(player_id: int) -> void:
	_torii_skip_final_draw[player_id] = GameManager.turn_serial


func should_skip_final_draw(player_id: int) -> bool:
	if not _torii_skip_final_draw.has(player_id):
		return false
	var set_turn: int = _torii_skip_final_draw[player_id]
	_torii_skip_final_draw.erase(player_id)
	return set_turn == GameManager.turn_serial


# =============================================================================
# hidromiel ("Ángeles y Demonios: Vigilantes")
# =============================================================================
func try_execute_hidromiel_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, Baraja hasta tres cartas de un Cementerio y
	Roba dos cartas' (hidromiel). Única cláusula de la carta — se registra
	directo en el despachador compartido sin guardia extra (no hay otra
	cláusula propia con la que confundirse). 'De un Cementerio' (singular)
	se simplifica a un pool combinado de ambos Cementerios en el picker
	(mismo criterio ya aceptado para Quinto Sello, que decía 'de los
	Cementerios' en plural) — permite elegir cartas de ambos si el jugador
	quiere, en vez de forzar la elección de un solo Cementerio primero;
	limitación conocida, no una garantía estricta de 'un solo Cementerio'."""
	var lower := ability_text.to_lower()
	if not ("baraja hasta tres cartas de un cementerio y roba dos cartas" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true
	var no_filter := func(_c: Node) -> bool: return true
	var picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"hidromiel — elige hasta 3 cartas de los Cementerios para Barajar", no_filter, 3, "cemetery", false, false, controller_id)
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		if not CardManager.take_from_cemetery(owner_of_picked, picked_data):
			continue
		CardManager.get_deck(owner_of_picked).append(picked_data)
		CardManager.shuffle_deck(owner_of_picked)

	await ActionModule.draw(controller_id, 2, "hidromiel", true)
	return true


# =============================================================================
# udjat ("Ángeles y Demonios: Vigilantes")
# =============================================================================
func try_execute_udjat_vigilia_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""udjat: "Una vez por turno, dos Aliados ganan y/o pierden 1 de Fuerza por el turno o Baraja una
	carta de tu mano para Robar una carta". Habilidad ACTIVADA (camino compartido, como
	kotoku-in/sable corto). Guardia "en tu fase final" (su otra cláusula): sin ella, el despachador
	la probaría también en on_turn_end (arquitectura.md §12.9). Simplificación: un solo Aliado
	elegido gana o pierde 1 de Fuerza."""
	var lower := ability_text.to_lower()
	if not ("dos aliados ganan y/o pierden 1 de fuerza por el turno" in lower):
		return false
	if "en tu fase final" in lower:
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true

	var options: Array = ["Un Aliado gana o pierde 1 de Fuerza este turno", "Baraja una carta de tu mano para Robar una carta"]
	var choice: int = await SelectionManager.await_choice(main, "%s: elige un efecto" % (card.card_name if card.get("card_name") else "udjat"), options, controller_id)
	if choice == 0:
		var filter := func(c: Node) -> bool: return c.get("card_type") == Constants.CardType.ALIADO \
			and c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
		var target: Node = await main._card_interaction.await_target("Elige un Aliado (gana o pierde 1 de Fuerza este turno)", filter, true, controller_id)
		if not target or not is_instance_valid(target):
			return true
		var sign_options: Array = ["Gana 1 de Fuerza", "Pierde 1 de Fuerza"]
		var sign_choice: int = await SelectionManager.await_choice(main, "udjat: ¿gana o pierde Fuerza?", sign_options, controller_id)
		ContinuousEffectManager.register_modifier({
			"source": card, "target": target,
			"type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
			"value": 1 if sign_choice == 0 else -1, "operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": 1,
			"description": "udjat: %s 1 Fuerza este turno" % ("gana" if sign_choice == 0 else "pierde")
		})
	else:
		var hand_container_udjat = main.player_hand if controller_id == 0 else main._opponent_fan
		if not hand_container_udjat or hand_container_udjat.cards.is_empty():
			return true
		var hand_cards: Array = hand_container_udjat.cards.duplicate()
		var hand_filter := func(c: Node) -> bool: return c in hand_cards
		var to_shuffle: Node = await main._card_interaction.await_target("Elige una carta de tu mano para Barajar (y Robar una carta)", hand_filter, true, controller_id)
		if not to_shuffle or not is_instance_valid(to_shuffle):
			return true
		var data: Dictionary = to_shuffle.card_data.duplicate()
		hand_container_udjat.remove_card(to_shuffle, false)
		to_shuffle.queue_free()
		CardManager.get_deck(controller_id).append(data)
		CardManager.shuffle_deck(controller_id)
		AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (udjat)")
		await ActionModule.draw(controller_id, 1, "udjat", true)
	return true


func try_execute_udjat_final_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'En tu Fase Final, puedes Desterrar una carta de tu Cementerio para
	Desterrar hasta dos cartas del Cementerio oponente' (udjat). Llamada
	EXPLÍCITA con la cláusula YA AISLADA desde el branch on_turn_end de
	TriggerResolution.gd — a propósito NO registrada en el despachador
	compartido (mismo criterio que try_execute_canon_naval_final_pattern
	en WeaponAbilityPatterns.gd, ver su docstring)."""
	var lower := ability_text.to_lower()
	if not ("puedes desterrar una carta de tu cementerio para desterrar hasta dos cartas del cementerio oponente" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._zone_viewer:
		return true
	if CardManager.get_cemetery(controller_id).is_empty():
		return true

	var own_only := func(c: Node) -> bool: return c.owner_id == controller_id
	var own_picked: Array = await main._zone_viewer.open_cemetery_target_picker(
		"udjat — Destierra una carta de tu Cementerio (opcional)", own_only, 1, "cemetery", false, false, controller_id)
	if own_picked.is_empty():
		return true
	var own_entry: Dictionary = own_picked[0]
	if not CardManager.take_from_cemetery(controller_id, own_entry.data):
		return true
	CardManager.add_to_exile(controller_id, own_entry.data)

	var opponent_id: int = 1 - controller_id
	if not CardManager.get_cemetery(opponent_id).is_empty():
		var opp_only := func(c: Node) -> bool: return c.owner_id == opponent_id
		var opp_picked: Array = await main._zone_viewer.open_cemetery_target_picker(
			"udjat — Destierra hasta 2 cartas del Cementerio oponente", opp_only, 2, "cemetery", false, false, controller_id)
		for entry in opp_picked:
			var idx: int = CardManager.get_cemetery(opponent_id).find(entry.data)
			if idx >= 0:
				CardManager.remove_from_cemetery(opponent_id, idx)
				CardManager.add_to_exile(opponent_id, entry.data)
	return true


# =============================================================================
# libro de thoth ("Bestiarium")
# =============================================================================
func try_execute_libro_de_thoth_pay_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""libro de thoth: "Una vez por turno, puedes pagar un Oro para Robar una carta y elegir entre que
	un Aliado gane Furia, duplique su Fuerza, o su daño sea enviado al Destierro este turno".
	Habilidad ACTIVADA. Su otra cláusula ("Cuando bloquees, genera un Oro por el turno") la
	resuelve GoldManager.check_libro_de_thoth_block() desde el Bloqueo, no por aquí.
	Paga con GameState.puede_pagar()/pagar_oro(), que reciben player_id (oro_reserva/oro_pagado
	indexados por jugador)."""
	var lower := ability_text.to_lower()
	if not ("puedes pagar un oro para robar una carta y elegir entre que un aliado gane furia" in lower):
		return false
	if not GameState.puede_pagar(controller_id, 1):
		return true

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var filter := func(c: Node) -> bool: return c.get("card_type") == Constants.CardType.ALIADO \
		and c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	var target: Node = await main._card_interaction.await_target("libro de thoth: elige un Aliado", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return true

	var options: Array = ["Gana Furia", "Duplica su Fuerza", "Su daño es enviado al Destierro este turno"]
	var choice: int = await SelectionManager.await_choice(main, "libro de thoth: elige un efecto para %s" % target.card_name, options, controller_id)

	GameState.pagar_oro(controller_id, 1)
	await ActionModule.draw(controller_id, 1, "libro de thoth", true)
	match choice:
		0:
			ContinuousEffectManager.register_modifier({
				"source": card, "target": target,
				"type": ContinuousEffectManager.ModifierType.KEYWORDS, "stat": "",
				"value": 0, "operation": "add",
				"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
				"layer": ContinuousEffectManager.ModifierLayer.LAYER_6_ABILITIES,
				"keywords_add": [Constants.Keyword.FURIA],
				"description": "libro de thoth: Furia"
			})
		1:
			var current_strength: int = ContinuousEffectManager.get_modified_strength(target)
			ContinuousEffectManager.register_modifier({
				"source": card, "target": target,
				"type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
				"value": current_strength, "operation": "add",
				"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
				"description": "libro de thoth: Fuerza duplicada"
			})
		2:
			# "Este turno" — mismo mecanismo real ya usado por Segundo Sello
			# (SearchOwnZonePatterns.gd) para la misma duración de un solo
			# turno sobre Card.damage_goes_to_exile: una conexión de una sola
			# vez a GameManager.turn_started que se desconecta sola.
			target.damage_goes_to_exile = true
			# "Este turno": el flag se limpia en el PRÓXIMO turn_started, sea de quien sea (como Segundo
			# Sello en SearchOwnZonePatterns.gd).
			var clear_it: Callable
			clear_it = func(_started_player_id: int, _turn: int) -> void:
				if is_instance_valid(target):
					target.damage_goes_to_exile = false
				if GameManager.turn_started.is_connected(clear_it):
					GameManager.turn_started.disconnect(clear_it)
			GameManager.turn_started.connect(clear_it)
	return true


# =============================================================================
# torii ("Espíritu Samurái")
# =============================================================================
func try_execute_torii_agrupacion_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Al comienzo de tu Agrupación, puedes mirar las primeras dos cartas
	de tu Castillo, poner una en tu mano y Barajar la otra. Si lo haces, no
	Robas al finalizar tu turno' (torii). Llamada EXPLÍCITA con la
	cláusula YA AISLADA desde el branch on_agrupacion de TriggerResolution.gd
	(mismo criterio que udjat/Fase Final arriba). Requirió agregar la frase
	'al comienzo de tu agrupación'/'al comienzo de tu agrupacion' a
	Card.TRIGGER_KEYWORDS['on_agrupacion'] — la única frase que había ahí
	('en tu agrupación') no matchea el texto real de torii."""
	var lower := ability_text.to_lower()
	if not ("mirar las primeras dos cartas de tu castillo" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main.has_method("_create_card"):
		return true
	var deck: Array = CardManager.get_deck(controller_id)
	if deck.is_empty():
		return true

	var use_it: bool = await SelectionManager.await_two_choice(
		main, "torii: ¿mirar las primeras 2 cartas de tu Castillo? (no Robarás al finalizar tu turno)", "Sí", "No", controller_id)
	if not use_it:
		return true

	var top_two: Array = []
	for i in range(mini(2, deck.size())):
		top_two.append(deck.pop_front())
	if top_two.is_empty():
		return true

	var chosen: Dictionary = top_two[0]
	if top_two.size() > 1:
		var names: Array = []
		for c in top_two:
			names.append(str(c.get("nombre", "?")))
		var choice: int = await SelectionManager.await_choice(main, "torii: elige una para tu mano (la otra se baraja)", names, controller_id)
		chosen = top_two[choice]
		top_two.remove_at(choice)

	var card_node = main._create_card(chosen, false)
	var hand_container_torii = main.player_hand if controller_id == 0 else main._opponent_fan
	hand_container_torii.add_card(card_node)
	main._connect_card_signals(card_node)
	for c in top_two:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (torii)")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()

	register_torii_skip_final_draw(controller_id)
	return true


func try_execute_carro_szgany_final_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Carro Szgany: "En tu Fase Final, Destierra hasta dos cartas de un Cementerio, mira tantas
	cartas del tope de tu Castillo como Aliados controles y ordénalas". EffectCompiler no entiende
	la frase completa. Destierro: selector del tablero con los dos Cementerios, todas de UNO
	(one_zone). Mirar: CastleLook con la segunda mitad del texto."""
	var lower := ability_text.to_lower()
	var look_at: int = lower.find("mira tantas cartas del tope de tu castillo como aliados controles")
	if not ("destierra hasta dos cartas de un cementerio" in lower) or look_at < 0:
		return false
	await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, 2, true, card,
		Constants.Zone.DESTIERRO, false, true)
	await CastleLookScript.try_execute_text(card, ability_text.substr(look_at), controller_id)
	return true


func try_execute_torii_final_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'En la Fase Final, si tienes dos o menos cartas en tu mano, puedes
	Robar una carta' (torii). Llamada EXPLÍCITA con la cláusula YA AISLADA
	desde el branch on_turn_end. Frase agregada a Card.TRIGGER_KEYWORDS
	('en la fase final, si tienes') deliberadamente NARROW — 'en la fase
	final' a secas colisionaría con 'en la fase final oponente' (Biblioteca
	de Caballería, on_opponent_turn_end), clasificando esa carta también
	como on_turn_end por error."""
	var lower := ability_text.to_lower()
	if not ("si tienes dos o menos cartas en tu mano, puedes robar una carta" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var hand_container_torii_final = main.player_hand if controller_id == 0 else main._opponent_fan
	if not hand_container_torii_final:
		return true
	if hand_container_torii_final.cards.size() > 2:
		return true

	var use_it: bool = await SelectionManager.await_two_choice(
		main, "torii: tienes %d carta(s) en mano, ¿Robar una carta?" % hand_container_torii_final.cards.size(), "Sí", "No", controller_id)
	if not use_it:
		return true
	await ActionModule.draw(controller_id, 1, "torii", true)
	return true
