extends RefCounted
## DSR_DiscardChoicePatterns — parte de DrawShuffleResolver.gd (fachada con reenvíos de una línea;
## hermanos: DSR_ShuffleDrawCombos.gd, DSR_CemeteryBanishDraw.gd, DSR_SearchGoldCombos.gd).
## Descartes compuestos y elecciones A/B (Tempilcahue, Golpe Solar, Escamas de Dragón). Opera sobre
## TriggerSystem vía _executor._main (ver TargetedEffectExecutor.gd).

const CemeteryPopupScript = preload("res://scripts/ui/zones/CemeteryRevealPopup.gd")

var _executor: TargetedEffectExecutor


func setup(executor: TargetedEffectExecutor) -> void:
	_executor = executor


func try_execute_tempilcahue_choice_pattern(full_text: String, card: Node, controller_id: int) -> bool:
	"""Tempilcahue: "Cuando lo juegues, Destiérralo. Elige un efecto: - Busca una carta en tu
	Castillo, ponla en tu mano y Roba una carta. No puedes jugar más cartas este turno. - Paga dos
	Oros para Barajar cartas cuyos costes sumen hasta 4 y Robar dos cartas." Talismán
	(TriggerSystem.resolve_talisman()); el autodestierro lo hace GoldManager._play_talisman(). Aquí
	solo la elección. "Barajar cartas cuyos costes sumen..." sin "de tu mano" = cartas en juego de
	cualquier lado (a diferencia de Aaru, que dice "de tu mano")."""
	var lower := full_text.to_lower()
	if not ("elige un efecto" in lower and "no puedes jugar más cartas" in lower and "paga dos oros" in lower):
		return false
	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true

	# Los botones muestran el texto EXACTO de cada opción de la carta: el texto del botón no coincidía
	# con la carta); si no se encuentra, quedan los resúmenes de siempre.
	var label_search := "Buscar una carta en tu Castillo y robar una (no juegas más cartas este turno)"
	var label_shuffle := "Pagar 2 Oros: barajar cartas en juego (coste ≤4) y robar 2"
	for raw_line in full_text.split("\n"):
		var line: String = raw_line.strip_edges().trim_prefix("-").strip_edges()
		if line.to_lower().begins_with("busca una carta en tu castillo"):
			label_search = line
		elif line.to_lower().begins_with("paga dos oros"):
			label_shuffle = line
	var candidates: Array = []
	for field in [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
			main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and c != card and _cost_of(c) <= 4:
				candidates.append(c)

	# Sin popup. Si no puede pagar los dos Oros (o no hay nada que barajar), busca directo. Si puede,
	# brillan su Castillo (buscar) y las cartas en juego que se pueden barajar; la primera carta
	# elegida ya cuenta para la suma de 4.
	var choose_search := true
	var first_pick: Node = null
	if main._gold_manager.puede_pagar(2, -1, "", -1, controller_id) and not candidates.is_empty() and main._card_interaction:
		var in_play_filter := func(c: Node) -> bool: return c in candidates
		var pick: Dictionary = await main._card_interaction.await_target_or_castillo_pick(
			"Tempilcahue: tu Castillo para buscar, o una carta en juego para pagar 2 Oros y barajar",
			in_play_filter, "Tempilcahue: buscar en tu Castillo", false, true, controller_id)
		if pick.get("type", "") == "card" and is_instance_valid(pick.get("card")):
			choose_search = false
			first_pick = pick.card

	if choose_search:
		# Sin ventana aquí: Tempilcahue es un Talismán y resolve_talisman() ya abrió una para toda la
		# carta.
		await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {}, 1, true, false, false, card, Constants.Zone.MANO, false)
		await ActionModule.draw(controller_id, 1, "talisman_resolve", true)
		main._gold_manager.set_no_more_cards_this_turn(controller_id)
		return true

	await main._gold_manager.pagar_coste(2, -1, "", -1, controller_id)

	# Click directo sobre las cartas en juego; el presupuesto se cumple en el momento: dynamic_filter
	# apaga el brillo de cualquier carta que haría superar la suma de 4.
	var first_cost: int = _cost_of(first_pick)
	var budget_filter := func(chosen_so_far: Array, c: Node) -> bool:
		var sum_cost: int = first_cost
		for x in chosen_so_far:
			sum_cost += _cost_of(x)
		return sum_cost + _cost_of(c) <= 4
	var rest: Array = candidates.filter(func(c): return c != first_pick and first_cost + _cost_of(c) <= 4)
	var chosen: Array = [first_pick]
	if not rest.is_empty():
		chosen += await main._card_interaction.await_multi_target(
			"Baraja más cartas en juego (suma de costes hasta 4) — N para terminar", rest, -1, Callable(),
			budget_filter, true, null, controller_id)
	# Sin ventana genérica aquí: return_to_deck (dentro del loop) ya consulta Prevención adentro por
	# cada carta.
	for c in chosen:
		if not is_instance_valid(c):
			continue
		var owner_id: int = c.owner_id if c.get("owner_id") != null else controller_id
		await ActionModule.return_to_deck(c, owner_id, true, card)
		CardManager.shuffle_deck(owner_id)

	await ActionModule.draw(controller_id, 2, "talisman_resolve", true)
	return true


