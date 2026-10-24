extends Node
## Revisión de lo que compila EffectCompiler (2026-10-24): para cada texto, la descripción legible de
## sus pasos (EffectInterpreter.describe_steps()) y los pasos crudos. Sirve para comparar a mano, carta
## por carta, el texto impreso con lo que el juego va a hacer antes de dar por buena una pieza nueva.
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/describe_compiled.tscn -- textos.json
## (escena y no -s: el intérprete usa autoloads, que un script -s no ve al compilar).
## textos.json: [{"carta": "...", "texto": "..."}, ...]

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")
const EffectInterpreterScript = preload("res://scripts/core/effects/compiler/EffectInterpreter.gd")


func _ready() -> void:
	var items = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	for it in items:
		var c: Dictionary = EffectCompilerScript.compile_clause(str(it.texto))
		print("REV %s | %s" % [it.carta, str(it.texto).left(200)])
		print("    -> %s%s" % ["" if c.get("ok", false) else "[NO COMPILA] ",
			EffectInterpreterScript.describe_steps(c.get("steps", []))])
		print("    pasos: %s" % JSON.stringify(c.get("steps", [])).left(400))
	get_tree().quit(0)
