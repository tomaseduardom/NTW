extends "res://scripts/core/effects/compiler/EffectInterpreterCostes.gd"
## EffectInterpreterDeclaracion — familia Declaracion de EffectInterpreter.gd (ver EffectInterpreterBase.gd).


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
			if main._card_interaction.has_method("_pay_affect_tax") and not await main._card_interaction._pay_affect_tax([pre], controller_id, str(st.get("verb", ""))):
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
	if spec.get("controller", "any") == "own" and _controller_of(c) != controller_id:
		return false  # "un Aliado que controles" (kuji-in)
	if spec.get("owned", false) and int(c.get("owner_id") if c.get("owner_id") != null else controller_id) != controller_id:
		return false  # "del que seas dueño" (lurulu)
	# "un Aliado Bandido": raza sin tildes; los 5 primeros caracteres cubren plurales.
	var race: String = str(spec.get("race", ""))
	if not race.is_empty() and not (race.substr(0, 5) in EffectCompilerScript.normalize(str(c.get("card_raza")))):
		return false
	var stat: String = spec.get("stat", "")
	if stat == "coste" and ctype == Constants.CardType.ORO and spec.get("gold_ok", false):
		return true  # "un Oro o carta de coste 2 o menos": el Oro no se mide por coste
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
