extends Control
## Main - Escena principal del juego. Punto de entrada que instancia módulos y conecta señales.

@export var test_mode: bool = false

# =============================================================================
# ESCENAS PRECARGADAS
# =============================================================================
const CardScene = preload("res://scenes/cards/Card.tscn")
# preload y no el class_name global: un editor abierto desde antes de crear la clase no la tiene
# registrada y falla con "Could not find type".
const ZoneBrowsePickerScript = preload("res://scripts/ui/zones/ZoneBrowsePicker.gd")
const DropZoneScript = preload("res://scripts/ui/zones/DropZone.gd")
const OpponentFanScript = preload("res://scripts/ui/hand/OpponentFan.gd")
const GameStateScript = preload("res://scripts/core/config/GameState.gd")

# Preloads de módulos (fuerzan registro de class_name antes del parse de Main)
const _ZoneManagerScript      = preload("res://scripts/core/game/ZoneManager.gd")
const _PhaseFlowScript        = preload("res://scripts/core/game/PhaseFlowController.gd")
const _GameHUDScript          = preload("res://scripts/ui/hud/GameHUDModule.gd")
const _GameBootstrapScript    = preload("res://scripts/core/game/GameBootstrap.gd")
const _CardInteractionScript  = preload("res://scripts/ui/hud/CardInteractionModule.gd")
const _SceneSetupScript       = preload("res://scripts/ui/hud/SceneSetupModule.gd")
const _DebugInputScript       = preload("res://scripts/ui/hud/DebugInputModule.gd")
const _ActionLogDrawerScript  = preload("res://scripts/ui/hud/ActionLogDrawer.gd")
const MatchConnectionWatcherScript = preload("res://scripts/core/network/MatchConnectionWatcher.gd")
const TurnClockScript = preload("res://scripts/core/network/TurnClock.gd")

# =============================================================================
# REFERENCIAS A NODOS
# =============================================================================

@onready var turn_label: Label               = $TopBar/TurnLabel
@onready var phase_label: Label              = $TopBar/PhaseLabel
@onready var player_info: Label              = $TopBar/PlayerInfo
@onready var debug_label: Label              = $UI/DebugPanel/DebugLabel
@onready var game_board: Control             = $GameBoard
@onready var player_hand: Control            = $GameBoard/PlayerArea/PlayerHand
@onready var player_field: HBoxContainer     = $GameBoard/PlayerArea/PlayerField
@onready var player_linea_ataque: HBoxContainer = $GameBoard/PlayerArea/PlayerLineaAtaque
@onready var player_linea_apoyo: HBoxContainer  = $GameBoard/PlayerArea/PlayerLineaApoyo
@onready var player_gold: HBoxContainer      = $GameBoard/PlayerArea/PlayerReservaOro
@onready var player_oro_pagado: HBoxContainer= $GameBoard/PlayerArea/PlayerOroPagado
@onready var opponent_field: HBoxContainer   = $GameBoard/OpponentArea/OpponentField
@onready var opponent_linea_ataque: HBoxContainer = $GameBoard/OpponentArea/OpponentLineaAtaque
@onready var opponent_linea_apoyo: HBoxContainer  = $GameBoard/OpponentArea/OpponentLineaApoyo
# Contenedores del Oro del oponente (Reserva y Oro Pagado): sus Oros se muestran como cartas reales,
# además del número en OpponentReservaOroLabel/OpponentOroPagadoLabel.
@onready var opponent_gold: HBoxContainer         = $GameBoard/OpponentArea/OpponentReservaOro
@onready var opponent_oro_pagado: HBoxContainer   = $GameBoard/OpponentArea/OpponentOroPagado
var _opponent_fan: Node = null

@onready var player_castillo_count: Label    = $GameBoard/PlayerArea/PlayerCastillo/Count
@onready var player_cementerio_count: Label  = $GameBoard/PlayerArea/PlayerCementerio/Count
@onready var player_destierro_count: Label   = $GameBoard/PlayerArea/PlayerDestierro/Count
@onready var opponent_castillo_count: Label  = $GameBoard/OpponentArea/OpponentCastillo/Count
@onready var opponent_cementerio_count: Label= $GameBoard/OpponentArea/OpponentCementerio/Count
@onready var opponent_destierro_count: Label = $GameBoard/OpponentArea/OpponentDestierro/Count

