extends RefCounted
## LimitedEventTriggers — "(Hasta N veces / Una vez) por turno, cuando <evento>, ..." de cartas en juego (o en
## la zona que diga el texto) que el sistema de disparadores no ve: el parser las deja como activadas,
## pero no se activan, se disparan. Cada evento llega con fire(evento, datos) desde su punto real:
## - "ally_entered" / "gold_entered": EffectController.on_card_entered_play (conectado en GoldManager).
## - "card_played", "talisman_resolved": GoldManager._trigger_enter_play().
## - "damage": BattleManager._apply_castle_damage() (combate) y DamageManager.damage_dealt (directo).
## - "castle_searched": ActionSearch.pick_in_zones() (todo lo que busca en un Castillo pasa por ahí).
## - "effect_draw": ActionModule.draw(). "hand_loss": ActionModule.discard() y EnterPatterns._exile_from_hand().
## - "strength_gain": ContinuousEffectManager.register_modifier() (Fuerza sumada a un Aliado).
## - "ally_annulled": AllyEventTriggers.on_stopped(). "weapon_destroyed": CardManager.card_destroyed.
## - "to_zone" / "self_exiled": CardManager.card_put_in_cemetery / card_put_in_exile.
## Se resuelven en cola cuando no queda nada resolviéndose (CemeteryTriggers.is_idle()). El cupo se cuenta
## en RuleState ("evt:<handler>:<carta>", por turno). Solo corre en el Anfitrión; las elecciones van por
## SelectionManager / pick_in_zones, que ya llegan al Remoto.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")
const EnterScript = preload("res://scripts/core/effects/mechanics/EnterPatterns.gd")
const TalismanScript = preload("res://scripts/core/effects/mechanics/TalismanPatterns.gd")
const ActivatedScript = preload("res://scripts/core/effects/mechanics/ActivatedPatterns.gd")
const AttackScript = preload("res://scripts/core/effects/mechanics/AttackPatterns.gd")
const LeavePlayScript = preload("res://scripts/core/effects/triggers/LeavePlayPatterns.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")

