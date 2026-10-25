extends RefCounted
class_name CardText
## CardText — una sola forma de limpiar y comparar el texto de las cartas.
## - clean(): al cargar cada carta (CardDatabase._corrected_text()). Arregla tipografía sin cambiar
##   el sentido: saltos de línea de Windows, espacios sobrantes, espacio antes de puntuación, falta
##   de espacio tras un punto, comillas tipográficas, "de de", y las erratas de GRAMMAR_FIXES.
## - fold(): minúsculas, sin tildes ni ñ/ü y espacios colapsados. La usan los normalizadores de los
##   handlers (EffectCompiler.normalize(), CemeteryTriggers.normalize(), DeckValidator) para que una
##   frase se compare igual venga como venga escrita.
## - has(): "contiene esta frase" con fold() de los dos lados.
## Se usa con preload / load.

## Erratas de concordancia impresas: [texto, corrección]. Solo casos verificados (sujeto plural con
## verbo en singular que rompe la lectura de la regla).
const GRAMMAR_FIXES := [
	["Los Oros oponentes pierde su habilidad", "Los Oros oponentes pierden su habilidad"],  # wayra tata
	["busca un Oto en tu Castillo", "busca un Oro en tu Castillo"],  # trofeo de cazador
	["una carta carta", "una carta"],  # lucy
]

const _FOLD_PAIRS := [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"],
	["Á", "a"], ["É", "e"], ["Í", "i"], ["Ó", "o"], ["Ú", "u"], ["Ü", "u"], ["Ñ", "n"], ["�", "n"]]

static var _rx_spaces: RegEx = null
static var _rx_before_punct: RegEx = null
static var _rx_after_dot: RegEx = null


static func clean(text: String) -> String:
	if text.is_empty():
		return text
	_ensure_rx()
	var t := text.replace("\r\n", "\n").replace("\r", "\n").replace(" ", " ").replace("\t", " ")
	t = t.replace("“", "\"").replace("”", "\"").replace("‘", "'").replace("’", "'")
	var lines: PackedStringArray = []
	for line in t.split("\n"):
		var l: String = _rx_spaces.sub(line, " ", true).strip_edges()
		l = _rx_before_punct.sub(l, "$1", true)
		l = _rx_after_dot.sub(l, ". $1", true)
		l = l.replace(" de de ", " de ")
		lines.append(l)
	t = "\n".join(lines).strip_edges()
	for fix in GRAMMAR_FIXES:
		t = t.replace(fix[0], fix[1])
	return t


static func fold(text: String) -> String:
	_ensure_rx()
	var t := text.to_lower()
	for pair in _FOLD_PAIRS:
		t = t.replace(pair[0], pair[1])
	return _rx_spaces.sub(t, " ", true)


static func has(text: String, phrase: String) -> bool:
	return fold(phrase).strip_edges() in fold(text.replace("\n", " "))


static func _ensure_rx() -> void:
	if _rx_spaces:
		return
	_rx_spaces = RegEx.create_from_string("[ \\t\\x{00a0}]+")
	_rx_before_punct = RegEx.create_from_string("\\s+([.,;:])")
	# "Vigilia.Puedes" -> "Vigilia. Puedes" (no toca números como "1.5" ni abreviaturas en minúscula).
	_rx_after_dot = RegEx.create_from_string("(?<=[a-záéíóúñ])\\.([A-ZÁÉÍÓÚÑ])")
