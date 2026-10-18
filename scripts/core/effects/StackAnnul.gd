extends RefCounted
## StackAnnul — Anular / Cancelar sobre la PILA real (2026-10-14, revisión del
## mazo 170, docs/revision-mazo-170.md).
##
## Antes, "Anula X" destruía una carta que ya estaba en juego: un Talismán de
## respuesta nunca podía anular la carta o habilidad a la que respondía (esa
## carta todavía estaba en la pila, esperando su ventana). Ahora, si hay en la
## pila un objeto del rival que el texto puede anular/cancelar, se marca y el
## dueño de esa ventana lo maneja:
##   - Anular una carta jugada (Aliado, Arma, Tótem, Oro con ventana,
##     Talismán): no resuelve; el Aliado ya en el tablero se destruye (sin su
##     "Cuando entra en juego") y el Talismán va al Cementerio
##     (GoldManager._trigger_enter_play / TriggerSystem.open_response_window).
##   - Cancelar una habilidad (disparada o activada): no ocurre.
## Si no hay nada en la pila que calce, cada patrón sigue con su
## comportamiento de antes.
##
## Tipo de cada objeto: context.window_kind ("carta", "Talismán",
## "disparada", "activada"), que TriggerSystem.open_response_window() anota;
## los objetos ACTIVATED_ABILITY de ActionPipeline son "activada".
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
	var text: String = str(data.get("habilidad", "")).to_lower()
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


static func cost_of(obj: Dictionary) -> int:
	var node = card_of(obj)
	if node != null and is_instance_valid(node):
		return int(ContinuousEffectManager.get_modified_cost(node))
	return int(data_of(obj).get("coste", 0))


static func type_of(obj: Dictionary) -> int:
	return int(data_of(obj).get("tipo", -1))


static func try_from_text(card: Node, text: String, controller_id: int) -> Dictionary:
	"""Intenta Anular/Cancelar en la pila según el texto. Reconoce:
	  "Anula una carta (de coste N o menos)", "Anula un Aliado/Talismán
	  (oponente) (de coste N o menos)", "Anula o cancela la habilidad de un
	  Aliado/una carta (de coste N o menos)", "Cancela la habilidad de una
	  carta". Devuelve {} si no aplica (sin texto de Anular/Cancelar o nada
	  en la pila que calce); si no, {obj, applied}."""
	var lower := text.to_lower().replace("\n", " ")
	var rx := RegEx.new()
	rx.compile("\\b(anula o cancela la habilidad de|anula|cancela la habilidad de) (?:una carta|un (aliado|talismán|tótem|arma))( oponente)?(?: de coste (\\w+) o menos)?")
	var m := rx.search(lower)
	if not m:
		return {}
	var verb: String = m.get_string(1)
	var want_card: bool = verb.begins_with("anula")
	var want_ability: bool = verb.begins_with("anula o cancela") or verb.begins_with("cancela")
	var type_word: String = m.get_string(2)
	var max_cost: int = UniversalCardParser._parse_amount(m.get_string(4)) if not m.get_string(4).is_empty() else -1
	var type_map := {"aliado": Constants.CardType.ALIADO, "talismán": Constants.CardType.TALISMAN,
		"tótem": Constants.CardType.TOTEM, "arma": Constants.CardType.ARMA}
	var free_this_turn: bool = "o jugada sin pagar su coste" in lower
	var filter := func(obj: Dictionary) -> bool:
		if not type_word.is_empty() and type_of(obj) != type_map.get(type_word, -99):
			return false
		if max_cost >= 0:
			# Un Oro no tiene coste (2026-10-17): nunca es "de coste N o menos".
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
	return {"obj": obj, "applied": apply(obj, card)}
