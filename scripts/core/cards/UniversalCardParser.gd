extends Node
## UniversalCardParser - Parsea textos de habilidades a objetos Action ejecutables
## Maneja conectores (Luego, Y, O), ventanas de respuesta, y resolución de cadenas

# =============================================================================
# SEÑALES
# =============================================================================
signal parsing_completed(card_name: String, actions: Array)
signal chain_resolution_started(actions: Array)
signal chain_resolution_completed(results: Array)
signal action_resolved(action: Dictionary, result: Dictionary)
signal response_window_requested(card_data: Dictionary, pending_actions: Array)

# =============================================================================
# ENUMS
# =============================================================================
enum ActionType {
	DRAW,           # Robar cartas
	MILL,           # Botar del mazo al cementerio
	DISCARD,        # Descartar de la mano
	DESTROY,        # Destruir carta en juego
	BANISH,         # Desterrar carta
	SEARCH,         # Buscar en zona
	DAMAGE,         # Infligir daño
	BUFF,           # Aumentar stats
	DEBUFF,         # Reducir stats
	HEAL,           # Curar/recuperar vida
	RETURN_HAND,    # Devolver a la mano
	RETURN_DECK,    # Devolver al mazo
	REVEAL,         # Revelar cartas
	LOOK,           # Mirar cartas (privado)
	SHUFFLE,        # Barajar mazo
	TAP,            # Girar carta
	UNTAP,          # Enderezar carta
	CREATE_TOKEN,   # Crear token
	COPY,           # Copiar carta/efecto
	COUNTER,        # Contrarrestar/anular
	MOVE,           # Mover carta de zona
	GOLD,           # Generar oro virtual
	SILENCE,        # Quitar todas las keywords/habilidades de una carta
	PREVENT_DAMAGE, # Prevenir daño futuro
	CUSTOM          # Efecto personalizado
}

enum Connector {
	NONE,           # Sin conector (primera acción)
	Y,              # Y - siempre continúa
	LUEGO,          # Luego - requiere éxito previo
	O,              # O - continúa si anterior falló
	EN_MEDIDA       # En medida de lo posible - ejecución parcial OK
}

## Tipo de coste de habilidad activada
enum CostType {
	NONE,           # Sin coste identificado (no es activada)
	ONCE_PER_TURN,  # Una vez por turno
	GOLD,           # Paga X Oro
	DISCARD,        # Descarta una carta
	TAP,            # Gira esta carta
	SELF_AS_GOLD,   # "Pagar este Oro" — la propia carta se gasta como Oro (p.ej. Tyet)
	SELF_BANISH,    # "Puedes Desterrarlo" — la propia carta se destierra como costo (p.ej. Legión Paladín, Ramón Freire)
	SELF_TO_DECK_BOTTOM, # "Puedes poner esta ... carta(s) en el fondo de tu Castillo" — la propia carta (+ otra) al fondo del mazo como costo (p.ej. Tyet)
	SELF_SHUFFLE,   # "Barajar esta carta desde tu mano/Barajarla" — la propia carta se baraja de vuelta al Castillo como costo (p.ej. Sacrificio Solar, skofnung)
	SELF_CONVERT,   # "Puedes convertirlo/la en un Oro sin habilidad" — la propia carta se convierte como costo (p.ej. Perla de Sangre)
	SELF_DISCARD,   # "Puedes Descartarlo/Descartarla" — la propia carta se descarta como costo (p.ej. Sumi)
	SELF_DESTROY,   # "Puedes Destruir esta Arma" — la propia carta se destruye como costo (p.ej. Lanza Argenta)
	EFFECT_COST,    # "Puedes <coste> para <efecto>" con un coste que entiende EffectCompiler.COST_PIECES (lo paga el intérprete, p.ej. hem hem real: "subir este Oro a tu mano")
}

enum TargetType {
	SELF,           # El jugador que controla la carta
	OPPONENT,       # El oponente
	BOTH,           # Ambos jugadores
	CARD_SELF,      # La carta misma
	CARD_TARGET,    # Carta objetivo (selección)
	CARD_ALL,       # Todas las cartas (de un tipo/zona)
	CARD_RANDOM,    # Carta aleatoria
	ZONE            # Una zona específica
}

# Patrones de objetivo
const TARGET_PATTERNS = {
	"opponent": ["el oponente", "tu oponente", "oponente", "rival"],
	"self": ["tú", "tu ", "robas", "buscas", "descartas"],
	"all": ["todas las", "todos los", "cada"],
	"random": ["al azar", "aleatoria", "aleatorio"]
}

# =============================================================================
# WORD_TO_INT — Conversión de números escritos a enteros
# Usado por extract_action() y _parse_amount() para cubrir las 2000 cartas.
# =============================================================================
const WORD_TO_INT: Dictionary = {
	"cero": 0,
	"un": 1,  "uno": 1,  "una": 1,
	"dos": 2,
	"tres": 3,
	"cuatro": 4,
	"cinco": 5,
	"seis": 6,
	"siete": 7,
	"ocho": 8,
	"nueve": 9,
	"diez": 10,
	"once": 11,
	"doce": 12,
	"todas": -1, "todos": -1, "all": -1,
}

