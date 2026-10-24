extends RefCounted
## GoldManagerTax — impuestos de coste sobre Talismanes/Tótems/Oro ("jugar Talismanes y Tótems
## cuesta un Oro adicional", Bernardo O'Higgins; "cuesta un Oro adicional si ya jugaste/pusiste uno
## este turno", Fuente de la Juventud) y descuentos al jugar ("muestra X de tu mano/Cementerio/en
## juego", El Rey y el Verdugo, Shiji; "Descarta una carta", voragh el devorador). GoldManager.gd
## los expone con reenvíos de una línea.
## _main es Main; el estado de GoldManager que hace falta (oro_colocado_conteo, _fix_mojibake()) se
## alcanza vía _main._gold_manager.

const CemeteryPopupScript = preload("res://scripts/ui/zones/CemeteryRevealPopup.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var _main: Node = null


func setup(main: Node) -> void:
	_main = main


func _register_talisman_totem_tax(card: Node) -> void:
	""""jugar Talismanes y Tótems cuesta un Oro adicional" (p.ej. Bernardo O'Higgins): impuesto en
	PaymentManager para cualquier Talismán/Tótem que pase por calcular_coste_real(), de los dos
	jugadores.
	PaymentManager.cost_modifiers se vacía en cada turno (descuentos de un uso como Lobo Sagrado),
	así que se re-registra en cada turn_started mientras la carta siga en juego y se desconecta
	solo cuando deja de estarlo. Al salir de juego lo limpia Card._exit_tree() →
	PaymentManager.remover_modificador_coste()."""
	var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return
	# _fix_mojibake(): la API trae "TalismÃ¡n"/"TÃ³tem" con doble codificación en varias cartas (p.ej.
	# Bernardo O'Higgins); sin normalizar, el impuesto no se detectaba.
	var lower: String = _main._gold_manager._fix_mojibake(ability_text).to_lower()
	var mentions_tax := "oro adicional" in lower
	var mentions_talisman_totem := ("talismán" in lower or "talisman" in lower) and ("tótem" in lower or "totem" in lower)
	if not (mentions_tax and mentions_talisman_totem):
		return

	var condition := func(c: Node) -> bool:
		return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM]

	PaymentManager.agregar_modificador_coste(card, 1, condition)
	# Afecta a una CATEGORÍA de cartas (todo Talismán/Tótem), no una sola — refresca toda la mano, no
	# un solo card_node.
	PaymentManager.refresh_all_hand_cost_badges()

	var reapply: Callable
	reapply = func(_player_id: int, _turn: int) -> void:
		if not is_instance_valid(card) or not card.is_in_play():
			if GameManager.turn_started.is_connected(reapply):
				GameManager.turn_started.disconnect(reapply)
			return
		PaymentManager.agregar_modificador_coste(card, 1, condition)
		PaymentManager.refresh_all_hand_cost_badges()
	GameManager.turn_started.connect(reapply)


func _register_talisman_second_play_tax(card: Node) -> void:
	"""Fuente de la Juventud: "A los jugadores les cuesta un Oro adicional jugar Talismanes si han
	jugado Talismanes este turno y les cuesta un Oro adicional poner Oros en juego si han puesto
	Oros en juego este turno". Condicional por jugador: solo la SEGUNDA del tipo en el turno paga;
	"a los jugadores" = ambos, según el owner_id de la carta.
	Talismanes: _play_talisman() registra 'talisman_played:<owner_id>' en turn_registry al resolver
	el primero. La mitad de Oros queda registrada pero sin efecto: poner un Oro no pasa por
	PaymentManager.calcular_coste_real() (no hay acción de pagar para colocar un Oro)."""
	var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return
	var lower: String = _main._gold_manager._fix_mojibake(ability_text).to_lower()
	if not ("oro adicional jugar talismanes" in lower and "oro adicional poner oros en juego" in lower):
		return

	var condition := func(c: Node) -> bool:
		var owner: int = c.owner_id if c.get("owner_id") != null else 0
		if c.get("card_type") == Constants.CardType.TALISMAN:
			return UniversalCardParser.turn_registry.was_used("talisman_played:%d" % owner, 0, GameManager.turn_serial)
		if c.get("card_type") == Constants.CardType.ORO:
			return _main._gold_manager.oro_colocado_conteo.get(owner, 0) >= 1
		return false

	PaymentManager.agregar_modificador_coste(card, 1, condition)
	PaymentManager.refresh_all_hand_cost_badges()

	var reapply2: Callable
	reapply2 = func(_player_id: int, _turn: int) -> void:
		if not is_instance_valid(card) or not card.is_in_play():
			if GameManager.turn_started.is_connected(reapply2):
				GameManager.turn_started.disconnect(reapply2)
			return
		PaymentManager.agregar_modificador_coste(card, 1, condition)
		PaymentManager.refresh_all_hand_cost_badges()
	GameManager.turn_started.connect(reapply2)


