extends Node
## Suite mínima de reglas y red, sin tablero: CardText, datos de cartas, DeckValidator, auras de
## "pierden su habilidad", respuestas por defecto de TurnClock, historial (CombatLog, RevealedCards) y
## MatchReset.
## Uso (o tools/run_tests.ps1, que corre también test_keywords_strength):
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/tests/test_core.tscn
## Sale con código 1 si algún caso falla.

const CardTextScript = preload("res://scripts/core/cards/CardText.gd")
const DeckValidatorScript = preload("res://scripts/core/cards/DeckValidator.gd")
const TurnClockScript = preload("res://scripts/core/network/TurnClock.gd")
const RevealedCardsScript = preload("res://scripts/core/effects/mechanics/RevealedCards.gd")
const CombatLogScript = preload("res://scripts/core/logging/CombatLog.gd")
const SilenceAurasScript = preload("res://scripts/core/effects/continuous/SilenceAuras.gd")
const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")
const MatchResetScript = preload("res://scripts/core/game/MatchReset.gd")
const PhaseStartWindowScript = preload("res://scripts/core/game/PhaseStartWindow.gd")

var failed := 0
var passed := 0


func _ready() -> void:
	if not CardDatabase.is_loaded:
		CardDatabase.load_cards_from_bundled()
	if CardDatabase.cards.is_empty():
		print("ERROR: CardDatabase no cargó")
		get_tree().quit(1)
		return
	_card_text()
	_card_data()
	_deck_validator()
	_silence_parse()
	_turn_clock_defaults()
	_history()
	_match_reset()
	_compiler()
	print("Core: %d/%d casos OK" % [passed, passed + failed])
	get_tree().quit(1 if failed > 0 else 0)


# =============================================================================
# AYUDAS
# =============================================================================
func check(label: String, got, expected) -> void:
	if got == expected:
		passed += 1
	else:
		failed += 1
		print("FALLA: %s\n   esperado: %s\n   obtenido: %s" % [label, str(expected), str(got)])


func card(name: String, tipo: int = -1) -> Dictionary:
	for c in CardDatabase.cards.values():
		if str(c.nombre).to_lower() == name.to_lower() and (tipo < 0 or int(c.tipo) == tipo):
			return c
	print("ERROR: no está la carta '%s'" % name)
	return {}


func deck_of(groups: Array) -> Array:
	"""[[datos, copias], ...] -> lista de datos."""
	var out: Array = []
	for g in groups:
		for _i in int(g[1]):
			out.append(g[0])
	return out


# =============================================================================
# CASOS
# =============================================================================
func _card_text() -> void:
	check("clean: espacios, CRLF y espacio antes del punto", CardTextScript.clean("Furia.  Si\r\nRoba una carta ."), "Furia. Si\nRoba una carta.")
	check("clean: falta espacio tras el punto", CardTextScript.clean("en esta Vigilia.Puedes Desterrarlo"), "en esta Vigilia. Puedes Desterrarlo")
	check("clean: comillas tipográficas", CardTextScript.clean("la habilidad “Puedes”"), "la habilidad \"Puedes\"")
	check("clean: no toca números", CardTextScript.clean("Fuerza 1.5"), "Fuerza 1.5")
	check("clean: errata de concordancia", CardTextScript.clean("Los Oros oponentes pierde su habilidad."), "Los Oros oponentes pierden su habilidad.")
	check("fold: tildes, ñ, ü y mayúsculas", CardTextScript.fold("Única ÑANDÚ pingüino"), "unica nandu pinguino")
	check("fold: espacios colapsados", CardTextScript.fold("a  \tb"), "a b")
	check("has: compara plegando los dos lados", CardTextScript.has("Los Aliados  ganan FURIA.\nRoba", "aliados ganan furia"), true)
	check("has: frase ausente", CardTextScript.has("Los Aliados ganan Furia", "pierden"), false)
	check("EffectCompiler.normalize usa fold", EffectCompilerScript.normalize("Única.\nRoba  una carta."), "unica. roba una carta")


