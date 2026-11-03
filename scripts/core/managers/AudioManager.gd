extends Node
## AudioManager — Gestor centralizado de audio (música de fondo y efectos de sonido).
## Se ejecuta como Autoload global persistente entre cambios de escena.

enum ClickSoundStyle {
	WOOD,   # Clack de madera pulida / táctil cálido
	STONE,  # Golpe de losa / piedra tallada medieval
	COIN    # Tintineo sutil de bronce / moneda de oro
}

const DEFAULT_BGM_PATH := "res://assets/audio/music/the_final_vigil.mp3"

const SFX_HOVER_SOFT := preload("res://assets/audio/sfx/ui/btn_hover_soft.wav")
const SFX_CLICK_WOOD := preload("res://assets/audio/sfx/ui/btn_click_wood.wav")
const SFX_CLICK_STONE := preload("res://assets/audio/sfx/ui/btn_click_stone.wav")
const SFX_CLICK_COIN := preload("res://assets/audio/sfx/ui/btn_click_coin.wav")
const SFX_ACTION_HEAVY := preload("res://assets/audio/sfx/ui/btn_action_heavy.wav")

var current_click_style: ClickSoundStyle = ClickSoundStyle.WOOD

var _player_1: AudioStreamPlayer = null
var _player_2: AudioStreamPlayer = null
var _active_player: AudioStreamPlayer = null
var _current_music_path: String = ""
var _music_tween: Tween = null
var _is_paused: bool = false

# Control de rebote (cooldown) para evitar saturación de hovers simultáneos
var _last_hover_time: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	call_deferred("_start_default_bgm")
	call_deferred("_hook_scene_buttons")


func _setup_audio_players() -> void:
	# Asegurar que los buses Music y SFX existan en AudioServer
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")

	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

	_player_1 = AudioStreamPlayer.new()
	_player_1.name = "MusicPlayer1"
	_player_1.bus = "Music"
	_player_1.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_1)

	_player_2 = AudioStreamPlayer.new()
	_player_2.name = "MusicPlayer2"
	_player_2.bus = "Music"
	_player_2.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_2)

	_player_1.finished.connect(func(): _on_player_finished(_player_1))
	_player_2.finished.connect(func(): _on_player_finished(_player_2))


func _start_default_bgm() -> void:
	if ResourceLoader.exists(DEFAULT_BGM_PATH):
		play_music(DEFAULT_BGM_PATH, 1.2, true)


func _on_player_finished(player: AudioStreamPlayer) -> void:
	if player == _active_player and not _is_paused and is_instance_valid(player.stream):
		player.play()


# =============================================================================
# CONTROL DE MÚSICA DE FONDO (BGM)
# =============================================================================