func _get_reveal_cost_reduction_pattern(card: Node) -> Dictionary:
	"""Detecta "Reduce su coste en un Oro por cada X que muestres de tu mano, Cementerio o que
	controles, hasta un mínimo de N" (p.ej. El Rey y el Verdugo: "...por cada Arma..."), que escala
	con la cantidad mostrada, y "Reduce su coste en un Oro si muestras un X (o Y) de tu mano o
	Cementerio" (p.ej. Shiji: "...un Arma o Tótem..."), singular: tope de 1 carta (max_reveal en
	_resolve_reveal_cost_reduction()). "Arma o Tótem" es una lista de tipos válidos.
	Es un descuento de un solo uso sobre la carta que se juega ahora (se resuelve en play_card()),
	no un modificador persistente como _register_talisman_totem_tax().
	Devuelve {} si no aplica; si no, {types: Array[Constants.CardType], allow_zero: bool, single:
	bool}."""
	var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return {}
	var lower: String = _main._gold_manager._fix_mojibake(ability_text).to_lower()
	if not ("reduce su coste" in lower and ("que muestres" in lower or "si muestras" in lower)):
		return {}
	# Enmascarar "reduce su coste en [un/N] Oro(s)" ANTES de buscar tipos: ahí "Oro" es la unidad del
	# descuento, no un tipo a mostrar (p.ej. Shiji).
	var cost_amount_rx := RegEx.new()
	cost_amount_rx.compile("reduce su coste en (?:un|una|\\d+|dos|tres|cuatro|cinco)\\s+oros?")
	var type_scan_text: String = cost_amount_rx.sub(lower, "", true)

	var wanted_types: Array = []
	if "arma" in type_scan_text:
		wanted_types.append(Constants.CardType.ARMA)
	if "aliado" in type_scan_text:
		wanted_types.append(Constants.CardType.ALIADO)
	if "talismán" in type_scan_text or "talisman" in type_scan_text:
		wanted_types.append(Constants.CardType.TALISMAN)
	if "tótem" in type_scan_text or "totem" in type_scan_text:
		wanted_types.append(Constants.CardType.TOTEM)
	if "oro" in type_scan_text:
		wanted_types.append(Constants.CardType.ORO)
	if wanted_types.is_empty():
		return {}
	var allow_zero := "mínimo de 0" in lower or "minimo de 0" in lower
	var single := "si muestras un" in lower or "si muestras una" in lower
	# Zonas de origen realmente mencionadas (p.ej. Shiji: 'de tu mano o Cementerio', SIN 'que
	# controles' — a diferencia de El Rey y el Verdugo que sí ofrece las tres). No ofrecer una zona que
	# el texto no menciona.
	var zones: Array = []
	if "tu mano" in lower:
		zones.append(0)
	if "cementerio" in lower:
		zones.append(1)
	if "que controles" in lower:
		zones.append(2)
	if zones.is_empty():
		zones = [0, 1, 2]
	return {"types": wanted_types, "allow_zero": allow_zero, "single": single, "zones": zones}


func _gather_showable_candidate_nodes(card_types, exclude_card: Node, source: int, player_id: int = 0) -> Array:
	"""Devuelve los NODOS reales mostrables de la mano/en juego (para click directo; arquitectura.md
	§10.14/§10.17). "Mostrar" (DAR) no mueve ni gasta nada. card_types acepta un int o un Array
	(Shiji: "un Arma o Tótem"). El Cementerio (source = 1) no tiene nodos persistentes: ver
	_build_cemetery_reveal_candidates() en _resolve_reveal_cost_reduction()."""
	var types_array: Array = card_types if card_types is Array else [card_types]
	var candidates: Array = []
	var hand_container = _main.player_hand if player_id == 0 else _main._opponent_fan
	match source:
		0:
			if not hand_container:
				return candidates
			for c in hand_container.cards:
				if c == exclude_card:
					continue
				if c.get("card_type") in types_array:
					candidates.append(c)
		2:
			var field_zones: Array = [_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo] if player_id == 0 \
				else [_main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo]
			for zone in field_zones:
				if not zone:
					continue
				for ally in zone.get_children():
					if ally.get("card_type") in types_array:
						candidates.append(ally)
					for weapon in ally.get("equipped_weapons") if ally.get("equipped_weapons") != null else []:
						if is_instance_valid(weapon) and weapon.get("card_type") in types_array:
							candidates.append(weapon)
	return candidates


const _CARD_TYPE_DISPLAY_NAMES: Dictionary = {
	0: "Oro", 1: "Aliado(s)", 2: "Arma(s)", 3: "Talismán(es)", 4: "Tótem(s)"
}


