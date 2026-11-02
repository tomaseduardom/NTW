extends Node
## AudioManager — Gestor centralizado de audio (música de fondo y efectos de sonido).
## Se ejecuta como Autoload global persistente entre cambios de escena.

const DEFAULT_BGM_PATH := "res://assets/audio/music/the_final_vigil.mp3"

var _player_1: AudioStreamPlayer = null
var _player_2: AudioStreamPlayer = null
var _active_player: AudioStreamPlayer = null
var _current_music_path: String = ""
var _music_tween: Tween = null
var _is_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	# Inicia la música por defecto suavemente al arrancar el juego
	call_deferred("_start_default_bgm")


func _setup_audio_players() -> void:
	# Asegurar que el bus Music exista antes de asignar
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
	# Garantía de bucle continuo si la pista termina
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

	# Configurar bucle en el stream según tipo
	if loop:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true

	_current_music_path = path_str
	_is_paused = false

	# Seleccionar el reproductor alternativo para crossfade
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
# REPRODUCCIÓN DE EFECTOS DE SONIDO (SFX)
# =============================================================================

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

