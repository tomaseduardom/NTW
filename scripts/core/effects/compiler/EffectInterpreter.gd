extends RefCounted
class_name EffectInterpreter
## EffectInterpreter — ejecuta los planes de EffectCompiler (arquitectura.md §54).
## Orden: se declara todo (el "puedes", la rama de una elección "A, o B", los objetivos en juego) y
## después se ejecutan los pasos en orden, "en la medida de lo posible". Un paso "then" (tras
## "Luego,") solo corre si el anterior se resolvió por completo.
## Ventana de respuesta (§59): tras declarar llama a EffectContext.ensure_window(): si el efecto aún
## no le dio su ventana al rival, se abre ahí; si ya la tuvo (Talismanes, activadas en la Pila), no
## se abre otra.
## Quién elige: el jugador 0 con clic en el tablero; el Remoto (1 con sala) por red
## (await_target()/await_multi_target()/await_choice() delegan solos); el bot (1 sin sala) aquí, con
## una heurística simple.
## Solo ejecuta planes cuyos pasos sabe resolver (EffectCompiler.EXECUTABLE_OPS/VERBS); si no,
## devuelve false y sigue la cadena de patrones. Al agregar una pieza aquí, sumarla también a esas
## listas.

const VERB_LABELS := {
	"destroy": "destruir", "banish": "desterrar", "shuffle": "barajar en el Castillo de su dueño",
	"bounce": "subir a la mano de su dueño", "buff": "cambiar su Fuerza", "cost_shift": "cambiar su coste", "silence": "que pierda su habilidad",
}
const TYPE_LABELS := {
	"aliado": ["Aliado", "Aliados"], "arma": ["Arma", "Armas"], "totem": ["Tótem", "Tótems"],
	"talisman": ["Talismán", "Talismanes"], "oro": ["Oro", "Oros"], "": ["carta", "cartas"],
}
const BOARD_CONTAINERS := ["player_field", "player_linea_ataque", "player_linea_apoyo",
	"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo"]
const GOLD_CONTAINERS := ["player_gold", "opponent_gold", "player_oro_pagado", "opponent_oro_pagado"]

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")

var _ts: Node  # TriggerSystem (dueño de este intérprete)
## La carta tocada directamente al elegir una opción de "A o B" en la mesa (BoardChoice): es el objetivo
## del primer paso de esa opción (_declare_targets()).
var _preselected_target: Node = null


func setup(trigger_system: Node) -> void:
	_ts = trigger_system


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


func _execute_steps(main: Node, steps: Array, chosen_targets: Dictionary, card: Node, controller_id: int) -> bool:
	"""Ejecuta en orden; corta en un paso 'then' si el anterior no se
	resolvió por completo. Devuelve si el último paso se resolvió."""
	var last_ok := true
	for i in range(steps.size()):
		var st: Dictionary = steps[i]
		if st.get("then", false) and not last_ok:
			print("[EffectInterpreter] %s: 'Luego' cortado (el paso anterior no se resolvió)" % _card_name(card))
			break
		last_ok = await _execute_step(main, st, chosen_targets.get(i, []), card, controller_id)
	return last_ok


# =============================================================================
# DECLARACIÓN
# =============================================================================
func _resolve_choices(main: Node, steps: Array, card: Node, controller_id: int) -> Array:
	"""Reemplaza cada paso 'choice' por los pasos de la rama elegida."""
	var out: Array = []
	for st in steps:
		if st.op != "choice":
			out.append(st)
			continue
		var options: Array = st.options.filter(func(o): return _option_possible(o, card, controller_id))
		if options.is_empty():
			options = st.options
		var picked := 0
		if _is_bot(controller_id) or options.size() == 1:
			picked = 0
		else:
			var labels: Array = []
			for o in options:
				labels.append(describe_steps(o))
			var title := "%s: elige una opción" % _card_name(card)
			var remote: bool = controller_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host
			if remote:
				picked = await SelectionManager.await_choice(main, title, labels, controller_id)
			else:
				# En la mesa: las opciones que eligen una carta en juego (Desterrar, Destruir...) marcan sus
				# objetivos; tocar uno elige la opción y esa carta de una vez (_preselected_target).
				var target_sets: Dictionary = {}
				for oi in range(options.size()):
					var first: Dictionary = options[oi][0] if not options[oi].is_empty() else {}
					if first.has("target") and int(first.get("count", 1)) == 1:
						target_sets[oi] = _candidates(main, first.target, card, controller_id)
				EffectContextScript.check_chooser(controller_id, title)
				picked = await load("res://scripts/ui/hud/BoardChoice.gd").choose(main, title, labels, card, target_sets)
				_preselected_target = load("res://scripts/ui/hud/BoardChoice.gd").last_target
			picked = clampi(picked, 0, options.size() - 1)
		out.append_array(await _resolve_choices(main, options[picked], card, controller_id))
	return out


func _option_possible(steps: Array, card: Node, controller_id: int) -> bool:
	"""Una opción de "A o B" que empieza Anulando sin nada en la Pila no se ofrece (vision heroica)."""
	if steps.is_empty() or steps[0].op != "annul":
		return true
	return not StackAnnulScript.try_from_text(card, str(steps[0].text), controller_id, true).is_empty()


func _declare_targets(main: Node, st: Dictionary, card: Node, controller_id: int, may_decline: bool = false) -> Array:
	var spec: Dictionary = st.target
	var candidates := _candidates(main, spec, card, controller_id)
	if st.get("verb", "") == "shuffle":
		var rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
		candidates = candidates.filter(func(c): return not rules.cannot_be_shuffled(c))
	if candidates.is_empty():
		return []
	var count: int = st.count
	var mandatory: bool = not st.up_to and not may_decline
	if is_instance_valid(_preselected_target):
		var pre: Node = _preselected_target
		_preselected_target = null
		if count == 1 and pre in candidates:
			if main._card_interaction.has_method("_pay_affect_tax") and not await main._card_interaction._pay_affect_tax([pre], controller_id):
				return []
			return [pre]
	if _is_bot(controller_id):
		# Ganar Fuerza o una palabra clave: el bot prefiere sus propios Aliados.
		if st.op == "buff" and (int(st.get("amount", 0)) > 0 or st.get("double", false) or st.get("double_damage", false)
				or (int(st.get("amount", 0)) == 0 and not st.get("no_damage", false)
				and not st.has("set_strength") and (not st.get("keywords", []).is_empty() or st.get("no_shuffle", false)))):
			return _bot_pick(candidates, 1 - controller_id, count)
		# "Hasta N" / "puedes": el bot no se perjudica a sí mismo si puede no elegir nada.
		if not mandatory:
			candidates = candidates.filter(func(c): return _controller_of(c) != controller_id)
		return _bot_pick(candidates, controller_id, count)
	if mandatory and candidates.size() <= count:
		return candidates
	var prompt := "Elige %s para %s" % [_object_label(spec, count), VERB_LABELS.get(st.verb, st.verb)]
	if count == 1:
		var filter := func(c: Node) -> bool: return c in candidates
		var picked: Node = await main._card_interaction.await_target(prompt, filter, not mandatory, controller_id)
		return [picked] if picked and is_instance_valid(picked) else []
	return await main._card_interaction.await_multi_target(prompt, candidates, count, Callable(), Callable(),
		not mandatory, null, controller_id)


func _candidates(main: Node, spec: Dictionary, source: Node, controller_id: int) -> Array:
	var containers: Array = BOARD_CONTAINERS.duplicate()
	var types: Array = spec.get("card_types", [])
	if ("oro" in types) or (types.is_empty() and not spec.get("exclude_gold", false)):
		containers.append_array(GOLD_CONTAINERS)
	var out: Array = []
	for cname in containers:
		var container = main.get(cname)
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") != null and _matches(c, spec, source, controller_id):
				out.append(c)
			# Armas equipadas cuelgan del Aliado portador, no del contenedor.
			if is_instance_valid(c) and c.get("equipped_weapons") is Array:
				for w in c.equipped_weapons:
					if is_instance_valid(w) and _matches(w, spec, source, controller_id) and w not in out:
						out.append(w)
	return out


