extends Node
## CardFactory - Convierte datos JSON en recursos Card con bloques de habilidades
## Mapea datos de la base de datos a la estructura del juego

# =============================================================================
# CONSTANTES
# =============================================================================
const CARD_SCENE_PATH = "res://scenes/cards/Card.tscn"

## Palabras clave que indican triggers
const TRIGGER_PATTERNS: Dictionary = {
	# (2026-08-28, corrección de terminología real de Mitos y Leyendas, a
	# pedido del usuario): "cuando deje/dejar/abandona el juego" no existe
	# como frase real — es "al salir del juego"/"cuando salga del
	# juego"/"cuando sale del juego". Algunas cartas mezclan ambos conceptos
	# en una sola oración ("cuando entra o salga del juego") — se agrega esa
	# frase completa a los dos, pero OJO: esto solo la CLASIFICA en el
	# primer tipo que la detecte, no dispara ambos triggers a la vez (eso
	# necesitaría lógica aparte, no implementada todavía).
	"on_enter_play": ["cuando entre al juego", "al entrar al juego", "cuando entra al juego", "al ser jugado", "cuando entra o salga del juego"],
	"on_leave_play": ["al salir del juego", "cuando salga del juego", "cuando sale del juego", "cuando entra o salga del juego"],
	# "cuando muera"/"al morir" no existen como concepto real en el juego —
	# se eliminaron (2026-08-28, a pedido del usuario).
	"on_destroyed": ["cuando sea destruido", "al ser destruido"],
	"on_discard": ["cuando descartes", "al descartar", "cuando sea descartado"],
	"on_draw": ["cuando robes", "al robar", "cada vez que robes"],
	"on_attack": ["cuando ataque", "al atacar", "cada vez que ataque"],
	"on_block": ["cuando bloquee", "al bloquear"],
	# "infligir"/"inflija"/"inflige" no es terminología real (2026-08-28) —
	# se reemplazó por "cuando haga daño de combate", la forma más común en
	# el texto real de las cartas junto a "cuando haga daño" a secas.
	"on_damage_dealt": ["cuando haga daño de combate", "cuando haga daño", "si hizo daño", "cuando hace daño"],
	# "cuando reciba daño"/"al recibir daño" no son la frase real — es
	# "cuando fueras a recibir daño" (2026-08-28, a pedido del usuario).
	"on_damage_received": ["cuando fueras a recibir daño"],
	"on_turn_start": ["al comienzo del turno", "al inicio del turno", "al comenzar tu turno"],
	"on_turn_end": ["al final del turno", "al terminar el turno", "al finalizar tu turno"],
	"on_ally_enters": ["cuando otro aliado entre", "cuando un aliado entre"],
	"on_ally_dies": ["cuando otro aliado muera", "cuando un aliado sea destruido"],
	"on_oro_placed": ["cuando pongas un oro", "al poner un oro", "cada vez que pongas un oro"],
	"on_card_played": ["cuando juegues", "al jugar una carta"],
	"on_activate": ["activa:", "activar:"],  # Habilidades activadas manualmente
}

## Palabras clave que indican costes
const COST_PATTERNS: Dictionary = {
	"pay_gold": ["paga %d oro", "paga %d de oro", "gasta %d oro"],
	"discard_cards": ["descarta %d carta", "descarta una carta", "descarta %d cartas"],
	"sacrifice": ["sacrifica", "sacrifica un aliado", "sacrifica una criatura"],
	"tap": ["gira", "gira esta carta", "gírala"],
	"exile_from_grave": ["destierra %d carta de tu cementerio", "exilia una carta de tu cementerio"],
	"life_cost": ["paga %d vida", "pierde %d vida"],
}

## Palabras clave que indican efectos/acciones
const EFFECT_PATTERNS: Dictionary = {
	"draw": ["roba %d carta", "roba una carta", "roba %d cartas"],
	"discard": ["descarta %d carta", "cada jugador descarta"],
	"destroy": ["destruye", "destruye un", "destruye una", "destruye todos"],
	"damage": ["inflige %d de daño", "hace %d de daño", "causa %d de daño"],
	"buff": ["+%d/+%d", "obtiene +%d", "gana +%d de fuerza"],
	"debuff": ["-%d/-%d", "pierde -%d", "tiene -%d"],
	"heal": ["gana %d vida", "recupera %d vida", "cura %d"],
	"mill": ["envía %d carta al cementerio", "muele %d carta"],
	"search": ["busca", "busca en tu mazo", "busca una carta"],
	"return_to_hand": ["devuelve a la mano", "regresa a tu mano"],
	"return_to_deck": ["devuelve al mazo", "pon en la parte superior", "pon en el fondo"],
	"banish": ["destierra", "exilia", "remueve del juego"],
	"counter": ["contrarresta", "cancela", "niega"],
	"copy": ["copia", "crea una copia"],
	"token": ["crea un token", "genera un token", "invoca un token"],
	"virtual_gold": ["genera %d oro", "obtiene %d oro virtual", "añade %d oro"],
	"look": ["mira las %d primeras", "mira el tope de tu mazo"],
	"reveal": ["revela", "muestra"],
	"shuffle": ["baraja", "mezcla tu mazo"],
}

