class_name EffectInterpreter
extends "res://scripts/core/effects/compiler/EffectInterpreterEjecucion.gd"
## EffectInterpreter — familia Entrada (ver EffectInterpreterBase.gd para la cabecera, constantes y ayudas).


# =============================================================================
# ENTRADA
# =============================================================================


func try_execute(card: Node, clause_text: String, controller_id: int) -> bool:
	"""Compila y ejecuta. Devuelve true si el plan era válido y se resolvió
	por aquí (aunque el jugador haya rechazado un "puedes"); false si hay
	que seguir con la cadena de patrones vieja."""
	if not is_instance_valid(card) or clause_text.strip_edges().is_empty():
		return false
	var plan: Dictionary = EffectCompilerScript.compile_clause(clause_text)
	if not plan.ok or not EffectCompilerScript.is_executable(plan.steps):
		return false
	for st in plan.steps:
		if st.op == "castle_look" and not load("res://scripts/core/effects/CastleLook.gd").try_execute_text(card, str(st.text), controller_id, true):
			return false  # CastleLook no entiende ese "mira...": sigue la cadena vieja
	print("[EffectInterpreter] %s: %d paso(s) compilados" % [_card_name(card), plan.steps.size()])
	await execute_plan(plan, card, controller_id)
	return true


func execute_plan(plan: Dictionary, card: Node, controller_id: int) -> void:
	var main := _ts.get_node_or_null("/root/Main")
	if not main:
		return
	var name := _card_name(card)

	# ── Declarar ──────────────────────────────────────────────────────────
	# "Puedes": si el primer paso ya se puede rechazar en el propio selector (búsqueda con mínimo 0,
	# objetivo con ESC), no se agrega un popup Sí/No aparte —, la elección va en el tablero siempre que
	# se pueda (§49-§53).
	var effect_steps: Array = plan.steps.filter(func(st): return st.op not in ["pay", "cost"])
	var first_op: String = effect_steps[0].op if not effect_steps.is_empty() else ""
	var declinable_in_place: bool = first_op in ["search", "target", "buff"] and effect_steps.size() == plan.steps.size()
	# Habilidad activada: el clic en su botón ya confirmó el "puedes"
	# (mismo criterio que UniversalCardParser.parse_abilities()). También las que no dicen "una vez
	# por turno" ("Puedes Desterrarlo para..."): llegan por la Pila con contexto "activada".
	var from_button: bool = plan.get("activated", false) or str(EffectContextScript.current().get("kind", "")) == "activada"
	if plan.optional and not declinable_in_place and not from_button:
		if not await _ask_yes_no(main, "¿Usar la habilidad de %s?" % name, controller_id):
			return

	var steps: Array = await _resolve_choices(main, plan.steps, card, controller_id)
	# Costo en Oros ("pagar N Oros para ..."): antes de declarar objetivos; si no se puede pagar, no se
	# resuelve nada.
	var cost := 0
	var other_costs: Array = []
	for st in steps:
		if st.op == "pay":
			cost += int(st.amount)
		elif st.op == "cost":
			other_costs.append(st)
	steps = steps.filter(func(st): return st.op not in ["pay", "cost"])
	# Lo que la Pila ya cobró al activarla (StackStepResolver._resolve_ability(), CostType.GOLD).
	var ctx_now: Dictionary = EffectContextScript.current()
	if int(ctx_now.get("gold_paid", 0)) > 0:
		var already: int = mini(cost, int(ctx_now.gold_paid))
		cost -= already
		ctx_now["gold_paid"] = int(ctx_now.gold_paid) - already
	if cost > 0 and not main._gold_manager.puede_pagar(cost, -1, "", -1, controller_id):
		main._update_debug("%s: no puedes pagar %d Oro%s" % [name, cost, "" if cost == 1 else "s"])
		return
	# Sin ningún ataque que cancelar / nada en la pila que Anular, no se paga el coste (zawbaa, perun,
	# tenshi z, conde dracula).
	if (cost > 0 or not other_costs.is_empty()) and steps.size() == 1:
		if steps[0].op == "cancel_attack" and not GameManager.attackers.any(func(a): return is_instance_valid(a)):
			main._update_debug("%s: no hay un ataque que cancelar" % name)
			return
		if steps[0].op == "annul" and StackAnnulScript.try_from_text(card, str(steps[0].text), controller_id, true).is_empty():
			main._update_debug("%s: no hay nada en la pila que pueda Anular o Cancelar" % name)
			return
	for c in other_costs:
		var why := _cost_unpayable(main, c, card, controller_id)
		if not why.is_empty():
			main._update_debug("%s: %s" % [name, why])
			return
	if cost > 0 and not await PlayerSideScript.pay(main, controller_id, cost, null):
		return
	var src_data: Dictionary = card.card_data.duplicate() if card.get("card_data") is Dictionary else {}
	var src_owner: int = card.owner_id if card.get("owner_id") != null else controller_id
	for c in other_costs:
		if not await _pay_cost(main, c, card, controller_id):
			return
	if not is_instance_valid(card) or card.is_queued_for_deletion():
		# Descartarlo / Desterrarlo como coste liberó el Nodo: el resto del efecto usa una copia fuera
		# del tablero (nombre, dueño, fuente de la búsqueda...).
		card = main._create_card(src_data, false)
		card.owner_id = src_owner
		card.controller_id = controller_id
		await _execute_plan_steps(main, plan, steps, card, controller_id, declinable_in_place)
		card.free()
		return
	await _execute_plan_steps(main, plan, steps, card, controller_id, declinable_in_place)


func _execute_plan_steps(main: Node, plan: Dictionary, steps: Array, card: Node, controller_id: int,
		declinable_in_place: bool) -> void:
	var chosen_targets: Dictionary = {}  # índice de paso → Array[Node]
	for i in range(steps.size()):
		var st: Dictionary = steps[i]
		if st.op in ["target", "buff"]:
			var may_decline: bool = plan.optional and i == 0 and declinable_in_place
			chosen_targets[i] = await _declare_targets(main, st, card, controller_id, may_decline)
			if may_decline and chosen_targets[i].is_empty():
				return  # rechazó el "puedes" desde el propio selector

	if card.is_inside_tree() and card.has_method("play_ability_activation_effect"):
		card.play_ability_activation_effect()

	# Ventana del rival DESPUÉS de declarar (§59, opción B): si el efecto
	# todavía no la tuvo, se abre acá; si la cancela, no se resuelve nada.
	if await EffectContextScript.ensure_window():
		return

	# ── Resolver en orden, en la medida de lo posible ─────────────────────
	await _execute_steps(main, steps, chosen_targets, card, controller_id)
