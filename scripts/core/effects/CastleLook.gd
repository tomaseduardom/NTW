extends RefCounted
## CastleLook — motor único de "mira N cartas del tope/fondo de un Castillo" (arquitectura.md §69).
## Regla (DAR): mirar un Castillo siempre deja ordenar las cartas que vuelven, aunque el texto no lo
## diga; vuelven al lado del que se miraron (tope → tope, fondo → fondo) salvo que el efecto diga
## otra cosa (Infernum Vox: "tope y/o fondo"). "Muestra" no entra aquí (es público).
## Todo en una ventana (CastleLookWindow): repartir a los destinos y ordenar el resto. Nada se mueve
## hasta confirmar, y los destinos que pueden disparar efectos (Oros a la Reserva/Oro Pagado, p.ej.
## Drácula) se aplican AL FINAL.
## Quién elige: Anfitrión (ventana local), Remoto (la misma ventana por red, prompt "castle_look") o
## bot local (reparto automático).
## boxes: [{key, label, dest, min = 0, max = -1, ordered = false, filter = Callable(card_data) ->
## bool}]
## dest: "top" | "bottom" | "shuffle" (vuelven al Castillo) | "hand" | "cemetery" | "exile" |
## "reserva" | "pagado" | "custom" (lo aplica el llamador).
## La primera zona con ordered = true (o start = true, sin flechas de orden) es donde empiezan todas
## las cartas.
## Devuelve {key: [card_data...]} (vacío si no había nada que mirar).
## Se usa con preload (sin class_name global; ver §54).

const WindowScript = preload("res://scripts/ui/zones/CastleLookWindow.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")


