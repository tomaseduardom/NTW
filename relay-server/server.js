// Relay WebSocket ciego para NTW (Fase A del multiplayer remoto).
//
// No sabe NADA de las reglas de Mitos y Leyendas. Su unico trabajo:
//   1. Agrupar 2 conexiones bajo un codigo de sala corto.
//   2. Reenviar cualquier mensaje que llegue de un lado, tal cual, al otro
//      lado de la misma sala.
//   3. Si un lado pierde la conexion, guardarle su lugar GRACE_MS: lo que el otro le mande queda
//      guardado y se le reenvia cuando vuelve (rejoin), sin perder ni repetir nada.
//
// Protocolo de control (el unico que este servidor entiende):
//   Cliente -> Servidor:
//     {"op": "create_room"}                  -> crea sala, quien la crea es el Anfitrion
//     {"op": "join_room", "code": "ABCDE"}    -> se une como Remoto a una sala existente
//     {"op": "rejoin", "code", "token", "last_s"} -> vuelve a su lugar tras perder la conexion
//     {"op": "ping", "last_s"}                -> latido; last_s confirma lo recibido
//     {"op": "leave"}                         -> sale de la sala a proposito (sin espera)
//     cualquier otro mensaje                  -> se reenvia al otro peer de la sala
//   Servidor -> Cliente:
//     {"op": "room_created", "code", "token"}
//     {"op": "room_joined", "code", "token"}
//     {"op": "rejoined", "code", "last_c"}    -> last_c: ultimo mensaje suyo que llego
//     {"op": "rejoin_failed", "message"}
//     {"op": "pong", "last_c"}
//     {"op": "peer_joined"}                   -> avisa al Anfitrion que el Remoto ya esta
//     {"op": "peer_reconnecting", "grace_ms"} -> el otro perdio la conexion; se lo espera
//     {"op": "peer_returned"}                 -> el otro volvio
//     {"op": "peer_disconnected"}             -> el otro se fue (o no volvio a tiempo)
//     {"op": "error", "message": "..."}
//     cualquier otro mensaje                  -> lo que el otro peer mando, reenviado
//
// Numeracion (para no perder ni repetir mensajes al reconectar):
//   - El cliente numera sus mensajes de juego con "_c" (1, 2, 3...). El servidor descarta los que
//     ya recibio (un reenvio tras reconectar) y avisa el ultimo en "rejoined"/"pong".
//   - El servidor numera con "_s" lo que le entrega a cada lado y guarda los ultimos RING_MAX; el
//     cliente avisa el ultimo que recibio ("last_s" en ping/rejoin): se borra lo confirmado y al
//     volver se le reenvia lo que falte.
//   Un cliente viejo (sin "_c") funciona igual, sin reconexion.
//
// Seguridad (todo configurable por variable de entorno):
//   - Mensajes de hasta MAX_PAYLOAD bytes; mas grandes cierran la conexion.
//   - Un peer no puede mandar las ops de control del servidor (room_created, peer_disconnected...):
//     se descartan, asi no puede hacerle creer al otro que se desconecto o cambio de sala.
//   - Una conexion esta en una sola sala (no puede crear ni unirse dos veces).
//   - Codigo de sala con crypto.randomInt y token de lugar con crypto.randomBytes; MAX_JOIN_FAILS
//     intentos fallidos (join o rejoin) por conexion y por IP (ventana de 10 min).
//   - Limite de conexiones por IP, de salas totales y de mensajes por segundo.
//   - Ping cada 30 s: las conexiones muertas se cierran (y su lugar entra en espera).
//   - Una sala sin Remoto se borra a los ROOM_IDLE_MS.
//
// Correr local: npm install && npm start (por defecto puerto 8080, override con PORT).
// Detras de un proxy con TLS (Render, Railway, Fly.io) se usa wss:// y la IP real llega en
// X-Forwarded-For (TRUST_PROXY=1, por defecto).

const crypto = require("crypto");
const { WebSocketServer } = require("ws");

