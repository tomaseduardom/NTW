extends RefCounted
class_name EffectCompiler
## EffectCompiler — compila el texto de UNA habilidad (disparada, activada o
## Talismán) a un plan de pasos atómicos (2026-10-12, "paso B" acordado con
## el usuario, ver arquitectura.md §54).
##
## Por qué existe: hasta aquí cada carta nueva se resolvía con su propia
## función try_execute_*_pattern() (252 en el proyecto, 144 encadenadas en
## TriggerResolution, gana la primera que matchea sobre el texto completo).
## Este compilador arma el efecto con piezas reutilizables: una carta nueva
## casi siempre es una combinación de piezas que ya existen, o una pieza
## nueva que sirve para muchas cartas.
##
## Regla de oro: el plan solo es válido (ok = true) si se entendió TODO el
## texto del efecto. Si queda cualquier resto sin entender, ok = false y el
## llamador sigue con la cadena de patrones vieja — nunca se ejecuta un
## efecto a medias.
##
## Clase pura: no usa autoloads ni nodos (los tipos y zonas van como texto,
## EffectInterpreter los traduce a Constants) — así se prueba headless con
## tools/test_effect_compiler.gd y se audita el catálogo completo con
## tools/audit_cards.gd.
##
## Plan: {ok, optional, activated, steps: [paso], unparsed: String}
## activated = el texto traía momento/frecuencia de habilidad ACTIVADA ("En
## tu Vigilia, una vez por turno, ..."): el clic en su botón ya fue la
## confirmación del "puedes".
## Pasos (todos llevan además "then": true si van después de "Luego," — solo
## corren si el paso anterior se resolvió por completo, DAR):
##   {op: "draw", amount}                            — Roba N cartas
##   {op: "mill", who: "self"|"opponent", amount}    — Bota N cartas
##   {op: "discard", who, amount, random}            — Descarta N cartas
##   {op: "shuffle_from_hand", amount, up_to}        — Baraja N cartas de tu mano
##   {op: "search", zones, card_type, amount, up_to} — Busca ... y ponla en tu mano
##   {op: "target", verb, count, up_to, target}      — Destruye/Destierra/Baraja/Sube N cartas en juego
##   {op: "mass", verb, target}                      — Destruye todos los Aliados ...
##   {op: "choice", options: [[pasos], [pasos]]}     — "A, o B"
##   {op: "shuffle_from_cemetery", amount, up_to}    — Baraja N cartas de tu Cementerio en tu Castillo
##   {op: "self", verb}                              — Destrúyelo / Destiérralo (la propia carta)
##   {op: "if", cond, steps}                         — "si no fue declarado atacante este turno, ..."
## Extras de "target"/"mass": silence_first (pierde su habilidad y es
## Destruido), replace_if_keyword: {keyword, verb} ("Si tiene Exhumar, en
## vez de eso, Destiérralo"). Extra de "mill": per (Bota una carta por cada
## Aliado en tu Línea de Defensa / Tótem en juego / ...).
## verb: "destroy" | "banish" | "shuffle" | "bounce"
## target: {card_types: ["aliado", ...] (vacío = cualquier tipo en juego),
##          controller: "any"|"opponent", exclude_gold, stat: ""|"fuerza"|"coste",
##          cmp: "<="|">=", value}
## card_type / card_types usan: "aliado", "arma", "totem", "talisman", "oro"
## ("" = cualquier carta). zones: "castillo", "cementerio".

const NUMBER_WORDS := {
	"un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
	"seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
}
const NUM := "(?:\\d+|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)"

## Prefijos de disparador que se quitan antes de compilar — el disparador
## en sí ya lo decidió quien llama (Card.TRIGGER_KEYWORDS/TriggerResolution).
## Los más largos primero.
const TRIGGER_PREFIXES := [
	"cuando entra en juego o ataca", "cuando entra en juego o ataque", "cuando entra o sale del juego",
	"cuando entra o salga del juego", "cuando entra en juego", "cuando entre en juego", "al entrar en juego",
	"cuando ataca", "cuando ataque", "al atacar", "cuando bloquea", "cuando bloquee", "cuando lo juegues",
	"cuando salga del juego", "cuando sale del juego", "al salir del juego",
	"cuando hace dano al castillo oponente", "cuando haga dano al castillo oponente",
	"cuando haga dano de combate", "cuando haga dano",
	"en tu fase final", "al comienzo de tu vigilia", "al comienzo de la vigilia", "al comienzo del turno",
]