func play_music(music_path_or_stream, fade_duration: float = 1.0, loop: bool = true) -> void:
	"""Reproduce música de fondo con fundido suave (fade in/crossfade).
	Si ya se está reproduciendo la misma pista, no la reinicia."""
	var stream: AudioStream = null
	var path_str: String = ""

	if music_path_or_stream is String:
		path_str = music_path_or_stream
		if path_str == _current_music_path and is_music_playing():
			return
		if not ResourceLoader.exists(path_str):
			push_warning("[AudioManager] Archivo de música no encontrado: %s" % path_str)
			return
		stream = load(path_str)
	elif music_path_or_stream is AudioStream:
		stream = music_path_or_stream
		path_str = stream.resource_path
		if path_str != "" and path_str == _current_music_path and is_music_playing():
			return

	if not stream:
		return

	if loop:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true

	_current_music_path = path_str
	_is_paused = false

	var next_player: AudioStreamPlayer = _player_2 if _active_player == _player_1 else _player_1
	var prev_player: AudioStreamPlayer = _active_player

	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play()
	_active_player = next_player

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(next_player, "volume_db", 0.0, maxf(fade_duration, 0.05)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	if prev_player and prev_player.playing:
		_music_tween.tween_property(prev_player, "volume_db", -80.0, maxf(fade_duration, 0.05)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_music_tween.chain().tween_callback(func():
			if is_instance_valid(prev_player) and prev_player != _active_player:
				prev_player.stop()
		)


func stop_music(fade_duration: float = 1.0) -> void:
	"""Detiene la música con fade out."""
	_current_music_path = ""
	_is_paused = false
	if not _active_player or not _active_player.playing:
		return

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	var player_to_stop = _active_player
	_active_player = null

	_music_tween = create_tween()
	_music_tween.tween_property(player_to_stop, "volume_db", -80.0, maxf(fade_duration, 0.05)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_music_tween.tween_callback(func():
		if is_instance_valid(player_to_stop):
			player_to_stop.stop()
	)


func pause_music() -> void:
	if _active_player and _active_player.playing and not _is_paused:
		_active_player.stream_paused = true
		_is_paused = true


func resume_music() -> void:
	if _active_player and _is_paused:
		_active_player.stream_paused = false
		_is_paused = false


func is_music_playing() -> bool:
	return _active_player != null and _active_player.playing and not _is_paused


# =============================================================================
# EFECTOS DE SONIDO DE INTERFAZ (UI SFX)
# =============================================================================

func play_ui_hover() -> void:
	"""Sonido de roce suave de pergamino al posar el cursor sobre un botón."""
	var now = Time.get_ticks_msec()
	if now - _last_hover_time < 35:
		return
	_last_hover_time = now

	# Variación sutil de pitch (0.97 - 1.03) para que suene orgánico
	var pitch = randf_range(0.97, 1.03)
	play_sfx(SFX_HOVER_SOFT, pitch, -10.0)


func play_ui_click(style: int = -1) -> void:
	"""Sonido de pulsación de botón según el estilo medieval activo."""
	var chosen_style = style if style >= 0 else current_click_style
	var stream: AudioStream = SFX_CLICK_WOOD
	match chosen_style:
		ClickSoundStyle.STONE:
			stream = SFX_CLICK_STONE
		ClickSoundStyle.COIN:
			stream = SFX_CLICK_COIN
		_:
			stream = SFX_CLICK_WOOD

	var pitch = randf_range(0.98, 1.02)
	play_sfx(stream, pitch, -3.0)


func play_ui_action_heavy() -> void:
	"""Sonido de impacto más rotundo para botones de acción mayor (JUGAR, Pasar, Confirmar)."""
	var pitch = randf_range(0.99, 1.01)
	play_sfx(SFX_ACTION_HEAVY, pitch, 0.0)


func set_click_style(style: ClickSoundStyle) -> void:
	current_click_style = style


func set_click_style_by_name(style_name: String) -> void:
	match style_name.to_lower():
		"stone":
			current_click_style = ClickSoundStyle.STONE
		"coin":
			current_click_style = ClickSoundStyle.COIN
		_:
			current_click_style = ClickSoundStyle.WOOD


func is_master_muted() -> bool:
	return GameSettings.master_volume <= 0.01


func toggle_mute_master() -> bool:
	if is_master_muted():
		var restored: float = 1.0
		if GameSettings.has_meta(&"prev_master_volume"):
			restored = float(GameSettings.get_meta(&"prev_master_volume"))
		if restored <= 0.05:
			restored = 1.0
		GameSettings.set_master_volume(restored)
		return false
	else:
		GameSettings.set_meta(&"prev_master_volume", GameSettings.master_volume)
		GameSettings.set_master_volume(0.0)
		return true


func is_music_muted() -> bool:
	return GameSettings.music_volume <= 0.01


func is_sfx_muted() -> bool:
	return GameSettings.sfx_volume <= 0.01


func toggle_mute_music() -> bool:
	if is_music_muted():
		var restored: float = 0.8
		if GameSettings.has_meta(&"prev_music_volume"):
			restored = float(GameSettings.get_meta(&"prev_music_volume"))
		if restored <= 0.05:
			restored = 0.8
		GameSettings.set_music_volume(restored)
		return false
	else:
		GameSettings.set_meta(&"prev_music_volume", GameSettings.music_volume)
		GameSettings.set_music_volume(0.0)
		return true


func toggle_mute_sfx() -> bool:
	if is_sfx_muted():
		var restored: float = 1.0
		if GameSettings.has_meta(&"prev_sfx_volume"):
			restored = float(GameSettings.get_meta(&"prev_sfx_volume"))
		if restored <= 0.05:
			restored = 1.0
		GameSettings.set_sfx_volume(restored)
		return false
	else:
		GameSettings.set_meta(&"prev_sfx_volume", GameSettings.sfx_volume)
		GameSettings.set_sfx_volume(0.0)
		return true


func play_sfx(stream: AudioStream, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	"""Reproduce un efecto de sonido descartable en el bus SFX."""
	if not stream:
		return
	var sfx_player := AudioStreamPlayer.new()
	sfx_player.stream = stream
	sfx_player.bus = "SFX"
	sfx_player.pitch_scale = pitch_scale
	sfx_player.volume_db = volume_db
	add_child(sfx_player)
	sfx_player.finished.connect(sfx_player.queue_free)
	sfx_player.play()


# =============================================================================
# HOOK AUTOMÁTICO PARA BOTONES DE TODA LA APLICACIÓN
# =============================================================================

func _hook_scene_buttons() -> void:
	var tree = get_tree()
	if not tree:
		return
	tree.node_added.connect(_on_tree_node_added)
	_scan_and_hook_recursive(tree.root)


func _on_tree_node_added(node: Node) -> void:
	if node is Button:
		_hook_button(node as Button)


func _scan_and_hook_recursive(node: Node) -> void:
	if node is Button:
		_hook_button(node as Button)
	for child in node.get_children():
		_scan_and_hook_recursive(child)


func _hook_button(btn: Button) -> void:
	if btn.has_meta(&"sfx_hooked"):
		return
	btn.set_meta(&"sfx_hooked", true)

	btn.mouse_entered.connect(func():
		if not btn.disabled and btn.is_visible_in_tree():
			play_ui_hover()
	)

	btn.pressed.connect(func():
		if btn.has_meta(&"sfx_heavy") or btn.name in ["PlayButton", "PasoButton", "BtnComenzarPartida"]:
			play_ui_action_heavy()
		elif btn.has_meta(&"sfx_coin"):
			play_ui_click(ClickSoundStyle.COIN)
		elif btn.has_meta(&"sfx_stone"):
			play_ui_click(ClickSoundStyle.STONE)
		else:
			play_ui_click()
	)