## [frase (normalizada), evento, cupo por turno, handler, zonas extra donde también mira ("exile", "cemetery")]
const ENTRIES := [
	["cuando este u otro aliado entre en juego bajo tu control, pon la primera o ultima carta de tu castillo en tu mano", "ally_entered", 2, "_dato_paroi", []],
	["cuando este u otro aliado entre en juego bajo tu control, hasta tres veces por turno, este aliado gana 1 de fuerza", "ally_entered", 3, "_mr_hyde", []],
	["hasta dos veces por turno, puedes desterrar la primera carta de tu castillo para jugar un arma de tu mano o cementerio", "ally_entered", 2, "_oniwaban", []],
	["cuando este u otro aliado dragon entre en juego bajo tu control tu oponente bota tantas cartas como fuerza", "ally_entered", 2, "_lluhay", []],
	["cuando un oro entra en juego bajo tu control, hasta tres veces por turno, tu oponente bota tres cartas", "gold_entered", 3, "_gusano_blanco", []],
	["cuando juegues un totem, una vez por turno, puedes robar una carta", "card_played", 1, "_yaldabaoth", []],
	["cuando tu oponente juegue un talisman, hasta tres veces por turno, este aliado gana 2 de fuerza permanentemente", "card_played", 3, "_jane_eyre", []],
	["cuando uno de tus talismanes se resuelva, puedes pagar un oro para volver a jugarlo sin pagar su coste", "talisman_resolved", 99, "_baron_gossler", []],
	["hasta dos veces por turno, cuando recibas dano, puedes robar una carta", "damage", 2, "_yamabushi", []],
	["cuando se fuera a buscar cartas, destierra dos cartas del fondo de un castillo y hasta una carta de un cementerio", "castle_searched", 2, "_lilith", []],
	["cuando busques cartas en un castillo, tu oponente destierra dos cartas del tope de su castillo", "castle_searched", 1, "_calchona", []],
	["cuando busques cartas en el castillo oponente, tu oponente destierra la primera carta del tope de su castillo", "castle_searched", 1, "_invunche", []],
	["cuando busques una carta en el castillo oponente, este aliado gana 1 de fuerza permanentemente", "castle_searched", 3, "_hanuch", []],
	["cuando tu oponente ponga cartas en su mano por efectos, el bota esa misma cantidad de cartas", "effect_draw", 3, "_berserker_z", []],
	["si tu oponente descarta o destierra cartas de su mano por un efecto, tu robas tantas cartas como coste tenga esa carta", "hand_loss", 1, "_inari", []],
	["cuando un aliado gane fuerza permanentemente, puedes hacer que un aliado gane 1 de fuerza permanentemente", "strength_gain", 1, "_pirata_wokou", []],
	["cuando un aliado que controles gane fuerza, destierra hasta dos cartas de un cementerio", "strength_gain", 2, "_lobo_malvado", []],
	["cuando un aliado que controles gane fuerza por la habilidad de una carta que no sea dinosaurio megalosaurus", "strength_gain", 2, "_megalosaurus", []],
	["cuando tu oponente anule un aliado, puedes mostrar un arma de tu mano para poner ese aliado en juego como un aliado sin habilidad", "ally_annulled", 2, "_mundo_perdido", []],
	["cuando un aliado sea puesto en el cementerio o destierro oponente, puedes convertirlo en un aliado sin habilidad de coste y fuerza 1", "to_zone", 2, "_azathoth", []],
	["cuando este u otro aliado sea puesto en un destierro, tu oponente bota tres cartas", "to_zone", 1, "_ereshkigal", ["exile"]],
	["cuando una carta sea puesta en un destierro, una vez por turno, tu oponente bota tres cartas", "to_zone", 1, "_kushinada", []],
	["cuando tu oponente ponga cartas en su cementerio, puedes desterrar hasta dos cartas de su cementerio", "to_zone", 2, "_nefertiti", []],
	["cuando una de tus armas sea destruida puedes subirla a tu mano", "weapon_destroyed", 2, "_holmwood", ["cemetery"]],
	["cuando tu oponente afecte a aliados que controles, hasta dos veces por turno, destierra dos cartas del tope de su castillo", "ally_affected", 2, "_montanas_locura", []],
	# La propia carta, al llegar a tu Destierro.
	["cuando sea desterrado, puedes pagar un oro para robar dos cartas", "self_exiled", 99, "_lady_madeline", []],
	["cuando sea puesto en tu destierro por la habilidad de un aliado, puedes pagar un oro para que un oro oponente pierda su habilidad", "self_exiled", 99, "_carnacki", []],
	["cuando sea desterrado por un aliado, puedes pagar un oro para buscar un aliado en cada castillo, desterrarlos y robar una carta", "self_exiled", 99, "_perugia", []],
]

static var _inst = null
## Dinosaurio Megalosaurus: su propia ganancia no lo vuelve a disparar.
static var _suppress_megalosaurus: bool = false

var _pending: Array = []
var _running: bool = false


static func reset_match() -> void:
	"""MatchReset: cola nueva (una resolución a medias de la partida anterior no queda trabada)."""
	_inst = null
	_suppress_megalosaurus = false


static func _main() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func _logic_side() -> bool:
	return NetworkClient.room_code == "" or NetworkClient.is_host


static func _norm(t) -> String:
	return CemeteryTriggersScript.normalize(str(t))


static func _name(src) -> String:
	if src is Dictionary:
		return str(src.get("nombre", "Carta"))
	return str(src.get("card_name")) if is_instance_valid(src) else "Carta"


