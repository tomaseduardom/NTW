// Pruebas del relay (server.js): salas, reenvio, ops de control, reconexion sin perder ni repetir
// mensajes, espera vencida y limites. Levanta el servidor en un puerto libre como proceso aparte.
// Uso: cd relay-server && npm test   (node --test, sin dependencias extra)

const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const net = require("node:net");
const path = require("node:path");
const { WebSocket } = require("ws");

const GRACE_MS = 600;

function freePort() {
	return new Promise((resolve, reject) => {
		const srv = net.createServer();
		srv.listen(0, () => {
			const { port } = srv.address();
			srv.close(() => resolve(port));
		});
		srv.on("error", reject);
	});
}

async function startServer(extraEnv = {}) {
	const port = await freePort();
	const proc = spawn(process.execPath, [path.join(__dirname, "..", "server.js")], {
		env: { ...process.env, PORT: String(port), TRUST_PROXY: "0", MAX_CONN_PER_IP: "200", GRACE_MS: String(GRACE_MS), ...extraEnv },
		stdio: ["ignore", "pipe", "pipe"],
	});
	await new Promise((resolve, reject) => {
		const timer = setTimeout(() => reject(new Error("el relay no arranco")), 5000);
		proc.stdout.on("data", (d) => {
			if (String(d).includes("escuchando")) {
				clearTimeout(timer);
				resolve();
			}
		});
		proc.on("exit", (code) => reject(new Error(`el relay salio con codigo ${code}`)));
	});
	return { url: `ws://127.0.0.1:${port}`, stop: () => proc.kill() };
}

/** Cliente de prueba: guarda todo lo que recibe y permite esperar un mensaje puntual. */
class Client {
	static async open(url) {
		const c = new Client();
		c.ws = new WebSocket(url);
		c.inbox = [];
		c.closed = false;
		c.waiters = [];
		c.ws.on("message", (raw) => {
			const msg = JSON.parse(raw.toString());
			c.inbox.push(msg);
			c.waiters = c.waiters.filter((w) => !w(msg));
		});
		c.ws.on("close", () => { c.closed = true; });
		await new Promise((resolve, reject) => {
			c.ws.once("open", resolve);
			c.ws.once("error", reject);
		});
		return c;
	}

	send(msg) {
		this.ws.send(JSON.stringify(msg));
	}

	/** Espera (y saca de la bandeja) el primer mensaje con esa op. */
	next(op, ms = 2000) {
		const i = this.inbox.findIndex((m) => m.op === op);
		if (i >= 0) return Promise.resolve(this.inbox.splice(i, 1)[0]);
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => reject(new Error(`no llego "${op}"`)), ms);
			this.waiters.push((msg) => {
				if (msg.op !== op) return false;
				clearTimeout(timer);
				this.inbox.splice(this.inbox.indexOf(msg), 1);
				resolve(msg);
				return true;
			});
		});
	}

	/** Los mensajes con esa op que llegaron en los proximos ms (sin sacar los de otras ops). */
	async collect(op, ms = 300) {
		await new Promise((r) => setTimeout(r, ms));
		const got = this.inbox.filter((m) => m.op === op);
		this.inbox = this.inbox.filter((m) => m.op !== op);
		return got;
	}

	close() {
		this.ws.terminate();
	}
}

/** Sala con Anfitrion y Remoto ya unidos. */
async function room(url) {
	const host = await Client.open(url);
	host.send({ op: "create_room" });
	const created = await host.next("room_created");
	const remote = await Client.open(url);
	remote.send({ op: "join_room", code: created.code });
	const joined = await remote.next("room_joined");
	await host.next("peer_joined");
	return { host, remote, code: created.code, hostToken: created.token, remoteToken: joined.token };
}

let server;
before(async () => { server = await startServer(); });
after(() => server.stop());

test("crear y unirse a una sala", async () => {
	const host = await Client.open(server.url);
	host.send({ op: "create_room" });
	const created = await host.next("room_created");
	assert.match(created.code, /^[A-Z2-9]{6}$/);
	assert.match(created.token, /^[0-9a-f]{32}$/);
	const remote = await Client.open(server.url);
	remote.send({ op: "join_room", code: created.code.toLowerCase() });
	const joined = await remote.next("room_joined");
	assert.equal(joined.code, created.code);
	assert.notEqual(joined.token, created.token);
	await host.next("peer_joined");
	host.close();
	remote.close();
});