const env = (name, def) => (process.env[name] ? parseInt(process.env[name], 10) : def);
const PORT = env("PORT", 8080);
const MAX_PAYLOAD = env("MAX_PAYLOAD", 1024 * 1024);
const MAX_CONN_PER_IP = env("MAX_CONN_PER_IP", 8);
const MAX_ROOMS = env("MAX_ROOMS", 2000);
const MAX_JOIN_FAILS = env("MAX_JOIN_FAILS", 10);
const MSG_PER_SEC = env("MSG_PER_SEC", 200);
const MSG_BURST = env("MSG_BURST", 1000);
const ROOM_IDLE_MS = env("ROOM_IDLE_MS", 30 * 60 * 1000);
const GRACE_MS = env("GRACE_MS", 60 * 1000);
const RING_MAX = env("RING_MAX", 5000);
const TRUST_PROXY = env("TRUST_PROXY", 1) === 1;

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // sin 0/O/1/I/L, para leerlo por voz/chat sin confundir
const CODE_LENGTH = 6;
const CODE_RE = /^[A-Z0-9]{4,8}$/;
const CONTROL_OPS = new Set(["create_room", "join_room", "room_created", "room_joined", "peer_joined", "peer_disconnected",
	"error", "rejoin", "rejoined", "rejoin_failed", "ping", "pong", "leave", "peer_reconnecting", "peer_returned"]);
const JOIN_FAIL_WINDOW_MS = 10 * 60 * 1000;

/**
 * Un lugar de la sala. ws es null mientras su jugador esta reconectando.
 * @typedef {{ws: import("ws").WebSocket|null, token: string, inSeq: number, outSeq: number,
 *   ring: Array<{s: number, text: string}>, graceTimer: NodeJS.Timeout|null}} Seat
 */
/** @type {Map<string, {host: Seat, remote: Seat|null, createdAt: number}>} */
const rooms = new Map();
/** @type {Map<string, number>} */
const connPerIp = new Map();
/** @type {Map<string, {count: number, since: number}>} */
const joinFailsPerIp = new Map();

function generateRoomCode() {
	let code;
	do {
		code = "";
		for (let i = 0; i < CODE_LENGTH; i++) {
			code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
		}
	} while (rooms.has(code));
	return code;
}

function newSeat(ws) {
	return { ws, token: crypto.randomBytes(16).toString("hex"), inSeq: 0, outSeq: 0, ring: [], graceTimer: null };
}

function send(ws, payload) {
	if (ws && ws.readyState === ws.OPEN) {
		ws.send(JSON.stringify(payload));
	}
}

function otherSeat(room, seat) {
	if (room.host === seat) return room.remote;
	if (room.remote === seat) return room.host;
	return null;
}

/** Entrega un mensaje de juego al lugar 'seat': numerado, guardado y enviado si esta conectado. */
function deliver(seat, msg) {
	seat.outSeq++;
	msg._s = seat.outSeq;
	const text = JSON.stringify(msg);
	seat.ring.push({ s: seat.outSeq, text });
	if (seat.ring.length > RING_MAX) seat.ring.splice(0, seat.ring.length - RING_MAX);
	if (seat.ws && seat.ws.readyState === seat.ws.OPEN) seat.ws.send(text);
}

/** El cliente confirmo hasta last_s: eso ya no hace falta reenviarlo. */
function trimRing(seat, lastS) {
	if (typeof lastS !== "number") return;
	let i = 0;
	while (i < seat.ring.length && seat.ring[i].s <= lastS) i++;
	if (i > 0) seat.ring.splice(0, i);
}

function clientIp(req) {
	if (TRUST_PROXY) {
		const fwd = req.headers["x-forwarded-for"];
		if (typeof fwd === "string" && fwd.length > 0) return fwd.split(",")[0].trim();
	}
	return req.socket.remoteAddress || "?";
}

function joinFails(ip) {
	const entry = joinFailsPerIp.get(ip);
	if (!entry || Date.now() - entry.since > JOIN_FAIL_WINDOW_MS) return 0;
	return entry.count;
}

function addJoinFail(ip) {
	const entry = joinFailsPerIp.get(ip);
	if (!entry || Date.now() - entry.since > JOIN_FAIL_WINDOW_MS) {
		joinFailsPerIp.set(ip, { count: 1, since: Date.now() });
	} else {
		entry.count++;
	}
}

function deleteRoom(code, room) {
	for (const seat of [room.host, room.remote]) {
		if (!seat) continue;
		if (seat.graceTimer) clearTimeout(seat.graceTimer);
		if (seat.ws) seat.ws._roomCode = null;
	}
	rooms.delete(code);
}

/** Sale de la sala ya: el otro recibe peer_disconnected y la sala se borra. */
function leaveRoom(ws) {
	const code = ws._roomCode;
	if (!code) return;
	const room = rooms.get(code);
	ws._roomCode = null;
	if (!room) return;
	const other = otherSeat(room, ws._seat);
	if (other) send(other.ws, { op: "peer_disconnected" });
	deleteRoom(code, room);
}

