extends RefCounted
## LeavePlayPatterns — "Cuando salga del juego" (y "Cuando entra o sale del juego") que no son una
## secuencia compilable: cambios de control (ryugu-jo, dulgruss, Vâlva Apei), convertir (Marchosias,
## Isla de Poveglia, transilvania, zennyo ryuo, orikalon), condiciones de turno o de causa (kintaro,
## urashima taro, kato tsune) y la propia carta como costo (momotaro, yekamus).
## Se usa con preload desde TriggerResolution (on_enter_play y on_leave_play).
##
## La salida se resuelve con la carta todavía en su zona: EffectController emite on_card_left_play
## antes de moverla y la mueve (y libera el Nodo) en cuanto el efecto espera algo. Por eso se toma
## todo de la carta al empezar y la ventana de respuesta se abre sobre un Nodo temporal con sus
## datos; "Desterrarlo"/"convertirlo" esperan a que llegue al Cementerio o al Destierro (_landed()).

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const ConvertScript = preload("res://scripts/core/effects/mechanics/ConvertPatterns.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")

## Textos normalizados (CemeteryTriggers.normalize: minúsculas, sin tildes).
const MARCHOSIAS := "puedes convertir hasta una carta de los cementerios en un aliado bestia de fuerza 2 con la habilidad"
const POVEGLIA := "puedes convertir la primera carta de un castillo en un aliado de fuerza 2 sin habilidad y ponla bajo tu control"
const TRANSILVANIA := "puedes pagar un oro para convertir una carta de coste 4 o menos en un oro sin habilidad y moverlo a tu oro pagado"
const ANTU := "puedes elegir aliado o totem. muestra cinco cartas del tope de tu castillo y pon las cartas del tipo elegido en tu mano"
const MAGOG := "cuando salga del juego, tus aliados no pueden salir del juego este turno"
const RYUGU := "cuando salga del juego, gana el control de un aliado o totem de coste 2 o menos"
const DULGRUSS := "cuando salga del juego, gana el control de una carta que no sea oro de la que seas dueno"
const VALVA := "cuando salga del juego, cada jugador recupera el control de las cartas de las que sea dueno que no sean oro"
const MOMOTARO := "cuando salga del juego, si controlas otros dos o mas aliados, puedes desterrarlo para que tu oponente bote una carta por cada talisman en su destierro"
const KINTARO := "cuando salga del juego en el turno oponente, puedes mover un oro a su oro pagado"
const URASHIMA := "cuando salga del juego en el turno oponente, el primer aliado que juegues en tu proximo turno reduce su coste en un oro"
const KATO := "cuando salga del juego por un efecto oponente, puedes mover hasta un oro oponente a su oro pagado y robar una carta"
const ZENNYO := "cuando salga del juego, puedes convertirlo en un oro sin habilidad y ponerlo en tu oro pagado"
const ORIKALON := "cuando salga del juego, conviertela en un arma con la habilidad"
const ORIKALON_WEAPON := "El portador gana 2 de Fuerza e Imbloqueable."
const CHINIVILU := "cuando salga del juego, puedes buscar en tu castillo una copia de este aliado y juegalo sin pagar su coste"
const YEKAMUS := "cuando salga del juego, puedes desterrarlo para buscar un yekamus en tu castillo y ponerlo en tu mano"
const FARSARIOS := "cuando salga del juego, puedes activar la habilidad de un aliado en tu destierro"

## Las de "entra o sale": también se resuelven al entrar.
const ENTER_OR_LEAVE := [MARCHOSIAS, POVEGLIA, TRANSILVANIA, ANTU]
const LEAVE_ONLY := [MAGOG, RYUGU, DULGRUSS, VALVA, MOMOTARO, KINTARO, URASHIMA, KATO, ZENNYO, ORIKALON,
	CHINIVILU, YEKAMUS, FARSARIOS]