func _matches(c: Node, spec: Dictionary, source: Node, controller_id: int) -> bool:
	if c == source and spec.get("controller", "any") == "opponent":
		return false
	var ctype: int = int(c.card_type)
	var types: Array = spec.get("card_types", [])
	if not types.is_empty() and _type_word(ctype) not in types:
		return false
	if spec.get("exclude_gold", false) and ctype == Constants.CardType.ORO:
		return false
	if ctype == Constants.CardType.TALISMAN:
		return false  # los Talismanes no quedan en juego
	if spec.get("controller", "any") == "opponent" and _controller_of(c) == controller_id:
		return false
	# "un Aliado Bandido": raza sin tildes; los 5 primeros caracteres cubren plurales.
	var race: String = str(spec.get("race", ""))
	if not race.is_empty() and not (race.substr(0, 5) in EffectCompilerScript.normalize(str(c.get("card_raza")))):
		return false
	var stat: String = spec.get("stat", "")
	if stat == "coste" and ctype == Constants.CardType.ORO:
		return false  # Un Oro no tiene coste: nunca es "de coste N o menos/más"
	if stat != "":
		var v: int = ContinuousEffectManager.get_modified_strength(c) if stat == "fuerza" \
			else ContinuousEffectManager.get_modified_cost(c)
		var limit: int = spec.get("value", 0)
		if spec.get("cmp", "<=") == "<=" and v > limit:
			return false
		if spec.get("cmp", "<=") == ">=" and v < limit:
			return false
		if spec.get("cmp", "<=") == "==" and v != limit:  # "de coste 2" (sin "o menos/más")
			return false
	# Mismas protecciones que TargetedEffectExecutor._select_ally_target().
	if _ts._targeted_executor._is_immune_to_enemy_ally(c, source):
		return false
	if source and source.get("card_type") == Constants.CardType.TALISMAN \
			and ContinuousEffectManager.has_protection(c, "TALISMAN"):
		return false
	return true


func _bot_pick(candidates: Array, controller_id: int, count: int) -> Array:
	"""Heurística del bot local: primero cartas del rival, las más fuertes y
	caras primero."""
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Node, b: Node) -> bool:
		var a_enemy := _controller_of(a) != controller_id
		var b_enemy := _controller_of(b) != controller_id
		if a_enemy != b_enemy:
			return a_enemy
		var a_val: int = ContinuousEffectManager.get_modified_strength(a) + ContinuousEffectManager.get_modified_cost(a)
		var b_val: int = ContinuousEffectManager.get_modified_strength(b) + ContinuousEffectManager.get_modified_cost(b)
		return a_val > b_val)
	return sorted.slice(0, count)


# =============================================================================
# EJECUCIÓN
# =============================================================================
func _execute_step(main: Node, st: Dictionary, targets: Array, card: Node, controller_id: int) -> bool:
	"""Devuelve true si el paso se resolvió por completo (para 'Luego')."""
	var opponent_id := 1 - controller_id
	match st.op:
		"draw":
			if st.get("up_to", false):
				await ActionModule.draw_up_to(controller_id, st.amount, "efecto_compilado", true)
			else:
				await ActionModule.draw(controller_id, st.amount, "efecto_compilado", true)
			return true
		"draw_to_match":
			var missing: int = _hand_cards(main, opponent_id).size() - _hand_cards(main, controller_id).size()
			if missing <= 0:
				return true
			await ActionModule.draw(controller_id, missing, "efecto_compilado", true)
			return true
		"mill":
			var mill_pids: Array = [controller_id, opponent_id] if st.who == "both" \
				else [controller_id if st.who == "self" else opponent_id]
			var mill_amount: int = st.amount
			if st.get("per", "") != "":
				mill_amount *= _count_per(main, st.per, controller_id)
			if mill_amount > 0:
				for mill_pid in mill_pids:
					await ActionModule.mill(mill_pid, mill_amount, false, "efecto_compilado", true)
			return true
		"reveal_until":
			return await _reveal_until(main, st, card, controller_id)
		"hand_peek":
			return await _hand_peek(main, st, card, controller_id)
		"shuffle_from_cemetery":
			var res_cem: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], {},
				st.amount, st.up_to, false, false, card, Constants.Zone.CASTILLO)
			return st.up_to or res_cem.get("selected", []).size() >= st.amount
		"self_buff_per":
			var per_n: int = _count_per(main, str(st.per), controller_id)
			if per_n <= 0:
				return true
			if await EffectContextScript.ensure_window():
				return false
			return await _buff({"amount": int(st.amount) * per_n, "count": 1}, [card], card)
		"self":
			if not card.has_method("is_in_play") or not card.is_in_play():
				return false
			return await _apply_verb({"verb": st.verb, "count": 1, "up_to": false}, [card], card)
		"if":
			if not _condition_holds(st.cond, card):
				print("[EffectInterpreter] %s: condición '%s' no se cumple" % [_card_name(card), st.cond])
				return true
			return await _execute_steps(main, st.steps, {}, card, controller_id)
		"discard":
			return await _discard(main, st, controller_id)
		"shuffle_from_hand":
			return await _shuffle_from_hand(main, st, controller_id)
		"search":
			var zones: Array = []
			for z in st.zones:
				zones.append(Constants.Zone.CASTILLO if z == "castillo" else Constants.Zone.CEMENTERIO)
			var filter := _search_filter(st)
			var play: Dictionary = st.get("play", {})
			var dest: int = {"pagado": Constants.Zone.ORO_PAGADO, "cementerio": Constants.Zone.CEMENTERIO}.get(
				st.get("dest", "mano"), Constants.Zone.MANO)
			if play.get("free", false):
				dest = -1  # "y jugarlo sin pagar su coste": se juega desde los datos, sin pasar por la mano
			var res: Dictionary = await ActionModule.search_zones(controller_id, zones, filter, st.amount, true, false,
				not play.is_empty() and not play.get("free", false), card, dest, false, -1, int(play.get("reduce", 0)))
			if play.get("free", false) and main.get("_gold_manager"):
				for d in res.get("selected", []):
					await main._gold_manager.play_card_for_free(d, controller_id)
			return res.get("success", false) and not res.get("selected", []).is_empty()
		"gold_to_paid":
			return await _gold_to_paid(main, st, card, controller_id)
		"play_from":
			return await _play_from(main, st, card, controller_id)
		"peek_hand", "show_hand":
			# "Mira la mano de tu oponente" (la ve quien controla el efecto) / "Muestra tu mano" (la ve el
			# rival). Respeta Fisión Nuclear y Colapso Global como _hand_peek().
			if await EffectContextScript.ensure_window():
				return false
			var owner_pid: int = 1 - controller_id if st.op == "peek_hand" else controller_id
			var viewer: int = 1 - owner_pid
			if st.op == "peek_hand" and (EffectController.fision_hides_zones_of(owner_pid, controller_id, Constants.Zone.MANO)
					or await EffectController.offer_colapso_global(controller_id)):
				return false
			var shown: Array = PlayerSideScript.hand_cards(main, owner_pid).filter(func(c): return is_instance_valid(c)) \
				.map(func(c): return c.card_data)
			if not shown.is_empty() and not _is_bot(viewer):
				SelectionManager.open_reveal(shown, "%s: %s" % [_card_name(card),
					"la mano de tu oponente" if st.op == "peek_hand" else "la mano de tu oponente (te la muestra)"], viewer)
			return true
		"deck_to_hand":
			if await EffectContextScript.ensure_window():
				return false
			return _deck_to_hand(main, st, controller_id)
		"cancel_attack":
			return await _cancel_attack(main, st, card, controller_id)
		"mill_x":
			return await _mill_x(main, st, card, controller_id)
		"revive_blank":
			return await _revive_blank(main, st, card, controller_id)
		"opp_gold_to_paid":
			var opp_golds: Array = PlayerSideScript.gold_reserva(main, opponent_id).get_children().filter(
				func(g): return is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO)
			if opp_golds.is_empty():
				return false
			var gold: Node = opp_golds[0]
			if not _is_bot(controller_id) and opp_golds.size() > 1 and main.get("_card_interaction"):
				var g_pick: Node = await main._card_interaction.await_target("%s: elige un Oro oponente de su Reserva" % _card_name(card),
					func(c: Node) -> bool: return c in opp_golds, false, controller_id)
				if g_pick and is_instance_valid(g_pick):
					gold = g_pick
			if await EffectContextScript.ensure_window():
				return false
			if not await main._gold_manager._mover_oro_a_pagado(gold):
				GameState.pagar_oro(opponent_id, 1)
			main._gold_manager._update_gold_display()
			return true
		"self_raise":
			# "...para subirlo de tu Cementerio a tu mano" (Belial, sai): sus datos salen del Cementerio.
			var raise_owner: int = card.owner_id if card.get("owner_id") != null else controller_id
			var raise_idx: int = CardManager.get_cemetery(raise_owner).find(card.card_data)
			if raise_idx < 0:
				return false
			if await EffectContextScript.ensure_window():
				return false
			raise_idx = CardManager.get_cemetery(raise_owner).find(card.card_data)
			if raise_idx < 0:
				return false
			PlayerSideScript.put_in_hand(main, raise_owner, CardManager.remove_from_cemetery(raise_owner, raise_idx))
			return true
		"castle_exile":
			var exile_amount: int = int(st.amount)
			if st.get("per", "") == "opp_reserve":  # leng: "como Oros tenga en su Reserva"
				exile_amount = GameState.get_oro_reserva(opponent_id)
				if exile_amount <= 0:
					return true
			if await EffectContextScript.ensure_window():
				return false
			return not CardManager.banish_from_deck(opponent_id, exile_amount, st.get("bottom", false), controller_id).is_empty()
		"no_damage":
			if await EffectContextScript.ensure_window():
				return false
			var until: int = RuleState.next_own_turn(controller_id)
			RuleState.set_until("no_combat_damage", controller_id, until)
			if not st.get("combat_only", false):
				RuleState.set_until("no_direct_damage", controller_id, until)
			return true
		"target":
			return await _apply_verb(st, targets, card)
		"cemetery_cleanup":
			return await _cemetery_cleanup(main, st, card, controller_id)
		"gold":
			if main.get("_gold_manager"):
				var for_type: String = st.get("for", "")
				if for_type == "":
					main._gold_manager.generar_oros_virtuales(int(st.amount), controller_id)
				else:
					# "Genera un Oro para jugar Aliados": Oro Virtual restringido a ese tipo.
					var wanted: int = _type_enum(for_type)
					var predicate := func(card_type: int, _race: String, _cost: int) -> bool: return card_type == wanted
					main._gold_manager.generar_oro_virtual_restringido(int(st.amount), predicate,
						TYPE_LABELS.get(for_type, [for_type, for_type])[1].capitalize(), controller_id)
			return true
		"regroup_gold":
			if main.get("_gold_manager"):
				await main._gold_manager.agrupar_oros(controller_id, int(st.amount))
			return true
		"regroup_cards":
			if main.get("_gold_manager"):
				await main._gold_manager.agrupar_cartas(controller_id, int(st.amount))
			return true
		"castle_look":
			if await EffectContextScript.ensure_window():
				return false
			return await load("res://scripts/core/effects/CastleLook.gd").try_execute_text(card, str(st.text), controller_id)
		"buff":
			return await _buff(st, targets, card)
		"annul":
			var annul_res: Dictionary = StackAnnulScript.try_from_text(card, str(st.text), controller_id)
			if annul_res.is_empty():
				main._update_debug("%s: no hay nada en la pila que pueda Anular o Cancelar" % _card_name(card))
				return false
			return bool(annul_res.applied)
		"talisman_fizzle":
			_ts._totem_patterns.register_kotoku_in_talisman_fizzle(opponent_id)
			main._update_debug("%s: el próximo Talismán de tu oponente este turno se resuelve sin efecto" % _card_name(card))
			return true
		"mass_buff":
			return await execute_step_mass_buff(main, st, card, controller_id)
		"mass":
			var all := _candidates(main, st.target, card, controller_id)
			if all.is_empty():
				return true
			var mass_st := st.duplicate()
			mass_st["count"] = all.size()
			mass_st["up_to"] = false
			return await _apply_verb(mass_st, all, card)
	push_warning("[EffectInterpreter] Paso no soportado: %s" % st.op)
	return false