## Punto de entrada: anota el evento; los disparadores se resuelven después, en cola.
static func fire(event: String, args: Dictionary = {}) -> void:
	if not GameManager.is_game_active or not _logic_side():
		return
	if _inst == null:
		_inst = load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").new()
	_inst._collect(event, args)


func _collect(event: String, args: Dictionary) -> void:
	var main := _main()
	if not main:
		return
	if event == "self_exiled":
		var text := _norm(args.get("data", {}).get("habilidad", ""))
		var matched := false
		for e in ENTRIES:
			if e[1] == event and e[0] in text:
				matched = true
				_queue({"fn": e[3], "src": args.data, "ctrl": int(args.owner), "args": args, "limit": e[2], "key": "%s:%s" % [e[3], _name(args.data)]})
		# Sin entrada puntual: el genérico (ZoneSelfTriggers) compila el efecto (mu, yodo-dono, tadg, shinigami...).
		if not matched:
			var eff: String = load("res://scripts/core/effects/triggers/ZoneSelfTriggers.gd").exile_effect(args.data,
				args.get("by_ally", false), str(args.get("ally_race", "")))
			if not eff.is_empty():
				_queue({"fn": "_zone_self", "src": args.data, "ctrl": int(args.owner), "args": args.merged({"effect": eff}), "limit": 99,
					"key": "zone_self:%s" % _name(args.data)})
		return
	# Reglas con duración de cartas que ya no están en juego (RuleState, EffectInterpreter._apply_rule()).
	if event == "castle_searched" and int(args.owner) != int(args.searcher) and RuleState.active("search_toll", int(args.searcher)):
		_queue({"fn": "_search_toll", "src": {"nombre": "Tumulto Voraz"}, "ctrl": int(args.searcher), "args": args,
			"limit": 99, "key": "search_toll"})
	if event == "damage" and int(args.amount) > 0 and RuleState.active("zombie", int(args.pid)):
		_queue({"fn": "_zombie", "src": {"nombre": "Levantar Zombi"}, "ctrl": int(args.pid), "args": args,
			"limit": 99, "key": "zombie"})
	for e in ENTRIES:
		if e[1] != event:
			continue
		for pid in [0, 1]:
			for src in _sources(main, pid, e[0], e[4]):
				if _applies(e[3], src, pid, args):
					var id: String = str(src.get_instance_id()) if src is Node else "%s@%d" % [_name(src), pid]
					_queue({"fn": e[3], "src": src, "ctrl": pid, "args": args, "limit": e[2], "key": "%s:%s" % [e[3], id]})


## Cartas de 'pid' con la frase: en juego (líneas y Oros) y, si el texto lo dice, en su Destierro/Cementerio.
func _sources(main: Node, pid: int, phrase: String, extra: Array) -> Array:
	var out: Array = []
	var containers: Array = PlayerSideScript.line_containers(main, pid)
	containers.append(PlayerSideScript.gold_reserva(main, pid))
	containers.append(PlayerSideScript.oro_pagado(main, pid))
	for cont in containers:
		if not cont:
			continue
		for c in cont.get_children():
			if not is_instance_valid(c) or c.get("card_data") == null:
				continue
			if c.get("controller_id") != null and int(c.controller_id) != pid:
				continue
			if phrase in _norm(c.card_data.get("habilidad", "")) and not KeywordManager.is_silenced(c):
				out.append(c)
	if "exile" in extra:
		for d in CardManager.get_exile(pid):
			if phrase in _norm(d.get("habilidad", "")):
				out.append(d)
	if "cemetery" in extra:
		for d in CardManager.get_cemetery(pid):
			if phrase in _norm(d.get("habilidad", "")) and not CardManager.is_cemetery_card_silenced(d):
				out.append(d)
	return out


