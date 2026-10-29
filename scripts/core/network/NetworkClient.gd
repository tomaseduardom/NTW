extends Node
## NetworkClient — autoload, capa de red del multijugador remoto
## (docs/plans/2026-09-09-multiplayer-remoto-design.md). Cliente WebSocket crudo (WebSocketPeer, no
## MultiplayerAPI/ENet: el servidor es un reenviador ciego por sala) contra `relay-server/` (Node.js
## + ws, protocolo en su server.js). No sabe nada de las reglas: solo mueve JSON. Los mensajes los
## interpretan GameBootstrap/RemotePlayerController/RemoteMirrorController.
## `is_host` se fija al llamar create_room()/join_room(); antes no hay modo (partida local contra el
## bot).
## Reconexión (con un relay que da "token" al crear/unirse): en partida (in_match), si se cae el socket
## o deja de llegar nada por HEARTBEAT_DEAD_MS, se reintenta solo hasta RECONNECT_WINDOW_MS con
## {"op":"rejoin"}. Los mensajes de juego van numerados ("_c" los propios, "_s" los del relay): al volver,
## el relay reenvía lo que no llegó y aquí se reenvía lo propio que él no recibió, sin repetir nada.

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
## Se cayó la conexión propia en partida y se está reintentando / ya volvió.
signal reconnecting
signal reconnected
## El rival perdió la conexión y el relay le guarda el lugar grace_s segundos / ya volvió.
signal peer_reconnecting(grace_s: int)
signal peer_returned

const PING_INTERVAL_MS := 3000
const HEARTBEAT_DEAD_MS := 12000
const RECONNECT_WINDOW_MS := 50000
const RECONNECT_RETRY_MS := 2000
const OUT_RING_MAX := 5000

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
## La partida empezó (MatchConnectionWatcher): desde ahí una caída se reconecta en vez de terminar.
var in_match: bool = false
var reconnecting_now: bool = false
## El rival perdió la conexión y el relay le guarda el lugar (TurnClock detiene los relojes).
var peer_away: bool = false
var _url: String = ""
var _token: String = ""
var _out_seq: int = 0
var _out_ring: Array = []  # [{c, text}] lo propio que el relay todavía no confirmó
var _in_seq: int = 0  # último "_s" recibido
var _last_rx_ms: int = 0
var _last_ping_ms: int = 0
var _reconnect_deadline_ms: int = 0
var _next_retry_ms: int = 0
var _rejoin_sent: bool = false


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
	_reset_session()
	_url = url
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		emit_signal("connection_failed", "No se pudo iniciar la conexión (error %d)" % err)
		return
	_last_rx_ms = Time.get_ticks_msec()
	set_process(true)


func _reset_session() -> void:
	in_match = false
	reconnecting_now = false
	peer_away = false
	_token = ""
	_out_seq = 0
	_out_ring.clear()
	_in_seq = 0
	_rejoin_sent = false


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
	var op := str(data.get("op", ""))
	if is_host and op == "prompt":
		last_prompt = data
	if not is_host and op == "intent" and _drop_intents > 0:
		_drop_intents -= 1
		return
	if _token.is_empty():
		# Relay sin reconexión: como siempre.
		if not is_instance_valid(_socket) or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			push_warning("[NetworkClient] send_message() sin conexión abierta — descartado: %s" % str(data))
			return
		_socket.send_text(JSON.stringify(data))
		return
	# Numerado y guardado hasta que el relay lo confirme: si la conexión está caída, sale al volver.
	_out_seq += 1
	var numbered: Dictionary = data.duplicate()
	numbered["_c"] = _out_seq
	var text := JSON.stringify(numbered)
	_out_ring.append({"c": _out_seq, "text": text})
	if _out_ring.size() > OUT_RING_MAX:
		_out_ring = _out_ring.slice(_out_ring.size() - OUT_RING_MAX)
	if not reconnecting_now and is_instance_valid(_socket) and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(text)


func disconnect_from_relay() -> void:
	if is_instance_valid(_socket):
		# Salida a propósito: el relay avisa al otro ya, sin esperar una reconexión.
		if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not _token.is_empty():
			_socket.send_text(JSON.stringify({"op": "leave"}))
		_socket.close()
	_socket = null
	set_process(false)
	is_host = false
	room_code = ""
	peer_present = false
	_announced_connected = false
	_reset_clock_state()
	_reset_session()


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
	var now := Time.get_ticks_msec()
	if reconnecting_now:
		_process_reconnect(now)
		return
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
		while is_instance_valid(_socket) and not reconnecting_now and _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet())
		if not _token.is_empty() and is_instance_valid(_socket) and not reconnecting_now:
			if now - _last_ping_ms >= PING_INTERVAL_MS:
				_last_ping_ms = now
				_socket.send_text(JSON.stringify({"op": "ping", "last_s": _in_seq}))
			# Sin nada del relay (ni pong) por un rato: la conexión está muerta aunque el socket no lo sepa.
			if now - _last_rx_ms > HEARTBEAT_DEAD_MS:
				_connection_dropped("sin respuesta del relay")
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _socket.get_close_code()
		if not _announced_connected:
			set_process(false)
			_socket = null
			emit_signal("connection_failed", "El relay cerró la conexión (código %d)" % code)
		else:
			_connection_dropped("código %d" % code)