func _apply_verb(st: Dictionary, targets: Array, card: Node) -> bool:
	"""Aplica el verbo de un paso 'target'/'mass'/'self' a sus objetivos,
	revalidando que sigan en juego (pudieron salir durante la ventana de
	respuesta). silence_first: pierden la habilidad antes (no disparan su
	'cuando salga del juego'). replace_if_keyword: "Si tiene Exhumar, en
	vez de eso, Destiérralo" — por objetivo."""
	var alive: Array = []
	for t in targets:
		if is_instance_valid(t) and t.has_method("is_in_play") and t.is_in_play():
			alive.append(t)
	if alive.is_empty():
		return false
	var all_ok: bool = alive.size() >= int(st.get("count", 1)) or st.get("up_to", false)

	if st.get("silence_first", false):
		for t in alive:
			if not _ts._targeted_executor._target_text_denies(t, ["no puede perder su habilidad", "no pierde su habilidad"]):
				await KeywordManager.silence_card(t, card, "permanent")

	# Separar por verbo final (el reemplazo por keyword puede cambiarlo).
	var by_verb := {}
	var repl: Dictionary = st.get("replace_if_keyword", {})
	for t in alive:
		var verb: String = st.verb
		if not repl.is_empty() and KeywordManager.has_keyword(t, _keyword_enum(repl.keyword)):
			verb = repl.verb
		if not by_verb.has(verb):
			by_verb[verb] = []
		by_verb[verb].append(t)

	for verb in by_verb:
		var group: Array = by_verb[verb]
		match verb:
			"destroy":
				var r: Dictionary = await ActionModule.destroy(group, card, true, true)
				all_ok = all_ok and r.get("success", true)
			"banish":
				var r2: Dictionary = await ActionModule.banish(group, card, true, true)
				all_ok = all_ok and r2.get("success", true)
			"cost_shift":
				for t in group:
					var amount: int = int(st.get("amount", 1))
					var raise: bool = _controller_of(t) == _controller_of(card)  # bot: sube las propias, baja las rivales
					if not _is_bot(_controller_of(card)):
						raise = await SelectionManager.await_two_choice(_ts.get_node_or_null("/root/Main"), _card_name(card),
							"Aumentar su coste en %d" % amount, "Reducir su coste en %d" % amount, _controller_of(card))
					ContinuousEffectManager.register_modifier({
						"source": card, "target": t,
						"type": ContinuousEffectManager.ModifierType.COST, "stat": "cost",
						"value": amount if raise else -amount, "operation": "add",
						"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
						"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
						"description": "%s: coste %+d" % [_card_name(card), amount if raise else -amount],
					})
			"silence":
				# silence_card() ya revisa las protecciones ("no pueden perder su habilidad") y ofrece la
				# Prevención del rival.
				for t in group:
					if not _ts._targeted_executor._target_text_denies(t, ["no puede perder su habilidad", "no pierde su habilidad"]):
						await KeywordManager.silence_card(t, card, str(st.get("duration", "permanent")))
			"shuffle":
				for t in group:
					var owner: int = int(t.owner_id) if t.get("owner_id") != null else _controller_of(t)
					if await ActionModule.return_to_deck(t, owner, true, card):
						CardManager.shuffle_deck(owner)
					else:
						all_ok = false
	return all_ok


func _search_filter(st: Dictionary) -> Dictionary:
	"""Filtro de ActionModule._apply_card_filter() para un paso 'search' / 'play_from'."""
	var filter := {}
	var card_types: Array = st.get("card_types", [])
	if card_types.size() > 1:
		filter["type"] = card_types.map(func(w): return _type_enum(w))
	elif st.get("card_type", "") != "":
		filter["type"] = _type_enum(st.card_type)
	if not st.get("types_not", []).is_empty():
		filter["types_not"] = st.types_not.map(func(w): return _type_enum(w))
	if int(st.get("cost_val", -1)) >= 0:
		if st.get("cost_cmp", "") != "mas":
			filter["cost_max"] = int(st.cost_val)
		if st.get("cost_cmp", "") != "menos":
			filter["cost_min"] = int(st.cost_val)
	if st.get("no_ability", false):
		filter["no_ability"] = true
	if str(st.get("name", "")) != "":
		filter["name_contains"] = str(st.name)  # "busca un Leyaden..."
	if st.has("alts"):
		filter["alts"] = st.alts.map(func(a): return {"type": _type_enum(a.type) if a.type != "" else -1, "race": a.race})
	return filter