## ¿Este texto tiene un disparador que resuelve este módulo? (entering = on_enter_play).
static func handles(full_text: String, entering: bool) -> bool:
	return not _kind(CemeteryTriggersScript.normalize(full_text), entering).is_empty()


static func _kind(t: String, entering: bool) -> String:
	for k in ENTER_OR_LEAVE:
		if k in t:
			return k
	if not entering:
		for k in LEAVE_ONLY:
			if k in t:
				return k
	return ""


## true si lo resolvió (aunque el jugador haya rechazado un "puedes" o no hubiera objetivos).
static func try_execute(card: Node, full_text: String, controller_id: int, entering: bool, event_data: Dictionary = {}) -> bool:
	var kind := _kind(CemeteryTriggersScript.normalize(full_text), entering)
	if kind.is_empty() or not is_instance_valid(card):
		return false
	var main := CardQuery.main_node()
	if not main:
		return true
	var s := {
		"card": card,
		"id": card.get_instance_id(),
		"name": str(card.get("card_name")),
		"owner": int(card.owner_id) if card.get("owner_id") != null else controller_id,
		"ctrl": int(card.controller_id) if card.get("controller_id") != null else controller_id,
		"data": card.card_data.duplicate() if card.get("card_data") != null else {},
		"cem": 0, "exile": 0,
	}
	s.cem = CardManager.get_cemetery(s.owner).size()
	s.exile = CardManager.get_exile(s.owner).size()
	var proxy: Node = _proxy(main, s)
	var token: int = EffectContextScript.push(proxy, s.ctrl, "disparada", "pending")
	match kind:
		MARCHOSIAS: await _marchosias(main, s, proxy)
		POVEGLIA: await _poveglia(main, s, proxy)
		TRANSILVANIA: await _transilvania(main, s, proxy)
		ANTU: await _antu(main, s, proxy)
		MAGOG: await _magog(main, s, proxy)
		RYUGU: await _gain_control(main, s, proxy, "gana el control de un Aliado o Tótem de coste 2 o menos",
			func(c: Node) -> bool:
				return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM] \
					and ContinuousEffectManager.cost_at_most(c, 2))
		DULGRUSS: await _gain_control(main, s, proxy, "gana el control de una carta tuya que no sea Oro",
			func(c: Node) -> bool:
				return c.get("card_type") != Constants.CardType.ORO and c.get("owner_id") != null and int(c.owner_id) == s.ctrl)
		VALVA: await _valva(main, s, proxy)
		MOMOTARO: await _momotaro(main, s, proxy)
		KINTARO: await _kintaro(main, s, proxy)
		URASHIMA: await _urashima(main, s, proxy)
		KATO: await _kato(main, s, proxy, event_data)
		ZENNYO: await _zennyo(main, s, proxy)
		ORIKALON: await _orikalon(main, s, proxy)
		CHINIVILU: await _chinivilu(main, s, proxy)
		YEKAMUS: await _yekamus(main, s, proxy)
		FARSARIOS: await _farsarios(main, s, proxy)
	EffectContextScript.pop(token)
	if is_instance_valid(proxy):
		proxy.queue_free()
	return true


# =============================================================================
# AYUDAS
# =============================================================================
static func _proxy(main: Node, s: Dictionary) -> Node:
	var proxy: Node = main._create_card(s.data, false)
	proxy.visible = false
	main.add_child(proxy)
	proxy.owner_id = s.owner
	if proxy.get("controller_id") != null:
		proxy.controller_id = s.ctrl
	proxy.current_zone = Constants.Zone.CEMENTERIO
	return proxy


## Ventana del rival (una por efecto, §59). true = cancelado.
static func _window(proxy: Node, s: Dictionary) -> bool:
	return await TriggerSystem.open_response_window(proxy, s.name, s.ctrl)


static func _confirm(main: Node, pid: int, title: String, yes: String) -> bool:
	if PlayerSideScript.is_bot(pid):
		return true
	return await SelectionManager.await_two_choice(main, title, yes, "No", pid)


