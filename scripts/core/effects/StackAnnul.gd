extends RefCounted
## StackAnnul — Anular / Cancelar sobre la PILA real (docs/revision-mazo-170.md). Si en la pila hay
## un objeto del rival que el texto puede anular/cancelar, se marca y el dueño de esa ventana lo
## maneja:
## - Anular una carta jugada (Aliado, Arma, Tótem, Oro con ventana, Talismán): no resuelve; el
## Aliado ya en el tablero se destruye (sin su "Cuando entra en juego") y el Talismán va al
## Cementerio (GoldManager._trigger_enter_play / TriggerSystem.open_response_window).
## - Cancelar una habilidad (disparada o activada): no ocurre.
## Si no hay nada en la pila que calce, cada patrón sigue con su comportamiento propio.
## Tipo de cada objeto: context.window_kind ("carta", "Talismán", "disparada", "activada"), que
## anota TriggerSystem.open_response_window(); los ACTIVATED_ABILITY de ActionPipeline son
## "activada".
## Se usa con preload (ver §54).


static func _kind(obj: Dictionary) -> String:
	var k: String = str(obj.get("context", {}).get("window_kind", ""))
	if k.is_empty():
		return "activada" if obj.get("type") == ActionPipeline.StackObjectType.ACTIVATED_ABILITY else "disparada"
	return k


static func is_card_play(obj: Dictionary) -> bool:
	return _kind(obj) in ["carta", "Talismán"]


static func card_of(obj: Dictionary):
	"""Nodo de la carta (puede estar liberado) — sin tipo a propósito."""
	return obj.get("context", {}).get("source_card_node")


static func data_of(obj: Dictionary) -> Dictionary:
	var node = card_of(obj)
	if node != null and is_instance_valid(node) and node.get("card_data") is Dictionary:
		return node.card_data
	return obj.get("card_data", {})


static func find_target(controller_id: int, want_card: bool, want_ability: bool, filter: Callable = Callable()) -> Dictionary:
	"""El objeto del rival más cercano al tope que se puede Anular (carta
	jugada) o Cancelar (habilidad) y que pasa 'filter(obj) -> bool'. {} si
	no hay."""
	var stack: Array = ActionPipeline.get_stack()
	for i in range(stack.size() - 1, -1, -1):
		var obj: Dictionary = stack[i]
		if obj.get("was_annulled", false) or obj.get("was_cancelled", false):
			continue
		if int(obj.get("context", {}).get("controller_id", -1)) == controller_id:
			continue
		var card_play: bool = is_card_play(obj)
		if (card_play and not want_card) or (not card_play and not want_ability):
			continue
		if filter.is_valid() and not filter.call(obj):
			continue
		return obj
	return {}


static func protected_from_annul(obj: Dictionary) -> bool:
	var data: Dictionary = data_of(obj)
	var annul_text: String = str(data.get("habilidad", "")).to_lower()
	if "no puede ser anulad" in annul_text or annul_text.begins_with("no se puede anular") \
			or data.get("_no_annul", false):
		return true
	var node = card_of(obj)
	return node != null and is_instance_valid(node) and node.get_meta("protected_from_annul_this_turn", false)


static func protected_from_cancel(obj: Dictionary) -> bool:
	var data: Dictionary = data_of(obj)
	# Nu-galahad: "Tus Armas no pueden ser canceladas" protege a las Armas, no a sus propias
	# habilidades.
	var rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var ctrl := int(obj.get("context", {}).get("controller_id", -1))
	if rules.weapon_cancel_protected(data, ctrl):
		return true
	if obj.get("context", {}).get("_first_gold_ability", false) and rules.first_gold_ability_protected(ctrl):
		return true  # Crono Diamante
	# Rugido de Titán: "Prevén que una carta de nombre Ignis o Titán sea ... cancelada".
	var node = card_of(obj)
	if node != null and is_instance_valid(node) and int(node.get_meta("protected_from_cancel_turn", -1)) == GameManager.turn_serial:
		return true
	var text: String = str(data.get("habilidad", "")).to_lower().replace("tus armas no pueden ser canceladas", "")
	return "no pueden ser canceladas" in text or "su habilidad no puede ser cancelada" in text \
		or "ni su habilidad cancelada" in text or "no se puede anular ni cancelar su habilidad" in text


static func apply(obj: Dictionary, annuller_card: Node) -> bool:
	"""Anula (carta) o Cancela (habilidad) 'obj'. false si está protegido."""
	var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Main")
	var name: String = str(data_of(obj).get("nombre", obj.get("name", "esa carta")))
	var annuller_data: Dictionary = annuller_card.card_data if is_instance_valid(annuller_card) and annuller_card.get("card_data") is Dictionary else {}
	if is_card_play(obj):
		if protected_from_annul(obj):
			if main:
				main._update_debug("%s no puede ser Anulada" % name)
			return false
		# paso de la plaga: "hasta tu próximo turno, ... Anular tus Aliados cuesta un Oro adicional". Quien
		# Anula lo paga; si no puede, no la Anula.
		var target_ctrl := int(obj.get("context", {}).get("controller_id", -1))
		if target_ctrl >= 0 and type_of(obj) == Constants.CardType.ALIADO and RuleState.active("ally_annul_tax", target_ctrl) and main:
			var annuller := 1 - target_ctrl
			if not main._gold_manager.puede_pagar(1, -1, "", -1, annuller):
				main._update_debug("%s: Anularla cuesta un Oro adicional que no se puede pagar" % name)
				return false
			load("res://scripts/core/game/PlayerSide.gd").pay(main, annuller, 1)  # se cobra en segundo plano
			main._update_debug("Oro adicional por Anular %s" % name)
		obj["was_annulled"] = true
		obj["annuller"] = annuller_data
		if main:
			main._update_debug("%s es Anulada" % name)
	else:
		if protected_from_cancel(obj):
			if main:
				main._update_debug("La habilidad de %s no puede ser cancelada" % name)
			return false
		obj["was_cancelled"] = true
		obj["cancel_reason"] = "cancelled_by_effect"
		if main:
			main._update_debug("La habilidad de %s es Cancelada" % name)
	return true


