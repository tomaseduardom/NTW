extends Node
class_name MatchConnectionWatcher
## MatchConnectionWatcher — instanciado siempre en Main.gd, solo actúa con una sala activa. Cierra
## la partida en línea cuando alguien se va:
## - El rival se desconecta (peer_disconnected): con la partida en curso gana el que queda; antes de
##   empezar se avisa y se vuelve al menú.
## - Se cae la conexión propia (connection_lost): se avisa y se vuelve al menú.
## - Fin de partida: el Anfitrión manda {"op":"game_over","winner"} (winner del lado del Anfitrión)
##   y el Remoto muestra la misma pantalla de Victoria/Derrota.
## - Concesión del Remoto: {"op":"concede"} al Anfitrión, que lo aplica con GameManager.
## Al salir de una partida en línea (menú de pausa, fin de partida) se llama leave_match().

var _main: Node = null
var _active: bool = false
var _ended: bool = false
## Remoto: ya llegó algo de la partida (dados o un prompt) — desde ahí una desconexión del
## Anfitrión es victoria y no "partida cancelada".
var _remote_started: bool = false


func setup(main: Node) -> void:
	_main = main
	_active = NetworkClient.room_code != ""
	if not _active:
		return
	NetworkClient.peer_disconnected.connect(_on_peer_disconnected)
	NetworkClient.connection_lost.connect(_on_connection_lost)
	NetworkClient.message_received.connect(_on_message)
	GameManager.game_ended.connect(_on_game_ended)


static func is_online() -> bool:
	return NetworkClient.room_code != ""


static func leave_match() -> void:
	"""Sale de la sala al dejar la partida: el otro lado recibe peer_disconnected."""
	if NetworkClient.room_code != "":
		NetworkClient.disconnect_from_relay()


static func concede() -> void:
	"""Concesión desde el menú de pausa: el Anfitrión la aplica directo; el Remoto se la pide."""
	if NetworkClient.room_code != "" and not NetworkClient.is_host:
		NetworkClient.send_message({"op": "concede"})
	else:
		GameManager.player_loses(0, "Concesión de la partida")


func _cancelled_by_bootstrap() -> bool:
	return _main and _main._bootstrap and _main._bootstrap._match_cancelled


func _on_message(data: Dictionary) -> void:
	match str(data.get("op", "")):
		"game_over":
			if not NetworkClient.is_host and not _ended:
				_ended = true
				# winner viene del lado del Anfitrión: el Remoto es su jugador 1.
				_main._on_game_ended(1 - int(data.get("winner", 0)))
		"concede":
			if NetworkClient.is_host and GameManager.is_game_active:
				GameManager.player_loses(1, "Concesión del rival")
		"dice_roll", "prompt":
			_remote_started = true


func _on_game_ended(winner: int) -> void:
	_ended = true
	if NetworkClient.is_host:
		NetworkClient.send_message({"op": "game_over", "winner": winner})


func _on_peer_disconnected() -> void:
	if _ended or _cancelled_by_bootstrap():
		return
	if NetworkClient.is_host and GameManager.is_game_active:
		GameManager.player_loses(1, "Desconexión del rival")
		return
	if not NetworkClient.is_host and _remote_started:
		_ended = true
		_main._on_game_ended(0)
		return
	_ended = true
	_show_exit_dialog("El rival se desconectó", "El otro jugador salió antes de empezar la partida.")


func _on_connection_lost() -> void:
	if _ended or _cancelled_by_bootstrap():
		return
	_ended = true
	_show_exit_dialog("Conexión perdida", "Se perdió la conexión con el servidor. La partida terminó.")


func _show_exit_dialog(title: String, text: String) -> void:
	var loading_overlay := get_node_or_null("/root/MatchLoadingOverlay")
	if loading_overlay:
		loading_overlay.hide_loading()
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = "Volver al menú"
	dialog.exclusive = true
	dialog.confirmed.connect(_go_to_menu)
	dialog.canceled.connect(_go_to_menu)
	_main.add_child(dialog)
	dialog.popup_centered()


func _go_to_menu() -> void:
	leave_match()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