## ¿El evento le corresponde a esta carta (de 'pid')? Solo mira; no cambia nada.
func _applies(fn: String, src, pid: int, a: Dictionary) -> bool:
	match fn:
		"_dato_paroi", "_mr_hyde", "_oniwaban":
			return int(a.ctrl) == pid
		"_lluhay":
			return int(a.ctrl) == pid and is_instance_valid(a.card) and "dragon" in _norm(a.card.get("card_raza"))
		"_gusano_blanco":
			return int(a.ctrl) == pid
		"_yaldabaoth":
			return int(a.pid) == pid and a.card.get("card_type") == Constants.CardType.TOTEM
		"_jane_eyre":
			return int(a.pid) == 1 - pid and a.card.get("card_type") == Constants.CardType.TALISMAN
		"_baron_gossler":
			return int(a.pid) == pid
		"_yamabushi":
			return int(a.pid) == pid and int(a.amount) > 0
		"_lilith":
			return true
		"_calchona":
			return int(a.searcher) == pid
		"_invunche":
			return int(a.searcher) == pid and int(a.owner) != pid and GameManager.current_phase == Constants.Phase.VIGILIA \
				and GameManager.active_player_id == pid
		"_hanuch":
			return int(a.searcher) == pid and int(a.owner) != pid
		"_berserker_z":
			return int(a.pid) == 1 - pid and int(a.amount) > 0
		"_inari":
			return int(a.pid) == 1 - pid and bool(a.get("by_effect", false))
		"_pirata_wokou":
			return bool(a.permanent) and src != a.get("source")
		"_lobo_malvado":
			return CardQuery_controller(a.target) == pid
		"_megalosaurus":
			return CardQuery_controller(a.target) == pid and not _suppress_megalosaurus
		"_mundo_perdido":
			return int(a.pid) == pid
		"_azathoth":
			return int(a.owner) == 1 - pid and int(a.get("tipo", -1)) == Constants.CardType.ALIADO
		"_ereshkigal":
			return a.zone == "exile" and int(a.get("tipo", -1)) == Constants.CardType.ALIADO
		"_kushinada":
			return a.zone == "exile"
		"_nefertiti":
			return a.zone == "cemetery" and int(a.owner) == 1 - pid
		"_holmwood", "_montanas_locura":
			return int(a.pid) == pid
	return false


static func CardQuery_controller(c) -> int:
	if not is_instance_valid(c):
		return -1
	return int(c.controller_id) if c.get("controller_id") != null else int(c.get("owner_id")) if c.get("owner_id") != null else 0


func _queue(entry: Dictionary) -> void:
	_pending.append(entry)
	if not _running:
		_running = true
		_run.call_deferred()


func _run() -> void:
	var idle = TriggerSystem.get("_cemetery_triggers")
	while not _pending.is_empty():
		if idle and not await idle._wait_until_idle():
			break
		var e: Dictionary = _pending.pop_front()
		await _resolve(e)
	_pending.clear()
	_running = false


func _resolve(e: Dictionary) -> void:
	var main := _main()
	if not main:
		return
	var src = e.src
	if src is Node and (not is_instance_valid(src) or KeywordManager.is_silenced(src)):
		return
	var key: String = "evt:" + str(e.key)
	if RuleState.count(key, e.ctrl) >= int(e.limit):
		return
	RuleState.add(key, e.ctrl)
	if src is Node and await TriggerSystem.open_response_window(src, _name(src), e.ctrl):
		return
	main._update_debug("%s: se dispara" % _name(src))
	await call(e.fn, main, src, int(e.ctrl), e.args)


# =============================================================================
# HANDLERS
# =============================================================================
func _dato_paroi(main: Node, src, pid: int, _a: Dictionary) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var first := true
	if not PlayerSideScript.is_bot(pid) and deck.size() > 1:
		first = await SelectionManager.await_two_choice(main, _name(src), "La primera carta de tu Castillo", "La última carta de tu Castillo", pid)
	PlayerSideScript.put_in_hand(main, pid, deck.pop_front() if first else deck.pop_back())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


