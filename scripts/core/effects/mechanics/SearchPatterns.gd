extends RefCounted
## SearchPatterns — Buscar y jugar desde el Castillo: fortaleza hoshi, Pan de Muerto, Ángel Redentor,
## Dos de Cada Uno, Supremacia Kaiju.
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")


## fortaleza hoshi: "Cuando entra en juego, muestra cartas del tope de tu
## Castillo hasta mostrar dos Tótem de coste 2 o menos de distinto nombre y
## juégalos sin pagar su coste." (El resto vuelve al Castillo, barajado.)
static func hoshi_enter(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main or not main._gold_manager:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "fortaleza hoshi"
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	var deck: Array = CardManager.get_deck(controller_id)
	var revealed: Array = []
	var totems: Array = []
	var names: Array = []
	while not deck.is_empty() and totems.size() < 2:
		var top: Dictionary = deck.pop_front()
		revealed.append(top)
		var n: String = str(top.get("nombre", "")).to_lower()
		if int(top.get("tipo", -1)) == Constants.CardType.TOTEM and ContinuousEffectManager.data_cost_at_most(top, 2) \
				and not (n in names):
			totems.append(top)
			names.append(n)
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(controller_id, revealed, title)
	for t in totems:
		revealed.erase(t)
	for c in revealed:
		deck.append(c)
	CardManager.shuffle_deck(controller_id)
	AnimationQueue.queue_shuffle(controller_id, "Barajar mazo (%s)" % title)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	var ordered: Array = await load("res://scripts/ui/zones/RevealWindow.gd").choose_order(main, controller_id, totems, title,
		"Toca los Tótem en el orden en que se juegan")
	var queue_before: int = TriggerSystem.trigger_queue.size()
	for t in ordered:
		var data: Dictionary = t.duplicate()
		data["esta_oculta"] = false
		await main._gold_manager.play_found_card(data, controller_id, controller_id, int(data.get("coste", 0)), true)
	# Si los dos disparan "Cuando entra en juego", el jugador elige cuál se resuelve primero (cada uno con su
	# ventana de respuesta al resolverse).
	await reorder_new_triggers(queue_before, controller_id)


## Los disparos que quedaron en la cola desde 'queue_before' (jugar varias cartas dentro de un efecto):
## si son 2 o más del jugador (humano), él elige el orden (TriggerSystem._prompt_trigger_order).
static func reorder_new_triggers(queue_before: int, controller_id: int) -> void:
	var q: Array = TriggerSystem.trigger_queue
	if q.size() - queue_before < 2 or PlayerSideScript.is_bot(controller_id):
		return
	var fresh: Array[Dictionary] = []
	for k in range(queue_before, q.size()):
		fresh.append(q[k])
	var ordered: Array = await TriggerSystem._prompt_trigger_order(fresh)
	for k in range(ordered.size()):
		q[queue_before + k] = ordered[k]


# -----------------------------------------------------------------------------
# Pan de Muerto
#   "En tu Vigilia, una vez por turno, puedes pagarlo para buscar un Talismán o
#   Tótem de coste 2 o más en tu Castillo y jugarlo reduciendo su coste en un
#   Oro." (Botón: AbilityButtonPatternsD.)
#   "Sólo se puede Botar y/o Desterrar hasta quince cartas de cada Castillo por
#   turno y tus Aliados son Indestructibles mientras bloquean."
# -----------------------------------------------------------------------------
const PAN_TEXT := "pagarlo para buscar un talismán o tótem de coste 2 o más en tu castillo y jugarlo reduciendo su coste en un oro"


static func pan_search(source_card: Node, ability: Dictionary) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(source_card) or not main._gold_manager:
		return
	var pid: int = CardQuery.controller_of(source_card)
	var title: String = str(source_card.get("card_name"))
	if source_card.get("current_zone") != Constants.Zone.RESERVA_ORO:
		main._update_debug("%s ya no está en tu Reserva" % title)
		return
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)
	await main._gold_manager._mover_oro_a_pagado(source_card)
	if await TriggerSystem.open_response_window(source_card, title, pid):
		return
	var res: Dictionary = await ActionModule.search(pid, Constants.Zone.CASTILLO,
		{"type": [Constants.CardType.TALISMAN, Constants.CardType.TOTEM], "cost_min": 2}, 1, true, false, false,
		source_card, -1)
	for d in res.get("selected", []):
		var data: Dictionary = d.duplicate()
		data["esta_oculta"] = false
		await main._gold_manager.play_found_card(data, pid, pid, 1, false)


