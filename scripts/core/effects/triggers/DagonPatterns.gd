extends RefCounted
## Padre Dagón (2026-10-17, a pedido del usuario): dos habilidades en un solo
## texto, como Bernardo O'Higgins, que comparten el "Una vez por turno":
##   - Activada (tu turno o Guerra de Talismanes), global, sin objetivo: "las
##     cartas oponentes que no sean Oro pierden su habilidad y son
##     Destruidas". Primero pierden la habilidad, así que lo que dirían al
##     salir del juego no ocurre.
##   - Prevención (EffectController._prevention_registry, "Padre Dagón"):
##     "prevén que uno o más Aliados sean afectados por un efecto oponente",
##     como Estaca o Cañón Helios.
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const ACTIVATED_TEXT := "las cartas oponentes que no sean oro pierden su habilidad y son destruidas"
const PREVENTION_TEXT := "prevén que uno o más aliados sean afectados por un efecto oponente"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func usage_key(card: Node) -> String:
	return "dagon:%d" % card.get_instance_id()


static func used_this_turn(card: Node) -> bool:
	return UniversalCardParser.turn_registry.was_used(usage_key(card), 0, GameManager.current_turn)


static func mark_used(card: Node) -> void:
	UniversalCardParser.turn_registry.register(usage_key(card), 0, GameManager.current_turn)


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	if not (ACTIVATED_TEXT in text.to_lower()):
		return false
	var main := _main_node()
	if not main or not is_instance_valid(card):
		return true
	var card_name: String = str(card.get("card_name"))
	if used_this_turn(card):
		main._update_debug("%s: ya usaste su habilidad este turno" % card_name)
		return true
	mark_used(card)
	var opponent_id: int = 1 - controller_id
	var victims: Array = []
	for container in PlayerSideScript.line_containers(main, opponent_id):
		if not container:
			continue
		for c in container.get_children():
			if not is_instance_valid(c) or c.get("card_type") == Constants.CardType.ORO:
				continue
			victims.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w) and not (w in victims):
						victims.append(w)
	if victims.is_empty():
		main._update_debug("%s: tu oponente no tiene cartas que no sean Oro" % card_name)
		return true
	# 0) Antes de que pase nada (2026-10-17, a pedido del usuario): el
	# oponente puede prevenir que cada carta sea afectada (Estaca, Cañón
	# Helios...) — la que se previene no pierde su habilidad ni es Destruida.
	var affected: Array = []
	for v in victims:
		if not is_instance_valid(v) or not (v.get("current_zone") in Constants.ZONES_IN_PLAY):
			continue
		if await EffectController.offer_prevention(v, card, "silence"):
			continue
		affected.append(v)
	# 1) Pierden su habilidad (también Indestructible, salvo las que no
	# pueden perderla) — 2) son Destruidas.
	for v in affected:
		if is_instance_valid(v):
			await KeywordManager.silence_card(v, card, "permanent", true)
	var to_destroy: Array = affected.filter(func(v): return is_instance_valid(v) and v.get("current_zone") in Constants.ZONES_IN_PLAY)
	if not to_destroy.is_empty():
		await ActionModule.destroy(to_destroy, card, false)
	main._update_debug("%s: las cartas oponentes que no son Oro pierden su habilidad y son Destruidas" % card_name)
	return true