func _card_data() -> void:
	var bad := 0
	var first := ""
	for c in CardDatabase.cards.values():
		var h: String = str(c.get("habilidad", ""))
		if "\r" in h or "  " in h or " ." in h or "\t" in h or " " in h:
			bad += 1
			if first.is_empty():
				first = str(c.nombre)
	check("texto de cartas limpio al cargar (primera con problema: %s)" % first, bad, 0)
	check("wayra tata corregida al cargar", "pierden su habilidad" in str(card("wayra tata").get("habilidad", "")), true)


func _deck_validator() -> void:
	# Los presets de data/decks son válidos.
	var dir := DirAccess.open("res://data/decks")
	var presets := 0
	if dir:
		for f in dir.get_files():
			if not f.ends_with(".json"):
				continue
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/decks/" + f))
			var ids: Array = []
			for e in d.get("entries", []):
				for _i in int(e.get("quantity", 1)):
					ids.append(str(e.get("myl_id", "")))
			check("preset válido: %s" % f, DeckValidatorScript.validate_ids(ids), [])
			presets += 1
	check("hay presets para validar", presets > 0, true)

	var oro: Dictionary = {}
	for c in CardDatabase.cards.values():
		if int(c.tipo) == Constants.CardType.ORO and str(c.habilidad).strip_edges().is_empty():
			oro = c
			break
	var normals: Array = []
	for c in CardDatabase.cards.values():
		var h := CardTextScript.fold(str(c.habilidad))
		if int(c.tipo) == Constants.CardType.ALIADO and not ("unica" in h) and not ("mas de tres copias" in h) \
				and not normals.any(func(n): return CardTextScript.fold(str(n.nombre)) == CardTextScript.fold(str(c.nombre))):
			normals.append(c)
		if normals.size() >= 10:
			break
	var base := [[oro, 20]]
	for n in normals:
		base.append([n, 3])
	check("50 cartas: 20 Oros sin habilidad + 10 x3", DeckValidatorScript.validate(deck_of(base)), [])
	check("49 cartas no vale", DeckValidatorScript.validate(deck_of(base).slice(1)).size(), 1)
	var four := base.duplicate(true)
	four[0] = [oro, 19]
	four[1] = [normals[0], 4]
	check("4 copias no vale", DeckValidatorScript.validate(deck_of(four)).size(), 1)
	var banned := base.duplicate(true)
	banned[0] = [oro, 19]
	banned.append([card("liberar esclavos"), 1])
	check("carta baneada no vale", DeckValidatorScript.validate(deck_of(banned)).size(), 1)
	var unique: Dictionary = {}
	for c in CardDatabase.cards.values():
		if load("res://scripts/core/cards/KeywordParser.gd").has_own(str(c.habilidad), Constants.Keyword.UNICA):
			unique = c
			break
	if not unique.is_empty():
		var two := base.duplicate(true)
		two[0] = [oro, 18]
		two.append([unique, 2])
		check("Única x2 no vale", DeckValidatorScript.validate(deck_of(two)).size(), 1)
	var many := base.duplicate(true)
	many[0] = [oro, 15]
	many.append([card("ofuda"), 5])
	check("'más de tres copias' x5 vale", DeckValidatorScript.validate(deck_of(many)), [])
	var ids50: Array = []
	for _i in 50:
		ids50.append(str(oro.id))
	ids50[0] = "no-existe"
	check("id desconocido no vale", DeckValidatorScript.validate_ids(ids50).size() > 0, true)


