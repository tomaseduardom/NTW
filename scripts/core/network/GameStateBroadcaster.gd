extends Node
class_name GameStateBroadcaster
## GameStateBroadcaster — instanciado siempre en Main.gd, pero SOLO activo
## cuando esta instancia es el Anfitrión de una sala de red activa
## (NetworkClient.room_code != "" and NetworkClient.is_host). Traduce las
## señales que EffectController YA emite en cada transición de zona real
## (on_card_entered_play/on_card_left_play) a instrucciones de red
## ({"op":"move_card"/"remove_card",...}) para que RemoteMirrorController
## (del lado del cliente Remoto) pueda reflejar el tablero.
##
## Alcance original (2026-09-11, Fase B): las 5 zonas PÚBLICAS "en juego"
## (Constants.ZONES_IN_PLAY — Reserva de Oro, Oro Pagado, Línea de Defensa/
## Ataque/Apoyo), las únicas con Nodos Card visibles en el tablero
## (Cementerio/Destierro solo muestran un contador de texto, sin cartas
## individuales visibles — no hace falta streaming para eso todavía).
## Castillo (privado) queda fuera a propósito — ver GameManager/ZoneManager,
## no tiene Nodos persistentes que mostrar de todos modos (solo un contador).
##
## 2026-10-08 (ver arquitectura.md §45, a pedido del usuario — "revisa la
## mano para que se pueda ver durante toda la partida"): la Mano del
## jugador 1 YA se transmite también, para que el Remoto tenga su propia
## mano real y persistente (player_hand poblado todo el tiempo), no solo
## una fila de cartas dentro de cada prompt puntual. La mano del Anfitrión
## NUNCA viaja por aquí (fog of war real, no solo visual) — solo se
## escuchan las señales de _opponent_fan (jugador 1), nunca las de
## player_hand.

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


## Cartas que YA estaban en juego antes de conectarnos (2026-10-11, bug real
## reportado por el usuario: "no puedo ver los oros iniciales"): el Oro
## Inicial se coloca con add_child() directo en GameBootstrap._setup_oro_
## inicial(), sin pasar por EffectController.on_card_entered_play, así que
## nunca viajaba al Remoto. Snapshot de las 5 zonas en juego de ambos lados
## al empezar la partida — move_card es idempotente por card_id del lado
## Remoto, así que no duplica nada si alguna ya se había enviado.
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


## Contenedor en juego -> (jugador, zona). 2026-10-12, bug real reportado por
## el usuario ("jugué una carta desde el jugador 2 y ni siquiera se pagaron
## los Oros"): pagar mueve el Oro de Reserva a Oro Pagado con add_child()
## directo (GoldManager.pagar_coste()/EasyBotController._pay_oro_for_bot()),
## sin pasar por on_card_entered_play — el Remoto nunca se enteraba, ni de
## sus Oros ni de los del Anfitrión (lo mismo al recuperarlos en la
## Agrupación). Vigilar child_entered_tree de los 10 contenedores cubre
## CUALQUIER movimiento entre zonas en juego, venga del código que venga;
## move_card es idempotente del lado Remoto.
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
	# "own" es relativo al RECEPTOR (el Remoto, que del lado del Anfitrión
	# siempre es el jugador 1) — ver "perspectiva relativa al receptor" en
	# docs/plans/2026-09-09-multiplayer-remoto-design.md.
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


## Cartas sin habilidad (silenciadas, con el nombre bloqueado o convertidas)
## — 2026-10-13 (§63, Alicia en Wonderland): el Remoto no tiene esos
## bloqueos (viven en el KeywordManager del Anfitrión), así que nunca veía
## el gris de "sin habilidad". Se manda la lista completa (mesa + la mano
## del Remoto; nunca la del Anfitrión) solo cuando cambia.
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
