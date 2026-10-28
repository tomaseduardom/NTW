extends RefCounted
class_name PlayerSide
## PlayerSide — "la mano / las líneas / los Oros / el pago DEL JUGADOR X" (arquitectura.md §56).
## Mucho código de efectos usa main.player_hand/player_field/GoldManager.pagar_coste() sin jugador
## (de cuando el jugador 1 era siempre el bot); con un Remoto, su carta tocaría las cartas o los
## Oros del Anfitrión. Estas funciones resuelven el lado correcto según el player_id: al arreglar un
## patrón viejo, cambiar main.player_hand por PlayerSide.hand(main, pid).
## En el Anfitrión el jugador 1 es "opponent_*" (_opponent_fan para la mano). Se usa con preload (no
## con el class_name global; ver §54).

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
# ELEGIR Y MOVER CARTAS (en vez de copiar estos bloques en cada patrón, con su rama del bot)
# =============================================================================
# Elige una carta EN JUEGO (líneas de los dos jugadores) que pase 'filter'.
# - Anfitrión / Remoto: click en el tablero (await_target; el Remoto elige por red). 'optional' = se
# puede no elegir (N).
# - Bot local: la primera que pase 'bot_filter' (o 'filter') en los lados de 'bot_sides' en orden
# (por defecto el rival y después el propio). Con 'bot_skip' no elige ninguna ("hasta"/"puedes" que
# no le conviene).
static func pick_in_play(main: Node, pid: int, prompt: String, filter: Callable, optional: bool = true,
		bot_sides: Array = [], bot_skip: bool = false, bot_filter: Callable = Callable()) -> Node:
	if is_bot(pid):
		if bot_skip:
			return null
		var check: Callable = bot_filter if bot_filter.is_valid() else filter
		for side in (bot_sides if not bot_sides.is_empty() else [1 - pid, pid]):
			for container in line_containers(main, side):
				for c in container.get_children():
					if is_instance_valid(c) and check.call(c):
						return c
		return null
	if not main.get("_card_interaction"):
		return null
	return await main._card_interaction.await_target(prompt, filter, optional, pid)


## Elige una carta de la mano de 'pid' que pase 'filter' (si se da). El bot
## toma la primera, o una al azar con 'bot_random'. null si no hay o no eligió.
static func pick_from_hand(main: Node, pid: int, prompt: String, filter: Callable = Callable(),
		optional: bool = true, bot_random: bool = false) -> Node:
	var cards: Array = hand_cards(main, pid).filter(func(c):
		return is_instance_valid(c) and (not filter.is_valid() or filter.call(c)))
	if cards.is_empty():
		return null
	if is_bot(pid):
		return cards.pick_random() if bot_random else cards[0]
	if not main.get("_card_interaction"):
		return null
	return await main._card_interaction.await_target(prompt, func(c: Node) -> bool: return c in cards, optional, pid)


## Muestra la mano de 'owner' a 'viewer' con las cartas a la vista y espera que haga clic en una de las que
## pasan 'eligible' (las demás se ven pero no se eligen): "mira la mano de tu oponente y Destierra un
## Talismán de ahí" (carcosa). El bot elige la primera. El Remoto elige por red (await_single_pick()).
static func pick_from_hand_view(main: Node, viewer: int, owner: int, title: String, eligible: Callable) -> Node:
	var hand: Array = hand_cards(main, owner).filter(func(c): return is_instance_valid(c))
	var candidates: Array = hand.filter(func(c): return eligible.call(c))
	if candidates.is_empty():
		return null
	if is_bot(viewer) or candidates.size() == 1 and hand.size() == 1:
		return candidates[0]
	var picked: Dictionary = await SelectionManager.await_single_pick(hand.map(func(c): return c.card_data), title, false, 1,
		func(d: Dictionary) -> bool: return candidates.any(func(c): return is_instance_valid(c) and c.card_data == d), viewer)
	for c in candidates:
		if is_instance_valid(c) and c.card_data == picked:
			return c
	return candidates[0]


## Saca una carta de la mano de 'pid' y devuelve sus datos (boca arriba). El
## Nodo se libera: el llamador decide adónde van los datos.
static func take_from_hand(main: Node, pid: int, card: Node) -> Dictionary:
	if not is_instance_valid(card):
		return {}
	var data: Dictionary = card.card_data.duplicate()
	data["esta_oculta"] = false
	remove_from_hand(main, pid, card)
	if is_instance_valid(card):
		CardManager._disconnect_card_interaction_signals(card)
		card.queue_free()
	return data


## Crea la carta (desde sus datos) en la mano de 'pid', que queda como dueño y
## controlador. Devuelve el Nodo.
static func put_in_hand(main: Node, pid: int, data: Dictionary) -> Node:
	data.erase("_from_cemetery_turn")  # ya no se juega "desde el Cementerio" (GoldManager._mark_cemetery_exhumar)
	data["esta_oculta"] = false
	var node = main._create_card(data, false)
	node.owner_id = pid
	node.controller_id = pid
	var h = hand(main, pid)
	if h:
		h.add_card(node)
	main._connect_card_signals(node)
	return node


## Baraja una carta EN JUEGO en el Castillo de su dueño (con Prevención: pasa
## por ActionModule.return_to_deck). true si se barajó.
static func shuffle_into_castle(card: Node, source: Node, label: String) -> bool:
	if not is_instance_valid(card):
		return false
	var owner: int = card.owner_id if card.get("owner_id") != null else 0
	if not await ActionModule.return_to_deck(card, owner, true, source):
		return false
	CardManager.shuffle_deck(owner)
	AnimationQueue.queue_shuffle(owner, "Barajar mazo (%s)" % label)
	return true


## Baraja una carta de la mano de 'pid' en su Castillo.
static func shuffle_from_hand(main: Node, pid: int, card: Node, label: String) -> void:
	var data: Dictionary = take_from_hand(main, pid, card)
	if data.is_empty():
		return
	data["esta_oculta"] = true
	CardManager.get_deck(pid).append(data)
	CardManager.shuffle_deck(pid)
	AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % label)


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
