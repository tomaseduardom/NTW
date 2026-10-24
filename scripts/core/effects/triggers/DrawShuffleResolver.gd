extends RefCounted
## DrawShuffleResolver — FACHADA de los patrones compuestos "roba N / baraja M / busca..." que
## combinan varias acciones en una oración (lo que extract_action(), una sola acción por texto, no
## resuelve). Cada función reenvía en una línea a una de sus partes, con el mismo nombre y firma
## (TriggerResolution.gd la llama vía `_main._draw_shuffle_resolver.try_execute_X(...)`):
## DSR_ShuffleDrawCombos.gd (barajar + robar), DSR_CemeteryBanishDraw.gd (Cementerios + robar),
## DSR_SearchGoldCombos.gd (buscar/subir + Oro Virtual) y DSR_DiscardChoicePatterns.gd (descarte
## compuesto / elecciones A-B). Opera sobre TriggerSystem vía _executor._main (ver
## TargetedEffectExecutor.gd).

const DSR_ShuffleDrawCombosScript = preload("res://scripts/core/effects/triggers/DSR_ShuffleDrawCombos.gd")
const DSR_CemeteryBanishDrawScript = preload("res://scripts/core/effects/triggers/DSR_CemeteryBanishDraw.gd")
const DSR_SearchGoldCombosScript = preload("res://scripts/core/effects/triggers/DSR_SearchGoldCombos.gd")
const DSR_DiscardChoicePatternsScript = preload("res://scripts/core/effects/triggers/DSR_DiscardChoicePatterns.gd")

var _executor: TargetedEffectExecutor
var _shuffle_draw: RefCounted
var _cemetery_banish: RefCounted
var _search_gold: RefCounted
var _discard_choice: RefCounted


func setup(executor: TargetedEffectExecutor) -> void:
	_executor = executor
	_shuffle_draw = DSR_ShuffleDrawCombosScript.new()
	_shuffle_draw.setup(executor)
	_cemetery_banish = DSR_CemeteryBanishDrawScript.new()
	_cemetery_banish.setup(executor)
	_search_gold = DSR_SearchGoldCombosScript.new()
	_search_gold.setup(executor)
	_discard_choice = DSR_DiscardChoicePatternsScript.new()
	_discard_choice.setup(executor)


func try_execute_shuffle_exile_and_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _shuffle_draw.try_execute_shuffle_exile_and_draw_pattern(ability_text, controller_id, card)


func try_execute_shuffle_hand_and_draw_plus_two_pattern(ability_text: String, controller_id: int) -> bool:
	return await _shuffle_draw.try_execute_shuffle_hand_and_draw_plus_two_pattern(ability_text, controller_id)


func try_execute_shuffle_ally_or_search_castle_pattern(full_text: String, card: Node, controller_id: int) -> bool:
	return await _discard_choice.try_execute_shuffle_ally_or_search_castle_pattern(full_text, card, controller_id)


func try_execute_tempilcahue_choice_pattern(full_text: String, card: Node, controller_id: int) -> bool:
	return await _discard_choice.try_execute_tempilcahue_choice_pattern(full_text, card, controller_id)


func try_execute_draw_and_shuffle_hand_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _shuffle_draw.try_execute_draw_and_shuffle_hand_pattern(ability_text, controller_id, card)


func try_execute_draw_and_shuffle_opponent_card_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _shuffle_draw.try_execute_draw_and_shuffle_opponent_card_pattern(ability_text, controller_id, card)


func try_execute_golpe_solar_pattern(full_text: String, card: Node, controller_id: int) -> bool:
	return await _discard_choice.try_execute_golpe_solar_pattern(full_text, card, controller_id)


func try_execute_shuffle_hand_then_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _shuffle_draw.try_execute_shuffle_hand_then_draw_pattern(ability_text, controller_id, card)


func try_execute_banish_cemeteries_equal_to_own_strength_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	return await _cemetery_banish.try_execute_banish_cemeteries_equal_to_own_strength_pattern(ability_text, card, controller_id)


func try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern(ability_text, controller_id, card)


func try_execute_shuffle_up_to_n_cemeteries_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_shuffle_up_to_n_cemeteries_pattern(ability_text, controller_id, card)


func try_execute_banish_up_to_n_cemeteries_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_banish_up_to_n_cemeteries_pattern(ability_text, controller_id, card)


func try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern(ability_text, controller_id, card)


func try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _search_gold.try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern(ability_text, controller_id, card)


func try_execute_draw_gold_search_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _search_gold.try_execute_draw_gold_search_pattern(ability_text, controller_id, card)


func try_execute_draw_reveal_talisman_gold_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _search_gold.try_execute_draw_reveal_talisman_gold_pattern(ability_text, controller_id, card)


func try_execute_deck_top_or_bottom_to_hand_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _search_gold.try_execute_deck_top_or_bottom_to_hand_pattern(ability_text, controller_id, card)


func try_execute_banish_from_cemeteries_and_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_banish_from_cemeteries_and_draw_pattern(ability_text, controller_id, card)


func try_execute_weapon_count_banish_cemetery_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_weapon_count_banish_cemetery_pattern(ability_text, controller_id, card)


func try_execute_vigilia_or_final_banish_opponent_cemetery_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _cemetery_banish.try_execute_vigilia_or_final_banish_opponent_cemetery_pattern(ability_text, controller_id, card)


func try_execute_each_player_discard_then_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	return await _discard_choice.try_execute_each_player_discard_then_draw_pattern(ability_text, controller_id, card)
