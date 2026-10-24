extends SceneTree
## Auditor de cobertura de EffectCompiler sobre el catálogo real (2026-10-12,
## ver arquitectura.md §54). Usa el compilador y el intérprete del juego,
## no una aproximación: un bloque "compilado" es exactamente lo que el juego
## resolverá por piezas.
##
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . -s tools/audit_cards.gd -- [filtro_edicion] [salida.json]
## filtro_edicion: texto a buscar en el campo "edicion" (p.ej. "Drácula");
## vacío o "*" = todo el catálogo. salida.json: opcional, detalle por carta.
##
## Clasificación de cada oración de una carta:
##   compilada   — bloque de disparador/Talismán que EffectInterpreter ejecuta
##   pieza_falta — el compilador lo entiende pero el intérprete aún no sabe
##                 ejecutar una de sus piezas (p.ej. "Sube ... a la mano")
##   sin_compilar— bloque de efecto que el compilador no entiende (lo resuelve
##                 la cadena de patrones vieja, si es que alguna lo toma)
##   estatica    — keyword/aura/permiso (sistema de efectos continuos, no auditado aquí)
##   activada    — habilidad activada ("una vez por turno", "puedes X para Y")
##                 que el compilador no resuelve (las que sí, cuentan como
##                 "compilada" y además en activada_compilada)
## Los Talismanes se compilan con TODO su texto en un solo bloque, igual que
## los recibe el juego (TriggerSystem.resolve_talisman()).
##
## Además lista las cartas de ediciones viejas cuyos bloques ahora se
## resuelven por piezas en vez de por su patrón de siempre (cambio de camino
## — conviene revisarlas).

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")
const CACHE_PATH := "user://card_cache/cards.json"
const ONCE_MARKERS := ["una vez por turno", "una vez al turno", "una vez en tu turno", "una vez en su turno"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var args := OS.get_cmdline_user_args()
	var ed_filter: String = args[0] if args.size() > 0 else "*"
	var out_path: String = args[1] if args.size() > 1 else ""
	_run(ed_filter, out_path)
	quit(0)
	return true


func _run(ed_filter: String, out_path: String) -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not f:
		print("AUDIT: no se pudo abrir ", CACHE_PATH)
		return
	var cards = JSON.parse_string(f.get_as_text().trim_prefix("﻿"))
	if not cards is Array:
		print("AUDIT: cache inválido")
		return

	var totals := {"compilada": 0, "pieza_falta": 0, "sin_compilar": 0, "estatica": 0, "activada": 0,
		"activada_compilada": 0}
	var detail: Array = []
	var full_cards := 0
	var considered := 0
	for c in cards:
		var ed: String = str(c.get("edicion", ""))
		if ed_filter != "*" and ed_filter != "" and ed_filter.to_lower() not in ed.to_lower():
			continue
		var text: String = str(c.get("habilidad", ""))
		if text.strip_edges().is_empty():
			continue
		considered += 1
		var is_talisman: bool = int(c.get("tipo", -1)) == 3
		var res := audit_text(text, is_talisman)
		for k in res.counts:
			totals[k] += res.counts[k]
		var effect_blocks: int = res.counts.compilada + res.counts.pieza_falta + res.counts.sin_compilar
		if effect_blocks > 0 and res.counts.compilada == effect_blocks:
			full_cards += 1
		detail.append({"id": c.get("id"), "nombre": c.get("nombre"), "edicion": ed, "tipo": c.get("tipo"),
			"counts": res.counts, "bloques": res.blocks})

	print("AUDIT: cartas con texto: %d (filtro: '%s')" % [considered, ed_filter])
	print("AUDIT: bloques de efecto — compilados: %d | pieza faltante: %d | sin compilar: %d" % [
		totals.compilada, totals.pieza_falta, totals.sin_compilar])
	print("AUDIT: oraciones estáticas: %d | activadas compiladas: %d | activadas sin compilar: %d" % [
		totals.estatica, totals.activada_compilada, totals.activada])
	print("AUDIT: cartas con TODOS sus bloques de efecto compilados: %d" % full_cards)
	if not out_path.is_empty():
		var w := FileAccess.open(out_path, FileAccess.WRITE)
		if w:
			w.store_string(JSON.stringify(detail, " "))
			print("AUDIT: detalle en ", out_path)


static func audit_text(text: String, is_talisman: bool) -> Dictionary:
	"""Separa el texto en bloques igual que el juego (disparador + sus
	continuaciones; Talismán = todo su texto) y clasifica cada uno."""
	var counts := {"compilada": 0, "pieza_falta": 0, "sin_compilar": 0, "estatica": 0, "activada": 0,
		"activada_compilada": 0}
	var blocks: Array = []
	if is_talisman:
		var tplan: Dictionary = EffectCompilerScript.compile_clause(text)
		var testado := "sin_compilar"
		if tplan.ok:
			testado = "compilada" if EffectCompilerScript.is_executable(tplan.steps) else "pieza_falta"
		counts[testado] += 1
		blocks.append({"texto": EffectCompilerScript.normalize(text), "estado": testado, "resto": tplan.unparsed})
		return {"counts": counts, "blocks": blocks}
	var sentences: Array = EffectCompilerScript._split_sentences(EffectCompilerScript.normalize(text))
	var i := 0
	while i < sentences.size():
		var s: String = sentences[i]
		if _is_activated(s):
			# Igual que parse_abilities(): las oraciones siguientes sin
			# disparador ni coste propio son continuación de la activada.
			var act: Array = [s]
			var k := i + 1
			while k < sentences.size():
				var nx: String = sentences[k]
				if _has_trigger_prefix(nx) or _is_activated(nx) or EffectCompilerScript._is_static(nx) \
						or _is_keyword_line(nx):
					break
				act.append(nx)
				k += 1
			var act_text := ". ".join(act)
			var aplan: Dictionary = EffectCompilerScript.compile_clause(act_text)
			if aplan.ok and EffectCompilerScript.is_executable(aplan.steps):
				counts.compilada += 1
				counts.activada_compilada += 1
				blocks.append({"texto": act_text, "estado": "compilada", "activada": true})
			else:
				counts.activada += 1
				blocks.append({"texto": act_text, "estado": "activada", "resto": aplan.unparsed})
			i = k
			continue
		if EffectCompilerScript._is_static(s) or _is_keyword_line(s):
			counts.estatica += 1
			blocks.append({"texto": s, "estado": "estatica"})
			i += 1
			continue
		var starts_block: bool = _has_trigger_prefix(s)
		if not starts_block:
			# Oración suelta que no es disparador ni estática conocida
			# (condición, regla especial, reemplazo...) — cuenta como efecto
			# sin compilar.
			counts.sin_compilar += 1
			blocks.append({"texto": s, "estado": "sin_compilar", "resto": s})
			i += 1
			continue
		var block: Array = [s]
		var j := i + 1
		while j < sentences.size():
			var nxt: String = sentences[j]
			if _has_trigger_prefix(nxt) or _is_activated(nxt) or EffectCompilerScript._is_static(nxt) \
					or _is_keyword_line(nxt):
				break
			block.append(nxt)
			j += 1
		var block_text := ". ".join(block)
		var plan: Dictionary = EffectCompilerScript.compile_clause(block_text)
		var estado := "sin_compilar"
		if plan.ok:
			estado = "compilada" if EffectCompilerScript.is_executable(plan.steps) else "pieza_falta"
		counts[estado] += 1
		blocks.append({"texto": block_text, "estado": estado, "resto": plan.unparsed})
		i = j
	return {"counts": counts, "blocks": blocks}


static func _has_trigger_prefix(s: String) -> bool:
	for p in EffectCompilerScript.TRIGGER_PREFIXES:
		if s.begins_with(p + ", ") or s.begins_with(p + " y "):
			return true
		# Sin coma ("cuando entra en juego baraja..."): mismo criterio que el compilador.
		if s.begins_with(p + " ") and EffectCompilerScript._strip_trigger_prefix(s) != s:
			return true
	return false


static func _is_activated(s: String) -> bool:
	for m in ONCE_MARKERS:
		if m in s:
			return true
	return s.begins_with("puedes ") and " para " in s


static func _is_keyword_line(s: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^(?:(?:furia|imbloqueable|indestructible|indesterrable|unica|exhumar|errante|retador"
		+ "|oro inicial)[ ,y]*)+$")
	return rx.search(s) != null
