extends RefCounted
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
## BanishOpponentPatterns — una de las mitades de LookAndPlayResolver.gd (fachada; ahí está la lista
## completa). Destierro/Botar/Anular dirigidos al oponente: ignis desatado, shoki, colaborador
## titan, Ngenechén, ea poe, Asmodeus, cuervo nocturno, resistencia de acero, Duelo de Dragones,
## Culto a la Muerte, Ciempiés-SP, Dragón Dorado, Carcosa, estacion gaia, templo de hatshepsut,
## necro-titan, akuma el terrible, akari musashi. Incluye _register_talisman_surcharge_once.

var _main: Node


func setup(main: Node) -> void:
	_main = main


func try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Destierra un Aliado oponente de coste 3 o menos y busca en tu Castillo o Cementerio una carta
	Ignis o Titán, juégalo reduciendo su coste en un Oro hasta un mínimo de 0' (ignis desatado) —
	dispara tanto en 'entra en juego' como en 'ataca'."""
	var lower := ability_text.to_lower()
	if not ("destierra un aliado oponente de coste 3 o menos y busca" in lower and "ignis o tit" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction or not main._gold_manager:
		return true
	var hand_container = main.player_hand if controller_id == 0 else main._opponent_fan
	if not hand_container:
		return true
	var opponent_id: int = 1 - controller_id
	var filter := func(c: Node) -> bool:
		if c.get("card_type") != Constants.CardType.ALIADO:
			return false
		if c.get("owner_id") != opponent_id:
			return false
		# current_zone (no get_parent()): un Arma equipada es hija de su portador, no de la línea
		# (arquitectura.md §10.5).
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, 3)
	var target: Node = await main._card_interaction.await_target("Elige un Aliado oponente de coste 3 o menos para desterrar", filter, true, controller_id)
	if target and is_instance_valid(target):
		await ActionModule.banish([target], card, true)

	# El selector del tablero con tu Castillo y tu Cementerio a la vez, en vez del popup "¿Dónde
	# buscar?". El Destierro de arriba ya consultó Prevención por su cuenta (banish) — esta ventana es
	# para la búsqueda+juego con descuento, sin cobertura propia.
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	var hand_before: Array = hand_container.cards.duplicate()
	var result: Dictionary = await ActionModule.search_zones(controller_id,
		[Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO], {"raza": ["Ignis", "Titán", "Titan"]}, 1, true, false, false,
		card, Constants.Zone.MANO)
	if result.get("selected", []).is_empty():
		return true

	var found_node: Node = null
	for c in hand_container.cards:
		if c not in hand_before:
			found_node = c
			break
	if not is_instance_valid(found_node):
		return true

	var applies_to_this_card := func(c: Node) -> bool:
		return c == found_node
	PaymentManager.agregar_modificador_coste(found_node, -1, applies_to_this_card, true)
	if found_node.has_method("refresh_cost_badge"):
		found_node.refresh_cost_badge()
	await main._gold_manager.play_card(found_node)
	return true


func try_execute_banish_two_from_one_cemetery_then_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'En tu Fase Final, Destierra dos cartas de un Cementerio. Luego, Roba una carta' (shoki) — 'un
	Cementerio' (sin posesivo, singular) = el jugador elige DE CUÁL de los dos, luego saca ambas de
	ESE MISMO (a diferencia de 'los Cementerios', que mezcla el pool de ambos)."""
	var lower := ability_text.to_lower()
	if not ("destierra dos cartas de un cementerio" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	# Pila de Respuesta Universal (docs/plans/2026-09-09-pila-respuesta-universal-design.md): ya se
	# declaró todo (de qué Cementerio); aquí se abre la ventana para el rival antes de ejecutar el
	# efecto.
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true  # anulado/cancelado durante la ventana — no se ejecuta nada
	# Selector con los dos Cementerios, las dos de UNO solo.
	await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, 2, true, card,
		Constants.Zone.DESTIERRO, false, true)
	await ActionModule.draw(controller_id, 1, "etb_trigger", true)
	return true


