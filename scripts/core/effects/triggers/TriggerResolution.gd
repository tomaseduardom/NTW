extends RefCounted
class_name TriggerResolution
## TriggerResolution — Saca triggers de la cola y los resuelve uno por uno
## (ventana de respuesta inmediata + ejecución del efecto, con fallback a
## extract_action() si la carta no tiene handler propio). Opera sobre
## TriggerSystem via _main (cola compartida, señales).
## Extraído de TriggerSystem.gd (Fase 4 de reestructuración).

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")  # detector de paridad (§56)
const TalismanSearchScript = preload("res://scripts/core/effects/triggers/TalismanSearchPatterns.gd")
const Deck170Script = preload("res://scripts/core/effects/triggers/Deck170Patterns.gd")
const AziScript = preload("res://scripts/core/effects/triggers/AziPatterns.gd")
const DagonScript = preload("res://scripts/core/effects/triggers/DagonPatterns.gd")
const RatPlagueScript = preload("res://scripts/core/effects/triggers/RatPlaguePatterns.gd")
const CemeteryReviveScript = preload("res://scripts/core/effects/triggers/CemeteryRevivePatterns.gd")
const VampireScript = preload("res://scripts/core/effects/triggers/VampirePatterns.gd")
const NoeScript = preload("res://scripts/core/effects/triggers/NoePatterns.gd")
const TriggerTollScript = preload("res://scripts/core/effects/triggers/TriggerTollPatterns.gd")
const BlockScript = preload("res://scripts/core/effects/triggers/BlockPatterns.gd")
const TurnStartScript = preload("res://scripts/core/effects/mechanics/TurnStartPatterns.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")
const LeavePlayScript = preload("res://scripts/core/effects/triggers/LeavePlayPatterns.gd")
const AttackScript = preload("res://scripts/core/effects/mechanics/AttackPatterns.gd")
const EnterScript = preload("res://scripts/core/effects/mechanics/EnterPatterns.gd")
const TalismanScript = preload("res://scripts/core/effects/mechanics/TalismanPatterns.gd")
const ActivatedScript = preload("res://scripts/core/effects/mechanics/ActivatedPatterns.gd")
const CastleLookScript = preload("res://scripts/core/effects/CastleLook.gd")  # "mira N cartas" (§69)

var _main: Node


const LOOK_AND_PLAY_LABELS := ["Deck170Script.try_annul_on_stack", "TalismanScript.try_execute", "ActivatedScript.try_execute", "AziScript.try_execute", "DagonScript.try_execute", "RatPlagueScript.try_execute", "CemeteryReviveScript.try_execute", "VampireScript.try_execute", "NoeScript.try_execute", "MechanicPatterns.try_execute", "draw_shuffle_resolver.try_execute_golpe_solar_pattern", "draw_shuffle_resolver.try_execute_shuffle_ally_or_search_castle_pattern", "effect_interpreter.try_execute", "CastleLookScript.try_execute_text", "TalismanSearchScript.try_execute", "Deck170Script.try_execute", "totem_patterns.try_execute_kotoku_in_vigilia_pattern", "totem_patterns.try_execute_metropolitan_vigilia_convert_pattern", "totem_patterns.try_execute_iga_ryu_convert_totems_pattern", "totem_patterns.try_execute_rueda_fortuna_reveal_pattern", "totem_patterns.try_execute_rueda_fortuna_sacrifice_pattern", "totem_patterns.try_execute_estacion_fantasma_name_pattern", "weapon_patterns.try_execute_canon_naval_shared_pattern", "weapon_patterns.try_execute_sable_corto_vigilia_pattern", "oro_patterns.try_execute_udjat_vigilia_pattern", "oro_patterns.try_execute_libro_de_thoth_pay_pattern", "look_and_play.try_execute_look_pick_pattern", "look_and_play.try_execute_look_play_free_pattern", "look_and_play.try_execute_look_play_or_hand_pattern", "look_and_play.try_execute_look_play_or_gold_pattern", "look_and_play.try_execute_look_dynamic_gold_count_pattern", "look_and_play.try_execute_look_two_hand_convert_gold_pattern", "look_and_play.try_execute_shuffle_or_draw_choice_pattern", "look_and_play.try_execute_convert_then_reveal_until_same_type_pattern", "look_and_play.try_execute_search_oro_castillo_or_cementerio_pattern", "look_and_play.try_execute_search_up_to_n_castillo_and_or_cementerio_play_discount_pattern", "look_and_play.try_execute_reveal_until_ally_and_gold_pattern", "look_and_play.try_execute_reveal_until_weapon_or_totem_and_ally_pattern", "look_and_play.try_execute_reveal_until_three_cost1_allies_play_one_pattern", "look_and_play.try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern", "look_and_play.try_execute_play_cemetery_ally_free_or_draw_three_pattern", "look_and_play.try_execute_gain_control_ally_rename_titan_pattern", "look_and_play.try_execute_shuffle_non_gold_or_draw_two_pattern", "look_and_play.try_execute_reveal_gold_weapon_totem_split_pattern", "look_and_play.try_execute_play_cemetery_ally_discounted_min1_pattern", "look_and_play.try_execute_gold_for_allies_until_next_turn_pattern", "look_and_play.try_execute_gold_for_allies_or_weapons_pattern", "look_and_play.try_execute_search_each_castillo_two_to_cemetery_pattern", "look_and_play.try_execute_draw_then_discard_pattern", "look_and_play.try_execute_shuffle_up_to_one_ally_pattern", "look_and_play.try_execute_reveal_until_ally_and_weapon_pattern", "look_and_play.try_execute_reveal_until_ally_and_talisman_pattern", "look_and_play.try_execute_search_two_distinct_names_banish_or_cemetery_pattern", "look_and_play.try_execute_convert_gold_or_opponent_cost_max_draw_pattern", "look_and_play.try_execute_draw_or_raise_cemetery_ally_pattern", "look_and_play.try_execute_shuffle_or_banish_opponent_cost_max_pattern", "look_and_play.try_execute_shuffle_banish_cemeteries_then_destroy_or_draw_pattern", "look_and_play.try_execute_draw_discard_opponent_mill_exile_pattern", "look_and_play.try_execute_opponent_mill_four_pattern", "look_and_play.try_execute_annul_cost_max_pattern", "look_and_play.try_execute_reveal_gold_to_pagado_weapon_or_totem_to_hand_pattern", "look_and_play.try_execute_name_reveal_until_match_then_gold_to_pagado_pattern", "look_and_play.try_execute_convert_two_top_castillo_to_allies_pattern", "look_and_play.try_execute_shuffle_banish_four_cemeteries_pattern", "look_and_play.try_execute_search_castillo_or_cemetery_to_pagado_pattern", "look_and_play.try_execute_annul_non_ally_banish_or_cancel_ability_pattern", "look_and_play.try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern", "look_and_play.try_execute_shuffle_any_cemetery_or_exile_into_castillo_then_draw_pattern", "look_and_play.try_execute_search_three_opponent_castillo_banish_draw_pattern", "look_and_play.try_execute_peek_hand_banish_search_castillo_cemetery_draw_pattern", "look_and_play.try_execute_raise_same_type_gold_and_search_banish_pattern", "look_and_play.try_execute_raise_up_to_one_ally_or_gold_from_cemetery_pattern", "look_and_play.try_execute_shuffle_cost_max_two_draw_two_pattern", "look_and_play.try_execute_shuffle_cost_max_three_pattern", "look_and_play.try_execute_bubble_protection_and_schedule_final_phase_pattern", "look_and_play.try_execute_opponent_mill_six_exile_pattern", "look_and_play.try_execute_banish_opponent_castillo_by_titan_ignis_cost_draw_pattern", "look_and_play.try_execute_pay_x_banish_opponent_castillo_draw_per_talisman_totem_pattern", "look_and_play.try_execute_shuffle_one_in_play_and_four_cemetery_pattern", "look_and_play.try_execute_banish_opponent_cost_sum_six_pattern", "look_and_play.try_execute_transformacion_pattern", "look_and_play.try_execute_search_azi_ally_to_hand_pattern", "look_and_play.try_execute_opponent_hand_cost_max_to_bottom_pattern", "look_and_play.try_execute_titan_abismal_conditional_play_or_draw_pattern", "look_and_play.try_execute_annul_then_shuffle_hand_by_cost_pattern", "look_and_play.try_execute_banish_two_from_one_cemetery_then_draw_pattern", "look_and_play.try_execute_draw_or_search_ally_or_gold_pattern", "look_and_play.try_execute_optional_search_totem_castillo_pattern", "look_and_play.try_execute_malleus_name_lock_pattern", "look_and_play.try_execute_espiritu_maquina_conditional_gold_pattern", "look_and_play.try_execute_banish_cost_or_search_two_banish_pattern", "look_and_play.try_execute_look_opponent_hand_discard_then_search_ally_pattern", "look_and_play.try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern", "draw_shuffle_resolver.try_execute_each_player_discard_then_draw_pattern", "draw_shuffle_resolver.try_execute_draw_gold_search_pattern", "draw_shuffle_resolver.try_execute_draw_reveal_talisman_gold_pattern", "draw_shuffle_resolver.try_execute_deck_top_or_bottom_to_hand_pattern", "draw_shuffle_resolver.try_execute_shuffle_exile_and_draw_pattern", "draw_shuffle_resolver.try_execute_shuffle_hand_and_draw_plus_two_pattern", "convert_misc_resolver.try_execute_mill_convert_to_ally_pattern", "draw_shuffle_resolver.try_execute_tempilcahue_choice_pattern", "draw_shuffle_resolver.try_execute_golpe_solar_pattern#2", "draw_shuffle_resolver.try_execute_shuffle_hand_then_draw_pattern", "draw_shuffle_resolver.try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern", "look_and_play.try_execute_reveal_until_distinct_cost_allies_pattern", "look_and_play.try_execute_search_ally_castillo_or_cementerio_then_buff_pattern", "look_and_play.try_execute_search_ally_cost_max_free_play_pattern", "look_and_play.try_execute_cain_damage_shuffle_search_pattern", "look_and_play.try_execute_search_two_oros_split_destination_pattern", "look_and_play.try_execute_primer_sello_pattern", "look_and_play.try_execute_segundo_sello_pattern", "look_and_play.try_execute_tercer_sello_pattern", "look_and_play.try_execute_cuarto_sello_pattern", "look_and_play.try_execute_quinto_sello_pattern", "look_and_play.try_execute_sexto_sello_pattern", "look_and_play.try_execute_septimo_sello_pattern", "convert_misc_resolver.try_execute_name_a_card_pattern", "convert_misc_resolver.try_execute_no_allies_convert_castillo_top_pattern", "convert_misc_resolver.try_execute_jabberwocky_convert_opponent_top_pattern", "convert_misc_resolver.try_execute_opponent_discard_and_draw_pattern", "draw_shuffle_resolver.try_execute_banish_from_cemeteries_and_draw_pattern", "draw_shuffle_resolver.try_execute_weapon_count_banish_cemetery_pattern", "draw_shuffle_resolver.try_execute_vigilia_or_final_banish_opponent_cemetery_pattern", "draw_shuffle_resolver.try_execute_shuffle_up_to_n_cemeteries_pattern", "draw_shuffle_resolver.try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern", "draw_shuffle_resolver.try_execute_banish_up_to_n_cemeteries_pattern", "draw_shuffle_resolver.try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern", "draw_shuffle_resolver.try_execute_banish_cemeteries_equal_to_own_strength_pattern", "draw_shuffle_resolver.try_execute_draw_and_shuffle_hand_pattern", "draw_shuffle_resolver.try_execute_draw_and_shuffle_opponent_card_pattern", "convert_misc_resolver.try_execute_banish_top_by_ally_count_and_draw_pattern", "analizador_viejo.extract_action"]


