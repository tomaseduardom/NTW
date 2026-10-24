extends RefCounted
## DSR_SearchGoldCombos — parte de DrawShuffleResolver.gd (fachada con reenvíos de una línea;
## hermanos: DSR_ShuffleDrawCombos.gd, DSR_CemeteryBanishDraw.gd, DSR_DiscardChoicePatterns.gd).
## Buscar/subir una carta (Castillo, mano o Cementerio) o generar Oro Virtual restringido, con un
## Robo u otro efecto (Legión Paladín, Levisterio, La Ouija, Shiji). Opera sobre TriggerSystem vía
## _executor._main (ver TargetedEffectExecutor.gd).

const CemeteryPopupScript = preload("res://scripts/ui/zones/CemeteryRevealPopup.gd")

var _executor: TargetedEffectExecutor


func setup(executor: TargetedEffectExecutor) -> void:
	_executor = executor


func try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern(
	ability_text: String, controller_id: int, card: Node = null
) -> bool:
	"""'Cuando entra en juego, juega un Arma o Tótem de coste 1 de tu mano
	o Cementerio sin pagar su coste' (Shiji, myl_id 18196, edición
	Escuadrón Mecha / reprint promo custom_mig_12). Pool combinado mano +
	Cementerio (mismo patrón de try_execute_golpe_solar_pattern más
	arriba), filtrado a Arma/Tótem de coste EXACTO 1. A diferencia de
	Golpe Solar (que paga con descuento), aquí es gratis de verdad — reusa
	GoldManager.play_card_for_free(), que ya rutea Arma (con selección de
	portador) y Tótem (a campo) sin pasar por PaymentManager. El llamador
	(esta función) saca la carta de su zona de origen ANTES de llamar,
	como pide el contrato documentado de play_card_for_free()."""
	var lower := ability_text.to_lower()
	var mentions_arma_totem_cost1 := "arma o tótem de coste 1" in lower or "arma o totem de coste 1" in lower
	if not mentions_arma_totem_cost1 or not ("sin pagar su coste" in lower):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var hand_container_shiji = main.player_hand if controller_id == 0 else main._opponent_fan
	if not hand_container_shiji:
		return true

	var hand_candidates: Array = []
	for c in hand_container_shiji.cards:
		if (
			is_instance_valid(c)
			and c.get("card_type") in [Constants.CardType.ARMA, Constants.CardType.TOTEM]
			and c.get("card_cost") != null
			and int(c.card_cost) == 1
		):
			hand_candidates.append(c)
	var cemetery_data: Array = []
	for d in CardManager.get_cemetery(controller_id):
		if d.get("tipo") in [Constants.CardType.ARMA, Constants.CardType.TOTEM] and int(d.get("coste", -1)) == 1:
			cemetery_data.append(d)

	if hand_candidates.is_empty() and cemetery_data.is_empty():
		main._update_debug("No tienes ningún Arma o Tótem de coste 1 en tu mano o Cementerio")
		return true
	if not main._card_interaction:
		return true

	# Click directo: mano (Nodos visibles) + popup liviano con el Cementerio propio (como Golpe Solar,
	# DSR_DiscardChoicePatterns.gd).
	var popup_result: Dictionary = CemeteryPopupScript.open(main, cemetery_data, controller_id)
	var cemetery_popup: CanvasLayer = popup_result.popup
	var cemetery_nodes: Array = popup_result.nodes

	var candidates: Array = hand_candidates + cemetery_nodes
	var filter := func(c: Node) -> bool: return c in candidates
	var picked_node: Node = await main._card_interaction.await_target(
		"Juega un Arma o Tótem de coste 1 sin pagar su coste", filter, true, controller_id
	)
	if is_instance_valid(cemetery_popup):
		cemetery_popup.queue_free()

	if not picked_node or not is_instance_valid(picked_node):
		return true
	var picked: Dictionary = picked_node.card_data
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Shiji", controller_id):
		return true

	var from_hand_node: Node = picked_node if picked_node in hand_candidates else null
	if from_hand_node:
		hand_container_shiji.remove_card(from_hand_node, true)
		from_hand_node.queue_free()
	else:
		var cidx: int = CardManager.get_cemetery(controller_id).find(picked)
		if cidx >= 0:
			CardManager.remove_from_cemetery(controller_id, cidx)

	await main._gold_manager.play_card_for_free(picked, controller_id)
	return true