func _cost_of(c) -> int:
	if not is_instance_valid(c):
		return 0
	return int(c.get("card_cost")) if c.get("card_cost") != null else 0


func try_execute_shuffle_ally_or_search_castle_pattern(full_text: String, card: Node, controller_id: int) -> bool:
	"""'Puedes Barajar un Aliado de Fuerza N o menos o buscar una carta en tu Castillo y ponerla en tu
	mano' (Sombrerero Loco). Sin popup: brillan los Aliados que se pueden barajar (de los dos
	lados, sin zona = en juego) y tu Castillo; al elegir uno, lo otro se apaga. ESC = no hacer nada
	(es opcional)."""
	var rx := RegEx.new()
	rx.compile("puedes barajar un aliado de fuerza (\\w+) o menos o buscar una carta en tu castillo y ponerla en tu mano")
	var m := rx.search(full_text.to_lower())
	if not m:
		return false
	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var max_str: int = UniversalCardParser._parse_amount(m.get_string(1))
	var allies: Array = []
	for field in [main.player_field, main.player_linea_ataque, main.player_linea_apoyo,
			main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]:
		if not field:
			continue
		for c in field.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.get_modified_strength(c) <= max_str:
				allies.append(c)
	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) else "Barajar o buscar"
	# Bot: busca en su Castillo sin preguntar (la elección no debe aparecer en la pantalla del
	# Anfitrión).
	if load("res://scripts/core/game/PlayerSide.gd").is_bot(controller_id):
		await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {}, 1, true, false, false, card,
			Constants.Zone.MANO, false, controller_id)
		return true
	var pick: Dictionary = await main._card_interaction.await_target_or_castillo_pick(
		"%s: baraja un Aliado de Fuerza %d o menos, o busca en tu Castillo (N: nada)" % [card_name, max_str],
		func(c: Node) -> bool: return c in allies, "%s: buscar en tu Castillo" % card_name, true, true, controller_id)
	match str(pick.get("type", "")):
		"card":
			var target: Node = pick.get("card")
			if is_instance_valid(target):
				var owner_id: int = target.owner_id if target.get("owner_id") != null else controller_id
				if await ActionModule.return_to_deck(target, owner_id, true, card):
					CardManager.shuffle_deck(owner_id)
		"castillo":
			await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {}, 1, true, false, false, card,
				Constants.Zone.MANO, false)
	return true