# =============================================================================
# ABILITY_PATTERNS — Compilador Fase 1
# Mapa canónico: Regex → Función de Manager
# Cada entrada asocia un patrón de texto con el manager y método que lo ejecuta.
# Usado por parse_abilities() para compilar texto natural a GameAction ejecutables.
# =============================================================================
const ABILITY_PATTERNS: Dictionary = {
	"DRAW": {
		"regex":        "roba (\\d+) cartas?|roba una carta",
		"manager_path": "/root/ActionModule",
		"method":       "draw",
		"action_type":  ActionType.DRAW,
		"group_amount": 1,
	},
	"MILL": {
		"regex":        "bota (\\d+) cartas? del mazo|bota las (\\d+) primeras",
		"manager_path": "/root/ActionModule",
		"method":       "mill",
		"action_type":  ActionType.MILL,
		"group_amount": 1,
	},
	"DISCARD": {
		"regex":        "descarta (\\d+|una?) cartas?|descarta una carta|descarta al azar",
		"manager_path": "/root/ActionModule",
		"method":       "discard",
		"action_type":  ActionType.DISCARD,
		"group_amount": 1,
	},
	"DESTROY": {
		"regex":        "destruye (\\d+|una?|todas?)|destruir (\\d+|una?|todas?)",
		"manager_path": "/root/ActionModule",
		"method":       "destroy",
		"action_type":  ActionType.DESTROY,
		"group_amount": 1,
	},
	"BANISH": {
		"regex":        "destierra (\\d+|una?|todas?)|desterrar (\\d+|una?)",
		"manager_path": "/root/ActionModule",
		"method":       "banish",
		"action_type":  ActionType.BANISH,
		"group_amount": 1,
	},
	"SEARCH": {
		# Regex amplio solo para DETECTAR que hay una búsqueda — el detalle
		# (zona, tipo de carta, cantidad, si se puede jugar) lo extrae
		# TriggerSystem._execute_targeted_search() releyendo el texto
		# completo de la carta, no este único grupo de captura.
		"regex":        "busca (?:\\d+|una?|un) (?:cartas?|aliados?|talismanes?|talisman|tótems?|totems?|armas?|oros?)|busca en (?:tu|un|el) (?:mazo|castillo|cementerio)",
		"manager_path": "/root/ActionModule",
		"method":       "search",
		"action_type":  ActionType.SEARCH,
		"group_amount": 0,
	},
	"SHUFFLE": {
		"regex":        "baraja(?: el mazo| en el mazo)?",
		"manager_path": "/root/ActionModule",
		"method":       "shuffle_deck",
		"action_type":  ActionType.SHUFFLE,
		"group_amount": 0,
	},
	"DAMAGE": {
		"regex":        "inflige (\\d+) de daño|hace (\\d+) de daño|recibe (\\d+) de daño",
		"manager_path": "/root/DamageManager",
		"method":       "apply_damage",
		"action_type":  ActionType.DAMAGE,
		"group_amount": 1,
	},
	"BUFF": {
		# Los Aliados tienen un único indicador de Fuerza (que también es su
		# vida/resistencia) — no hay par ataque/defensa como en otros CCG.
		"regex":        "(?:obtiene|gana) \\+(\\d+)(?: de fuerza)?",
		"manager_path": "/root/ContinuousEffectManager",
		"method":       "register_modifier",
		"action_type":  ActionType.BUFF,
		"group_amount": 1,
	},
	"DEBUFF": {
		"regex":        "obtiene -(\\d+)(?: de fuerza)?",
		"manager_path": "/root/ContinuousEffectManager",
		"method":       "register_modifier",
		"action_type":  ActionType.DEBUFF,
		"group_amount": 1,
	},
	"RETURN_HAND": {
		"regex":        "devuelve a la mano|regresa a la mano|vuelve a tu mano",
		"manager_path": "/root/ActionModule",
		"method":       "return_to_hand",
		"action_type":  ActionType.RETURN_HAND,
		"group_amount": 0,
	},
	"RETURN_DECK": {
		"regex":        "devuelve al mazo|pon en el fondo del mazo",
		"manager_path": "/root/ActionModule",
		"method":       "return_to_deck",
		"action_type":  ActionType.RETURN_DECK,
		"group_amount": 0,
	},
	"GOLD": {
		# Cantidad en dígito o palabra ('un', 'dos'...) y el calificador opcional 'por el turno' /
		# 'virtual(es)' (p.ej. Lobo Sagrado: "Cuando ataques, genera un Oro por el turno"). Se ejecuta en
		# TargetedEffectExecutor.execute_parsed_action() (case "GOLD"), no vía manager_path/method
		# (GoldManager no es autoload).
		"regex":        "(?:genera|añade) (\\w+) oros?(?: virtuales?)?(?: por el turno)?",
		"manager_path": "",
		"method":       "",
		"action_type":  ActionType.GOLD,
		"group_amount": 1,
	},
	"LOOK": {
		"regex":        "mira[s]? (\\d+|una|dos|tres|cuatro|cinco|seis|siete|ocho) cartas? del tope",
		"manager_path": "/root/CardManager",
		"method":       "get_deck",
		"action_type":  ActionType.LOOK,
		"group_amount": 1,
	},
	"REVEAL": {
		"regex":        "(?:revela|muestra)[s]? (\\d+|una|dos|tres|cuatro|cinco|seis|siete|ocho) cartas? del tope",
		"manager_path": "/root/CardManager",
		"method":       "get_deck",
		"action_type":  ActionType.REVEAL,
		"group_amount": 1,
	},
	"SILENCE": {
		# "Silenciar" no es un término de Mitos y Leyendas — es solo el nombre
		# interno (KeywordManager.silence_card/is_silenced). El texto real de
		# carta dice "pierde su habilidad" (DAR), no "es silenciada".
		"regex":        "pierde su habilidad|pierde todas sus habilidades|no tiene habilidades ni palabras clave",
		"manager_path": "/root/KeywordManager",
		"method":       "silence_card",
		"action_type":  ActionType.SILENCE,
		"group_amount": 0,
	},
	"PREVENT_DAMAGE": {
		"regex":        "previene[s]? (\\d+) de daño",
		"manager_path": "/root/DamageManager",
		"method":       "add_damage_prevention",
		"action_type":  ActionType.PREVENT_DAMAGE,
		"group_amount": 1,
	},
	"ANNUL": {
		# Palabras reutilizadas de TargetSelector._text_contains_annul()/
		# _text_contains_cancel() (líneas ~272-287) — mismo vocabulario que ya
		# usa el sistema de contra-magia de bajo nivel, aquí conectado a una
		# resolución directa (sin ventana de respuesta, ver plan de alcance).
		# Destino por defecto: Cementerio (destroy) — solo va a Destierro
		# (banish) si el propio texto de la carta lo dice explícitamente.
		"regex":        "(?:anula|anular|cancela|cancelar|contrarresta) (?:a )?(?:un|el) aliado",
		"manager_path": "/root/ActionModule",
		"method":       "destroy",
		"action_type":  ActionType.COUNTER,
		"group_amount": 0,
	},
}

