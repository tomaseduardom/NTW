extends "res://scripts/core/effects/compiler/EffectInterpreterBase.gd"
## EffectInterpreterAuxiliares — familia Auxiliares de EffectInterpreter.gd (ver EffectInterpreterBase.gd).


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
					"shuffle_hand": "Barajar %d de tu mano" % st.amount,
					"banish_hand": "Desterrar %d de tu mano" % st.amount,
					"sacrifice_any": "%s %d que controles" % [{"destroy": "Destruir", "banish": "Desterrar",
						"shuffle": "Barajar"}.get(str(st.get("verb", "")), ""), st.amount]}.get(st.kind, st.kind))
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
					"bearer": "la Fuerza del portador", "opp_hand_allies": "Aliados en la mano rival",
					"own_allies_count": "Aliados que controles"}.get(st.src, "")])
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
