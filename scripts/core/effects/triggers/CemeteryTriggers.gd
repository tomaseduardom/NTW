extends RefCounted
## CemeteryTriggers — "Cuando sea puesta en tu Cementerio, ..." (2026-10-14,
## a pedido del usuario: Lanza Argenta no tenía este disparador en ningún
## lado).
##
## Toda carta que entra a un Cementerio pasa por CardManager._append_to_cemetery()
## (choke point único), que emite card_put_in_cemetery. Aquí se anota la carta
## y el disparador se resuelve recién cuando NO queda nada resolviéndose (la
## regla que pidió el usuario: "Signo Amarillo descarta Lanza Argenta → Signo
## termina primero, después dispara la Lanza"). El texto de la carta vive en
## el Cementerio (es un Dictionary, no un Node), así que para la ventana de
## respuesta del rival se arma un Node temporal de la carta.
##
## Por ahora solo Lanza Argenta; las demás cartas de "puesta en tu Cementerio"
## (kultrung, piedra del chaman, serpiente verde, ...) se agregan aquí.

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")

## Lanza Argenta: "Cuando sea puesta en tu Cementerio, Baraja esta carta y
## hasta otras dos cartas de un Cementerio en el Castillo de su dueño."
const LANZA_TEXT := "cuando sea puesta en tu cementerio, baraja esta carta y hasta otras dos cartas de un cementerio"

var _pending: Array = []  # [{owner, data}]
var _running: bool = false


func on_card_put_in_cemetery(player_id: int, card_data: Dictionary) -> void:
	if not GameManager.is_game_active:
		return
	if not (LANZA_TEXT in _normalize(str(card_data.get("habilidad", "")))):
		return
	_pending.append({"owner": player_id, "data": card_data})
	if not _running:
		_running = true
		_run.call_deferred()


static func _normalize(t: String) -> String:
	return t.to_lower().replace("\n", " ").replace("ñ", "n").replace("�", "n")


func _run() -> void:
	while not _pending.is_empty():
		if not await _wait_until_idle():
			break
		var entry: Dictionary = _pending.pop_front()
		await _resolve_lanza(entry.owner, entry.data)
	_pending.clear()
	_running = false


func _main() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Main")


func is_idle() -> bool:
	"""Nada resolviéndose ni esperando una elección del jugador."""
	var main := _main()
	if not main:
		return false
	if not EffectContextScript._stack.is_empty():
		return false
	if ActionPipeline.is_stack_processing() or TriggerSystem.awaiting_response or TriggerSystem.is_resolving:
		return false
	if not TriggerSystem.trigger_queue.is_empty():
		return false
	if main._zone_browse_picker and main._zone_browse_picker.is_active():
		return false
	if SelectionManager.is_open:
		return false
	var ci = main.get("_card_interaction")
	if ci and ci.get("_target_callback") is Callable and ci._target_callback.is_valid():
		return false
	var bm = main.get_node_or_null("/root/BattleManager")
	if bm and bm.get("combat_in_progress"):
		return false
	return true


func _wait_until_idle() -> bool:
	"""Espera hasta que todo esté quieto durante 0,3 s seguidos (entre el
	costo y el efecto de una habilidad puede haber un instante "quieto")."""
	var tree := Engine.get_main_loop() as SceneTree
	var quiet := 0
	for _i in 6000:  # hasta 10 min: puede haber una elección larga del jugador
		if not GameManager.is_game_active:
			return false
		quiet = quiet + 1 if is_idle() else 0
		if quiet >= 3:
			return true
		await tree.create_timer(0.1).timeout
	return false


func _resolve_lanza(owner_id: int, lanza_data: Dictionary) -> void:
	var main := _main()
	if not main:
		return
	var cemetery: Array = CardManager.get_cemetery(owner_id)
	# Sin habilidad en el Cementerio (Sable de Napoleón) o nombre bloqueado.
	if CardManager.is_cemetery_card_silenced(lanza_data) \
			or KeywordManager.is_name_locked(str(lanza_data.get("nombre", ""))):
		return
	var card_name: String = str(lanza_data.get("nombre", "Lanza Argenta"))
	main._update_debug("%s fue puesta en tu Cementerio: se dispara su habilidad" % card_name)

	# Node temporal (la carta está en el Cementerio, solo hay datos).
	var proxy: Node = main._create_card(lanza_data, false)
	proxy.visible = false
	main.add_child(proxy)
	proxy.owner_id = owner_id
	proxy.current_zone = Constants.Zone.CEMENTERIO
	var token: int = EffectContextScript.push(proxy, owner_id, "disparada", "pending")

	# Hasta otras dos cartas de UN Cementerio (cualquiera de los dos).
	var pools: Array = []
	var src: Array = []
	for zone_owner in [owner_id, 1 - owner_id]:
		var entries: Array = []
		for d in CardManager.get_cemetery(zone_owner):
			entries.append({"data": d, "eligible": not is_same(d, lanza_data)})
		pools.append({"is_own": zone_owner == owner_id, "zone": Constants.Zone.CEMENTERIO, "cards": entries,
			"exclusive": true})
		src.append(zone_owner)
	var raw: Array = await ActionModule.pick_in_zones(owner_id,
		"%s: elige hasta otras dos cartas de un Cementerio para barajar con ella" % card_name, pools, 0, 2)
	var picks: Array = []
	var first_pool := -1
	for rp in raw:
		if not (rp is Array) or rp.size() != 2:
			continue
		var pi := int(rp[0])
		var ci := int(rp[1])
		if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			continue
		if first_pool < 0:
			first_pool = pi
		if pi != first_pool or picks.size() >= 2:
			continue
		var d: Dictionary = pools[pi].cards[ci].data
		if picks.any(func(p): return is_same(p.data, d)):
			continue
		picks.append({"owner": src[pi], "data": d})

	var cancelled: bool = await TriggerSystem.open_response_window(proxy, card_name, owner_id)
	EffectContextScript.pop(token)
	proxy.queue_free()
	if cancelled:
		return

	# Cada carta vuelve al Castillo de SU dueño; se baraja cada Castillo tocado.
	var shuffled: Dictionary = {}
	var moved := 0
	var to_move: Array = [{"owner": owner_id, "data": lanza_data}] + picks
	for m in to_move:
		var cem: Array = CardManager.get_cemetery(m.owner)
		var idx := -1
		for i in range(cem.size()):
			if is_same(cem[i], m.data):
				idx = i
				break
		if idx < 0:
			continue  # ya no está ahí (en medida de lo posible)
		var d: Dictionary = cem[idx]
		cem.remove_at(idx)
		CardManager._emit_cemetery_changed(m.owner)
		CardManager._update_cemetery_visual(m.owner)
		d["esta_oculta"] = true
		CardManager.get_deck(m.owner).append(d)
		shuffled[m.owner] = true
		moved += 1
	for p in shuffled:
		CardManager.shuffle_deck(p)
		AnimationQueue.queue_shuffle(p, "Barajar mazo (%s)" % card_name)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	main._update_debug("%s: %d carta(s) barajadas en el Castillo" % [card_name, moved])