func _mr_hyde(_main_n: Node, src, _pid: int, _a: Dictionary) -> void:
	await TalismanScript._buff_turn(src, src, 1)


func _oniwaban(main: Node, src, pid: int, _a: Dictionary) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not await EnterScript._confirm(main, pid, _name(src), "Desterrar la primera carta de tu Castillo para jugar un Arma por un Oro menos"):
		return
	var top: Dictionary = deck.pop_front()
	top["esta_oculta"] = false
	CardManager.append_to_exile(pid, top)
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and ActivatedScript._payable(main, pid, price).call(d)
	var taken: Dictionary = await ActivatedScript._take_from_pools(main, pid, "%s: juega un Arma de tu mano o Cementerio por un Oro menos" % _name(src),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	await ActivatedScript._play_taken(main, pid, taken, price.call(taken.get("data", {})))


func _lluhay(_main_n: Node, src, pid: int, a: Dictionary) -> void:
	if not is_instance_valid(a.card):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(a.card))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(src))


func _gusano_blanco(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 3, false, _name(src))


func _yaldabaoth(main: Node, src, pid: int, _a: Dictionary) -> void:
	if await EnterScript._confirm(main, pid, _name(src), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(src), true)


func _jane_eyre(_main_n: Node, src, _pid: int, _a: Dictionary) -> void:
	await TalismanScript._buff_turn(src, src, 2, true)


func _baron_gossler(main: Node, src, pid: int, a: Dictionary) -> void:
	var name := str(a.get("name", ""))
	var owner: int = int(a.get("owner", pid))
	var cem: Array = CardManager.get_cemetery(owner)
	var data: Dictionary = {}
	for i in range(cem.size() - 1, -1, -1):
		if str(cem[i].get("nombre", "")) == name:
			data = cem[i]
			break
	if data.is_empty() or not main._gold_manager or not main._gold_manager.puede_pagar(1, -1, "", -1, pid):
		return
	if not await EnterScript._confirm(main, pid, _name(src), "Pagar un Oro para volver a jugar %s sin pagar su coste" % name):
		return
	if not await PlayerSideScript.pay(main, pid, 1) or not CardManager.take_from_cemetery(owner, data):
		return
	if not await TalismanScript._play_paying(main, pid, data, 0):
		CardManager.add_to_cemetery(owner, data)


func _yamabushi(main: Node, src, pid: int, _a: Dictionary) -> void:
	if await EnterScript._confirm(main, pid, _name(src), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(src), true)


func _lilith(main: Node, src, pid: int, _a: Dictionary) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: dos cartas del fondo de un Castillo" % _name(src), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	var picks: Array = await EnterScript._pick_cemetery(pid, [1 - pid, pid], "%s: hasta una carta de un Cementerio al Destierro" % _name(src), 0, 1)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			CardManager.append_to_exile(pk.owner, pk.data)


func _calchona(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 2, true, _name(src))


func _invunche(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 1, true, _name(src))


## tumulto voraz: "hasta tu próximo turno, cuando busques cartas en el Castillo oponente, tu oponente
## Destierra una carta del tope de su Castillo".
func _search_toll(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 1, true, _name(src))


## Levantar Zombi: "hasta tu próximo turno, cada vez que recibas daño oponente, tu oponente Bota esa misma
## cantidad y tú pones en juego un Aliado de un Cementerio como un Aliado sin habilidad".
func _zombie(main: Node, src, pid: int, a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, int(a.amount), false, _name(src))
	var gm = main.get("_gold_manager")
	if not gm:
		return
	var res: Dictionary = await ActionModule.search_either_owner(pid, [Constants.Zone.CEMENTERIO],
		{"type": Constants.CardType.ALIADO}, 1, true, null, -1)
	for p in [0, 1]:
		CardManager._update_cemetery_visual(p)
	for d in res.get("selected", []):
		var ally_data: Dictionary = (d as Dictionary).duplicate()
		ally_data["habilidad"] = ""
		ally_data["esta_oculta"] = false
		var node: Node = main._create_card(ally_data, false)
		node.owner_id = pid
		node.controller_id = pid
		main._connect_card_signals(node)
		await gm._play_card_to_field(node)