func try_execute_banish_opponent_castillo_by_titan_ignis_cost_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Destierra tantas cartas del tope del Castillo oponente como coste sumen los Aliados Titán o
	Ignis que controles y Roba dos cartas' (colaborador titan). El descuento opcional por
	Destruir/Descartar un Aliado Titán o Ignis propio es GoldManagerTax._resolve_discard_cost_reduction()."""
	var lower := ability_text.to_lower()
	if not ("destierra tantas cartas del tope del castillo oponente como coste sumen los aliados titán o ignis que controles" in lower
			or "destierra tantas cartas del tope del castillo oponente como coste sumen los aliados titan o ignis que controles" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var own_fields_titan: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] if controller_id == 0 else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
	var total_cost := 0
	for field in own_fields_titan:
		if not field:
			continue
		for c in field.get_children():
			if c.get("card_type") == Constants.CardType.ALIADO:
				var raza: String = str(c.get("card_raza")).to_lower()
				if raza == "titán" or raza == "titan" or raza == "ignis":
					total_cost += ContinuousEffectManager.get_modified_cost(c)
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	if total_cost > 0:
		await ActionModule.mill(1 - controller_id, total_cost, true, "etb_trigger", true)
	await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	return true


func try_execute_banish_opponent_cost_sum_six_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego Destierra cartas oponentes cuyos costes sumen hasta 6' (Ngenechén) —
	solo esta cláusula. Las otras: 'Al comienzo del turno oponente...' en MechanicPatterns y la
	prevención en EffectController (registro de prevenciones)."""
	var lower := ability_text.to_lower()
	# "cuyos coste sumen" en una impresión (errata del texto).
	if not ("destierra cartas oponentes cuyos costes sumen hasta 6" in lower or "destierra cartas oponentes cuyos coste sumen hasta 6" in lower):
		return false
	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var opponent_cards: Array = []
	var rival_fields: Array = [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo, main.opponent_gold] if controller_id == 0 \
		else [main.player_field, main.player_linea_ataque, main.player_linea_apoyo, main.player_gold]
	for field in rival_fields:
		if field:
			opponent_cards.append_array(field.get_children())
	if opponent_cards.is_empty():
		return true
	if not main._card_interaction:
		return true
	# Click directo con presupuesto en vivo (dynamic_filter, ver arquitectura.md §10.20/Tempilcahue) en
	# vez del modal viejo que reintentaba toda la selección si te pasabas de 6.
	var budget_filter := func(chosen_so_far: Array, c: Node) -> bool:
		var sum_cost: int = 0
		for x in chosen_so_far:
			sum_cost += int(x.get("card_cost")) if x.get("card_cost") != null else 0
		var c_cost: int = int(c.get("card_cost")) if c.get("card_cost") != null else 0
		return sum_cost + c_cost <= 6
	var chosen: Array = await main._card_interaction.await_multi_target(
		"Destierra cartas rivales cuyos costes sumen hasta 6", opponent_cards, -1, Callable(), budget_filter, true, null, controller_id)
	if not chosen.is_empty():
		# Sin ventana genérica a propósito: banish() con can_be_prevented = true ya consulta Prevención;
		# abrirla aquí preguntaría dos veces por el mismo efecto.
		await ActionModule.banish(chosen, card, true)
	return true


