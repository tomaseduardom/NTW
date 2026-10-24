extends Node
class_name GameStateBroadcaster
## GameStateBroadcaster — instanciado siempre en Main.gd, pero solo activo en el Anfitrión de una
## sala (NetworkClient.room_code != "" and NetworkClient.is_host). Traduce las transiciones de zona
## (EffectController.on_card_entered_play/on_card_left_play y los contenedores en juego) a
## instrucciones de red ({"op":"move_card"/"remove_card",...}) para que RemoteMirrorController
## refleje el tablero.
## Zonas: las 5 públicas en juego (Constants.ZONES_IN_PLAY: Reserva, Oro Pagado, Línea de
## Defensa/Ataque/Apoyo). Castillo/Cementerio/Destierro van como contadores. La Mano del jugador 1
## también viaja, para que el Remoto tenga su mano persistente (arquitectura.md §45); la mano del
## Anfitrión nunca viaja (solo se escuchan las señales de _opponent_fan).

var _active: bool = false
var _main: Node = null
## Último envío de "disabled_cards" y si ya hay uno agendado este frame (§63).
var _last_disabled_ids: Array = []
var _disabled_sync_queued: bool = false


func setup(main: Node) -> void:
	_main = main
	_active = NetworkClient.room_code != "" and NetworkClient.is_host
	if not _active:
		return
	EffectController.on_card_entered_play.connect(_on_card_entered_play)
	EffectController.on_card_left_play.connect(_on_card_left_play)
	# ActionModule.return_to_deck() ("barajar de vuelta al mazo" — uno de
	# los efectos más comunes de todo el motor de triggers) no pasa por
	# on_card_left_play (no es un destroy/exile) — necesitaba su propia
	# señal, que estaba declarada pero nunca se emitía hasta hoy (ver el fix
	# en ActionReturnDiscard.gd).
	EffectController.on_card_returned_to_deck.connect(_on_card_returned_to_deck)
	KeywordManager.abilities_changed.connect(_queue_disabled_sync)
	# Aliados en la Línea de Ataque que no atacan (CardInteractionModule, se crea después): tono azul
	# hielo en el Remoto.
	_connect_idle_attack.call_deferred()
	# Recién tras game_started, no en setup() — _opponent_fan.add_card()/
	# remove_card() YA se llaman durante el mulligan (RemotePlayerController.
	# run_mulligan() dibuja ahí mismo mientras el jugador decide mantener/
	# redibujar, antes de que la partida "empiece" de verdad) — escuchar
	# desde el arranque le mostraría al Remoto cartas apareciendo en su mano
	# PERMANENTE mientras todavía está decidiendo el mulligan. El mulligan en
	# sí ya tiene su propio camino separado (RemoteMirrorController._show_
	# mulligan_prompt(), §44) que no pasa por acá.
	GameManager.game_started.connect(_start_hand_sync, CONNECT_ONE_SHOT)


func _start_hand_sync() -> void:
	if not _main or not _main.get("_opponent_fan") or not _main._opponent_fan:
		return
	_main._opponent_fan.card_added.connect(_on_hand_card_added)
	_main._opponent_fan.card_removed.connect(_on_hand_card_removed)
	# Estado inicial: la mano ya tiene las cartas que sobrevivieron el
	# mulligan (nunca se avisaron porque recién ahora nos conectamos) — se
	# sincronizan de una, como si cada una se hubiera agregado ahora mismo.
	for c in _main._opponent_fan.cards:
		_on_hand_card_added(c)
	_sync_cards_already_in_play()
	_watch_in_play_containers()
	# Contadores de Castillo (§47): públicos para ambos (solo el tamaño, nunca
	# el contenido). Mismo momento que la mano — el mulligan baraja y redibuja
	# antes de game_started, así que el primer conteo útil es este.
	if _main.get("_zone_manager") and _main._zone_manager:
		_main._zone_manager.castillo_counts_changed.connect(_on_castillo_counts_changed)
		_on_castillo_counts_changed(_main.player_deck.size(), _main.opponent_deck.size())


func _on_castillo_counts_changed(player_deck_size: int, opponent_deck_size: int) -> void:
	# "own"/"rival" relativos al RECEPTOR: el Remoto es el jugador 1 del
	# Anfitrión, así que su Castillo propio es opponent_deck.
	NetworkClient.send_message({
		"op": "castillo_counts",
		"own": opponent_deck_size,
		"rival": player_deck_size,
	})


## Snapshot de las 5 zonas en juego de ambos lados al empezar la partida: el Oro Inicial se coloca
## con add_child() directo (GameBootstrap._setup_oro_inicial()), sin pasar por on_card_entered_play.
## move_card es idempotente por card_id del lado Remoto.
func _sync_cards_already_in_play() -> void:
	var containers := {
		0: ["player_gold", "player_oro_pagado", "player_field", "player_linea_ataque", "player_linea_apoyo"],
		1: ["opponent_gold", "opponent_oro_pagado", "opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo"],
	}
	for player_id in containers:
		for prop in containers[player_id]:
			var container: Node = _main.get(prop)
			if not container:
				continue
			for child in container.get_children():
				if child.get("card_data") != null and child.get("current_zone") != null:
					_on_card_entered_play(player_id, child, int(child.current_zone))


