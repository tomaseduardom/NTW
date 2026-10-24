extends RefCounted
## AllyEventTriggers — disparadores de Fuerza para "tus Aliados" / "los Aliados oponentes" con eventos
## que el sistema de disparadores no ve solo:
## - ogun: "Una vez por turno, cuando este u otro Aliado entra en juego bajo tu control, tus Aliados
##   ganan 1 de Fuerza permanentemente." (EffectController.on_card_entered_play)
## - troll soberano: "Una vez por turno, cuando juegues un Aliado, los Aliados oponentes pierden 1 de
##   Fuerza permanentemente." (GoldManager._trigger_enter_play(), como Dhampir)
## - "Si es Anulado, ..." (santos pincheira y 18 Talismanes): on_stopped(), desde
##   TriggerSystem.open_response_window().
## El efecto es un "mass_buff" de EffectInterpreter (los Aliados en juego en ese momento, con la
## Prevención del rival) y abre su propia Ventana de Respuesta. Solo corre en el Anfitrión.
## Se usa con preload (sin class_name global; ver §54).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")

const OGUN := "cuando este u otro aliado entra en juego bajo tu control, tus aliados ganan"
const TROLL := "cuando juegues un aliado, los aliados oponentes pierden"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func _is_logic_side() -> bool:
	return NetworkClient.room_code == "" or NetworkClient.is_host


static func _text(c: Node) -> String:
	return str(c.get("card_ability")).to_lower()


static func _sources(main: Node, pid: int, phrase: String) -> Array:
	var out: Array = []
	for container in PlayerSideScript.line_containers(main, pid):
		for c in container.get_children():
			if is_instance_valid(c) and phrase in _text(c) and not KeywordManager.is_silenced(c):
				out.append(c)
	return out


static func on_card_entered(pid: int, card: Node) -> void:
	"""ogun."""
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ALIADO:
		return
	if not _is_logic_side() or not GameManager.is_game_active:
		return
	var main := _main_node()
	if not main:
		return
	var ctrl: int = int(card.controller_id) if card.get("controller_id") != null else pid
	for ogun in _sources(main, ctrl, OGUN):
		await _once_per_turn(ogun, ctrl, "ogun", 1)


static func on_card_played(played: Node, player_id: int) -> void:
	"""troll soberano."""
	if not is_instance_valid(played) or played.get("card_type") != Constants.CardType.ALIADO:
		return
	if not _is_logic_side() or not GameManager.is_game_active:
		return
	var main := _main_node()
	if not main:
		return
	for troll in _sources(main, player_id, TROLL):
		if troll != played:
			await _once_per_turn(troll, player_id, "troll", -1)


static func on_stopped(card: Node, controller_id: int, kind: String = "carta") -> void:
	""""Si es Anulado, <efecto>" (Acabar la Esperanza, Juicio de Vigilantes, ensamble, dulcinea, ...; 19
	cartas) y "Si es Anulado o su habilidad sea Cancelada, ..." (santos pincheira). 'kind' es el de la
	ventana (TriggerSystem.open_response_window): "carta"/"Talismán" = Anular; "disparada"/"activada"
	= Cancelar una habilidad, que solo cuenta con "o su habilidad sea Cancelada".
	El efecto se resuelve con EffectInterpreter en un contexto propio (el de la carta anulada quedó
	"cancelled"). "Conviértelo en un Oro sin habilidad y ponlo en tu Oro Pagado" (asalto estelar) lo
	aplica GoldManager._play_talisman() en vez de mandarlo al Cementerio."""
	if not is_instance_valid(card) or not _is_logic_side():
		return
	if kind == "carta" and card.get("card_type") == Constants.CardType.ALIADO:
		load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("ally_annulled", {"pid": controller_id,
			"name": str(card.card_name), "owner": int(card.owner_id) if card.get("owner_id") != null else controller_id})
	if _rx_stopped == null:
		_rx_stopped = RegEx.create_from_string("(?:^|[.\\n]\\s*)si es anulad[oa]( o su habilidad sea cancelada)?,? ([^.\\n]+)")
	var m := _rx_stopped.search(_text(card))
	if not m:
		return
	if kind in ["disparada", "activada"] and m.get_string(1) == "":
		return
	var effect := m.get_string(2).strip_edges()
	if effect.begins_with("conviértelo en un oro sin habilidad y ponlo en tu oro pagado"):
		card.set_meta("annul_to_pagado_gold", true)
		return
	var interpreter = TriggerSystem.get("_effect_interpreter")
	if not interpreter:
		return
	var token: int = EffectContextScript.push(card, controller_id, "disparada", "done")
	var resolved: bool = await interpreter.try_execute(card, effect, controller_id)
	EffectContextScript.pop(token)
	if not resolved:
		push_warning("[AllyEventTriggers] %s: 'Si es Anulado, %s' no se pudo resolver" % [str(card.get("card_name")), effect])

static var _rx_stopped: RegEx = null


static func _once_per_turn(source: Node, ctrl: int, tag: String, amount: int) -> void:
	var key := "%s:%d" % [tag, source.get_instance_id()]
	if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.turn_serial):
		return
	UniversalCardParser.turn_registry.register(key, 0, GameManager.turn_serial)
	if await TriggerSystem.open_response_window(source, str(source.card_name), ctrl):
		return
	await _mass_buff(source, ctrl, "opponent" if amount < 0 else "own", absi(amount))


static func _mass_buff(source: Node, ctrl: int, side: String, amount: int) -> void:
	var main := _main_node()
	if not main or not TriggerSystem.get("_effect_interpreter"):
		return
	var st := {"op": "mass_buff", "verb": "buff", "side": side, "others": false,
		"amount": -amount if side == "opponent" else amount, "keywords": [], "to_exile": false,
		"permanent": true, "turn_only": false}
	await TriggerSystem._effect_interpreter.execute_step_mass_buff(main, st, source, ctrl)
	main._update_debug("%s: %s %d de Fuerza" % [str(source.card_name),
		"los Aliados oponentes pierden" if side == "opponent" else "tus Aliados ganan", amount])