## Momento/frecuencia de las habilidades ACTIVADAS — lo controla
## ActionPipeline (once_per_turn, ventana), no es parte del efecto.
const TIMING_PREFIXES := [
	"en tu vigilia", "en guerra de talismanes", "una vez por turno", "una vez al turno", "una vez en tu turno",
]

## Oraciones al INICIO del texto que no son parte del efecto: keywords y
## "Cuando lo juegues, Destiérralo" de los Talismanes (eso lo aplica
## GoldManager._play_talisman() al mandar el Talismán al Destierro).
const LEADING_SKIP_RX := "^(?:(?:furia|imbloqueable|indestructible|indesterrable|unica|exhumar|errante|retador" \
	+ "|oro inicial)[ ,y]*)+$|^cuando lo juegues, (?:destierralo|destierrala)$"

## Condiciones al comienzo de una oración ("si X, efecto").
const CONDITIONS := [
	["not_attacked_this_turn", "si no fue declarado atacante este turno, "],
]

## Reemplazo sobre el paso anterior: "Si tiene Exhumar, en vez de eso, Destiérralo".
const REPLACE_RX := "^si tiene (?<kw>exhumar|furia|indestructible|imbloqueable|indesterrable|unica), en vez de eso, " \
	+ "(?<v>destierralo|destierrala|destruyelo|destruyela)$"

## Oraciones que son reglas estáticas (auras, keywords, permisos) — no son
## parte del efecto de esta habilidad: el compilador corta el bloque ahí
## (TriggerResolution._isolate_all_trigger_clauses() a veces las pega al
## final del bloque de un disparador).
const STATIC_STARTS := [
	"el portador", "los aliados", "tus aliados", "los totem", "las armas", "los talismanes",
	"puede atacar", "puedes jugar", "no puede", "no pueden", "mientras", "furia", "imbloqueable",
	"indestructible", "indesterrable", "unica", "exhumar", "errante", "retador", "oro inicial",
	"reduce su coste", "tu oponente no puede", "a tu oponente le cuesta",
	# Otra habilidad condicional de la misma carta (p.ej. Draig Ifang: "Si este
	# Aliado es Destruido o Barajado desde el juego...") — no es continuación.
	"si este aliado", "si esta carta", "si este totem", "si esta arma", "si es anulado",
]

const TYPE_WORDS := {
	"aliado": "aliado", "aliados": "aliado", "arma": "arma", "armas": "arma",
	"totem": "totem", "totems": "totem", "talisman": "talisman", "talismanes": "talisman",
	"oro": "oro", "oros": "oro", "carta": "", "cartas": "",
}

## Frase de objetivo en juego — usada por los verbos destruir/desterrar/
## barajar/subir. Grupos con nombre (PCRE2).
const TARGET_RX := "(?<det>(?:hasta )?" + NUM + ") (?<kind>aliados?|cartas?|totems?|armas?)" \
	+ "(?<opp> oponentes?)?(?: en juego)?(?<nogold> que no sean? (?:un )?oro)?" \
	+ "(?: de (?<stat>fuerza|coste) (?<val>\\d+) o (?<cmp>menos|mas))?"

