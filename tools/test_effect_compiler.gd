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
	# --- Deben rechazarse (que siga la cadena vieja) ---
	["Cuando entra en juego, tu oponente convierte una carta que controle que no sea Oro en un Tótem "
		+ "sin habilidad y tú ganas su control.",
		"FAIL"],
	["Cuando entra en juego, Destierra hasta dos cartas de los Cementerios.",
		"FAIL"],
	["Cuando entra en juego, Roba una carta y Baraja una carta oponente de coste igual o menor a la "
		+ "cantidad de Aliados que controles.",
		"FAIL"],
	["Cuando entra en juego, busca un Aliado y ponlo en tu mano.",
		"FAIL"],
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
