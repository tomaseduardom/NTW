extends RefCounted
class_name BernardoAbilityHandler
## BernardoAbilityHandler — Bernardo O'Higgins: coste alternativo (Barajar un Arma/Aliado Caballero)
## + efecto con objetivo (Desterrar coste ≤3 o cancelar una habilidad).
## CardInspectionLayer._build_ability_buttons() lo detecta (is_bernardo_pattern) y lo manda aquí.
## Opera sobre CardInspectionLayer vía _inspector (y sobre Main vía _inspector._main).

var _inspector: CardInspectionLayer


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func _activate_bernardo_shuffle_removal(source_card: Node, ability: Dictionary) -> void:
	""""Una vez por turno, puedes Barajar un Arma o Aliado Caballero de tu mano o que controles para
	Desterrar una carta de coste 3 o menos o cancelar una habilidad. No se pueden Barajar Aliados
	con Arma." (La versión de la API tiene las cláusulas en otro orden.)"""
	if not is_instance_valid(source_card):
		return

	var _main := _inspector._main
	var candidates: Array = []
	if _main.player_hand:
		for c in _main.player_hand.cards:
			if _bernardo_can_shuffle(c):
				candidates.append(c)
	for field in [_main.player_field, _main.player_linea_ataque]:
		if not field:
			continue
		for c in field.get_children():
			if c != source_card and _bernardo_can_shuffle(c):
				candidates.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if _bernardo_can_shuffle(w):
						candidates.append(w)

	if candidates.is_empty():
		_main._update_debug("No tienes un Arma ni un Aliado Caballero para Barajar")
		return

	if not _main._card_interaction:
		return
	# Click directo sobre la mano/campo en vez del modal de lista viejo.
	var cost_filter := func(c: Node) -> bool: return c in candidates
	var cost_card: Node = await _main._card_interaction.await_target(
		"Baraja un Arma o Caballero (coste de la habilidad)", cost_filter)
	if not cost_card or not is_instance_valid(cost_card):
		return  # canceló — no se pagó nada, no se marca "una vez por turno"
	# Revalidar source_card después del await: si Bernardo salió de juego mientras el jugador elegía,
	# la referencia queda colgante (como en HandCementerioAbilityHandler.gd).
	if not is_instance_valid(source_card) or not is_instance_valid(cost_card):
		return

	var cost_owner: int = cost_card.owner_id if cost_card.get("owner_id") != null else 0
	_bernardo_shuffle_into_deck(cost_card, cost_owner)

	# "Una vez por turno" se marca recién con el coste pagado (como ActionPipeline.activate_ability(),
	# Paso B). register_ability_use() usa el instance_id de source_card: cada copia tiene su propio
	# cupo.
	UniversalCardParser.turn_registry.register_ability_use(source_card, ability)

	# La rama se elige sola según el momento
	# (AbilityButtonSupport._is_responding_to_opponent_action()): en tu turno o en Guerra de Talismanes
	# (proactivo) → Desterrar; respondiendo a una carta o habilidad del rival (§10.53) → Cancelar.
	if not is_instance_valid(source_card):
		return

	if _inspector._button_support._is_responding_to_opponent_action():
		await _bernardo_cancel_ability_target(source_card)
	else:
		await _bernardo_banish_target(source_card)


func _bernardo_can_shuffle(c: Node) -> bool:
	if not is_instance_valid(c):
		return false
	if c.get("card_type") == Constants.CardType.ARMA:
		return true
	if c.get("card_type") == Constants.CardType.ALIADO:
		var raza: String = str(c.get("card_raza") if c.get("card_raza") != null else "").to_lower()
		if not ("caballero" in raza):
			return false
		var weapons = c.get("equipped_weapons")
		if weapons is Array and not weapons.is_empty():
			return false  # No se pueden Barajar Aliados con Arma
		return true
	return false


func _bernardo_shuffle_into_deck(card: Node, owner_id: int) -> void:
	var cm := CardManager
	var _main := _inspector._main
	var data: Dictionary = card.card_data.duplicate()
	data["esta_oculta"] = true
	# Barajar como coste un Arma equipada: hay que sacarla de equipped_weapons de su portador, o
	# compact_all_fields() lee una referencia liberada.
	CardManager._unequip_from_wielder(card)
	var parent = card.get_parent()
	if parent == _main.player_hand:
		var idx = _main.player_hand.cards.find(card)
		if idx >= 0:
			_main.player_hand.cards.remove_at(idx)
		_main.player_hand.remove_child(card)
		_main.player_hand._arrange_cards()
	elif parent:
		parent.remove_child(card)
	card.queue_free()
	cm.add_to_deck_top(owner_id, data)
	cm.shuffle_deck(owner_id)
	if _main._zone_manager:
		_main._zone_manager._update_castillo_counts()


func _bernardo_banish_target(source_card: Node) -> void:
	if not _inspector._main._card_interaction:
		return
	var filter := func(c: Node) -> bool:
		# Bernardo puede ser objetivo de su propio Destierro (a sí mismo u otra copia): el texto no lo
		# prohíbe.
		if not (c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.ARMA, Constants.CardType.TOTEM]):
			return false
		return int(c.get("card_cost")) <= 3
	var chosen: Node = await _inspector._main._card_interaction.await_target(
		"Elige una carta de coste 3 o menos para Desterrar", filter)
	if chosen and is_instance_valid(chosen) and is_instance_valid(source_card):
		await ActionModule.banish([chosen], source_card, true)


func _bernardo_cancel_ability_target(source_card: Node) -> void:
	if not _inspector._main._card_interaction:
		return
	var filter := func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO
	var chosen: Node = await _inspector._main._card_interaction.await_target(
		"Elige un Aliado que pierda su habilidad", filter)
	if chosen and is_instance_valid(chosen) and is_instance_valid(source_card):
		await KeywordManager.silence_card(chosen, source_card, "permanent")