## Registro de qué rama resolvió cada texto (tools/probe_handlers.gd lo enciende para encontrar handlers que
## ninguna carta usa). Apagado en el juego.
var trace_enabled: bool = false
var trace: Dictionary = {}
var last_hit: String = ""
## Textos exactos que llegaron al analizador viejo (tools/old_parser_report.tscn los clasifica).
var old_parser_texts: Array = []


func _hit(label: String) -> bool:
	if trace_enabled:
		trace[label] = int(trace.get(label, 0)) + 1
		last_hit = label
	return true


func trace_labels() -> Array:
	"""Todas las ramas de _resolve_look_and_play_patterns(), en orden."""
	return LOOK_AND_PLAY_LABELS

func setup(main: Node) -> void:
	_main = main


func resolve_next_trigger() -> Dictionary:
	"""Resuelve el siguiente trigger en la cola con ventana de respuesta
	DAR Sección 8: Permite cancelación antes de resolver
	Returns: El trigger resuelto o {} si no hay más
	"""
	if _main.trigger_queue.is_empty():
		_main.is_resolving = false
		_main.emit_signal("all_triggers_resolved")
		return {}

	_main.is_resolving = true
	var trigger = _main.trigger_queue.pop_front()

	var card: Node = trigger.card
	var trigger_type: String = trigger.trigger_type
	var event_data: Dictionary = trigger.event_data
	var controller_id: int = trigger.get("controller_id", 0)

	# Verificar que la carta sigue en juego
	if not is_instance_valid(card):
		print("[TriggerSystem] Carta ya no existe, saltando trigger")
		return await resolve_next_trigger()

	if not card.is_in_play():
		print("[TriggerSystem] %s ya no está en juego, saltando trigger" % card.card_name)
		return await resolve_next_trigger()

	# Verificar si un efecto continuo negativo bloquea este trigger
	if _main._restrictions.is_blocked_by_continuous_effect(card, trigger_type):
		print("[TriggerSystem] %s bloqueado por efecto continuo" % trigger_type)
		return await resolve_next_trigger()

	# === PASO D: VENTANA DE RESPUESTA (DAR Sección 8 - Cancelar) ===
	var opponent_id = 1 - controller_id
	_main.current_trigger_for_response = trigger
	_main.awaiting_response = true

	print("[TriggerSystem] Resolviendo trigger: %s" % card.card_name)
	# waiting_for_responses ya no se emite: Signo Amarillo se ofrece por
	# ResponseWindowHandler._offer_signo_amarillo_for_step_d(), que escucha
	# ActionPipeline.step_d_waiting (emitida por open_response_window() para cualquier objeto de la
	# Pila). ResponseWindowHandler._on_trigger_waiting_for_responses() queda sin emisor (§10.53).

	# Pila de Respuesta Universal (§10.53): todo trigger da al rival (humano o bot) una ventana real,
	# con el mismo Paso D, brillo/botón de Anular (§10.51) y auto-pase (§10.52) que cualquier carta
	# jugada.
	# El rival responde después de que se declaran los objetivos (§59): el efecto arranca con la
	# ventana "pendiente" en EffectContext; la abre el patrón tras declarar (open_response_window()) o,
	# si no la pide, EffectContext.ensure_window() antes de su primera acción real. Así el rival no
	# pasa varias veces por la misma carta.

	# === RESOLVER "EN MEDIDA DE LO POSIBLE" (DAR Sección 8) ===
	print("[TriggerSystem] Resolviendo: %s de %s" % [trigger_type, card.card_name])

	# awaiting_response sigue en true durante todo el efecto: la ventana que el patrón abre por dentro
	# queda bajo la guardia de PhaseFlowController._on_priority_both_passed_main() ("ventana anidada de
	# un trigger"). Si se apagaba antes, el "ambos pasaron" de esa ventana llegaba al fin de fase y
	# resolvía dos veces.
	# Matriz V: las habilidades de cartas de coste 0 o 1 del rival solo se disparan si Destierra una
	# carta de su mano.
	if await Deck170Script.matriz_v_blocks_trigger(card, controller_id):
		_main.awaiting_response = false
		return await resolve_next_trigger()
	# Mecha-Daikaiju: pagar un Oro para usar habilidades disparadas.
	if await TriggerTollScript.blocks_trigger(card, controller_id):
		_main.awaiting_response = false
		return await resolve_next_trigger()
	var ctx_token: int = EffectContextScript.push(card, controller_id, "disparada", "pending")
	var result = await _execute_trigger_effect(card, trigger_type, event_data)
	var window_state: String = EffectContextScript.window_state(ctx_token)
	EffectContextScript.pop(ctx_token)
	var was_cancelled: bool = window_state == "cancelled"
	if was_cancelled:
		_main.awaiting_response = false
		_main.emit_signal("response_window_closed", trigger, true)
		print("[TriggerSystem] %s de %s fue CANCELADO" % [trigger_type, card.card_name if is_instance_valid(card) else "?"])
		_main.emit_signal("trigger_cancelled", card, trigger_type, null)
		return await resolve_next_trigger()
	if window_state == "pending":
		# Ninguna acción pasó por un punto vigilado (ActionModule, Oros,
		# jugar gratis): o el efecto no hizo nada ("puedes" rechazado, sin
		# objetivos), o un patrón mueve cartas por su cuenta — en ese caso
		# conviene que pida su ventana con open_response_window().
		print("[TriggerSystem] %s de %s: resuelto sin ventana de respuesta" % [
			trigger_type, card.card_name if is_instance_valid(card) else "?"])
	result["card"] = card
	result["type"] = trigger_type

	_main.awaiting_response = false
	_main.emit_signal("response_window_closed", trigger, was_cancelled)
	_main.emit_signal("trigger_resolved", card, trigger_type, result)

	return trigger


