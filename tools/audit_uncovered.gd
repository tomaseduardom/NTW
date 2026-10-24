extends SceneTree
## Detector de bloques sin efecto (2026-10-21). audit_cards.gd dice qué compila EffectCompiler, pero
## un bloque "sin compilar" puede resolverlo igual un patrón viejo (detección por substring:
## '"tu oponente destierra seis cartas..." in lower'). Este detector junta esas frases de detección
## de todos los .gd de scripts/ y marca cada bloque no compilado como:
##   cubierto    — contiene alguna frase de detección de un patrón
##   sin_cubrir  — ninguna: candidato a "la carta no hace nada" (o lo detecta una RegEx, que esto no ve)
## Heurístico: una frase muy genérica ("cuando entra en juego") cubriría todo, así que se descartan
## las que aparecen en más de MAX_BLOCKS_PER_PHRASE bloques. Los patrones que detectan con RegEx
## (GoldManagerTax._PAY_REDUCTION_RX, CastleLook...) quedan como falsos "sin_cubrir": revisar a mano.
##
## Uso (después de audit_cards.gd, que genera el JSON):
##   Godot_v4.6-stable_win64_console.exe --headless --path . -s tools/audit_uncovered.gd -- audit.json salida.md

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")
const MIN_PHRASE_LEN := 14
const MAX_BLOCKS_PER_PHRASE := 25
const STATES := ["sin_compilar", "activada", "estatica", "pieza_falta"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("Uso: -s tools/audit_uncovered.gd -- audit.json salida.md")
		quit(1)
		return
	var cards = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not (cards is Array):
		print("No se pudo leer %s" % args[0])
		quit(1)
		return

	var blocks: Array = []  # {card, state, text}
	for c in cards:
		for b in c.get("bloques", []):
			if str(b.get("estado", "")) in STATES:
				blocks.append({"card": str(c.get("nombre", "?")), "state": str(b.estado), "text": str(b.get("texto", ""))})

	var phrases := _detection_phrases()
	var regexes := _detection_regexes()
	# Frases genéricas fuera: las que tocan demasiados bloques no prueban nada.
	var useful: Array = []
	for p in phrases:
		if _usable(blocks, func(t: String) -> bool: return p in t):
			useful.append(p)
	var useful_rx: Array = []
	for r in regexes:
		if _usable(blocks, func(t: String) -> bool: return r.search(t) != null):
			useful_rx.append(r)
	var named := _names_in_code(cards)

	var per_state := {}
	var uncovered: Array = []
	for b in blocks:
		var covered := false
		for p in useful:
			if p in b.text:
				covered = true
				break
		if not covered:
			for r in useful_rx:
				if r.search(b.text) != null:
					covered = true
					break
		var status := "cubierto"
		if not covered:
			status = "nombrada" if named.has(b.card.to_lower()) else "sin_cubrir"
		b["status"] = status
		var key: String = b.state + "|" + status
		per_state[key] = int(per_state.get(key, 0)) + 1
		if not covered:
			uncovered.append(b)

	var out := PackedStringArray()
	out.append("# Bloques sin efecto detectado (%s)" % Time.get_date_string_from_system())
	out.append("")
	out.append("Frases de detección: %d (útiles: %d), RegEx: %d (útiles: %d). Bloques no compilados: %d." % [
		phrases.size(), useful.size(), regexes.size(), useful_rx.size(), blocks.size()])
	out.append("'Nombrada': ninguna frase la cubre, pero el nombre de la carta aparece en el código (revisar).")
	out.append("")
	out.append("| Estado | Cubierto por un patrón | Nombrada | Sin cubrir |")
	out.append("|---|---|---|---|")
	for s in STATES:
		out.append("| %s | %d | %d | %d |" % [s, int(per_state.get(s + "|cubierto", 0)),
			int(per_state.get(s + "|nombrada", 0)), int(per_state.get(s + "|sin_cubrir", 0))])
	out.append("")
	out.append("## Familias sin cubrir (primeras tres palabras, sin estáticas)")
	out.append("")
	var fam := {}
	var fam_example := {}
	for b in uncovered:
		if b.state == "estatica" or b.status != "sin_cubrir":
			continue
		var words: PackedStringArray = EffectCompilerScript._strip_trigger_prefix(b.text).split(" ", false)
		var head := " ".join(words.slice(0, 3))
		fam[head] = int(fam.get(head, 0)) + 1
		if not fam_example.has(head):
			fam_example[head] = "%s: %s" % [b.card, b.text.substr(0, 120)]
	var heads: Array = fam.keys()
	heads.sort_custom(func(a, b): return fam[a] > fam[b])
	for h in heads.slice(0, 40):
		out.append("- **%d** · `%s` — %s" % [fam[h], h, fam_example[h]])
	for s in ["sin_compilar", "activada", "pieza_falta", "estatica"]:
		out.append("")
		out.append("## %s sin cubrir" % s)
		out.append("")
		for b in uncovered:
			if b.state == s:
				out.append("- %s**%s** — %s" % ["(nombrada) " if b.status == "nombrada" else "", b.card, b.text])
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	for s in STATES:
		print("UNCOVERED: %s — cubiertos %d, nombrados %d, sin cubrir %d" % [s, int(per_state.get(s + "|cubierto", 0)),
			int(per_state.get(s + "|nombrada", 0)), int(per_state.get(s + "|sin_cubrir", 0))])
	print("UNCOVERED: detalle en %s" % args[1])
	quit()


func _detection_phrases() -> Array:
	"""Literales en minúscula de todos los .gd de scripts/ (las frases que los patrones buscan con
	'in lower'), normalizados como los textos de la auditoría. Los textos en mayúscula son mensajes y
	prompts, no detección."""
	var rx := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var seen := {}
	for path in _gd_files("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for m in rx.search_all(src):
			var lit: String = m.get_string(1)
			if lit.length() < MIN_PHRASE_LEN or lit != lit.to_lower() or not (" " in lit):
				continue
			if "%" in lit or "res://" in lit or "/root" in lit or "(?" in lit or "\\" in lit or "[" in lit:
				continue
			var norm := EffectCompilerScript.normalize(lit)
			if norm.length() >= MIN_PHRASE_LEN:
				seen[norm] = true
	return seen.keys()


func _usable(blocks: Array, matches: Callable) -> bool:
	var n := 0
	for b in blocks:
		if matches.call(b.text):
			n += 1
			if n > MAX_BLOCKS_PER_PHRASE:
				return false
	return n > 0


func _detection_regexes() -> Array:
	"""Literales que parecen RegEx (p.ej. Arturo de Bretaña: "buscar en tu castillo y/o cementerio hasta
	(\\w+) (armas|...)"), desescapados y sin tildes (los textos auditados no las tienen). Los fragmentos
	que no compilan solos (concatenados con NUM, etc.) se descartan."""
	var rx := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var out: Array = []
	var seen := {}
	for path in _gd_files("res://scripts"):
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			var lit: String = m.get_string(1)
			if lit.length() < MIN_PHRASE_LEN or not ("(" in lit or "\\\\" in lit or "[" in lit) or not (" " in lit or "\\\\s" in lit):
				continue
			if lit != lit.to_lower() and not ("\\\\" in lit) or "res://" in lit or "%" in lit:
				continue
			var pattern := lit.replace("\\\\", "\\").replace("\\\"", "\"")
			for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ñ", "n"]]:
				pattern = pattern.replace(pair[0], pair[1])
			if seen.has(pattern):
				continue
			seen[pattern] = true
			# Al menos 10 letras seguidas o con espacios: un patrón sin texto propio (p.ej. "(\\d+)") cubre cualquier cosa.
			if RegEx.create_from_string("[a-z ]{10,}").search(pattern) == null:
				continue
			var r := RegEx.new()
			if r.compile(pattern) == OK:
				out.append(r)
	return out


func _names_in_code(cards: Array) -> Dictionary:
	"""Nombres de carta que aparecen en el código (comentarios incluidos), en minúscula."""
	var all := ""
	for path in _gd_files("res://scripts"):
		all += FileAccess.get_file_as_string(path).to_lower() + "\n"
	var names := {}
	for c in cards:
		var low: String = str(c.get("nombre", "")).to_lower()
		if low.length() >= 4 and low in all:
			names[low] = true
	return names


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(d)))
	return out