## Átomos en orden de prioridad (los más específicos primero: p.ej.
## 'descarta... de la mano de tu oponente al azar' antes que 'descarta N
## cartas'). Cada uno se ancla al inicio del texto restante.
const ATOMS := [
	["draw", "(?:tu )?roba(?:s|r)? (?<upto>hasta )?(?<n>" + NUM + ") cartas?(?: de tu castillo)?"],
	["mill_per", "tu oponente bota (?<n>" + NUM + ") cartas? por cada (?<per>aliado en tu linea de defensa" \
		+ "|aliado que controles|totem en juego|totem que controles)"],
	["mill_opp", "tu oponente bota (?<n>" + NUM + ") cartas?"],
	["mill_self", "bota(?:s|r)? (?<n>" + NUM + ") cartas?"],
	["discard_opp_random", "descarta(?:r)? (?<n>" + NUM + ") cartas? de la mano de tu oponente al azar"],
	["discard_self", "descarta(?:s|r)? (?<n>" + NUM + ") cartas?(?! de la mano)"],
	["shuffle_from_hand", "baraja(?:r)? (?<upto>hasta )?(?<n>" + NUM + ") cartas? de tu mano(?: en tu castillo)?"],
	["shuffle_from_cemetery", "baraja(?:r)? (?<upto>hasta )?(?<n>" + NUM + ") cartas? de tu cementerio en tu castillo"],
	["search", "busca(?:r)? (?:en tu (?<z1>castillo|cementerio)(?: o (?:tu )?(?<z2>castillo|cementerio))? )?" \
		+ "(?<det>(?:hasta )?" + NUM + ") (?<type>aliados?|armas?|totems?|talisman(?:es)?|oros?|cartas?)" \
		+ "(?: en tu (?<z3>castillo|cementerio)(?: o (?:tu )?(?<z4>castillo|cementerio))?)?" \
		+ ",? y (?:ponla|ponlo|ponerla|ponerlo|ponlas|ponlos|ponerlas|ponerlos) en tu mano"],
	["mass", "(?<verb>destruye|destierra) todos los (?<kind>aliados|totems|armas)(?<opp> oponentes)?(?: en juego)?" \
		+ "(?: de (?<stat>fuerza|coste) (?<val>\\d+) o (?<cmp>menos|mas))?"],
	["bounce", "sub(?:e|ir) " + TARGET_RX + " a la mano de su dueno"],
	# "Un Aliado oponente pierde su habilidad y es Destruido" (Guardia Gozosa)
	# / "Los Tótem de coste 2 o menos pierden su habilidad y son Destruidos"
	# (Destruir Refugio) — pierde la habilidad ANTES, así no dispara su
	# "cuando salga del juego".
	["target_silence", "(?<det>un|una) (?<kind>aliado|carta|totem|arma)(?<opp> oponente)?(?: en juego)?" \
		+ " pierde su habilidad y es (?<v>destruid[oa]|desterrad[oa])"],
	["mass_silence", "(?:los|las) (?<kind>totems?|aliados|armas)(?<opp> oponentes)?(?: en juego)?" \
		+ "(?: de (?<stat>fuerza|coste) (?<val>\\d+) o (?<cmp>menos|mas))? pierden su habilidad y son" \
		+ " (?<v>destruid[oa]s|desterrad[oa]s)"],
	["self", "(?<v>destruyelo|destruyela|destierralo|destierrala)"],
	# Barajar/Desterrar sin zona explícita = en juego (regla del usuario
	# 2026-08-30, ver DSR_ShuffleDrawCombos.try_execute_draw_and_shuffle_
	# opponent_card_pattern()) — por eso se rechaza si sigue 'de tu/los...'.
	["target", "(?<verb>destruye|destruir|destierra|desterrar|baraja|barajar) " + TARGET_RX + "(?! de (?:tu|los|un|su) )"],
]

## Piezas que EffectInterpreter sabe ejecutar HOY. Viven aquí (y no en el
## intérprete) para que el auditor headless las consulte sin cargar
## autoloads. El compilador puede entender más de lo que se ejecuta (p.ej.
## "bounce"): esos planes se dejan a la cadena de patrones vieja.
const EXECUTABLE_OPS := ["draw", "mill", "discard", "shuffle_from_hand", "search", "target", "mass", "choice",
	"shuffle_from_cemetery", "self", "if"]
const EXECUTABLE_VERBS := ["destroy", "banish", "shuffle"]

static var _compiled_atoms: Array = []
static var _connector_rx: RegEx = null