test("unirse: sala inexistente, llena o propia", async () => {
	const { host, remote, code } = await room(server.url);
	const third = await Client.open(server.url);
	third.send({ op: "join_room", code: "ZZZZZZ" });
	assert.equal((await third.next("error")).message, "Sala no encontrada");
	third.send({ op: "join_room", code });
	assert.equal((await third.next("error")).message, "Esa sala ya tiene 2 jugadores");
	const lone = await Client.open(server.url);
	lone.send({ op: "create_room" });
	const own = await lone.next("room_created");
	lone.send({ op: "join_room", code: own.code });
	assert.equal((await lone.next("error")).message, "Ya estas en una sala");
	for (const c of [host, remote, third, lone]) c.close();
});

test("reenvia en los dos sentidos, en orden y numerado", async () => {
	const { host, remote } = await room(server.url);
	for (let i = 1; i <= 5; i++) host.send({ op: "move_card", n: i, _c: i });
	remote.send({ op: "intent", kind: "pass", _c: 1 });
	const got = await remote.collect("move_card");
	assert.deepEqual(got.map((m) => m.n), [1, 2, 3, 4, 5]);
	assert.deepEqual(got.map((m) => m._s), [1, 2, 3, 4, 5]);
	assert.ok(got.every((m) => !("_c" in m)), "el _c del que manda no se reenvia");
	const intent = await host.next("intent");
	assert.equal(intent.kind, "pass");
	assert.equal(intent._s, 1);
	host.close();
	remote.close();
});

test("un mensaje repetido (mismo _c) no se entrega dos veces", async () => {
	const { host, remote } = await room(server.url);
	host.send({ op: "move_card", n: 1, _c: 1 });
	host.send({ op: "move_card", n: 2, _c: 2 });
	host.send({ op: "move_card", n: 2, _c: 2 });
	host.send({ op: "move_card", n: 1, _c: 1 });
	host.send({ op: "move_card", n: 3, _c: 3 });
	assert.deepEqual((await remote.collect("move_card")).map((m) => m.n), [1, 2, 3]);
	host.close();
	remote.close();
});

test("un peer no puede mandar ops de control del servidor", async () => {
	const { host, remote } = await room(server.url);
	remote.send({ op: "peer_disconnected" });
	remote.send({ op: "room_created", code: "AAAAAA", token: "x" });
	remote.send({ op: "pong", last_c: 99 });
	remote.send({ op: "ok", _c: 1 });
	await host.next("ok");
	for (const op of ["peer_disconnected", "room_created", "pong"]) {
		assert.equal(host.inbox.filter((m) => m.op === op).length, 0, `se reenvio ${op}`);
	}
	host.close();
	remote.close();
});

test("reconectar: recibe lo que se perdio, una sola vez y en orden", async () => {
	const { host, remote, code, remoteToken } = await room(server.url);
	host.send({ op: "move_card", n: 1, _c: 1 });
	const first = await remote.next("move_card");
	remote.close();
	await host.next("peer_reconnecting");
	for (let i = 2; i <= 4; i++) host.send({ op: "move_card", n: i, _c: i });

	const back = await Client.open(server.url);
	back.send({ op: "rejoin", code, token: remoteToken, last_s: first._s });
	const rejoined = await back.next("rejoined");
	assert.equal(rejoined.code, code);
	assert.deepEqual((await back.collect("move_card")).map((m) => m.n), [2, 3, 4]);
	await host.next("peer_returned");

	// Lo que mando antes de caerse y vuelve a mandar al reconectar no se repite del otro lado.
	assert.equal(rejoined.last_c, 0);
	back.send({ op: "intent", n: 1, _c: 1 });
	back.send({ op: "intent", n: 1, _c: 1 });
	back.send({ op: "intent", n: 2, _c: 2 });
	assert.deepEqual((await host.collect("intent")).map((m) => m.n), [1, 2]);
	host.close();
	back.close();
});

test("reconectar sin confirmar nada: recibe todo lo pendiente", async () => {
	const { host, remote, code, remoteToken } = await room(server.url);
	for (let i = 1; i <= 3; i++) host.send({ op: "move_card", n: i, _c: i });
	await remote.collect("move_card");
	remote.close();
	await host.next("peer_reconnecting");
	const back = await Client.open(server.url);
	back.send({ op: "rejoin", code, token: remoteToken });
	await back.next("rejoined");
	assert.deepEqual((await back.collect("move_card")).map((m) => m.n), [1, 2, 3]);
	host.close();
	back.close();
});

