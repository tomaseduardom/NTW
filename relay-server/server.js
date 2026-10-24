// Relay WebSocket ciego para NTW (Fase A del multiplayer remoto).
//
// No sabe NADA de las reglas de Mitos y Leyendas. Su unico trabajo:
//   1. Agrupar 2 conexiones bajo un codigo de sala corto.
//   2. Reenviar cualquier mensaje que llegue de un lado, tal cual, al otro
//      lado de la misma sala.
//
// Protocolo de control (el unico que este servidor entiende):
//   Cliente -> Servidor:
//     {"op": "create_room"}                  -> crea sala, quien la crea es el Anfitrion
//     {"op": "join_room", "code": "ABCDE"}    -> se une como Remoto a una sala existente
//     cualquier otro mensaje                  -> se reenvia ciego al otro peer de la sala
//   Servidor -> Cliente:
//     {"op": "room_created", "code": "ABCDE"}
//     {"op": "room_joined", "code": "ABCDE"}
//     {"op": "peer_joined"}                   -> avisa al Anfitrion que el Remoto ya esta
//     {"op": "peer_disconnected"}
//     {"op": "error", "message": "..."}
//     cualquier otro mensaje                  -> lo que el otro peer mando, reenviado tal cual
//
// Seguridad (todo configurable por variable de entorno):
//   - Mensajes de hasta MAX_PAYLOAD bytes; mas grandes cierran la conexion.
//   - Un peer no puede mandar las ops de control del servidor (room_created, peer_disconnected...):
//     se descartan, asi no puede hacerle creer al otro que se desconecto o cambio de sala.
//   - Una conexion esta en una sola sala (no puede crear ni unirse dos veces).
//   - Codigo de sala con crypto.randomInt; MAX_JOIN_FAILS intentos fallidos por conexion y por IP
//     (ventana de 10 min) contra la adivinacion de codigos.
//   - Limite de conexiones por IP, de salas totales y de mensajes por segundo.
//   - Ping cada 30 s: las conexiones muertas se cierran y su sala se borra.
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
const TRUST_PROXY = env("TRUST_PROXY", 1) === 1;

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // sin 0/O/1/I/L, para leerlo por voz/chat sin confundir
const CODE_LENGTH = 6;
const CODE_RE = /^[A-Z0-9]{4,8}$/;
const CONTROL_OPS = new Set(["create_room", "join_room", "room_created", "room_joined", "peer_joined", "peer_disconnected", "error"]);
const JOIN_FAIL_WINDOW_MS = 10 * 60 * 1000;

/** @type {Map<string, {host: import("ws").WebSocket, remote: import("ws").WebSocket|null, createdAt: number}>} */
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

function send(ws, payload) {
	if (ws && ws.readyState === ws.OPEN) {
		ws.send(JSON.stringify(payload));
	}
}

function sendRaw(ws, text) {
	if (ws && ws.readyState === ws.OPEN) {
		ws.send(text);
	}
}

function otherPeer(room, ws) {
	if (room.host === ws) return room.remote;
	if (room.remote === ws) return room.host;
	return null;
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

function leaveRoom(ws) {
	const code = ws._roomCode;
	if (!code) return;
	const room = rooms.get(code);
	ws._roomCode = null;
	if (!room) return;
	send(otherPeer(room, ws), { op: "peer_disconnected" });
	rooms.delete(code);
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
	ws._alive = true;
	ws._tokens = MSG_BURST;
	ws._lastRefill = Date.now();
	ws._joinFails = 0;
	ws.on("pong", () => { ws._alive = true; });

	ws.on("message", (raw, isBinary) => {
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
			rooms.set(code, { host: ws, remote: null, createdAt: Date.now() });
			ws._roomCode = code;
			send(ws, { op: "room_created", code });
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
			if (room.host === ws) {
				send(ws, { op: "error", message: "No puedes unirte a tu propia sala" });
				return;
			}
			room.remote = ws;
			ws._roomCode = code;
			send(ws, { op: "room_joined", code });
			send(room.host, { op: "peer_joined" });
			return;
		}

		// Las ops de control solo las manda el servidor.
		if (CONTROL_OPS.has(msg.op)) {
			return;
		}

		// Cualquier otro mensaje: reenvio ciego al otro lado de la misma sala.
		const room = ws._roomCode ? rooms.get(ws._roomCode) : undefined;
		if (!room) {
			send(ws, { op: "error", message: "No estas en ninguna sala todavia" });
			return;
		}
		const peer = otherPeer(room, ws);
		if (!peer) {
			send(ws, { op: "error", message: "Todavia no hay nadie del otro lado" });
			return;
		}
		sendRaw(peer, text);
	});

	ws.on("close", () => {
		const left = (connPerIp.get(ip) || 1) - 1;
		if (left <= 0) connPerIp.delete(ip);
		else connPerIp.set(ip, left);
		leaveRoom(ws);
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
			send(room.host, { op: "error", message: "La sala se cerro por inactividad" });
			room.host._roomCode = null;
			rooms.delete(code);
		}
	}
	for (const [ip, entry] of joinFailsPerIp) {
		if (now - entry.since > JOIN_FAIL_WINDOW_MS) joinFailsPerIp.delete(ip);
	}
}, 30 * 1000);

wss.on("close", () => clearInterval(sweep));

console.log(`[relay] escuchando en ws://0.0.0.0:${PORT}`);
