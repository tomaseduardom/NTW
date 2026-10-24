extends Node
class_name MulliganController
## MulliganController — Gestiona la fase de mulligan inicial (DAR 4.3).
## Se instancia como hijo de Main en _ready().

var _main: Node = null
var is_in_mulligan: bool = false
var mulligan_count: int = 0
var mulligan_hand_data: Array = []
## Mulligan del Remoto corriendo en paralelo al propio (ver start_mulligan_phase).
var _remote_mulligan_done: bool = true
## Mulligan gratis (DAR abril 2026, 4.3): una vez por partida, si muestras tu mano con uno o menos Oros,
## la cambias Robando la misma cantidad de cartas. El botón se crea aquí, junto a los otros dos; el
## Remoto lo reusa (RemoteMirrorController._show_mulligan_prompt()).
var free_mulligan_used: bool = false
var free_mulligan_button: Button = null
## Los dos jugadores nunca muestran la mano a la vez: un turno de "mostrar" que coordina el Anfitrión.
## Cada mano queda mostrada hasta que el rival cierra la ventana; si los dos lo piden, va primero el
## Anfitrión.
var _reveal_busy: bool = false
var _host_reveal_waiting: bool = false

func setup(main: Node) -> void:
	_main = main
	_main.keep_hand_button.pressed.connect(on_keep_hand_pressed)
	_main.mulligan_button.pressed.connect(on_mulligan_pressed)
	_main.mulligan_hand.card_right_clicked.connect(_on_mulligan_card_right_clicked)
	free_mulligan_button = Button.new()
	free_mulligan_button.name = "FreeMulliganButton"
	free_mulligan_button.visible = false
	_main.mulligan_button.get_parent().add_child(free_mulligan_button)
	free_mulligan_button.pressed.connect(on_free_mulligan_pressed)


static func gold_count(hand_data: Array) -> int:
	return hand_data.filter(func(d): return d is Dictionary and int(d.get("tipo", -1)) == Constants.CardType.ORO).size()


## Configura el botón de mulligan gratis (lo usa también el Remoto con la elegibilidad que manda el Anfitrión).
func set_free_button(available: bool, golds: int) -> void:
	if not free_mulligan_button:
		return
	free_mulligan_button.visible = available
	free_mulligan_button.disabled = not available
	free_mulligan_button.text = "Mulligan gratis: mostrar mano (%d Oro%s)" % [golds, "" if golds == 1 else "s"]


func _on_mulligan_card_right_clicked(card: Node) -> void:
	if _main and _main._card_inspector:
		_main._card_inspector.on_card_right_clicked(card)


func start_mulligan_phase() -> void:
	print("[Mulligan] === Iniciando ===")
	_main._bootstrap._setup_oro_inicial()
	print("[Mulligan] Cartas en mazo jugador: %d" % _main.player_deck.size())
	is_in_mulligan = true
	mulligan_count = 0
	free_mulligan_used = false
	UIManager.set_phase_text("Mulligan")
	_main.mulligan_overlay.visible = true
	await get_tree().process_frame
	print("[Mulligan] Overlay visible, robando mano...")
	_draw_mulligan_hand(_main.INITIAL_HAND_SIZE)
	_update_mulligan_ui()
	print("[Mulligan] Mulligan listo con %d cartas" % mulligan_hand_data.size())
	# Los dos jugadores ven su mano y hacen el mulligan al mismo tiempo: el del Remoto arranca en
	# paralelo (sin await) y _end_mulligan_phase() espera a que ambos elijan.
	if _main._easy_bot is RemotePlayerController:
		_remote_mulligan_done = false
		_run_remote_mulligan()


func _run_remote_mulligan() -> void:
	await _main._easy_bot.run_mulligan(_main.INITIAL_HAND_SIZE)
	_remote_mulligan_done = true


func _draw_mulligan_hand(count: int) -> void:
	_main.mulligan_hand.clear_cards_instant()
	mulligan_hand_data.clear()
	var castillo_pos = _main.get_node("GameBoard/PlayerArea/PlayerCastillo").global_position
	_main.mulligan_hand.set_deck_position(_main.mulligan_hand.get_global_transform().affine_inverse() * castillo_pos)
	for i in range(count):
		if _main.player_deck.is_empty():
			break
		var card_data = _main.player_deck.pop_front()
		mulligan_hand_data.append(card_data)
	_main.mulligan_hand.add_cards_with_animation(mulligan_hand_data, _main._create_card)
	_main._zone_manager._update_castillo_counts()


func _update_mulligan_ui() -> void:
	var current_hand_size = mulligan_hand_data.size()
	_main.mulligan_cards_label.text = "Mano actual: %d cartas" % current_hand_size
	var next_hand_size = current_hand_size - 1
	if next_hand_size <= 0:
		_main.mulligan_button.disabled = true
		_main.mulligan_button.text = "No puedes hacer mas mulligan"
	else:
		_main.mulligan_button.disabled = false
		_main.mulligan_button.text = "Mulligan (robar %d)" % next_hand_size
	var golds: int = gold_count(mulligan_hand_data)
	set_free_button(not free_mulligan_used and golds <= 1 and current_hand_size > 0, golds)


func on_keep_hand_pressed() -> void:
	if _main and _main._card_inspector:
		_main._card_inspector.close_card_inspection()
	print("[Mulligan] Jugador se queda con la mano de %d cartas" % mulligan_hand_data.size())
	_end_mulligan_phase()


