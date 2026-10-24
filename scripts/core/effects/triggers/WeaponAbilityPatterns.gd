extends RefCounted
## WeaponAbilityPatterns — patrones "try_execute_*_pattern" para Armas (auditoría de cartas sin
## cobertura, arquitectura.md). Mismo criterio que TotemAbilityPatterns.gd (detección por
## substring). El "el portador gana X" lo cubre GoldManager._register_weapon_strength_bonus(); aquí
## van las cláusulas adicionales (triggers de entrada/salida, habilidades de Vigilia/Fase Final).
## Instanciado en TriggerSystem._ready() como _weapon_patterns, llamado desde TriggerResolution.gd.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var _main: Node


func setup(main: Node) -> void:
	_main = main


# =============================================================================
# Cañón Naval ("Libertadores")
# =============================================================================
func try_execute_canon_naval_shared_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Cañón Naval: "Una vez por turno o cuando salga del juego, tu oponente Bota cinco cartas y
	Destierra hasta tres cartas de un Cementerio". Un efecto con dos disparadores: el cupo de "una
	vez por turno" (turn_registry) solo aplica al camino ACTIVADO; on_leave_play llama directo a
	_execute_canon_naval_effect().
	Está en el despachador compartido porque es una habilidad ACTIVADA
	(StackStepResolver._resolve_ability() aísla el texto); la guardia "el portador gana" (como
	sable corto) evita que se dispare en on_enter_play, que pasa el texto completo."""
	var lower := ability_text.to_lower()
	if not ("bota cinco cartas y destierra hasta tres cartas de un cementerio" in lower):
		return false
	if "el portador gana" in lower:
		return false
	if UniversalCardParser.turn_registry.was_used(str(card.get_instance_id()), 0, GameManager.turn_serial):
		return true
	UniversalCardParser.turn_registry.register(str(card.get_instance_id()), 0, GameManager.turn_serial)
	await _execute_canon_naval_effect(card, controller_id)
	return true


func try_execute_canon_naval_leave_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	var lower := ability_text.to_lower()
	if not ("bota cinco cartas y destierra hasta tres cartas de un cementerio" in lower):
		return false
	await _execute_canon_naval_effect(card, controller_id)
	return true


func _execute_canon_naval_effect(card: Node, controller_id: int) -> void:
	"""Ventana única para todo el efecto (mismo criterio que asedio naval en
	SearchOwnZonePatterns.gd) — la elección de QUÉ desterrar es interactiva y
	se recolecta ANTES, pero la ventana de respuesta se abre DESPUÉS de
	recolectar y ANTES de ejecutar cualquier parte del efecto (mill Y
	destierro), para que una Anulación/Cancelación pueda evitar las DOS
	partes, no solo la mitad que ya se hubiera ejecutado."""
	var main := _main.get_node_or_null("/root/Main")
	var picked: Array = []
	if main and main._zone_viewer:
		var no_filter := func(_c: Node) -> bool: return true
		picked = await main._zone_viewer.open_cemetery_target_picker(
			"Cañón Naval — Destierra hasta tres cartas de un Cementerio", no_filter, 3, "cemetery", true, false, controller_id)

	if await TriggerSystem.open_response_window(card, "Cañón Naval", controller_id):
		return

	var opponent_id: int = 1 - controller_id
	await ActionModule.mill(opponent_id, 5, false, "Cañón Naval", true)
	for entry in picked:
		var owner_of_picked: int = entry.owner_id
		var picked_data: Dictionary = entry.data
		if not CardManager.take_from_cemetery(owner_of_picked, picked_data):
			continue


func try_execute_canon_naval_final_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Cañón Naval: "En tu Fase Final, puedes Botar las primeras dos cartas de tu Castillo para
	agrupar un Oro". "Agrupar" se interpreta como "generar" un Oro, sin restricción de uso
	(predicado siempre verdadero).
	No está en el despachador compartido: se llama explícitamente desde la rama on_turn_end de
	TriggerResolution._execute_trigger_effect() con la cláusula aislada. En la lista compartida se
	probaría también en on_enter_play (texto completo) y dispararía al equipar."""
	var lower := ability_text.to_lower()
	if not ("botar las primeras dos cartas de tu castillo para agrupar un oro" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var deck: Array = CardManager.get_deck(controller_id)
	if deck.is_empty():
		return true
	var use_it: bool = await SelectionManager.await_two_choice(
		main, "¿Botar las primeras dos cartas de tu Castillo para generar un Oro?", "Sí", "No", controller_id)
	if not use_it:
		return true

	await ActionModule.mill(controller_id, 2, false, "Cañón Naval", true)
	var always_true := func(_t, _r, _c) -> bool: return true
	main._gold_manager.generar_oro_virtual_restringido(1, always_true, "Cañón Naval")
	return true


# =============================================================================
# flechar xoon ("Libertadores")
# =============================================================================
func try_execute_flechar_xoon_leave_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando salga del juego, puedes Desterrar una carta de coste 2 o menos' (flechar xoon). La otra
	cláusula adicional ('Una vez por turno, puedes subir una carta que controles a la mano de su
	dueño para Anular un Talismán o Tótem de coste 2 o menos') se implementó aparte en
	EffectController.offer_flechar_xoon_annul — no es un trigger propio de esta carta sino una
	reacción a que el RIVAL juegue algo, mismo mecanismo real de Almirante Akari
	(offer_counter_annul), así que vive en el mismo choke point que esa carta, no aquí."""
	var lower := ability_text.to_lower()
	if not ("cuando salga del juego, puedes desterrar una carta de coste 2 o menos" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var filter := func(c: Node) -> bool:
		if c.get("card_type") == Constants.CardType.ORO:
			return false
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, 2)
	var target: Node = await main._card_interaction.await_target(
		"flechar xoon: puedes Desterrar una carta de coste 2 o menos (N para no hacerlo)", filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return true
	await ActionModule.banish([target], card, true, true)
	return true


# =============================================================================
# sable corto ("Libertadores")
# =============================================================================
func try_execute_sable_corto_vigilia_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""sable corto: "En tu Vigilia, una vez por turno, tu oponente muestra tantas cartas del tope de
	su Castillo como Fuerza tenga un Aliado que controles y ponlas en su Cementerio". Habilidad
	ACTIVADA (camino compartido, como kotoku-in): elige un Aliado propio y el oponente Bota tantas
	como su Fuerza actual.
	Guardia "el portador gana": la lista compartida también se recorre en on_enter_play con el
	texto completo (que incluye "el portador gana 1 de fuerza e indesterrable"); sin la guardia,
	equipar sable corto dispararía esta elección."""
	var lower := ability_text.to_lower()
	if not ("tu oponente muestra tantas cartas del tope de su castillo como fuerza tenga un aliado que controles" in lower):
		return false
	if "el portador gana" in lower:
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var filter := func(c: Node) -> bool:
		if c.get("card_type") != Constants.CardType.ALIADO:
			return false
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		var owner: int = c.get("controller_id") if c.get("controller_id") != null else 0
		return owner == controller_id
	var chosen: Node = await main._card_interaction.await_target(
		"sable corto: elige un Aliado (tu oponente Bota tantas cartas como su Fuerza)", filter, true, controller_id)
	if not chosen or not is_instance_valid(chosen):
		return true
	var strength: int = ContinuousEffectManager.get_modified_strength(chosen)
	if strength <= 0:
		return true
	await ActionModule.mill(1 - controller_id, strength, false, "sable corto", true)
	return true


# =============================================================================
# nehushtan ("Bestiarium")
# =============================================================================
func try_execute_nehushtan_leave_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""nehushtan: "Cuando salga del juego, Roba dos cartas". "Si el portador está en Línea de
	Defensa los jugadores no pueden Desterrar cartas del Castillo de su oponente ni Botar cartas" es
	ProtectionRules.castle_banish_blocked() / mill_blocked(). Sin implementar:
	- "Puedes jugarla en Guerra de Talismanes": excepción de fase sobre sí misma;
	GoldManagerRestrictions._can_play_weapons_in_guerra_talismanes() solo cubre habilitadores
	generales como Lobo Sagrado."""
	var lower := ability_text.to_lower()
	if not ("cuando salga del juego, roba dos cartas" in lower):
		return false
	await ActionModule.draw(controller_id, 2, "nehushtan", true)
	return true


# =============================================================================
# azusa yumi ("Espíritu Samurái")
# =============================================================================
func try_execute_azusa_yumi_enter_leave_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""azusa yumi: "Cuando entra o salga del juego, tú Robas una carta y tu oponente Bota dos cartas"
	— el mismo texto para on_enter_play y on_leave_play (como arco del triunfo). El bono de Fuerza
	dinámico y el daño al Destierro están en GoldManager._register_weapon_strength_bonus()
	('azusa_rx'). "Puedes jugarla al comienzo de cualquier Fase" lo habilita PhaseStartWindow;
	"puedes tener más de tres copias" es de construcción de mazo."""
	var lower := ability_text.to_lower()
	if not ("cuando entra o salga del juego, t" in lower and "robas una carta" in lower and "bota dos cartas" in lower):
		return false
	await ActionModule.draw(controller_id, 1, "azusa yumi", true)
	await ActionModule.mill(1 - controller_id, 2, false, "azusa yumi", true)
	return true


# =============================================================================
# nodachi ("Espíritu Samurái")
# =============================================================================
func try_execute_nodachi_enter_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""nodachi: "Cuando entra en juego, mira la mano de tu oponente. Descarta de ahí hasta dos
	Talismanes cuyos costes sumen 2 o menos". "Los Talismanes cuestan un Oro adicional" está en
	GoldManager._register_weapon_talisman_tax() (estático mientras esté equipada). "Si el portador es
	de Raza Caballero, Guerrero y/o Héroe, gana 2 de Fuerza y no puede ser Barajado": StrengthAuras y
	ProtectionRules.cannot_be_shuffled()."""
	var lower := ability_text.to_lower()
	if not ("mira la mano de tu oponente" in lower and "descarta de ah" in lower and "talismanes cuyos costes sumen 2 o menos" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var opponent_id: int = 1 - controller_id
	var opponent_hand = main.player_hand if opponent_id == 0 else main._opponent_fan
	if EffectController.fision_hides_zones_of(opponent_id, controller_id, Constants.Zone.MANO):  # Fisión Nuclear
		opponent_hand = null
	if await EffectController.offer_colapso_global(controller_id):  # Colapso Global
		opponent_hand = null
	if not opponent_hand:
		return true
	var hand_nodes: Array = PlayerSideScript.hand_cards(main, opponent_id)  # DynamicHand no tiene get_cards()
	var talisman_nodes: Array = hand_nodes.filter(func(c: Node) -> bool:
		return is_instance_valid(c) and c.get("card_data") != null and int(c.card_data.get("tipo", -1)) == Constants.CardType.TALISMAN)
	if talisman_nodes.is_empty():
		return true

	if not main._card_interaction:
		return true
	var chosen: Array = await main._card_interaction.await_multi_target(
		"nodachi: elige hasta dos Talismanes de la mano rival cuyos costes sumen 2 o menos", talisman_nodes, 2, Callable(), Callable(), true, null, controller_id)
	var total_cost: int = 0
	var to_discard: Array = []
	for c in chosen:
		if not is_instance_valid(c) or c.get("card_data") == null:
			continue
		var c_cost: int = int(c.card_data.get("coste", 0))
		if total_cost + c_cost > 2:
			continue
		total_cost += c_cost
		to_discard.append(c)
	if to_discard.is_empty():
		return true
	if await TriggerSystem.open_response_window(card, "nodachi", controller_id):
		return true
	for c in to_discard:
		if is_instance_valid(c):
			opponent_hand.remove_card(c, true)
	return true


# =============================================================================
# Armadura Celestial ("Ángeles y Demonios: Vigilantes")
# =============================================================================
func try_execute_armadura_celestial_leave_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""Armadura Celestial: "Cuando esta Arma salga del juego, puedes Descartar una carta para ponerla
	en tu mano". "ponerla" = esta Arma: se recupera la propia Armadura del Cementerio a la mano
	pagando un descarte. Se resuelve cuando ya está en el Cementerio, así que no depende del orden
	de los eventos de salida.
	"Puedes Destruir el portador para Anular un Talismán de coste 2 o menos o cancelar la habilidad
	de una carta que afecte a un Aliado": InPlayAbilities.armadura_celestial() (botón)."""
	var lower := ability_text.to_lower()
	if not ("cuando esta arma salga del juego, puedes descartar una carta para ponerla en tu mano" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var hand_container = main.player_hand if controller_id == 0 else main._opponent_fan
	if not hand_container or hand_container.cards.is_empty():
		return true
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Armadura Celestial"
	var cemetery: Array = CardManager.get_cemetery(controller_id)
	var idx: int = -1
	for i in range(cemetery.size()):
		if str(cemetery[i].get("nombre", "")) == card_name:
			idx = i
			break
	if idx < 0:
		return true  # no está en el Cementerio (p.ej. desterrada en vez de destruida) — no hay de dónde recuperarla

	if not main._card_interaction:
		return true
	var hand_cards: Array = hand_container.cards.duplicate()
	var discard_filter := func(c: Node) -> bool: return c in hand_cards
	var to_discard: Node = await main._card_interaction.await_target(
		"%s: puedes Descartar una carta para recuperarla del Cementerio (N para no hacerlo)" % card_name, discard_filter, true, controller_id)
	if not to_discard or not is_instance_valid(to_discard):
		return true
	var discard_result: Dictionary = await ActionModule.discard(controller_id, [to_discard], card_name, true)
	if discard_result.get("actual", 0) <= 0:
		return true

	var refreshed_cemetery: Array = CardManager.get_cemetery(controller_id)
	var refreshed_idx: int = -1
	for i in range(refreshed_cemetery.size()):
		if str(refreshed_cemetery[i].get("nombre", "")) == card_name:
			refreshed_idx = i
			break
	if refreshed_idx < 0:
		return true
	var data: Dictionary = refreshed_cemetery[refreshed_idx]
	CardManager.remove_from_cemetery(controller_id, refreshed_idx)
	if main.has_method("_create_card"):
		var new_node = main._create_card(data, false)
		hand_container.add_card(new_node)
		main._connect_card_signals(new_node)
	return true