test("el ping confirma lo recibido: al reconectar no se reenvia", async () => {
	const { host, remote, code, remoteToken } = await room(server.url);
	for (let i = 1; i <= 3; i++) host.send({ op: "move_card", n: i, _c: i });
	const got = await remote.collect("move_card");
	remote.send({ op: "ping", last_s: got[got.length - 1]._s });
	await remote.next("pong");
	remote.close();
	await host.next("peer_reconnecting");
	host.send({ op: "move_card", n: 4, _c: 4 });
	const back = await Client.open(server.url);
	back.send({ op: "rejoin", code, token: remoteToken });
	await back.next("rejoined");
	assert.deepEqual((await back.collect("move_card")).map((m) => m.n), [4]);
	host.close();
	back.close();
});

test("reconectar con token equivocado falla", async () => {
	const { host, remote, code } = await room(server.url);
	const intruder = await Client.open(server.url);
	intruder.send({ op: "rejoin", code, token: "0".repeat(32) });
	assert.equal((await intruder.next("rejoin_failed")).message, "No tienes lugar en esa sala");
	intruder.send({ op: "rejoin", code: "ZZZZZZ", token: "0".repeat(32) });
	assert.equal((await intruder.next("rejoin_failed")).message, "La sala ya no existe");
	for (const c of [host, remote, intruder]) c.close();
});

test("la conexion nueva reemplaza a una vieja que el servidor todavia no vio caer", async () => {
	const { host, remote, code, remoteToken } = await room(server.url);
	const back = await Client.open(server.url);
	back.send({ op: "rejoin", code, token: remoteToken, last_s: 0 });
	await back.next("rejoined");
	host.send({ op: "move_card", n: 1, _c: 1 });
	assert.equal((await back.next("move_card")).n, 1);
	await new Promise((r) => setTimeout(r, 200));
	assert.ok(remote.closed, "la conexion vieja se cierra");
	assert.equal(host.inbox.filter((m) => m.op === "peer_returned").length, 0, "no estaba ausente");
	host.close();
	back.close();
});

test("si no vuelve a tiempo, el otro recibe peer_disconnected y la sala se borra", async () => {
	const { host, remote, code, remoteToken } = await room(server.url);
	remote.close();
	await host.next("peer_reconnecting");
	await host.next("peer_disconnected", GRACE_MS + 1500);
	const late = await Client.open(server.url);
	late.send({ op: "rejoin", code, token: remoteToken });
	assert.equal((await late.next("rejoin_failed")).message, "La sala ya no existe");
	host.close();
	late.close();
});

test("salir a proposito avisa al otro sin esperar", async () => {
	const { host, remote } = await room(server.url);
	remote.send({ op: "leave" });
	const t0 = Date.now();
	await host.next("peer_disconnected");
	assert.ok(Date.now() - t0 < GRACE_MS, "no espero la gracia");
	host.close();
	remote.close();
});

test("el Anfitrion solo (sin Remoto) que se cae borra la sala", async () => {
	const host = await Client.open(server.url);
	host.send({ op: "create_room" });
	const { code } = await host.next("room_created");
	host.close();
	await new Promise((r) => setTimeout(r, 200));
	const remote = await Client.open(server.url);
	remote.send({ op: "join_room", code });
	assert.equal((await remote.next("error")).message, "Sala no encontrada");
	remote.close();
});

test("mensajes invalidos o sin sala", async () => {
	const c = await Client.open(server.url);
	c.ws.send("no es json");
	assert.equal((await c.next("error")).message, "JSON invalido");
	c.send([1, 2]);
	assert.equal((await c.next("error")).message, "Mensaje invalido");
	c.send({ op: "move_card" });
	assert.equal((await c.next("error")).message, "No estas en ninguna sala todavia");
	c.send({ op: "create_room" });
	await c.next("room_created");
	c.send({ op: "move_card" });
	assert.equal((await c.next("error")).message, "Todavia no hay nadie del otro lado");
	c.close();
});

test("limite de mensajes por segundo", async () => {
	const limited = await startServer({ MSG_BURST: "5", MSG_PER_SEC: "1" });
	try {
		const c = await Client.open(limited.url);
		for (let i = 0; i < 10; i++) c.send({ op: "ping" });
		assert.equal((await c.next("error")).message, "Demasiados mensajes");
		await new Promise((r) => setTimeout(r, 200));
		assert.ok(c.closed, "cierra la conexion");
	} finally {
		limited.stop();
	}
});

test("limite de conexiones por IP", async () => {
	const limited = await startServer({ MAX_CONN_PER_IP: "2" });
	try {
		const a = await Client.open(limited.url);
		const b = await Client.open(limited.url);
		const c = await Client.open(limited.url);
		assert.equal((await c.next("error")).message, "Demasiadas conexiones desde tu red");
		for (const x of [a, b, c]) x.close();
	} finally {
		limited.stop();
	}
});