func try_execute_pay_x_banish_opponent_castillo_draw_per_talisman_totem_pattern(ability_text: String, controller_id: int) -> bool:
	"""ea poe: "Cuando lo juegues, puedes pagar cualquier cantidad de Oros. Destierra tantas cartas
	del tope del Castillo oponente como Oros hayas pagado por este Talismán más dos. Por cada
	Talismán o Tótem Desterrado de esta forma, Roba una carta". El "+2" va fijo en el código: el
	texto en el caché local llega con codificación rota ('m�s dos') y el ancla de detección evita
	esos caracteres.
	No usa ActionModule.mill(): su fallback (EffectController._mill_cards_fallback()) deja
	'milled_cards' vacío para el Destierro y no se sabría el tipo de cada carta. Se mueve carta por
	carta sobre CardManager.get_deck()/get_exile() (como Tyet)."""
	var lower := ability_text.to_lower()
	if not ("puedes pagar cualquier cantidad de oros" in lower
			and "destierra tantas cartas del tope del castillo oponente como oros hayas pagado" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._gold_manager:
		return true

	var disponible: int = main._gold_manager.get_oro_disponible(controller_id)
	var options: Array = []
	for n in range(disponible + 1):
		options.append("Pagar %d Oro%s" % [n, "s" if n != 1 else ""])
	var paid: int = await SelectionManager.await_choice(main, "¿Cuántos Oros quieres pagar?", options, controller_id)
	if paid < 0:
		paid = 0
	if paid > 0:
		await main._gold_manager.pagar_coste(paid, -1, "", -1, controller_id)
		PaymentManager.registrar_pago(paid)

	var amount_to_banish: int = paid + 2
	var opponent_id: int = 1 - controller_id
	var banished_talisman_totem_count: int = 0
	for card_data in CardManager.banish_from_deck(opponent_id, amount_to_banish, false, controller_id):
		var tipo: int = card_data.get("tipo", -1)
		if tipo == Constants.CardType.TALISMAN or tipo == Constants.CardType.TOTEM:
			banished_talisman_totem_count += 1

	if banished_talisman_totem_count > 0:
		await ActionModule.draw(controller_id, banished_talisman_totem_count, "etb_trigger", true)
	return true


func try_execute_opponent_hand_cost_max_to_bottom_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Cuando entra en juego, tu oponente pone sus cartas de coste 2 o menos en el fondo del
	Castillo' (Asmodeus) — TODAS las cartas de coste ≤2 de la mano rival, sin elección (no dice
	'puedes'), al fondo de su propio mazo."""
	var lower := ability_text.to_lower()
	if not ("tu oponente pone sus cartas de coste 2 o menos en el fondo del castillo" in lower):
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
	if not opponent_hand_container or not opponent_hand_container.has_method("get_cards"):
		return true
	if await TriggerSystem.open_response_window(card, "Asmodeus", controller_id):
		return true
	var opponent_hand: Array = opponent_hand_container.get_cards()
	var to_move: Array = []
	for c in opponent_hand:
		if is_instance_valid(c) and ContinuousEffectManager.cost_at_most(c, 2):
			to_move.append(c)
	var deck: Array = CardManager.get_deck(opponent_id)
	for c in to_move:
		var data: Dictionary = c.card_data.duplicate()
		data["esta_oculta"] = true
		opponent_hand_container.remove_card(c, true)
		deck.append(data)
	if not to_move.is_empty() and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func try_execute_opponent_mill_six_exile_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Tu oponente Destierra seis cartas del tope de su Castillo' (cuervo nocturno) — solo la
	cláusula incondicional. 'Puedes poner esta y otra carta de tu mano en el fondo de tu Castillo y
	Robar dos cartas' es activada desde la mano, por el mismo camino que Tyet
	(HandCementerioAbilityHandler._activate_tyet_mill_and_draw)."""
	var lower := ability_text.to_lower()
	# Impresión nueva: "Destierra seis cartas del tope del Castillo oponente".
	if not ("tu oponente destierra seis cartas del tope de su castillo" in lower
			or "destierra seis cartas del tope del castillo oponente" in lower):
		return false
	# ActionModule.mill() no consulta Prevención adentro (a diferencia de
	# destroy()/banish()) — le corresponde la ventana genérica.
	if await TriggerSystem.open_response_window(card, "cuervo nocturno", controller_id):
		return true
	await ActionModule.mill(1 - controller_id, 6, true, "etb_trigger", true)
	return true