func _play_from(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Jugar un Aliado de coste 2 o menos desde tu mano o Cementerio sin pagar su coste / reduciendo su
	coste en un Oro / pagando su coste'. Con las dos zonas, se elige de dónde (el bot: Cementerio
	primero). Gratis: GoldManager.play_card_for_free(). Con coste: la carta pasa por la mano con el
	descuento (PlayerSide.play_from_hand(); el bot solo juega Aliados) y, si no se jugó, vuelve al
	Cementerio de donde salió."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var filter := _search_filter(st)
	filter["types_not"] = filter.get("types_not", []) + [Constants.CardType.ORO]  # un Oro no se juega
	var play: Dictionary = st.get("play", {})
	var played := 0
	for _i in range(int(st.amount)):
		var hand_nodes: Array = []
		if "mano" in st.zones:
			hand_nodes = PlayerSideScript.hand_cards(main, controller_id).filter(func(c):
				return is_instance_valid(c) and c != card and not ActionModule._apply_card_filter([c.card_data], filter).is_empty())
		var cem_ok: bool = "cementerio" in st.zones \
			and not ActionModule._apply_card_filter(CardManager.get_cemetery(controller_id), filter).is_empty()
		if hand_nodes.is_empty() and not cem_ok:
			break
		var from_hand := not hand_nodes.is_empty()
		if from_hand and cem_ok:
			from_hand = false if _is_bot(controller_id) else await SelectionManager.await_two_choice(main, _card_name(card),
				"De tu mano", "De tu Cementerio", controller_id)
		var data := {}
		var node: Node = null
		if from_hand:
			node = await PlayerSideScript.pick_from_hand(main, controller_id, "%s: elige la carta para jugar" % _card_name(card),
				func(c): return c in hand_nodes)
			if not node:
				break
		else:
			var res: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], filter, 1, true,
				false, false, card, -1)
			if res.get("selected", []).is_empty():
				break
			data = res.selected[0]
		if await EffectContextScript.ensure_window():
			return false
		if play.get("free", false):
			if node:
				data = PlayerSideScript.take_from_hand(main, controller_id, node)
			await gm.play_card_for_free(data, controller_id, play.get("exile_after", false))
			played += 1
			continue
		if not node:
			node = PlayerSideScript.put_in_hand(main, controller_id, data)
		var reduce: int = int(play.get("reduce", 0))
		if reduce > 0:
			PaymentManager.agregar_modificador_coste(node, -reduce, func(c: Node) -> bool: return c == node,
				int(play.get("floor", 1)) == 0)  # "hasta un mínimo de 0"
		await PlayerSideScript.play_from_hand(main, controller_id, node)
		if is_instance_valid(node) and reduce > 0:
			PaymentManager.remover_modificador_coste(node)
		if is_instance_valid(node) and node.get("current_zone") == Constants.Zone.MANO:
			if not from_hand:  # no se jugó: vuelve al Cementerio
				CardManager.add_to_cemetery(controller_id, PlayerSideScript.take_from_hand(main, controller_id, node))
			break
		played += 1
	return played > 0 or st.get("up_to", false)


func _gold_to_paid(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Pon un Oro de tu mano o Cementerio en tu Oro Pagado' (cueva del horror, Lord Ruthven) y 'poner
	un Oro en juego desde tu mano o Cementerio' (a la Reserva). Con las dos zonas posibles, se elige
	primero de dónde; el bot prefiere el Cementerio."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var is_gold := func(c) -> bool:
		var t = c.get("card_type") if c is Node else c.get("tipo")
		return t != null and int(t) == Constants.CardType.ORO
	var hand_ok: bool = "mano" in st.zones and PlayerSideScript.hand_cards(main, controller_id).any(is_gold)
	var cem_ok: bool = "cementerio" in st.zones and CardManager.get_cemetery(controller_id).any(is_gold)
	if not hand_ok and not cem_ok:
		return false
	var to_paid: bool = st.get("dest", "pagado") == "pagado"
	var from_hand := hand_ok
	if hand_ok and cem_ok:
		from_hand = false if _is_bot(controller_id) else await SelectionManager.await_two_choice(main, _card_name(card),
			"Un Oro de tu mano", "Un Oro de tu Cementerio", controller_id)
	if not from_hand:
		var res: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO],
			{"type": Constants.CardType.ORO}, 1, true, false, false, card,
			Constants.Zone.ORO_PAGADO if to_paid else Constants.Zone.RESERVA_ORO)
		return not res.get("selected", []).is_empty()
	var picked: Node = await PlayerSideScript.pick_from_hand(main, controller_id,
		"%s: elige un Oro de tu mano" % _card_name(card), is_gold)
	if not picked or await EffectContextScript.ensure_window():
		return false
	var data: Dictionary = PlayerSideScript.take_from_hand(main, controller_id, picked)
	if to_paid:
		await gm.put_gold_directly_in_pagado(controller_id, data)
	else:
		await gm.put_gold_directly_in_reserva(controller_id, data)
	return true