## Contenedor en juego → (jugador, zona). Se vigila child_entered_tree de los 10 contenedores para
## cubrir cualquier movimiento entre zonas en juego (p.ej. pagar mueve el Oro de la Reserva al Oro
## Pagado con add_child() directo, y la Agrupación lo devuelve). move_card es idempotente del lado
## Remoto.
const WATCHED_CONTAINERS := {
	"player_gold": [0, Constants.Zone.RESERVA_ORO], "player_oro_pagado": [0, Constants.Zone.ORO_PAGADO],
	"player_field": [0, Constants.Zone.LINEA_DEFENSA], "player_linea_ataque": [0, Constants.Zone.LINEA_ATAQUE],
	"player_linea_apoyo": [0, Constants.Zone.LINEA_APOYO],
	"opponent_gold": [1, Constants.Zone.RESERVA_ORO], "opponent_oro_pagado": [1, Constants.Zone.ORO_PAGADO],
	"opponent_field": [1, Constants.Zone.LINEA_DEFENSA], "opponent_linea_ataque": [1, Constants.Zone.LINEA_ATAQUE],
	"opponent_linea_apoyo": [1, Constants.Zone.LINEA_APOYO],
}


func _watch_in_play_containers() -> void:
	for prop in WATCHED_CONTAINERS:
		var container: Node = _main.get(prop)
		if not container:
			continue
		var info: Array = WATCHED_CONTAINERS[prop]
		container.child_entered_tree.connect(_on_container_child_entered.bind(info[0], info[1]))


func _on_container_child_entered(node: Node, player_id: int, zone: int) -> void:
	# Diferido: el código que mueve la carta todavía puede estar ajustándola
	# en este mismo frame (set_zone, escala, esta_oculta).
	_send_container_move.call_deferred(node, player_id, zone)


func _send_container_move(node: Node, player_id: int, zone: int) -> void:
	if not is_instance_valid(node) or node.get("card_data") == null:
		return
	_on_card_entered_play(player_id, node, zone)


func _on_hand_card_added(card: Node) -> void:
	if not is_instance_valid(card):
		return
	var data: Dictionary = card.card_data.duplicate(true) if card.get("card_data") != null else {}
	data["card_id"] = str(card.get_instance_id())
	NetworkClient.send_message({"op": "hand_card_added", "data": data})
	_queue_disabled_sync()


func _on_hand_card_removed(card: Node) -> void:
	if not is_instance_valid(card):
		return
	NetworkClient.send_message({"op": "hand_card_removed", "card_id": str(card.get_instance_id())})


func _on_card_entered_play(player_id: int, card: Node, zone: int) -> void:
	if not is_instance_valid(card) or zone not in Constants.ZONES_IN_PLAY:
		return
	# "own" es relativo al RECEPTOR (el Remoto, que del lado del Anfitrión es siempre el jugador 1);
	# ver docs/plans/2026-09-09-multiplayer-remoto-design.md.
	var own_for_remote: bool = (player_id == 1)
	var card_data: Dictionary = card.card_data.duplicate() if card.get("card_data") != null else {}
	NetworkClient.send_message({
		"op": "move_card",
		"card_id": str(card.get_instance_id()),
		"own": own_for_remote,
		"zone": zone,
		"data": card_data,
	})
	_queue_disabled_sync()


func _on_card_left_play(_player_id: int, card: Node, from_zone: int) -> void:
	if from_zone not in Constants.ZONES_IN_PLAY:
		return
	_send_remove_card(card)
	# Si salió la fuente de un bloqueo (p.ej. Alicia), las cartas que
	# bloqueaba recuperan su habilidad.
	_queue_disabled_sync()


func _on_card_returned_to_deck(_player_id: int, card: Node, _to_top: bool) -> void:
	_send_remove_card(card)


func _send_remove_card(card: Node) -> void:
	var card_id: String = str(card.get_instance_id()) if is_instance_valid(card) else ""
	if card_id.is_empty():
		return
	NetworkClient.send_message({"op": "remove_card", "card_id": card_id})


## Cartas sin habilidad (silenciadas, con nombre bloqueado o convertidas; §63): el Remoto no tiene
## esos bloqueos (viven en el KeywordManager del Anfitrión). Se manda la lista completa (mesa + mano
## del Remoto, nunca la del Anfitrión) solo cuando cambia.
var _last_idle_attack_ids: Array = []


func _connect_idle_attack() -> void:
	if _main and _main.get("_card_interaction") and _main._card_interaction.has_signal("idle_attack_changed"):
		_main._card_interaction.idle_attack_changed.connect(_on_idle_attack_changed)


func _on_idle_attack_changed(card_ids: Array) -> void:
	var ids: Array = card_ids.duplicate()
	ids.sort()
	if ids == _last_idle_attack_ids:
		return
	_last_idle_attack_ids = ids
	NetworkClient.send_message({"op": "idle_attack_cards", "card_ids": ids})


func _queue_disabled_sync() -> void:
	if _disabled_sync_queued:
		return
	_disabled_sync_queued = true
	_send_disabled_cards.call_deferred()


func _send_disabled_cards() -> void:
	_disabled_sync_queued = false
	if not _main:
		return
	var cards: Array = []
	for prop in WATCHED_CONTAINERS:
		var container: Node = _main.get(prop)
		if container:
			cards.append_array(container.get_children())
	if _main.get("_opponent_fan") and _main._opponent_fan:
		cards.append_array(_main._opponent_fan.cards)
	var ids: Array = []
	for c in cards:
		if is_instance_valid(c) and c.get("card_data") != null \
				and (c.get("is_converted") == true or KeywordManager.is_silenced(c)):
			ids.append(str(c.get_instance_id()))
	ids.sort()
	if ids == _last_disabled_ids:
		return
	_last_disabled_ids = ids
	NetworkClient.send_message({"op": "disabled_cards", "card_ids": ids})