## "Prevén un efecto" (Concilio de los Eternos, Camino del Guerrero): el efecto no se resuelve. No es
## Anular ni Cancelar: vale aunque "no pueda ser cancelado/Anulado" (y al revés). Una habilidad queda
## sin resolverse; un Talismán se resuelve sin efecto (el corte de kotoku-in). Las demás cartas
## jugadas no son "un efecto".
static func prevent(obj: Dictionary) -> bool:
	var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Main")
	var name: String = str(data_of(obj).get("nombre", obj.get("name", "ese efecto")))
	if is_card_play(obj):
		if type_of(obj) != Constants.CardType.TALISMAN:
			return false
		var controller: int = int(obj.get("context", {}).get("controller_id", -1))
		TriggerSystem._totem_patterns.register_kotoku_in_talisman_fizzle(controller)
	else:
		obj["was_cancelled"] = true
		obj["cancel_reason"] = "prevented"
	if main:
		main._update_debug("Se previene el efecto de %s" % name)
	return true


## El efecto rival (habilidad o Talismán) más cercano al tope de la pila, para prevenirlo. {} si no hay.
static func find_preventable(controller_id: int) -> Dictionary:
	return find_target(controller_id, true, true, func(o: Dictionary) -> bool:
		return not is_card_play(o) or type_of(o) == Constants.CardType.TALISMAN)


static func cost_of(obj: Dictionary) -> int:
	var node = card_of(obj)
	if node != null and is_instance_valid(node):
		return int(ContinuousEffectManager.get_modified_cost(node))
	return int(data_of(obj).get("coste", 0))


static func type_of(obj: Dictionary) -> int:
	return int(data_of(obj).get("tipo", -1))


static func try_from_text(card: Node, text: String, controller_id: int, dry_run: bool = false) -> Dictionary:
	"""Intenta Anular/Cancelar en la pila según el texto. Reconoce:
	  "Anula una carta (de coste N o menos)", "Anula un Aliado/Talismán
	  (oponente) (de coste N o menos)", "Anula o cancela la habilidad de un
	  Aliado/una carta (de coste N o menos)", "Cancela la habilidad de una
	  carta". Devuelve {} si no aplica (sin texto de Anular/Cancelar o nada
	  en la pila que calce); si no, {obj, applied}. dry_run: solo busca (no
	  aplica), p.ej. para ofrecer la opción en una elección."""
	var lower := text.to_lower().replace("\n", " ")
	var rx := RegEx.new()
	# "Anula un Talismán o Tótem(,) de coste 2 o menos" (conde dracula, san martin): dos tipos.
	rx.compile("\\b(anula o cancela la habilidad de|anula|cancela la habilidad de) (?:una carta|un (aliado|talismán|tótem|arma)"
		+ "(?: o (?:un )?(aliado|talismán|tótem|arma))?)( oponente)?,?(?: de coste (\\w+) o menos)?")
	var m := rx.search(lower)
	if not m:
		return {}
	var verb: String = m.get_string(1)
	var want_card: bool = verb.begins_with("anula")
	var want_ability: bool = verb.begins_with("anula o cancela") or verb.begins_with("cancela")
	var type_word: String = m.get_string(2)
	var type_word2: String = m.get_string(3)
	var max_cost: int = UniversalCardParser._parse_amount(m.get_string(5)) if not m.get_string(5).is_empty() else -1
	var type_map := {"aliado": Constants.CardType.ALIADO, "talismán": Constants.CardType.TALISMAN,
		"tótem": Constants.CardType.TOTEM, "arma": Constants.CardType.ARMA}
	var free_this_turn: bool = "o jugada sin pagar su coste" in lower
	var filter := func(obj: Dictionary) -> bool:
		# DAR abril 2026 (Respuesta): no se responde a lo que no se puede Anular/Cancelar.
		if (is_card_play(obj) and protected_from_annul(obj)) or (not is_card_play(obj) and protected_from_cancel(obj)):
			return false
		if not type_word.is_empty() and type_of(obj) != type_map.get(type_word, -99) \
				and (type_word2.is_empty() or type_of(obj) != type_map.get(type_word2, -99)):
			return false
		if max_cost >= 0:
			# Un Oro no tiene coste: nunca es "de coste N o menos".
			if type_of(obj) == Constants.CardType.ORO:
				return false
			var ok_cost: bool = cost_of(obj) <= max_cost
			if not ok_cost and free_this_turn:
				var node = card_of(obj)
				ok_cost = node != null and is_instance_valid(node) and node.get_meta("played_free", false)
			if not ok_cost:
				return false
		return true
	var obj: Dictionary = find_target(controller_id, want_card, want_ability, filter)
	if obj.is_empty():
		return {}
	if dry_run:
		return {"obj": obj, "applied": false}
	return {"obj": obj, "applied": apply(obj, card)}
