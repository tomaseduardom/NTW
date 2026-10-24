extends Node
## RemoteMirrorControllerBase — base de RemoteMirrorController.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: RemoteMirrorControllerBase <- RemoteMirrorControllerUI <- RemoteMirrorControllerMesa <- RemoteMirrorControllerPrompts <- RemoteMirrorController. Lo de afuera usa solo RemoteMirrorController.gd (hereda todo).

## RemoteMirrorController — instanciado siempre en Main.gd, pero solo actúa si esta instancia es el
## Remoto de una sala activa (NetworkClient.room_code != "" and not NetworkClient.is_host). El
## Remoto no corre GameManager.setup_game()/start_game(): GameBootstrap se detiene tras mandar el
## mazo propio (_send_own_deck_and_wait_for_host()) y esta clase es la que permite seguir jugando.
## Escucha los {"op":"prompt","kind":...} de RemotePlayerController (lado Anfitrión), muestra la UI
## para que la persona elija y responde {"op":"intent","kind":...} (mismo protocolo documentado
## ahí). Además aplica los "move_card"/"remove_card" de GameStateBroadcaster, creando Nodos Card
## reales en las 5 zonas públicas en juego (Reserva/Oro Pagado/Línea de Defensa/Ataque/Apoyo). Ver
## GameStateBroadcaster.gd para la mano y los contadores de Castillo/Cementerio/Destierro.

var _main: Node = null

var _active: bool = false

var _current_overlay: Control = null

const CastleLookWindowScript = preload("res://scripts/ui/zones/CastleLookWindow.gd")

const RevealedCardsScript = preload("res://scripts/core/effects/mechanics/RevealedCards.gd")

var _card_nodes: Dictionary = {}  # card_id (String) -> Node local (ghost)

var _hand_card_nodes: Dictionary = {}  # card_id (String) -> Node local en player_hand (§45)

## card_ids sin habilidad según el Anfitrión (op "disabled_cards", §63).
var _disabled_ids: Dictionary = {}

## Botón de paso del Remoto: qué hace el botón del HUD (y el atajo P) según el prompt activo, y el
## window_id de la ventana de prioridad que se está respondiendo (-1 si no hay ninguna).
var _paso_action: Callable = Callable()

var _priority_window_id: int = -1

## Tecla N: qué hace "no hacerlo / terminar" en el prompt de objetivo activo (solo selecciones
## opcionales). Vacío si no hay ninguno.
var _skip_action: Callable = Callable()

## Último prompt de Vigilia todavía sin responder: si una ventana de
## prioridad lo tapa (p.ej. el Anfitrión responde a tu carta con un
## Talismán), se vuelve a mostrar al cerrarse esa ventana.
var _pending_vigilia: Dictionary = {}

## card_id de una carta de la mano física -> intent que manda su doble clic
## (Vigilia: poner Oro/jugar carta; ventana de prioridad: Talismán de
## respuesta). Vacío = ninguna carta de la mano se puede jugar ahora.
var _hand_actions: Dictionary = {}

## card_id de un Aliado propio en juego que puede atacar -> si está marcado como atacante (Fase de
## Ataque del Remoto).
var _attack_candidates: Dictionary = {}

## Bloqueo en el tablero: blocker_id -> [attacker_id válidos], blocker_id -> [attacker_id asignados],
## blocker_id -> a cuántos puede bloquear a la vez (Elías: 2), y el bloqueador que espera que se
## elija su atacante ("" si ninguno).
var _block_options: Dictionary = {}

var _block_pairs: Dictionary = {}

var _block_max: Dictionary = {}

var _block_pending_blocker: String = ""

## Selección genérica sobre el tablero/mano: card_id -> qué hacer al clickearla (portador de Arma,
## objetivo de un efecto, habilidad de respuesta). _pick_multi guarda las marcadas en una selección
## múltiple.
var _pick_targets: Dictionary = {}

var _pick_multi: Dictionary = {}

## Aliados en la Línea de Ataque que no atacan, según el Anfitrión: tono azul hielo
## (CardInteractionModule.IDLE_ATTACK_TINT).
var _idle_attack_ids: Dictionary = {}

const _CardScene = preload("res://scenes/cards/Card.tscn")

## Mulligan gratis del Anfitrión: te muestra su mano; al cerrarla se avisa (el Anfitrión no cambia su
## mano ni deja mostrar otra hasta entonces, MulliganController._acquire_reveal()).
## Pantalla de espera del mulligan que tapa la ventana: "" / "waiting" (mantuviste tu mano) / "showing"
## (estás mostrando la tuya).
var _mulligan_loading: String = ""