func _connection_dropped(reason: String) -> void:
	if is_instance_valid(_socket):
		_socket.close()
	_socket = null
	if not in_match or _token.is_empty() or room_code.is_empty():
		set_process(false)
		peer_present = false
		emit_signal("connection_lost")
		return
	print("[NetworkClient] Conexión caída (%s): reconectando..." % reason)
	reconnecting_now = true
	_reconnect_deadline_ms = Time.get_ticks_msec() + RECONNECT_WINDOW_MS
	_next_retry_ms = 0
	set_process(true)
	emit_signal("reconnecting")


func _process_reconnect(now: int) -> void:
	if now > _reconnect_deadline_ms:
		_give_up_reconnect()
		return
	if not is_instance_valid(_socket):
		if now < _next_retry_ms:
			return
		_next_retry_ms = now + RECONNECT_RETRY_MS
		_rejoin_sent = false
		_socket = WebSocketPeer.new()
		if _socket.connect_to_url(_url) != OK:
			_socket = null
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _rejoin_sent:
			_rejoin_sent = true
			_socket.send_text(JSON.stringify({"op": "rejoin", "code": room_code, "token": _token, "last_s": _in_seq}))
		while is_instance_valid(_socket) and _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		_socket = null


func _give_up_reconnect() -> void:
	reconnecting_now = false
	if is_instance_valid(_socket):
		_socket.close()
	_socket = null
	set_process(false)
	peer_present = false
	emit_signal("connection_lost")


func _on_rejoined(last_c: int) -> void:
	"""De vuelta en la sala: se reenvía lo propio que el relay no llegó a recibir (en orden)."""
	reconnecting_now = false
	_trim_out_ring(last_c)
	for entry in _out_ring:
		_socket.send_text(entry.text)
	_last_rx_ms = Time.get_ticks_msec()
	_last_ping_ms = 0
	print("[NetworkClient] Reconectado (%d mensaje(s) reenviados)" % _out_ring.size())
	emit_signal("reconnected")


func _trim_out_ring(last_c: int) -> void:
	var i := 0
	while i < _out_ring.size() and int(_out_ring[i].c) <= last_c:
		i += 1
	if i > 0:
		_out_ring = _out_ring.slice(i)


var _announced_connected: bool = false


func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[NetworkClient] Paquete no-JSON/no-Dictionary ignorado: %s" % text)
		return
	var data: Dictionary = parsed
	_last_rx_ms = Time.get_ticks_msec()
	if data.has("_s"):
		var s := int(data["_s"])
		if s <= _in_seq:
			return  # ya llegó (reenvío del relay al reconectar)
		_in_seq = s
		data.erase("_s")
	data.erase("_c")  # un relay viejo lo reenvía tal cual
	match data.get("op", ""):
		"room_created":
			room_code = str(data.get("code", ""))
			_token = str(data.get("token", ""))
			emit_signal("room_created", room_code)
		"room_joined":
			room_code = str(data.get("code", ""))
			_token = str(data.get("token", ""))
			peer_present = true
			emit_signal("room_joined", room_code)
		"peer_joined":
			peer_present = true
			emit_signal("peer_joined")
		"peer_disconnected":
			peer_present = false
			peer_away = false
			emit_signal("peer_disconnected")
		"peer_reconnecting":
			if in_match:
				peer_away = true
				emit_signal("peer_reconnecting", int(int(data.get("grace_ms", 60000)) / 1000.0))
			else:
				# Antes de empezar la partida no se espera a nadie: como si se hubiera ido.
				peer_present = false
				emit_signal("peer_disconnected")
		"peer_returned":
			peer_away = false
			emit_signal("peer_returned")
		"pong":
			_trim_out_ring(int(data.get("last_c", 0)))
		"rejoined":
			_on_rejoined(int(data.get("last_c", 0)))
		"rejoin_failed":
			print("[NetworkClient] No se pudo volver a la sala: %s" % str(data.get("message", "")))
			_give_up_reconnect()
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
