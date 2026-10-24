extends Node
## NetworkClient — autoload, capa de red del multijugador remoto
## (docs/plans/2026-09-09-multiplayer-remoto-design.md). Cliente WebSocket crudo (WebSocketPeer, no
## MultiplayerAPI/ENet: el servidor es un reenviador ciego por sala) contra `relay-server/` (Node.js
## + ws, protocolo en su server.js). No sabe nada de las reglas: solo mueve JSON. Los mensajes los
## interpretan GameBootstrap/RemotePlayerController/RemoteMirrorController.
## `is_host` se fija al llamar create_room()/join_room(); antes no hay modo (partida local contra el
## bot).

signal connected_to_relay
signal connection_failed(reason: String)
signal room_created(code: String)
signal room_joined(code: String)
signal peer_joined
signal peer_disconnected
## El socket propio se cerró después de conectar (se cayó internet o el relay): distinto de
## peer_disconnected, que es el relay avisando que el otro jugador se fue.
signal connection_lost
signal message_received(data: Dictionary)
signal relay_error(message: String)

var _socket: WebSocketPeer = null
var is_host: bool = false
var room_code: String = ""
var peer_present: bool = false

# Último mensaje de juego recibido por "op": un mensaje puede llegar antes de que el receptor
# escuche (p.ej. el Remoto manda su mazo apenas confirma, y el Anfitrión empieza a escuchar
# después), así que se puede revisar aquí en vez de depender solo de la señal. Se limpia con el
# resto del estado de sala.
var last_message_by_op: Dictionary = {}
## Anfitrión: cuántas esperas de una decisión del Remoto hay en curso (await_intent y la ventana de
## prioridad de RemotePlayerController). TurnClock lo usa para saber de quién corre el reloj.
var remote_waits: int = 0
## Anfitrión: Callable(expected_kinds: Array) -> Dictionary. Si devuelve un intent, await_intent lo
## usa en vez de esperar al Remoto (TurnClock: tiempo del turno agotado).
var forced_intent: Callable = Callable()
## Anfitrión: el jugador local se quedó sin tiempo (TurnClock): las ventanas abiertas se resuelven
## con su opción por defecto (ui_forced()).
var local_timeout: bool = false
## Ventanas propias abiertas esperando una elección (RevealWindow, CastleLookWindow, BoardChoice,
## ZoneBrowsePicker, CardNameSearchDialog): TurnClock las cuenta como "el jugador local decide".
var local_waits: int = 0
## Anfitrión: último prompt mandado al Remoto (TurnClock arma desde ahí la respuesta por defecto).
var last_prompt: Dictionary = {}
## Remoto: sube con cada {"op":"force_close"} del Anfitrión (se le acabó el tiempo y ya respondió
## por él). Una ventana abierta antes de eso se cierra, y lo que mande queda descartado.
var force_gen: int = 0
var _drop_intents: int = 0


func await_intent(expected_kinds: Array) -> Dictionary:
	"""Espera el próximo {"op":"intent","kind":X,...} con X en expected_kinds. Sin timeout propio:
	el límite lo pone TurnClock con forced_intent (y wake_intent_waiters() para cortar una espera ya
	empezada). Si la conexión se cae, MatchConnectionWatcher termina la partida. Lo usan
	RemotePlayerController, SelectionManager y SelectionDialogs
	(docs/plans/2026-09-20-remote-multiplayer-parity.md)."""
	remote_waits += 1
	while true:
		if forced_intent.is_valid():
			var forced: Dictionary = forced_intent.call(expected_kinds)
			if not forced.is_empty():
				remote_waits = maxi(0, remote_waits - 1)
				return forced
		var data = await message_received
		if data.get("op", "") == "intent" and data.get("kind", "") in expected_kinds:
			remote_waits = maxi(0, remote_waits - 1)
			return data
	return {}


func ui_forced(open_gen: int) -> bool:
	"""Para el bucle de espera de una ventana: true si debe cerrarse ya con su opción por defecto.
	'open_gen' es force_gen al abrirla."""
	if room_code == "":
		return false
	if is_host:
		return local_timeout
	return force_gen != open_gen


func ui_forced_done() -> void:
	"""Una ventana se cerró por ui_forced(): en el Remoto, el intent que mande a continuación ya lo
	respondió el Anfitrión y se descarta."""
	if room_code != "" and not is_host:
		_drop_intents += 1