func _hanuch(_main_n: Node, src, _pid: int, _a: Dictionary) -> void:
	await TalismanScript._buff_turn(src, src, 1, true)


func _berserker_z(_main_n: Node, src, pid: int, a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, int(a.amount), false, _name(src))


func _inari(_main_n: Node, src, pid: int, a: Dictionary) -> void:
	var n: int = int(a.get("cost", 0))
	if n > 0:
		await ActionModule.draw(pid, n, _name(src), true)


func _pirata_wokou(main: Node, src, pid: int, _a: Dictionary) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza permanentemente" % _name(src), EnterScript._all_allies(main), true)
	if is_instance_valid(ally):
		await TalismanScript._buff_turn(ally, src, 1, true)


func _lobo_malvado(main: Node, src, pid: int, _a: Dictionary) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: ¿de qué Cementerio?" % _name(src), "Cementerio oponente", "Tu Cementerio", pid) else pid
	var picks: Array = await EnterScript._pick_cemetery(pid, [owner], "%s: hasta dos cartas al Destierro" % _name(src), 0, 2)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			CardManager.append_to_exile(pk.owner, pk.data)


func _megalosaurus(_main_n: Node, src, _pid: int, a: Dictionary) -> void:
	var target: Node = a.target
	if not is_instance_valid(target):
		return
	_suppress_megalosaurus = true
	await TalismanScript._buff_turn(target, src, 2)
	_suppress_megalosaurus = false
	KeywordManager.grant_keyword(target, Constants.Keyword.FURIA, src, "turn")


func _mundo_perdido(main: Node, src, pid: int, a: Dictionary) -> void:
	var weapons: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ARMA)
	var shown: Node = await EnterScript._pick_from(main, pid, "%s: muestra un Arma de tu mano para poner en juego %s" % [_name(src), str(a.name)], weapons, true)
	if not is_instance_valid(shown):
		return
	main._update_debug("%s: muestra %s" % [_name(src), EnterScript._name(shown)])
	var owner: int = int(a.get("owner", pid))
	for d in CardManager.get_cemetery(owner):
		if str(d.get("nombre", "")) == str(a.name):
			if CardManager.take_from_cemetery(owner, d):
				await LeavePlayScript._ally_from_data(main, d, owner, pid, null, int(d.get("fuerza", 0)), [], "")
			return


func _azathoth(main: Node, src, pid: int, a: Dictionary) -> void:
	var data: Dictionary = a.data
	var owner: int = int(a.owner)
	if not await EnterScript._confirm(main, pid, _name(src), "Convertir %s en tu Aliado de coste y Fuerza 1" % str(data.get("nombre", ""))):
		return
	if a.zone == "exile":
		var ex: Array = CardManager.get_exile(owner)
		if not (data in ex):
			return
		ex.erase(data)
		CardManager._emit_exile_changed(owner)
	elif not CardManager.take_from_cemetery(owner, data):
		return
	var blank: Dictionary = data.duplicate()
	blank["coste"] = 1
	# "de Raza a tu elección": queda con la suya.
	await LeavePlayScript._ally_from_data(main, blank, owner, pid, null, 1, [], "")


func _ereshkigal(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 3, false, _name(src))


func _kushinada(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 3, false, _name(src))


func _nefertiti(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [1 - pid], "%s: hasta dos cartas del Cementerio oponente al Destierro" % _name(src), 0, 2)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			CardManager.append_to_exile(pk.owner, pk.data)