func try_execute_search_three_opponent_castillo_banish_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Busca tres cartas de distinto tipo en el Castillo oponente, Destiérralas y Roba una carta'
	(resistencia de acero) — simplificación conocida: no se fuerza 'de distinto tipo'
	(ActionModule. search no tiene ese filtro, solo distinct_names por NOMBRE)."""
	var lower := ability_text.to_lower()
	if not ("busca tres cartas de distinto tipo en el castillo oponente, destiérralas y roba una carta" in lower):
		return false
	var opponent_id: int = 1 - controller_id
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	await ActionModule.search(opponent_id, Constants.Zone.CASTILLO, {}, 3, true, false, false, card, Constants.Zone.DESTIERRO, false, controller_id)
	await ActionModule.draw(controller_id, 1, "etb_trigger", true)
	return true


func try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""cruzar el bosque: "Sube una carta oponente de coste 2 o menos a la mano o Destruye hasta dos
	cartas de coste 1 o menos. Roba dos cartas" — elección A/B + Robo. No cubre la variante de
	reingreso desde el Destierro (Barajarla en su Castillo al resolver): play_card_from_exile() no
	tiene override de destino."""
	var lower := ability_text.to_lower()
	if not ("sube una carta oponente de coste 2 o menos a la mano o destruye hasta dos cartas de coste 1 o menos" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var opponent_id: int = 1 - controller_id
	var choose_raise: bool = await SelectionManager.await_two_choice(
		main, str(card.get("card_name")), "Subir una carta oponente de coste 2 o menos de su Cementerio a la mano", "Destruir hasta dos cartas de coste 1 o menos", controller_id)

	if choose_raise:
		if main._zone_viewer:
			# Click directo en el Cementerio rival en vez del modal de lista viejo.
			var eligible_filter := func(c: Node) -> bool:
				return c.owner_id == opponent_id and ContinuousEffectManager.data_cost_at_most(c.card_data, 2)
			var picked_list: Array = await main._zone_viewer.open_cemetery_target_picker(
				"Sube una carta oponente de coste 2 o menos a su mano", eligible_filter, 1, "cemetery", false, false, controller_id)
			# _put_found_card_into_play() no consulta Prevención (a diferencia
			# de destroy(), usado en la otra rama) — sí le corresponde la
			# ventana genérica aquí.
			if not picked_list.is_empty() and not await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
				var picked_data: Dictionary = picked_list[0].data
				var idx: int = CardManager.get_cemetery(opponent_id).find(picked_data)
				if idx >= 0:
					CardManager.remove_from_cemetery(opponent_id, idx)
					await ActionModule._put_found_card_into_play(main, opponent_id, picked_data, false)
	else:
		var filter := func(c: Node) -> bool:
			# current_zone en vez de get_parent (ver §10.5)
			if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
					Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]:
				return false
			return ContinuousEffectManager.cost_at_most(c, 1)
		# Selección de hasta 2 objetivos en juego vía clicks sucesivos.
		var destroyed := 0
		while destroyed < 2:
			var target: Node = await main._card_interaction.await_target(
				"Elige una carta de coste 1 o menos para destruir (%d/2, cancela para terminar)" % destroyed, filter, true, controller_id)
			if not target or not is_instance_valid(target):
				break
			await ActionModule.destroy([target], card, true, true)
			destroyed += 1

	# El Robo es un efecto aparte, incondicional, sin cobertura propia (la
	# rama elegida arriba ya consultó Prevención/su propia ventana por su
	# lado) — ventana propia aquí.
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	await ActionModule.draw(controller_id, 2, "etb_trigger", true)
	return true


func try_execute_annul_non_ally_banish_or_cancel_ability_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Elige un efecto: - Anula una carta de coste 2 o menos que no sea Aliado y Destierra esa carta.
	- Cancela la habilidad de una carta y tu oponente no puede utilizar más habilidades de cartas
	con ese nombre este turno' (Culto a la Muerte) — elección A/B. Hoy lo resuelve antes
	Deck170Patterns.try_annul_on_stack() (_culto_a_la_muerte, con KeywordManager.lock_name_this_turn
	para la rama B)."""
	var lower := ability_text.to_lower()
	if not ("anula una carta de coste 2 o menos que no sea aliado y destierra esa carta" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var choose_banish: bool = await SelectionManager.await_two_choice(
		main, str(card.get("card_name")), "Anular y Desterrar una carta de coste 2 o menos (no Aliado)", "Cancelar la habilidad de una carta", controller_id)

	if choose_banish:
		var filter := func(c: Node) -> bool:
			if c.get("card_type") == Constants.CardType.ALIADO:
				return false
			# current_zone en vez de get_parent (ver §10.5)
			if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
					Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]:
				return false
			return ContinuousEffectManager.cost_at_most(c, 2)
		var target: Node = await main._card_interaction.await_target("Elige una carta de coste 2 o menos (no Aliado) para anular y desterrar", filter, true, controller_id)
		if target and is_instance_valid(target):
			if TriggerSystem._targeted_executor._target_text_denies(target, ["no puede ser anulad"]):
				main._update_debug("%s no puede ser anulada" % str(target.get("card_name")))
			else:
				# Sin ventana genérica aquí: banish/silence_card ya consultan Prevención adentro por su cuenta.
				await ActionModule.banish([target], card, true)
	else:
		var filter2 := func(c: Node) -> bool:
			# current_zone en vez de get_parent (ver §10.5)
			return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE,
				Constants.Zone.LINEA_APOYO, Constants.Zone.RESERVA_ORO]
		var target2: Node = await main._card_interaction.await_target("Elige una carta para cancelar su habilidad", filter2, true, controller_id)
		if target2 and is_instance_valid(target2):
			if TriggerSystem._targeted_executor._target_text_denies(target2, ["no puede perder su habilidad", "no pierde su habilidad"]):
				main._update_debug("%s no pierde su habilidad" % str(target2.get("card_name")))
			else:
				await KeywordManager.silence_card(target2, card, "permanent")
	return true


func try_execute_annul_cost_max_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Anula una carta de coste N o menos' (p.ej. Ciempiés-SP/cienpies sp: 'Única. Anula una carta de
	coste 3 o menos.') — el genérico ANNUL de UniversalCardParser solo reconoce 'anula un/el
	Aliado' (sin filtro de coste ni otros tipos), así que este patrón cubre la forma con tope de
	coste sobre cualquier objetivo (Aliado/Arma/Tótem). Reusa _select_annul_target_cost_filter
	(Paladín Bestiarium)."""
	var lower := ability_text.to_lower()
	var rx := RegEx.new()
	rx.compile("anula una carta de coste (\\d+) o menos")
	var m := rx.search(lower)
	if not m:
		return false

	var max_cost: int = int(m.get_string(1))
	var target: Node = await TriggerSystem._targeted_executor._select_annul_target_cost_filter(
		"Elige una carta de coste %d o menos para anular" % max_cost, max_cost, controller_id)
	if not target or not is_instance_valid(target):
		return true
	var main := _main.get_node_or_null("/root/Main")
	if TriggerSystem._targeted_executor._target_text_denies(target, ["no puede ser anulad"]):
		if main:
			main._update_debug("%s no puede ser anulada" % str(target.get("card_name")))
		return true
	# Sin ventana genérica aquí: destroy con can_be_prevented= true (4to arg) ya consulta Prevención
	# (Estaca) adentro.
	await ActionModule.destroy([target], card, true, true)
	return true


