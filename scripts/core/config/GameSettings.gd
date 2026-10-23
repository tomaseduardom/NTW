extends Node
## GameSettings - Gestiona la configuración del juego (dorsos, preferencias, etc.)

# =============================================================================
# SEÑALES
# =============================================================================
signal card_back_changed(back_id: String)
signal audio_volume_changed(bus_name: String, volume_linear: float)
signal animation_speed_changed(speed: float)
signal keybindings_changed

# =============================================================================
# CONSTANTES
# =============================================================================
const CONFIG_PATH = "user://settings.cfg"
const BACKS_PATH = "res://assets/card_backs/"

const BACK_FILES = {
	"dorso_1": "dorso_1.png",
	"dorso_2": "dorso_2.png",
	"dorso_3": "dorso_3.png",
}

const DEFAULT_KEYBINDINGS: Dictionary = {
	"pasar": KEY_P,              # Pasar Prioridad / Turno / Confirmar Ataque
	"toggle_mano": KEY_SPACE,    # Fijar / Reposar Mano
	"ocultar_mano": KEY_H,       # Ocultar / Mostrar Mano
	"historial": KEY_L,          # Abrir / Cerrar Historial y Estado
	"cancelar": KEY_N,           # Cancelar / Saltar Selección Opcional
}

const ACTION_LABELS: Dictionary = {
	"pasar": "Pasar Turno / Prioridad",
	"toggle_mano": "Fijar / Reposar Mano",
	"ocultar_mano": "Ocultar / Mostrar Mano",
	"historial": "Historial y Estado",
	"cancelar": "Cancelar / Saltar Selección",
}

const ACTION_DESCRIPTIONS: Dictionary = {
	"pasar": "Pasa prioridad, confirma ataque o fase de daño",
	"toggle_mano": "Fija la mano arriba o la baja a reposo",
	"ocultar_mano": "Oculta la mano completamente para ver la mesa",
	"historial": "Abre o cierra el panel lateral de historial",
	"cancelar": "Cancela la selección de objetivo o salta una acción opcional",
}

# =============================================================================
# VARIABLES
# =============================================================================
## Dorso del jugador local (player 0)
var player_card_back: String = "dorso_1"
## Dorso del oponente (player 1) - por defecto dorso_1
var opponent_card_back: String = "dorso_1"

## Ajustes de Audio (0.0 a 1.0)
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0

## Velocidad de Animación (1.0, 1.5, 2.0)
var animation_speed: float = 1.0

## Atajos de Teclado
var keybindings: Dictionary = DEFAULT_KEYBINDINGS.duplicate()

var _player_back_texture: Texture2D = null
var _opponent_back_texture: Texture2D = null


func _ready() -> void:
	_load_config()
	_load_back_textures()
	_apply_all_audio_settings()
	_apply_animation_speed()
	print("[GameSettings] Initialized - Player back: ", player_card_back, ", Opponent back: ", opponent_card_back, ", Speed: ", animation_speed)


func _load_config() -> void:
	"""Carga la configuración desde archivo"""
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	if err == OK:
		player_card_back = config.get_value("game", "player_card_back", "dorso_1")
		opponent_card_back = config.get_value("game", "opponent_card_back", "dorso_1")
		animation_speed = config.get_value("game", "animation_speed", 1.0)
		master_volume = config.get_value("audio", "master_volume", 1.0)
		music_volume = config.get_value("audio", "music_volume", 0.8)
		sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
		for action in DEFAULT_KEYBINDINGS.keys():
			keybindings[action] = int(config.get_value("controls", action, DEFAULT_KEYBINDINGS[action]))


func _save_config() -> void:
	"""Guarda la configuración a archivo"""
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("game", "player_card_back", player_card_back)
	config.set_value("game", "opponent_card_back", opponent_card_back)
	config.set_value("game", "animation_speed", animation_speed)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	for action in keybindings.keys():
		config.set_value("controls", action, keybindings[action])
	config.save(CONFIG_PATH)


# =============================================================================
# GESTIÓN DE ATAJOS Y CONTROLES
# =============================================================================
func get_key(action: String) -> int:
	"""Retorna el KeyCode configurado para una acción."""
	return keybindings.get(action, DEFAULT_KEYBINDINGS.get(action, KEY_NONE))


func set_key(action: String, keycode: int) -> void:
	"""Asigna un nuevo KeyCode a una acción y persiste la configuración."""
	if not DEFAULT_KEYBINDINGS.has(action):
		return
	keybindings[action] = keycode
	_save_config()
	keybindings_changed.emit()