static func _is_card(c: Node, s: Dictionary) -> bool:
	return c.get_instance_id() == s.id


## Espera a que la carta deje el juego y devuelve dónde quedó: {zone, data} o {} si no fue al
## Cementerio ni al Destierro de su dueño (volvió a la mano, se barajó...).
static func _landed(s: Dictionary) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var card = s.card
	for _i in 180:
		if not is_instance_valid(card) or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
			break
		await tree.process_frame
	await tree.process_frame
	if is_instance_valid(card) and card.get("current_zone") in [Constants.Zone.MANO, Constants.Zone.CASTILLO]:
		return {}
	for zone in [Constants.Zone.CEMENTERIO, Constants.Zone.DESTIERRO]:
		var arr: Array = CardManager.get_cemetery(s.owner) if zone == Constants.Zone.CEMENTERIO else CardManager.get_exile(s.owner)
		var from: int = s.cem if zone == Constants.Zone.CEMENTERIO else s.exile
		for i in range(arr.size() - 1, mini(from, arr.size()) - 1, -1):
			if str(arr[i].get("nombre", "")) == str(s.data.get("nombre", "")):
				return {"zone": zone, "data": arr[i]}
	return {}


## Saca de su zona la entrada que devolvió _landed().
static func _take_landed(s: Dictionary, spot: Dictionary) -> bool:
	if spot.is_empty():
		return false
	if spot.zone == Constants.Zone.CEMENTERIO:
		return CardManager.take_from_cemetery(s.owner, spot.data)
	var exile: Array = CardManager.get_exile(s.owner)
	var idx: int = exile.find(spot.data)
	if idx < 0:
		return false
	exile.remove_at(idx)
	CardManager._emit_exile_changed(s.owner)
	return true


## La propia carta, que ya salió del juego, al Destierro (costo de momotaro y yekamus).
static func _banish_self(s: Dictionary) -> bool:
	var spot := await _landed(s)
	if spot.is_empty():
		return false
	if spot.zone == Constants.Zone.DESTIERRO:
		return true  # ya está desterrada
	if not _take_landed(s, spot):
		return false
	spot.data["esta_oculta"] = false
	CardManager.append_to_exile(s.owner, spot.data)
	return true


## Pone en juego, bajo el control de 'ctrl', un Aliado convertido a partir de los datos de una carta
## fuera del juego (Marchosias, Isla de Poveglia).
static func _ally_from_data(main: Node, data: Dictionary, zone_owner: int, ctrl: int, source: Node, strength: int,
		keywords: Array, race: String) -> Node:
	var new_data: Dictionary = data.duplicate()
	new_data["tipo"] = Constants.CardType.ALIADO
	new_data["esta_oculta"] = false
	if not race.is_empty():
		new_data["raza"] = race
	var node: Node = main._create_card(new_data, false)
	node.owner_id = zone_owner
	node.controller_id = ctrl
	main._connect_card_signals(node)
	PlayerSideScript.ally_containers(main, ctrl)[0].add_child(node)
	node.set_zone(Constants.Zone.LINEA_DEFENSA)
	if CardFactory and CardFactory.has_method("on_card_enters_play"):
		CardFactory.on_card_enters_play(node)
	if node.has_method("play_enter_animation"):
		node.play_enter_animation()
	await ConvertScript._finish_conversion(node, source, ctrl, strength, keywords, false)
	return node


