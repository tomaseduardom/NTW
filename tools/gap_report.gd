extends SceneTree
## Informe de huecos del compilador (2026-10-24): para cada bloque no compilado de una auditoría
## (tools/audit_cards.gd), dónde se detiene EffectCompiler (campo "unparsed") y familias por las
## primeras palabras de ese resto. Sirve para elegir la próxima pieza del compilador: la familia más
## grande es la que más cartas destraba.
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . -s tools/gap_report.gd -- audit.json salida.json [palabras=3]

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("Uso: -s tools/gap_report.gd -- audit.json salida.json [palabras]")
		quit(1)
		return
	var words: int = int(args[2]) if args.size() > 2 else 3
	var cards = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var families := {}
	var items: Array = []
	for card in cards:
		for b in card.get("bloques", []):
			if not (str(b.get("estado", "")) in ["sin_compilar", "activada"]):
				continue
			var text: String = str(b.get("texto", ""))
			var c: Dictionary = EffectCompilerScript.compile_clause(text)
			var rest: String = str(c.get("unparsed", text)).strip_edges()
			var key := " ".join(rest.split(" ").slice(0, words))
			items.append({"carta": card.get("nombre", ""), "id": card.get("id", ""), "texto": text, "resto": rest,
				"activada": bool(c.get("activated", false))})
			if not families.has(key):
				families[key] = {"n": 0, "ejemplos": []}
			families[key].n += 1
			if families[key].ejemplos.size() < 4:
				families[key].ejemplos.append("%s: %s" % [card.get("nombre", ""), rest.left(140)])
	var keys := families.keys()
	keys.sort_custom(func(a, b): return families[a].n > families[b].n)
	var out := {"items": items, "familias": []}
	for k in keys:
		out.familias.append({"clave": k, "n": families[k].n, "ejemplos": families[k].ejemplos})
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	for k in keys.slice(0, 60):
		print("GAP %4d | %s | %s" % [families[k].n, k, families[k].ejemplos[0]])
	quit(0)
