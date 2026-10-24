extends Node
## RuleState — registro único del estado de las reglas especiales, en vez de metadatos sueltos en
## Main. Todo cuenta con GameManager.turn_serial (un número por cada turno de jugador; current_turn
## sube una vez por ronda) y vence o se reinicia solo:
## - contadores de este turno: count() / add()
## - efectos "hasta el turno N": set_until() / active() (next_own_turn())
## - marcas de este turno: mark() / marked()
## - pendientes de un solo uso: set_pending() / has_pending() / take_pending()
## - datos que valen este turno: set_turn_data() / turn_data()
## Se borra todo al empezar una partida (GameManager.game_started). Solo corre en el Anfitrión (el
## Remoto no ejecuta la lógica).
## Claves en uso: "searched", "outside_ability", "castle_removed" (TurnLimits), "no_combat_damage",
## "no_direct_damage" (Linaje Maldito, Quicaví), "trigger_gold_toll" (Mecha-Daikaiju), "escritura"
## (Escritura Sagrada), "next_gold_silenced" (Supremacia Kaiju), "sidhes_lock" (Sidhes del Bosque).

var _counters: Dictionary = {}   # clave -> {"turn": n, pid: cantidad}
var _until: Dictionary = {}      # clave -> {pid: turno de jugador en que vence}
var _from: Dictionary = {}       # clave -> {pid: turno de jugador en que empieza} (set_window)
var _marks: Dictionary = {}      # clave -> {pid: turno de jugador}
var _pending: Dictionary = {}    # clave -> {pid: valor}
var _turn_data: Dictionary = {}  # clave -> {"turn": n, "data": Dictionary}
var _source: Dictionary = {}     # clave -> {pid: jugador cuyo efecto lo puso (-1: sin saber)} (set_until)


func _ready() -> void:
	if not GameManager.game_started.is_connected(reset):
		GameManager.game_started.connect(reset)
	# Mano descubierta (Lady Mina Harker, invocar ángeles): se vuelve a mostrar al empezar cada turno.
	GameManager.turn_started.connect(func(_p: int, _t: int) -> void:
		load("res://scripts/core/effects/mechanics/HandReveal.gd").refresh())


func reset() -> void:
	_counters.clear()
	_until.clear()
	_from.clear()
	_marks.clear()
	_pending.clear()
	_turn_data.clear()
	_source.clear()


func _now() -> int:
	return GameManager.turn_serial


# --- contadores de este turno -------------------------------------------------
func count(key: String, pid: int) -> int:
	var c: Dictionary = _counters.get(key, {})
	if int(c.get("turn", -1)) != _now():
		return 0
	return int(c.get(pid, 0))


func add(key: String, pid: int, amount: int = 1) -> void:
	var c: Dictionary = _counters.get(key, {})
	if int(c.get("turn", -1)) != _now():
		c = {"turn": _now()}
	c[pid] = int(c.get(pid, 0)) + amount
	_counters[key] = c


# --- efectos con vencimiento ---------------------------------------------------
## El turno de jugador en que empieza el próximo turno de 'pid' (para "hasta tu
## próximo turno": el efecto vale mientras no haya llegado).
func next_own_turn(pid: int) -> int:
	return _now() + (2 if GameManager.active_player_id == pid else 1)


func set_until(key: String, pid: int, until_turn: int) -> void:
	var d: Dictionary = _until.get(key, {})
	d[pid] = maxi(int(d.get(pid, -1)), until_turn)
	_until[key] = d
	# Quién lo impuso (el controlador del efecto en curso): los costes adicionales que impone el rival
	# afectan al jugador (DAR abril 2026), EffectController.opp_cost_waived().
	var ctx: Dictionary = load("res://scripts/core/effects/EffectContext.gd").current()
	var s: Dictionary = _source.get(key, {})
	s[pid] = int(ctx.controller_id) if not ctx.is_empty() else -1
	_source[key] = s


## Jugador cuyo efecto puso 'key' sobre 'pid' (-1 si no se sabe).
func source_of(key: String, pid: int) -> int:
	return int(_source.get(key, {}).get(pid, -1))


func active(key: String, pid: int) -> bool:
	return int(_from.get(key, {}).get(pid, -1)) <= _now() and _now() < int(_until.get(key, {}).get(pid, -1))


## Vale desde el turno 'from_turn' (incluido) hasta antes de 'until_turn' ("los próximos dos turnos": el
## del rival y tu próximo).
func set_window(key: String, pid: int, from_turn: int, until_turn: int) -> void:
	var d: Dictionary = _from.get(key, {})
	d[pid] = from_turn
	_from[key] = d
	set_until(key, pid, until_turn)


# --- marcas de este turno ------------------------------------------------------
func mark(key: String, pid: int) -> void:
	var d: Dictionary = _marks.get(key, {})
	d[pid] = _now()
	_marks[key] = d


func marked(key: String, pid: int) -> bool:
	return int(_marks.get(key, {}).get(pid, -1)) == _now()


# --- pendientes de un solo uso ---------------------------------------------------
func set_pending(key: String, pid: int, value = true) -> void:
	var d: Dictionary = _pending.get(key, {})
	d[pid] = value
	_pending[key] = d


func has_pending(key: String, pid: int) -> bool:
	return _pending.get(key, {}).has(pid)


func take_pending(key: String, pid: int):
	var d: Dictionary = _pending.get(key, {})
	var value = d.get(pid)
	d.erase(pid)
	return value


# --- datos que valen este turno --------------------------------------------------
func set_turn_data(key: String, data: Dictionary) -> void:
	_turn_data[key] = {"turn": _now(), "data": data}


func turn_data(key: String) -> Dictionary:
	var entry: Dictionary = _turn_data.get(key, {})
	if int(entry.get("turn", -1)) != _now():
		return {}
	return entry.get("data", {})
