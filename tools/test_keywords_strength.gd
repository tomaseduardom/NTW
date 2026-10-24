extends Node
## Tests headless de palabras clave y Fuerza con cartas reales en el tablero: KeywordParser,
## KeywordConditions, KeywordAuras, StrengthAuras, KeywordManager.has_keyword() y la guarda de
## ContinuousEffectParser (arquitectura.md, "Palabras clave: KeywordParser").
## Uso:
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/test_keywords_strength.tscn
## (escena y no -s: los scripts del juego usan los autoloads, que un script -s no ve al compilar).
## Carga Main.tscn (queda en el selector de mazos, sin partida) y arma cada escenario a mano.
## Sale con código 1 si algún caso falla.

const K = preload("res://scripts/core/config/Constants.gd").Keyword
const KeywordParser = preload("res://scripts/core/cards/KeywordParser.gd")
const AllyEventTriggers = preload("res://scripts/core/effects/triggers/AllyEventTriggers.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")

var main: Node
var failed := 0
var passed := 0
var _created: Array = []


func _ready() -> void:
	main = load("res://scenes/game/Main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	for i in 60:
		await get_tree().process_frame
	if not CardDatabase.is_loaded:
		print("ERROR: CardDatabase no cargó")
		get_tree().quit(1)
		return
	ContinuousEffectManager._invalidate_cache()
	await _run()
	if "--audit" in OS.get_cmdline_user_args():
		await _audit_static_strength()
		await _audit_static_keywords()
		_audit_castle_look()
	print("KeywordsStrength: %d/%d casos OK" % [passed, passed + failed])
	get_tree().quit(1 if failed > 0 else 0)


# =============================================================================
# AYUDAS
# =============================================================================
func check(label: String, got, expected) -> void:
	if got == expected:
		passed += 1
	else:
		failed += 1
		print("FALLA: %s\n   esperado: %s\n   obtenido: %s" % [label, str(expected), str(got)])


func data(name: String, tipo: int = -1) -> Dictionary:
	for c in CardDatabase.cards.values():
		if str(c.nombre).to_lower() == name.to_lower() and (tipo < 0 or int(c.tipo) == tipo):
			return c.duplicate(true)
	print("ERROR: no está la carta '%s'" % name)
	return {}


func fake(name: String, cost: int, strength: int, text: String = "", race: String = "",
		tipo: int = Constants.CardType.ALIADO) -> Dictionary:
	return {"id": "test_" + name, "uuid": "test_" + name, "nombre": name, "tipo": tipo, "coste": cost,
		"fuerza": strength, "habilidad": text, "raza": race, "keywords": KeywordParser.own_keywords(text).duplicate()}


func zone_node(pid: int, where: String) -> Node:
	var props := {
		"def": ["player_field", "opponent_field"], "atk": ["player_linea_ataque", "opponent_linea_ataque"],
		"apoyo": ["player_linea_apoyo", "opponent_linea_apoyo"], "reserva": ["player_gold", "opponent_gold"],
		"pagado": ["player_oro_pagado", "opponent_oro_pagado"],
	}
	return main.get(props[where][pid])


func put(card_data: Dictionary, pid: int, where: String = "def") -> Node:
	var zones := {"def": Constants.Zone.LINEA_DEFENSA, "atk": Constants.Zone.LINEA_ATAQUE,
		"apoyo": Constants.Zone.LINEA_APOYO, "reserva": Constants.Zone.RESERVA_ORO, "pagado": Constants.Zone.ORO_PAGADO}
	var card: Node = main._create_card(card_data, false)
	zone_node(pid, where).add_child(card)
	card.owner_id = pid
	card.controller_id = pid
	card.set_zone(zones[where])
	ContinuousEffectManager._register_card_continuous_effects(card)
	_created.append(card)
	return card


func equip(weapon_data: Dictionary, ally: Node) -> Node:
	var weapon: Node = main._create_card(weapon_data, false)
	ally.add_child(weapon)
	weapon.owner_id = ally.owner_id
	weapon.controller_id = ally.controller_id
	weapon.set_zone(ally.current_zone)
	ally.equipped_weapons.append(weapon)
	main._gold_manager._register_weapon_strength_bonus(weapon, ally)
	_created.append(weapon)
	return weapon


func in_hand(pid: int, n: int) -> void:
	for i in n:
		var card: Node = main._create_card(fake("Mano %d" % i, 1, 1), pid != 0)
		if pid == 0:
			main.player_hand.add_card(card)
		else:
			main._opponent_fan.add_card(card)
		_created.append(card)


func strength(card: Node) -> int:
	ContinuousEffectManager._invalidate_cache()
	return ContinuousEffectManager.get_modified_strength(card)


func has(card: Node, kw: int) -> bool:
	return KeywordManager.has_keyword(card, kw)


func reset() -> void:
	for c in _created:
		if is_instance_valid(c):
			if c.get_parent():
				c.get_parent().remove_child(c)
			c.free()
	_created.clear()
	for h in [main.player_hand, main._opponent_fan]:
		if h.has_method("clear_hand"):
			h.clear_hand()
	for pid in [0, 1]:
		CardManager.get_cemetery(pid).clear()
		CardManager.get_exile(pid).clear()
		CardManager.get_deck(pid).clear()
	KeywordManager._temporary_keywords.clear()
	KeywordManager._removed_keywords.clear()
	KeywordManager._silenced_cards.clear()
	KeywordManager._instance_ability_locks.clear()
	BattleManager.attacked_on_turn.clear()
	GameManager.turn_serial = 10
	GameManager.active_player_id = 0
	ContinuousEffectManager._invalidate_cache()


# =============================================================================
# CASOS
# =============================================================================
func _run() -> void:
	_parser_cases()
	for test in [_printed_and_weapons, _conditional_keywords, _silence, _removal_auras, _strength_auras,
			_parser_guard, _exhumar, _mass_buff, _event_triggers, _real_equip, _combat_rules, _santos, _keyword_grants, _per_each, _badge_refresh, _if_annulled, _turn_end, _no_shuffle,
			_castle_locks, _hand_lock, _affect_tax, _crono_diamante, _compiled_choices, _batch5, _sandraudiga, _cuervo_nocturno, _amazona_fase_final, _iga_ryu, _estacion_fantasma, _corte_letal, _camilo_castle_look, _activated_costs, _compiled_prevention]:
		reset()
		await test.call()
	reset()


func _parser_cases() -> void:
	check("Furia impresa", KeywordParser.own_keywords("Furia. Cuando entra en juego, Roba una carta."), [K.FURIA])
	check("Tus Aliados ganan Furia no es propia", KeywordParser.own_keywords("Tus Aliados ganan Furia."), [])
	check("cita no es propia", KeywordParser.own_keywords("Convierte una carta en un Aliado con la habilidad \"Furia\"."), [])
	check("Arma: el portador gana", KeywordParser.wielder_keywords("El portador gana 1 de Fuerza e Imbloqueable."), [K.IMBLOQUEABLE])
	check("Arma: Exhumar no pasa al portador", KeywordParser.wielder_keywords("Exhumar. El portador gana 2 de Fuerza y Furia."), [K.FURIA])
	check("Arma: no es Indesterrable ella", KeywordParser.own_keywords(data("Lanza Argenta").habilidad).has(K.INDESTERRABLE), false)
	check("Guadaña: sin Furia falsa", KeywordParser.wielder_keywords(data("Guadaña de Santa Muerte").habilidad), [K.INDESTRUCTIBLE])
	check("a traves del espejo: sin condicional falsa", KeywordParser.conditional_keywords(data("a traves del espejo").habilidad), [])


func _printed_and_weapons() -> void:
	var ally := put(fake("Aliado", 2, 2), 0)
	check("sin Arma: sin Imbloqueable", has(ally, K.IMBLOQUEABLE), false)
	var espada := equip(data("Espada del Juicio"), ally)
	check("Espada del Juicio: Imbloqueable al portador", has(ally, K.IMBLOQUEABLE), true)
	check("Espada del Juicio: el Arma no es Imbloqueable", has(espada, K.IMBLOQUEABLE), false)
	check("Card.has_keyword delega", ally.has_keyword(K.IMBLOQUEABLE), true)
	var lanza_ally := put(fake("Portador", 2, 2), 0)
	var lanza := equip(data("Lanza Argenta"), lanza_ally)
	check("Lanza Argenta: portador Indesterrable", has(lanza_ally, K.INDESTERRABLE), true)
	check("Lanza Argenta: el Arma no es Indesterrable", has(lanza, K.INDESTERRABLE), false)
	await KeywordManager.silence_card(espada, null, "turn", true)
	check("Arma sin habilidad no da Imbloqueable", has(ally, K.IMBLOQUEABLE), false)


func _conditional_keywords() -> void:
	var honda := put(data("honda tadakatsu"), 0)
	var base_honda := strength(honda)
	check("honda tadakatsu sin Arma: sin Furia", has(honda, K.FURIA), false)
	equip(fake("Palo", 0, 0, "", "", Constants.CardType.ARMA), honda)
	check("honda tadakatsu con Arma: Furia", has(honda, K.FURIA), true)
	check("honda tadakatsu con Arma: +1 de Fuerza", strength(honda) - base_honda, 1)

	var hanzaki := put(data("hanzaki"), 0)
	var base_hanzaki := strength(hanzaki)
	check("hanzaki con 2 Aliados: sin Furia", has(hanzaki, K.FURIA), false)
	put(fake("Extra", 1, 1), 0)
	check("hanzaki con 3 Aliados en juego: Furia", has(hanzaki, K.FURIA), true)
	for i in 3:
		CardManager.get_exile(0).append(fake("Desterrado %d" % i, 1, 1))
		CardManager.get_cemetery(0).append(fake("Muerto %d" % i, 1, 1))
	check("hanzaki con 3 Aliados en el Destierro: Imbloqueable", has(hanzaki, K.IMBLOQUEABLE), true)
	check("hanzaki con 3 Aliados en el Cementerio: +2", strength(hanzaki) - base_hanzaki, 2)

	reset()
	var alicanto := put(data("alicanto", Constants.CardType.ALIADO), 0)
	in_hand(0, 2)
	in_hand(1, 1)
	check("alicanto con más cartas en la mano: sin Furia", has(alicanto, K.FURIA), false)
	in_hand(1, 3)
	check("alicanto con menos cartas en la mano: Furia e Indesterrable",
		[has(alicanto, K.FURIA), has(alicanto, K.INDESTERRABLE)], [true, true])

	reset()
	var bestia := put(fake("Bestia", 2, 2, "", "Bestia"), 0)
	var otro := put(fake("Humano", 2, 2, "", "Héroe"), 0)
	equip(data("kanabo bestial"), bestia)
	equip(data("kanabo bestial"), otro)
	check("kanabo bestial en una Bestia: Furia y +2", [has(bestia, K.FURIA), strength(bestia)], [true, 4])
	check("kanabo bestial en un Héroe: nada", [has(otro, K.FURIA), strength(otro)], [false, 2])
	var angel := put(fake("Angel", 2, 2, "", "Ángel"), 0)
	var no_angel := put(fake("Mortal", 2, 2, "", "Héroe"), 0)
	equip(data("Alas de Ángel"), angel)
	equip(data("Alas de Ángel"), no_angel)
	check("Alas de Ángel en un Ángel", [has(angel, K.IMBLOQUEABLE), has(angel, K.INDESTRUCTIBLE)], [true, true])
	check("Alas de Ángel en otro", [has(no_angel, K.IMBLOQUEABLE), has(no_angel, K.INDESTRUCTIBLE)], [true, false])

	var senalados := put(data("Los Señalados"), 0)
	senalados.set_meta("entered_play_turn", GameManager.turn_serial)
	check("Los Señalados el turno que entra: Imbloqueable", has(senalados, K.IMBLOQUEABLE), true)
	senalados.set_meta("entered_play_turn", GameManager.turn_serial - 2)
	check("Los Señalados después: sin Imbloqueable", has(senalados, K.IMBLOQUEABLE), false)


func _silence() -> void:
	var furia := put(fake("Con Furia", 2, 2, "Furia."), 0)
	check("Furia impresa", has(furia, K.FURIA), true)
	var source := put(fake("Fuente", 2, 2), 1)
	KeywordManager.lock_ability_by_instance(furia, source)
	check("bloqueada por instancia: pierde Furia impresa", has(furia, K.FURIA), false)
	KeywordManager.grant_keyword(furia, K.FURIA, source, "turn")
	check("una Furia otorgada después sí vale", has(furia, K.FURIA), true)


func _removal_auras() -> void:
	var low := put(fake("Coste 1", 1, 2, "Furia."), 1)
	var high := put(fake("Coste 3", 3, 2, "Furia."), 1)
	put(data("kuzuryu"), 0)
	check("kuzuryu: coste 1 pierde Furia", has(low, K.FURIA), false)
	check("kuzuryu: coste 3 la conserva", has(high, K.FURIA), true)

	reset()
	var own := put(fake("Propio", 2, 2, "Indestructible."), 0)
	var rival := put(fake("Rival", 2, 2, "Indestructible."), 1)
	put(data("Ianthe"), 0)
	check("Ianthe: el rival pierde Indestructible", has(rival, K.INDESTRUCTIBLE), false)
	check("Ianthe: el propio lo conserva", has(own, K.INDESTRUCTIBLE), true)

	reset()
	var atacante := put(fake("Imbloqueable", 2, 2, "Imbloqueable."), 1)
	check("sin Diadema: Imbloqueable", KeywordManager.can_be_blocked(atacante), false)
	var diadema := put(data("Diadema Celestial"), 0, "reserva")
	check("Diadema en la Reserva: se puede bloquear", KeywordManager.can_be_blocked(atacante), true)
	await KeywordManager.silence_card(diadema, null, "turn", true)
	check("Diadema sin habilidad: no se puede bloquear", KeywordManager.can_be_blocked(atacante), false)

	reset()
	var chico := put(fake("Chico", 1, 2, "Furia."), 1)
	put(data("cuernos del inmortal"), 0, "pagado")
	check("cuernos en el Oro Pagado: no aplica", has(chico, K.FURIA), true)
	put(data("cuernos del inmortal"), 0, "reserva")
	check("cuernos en la Reserva: pierde Furia", has(chico, K.FURIA), false)

	reset()
	var chico2 := put(fake("Chico", 1, 2, "Furia."), 1)
	CardManager.get_exile(0).append(data("red shadow"))
	check("red shadow en el Destierro: pierde Furia", has(chico2, K.FURIA), false)

	reset()
	var indes := put(fake("Indestructible", 2, 2, "Indestructible."), 1)
	put(data("dotaku"), 0, "reserva")
	put(fake("Oro rival", 0, 0, "", "", Constants.CardType.ORO), 1, "reserva")  # 1 Oro cada uno
	check("dotaku sin más Oros: el rival pierde Indestructible", has(indes, K.INDESTRUCTIBLE), false)
	put(fake("Oro A", 0, 0, "", "", Constants.CardType.ORO), 0, "reserva")
	check("dotaku con más Oros: lo conserva", has(indes, K.INDESTRUCTIBLE), true)


func _strength_auras() -> void:
	var c1 := put(fake("Coste 1", 1, 3), 1)
	var c3 := put(fake("Coste 3", 3, 3), 1)
	put(data("ahu tongariki"), 0)
	check("ahu tongariki: -1 a coste 1", strength(c1), 2)
	check("ahu tongariki: coste 3 igual", strength(c3), 3)

	reset()
	var r := put(fake("Rival", 2, 4), 1)
	put(data("zorya"), 0)
	check("zorya con 1 Aliado: sin -2", strength(r), 4)
	put(fake("A", 1, 1), 0)
	put(fake("B", 1, 1), 0)
	check("zorya con 3 Aliados: -2", strength(r), 2)

	reset()
	var mio := put(fake("Mío", 2, 2), 0)
	var suyo := put(fake("Suyo", 2, 2), 1)
	put(data("dotaku"), 0, "reserva")
	put(fake("Oro rival", 0, 0, "", "", Constants.CardType.ORO), 1, "reserva")  # 1 Oro cada uno
	check("dotaku sin más Oros: rival -1, propio igual", [strength(suyo), strength(mio)], [1, 2])
	put(fake("Oro A", 0, 0, "", "", Constants.CardType.ORO), 0, "reserva")
	check("dotaku con más Oros: propio +1, rival igual", [strength(mio), strength(suyo)], [3, 2])

	reset()
	var aliado := put(fake("Aliado", 2, 2), 0)
	put(data("Legión de Honor"), 0, "pagado")
	check("Legión de Honor en el Oro Pagado: +0", strength(aliado), 2)
	put(data("Legión de Honor"), 0, "reserva")
	check("Legión de Honor en la Reserva: +1", strength(aliado), 3)

	reset()
	var con_furia := put(fake("Con Furia", 1, 3, "Furia."), 1)
	var sin_furia := put(fake("Sin Furia", 1, 3), 1)
	CardManager.get_cemetery(0).append(data("Gusano Vampiro"))
	check("Gusano Vampiro: -1 al de coste 1 con Furia", [strength(con_furia), strength(sin_furia)], [2, 3])

	reset()
	var rysei := put(data("rysei"), 0)
	var furioso := put(fake("Furioso", 2, 2, "Furia."), 0)
	var calmo := put(fake("Calmo", 2, 2), 0)
	var base_rysei := int(rysei.card_data.fuerza)
	check("rysei: +1 a tus demás Aliados con Furia", [strength(furioso), strength(calmo), strength(rysei)],
		[3, 2, base_rysei])

	reset()
	var ally := put(fake("Aliado", 2, 2), 0)
	var odachi_ally := put(fake("Sacerdote", 2, 2, "", "Sacerdote"), 0)
	equip(data("odachi"), odachi_ally)
	equip(data("odachi"), ally)
	check("odachi en un Sacerdote: +2 e Indestructible", [strength(odachi_ally), has(odachi_ally, K.INDESTRUCTIBLE)], [4, true])
	check("odachi en otro: nada", [strength(ally), has(ally, K.INDESTRUCTIBLE)], [2, false])


func _parser_guard() -> void:
	var aliado := put(fake("Aliado", 2, 2), 0)
	put(data("Kuchiku Kan"), 0)
	check("Kuchiku Kan: su disparo no es un aura +1", strength(aliado), 2)
	put(data("troll soberano"), 1)
	check("troll soberano: su disparo no es un aura -1", strength(aliado), 2)
	var rival := put(fake("Rival", 2, 4), 1)
	put(data("amazona desafiante"), 0)
	check("amazona desafiante (aura fija) sigue: -2", strength(rival), 2)


func _exhumar() -> void:
	var cuervo := data("Cuervo Nocturno")
	CardManager.get_cemetery(0).append(cuervo)
	check("Cuervo Nocturno sin atacar: sin Exhumar", PaymentManager.card_has_exhumar(cuervo, 0), false)
	BattleManager.attacked_on_turn[0] = GameManager.turn_serial - 2
	check("Cuervo Nocturno tras atacar: Exhumar", PaymentManager.card_has_exhumar(cuervo, 0), true)
	var macu := data("macu")
	CardManager.get_cemetery(0).append(macu)
	check("macu sin Caballero: sin Exhumar", PaymentManager.card_has_exhumar(macu, 0), false)
	put(fake("Caballero", 2, 2, "", "Caballero"), 0)
	check("macu con Caballero: Exhumar", PaymentManager.card_has_exhumar(macu, 0), true)
	var expulsar := data("Expulsar el Mal")
	check("Expulsar el Mal no tiene Exhumar", PaymentManager.card_has_exhumar(expulsar, 0), false)


func _mass_buff() -> void:
	var ogun := put(data("ogun"), 0)
	var a := put(fake("A", 2, 2), 0)
	var rival := put(fake("Rival", 2, 2), 1)
	await AllyEventTriggers._mass_buff(ogun, 0, "own", 1)
	check("mass_buff propio: +1 permanente", [strength(a), strength(rival)], [3, 2])
	var troll := put(data("troll soberano"), 0)
	await AllyEventTriggers._mass_buff(troll, 0, "opponent", 1)
	check("mass_buff al rival: -1", strength(rival), 1)
	var nuevo := put(fake("Nuevo", 2, 2), 0)
	check("mass_buff no sigue a los que entran después", strength(nuevo), 2)


func _event_triggers() -> void:
	# Camino real: Ventana de Respuesta contra el bot (jugador 1) y "una vez por turno".
	GameManager.is_game_active = true
	var troll := put(data("troll soberano"), 0)
	var rival := put(fake("Rival", 2, 3), 1)
	var jugado := put(fake("Jugado", 1, 1), 0)
	await AllyEventTriggers.on_card_played(jugado, 0)
	check("troll soberano al jugar un Aliado: rival -1", strength(rival), 2)
	await AllyEventTriggers.on_card_played(jugado, 0)
	check("troll soberano: una vez por turno", strength(rival), 2)
	var ogun := put(data("ogun"), 0)
	var mio := put(fake("Mío", 2, 2), 0)
	await AllyEventTriggers.on_card_entered(0, mio)
	check("ogun al entrar un Aliado propio: +1", strength(mio), 3)
	var rival_entra := put(fake("Rival entra", 2, 2), 1)
	await AllyEventTriggers.on_card_entered(1, rival_entra)
	check("ogun no reacciona a un Aliado rival", strength(mio), 3)
	check("ogun también sube a troll y a sí mismo (Aliados propios)", [strength(troll), strength(ogun)],
		[int(troll.card_data.fuerza) + 1, int(ogun.card_data.fuerza) + 1])
	GameManager.is_game_active = false


func _alive(card: Node) -> bool:
	return is_instance_valid(card) and card.is_in_play()


func _real_equip() -> void:
	# Equipar por el flujo real de jugar el Arma (GoldManager._equip_weapon, con su Ventana de Respuesta).
	GameManager.is_game_active = true
	var ally := put(fake("Portador", 2, 2), 0)
	var weapon: Node = main._create_card(data("Lanza de Exorcista"), false)
	weapon.owner_id = 0
	weapon.controller_id = 0
	main.player_hand.add_card(weapon)
	_created.append(weapon)
	await main._gold_manager._equip_weapon(weapon, ally)
	check("equipada de verdad: el Arma porta en el Aliado", ally.equipped_weapons.has(weapon), true)
	check("Lanza de Exorcista: +3, Furia e Imbloqueable",
		[strength(ally), has(ally, K.FURIA), has(ally, K.IMBLOQUEABLE)], [5, true, true])
	check("Lanza de Exorcista: el Arma no tiene Exhumar en juego como portador", has(ally, K.EXHUMAR), false)
	GameManager.is_game_active = false


func _combat_rules() -> void:
	var lento := put(fake("Lento", 1, 2, "Furia."), 1)
	check("Furia: puede atacar el turno que entra", KeywordManager.can_attack_immediately(lento), true)
	put(data("kuzuryu"), 0)
	check("con kuzuryu: ya no puede atacar el turno que entra", KeywordManager.can_attack_immediately(lento), false)

	reset()
	var duro := put(fake("Duro", 2, 2, "Indestructible."), 1)
	var r1: Dictionary = await ActionModule.destroy([duro], null)
	check("Indestructible: sobrevive a Destruir", r1.get("destroyed", []).has(duro), false)
	put(data("Ianthe"), 0)
	var r2: Dictionary = await ActionModule.destroy([duro], null)
	check("con Ianthe: se Destruye", r2.get("destroyed", []).has(duro), true)

	reset()
	var fijo := put(fake("Fijo", 2, 2, "Indesterrable."), 1)
	var r3: Dictionary = await ActionModule.banish([fijo], null)
	check("Indesterrable: no se Destierra", r3.get("banished", []).has(fijo), false)
	put(data("Lucy Westenra"), 0)
	var r4: Dictionary = await ActionModule.banish([fijo], null)
	check("con Lucy Westenra: se Destierra", r4.get("banished", []).has(fijo), true)


func _santos() -> void:
	var santos := put(data("santos pincheira"), 0)
	var mio := put(fake("Mío", 2, 2), 0)
	var rival := put(fake("Rival", 2, 2), 1)
	await AllyEventTriggers.on_stopped(santos, 0)
	check("santos pincheira anulado: tus Aliados +2", [strength(mio), strength(rival)], [4, 2])
	var otro := put(fake("Otro", 2, 2), 0)
	await AllyEventTriggers.on_stopped(otro, 0)
	check("otra carta anulada no dispara nada", strength(mio), 4)



func _keyword_grants() -> void:
	var mio := put(fake("Mío", 2, 2), 0)
	var suyo := put(fake("Suyo", 2, 2), 1)
	put(data("los gracones"), 0)
	check("los gracones: tus Aliados Furia, el rival no", [has(mio, K.FURIA), has(suyo, K.FURIA)], [true, false])

	reset()
	var dragon := put(fake("Dragón", 2, 2, "", "Dragón"), 0)
	var bestia := put(fake("Bestia", 2, 2, "", "Bestia"), 0)
	put(data("daikaiju"), 0)
	check("daikaiju: solo los Dragón", [has(dragon, K.FURIA), has(bestia, K.FURIA)], [true, false])

	reset()
	var imb := put(fake("Imbloqueable", 2, 2, "Imbloqueable."), 0)
	var comun := put(fake("Común", 2, 2), 0)
	put(data("okyo"), 0)
	check("okyo: Indestructible solo a los Imbloqueable", [has(imb, K.INDESTRUCTIBLE), has(comun, K.INDESTRUCTIBLE)], [true, false])

	reset()
	var armado := put(fake("Armado", 2, 2), 0)
	var desarmado := put(fake("Desarmado", 2, 2), 0)
	equip(fake("Palo", 0, 0, "", "", Constants.CardType.ARMA), armado)
	put(data("fuerte de niebla"), 0)
	check("fuerte de niebla: Furia a los que portan Armas", [has(armado, K.FURIA), has(desarmado, K.FURIA)], [true, false])

	reset()
	var aliado := put(fake("Aliado", 2, 2), 0)
	var capricornio := put(data("capricornio"), 0)
	check("capricornio sin Arma: nada", has(aliado, K.INDESTRUCTIBLE), false)
	equip(fake("Palo", 0, 0, "", "", Constants.CardType.ARMA), capricornio)
	check("capricornio con Arma: tus Aliados Indestructibles", has(aliado, K.INDESTRUCTIBLE), true)

	reset()
	var a2 := put(fake("Aliado", 2, 2), 0)
	put(data("el mundo"), 0, "reserva")
	for i in 5:
		put(fake("Oro %d" % i, 0, 0, "", "", Constants.CardType.ORO), 0, "reserva")
	check("el mundo con 6 Oros: nada", [has(a2, K.FURIA), strength(a2)], [false, 2])
	put(fake("Oro 7", 0, 0, "", "", Constants.CardType.ORO), 0, "pagado")
	check("el mundo con 7 Oros: +4, Furia e Imbloqueable", [strength(a2), has(a2, K.FURIA), has(a2, K.IMBLOQUEABLE)], [6, true, true])

	reset()
	var a3 := put(fake("Aliado", 2, 2), 0)
	put(data("Libro de Enoc"), 0, "reserva")
	check("Libro de Enoc en la Reserva: nada", has(a3, K.INDESTRUCTIBLE), false)
	put(data("Libro de Enoc"), 0, "pagado")
	check("Libro de Enoc en el Oro Pagado: +1 e Indestructible", [strength(a3), has(a3, K.INDESTRUCTIBLE)], [3, true])

	reset()
	var a4 := put(fake("Aliado", 2, 2), 0)
	put(data("mug ruith"), 0)
	for i in 9:
		CardManager.get_exile(1).append(fake("D%d" % i, 1, 1))
	check("mug ruith con 9 en los Destierros: nada", has(a4, K.IMBLOQUEABLE), false)
	CardManager.get_exile(0).append(fake("D10", 1, 1))
	check("mug ruith con 10: +2 e Imbloqueable", [has(a4, K.IMBLOQUEABLE), strength(a4)], [true, 4])

	reset()
	var a5 := put(fake("Aliado", 2, 2), 0)
	put(data("empanada"), 0)
	check("empanada sin Pebre: nada", [has(a5, K.IMBLOQUEABLE), strength(a5)], [false, 2])
	put(fake("pebre", 1, 1), 0)
	check("empanada con Pebre: +1 e Imbloqueable", [has(a5, K.IMBLOQUEABLE), strength(a5)], [true, 3])

	reset()
	var a6 := put(fake("Aliado", 2, 2), 0)
	var escuadron := put(data("Escuadrón Ángel"), 0)
	check("Escuadrón Ángel: los demás sí, él no", [has(a6, K.INDESTRUCTIBLE), has(escuadron, K.INDESTRUCTIBLE)], [true, false])

	reset()
	var exh := put(fake("Con Exhumar", 2, 2, "Exhumar."), 0)
	var sin := put(fake("Sin Exhumar", 2, 2), 0)
	put(data("Cementerio General"), 0)
	check("Cementerio General: Furia a los que tienen Exhumar", [has(exh, K.FURIA), has(sin, K.FURIA)], [true, false])

	reset()
	var a7 := put(fake("Aliado", 2, 2), 0)
	var fuente := put(data("los gracones"), 0)
	await KeywordManager.silence_card(fuente, null, "turn", true)
	check("aura de una carta sin habilidad: no da nada", has(a7, K.FURIA), false)


func _totem(pid: int) -> Node:
	return put(fake("Tótem", 1, 0, "", "", Constants.CardType.TOTEM), pid, "apoyo")


func _per_each() -> void:
	var rival := put(fake("Rival", 2, 5), 1)
	put(data("rogue mecha"), 0)
	check("rogue mecha sin Tótem: nada", strength(rival), 5)
	_totem(0)
	_totem(0)
	check("rogue mecha con 2 Tótem: -2", strength(rival), 3)

	reset()
	var r2 := put(fake("Rival", 2, 5), 1)
	put(data("felicia"), 0)
	CardManager.get_exile(0).append(fake("Aliado D", 1, 1))
	CardManager.get_exile(0).append(fake("Oro D", 0, 0, "", "", Constants.CardType.ORO))
	CardManager.get_exile(0).append(fake("Otro Aliado D", 1, 1))
	check("felicia con 2 tipos en tu Destierro: -2", strength(r2), 3)

	reset()
	var r3 := put(fake("Rival", 2, 5), 1)
	put(data("sargento orok"), 0)
	_totem(0)
	_totem(0)
	CardManager.get_exile(0).append(fake("Tal", 1, 0, "", "", Constants.CardType.TALISMAN))
	check("sargento orok: -1 por Tótem, +1 por Talismán en tu Destierro", strength(r3), 4)

	reset()
	var mio := put(fake("Mío", 2, 2), 0)
	var suyo := put(fake("Suyo", 2, 5), 1)
	put(data("siete enanos"), 0)
	check("siete enanos con 1 de coste 2 (él no cuenta si no es 2)", [strength(mio), strength(suyo)],
		[2 + 1 * (1 + int(int(data("siete enanos").coste) == 2)), 5 - 1 * (1 + int(int(data("siete enanos").coste) == 2))])
	put(fake("Otro 2", 2, 1), 0)
	check("siete enanos con un Aliado de coste 2 más: un punto más", strength(suyo),
		5 - (2 + int(int(data("siete enanos").coste) == 2)))

	reset()
	var a := put(fake("A", 2, 4), 0)
	put(fake("B", 2, 4), 0)
	var solo := put(fake("Solo", 2, 4), 1)
	put(data("campus de muerte"), 1, "apoyo")
	var campus_ally := int(data("campus de muerte").tipo) == Constants.CardType.ALIADO
	check("campus de muerte: -1 por cada otro Aliado de su controlador", [strength(a), strength(solo)],
		[4 - (1 + 0), 4 - (1 if campus_ally else 0)])

	reset()
	var aliado := put(fake("Aliado", 2, 2), 0)
	put(data("doctora kan"), 0)
	CardManager.get_exile(0).append(fake("X", 1, 1))
	CardManager.get_exile(0).append(fake("Y", 0, 0, "", "", Constants.CardType.ORO))
	check("doctora kan: +1 por tipo en tu Destierro", strength(aliado), 4)

	reset()
	var r4 := put(fake("Rival", 2, 5), 1)
	var mio2 := put(fake("Mío", 2, 2), 0)
	put(data("las aventuras de sherlock holmes"), 0, "reserva")
	put(data("las aventuras de sherlock holmes"), 0, "reserva")
	check("sherlock: -1 por cada copia en tu Reserva (2 copias, 2 fuentes)", strength(r4), 1)
	check("sherlock en la Reserva: el +1 del Oro Pagado no aplica", strength(mio2), 2)

	reset()
	var r5 := put(fake("Coste 1", 1, 2), 0)
	put(fake("Coste 3", 3, 2), 0)
	put(data("reni"), 0, "apoyo")  # Tótem: no cuenta como Aliado
	check("reni: +1 por cada coste distinto de tus Aliados (1 y 3)", strength(r5), 4)


func _badge_refresh() -> void:
	var hanzaki := put(data("hanzaki"), 0)
	for i in 3:
		CardManager._append_to_cemetery(0, fake("Muerto %d" % i, 1, 1))
	for i in 3:
		await get_tree().process_frame
	check("el contador de Fuerza se refresca solo al cambiar el Cementerio",
		[hanzaki._badges.strength_badge.visible, str(hanzaki._badges._strength_plaque_lbl.text)], [true, "+2"])


# =============================================================================
# AUDITORÍA (--audit): toda aura estática simple de Fuerza, medida contra su texto
# =============================================================================
func _audit_static_strength() -> void:
	var rx := RegEx.create_from_string("^(tus|los) (demás )?aliados( oponentes)?( en juego)?( que control(?:as|es))? (ganan|pierden) (\\d+) de fuerza$")
	var seen := {}
	var bad := 0
	var total := 0
	for c in CardDatabase.cards.values():
		var tipo := int(c.tipo)
		if tipo == Constants.CardType.TALISMAN or seen.has(str(c.nombre).to_lower()):
			continue
		for sentence in KeywordParser.sentences(str(c.habilidad)):
			var m := rx.search(sentence)
			if not m:
				continue
			seen[str(c.nombre).to_lower()] = true
			reset()
			var where := "reserva" if tipo == Constants.CardType.ORO else ("apoyo" if tipo != Constants.CardType.ALIADO else "def")
			var src := put(c.duplicate(true), 0, where)
			var own := put(fake("Propio", 2, 5), 0)
			var rival := put(fake("Rival", 2, 5), 1)
			var n := int(m.get_string(7)) * (-1 if m.get_string(6) == "pierden" else 1)
			var opp := m.get_string(3) != ""
			var mine := m.get_string(1) == "tus" or m.get_string(5) != ""
			var exp_own := 5 if opp else 5 + n
			var exp_rival := 5 + n if (opp or not mine) else 5
			var exp_self := int(c.fuerza) + (n if (tipo == Constants.CardType.ALIADO and not opp and m.get_string(2) == "") else 0)
			var got := [strength(own), strength(rival)]
			var want := [max(0, exp_own), max(0, exp_rival)]
			if tipo == Constants.CardType.ALIADO:
				got.append(strength(src))
				want.append(max(0, exp_self))
			total += 1
			if got != want:
				bad += 1
				print("AUDIT|%s|%s|esperado %s|obtenido %s" % [c.nombre, sentence, str(want), str(got)])
			break
	reset()
	print("AUDIT: %d/%d auras estáticas simples de Fuerza correctas" % [total - bad, total])



func _audit_static_keywords() -> void:
	var kw := "(?:furia|imbloqueables?|indestructibles?|indesterrables?)"
	var rx := RegEx.create_from_string("^(tus|los) (demás )?aliados( oponentes)?( en juego)?( que control(?:as|es))? "
		+ "(ganan|tienen|son|pierden) (" + kw + "(?:(?:, | y | e )" + kw + ")*)$")
	var words := RegEx.create_from_string(kw)
	var seen := {}
	var bad := 0
	var total := 0
	for c in CardDatabase.cards.values():
		var tipo := int(c.tipo)
		if tipo == Constants.CardType.TALISMAN or seen.has(str(c.nombre).to_lower()):
			continue
		for sentence in KeywordParser.sentences(str(c.habilidad)):
			var m := rx.search(sentence)
			if not m:
				continue
			seen[str(c.nombre).to_lower()] = true
			var loses := m.get_string(6) == "pierden"
			var opp := m.get_string(3) != ""
			var mine := m.get_string(1) == "tus" or m.get_string(5) != ""
			for wm in words.search_all(m.get_string(7)):
				var k := KeywordParser.keyword_of(wm.get_string().trim_suffix("s") if wm.get_string() != "furia" else "furia")
				reset()
				var where := "reserva" if tipo == Constants.CardType.ORO else ("apoyo" if tipo != Constants.CardType.ALIADO else "def")
				put(c.duplicate(true), 0, where)
				var printed: String = (str(Constants.Keyword.keys()[k]).capitalize() + ".") if loses else ""
				var own := put(fake("Propio", 2, 2, printed), 0)
				var rival := put(fake("Rival", 2, 2, printed), 1)
				var affects_own := not opp
				var affects_rival := opp or not mine
				var want := [(not affects_own) if loses else affects_own, (not affects_rival) if loses else affects_rival]
				var got := [has(own, k), has(rival, k)]
				total += 1
				if got != want:
					bad += 1
					print("AUDIT-KW|%s|%s|%s|esperado %s|obtenido %s" % [c.nombre, sentence, Constants.Keyword.keys()[k], str(want), str(got)])
			break
	reset()
	print("AUDIT-KW: %d/%d auras estáticas simples de palabras clave correctas" % [total - bad, total])



func _talisman_node(name: String, pid: int) -> Node:
	var t: Node = main._create_card(data(name), false)
	t.owner_id = pid
	t.controller_id = pid
	zone_node(pid, "apoyo").add_child(t)
	_created.append(t)
	return t


func _if_annulled() -> void:
	GameManager.is_game_active = true
	var gm: Node = main._gold_manager
	gm.limpiar_oros_virtuales()
	var acabar := _talisman_node("Acabar La Esperanza", 0)
	await AllyEventTriggers.on_stopped(acabar, 0, "Talismán")
	check("Acabar la Esperanza anulado: genera un Oro", int(gm.oros_virtuales.get(0, 0)), 1)
	await AllyEventTriggers.on_stopped(acabar, 0, "disparada")
	check("cancelar una habilidad no cuenta como Anular", int(gm.oros_virtuales.get(0, 0)), 1)

	var rancagua := _talisman_node("batalla de rancagua", 0)
	var pools_before: int = gm.restricted_gold_pools.get(0, []).size()
	await AllyEventTriggers.on_stopped(rancagua, 0, "Talismán")
	var pools: Array = gm.restricted_gold_pools.get(0, [])
	check("batalla de rancagua: Oro solo para Aliados", [pools.size() - pools_before,
		pools[-1].predicate.call(Constants.CardType.ALIADO, "", 1), pools[-1].predicate.call(Constants.CardType.ARMA, "", 1)],
		[1, true, false])

	var oro := put(fake("Oro pagado", 0, 0, "", "", Constants.CardType.ORO), 0, "pagado")
	var ensamble := _talisman_node("ensamble", 0)
	await AllyEventTriggers.on_stopped(ensamble, 0, "Talismán")
	check("ensamble anulado: agrupa el Oro (a la Reserva)", oro.get_parent() == zone_node(0, "reserva"), true)

	CardManager.get_deck(1).append(fake("Oro liso", 0, 0, "", "", Constants.CardType.ORO))
	CardManager.get_deck(1).append(fake("Oro con texto", 0, 0, "Oro Inicial.", "", Constants.CardType.ORO))
	var titan := _talisman_node("fuerza de titan", 1)
	var pagado_before: int = zone_node(1, "pagado").get_child_count()
	await AllyEventTriggers.on_stopped(titan, 1, "Talismán")
	for i in 5:
		await get_tree().process_frame
	var names: Array = zone_node(1, "pagado").get_children().map(func(c): return str(c.card_name))
	check("fuerza de titan (bot): un Oro sin habilidad del Castillo al Oro Pagado",
		[zone_node(1, "pagado").get_child_count() - pagado_before, "Oro liso" in names], [1, true])

	var asalto := _talisman_node("asalto estelar", 0)
	await AllyEventTriggers.on_stopped(asalto, 0, "Talismán")
	check("asalto estelar: queda marcado para volverse Oro", asalto.get_meta("annul_to_pagado_gold", false), true)
	GameManager.is_game_active = false



func _audit_castle_look() -> void:
	var CastleLook = load("res://scripts/core/effects/CastleLook.gd")
	var seen := {}
	var ok := 0
	var total := 0
	for c in CardDatabase.cards.values():
		for raw in str(c.habilidad).split("\n"):
			for sentence in raw.split(". "):
				var low: String = sentence.to_lower()
				if not ("mira" in low and "castillo" in low) or seen.has(low):
					continue
				seen[low] = true
				total += 1
				if CastleLook.try_execute_text(null, sentence, 0, true):
					ok += 1
				else:
					print("AUDIT-LOOK|%s|%s" % [c.nombre, sentence])
	print("AUDIT-LOOK: %d/%d oraciones de mirar el Castillo las entiende CastleLook" % [ok, total])



func _turn_end() -> void:
	# "Cuando entra en juego o en tu Fase Final, ..." (amazona desafiante) también en la Fase Final.
	GameManager.is_game_active = true
	put(data("amazona desafiante"), 1)
	for i in 4:
		CardManager.get_cemetery(1).append(fake("Muerto %d" % i, 1, 1))
	await TriggerSystem.resolve_turn_end_triggers(1)
	for i in 10:
		await get_tree().process_frame
	check("amazona desafiante en su Fase Final: baraja cartas de los Cementerios", CardManager.get_cemetery(1).size() < 4, true)
	GameManager.is_game_active = false



func _no_shuffle() -> void:
	var Rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var ianthe := put(data("Ianthe"), 1)
	var comun := put(fake("Común", 2, 2), 1)
	var portador := put(fake("Portador", 2, 2), 1)
	equip(data("Garras de Dragón"), portador)
	var guerrero := put(fake("Guerrero", 2, 2, "", "Guerrero"), 1)
	var bestia := put(fake("Bestia", 2, 2, "", "Bestia"), 1)
	equip(data("nodachi"), guerrero)
	equip(data("nodachi"), bestia)
	check("no puede ser Barajado: Ianthe, Garras de Dragón y nodachi en un Guerrero",
		[Rules.cannot_be_shuffled(ianthe), Rules.cannot_be_shuffled(comun), Rules.cannot_be_shuffled(portador),
			Rules.cannot_be_shuffled(guerrero), Rules.cannot_be_shuffled(bestia)], [true, false, true, true, false])
	var deck_before := CardManager.get_deck(1).size()
	await ActionModule.return_to_deck(ianthe, 1, true, null)
	check("Barajar a Ianthe no la saca del juego", [ianthe.is_in_play(), CardManager.get_deck(1).size()], [true, deck_before])
	check("nodachi en un Guerrero: también +2", strength(guerrero), 4)


func _fill_deck(pid: int, n: int) -> void:
	# Robar lee Main.player_deck/opponent_deck: en la escena de test no siempre es el mismo Array.
	var main_deck: Array = main.player_deck if pid == 0 else main.opponent_deck
	for i in n:
		var d := fake("Mazo %d-%d" % [pid, i], 1, 1)
		CardManager.get_deck(pid).append(d)
		if not is_same(main_deck, CardManager.get_deck(pid)):
			main_deck.append(d)


func _castle_locks() -> void:
	var Rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	_fill_deck(0, 6)
	_fill_deck(1, 6)
	var portador := put(fake("Portador", 2, 2), 1)
	equip(data("Cetro Demoniaco"), portador)
	check("Cetro Demoniaco: el rival no puede Desterrar del Castillo; su dueño sí",
		[Rules.castle_banish_blocked(1, 0), Rules.castle_banish_blocked(1, 1), Rules.castle_banish_blocked(0, 1)],
		[true, false, false])
	var moved: Array = CardManager.banish_from_deck(1, 2, false, 0)
	check("banish_from_deck bloqueado no mueve nada", [moved.size(), CardManager.get_deck(1).size()], [0, 6])
	var top: Dictionary = CardManager.get_deck(0)[0]
	moved = CardManager.banish_from_deck(0, 2, false, 1)
	check("banish_from_deck sin bloqueo saca del tope", [moved.size(), moved[0] == top, CardManager.get_exile(0).size()], [2, true, 2])
	var src := put(fake("Fuente", 1, 1), 0)
	var token: int = EffectContext.push(src, 0, "disparada")
	var res: Dictionary = await ActionModule.mill(1, 2, true, "test", true)
	EffectContext.pop(token)
	check("Desterrar del tope del Castillo protegido (ActionModule.mill)", [res.get("prevented", false), CardManager.get_deck(1).size()], [true, 6])
	reset()
	_fill_deck(1, 6)
	var defensor := put(fake("Defensor", 2, 2), 0)
	equip(data("nehushtan"), defensor)
	check("nehushtan en Defensa: nadie Bota ni Destierra del Castillo rival",
		[Rules.mill_blocked(), Rules.castle_banish_blocked(1, 0), Rules.castle_banish_blocked(0, 1), Rules.castle_banish_blocked(1, 1)],
		[true, true, true, false])
	res = await ActionModule.mill(1, 2, false, "test", true)
	check("Botar bloqueado por nehushtan", [res.get("prevented", false), CardManager.get_deck(1).size()], [true, 6])
	defensor.set_zone(Constants.Zone.LINEA_ATAQUE)
	check("nehushtan fuera de Defensa no bloquea", [Rules.mill_blocked(), Rules.castle_banish_blocked(1, 0)], [false, false])


func _hand_lock() -> void:
	var Rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	put(data("Jinete de la Peste"), 0)
	put(fake("Jinete de la Guerra", 1, 1), 0)
	put(fake("Jinete del Hambre", 1, 1), 0)
	put(fake("Caballero", 1, 1), 0)
	check("Jinete de la Peste con tres Jinetes: no bloquea", Rules.hand_by_effects_blocked(1), false)
	put(fake("Jinete de la Muerte", 1, 1), 0)
	check("Jinete de la Peste con cuatro Jinetes: el rival no pone cartas en su mano por efectos",
		[Rules.hand_by_effects_blocked(1), Rules.hand_by_effects_blocked(0)], [true, false])


func _affect_tax() -> void:
	var Rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var sake := put(data("sake"), 1, "reserva")
	var otro := put(fake("Oro común", 0, 0, "", "", Constants.CardType.ORO), 1, "reserva")
	check("Sake: Oro adicional por afectar a sus demás Oros (solo al rival)",
		[Rules.affect_tax(otro, 0), Rules.affect_tax(sake, 0), Rules.affect_tax(otro, 1)], [1, 0, 0])
	var ally := put(fake("Aliado", 2, 2), 1)
	check("Sin manuel rodriguez no hay impuesto a los Aliados", Rules.affect_tax(ally, 0), 0)
	Rules.grant_ally_affect_tax(1, GameManager.turn_serial + 1)
	var during: int = Rules.affect_tax(ally, 0)
	GameManager.turn_serial += 1
	var next_turn: int = Rules.affect_tax(ally, 0)
	GameManager.turn_serial += 1
	check("manuel rodriguez: hasta su próximo turno", [during, next_turn, Rules.affect_tax(ally, 0)], [1, 1, 0])
	Rules.reset_game_state()
	# De punta a punta: el bot (jugador 1) sin Oro no puede elegir un Oro protegido por Sake.
	var sake0 := put(data("sake"), 0, "reserva")
	var oro0 := put(fake("Oro del Anfitrión", 0, 0, "", "", Constants.CardType.ORO), 0, "reserva")
	for g in zone_node(1, "reserva").get_children():
		if g != sake and g != otro:
			g.queue_free()
	var picked: Node = await main._card_interaction.await_target("Destruye un Oro", func(c): return c == oro0, true, 1)
	var picked_multi: Array = await main._card_interaction.await_multi_target("Destruye Oros", [oro0, sake0], 2, Callable(), Callable(), true, null, 1)
	check("Sake: el bot sin Oro no puede elegir los demás Oros protegidos", [picked, picked_multi], [null, [sake0]])
	# El Oro adicional se paga tras la ventana de respuesta: si el rival cancela el efecto, no se cobra.
	var EC = load("res://scripts/core/effects/EffectContext.gd")
	var token: int = EC.push(sake, 1, "disparada", "cancelled")
	var paid: bool = await main._card_interaction._pay_affect_tax([oro0], 1)
	EC.pop(token)
	check("Sake: efecto cancelado en la ventana → no se paga ni afecta", paid, false)


func _crono_diamante() -> void:
	var Rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var StackAnnul = load("res://scripts/core/effects/StackAnnul.gd")
	put(data("crono diamante"), 0, "reserva")
	var oro := put(fake("Oro activable", 0, 0, "", "", Constants.CardType.ORO), 0, "reserva")
	GameManager.turn_serial = 77
	var first: bool = Rules.note_gold_ability_use(oro, 0)
	var second: bool = Rules.note_gold_ability_use(oro, 0)
	check("Crono Diamante: solo la primera habilidad de Oro del turno", [first, second], [true, false])
	var obj := {"context": {"controller_id": 0, "source_card_node": oro, "_first_gold_ability": true}}
	var other := {"context": {"controller_id": 0, "source_card_node": oro}}
	check("Crono Diamante: la primera no puede ser cancelada", [StackAnnul.protected_from_cancel(obj), StackAnnul.protected_from_cancel(other)], [true, false])


func _compiled_choices() -> void:
	var Rules = load("res://scripts/core/effects/mechanics/ProtectionRules.gd")
	var sarcofago := put(data("Sarcófago Impío"), 1, "reserva")
	var propio := put(fake("Propio", 2, 2), 1)
	var rival := put(fake("Rival", 2, 2), 0)
	GameManager.turn_serial = 20
	var ok: bool = await TriggerSystem._effect_interpreter.try_execute(sarcofago,
		"Una vez por turno, un Aliado gana Indestructible, Indesterrable o \"No puede ser Barajado\", hasta tu próximo turno.", 1)
	var now: bool = has(propio, Constants.Keyword.INDESTRUCTIBLE)
	GameManager.turn_serial = 21
	var opp_turn: bool = has(propio, Constants.Keyword.INDESTRUCTIBLE)
	GameManager.turn_serial = 22
	check("Sarcófago Impío: el bot da Indestructible a su Aliado hasta su próximo turno",
		[ok, now, opp_turn, has(propio, Constants.Keyword.INDESTRUCTIBLE), has(rival, Constants.Keyword.INDESTRUCTIBLE)],
		[true, true, true, false, false])
	var interp = TriggerSystem._effect_interpreter
	check("vision heroica: sin nada en la Pila no se ofrece Anular",
		[interp._option_possible([{"op": "annul", "text": "anula un talismán oponente"}], sarcofago, 1),
			interp._option_possible([{"op": "draw", "amount": 1}], sarcofago, 1)], [false, true])
	var oro := put(fake("Oro", 0, 0, "", "", Constants.CardType.ORO), 0, "reserva")
	var spec := {"card_types": [], "controller": "any", "exclude_gold": false, "stat": "coste", "cmp": "<=", "value": 2}
	check("\"una carta de coste 2 o menos\" no incluye Oros", [interp._matches(oro, spec, sarcofago, 1), interp._matches(rival, spec, sarcofago, 1)], [false, true])
	# kotoku-in (bot): elige la primera opción con objetivo; la bandera del Talismán la deja el intérprete.
	await interp._execute_step(main, {"op": "talisman_fizzle"}, [], sarcofago, 1)
	check("kotoku-in: el próximo Talismán del rival se resuelve sin efecto",
		[TriggerSystem._totem_patterns.consume_kotoku_in_talisman_fizzle(0), TriggerSystem._totem_patterns.consume_kotoku_in_talisman_fizzle(0)], [true, false])
	propio.set_meta("cannot_be_shuffled_until", -1)
	await interp._buff({"count": 1, "amount": 0, "keywords": [], "no_shuffle": true, "duration": "until_next_turn"}, [propio], sarcofago)
	var ns_now: bool = Rules.cannot_be_shuffled(propio)
	GameManager.turn_serial = 24
	check("\"No puede ser Barajado\" hasta tu próximo turno", [ns_now, Rules.cannot_be_shuffled(propio)], [true, false])


func _batch5() -> void:
	var tax = main._gold_manager._tax
	var colab: Node = main._create_card(data("colaborador titan"), true)
	var voragh: Node = main._create_card(fake("Voragh", 3, 3, "Puedes Descartar una carta para reducir su coste en un Oro."), true)
	_created.append_array([colab, voragh])
	var pc: Dictionary = tax._get_discard_cost_reduction_pattern(colab)
	var pv: Dictionary = tax._get_discard_cost_reduction_pattern(voragh)
	check("Descuentos \"Puedes X para reducir su coste\": colaborador titan y voragh",
		[pc.get("verbs"), pc.get("ally"), pc.get("races"), pc.get("reduce"), pv.get("verbs"), pv.get("ally"), pv.get("reduce")],
		[["descartar", "destruir"], true, ["titán", "ignis"], 1, ["descartar"], false, 1])
	# kabutowari (bot): +1 por Aliado en Defensa, Roba 2 si ganó más de 1.
	var portador := put(fake("Portador", 2, 2), 1)
	put(fake("Def A", 1, 1), 1)
	put(fake("Def B", 1, 1), 1)
	var kabuto := equip(data("kabutowari"), portador)
	_fill_deck(1, 5)
	var hand_before: int = main._opponent_fan.get_cards().size()
	await load("res://scripts/core/effects/mechanics/InPlayAbilities.gd").kabutowari(kabuto, {"ability_index": 0})
	check("kabutowari: +3 de Fuerza (tres en Defensa) y Roba dos",
		[strength(portador), main._opponent_fan.get_cards().size() - hand_before], [5, 2])
	reset()
	# Agrupar dos cartas (iga ryu): un Oro Pagado y un Aliado de Línea de Ataque del bot.
	for leftover in zone_node(1, "pagado").get_children():
		leftover.free()
	var pagado := put(fake("Oro pagado", 0, 0, "", "", Constants.CardType.ORO), 1, "pagado")
	var atacante := put(fake("Atacante", 2, 2), 1, "atk")
	var moved: int = await main._gold_manager.agrupar_cartas(1, 2)
	check("agrupar_cartas: Oro Pagado → Reserva y Ataque → Defensa",
		[moved, pagado.current_zone == Constants.Zone.RESERVA_ORO, atacante.current_zone == Constants.Zone.LINEA_DEFENSA], [2, true, true])
	reset()
	# Titán Abismal (bot): sube el coste de la carta propia.
	var titan := put(data("Titán Abismal"), 1)
	var interp = TriggerSystem._effect_interpreter
	await interp._apply_verb({"verb": "cost_shift", "count": 1, "amount": 1}, [titan], titan)
	ContinuousEffectManager._invalidate_cache()
	check("Titán Abismal: el bot aumenta el coste de su carta en 1", ContinuousEffectManager.get_modified_cost(titan), int(titan.card_cost) + 1)


func _sandraudiga() -> void:
	var sd := data("sandraudiga")
	var text: String = sd.habilidad
	var parsed: Array = UniversalCardParser.parse_abilities(text, str(sd.id)).filter(func(a): return a.get("ability_type", "") == "ACTIVATED")
	var exile_ab: Dictionary = {}
	for a in parsed:
		if main._card_inspector._ability_is_destierro_usable(str(a.raw_text)):
			exile_ab = a
	check("sandraudiga: la segunda habilidad es activada y usable desde el Destierro", exile_ab.is_empty(), false)
	CardManager.get_exile(1).append(sd)
	in_hand(1, 1)
	var hand_before: int = main._opponent_fan.cards.size()
	var proxy: Node = main._create_card(sd, false)
	proxy.owner_id = 1
	proxy.controller_id = 1
	proxy.set_zone(Constants.Zone.DESTIERRO)
	await main._card_inspector._hand_cementerio_handler._activate_sandraudiga_shuffle_from_exile(proxy, exile_ab)
	proxy.free()
	var in_deck: bool = CardManager.get_deck(1).any(func(d): return str(d.get("nombre")) == "sandraudiga")
	var in_exile: bool = CardManager.get_exile(1).any(func(d): return str(d.get("nombre")) == "sandraudiga")
	check("sandraudiga: Destierra una carta de la mano y se baraja en el Castillo (bot)",
		[in_deck, in_exile, main._opponent_fan.cards.size()], [true, false, hand_before - 1])


func _cuervo_nocturno() -> void:
	var cd := data("cuervo nocturno")
	var parsed: Array = UniversalCardParser.parse_abilities(cd.habilidad, str(cd.id)).filter(func(a): return a.get("ability_type", "") == "ACTIVATED")
	var hand_ab: Dictionary = {}
	for a in parsed:
		if main._card_inspector._ability_is_hand_usable(str(a.raw_text)):
			hand_ab = a
	check("cuervo nocturno: poner en el fondo y Robar dos es activada desde la mano", hand_ab.is_empty(), false)
	_fill_deck(1, 4)
	in_hand(1, 1)
	var cuervo: Node = main._create_card(cd, true)
	main._opponent_fan.add_card(cuervo)
	cuervo.owner_id = 1
	cuervo.controller_id = 1
	_created.append(cuervo)
	var hand_before: int = main._opponent_fan.cards.size()
	await main._card_inspector._hand_cementerio_handler._activate_tyet_mill_and_draw(cuervo, hand_ab)
	var bottom: Dictionary = CardManager.get_deck(1).back() if not CardManager.get_deck(1).is_empty() else {}
	var in_deck: bool = CardManager.get_deck(1).any(func(d): return str(d.get("nombre")).to_lower() == "cuervo nocturno")
	check("cuervo nocturno: va al fondo con otra carta y Roba dos", [in_deck, main._opponent_fan.cards.size()], [true, hand_before])


func _amazona_fase_final() -> void:
	put(data("amazona desafiante"), 1)
	for i in 3:
		CardManager.get_cemetery(0).append(fake("Cementerio %d" % i, 1, 1))
	var before: int = CardManager.get_cemetery(0).size() + CardManager.get_cemetery(1).size()
	await TriggerSystem.resolve_turn_end_triggers(1)
	var waited := 0
	while (TriggerSystem.is_collecting or TriggerSystem.is_resolving) and waited < 300:
		await get_tree().process_frame
		waited += 1
	var after: int = CardManager.get_cemetery(0).size() + CardManager.get_cemetery(1).size()
	check("amazona desafiante: en su Fase Final Baraja cartas de los Cementerios", after < before, true)


func _iga_ryu() -> void:
	var iga := put(data("iga ryu"), 0, "apoyo")
	GameManager.turn_serial = 40
	var first: Node = put(fake("Primer Aliado", 2, 2, "Cuando entra en juego, Roba una carta."), 1)
	await TriggerSystem._collect_triggers_for_event("on_enter_play", {"player_id": 1, "card": first})
	var second: Node = put(fake("Segundo Aliado", 2, 2, "Cuando entra en juego, Roba una carta."), 1)
	await TriggerSystem._collect_triggers_for_event("on_enter_play", {"player_id": 1, "card": second})
	check("iga ryu: solo el primer Aliado rival del turno pierde su habilidad",
		[KeywordManager.is_silenced(first), KeywordManager.is_silenced(second)], [true, false])
	var totem := put(fake("Tótem propio", 0, 1, "", "", Constants.CardType.TOTEM), 1, "apoyo")
	var ok: bool = await TriggerSystem._totem_patterns.try_execute_iga_ryu_convert_totems_pattern(
		"Una vez por turno, puedes convertir hasta tres Tótem en Aliados de Fuerza 4 por el turno.", iga, 1)
	var as_ally: bool = totem.card_type == Constants.CardType.ALIADO and totem.current_zone == Constants.Zone.LINEA_DEFENSA
	var str_now: int = strength(totem)
	TriggerSystem._totem_patterns._on_turn_started_revert_converted(0, 41)
	check("iga ryu: convierte Tótems en Aliados de Fuerza 4 por el turno",
		[ok, as_ally, str_now, totem.card_type == Constants.CardType.TOTEM], [true, true, 4, true])


func _estacion_fantasma() -> void:
	put(data("Estación Fantasma"), 1, "apoyo")
	_fill_deck(0, 8)
	var furia: Node = put(fake("Furioso", 2, 3, "Furia."), 1)
	var deck_before: int = CardManager.get_deck(0).size()
	GameManager.turn_serial = 50
	await load("res://scripts/core/effects/mechanics/InPlayAbilities.gd").estacion_fantasma_on_attack(1)
	var result := {"total_damage_to_castle": 0, "total_damage_to_exile": 0}
	BattleManager._accumulate_castle_damage(result, furia, 3)
	check("Estación Fantasma: el Aliado con Furia no hace daño y el rival Destierra su Fuerza del fondo",
		[CardManager.get_deck(0).size(), result.total_damage_to_castle], [deck_before - 3, 0])


func _corte_letal() -> void:
	var corte := put(data("corte letal"), 0)
	var pattern: Dictionary = main._gold_manager._get_discard_cost_reduction_pattern(corte)
	check("corte letal: Descartar dos reduce dos y no puede ser Anulado",
		[pattern.get("count"), pattern.get("reduce"), pattern.get("no_annul")], [2, 2, true])


func _activated_costs() -> void:
	"""Costes de las activadas compilados (EffectCompiler.COST_PIECES): la carta misma como coste."""
	var ctx: int = EffectContextScript.push(null, 1, "activada")
	# lurulu: "Puedes Descartarlo para Robar una carta" (desde la mano).
	var ld := data("lurulu")
	var ab: Dictionary = {}
	for a in UniversalCardParser.parse_abilities(ld.habilidad, str(ld.id)):
		if a.get("ability_type", "") == "ACTIVATED" and main._card_inspector._ability_is_hand_usable(str(a.raw_text)):
			ab = a
	# El efecto sigue aunque Descartarla libere el Nodo (se mide con Botar: Robar sale del GameBoard
	# legacy en este entorno).
	_fill_deck(0, 3)
	var lurulu: Node = main._create_card(ld, true)
	main._opponent_fan.add_card(lurulu)
	lurulu.owner_id = 1
	lurulu.controller_id = 1
	lurulu.set_zone(Constants.Zone.MANO)
	_created.append(lurulu)
	var deck_before: int = CardManager.get_deck_count(0)
	var ok: bool = await TriggerSystem._effect_interpreter.try_execute(lurulu,
		"Puedes Descartarlo para que tu oponente Bote dos cartas.", 1)
	var in_cem: bool = CardManager.get_cemetery(1).any(func(d): return str(d.get("nombre")) == "lurulu")
	check("lurulu: activada desde la mano; Descartarla es el coste y el efecto sigue",
		[ab.is_empty(), ok, in_cem, deck_before - CardManager.get_deck_count(0)], [false, true, true, 2])
	# antu: "Puedes Desterrarlo de tu Cementerio para subir un Aliado de tu Cementerio a tu mano".
	var ad := data("antu")
	CardManager.get_cemetery(1).append(ad)
	CardManager.get_cemetery(1).append(fake("Aliado Cementerio", 1, 1))
	var proxy: Node = main._create_card(ad, false)
	proxy.owner_id = 1
	proxy.controller_id = 1
	proxy.set_zone(Constants.Zone.CEMENTERIO)
	var hand_before: int = main._opponent_fan.cards.size()
	ok = await TriggerSystem._effect_interpreter.try_execute(proxy,
		"Puedes Desterrarlo de tu Cementerio para subir un Aliado de tu Cementerio a tu mano.", 1)
	proxy.free()
	var antu_exiled: bool = CardManager.get_exile(1).any(func(d): return str(d.get("nombre")) == "antu")
	var antu_in_cem: bool = CardManager.get_cemetery(1).any(func(d): return str(d.get("nombre")) == "antu")
	check("antu: se Destierra del Cementerio como coste y sube otro Aliado a la mano",
		[ok, antu_exiled, antu_in_cem, main._opponent_fan.cards.size() - hand_before], [true, true, false, 1])
	EffectContextScript.pop(ctx)
	# Belial: "Sólo puedes utilizar esta habilidad de Belial una vez por turno" no es una habilidad: la
	# anterior queda como activada una vez por turno.
	var bd := data("belial")
	var acts: Array = UniversalCardParser.parse_abilities(bd.habilidad, str(bd.id)).filter(
		func(a): return a.get("ability_type", "") == "ACTIVATED")
	check("Belial: una sola activada (Botar dos para subirlo), una vez por turno",
		[acts.size(), "botar dos cartas" in str(acts[0].raw_text).to_lower() if not acts.is_empty() else false],
		[1, true])


func _compiled_prevention() -> void:
	"""CompiledPrevention: "Puedes Desterrarlo para prevenir que un Aliado sea Anulado o su habilidad
	cancelada" (wendy) entra al registro de prevenciones con su coste compilado."""
	var cp = load("res://scripts/core/effects/mechanics/CompiledPrevention.gd")
	var wendy: Node = put(data("wendy"), 1)
	var sp: Dictionary = cp.spec(str(wendy.card_ability), EffectController._prevention_registry)
	var detected: bool = EffectController._prevention_registry.any(func(e): return e.detect.call(str(wendy.card_ability)))
	var ally: Node = put(fake("Protegido", 2, 2), 1)
	var totem_data := fake("Tótem rival", 2, 0, "", "", Constants.CardType.TOTEM)
	check("wendy: prevención compilada (Anular, solo Aliados, coste Desterrarlo)",
		[sp.get("kind", ""), sp.get("types", []), detected, cp.applies(sp, ally, wendy), cp.applies(sp, totem_data, wendy),
			cp.is_available(sp, wendy)], ["annul", ["aliado"], true, true, false, true])
	var paid: bool = await cp.pay(sp, wendy)
	check("wendy: pagar la prevención la Destierra",
		[paid, CardManager.get_exile(1).any(func(d): return str(d.get("nombre")) == "wendy")], [true, true])


func _camilo_castle_look() -> void:
	var camilo := put(data("camilo henriquez"), 1)
	_fill_deck(1, 6)
	var hand_before: int = main._opponent_fan.cards.size()
	var exile_before: int = CardManager.get_exile(1).size()
	var text := "Cuando entra en juego, Destierra hasta una carta de coste 2 o menos y mira las primeras cuatro cartas de tu Castillo. Pon dos en tu Destierro y el resto en tu mano."
	var ok: bool = await TriggerSystem._effect_interpreter.try_execute(camilo, text, 1)
	check("camilo henriquez: Destierra y luego mira cuatro (dos al Destierro, dos a la mano)",
		[ok, main._opponent_fan.cards.size() - hand_before, CardManager.get_exile(1).size() - exile_before],
		[true, 2, 2])