func cancel_current_trigger(cancelling_card: Node = null) -> bool:
	"""Cancela el trigger actual en la ventana de respuesta
	Llamado cuando el oponente usa una habilidad de cancelación
	"""
	if not _main.awaiting_response:
		return false

	if _main.current_trigger_for_response.is_empty():
		return false

	_main.pending_cancel_callback = func(): pass  # Flag para indicar cancelación
	var card = _main.current_trigger_for_response.get("card")
	var trigger_type = _main.current_trigger_for_response.get("trigger_type", "")

	print("[TriggerSystem] Cancelando %s con %s" % [
		trigger_type,
		cancelling_card.card_name if cancelling_card else "efecto"
	])

	_main.emit_signal("trigger_cancelled", card, trigger_type, cancelling_card)
	return true


func pass_response() -> void:
	"""El jugador pasa su oportunidad de responder"""
	_main.awaiting_response = false


## Condiciones de "Cuando ataque/ataques" que el compilador no ve (las quita como parte del disparador):
## - "con un sólo Aliado" / "cuando ataque solo": un único atacante (kaihime, arturo prat, uriko-hime);
## - "por primera vez en el juego": una vez por carta (toyotomi hideyoshi); fasolt, además, "si porta
## Armas".
func _attack_condition_met(card: Node, clause: String) -> bool:
	var t := CemeteryTriggersScript.normalize(clause)
	if ("con un solo aliado" in t or "ataque solo" in t or "ataca solo" in t) and GameManager.attackers.size() != 1:
		return false
	if "si porta armas" in t:
		var weapons = card.get("equipped_weapons")
		if not (weapons is Array) or not weapons.any(func(w): return is_instance_valid(w)):
			return false
	if "por primera vez en el juego" in t:
		if card.has_meta("first_attack_done"):
			return false
		card.set_meta("first_attack_done", true)
	return true


## El bloque de "entra en juego o ataca" (todas sus oraciones hasta el próximo disparador), o la
## oración sola si no es uno de esos.
func _attack_block(full_text: String, clause: String) -> String:
	var blocks: Array[String] = _isolate_all_trigger_clauses(full_text, ["en juego o ataque", "en juego o ataca"])
	return blocks[0] if not blocks.is_empty() and clause in blocks[0] else clause