func try_execute_annul_then_shuffle_hand_by_cost_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Anula una carta. Luego, Baraja tantas cartas de tu mano como coste tenga' (Dragón Dorado) —
	'Anula una carta' SIN tope de coste (a diferencia de try_execute_annul_cost_max_pattern), y
	'Luego' depende de que la anulación haya resuelto de verdad (se lee el coste de la carta
	anulada, DAR: si no se anuló nada, 'Luego' no corre)."""
	var lower := ability_text.to_lower()
	if not ("anula una carta. luego, baraja tantas cartas de tu mano como coste tenga" in lower):
		return false

	var target: Node = await TriggerSystem._targeted_executor._select_annul_target_cost_filter(
		"Elige una carta para anular", 999, controller_id)
	if not target or not is_instance_valid(target):
		return true
	var main := _main.get_node_or_null("/root/Main")
	if TriggerSystem._targeted_executor._target_text_denies(target, ["no puede ser anulad"]):
		if main:
			main._update_debug("%s no puede ser anulada" % str(target.get("card_name")))
		return true
	var target_cost: int = ContinuousEffectManager.get_modified_cost(target)
	await ActionModule.destroy([target], card, true, true)

	if target_cost > 0 and main and main._card_interaction:
		var hand_container = main.player_hand if controller_id == 0 else main._opponent_fan
		if hand_container:
			var hand_cards: Array = hand_container.cards.duplicate()
			var amount: int = mini(target_cost, hand_cards.size())
			if amount > 0:
				# Click directo en la mano. Costo todo o nada de 'amount' cartas exactas (como Belta, §10.19):
				# si elige menos, no se mueve nada.
				var picked: Array = await main._card_interaction.await_multi_target(
					"Baraja %d carta(s) de tu mano" % amount, hand_cards, amount, Callable(), Callable(), true, null, controller_id)
				# 'Luego' (DAR): este segundo efecto solo llega aquí si el primero
				# (Anular, ya resuelto arriba) resolvió de verdad — ventana propia
				# porque este barajado manipula la mano/mazo directo, sin pasar
				# por return_to_deck() (que sí consulta Prevención solo, sin
				# ventana genérica).
				if picked.size() < amount or await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
					return true
				for node in picked:
					if is_instance_valid(node):
						var data: Dictionary = node.card_data.duplicate()
						hand_container.remove_card(node, true)
						CardManager.get_deck(controller_id).append(data)
				CardManager.shuffle_deck(controller_id)
				AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (Dragón Dorado)")
	return true


func try_execute_opponent_mill_four_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Al comienzo de tu turno y cuando salga del juego, tu oponente Bota cuatro cartas' (Carcosa) —
	dispara tanto en on_turn_start como en on_leave_play (mismo dispatcher compartido)."""
	var lower := ability_text.to_lower()
	if not ("tu oponente bota cuatro cartas" in lower):
		return false
	if await TriggerSystem.open_response_window(card, "Carcosa", controller_id):
		return true
	await ActionModule.mill(1 - controller_id, 4, false, "etb_trigger", true)
	return true