# -----------------------------------------------------------------------------
# Ángel Redentor
# -----------------------------------------------------------------------------
static func discard_for_same_type(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Ángel Redentor"
	var picked: Node = await PlayerSideScript.pick_from_hand(main, controller_id,
		"%s: puedes Descartar una carta para buscar otra del mismo tipo (N: no)" % title)
	if not picked or not is_instance_valid(picked):
		return
	var tipo: int = int(picked.get("card_type"))
	if await TriggerSystem.open_response_window(card, title, controller_id):
		return
	await ActionModule.discard(controller_id, [picked], title, true)
	await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {"type": tipo}, 1, true, false, false, card)


# -----------------------------------------------------------------------------
# Dos de Cada Uno: "Busca dos cartas del mismo nombre que no sean Talismán en
# tu Castillo y ponlas en tu mano." Se elige una; la otra copia sale sola.
# -----------------------------------------------------------------------------
static func two_of_same_name(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main:
		return
	var counts: Dictionary = {}
	for d in CardManager.get_deck(controller_id):
		if int(d.get("tipo", -1)) == Constants.CardType.TALISMAN:
			continue
		var n: String = str(d.get("nombre", "")).to_lower()
		counts[n] = int(counts.get(n, 0)) + 1
	var names: Array = counts.keys().filter(func(n): return int(counts[n]) >= 2)
	var res: Dictionary = await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {"names_in": names}, 1, true,
		false, false, card)
	var selected: Array = res.get("selected", [])
	if selected.is_empty():
		return
	var picked_name: String = str(selected[0].get("nombre", "")).to_lower()
	var deck: Array = CardManager.get_deck(controller_id)
	for d in deck:
		if str(d.get("nombre", "")).to_lower() != picked_name or int(d.get("tipo", -1)) == Constants.CardType.TALISMAN:
			continue
		deck.erase(d)
		PlayerSideScript.put_in_hand(main, controller_id, d)
		break
	CardManager.shuffle_deck(controller_id)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# -----------------------------------------------------------------------------
# Supremacia Kaiju: "Baraja y/o Destierra hasta tres cartas de los
# Cementerios. Busca en tu Castillo una carta y ponla en tu mano. El próximo
# Oro que ponga en juego tu oponente entra sin habilidad por el turno."
# -----------------------------------------------------------------------------
static func supremacia_kaiju(card: Node, controller_id: int) -> void:
	var main := CardQuery.main_node()
	if not main or not main._gold_manager:
		return
	var title: String = str(card.get("card_name")) if is_instance_valid(card) else "Supremacia Kaiju"
	await main._gold_manager._resolve_armeria_barajar_desterrar(3, title, controller_id)
	await ActionModule.search(controller_id, Constants.Zone.CASTILLO, {}, 1, true, false, false, card)
	RuleState.set_pending("next_gold_silenced", 1 - controller_id)


## Llamar cuando una carta entra en juego (ContinuousEffectManager).
static func on_card_entered(card: Node, zone: int) -> void:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ORO:
		return
	if not (zone in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]):
		return
	var pid: int = CardQuery.controller_of(card)
	if not RuleState.has_pending("next_gold_silenced", pid):
		return
	RuleState.take_pending("next_gold_silenced", pid)
	KeywordManager.silence_card(card, null, "turn", true)
	main._update_debug("%s entra sin habilidad por el turno (Supremacia Kaiju)" % str(card.get("card_name")))