# Frases de Trigger canónicas → nombre de evento interno
const TRIGGER_EVENTS: Dictionary = {
	"cuando entra":      "ENTER",
	"al entrar":         "ENTER",
	"al salir":          "EXIT",
	"cuando sale":       "EXIT",
	# "Una vez en tu turno, cuando este u otro de tus Aliados salga del juego" (Vlad el Empalador):
	# disparada, no un botón.
	"salga del juego":   "EXIT",
	"al atacar":         "ATTACK",
	"cuando ataca":      "ATTACK",
	"al bloquear":       "BLOCK",
	# "al morir" no es terminología del juego: para DIE queda "cuando es destruida".
	"cuando es destruida": "DIE",
	"al comienzo de":    "TURN_START",
	"al inicio de":      "TURN_START",
	"al final del turno": "TURN_END",
}

# =============================================================================
# TURN REGISTRY — Registro de habilidades de "Una vez por turno"
# =============================================================================
class TurnRegistry:
	## Registra qué habilidades "Una vez por turno" ya se usaron.
	## Clave: "card_id|ability_index|turn_number"
	var _used: Dictionary = {}  # clave -> cantidad de usos en ese turno

	func register(card_id: String, ability_index: int, turn: int) -> void:
		var key := "%s|%d|%d" % [card_id, ability_index, turn]
		_used[key] = int(_used.get(key, 0)) + 1

	## Cuántas veces se usó en ese turno ("Hasta dos veces por turno").
	func use_count(card_id: String, ability_index: int, turn: int) -> int:
		return int(_used.get("%s|%d|%d" % [card_id, ability_index, turn], 0))

	## ¿Ya agotó sus usos del turno? 'limit' = uses_per_turn de la habilidad.
	func is_exhausted(card_id: String, ability_index: int, turn: int, limit: int = 1) -> bool:
		return use_count(card_id, ability_index, turn) >= maxi(1, limit)

	func register_ability_use(source_card: Node, ability: Dictionary) -> void:
		"""Envoltorio de register() que saca ability_index/turno y usa el instance_id de source_card como
		clave. instance_id y no card_data.id (compartido por todas las copias): cada copia física
		tiene su propio cupo de "una vez por turno"."""
		var card_id: String = str(source_card.get_instance_id())
		var ability_index: int = ability.get("ability_index", 0)
		register(card_id, ability_index, GameManager.turn_serial)

	func was_used(card_id: String, ability_index: int, turn: int) -> bool:
		return _used.has("%s|%d|%d" % [card_id, ability_index, turn])

	func reset_for_turn(turn: int) -> void:
		"""Limpia las entradas del turno anterior al comenzar un turno nuevo."""
		var to_remove: Array = []
		for key: String in _used:
			if key.ends_with("|%d" % (turn - 1)):
				to_remove.append(key)
		for key in to_remove:
			_used.erase(key)

	func clear_all() -> void:
		_used.clear()


# =============================================================================
# REFERENCIAS
# =============================================================================
## Registro de usos "Una vez por turno" — compartido con ActionPipeline
var turn_registry: TurnRegistry = TurnRegistry.new()


func _ready() -> void:
	call_deferred("_connect_signals")


func _connect_signals() -> void:
	# Resetear TurnRegistry al inicio de cada turno nuevo
	if not GameManager.turn_started.is_connected(_on_turn_started_reset_registry):
		GameManager.turn_started.connect(_on_turn_started_reset_registry)


func _on_turn_started_reset_registry(_player_id: int, _turn_number: int) -> void:
	# turn_serial: el registro cuenta turnos de jugador, no rondas.
	turn_registry.reset_for_turn(GameManager.turn_serial)


func _parse_amount(amount_str: String) -> int:
	"""Parsea una cantidad del texto usando WORD_TO_INT.
	Soporta dígitos ('3'), palabras ('tres') y totales ('todas' → -1).
	"""
	if amount_str.is_valid_int():
		return int(amount_str)
	return WORD_TO_INT.get(amount_str.to_lower(), 1)


func _detect_target(text: String) -> TargetType:
	"""Detecta el objetivo de la acción"""
	var lower = text.to_lower()

	for pattern in TARGET_PATTERNS.opponent:
		if pattern in lower:
			return TargetType.OPPONENT

	for pattern in TARGET_PATTERNS.all:
		if pattern in lower:
			return TargetType.CARD_ALL

	for pattern in TARGET_PATTERNS.random:
		if pattern in lower:
			return TargetType.CARD_RANDOM

	return TargetType.SELF


# =============================================================================
# PARSE_ABILITIES — Compilador Fase 1 (entrada pública unificada)
# =============================================================================
static var _event_phrases: Array = []


## ¿Es un disparador por evento con handler propio (no un botón de habilidad activada)?
static func _is_event_sentence(lower_s: String) -> bool:
	if _event_phrases.is_empty():
		for e in load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").ENTRIES:
			_event_phrases.append(e[0])
		var ally_events = load("res://scripts/core/effects/triggers/AllyEventTriggers.gd")
		_event_phrases.append_array([ally_events.OGUN, ally_events.TROLL,
			load("res://scripts/core/effects/triggers/CemeteryTriggers.gd").ESCUDO,
			"cuando tu oponente juegue una carta, hasta tres veces por turno, el bota dos cartas",  # Dhampir
			"cuando se resuelva el efecto de uno de tus talismanes sello",  # Los Siete Sellos (GoldManager)
			"cuando ataque solo, puedes desterrarlo para que tu oponente"])  # uriko-hime (AttackPatterns)
	var t: String = load("res://scripts/core/effects/triggers/CemeteryTriggers.gd").normalize(lower_s)
	for ph in _event_phrases:
		if ph in t:
			return true
	return false