@onready var _panel_player_castillo: Panel = $GameBoard/PlayerArea/PlayerCastillo
@onready var _panel_opp_castillo: Panel    = $GameBoard/OpponentArea/OpponentCastillo
@onready var _panel_player_cem: Panel = $GameBoard/PlayerArea/PlayerCementerio
@onready var _panel_player_dst: Panel = $GameBoard/PlayerArea/PlayerDestierro
@onready var _panel_opp_cem: Panel    = $GameBoard/OpponentArea/OpponentCementerio
@onready var _panel_opp_dst: Panel    = $GameBoard/OpponentArea/OpponentDestierro

@onready var player_oro_reserva_label: Label   = $GameBoard/PlayerArea/GoldAreaLabel
@onready var player_oro_pagado_label: Label    = $GameBoard/PlayerArea/OroPagadoLabel
@onready var opponent_oro_reserva_label: Label = $GameBoard/OpponentArea/OpponentReservaOroLabel
@onready var opponent_oro_pagado_label: Label  = $GameBoard/OpponentArea/OpponentOroPagadoLabel
@onready var timer_label: Label                = $TurnTimer/VBox/TimerLabel

@onready var mulligan_overlay: Panel      = $UI/MulliganOverlay
@onready var mulligan_hand: MulliganHand  = $UI/MulliganOverlay/MulliganHand
@onready var mulligan_cards_label: Label  = $UI/MulliganOverlay/MulliganCardsLabel
@onready var keep_hand_button: Button     = $UI/MulliganOverlay/MulliganButtons/KeepHandButton
@onready var mulligan_button: Button      = $UI/MulliganOverlay/MulliganButtons/MulliganButton

@onready var inspection_layer: CanvasLayer      = $CardInspectionLayer
@onready var inspection_blur: ColorRect         = $CardInspectionLayer/BlurBackground
@onready var inspection_container: CenterContainer = $CardInspectionLayer/CardContainer

# =============================================================================
# MÓDULOS (hijos Node creados en _ready)
# =============================================================================
var _gold_manager: GoldManager             = null
var _mulligan_ctrl: MulliganController     = null
var _card_inspector: CardInspectionLayer   = null
var _zone_viewer: ZoneViewerModule         = null
var _zone_browse_picker: Node               = null  # ZoneBrowsePicker (ver ZoneBrowsePickerScript)
var _selection: SelectionModule            = null
var _zone_manager: ZoneManager             = null
var _phase_flow: PhaseFlowController       = null
var _easy_bot: EasyBotController           = null
var _game_hud: GameHUDModule               = null
var _bootstrap: GameBootstrap              = null
var _card_interaction: CardInteractionModule = null
var _scene_setup: SceneSetupModule         = null
var _debug_input: DebugInputModule         = null
var _remote_mirror: RemoteMirrorController  = null
var _state_broadcaster: GameStateBroadcaster = null
var _connection_watcher: Node = null
var _turn_clock: Node = null
var _game_over_overlay: GameOverOverlay    = null
var _combat_juice: CombatJuiceModule       = null
var _action_log_drawer: Node               = null

# =============================================================================
# ESTADO
# =============================================================================
var _dice_winner: int = 0
var gold_cards: Array = []
var player_deck: Array = []
var opponent_deck: Array = []
var player_cemetery: Array = []
var opponent_cemetery: Array = []
const INITIAL_HAND_SIZE: int = 8  # DAR 4.3