static func compile_clause(text: String) -> Dictionary:
	"""Compila el bloque de texto de una habilidad. Ver el docstring de la
	clase para el formato del plan."""
	var plan := {"ok": false, "optional": false, "activated": false, "steps": [], "unparsed": ""}
	var norm := normalize(text)
	if norm.is_empty():
		plan.unparsed = "(vacío)"
		return plan

	var steps: Array = []
	var sentences := _split_sentences(norm)
	var skip_rx := RegEx.new()
	skip_rx.compile(LEADING_SKIP_RX)
	while not sentences.is_empty() and skip_rx.search(sentences[0]) != null:
		sentences.remove_at(0)
	var replace_rx := RegEx.new()
	replace_rx.compile(REPLACE_RX)
	for i in range(sentences.size()):
		var s: String = sentences[i]
		var then := false
		if i == 0:
			var stripped := _strip_trigger_prefix(s)
			plan.activated = _had_timing_prefix(s)
			s = stripped
		else:
			var rm := replace_rx.search(s)
			if rm:
				# Modifica el paso anterior (debe ser un objetivo en juego).
				if steps.is_empty() or steps[-1].op not in ["target", "mass"]:
					plan.unparsed = s
					return plan
				var v: String = rm.get_string("v")
				steps[-1]["replace_if_keyword"] = {"keyword": rm.get_string("kw"),
					"verb": "banish" if v.begins_with("destierr") else "destroy"}
				continue
			if _is_static(s):
				break  # el resto es texto estático pegado al bloque
			if s.begins_with("luego"):
				s = s.trim_prefix("luego").trim_prefix(",").strip_edges()
				then = true
		if s.begins_with("puedes "):
			s = s.substr(7)
			if i == 0:
				plan.optional = true
		var sub := _compile_sentence(s)
		if not sub.ok:
			plan.unparsed = sub.unparsed
			return plan
		if then and not sub.steps.is_empty():
			sub.steps[0]["then"] = true
		steps.append_array(sub.steps)

	plan.steps = steps
	plan.ok = not steps.is_empty()
	if not plan.ok:
		plan.unparsed = norm
	return plan


static func is_executable(steps: Array) -> bool:
	"""true si EffectInterpreter sabe ejecutar todos los pasos (ver
	EXECUTABLE_OPS/EXECUTABLE_VERBS)."""
	for st in steps:
		if st.op not in EXECUTABLE_OPS:
			return false
		if st.op in ["target", "mass"] and st.verb not in EXECUTABLE_VERBS:
			return false
		if st.op == "choice":
			for option in st.options:
				if not is_executable(option):
					return false
		if st.op == "if" and not is_executable(st.steps):
			return false
	return true


static func normalize(text: String) -> String:
	"""Minúsculas, sin tildes ni ñ, espacios colapsados, sin punto
	final. Los saltos de línea de la API valen como fin de oración."""
	var t := text.to_lower().replace("\r", "").replace("\n", ". ")
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		t = t.replace(pair[0], pair[1])
	var ws := RegEx.new()
	ws.compile("\\s+")
	t = ws.sub(t, " ", true).strip_edges()
	var dots := RegEx.new()
	dots.compile("(?:\\.\\s*){2,}")
	t = dots.sub(t, ". ", true).strip_edges()
	while t.ends_with("."):
		t = t.substr(0, t.length() - 1).strip_edges()
	return t


static func parse_amount(word: String) -> int:
	word = word.strip_edges()
	if word.is_valid_int():
		return int(word)
	return NUMBER_WORDS.get(word, 1)


static func _split_sentences(t: String) -> Array:
	var out: Array = []
	for raw in t.split(". "):
		var s: String = raw.strip_edges().trim_suffix(".").strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


static func _strip_trigger_prefix(s: String) -> String:
	"""Quita el disparador y, en las activadas, el momento/frecuencia ("En tu
	Vigilia, una vez por turno, ..."), que pueden venir encadenados."""
	var changed := true
	while changed:
		changed = false
		for p in TRIGGER_PREFIXES + TIMING_PREFIXES:
			if s.begins_with(p + ", "):
				s = s.substr(p.length() + 2)
				changed = true
				break
	return s