## Una carta EN JUEGO pasa a ser un Oro sin habilidad en el Oro Pagado de 'ctrl' (transilvania). No
## sale del juego: no dispara salidas. Sus Armas, si era un Aliado, van al Cementerio.
static func _in_play_to_paid_gold(main: Node, node: Node, ctrl: int, source: Node) -> void:
	var wielder = node.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(node)
	var weapons = node.get("equipped_weapons")
	if weapons is Array:
		for w in weapons.duplicate():
			if is_instance_valid(w):
				await CardManager.destroy_card(int(w.owner_id) if w.get("owner_id") != null else ctrl, w)
	var parent = node.get_parent()
	if parent:
		parent.remove_child(node)
	var new_data: Dictionary = node.card_data.duplicate()
	new_data["tipo"] = Constants.CardType.ORO
	new_data["habilidad"] = ""
	node.load_from_data(new_data)
	node.controller_id = ctrl
	PlayerSideScript.oro_pagado(main, ctrl).add_child(node)
	node.top_level = false
	node.set_zone(Constants.Zone.ORO_PAGADO)
	node.scale = Constants.GOLD_CARD_SCALE
	node.base_scale = Constants.GOLD_CARD_SCALE
	node.modulate = Color(0.6, 0.6, 0.6, 1.0)
	node.can_interact = (ctrl == 0)
	node.is_converted = true
	await KeywordManager.silence_card(node, source, "permanent", true)
	ContinuousEffectManager.remove_modifiers_from_source(node)
	GameState.agregar_oro_pagado(ctrl, 1)
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)


## Mueve un Oro de una Reserva al Oro Pagado de quien lo controla (kintaro, kato tsune).
static func _gold_to_paid(main: Node, gold: Node) -> void:
	var pid: int = CardQuery.controller_of(gold)
	if not await main._gold_manager._mover_oro_a_pagado(gold):
		GameState.pagar_oro(pid, 1)
	main._gold_manager._update_gold_display()


static func _pick_reserve_gold(main: Node, chooser: int, sides: Array, prompt: String) -> Node:
	var golds: Array = []
	for side in sides:
		for g in PlayerSideScript.gold_reserva(main, side).get_children():
			if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO:
				golds.append(g)
	if golds.is_empty():
		return null
	if PlayerSideScript.is_bot(chooser) or not main.get("_card_interaction"):
		return golds[0]
	return await main._card_interaction.await_target(prompt, func(c: Node) -> bool: return c in golds, true, chooser)


# =============================================================================
# CARTAS
# =============================================================================
# Marchosias: "Cuando entra o sale del juego, puedes convertir hasta una carta de los Cementerios en
# un Aliado Bestia de Fuerza 2 con la habilidad "Furia"."
static func _marchosias(main: Node, s: Dictionary, proxy: Node) -> void:
	var pools: Array = []
	var owners: Array = []
	for zone_owner in [s.ctrl, 1 - s.ctrl]:
		var entries: Array = []
		for d in CardManager.get_cemetery(zone_owner):
			entries.append({"data": d, "eligible": true})
		pools.append({"is_own": zone_owner == s.ctrl, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true})
		owners.append(zone_owner)
	var raw: Array = await ActionModule.pick_in_zones(s.ctrl,
		"%s: puedes convertir una carta de los Cementerios en un Aliado Bestia de Fuerza 2 con Furia" % s.name, pools, 0, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size():
		return
	var data: Dictionary = pools[pi].cards[ci].data
	if await _window(proxy, s) or not CardManager.take_from_cemetery(owners[pi], data):
		return
	var node := await _ally_from_data(main, data, owners[pi], s.ctrl, proxy, 2, [Constants.Keyword.FURIA], "Bestia")
	main._update_debug("%s: %s es ahora un Aliado Bestia de Fuerza 2 con Furia" % [s.name, str(node.get("card_name"))])


# Isla de Poveglia: "Cuando entra o sale del juego, puedes convertir la primera carta de un Castillo
# en un Aliado de Fuerza 2 sin habilidad y ponla bajo tu control."
static func _poveglia(main: Node, s: Dictionary, proxy: Node) -> void:
	var zone_owner: int = 1 - s.ctrl
	if PlayerSideScript.is_bot(s.ctrl):
		if CardManager.get_deck(zone_owner).is_empty():
			zone_owner = s.ctrl
	else:
		var pick: int = await SelectionManager.await_choice(main,
			"%s: puedes convertir la primera carta de un Castillo en un Aliado de Fuerza 2 sin habilidad" % s.name,
			["Castillo oponente", "Tu Castillo", "No"], s.ctrl)
		if pick < 0 or pick > 1:
			return
		zone_owner = 1 - s.ctrl if pick == 0 else s.ctrl
	var deck: Array = CardManager.get_deck(zone_owner)
	if deck.is_empty() or await _window(proxy, s):
		return
	var data: Dictionary = deck.pop_front()
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	var node := await _ally_from_data(main, data, zone_owner, s.ctrl, proxy, 2, [], "")
	main._update_debug("%s: %s es ahora tu Aliado de Fuerza 2 sin habilidad" % [s.name, str(node.get("card_name"))])


# transilvania: "Cuando entra o sale del juego, puedes pagar un Oro para convertir una carta de coste 4
# o menos en un Oro sin habilidad y moverlo a tu Oro Pagado."
static func _transilvania(main: Node, s: Dictionary, proxy: Node) -> void:
	if not main._gold_manager or not main._gold_manager.puede_pagar(1, -1, "", -1, s.ctrl):
		return
	var target: Node = await PlayerSideScript.pick_in_play(main, s.ctrl,
		"%s: puedes pagar un Oro para convertir una carta de coste 4 o menos en un Oro sin habilidad (N: no)" % s.name,
		func(c: Node) -> bool:
			return c.get("current_zone") in Constants.ZONES_IN_PLAY and not _is_card(c, s) \
				and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 4),
		true, [1 - s.ctrl])
	if not target or not is_instance_valid(target):
		return
	if not await PlayerSideScript.pay(main, s.ctrl, 1):
		return
	if await _window(proxy, s) or not is_instance_valid(target) or not (target.get("current_zone") in Constants.ZONES_IN_PLAY):
		return
	var target_name := str(target.get("card_name"))
	await _in_play_to_paid_gold(main, target, s.ctrl, proxy)
	main._update_debug("%s: %s es ahora un Oro sin habilidad en tu Oro Pagado" % [s.name, target_name])