# =============================================================================
# INICIALIZACIÓN
# =============================================================================
func _ready() -> void:
	print("[Main] Escena principal cargada")
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_ended.connect(_on_game_ended)

	# ── Módulos ──────────────────────────────────────────────────────────────
	_scene_setup = SceneSetupModule.new(); _scene_setup.name = "SceneSetupModule"
	add_child(_scene_setup); _scene_setup.setup(self)

	_game_hud = GameHUDModule.new(); _game_hud.name = "GameHUDModule"
	add_child(_game_hud); _game_hud.setup(self)

	_zone_manager = ZoneManager.new(); _zone_manager.name = "ZoneManager"
	add_child(_zone_manager); _zone_manager.setup(self)

	# Multijugador remoto (docs/plans/2026-09-09-multiplayer-remoto-design.md): si esta instancia es el
	# Anfitrión de una sala activa, el jugador 1 lo controla una persona por red.
	# RemotePlayerController extiende EasyBotController con la misma superficie pública
	# (_easy_bot.<método>).
	if NetworkClient.room_code != "" and NetworkClient.is_host:
		_easy_bot = RemotePlayerController.new()
	else:
		_easy_bot = EasyBotController.new()
	_easy_bot.name = "EasyBotController"
	add_child(_easy_bot); _easy_bot.setup(self)

	# Etiqueta superior "Jugador N" según quién mira la pantalla: en una sala online el Remoto es
	# Jugador 2; en cualquier otro modo (local, contra el bot), la persona es Jugador 1.
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		player_info.text = "Jugador 2"

	# Multiplayer remoto — lado Remoto: si esta instancia es el Remoto de una
	# sala de red activa, RemoteMirrorController es lo que le permite seguir
	# jugando después de mandar su mazo (ver GameBootstrap._send_own_deck_
	# and_wait_for_host()) — sin esto, se quedaría en la pantalla de espera
	# para siempre. No hace nada si esta instancia es el Anfitrión o no hay
	# sala de red activa (chequea NetworkClient en su propio setup()).
	_remote_mirror = RemoteMirrorController.new(); _remote_mirror.name = "RemoteMirrorController"
	add_child(_remote_mirror); _remote_mirror.setup(self)

	# Multiplayer remoto — lado Anfitrión: traduce on_card_entered_play/
	# on_card_left_play (señales que EffectController ya emite) a
	# instrucciones de red para que RemoteMirrorController, del otro lado,
	# pueda reflejar el tablero. Inerte si no hay sala de red activa o esta
	# instancia no es el Anfitrión (chequea NetworkClient en su setup()).
	_state_broadcaster = GameStateBroadcaster.new(); _state_broadcaster.name = "GameStateBroadcaster"
	add_child(_state_broadcaster); _state_broadcaster.setup(self)

	# Partida en línea: desconexiones, fin de partida y concesión del Remoto. Inerte sin sala.
	_connection_watcher = MatchConnectionWatcherScript.new(); _connection_watcher.name = "MatchConnectionWatcher"
	add_child(_connection_watcher); _connection_watcher.setup(self)

	# Partida en línea: reloj de turno (1 minuto, +2 s por acción). Inerte sin sala.
	_turn_clock = TurnClockScript.new(); _turn_clock.name = "TurnClock"
	add_child(_turn_clock); _turn_clock.setup(self)

	_phase_flow = PhaseFlowController.new(); _phase_flow.name = "PhaseFlowController"
	add_child(_phase_flow); _phase_flow.setup(self)

	_gold_manager = GoldManager.new(); _gold_manager.name = "GoldManager"
	add_child(_gold_manager); _gold_manager.setup(self)

	_card_interaction = CardInteractionModule.new(); _card_interaction.name = "CardInteractionModule"
	add_child(_card_interaction); _card_interaction.setup(self)

	_mulligan_ctrl = MulliganController.new(); _mulligan_ctrl.name = "MulliganController"
	add_child(_mulligan_ctrl); _mulligan_ctrl.setup(self)

	_card_inspector = CardInspectionLayer.new(); _card_inspector.name = "CardInspectorModule"
	add_child(_card_inspector); _card_inspector.setup(self)

	_zone_viewer = ZoneViewerModule.new(); _zone_viewer.name = "ZoneViewerModule"
	add_child(_zone_viewer); _zone_viewer.setup(self)

	_zone_browse_picker = ZoneBrowsePickerScript.new(); _zone_browse_picker.name = "ZoneBrowsePicker"
	add_child(_zone_browse_picker); _zone_browse_picker.setup(self)

	_selection = SelectionModule.new(); _selection.name = "SelectionModule"
	add_child(_selection); _selection.setup(self)

	_bootstrap = GameBootstrap.new(); _bootstrap.name = "GameBootstrap"
	add_child(_bootstrap); _bootstrap.setup(self)

	_debug_input = DebugInputModule.new(); _debug_input.name = "DebugInputModule"
	# PROCESS_MODE_ALWAYS: este nodo es dueño del _input() que escucha ESC; con el árbol pausado
	# dejaría de recibirlo y ESC no cerraría el menú de pausa (pause_menu ya usa este modo,
	# SceneSetupModule.gd).
	_debug_input.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_debug_input); _debug_input.setup(self)

	_combat_juice = CombatJuiceModule.new()
	add_child(_combat_juice)
	_combat_juice.setup(self)

	_action_log_drawer = _ActionLogDrawerScript.new()
	_action_log_drawer.name = "ActionLogDrawer"
	add_child(_action_log_drawer)
	_action_log_drawer.setup(self)

	VisualManager.setup(self, $Background)

	UIManager.setup({
		"turn_label": turn_label, "phase_label": phase_label,
		"player_info": player_info, "debug_label": debug_label,
		"timer_label": timer_label,
		"player_castillo_count": player_castillo_count,
		"player_cementerio_count": player_cementerio_count,
		"player_destierro_count": player_destierro_count,
		"opponent_castillo_count": opponent_castillo_count,
		"opponent_cementerio_count": opponent_cementerio_count,
		"opponent_destierro_count": opponent_destierro_count,
		"player_oro_reserva_label": player_oro_reserva_label,
		"player_oro_pagado_label": player_oro_pagado_label,
		"opponent_oro_reserva_label": opponent_oro_reserva_label,
		"opponent_oro_pagado_label": opponent_oro_pagado_label,
	})

	_bootstrap.start()


