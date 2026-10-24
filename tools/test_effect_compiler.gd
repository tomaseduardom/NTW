extends SceneTree
## Tests headless de EffectCompiler (2026-10-12, ver arquitectura.md §54).
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . -s tools/test_effect_compiler.gd
## Sale con código 1 si algún caso falla.
##
## Cada caso: [texto, resumen esperado]. El resumen es compacto a propósito
## (ver _summary()); "FAIL" = el compilador debe rechazar el texto (ok=false)
## para que siga resolviendo la cadena de patrones vieja.

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")

const CASES := [
	# --- Cartas nuevas de Drácula (2026-10-12) ---
	["Cuando entra en juego, Roba una carta y Baraja hasta una carta de tu mano. "
		+ "Los Aliados oponentes pierden 1 de Fuerza y deben atacar si pueden.",
		"draw(1) shuffle_from_hand(1,hasta)"],
	["Cuando entra en juego, Roba dos cartas y Descarta una carta, o busca un Arma en tu Castillo y ponla en tu mano.",
		"choice[draw(2) discard(self,1) | search(castillo,arma,1)]"],
	["Cuando entra en juego o ataque, puedes buscar en tu Castillo o Cementerio un Arma y ponerla en tu mano.",
		"? search(castillo+cementerio,arma,1)"],
	["Cuando hace daño al Castillo oponente, Descarta una carta de la mano de tu oponente al azar.",
		"discard(opponent,1,azar)"],
	["Destruye un Aliado oponente de Fuerza 2 o menos. Luego, Roba una carta.",
		"target(destroy,1,aliado,opponent,fuerza<=2) then:draw(1)"],
	["Cuando entra en juego, Baraja un Aliado oponente en juego.",
		"target(shuffle,1,aliado,opponent)"],
	["Cuando entra en juego, Destruye un Aliado oponente en juego.",
		"target(destroy,1,aliado,opponent)"],
	["Cuando entra en juego, Destruye todos los Aliados en juego de Fuerza 2 o menos.",
		"mass(destroy,aliado,any,fuerza<=2)"],
	["Destruye una carta en juego que no sea un Oro.",
		"target(destroy,1,*,any,sin_oro)"],
	["Sube una carta oponente en juego que no sea Oro a la Mano de su dueño.",
		"target(bounce,1,*,opponent,sin_oro)"],
	["Cuando entra en juego, puedes buscar un Oro en tu Castillo y ponerlo en tu Mano.",
		"? search(castillo,oro,1)"],
	["El portador gana 1 de Fuerza. Cuando entra en juego, Roba dos cartas de tu Castillo.",
		"FAIL"],
	["Cuando entra en juego, Roba dos cartas de tu Castillo.",
		"draw(2)"],
	["Cuando entra en juego, puedes Robar una carta.",
		"? draw(1)"],
	["Cuando entra o sale del juego, Roba dos cartas y tu oponente Bota tres cartas.",
		"draw(2) mill(opponent,3)"],
	# --- Piezas agregadas en la misma sesión (2026-10-12) ---
	["Exhumar. Cuando lo juegues, Destiérralo. Los Tótem de coste 2 o menos pierden su habilidad y son Destruidos.",
		"mass(destroy,totem,any,coste<=2)+silencio"],
	["Cuando entra en juego, un Aliado oponente pierde su habilidad y es Destruido.",
		"target(destroy,1,aliado,opponent,sin_oro)+silencio"],
	["En tu Vigilia, una vez por turno, Destruye un Aliado oponente de coste 2 o menos. "
		+ "Si tiene Exhumar, en vez de eso, Destiérralo.",
		"target(destroy,1,aliado,opponent,coste<=2)+si_exhumar:banish"],
	["En Guerra de Talismanes, una vez por turno, tu oponente Bota una carta por cada Aliado en tu Línea de Defensa.",
		"mill(opponent,1,x own_allies_defense)"],
	["Cuando entra en juego, puedes Barajar dos cartas de tu Cementerio en tu Castillo.",
		"? shuffle_from_cemetery(2)"],
	["En tu Fase Final, si no fue declarado atacante este turno, destrúyelo.",
		"if(not_attacked_this_turn)[self(destroy)]"],
	["Cuando entra en juego, Destierra hasta dos cartas de los Cementerios.",
		"cemetery_cleanup"],
	# --- Fuerza para todos los Aliados de un lado y pérdida de habilidad ---
	["Cuando entra o salga del juego, tus Aliados ganan 2 de Fuerza permanentemente.",
		"mass_buff(own,+2,perm)"],
	["Cuando ataca, tus demás Aliados ganan 1 de Fuerza e Indestructible por el turno.",
		"mass_buff(own,demas,+1,turno,indestructible)"],
	["Cuando ataca tus Aliados ganan 1 de Fuerza.",
		"mass_buff(own,+1,-)"],
	["Cuando entra en juego, si controlas Armas tus Aliados ganan 2 de Fuerza por el turno.",
		"if({ \"kind\": \"controls\", \"count\": 1, \"type\": \"arma\", \"race\": \"\", \"other\": false, \"min_strength\": -1, \"attack_line\": false })[mass_buff(own,+2,turno)]"],
	["Una vez por turno, los Aliados oponentes pierden 1 de Fuerza permanentemente y una carta pierda su habilidad por el turno.",
		"mass_buff(opponent,-1,perm) target(silence,1,*,any)[turn]"],
	["Cuando entra en juego, una carta de coste 2 o menos pierde su habilidad.",
		"target(silence,1,*,any,coste<=2)[permanent]"],
	["Cuando entra en juego, una carta pierde su habilidad hasta tu próximo turno.",
		"FAIL"],
	["Los Aliados oponentes pierden Furia.",
		"FAIL"],
	# --- Deben rechazarse (que siga la cadena vieja) ---
	["Cuando entra en juego, tu oponente convierte una carta que controle que no sea Oro en un Tótem "
		+ "sin habilidad y tú ganas su control.",
		"FAIL"],
	["Cuando entra en juego, Roba una carta y Baraja una carta oponente de coste igual o menor a la "
		+ "cantidad de Aliados que controles.",
		"FAIL"],
	["Cuando entra en juego, busca un Aliado y ponlo en tu mano.",
		"FAIL"],
	# --- "A o B" sin coma, Anular, Talismán sin efecto, elegir qué gana (2026-10-21) ---
	["Baraja una carta de coste 3 o menos o Anula un Talismán oponente.",
		"choice[target(shuffle,1,*,any,coste<=3) | annul(anula un talismán oponente)]"],
	["En tu Vigilia, una vez por turno, puedes Destruir una carta de coste 2 o menos o hacer que el próximo "
		+ "Talismán que juegue tu oponente este turno se resuelva sin efecto.",
		"? choice[target(destroy,1,*,any,coste<=2) | talisman_fizzle]"],
	["Una vez por turno, un Aliado gana Indestructible, Indesterrable o \"No puede ser Barajado\", hasta tu próximo turno.",
		"choice[buff(indestructible,hasta_prox) | buff(indesterrable,hasta_prox) | buff(no_barajar,hasta_prox)]"],
	["Cuando entra en juego, puedes robar dos cartas o tu oponente bota tres cartas.",
		"? choice[draw(2) | mill(opponent,3)]"],
	["Anula una carta de coste 1 o menos o mira la mano de tu oponente y Descarta una carta de coste 1 o menos de ahí.",
		"choice[annul(anula una carta de coste 1 o menos) | hand_peek]"],
	# La "o" de "3 o menos" no parte nada.
	["Destruye una carta de coste 3 o menos.",
		"target(destroy,1,*,any,coste<=3)"],
	# Efecto antes de mirar el Castillo: lo de "mira" lo ejecuta CastleLook (paso castle_look).
	["Cuando entra en juego, Destierra hasta una carta de coste 2 o menos y mira las primeras cuatro cartas de tu Castillo. Pon dos en tu Destierro y el resto en tu mano.\nLas cartas de coste 0 pierden su habilidad y cuestan un Oro adicional.",
		"target(banish,hasta 1,*,any,coste<=2) castle_look"],
	["En tu Fase Final, Destierra hasta dos cartas de un Cementerio, mira tantas cartas del tope de tu Castillo como Aliados controles y ordénalas.",
		"cemetery_cleanup castle_look"],
	# Disparador sin coma.
	["Cuando entra en juego baraja hasta cuatro cartas de los Cementerios y roba una carta.",
		"cemetery_cleanup draw(1)"],
	# Búsquedas con raza, varias cartas y "y jugarlo".
	["Cuando entra en juego, puedes buscar un Aliado, un Talismán y un Tótem en tu Castillo y ponerlos en tu mano.",
		"? search(castillo,aliado,1) search(castillo,talisman,1) search(castillo,totem,1)"],
	["Cuando entra en juego, puedes buscar en tu Castillo un Aliado Dragón de coste 3 o más y jugarlo reduciendo su coste en un Oro.",
		"? search(castillo,*,1)"],
	["Cuando entra en juego, puedes subir hasta un Aliado y un Arma de tu Cementerio a tu mano.",
		"? search(cementerio,aliado,1,hasta) search(cementerio,arma,1,hasta)"],
	["Cuando entra en juego, pon un Oro de tu mano o Cementerio en tu Oro Pagado.", "gold_to_paid"],
	["Cuando entra en juego, pon dos cartas del fondo de tu Castillo en tu mano.", "deck_to_hand"],
	["Cuando entra en juego, no recibes daño de combate hasta tu próximo turno.", "no_damage"],
	# Costes de las activadas antes de "para (que)".
	["Puedes Descartarlo para que un Aliado de Fuerza 3 o menos gane 2 de Fuerza este turno.",
		"? cost(self_discard) buff(+2)"],
	["Puedes Desterrarlo de tu Cementerio y pagar un Oro para subir hasta dos cartas que no sean Talismán de tu Cementerio a tu mano.",
		"? cost(self_banish) pay(1) search(cementerio,*,2,hasta)"],
	["Una vez por turno, puedes Descartar un Oro o Talismán para Robar una carta.", "? cost(discard,1) draw(1)"],
	["En tu Vigilia, una vez por turno, puedes Botar dos cartas para que tu oponente Bote tres cartas.",
		"? cost(mill,2) mill(opponent,3)"],
	["Una vez en tu turno, puedes mostrar un Aliado de tu mano para que tu oponente Bote tres cartas.",
		"? cost(reveal) mill(opponent,3)"],
	["Puedes pagarlo y convertirlo en un Oro sin habilidad para robar dos cartas.",
		"? cost(self_pay) cost(self_convert) draw(2)"],
	["Puedes Desterrarlo para Anular un Talismán o Tótem de coste 2 o menos.",
		"? cost(self_banish) annul(anula un talismán o tótem de coste 2 o menos)"],
	["Una vez por turno, puedes hacer que un Aliado gane o pierda 2 de Fuerza por el turno.",
		"? choice[buff(+2) | buff(-2)]"],
	["Una vez por turno, tu oponente Destierra dos cartas del tope de su Castillo y tu oponente Descarta una carta de su mano.",
		"castle_exile discard(opponent,1)"],
	["Una vez por turno, un Aliado de coste 2 o menos tiene Fuerza 0 hasta tu próximo turno.", "buff(=0,hasta_prox)"],
	["Una vez por turno, un Aliado tiene Fuerza 0 o duplica su Fuerza por el turno.", "choice[buff(=0) | buff(x2)]"],
	["Puedes Desterrarlo de tu Cementerio para cancelar el ataque de un Aliado oponente.", "? cost(self_banish) cancel_attack"],
	["En tu Vigilia, una vez por turno, puedes hacer que un Aliado haga el doble de daño este turno.", "? buff(doble_dano)"],
	["Una vez en tu turno, un Aliado Bandido gana Imbloqueable y hace daño al Destierro este turno.", "buff(imbloqueable,bandido)"],
	# Otra habilidad activada pegada a un Talismán: corta el bloque.
	["Destruye un Aliado oponente. Puedes Desterrarlo de tu Cementerio y pagar un Oro para robar una carta.",
		"target(destroy,1,aliado,opponent)"],
	# Sin efecto previo no se compila: lo resuelve CastleLook solo.
	["Cuando entra en juego, mira las primeras tres cartas de tu Castillo y ordénalas.", "FAIL"],
]