# =============================================================================
# PATRÓN "CUANDO JUEGUES ESTA CARTA, DESTIÉRRALO. DESCARTA HASTA DOS CARTAS Y
# JUEGA UN ALIADO DE TU MANO O CEMENTERIO REDUCIENDO SU COSTE... BARAJA HASTA
# UNA CARTA OPONENTE DE COSTE 2 O MENOS" (Golpe Solar)
# =============================================================================
func try_execute_golpe_solar_pattern(full_text: String, card: Node, controller_id: int) -> bool:
	"""Golpe Solar: "Cuando juegues esta carta, Destiérralo. Descarta hasta dos cartas y juega un
	Aliado de tu mano o Cementerio reduciendo su coste en tantos Oros como cartas hayas Descartado,
	hasta un mínimo de 0. Baraja hasta una carta oponente de coste 2 o menos." Talismán
	(TriggerSystem.resolve_talisman()); el autodestierro lo hace GoldManager._play_talisman().
	Descuento: como Lobo Sagrado (TargetedEffectExecutor._execute_play_weapon_discount_draw()): se
	calcula con un modificador temporal, se quita y se paga el número resultante, para un Aliado
	(sin portador).
	"Baraja... una carta oponente" sin zona = en juego (candidatos como Espada Vikinga), coste ≤2 y
	opcional ("hasta una": ESC para declinar).
	Se DECLARAN primero las 3 elecciones (la carta rival a Barajar, el descarte y el Aliado) sin
	tocar nada, y después se ejecutan (Pila de Respuesta Universal,
	docs/plans/2026-09-09-pila-respuesta-universal-design.md)."""
	var lower := full_text.to_lower()
	if not ("descarta hasta dos cartas" in lower and "reduciendo su coste" in lower
			and "baraja hasta una carta oponente" in lower):
		return false
	var main := _executor._main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true
	var hand_container_golpe = main.player_hand if controller_id == 0 else main._opponent_fan

	# ============ DECLARAR (nada se ejecuta todavía) ============

	# El objetivo a Barajar se elige PRIMERO (N para no barajar ninguna), luego el descarte y el
	# Aliado. Se resuelve igual en el orden impreso. --- Declarar "Baraja hasta una carta oponente de
	# coste 2 o menos" ---
	var opponent_id: int = 1 - controller_id
	var opp_fields: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if opponent_id == 0 \
		else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
	var shuffle_candidates: Array = []
	# Sin Oros: Golpe Solar no puede barajar Oros.
	for field in opp_fields:
		if not field:
			continue
		for c in field.get_children():
			if not is_instance_valid(c):
				continue
			if ContinuousEffectManager.cost_at_most(c, 2):
				shuffle_candidates.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and ContinuousEffectManager.cost_at_most(w, 2):
						shuffle_candidates.append(w)

	var shuffle_chosen: Node = null
	if not shuffle_candidates.is_empty() and main._card_interaction:
		var shuffle_filter := func(c: Node) -> bool:
			return c in shuffle_candidates
		shuffle_chosen = await main._card_interaction.await_target(
			"Baraja hasta una carta rival en juego (coste 2 o menos) — N para no barajar ninguna", shuffle_filter, true, controller_id)

	# --- Declarar "Descarta hasta dos cartas" (0-2, elección del jugador) ---
	# Click directo en la mano.
	var to_discard: Array = []
	if hand_container_golpe and not hand_container_golpe.cards.is_empty() and main._card_interaction:
		var hand_cards: Array = hand_container_golpe.cards.duplicate()
		to_discard = await main._card_interaction.await_multi_target(
			"Descarta hasta dos cartas (reduce el coste del Aliado por cada una)", hand_cards, 2, Callable(), Callable(), true, null, controller_id)
	var just_discarded_data: Array = to_discard.map(func(c): return c.card_data)
	var discount: int = to_discard.size()

	# Declarar "juega un Aliado de tu mano o Cementerio" con ese descuento --- Un Aliado recién
	# descartado por ESTE mismo efecto no puede ser el elegido aquí: _discard lo manda directo al
	# Cementerio, así que sin esta exclusión aparecía como candidata de 'Cementerio' en la misma
	# resolución que lo descartó.
	var hand_allies: Array = []
	if hand_container_golpe:
		for c in hand_container_golpe.cards:
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and not (c in to_discard):
				hand_allies.append(c)
	var cemetery_allies: Array = []
	for d in CardManager.get_cemetery(controller_id):
		if d.get("tipo") == Constants.CardType.ALIADO and not (d in just_discarded_data):
			cemetery_allies.append(d)

	var ally_node: Node = null
	var from_hand := false
	var coste_real := 0
	var puede_pagar := false
	var picked_ally_data: Dictionary = {}
	if not (hand_allies.is_empty() and cemetery_allies.is_empty()) and main._card_interaction:
		# Click directo: mano (Nodos visibles) + popup liviano con el Cementerio propio (como Sake,
		# arquitectura.md §10.23).
		var popup_result: Dictionary = CemeteryPopupScript.open(main, cemetery_allies, controller_id)
		var cemetery_popup: CanvasLayer = popup_result.popup
		var cemetery_nodes: Array = popup_result.nodes

		var candidates: Array = hand_allies + cemetery_nodes
		var filter := func(c: Node) -> bool: return c in candidates
		var picked_node: Node = await main._card_interaction.await_target(
			"Juega un Aliado con -%d Oro (mín 0)" % discount, filter, true, controller_id)
		if is_instance_valid(cemetery_popup):
			cemetery_popup.queue_free()

		if picked_node and is_instance_valid(picked_node):
			from_hand = picked_node in hand_allies
			picked_ally_data = picked_node.card_data
			ally_node = picked_node if from_hand else main._create_card(picked_ally_data, false)
			if not from_hand:
				ally_node.owner_id = controller_id
				ally_node.controller_id = controller_id
				main._connect_card_signals(ally_node)

			var applies_to_this_ally := func(c: Node) -> bool:
				return c == ally_node
			PaymentManager.agregar_modificador_coste(ally_node, -discount, applies_to_this_ally, true)
			coste_real = PaymentManager.calcular_coste_real(ally_node)
			puede_pagar = PaymentManager.puede_jugar_carta(ally_node, controller_id)
			PaymentManager.remover_modificador_coste(ally_node)
			if not puede_pagar and not from_hand:
				ally_node.queue_free()
				ally_node = null

	# Sin ventana genérica aquí: resolve_talisman() ya la abrió para toda la carta (si la anulaban,
	# este patrón no se llamaba).
	# ============ RESOLVER ============
	if not to_discard.is_empty():
		await ActionModule.discard(controller_id, to_discard, "talisman_resolve")

	if hand_allies.is_empty() and cemetery_allies.is_empty():
		main._update_debug("No tienes ningún Aliado en tu mano o Cementerio para jugar")
	elif not picked_ally_data.is_empty() and ally_node:
		if not puede_pagar:
			main._update_debug("No puedes pagar el Aliado con descuento (%d Oro)" % coste_real)
		else:
			if from_hand:
				var hidx = hand_container_golpe.cards.find(ally_node)
				if hidx >= 0:
					hand_container_golpe.cards.remove_at(hidx)
				if ally_node.get_parent() == hand_container_golpe:
					hand_container_golpe.remove_child(ally_node)
			else:
				var cidx: int = CardManager.get_cemetery(controller_id).find(picked_ally_data)
				if cidx >= 0:
					CardManager.remove_from_cemetery(controller_id, cidx)

			if coste_real > 0:
				var ally_race: String = str(ally_node.get("card_raza")) if ally_node.get("card_raza") != null else ""
				await main._gold_manager.pagar_coste(coste_real, ally_node.card_type, ally_race, ally_node.card_cost, controller_id)
				PaymentManager.registrar_pago(coste_real)

			await main._gold_manager._play_card_to_field(ally_node)

	if shuffle_chosen and is_instance_valid(shuffle_chosen):
		var true_owner: int = shuffle_chosen.owner_id if shuffle_chosen.get("owner_id") != null else opponent_id
		await ActionModule.return_to_deck(shuffle_chosen, true_owner, true, card)
		CardManager.shuffle_deck(true_owner)

	return true


