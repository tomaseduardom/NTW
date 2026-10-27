extends "res://scripts/core/effects/compiler/EffectInterpreterAuxiliares.gd"
## EffectInterpreterCostes — familia Costes de EffectInterpreter.gd (ver EffectInterpreterBase.gd).


# =============================================================================
# COSTES (EffectCompiler.COST_PIECES): se revisan todos y después se pagan, antes de declarar.
# =============================================================================


func _cost_candidates(main: Node, c: Dictionary, card: Node, controller_id: int) -> Array:
	"""Cartas entre las que se elige el coste: la mano (Descartar / mostrar / Desterrar de la mano) o
	tus otros Aliados en juego (Destruir otro Aliado que controles)."""
	match c.kind:
		"discard", "reveal", "banish_hand":
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
		"sacrifice_any":
			return _controlled_in_play(main, controller_id).filter(func(x: Node) -> bool:
				if not c.get("types", []).is_empty() and _type_word(int(x.card_type)) not in c.types:
					return false
				if int(c.get("cost_val", -1)) >= 0:
					var cost := int(x.get("card_cost"))
					var cv := int(c.cost_val)
					if (c.cost_cmp == "mas" and cost < cv) or (c.cost_cmp == "menos" and cost > cv) \
							or (c.cost_cmp == "" and cost != cv):
						return false
				return true)
	return []


func _own_cemetery_cost_pool(card: Node, controller_id: int) -> Array:
	"""Cartas del Cementerio propio que pueden pagar "Desterrar N cartas de tu Cementerio": todas menos la
	carta misma (si la habilidad se usa desde el Cementerio)."""
	var self_data = card.card_data if card and card.get("card_data") != null else null
	return CardManager.get_cemetery(controller_id).filter(func(d): return not is_same(d, self_data))


func _shuffle_self(main: Node, card: Node, controller_id: int) -> bool:
	"""Baraja la carta misma en el Castillo de su dueño desde donde esté: en juego (con sus Armas), en la
	Reserva, en la mano, en el Cementerio o en el Destierro."""
	var owner_id: int = card.owner_id if card.get("owner_id") != null else controller_id
	var zone = card.get("current_zone")
	var data: Dictionary = {}
	match zone:
		Constants.Zone.CEMENTERIO:
			var idx: int = CardManager.get_cemetery(owner_id).find(card.card_data)
			if idx < 0:
				return false
			data = CardManager.remove_from_cemetery(owner_id, idx)
		Constants.Zone.DESTIERRO:
			var exile: Array = CardManager.get_exile(owner_id)
			var eidx: int = exile.find(card.card_data)
			if eidx < 0:
				return false
			data = exile[eidx]
			exile.remove_at(eidx)
		Constants.Zone.MANO:
			data = PlayerSideScript.take_from_hand(main, owner_id, card)
		_:
			if not await ActionModule.return_to_deck(card, owner_id, true, card):
				return false
	if not data.is_empty():
		data["esta_oculta"] = true
		CardManager.add_to_deck_top(owner_id, data)
	CardManager.shuffle_deck(owner_id)
	AnimationQueue.queue_shuffle(owner_id, "Barajar mazo (%s)" % _card_name(card))
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return true


func _controlled_in_play(main: Node, pid: int) -> Array:
	"""Cartas en juego que controla 'pid': Líneas, Armas portadas, Reserva y Oro Pagado."""
	var out: Array = []
	for cont in PlayerSideScript.line_containers(main, pid):
		for x in cont.get_children():
			if not is_instance_valid(x) or x.get("card_type") == null:
				continue
			out.append(x)
			if x.get("equipped_weapons") is Array:
				for w in x.equipped_weapons:
					if is_instance_valid(w) and not (w in out):
						out.append(w)
	for cont in [PlayerSideScript.gold_reserva(main, pid), PlayerSideScript.oro_pagado(main, pid)]:
		if cont:
			for g in cont.get_children():
				if is_instance_valid(g) and g.get("card_type") != null:
					out.append(g)
	return out


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
		"self_shuffle":
			if zone in Constants.ZONES_IN_PLAY and load("res://scripts/core/effects/mechanics/ProtectionRules.gd").cannot_be_shuffled(card):
				return "no puede ser Barajado"
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
		"banish_cemetery":
			if _own_cemetery_cost_pool(card, controller_id).size() < int(c.amount):
				return "no tienes %d cartas en tu Cementerio" % int(c.amount)
		"discard", "reveal", "sacrifice", "banish_hand", "sacrifice_any":
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
		"self_shuffle":
			return await _shuffle_self(main, card, controller_id)
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
		"banish_cemetery":
			var cem_pool := _own_cemetery_cost_pool(card, controller_id)
			var need: int = int(c.amount)
			var chosen: Array = []
			if _is_bot(controller_id):
				chosen = cem_pool.slice(0, need)
			else:
				var entries: Array = cem_pool.map(func(d): return {"data": d, "eligible": true})
				var raw: Array = await ActionModule.pick_in_zones(controller_id, "%s: Destierra %d carta(s) de tu Cementerio" % [name, need],
					[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], need, need)
				for r in raw:
					if r is Array and r.size() == 2 and int(r[1]) >= 0 and int(r[1]) < entries.size():
						chosen.append(entries[int(r[1])].data)
			if chosen.size() < need:
				return false
			for d in chosen:
				if CardManager.take_from_cemetery(controller_id, d):
					d["esta_oculta"] = false
					CardManager.append_to_exile(controller_id, d)
			return true
		"discard", "reveal", "sacrifice", "banish_hand", "sacrifice_any":
			var pool := _cost_candidates(main, c, card, controller_id)
			var n: int = int(c.amount)
			var picked: Array = []
			if _is_bot(controller_id):
				pool.sort_custom(func(a: Node, b: Node) -> bool: return int(a.card_cost) < int(b.card_cost))
				picked = pool.slice(0, n)
			elif c.kind == "discard":
				picked = await _ts._targeted_executor._select_hand_cards_for_discard(pool, n, controller_id)
			else:
				var sac_verb := {"destroy": "Destruye", "banish": "Destierra", "shuffle": "Baraja"}
				var what := {"reveal": "muestra una carta de tu mano", "sacrifice": "Destruye otro Aliado que controles",
					"banish_hand": "Destierra %d carta(s) de tu mano" % n,
					"sacrifice_any": "%s %d carta(s) que controles" % [sac_verb.get(str(c.get("verb", "")), ""), n]}
				var prompt := "%s: %s" % [name, what.get(c.kind, "")]
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
				"sacrifice_any":
					match str(c.get("verb", "destroy")):
						"destroy":
							await ActionModule.destroy(picked, card, false, true)
						"banish":
							for p in picked:
								var p_owner: int = p.owner_id if p.get("owner_id") != null else controller_id
								await EffectController.exile_card(p_owner, p, true)
						"shuffle":
							for p in picked:
								var s_owner: int = p.owner_id if p.get("owner_id") != null else controller_id
								await ActionModule.return_to_deck(p, s_owner, true, card)
				"banish_hand":
					for p in picked:
						var data: Dictionary = PlayerSideScript.take_from_hand(main, controller_id, p)
						if not data.is_empty():
							data["esta_oculta"] = false
							CardManager.add_to_exile(controller_id, data)
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