func reset_keybindings_to_default() -> void:
	"""Restaura todos los atajos a sus valores predeterminados."""
	keybindings = DEFAULT_KEYBINDINGS.duplicate()
	_save_config()
	keybindings_changed.emit()


func get_key_display_string(keycode: int) -> String:
	"""Devuelve una representación de texto legible y limpia para una tecla."""
	match keycode:
		KEY_SPACE:
			return "ESPACIO"
		KEY_ENTER, KEY_KP_ENTER:
			return "ENTER"
		KEY_ESCAPE:
			return "ESC"
		KEY_TAB:
			return "TAB"
		KEY_BACKSPACE:
			return "RETROCESO"
		KEY_UP:
			return "ARRIBA"
		KEY_DOWN:
			return "ABAJO"
		KEY_LEFT:
			return "IZQUIERDA"
		KEY_RIGHT:
			return "DERECHA"
		KEY_CAPSLOCK:
			return "BLOQ MAYÚS"
		_:
			var s: String = OS.get_keycode_string(keycode).to_upper()
			return s if not s.is_empty() else "TECLA %d" % keycode


func _apply_all_audio_settings() -> void:
	apply_audio_bus_volume("Master", master_volume)
	apply_audio_bus_volume("Music", music_volume)
	apply_audio_bus_volume("SFX", sfx_volume)


func _apply_animation_speed() -> void:
	if not get_tree().paused:
		Engine.time_scale = animation_speed


func apply_audio_bus_volume(bus_name: String, val: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx < 0 and bus_name != "Master":
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(val, 0.0001, 1.0)))
		AudioServer.set_bus_mute(idx, val <= 0.01)


func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	apply_audio_bus_volume("Master", master_volume)
	_save_config()
	audio_volume_changed.emit("Master", master_volume)


func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	apply_audio_bus_volume("Music", music_volume)
	_save_config()
	audio_volume_changed.emit("Music", music_volume)


func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	apply_audio_bus_volume("SFX", sfx_volume)
	_save_config()
	audio_volume_changed.emit("SFX", sfx_volume)


func set_animation_speed(val: float) -> void:
	animation_speed = clampf(val, 0.5, 3.0)
	_apply_animation_speed()
	_save_config()
	animation_speed_changed.emit(animation_speed)


func _load_back_textures() -> void:
	"""Carga las texturas de dorso para ambos jugadores"""
	# Dorso del jugador
	var player_file = BACK_FILES.get(player_card_back, "dorso_1.png")
	_player_back_texture = load(BACKS_PATH + player_file)
	if not _player_back_texture:
		_player_back_texture = load(BACKS_PATH + "dorso_1.png")

	# Dorso del oponente
	var opponent_file = BACK_FILES.get(opponent_card_back, "dorso_1.png")
	_opponent_back_texture = load(BACKS_PATH + opponent_file)
	if not _opponent_back_texture:
		_opponent_back_texture = load(BACKS_PATH + "dorso_1.png")


# =============================================================================
# API PÚBLICA
# =============================================================================

func set_card_back(back_id: String, player_id: int = 0) -> void:
	"""Cambia el dorso de las cartas para un jugador específico"""
	var current = player_card_back if player_id == 0 else opponent_card_back
	print("[GameSettings] set_card_back llamado - player: ", player_id, ", back: ", back_id, " (actual: ", current, ")")

	if back_id == current:
		print("[GameSettings] Ya es el dorso actual, ignorando")
		return

	if not BACK_FILES.has(back_id):
		print("[GameSettings] Invalid back id: ", back_id)
		return

	if player_id == 0:
		player_card_back = back_id
	else:
		opponent_card_back = back_id

	_save_config()
	_load_back_textures()
	print("[GameSettings] Emitiendo señal card_back_changed...")
	card_back_changed.emit(back_id)
	print("[GameSettings] Card back changed for player ", player_id, " to: ", back_id)


func get_card_back_id(player_id: int = 0) -> String:
	"""Retorna el ID del dorso para un jugador"""
	return player_card_back if player_id == 0 else opponent_card_back


func get_card_back_texture(player_id: int = 0) -> Texture2D:
	"""Retorna la textura del dorso para un jugador"""
	if player_id == 0:
		if not _player_back_texture:
			_load_back_textures()
		return _player_back_texture
	else:
		if not _opponent_back_texture:
			_load_back_textures()
		return _opponent_back_texture