/** Se cayo la conexion: con la partida armada (los dos lugares), se espera GRACE_MS a que vuelva. */
function connectionDropped(ws) {
	const code = ws._roomCode;
	if (!code) return;
	const room = rooms.get(code);
	const seat = ws._seat;
	if (!room || !seat || seat.ws !== ws) return; // ya lo reemplazo un rejoin
	if (!room.remote) {
		leaveRoom(ws);
		return;
	}
	seat.ws = null;
	ws._roomCode = null;
	const other = otherSeat(room, seat);
	if (other) send(other.ws, { op: "peer_reconnecting", grace_ms: GRACE_MS });
	seat.graceTimer = setTimeout(() => {
		seat.graceTimer = null;
		if (rooms.get(code) !== room || seat.ws) return;
		if (other) send(other.ws, { op: "peer_disconnected" });
		deleteRoom(code, room);
	}, GRACE_MS);
}

function rejoin(ws, msg, ip) {
	const fail = (message) => {
		ws._joinFails++;
		addJoinFail(ip);
		send(ws, { op: "rejoin_failed", message });
	};
	if (ws._roomCode) return send(ws, { op: "rejoin_failed", message: "Ya estas en una sala" });
	if (ws._joinFails >= MAX_JOIN_FAILS || joinFails(ip) >= MAX_JOIN_FAILS * 3) {
		send(ws, { op: "rejoin_failed", message: "Demasiados intentos, espera unos minutos" });
		ws.close(1008, "too many join attempts");
		return;
	}
	const code = String(msg.code || "").toUpperCase().trim();
	const room = CODE_RE.test(code) ? rooms.get(code) : undefined;
	const token = String(msg.token || "");
	if (!room || token.length !== 32) return fail("La sala ya no existe");
	const seat = [room.host, room.remote].find((s) => s && crypto.timingSafeEqual(Buffer.from(s.token), Buffer.from(token)));
	if (!seat) return fail("No tienes lugar en esa sala");
	if (seat.graceTimer) {
		clearTimeout(seat.graceTimer);
		seat.graceTimer = null;
	}
	const wasAway = !seat.ws;
	if (seat.ws && seat.ws !== ws) {
		// El servidor todavia no noto que la conexion vieja murio: la nueva la reemplaza.
		seat.ws._roomCode = null;
		seat.ws.terminate();
	}
	seat.ws = ws;
	ws._seat = seat;
	ws._roomCode = code;
	send(ws, { op: "rejoined", code, last_c: seat.inSeq });
	trimRing(seat, msg.last_s);
	for (const entry of seat.ring) ws.send(entry.text);
	const other = otherSeat(room, seat);
	if (other && wasAway) send(other.ws, { op: "peer_returned" });
}

const wss = new WebSocketServer({ port: PORT, maxPayload: MAX_PAYLOAD });