func wake_intent_waiters() -> void:
	"""Despierta las esperas de await_intent para que vuelvan a consultar forced_intent. Mensaje
	local (no viaja por red); los demás oyentes de message_received ignoran el op."""
	emit_signal("message_received", {"op": "_wake"})


func connect_to_relay(url: String) -> void:
	"""Abre la conexión al relay. No crea ni une ninguna sala todavía — eso
	se hace solo cuando `connected_to_relay` se emite, llamando
	create_room()/join_room()."""
	is_host = false
	room_code = ""
	peer_present = false
	_announced_connected = false
	_pending_control.clear()
	last_message_by_op.clear()
	_reset_clock_state()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		emit_signal("connection_failed", "No se pudo iniciar la conexión (error %d)" % err)
		return
	set_process(true)


func create_room() -> void:
	"""Pide al relay un código de sala nuevo — este cliente queda como
	Anfitrión. Solo tiene efecto si ya hay conexión abierta al relay."""
	is_host = true
	_send_control({"op": "create_room"})


func join_room(code: String) -> void:
	"""Pide unirse a una sala existente — este cliente queda como Remoto."""
	is_host = false
	_send_control({"op": "join_room", "code": code.strip_edges().to_upper()})


func send_message(data: Dictionary) -> void:
	"""Manda un mensaje de juego (intent/instrucción) al otro lado de la
	sala. No hace nada si todavía no hay sala confirmada de los dos lados —
	llamarlo antes de eso es un error del llamador, no de esta capa."""
	if not is_instance_valid(_socket) or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("[NetworkClient] send_message() sin conexión abierta — descartado: %s" % str(data))
		return
	var op := str(data.get("op", ""))
	if is_host and op == "prompt":
		last_prompt = data
	if not is_host and op == "intent" and _drop_intents > 0:
		_drop_intents -= 1
		return
	_socket.send_text(JSON.stringify(data))


func disconnect_from_relay() -> void:
	if is_instance_valid(_socket):
		_socket.close()
	_socket = null
	set_process(false)
	is_host = false
	room_code = ""
	peer_present = false
	_announced_connected = false
	_reset_clock_state()


func _reset_clock_state() -> void:
	remote_waits = 0
	forced_intent = Callable()
	local_timeout = false
	local_waits = 0
	last_prompt = {}
	force_gen = 0
	_drop_intents = 0


func _send_control(data: Dictionary) -> void:
	# Los mensajes de control (create_room/join_room) pueden llegar a
	# pedirse antes de que el socket termine su handshake — se reintenta en
	# _process() hasta que STATE_OPEN, en vez de exigirle al llamador que
	# espere la señal a mano.
	_pending_control.append(data)


var _pending_control: Array = []


func _process(_delta: float) -> void:
	if not is_instance_valid(_socket):
		set_process(false)
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _announced_connected:
			_announced_connected = true
			emit_signal("connected_to_relay")
		if not _pending_control.is_empty():
			for msg in _pending_control:
				_socket.send_text(JSON.stringify(msg))
			_pending_control.clear()
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _socket.get_close_code()
		set_process(false)
		if not _announced_connected:
			emit_signal("connection_failed", "El relay cerró la conexión (código %d)" % code)
		else:
			peer_present = false
			emit_signal("connection_lost")
		_socket = null


var _announced_connected: bool = false


func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[NetworkClient] Paquete no-JSON/no-Dictionary ignorado: %s" % text)
		return
	var data: Dictionary = parsed
	match data.get("op", ""):
		"room_created":
			room_code = str(data.get("code", ""))
			emit_signal("room_created", room_code)
		"room_joined":
			room_code = str(data.get("code", ""))
			peer_present = true
			emit_signal("room_joined", room_code)
		"peer_joined":
			peer_present = true
			emit_signal("peer_joined")
		"peer_disconnected":
			peer_present = false
			emit_signal("peer_disconnected")
		"error":
			emit_signal("relay_error", str(data.get("message", "")))
		_:
			if data.get("op", "") == "force_close" and not is_host:
				force_gen += 1
			elif data.get("op", "") == "prompt" and not is_host:
				# Una ventana cerrada por force_close manda su intent en el mismo frame; si no mandó
				# nada, el descarte pendiente no debe comerse la respuesta a este prompt nuevo.
				_drop_intents = 0
			last_message_by_op[str(data.get("op", ""))] = data
			emit_signal("message_received", data)