static func _had_timing_prefix(s: String) -> bool:
	"""¿El texto empieza (tras el disparador) con momento/frecuencia de
	habilidad activada?"""
	var rest := s
	var changed := true
	while changed:
		changed = false
		for p in TRIGGER_PREFIXES + TIMING_PREFIXES:
			if rest.begins_with(p + ", "):
				if p in TIMING_PREFIXES:
					return true
				rest = rest.substr(p.length() + 2)
				changed = true
				break
	return false


static func _is_static(s: String) -> bool:
	for p in STATIC_STARTS:
		if s.begins_with(p):
			return true
	return false


static func _compile_sentence(s: String) -> Dictionary:
	"""Una oración: primero intenta la secuencia completa; si no, una
	elección 'A, o B' de nivel superior. Una condición inicial ('si X, ...')
	envuelve toda la oración en un paso 'if'."""
	for c in CONDITIONS:
		if s.begins_with(c[1]):
			var inner := _compile_sentence(s.substr(c[1].length()))
			if not inner.ok:
				return inner
			return {"ok": true, "steps": [{"op": "if", "cond": c[0], "steps": inner.steps}], "unparsed": ""}
	var seq := _compile_sequence(s)
	if seq.ok:
		return seq
	var cut := s.rfind(", o ")
	if cut > 0:
		var a := _compile_sequence(s.substr(0, cut))
		var b := _compile_sequence(s.substr(cut + 4))
		if a.ok and b.ok:
			return {"ok": true, "steps": [{"op": "choice", "options": [a.steps, b.steps]}], "unparsed": ""}
	return seq


static func _compile_sequence(s: String) -> Dictionary:
	"""Consume átomos de izquierda a derecha, unidos por ', ', ' y ',
	', y luego, '. Falla si queda cualquier resto sin consumir."""
	if _connector_rx == null:
		_connector_rx = RegEx.new()
		_connector_rx.compile("^(?:,\\s*)?(?:y luego,?\\s*|luego,?\\s*|y\\s+)?")
	var steps: Array = []
	var rest := s.strip_edges()
	var next_is_then := false
	while not rest.is_empty():
		var step := {}
		var consumed := 0
		for atom in _get_atoms():
			var m: RegExMatch = atom.rx.search(rest)
			if m == null:
				continue
			step = _build(atom.name, m)
			if not step.is_empty():
				consumed = m.get_end()
				break
		if step.is_empty():
			return {"ok": false, "steps": [], "unparsed": rest}
		if next_is_then:
			step["then"] = true
		steps.append(step)
		rest = rest.substr(consumed).strip_edges()
		var c := _connector_rx.search(rest)
		next_is_then = c != null and "luego" in c.get_string()
		if c and c.get_end() > 0:
			rest = rest.substr(c.get_end()).strip_edges()
	return {"ok": not steps.is_empty(), "steps": steps, "unparsed": ""}


static func _get_atoms() -> Array:
	if _compiled_atoms.is_empty():
		for a in ATOMS:
			var r := RegEx.new()
			var err := r.compile("^" + a[1])
			if err != OK:
				push_error("EffectCompiler: regex inválido en el átomo '%s'" % a[0])
				continue
			_compiled_atoms.append({"name": a[0], "rx": r})
	return _compiled_atoms