wss.on("connection", (ws, req) => {
	const ip = clientIp(req);
	const open = (connPerIp.get(ip) || 0) + 1;
	if (open > MAX_CONN_PER_IP) {
		send(ws, { op: "error", message: "Demasiadas conexiones desde tu red" });
		ws.close(1008, "too many connections");
		return;
	}
	connPerIp.set(ip, open);
	ws._ip = ip;
	ws._roomCode = null;
	ws._seat = null;
	ws._alive = true;
	ws._tokens = MSG_BURST;
	ws._lastRefill = Date.now();
	ws._joinFails = 0;
	ws.on("pong", () => { ws._alive = true; });

	ws.on("message", (raw, isBinary) => {
		ws._alive = true;
		// Limite de mensajes (token bucket).
		const now = Date.now();
		ws._tokens = Math.min(MSG_BURST, ws._tokens + ((now - ws._lastRefill) / 1000) * MSG_PER_SEC);
		ws._lastRefill = now;
		if (ws._tokens < 1) {
			send(ws, { op: "error", message: "Demasiados mensajes" });
			ws.close(1008, "rate limit");
			return;
		}
		ws._tokens -= 1;
		if (isBinary) return;

		const text = raw.toString();
		let msg;
		try {
			msg = JSON.parse(text);
		} catch (err) {
			send(ws, { op: "error", message: "JSON invalido" });
			return;
		}
		if (!msg || typeof msg !== "object" || Array.isArray(msg)) {
			send(ws, { op: "error", message: "Mensaje invalido" });
			return;
		}

		if (msg.op === "create_room") {
			if (ws._roomCode) {
				send(ws, { op: "error", message: "Ya estas en una sala" });
				return;
			}
			if (rooms.size >= MAX_ROOMS) {
				send(ws, { op: "error", message: "El servidor esta lleno, intenta mas tarde" });
				return;
			}
			const code = generateRoomCode();
			const seat = newSeat(ws);
			rooms.set(code, { host: seat, remote: null, createdAt: Date.now() });
			ws._roomCode = code;
			ws._seat = seat;
			send(ws, { op: "room_created", code, token: seat.token });
			return;
		}

		if (msg.op === "join_room") {
			if (ws._roomCode) {
				send(ws, { op: "error", message: "Ya estas en una sala" });
				return;
			}
			if (ws._joinFails >= MAX_JOIN_FAILS || joinFails(ip) >= MAX_JOIN_FAILS * 3) {
				send(ws, { op: "error", message: "Demasiados intentos, espera unos minutos" });
				ws.close(1008, "too many join attempts");
				return;
			}
			const code = String(msg.code || "").toUpperCase().trim();
			const room = CODE_RE.test(code) ? rooms.get(code) : undefined;
			if (!room) {
				ws._joinFails++;
				addJoinFail(ip);
				send(ws, { op: "error", message: "Sala no encontrada" });
				return;
			}
			if (room.remote) {
				send(ws, { op: "error", message: "Esa sala ya tiene 2 jugadores" });
				return;
			}
			if (room.host.ws === ws) {
				send(ws, { op: "error", message: "No puedes unirte a tu propia sala" });
				return;
			}
			const seat = newSeat(ws);
			room.remote = seat;
			ws._roomCode = code;
			ws._seat = seat;
			send(ws, { op: "room_joined", code, token: seat.token });
			send(room.host.ws, { op: "peer_joined" });
			return;
		}

		if (msg.op === "rejoin") {
			rejoin(ws, msg, ip);
			return;
		}

		if (msg.op === "ping") {
			if (ws._seat) {
				trimRing(ws._seat, msg.last_s);
				send(ws, { op: "pong", last_c: ws._seat.inSeq });
			} else {
				send(ws, { op: "pong", last_c: 0 });
			}
			return;
		}

		if (msg.op === "leave") {
			leaveRoom(ws);
			return;
		}

		// Las ops de control solo las manda el servidor.
		if (CONTROL_OPS.has(msg.op)) {
			return;
		}

		// Cualquier otro mensaje: reenvio al otro lado de la misma sala.
		const room = ws._roomCode ? rooms.get(ws._roomCode) : undefined;
		if (!room || !ws._seat) {
			send(ws, { op: "error", message: "No estas en ninguna sala todavia" });
			return;
		}
		const peer = otherSeat(room, ws._seat);
		if (!peer) {
			send(ws, { op: "error", message: "Todavia no hay nadie del otro lado" });
			return;
		}
		if (typeof msg._c === "number") {
			if (msg._c <= ws._seat.inSeq) return; // ya llego (reenvio tras reconectar)
			ws._seat.inSeq = msg._c;
			delete msg._c;
		}
		deliver(peer, msg);
	});

	ws.on("close", () => {
		const left = (connPerIp.get(ip) || 1) - 1;
		if (left <= 0) connPerIp.delete(ip);
		else connPerIp.set(ip, left);
		connectionDropped(ws);
	});

	ws.on("error", () => {
		// El cierre llega por "close".
	});
});

// Conexiones muertas y salas abandonadas.
const sweep = setInterval(() => {
	for (const ws of wss.clients) {
		if (!ws._alive) {
			ws.terminate();
			continue;
		}
		ws._alive = false;
		ws.ping();
	}
	const now = Date.now();
	for (const [code, room] of rooms) {
		if (!room.remote && now - room.createdAt > ROOM_IDLE_MS) {
			send(room.host.ws, { op: "error", message: "La sala se cerro por inactividad" });
			deleteRoom(code, room);
		}
	}
	for (const [ip, entry] of joinFailsPerIp) {
		if (now - entry.since > JOIN_FAIL_WINDOW_MS) joinFailsPerIp.delete(ip);
	}
}, 30 * 1000);

wss.on("close", () => clearInterval(sweep));

console.log(`[relay] escuchando en ws://0.0.0.0:${PORT}`);