func try_execute_each_player_discard_then_draw_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Cada jugador Bota N carta(s) y tú Robas M carta(s)' (p.ej. Escamas de Dragón: 'cada jugador
	Bota tres cartas y tú Robas una carta') — mandatorio, sin 'puedes'. Cada jugador Bota del tope
	de su Castillo (no de la mano)."""
	var lower := ability_text.to_lower()
	if not ("cada jugador bota" in lower and "tú robas" in lower):
		return false

	var discard_rx := RegEx.new()
	discard_rx.compile("cada jugador bota (\\w+) cartas?")
	var dm := discard_rx.search(lower)
	var discard_amount: int = UniversalCardParser._parse_amount(dm.get_string(1)) if dm else 1

	var draw_rx := RegEx.new()
	draw_rx.compile("tú robas (\\w+) cartas?")
	var rm := draw_rx.search(lower)
	var draw_amount: int = UniversalCardParser._parse_amount(rm.get_string(1)) if rm else 1

	if await TriggerSystem.open_response_window(card, str(card.get("card_name")) if card else "Escamas de Dragón", controller_id):
		return true

	# "Bota" = las cartas del tope del Castillo al Cementerio, NO descartar de la mano: Escamas de
	# Dragón pedía descartar tres cartas de la mano.
	var card_name: String = str(card.get("card_name")) if card else "Escamas de Dragón"
	for pid in [controller_id, 1 - controller_id]:
		await ActionModule.mill(pid, discard_amount, false, card_name)

	await ActionModule.draw(controller_id, draw_amount, "etb_trigger", true)
	return true