static func _build(atom_name: String, m: RegExMatch) -> Dictionary:
	"""Arma el paso de un átomo reconocido. Devuelve {} si el texto calzó
	pero el caso es ambiguo (que lo resuelva la cadena vieja)."""
	match atom_name:
		"draw":
			return {"op": "draw", "amount": parse_amount(m.get_string("n")), "up_to": not m.get_string("upto").is_empty()}
		"mill_per":
			var per_map := {
				"aliado en tu linea de defensa": "own_allies_defense", "aliado que controles": "own_allies",
				"totem en juego": "totems_in_play", "totem que controles": "own_totems",
			}
			return {"op": "mill", "who": "opponent", "amount": parse_amount(m.get_string("n")),
				"per": per_map.get(m.get_string("per"), "")}
		"mill_opp":
			return {"op": "mill", "who": "opponent", "amount": parse_amount(m.get_string("n"))}
		"mill_self":
			return {"op": "mill", "who": "self", "amount": parse_amount(m.get_string("n"))}
		"discard_opp_random":
			return {"op": "discard", "who": "opponent", "amount": parse_amount(m.get_string("n")), "random": true}
		"discard_self":
			return {"op": "discard", "who": "self", "amount": parse_amount(m.get_string("n")), "random": false}
		"shuffle_from_hand":
			return {"op": "shuffle_from_hand", "amount": parse_amount(m.get_string("n")),
				"up_to": not m.get_string("upto").is_empty()}
		"shuffle_from_cemetery":
			return {"op": "shuffle_from_cemetery", "amount": parse_amount(m.get_string("n")),
				"up_to": not m.get_string("upto").is_empty()}
		"target_silence":
			var ts_target := {"card_types": [], "controller": "opponent" if not m.get_string("opp").is_empty() else "any",
				"exclude_gold": true, "stat": "", "cmp": "<=", "value": 0}
			var ts_type: String = TYPE_WORDS.get(m.get_string("kind"), "")
			if not ts_type.is_empty():
				ts_target.card_types = [ts_type]
			return {"op": "target", "verb": "banish" if m.get_string("v").begins_with("desterrad") else "destroy",
				"count": 1, "up_to": false, "target": ts_target, "silence_first": true}
		"mass_silence":
			var ms_target := _target_from(m)
			ms_target.exclude_gold = true
			return {"op": "mass", "verb": "banish" if m.get_string("v").begins_with("desterrad") else "destroy",
				"target": ms_target, "silence_first": true}
		"self":
			return {"op": "self", "verb": "banish" if m.get_string("v").begins_with("destierr") else "destroy"}
		"search":
			var zones: Array = []
			for g in ["z1", "z2", "z3", "z4"]:
				var z: String = m.get_string(g)
				if not z.is_empty() and z not in zones:
					zones.append(z)
			if zones.is_empty():
				return {}  # sin zona explícita: ambiguo
			var det: String = m.get_string("det")
			return {"op": "search", "zones": zones, "card_type": TYPE_WORDS.get(m.get_string("type"), ""),
				"amount": parse_amount(det.trim_prefix("hasta ")), "up_to": det.begins_with("hasta ")}
		"mass":
			var mass_target := _target_from(m)
			mass_target.exclude_gold = true
			return {"op": "mass", "verb": "destroy" if m.get_string("verb") == "destruye" else "banish",
				"target": mass_target}
		"bounce":
			return _target_step("bounce", m)
		"target":
			var verb_word: String = m.get_string("verb")
			var verb := "destroy"
			if verb_word.begins_with("destierra") or verb_word.begins_with("desterrar"):
				verb = "banish"
			elif verb_word.begins_with("baraj"):
				verb = "shuffle"
			return _target_step(verb, m)
	return {}


static func _target_step(verb: String, m: RegExMatch) -> Dictionary:
	var det: String = m.get_string("det")
	return {"op": "target", "verb": verb, "count": parse_amount(det.trim_prefix("hasta ")),
		"up_to": det.begins_with("hasta "), "target": _target_from(m)}


static func _group(m: RegExMatch, name: String) -> String:
	# get_string() con un nombre que el regex no tiene da error — no todos
	# los átomos que arman objetivos definen los mismos grupos.
	return m.get_string(name) if m.names.has(name) else ""


static func _target_from(m: RegExMatch) -> Dictionary:
	var t := {
		"card_types": [],
		"controller": "opponent" if not _group(m, "opp").is_empty() else "any",
		"exclude_gold": not _group(m, "nogold").is_empty(),
		"stat": _group(m, "stat"),
		"cmp": "<=" if _group(m, "cmp") == "menos" else ">=",
		"value": int(_group(m, "val")) if not _group(m, "val").is_empty() else 0,
	}
	var tw: String = TYPE_WORDS.get(_group(m, "kind"), "")
	if not tw.is_empty():
		t.card_types = [tw]
	return t