# antu: "Cuando entra o sale del juego, puedes elegir Aliado o Tótem. Muestra cinco cartas del tope de
# tu Castillo y pon las cartas del tipo elegido en tu mano y Baraja el resto."
static func _antu(main: Node, s: Dictionary, proxy: Node) -> void:
	var deck: Array = CardManager.get_deck(s.ctrl)
	if deck.is_empty():
		return
	var pick := 0
	if not PlayerSideScript.is_bot(s.ctrl):
		pick = await SelectionManager.await_choice(main, "%s: puedes elegir un tipo" % s.name, ["Aliado", "Tótem", "No"], s.ctrl)
	if pick < 0 or pick > 1:
		return
	var chosen: int = Constants.CardType.ALIADO if pick == 0 else Constants.CardType.TOTEM
	if await _window(proxy, s):
		return
	var shown: Array = []
	for _i in mini(5, deck.size()):
		shown.append(deck.pop_front())
	var names: Array = shown.map(func(d): return str(d.get("nombre", "?")))
	main._update_debug("%s muestra: %s" % [s.name, ", ".join(names)])
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(s.ctrl, shown, s.name)
	if CombatLog and CombatLog.has_method("log_action"):
		CombatLog.log_action("%s muestra: %s" % [s.name, ", ".join(names)])
	var kept := 0
	for d in shown:
		if int(d.get("tipo", -1)) == chosen:
			PlayerSideScript.put_in_hand(main, s.ctrl, d)
			kept += 1
		else:
			d["esta_oculta"] = true
			deck.append(d)
	CardManager.shuffle_deck(s.ctrl)
	AnimationQueue.queue_shuffle(s.ctrl, "Barajar mazo (%s)" % s.name)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	main._update_debug("%s: %d carta(s) a tu mano" % [s.name, kept])


# espada de magog: "Cuando salga del juego, tus Aliados no pueden salir del juego este turno."
static func _magog(main: Node, s: Dictionary, proxy: Node) -> void:
	if await _window(proxy, s):
		return
	EffectController.add_leave_play_immunity_this_turn(s.ctrl)
	main._update_debug("%s: tus Aliados no pueden salir del juego este turno" % s.name)


