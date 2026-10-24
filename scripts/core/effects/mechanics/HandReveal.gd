extends RefCounted
## HandReveal — "juega con su mano descubierta":
## - Lady Mina Harker (en juego): "Tu oponente juega con su mano descubierta";
## - invocar ángeles: "tu oponente juega mostrando su mano por el resto del juego" (RuleState "hand_revealed").
## Mano del jugador 1 vista por el Anfitrión: sus cartas se ponen boca arriba (OpponentFan.add_card llama a
## reveal_if_needed). Mano del Anfitrión vista por el Remoto (el Remoto no recibe la mano del Anfitrión): al
## empezar cada turno se le muestra con SelectionManager.open_reveal, por red. Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const LADY_MINA := "tu oponente juega con su mano descubierta"


static func is_revealed(pid: int) -> bool:
	if RuleState.active("hand_revealed", pid):
		return true
	return not CardQuery.cards_in_play_with(1 - pid, LADY_MINA).is_empty()


## Una carta que entra a la mano del jugador 1 (en la pantalla del Anfitrión).
static func reveal_if_needed(card: Node) -> void:
	if is_instance_valid(card) and is_revealed(1):
		card.esta_oculta = false


## Da vuelta la mano del jugador 1 y le muestra la del Anfitrión al Remoto si corresponde.
static func refresh() -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	if is_revealed(1):
		for c in PlayerSideScript.hand_cards(main, 1):
			if is_instance_valid(c):
				c.esta_oculta = false
	if is_revealed(0) and not PlayerSideScript.is_bot(1):
		var hand: Array = PlayerSideScript.hand_cards(main, 0).filter(func(c): return is_instance_valid(c))
		if not hand.is_empty():
			SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "Mano descubierta de tu oponente", 1)