func _silence_parse() -> void:
	var s: Dictionary = SilenceAurasScript._parse_sentence("los oros oponentes pierden su habilidad")
	check("aura: Oros oponentes (lado)", s.get("side", ""), "opp")
	check("aura: Oros oponentes (tipo)", int(s.get("type", -2)), Constants.CardType.ORO)
	check("aura: 'cuando' no es continua", SilenceAurasScript._parse_sentence("cuando entra en juego, los oros oponentes pierden su habilidad"), {})
	var cost: Dictionary = SilenceAurasScript._parse_sentence("las cartas de coste 1 pierden su habilidad")
	check("aura: coste 1 (septimus)", [cost.get("cost_val", -1), cost.get("cost_cmp", "")], [1, "eq"])


func _turn_clock_defaults() -> void:
	var tc = TurnClockScript.new()
	check("reloj: Vigilia termina", tc._default_intent(["place_gold", "end_vigilia"], {}).get("kind"), "end_vigilia")
	check("reloj: sin atacantes", tc._default_intent(["declare_attackers"], {}).get("card_ids"), [])
	check("reloj: pasa prioridad", tc._default_intent(["priority_response"], {}).get("kind"), "pass")
	check("reloj: selección opcional se cancela",
		tc._default_intent(["select_cards_choice"], {"can_cancel": true}).get("cancelled"), true)
	check("reloj: selección obligatoria toma el mínimo",
		tc._default_intent(["select_cards_choice"], {"can_cancel": false, "min_selections": 2, "candidates": [{}, {}, {}]}).get("indices"), [0, 1])
	check("reloj: objetivo obligatorio, el primero",
		tc._default_intent(["await_target_choice"], {"cancellable": false, "candidates": [{"card_id": "7"}, {"card_id": "9"}]}).get("card_id"), "7")
	check("reloj: buscar con mínimo, la primera elegible",
		tc._default_intent(["zone_pick_choice"], {"min_selections": 1, "pools": [{"cards": [{"eligible": false, "data": {}}, {"eligible": true, "data": {}}]}]}).get("picks"), [[0, 1]])
	tc.hand_limit_pid = 1
	tc._active_pid = 1
	check("reloj: descarte de Fase Final espera el plazo",
		tc._default_intent(["await_multi_target_choice"], {"cancellable": false, "max_selections": 2, "candidates": [{"card_id": "1"}, {"card_id": "2"}, {"card_id": "3"}]}), {})
	tc._grace_start_ms = Time.get_ticks_msec() - 11000
	check("reloj: tras el plazo, las primeras de la izquierda",
		tc._default_intent(["await_multi_target_choice"], {"cancellable": false, "max_selections": 2, "candidates": [{"card_id": "1"}, {"card_id": "2"}, {"card_id": "3"}]}).get("card_ids"), ["1", "2"])
	tc.free()


func _history() -> void:
	check("historial: se cambian los jugadores en el Remoto",
		CombatLogScript._swap_players("TURNO 2 - JUGADOR 1 · Jugador 2 juega"), "TURNO 2 - JUGADOR 2 · Jugador 1 juega")
	RevealedCardsScript.record(1, [{"nombre": "Prueba", "esta_oculta": true}], "Test")
	var g: Dictionary = RevealedCardsScript.group(RevealedCardsScript._next_id - 1)
	check("cartas mostradas: grupo guardado", g.get("title", ""), "Test")
	check("cartas mostradas: se ven boca arriba", g.get("cards", [{}])[0].get("esta_oculta", true), false)
	var entries: Array = CombatLog.get_entries(1)
	check("cartas mostradas: entrada en el historial", entries[0].get("type", "") if not entries.is_empty() else "", "reveal")