func _resolve_reveal_cost_reduction(card: Node, pattern: Dictionary, player_id: int = 0) -> int:
	"""Click directo sobre las cartas de todas las zonas permitidas a la vez (arquitectura.md §10.17):
	mano y en juego son Nodos visibles; el Cementerio usa un popup liviano con Nodos temporales
	(_open_cemetery_reveal_popup()). El "y/o" del texto = elegir UNA zona: lock_group_key hace que
	el primer click defina la zona (current_zone).
	Devuelve cuántas cartas se mostraron (0 si no había o no se eligió ninguna). No saca nada de su
	zona."""
	var types: Array = pattern.get("types", [])
	var type_name: String = " o ".join(types.map(func(t): return _CARD_TYPE_DISPLAY_NAMES.get(t, "carta(s)"))) if not types.is_empty() else "carta(s)"
	var zone_choices: Array = pattern.get("zones", [0, 1, 2])

	var candidates: Array = []
	if 0 in zone_choices:
		candidates.append_array(_gather_showable_candidate_nodes(types, card, 0, player_id))
	if 2 in zone_choices:
		candidates.append_array(_gather_showable_candidate_nodes(types, card, 2, player_id))
	var cemetery_popup: CanvasLayer = null
	if 1 in zone_choices:
		var popup_result: Dictionary = _open_cemetery_reveal_popup(types, player_id)
		cemetery_popup = popup_result.get("popup")
		candidates.append_array(popup_result.get("nodes", []))

	if candidates.is_empty():
		if is_instance_valid(cemetery_popup):
			cemetery_popup.queue_free()
		return 0

	# Tope de cartas útiles a mostrar: más allá de coste_base - piso no reducen nada (el piso de
	# calcular_coste_real() es 0 con allow_zero, 1 si no). 'single' (Shiji, no escala) agrega un tope
	# de 1; gana el menor.
	var floor_val: int = 0 if pattern.get("allow_zero", false) else 1
	var base_cost: int = int(card.get("card_cost")) if card.get("card_cost") != null else 0
	var useful_cap: int = maxi(base_cost - floor_val, 0)
	var max_selections: int = mini(candidates.size(), useful_cap) if useful_cap > 0 else candidates.size()
	if pattern.get("single", false):
		max_selections = mini(max_selections, 1)

	var lock_key := func(c: Node) -> Variant:
		if c.get("current_zone") == Constants.Zone.MANO:
			return 0
		elif c.get("current_zone") == Constants.Zone.CEMENTERIO:
			return 1
		else:
			return 2
	var chosen: Array = await _main._card_interaction.await_multi_target(
		"Muestra %s para reducir el coste (1 Oro c/u, misma zona)" % type_name, candidates, max_selections, lock_key, Callable(), true, null, player_id)

	if is_instance_valid(cemetery_popup):
		cemetery_popup.queue_free()
	return chosen.size()


const _PAY_REDUCTION_RX := "puedes (descartar o destruir|destruir o descartar|descartar|destruir|desterrar) " \
	+ "(una|un|dos) (carta|cartas|aliado|aliados|de tus cartas)( (?!de |que )[a-záéíóúñ]+(?: o [a-záéíóúñ]+)?)?" \
	+ "( de tu mano| que controles)? para (?:para )?reducir su coste en (un|dos) oros?( y no pueda ser anulado)?"


func _get_discard_cost_reduction_pattern(card: Node) -> Dictionary:
	"""Costo alternativo opcional "Puedes Descartar / Destruir / Desterrar <qué> para reducir su coste
	en N Oros", resuelto al jugar la carta: voragh el devorador ("una carta"), colaborador titan
	("Destruir o Descartar un Aliado Titán o Ignis"), "una carta que controles", "un Aliado Bestia",
	"un Aliado de tu mano"... Descartar = de la mano; Destruir = una carta propia en juego;
	Desterrar = de la mano ("de tu mano") o en juego ("que controles"). "...y no pueda ser Anulado"
	(corte letal): no_annul.
	{verbs, count, ally, races, where, reduce, no_annul} o {}."""
	var ability_text: String = str(card.get("card_ability")) if card.get("card_ability") != null else ""
	if ability_text.is_empty():
		return {}
	var lower: String = _main._gold_manager._fix_mojibake(ability_text).to_lower()
	var m := RegEx.create_from_string(_PAY_REDUCTION_RX).search(lower)
	if m == null:
		return {}
	var verbs: Array = []
	for v in ["descartar", "destruir", "desterrar"]:
		if v in m.get_string(1):
			verbs.append(v)
	var races: Array = []
	var race_part := m.get_string(4).strip_edges()
	if not race_part.is_empty():
		for r in race_part.split(" o "):
			races.append(r.strip_edges())
	return {"found": true, "verbs": verbs, "count": 2 if m.get_string(2) == "dos" else 1,
		"ally": m.get_string(3).begins_with("aliado"), "races": races,
		"where": m.get_string(5).strip_edges(), "reduce": 2 if m.get_string(6) == "dos" else 1,
		"no_annul": not m.get_string(7).is_empty()}


