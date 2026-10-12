extends RefCounted
class_name EffectContext
## EffectContext — qué carta y qué jugador controlan el efecto que se está
## resolviendo AHORA, y el detector de paridad (2026-10-12, arquitectura.md
## §56, a pedido del usuario).
##
## Lo empujan los tres puntos donde se resuelve un efecto: TriggerResolution.
## resolve_next_trigger() (habilidades disparadas), TriggerSystem.
## resolve_talisman() y StackStepResolver._resolve_ability() (activadas).
##
## Detector: las funciones de selección (CardInteractionModule.await_*,
## SelectionManager.await_*/open_*, ZoneViewerModule.open_cemetery_target_
## picker(), ActionSearch) y GoldManager.pagar_coste() llaman a check_*().
## Si el efecto es del jugador 1 (Remoto o bot) pero elige/paga el jugador
## 0, imprime una línea "[PARIDAD]" con la carta y qué se pidió — casi
## siempre es un patrón viejo escrito solo para el Anfitrión. Es una
## heurística: hay casos legítimos ("tu oponente elige", prevenciones que
## ofrece el rival), por eso solo avisa, nunca cambia nada.
##
## Funciona también contra el bot: jugando una partida local, cada línea
## [PARIDAD] marca una carta que con un Remoto real fallaría.
##
## Ventana de respuesta única por efecto (2026-10-12, §59, opción B elegida
## por el usuario: el rival responde DESPUÉS de que se declaran los
## objetivos). Cada entrada lleva 'window': "pending" (todavía no se le dio
## la ventana al rival), "done" o "cancelled". TriggerSystem.
## open_response_window() la consulta cuando la pide la propia carta del
## efecto: si ya se abrió, no abre otra; si estaba pendiente, esa ES la
## ventana. Si el patrón nunca la pide, ensure_window() la abre justo antes
## de la primera acción real (ActionModule, poner Oros en juego, jugar
## gratis). Si el rival la cancela, las acciones siguientes no se ejecutan.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

static var _stack: Array = []
static var _next_token: int = 1
static var _reported: Dictionary = {}


static func push(card: Node, controller_id: int, kind: String, window: String = "done") -> int:
	"""Devuelve un token para pop(): los efectos pueden anidarse y, como son
	coroutines, terminar en otro orden — pop() saca SU entrada, no la de
	arriba. 'window': "pending" si al rival todavía no se le dio su
	ventana de respuesta para este efecto, "done" si ya la tuvo (activadas:
	la Pila ya les dio su Paso D)."""
	var token := _next_token
	_next_token += 1
	var name: String = str(card.get("card_name")) if is_instance_valid(card) and card.get("card_name") != null else "?"
	_stack.append({"token": token, "card": card, "card_name": name, "controller_id": controller_id, "kind": kind,
		"window": window})
	return token


static func window_state(token: int) -> String:
	for e in _stack:
		if e.token == token:
			return e.window
	return ""


static func ensure_window() -> bool:
	"""Abre la ventana de respuesta del efecto en curso si todavía estaba
	pendiente (justo antes de su primera acción real). Devuelve true si el
	efecto quedó cancelado/anulado — el llamador NO debe ejecutar su acción."""
	var ctx := current()
	if ctx.is_empty():
		return false
	match str(ctx.window):
		"cancelled":
			return true
		"pending":
			if not is_instance_valid(ctx.card):
				ctx.window = "done"
				return false
			return await TriggerSystem.open_response_window(ctx.card, ctx.card_name, int(ctx.controller_id))
	return false


static func pop(token: int) -> void:
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i].token == token:
			_stack.remove_at(i)
			return


static func current() -> Dictionary:
	return _stack[-1] if not _stack.is_empty() else {}


static func check_chooser(chooser_id: int, what: String) -> void:
	"""Una selección se abre para 'chooser_id' — avisa si el efecto en curso
	es del jugador 1 y elige el 0."""
	var ctx := current()
	if ctx.is_empty() or int(ctx.controller_id) != 1 or chooser_id != 0:
		return
	_report(ctx, "elige el Anfitrión: %s" % what)


static func check_payment(player_id: int, amount: int) -> void:
	"""Un pago sale de los Oros de 'player_id' — avisa si el efecto en curso
	es del jugador 1 y paga el 0."""
	var ctx := current()
	if ctx.is_empty() or int(ctx.controller_id) != 1 or player_id != 0 or amount <= 0:
		return
	_report(ctx, "paga %d Oro el Anfitrión" % amount)


static func _report(ctx: Dictionary, detail: String) -> void:
	var key := "%s|%s" % [ctx.card_name, detail]
	var n: int = _reported.get(key, 0) + 1
	_reported[key] = n
	if n > 3:
		return  # no inundar el log con la misma carta en bucle
	var line := "[PARIDAD] %s (%s del %s) — %s" % [ctx.card_name, ctx.kind, PlayerSideScript.label(1), detail]
	print(line)
	push_warning(line)