static func look(player_id: int, deck_owner: int, count: int, from_top: bool, boxes: Array, title: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = tree.root.get_node_or_null("/root/Main") if tree else null
	if EffectController.fision_hides_zones_of(deck_owner, player_id):  # Fisión Nuclear
		return {}
	var deck: Array = CardManager.get_deck(deck_owner)
	var n: int = mini(count, deck.size())
	if n <= 0 or not main:
		return {}
	var cards: Array = deck.slice(0, n) if from_top else deck.slice(deck.size() - n)

	var cfg_boxes: Array = []
	var start_key := ""
	for box in boxes:
		var filter: Callable = box.get("filter", Callable())
		var eligible: Array = []
		var eligible_count := 0
		for d in cards:
			var ok: bool = not filter.is_valid() or filter.call(d)
			eligible.append(ok)
			if ok:
				eligible_count += 1
		var ordered: bool = box.get("ordered", false)
		if (ordered or box.get("start", false)) and start_key.is_empty():
			start_key = box.key
		cfg_boxes.append({"key": box.key, "label": box.label, "ordered": ordered,
			"min": mini(int(box.get("min", 0)), eligible_count), "max": int(box.get("max", -1)),
			"eligible": eligible})
	if start_key.is_empty():
		push_warning("[CastleLook] '%s' sin zona ordenada de inicio" % title)
		return {}
	var shown: Array = []
	for d in cards:
		var c: Dictionary = d.duplicate()
		c["esta_oculta"] = false
		shown.append(c)
	var cfg := {"title": title, "cards": shown, "boxes": cfg_boxes, "start": start_key}

	EffectContextScript.check_chooser(player_id, title)
	var picks: Dictionary
	if player_id == 1 and NetworkClient.room_code != "" and NetworkClient.is_host:
		NetworkClient.send_message({"op": "prompt", "kind": "castle_look", "config": cfg})
		var intent: Dictionary = await NetworkClient.await_intent(["castle_look_choice"])
		picks = WindowScript.validate(cfg, intent.get("result", {}))
	elif player_id == 1:
		picks = WindowScript.auto_pick(cfg)
	else:
		var w = WindowScript.new()
		picks = WindowScript.validate(cfg, await w.open(main, cfg))

	# Ventana de respuesta del rival DESPUÉS de elegir (opción B, §59): si
	# cancela el efecto, las cartas se quedan donde estaban.
	if await EffectContextScript.ensure_window():
		return {}

	# Recién ahora salen del Castillo (las mismas n del tope/fondo).
	for _i in n:
		deck.remove_at(0 if from_top else deck.size() - 1)
	var out: Dictionary = {}
	for box in boxes:
		out[box.key] = []
		for i in picks.get(box.key, []):
			out[box.key].append(cards[int(i)])

	# Castillo primero, después mano/Cementerio/Destierro, y los Oros al final
	# (pueden disparar "cuando entra en juego").
	var shuffle_needed := false
	var exile_blocked: bool = load("res://scripts/core/effects/mechanics/ProtectionRules.gd").castle_banish_blocked(deck_owner, player_id)
	for phase in [["top", "bottom", "shuffle"], ["hand", "cemetery", "exile"], ["reserva", "reserva_noskill", "pagado"]]:
		for box in boxes:
			var dest: String = box.get("dest", "custom")
			if dest not in phase:
				continue
			var list: Array = out[box.key]
			match dest:
				"top":
					for i in range(list.size() - 1, -1, -1):
						deck.push_front(list[i])
				"bottom":
					for d in list:
						deck.append(d)
				"shuffle":
					for d in list:
						deck.append(d)
					shuffle_needed = shuffle_needed or not list.is_empty()
				"hand":
					# Jinete de la Peste: no puede poner cartas en su mano por efectos — vuelven al tope.
					if load("res://scripts/core/effects/mechanics/ProtectionRules.gd").hand_by_effects_blocked(player_id):
						for i in range(list.size() - 1, -1, -1):
							deck.push_front(list[i])
						CardManager._emit_deck_changed(deck_owner)
					else:
						for d in list:
							await ActionModule._put_found_card_into_play(main, player_id, d, false)
				"cemetery":
					for d in list:
						CardManager.add_to_cemetery(deck_owner, d)
				"exile":
					# Cetro Demoniaco / nehushtan: no se puede Desterrar de ese Castillo — vuelven al tope.
					if exile_blocked:
						for i in range(list.size() - 1, -1, -1):
							deck.push_front(list[i])
						CardManager._emit_deck_changed(deck_owner)
					else:
						for d in list:
							CardManager.add_to_exile(deck_owner, d)
				"reserva":
					for d in list:
						await main._gold_manager.put_gold_directly_in_reserva(player_id, d)
				"reserva_noskill":
					for d in list:
						var no_skill: Dictionary = d.duplicate()
						no_skill["habilidad"] = ""
						await main._gold_manager.put_gold_directly_in_reserva(player_id, no_skill)
				"pagado":
					for d in list:
						await main._gold_manager.put_gold_directly_in_pagado(player_id, d)
		if phase[0] == "top":
			if shuffle_needed:
				CardManager.shuffle_deck(deck_owner)
				AnimationQueue.queue_shuffle(deck_owner, "Barajar mazo (%s)" % title.get_slice(":", 0))
			CardManager._emit_deck_changed(deck_owner)
			if main.get("_zone_manager"):
				main._zone_manager._update_castillo_counts()
	return out


static func rest_box(from_top: bool, can_choose_side: bool = false) -> Array:
	"""Zona(s) para las cartas que vuelven al Castillo. Con can_choose_side
	(Infernum Vox: 'en el tope y/o fondo'), dos zonas."""
	if can_choose_side:
		return [
			{"key": "top", "label": "Tope del Castillo", "dest": "top", "ordered": true},
			{"key": "bottom", "label": "Fondo del Castillo", "dest": "bottom", "ordered": true},
		]
	return [{"key": "rest", "label": "Vuelven al %s del Castillo" % ("tope" if from_top else "fondo"),
		"dest": "top" if from_top else "bottom", "ordered": true}]


# =============================================================================
# LECTOR DE TEXTO — "mira N cartas del tope/fondo de tu/un Castillo. Pon una
# en tu mano, otra en tu Cementerio y ordena/baraja el resto" y variantes.
# Solo se encarga si entiende TODO el bloque (lo que sobra puede ser solo un
# "Roba N cartas" final); si no, devuelve false y sigue la cadena de patrones
# de siempre (TriggerResolution._resolve_look_and_play_patterns()).
# =============================================================================
const _NUM := "(una|un|dos|tres|cuatro|cinco|seis|siete|ocho|\\d+)"
const _BASIS := "(oros controles|aliados controles más una|aliados controles|armas y tótem controles|armas controles|tótem hay en juego|aliados haya en tu destierro)"


static func _rx(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile("(?i)" + pattern)
	return r


static func _cut(text: String, m: RegExMatch) -> String:
	return text.substr(0, m.get_start()) + " " + text.substr(m.get_end())


static func try_execute_text(card: Node, text: String, controller_id: int, dry_run: bool = false) -> bool:
	"""dry_run: solo dice si entiende el texto (tests/auditor), sin ejecutar."""
	var lower := text.to_lower().replace("\n", " ")
	var look := _rx("mira(?:r|s)?\\s+(?:hasta\\s+)?(?:las\\s+)?(?:" + _NUM + "\\s+)?(?:primeras\\s+)?"
		+ "(?:(una|dos|tres|cuatro|cinco|seis|siete|ocho|\\d+|tantas)\\s+)?cartas\\s+"
		+ "(?:del\\s+(tope|fondo)\\s+|de\\s+la\\s+parte\\s+superior\\s+)?de\\s+(tu|un)\\s+castillo"
		+ "(?:\\s+como\\s+" + _BASIS + ")?").search(lower)
	if not look:
		return false
	# Lo de antes de "mira": solo disparadores/frecuencia, nunca un coste.
	var prefix: String = lower.substr(0, look.get_start())
	prefix = _rx("cuando [^,]+,|al comienzo de [^,]+,|en tu vigilia,|en tu fase final,|una vez (?:por|en tu) turno,"
		+ "|si no has puesto oros en juego este turno,|puedes|\\by\\b|^\\s*-").sub(prefix, "", true)
	if not prefix.strip_edges().is_empty():
		return false

	var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Main")
	if not main and not dry_run:
		return false
	# dry_run sin Main (EffectCompiler en los tests de consola): solo importa si entiende el texto.
	var count: int = _look_count(main, look, controller_id) if main else 0
	if count < 0:
		return false
	var from_top: bool = look.get_string(3) != "fondo"

	# Destinos: se corta cada fragmento reconocido; lo que sobre decide.
	var rest: String = lower.substr(look.get_end())
	var boxes: Array = []
	var rest_dest := "same"
	var draw_after := 0
	var m: RegExMatch
	m = _rx("esta habilidad no puede ser cancelada").search(rest)
	if m:
		rest = _cut(rest, m)
	m = _rx("y\\s+devolverlas\\s+en\\s+cualquier\\s+orden\\s+en\\s+el\\s+tope\\s+y/o\\s+fondo\\s+del\\s+castillo").search(rest)
	if m:
		rest_dest = "both"
		rest = _cut(rest, m)
	m = _rx("(?:pon|poner)\\s+un\\s+oro\\s+de\\s+ah[ií]\\s+en\\s+tu\\s+reserva(\\s+como\\s+un\\s+oro\\s+sin\\s+habilidad)?").search(rest)
	if m:
		boxes.append({"key": "reserva", "label": "Un Oro a tu Reserva", "min": 0, "max": 1,
			"dest": "reserva_noskill" if not m.get_string(1).is_empty() else "reserva",
			"filter": func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO})
		rest = _cut(rest, m)
	m = _rx("(?:pon|poner)\\s+(hasta\\s+)?" + _NUM + "\\s+(cartas?\\s+|oros\\s+y/o\\s+aliados\\s+)?(?:de\\s+ah[ií]\\s+)?en\\s+tu\\s+mano").search(rest)
	if m:
		var n_hand: int = UniversalCardParser._parse_amount(m.get_string(2))
		var hand_box := {"key": "hand", "label": "A tu mano", "dest": "hand",
			"min": 0 if not m.get_string(1).is_empty() else n_hand, "max": n_hand}
		if "oros" in m.get_string(3):
			hand_box["filter"] = func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ORO, Constants.CardType.ALIADO]
		boxes.append(hand_box)
		rest = _cut(rest, m)
	# "pon una en tu mano y otra en tu Cementerio o Destierro" (Relicario de San Pancracio): se elige la
	# carta en la ventana y después el destino.
	m = _rx("(?:otra|la\\s+otra)\\s+en\\s+tu\\s+cementerio\\s+o\\s+destierro").search(rest)
	if m:
		boxes.append({"key": "cem_or_exile", "label": "A tu Cementerio o Destierro", "dest": "custom", "min": 1, "max": 1})
		rest = _cut(rest, m)
	# "y Destierra dos cartas de ahí" (negar la luz), "y Desterrar una de ellas" (Relicario).
	m = _rx("(?:destierra|desterrar)\\s+" + _NUM + "\\s+(?:cartas?\\s+)?de\\s+(?:ah[ií]|ellas)").search(rest)
	if m:
		var n_banish: int = UniversalCardParser._parse_amount(m.get_string(1))
		boxes.append({"key": "exile_n", "label": "Al Destierro", "dest": "exile", "min": n_banish, "max": n_banish})
		rest = _cut(rest, m)
	for spec in [["cemetery", "A tu Cementerio", "cementerio"], ["exile", "A tu Destierro", "destierro"]]:
		var n_zone := 1
		m = _rx("(?:pon|poner)\\s+" + _NUM + "\\s+(?:cartas?\\s+)?(?:de\\s+ah[ií]\\s+)?en\\s+(?:tu|el|su)\\s+" + spec[2]).search(rest)
		if m:
			n_zone = UniversalCardParser._parse_amount(m.get_string(1))
		else:
			m = _rx("(?:otra|la\\s+otra)\\s+(?:en|a)\\s+tu\\s+" + spec[2]).search(rest)
		if m:
			boxes.append({"key": spec[0], "label": spec[1], "dest": spec[0], "min": n_zone, "max": n_zone})
			rest = _cut(rest, m)
	m = _rx("otra\\s+en\\s+el\\s+fondo\\s+de\\s+tu\\s+castillo").search(rest)
	if m:
		boxes.append({"key": "bottom1", "label": "Al fondo de tu Castillo", "dest": "bottom", "min": 1, "max": 1})
		rest = _cut(rest, m)
	for spec in [["el\\s+resto\\s+en\\s+tu\\s+cementerio", "cemetery"], ["el\\s+resto\\s+en\\s+tu\\s+mano", "hand"],
			["(?:baraja|barajar)\\s+(?:el\\s+resto|la\\s+otra|las\\s+demás)", "shuffle"],
			["ordena\\s+el\\s+resto|ordénalas|ordenalas|regresa\\s+el\\s+resto\\s+en\\s+cualquier\\s+orden", "same"]]:
		m = _rx(spec[0]).search(rest)
		if m:
			if rest_dest == "same":
				rest_dest = spec[1]
			rest = _cut(rest, m)
	m = _rx("roba\\s+" + _NUM + "\\s+cartas?").search(rest)
	if m:
		draw_after = UniversalCardParser._parse_amount(m.get_string(1))
		rest = _cut(rest, m)
	var leftover: String = _rx("\\b(y|de|ahí|ahi|cartas?)\\b").sub(rest, "", true)
	if not _rx("[^a-záéíóúñ]").sub(leftover, "", true).is_empty():
		return false  # hay algo más que no entiendo: lo resuelve la cadena vieja
	if dry_run:
		return true

	var card_name: String = str(card.get("card_name")) if is_instance_valid(card) and card.get("card_name") != null else "Mirar"
	# "Cuando entra en juego, puedes mirar..." es opcional (en una habilidad
	# activada, el botón ya es la confirmación).
	if "puedes mira" in lower and (lower.begins_with("cuando") or lower.begins_with("al comienzo")):
		if not await SelectionManager.await_two_choice(main, card_name, "Mirar", "No mirar", controller_id):
			return true
	var deck_owner: int = controller_id
	if look.get_string(4) == "un":
		var own: bool = await SelectionManager.await_castillo_pick(main, "%s: ¿qué Castillo miras?" % card_name, controller_id)
		deck_owner = controller_id if own else 1 - controller_id

	match rest_dest:
		"both":
			boxes = rest_box(from_top, true) + boxes
		"same":
			boxes = rest_box(from_top) + boxes
		"shuffle":
			boxes = [{"key": "rest", "label": "Se barajan en el Castillo", "dest": "shuffle", "start": true}] + boxes
		"cemetery":
			boxes = [{"key": "rest", "label": "El resto a tu Cementerio", "dest": "cemetery", "start": true}] + boxes
		"hand":
			boxes = [{"key": "rest", "label": "El resto a tu mano", "dest": "hand", "start": true}] + boxes
	var title := "%s: mira %d carta(s) del %s" % [card_name, count, "tope" if from_top else "fondo"]
	var result: Dictionary = await look(controller_id, deck_owner, count, from_top, boxes, title)
	for d in result.get("cem_or_exile", []):
		var to_exile := false
		if not PlayerSideScript.is_bot(controller_id) \
				and not load("res://scripts/core/effects/mechanics/ProtectionRules.gd").castle_banish_blocked(deck_owner, controller_id):
			to_exile = await SelectionManager.await_choice(main, "%s: ¿a tu Cementerio o a tu Destierro?" % card_name,
				["Cementerio", "Destierro"], controller_id) == 1
		if to_exile:
			CardManager.add_to_exile(deck_owner, d)
		else:
			CardManager.add_to_cemetery(deck_owner, d)
	if draw_after > 0:
		await ActionModule.draw(controller_id, draw_after, card_name, true)
	return true


static func _look_count(main: Node, look: RegExMatch, controller_id: int) -> int:
	for g in [1, 2]:
		var s: String = look.get_string(g)
		if not s.is_empty() and s != "tantas":
			return UniversalCardParser._parse_amount(s)
	var basis: String = look.get_string(5)
	match basis:
		"oros controles":
			return (main.player_gold if controller_id == 0 else main.opponent_gold).get_child_count() \
				+ (main.player_oro_pagado if controller_id == 0 else main.opponent_oro_pagado).get_child_count()
		"aliados controles", "aliados controles más una":
			var allies := 0
			for c in PlayerSideScript.ally_containers(main, controller_id):
				for a in c.get_children():
					if a.get("card_type") == Constants.CardType.ALIADO:
						allies += 1
			return allies + (1 if basis.ends_with("más una") else 0)
		"armas controles", "armas y tótem controles":
			var n := 0
			for c in PlayerSideScript.line_containers(main, controller_id):
				for x in c.get_children():
					if x.get("card_type") == Constants.CardType.TOTEM and basis.contains("tótem"):
						n += 1
					var weapons = x.get("equipped_weapons")
					if weapons is Array:
						n += weapons.size()
			return n
		"tótem hay en juego":
			var t := 0
			for pid in [0, 1]:
				for c in PlayerSideScript.line_containers(main, pid):
					for x in c.get_children():
						if x.get("card_type") == Constants.CardType.TOTEM:
							t += 1
			return t
		"aliados haya en tu destierro":
			return CardManager.get_exile(controller_id).filter(
				func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO).size()
	return -1