# =============================================================================
# CARTA — fábrica y señales
# =============================================================================
func _create_card(data: Dictionary, is_hidden: bool = false) -> Node:
	var card = CardScene.instantiate()
	card.load_from_data(data, is_hidden)
	return card


func _connect_card_signals(card: Node) -> void:
	card.card_clicked.connect(_card_interaction._on_card_clicked)
	card.card_double_clicked.connect(_card_interaction._on_card_double_clicked)
	card.card_right_clicked.connect(_card_inspector.on_card_right_clicked)
	card.card_hovered.connect(_card_interaction._on_card_hovered)
	card.card_unhovered.connect(_card_interaction._on_card_unhovered)
	card.card_dropped.connect(_card_interaction._on_card_dropped)


# =============================================================================
# CALLBACKS DEL GAMEMANAGER
# =============================================================================
func _on_game_started() -> void:
	_update_debug("Partida iniciada!")

func _on_game_ended(winner: int) -> void:
	_update_debug("Jugador %d gana!" % (winner + 1))
	UIManager.set_phase_text("¡VICTORIA!" if winner == 0 else "DERROTA")

	var stats: Dictionary = {
		"winner": winner,
		"is_victory": (winner == 0),
		"turns": GameManager.current_turn,
		"player_deck": player_deck.size() if player_deck is Array else 0,
		"opponent_deck": opponent_deck.size() if opponent_deck is Array else 0,
		"player_cemetery": CardManager.get_cemetery_count(0),
		"opponent_cemetery": CardManager.get_cemetery_count(1),
		"player_exile": CardManager.get_exile_count(0),
		"opponent_exile": CardManager.get_exile_count(1),
	}

	if not _game_over_overlay:
		_game_over_overlay = GameOverOverlay.new()
		_game_over_overlay.name = "GameOverOverlay"
		add_child(_game_over_overlay)

	_game_over_overlay.show_game_over(stats)

func _update_buttons_for_phase(_phase: Constants.Phase) -> void:
	pass

func get_deck_size(player_id: int) -> int:
	return CardManager.get_deck_count(player_id)

func _sync_oro_ui() -> void:
	UIManager.update_oro_reserva(0, GameState.get_oro_reserva(0))
	UIManager.update_oro_pagado(0, GameState.get_oro_pagado(0))
	UIManager.update_oro_reserva(1, GameState.get_oro_reserva(1))
	UIManager.update_oro_pagado(1, GameState.get_oro_pagado(1))


# =============================================================================
# DEBUG
# =============================================================================
# Los atajos F1-F9/ESC y su _input() están en DebugInputModule.gd. _update_debug() queda aquí: es
# infraestructura mínima usada por todo el proyecto (_main._update_debug()).
var _last_debug_text: String = ""


func _update_debug(text: String) -> void:
	UIManager.show_debug(text)
	# ("quitar el log redundante, hay bastante"): un rechazo repetido (clicks fallidos seguidos, p.ej.
	# "Objetivo no válido" varias veces) imprimía la misma línea una vez por click — la UI ya se
	# actualiza igual (el jugador ve el mensaje en pantalla cada vez), solo se evita reimprimir la
	# MISMA línea dos veces seguidas en consola.
	if text != _last_debug_text:
		print("[Main] %s" % text)
		_last_debug_text = text
