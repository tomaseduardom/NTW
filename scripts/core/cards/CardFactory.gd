extends Node
## CardFactory - Convierte datos JSON en recursos Card con bloques de habilidades
## Mapea datos de la base de datos a la estructura del juego

# =============================================================================
# CONSTANTES
# =============================================================================
const CARD_SCENE_PATH = "res://scenes/cards/Card.tscn"


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
	"""Registra en el log las keywords impresas (KeywordManager → KeywordParser)."""
	KeywordManager.scan_and_apply_keywords(card)


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

	# Log de las keywords impresas
	_scan_and_apply_keywords(card)


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