func _deck_to_hand(main: Node, st: Dictionary, controller_id: int) -> bool:
	"""'Pon dos cartas del fondo de tu Castillo en tu mano' / 'la primera y la última' (el índice 0 es
	el tope)."""
	if load("res://scripts/core/effects/mechanics/ProtectionRules.gd").hand_by_effects_blocked(controller_id):
		return false
	var deck: Array = CardManager.get_deck(controller_id)
	var taken: Array = []
	if st.from == "both":
		if not deck.is_empty():
			taken.append(deck.pop_front())
		if not deck.is_empty():
			taken.append(deck.pop_back())
	else:
		for i in int(st.amount):
			if deck.is_empty():
				break
			taken.append(deck.pop_back() if st.from == "bottom" else deck.pop_front())
	for d in taken:
		PlayerSideScript.put_in_hand(main, controller_id, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return not taken.is_empty()


func _cemetery_cleanup(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Baraja y/o Destierra hasta N cartas de los Cementerios' (mode both),
	'Destierra hasta N...' (banish), 'Baraja hasta N...' (shuffle). Los dos
	Cementerios; cada carta va al Castillo / Destierro de su dueño. one_zone ("de un Cementerio"):
	todas del mismo."""
	var amount: int = int(st.amount)
	var one_zone: bool = st.get("one_zone", false)
	match str(st.mode):
		"both":
			if main.get("_gold_manager"):
				await main._gold_manager._resolve_armeria_barajar_desterrar(amount, _card_name(card), controller_id)
		"banish":
			await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {}, amount, true, card,
				Constants.Zone.DESTIERRO, false, one_zone)
		"shuffle":
			var res: Dictionary = await ActionModule.search_either_owner(controller_id, [Constants.Zone.CEMENTERIO], {},
				amount, true, card, Constants.Zone.CASTILLO, false, one_zone)
			for pid in [0, 1]:
				for d in res.get("selected", []):
					if CardManager.get_deck(pid).has(d):
						CardManager.shuffle_deck(pid)
						break
	return true  # "hasta": siempre se resuelve


func execute_step_mass_buff(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Tus (demás) Aliados ganan... / Los Aliados oponentes pierden...': todos los Aliados en juego de
	ese lado en este momento (también lo usa AllyEventTriggers.gd)."""
	var side: int = 1 - controller_id if st.side == "opponent" else controller_id
	var allies: Array = []
	for container in PlayerSideScript.ally_containers(main, side):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and not (st.others and c == card):
				allies.append(c)
	var mass_st := st.duplicate()
	mass_st["count"] = allies.size()
	mass_st["up_to"] = true
	return await _buff(mass_st, allies, card)


func _buff(st: Dictionary, targets: Array, card: Node) -> bool:
	"""'Un Aliado gana/pierde N de Fuerza, Furia, ... y hace daño al
	Destierro'. Duración (regla del usuario): la Fuerza es por el turno salvo
	'permanentemente'; las keywords son permanentes salvo 'por el turno'; el
	daño al Destierro, por el turno salvo 'permanentemente'. Prevención del
	rival incluida."""
	var all_ok: bool = targets.size() >= int(st.get("count", 1)) or st.get("up_to", false)
	for t in targets:
		if not (is_instance_valid(t) and t.has_method("is_in_play") and t.is_in_play()):
			all_ok = false
			continue
		if await EffectController.offer_prevention(t, card, "strength_change"):
			continue
		var kw_duration: String = "turn" if st.get("turn_only", false) else "permanent"
		if st.get("duration", "") == "until_next_turn":
			kw_duration = "until_next_turn"
		for kw in st.get("keywords", []):
			KeywordManager.grant_keyword(t, _keyword_enum(kw), card, kw_duration)
		if st.get("no_shuffle", false):
			# ProtectionRules.cannot_be_shuffled(); hasta tu próximo turno = también el del rival.
			var until: int = GameManager.turn_serial + 1 if kw_duration == "until_next_turn" \
				else (GameManager.turn_serial if kw_duration == "turn" else 1 << 30)
			t.set_meta("cannot_be_shuffled_until", until)
		if st.get("to_exile", false):
			if st.get("permanent", false):
				t.set_meta("converted_damage_to_exile", true)  # ProtectionRules.combat_damage_to_exile
			else:
				t.set_meta("damage_to_exile_turn", GameManager.turn_serial)  # BattleManager._accumulate_castle_damage
		if st.get("double_damage", false):
			t.set_meta("double_combat_damage_turn", GameManager.turn_serial)  # BattleManager
		if st.get("no_damage", false):
			t.set_meta("no_damage_turn", GameManager.turn_serial)  # BattleManager: ni al Castillo ni al bloqueador
		if st.has("set_strength") or st.get("double", false):
			_set_or_double_strength(st, t, card)
			continue
		if int(st.amount) == 0:
			continue
		ContinuousEffectManager.register_modifier({
			"source": t,
			"target": t,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": int(st.amount),
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT if st.get("permanent", false)
				else ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s %+d" % [_card_name(card), int(st.amount)],
		})
		if t.has_method("refresh_strength_badge"):
			t.refresh_strength_badge()
	return all_ok


func _revive_blank(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Pon en juego (hasta) N Aliados de tu Cementerio como Aliados sin habilidad': mismo camino que
	Alto Prime (CemeteryRevivePatterns): los datos salen del Cementerio con el texto vacío y entran
	por GoldManager._play_card_to_field()."""
	var gm = main.get("_gold_manager")
	if not gm:
		return false
	var filter := _search_filter({"card_type": "aliado", "cost_val": st.get("cost_val", -1), "cost_cmp": st.get("cost_cmp", "")})
	if ActionModule._apply_card_filter(CardManager.get_cemetery(controller_id), filter).is_empty():
		return st.get("up_to", false)
	var res: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], filter, int(st.amount),
		true, false, false, card, -1)
	var picked: Array = res.get("selected", [])
	if picked.is_empty():
		return st.get("up_to", false)
	if await EffectContextScript.ensure_window():
		return false
	for d in picked:
		var ally_data: Dictionary = (d as Dictionary).duplicate()
		ally_data["habilidad"] = ""
		ally_data["esta_oculta"] = false
		var node: Node = main._create_card(ally_data, false)
		node.owner_id = controller_id
		node.controller_id = controller_id
		main._connect_card_signals(node)
		await gm._play_card_to_field(node)
	return picked.size() >= int(st.amount) or st.get("up_to", false)


func _mill_x(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""Botar (o Desterrar del tope del Castillo rival) tantas cartas como: la Fuerza de un Aliado que
	controles / que porte Armas (se elige; el bot, el de más Fuerza), la del portador de esta Arma, o
	los Aliados en la mano rival. 'un jugador': se elige quién (el bot, el rival)."""
	var n := 0
	match str(st.src):
		"own_ally", "armed_ally":
			var pool: Array = []
			var pids: Array = [controller_id] if st.src == "own_ally" else [0, 1]
			for pid in pids:
				for cont in PlayerSideScript.ally_containers(main, pid):
					for a in cont.get_children():
						if not is_instance_valid(a) or a.get("card_type") != Constants.CardType.ALIADO:
							continue
						if st.src == "armed_ally" and (not (a.get("equipped_weapons") is Array) or a.equipped_weapons.is_empty()):
							continue
						pool.append(a)
			if pool.is_empty():
				main._update_debug("%s: no hay un Aliado para contar su Fuerza" % _card_name(card))
				return false
			pool.sort_custom(func(a: Node, b: Node) -> bool:
				return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
			var pick: Node = pool[0]
			if not _is_bot(controller_id) and pool.size() > 1 and main.get("_card_interaction"):
				var chosen: Node = await main._card_interaction.await_target("%s: elige el Aliado (cuenta su Fuerza)" % _card_name(card),
					func(c: Node) -> bool: return c in pool, false, controller_id)
				if chosen and is_instance_valid(chosen):
					pick = chosen
			n = ContinuousEffectManager.get_modified_strength(pick)
		"bearer":
			var bearer = card.get("wielder")
			if not (bearer is Node and is_instance_valid(bearer)):
				bearer = card.get_parent() if card.get_parent() and card.get_parent().get("equipped_weapons") is Array else null
			if bearer == null:
				return false
			n = ContinuousEffectManager.get_modified_strength(bearer)
		"opp_hand_allies":
			n = PlayerSideScript.hand_cards(main, 1 - controller_id).filter(
				func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO).size()
	var target_pid: int = 1 - controller_id
	if st.get("who", "opponent") == "choose" and not _is_bot(controller_id):
		target_pid = 1 - controller_id if await SelectionManager.await_two_choice(main, "%s: ¿quién Bota %d?" % [_card_name(card), n],
			"Tu oponente", "Tú", controller_id) else controller_id
	if n <= 0:
		return true
	if await EffectContextScript.ensure_window():
		return false
	if st.get("exile", false):
		CardManager.banish_from_deck(1 - controller_id, n, false, controller_id)
	else:
		await ActionModule.mill(target_pid, n, false, "efecto_compilado", true)
	return true


func _cancel_attack(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Cancela el ataque de (hasta N) Aliado(s) (oponente)': salen de GameManager.attackers y
	vuelven a su aspecto (mismo camino que Drácula en HandCementerioAbilityHandler). Respeta "su
	ataque no puede ser cancelado" (ProtectionRules.attack_uncancellable)."""
	var rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var candidates: Array = []
	for a in GameManager.attackers:
		if not is_instance_valid(a) or rules.attack_uncancellable(a):
			continue
		if st.get("opponent", false) and _controller_of(a) == controller_id:
			continue
		candidates.append(a)
	if candidates.is_empty():
		main._update_debug("%s: no hay un ataque que cancelar" % _card_name(card))
		return false
	var n: int = int(st.get("count", 1))
	var chosen: Array = []
	if _is_bot(controller_id):
		chosen = candidates.filter(func(a): return _controller_of(a) != controller_id).slice(0, n)
	elif main.get("_card_interaction"):
		chosen = await main._card_interaction.await_multi_target("%s: cancela el ataque de %d Aliado%s" % [
			_card_name(card), n, "" if n == 1 else "s"], candidates, n, Callable(), Callable(), true, null, controller_id)
	chosen = chosen.filter(func(a): return is_instance_valid(a))
	if chosen.is_empty():
		return false
	if await EffectContextScript.ensure_window():
		return false
	chosen = await EffectController.filter_attack_cancel(chosen, card)  # cancelar ataque afecta al Aliado
	for a in chosen:
		GameManager.attackers.erase(a)
	if main._card_interaction and main._card_interaction.has_method("unmark_attackers") and not chosen.is_empty():
		await main._card_interaction.unmark_attackers(chosen)
	return true


func _set_or_double_strength(st: Dictionary, t: Node, card: Node) -> void:
	"""'Tiene Fuerza N' (capa 7A, operación set: lo que se sume después se suma a N) o 'duplica su
	Fuerza' (+ la Fuerza actual). Por el turno, o hasta tu próximo turno: TIMED, que se descuenta
	en cada fin de turno (2 si es tu turno: este y el del rival)."""
	var duration: int = ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN
	var turns := 0
	if st.get("duration", "") == "until_next_turn":
		duration = ContinuousEffectManager.ModifierDuration.TIMED
		turns = 2 if GameManager.active_player_id == _controller_of(card) else 1
	var doubling: bool = st.get("double", false)
	var current: int = ContinuousEffectManager.get_modified_strength(t)
	ContinuousEffectManager.register_modifier({
		"source": t,
		"target": t,
		"type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength",
		"value": current if doubling else int(st.set_strength),
		"operation": "add" if doubling else "set",
		"duration": duration,
		"duration_value": turns,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY if doubling
			else ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "%s: %s" % [_card_name(card), "duplica su Fuerza" if doubling else "Fuerza %d" % int(st.set_strength)],
	})
	if t.has_method("refresh_strength_badge"):
		t.refresh_strength_badge()


func _reveal_until(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Muestra cartas del tope de tu Castillo hasta mostrar <specs> y ponlos
	en tu mano': se muestran del tope hasta completar cada spec (cantidad,
	tipos, coste); esas van a la mano y el resto se baraja en el Castillo."""
	var deck: Array = CardManager.get_deck(controller_id)
	var need: Array = []
	for sp in st.specs:
		need.append(int(sp.count))
	var revealed: Array = []
	var taken: Array = []
	while not deck.is_empty() and need.any(func(n): return n > 0):
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		for i in range(st.specs.size()):
			if need[i] > 0 and _spec_matches(st.specs[i], top):
				need[i] -= 1
				taken.append(top)
				break
	var title := _card_name(card)
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, title)
	# Visor de mostrar para quien controla el efecto: solo las cartas que indica (RevealWindow).
	if not taken.is_empty():
		var reveal_window = load("res://scripts/ui/zones/RevealWindow.gd")
		if st.get("play_free", false) and taken.size() > 1:
			taken = await reveal_window.choose_order(main, controller_id, taken, title)
		else:
			await reveal_window.show_cards(main, controller_id, taken, title,
				"Se juega sin pagar su coste" if st.get("play_free", false) else "Van a tu mano")
	for d in taken:
		revealed.erase(d)
	for d in revealed:
		deck.append(d)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	var queue_before: int = _ts.trigger_queue.size() if _ts else 0
	for d in taken:
		if st.get("play_free", false) and main.get("_gold_manager") and int(d.get("tipo", -1)) != Constants.CardType.ORO:
			await main._gold_manager.play_card_for_free(d.duplicate(), controller_id)  # "y juégalo sin pagar su coste"
		else:
			PlayerSideScript.put_in_hand(main, controller_id, d.duplicate())
	if st.get("play_free", false) and taken.size() > 1:
		await load("res://scripts/core/effects/mechanics/SearchPatterns.gd").reorder_new_triggers(queue_before, controller_id)
	return not need.any(func(n): return n > 0)


func _hand_peek(main: Node, st: Dictionary, card: Node, controller_id: int) -> bool:
	"""'Mira la mano de tu oponente y Destierra/Descarta/Baraja N cartas
	(filtro) de ahí'. Quien elige ve la mano entera; respeta Fisión Nuclear,
	Colapso Global y Terminal P-12 (EffectController.fision_hides_zones_of)."""
	var opp: int = 1 - controller_id
	var title := _card_name(card)
	if EffectController.fision_hides_zones_of(opp, controller_id, Constants.Zone.MANO) \
			or await EffectController.offer_colapso_global(controller_id):
		return false
	var hand: Array = PlayerSideScript.hand_cards(main, opp).filter(func(c): return is_instance_valid(c))
	if hand.is_empty():
		return false
	if not _is_bot(controller_id):
		SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % title, controller_id)
	var spec := {"types": st.get("types", []), "cost_val": st.get("cost_val", -1), "cost_cmp": st.get("cost_cmp", "")}
	var types_not: Array = st.get("types_not", [])
	var picked_count := 0
	for _i in range(int(st.count)):
		var candidates: Array = hand.filter(func(c):
			return is_instance_valid(c) and _spec_matches(spec, c.card_data) and _type_word(int(c.card_type)) not in types_not)
		if candidates.is_empty():
			break
		var idx := 0
		if not _is_bot(controller_id) and candidates.size() > 1:
			idx = await SelectionManager.await_choice(main, "%s: elige una carta de su mano" % title,
				candidates.map(func(c): return str(c.get("card_name"))), controller_id)
		var chosen: Node = candidates[clampi(idx, 0, candidates.size() - 1)]
		hand.erase(chosen)
		match str(st.verb):
			"banish":
				CardManager.add_to_exile(opp, PlayerSideScript.take_from_hand(main, opp, chosen))
			"discard":
				await ActionModule.discard(opp, [chosen], title, true)
			_:
				PlayerSideScript.shuffle_from_hand(main, opp, chosen, title)
		picked_count += 1
	return picked_count >= int(st.count)


func _spec_matches(spec: Dictionary, data: Dictionary) -> bool:
	var types: Array = spec.get("types", [])
	if not types.is_empty() and _type_word(int(data.get("tipo", -1))) not in types:
		return false
	if _type_word(int(data.get("tipo", -1))) in spec.get("types_not", []):
		return false
	var race: String = str(spec.get("race", ""))
	if race != "" and not (race.substr(0, 5) in ActionModule._strip_accents(str(data.get("raza", "")).to_lower())):
		return false
	var cval: int = int(spec.get("cost_val", -1))
	if cval >= 0:
		if int(data.get("tipo", -1)) == Constants.CardType.ORO:
			return false  # un Oro no tiene coste
		var cost: int = int(data.get("coste", 0))
		match str(spec.get("cost_cmp", "")):
			"menos":
				return cost <= cval
			"mas":
				return cost >= cval
			_:
				return cost == cval
	return true


func _condition_holds(cond, card: Node) -> bool:
	if cond is Dictionary and cond.get("kind", "") == "controls":
		return _controls_holds(cond, card)
	match str(cond):
		"not_attacked_this_turn":
			return int(card.get_meta("declared_attacker_turn", -1)) != GameManager.turn_serial
	push_warning("[EffectInterpreter] Condición desconocida: %s" % str(cond))
	return false


func _controls_holds(cond: Dictionary, card: Node) -> bool:
	"""'Si controlas (otro) (N o más) <tipo/raza> (de Fuerza N o más) (en Línea
	de Ataque)' — se cuenta al resolver, entre las cartas que controla quien
	controla 'card'."""
	var main := _ts.get_node_or_null("/root/Main")
	if not main:
		return false
	var pid: int = _controller_of(card)
	var containers: Array = []
	if cond.get("attack_line", false):
		containers = [PlayerSideScript.line_containers(main, pid)[1]]
	else:
		containers = PlayerSideScript.line_containers(main, pid)
	if cond.get("type", "") in ["oro", ""]:
		containers.append(PlayerSideScript.gold_reserva(main, pid))
		containers.append(PlayerSideScript.oro_pagado(main, pid))
	var race_forms: Array = []
	var race: String = EffectCompilerScript.normalize(str(cond.get("race", "")))
	if not race.is_empty():
		race_forms.append(race)
		if race.ends_with("es") and race.length() > 4:
			race_forms.append(race.substr(0, race.length() - 2))
		if race.ends_with("s"):
			race_forms.append(race.substr(0, race.length() - 1))
	var count := 0
	for container in containers:
		if not container:
			continue
		var pool: Array = container.get_children()
		for c in container.get_children():
			if is_instance_valid(c) and c.get("equipped_weapons") is Array:
				pool.append_array(c.equipped_weapons)
		for c in pool:
			if not is_instance_valid(c) or c.get("card_type") == null:
				continue
			if cond.get("other", false) and c == card:
				continue
			if _controller_of(c) != pid:
				continue
			var t: String = str(cond.get("type", ""))
			if t != "" and _type_word(int(c.card_type)) != t:
				continue
			if int(c.card_type) == Constants.CardType.TALISMAN:
				continue
			if not race_forms.is_empty():
				var card_race: String = EffectCompilerScript.normalize(str(c.get("card_raza")))
				if not race_forms.any(func(f): return f in card_race):
					continue
			if int(cond.get("min_strength", -1)) >= 0 \
					and ContinuousEffectManager.get_modified_strength(c) < int(cond.min_strength):
				continue
			count += 1
	return count >= int(cond.get("count", 1))


func _count_per(main: Node, per: String, controller_id: int) -> int:
	"""Cantidades dinámicas de 'por cada ...'."""
	var n := 0
	match per:
		"own_allies_defense":
			var field = main.get("player_field" if controller_id == 0 else "opponent_field")
			if field:
				for c in field.get_children():
					if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO:
						n += 1
		"own_golds":  # dragones de la reina: Reserva y Oro Pagado
			for zone in [PlayerSideScript.gold_reserva(main, controller_id), PlayerSideScript.oro_pagado(main, controller_id)]:
				if zone:
					for g in zone.get_children():
						if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO:
							n += 1
		"opp_exile":  # udug
			n = CardManager.get_exile(1 - controller_id).size()
		"own_exile_allies":  # brujo mendigo
			for d in CardManager.get_exile(controller_id):
				if int(d.get("tipo", -1)) == Constants.CardType.ALIADO:
					n += 1
		"totems_in_play_and_exile":  # Dr. Van Helsing: "por cada Tótem en juego y en tu Destierro"
			n = _count_per(main, "totems_in_play", controller_id)
			for d in CardManager.get_exile(controller_id):
				if int(d.get("tipo", -1)) == Constants.CardType.TOTEM:
					n += 1
		"own_allies", "own_totems", "totems_in_play":
			var want: int = Constants.CardType.ALIADO if per == "own_allies" else Constants.CardType.TOTEM
			for cname in BOARD_CONTAINERS:
				var container = main.get(cname)
				if not container:
					continue
				var is_own: bool = cname.begins_with("player_") == (controller_id == 0)
				if per != "totems_in_play" and not is_own:
					continue
				for c in container.get_children():
					if is_instance_valid(c) and c.get("card_type") == want:
						n += 1
	return n


func _discard(main: Node, st: Dictionary, controller_id: int) -> bool:
	var pid: int = controller_id if st.who == "self" else 1 - controller_id
	var hand := _hand_cards(main, pid)
	if hand.is_empty():
		return false
	var amount: int = mini(st.amount, hand.size())
	var picked: Array = []
	if st.random:
		hand.shuffle()
		picked = hand.slice(0, amount)
	elif _is_bot(pid):
		hand.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
		picked = hand.slice(0, amount)
	else:
		picked = await _ts._targeted_executor._select_hand_cards_for_discard(hand, amount, pid)
	if picked.is_empty():
		return false
	await ActionModule.discard(pid, picked, "efecto_compilado", true)
	return picked.size() >= st.amount


# =============================================================================
# COSTES (EffectCompiler.COST_PIECES): se revisan todos y después se pagan, antes de declarar.
# =============================================================================
func _cost_candidates(main: Node, c: Dictionary, card: Node, controller_id: int) -> Array:
	"""Cartas entre las que se elige el coste: la mano (Descartar / mostrar) o tus otros Aliados en
	juego (Destruir otro Aliado que controles)."""
	match c.kind:
		"discard", "reveal":
			var types: Array = c.get("types", [])
			var race := str(c.get("race", ""))
			var in_hand: Array = []
			for h in _hand_cards(main, controller_id):
				if not is_instance_valid(h) or h == card:
					continue
				if not types.is_empty() and _type_word(int(h.card_type)) not in types:
					continue
				if not race.is_empty() and not (race.substr(0, 5) in EffectCompilerScript.normalize(str(h.get("card_raza")))):
					continue
				in_hand.append(h)
			return in_hand
		"sacrifice":
			var out: Array = []
			for cont in PlayerSideScript.ally_containers(main, controller_id):
				for a in cont.get_children():
					if is_instance_valid(a) and a != card and a.get("card_type") == Constants.CardType.ALIADO:
						out.append(a)
			return out
	return []


func _cost_unpayable(main: Node, c: Dictionary, card: Node, controller_id: int) -> String:
	"""'' si el coste se puede pagar; si no, por qué."""
	var zone = card.get("current_zone")
	match c.kind:
		"self_banish":
			if zone == Constants.Zone.DESTIERRO:
				return "ya está en el Destierro"
			if load("res://scripts/core/effects/mechanics/ProtectionRules.gd").cannot_be_banished(card):
				return "no puede ser Desterrado"
		"self_discard":
			if zone != Constants.Zone.MANO:
				return "no está en tu mano"
		"self_bounce":
			if not (zone in Constants.ZONES_IN_PLAY):
				return "no está en juego"
		"self_destroy":
			if not (zone in Constants.ZONES_IN_PLAY):
				return "no está en juego"
			if not KeywordManager.can_be_destroyed(card):
				return "no puede ser Destruido"
		"shuffle_hand":
			if _hand_cards(main, controller_id).filter(func(h): return h != card).size() < int(c.amount):
				return "no tienes %d cartas en tu mano" % int(c.amount)
		"self_pay":
			if card.get_parent() != PlayerSideScript.gold_reserva(main, controller_id):
				return "no está en tu Reserva"
		"self_convert":
			if int(card.get("card_type")) != Constants.CardType.ORO or KeywordManager.is_silenced(card):
				return "ya es un Oro sin habilidad"
		"mill":
			if CardManager.get_deck_count(controller_id) < int(c.amount):
				return "no tienes %d cartas en tu Castillo" % int(c.amount)
		"discard", "reveal", "sacrifice":
			if _cost_candidates(main, c, card, controller_id).size() < int(c.amount):
				return "no tienes con qué pagar el coste"
	return ""


func _pay_cost(main: Node, c: Dictionary, card: Node, controller_id: int) -> bool:
	var name := _card_name(card)
	match c.kind:
		"self_banish":
			var owner_id: int = card.owner_id if card.get("owner_id") != null else controller_id
			if card.get("current_zone") == Constants.Zone.CEMENTERIO:
				# En el Cementerio la carta son datos (CardManager); el Nodo fuente es una vista.
				var idx: int = CardManager.get_cemetery(owner_id).find(card.card_data)
				if idx < 0:
					return false
				var data: Dictionary = CardManager.remove_from_cemetery(owner_id, idx)
				data["esta_oculta"] = false
				CardManager.append_to_exile(owner_id, data)
				return true
			if card.get("current_zone") == Constants.Zone.MANO:
				# Como Drácula (HandCementerioAbilityHandler): sale de la mano y sus datos van al Destierro.
				var hand_data: Dictionary = PlayerSideScript.take_from_hand(main, owner_id, card)
				if hand_data.is_empty():
					return false
				CardManager.add_to_exile(owner_id, hand_data)
				return true
			# bypass_prevention: es un coste propio (EffectController.exile_card()).
			return await EffectController.exile_card(owner_id, card, true)
		"self_discard":
			await ActionModule.discard(controller_id, [card], "coste", true)
			return true
		"self_destroy":
			# Cementerio de Kingstead. Con Exhumar va al Destierro (CardManager.destroy_card()).
			var d_owner: int = card.owner_id if card.get("owner_id") != null else controller_id
			return await EffectController.destroy_card(d_owner, card, true, card)
		"self_bounce":
			# "Subir este Oro a tu mano" (hem hem real): sale de juego y sus datos vuelven a la mano.
			var b_owner: int = card.owner_id if card.get("owner_id") != null else controller_id
			var b_data: Dictionary = card.card_data.duplicate()
			if card.get_parent() == PlayerSideScript.gold_reserva(main, b_owner):
				GameState.agregar_oro_reserva(b_owner, -1)
			elif card.get_parent() == PlayerSideScript.oro_pagado(main, b_owner):
				GameState.agregar_oro_pagado(b_owner, -1)
			if b_owner == 0 and main.get("gold_cards") is Array:
				main.gold_cards.erase(card)
			if card.get_parent():
				card.get_parent().remove_child(card)
			card.queue_free()
			PlayerSideScript.put_in_hand(main, b_owner, b_data)
			if main._gold_manager:
				main._gold_manager._update_gold_display()
			return true
		"shuffle_hand":
			return await _shuffle_from_hand(main, {"amount": int(c.amount), "up_to": false}, controller_id)
		"self_pay":
			var diverted: bool = await main._gold_manager._mover_oro_a_pagado(card)
			if not diverted:
				GameState.pagar_oro(controller_id, 1)
			main._gold_manager._update_gold_display()
			return true
		"self_convert":
			await KeywordManager.silence_card(card, card, "permanent", true)
			main._update_debug("%s se convierte en un Oro sin habilidad" % name)
			return true
		"mill":
			await ActionModule.mill(controller_id, int(c.amount), false, "coste", true)
			return true
		"discard", "reveal", "sacrifice":
			var pool := _cost_candidates(main, c, card, controller_id)
			var n: int = int(c.amount)
			var picked: Array = []
			if _is_bot(controller_id):
				pool.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
				picked = pool.slice(0, n)
			elif c.kind == "discard":
				picked = await _ts._targeted_executor._select_hand_cards_for_discard(pool, n, controller_id)
			else:
				var prompt := "%s: %s" % [name, "muestra una carta de tu mano" if c.kind == "reveal" else "Destruye otro Aliado que controles"]
				picked = await main._card_interaction.await_multi_target(prompt, pool, n, Callable(), Callable(),
					false, null, controller_id)
			picked = picked.filter(func(p): return is_instance_valid(p))
			if picked.size() < n:
				return false
			match c.kind:
				"discard":
					await ActionModule.discard(controller_id, picked, "coste", true)
				"reveal":
					load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, picked.map(func(p): return p.card_data), name)
				"sacrifice":
					await ActionModule.destroy(picked, card, false, true)
			return true
	return false


func _shuffle_from_hand(main: Node, st: Dictionary, controller_id: int) -> bool:
	"""'Baraja (hasta) N cartas de tu mano (en tu Castillo)' — mismo
	mecanismo que DSR_ShuffleDrawCombos (Manuel Bulnes)."""
	var hand_container = PlayerSideScript.hand(main, controller_id)
	var hand := _hand_cards(main, controller_id)
	if not hand_container or hand.is_empty():
		return st.up_to  # "hasta N" con la mano vacía igual se resolvió
	var pick_amount: int = mini(st.amount, hand.size())
	var chosen: Array = []
	if _is_bot(controller_id):
		if not st.up_to:
			hand.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
			chosen = hand.slice(0, pick_amount)
	else:
		var prompt := "Baraja %s%d carta(s) de tu mano en tu Castillo" % ["hasta " if st.up_to else "", st.amount]
		chosen = await main._card_interaction.await_multi_target(prompt, hand, pick_amount, Callable(), Callable(),
			st.up_to, null, controller_id)
	var shuffled := 0
	for c in chosen:
		if is_instance_valid(c):
			var data: Dictionary = c.card_data
			hand_container.remove_card(c, true)
			CardManager.get_deck(controller_id).append(data)
			shuffled += 1
	if shuffled > 0:
		CardManager.shuffle_deck(controller_id)
		AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (efecto compilado)")
	return st.up_to or shuffled >= st.amount


# =============================================================================
# AUXILIARES
# =============================================================================
func _ask_yes_no(main: Node, title: String, chooser_id: int) -> bool:
	if _is_bot(chooser_id):
		return true
	return await SelectionManager.await_two_choice(main, title, "Sí", "No", chooser_id)


func _is_bot(pid: int) -> bool:
	return PlayerSideScript.is_bot(pid)


func _hand_cards(main: Node, pid: int) -> Array:
	return PlayerSideScript.hand_cards(main, pid)


static func _controller_of(c: Node) -> int:
	if c.get("controller_id") != null:
		return int(c.controller_id)
	return int(c.owner_id) if c.get("owner_id") != null else 0


static func _card_name(card: Node) -> String:
	return str(card.card_name) if card and card.get("card_name") != null else "Habilidad"


static func _keyword_enum(word: String) -> int:
	match word:
		"furia":
			return Constants.Keyword.FURIA
		"imbloqueable":
			return Constants.Keyword.IMBLOQUEABLE
		"indestructible":
			return Constants.Keyword.INDESTRUCTIBLE
		"indesterrable":
			return Constants.Keyword.INDESTERRABLE
		"unica":
			return Constants.Keyword.UNICA
	return Constants.Keyword.EXHUMAR


static func _type_enum(word: String) -> int:
	match word:
		"oro":
			return Constants.CardType.ORO
		"arma":
			return Constants.CardType.ARMA
		"talisman":
			return Constants.CardType.TALISMAN
		"totem":
			return Constants.CardType.TOTEM
	return Constants.CardType.ALIADO


static func _type_word(ctype: int) -> String:
	match ctype:
		Constants.CardType.ORO:
			return "oro"
		Constants.CardType.ARMA:
			return "arma"
		Constants.CardType.TALISMAN:
			return "talisman"
		Constants.CardType.TOTEM:
			return "totem"
	return "aliado"


static func _object_label(spec: Dictionary, count: int) -> String:
	var types: Array = spec.get("card_types", [])
	var words: Array = TYPE_LABELS.get(types[0] if not types.is_empty() else "", TYPE_LABELS[""])
	var noun: String = words[0] if count == 1 else "%d %s" % [count, words[1]]
	var article := ("un " if words[0] in ["Aliado", "Tótem", "Talismán", "Oro"] else "una ") if count == 1 else ""
	var suffix := " oponente" if spec.get("controller", "any") == "opponent" else ""
	if count != 1 and suffix != "":
		suffix = " oponentes"
	return article + noun + suffix


static func _upper_first(s: String) -> String:
	# String.capitalize() de Godot pone en mayúscula CADA palabra.
	return s.substr(0, 1).to_upper() + s.substr(1)


static func describe_steps(steps: Array) -> String:
	"""Texto corto en español neutro para los botones de una elección."""
	var parts: Array = []
	for st in steps:
		match st.op:
			"draw":
				parts.append(("Robar hasta %d" if st.get("up_to", false) else "Robar %d") % st.amount)
			"draw_to_match":
				parts.append("Robar hasta igualar la mano de tu oponente")
			"self_buff_per":
				parts.append("Gana %d de Fuerza por cada carta" % st.amount)
			"mill":
				var mill_words := {"self": "Botar %d", "opponent": "Tu oponente bota %d", "both": "Cada jugador bota %d"}
				parts.append(mill_words.get(st.who, "Botar %d") % st.amount)
			"reveal_until":
				var wanted: Array = []
				for sp in st.specs:
					var tl: Array = TYPE_LABELS.get(sp.types[0] if sp.types.size() == 1 else "", TYPE_LABELS[""])
					wanted.append(tl[0] if int(sp.count) == 1 else "%d %s" % [sp.count, tl[1]])
				parts.append("Mostrar del tope hasta %s" % " y ".join(wanted))
			"discard":
				parts.append("Descartar %d" % st.amount)
			"shuffle_from_hand":
				parts.append("Barajar %d de tu mano" % st.amount)
			"search":
				var t: Array = TYPE_LABELS.get(st.card_type, TYPE_LABELS[""])
				var zones: Array = []
				for z in st.zones:
					zones.append("tu Castillo" if z == "castillo" else "tu Cementerio")
				parts.append("Buscar %s en %s" % [t[0] if st.amount == 1 else "%d %s" % [st.amount, t[1]], " o ".join(zones)])
			"target":
				parts.append("%s %s" % [_upper_first(VERB_LABELS.get(st.verb, st.verb)), _object_label(st.target, st.count)])
			"mass":
				parts.append("%s todos" % _upper_first(VERB_LABELS.get(st.verb, st.verb)))
			"shuffle_from_cemetery":
				parts.append("Barajar %d de tu Cementerio" % st.amount)
			"self":
				parts.append("Destruirla" if st.verb == "destroy" else "Desterrarla")
			"cemetery_cleanup":
				var verb_words := {"both": "Barajar y/o Desterrar", "banish": "Desterrar", "shuffle": "Barajar"}
				parts.append("%s hasta %d de los Cementerios" % [verb_words.get(st.mode, ""), st.amount])
			"gold":
				parts.append("Generar %d Oro%s" % [st.amount, "" if st.amount == 1 else "s"])
			"pay":
				parts.append("Pagar %d Oro%s" % [st.amount, "" if st.amount == 1 else "s"])
			"cost":
				parts.append({"self_banish": "Desterrar esta carta", "self_discard": "Descartar esta carta",
					"self_pay": "Pagar este Oro", "self_convert": "Convertir este Oro en un Oro sin habilidad",
					"discard": "Descartar %d" % st.amount, "mill": "Botar %d" % st.amount,
					"reveal": "Mostrar una carta de tu mano", "sacrifice": "Destruir otro Aliado",
					"self_bounce": "Subir esta carta a tu mano", "self_destroy": "Destruir esta carta",
					"shuffle_hand": "Barajar %d de tu mano" % st.amount}.get(st.kind, st.kind))
			"hand_peek":
				var peek_verbs := {"banish": "Desterrar", "discard": "Descartar", "shuffle": "Barajar"}
				parts.append("Mirar la mano rival y %s %d" % [str(peek_verbs.get(st.verb, "")).to_lower(), st.count])
			"buff" when st.has("set_strength") or st.get("double", false):
				parts.append("%s %s" % [_object_label(st.target, st.count),
					"duplica su Fuerza" if st.get("double", false) else "tiene Fuerza %d" % int(st.get("set_strength", 0))])
			"buff":
				var gains: Array = []
				for kw in st.get("keywords", []):
					gains.append(_upper_first(kw))
				if int(st.amount) != 0:
					gains.append("%d de Fuerza" % absi(st.amount))
				if st.get("to_exile", false):
					gains.append("daño al Destierro")
				if st.get("no_shuffle", false):
					gains.append("\"No puede ser Barajado\"")
				if st.get("double_damage", false):
					gains.append("doble de daño")
				if st.get("no_damage", false):
					gains.append("no hacer daño de combate")
				parts.append("%s %s %s" % [_object_label(st.target, st.count),
					"pierde" if st.amount < 0 else "gana", ", ".join(gains)])
			"mass_buff":
				var mass_gains: Array = []
				for kw in st.get("keywords", []):
					mass_gains.append(_upper_first(kw))
				if int(st.amount) != 0:
					mass_gains.append("%d de Fuerza" % absi(st.amount))
				parts.append("%s %s %s" % ["Los Aliados oponentes" if st.side == "opponent" else ("Tus demás Aliados" if st.others else "Tus Aliados"),
					"pierden" if st.amount < 0 else "ganan", ", ".join(mass_gains)])
			"choice":
				var labels: Array = []
				for o in st.options:
					labels.append(describe_steps(o))
				parts.append(" o ".join(labels))
			"annul":
				parts.append(_upper_first(str(st.text)))
			"regroup_gold":
				parts.append("Agrupar %d Oro%s" % [st.amount, "" if st.amount == 1 else "s"])
			"regroup_cards":
				parts.append("Agrupar %d carta%s" % [st.amount, "" if st.amount == 1 else "s"])
			"castle_look":
				parts.append(_upper_first(str(st.text)))
			"gold_to_paid":
				parts.append("Poner un Oro en tu %s" % ("Oro Pagado" if st.get("dest", "pagado") == "pagado" else "Reserva"))
			"deck_to_hand":
				parts.append("Poner cartas de tu Castillo en tu mano")
			"self_raise":
				parts.append("Subir esta carta de tu Cementerio a tu mano")
			"mill_x":
				parts.append("%s tantas cartas como %s" % ["Desterrar del Castillo rival" if st.get("exile", false) else "Botar",
					{"own_ally": "la Fuerza de un Aliado tuyo", "armed_ally": "la Fuerza de un Aliado con Arma",
					"bearer": "la Fuerza del portador", "opp_hand_allies": "Aliados en la mano rival"}.get(st.src, "")])
			"cancel_attack":
				parts.append("Cancelar el ataque de %d Aliado%s" % [st.count, "" if st.count == 1 else "s"])
			"castle_exile":
				if st.get("per", "") == "opp_reserve":
					parts.append("Desterrar del tope del Castillo rival tantas como Oros tenga en su Reserva")
				else:
					parts.append("Desterrar %d del %s del Castillo rival" % [st.amount, "fondo" if st.get("bottom", false) else "tope"])
			"peek_hand":
				parts.append("Mirar la mano de tu oponente")
			"show_hand":
				parts.append("Mostrar tu mano")
			"play_from":
				var pt: Array = TYPE_LABELS.get(st.get("card_type", ""), TYPE_LABELS[""])
				parts.append("Jugar %s de tu %s" % [pt[0], " o ".join(st.zones)])
			"no_damage":
				parts.append("No recibir daño%s hasta tu próximo turno" % (" de combate" if st.get("combat_only", false) else ""))
			"talisman_fizzle":
				parts.append("El próximo Talismán de tu oponente este turno se resuelve sin efecto")
			_:
				parts.append(st.op)
	return " y ".join(parts)