func _match_reset() -> void:
	# Estado que una partida cortada a la mitad dejaba vivo.
	PriorityManager.suppress_human_autopass = true
	PriorityManager.priority_window_active = true
	AnimationQueue.is_running = true
	AnimationQueue.command_queue.append({"x": 1})
	TurnManager.ally_played_serial[123] = 4
	GameManager.turn_serial = 9
	PhaseStartWindowScript._running = true
	SilenceAurasScript._disabled[1] = true
	CombatLog.add_entry("play", "entrada de la partida anterior")
	var registry_size: int = EffectController._prevention_registry.size()
	var count: int = MatchResetScript.reset_all()
	check("reset: variables reiniciadas", count > 50, true)
	check("reset: prioridad", [PriorityManager.suppress_human_autopass, PriorityManager.priority_window_active], [false, false])
	check("reset: cola de animaciones", [AnimationQueue.is_running, AnimationQueue.command_queue.size()], [false, 0])
	check("reset: turno y Aliados jugados", [GameManager.turn_serial, TurnManager.ally_played_serial.size()], [0, 0])
	check("reset: ventana de comienzo de fase", PhaseStartWindowScript._running, false)
	check("reset: auras", SilenceAurasScript._disabled.size(), 0)
	check("reset: historial vacío", CombatLog.get_entries().size(), 0)
	check("reset: Array tipado sigue tipado", AnimationQueue.command_queue.is_typed(), true)
	check("reset: se conserva lo armado en _ready", EffectController._prevention_registry.size(), registry_size)
	check("reset: submódulos siguen vivos", is_instance_valid(TriggerSystem._effect_interpreter), true)
	check("reset: las cartas no se tocan", CardDatabase.cards.is_empty(), false)


func _compiler() -> void:
	# Piezas del compilador: cada frase debe compilar completa (ok) en vez de quedar para un handler suelto.
	for text in [
		"Una vez por turno, puedes Desterrar una carta de tu mano para Robar una carta.",
		"En tu Fase Final, puedes Desterrar una carta de tu mano para agrupar un Oro.",
		"En tu Fase Final, busca una carta en tu Castillo, ponla en tu mano y Roba una carta.",
		"Cuando entra en juego, busca un Aliado en tu Castillo o Cementerio, ponlo en tu mano y tus Aliados ganan 1 de Fuerza permanentemente.",
		"Busca en tu Castillo un Aliado, ponlo en tu mano y Roba dos cartas.",
		"Cuando entra en juego, muestra cartas del tope de tu Castillo hasta mostrar un Oro. Pon esa carta en tu mano y Baraja el resto.",
		"Cuando entra en juego, Baraja hasta cinco cartas de tu Cementerio y Roba una carta.",
		"Cuando entra en juego, mira la mano de tu oponente y Descarta una carta de ahí de coste 1.",
		"Una vez por turno, puedes Destruir una carta que controles para Robar una carta.",
		"Una vez por turno, puedes Desterrar un Oro que controles para Destruir una carta de coste 2 o menos.",
		"Cuando entra en juego, busca en tu Castillo una copia de esta carta y ponla en tu mano.",
		"Cuando entra en juego, busca en tu Castillo un Aliado que no sea Ahab y ponlo en tu mano.",
		"Cuando entra en juego, busca en tu Castillo un Aliado de Fuerza 2 o menos y ponlo en tu mano.",
		"Cuando entra en juego, busca en tu Castillo un Aliado Sacerdote y destiérralo.",
	]:
		check("compila: %s" % text, EffectCompilerScript.compile_clause(text).get("ok", false), true)
	var c: Dictionary = EffectCompilerScript.compile_clause("Una vez por turno, puedes Desterrar una carta de tu mano para Robar una carta.")
	var costs: Array = c.get("steps", []).filter(func(s): return s.get("op") == "cost")
	check("coste: desterrar de la mano", costs[0].get("kind", "") if not costs.is_empty() else "", "banish_hand")
	# "una carta del mismo tipo" no es un nombre de carta.
	check("no compila: una carta del mismo tipo",
		EffectCompilerScript.compile_clause("Busca en tu Castillo una carta del mismo tipo y ponla en tu mano.").get("ok", false), false)
	# "de tu mano o Cementerio" sigue en su patrón (no es solo de la mano).
	check("no compila: de tu mano o Cementerio",
		EffectCompilerScript.compile_clause("Una vez por turno, puedes Desterrar una carta de tu mano o Cementerio para Desterrar una carta oponente de coste 3 o menos.").get("ok", false), false)