func try_execute_draw_discard_opponent_mill_exile_pattern(ability_text: String, controller_id: int, card: Node = null) -> bool:
	"""'Cuando entra en juego, Roba dos cartas, Descarta una carta y tu oponente Destierra dos cartas
	del tope de su Castillo' (estacion gaia)."""
	var lower := ability_text.to_lower()
	if not ("roba dos cartas, descarta una carta y tu oponente destierra dos cartas del tope de su castillo" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var own_hand_container_gaia = main.player_hand if controller_id == 0 else main._opponent_fan
	if not own_hand_container_gaia:
		return true
	# Ventana única para las 3 partes (robar/descartar/mill oponente) — sin
	# objetivos puntuales que declarar antes (el descarte es al azar/elegido
	# solo dentro, el mill es del tope, sin target).
	if await TriggerSystem.open_response_window(card, "estacion gaia", controller_id):
		return true
	await ActionModule.draw(controller_id, 2, "etb_trigger", true)

	var hand_cards: Array = own_hand_container_gaia.cards.duplicate()
	if not hand_cards.is_empty():
		var to_discard: Array = await _main._targeted_executor._select_hand_cards_for_discard(hand_cards, 1, controller_id)
		if not to_discard.is_empty():
			await ActionModule.discard(controller_id, to_discard, "etb_trigger", true)

	var opponent_id: int = 1 - controller_id
	await ActionModule.mill(opponent_id, 2, true, "etb_trigger", true)
	return true


func try_execute_shuffle_or_banish_opponent_cost_max_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, Baraja o Destierra una carta oponente de coste N o menos' (templo de
	hatshepsut) — objetivo único, elección A/B sobre el MISMO objetivo (se elige el objetivo
	primero, después qué hacerle — 'baraja o destierra' aplica a la misma carta)."""
	var lower := ability_text.to_lower()
	var cost_rx := RegEx.new()
	cost_rx.compile("baraja o destierra una carta oponente de coste (\\d+) o menos")
	var m := cost_rx.search(lower)
	if not m:
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var max_cost: int = int(m.get_string(1))
	var opponent_id: int = 1 - controller_id
	var filter := func(c: Node) -> bool:
		if c.get("owner_id") != opponent_id:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		if c.get("current_zone") not in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]:
			return false
		return ContinuousEffectManager.cost_at_most(c, max_cost)
	var target: Node = await main._card_interaction.await_target("Elige una carta oponente de coste %d o menos" % max_cost, filter, true, controller_id)
	if not target or not is_instance_valid(target):
		return true

	var choose_banish: bool = await SelectionManager.await_two_choice(
		main, str(card.get("card_name")), "Barajarla", "Desterrarla", controller_id)
	# Sin ventana genérica aquí: banish/return_to_deck ya consultan Prevención adentro por su cuenta en
	# las dos ramas.
	if choose_banish:
		await ActionModule.banish([target], card, true)
	else:
		var target_owner: int = target.controller_id if target.get("controller_id") != null else opponent_id
		if await ActionModule.return_to_deck(target, target_owner, true, card):
			CardManager.shuffle_deck(target_owner)
	return true


func try_execute_search_two_distinct_names_banish_or_cemetery_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, busca en un Castillo dos cartas de distinto nombre y ponlas en el
	Destierro o Cementerio de su dueño' (necro-titan) — 'de su dueño' = el destino es del dueño de
	CADA carta buscada (search ya lo hace así, ver docstring de ActionModule.search: 'el destino
	también es SUYO'). 'Destierro o Cementerio' = una elección para ambas cartas."""
	var lower := ability_text.to_lower()
	if not ("busca en un castillo dos cartas de distinto nombre y ponlas en el destierro o cementerio" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var to_banish: bool = await SelectionManager.await_two_choice(
		main, "necro-titan", "Ponerlas en el Destierro", "Ponerlas en el Cementerio", controller_id)
	var destination: int = Constants.Zone.DESTIERRO if to_banish else Constants.Zone.CEMENTERIO
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	await ActionModule.search_either_owner(controller_id, [Constants.Zone.CASTILLO], {}, 2, true, card, destination, true)
	return true


func try_execute_banish_cost_or_search_two_banish_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego, Destierra una carta de coste 2 o menos o busca dos cartas en un
	Castillo y Destiérralas' (akuma el terrible) — elección A/B."""
	var lower := ability_text.to_lower()
	if not ("destierra una carta de coste 2 o menos o busca dos cartas en un castillo" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main:
		return true
	var choose_direct: bool = await SelectionManager.await_two_choice(
		main, "akuma el terrible", "Desterrar una carta de coste 2 o menos", "Buscar dos cartas en un Castillo y Desterrarlas", controller_id)
	if choose_direct:
		var target: Node = await _main._targeted_executor._select_banish_target_cost_filter("Elige una carta de coste 2 o menos para desterrar", 2, controller_id)
		# Sin ventana genérica aquí: banish ya consulta Prevención adentro.
		if target and is_instance_valid(target):
			await ActionModule.banish([target], card, true)
	else:
		if not await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
			await ActionModule.search_either_owner(controller_id, [Constants.Zone.CASTILLO], {}, 2, true, card,
				Constants.Zone.DESTIERRO)
	return true


func try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern(ability_text: String, card: Node, controller_id: int) -> bool:
	"""'Cuando entra en juego o ataque, Destierra una carta oponente que no sea Oro.... A tu oponente
	le cuesta un Oro adicional jugar Talismanes' (akari musashi) — esta función solo cubre el
	Destierro dirigido (la sobretasa de Talismanes se registra aparte, una sola vez, desde el mismo
	llamador vía _register_talisman_surcharge_once)."""
	var lower := ability_text.to_lower()
	if not ("destierra una carta oponente que no sea oro" in lower):
		return false

	var main := _main.get_node_or_null("/root/Main")
	if not main or not main._card_interaction:
		return true
	var opponent_id: int = 1 - controller_id
	var filter := func(c: Node) -> bool:
		if c.get("card_type") == Constants.CardType.ORO:
			return false
		if c.get("owner_id") != opponent_id:
			return false
		# current_zone en vez de get_parent (ver §10.5)
		return c.get("current_zone") in [Constants.Zone.LINEA_DEFENSA, Constants.Zone.LINEA_ATAQUE, Constants.Zone.LINEA_APOYO]
	# Sin cartas válidas no se pide objetivo: pedía elegir aunque el oponente no tuviera cartas.
	var has_target := false
	for container in PlayerSideScript.line_containers(main, opponent_id):
		for c in container.get_children():
			if is_instance_valid(c) and filter.call(c):
				has_target = true
	var target: Node = null
	if has_target:
		target = await main._card_interaction.await_target("Elige una carta oponente (que no sea Oro) para desterrar", filter, true, controller_id)
	else:
		main._update_debug("%s: tu oponente no tiene cartas que no sean Oro para desterrar" % str(card.card_name))
	# Sin ventana genérica aquí: banish ya consulta Prevención adentro.
	if target and is_instance_valid(target):
		await ActionModule.banish([target], card, true)

	# La sobretasa a Talismanes rivales es un efecto aparte, sin cobertura
	# propia (no pasa por destroy/banish/silence/return_to_deck).
	if await TriggerSystem.open_response_window(card, str(card.card_name), controller_id):
		return true
	_register_talisman_surcharge_once(card, controller_id)
	return true


func _register_talisman_surcharge_once(card: Node, controller_id: int) -> void:
	"""'A tu oponente le cuesta un Oro adicional jugar Talismanes' — se
	registra UNA vez mientras 'card' siga en juego (PaymentManager.
	remover_modificador_coste() se llama solo desde Card._exit_tree(), así
	que no hace falta desregistrar a mano). meta 'talisman_surcharge_
	registered' evita duplicar el modificador si el patrón ETB se dispara
	más de una vez (p.ej. 'entra en juego o ataque' puede re-entrar la
	misma instancia varias veces sin volver a salir del juego)."""
	if not is_instance_valid(card) or card.get_meta("talisman_surcharge_registered", false):
		return
	card.set_meta("talisman_surcharge_registered", true)
	var opponent_id: int = 1 - controller_id
	var condition := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.TALISMAN and c.get("owner_id") == opponent_id
	PaymentManager.agregar_modificador_coste(card, 1, condition, false)