func _resolve_look_and_play_patterns(card: Node, full_ability_text: String, isolated_ability_text: String, controller_id: int, event_data: Dictionary) -> bool:
	"""Prueba en orden los patrones compuestos "muestra/mira N..." (cada uno con su regex, sobre el
	texto completo) y, si ninguno calza, el genérico extract_action() + execute_parsed_action()
	sobre el texto aislado. Compartido por las habilidades disparadas y por los Talismanes
	(TriggerSystem.resolve_talisman(): los Talismanes no disparan, resuelven). Devuelve true si
	algo se ejecutó."""
	# Efecto compilado por piezas (arquitectura.md §54): si EffectCompiler entiende todo el texto
	# aislado y EffectInterpreter sabe ejecutar todos sus pasos, se resuelve por ahí. Va primero porque
	# la cadena vieja busca sobre el texto completo y la primera coincidencia puede quedarse con solo
	# una parte del efecto.
	# Anular/Cancelar sobre la pila real (StackAnnul) va antes que todo: si no, "Anula X" caía en
	# patrones que destruían una carta en juego (Sacrificio Solar barajaba el mazo).
	if card and card.get("card_type") == Constants.CardType.TALISMAN \
			and await Deck170Script.try_annul_on_stack(card, full_ability_text, controller_id):
		return _hit("Deck170Script.try_annul_on_stack")
	# Talismanes sueltos armados con piezas existentes (caminar el tablón, el juicio, momificar...).
	if card and card.get("card_type") == Constants.CardType.TALISMAN \
			and await TalismanScript.try_execute(card, full_ability_text, controller_id):
		return _hit("TalismanScript.try_execute")
	# Habilidades activadas sueltas armadas con piezas existentes (el emperador, kultrung, animita...).
	if card and card.get("card_type") != Constants.CardType.TALISMAN 			and await ActivatedScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("ActivatedScript.try_execute")
	# Azi del Abismo: Descartar para convertirse en Oro hasta tu próximo turno. Antes del intérprete,
	# que solo veía "Descarta una".
	if await AziScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("AziScript.try_execute")
	# Padre Dagón: la mitad activada, global.
	if await DagonScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("DagonScript.try_execute")
	# Plaga de Ratas.
	if await RatPlagueScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("RatPlagueScript.try_execute")
	# Kaitai: su habilidad de Fase Final.
	if await CemeteryReviveScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("CemeteryReviveScript.try_execute")
	# Vlad el Empalador, Dhampir.
	if await VampireScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("VampireScript.try_execute")
	# Noé.
	if await NoeScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("NoeScript.try_execute")
	# Mazos guardados: Aegishjalmur...
	if await load("res://scripts/core/effects/mechanics/MechanicPatterns.gd").try_execute(card, isolated_ability_text, controller_id):
		return _hit("MechanicPatterns.try_execute")
	# Golpe Solar: antes del intérprete (que lo resolvía en el orden impreso). Primero elige el
	# objetivo a Barajar, luego el descarte y el Aliado.
	if await _main._draw_shuffle_resolver.try_execute_golpe_solar_pattern(full_ability_text, card, controller_id):
		return _hit("draw_shuffle_resolver.try_execute_golpe_solar_pattern")
	# Sombrerero Loco: elección en el tablero, sin popup. Antes del intérprete, que la compila como
	# "A o B" con popup.
	if await _main._draw_shuffle_resolver.try_execute_shuffle_ally_or_search_castle_pattern(isolated_ability_text, card, controller_id):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_ally_or_search_castle_pattern")
	if await _main._effect_interpreter.try_execute(card, isolated_ability_text, controller_id):
		return _hit("effect_interpreter.try_execute")
	# "Mira N cartas del tope/fondo de un Castillo" (§69): una sola ventana para repartir y ordenar
	# (CastleLook.gd). Solo si entiende todo el bloque.
	if await CastleLookScript.try_execute_text(card, isolated_ability_text, controller_id):
		return _hit("CastleLookScript.try_execute_text")
	# "Busca un Talismán en un Castillo y juégalo" (Reina Nyssara, Nyssara Cautiva).
	if await TalismanSearchScript.try_execute(card, isolated_ability_text, controller_id):
		return _hit("TalismanSearchScript.try_execute")
	# Mazo 170: Rey de los Loñolicos, Ursitoare, Nyssara Cautiva...
	if await Deck170Script.try_execute(card, isolated_ability_text, controller_id):
		return _hit("Deck170Script.try_execute")
	# Habilidades activadas de Tótems: llegan aquí también vía TriggerSystem.resolve_ability_effect()
	# (camino compartido con los triggers), así que se chequean primero.
	if await _main._totem_patterns.try_execute_kotoku_in_vigilia_pattern(full_ability_text, card, controller_id):
		return _hit("totem_patterns.try_execute_kotoku_in_vigilia_pattern")
	if await _main._totem_patterns.try_execute_metropolitan_vigilia_convert_pattern(full_ability_text, card, controller_id):
		return _hit("totem_patterns.try_execute_metropolitan_vigilia_convert_pattern")
	# Solo con el texto aislado de la activada: el texto completo también lo trae el "cuando entra".
	if await _main._totem_patterns.try_execute_iga_ryu_convert_totems_pattern(isolated_ability_text, card, controller_id):
		return _hit("totem_patterns.try_execute_iga_ryu_convert_totems_pattern")
	if await _main._totem_patterns.try_execute_rueda_fortuna_reveal_pattern(full_ability_text, card, controller_id):
		return _hit("totem_patterns.try_execute_rueda_fortuna_reveal_pattern")
	if await _main._totem_patterns.try_execute_rueda_fortuna_sacrifice_pattern(full_ability_text, card, controller_id):
		return _hit("totem_patterns.try_execute_rueda_fortuna_sacrifice_pattern")
	if await _main._totem_patterns.try_execute_estacion_fantasma_name_pattern(full_ability_text, card, controller_id):
		return _hit("totem_patterns.try_execute_estacion_fantasma_name_pattern")
	# Habilidades activadas de Armas: mismo camino que las de Tótems; cada una con su guardia "el
	# portador gana" contra el falso positivo de on_enter_play (WeaponAbilityPatterns.gd).
	if await _main._weapon_patterns.try_execute_canon_naval_shared_pattern(full_ability_text, card, controller_id):
		return _hit("weapon_patterns.try_execute_canon_naval_shared_pattern")
	if await _main._weapon_patterns.try_execute_sable_corto_vigilia_pattern(full_ability_text, card, controller_id):
		return _hit("weapon_patterns.try_execute_sable_corto_vigilia_pattern")
	# Habilidades activadas de Oros: mismo camino; cada una con su guardia de texto contra el falso
	# positivo de on_enter_play/on_turn_end (OroAbilityPatterns.gd).
	if await _main._oro_patterns.try_execute_udjat_vigilia_pattern(full_ability_text, card, controller_id):
		return _hit("oro_patterns.try_execute_udjat_vigilia_pattern")
	if await _main._oro_patterns.try_execute_libro_de_thoth_pay_pattern(full_ability_text, card, controller_id):
		return _hit("oro_patterns.try_execute_libro_de_thoth_pay_pattern")
	if await _main._look_and_play.try_execute_look_pick_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_look_pick_pattern")
	if await _main._look_and_play.try_execute_look_play_free_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_look_play_free_pattern")
	if await _main._look_and_play.try_execute_look_play_or_hand_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_look_play_or_hand_pattern")
	if await _main._look_and_play.try_execute_look_play_or_gold_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_look_play_or_gold_pattern")
	if await _main._look_and_play.try_execute_look_dynamic_gold_count_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_look_dynamic_gold_count_pattern")
	if await _main._look_and_play.try_execute_look_two_hand_convert_gold_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_look_two_hand_convert_gold_pattern")
	if await _main._look_and_play.try_execute_shuffle_or_draw_choice_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_shuffle_or_draw_choice_pattern")
	if await _main._look_and_play.try_execute_convert_then_reveal_until_same_type_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_convert_then_reveal_until_same_type_pattern")
	if await _main._look_and_play.try_execute_search_oro_castillo_or_cementerio_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_oro_castillo_or_cementerio_pattern")
	if await _main._look_and_play.try_execute_search_up_to_n_castillo_and_or_cementerio_play_discount_pattern(
			full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_up_to_n_castillo_and_or_cementerio_play_discount_pattern")
	if await _main._look_and_play.try_execute_reveal_until_ally_and_gold_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_until_ally_and_gold_pattern")
	if await _main._look_and_play.try_execute_reveal_until_weapon_or_totem_and_ally_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_until_weapon_or_totem_and_ally_pattern")
	if await _main._look_and_play.try_execute_reveal_until_three_cost1_allies_play_one_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_until_three_cost1_allies_play_one_pattern")
	if await _main._look_and_play.try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern")
	if await _main._look_and_play.try_execute_play_cemetery_ally_free_or_draw_three_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_play_cemetery_ally_free_or_draw_three_pattern")
	if await _main._look_and_play.try_execute_gain_control_ally_rename_titan_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_gain_control_ally_rename_titan_pattern")
	if await _main._look_and_play.try_execute_shuffle_non_gold_or_draw_two_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_shuffle_non_gold_or_draw_two_pattern")
	if await _main._look_and_play.try_execute_reveal_gold_weapon_totem_split_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_gold_weapon_totem_split_pattern")
	if await _main._look_and_play.try_execute_play_cemetery_ally_discounted_min1_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_play_cemetery_ally_discounted_min1_pattern")
	if await _main._look_and_play.try_execute_gold_for_allies_until_next_turn_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_gold_for_allies_until_next_turn_pattern")
	if await _main._look_and_play.try_execute_gold_for_allies_or_weapons_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_gold_for_allies_or_weapons_pattern")
	if await _main._look_and_play.try_execute_search_each_castillo_two_to_cemetery_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_each_castillo_two_to_cemetery_pattern")
	if await _main._look_and_play.try_execute_draw_then_discard_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_draw_then_discard_pattern")
	if await _main._look_and_play.try_execute_shuffle_up_to_one_ally_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_shuffle_up_to_one_ally_pattern")
	if await _main._look_and_play.try_execute_reveal_until_ally_and_weapon_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_until_ally_and_weapon_pattern")
	if await _main._look_and_play.try_execute_reveal_until_ally_and_talisman_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_until_ally_and_talisman_pattern")
	if await _main._look_and_play.try_execute_search_two_distinct_names_banish_or_cemetery_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_two_distinct_names_banish_or_cemetery_pattern")
	if await _main._look_and_play.try_execute_convert_gold_or_opponent_cost_max_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_convert_gold_or_opponent_cost_max_draw_pattern")
	if await _main._look_and_play.try_execute_draw_or_raise_cemetery_ally_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_draw_or_raise_cemetery_ally_pattern")
	if await _main._look_and_play.try_execute_shuffle_or_banish_opponent_cost_max_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_shuffle_or_banish_opponent_cost_max_pattern")
	if await _main._look_and_play.try_execute_shuffle_banish_cemeteries_then_destroy_or_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_shuffle_banish_cemeteries_then_destroy_or_draw_pattern")
	if await _main._look_and_play.try_execute_draw_discard_opponent_mill_exile_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_draw_discard_opponent_mill_exile_pattern")
	if await _main._look_and_play.try_execute_opponent_mill_four_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_opponent_mill_four_pattern")
	if await _main._look_and_play.try_execute_annul_cost_max_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_annul_cost_max_pattern")
	if await _main._look_and_play.try_execute_reveal_gold_to_pagado_weapon_or_totem_to_hand_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_gold_to_pagado_weapon_or_totem_to_hand_pattern")
	if await _main._look_and_play.try_execute_name_reveal_until_match_then_gold_to_pagado_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_name_reveal_until_match_then_gold_to_pagado_pattern")
	if await _main._look_and_play.try_execute_convert_two_top_castillo_to_allies_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_convert_two_top_castillo_to_allies_pattern")
	if await _main._look_and_play.try_execute_shuffle_banish_four_cemeteries_pattern(full_ability_text, controller_id):
		return _hit("look_and_play.try_execute_shuffle_banish_four_cemeteries_pattern")
	if await _main._look_and_play.try_execute_search_castillo_or_cemetery_to_pagado_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_castillo_or_cemetery_to_pagado_pattern")
	if await _main._look_and_play.try_execute_annul_non_ally_banish_or_cancel_ability_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_annul_non_ally_banish_or_cancel_ability_pattern")
	if await _main._look_and_play.try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern")
	if await _main._look_and_play.try_execute_shuffle_any_cemetery_or_exile_into_castillo_then_draw_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_shuffle_any_cemetery_or_exile_into_castillo_then_draw_pattern")
	if await _main._look_and_play.try_execute_search_three_opponent_castillo_banish_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_three_opponent_castillo_banish_draw_pattern")
	if await _main._look_and_play.try_execute_peek_hand_banish_search_castillo_cemetery_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_peek_hand_banish_search_castillo_cemetery_draw_pattern")
	if await _main._look_and_play.try_execute_raise_same_type_gold_and_search_banish_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_raise_same_type_gold_and_search_banish_pattern")
	if await _main._look_and_play.try_execute_raise_up_to_one_ally_or_gold_from_cemetery_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_raise_up_to_one_ally_or_gold_from_cemetery_pattern")
	if await _main._look_and_play.try_execute_shuffle_cost_max_two_draw_two_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_shuffle_cost_max_two_draw_two_pattern")
	if await _main._look_and_play.try_execute_shuffle_cost_max_three_pattern(full_ability_text, controller_id):
		return _hit("look_and_play.try_execute_shuffle_cost_max_three_pattern")
	if await _main._look_and_play.try_execute_bubble_protection_and_schedule_final_phase_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_bubble_protection_and_schedule_final_phase_pattern")
	if await _main._look_and_play.try_execute_opponent_mill_six_exile_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_opponent_mill_six_exile_pattern")
	if await _main._look_and_play.try_execute_banish_opponent_castillo_by_titan_ignis_cost_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_banish_opponent_castillo_by_titan_ignis_cost_draw_pattern")
	if await _main._look_and_play.try_execute_pay_x_banish_opponent_castillo_draw_per_talisman_totem_pattern(full_ability_text, controller_id):
		return _hit("look_and_play.try_execute_pay_x_banish_opponent_castillo_draw_per_talisman_totem_pattern")
	if await _main._look_and_play.try_execute_shuffle_one_in_play_and_four_cemetery_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_shuffle_one_in_play_and_four_cemetery_pattern")
	if await _main._look_and_play.try_execute_banish_opponent_cost_sum_six_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_banish_opponent_cost_sum_six_pattern")
	if await _main._look_and_play.try_execute_transformacion_pattern(full_ability_text, controller_id):
		return _hit("look_and_play.try_execute_transformacion_pattern")
	if await _main._look_and_play.try_execute_search_azi_ally_to_hand_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_search_azi_ally_to_hand_pattern")
	if await _main._look_and_play.try_execute_opponent_hand_cost_max_to_bottom_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_opponent_hand_cost_max_to_bottom_pattern")
	if await _main._look_and_play.try_execute_titan_abismal_conditional_play_or_draw_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_titan_abismal_conditional_play_or_draw_pattern")
	if await _main._look_and_play.try_execute_annul_then_shuffle_hand_by_cost_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_annul_then_shuffle_hand_by_cost_pattern")
	if await _main._look_and_play.try_execute_banish_two_from_one_cemetery_then_draw_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_banish_two_from_one_cemetery_then_draw_pattern")
	if await _main._look_and_play.try_execute_draw_or_search_ally_or_gold_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_draw_or_search_ally_or_gold_pattern")
	if await _main._look_and_play.try_execute_optional_search_totem_castillo_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_optional_search_totem_castillo_pattern")
	if await _main._look_and_play.try_execute_malleus_name_lock_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_malleus_name_lock_pattern")
	if await _main._look_and_play.try_execute_espiritu_maquina_conditional_gold_pattern(full_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_espiritu_maquina_conditional_gold_pattern")
	if await _main._look_and_play.try_execute_banish_cost_or_search_two_banish_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_banish_cost_or_search_two_banish_pattern")
	if await _main._look_and_play.try_execute_look_opponent_hand_discard_then_search_ally_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_look_opponent_hand_discard_then_search_ally_pattern")
	if await _main._look_and_play.try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern(full_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern")
	if await _main._draw_shuffle_resolver.try_execute_each_player_discard_then_draw_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_each_player_discard_then_draw_pattern")
	if await _main._draw_shuffle_resolver.try_execute_draw_gold_search_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_draw_gold_search_pattern")
	if await _main._draw_shuffle_resolver.try_execute_draw_reveal_talisman_gold_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_draw_reveal_talisman_gold_pattern")
	if await _main._draw_shuffle_resolver.try_execute_deck_top_or_bottom_to_hand_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_deck_top_or_bottom_to_hand_pattern")
	if await _main._draw_shuffle_resolver.try_execute_shuffle_exile_and_draw_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_exile_and_draw_pattern")
	if await _main._draw_shuffle_resolver.try_execute_shuffle_hand_and_draw_plus_two_pattern(full_ability_text, controller_id):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_hand_and_draw_plus_two_pattern")
	if await _main._convert_misc_resolver.try_execute_mill_convert_to_ally_pattern(full_ability_text, card, controller_id):
		return _hit("convert_misc_resolver.try_execute_mill_convert_to_ally_pattern")
	if await _main._draw_shuffle_resolver.try_execute_tempilcahue_choice_pattern(full_ability_text, card, controller_id):
		return _hit("draw_shuffle_resolver.try_execute_tempilcahue_choice_pattern")
	if await _main._draw_shuffle_resolver.try_execute_golpe_solar_pattern(full_ability_text, card, controller_id):
		return _hit("draw_shuffle_resolver.try_execute_golpe_solar_pattern#2")
	if await _main._draw_shuffle_resolver.try_execute_shuffle_hand_then_draw_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_hand_then_draw_pattern")
	if await _main._draw_shuffle_resolver.try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern(full_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern")
	# Estos dos chequean sobre el texto ya aislado al bloque de este trigger: una carta puede repetir
	# el mismo trigger (Alicia en Wonderland) y este resolutor se llama una vez por bloque; con el
	# texto completo se dispararían dos veces.
	if await _main._look_and_play.try_execute_reveal_until_distinct_cost_allies_pattern(isolated_ability_text, controller_id, card):
		return _hit("look_and_play.try_execute_reveal_until_distinct_cost_allies_pattern")
	if await _main._look_and_play.try_execute_search_ally_castillo_or_cementerio_then_buff_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_ally_castillo_or_cementerio_then_buff_pattern")
	if await _main._look_and_play.try_execute_search_ally_cost_max_free_play_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_ally_cost_max_free_play_pattern")
	if await _main._look_and_play.try_execute_cain_damage_shuffle_search_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_cain_damage_shuffle_search_pattern")
	if await _main._look_and_play.try_execute_search_two_oros_split_destination_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_search_two_oros_split_destination_pattern")
	if await _main._look_and_play.try_execute_primer_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_primer_sello_pattern")
	if await _main._look_and_play.try_execute_segundo_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_segundo_sello_pattern")
	if await _main._look_and_play.try_execute_tercer_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_tercer_sello_pattern")
	if await _main._look_and_play.try_execute_cuarto_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_cuarto_sello_pattern")
	if await _main._look_and_play.try_execute_quinto_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_quinto_sello_pattern")
	if await _main._look_and_play.try_execute_sexto_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_sexto_sello_pattern")
	if await _main._look_and_play.try_execute_septimo_sello_pattern(isolated_ability_text, card, controller_id):
		return _hit("look_and_play.try_execute_septimo_sello_pattern")
	if await _main._convert_misc_resolver.try_execute_name_a_card_pattern(isolated_ability_text, card, controller_id):
		return _hit("convert_misc_resolver.try_execute_name_a_card_pattern")
	if await _main._convert_misc_resolver.try_execute_no_allies_convert_castillo_top_pattern(isolated_ability_text, card, controller_id):
		return _hit("convert_misc_resolver.try_execute_no_allies_convert_castillo_top_pattern")
	if await _main._convert_misc_resolver.try_execute_jabberwocky_convert_opponent_top_pattern(full_ability_text, card, controller_id):
		return _hit("convert_misc_resolver.try_execute_jabberwocky_convert_opponent_top_pattern")
	if await _main._convert_misc_resolver.try_execute_opponent_discard_and_draw_pattern(isolated_ability_text, card, controller_id):
		return _hit("convert_misc_resolver.try_execute_opponent_discard_and_draw_pattern")
	if await _main._draw_shuffle_resolver.try_execute_banish_from_cemeteries_and_draw_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_banish_from_cemeteries_and_draw_pattern")
	if await _main._draw_shuffle_resolver.try_execute_weapon_count_banish_cemetery_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_weapon_count_banish_cemetery_pattern")
	if await _main._draw_shuffle_resolver.try_execute_vigilia_or_final_banish_opponent_cemetery_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_vigilia_or_final_banish_opponent_cemetery_pattern")
	if await _main._draw_shuffle_resolver.try_execute_shuffle_up_to_n_cemeteries_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_up_to_n_cemeteries_pattern")
	if await _main._draw_shuffle_resolver.try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern")
	if await _main._draw_shuffle_resolver.try_execute_banish_up_to_n_cemeteries_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_banish_up_to_n_cemeteries_pattern")
	if await _main._draw_shuffle_resolver.try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern")
	if await _main._draw_shuffle_resolver.try_execute_banish_cemeteries_equal_to_own_strength_pattern(isolated_ability_text, card, controller_id):
		return _hit("draw_shuffle_resolver.try_execute_banish_cemeteries_equal_to_own_strength_pattern")
	if await _main._draw_shuffle_resolver.try_execute_draw_and_shuffle_hand_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_draw_and_shuffle_hand_pattern")
	if await _main._draw_shuffle_resolver.try_execute_draw_and_shuffle_opponent_card_pattern(isolated_ability_text, controller_id, card):
		return _hit("draw_shuffle_resolver.try_execute_draw_and_shuffle_opponent_card_pattern")
	if await _main._convert_misc_resolver.try_execute_banish_top_by_ally_count_and_draw_pattern(isolated_ability_text, controller_id, card):
		return _hit("convert_misc_resolver.try_execute_banish_top_by_ally_count_and_draw_pattern")
	var action := UniversalCardParser.extract_action(isolated_ability_text)
	if action.get("matched", false):
		if trace_enabled:
			old_parser_texts.append({"carta": str(card.get("card_name")) if is_instance_valid(card) else "",
				"texto": isolated_ability_text})
		await _main._targeted_executor.execute_parsed_action(action, card, event_data)
		return _hit("analizador_viejo.extract_action")
	return false


func _execute_trigger_effect(card: Node, trigger_type: String, event_data: Dictionary) -> Dictionary:
	"""Ejecuta el efecto del trigger usando Callable
	Resuelve 'en medida de lo posible' (DAR Sección 8)
	"""
	var result = {
		"resolved": true,
		"partial": false,
		"blocked_by": null
	}

	# Handler específico de la carta (Card.effect_handlers): 'handled' solo queda true si de verdad
	# hizo algo. Si no hay handler, _on_trigger_event() marca no_handler y la ejecución sigue al
	# fallback de abajo, que aísla la oración correcta (si no, p.ej. Tyet robaba en vez de buscar).
	var handled := false
	if card.has_method("_on_trigger_event"):
		var effect_callable: Callable = card._on_trigger_event
		var effect_result = await effect_callable.call(trigger_type, event_data)
		if effect_result is Dictionary:
			result.merge(effect_result, true)
			handled = not effect_result.get("no_handler", false)
	elif card.has_method("execute_ability"):
		await card.execute_ability(trigger_type, event_data)
		handled = true

	if not handled:
		# ── Fallback: parsear texto de la carta con extract_action() ─────────
		# Cubre habilidades ETB declaradas en texto plano ("Cuando entra: Roba dos cartas")
		result["no_handler"] = true
		if trigger_type in ["on_enter_play", "on_ally_enters"]:
			var full_ability_text: String = ""
			if card.get("card_data") != null:
				full_ability_text = card.card_data.get("habilidad", "")
			# Aislar las oraciones de "entra en juego": sin aislar, extract_action() podía tomar la primera
			# acción de otra habilidad (p.ej. un "Destierra..." de Fase Final). Una carta puede tener dos
			# "Cuando entra en juego" independientes (Alicia en Wonderland): se procesa cada bloque.
			var clauses: Array[String] = _isolate_all_trigger_clauses(full_ability_text, ["cuando entra", "al entrar", "cuando ataca, entra"])
			if clauses.is_empty() and not full_ability_text.is_empty():
				clauses = [full_ability_text]
			var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
			# Tótems con patrón propio (no son un bloque "mira/muestra" genérico; arco del triunfo necesita
			# is_entering, ver TotemAbilityPatterns.gd): se chequean antes del bucle genérico. Tienen una
			# sola cláusula de entrada y su patrón la resuelve completa; explicit_done evita que el bucle
			# genérico la ejecute otra vez (arquitectura.md §54).
			var explicit_done := false
			if await _main._totem_patterns.try_execute_arco_del_triunfo_pattern(full_ability_text, card, controller_id, true):
				result["no_handler"] = false
				explicit_done = true
			if await _main._totem_patterns.try_execute_kotoku_in_enter_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._totem_patterns.try_execute_iga_ryu_enter_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._totem_patterns.try_execute_hangar_ciudadela_enter_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._totem_patterns.try_execute_metropolitan_enter_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			# Armas con patrón propio: mismo criterio que los Tótems (necesitan saber si es entrada u otras
			# condiciones).
			if await _main._weapon_patterns.try_execute_nodachi_enter_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._weapon_patterns.try_execute_azusa_yumi_enter_leave_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			# hidromiel: única cláusula de la carta; se registra igual que los Tótems/Armas por consistencia.
			if await _main._oro_patterns.try_execute_hidromiel_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			# Marchosias, Isla de Poveglia, transilvania, antu: "cuando entra o sale del juego" (LeavePlayPatterns).
			if trigger_type == "on_enter_play" and not explicit_done and LeavePlayScript.handles(full_ability_text, true):
				if await LeavePlayScript.try_execute(card, full_ability_text, controller_id, true, event_data):
					result["no_handler"] = false
					explicit_done = true
			# Cartas sueltas armadas con piezas existentes (EnterPatterns: garfio pirata, la muerte, Lamec...).
			if trigger_type == "on_enter_play" and not explicit_done and EnterScript.handles(full_ability_text):
				if await EnterScript.try_execute(card, full_ability_text, controller_id):
					result["no_handler"] = false
					explicit_done = true
			# fuma kotaro: "Cuando entra en juego o ataques con un sólo Aliado" (AttackPatterns).
			if trigger_type == "on_enter_play" and not explicit_done and AttackScript.handles_enter(full_ability_text):
				if await AttackScript.try_execute(card, full_ability_text, controller_id):
					result["no_handler"] = false
					explicit_done = true
			for ability_text: String in clauses:
				if explicit_done:
					break
				var resolved := await _resolve_look_and_play_patterns(card, full_ability_text, ability_text, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_leave_play":
			# "Al salir del juego" / "cuando salga del juego" / "cuando entra o salga del juego" (p.ej.
			# Legión Paladín): fallback genérico por texto.
			var full_ability_text: String = ""
			if card.get("card_data") != null:
				full_ability_text = card.card_data.get("habilidad", "")
			var ability_text := _isolate_trigger_clause(full_ability_text, [
				"al salir del juego", "cuando salga del juego", "cuando sale del juego", "cuando entra o salga del juego",
				"cuando entra o sale del juego", "entra o sale del juego"
			])
			if ability_text.is_empty():
				ability_text = full_ability_text
			var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
			# arco del triunfo con is_entering = false: desregistra el daño al Destierro (el aura de Fuerza
			# la limpia ModifierRegistry al salir la fuente). Mismo corte de doble disparo que en
			# on_enter_play.
			var explicit_done := false
			if await _main._totem_patterns.try_execute_arco_del_triunfo_pattern(full_ability_text, card, controller_id, false):
				result["no_handler"] = false
				explicit_done = true
			# Armas con patrón propio: mismo criterio que arco del triunfo.
			if await _main._weapon_patterns.try_execute_azusa_yumi_enter_leave_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._weapon_patterns.try_execute_armadura_celestial_leave_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._weapon_patterns.try_execute_nehushtan_leave_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._weapon_patterns.try_execute_flechar_xoon_leave_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			if await _main._weapon_patterns.try_execute_canon_naval_leave_pattern(full_ability_text, card, controller_id):
				result["no_handler"] = false
				explicit_done = true
			# mahishi, onryo, los umbras, ryujin: los resuelve CemeteryTriggers.on_card_destroyed().
			# el fantasma / agentes de killbird: "...no disparan sus habilidades al salir del juego" es una regla
			# (TriggerRestrictions._blocked_by_rule_in_play), no un disparador propio.
			var lower_leave: String = CemeteryTriggersScript.normalize(full_ability_text)
			if TriggerRestrictions.FANTASMA_TEXT in lower_leave or TriggerRestrictions.KILLBIRD_TEXT in lower_leave:
				result["no_handler"] = false
				explicit_done = true
			if CemeteryTriggersScript.handles_leave_clause(ability_text):
				result["no_handler"] = false
				explicit_done = true
			# Cambios de control, convertir, condiciones de turno o de causa (LeavePlayPatterns).
			if not explicit_done and LeavePlayScript.handles(full_ability_text, false):
				if await LeavePlayScript.try_execute(card, full_ability_text, controller_id, false, event_data):
					result["no_handler"] = false
					explicit_done = true
			# libra, zmeoaica: lo mismo que al entrar (EnterPatterns).
			if not explicit_done and EnterScript.handles_leave(full_ability_text):
				if await EnterScript.try_execute(card, full_ability_text, controller_id):
					result["no_handler"] = false
					explicit_done = true
			if not ability_text.is_empty() and not explicit_done:
				# El bloque completo (como en on_enter_play) si el compilador lo entiende entero (mochizuki
				# chiyome: "...hasta mostrar un Aliado de coste 2. Ponlo en tu mano y Baraja el resto");
				# si no, la oración sola, como siempre.
				var leave_blocks: Array[String] = _isolate_all_trigger_clauses(full_ability_text, [
					"al salir del juego", "cuando salga del juego", "cuando sale del juego", "cuando entra o salga del juego",
					"cuando entra o sale del juego", "entra o sale del juego", "o salga del juego"])
				if not leave_blocks.is_empty() and leave_blocks[0] != ability_text:
					var block_plan: Dictionary = EffectCompiler.compile_clause(leave_blocks[0])
					if block_plan.ok and EffectCompiler.is_executable(block_plan.steps):
						ability_text = leave_blocks[0]
				var resolved := await _resolve_look_and_play_patterns(card, full_ability_text, ability_text, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_attack":
			# No usar extract_action() sobre el texto completo: una carta puede
			# tener "Cuando entra en juego, Roba dos cartas. Cuando ataque, ..."
			# en el mismo bloque, y extract_action() encuentra la PRIMERA acción
			# reconocible en todo el texto sin importar bajo qué disparador
			# está — dispararía de nuevo el robo de la entrada. Por eso aquí se
			# aísla primero la oración que contiene la frase de "ataque".
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			# "cuando entra en juego o ataque/ataca/ataques" (p.ej. Sherlock Holmes, Viejo del Saco, fuma
			# kotaro) es la misma cláusula que la de entrada: no contiene "cuando ataque" literal.
			var clause := _isolate_trigger_clause(ability_text, [
				"cuando ataque", "cuando atac", "al atacar", "en juego o ataque", "en juego o ataca", "cuando el portador ataque"
			])
			if not clause.is_empty() and not _attack_condition_met(card, clause):
				result["no_handler"] = false  # condición no cumplida: no hace nada
			elif not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				# príncipe orión, Los Szgany, elemental de magma...: bloqueos elegidos por el atacante.
				if await AttackScript.try_execute(card, clause, controller_id):
					result["no_handler"] = false
				# Vlad el Empalador, Dhampir, Antonio Pincheira: "Cuando entra en juego o ataca" / "Cuando
				# ataca, entra o sale".
				elif await VampireScript.try_execute(card, clause, controller_id):
					result["no_handler"] = false
				# Viejo del Saco: "Cuando entra en juego o ataca".
				elif await load("res://scripts/core/effects/mechanics/MechanicPatterns.gd").try_execute(card, clause, controller_id):
					result["no_handler"] = false
				elif await CemeteryReviveScript.try_execute(card, clause, controller_id):
					result["no_handler"] = false
				elif await _main._totem_patterns.try_execute_metropolitan_attack_pattern(clause, card, controller_id):
					result["no_handler"] = false
				elif await _main._look_and_play.try_execute_look_hand_name_play_lock_pattern(ability_text, card, controller_id):
					result["no_handler"] = false
				elif await _main._convert_misc_resolver.try_execute_mill_convert_to_ally_pattern(clause, card, controller_id):
					result["no_handler"] = false
				elif await _main._look_and_play.try_execute_wielder_attack_gold_or_draw_pattern(clause, card, controller_id):
					result["no_handler"] = false
				elif await _main._look_and_play.try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern(ability_text, card, controller_id):
					result["no_handler"] = false
				elif await _main._look_and_play.try_execute_reveal_until_three_cost1_allies_play_one_pattern(ability_text, controller_id, card):
					result["no_handler"] = false
				elif await _main._look_and_play.try_execute_attacks_alone_draw_pattern(ability_text, controller_id, card):
					result["no_handler"] = false
				elif await _main._look_and_play.try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern(ability_text, card, controller_id):
					result["no_handler"] = false
				elif await _main._effect_interpreter.try_execute(card, clause, controller_id):
					result["no_handler"] = false
				# "Cuando entra en juego o ataca, ...": la misma cadena que al entrar (seiryu, yaj, Papa
				# Legba...), que termina en extract_action() sobre la cláusula.
				# Con el bloque entero, como al entrar (Papa Legba: "...pon una en tu mano y la otra en tu
				# Cementerio. Si mostraste ambos, ...").
				elif await _resolve_look_and_play_patterns(card, ability_text, _attack_block(ability_text, clause), controller_id, event_data):
					result["no_handler"] = false
		elif trigger_type == "on_block":
			# "Cuando bloquee" / "al bloquear" impreso en el Aliado que bloquea (recolectado en
			# GameManager.confirm_blockers_and_collect_triggers(), card = el bloqueador; camino directo como
			# on_attack). libro de thoth es otra cosa: un Oro que reacciona a que bloquees con cualquier
			# Aliado; se resuelve aparte con un chequeo directo (como Llave del Abismo), porque el camino
			# directo solo llega a la carta que disparó el evento.
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, [
				"cuando bloquee", "al bloquear"
			])
			if not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				# arthur gordon pym, Elías: dependen de a quién bloquea (event_data.blocked).
				if await BlockScript.try_execute(card, clause, controller_id, event_data):
					result["no_handler"] = false
				else:
					var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
					if resolved:
						result["no_handler"] = false
		elif trigger_type == "on_turn_end":
			# "En tu Fase Final" / "Al final del turno" (p.ej. Espada de O'Higgins), disparado por
			# TriggerSystem.resolve_turn_end_triggers(). Se aísla la oración como en
			# on_attack/on_damage_dealt: una carta puede tener varios disparadores en el mismo bloque.
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, [
				"en tu fase final", "al final del turno", "al terminar el turno",
				# torii: frase acotada a propósito; ver try_execute_torii_final_pattern() en
				# OroAbilityPatterns.gd ("en la fase final" a secas no sirve).
				"en la fase final, si tienes"
			])
			if not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				# Cañón Naval: llamada explícita con la cláusula ya aislada, no registrada en el despachador
				# compartido (motivo en su docstring, WeaponAbilityPatterns.gd).
				if await _main._weapon_patterns.try_execute_canon_naval_final_pattern(clause, card, controller_id):
					result["no_handler"] = false
				# udjat / torii: mismo criterio que Cañón Naval.
				if await _main._oro_patterns.try_execute_udjat_final_pattern(clause, card, controller_id):
					result["no_handler"] = false
				if await _main._oro_patterns.try_execute_torii_final_pattern(clause, card, controller_id):
					result["no_handler"] = false
				if await _main._oro_patterns.try_execute_carro_szgany_final_pattern(clause, card, controller_id):
					result["no_handler"] = false
				else:
					var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
					if resolved:
						result["no_handler"] = false
		elif trigger_type == "on_opponent_turn_end":
			# "En la Fase Final oponente" (p.ej. Biblioteca de Caballería): como on_turn_end, pero
			# TriggerSystem.resolve_turn_end_triggers() lo dispara sobre el campo del jugador que no termina
			# el turno.
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, [
				"en la fase final oponente", "en la fase final de tu oponente"
			])
			if "puedes jugarla" in clause.to_lower() or "puedes jugarlo" in clause.to_lower():
				# "Puedes jugarla en Guerra de Talismanes o en la Fase Final oponente" (Kukri, Diabolista de Ébano):
				# momento para jugarla (PhaseStartWindow), no un disparador.
				result["no_handler"] = false
			elif not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_agrupacion":
			# "En tu Agrupación" (p.ej. Espada del Juicio: "Cuando entra en juego y en tu Agrupación,
			# Destierra..."): una oración puede tener dos disparadores; se procesa una vez por cada
			# trigger_type que calce (son dos eventos distintos, no un doble disparo).
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, [
				"en tu agrupación", "en tu agrupacion",
				# torii: su frase es "al comienzo de tu Agrupación" (también en
				# Card.TRIGGER_KEYWORDS['on_agrupacion'] para clasificarlo).
				"al comienzo de tu agrupación", "al comienzo de tu agrupacion"
			])
			if not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				# torii: llamada explícita con la cláusula aislada, como Cañón Naval/udjat.
				if await _main._oro_patterns.try_execute_torii_agrupacion_pattern(clause, card, controller_id):
					result["no_handler"] = false
				var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_turn_start":
			# "Al comienzo del turno" (p.ej. manuel rodriguez): mismo aislamiento que on_agrupacion,
			# disparado desde TriggerSystem.resolve_agrupacion_triggers().
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			# La oración que vale en este turno (Carcosa: "al comienzo del turno oponente" y "al comienzo de
			# tu turno" en oraciones distintas).
			var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
			if card.get("controller_id") != null:
				controller_id = int(card.controller_id)
			var clause: String = load("res://scripts/core/effects/mechanics/CardQuery.gd").turn_start_clause(
				ability_text, GameManager.active_player_id == controller_id)
			if not clause.is_empty():
				if await _main._look_and_play.try_execute_gold_for_allies_or_shuffle_cost_max_pattern(clause, card, controller_id):
					result["no_handler"] = false
				else:
					var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
					if resolved:
						result["no_handler"] = false
		elif trigger_type == "on_ataque_start":
			# "Al comienzo del Ataque" (p.ej. almirante akari: "genera un Oro por el turno para jugar Aliados
			# o Armas").
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, [
				"al comienzo del ataque"
			])
			# ambrosio ohiggins: su "Al comienzo del Ataque" se usa desde la mano o el Cementerio, antes de
			# declarar (TurnStartPatterns.ambrosio_on_ataque_start()); en juego no hace nada.
			if TurnStartScript.AMBROSIO_TEXT in CemeteryTriggersScript.normalize(clause):
				result["no_handler"] = false
				clause = ""
			if not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_vigilia":
			# "Al comienzo de tu/la Vigilia". No "en tu vigilia" sola: esa es la ventana normal de las
			# habilidades activadas ("una vez por turno, puedes X"), ver Card.gd
			# TRIGGER_KEYWORDS['on_vigilia']. "en tu vigilia o fase final" queda aparte, acotado a Mariano
			# Osorio.
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, [
				"al comienzo de tu vigilia", "al comienzo de la vigilia", "en tu vigilia o fase final"
			])
			var nclause: String = CemeteryTriggersScript.normalize(clause)
			if "vigilia oponente" in nclause or "esta en tu cementerio" in nclause or "jugar este aliado de tu cementerio" in nclause \
					or "este u otro oro de tu cementerio" in nclause or "puedes jugarlo al comienzo" in nclause:
				# París, pulsera de energia, compendium maleficarum, gumyocho, veinte mil leguas: los resuelve
				# ActivatedPatterns.vigilia_start_extras(). "Puedes jugarlo al comienzo de la Vigilia" (Guerrillero
				# Rodriguez) es un momento para jugarlo (PhaseStartWindow), no un disparador.
				result["no_handler"] = false
			elif not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_destroyed":
			# "Cuando sea Destruido": la carta ya está en el Cementerio y su Nodo se liberó; llega aquí
			# con un proxy desde CemeteryTriggers.on_card_destroyed(), no por la cola de triggers.
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			var clause := _isolate_trigger_clause(ability_text, ["cuando sea destruido", "al ser destruido"])
			if not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				if card.get("controller_id") != null:
					controller_id = int(card.controller_id)
				# dis pater: "si hay seis o más cartas en tu Destierro, puedes ...". Los patrones de abajo
				# no ven la condición; sin cumplirla, la habilidad se resuelve sin hacer nada.
				var cond := RegEx.create_from_string("(?i)si hay (\\w+) o m[aá]s cartas en tu destierro, ").search(clause)
				if cond:
					var needed: int = EffectCompiler.parse_amount(cond.get_string(1).to_lower())
					if CardManager.get_exile_count(controller_id) < needed:
						result["no_handler"] = false
						return result
				var resolved := await _resolve_look_and_play_patterns(card, ability_text, clause, controller_id, event_data)
				if resolved:
					result["no_handler"] = false
		elif trigger_type == "on_damage_dealt":
			# "Cuando haga daño de combate" / "cuando haga daño" / "si hizo daño" (DAR): mismo aislamiento de
			# oración que on_attack. "Infligir" no es terminología del juego.
			var ability_text: String = ""
			if card.get("card_data") != null:
				ability_text = card.card_data.get("habilidad", "")
			# "cuando hace daño" (p.ej. Sir Galahad: "Cuando hace daño al Castillo oponente"):
			# on_damage_dealt solo se dispara por daño al Castillo
			# (PhaseFlowController._fire_damage_dealt_triggers()).
			var clause := _isolate_trigger_clause(ability_text, [
				"cuando haga daño de combate", "cuando haga daño", "si hizo daño", "cuando hace daño"
			])
			if not clause.is_empty():
				var controller_id: int = card.get("owner_id") if card.get("owner_id") != null else 0
				# Zadquiel: texto completo; la cláusula aislada corta antes de "Esa carta no puede ser
				# jugada...".
				if await _main._look_and_play.try_execute_look_hand_name_play_lock_pattern(ability_text, card, controller_id):
					result["no_handler"] = false
				elif await _main._convert_misc_resolver.try_execute_convert_ally_to_gold_pattern(clause, card, controller_id):
					result["no_handler"] = false
				elif await _main._draw_shuffle_resolver.try_execute_banish_cemeteries_equal_to_own_strength_pattern(clause, card, controller_id):
					result["no_handler"] = false
				elif await ActivatedScript.try_execute(card, clause, controller_id):  # escorpio, malafar, nagaraja, vinci y yang...
					result["no_handler"] = false
				elif await _main._effect_interpreter.try_execute(card, clause, controller_id):
					result["no_handler"] = false
				else:
					var action := UniversalCardParser.extract_action(clause)
					if action.get("matched", false):
						await _main._targeted_executor.execute_parsed_action(action, card, event_data)
						result["no_handler"]    = false
						result["parsed_action"] = action

	return result