## Conectores de pipeline (DAR 7.1)
const CONNECTOR_PATTERNS: Dictionary = {
	"LUEGO": ["luego", "después", "a continuación", "entonces"],
	"Y": [" y ", ", y "],
	"O": [" o ", "alternativamente"],
}

# =============================================================================
# REFERENCIAS
# =============================================================================
var _card_scene: PackedScene = null


func _ready() -> void:
	_card_scene = load(CARD_SCENE_PATH)
	print("[CardFactory] Inicializado")


# =============================================================================
# CREACIÓN DE CARTAS
# =============================================================================
func _scan_and_apply_keywords(card: Node) -> void:
	"""Escanea el texto de habilidad y activa flags de keywords

	Usa KeywordManager si está disponible, sino aplica directamente
	"""
	# KeywordManager es autoload — siempre existe (2026-08-28, "módulos
	# gordos" punto 1: el fallback manual de abajo, _apply_keyword_flag_
	# fallback(), era inalcanzable siempre; se sacó).
	KeywordManager.scan_and_apply_keywords(card)


func _parse_keywords(json_data: Dictionary) -> Array:
	"""Extrae keywords del JSON o del texto de habilidad"""
	var keywords: Array = []

	# Primero intentar obtener del campo directo
	if json_data.has("keywords"):
		var kw = json_data.get("keywords")
		if kw is Array:
			keywords = kw
		elif kw is String:
			keywords = kw.split(",")

	# Detectar keywords del texto de habilidad
	var ability = json_data.get("habilidad", json_data.get("ability", "")).to_lower()

	if ability.contains("indestructible") or ability.contains("no puede ser destruid"):
		keywords.append(Constants.Keyword.INDESTRUCTIBLE)
	if ability.contains("furia") or ability.contains("puede atacar"):
		keywords.append(Constants.Keyword.FURIA)
	if ability.contains("imbloqueable") or ability.contains("no puede ser bloqueado"):
		keywords.append(Constants.Keyword.IMBLOQUEABLE)
	if ability.contains("indesterrable") or ability.contains("no puede ser desterrad"):
		keywords.append(Constants.Keyword.INDESTERRABLE)
	if ability.contains("exhumar") or ability.contains("jugar desde el cementerio"):
		keywords.append(Constants.Keyword.EXHUMAR)
	if ability.contains("única") or ability.contains("solo 1 copia"):
		keywords.append(Constants.Keyword.UNICA)
	if ability.contains("errante"):
		keywords.append(Constants.Keyword.ERRANTE)
	if ability.contains("retador"):
		keywords.append(Constants.Keyword.RETADOR)

	return keywords


# =============================================================================
# ON ENTER PLAY - Escaneo de keywords al entrar en juego
# =============================================================================
func on_card_enters_play(card: Node) -> void:
	"""Llamar cuando una carta entra en juego para escanear keywords

	Esta función debe invocarse desde GameBoard/EffectController cuando
	una carta se mueve a una zona de juego (Línea de Defensa, Línea de Apoyo, etc.)

	Esto asegura que cartas que entran por efectos (no por CardFactory)
	también tengan sus keywords escaneados.
	"""
	# Marcar que entró este turno (para verificación de Furia, DAR 3.1)
	card.entered_this_turn = true

	# Escanear keywords si no se hizo antes
	_scan_and_apply_keywords(card)

	# Emitir señal para que otros sistemas reaccionen
	var keywords = KeywordManager.get_cached_keywords(card)
	if not keywords.is_empty():
		print("[CardFactory] %s entró en juego con keywords: %s" % [
			card.card_name if card.get("card_name") else "Carta",
			keywords.map(func(k): return KeywordManager.Keyword.keys()[k])
		])


func on_turn_start_clear_summon_sickness(player_id: int) -> void:
	"""Limpia entered_this_turn de los Aliados del jugador que pasaron por su
	Agrupación (DAR 3.1) — a partir de ahí pueden atacar sin necesitar Furia.
	Llamar al inicio de cada Fase de Agrupación del dueño de las cartas.

	No depende de GameManager.game_board (GameBoard legacy huérfano, ver
	docs/audit) — usa directamente el campo real de Main."""
	var main = get_node_or_null("/root/Main")
	if not main:
		return
	var fields = [main.player_field, main.player_linea_ataque] if player_id == 0 else [main.opponent_field, main.opponent_linea_ataque]
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if card.get("entered_this_turn") == true:
				card.entered_this_turn = false
				print("[CardFactory] %s ya puede atacar sin Furia (pasó por Agrupación)" % (
					card.card_name if card.get("card_name") else "Aliado"
				))
