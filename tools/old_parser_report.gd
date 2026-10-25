extends Node
## Clasificador de lo que resuelve el analizador viejo (2026-10-25). La sonda de handlers
## (docs/sondas/ramas-*.json) dice qué textos llegan a UniversalCardParser.extract_action(): ese
## camino ejecuta UNA acción suelta (la primera palabra clave que reconoce), sin filtros ni reparto.
## Para cada texto compara esa acción con lo que dice la carta y lo marca:
##   bien        — un solo efecto simple que la acción extraída cubre entera
##   incompleta  — más de un efecto, filtros que la acción pierde, elecciones, condiciones, cantidades
##                 distintas o más de una oración con efecto (la razón va en el informe)
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/old_parser_report.tscn -- textos.json salida.md
## textos.json: [{"carta": "...", "texto": "..."}, ...]

const CardTextScript = preload("res://scripts/core/cards/CardText.gd")
const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")

## Verbos de efecto (imperativo y en infinitivo) en texto plegado.
const VERBS := ["roba", "robar", "robas", "descarta", "descartar", "destruye", "destruir", "destierra", "desterrar",
	"baraja", "barajar", "bota", "botar", "busca", "buscar", "muestra", "mostrar", "mira", "mirar", "pon", "poner",
	"ponlo", "ponla", "ponlos", "ponlas", "juega", "jugar", "juegalo", "juegala", "sube", "subir", "gana", "ganan",
	"pierde", "pierden", "convierte", "convertir", "anula", "anular", "cancela", "cancelar", "genera", "generar",
	"agrupa", "agrupar", "elige", "elegir", "nombra", "nombrar", "preven", "prevenir", "paga", "pagar", "intercambia"]
const FILTERS := ["de coste", "que no sea", "que no sean", "de fuerza", "sin habilidad", "con habilidad", "de distinto",
	"oponente", "oponentes", "que controles", "de tu cementerio", "de tu mano", "de un cementerio", "de los cementerios",
	"del tope", "del fondo", "al azar", "aliado", "aliados", "oro", "oros", "arma", "armas", "totem", "talisman"]
const CHOICES := ["elige", " o ", "si ", "por cada", "hasta mostrar", "tantas", "igual a", "cualquier cantidad",
	"luego", "ademas", "cada jugador", "en su lugar"]
## Lo que cada action_type entiende sin perder nada.
const SIMPLE_OBJECTS := ["cartas", "carta"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var items = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var rows: Array = []
	var counts := {"bien": 0, "incompleta": 0, "sin_accion": 0}
	var families := {}
	for it in items:
		var text: String = CardTextScript.fold(str(it.texto)).replace("\n", " ")
		var effect: String = _effect_part(text)
		var action: Dictionary = UniversalCardParser.extract_action(str(it.texto))
		var reasons: Array = _reasons(effect, action)
		var verdict := "sin_accion" if not action.get("matched", false) else ("bien" if reasons.is_empty() else "incompleta")
		counts[verdict] += 1
		var fam: String = " ".join(effect.split(" ").slice(0, 2))
		if verdict == "incompleta":
			families[fam] = int(families.get(fam, 0)) + 1
		# Dónde se detiene el compilador con este mismo texto: la pieza que falta para migrarlo.
		var comp: Dictionary = EffectCompilerScript.compile_clause(str(it.texto))
		rows.append({"carta": it.carta, "veredicto": verdict, "accion": str(action.get("method", "")) + " " + str(action.get("raw_text", "")),
			"razones": reasons, "efecto": effect, "compilador_resto": str(comp.get("unparsed", "")).strip_edges()})
	var out: PackedStringArray = []
	out.append("# Analizador viejo: qué resuelve bien y qué no (%s)" % Time.get_date_string_from_system())
	out.append("")
	out.append("Textos: %d · bien: %d · incompletos: %d · sin acción: %d" % [rows.size(), counts.bien, counts.incompleta, counts.sin_accion])
	out.append("")
	out.append("## Familias incompletas (primeras dos palabras del efecto)")
	var fk := families.keys()
	fk.sort_custom(func(a, b): return families[a] > families[b])
	for k in fk:
		out.append("- **%d** · `%s`" % [families[k], k])
	for verdict in ["incompleta", "bien", "sin_accion"]:
		out.append("")
		out.append("## %s" % verdict)
		for r in rows:
			if r.veredicto == verdict:
				out.append("- **%s** — hace: `%s`%s — %s" % [r.carta, str(r.accion).strip_edges(),
					(" · " + ", ".join(PackedStringArray(r.razones))) if not r.razones.is_empty() else "", str(r.efecto).left(160)])
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	var jf := FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(rows, "\t"))
	jf.close()
	print("VIEJO: textos %d | bien %d | incompletos %d | sin accion %d" % [rows.size(), counts.bien, counts.incompleta, counts.sin_accion])
	get_tree().quit(0)


func _effect_part(text: String) -> String:
	"""El efecto sin disparador ni frecuencia ("Cuando entra en juego, una vez por turno, ...")."""
	var t := text.strip_edges()
	var prefix := RegEx.create_from_string("^(?:(?:cuando|al comienzo|al final|en tu|en la|una vez|hasta dos veces|hasta tres veces)[^,]*, )+")
	t = prefix.sub(t, "")
	return t.trim_suffix(".").strip_edges()


func _reasons(effect: String, action: Dictionary) -> Array:
	var out: Array = []
	var words := effect.replace(",", " ").replace(".", " ").split(" ", false)
	var verbs := 0
	for w in words:
		if w in VERBS:
			verbs += 1
	if verbs > 1:
		out.append("%d verbos" % verbs)
	var sentences: Array = Array(effect.split(". ", false)).filter(func(s): return VERBS.any(func(v): return (" " + v + " ") in (" " + s + " ")))
	if sentences.size() > 1:
		out.append("%d oraciones con efecto" % sentences.size())
	for c in CHOICES:
		if c in (" " + effect + " "):
			out.append("'%s'" % c.strip_edges())
			break
	var raw := CardTextScript.fold(str(action.get("raw_text", "")))
	for fl in FILTERS:
		if (" " + fl) in (" " + effect) and not (fl in raw):
			out.append("filtro '%s'" % fl)
			break
	# Cantidad: el número del texto contra el de la acción.
	var amount_rx := RegEx.create_from_string("\\b(un|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|\\d+)\\b")
	var m := amount_rx.search(effect)
	if m and action.has("amount"):
		var n: int = EffectCompilerScript.parse_amount(m.get_string(1))
		if n != int(action.get("amount", n)):
			out.append("cantidad %d vs %d" % [n, int(action.amount)])
	return out