# ryugu-jo / dulgruss: "Cuando salga del juego, gana el control de...".
static func _gain_control(main: Node, s: Dictionary, proxy: Node, what: String, filter: Callable) -> void:
	var target: Node = await PlayerSideScript.pick_in_play(main, s.ctrl, "%s: %s" % [s.name, what],
		func(c: Node) -> bool:
			return c.get("current_zone") in Constants.ZONES_IN_PLAY and not _is_card(c, s) \
				and CardQuery.controller_of(c) != s.ctrl and filter.call(c),
		false, [1 - s.ctrl])
	if not target or not is_instance_valid(target) or await _window(proxy, s) or not is_instance_valid(target):
		return
	ContinuousEffectManager.gain_control_of_card(target, s.ctrl)
	if CardQuery.controller_of(target) == s.ctrl:
		main._update_debug("%s: ganas el control de %s" % [s.name, str(target.get("card_name"))])


# Vâlva Apei: "Cuando salga del juego, cada jugador recupera el control de las cartas de las que sea
# dueño que no sean Oro."
static func _valva(main: Node, s: Dictionary, proxy: Node) -> void:
	var borrowed: Array = []
	for pid in [0, 1]:
		for container in PlayerSideScript.line_containers(main, pid):
			for c in container.get_children():
				if is_instance_valid(c) and not _is_card(c, s) and c.get("card_type") != Constants.CardType.ORO \
						and c.get("owner_id") != null and int(c.owner_id) != CardQuery.controller_of(c):
					borrowed.append(c)
	if borrowed.is_empty() or await _window(proxy, s):
		return
	for c in borrowed:
		if is_instance_valid(c):
			ContinuousEffectManager.gain_control_of_card(c, int(c.owner_id))
	main._update_debug("%s: cada jugador recupera el control de sus cartas" % s.name)


# momotaro: "Cuando salga del juego, si controlas otros dos o más Aliados, puedes Desterrarlo para que
# tu oponente Bote una carta por cada Talismán en su Destierro."
static func _momotaro(main: Node, s: Dictionary, proxy: Node) -> void:
	var others := 0
	for container in PlayerSideScript.ally_containers(main, s.ctrl):
		for c in container.get_children():
			if is_instance_valid(c) and not _is_card(c, s) and c.get("card_type") == Constants.CardType.ALIADO \
					and CardQuery.controller_of(c) == s.ctrl:
				others += 1
	if others < 2:
		return
	var opp: int = 1 - s.ctrl
	var talismans: int = CardManager.get_exile(opp).filter(
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN).size()
	if not await _confirm(main, s.ctrl, "%s salió del juego" % s.name,
			"Desterrarlo: tu oponente Bota %d carta(s)" % talismans):
		return
	if not await _banish_self(s) or await _window(proxy, s) or talismans <= 0:
		return
	await ActionModule.mill(opp, talismans, false, s.name)


# kintaro: "Cuando salga del juego en el turno oponente, puedes mover un Oro a su Oro Pagado."
static func _kintaro(main: Node, s: Dictionary, proxy: Node) -> void:
	if GameManager.active_player_id == s.ctrl:
		return
	var gold: Node = await _pick_reserve_gold(main, s.ctrl, [1 - s.ctrl, s.ctrl],
		"%s: puedes mover un Oro a su Oro Pagado (N: no)" % s.name)
	if not gold or await _window(proxy, s) or not is_instance_valid(gold):
		return
	await _gold_to_paid(main, gold)


# urashima taro: "Cuando salga del juego en el turno oponente, el primer Aliado que juegues en tu
# próximo turno reduce su coste en un Oro."
static func _urashima(main: Node, s: Dictionary, proxy: Node) -> void:
	if GameManager.active_player_id == s.ctrl or await _window(proxy, s):
		return
	PaymentManager.add_first_ally_discount(s.ctrl, GameManager.turn_serial + 1)
	main._update_debug("%s: el primer Aliado que juegues en tu próximo turno cuesta un Oro menos" % s.name)