func _init() -> void:
	var failed := 0
	for case in CASES:
		var plan: Dictionary = EffectCompilerScript.compile_clause(case[0])
		var got := _summary(plan)
		if got != case[1]:
			failed += 1
			print("FALLA: %s\n   esperado: %s\n   obtenido: %s  (resto: '%s')" % [case[0], case[1], got, plan.unparsed])
	print("EffectCompiler: %d/%d casos OK" % [CASES.size() - failed, CASES.size()])
	quit(1 if failed > 0 else 0)


static func _summary(plan: Dictionary) -> String:
	if not plan.ok:
		return "FAIL"
	var parts: Array = []
	for st in plan.steps:
		parts.append(_step_summary(st))
	return ("? " if plan.optional else "") + " ".join(parts)


static func _step_summary(st: Dictionary) -> String:
	var s := ""
	match st.op:
		"draw":
			s = "draw(%d)" % st.amount
		"mill":
			s = "mill(%s,%d%s)" % [st.who, st.amount, (",x " + st.per) if st.get("per", "") != "" else ""]
		"shuffle_from_cemetery":
			s = "shuffle_from_cemetery(%d%s)" % [st.amount, ",hasta" if st.up_to else ""]
		"self":
			s = "self(%s)" % st.verb
		"if":
			var inner: Array = []
			for sub in st.steps:
				inner.append(_step_summary(sub))
			s = "if(%s)[%s]" % [st.cond, " ".join(inner)]
		"discard":
			s = "discard(%s,%d%s)" % [st.who, st.amount, ",azar" if st.random else ""]
		"shuffle_from_hand":
			s = "shuffle_from_hand(%d%s)" % [st.amount, ",hasta" if st.up_to else ""]
		"search":
			s = "search(%s,%s,%d%s)" % ["+".join(st.zones), st.card_type if st.card_type != "" else "*", st.amount,
				",hasta" if st.up_to else ""]
		"target", "mass":
			var t: Dictionary = st.target
			var bits: Array = [st.verb]
			if st.op == "target":
				bits.append(("hasta " if st.up_to else "") + str(st.count))
			bits.append("+".join(t.card_types) if not t.card_types.is_empty() else "*")
			bits.append(t.controller)
			if t.stat != "":
				bits.append("%s%s%d" % [t.stat, t.cmp, t.value])
			if t.exclude_gold and st.op == "target":
				bits.append("sin_oro")
			s = "%s(%s)" % [st.op, ",".join(bits)]
			if st.get("silence_first", false):
				s += "+silencio"
			if st.has("replace_if_keyword"):
				s += "+si_%s:%s" % [st.replace_if_keyword.keyword, st.replace_if_keyword.verb]
			if st.verb == "silence":
				s += "[%s]" % st.duration
		"mass_buff":
			var mb: Array = [st.side]
			if st.others:
				mb.append("demas")
			mb.append("%+d" % st.amount)
			mb.append("perm" if st.permanent else ("turno" if st.turn_only else "-"))
			mb.append_array(st.keywords)
			s = "mass_buff(%s)" % ",".join(mb)
		"annul":
			s = "annul(%s)" % st.text
		"buff":
			var gains: Array = st.keywords.duplicate()
			if st.get("no_shuffle", false):
				gains.append("no_barajar")
			if int(st.amount) != 0:
				gains.append("%+d" % st.amount)
			if st.has("set_strength"):
				gains.append("=%d" % st.set_strength)
			if st.get("double", false):
				gains.append("x2")
			if st.get("double_damage", false):
				gains.append("doble_dano")
			if st.get("no_damage", false):
				gains.append("sin_dano")
			if st.target.has("race"):
				gains.append(st.target.race)
			if st.get("duration", "") == "until_next_turn":
				gains.append("hasta_prox")
			s = "buff(%s)" % ",".join(gains)
		"cost":
			s = "cost(%s%s)" % [st.kind, (",%d" % st.amount) if st.kind in ["discard", "mill"] else ""]
		"pay":
			s = "pay(%d)" % st.amount
		"choice":
			var opts: Array = []
			for o in st.options:
				var ps: Array = []
				for sub in o:
					ps.append(_step_summary(sub))
				opts.append(" ".join(ps))
			s = "choice[%s]" % " | ".join(opts)
		_:
			s = st.op
	return ("then:" if st.get("then", false) else "") + s