static func _has_compiled_cost(sentence: String) -> bool:
	"""'Puedes <coste> para <efecto>' (sin disparador) con un coste de EffectCompiler.COST_PIECES: es una
	activada propia, no la continuación de la anterior (hem hem real: "Puedes subir este Oro a tu mano
	para Robar dos cartas...")."""
	var norm: String = EffectCompiler.normalize(sentence)
	if not norm.begins_with("puedes ") or not (" para " in norm):
		return false
	var costs: Dictionary = EffectCompiler._parse_costs(norm.substr(7))
	if costs.is_empty():
		return false
	# Coste alternativo al jugarla ("para reducir su coste en dos Oros", "para jugarlo desde tu
	# Cementerio": lo aplica el pago) y prevenciones reactivas ("para prevenir que...":
	# EffectController._prevention_registry) no son botones.
	for alt in ["reducir su coste", "jugarlo", "jugarla", "jugar este", "jugar esta", "prevenir"]:
		if str(costs.rest).begins_with(alt):
			return false
	return true


static func _fold_usage_qualifiers(raw: PackedStringArray) -> Array:
	"""Oraciones que solo limitan la habilidad anterior, no son habilidades (si no, quedaba un botón
	que no hacía nada):
	- "Sólo puedes utilizar esta habilidad de Belial una vez por turno": la oración anterior pasa a
	  empezar con "Una vez por turno, " (Belial: "Puedes Botar dos cartas para subirlo de tu
	  Cementerio a tu mano" queda como activada una vez por turno). Si la anterior ya dice "por
	  turno" se deja igual.
	- "Puedes utilizar esta habilidad más de una vez por turno" (brown bess, Llave del Abismo): se
	  descarta; la anterior no tiene límite."""
	var out: Array = []
	for s: String in raw:
		var low := s.strip_edges().to_lower()
		if low.begins_with("puedes utilizar esta habilidad m") and "de una vez por turno" in low:
			continue
		if (low.begins_with("sólo puedes utilizar esta habilidad") or low.begins_with("solo puedes utilizar esta habilidad")) \
				and low.ends_with("una vez por turno") and not out.is_empty():
			var prev: String = str(out[-1]).strip_edges()
			# Un disparador ("Cuando Destierres cartas..., puedes jugar este Aliado", el horla) no pasa a
			# activada: el límite lo lleva quien lo dispara.
			if not ("por turno" in prev.to_lower()) and not prev.to_lower().begins_with("cuando"):
				out[-1] = "Una vez por turno, " + prev.substr(0, 1).to_lower() + prev.substr(1)
			continue
		out.append(s)
	return out