# kato tsune: "Cuando salga del juego por un efecto oponente, puedes mover hasta un Oro oponente a su
# Oro Pagado y Robar una carta."
static func _kato(main: Node, s: Dictionary, proxy: Node, event_data: Dictionary) -> void:
	var cause: Dictionary = event_data.get("cause", {})
	if cause.get("kind", "") != "effect" or int(cause.get("by", -1)) != 1 - s.ctrl:
		return
	if not await _confirm(main, s.ctrl, "%s salió del juego por un efecto oponente" % s.name,
			"Mover hasta un Oro oponente a su Oro Pagado y Robar una carta"):
		return
	var gold: Node = await _pick_reserve_gold(main, s.ctrl, [1 - s.ctrl],
		"%s: puedes mover un Oro oponente a su Oro Pagado (N: ninguno)" % s.name)
	if await _window(proxy, s):
		return
	if gold and is_instance_valid(gold):
		await _gold_to_paid(main, gold)
	await ActionModule.draw(s.ctrl, 1, s.name, true)


# zennyo ryuo: "Cuando salga del juego, puedes convertirlo en un Oro sin habilidad y ponerlo en tu Oro
# Pagado."
static func _zennyo(main: Node, s: Dictionary, proxy: Node) -> void:
	if not main._gold_manager or not await _confirm(main, s.ctrl, "%s salió del juego" % s.name,
			"Convertirlo en un Oro sin habilidad en tu Oro Pagado"):
		return
	if await _window(proxy, s):
		return
	var spot := await _landed(s)
	if not _take_landed(s, spot):
		return
	var data: Dictionary = spot.data.duplicate()
	data["tipo"] = Constants.CardType.ORO
	data["habilidad"] = ""
	var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(s.ctrl, data)
	if is_instance_valid(gold):
		gold.owner_id = s.owner
		gold.is_converted = true
		await KeywordManager.silence_card(gold, null, "permanent", true)
	main._update_debug("%s es ahora un Oro sin habilidad en tu Oro Pagado" % s.name)


# orikalon: "Cuando salga del juego, conviértela en un Arma con la habilidad "El portador gana 2 de
# Fuerza e Imbloqueable" y pórtala." Con la habilidad nueva en sus datos (no se silencia: es su
# texto).
static func _orikalon(main: Node, s: Dictionary, proxy: Node) -> void:
	if not main._gold_manager:
		return
	var wielder: Node = await PlayerSideScript.pick_in_play(main, s.ctrl,
		"%s: elige el Aliado que la porta como Arma" % s.name,
		func(c: Node) -> bool:
			return c.get("card_type") == Constants.CardType.ALIADO and not _is_card(c, s) \
				and c.get("current_zone") in Constants.ZONES_IN_PLAY and CardQuery.controller_of(c) == s.ctrl,
		false, [s.ctrl])
	if not wielder or await _window(proxy, s):
		return
	var spot := await _landed(s)
	if not is_instance_valid(wielder) or not _take_landed(s, spot):
		return
	var data: Dictionary = spot.data.duplicate()
	data["tipo"] = Constants.CardType.ARMA
	data["habilidad"] = ORIKALON_WEAPON
	data["esta_oculta"] = false
	var weapon: Node = main._create_card(data, false)
	weapon.owner_id = s.owner
	if weapon.get("controller_id") != null:
		weapon.controller_id = s.ctrl
	main._connect_card_signals(weapon)
	await main._gold_manager._equip_weapon(weapon, wielder, false)
	main._update_debug("%s es ahora un Arma de %s" % [s.name, str(wielder.get("card_name"))])


