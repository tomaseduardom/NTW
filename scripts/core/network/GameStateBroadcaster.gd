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


func _on_hand_card_added(card: Node) -> void:
	if not is_instance_valid(card):
		return
	var data: Dictionary = card.card_data.duplicate(true) if card.get("card_data") != null else {}
	data["card_id"] = str(card.get_instance_id())
	NetworkClient.send_message({"op": "hand_card_added", "data": data})


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


func _on_card_left_play(_player_id: int, card: Node, from_zone: int) -> void:
	if from_zone not in Constants.ZONES_IN_PLAY:
		return
	_send_remove_card(card)


func _on_card_returned_to_deck(_player_id: int, card: Node, _to_top: bool) -> void:
	_send_remove_card(card)


func _send_remove_card(card: Node) -> void:
	var card_id: String = str(card.get_instance_id()) if is_instance_valid(card) else ""
	if card_id.is_empty():
		return
	NetworkClient.send_message({"op": "remove_card", "card_id": card_id})