func _isolate_trigger_clause(ability_text: String, trigger_phrases: Array) -> String:
	"""Devuelve solo la oración (separada por '.') que contiene alguna de las
	frases disparadoras dadas, para no interpretar el texto de OTRO
	disparador de la misma carta como si fuera el de este evento."""
	if ability_text.is_empty():
		return ""
	for raw_sentence in ability_text.split("."):
		var sentence: String = raw_sentence.strip_edges()
		if sentence.is_empty():
			continue
		var lower_s := sentence.to_lower()
		for phrase in trigger_phrases:
			if phrase in lower_s:
				return sentence
	return ""


func _isolate_all_trigger_clauses(ability_text: String, trigger_phrases: Array) -> Array[String]:
	"""Como _isolate_trigger_clause(), pero devuelve todos los bloques que empiezan con alguna frase
	de trigger_phrases (una carta puede repetir el mismo trigger, p.ej. Alicia en Wonderland). Cada
	bloque junta las oraciones siguientes hasta:
	- otra oración que calce trigger_phrases (siguiente bloque);
	- una habilidad activada ("una vez por turno" y variantes), que se resuelve por
	parse_abilities() + ActionPipeline (p.ej. Tesoro de los Césares);
	- una oración de un trigger de otro tipo de Card.TRIGGER_KEYWORDS (p.ej. Garfio Pirata: si no,
	su "Roba una carta" de "Cuando el portador ataque" se ejecutaba al equiparse)."""
	var blocks: Array[String] = []
	if ability_text.is_empty():
		return blocks

	var current: Array[String] = []
	var once_markers := ["una vez por turno", "una vez al turno", "una vez en tu turno", "una vez en su turno"]

	# Frases de los otros tipos de trigger (no las de trigger_phrases).
	var other_trigger_phrases: Array = []
	for kw_type in Card.TRIGGER_KEYWORDS:
		for phrase in Card.TRIGGER_KEYWORDS[kw_type]:
			if phrase not in trigger_phrases:
				other_trigger_phrases.append(phrase)
	# "Al comienzo de cada turno" (la esmeralda): no está en TRIGGER_KEYWORDS, pero es otra habilidad y
	# corta el bloque.
	if "al comienzo de cada turno" not in trigger_phrases:
		other_trigger_phrases.append("al comienzo de cada turno")

	# Cada renglón del texto es una habilidad aparte (Signo Amarillo: su "Cuando entra en juego,
	# mira..." se llevaba el renglón "Puedes convertir este Oro..." y CastleLook/EffectCompiler ya no
	# lo entendían). Un bloque sigue en el renglón de abajo solo si éste empieza en minúscula (oración
	# cortada).
	var sentences: Array = []  # [oración, empieza_renglón]
	for line in ability_text.split("\n"):
		var first_in_line := true
		for raw_sentence in line.split("."):
			var s: String = raw_sentence.strip_edges()
			if s.is_empty():
				continue
			sentences.append([s, first_in_line])
			first_in_line = false

	for entry in sentences:
		var sentence: String = entry[0]
		var lower_s := sentence.to_lower()
		if entry[1] and not current.is_empty() and sentence.left(1) != sentence.left(1).to_lower():
			blocks.append(". ".join(current))
			current = []

		var starts_new_block := false
		for phrase in trigger_phrases:
			if phrase in lower_s:
				starts_new_block = true
				break

		if starts_new_block:
			if not current.is_empty():
				blocks.append(". ".join(current))
			current = [sentence]
			continue

		var is_once_marker := false
		for marker in once_markers:
			if marker in lower_s:
				is_once_marker = true
				break
		if is_once_marker:
			if not current.is_empty():
				blocks.append(". ".join(current))
				current = []
			continue

		var starts_other_trigger := false
		for phrase in other_trigger_phrases:
			if phrase in lower_s:
				starts_other_trigger = true
				break
		if starts_other_trigger:
			if not current.is_empty():
				blocks.append(". ".join(current))
				current = []
			continue

		if not current.is_empty():
			current.append(sentence)

	if not current.is_empty():
		blocks.append(". ".join(current))
	return blocks


func resolve_all_triggers() -> void:
	"""Resuelve todos los triggers en la cola secuencialmente"""
	while not _main.trigger_queue.is_empty():
		var trigger = await resolve_next_trigger()
		if trigger.is_empty():
			break
		# Esperar un frame entre triggers para permitir animaciones
		await _main.get_tree().process_frame

	_main.is_resolving = false
	_main.emit_signal("all_triggers_resolved")


func has_pending_triggers() -> bool:
	"""Verifica si hay triggers pendientes"""
	return not _main.trigger_queue.is_empty()


func clear_triggers() -> void:
	"""Limpia todos los triggers pendientes"""
	_main.trigger_queue.clear()
	_main.pending_active_triggers.clear()
	_main.pending_opponent_triggers.clear()
	_main.is_collecting = false
	_main.is_resolving = false
