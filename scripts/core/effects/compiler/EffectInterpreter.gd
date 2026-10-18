extends RefCounted
class_name EffectInterpreter
## EffectInterpreter — ejecuta los planes de EffectCompiler (2026-10-12, ver
## arquitectura.md §54).
##
## Orden: se declara todo (opcional "puedes", rama de una elección "A, o
## B", objetivos en juego) y después se ejecutan los pasos en orden, "en la
## medida de lo posible". Un paso marcado "then" (impreso tras "Luego,")
## solo corre si el anterior se resolvió por completo.
##
## Ventana de respuesta (§59): tras declarar llama a EffectContext.
## ensure_window() — si el efecto todavía no le dio su ventana al rival
## (triggers: ya no se abre por adelantado), se abre ahí; si ya la tuvo
## (Talismanes, activadas en la Pila), no se abre otra.
##
## Quién elige: el jugador local (0) con clic en el tablero; el Remoto real
## (1 con sala abierta) por red — await_target()/await_multi_target()/
## await_choice() ya delegan solos; el bot local (1 sin sala) elige aquí
## mismo con una heurística simple.
##
## Solo ejecuta planes cuyos pasos sabe resolver (EffectCompiler.
## EXECUTABLE_OPS/VERBS): si el compilador entendió algo que el intérprete
## todavía no sabe hacer (p.ej. "Sube ... a la mano de su dueño"), devuelve
## false y sigue la cadena de patrones vieja. Al agregar una pieza nueva
## aquí, sumarla también a esas listas.

const VERB_LABELS := {
	"destroy": "destruir", "banish": "desterrar", "shuffle": "barajar en el Castillo de su dueño",
	"bounce": "subir a la mano de su dueño",
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

var _ts: Node  # TriggerSystem (dueño de este intérprete)


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
	print("[EffectInterpreter] %s: %d paso(s) compilados" % [_card_name(card), plan.steps.size()])
	await execute_plan(plan, card, controller_id)
	return true


func execute_plan(plan: Dictionary, card: Node, controller_id: int) -> void:
	var main := _ts.get_node_or_null("/root/Main")
	if not main:
		return
	var name := _card_name(card)

	# ── Declarar ──────────────────────────────────────────────────────────
	# "Puedes": si el primer paso ya se puede rechazar en el propio
	# selector (búsqueda con mínimo 0, objetivo con ESC), no se agrega un
	# popup Sí/No aparte — a pedido del usuario, la elección va en el
	# tablero siempre que se pueda (§49-§53).
	var first_op: String = plan.steps[0].op if not plan.steps.is_empty() else ""
	var declinable_in_place: bool = first_op in ["search", "target"]
	# Habilidad activada: el clic en su botón ya confirmó el "puedes"
	# (mismo criterio que UniversalCardParser.parse_abilities()).
	if plan.optional and not declinable_in_place and not plan.get("activated", false):
		if not await _ask_yes_no(main, "¿Usar la habilidad de %s?" % name, controller_id):
			return

	var steps: Array = await _resolve_choices(main, plan.steps, card, controller_id)
	var chosen_targets: Dictionary = {}  # índice de paso → Array[Node]
	for i in range(steps.size()):
		var st: Dictionary = steps[i]
		if st.op == "target":
			var may_decline: bool = plan.optional and i == 0 and declinable_in_place
			chosen_targets[i] = await _declare_targets(main, st, card, controller_id, may_decline)
			if may_decline and chosen_targets[i].is_empty():
				return  # rechazó el "puedes" desde el propio selector

	if card.has_method("play_ability_activation_effect"):
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
		var options: Array = st.options
		var picked := 0
		if _is_bot(controller_id):
			picked = 0
		else:
			var labels: Array = []
			for o in options:
				labels.append(describe_steps(o))
			picked = await SelectionManager.await_choice(main, "%s: elige una opción" % _card_name(card), labels, controller_id)
			picked = clampi(picked, 0, options.size() - 1)
		out.append_array(await _resolve_choices(main, options[picked], card, controller_id))
	return out


func _declare_targets(main: Node, st: Dictionary, card: Node, controller_id: int, may_decline: bool = false) -> Array:
	var spec: Dictionary = st.target
	var candidates := _candidates(main, spec, card, controller_id)
	if candidates.is_empty():
		return []
	var count: int = st.count
	var mandatory: bool = not st.up_to and not may_decline
	if _is_bot(controller_id):
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
	var stat: String = spec.get("stat", "")
	if stat != "":
		var v: int = ContinuousEffectManager.get_modified_strength(c) if stat == "fuerza" \
			else ContinuousEffectManager.get_modified_cost(c)
		var limit: int = spec.get("value", 0)
		if spec.get("cmp", "<=") == "<=" and v > limit:
			return false
		if spec.get("cmp", "<=") == ">=" and v < limit:
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
		"mill":
			var mill_pid: int = controller_id if st.who == "self" else opponent_id
			var mill_amount: int = st.amount
			if st.get("per", "") != "":
				mill_amount *= _count_per(main, st.per, controller_id)
			if mill_amount > 0:
				await ActionModule.mill(mill_pid, mill_amount, false, "efecto_compilado", true)
			return true
		"shuffle_from_cemetery":
			var res_cem: Dictionary = await ActionModule.search_zones(controller_id, [Constants.Zone.CEMENTERIO], {},
				st.amount, st.up_to, false, false, card, Constants.Zone.CASTILLO)
			return st.up_to or res_cem.get("selected", []).size() >= st.amount
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
			var filter := {}
			if st.card_type != "":
				filter["type"] = _type_enum(st.card_type)
			var res: Dictionary = await ActionModule.search_zones(controller_id, zones, filter, st.amount, true, false,
				false, card, Constants.Zone.MANO)
			return res.get("success", false) and not res.get("selected", []).is_empty()
		"target":
			return await _apply_verb(st, targets, card)
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
			"shuffle":
				for t in group:
					var owner: int = int(t.owner_id) if t.get("owner_id") != null else _controller_of(t)
					if await ActionModule.return_to_deck(t, owner, true, card):
						CardManager.shuffle_deck(owner)
					else:
						all_ok = false
	return all_ok


func _condition_holds(cond: String, card: Node) -> bool:
	match cond:
		"not_attacked_this_turn":
			return int(card.get_meta("declared_attacker_turn", -1)) != GameManager.current_turn
	push_warning("[EffectInterpreter] Condición desconocida: %s" % cond)
	return false


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
			"mill":
				parts.append(("Botar %d" if st.who == "self" else "Tu oponente bota %d") % st.amount)
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
			_:
				parts.append(st.op)
	return " y ".join(parts)