# parse_abilities() es lo que usa CardInspectionLayer para los botones de habilidad activada.
func parse_abilities(text: String, card_id: String = "") -> Array[Dictionary]:
	"""Compilador Fase 1: analiza el texto de una carta y devuelve habilidades estructuradas.
	
	Divide el texto por puntos y clasifica cada oración:
	- TRIGGER: se activa sola por un evento ("Cuando entra", "Al atacar"...).
	- ACTIVATED: el jugador la activa desde el Zoom (tiene coste o "Una vez por turno").
	
	Flags:
	- is_optional: contiene "Puedes". En ACTIVATED no pide confirmación aparte (el botón ya lo es);
	en TRIGGER el declinar lo ofrece el can_cancel del SelectionManager que abre
	TriggerResolution/LookAndPlayResolver.
	- once_per_turn: "Una vez por turno"; se registra en TurnRegistry. uses_per_turn: "Hasta
	dos/tres veces por turno".
	- once_per_turn_own_turn_only: "una vez EN tu/su turno": además solo en tu turno normal, nunca
	en una ventana anidada (arquitectura.md §10.11; CardInspectionLayer oculta el botón).
	
	Cada elemento: {raw_text, ability_type, trigger_event, cost_text, cost_type, cost_amount,
	effect_text, actions, is_optional, once_per_turn, once_per_turn_own_turn_only, uses_per_turn,
	ability_index, card_id, manager_path, method}"""
	var result: Array[Dictionary] = []
	if text.is_empty():
		return result

	var ability_index := 0

	for raw_sentence: String in _fold_usage_qualifiers(text.split(".")):
		var sentence: String = raw_sentence.strip_edges()
		if sentence.is_empty():
			continue

		var lower_s: String = sentence.to_lower()

		# ── Continuación encadenada ("Luego, busca...") ────────────────────────
		# Una oración que empieza con Luego/Después/A continuación/Entonces no es una habilidad nueva: se
		# concatena a la última entrada (p.ej. Don de Amma: "...puedes Desterrar un Oro con habilidad de
		# tu Reserva. Luego, busca un Oro en tu Castillo y ponlo en tu Reserva."). Si no, se perdía en
		# silencio.
		var is_luego_continuation: bool = false
		for connector_word: String in ["luego,", "después,", "a continuación,", "entonces,"]:
			if lower_s.begins_with(connector_word):
				is_luego_continuation = true
				break
		if is_luego_continuation and not result.is_empty():
			var prev: Dictionary = result[result.size() - 1]
			prev["raw_text"]    = "%s. %s" % [prev.get("raw_text", ""), sentence]
			prev["effect_text"] = "%s. %s" % [prev.get("effect_text", ""), sentence]
			continue

		# ── Flags globales de la oración ──────────────────────────────────────
		var is_optional:   bool = "puedes" in lower_s
		# "una vez EN tu/su turno" (p.ej. Padre de la Patria) es una tercera variante de esta cláusula.
		var once_per_turn: bool = ("una vez por turno" in lower_s
			or "una vez al turno" in lower_s
			or "una vez en tu turno" in lower_s
			or "una vez en su turno" in lower_s)
		# "una vez EN tu/su turno" restringe CUÁNDO (arquitectura.md §10.11): "una vez por turno" /
		# "puedes" = en tu turno normal y en cualquier ventana de prioridad abierta; "una vez EN tu turno"
		# = solo en tu turno normal, nunca en una ventana anidada, aunque pueda Anular/Cancelar (p.ej.
		# paladín bestiarium: la restricción explícita pesa más que la convención de respuesta
		# instantánea).
		var once_per_turn_own_turn_only: bool = ("una vez en tu turno" in lower_s
			or "una vez en su turno" in lower_s)
		# "Hasta dos/tres veces por turno": mismo registro, con más usos (TurnRegistry.is_exhausted).
		var uses_per_turn := 1
		if "hasta dos veces por turno" in lower_s or "dos veces por turno" in lower_s:
			uses_per_turn = 2
		elif "hasta tres veces por turno" in lower_s or "tres veces por turno" in lower_s:
			uses_per_turn = 3
		if uses_per_turn > 1:
			once_per_turn = true

		# "Sólo puedes utilizar la habilidad de X una vez por turno" (p.ej. Ramón Freire): oración de
		# cierre que reafirma la restricción de la habilidad anterior, no una habilidad nueva (si no,
		# quedaba un botón espurio).
		var is_once_per_turn_qualifier_only: bool = once_per_turn and (
			"solo puedes utilizar la habilidad" in lower_s
			or "sólo puedes utilizar la habilidad" in lower_s
			or "solo puedes usar esta habilidad" in lower_s
			or "sólo puedes usar esta habilidad" in lower_s
			# Variante "Sólo puedes utilizar ESTA habilidad de X una vez por turno" (p.ej. Cuervo Nocturno).
			or "solo puedes utilizar esta habilidad" in lower_s
			or "sólo puedes utilizar esta habilidad" in lower_s
		)
		if is_once_per_turn_qualifier_only and not result.is_empty():
			var prev_qual: Dictionary = result[result.size() - 1]
			prev_qual["once_per_turn"] = true
			prev_qual["uses_per_turn"] = uses_per_turn
			if once_per_turn_own_turn_only:
				prev_qual["once_per_turn_own_turn_only"] = true
			continue

		# ── Detectar Trigger ──────────────────────────────────────────────────
		var trigger_event: String = ""
		for phrase: String in TRIGGER_EVENTS:
			if phrase in lower_s:
				trigger_event = TRIGGER_EVENTS[phrase]
				break

		# ── Detectar Costo (para ACTIVATED) ───────────────────────────────────
		var cost_type:   int    = CostType.NONE
		var cost_amount: int    = 0
		var cost_text:   String = ""
		var effect_text: String = sentence

		# "Puedes pagarlo..." (Tyet: "Puedes pagarlo para que...", con pronombre): la carta se paga a sí
		# misma como Oro.
		var pays_self_as_gold: bool = ("pagar este oro" in lower_s or "pagar esta carta" in lower_s
			or "puedes pagarlo" in lower_s)
		# "Puedes Desterrarlo/Desterrarla..." (Legión Paladín, Ramón Freire; Estaca en femenino): coste de
		# autodesterrarse, sin "una vez por turno" ni ':'.
		var pays_self_banish: bool = "puedes desterrarlo" in lower_s or "puedes desterrarla" in lower_s
		# "Puedes poner esta y otra carta de tu mano en el fondo de tu Castillo..." (Tyet): coste de
		# mandar esta carta (+ otra) al fondo del mazo.
		var pays_self_to_deck_bottom: bool = "poner esta" in lower_s and "fondo de tu castillo" in lower_s
		# "Barajar esta carta desde tu mano" / "Barajarla de tu mano" / "Barajarla" (Sacrificio Solar:
		# "Puedes pagar un Oro y Barajar esta carta desde tu mano para..."; skofnung).
		var pays_self_shuffle: bool = ("barajar esta carta" in lower_s and "mano" in lower_s) \
			or "barajarla de tu mano" in lower_s or "puedes barajarla" in lower_s
		# "Puedes convertirlo/la en un Oro sin habilidad para..." (Perla de Sangre): su propia entrada
		# ACTIVATED; si no, se fusionaba como continuación de la primera habilidad.
		var pays_self_convert: bool = "convertirlo en un oro sin habilidad" in lower_s \
			or "convertirla en un oro sin habilidad" in lower_s
		# "Puedes Barajarlo..." (Tótem del Dragón Ancestral): variante masculina de pays_self_shuffle.
		var pays_self_shuffle_masc: bool = "puedes barajarlo" in lower_s
		# "Puedes Descartarlo/Descartarla..." (Sumi): coste de autodescartarse, como pays_self_banish.
		var pays_self_discard_self: bool = "puedes descartarlo" in lower_s or "puedes descartarla" in lower_s
		# "Puedes Destruir esta Arma..." (Lanza Argenta): coste de autodestruirse.
		var pays_self_destroy: bool = "puedes destruir esta arma" in lower_s
		# "Puedes pagar un/N Oro(s) para..." sin ':' (Sandraudiga, Visión Heroica): se paga Oro genérico
		# de la Reserva como costo; la variante con ':' ya la cubre el formato normal. Distinto de
		# pays_self_as_gold (la carta se paga a sí misma).
		# También: habilidad de Vigilia sin coste con condición (Patria Vieja: "En tu Vigilia, si no has
		# puesto Oros en juego este turno, puedes mirar...") y la que la carta gana en el Cementerio
		# (Duelo Espacial: "gana la habilidad 'En tu Vigilia, puedes Robar una carta'"). Solo la variante
		# "puedes mirar...": las otras con esa condición (Fuente de Ladurum, Karesansui, Corazón de
		# Dragón...) son "ponerlo desde tu mano o Cementerio en tu Reserva", otra mecánica.
		var vigilia_no_gold_yet: bool = "si no has puesto oros en juego este turno" in lower_s \
			and "puedes mirar las primeras" in lower_s
		var cemetery_granted: bool = "en tu cementerio" in lower_s and "gana la habilidad" in lower_s and "puedes" in lower_s
		var pay_gold_rx := RegEx.new()
		pay_gold_rx.compile("puedes pagar (\\w+) oros? para")
		var m_pay_gold := pay_gold_rx.search(lower_s)

		# La habilidad que dan tundra viva / isla de gigantes a cartas del Cementerio (el costo de Desterrar las
		# otras lo paga ActivatedPatterns; la carta sale del Cementerio al usarla).
		var granted_by_tundra_isla: bool = lower_s.begins_with("destierra dos cartas de tu cementerio para subirlo") 			or lower_s.begins_with("destierra tres cartas de tu cementerio para jugarlo")
		if once_per_turn or vigilia_no_gold_yet or cemetery_granted or granted_by_tundra_isla:
			cost_type = CostType.ONCE_PER_TURN
		elif pays_self_as_gold:
			cost_type = CostType.SELF_AS_GOLD
		elif pays_self_banish:
			cost_type = CostType.SELF_BANISH
		elif pays_self_to_deck_bottom:
			cost_type = CostType.SELF_TO_DECK_BOTTOM
		elif pays_self_shuffle:
			cost_type = CostType.SELF_SHUFFLE
		elif pays_self_convert:
			cost_type = CostType.SELF_CONVERT
		elif pays_self_shuffle_masc:
			cost_type = CostType.SELF_SHUFFLE
		elif pays_self_discard_self:
			cost_type = CostType.SELF_DISCARD
		elif pays_self_destroy:
			cost_type = CostType.SELF_DESTROY
		elif m_pay_gold:
			cost_type = CostType.GOLD
			cost_amount = _parse_amount(m_pay_gold.get_string(1))
		elif trigger_event == "" and _has_compiled_cost(sentence):
			cost_type = CostType.EFFECT_COST
		elif ":" in sentence:
			var colon_pos: int = sentence.find(":")
			cost_text   = sentence.substr(0, colon_pos).strip_edges()
			effect_text = sentence.substr(colon_pos + 1).strip_edges()
			var lower_cost: String = cost_text.to_lower()
			if "paga" in lower_cost and ("oro" in lower_cost or "oros" in lower_cost):
				cost_type = CostType.GOLD
				var rx := RegEx.new()
				rx.compile("(\\d+)")
				var m := rx.search(lower_cost)
				cost_amount = int(m.get_string(1)) if m else 1
			elif "descarta" in lower_cost:
				cost_type   = CostType.DISCARD
				cost_amount = 1
			elif "girar" in lower_cost or "gira" in lower_cost or "tapa" in lower_cost:
				cost_type = CostType.TAP

		# ── Determinar tipo de habilidad ──────────────────────────────────────
		# Reglas estáticas que no son una habilidad que se activa (el mandinga, mi-go: "Exhumar"; flechar
		# xoon: "El portador gana..."; duque glauru: "Sólo puedes utilizar la habilidad..."; Tablas del
		# Juramento, Diente de Dragón, huevos de oro: "No se puede..." / "Cada jugador sólo puede..."): sin esto
		# salía un botón que no hacía nada.
		var static_rule_start := false
		for rule_start in ["exhumar", "el portador ", "sólo puedes utilizar", "solo puedes utilizar", "no se puede",
				"cada jugador sólo puede", "cada jugador solo puede"]:
			if lower_s.strip_edges().begins_with(rule_start):
				static_rule_start = true
		if static_rule_start and trigger_event == "":
			ability_index += 1
			continue
		# "(Hasta N veces) por turno, cuando <evento>, ..." que se resuelven por evento (LimitedEventTriggers,
		# AllyEventTriggers, CemeteryTriggers, VampirePatterns): disparadas, no un botón.
		if trigger_event == "" and _is_event_sentence(lower_s):
			trigger_event = "EVENT"
		var ability_type: String
		if trigger_event != "":
			ability_type = "TRIGGER"
		elif cost_type != CostType.NONE:
			ability_type = "ACTIVATED"
		else:
			# Oración sin coste ni trigger propio: si no es una regla estática/pasiva
			# y viene justo después de una habilidad ACTIVADA abierta, es su continuación
			# (p.ej. Tesoro de los Césares: "Una vez por turno... nombrar una carta. Esa carta cuesta...").
			var is_static_rule := lower_s.begins_with("no se puede") or lower_s.begins_with("los aliados") \
				or lower_s.begins_with("tus aliados") or lower_s.begins_with("los talismán") \
				or lower_s.begins_with("las armas") or lower_s.begins_with("los tótem") \
				or lower_s.begins_with("juega mostrando") or lower_s.begins_with("mientras controles") \
				or lower_s.begins_with("mientras esté en juego") or lower_s.begins_with("gana ") \
				or lower_s.begins_with("pierde ") or lower_s.begins_with("no puede ser ")
			# Otra habilidad, no la continuación de la activada (simurg: "...a tu mano. Cuando sea Destruido,
			# ..."): un disparador o una regla de zona.
			for other_start in ["cuando ", "al comienzo", "al final", "en tu fase final", "en la fase final",
					"si está en tu", "si esta en tu", "sólo puedes", "solo puedes"]:
				if lower_s.begins_with(other_start):
					is_static_rule = true

			if not is_static_rule and not result.is_empty() and result[result.size() - 1].get("ability_type", "") == "ACTIVATED":
				var prev_open: Dictionary = result[result.size() - 1]
				prev_open["raw_text"]    = "%s. %s" % [prev_open.get("raw_text", ""), sentence]
				prev_open["effect_text"] = "%s. %s" % [prev_open.get("effect_text", ""), sentence]
				continue
			# Oración sin coste ni trigger → no es habilidad activada reconocida
			# (puede ser texto de reglas pasivo o palabra clave)
			ability_index += 1
			continue

		# ── Detectar acciones usando ABILITY_PATTERNS ─────────────────────────
		var actions: Array[Dictionary] = []
		var matched_manager_path: String = ""
		var matched_method:       String = ""
		var scan_text: String = effect_text.to_lower()

		for action_key: String in ABILITY_PATTERNS:
			var entry: Dictionary = ABILITY_PATTERNS[action_key]
			var rx := RegEx.new()
			rx.compile("(?i)" + entry["regex"])
			var m := rx.search(scan_text)
			if not m:
				continue

			var amount := 1
			var grp: int = entry["group_amount"]
			if grp > 0 and m.get_group_count() >= grp:
				var gs: String = m.get_string(grp)
				amount = _parse_amount(gs) if not gs.is_valid_int() else int(gs)

			if matched_manager_path.is_empty():
				matched_manager_path = entry["manager_path"]
				matched_method       = entry["method"]

			actions.append({
				"action_key":   action_key,
				"action_type":  entry["action_type"],
				"amount":       amount,
				"manager_path": entry["manager_path"],
				"method":       entry["method"],
				"target":       _detect_target(scan_text),
				"raw_text":     effect_text,
			})
			break  # una acción principal por oración

		# Errata retroactiva de Cuervo Nocturno/Tyet: la última impresión de "Puedes poner esta y otra
		# carta de tu mano en el fondo de tu Castillo y Robar dos cartas" agrega "Sólo puedes utilizar
		# esta habilidad de [Nombre] una vez por turno". En Mitos y Leyendas la versión más reciente rige
		# para todas las impresiones, así que se fuerza el límite aquí.
		var effective_once_per_turn: bool = once_per_turn or pays_self_to_deck_bottom or vigilia_no_gold_yet
		result.append({
			"raw_text":      sentence,
			"ability_type":  ability_type,
			"trigger_event": trigger_event,
			"cost_text":     cost_text,
			"cost_amount":   cost_amount,
			"cost_type":     cost_type,
			"effect_text":   effect_text,
			"actions":       actions,
			"is_optional":   is_optional,
			"once_per_turn": effective_once_per_turn,
			"uses_per_turn": uses_per_turn,
			"once_per_turn_own_turn_only": once_per_turn_own_turn_only,
			"ability_index": ability_index,
			"card_id":       card_id,
			"manager_path":  matched_manager_path,
			"method":        matched_method,
		})
		ability_index += 1

	return result