func on_mulligan_pressed() -> void:
	if _main and _main._card_inspector:
		_main._card_inspector.close_card_inspection()
	var next_hand_size = mulligan_hand_data.size() - 1
	if next_hand_size <= 0:
		return
	print("[Mulligan] Jugador hace mulligan (mano anterior: %d, nueva: %d)" % [mulligan_hand_data.size(), next_hand_size])
	mulligan_count += 1
	await _redraw(next_hand_size)


func _acquire_reveal(host: bool) -> void:
	if host:
		_host_reveal_waiting = true
	while _reveal_busy or (not host and _host_reveal_waiting):
		await get_tree().process_frame
	_reveal_busy = true
	if host:
		_host_reveal_waiting = false


## Mulligan gratis del Remoto (RemotePlayerController.run_mulligan()): el Anfitrión ve su mano, cuando
## le toque el turno de mostrar, hasta que cierra la ventana.
func remote_reveal_to_host(hand_data: Array) -> void:
	await _acquire_reveal(false)
	var loading := get_node_or_null("/root/MatchLoadingOverlay")
	var was_waiting: bool = not is_in_mulligan and not _remote_mulligan_done  # tapado por "ESPERANDO JUGADOR"
	if loading and was_waiting:
		loading.hide_loading()
	SelectionManager.open_reveal(hand_data, "Tu oponente muestra su mano (mulligan gratis)", 0)
	await SelectionManager.selection_completed
	if loading and was_waiting and not _remote_mulligan_done:
		loading.show_loading(_main, "ESPERANDO JUGADOR",
			"Tu mano ya está lista — esperando a que el otro jugador elija la suya...")
	_reveal_busy = false


## Mulligan gratis: muestra la mano al oponente (hasta que la cierre) y la cambia Robando la misma cantidad.
func on_free_mulligan_pressed() -> void:
	if free_mulligan_used or gold_count(mulligan_hand_data) > 1 or mulligan_hand_data.is_empty():
		return
	if _main and _main._card_inspector:
		_main._card_inspector.close_card_inspection()
	free_mulligan_used = true
	var size: int = mulligan_hand_data.size()
	print("[Mulligan] Jugador hace el mulligan gratis (muestra %d cartas, %d Oros)" % [size, gold_count(mulligan_hand_data)])
	if _main._easy_bot is RemotePlayerController:
		_main.keep_hand_button.disabled = true
		_main.mulligan_button.disabled = true
		free_mulligan_button.disabled = true
		var label_text: String = _main.mulligan_cards_label.text
		_main.mulligan_cards_label.text = "Esperando para mostrar tu mano..." if _reveal_busy else "Tu oponente está viendo tu mano..."
		await _acquire_reveal(true)
		_main.mulligan_cards_label.text = "Tu oponente está viendo tu mano..."
		NetworkClient.send_message({"op": "hand_shown", "title": "Tu oponente muestra su mano (mulligan gratis)",
			"cards": mulligan_hand_data.map(func(d): return (d as Dictionary).duplicate(true))})
		await NetworkClient.await_intent(["hand_shown_closed"])
		_reveal_busy = false
		_main.mulligan_cards_label.text = label_text
	_main._update_debug("Mulligan gratis: muestras tu mano (%d Oro%s) y la cambias por %d cartas" % [
		gold_count(mulligan_hand_data), "" if gold_count(mulligan_hand_data) == 1 else "s", size])
	await _redraw(size)


func _redraw(next_hand_size: int) -> void:
	_main.keep_hand_button.disabled = true
	_main.mulligan_button.disabled = true
	if free_mulligan_button:
		free_mulligan_button.disabled = true
	_main.mulligan_hand.clear_cards()
	await get_tree().create_timer(0.5).timeout
	for card_data in mulligan_hand_data:
		_main.player_deck.append(card_data)
	_main._zone_manager.shuffle_deck(0)
	_draw_mulligan_hand(next_hand_size)
	_update_mulligan_ui()
	_main.keep_hand_button.disabled = false


func _end_mulligan_phase() -> void:
	print("[Mulligan] Fin de fase. Mulligans realizados: %d" % mulligan_count)
	is_in_mulligan = false
	set_free_button(false, 0)
	_main.mulligan_hand.clear_cards()
	await get_tree().create_timer(0.4).timeout
	_main.mulligan_overlay.visible = false
	for card_data in mulligan_hand_data:
		var card = _main._create_card(card_data)
		_main.player_hand.add_card(card)
		_main._connect_card_signals(card)
	mulligan_hand_data.clear()
	# Si el jugador 1 es un Remoto conectado, corre un mulligan real (mantener/redibujar por red); el
	# bot roba su mano directo.
	if _main._easy_bot is RemotePlayerController:
		if not _remote_mulligan_done:
			var loading := get_node_or_null("/root/MatchLoadingOverlay")
			if loading:
				loading.show_loading(_main, "ESPERANDO JUGADOR",
					"Tu mano ya está lista — esperando a que el otro jugador elija la suya...")
			while not _remote_mulligan_done:
				await get_tree().process_frame
			if loading:
				loading.hide_loading()
	else:
		await _main._zone_manager.draw_initial_hand(1, _main.INITIAL_HAND_SIZE)
	GameManager.start_game(_main._dice_winner)
	CardManager.sync_from_main()
	_main._gold_manager._update_gold_display()
	_main._zone_manager._update_castillo_counts()
	_main._sync_oro_ui()
	_main._update_debug("Partida iniciada! Mano: %d cartas" % _main.player_hand.get_child_count())
