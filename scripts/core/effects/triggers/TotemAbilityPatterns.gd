extends RefCounted
## TotemAbilityPatterns — patrones "try_execute_*_pattern" para Tótems (auditoría de cartas sin
## cobertura, arquitectura.md). Detección por substring, como LookAndPlayResolver.gd. Instanciado en
## TriggerSystem._ready() como _totem_patterns, llamado desde TriggerResolution.gd en
## on_enter_play/on_leave_play.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const InPlayAbilities = preload("res://scripts/core/effects/mechanics/InPlayAbilities.gd")
var _main: Node

## kotoku-in: "hacer que el próximo Talismán que juegue tu oponente este turno se resuelva sin
## efecto". Bandera de un uso por controller_id afectado, que consume
## TriggerSystem.resolve_talisman() al empezar (true = no resuelve, al Cementerio, como
## Anular/Cancelar). Se guarda con el número de turno para que no sobreviva al cambio de turno (se
## chequea al consumirla).
var _kotoku_in_talisman_fizzle: Dictionary = {}

## metropolitan: "convertirlo en un Aliado con Fuerza 3 hasta la Fase Final". Card → modifier_id de
## la Fuerza fija, para revertir tipo/zona/modificador al llegar a FINAL. GameManager.phase_changed
## se conecta la primera vez que se usa (_metropolitan_signal_connected), no en setup().
var _metropolitan_pending_reverts: Dictionary = {}
var _metropolitan_signal_connected: bool = false


func setup(main: Node) -> void:
	_main = main


## max_cost >= 0: solo un Talismán de ese coste o menos (nuckelavee: "el próximo Talismán de coste 1 o
## menos que juegue tu oponente este turno es Anulado").
func register_kotoku_in_talisman_fizzle(target_controller_id: int, max_cost: int = -1) -> void:
	_kotoku_in_talisman_fizzle[target_controller_id] = {"turn": GameManager.turn_serial, "max_cost": max_cost}


func consume_kotoku_in_talisman_fizzle(controller_id: int, talisman_cost: int = -1) -> bool:
	if not _kotoku_in_talisman_fizzle.has(controller_id):
		return false
	var entry: Dictionary = _kotoku_in_talisman_fizzle[controller_id]
	if int(entry.turn) != GameManager.turn_serial:
		_kotoku_in_talisman_fizzle.erase(controller_id)
		return false
	if int(entry.max_cost) >= 0 and talisman_cost > int(entry.max_cost):
		return false  # este Talismán no cuenta; sigue esperando al próximo
	_kotoku_in_talisman_fizzle.erase(controller_id)
	return true


