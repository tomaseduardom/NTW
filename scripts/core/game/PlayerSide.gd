extends RefCounted
class_name PlayerSide
## PlayerSide — "la mano / las líneas / los Oros / el pago DEL JUGADOR X"
## (2026-10-12, arquitectura.md §56, a pedido del usuario: "cómo podemos
## arreglar esas cartas que solo funcionan con el Anfitrión").
##
## Mucho código de efectos se escribió cuando "jugador 0 = la persona,
## jugador 1 = el bot" y usa directo main.player_hand/player_field/
## GoldManager.pagar_coste() sin jugador. Con un Remoto real eso hace que su
## carta mire o mueva las cartas del Anfitrión, o pague con sus Oros. Estas
## funciones resuelven el lado correcto a partir del player_id; al arreglar
## un patrón viejo, cambiar main.player_hand por PlayerSide.hand(main, pid).
##
## Del lado del Anfitrión el jugador 1 se ve como "opponent_*" (_opponent_fan
## para la mano). Se usa con preload (no con el class_name global) para no
## depender de que el editor ya haya registrado la clase — ver §54.

const LINE_PROPS := {
	0: ["player_field", "player_linea_ataque", "player_linea_apoyo"],
	1: ["opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo"],
}


## ¿Esta instancia es el Anfitrión de una sala online?
static func is_online_host() -> bool:
	return NetworkClient.room_code != "" and NetworkClient.is_host


## El jugador 1 es una persona real conectada (elige por red).
static func is_remote(pid: int) -> bool:
	return pid == 1 and is_online_host()


## El jugador 1 es el bot local (elige el código, sin preguntar a nadie).
static func is_bot(pid: int) -> bool:
	return pid == 1 and not is_online_host()


## Etiqueta para logs: "Anfitrión" / "Remoto" / "bot".
static func label(pid: int) -> String:
	if pid == 0:
		return "Anfitrión"
	return "Remoto" if is_remote(pid) else "bot"


# =============================================================================
# MANO
# =============================================================================
static func hand(main: Node, pid: int) -> Node:
	return main.player_hand if pid == 0 else main.get("_opponent_fan")


static func hand_cards(main: Node, pid: int) -> Array:
	"""Copia de las cartas (Nodos) de la mano del jugador."""
	var h = hand(main, pid)
	if not h:
		return []
	if pid == 0:
		return h.cards.duplicate() if h.get("cards") != null else []
	return h.get_cards().duplicate() if h.has_method("get_cards") else []


static func remove_from_hand(main: Node, pid: int, card: Node) -> void:
	"""Saca una carta de la mano sin animación (el llamador la pone en otra
	zona). Del lado del jugador 1 además la da vuelta: fuera de la mano ya
	no es información oculta."""
	var h = hand(main, pid)
	if not h or not is_instance_valid(card):
		return
	h.remove_card(card, false)
	if pid != 0:
		card.esta_oculta = false


# =============================================================================
# TABLERO
# =============================================================================
static func line_containers(main: Node, pid: int) -> Array:
	"""Línea de Defensa, Ataque y Apoyo del jugador."""
	var out: Array = []
	for prop in LINE_PROPS.get(pid, []):
		var c = main.get(prop)
		if c:
			out.append(c)
	return out


static func ally_containers(main: Node, pid: int) -> Array:
	"""Solo Defensa y Ataque (donde están los Aliados)."""
	var out := line_containers(main, pid)
	return out.slice(0, 2)


static func gold_reserva(main: Node, pid: int) -> Node:
	return main.player_gold if pid == 0 else main.opponent_gold


static func oro_pagado(main: Node, pid: int) -> Node:
	return main.player_oro_pagado if pid == 0 else main.opponent_oro_pagado


# =============================================================================
# JUGAR UNA CARTA DE LA MANO
# =============================================================================
static func play_from_hand(main: Node, pid: int, card: Node) -> void:
	"""Juega una carta que ya está en la mano del jugador, pagando su coste
	real (con los modificadores de coste que el llamador haya puesto, p.ej.
	un descuento). GoldManager.play_card() es SOLO del Anfitrión (rechaza con
	'No es tu turno' cuando el turno es del jugador 1); el jugador 1 usa sus
	propios caminos: EasyBotController._play_ally() y, si es el Remoto real,
	RemotePlayerController._play_weapon_remote()/_play_talisman_remote()/
	_play_totem_remote() (eligen por red). El bot local solo juega Aliados."""
	if not is_instance_valid(card):
		return
	if pid == 0:
		await main._gold_manager.play_card(card)
		return
	var bot = main.get("_easy_bot")
	if not bot:
		return
	match int(card.card_type):
		Constants.CardType.ALIADO:
			await bot._play_ally(card)
		Constants.CardType.ARMA:
			if bot.has_method("_play_weapon_remote"):
				await bot._play_weapon_remote(card)
		Constants.CardType.TALISMAN:
			if bot.has_method("_play_talisman_remote"):
				await bot._play_talisman_remote(card)
		Constants.CardType.TOTEM:
			if bot.has_method("_play_totem_remote"):
				await bot._play_totem_remote(card)


# =============================================================================
# PAGO
# =============================================================================
static func pay(main: Node, pid: int, amount: int, card: Node = null) -> bool:
	"""Paga 'amount' de Oro del jugador correcto con el pago completo de
	GoldManager (Oro Virtual, restringido y físico, elección de qué Oro
	gastar — por red si es el Remoto). Antes los patrones viejos llamaban
	pagar_coste() sin player_id (siempre el Anfitrión) o _pay_oro_for_bot()
	(sin Oro Virtual)."""
	if amount <= 0:
		return true
	if not main or not main.get("_gold_manager") or not main._gold_manager:
		return false
	var card_type: int = int(card.card_type) if card and card.get("card_type") != null else -1
	var race: String = str(card.get("card_raza")) if card and card.get("card_raza") != null else ""
	var cost: int = int(card.card_cost) if card and card.get("card_cost") != null else -1
	var ok: bool = await main._gold_manager.pagar_coste(amount, card_type, race, cost, pid)
	if ok and pid == 0:
		PaymentManager.registrar_pago(amount)
	return ok
