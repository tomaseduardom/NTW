extends RefCounted
## PlayableGlow — qué cartas de la mano se pueden jugar AHORA que el jugador tiene la prioridad fuera
## de su Vigilia, para que brillen: dorado si es una respuesta (Talismán de Anular/Cancelar o de
## respuesta instantánea en una Ventana de Respuesta; cualquier Talismán en la Guerra de Talismanes),
## celeste si es una carta que su texto deja jugar al comienzo de esta fase (PhaseStartWindow).
## Las habilidades en juego (Signo Amarillo en la Reserva, Armas...) ya brillan en dorado por
## CardInspectionLayer.refresh_activatable_glows().
## Mismo cálculo para el Anfitrión (PhaseFlowController) y el Remoto (RemotePlayerController manda la
## lista; RemoteMirrorController pinta su mano con el mismo color).
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const PhaseStartWindowScript = preload("res://scripts/core/game/PhaseStartWindow.gd")
const Deck170PatternsScript = preload("res://scripts/core/effects/triggers/Deck170Patterns.gd")

const COLOR_RESPONSE := CardBadges.GLOW_COLOR_GOLD
const COLOR_PHASE_START := CardBadges.GLOW_COLOR_CELESTE
const REASON := &"playable_now"


static func response_talismans(main: Node, pid: int, response_only: bool) -> Array:
	"""Talismanes de la mano de 'pid' que puede pagar y jugar en esta ventana: solo los de respuesta
	instantánea (Red de Plata, Sacrificio Solar, Anular/Cancelar...) en una Ventana de Respuesta;
	cualquiera en la Guerra de Talismanes. Un Talismán de Anular/Cancelar, solo si hay algo del rival
	en la Pila que pueda Anular o Cancelar (mismas condiciones que GoldManager.play_card())."""
	var result: Array = []
	var gm = main.get("_gold_manager") if main else null
	if not gm:
		return result
	for c in PlayerSideScript.hand_cards(main, pid):
		if not is_instance_valid(c) or c.get("card_type") != Constants.CardType.TALISMAN:
			continue
		if gm._no_more_cards_violation(c) or gm._card_play_locked(c) or gm._errante_violation(c) \
				or gm._play_limit_violation(c):
			continue
		var cost: int = PaymentManager.calcular_coste_real(c)
		if not gm.puede_pagar(cost, Constants.CardType.TALISMAN, str(c.get("card_raza")), int(c.get("card_cost")), pid):
			continue
		var instant: bool = gm._is_response_only_talisman(c)
		if response_only and not instant:
			continue
		if instant and not (gm._responding_to_opponent(pid) \
				and Deck170PatternsScript.annul_response_has_target(c, str(c.get("card_ability")), pid)):
			continue
		result.append(c)
	return result


static func playable_now(main: Node, pid: int) -> Dictionary:
	"""{carta: color} de lo que 'pid' puede jugar de su mano en la ventana de prioridad abierta, si
	la prioridad es suya. Vacío fuera de esas ventanas."""
	var out: Dictionary = {}
	if not PriorityManager.priority_window_active or PriorityManager.current_priority_player != pid:
		return out
	match PriorityManager.current_priority_context:
		PriorityManager.PriorityContext.PHASE_START:
			for c in PhaseStartWindowScript.playable_cards(pid):
				out[c] = COLOR_PHASE_START
		PriorityManager.PriorityContext.RESPONSE_WINDOW:
			if PriorityManager.needs_real_decision(pid):
				for c in response_talismans(main, pid, true):
					out[c] = COLOR_RESPONSE
				for c in hand_abilities(main, pid):
					out[c] = COLOR_RESPONSE
		PriorityManager.PriorityContext.GUERRA_TALISMANES:
			for c in response_talismans(main, pid, false):
				out[c] = COLOR_RESPONSE
			for c in hand_abilities(main, pid):
				out[c] = COLOR_RESPONSE
	return out


static func refresh_hand(main: Node, pid: int) -> void:
	"""Prende el brillo de lo jugable ahora en la mano de 'pid' y lo apaga en el resto."""
	var glowing: Dictionary = playable_now(main, pid)
	for c in PlayerSideScript.hand_cards(main, pid):
		if not is_instance_valid(c) or not c.has_method("set_activatable"):
			continue
		if glowing.has(c):
			c.set_activatable(true, glowing[c], REASON)
		else:
			c.set_activatable(false, COLOR_RESPONSE, REASON)


static func hand_abilities(main: Node, pid: int) -> Array:
	"""Cartas de la mano con una habilidad usable desde ahí ahora (Espada Vikinga: "Puedes pagar un Oro
	y Desterrar esta carta de tu mano para Anular una carta de coste 1"), con el mismo filtro que los
	botones de la inspección. Si la habilidad Anula o Cancela, solo si hay en la Pila algo del rival
	que pueda afectar."""
	var result: Array = []
	var insp = main.get("_card_inspector") if main else null
	if not insp or not insp.has_method("usable_abilities_for"):
		return result
	for c in PlayerSideScript.hand_cards(main, pid):
		if not is_instance_valid(c):
			continue
		for entry in insp.usable_abilities_for(c, pid):
			var text: String = str(entry.get("ability", {}).get("raw_text", "")).to_lower()
			if _annul_clause_has_target(c, text, pid):
				result.append(c)
				break
	return result


static func _annul_clause_has_target(card: Node, text: String, pid: int) -> bool:
	"""true si la habilidad no Anula ni Cancela, o si lo que Anula/Cancela está en la Pila."""
	var at := -1
	for verb in ["anular ", "anula ", "cancelar ", "cancela "]:
		var i := text.find(verb)
		if i >= 0 and (at < 0 or i < at):
			at = i
	if at < 0:
		return true
	var clause: String = text.substr(at).get_slice(".", 0).strip_edges()
	clause = clause.replace("anular ", "anula ").replace("cancelar ", "cancela ")
	var stack_annul = load("res://scripts/core/effects/StackAnnul.gd")
	# "Anular una carta de coste 1" (Espada Vikinga) es coste exacto; try_from_text() lo lee como "o menos".
	var exact := RegEx.create_from_string("^anula una carta de coste (\\w+)$").search(clause)
	if exact:
		var n: int = UniversalCardParser._parse_amount(exact.get_string(1))
		return not stack_annul.find_target(pid, true, false, func(o): return stack_annul.cost_of(o) == n).is_empty()
	return not stack_annul.try_from_text(card, clause, pid, true).is_empty()