func try_execute_arco_del_triunfo_pattern(ability_text: String, card: Node, controller_id: int, is_entering: bool) -> bool:
	"""'Cuando entra o sale del juego, muestra cartas de la parte superior de
	tu Castillo hasta mostrar un Aliado o Tótem de coste 2. Ponlo en juego o
	en tu mano y Baraja el resto. Los Aliados que controlas ganan 1 de Fuerza
	y su daño de combate es enviado al Destierro' (arco del triunfo, "Ángeles
	y Demonios: Vigilantes"). Un solo disparador de texto cubre AMBOS
	trigger_type (on_enter_play Y on_leave_play — TriggerResolution.gd ya
	aísla 'cuando entra o sale del juego' para los dos), por eso se llama con
	is_entering explícito desde los dos branches en vez de inferirlo aquí.

	El aura de +1 Fuerza y la redirección de daño son EFECTOS ESTÁTICOS
	'mientras esté en juego' — se registran solo al ENTRAR (is_entering) y
	se limpian solas o se desregistran al SALIR, no dependen de si la
	búsqueda encuentra algo."""
	var lower := ability_text.to_lower()
	if not ("muestra cartas de la parte superior de tu castillo hasta mostrar un aliado o t" in lower):
		return false

	if is_entering:
		# Aura permanente "Tus Aliados ganan 1 de Fuerza" — mecanismo ya
		# usado para auras "Tus Aliados" (ver _card_matches_global_target()
		# en ModifierRegistry.gd), limpieza automática al salir de juego vía
		# EffectController.on_card_left_play → _on_card_left_zone (mismo
		# mecanismo que cualquier otro modificador con source=esta carta).
		ContinuousEffectManager.register_modifier({
			"source": card,
			"target": "ALLIES",
			"filter": {"type": Constants.CardType.ALIADO},
			"stat": "strength",
			"operation": "add",
			"value": 1,
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"static_ability": true,
			"description": "arco del triunfo: +1 Fuerza a tus Aliados"
		})
		# "Su daño de combate es enviado al Destierro": se registra en
		# TriggerSystem.get_active_continuous_effects("damage_to_exile"), que consulta
		# BattleManager._check_damage_to_exile_effect() filtrando por el DEFENSOR. Como el aura cubre a
		# todos los Aliados propios (presentes y futuros), el target es el oponente (1 - controller_id).
		TriggerSystem.register_continuous_effect(card, {
			"type": "damage_to_exile",
			"targets": [1 - controller_id]
		})
	else:
		TriggerSystem.unregister_continuous_effect(card)

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main.has_method("_create_card") or not main._gold_manager:
		return true

	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var found: Dictionary = {}
	while not deck.is_empty() and found.is_empty():
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var t: int = top.get("tipo", -1)
		if (t == Constants.CardType.ALIADO or t == Constants.CardType.TOTEM) and int(top.get("coste", -1)) == 2:
			found = top

	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, (str(card.card_name) if card else "Arco del Triunfo"))
	if not found.is_empty():
		revealed.erase(found)
		var options: Array = ["Ponerla en juego (sin pagar su coste)", "Ponerla en tu mano"]
		var choice: int = await SelectionManager.await_choice(main, "%s: ¿dónde poner la carta encontrada?" % (card.card_name if card.get("card_name") else "arco del triunfo"), options, controller_id)
		if choice == 0:
			await main._gold_manager.play_card_for_free(found, controller_id)
		else:
			var card_node = main._create_card(found, false)
			var arco_hand_container = main.player_hand if controller_id == 0 else main._opponent_fan
			arco_hand_container.add_card(card_node)
			main._connect_card_signals(card_node)

	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (arco del triunfo)")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_kotoku_in_enter_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, genera un Oro por el turno para jugar cartas
	que no sean Talismán' (kotoku-in, "Espíritu Samurái"). Solo la cláusula
	de entrada — la segunda cláusula ('En tu Vigilia, una vez por turno,
	puedes Destruir una carta de coste 4 o menos o hacer que el próximo
	Talismán que juegue tu oponente este turno se resuelva sin efecto') es
	una habilidad ACTIVADA que necesita un botón nuevo en CardInspectionLayer/
	AbilityButtonSupport (fuera de alcance de esta tarea, sin verificar con
	tiempo suficiente todavía — queda pendiente a propósito)."""
	var lower := ability_text.to_lower()
	if not ("genera un oro por el turno para jugar cartas que no sean talism" in lower):
		return false
	# Sin elección de por medio — sirve igual para el jugador 1 (Remoto o bot), con su propio Oro
	# Virtual restringido.

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true

	var predicate := func(card_type, _card_race, _card_cost) -> bool:
		return card_type != Constants.CardType.TALISMAN
	main._gold_manager.generar_oro_virtual_restringido(1, predicate, "kotoku-in", controller_id)
	return true


func try_execute_metropolitan_enter_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, genera un Oro para Aliados de coste 2 o más o
	Roba dos cartas' (metropolitan, "Kaiju vs Mecha - Titanes"). Solo la
	cláusula de entrada — la conversión en Aliado de Vigilia se implementó
	aparte (try_execute_metropolitan_vigilia_convert_pattern, más abajo). La
	tercera ('Cuando ataca, un Aliado que no sea Metropolitan se convierte
	por el turno en un Aliado de Fuerza y coste 5') queda pendiente a
	propósito: solo tiene sentido una vez que metropolitan YA se convirtió en
	Aliado y de hecho ataca, y elegir/aplicar el buff a OTRO Aliado en ese
	momento puntual no alcanzó a verificarse con solidez en esta tarea."""
	var lower := ability_text.to_lower()
	if not ("genera un oro para aliados de coste 2 o m" in lower and "roba dos cartas" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true

	var options: Array = ["Generar un Oro (para Aliados de coste 2 o más)", "Robar dos cartas"]
	var choice: int = await SelectionManager.await_choice(main, "%s: elige un efecto" % (card.card_name if card.get("card_name") else "metropolitan"), options, controller_id)
	if choice == 0:
		var predicate := func(card_type, _card_race, card_cost) -> bool:
			return card_type == Constants.CardType.ALIADO and int(card_cost) >= 2
		main._gold_manager.generar_oro_virtual_restringido(1, predicate, "metropolitan")
	else:
		await ActionModule.draw(controller_id, 2, "metropolitan", true)
	return true


func try_execute_kotoku_in_vigilia_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""kotoku-in ("Espíritu Samurái"): "En tu Vigilia, una vez por turno, puedes Destruir una carta de
	coste 2 o menos o hacer que el próximo Talismán que juegue tu oponente este turno se resuelva
	sin efecto". Habilidad ACTIVADA: llega vía TriggerSystem.resolve_ability_effect(); el botón y
	el cupo los resuelve UniversalCardParser/ActionPipeline.activate_ability().
	Destruir es directo (ActionModule.destroy()); "próximo Talismán sin efecto" es la bandera que
	consume resolve_talisman() (consume_kotoku_in_talisman_fizzle()).
	Guardia "genera un oro por el turno": la lista compartida también se recorre en on_enter_play
	con el texto completo, que incluye esa otra cláusula; sin la guardia, jugar kotoku-in
	dispararía esta elección (como sable corto, WeaponAbilityPatterns.gd)."""
	var lower := ability_text.to_lower()
	if not ("destruir una carta de coste 2 o menos" in lower and "se resuelva sin efecto" in lower):
		return false
	if "genera un oro por el turno" in lower:
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true

	var options: Array = ["Destruir una carta de coste 2 o menos", "El próximo Talismán rival este turno no tiene efecto"]
	var choice: int = await SelectionManager.await_choice(main, "%s: elige un efecto" % (card.card_name if card.get("card_name") else "kotoku-in"), options, controller_id)
	if choice == 0:
		var filter := func(c: Node) -> bool:
			if c.get("card_type") == Constants.CardType.ORO:
				return false
			return ContinuousEffectManager.cost_at_most(c, 2)
		var target: Node = await main._card_interaction.await_target("Elige una carta de coste 2 o menos para Destruir", filter, true, controller_id)
		if target and is_instance_valid(target):
			await ActionModule.destroy([target], card, true, true)
	else:
		register_kotoku_in_talisman_fizzle(1 - controller_id)
	return true


func try_execute_metropolitan_vigilia_convert_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""metropolitan: "En tu Vigilia, puedes convertirlo en un Aliado con Fuerza 3 hasta la Fase
	Final". Habilidad ACTIVADA (mismo camino que kotoku-in). Conversión Tótem → Aliado como
	Sherlock Holmes (ConvertAndMiscResolver.try_execute_mill_convert_to_ally_pattern: mover de
	contenedor, card_type = ALIADO, set_zone(LINEA_DEFENSA), Fuerza fija 'set'), pero temporal: el
	modificador usa source = card para ubicarlo al revertir, y el Node queda en
	_metropolitan_pending_reverts hasta que phase_changed emita FINAL.
	Guardia "genera un oro para aliados": igual que kotoku-in, evita convertirlo al jugarlo
	(on_enter_play con el texto completo)."""
	var lower := ability_text.to_lower()
	if not ("convertirlo en un aliado con fuerza 3 hasta la fase final" in lower):
		return false
	if "genera un oro para aliados" in lower:
		return false
	if card.get("card_type") == Constants.CardType.ALIADO:
		return true  # ya convertido este turno, nada que hacer

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true

	_convert_totem_to_ally(card, controller_id, 3, "metropolitan convertido en Aliado: Fuerza 3")
	_metropolitan_pending_reverts[card] = true
	if not _metropolitan_signal_connected:
		_metropolitan_signal_connected = true
		GameManager.phase_changed.connect(_on_phase_changed_revert_metropolitan)
	return true


func _on_phase_changed_revert_metropolitan(new_phase: Constants.Phase) -> void:
	if new_phase != Constants.Phase.FINAL:
		return
	if _metropolitan_pending_reverts.is_empty():
		return
	for target_card: Node in _metropolitan_pending_reverts.keys():
		_revert_ally_to_totem(target_card)
	_metropolitan_pending_reverts.clear()


func _convert_totem_to_ally(card: Node, controller_id: int, strength: int, description: String) -> void:
	"""Tótem en juego → Aliado de Fuerza fija en la Línea de Defensa (modificador con source = card
	para ubicarlo al revertir: _revert_ally_to_totem())."""
	var main := _main.get_node_or_null("/root/Main")
	var target_field: HBoxContainer = main.player_field if controller_id == 0 else main.opponent_field
	var old_parent := card.get_parent()
	if old_parent and old_parent != target_field:
		old_parent.remove_child(card)
		target_field.add_child(card)
	card.card_type = Constants.CardType.ALIADO
	if card.has_method("set_zone"):
		card.set_zone(Constants.Zone.LINEA_DEFENSA)
	ContinuousEffectManager.register_modifier({
		"source": card,
		"target": card,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": strength,
		"operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": description
	})


func _revert_ally_to_totem(target_card: Node) -> void:
	if not is_instance_valid(target_card) or target_card.get("card_type") != Constants.CardType.ALIADO:
		return  # salió de juego o ya se revirtió por otro camino
	if not (target_card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return
	ContinuousEffectManager.remove_modifiers_from_source(target_card)
	target_card.card_type = Constants.CardType.TOTEM
	var owner: int = target_card.get("controller_id") if target_card.get("controller_id") != null else 0
	var main := _main.get_node_or_null("/root/Main")
	var totem_field: HBoxContainer = main.player_linea_apoyo if owner == 0 else main.opponent_linea_apoyo
	var old_parent: Node = target_card.get_parent()
	if totem_field and old_parent and old_parent != totem_field:
		old_parent.remove_child(target_card)
		totem_field.add_child(target_card)
	if target_card.has_method("set_zone"):
		target_card.set_zone(Constants.Zone.LINEA_APOYO)


## iga ryu: Tótems convertidos "por el turno"; vuelven a ser Tótem al comenzar el turno siguiente.
var _turn_convert_reverts: Dictionary = {}


func try_execute_iga_ryu_convert_totems_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""iga ryu: 'Una vez por turno, puedes convertir hasta tres Tótem en Aliados de Fuerza 4 por el
	turno' (activada). Cualquier Tótem en juego; el bot elige los propios."""
	if not (InPlayAbilities.IGA_RYU_CONVERT_TEXT in ability_text.to_lower()):
		return false
	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var totems: Array = []
	# El bot no le da Aliados al rival: solo sus Tótems.
	for pid in ([controller_id] if PlayerSideScript.is_bot(controller_id) else [controller_id, 1 - controller_id]):
		for line in PlayerSideScript.line_containers(main, pid):
			for c in line.get_children():
				if is_instance_valid(c) and c.get("card_type") == Constants.CardType.TOTEM:
					totems.append(c)
	if totems.is_empty():
		main._update_debug("No hay Tótems en juego para convertir")
		return true
	var chosen: Array = await main._card_interaction.await_multi_target(
		"Elige hasta tres Tótem para convertir en Aliados de Fuerza 4 por el turno", totems, 3,
		Callable(), Callable(), true, null, controller_id)
	if chosen.is_empty():
		return true
	if await EffectContextScript.ensure_window():
		return true
	for t in chosen:
		if is_instance_valid(t) and t.get("card_type") == Constants.CardType.TOTEM:
			_convert_totem_to_ally(t, CardQuery.controller_of(t), 4, "%s convertido en Aliado: Fuerza 4" % str(t.get("card_name")))
			_turn_convert_reverts[t] = true
	if not GameManager.turn_started.is_connected(_on_turn_started_revert_converted):
		GameManager.turn_started.connect(_on_turn_started_revert_converted)
	return true


func _on_turn_started_revert_converted(_player_id: int, _turn: int) -> void:
	for t: Node in _turn_convert_reverts.keys():
		_revert_ally_to_totem(t)
	_turn_convert_reverts.clear()


func try_execute_metropolitan_attack_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando ataca, un Aliado que no sea Metropolitan se convierte por el
	turno en un Aliado de Fuerza y coste 5' — solo dispara de verdad cuando
	metropolitan YA se convirtió en Aliado (try_execute_metropolitan_vigilia_
	convert_pattern) y de hecho ataca; para ese momento card_type ya es
	ALIADO, así que el trigger on_attack genérico lo recoge igual que a
	cualquier otro Aliado, sin chequeo especial aquí. 'Por el turno' = TIMED
	duration_value=1 (mismo cálculo que Tercer Sello: decuenta en el primer
	fin de turno, que es el de ESTE mismo turno de ataque)."""
	var lower := ability_text.to_lower()
	if not ("un aliado que no sea metropolitan se convierte por el turno en un aliado de fuerza y coste 5" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var filter := func(c: Node) -> bool:
		if c == card or c.get("card_type") != Constants.CardType.ALIADO:
			return false
		var owner: int = c.get("controller_id") if c.get("controller_id") != null else 0
		return owner == controller_id and c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE]
	var target: Node = await main._card_interaction.await_target("Elige un Aliado (no Metropolitan) para volverse Fuerza y coste 5 este turno", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return true

	ContinuousEffectManager.register_modifier({
		"source": card, "target": target,
		"type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
		"value": 5, "operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": 1,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "metropolitan: Fuerza 5 este turno"
	})
	ContinuousEffectManager.register_modifier({
		"source": card, "target": target,
		"type": ContinuousEffectManager.ModifierType.COST, "stat": "cost",
		"value": 5, "operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": 1,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "metropolitan: coste 5 este turno"
	})
	return true


func try_execute_rueda_fortuna_reveal_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Una vez por turno, muestra la primera carta de tu Castillo. Tus
	Aliados ganan tanta Fuerza como coste tenga esa carta. Si es un Oro,
	puedes ponerlo en tu mano y Robar una carta' (la rueda de la fortuna,
	"Secretos Arcanos"). Habilidad ACTIVADA (mismo camino compartido que
	kotoku-in/metropolitan arriba). El pump de Fuerza es un modificador
	PERMANENT por Aliado en juego en ESE momento (mismo criterio ya usado
	para Kuchiku Kan: 'permanentemente' en el texto, no 'los Aliados que
	controles' en presente continuo — no es un aura que siga a futuros
	Aliados). La carta se MIRA (no se saca del Castillo) salvo que sea un
	Oro y el jugador elija tomarla."""
	var lower := ability_text.to_lower()
	if not ("muestra la primera carta de tu castillo" in lower and "tus aliados ganan tanta fuerza como coste tenga esa carta" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main.has_method("_create_card"):
		return true
	var deck: Array = CardManager.get_deck(controller_id)
	if deck.is_empty():
		return true
	var top: Dictionary = deck[0]
	var top_cost: int = int(top.get("coste", 0))
	var revealed_script = load("res://scripts/core/effects/mechanics/RevealedCards.gd")
	revealed_script.record(controller_id, [top], "la rueda de la fortuna")
	var taken := false

	var allies: Array = []
	var ally_fields: Array = [main.player_field, main.player_linea_ataque] if controller_id == 0 else [main.opponent_field, main.opponent_linea_ataque]
	for f in ally_fields:
		if not f:
			continue
		for c in f.get_children():
			if c.get("card_type") == Constants.CardType.ALIADO:
				allies.append(c)
	for ally in allies:
		if top_cost > 0:
			ContinuousEffectManager.register_modifier({
				"source": ally, "target": ally,
				"type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
				"value": top_cost, "operation": "add",
				"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
				"description": "la rueda de la fortuna: +%d Fuerza" % top_cost
			})

	if top.get("tipo", -1) == Constants.CardType.ORO:
		var options: Array = ["Ponerlo en tu mano y robar una carta", "Dejarlo en el Castillo"]
		var choice: int = await SelectionManager.await_choice(main, "%s: ¿qué hacer con el Oro revelado?" % (card.card_name if card.get("card_name") else "la rueda de la fortuna"), options, controller_id)
		if choice == 0:
			taken = true
			deck.pop_front()
			var card_node = main._create_card(top, false)
			var rueda_hand_container = main.player_hand if controller_id == 0 else main._opponent_fan
			rueda_hand_container.add_card(card_node)
			main._connect_card_signals(card_node)
			await ActionModule.draw(controller_id, 1, "la rueda de la fortuna", true)
			if main.get("_zone_manager"):
				main._zone_manager._update_castillo_counts()
	# La carta mostrada que no se tomó sigue en el Castillo, que se Baraja.
	if not taken:
		revealed_script.shuffle_back(main, controller_id, [], "la rueda de la fortuna")
	return true


func try_execute_rueda_fortuna_sacrifice_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Puedes Destruirlo para que tus Aliados no puedan ser afectados por
	efectos oponentes este turno' (la rueda de la fortuna). Reutiliza el
	campo protection_type='ALL' del sistema de Protección ya existente
	(KeywordQuery.has_protection(): 'ALL' matchea cualquier protection_type
	consultado) — cobertura REAL pero PARCIAL: solo bloquea en los puntos
	del código que efectivamente consultan has_protection() (hoy: selección
	de objetivo de Talismanes y 'fuera del juego mientras ataca'), no
	literalmente cualquier efecto oponente posible — mismo tipo de
	limitación ya documentada para Segundo Sello (damage_goes_to_exile solo
	cubre daño al Castillo)."""
	var lower := ability_text.to_lower()
	if not ("puedes destruirlo para que tus aliados no puedan ser afectados por efectos oponentes este turno" in lower):
		return false

	await ActionModule.destroy([card], card, false, true)
	ContinuousEffectManager.register_modifier({
		"source": card, "target": "ALLIES",
		"filter": {"type": Constants.CardType.ALIADO},
		"type": ContinuousEffectManager.ModifierType.PROTECTION, "stat": "",
		"value": 0, "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": 1,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_6_ABILITIES,
		"protection_type": "ALL",
		"description": "la rueda de la fortuna: protección este turno"
	})
	return true


func try_execute_iga_ryu_enter_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, agrupa dos cartas o gana el control de
	cualquier carta oponente' (iga ryu, "Espíritu Samurái"). 'Gana el control'
	reutiliza ContinuousEffectManager.gain_control_of_card() (shedo titan);
	'agrupa dos cartas' es GoldManager.agrupar_cartas() (lo de la Agrupación,
	DAR 5.1: Oro Pagado → Reserva, Línea de Ataque → Defensa). Las
	otras dos: InPlayAbilities.iga_ryu_on_ally_enters() y
	try_execute_iga_ryu_convert_totems_pattern()."""
	var lower := ability_text.to_lower()
	if not ("gana el control de cualquier carta oponente" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var opponent_id: int = 1 - controller_id
	var in_play_zones: Array = [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	var filter := func(c: Node) -> bool:
		if c.get("card_type") == Constants.CardType.ORO:
			return false
		var owner: int = c.get("controller_id") if c.get("controller_id") != null else 0
		return owner == opponent_id and c.get("current_zone") in in_play_zones
	if "agrupa dos cartas o gana el control" in lower:
		var has_target := false
		for line in PlayerSideScript.line_containers(main, opponent_id):
			if line and line.get_children().any(func(c): return is_instance_valid(c) and filter.call(c)):
				has_target = true
				break
		var regroup: bool = not has_target
		if has_target and not PlayerSideScript.is_bot(controller_id):
			regroup = await SelectionManager.await_two_choice(main, str(card.card_name) if card.get("card_name") else "iga ryu",
				"Agrupar dos cartas", "Ganar el control de una carta oponente", controller_id)
		if regroup:
			if await TriggerSystem.open_response_window(card, str(card.card_name) if card.get("card_name") else "iga ryu", controller_id):
				return true
			await main._gold_manager.agrupar_cartas(controller_id, 2)
			return true
	var target: Node = await main._card_interaction.await_target("Elige una carta oponente para ganar su control", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card.get("card_name") else "iga ryu", controller_id):
		return true
	if await EffectController.offer_prevention(target, card, "control"):
		return true
	ContinuousEffectManager.gain_control_of_card(target, controller_id)
	return true


func try_execute_estacion_fantasma_name_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Una vez por turno, puedes nombrar una carta que no sea Oro. Tu
	oponente Baraja las cartas que controle con ese nombre' (Estación
	Fantasma, "Chile Oscuro 2"). Habilidad ACTIVADA. Reutiliza _main.
	_card_name_search.open_and_wait() (Malleus Maleficarum/Alicia en
	Wonderland) para el diálogo de nombrar, y ActionReturnDiscard.
	return_to_deck() (Legión Paladín) por cada carta EN JUEGO que coincida
	— busca solo en Línea de Defensa/Ataque/Apoyo del oponente (Aliados,
	Armas equipadas, Tótems; Oro excluido por el propio filtro del nombrado,
	no hace falta revisar Reserva/Oro Pagado). La segunda cláusula ('Cuando
	ataques, elige hasta dos Aliados con Furia...'):
	InPlayAbilities.estacion_fantasma_on_attack()."""
	var lower := ability_text.to_lower()
	if not ("nombra una carta que no sea oro" in lower and "tu oponente baraja las cartas que controle con ese nombre" in lower):
		return false
	if PlayerSideScript.is_bot(controller_id):
		return true  # el bot no sabe nombrar cartas (el Remoto sí)

	var picked: Dictionary = await _main._card_name_search.open_and_wait(
		"Nombra una carta que no sea Oro (tu oponente baraja las que controle con ese nombre)", controller_id)
	if picked.is_empty():
		return true
	var picked_name: String = str(picked.get("nombre", ""))
	if picked_name.is_empty() or int(picked.get("tipo", -1)) == Constants.CardType.ORO:
		return true

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card.get("card_name") else "Estación Fantasma", controller_id):
		return true

	var opponent_id: int = 1 - controller_id
	var opponent_fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if opponent_id == 0 else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
	var to_shuffle: Array = []
	for f in opponent_fields:
		if not f:
			continue
		for c in f.get_children():
			if str(c.get("card_name")) == picked_name:
				to_shuffle.append(c)
	for c in to_shuffle:
		# Sin await, shuffle_deck() corría antes de que return_to_deck()
		# terminara de insertar la carta en el mazo (espera la ventana de
		# Prevención real) — el barajado podía tocar un mazo que todavía no
		# tenía la carta devuelta.
		await ActionModule.return_to_deck(c, opponent_id, true, card)
	if not to_shuffle.is_empty():
		CardManager.shuffle_deck(opponent_id)
	return true


func try_execute_hangar_ciudadela_enter_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, tu oponente Baraja una carta de su mano y tú
	Robas dos cartas' (hangar de la ciudadela, "Kaiju vs Mecha - Titanes").
	Solo la cláusula de entrada. Las otras dos ('Los Aliados de coste o
	Fuerza 0 no pueden atacar ni disparar sus habilidades' y 'Si Botas esta
	carta desde tu Castillo por daño, dejas de Botar cartas y Destierra este
	Tótem') quedan pendientes a propósito: la primera necesita un bloqueo de
	ATAQUE (no solo de habilidades, que sí tiene precedente vía Tercer
	Sello) sin ningún gancho existente en la declaración de atacantes; la
	segunda es un reemplazo de efecto sobre daño-al-Castillo específico a
	ESTA carta (no una redirección genérica como arco del triunfo), y no
	alcanzó el tiempo para verificar con solidez el punto exacto donde
	`_check_damage_to_exile_effect`-adyacente resuelve qué cartas se botan
	por daño antes de interceptarlo ahí con seguridad."""
	var lower := ability_text.to_lower()
	if not ("tu oponente baraja una carta de su mano y t" in lower and "robas dos cartas" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	# La mano real del oponente (con datos reales, boca abajo si es el Remoto)
	# vive en player_hand si el oponente es el jugador 0, o en _opponent_fan si
	# es el jugador 1 — 'opponent_hand' no existe como propiedad en Main.gd. Se
	# devuelve al MAZO de datos (CardManager.get_deck), no vía ActionModule.
	# return_to_deck() (esa función asume una carta EN JUEGO, no en la mano).
	var opponent_id: int = 1 - controller_id
	var opponent_hand_hangar = main.player_hand if opponent_id == 0 else main._opponent_fan
	if EffectController.fision_hides_zones_of(opponent_id, controller_id, Constants.Zone.MANO):  # Fisión Nuclear
		opponent_hand_hangar = null
	if await EffectController.offer_colapso_global(controller_id):  # Colapso Global
		opponent_hand_hangar = null
	if opponent_hand_hangar:
		var hand_nodes: Array[Node] = opponent_hand_hangar.get_cards()
		if not hand_nodes.is_empty():
			var chosen_node: Node = hand_nodes[randi() % hand_nodes.size()]
			if is_instance_valid(chosen_node) and chosen_node.get("card_data") != null:
				var data: Dictionary = chosen_node.card_data.duplicate()
				opponent_hand_hangar.remove_card(chosen_node, true)
				CardManager.get_deck(opponent_id).append(data)
				CardManager.shuffle_deck(opponent_id)
	await ActionModule.draw(controller_id, 2, "hangar de la ciudadela", true)
	return true
