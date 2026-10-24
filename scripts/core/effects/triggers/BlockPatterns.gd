extends RefCounted
## "Cuando bloquee" que el compilador no entiende porque dependen de a quién bloquea la carta
## (event_data.blocked, armado en GameManager.confirm_blockers_and_collect_triggers()), y la regla
## estática de al-ahmar. "No hace daño de combate": meta no_damage_turn, como Estación Fantasma
## (BattleManager no suma su daño ni destruye a su bloqueador). Se usa con preload.

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")

## arthur gordon pym: "Cuando bloquee, los Aliados que hayan sido bloqueados no hacen de daño de
## combate este turno".
const BLOCKED_NO_DAMAGE_RX := "los aliados que hayan sido bloqueados no hacen (?:de )?dano de combate este turno"
## Elías: "Cuando bloquee, puedes Robar una carta por cada Aliado al que bloquee".
const DRAW_PER_BLOCKED := "puedes robar una carta por cada aliado al que bloquee"
## al-ahmar (estática, no disparada): "Los Aliados bloqueados por este Aliado no hacen daño de
## combate este turno".
const STATIC_NO_DAMAGE := "los aliados bloqueados por este aliado no hacen dano de combate este turno"
## Elías (estáticas): "puede bloquear hasta dos Aliados" y "no recibes daño de Aliados bloqueados por
## este Aliado".
const BLOCKS_TWO := "puede bloquear hasta dos aliados"
const NO_CASTLE_DAMAGE := "no recibes dano de aliados bloqueados por este aliado"


static func _has_static(card: Node, phrase: String) -> bool:
	return is_instance_valid(card) and not KeywordManager.is_silenced(card) \
		and phrase in CemeteryTriggersScript.normalize(str(card.get("card_ability")))


static func max_blocks(blocker: Node) -> int:
	"""Cuántos atacantes puede bloquear a la vez (GameManager.blockers es {atacante: bloqueador}, así
	que un bloqueador puede aparecer como valor más de una vez)."""
	return 2 if _has_static(blocker, BLOCKS_TWO) else 1


static func blocks_of(blocker: Node) -> Array:
	"""Atacantes que 'blocker' tiene declarados este combate."""
	var out: Array = []
	for attacker in GameManager.blockers:
		if GameManager.blockers[attacker] == blocker:
			out.append(attacker)
	return out


static func can_block_more(blocker: Node) -> bool:
	return blocks_of(blocker).size() < max_blocks(blocker)


static func shields_castle(blocker: Node) -> bool:
	"""Elías: el daño excedente de los Aliados que bloquea no llega al Castillo."""
	return _has_static(blocker, NO_CASTLE_DAMAGE)


static func _main_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func try_execute(card: Node, clause: String, controller_id: int, event_data: Dictionary) -> bool:
	"""Disparadores "Cuando bloquee" de este archivo. true si la cláusula es suya (aunque no haga
	nada: sin bloqueados o "puedes" rechazado)."""
	var text := CemeteryTriggersScript.normalize(clause)
	var blocked: Array = event_data.get("blocked", []).filter(func(a): return is_instance_valid(a))
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Carta"
	var main := _main_node()
	if RegEx.create_from_string(BLOCKED_NO_DAMAGE_RX).search(text) != null:
		if blocked.is_empty() or await EffectContextScript.ensure_window():
			return true
		for a in blocked:
			a.set_meta("no_damage_turn", GameManager.turn_serial)
		if main:
			main._update_debug("%s: los Aliados bloqueados no hacen daño de combate este turno" % card_name)
		return true
	if DRAW_PER_BLOCKED in text:
		if blocked.is_empty():
			return true
		var amount := blocked.size()
		if not PlayerSideScript.is_bot(controller_id) and main:
			var label := "Robar %d carta%s" % [amount, "" if amount == 1 else "s"]
			if not await SelectionManager.await_two_choice(main, card_name, label, "No robar", controller_id):
				return true
		await ActionModule.draw(controller_id, amount, card_name)
		return true
	return false


static func apply_static_on_blockers(blocks: Dictionary) -> void:
	"""al-ahmar: al confirmar los bloqueos. blocks = {bloqueador: [atacantes]}. No es una habilidad
	disparada: no tiene ventana de respuesta."""
	for blocker in blocks:
		if not _has_static(blocker, STATIC_NO_DAMAGE):
			continue
		for a in blocks[blocker]:
			if is_instance_valid(a):
				a.set_meta("no_damage_turn", GameManager.turn_serial)
