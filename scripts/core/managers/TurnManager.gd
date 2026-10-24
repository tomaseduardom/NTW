extends Node
## TurnManager — autoload reducido a dos responsabilidades del flujo de turno (DAR Sección 5).
## GameManager._change_phase()/advance_to_phase() es el único conductor de fases; el turno activo y
## su número se leen de GameManager (que también arranca el Turno 1 con _start_turn()). Aquí queda:
## - el sistema de Oro (can_place_oro/on_card_played/_reset_oro_tracking), usado por GoldManager y
## CardInteractionModule;
## - la validación de enfermedad de invocación / Furia (can_attack), usada por
## GameManager.declare_attacker() y DropZone;
## - el contador de cartas jugadas por turno (Quinto Sello).

# =============================================================================
# SISTEMA DE OROS (DAR Sección 5.B)
# =============================================================================
# Regla 5.B: El oro DEBE ser la primera carta jugada en Vigilia
# Si se juega cualquier otra carta primero, se pierde la oportunidad de poner oro
var oro_placed_this_turn: bool = false      # ¿Ya se puso oro este turno?
var any_card_played_this_turn: bool = false  # ¿Se jugó alguna carta? (bloquea oro)
var oro_chance_lost: bool = false       # ¿Se perdió la oportunidad de poner oro?

# Quinto Sello ("Si está en tu Cementerio, no se pueden jugar más de cinco cartas por turno"):
# contador GLOBAL de cartas jugadas en el turno, de cualquier jugador. A diferencia de
# any_card_played_this_turn (solo para la regla del Oro, solo en Vigilia), cuenta toda carta que
# entra en juego en cualquier fase. Se incrementa en GoldManager._trigger_enter_play() (por donde
# pasa toda carta jugada, arquitectura.md §1) y se consulta en GoldManager.play_card() antes de
# pagar.
var cards_played_count_this_turn: int = 0

# kamidana ("si no jugó Aliados en su turno anterior"): jugador -> último turn_serial en que jugó un
# Aliado en su propio turno. Se anota en GoldManager._trigger_enter_play(), junto al contador de arriba.
var ally_played_serial: Dictionary = {}


func played_ally_in_previous_turn(player_id: int) -> bool:
	"""En el turno de 'player_id': ¿jugó un Aliado en su turno anterior (turn_serial - 2)?"""
	return int(ally_played_serial.get(player_id, -1)) == GameManager.turn_serial - 2


func _ready() -> void:
	print("[TurnManager] Inicializado")


func can_place_oro(phase_override: int = -1, card: Node = null) -> bool:
	"""Verifica si el jugador puede poner un Oro desde la mano (DAR 5.B)
	Condiciones:
	- Estar en Fase de Vigilia
	- No haber puesto oro este turno
	- No haber jugado ninguna otra carta antes (oro debe ser la primera acción),
	  SALVO que la propia carta traiga una excepción explícita a esa regla
	  (ver ignores_oro_chance_lost()).

	Args:
		phase_override: Si es >= 0, usa esta fase en lugar de GameManager.current_phase
		card: la carta que se está por colocar como Oro (opcional) — solo se
			usa para chequear si tiene la excepción de texto propia.
	"""
	var phase = phase_override if phase_override >= 0 else GameManager.current_phase
	if phase != Constants.Phase.VIGILIA:
		return false
	if oro_placed_this_turn:
		return false
	if oro_chance_lost and not ignores_oro_chance_lost(card):
		return false
	return true


func ignores_oro_chance_lost(card: Node) -> bool:
	""""En tu Vigilia, si no pusiste Oros en juego este turno, ponlo de tu mano en tu Reserva" (p.ej.
	Infernum Vox). Excepción de esta carta a la regla general (DAR 5.B: el Oro debe ser la primera
	carta jugada del turno): se puede colocar en cualquier momento de tu Vigilia mientras no hayas
	puesto un Oro, aunque ya hayas jugado otra carta. Se detecta por texto."""
	if not card or card.get("card_data") == null:
		return false
	var habilidad: String = str(card.card_data.get("habilidad", "")).to_lower()
	return "si no pusiste oros en juego este turno" in habilidad


func on_card_played(card: Node) -> void:
	"""Llamar cuando se juega cualquier carta que NO sea oro (DAR 5.B)
	Esto marca que se perdió la oportunidad de poner oro este turno
	"""
	if GameManager.current_phase != Constants.Phase.VIGILIA:
		return

	if not oro_placed_this_turn and not any_card_played_this_turn:
		# Primera carta jugada y no fue oro → se pierde la oportunidad
		oro_chance_lost = true
		print("[TurnManager] Jugador %d perdió la oportunidad de poner Oro este turno" % (GameManager.active_player_id + 1))

	any_card_played_this_turn = true


func _reset_oro_tracking() -> void:
	"""Resetea el tracking de oros para un nuevo turno"""
	oro_placed_this_turn = false
	any_card_played_this_turn = false
	oro_chance_lost = false
	cards_played_count_this_turn = 0


# =============================================================================
# ENFERMEDAD DE INVOCACIÓN / FURIA (DAR 3.1 y 8)
# =============================================================================
func player_can_attack(player_id: int) -> bool:
	"""¿Tiene 'player_id' al menos un Aliado en juego que pueda declarar ataque? (botón "Atacar"/"Fase
	Final" y salto del Ataque)."""
	var main := get_node_or_null("/root/Main")
	if not main:
		return false
	for container in load("res://scripts/core/game/PlayerSide.gd").ally_containers(main, player_id):
		for ally in container.get_children():
			if is_instance_valid(ally) and ally.get("card_type") == Constants.CardType.ALIADO \
					and can_attack(ally).get("can_attack", false):
				return true
	return false


func can_attack(ally: Node) -> Dictionary:
	"""Verifica si un Aliado puede atacar (DAR 3.1 y 8)

	Returns: {can_attack: bool, reason: String, has_furia: bool}
	"""
	var result = {"can_attack": true, "reason": "", "has_furia": false}

	# Restricción explícita (p.ej. Kuchiku Kan: 'no pueda atacar... mientras este Aliado esté en
	# juego') — ContinuousEffect Manager.can_attack ya existía pero nadie lo consultaba todavía.
	if ContinuousEffectManager and not ContinuousEffectManager.can_attack(ally):
		result.can_attack = false
		result.reason = "no puede atacar — efecto continuo se lo impide"
		return result
	# furia de titán: "tu oponente no puede atacar con Aliados de mayor Fuerza que ese Aliado".
	if GameManager.attack_strength_cap_blocks(ally):
		result.can_attack = false
		result.reason = "furia de titán: no puede atacar con más Fuerza que ese Aliado"
		return result
	# ambrosio ohiggins: "para que un Aliado no pueda ser declarado atacante este turno".
	if int(ally.get_meta("no_attack_turn", -1)) == GameManager.turn_serial:
		result.can_attack = false
		result.reason = "no puede ser declarado atacante este turno"
		return result

	# Verificar si entró este turno (enfermedad de invocación)
	var entered_this_turn = ally.get("entered_this_turn") if ally.get("entered_this_turn") != null else false

	if entered_this_turn:
		# Verificar si tiene Furia
		result.has_furia = KeywordManager.can_attack_immediately(ally)

		if not result.has_furia:
			result.can_attack = false
			result.reason = "no puede atacar aún — no ha pasado por tu Agrupación (sin Furia)"

	return result


# _has_furia_fallback se eliminó aquí ("módulos gordos" punto 1): KeywordManager es autoload —
# siempre existe, esta rama nunca corría.