func _holmwood(main: Node, src, pid: int, a: Dictionary) -> void:
	var cem: Array = CardManager.get_cemetery(pid)
	for i in range(cem.size() - 1, -1, -1):
		if str(cem[i].get("nombre", "")) == str(a.name):
			var d: Dictionary = cem[i]
			if await EnterScript._confirm(main, pid, _name(src), "Subir %s a tu mano" % str(a.name)) and CardManager.take_from_cemetery(pid, d):
				PlayerSideScript.put_in_hand(main, pid, d)
			return


func _montanas_locura(_main_n: Node, src, pid: int, _a: Dictionary) -> void:
	await ActionModule.mill(1 - pid, 2, true, _name(src))


func _pay_one(main: Node, pid: int, title: String, yes: String) -> bool:
	if not main._gold_manager or not main._gold_manager.puede_pagar(1, -1, "", -1, pid):
		return false
	if not await EnterScript._confirm(main, pid, title, yes):
		return false
	return await PlayerSideScript.pay(main, pid, 1)


func _lady_madeline(main: Node, src, pid: int, _a: Dictionary) -> void:
	if await _pay_one(main, pid, _name(src), "Pagar un Oro para Robar dos cartas"):
		await ActionModule.draw(pid, 2, _name(src), true)


func _zone_self(_main_node: Node, src, pid: int, a: Dictionary) -> void:
	"""Disparador genérico de la propia carta al llegar a tu Destierro (ZoneSelfTriggers)."""
	await load("res://scripts/core/effects/triggers/ZoneSelfTriggers.gd").run(src, pid, "exile", str(a.get("effect", "")))


func _carnacki(main: Node, src, pid: int, a: Dictionary) -> void:
	if not a.get("by_ally_ability", false):
		return
	var golds: Array = EnterScript._golds(main, [1 - pid])
	if golds.is_empty() or not await _pay_one(main, pid, _name(src), "Pagar un Oro: un Oro oponente pierde su habilidad"):
		return
	var g: Node = await EnterScript._pick_from(main, pid, "%s: un Oro oponente pierde su habilidad" % _name(src), golds, false)
	if is_instance_valid(g):
		await EnterScript._blank(g, null)


func _perugia(main: Node, src, pid: int, a: Dictionary) -> void:
	if not a.get("by_ally", false) or not await _pay_one(main, pid, _name(src), "Pagar un Oro para buscar un Aliado en cada Castillo"):
		return
	for owner in [1 - pid, pid]:
		var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: un Aliado para Desterrar" % _name(src),
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO, 0, 1, false)
		for d in picked:
			d["esta_oculta"] = false
			CardManager.append_to_exile(owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	await ActionModule.draw(pid, 1, _name(src), true)


# =============================================================================
# AYUDAS PARA LOS PUNTOS DE ENGANCHE
# =============================================================================
## CardManager.card_put_in_cemetery / card_put_in_exile.
static func on_card_to_zone(owner: int, data: Dictionary, zone: String) -> void:
	var a := {"owner": owner, "data": data, "zone": zone, "tipo": int(data.get("tipo", -1))}
	fire("to_zone", a)
	if zone == "exile":
		var ctx: Dictionary = EffectContextScript.current()
		var by_ally: bool = not ctx.is_empty() and is_instance_valid(ctx.get("card")) and ctx.card.get("card_type") == Constants.CardType.ALIADO
		var race: String = str(ctx.card.get("card_raza")) if by_ally else ""
		fire("self_exiled", {"owner": owner, "data": data, "by_ally": by_ally, "by_ally_ability": by_ally, "ally_race": race})


## EffectController.on_card_entered_play.
static func on_card_entered(pid: int, card) -> void:
	if not is_instance_valid(card):
		return
	var ctrl: int = int(card.controller_id) if card.get("controller_id") != null else pid
	if card.get("card_type") == Constants.CardType.ALIADO:
		fire("ally_entered", {"card": card, "ctrl": ctrl})
	elif card.get("card_type") == Constants.CardType.ORO:
		fire("gold_entered", {"card": card, "ctrl": ctrl})