# =============================================================================
# EXTRACT_ACTION — Extractor de Acción (Compilador Fase 1)
# Punto de entrada rápido para obtener la primera acción ejecutable de un texto.
# Usado por TriggerSystem al resolver ETB y por debug en tiempo real.
# =============================================================================

## Regex de robo canónico: "Roba dos cartas", "Robas 3 cartas", "Roba hasta tres cartas"
## (Mecha-Daikaiju; "hasta N" se trata como N: nunca conviene robar menos).
const DRAW_REGEX: String = "(?:Roba|Robas)\\s+(?:hasta\\s+)?(una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|\\d+)\\s+cartas?"


func extract_action(text: String) -> Dictionary:
	"""Ver _extract_action_impl(). Agrega "source_text" (el texto analizado), para que la búsqueda
	genérica no relea el texto completo de la carta (Akari Musashi: encontraba "oponente" en otra
	habilidad y buscaba en el Castillo rival)."""
	var action := _extract_action_impl(text)
	if action.get("matched", false):
		action["source_text"] = text
	return action


func _extract_action_impl(text: String) -> Dictionary:
	"""Extrae la primera acción reconocida del texto de una habilidad.

	Prioridad:
	  0. Patrones compuestos "puedes [costo] y Roba N" (SHUFFLE_FOR_DRAW,
	     PLAY_WEAPON_DISCOUNT_DRAW) — deben ir antes del robo canónico o
	     éste los captura primero (ver sección 0 abajo)
	  1. Patrón de robo canónico (DRAW_REGEX)
	  2. Resto de ABILITY_PATTERNS en orden de iteración

	Retorna un GameAction con: type, action_type, value, manager_path, method, params, raw_text.
	Si no detecta nada: {matched: false}.

	Ejemplo — Ciudad de los Césares 'Roba dos cartas':
	  → {matched: true, type: 'DRAW', value: 2, manager_path: '/root/ActionModule', method: 'draw'}
	"""
	if text.is_empty():
		return {"matched": false}

	# ── 0. Patrones compuestos "puedes [costo] y Roba N cartas" ──
	# Van antes que todo, incluido el robo canónico: si no, "Roba dos cartas" se ejecutaba suelto
	# ignorando el "puedes" y el costo (Bernardo O'Higgins, Lobo Sagrado). Necesitan varios números a
	# la vez, así que se resuelven aparte.
	var shuffle_draw_rx := RegEx.new()
	shuffle_draw_rx.compile("(?i)puedes barajar cartas? cuyos? costes? sum(?:en|an) hasta (\\w+)[^.]*?y robar? (\\w+) cartas?")
	var m_sd := shuffle_draw_rx.search(text)
	if m_sd:
		var max_sum: int = _parse_amount(m_sd.get_string(1))
		var draw_amt: int = _parse_amount(m_sd.get_string(2))
		print("[Parser] Acción detectada: SHUFFLE_FOR_DRAW | Suma máx: %d | Roba: %d" % [max_sum, draw_amt])
		return {
			"matched":      true,
			"type":         "SHUFFLE_FOR_DRAW",
			"action_type":  ActionType.CUSTOM,
			"value":        draw_amt,
			"params":       {"max_cost_sum": max_sum, "draw_amount": draw_amt},
			"raw_text":     m_sd.get_string(0),
		}

	var weapon_draw_rx := RegEx.new()
	weapon_draw_rx.compile("(?i)puedes jugar un arma desde tu mano o cementerio reduciendo su coste en (\\w+) oros?, hasta un m[ií]nimo de (\\w+)[^.]*?y robar? (\\w+) cartas?")
	var m_wd := weapon_draw_rx.search(text)
	if m_wd:
		var discount: int = _parse_amount(m_wd.get_string(1))
		var floor_val: int = _parse_amount(m_wd.get_string(2))
		var draw_amt2: int = _parse_amount(m_wd.get_string(3))
		print("[Parser] Acción detectada: PLAY_WEAPON_DISCOUNT_DRAW | Descuento: %d | Mínimo: %d | Roba: %d" % [discount, floor_val, draw_amt2])
		return {
			"matched":      true,
			"type":         "PLAY_WEAPON_DISCOUNT_DRAW",
			"action_type":  ActionType.CUSTOM,
			"value":        draw_amt2,
			"params":       {"discount": discount, "floor": floor_val, "draw_amount": draw_amt2},
			"raw_text":     m_wd.get_string(0),
		}

	# Variante con portador restringido (Zadquiel: "puedes jugar un Arma sobre este Aliado o uno
	# oponente, reduciendo su coste en un Oro, hasta un mínimo de 1"). No dice "de tu mano": también
	# Armas del Cementerio con Exhumar (no se destierran al salir: eso es solo para Talismanes).
	var weapon_on_rx := RegEx.new()
	weapon_on_rx.compile("(?i)puedes jugar un arma sobre este aliado o uno oponente,?\\s*reduciendo su coste en (\\w+) oros?,?\\s*hasta un m[ií]nimo de (\\w+)")
	var m_wo := weapon_on_rx.search(text)
	if m_wo:
		var discount3: int = _parse_amount(m_wo.get_string(1))
		var floor_val3: int = _parse_amount(m_wo.get_string(2))
		print("[Parser] Acción detectada: PLAY_WEAPON_DISCOUNT (este Aliado u oponente) | Descuento: %d | Mínimo: %d" % [discount3, floor_val3])
		return {
			"matched":      true,
			"type":         "PLAY_WEAPON_DISCOUNT",
			"action_type":  ActionType.CUSTOM,
			"value":        discount3,
			"params":       {"discount": discount3, "floor": floor_val3, "hand_only": false, "draw_amount": 0,
				"wielder": "self_or_opponent", "cemetery_needs_exhumar": true},
			"raw_text":     m_wo.get_string(0),
		}

	# Variante sin robo, solo desde la mano (p.ej. Hanta: "puedes jugar un
	# Arma de tu mano reduciendo su coste en 1 Oro, hasta un mínimo de 0").
	var weapon_hand_rx := RegEx.new()
	weapon_hand_rx.compile("(?i)puedes jugar un arma de tu mano reduciendo su coste en (\\w+) oros?,?\\s*hasta un m[ií]nimo de (\\w+)")
	var m_wh := weapon_hand_rx.search(text)
	if m_wh:
		var discount2: int = _parse_amount(m_wh.get_string(1))
		var floor_val2: int = _parse_amount(m_wh.get_string(2))
		print("[Parser] Acción detectada: PLAY_WEAPON_DISCOUNT | Descuento: %d | Mínimo: %d" % [discount2, floor_val2])
		return {
			"matched":      true,
			"type":         "PLAY_WEAPON_DISCOUNT",
			"action_type":  ActionType.CUSTOM,
			"value":        discount2,
			"params":       {"discount": discount2, "floor": floor_val2, "hand_only": true, "draw_amount": 0},
			"raw_text":     m_wh.get_string(0),
		}

	# "sube un Arma que controles a la mano de su dueño para jugar un Arma del mismo o menor coste
	# desde tu mano sin pagar su coste" (Padre de la Patria): intercambio de Armas, no descuento fijo
	# como Lobo Sagrado/Hanta.
	var weapon_swap_rx := RegEx.new()
	weapon_swap_rx.compile("(?i)subir un arma que controles a la mano de su due[ñn]o para jugar un arma del mismo o menor coste desde tu mano sin pagar su coste")
	var m_ws := weapon_swap_rx.search(text)
	if m_ws:
		print("[Parser] Acción detectada: RETURN_WEAPON_SWAP_FREE")
		return {
			"matched":      true,
			"type":         "RETURN_WEAPON_SWAP_FREE",
			"action_type":  ActionType.CUSTOM,
			"value":        0,
			"params":       {},
			"raw_text":     m_ws.get_string(0),
		}

	# "convertir un Oro o una carta de coste N o menos en una carta del mismo tipo sin habilidad" (DAR
	# Sección 8 - Convertir, Capitán O'Brien): misma carta, mismo tipo/coste/Fuerza, sin habilidad.
	# Objetivo dentro del juego (propio o enemigo), salvo que el texto diga otra cosa.
	var convert_rx := RegEx.new()
	convert_rx.compile("(?i)convertir un oro o una carta de coste (\\w+) o menos en una carta del mismo tipo sin habilidad")
	var m_cv := convert_rx.search(text)
	if m_cv:
		var max_cost: int = _parse_amount(m_cv.get_string(1))
		print("[Parser] Acción detectada: CONVERT_ORO_OR_LOW_COST | Coste máx: %d" % max_cost)
		return {
			"matched":      true,
			"type":         "CONVERT_ORO_OR_LOW_COST",
			"action_type":  ActionType.CUSTOM,
			"value":        max_cost,
			"params":       {"max_cost": max_cost},
			"raw_text":     m_cv.get_string(0),
		}

	# ── 1. Patrón de robo canónico ─────────────────────────────────────────────
	var draw_rx := RegEx.new()
	draw_rx.compile("(?i)" + DRAW_REGEX)
	var m := draw_rx.search(text)
	if m:
		var amount: int = _parse_amount(m.get_string(1))
		print("[Parser] Acción detectada: ROBA | Cantidad: %d" % amount)
		return {
			"matched":      true,
			"type":         "DRAW",
			"action_type":  ActionType.DRAW,
			"value":        amount,
			"amount":       amount,
			"manager_path": "/root/ActionModule",
			"method":       "draw",
			"params":       {"target_player": 0, "amount": amount},
			"raw_text":     m.get_string(0),
			"up_to":        "hasta" in m.get_string(0).to_lower(),
		}

	# ── 2. Resto de ABILITY_PATTERNS ───────────────────────────────────────────
	for action_key: String in ABILITY_PATTERNS:
		var entry: Dictionary = ABILITY_PATTERNS[action_key]
		var rx := RegEx.new()
		rx.compile("(?i)" + entry["regex"])
		var m2 := rx.search(text)
		if not m2:
			continue
		var amount := 1
		var grp: int = entry["group_amount"]
		if grp > 0 and m2.get_group_count() >= grp:
			amount = _parse_amount(m2.get_string(grp))
		print("[Parser] Acción detectada: %s | Cantidad: %d" % [action_key, amount])
		return {
			"matched":      true,
			"type":         action_key,
			"action_type":  entry["action_type"],
			"value":        amount,
			"amount":       amount,
			"manager_path": entry["manager_path"],
			"method":       entry["method"],
			"params":       {"amount": amount, "target_player": 0},
			"raw_text":     m2.get_string(0),
		}

	return {"matched": false}


