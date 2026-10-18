extends RefCounted
## Peaje de Oro a habilidades disparadas (2026-10-17, Mecha-Daikaiju: "...y
## hasta tu próximo turno tu oponente no puede utilizar habilidades
## disparadas a menos que pague un Oro."). El estado vive como meta del nodo
## Main: {jugador afectado: turno en que deja de valer}. Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const TEXT := "hasta tu próximo turno tu oponente no puede utilizar habilidades disparadas a menos que pague un oro"


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func register_if_text(full_text: String, controller_id: int) -> void:
	"""Llamar cuando se resuelve el efecto que trae el texto."""
	if not (TEXT in full_text.to_lower().replace("\n", " ")):
		return
	var main := _main_node()
	if not main:
		return
	var tolls: Dictionary = main.get_meta("gold_trigger_toll", {})
	# Hasta el próximo turno del controlador: los turnos se cuentan de a uno
	# por jugador, así que es el turno actual + 2.
	tolls[1 - controller_id] = GameManager.current_turn + 2
	main.set_meta("gold_trigger_toll", tolls)
	main._update_debug("Hasta tu próximo turno, tu oponente debe pagar un Oro para usar habilidades disparadas")


static func blocks_trigger(card: Node, controller_id: int) -> bool:
	"""true si la habilidad disparada de 'card' no se usa (no pagó el Oro)."""
	var main := _main_node()
	if not main or not main._gold_manager or not is_instance_valid(card):
		return false
	var tolls: Dictionary = main.get_meta("gold_trigger_toll", {})
	if not tolls.has(controller_id):
		return false
	if GameManager.current_turn >= int(tolls[controller_id]):
		tolls.erase(controller_id)
		main.set_meta("gold_trigger_toll", tolls)
		return false
	var gm = main._gold_manager
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "esa carta"
	if not gm.puede_pagar(1, -1, "", -1, controller_id):
		main._update_debug("%s: no puedes pagar un Oro — la habilidad no se usa" % card_name)
		return true
	var pay: bool = PlayerSideScript.is_bot(controller_id)
	if not pay:
		pay = await SelectionManager.await_two_choice(main, card_name,
			"Pagar un Oro para usar la habilidad", "No usarla", controller_id)
	if not pay or not await gm.pagar_coste(1, -1, "", -1, controller_id):
		main._update_debug("La habilidad de %s no se usa" % card_name)
		return true
	return false