func _resolve_discard_cost_reduction(card: Node, player_id: int = 0, pattern: Dictionary = {}) -> int:
	"""Resuelve el costo alternativo de _get_discard_cost_reduction_pattern() ANTES de calcular
	coste_real (ver GoldManager.play_card()). 'Puedes' = opcional: ESC declina sin penalidad. Las
	cartas se Descartan / Destruyen / Destierran de verdad. Devuelve cuántos Oros descontar (0 si no
	se pagó)."""
	if pattern.is_empty():
		pattern = _get_discard_cost_reduction_pattern(card)
	if pattern.is_empty():
		return 0
	var hand_container = _main.player_hand if player_id == 0 else _main._opponent_fan
	var fits := func(c: Node) -> bool:
		if not is_instance_valid(c) or c == card:
			return false
		if pattern.ally and c.get("card_type") != Constants.CardType.ALIADO:
			return false
		if not pattern.races.is_empty():
			var raza := str(c.get("card_raza")).to_lower()
			if not pattern.races.any(func(r): return r.trim_suffix("s") in raza or r in raza):
				return false
		return true
	var candidates: Array = []
	var from_hand: bool = "descartar" in pattern.verbs or ("desterrar" in pattern.verbs and pattern.where != "que controles")
	var from_play: bool = "destruir" in pattern.verbs or ("desterrar" in pattern.verbs and pattern.where == "que controles")
	if from_hand and hand_container:
		candidates.append_array(hand_container.cards.filter(fits))
	if from_play:
		var zones: Array = PlayerSideScript.line_containers(_main, player_id)
		if not pattern.ally:
			zones.append(PlayerSideScript.gold_reserva(_main, player_id))
			zones.append(PlayerSideScript.oro_pagado(_main, player_id))
		for z in zones:
			if z:
				candidates.append_array(z.get_children().filter(func(c): return fits.call(c) and c.get("controller_id") == player_id))
	if candidates.size() < int(pattern.count) or PlayerSideScript.is_bot(player_id):
		return 0
	var verb_label := " o ".join(pattern.verbs.map(func(v): return v.capitalize()))
	var prompt := "Puedes %s %d carta%s para reducir el coste en %d (N para no hacerlo)" % [
		verb_label, pattern.count, "" if pattern.count == 1 else "s", pattern.reduce]
	var chosen: Array = []
	if int(pattern.count) == 1:
		var one: Node = await _main._card_interaction.await_target(prompt, func(c: Node) -> bool: return c in candidates, true, player_id)
		if one and is_instance_valid(one):
			chosen = [one]
	else:
		chosen = await _main._card_interaction.await_multi_target(prompt, candidates, int(pattern.count), Callable(), Callable(),
			true, null, player_id)
	if chosen.size() < int(pattern.count):
		return 0
	var title: String = str(card.get("card_name"))
	for c in chosen:
		var in_hand: bool = c.get("current_zone") == Constants.Zone.MANO
		if in_hand and "descartar" in pattern.verbs:
			await ActionModule.discard(player_id, [c], title, true)
		elif in_hand:
			CardManager.add_to_exile(player_id, PlayerSideScript.take_from_hand(_main, player_id, c))
		elif "destruir" in pattern.verbs:
			await ActionModule.destroy([c], card, false, true)
		else:
			await ActionModule.banish([c], card, true, false)
	return int(pattern.reduce)


func _open_cemetery_reveal_popup(card_types, player_id: int = 0) -> Dictionary:
	"""Popup liviano (SIN oscurecer el resto de la pantalla — a diferencia
	de ZoneViewerModule.open_cemetery_target_picker(), aquí mano/campo
	siguen siendo clickeables al mismo tiempo, ver _resolve_reveal_cost_
	reduction()) mostrando el Cementerio PROPIO con Nodos temporales
	interactivos, en una esquina de la pantalla. Returns: {popup:
	CanvasLayer, nodes: Array[Node]}."""
	var types_array: Array = card_types if card_types is Array else [card_types]
	var own_cemetery: Array = CardManager.get_cemetery(player_id).filter(func(d): return d.get("tipo", -1) in types_array)
	var nodes: Array = []
	if own_cemetery.is_empty():
		return {"popup": null, "nodes": nodes}

	return CemeteryPopupScript.open(_main, own_cemetery, player_id)