# =============================================================================
# PATRÓN "CUANDO ENTRA EN JUEGO, ROBA N, GENERA UN ORO PARA JUGAR X DE COSTE
# Y O MÁS Y SUBE HASTA M CARTA(S) DE TU CEMENTERIO A TU MANO" (Legión Paladín)
# =============================================================================
func try_execute_draw_gold_search_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Legión Paladín: "Roba N carta(s), genera un Oro para jugar Aliados o Armas de coste X o más y
	sube hasta M carta(s) de tu Cementerio a tu mano" (texto de la API, que varió entre consultas;
	el caché local, id 20857, está sincronizado). Tres efectos encadenados sin "puedes", solo
	"cuando entra en juego"; se ejecutan en orden.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("genera un oro para jugar" in lower and "sube hasta" in lower and "cementerio" in lower):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true

	var draw_rx := RegEx.new()
	draw_rx.compile("(?i)roba[s]?\\s+(\\w+)\\s+cartas?")
	var m_draw := draw_rx.search(ability_text)
	var draw_amount: int = UniversalCardParser._parse_amount(m_draw.get_string(1)) if m_draw else 0

	var cost_rx := RegEx.new()
	cost_rx.compile("(?i)coste\\s+(\\w+)\\s+o\\s+m[aá]s")
	var m_cost := cost_rx.search(ability_text)
	var min_cost: int = UniversalCardParser._parse_amount(m_cost.get_string(1)) if m_cost else 0

	var search_rx := RegEx.new()
	search_rx.compile("(?i)sube\\s+hasta\\s+(\\w+)\\s+cartas?\\s+de\\s+tu\\s+cementerio\\s+a\\s+tu\\s+mano")
	var m_search := search_rx.search(ability_text)
	var search_amount: int = UniversalCardParser._parse_amount(m_search.get_string(1)) if m_search else 0

	# Ventana única para las 3 partes juntas (ninguna pasa por un choke point
	# ya protegido por Prevención) — sin objetivos que declarar antes (robar/
	# generar Oro son automáticos, y a quién sube del Cementerio se elige
	# solo dentro de _resolve_search_cemetery_to_hand()).
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Legión Paladín", controller_id):
		return true

	if draw_amount > 0:
		await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)

	# generar_oro_virtual_restringido() y _resolve_search_cemetery_to_hand() son por jugador
	# (arquitectura.md §33).
	if min_cost > 0 and main._gold_manager:
		var predicate := func(card_type: int, _card_race: String, card_cost: int) -> bool:
			return card_type in [Constants.CardType.ALIADO, Constants.CardType.ARMA] and card_cost >= min_cost
		main._gold_manager.generar_oro_virtual_restringido(
			1, predicate, "Aliados o Armas de coste %d o más" % min_cost, controller_id
		)

	if search_amount > 0:
		await _executor._resolve_search_cemetery_to_hand(controller_id, search_amount)

	return true


func try_execute_draw_reveal_talisman_gold_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""Levisterio: "Roba una carta y puedes mostrar tu mano. Si no tienes más de un Talismán, genera
	un Oro para jugar Armas y Roba una carta adicional". Mostrar la mano es cómo se demuestra la
	condición: se lee la mano del controlador directamente y queda constancia en el log, sin UI de
	revelado.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not (
		"puedes mostrar tu mano" in lower
		and "genera un oro para jugar armas" in lower
		and "roba una carta adicional" in lower
	):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true
	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "Levisterio", controller_id):
		return true

	await ActionModule.draw(controller_id, 1, "etb_trigger", true)

	# La mano a contar es la del jugador que activó la carta.
	var hand_container_levisterio = main.player_hand if controller_id == 0 else main._opponent_fan
	if hand_container_levisterio:
		var talisman_count: int = 0
		for c in hand_container_levisterio.cards:
			if is_instance_valid(c) and c.card_type == Constants.CardType.TALISMAN:
				talisman_count += 1
		main._update_debug(
			"Levisterio: mano mostrada (%d Talismán%s)" % [talisman_count, "" if talisman_count == 1 else "es"]
		)
		if talisman_count <= 1 and main._gold_manager:
			var predicate := func(card_type: int, _card_race: String, _card_cost: int) -> bool:
				return card_type == Constants.CardType.ARMA
			main._gold_manager.generar_oro_virtual_restringido(1, predicate, "Armas", controller_id)
			await ActionModule.draw(controller_id, 1, "etb_trigger", true)

	return true


func try_execute_deck_top_or_bottom_to_hand_pattern(
	ability_text: String, controller_id: int, card: Node = null
) -> bool:
	"""La Ouija: "pon la primera o la última carta de tu Castillo en tu mano" (carta promocional sin
	myl_id; ver _activate_ouija_play_from_cemetery_or_deck_top() en
	HandCementerioAbilityHandler.gd). Sin "puedes": obligatorio, pero con elección entre las dos.
	"primera" = tope (índice 0, ver CardManager.add_to_deck_top()), "última" = fondo.
	Devuelve true si el patrón aplicaba."""
	var lower := ability_text.to_lower()
	if not ("primera o la última carta de tu castillo" in lower and "en tu mano" in lower):
		return false

	var main := _executor._main.get_node_or_null("/root/Main")
	if not main:
		return true
	var deck: Array = main.player_deck if controller_id == 0 else main.opponent_deck
	var hand_container_ouija2 = main.player_hand if controller_id == 0 else main._opponent_fan
	if deck.is_empty():
		return true

	# El revelado del tope ("Juega mostrando la primera carta de tu Castillo") rige desde que entra en
	# juego: se refresca aquí, antes de elegir tope/fondo, para que el jugador vea cuál es la del tope
	# (la del fondo sigue a ciegas). La carta ya está en player_gold con zona RESERVA_ORO
	# (_trigger_enter_play() corre después de _place_card_as_gold()).
	if main._zone_viewer:
		main._zone_viewer.refresh_castillo_top_reveal()

	var choose_top: bool = true
	if deck.size() > 1:
		var top_card: Dictionary = deck.front()
		var bottom_card: Dictionary = deck.back()
		choose_top = await SelectionManager.await_card_pair_choice(
			main, "La Ouija", top_card, bottom_card, "Tope", "Fondo", true, false, controller_id
		)

	if await TriggerSystem.open_response_window(card, str(card.card_name) if card else "La Ouija", controller_id):
		return true
	var card_data: Dictionary = deck.pop_front() if choose_top else deck.pop_back()
	var card_node: Node = main._create_card(card_data, false)
	card_node.owner_id = controller_id
	hand_container_ouija2.add_card(card_node)
	main._connect_card_signals(card_node)
	if main._zone_manager:
		main._zone_manager._update_castillo_counts()

	return true