# chinivilu: "Cuando salga del juego, puedes buscar en tu Castillo una copia de este Aliado y juégalo
# sin pagar su coste."
static func _chinivilu(main: Node, s: Dictionary, proxy: Node) -> void:
	var deck: Array = CardManager.get_deck(s.ctrl)
	var nombre := str(s.data.get("nombre", ""))
	if not main._gold_manager or not await _confirm(main, s.ctrl, "%s salió del juego" % s.name,
			"Buscar una copia en tu Castillo y jugarla gratis"):
		return
	if await _window(proxy, s):
		return
	var found: Dictionary = {}
	for d in deck:
		if str(d.get("nombre", "")) == nombre:
			found = d
			break
	if not found.is_empty():
		deck.erase(found)
	CardManager.shuffle_deck(s.ctrl)
	AnimationQueue.queue_shuffle(s.ctrl, "Barajar mazo (%s)" % s.name)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if found.is_empty():
		main._update_debug("%s: no hay otra copia en tu Castillo" % s.name)
		return
	found["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(found, s.ctrl):
		CardManager.add_to_cemetery(s.ctrl, found)


# yekamus: "Cuando salga del juego, puedes Desterrarlo para buscar un Yekamus en tu Castillo y ponerlo
# en tu mano."
static func _yekamus(main: Node, s: Dictionary, proxy: Node) -> void:
	if not await _confirm(main, s.ctrl, "%s salió del juego" % s.name, "Desterrarlo para buscar otro en tu Castillo"):
		return
	if not await _banish_self(s):
		return
	await ActionModule.search(s.ctrl, Constants.Zone.CASTILLO, {"name_contains": "yekamus"}, 1, true, false, false,
		proxy, Constants.Zone.MANO)


# los farsarios: "Cuando salga del juego, puedes activar la habilidad de un Aliado en tu Destierro."
# Una habilidad activada que el compilador entiende entera ("(Una vez por turno,) puedes..."); la
# resuelve EffectInterpreter sobre un Nodo temporal con los datos de ese Aliado.
static func _farsarios(main: Node, s: Dictionary, proxy: Node) -> void:
	var exile: Array = CardManager.get_exile(s.ctrl)
	var entries: Array = []
	var clauses: Array = []
	for d in exile:
		var clause := _activated_clause(d) if int(d.get("tipo", -1)) == Constants.CardType.ALIADO else ""
		entries.append({"data": d, "eligible": not clause.is_empty()})
		clauses.append(clause)
	if not clauses.any(func(c): return not str(c).is_empty()):
		return
	var pools: Array = [{"is_own": true, "zone": Constants.Zone.DESTIERRO, "cards": entries, "exclusive": true}]
	var raw: Array = await ActionModule.pick_in_zones(s.ctrl,
		"%s: puedes activar la habilidad de un Aliado en tu Destierro" % s.name, pools, 0, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2 or int(raw[0][0]) != 0:
		return
	var ci := int(raw[0][1])
	if ci < 0 or ci >= entries.size() or not entries[ci].eligible:
		return
	var ally_s := {"data": entries[ci].data, "owner": s.ctrl, "ctrl": s.ctrl}
	var ally_proxy: Node = _proxy(main, ally_s)
	ally_proxy.current_zone = Constants.Zone.DESTIERRO
	main._update_debug("%s activa la habilidad de %s" % [s.name, str(entries[ci].data.get("nombre", ""))])
	await TriggerSystem._effect_interpreter.try_execute(ally_proxy, clauses[ci], s.ctrl)
	if is_instance_valid(ally_proxy):
		ally_proxy.queue_free()


static func _activated_clause(data: Dictionary) -> String:
	var rx := RegEx.create_from_string("^(?:una vez por turno|hasta \\w+ veces por turno), ")
	for sentence in str(data.get("habilidad", "")).split("."):
		var t := sentence.strip_edges()
		var plain := rx.sub(t.to_lower(), "")
		if not plain.begins_with("puedes"):
			continue
		var plan: Dictionary = EffectCompiler.compile_clause(plain)
		if plan.ok and EffectCompiler.is_executable(plan.steps):
			return plain
	return ""
