extends RefCounted
## EnterPatterns — "Cuando entra en juego" de una sola carta que el compilador no entiende pero que se
## arman con piezas que ya existen: inmunidad a salir del juego (garfio pirata, abd-el-kerim, Turiel),
## Oros sin habilidad (Ángel Barachiel, draig wych, sibila saint germain, la muerte, Zmeu Abismal,
## lucy), Botar/Desterrar/Descartar por cantidad (honengyo, Garras de Dragón, Lamec, jangseung,
## Baphomet, mr smee, mina maldita, smaragos, abadon, acuario, Auguste Dupin...), control y convertir
## (regan liberator, esfinge antartica, Lucy Westenra, jack, Rugiaevit, kokudaka, isabel riquelme,
## hitotsume kozo) y algunas más.
## Se usa con preload desde TriggerResolution (on_enter_play). La carta acaba de entrar: sigue en juego.

const RevealedCardsScript = preload("res://scripts/core/effects/mechanics/RevealedCards.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const ConvertScript = preload("res://scripts/core/effects/mechanics/ConvertPatterns.gd")
const AttackScript = preload("res://scripts/core/effects/mechanics/AttackPatterns.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")
const LeavePlayScript = preload("res://scripts/core/effects/triggers/LeavePlayPatterns.gd")

## Texto normalizado (CemeteryTriggers.normalize) -> función.
const KINDS := {
	"cuando entra en juego, el portador no puede salir del juego hasta tu proximo turno": "_garfio",
	"este y otro aliado que controles no pueden salir del juego hasta tu proximo turno": "_abd_el_kerim",
	"puedes hacer que un aliado oponente tenga fuerza 0 y no pueda salir del juego este turno": "_turiel",
	"tu oponente bota dos cartas y no puede jugar cartas por el turno": "_minamoto",
	"convierte la primera carta de un castillo en un oro sin habilidad y ponlo en tu oro pagado": "_barachiel",
	"pon la primera carta de tu castillo en tu oro pagado como un oro sin habilidad": "_draig",
	"cuando entra en juego, convierte un oro oponente en un oro sin habilidad": "_sibila",
	"convierte los oros en oros sin habilidad. las cartas de coste 3 o menos pierden su habilidad y destruyelas": "_la_muerte",
	"puedes convertir un oro en un oro sin habilidad y ganar su control": "_zmeu",
	"si tu oponente tiene ocho o mas cartas en su destierro, convierte dos oros oponentes en oros sin habilidad": "_lucy",
	"un jugador bota tantas cartas como oros haya en tu oro pagado": "_honengyo",
	"cada jugador bota tantas cartas como oros controle su oponente": "_garras",
	"puedes hacer que cada jugador destierre dos cartas de su mano": "_lamec",
	"cada jugador busca en su castillo dos cartas y las pone en su cementerio. si no lo hace, bota cinco cartas": "_jangseung",
	"tu oponente muestra una carta al azar de su mano y no la puede jugar hasta tu proximo turno": "_holmwood",
	"cuando entra en juego, destierra las cartas oponentes de coste 2 o menos": "_mina_maldita",
	"destruye o destierra hasta dos cartas oponentes de coste 3 o menos": "_smaragos",
	"roba tantas cartas como aliados de distinto coste controles": "_los_almas",
	"tu oponente bota tantas cartas como aliados controles o como fuerza tenga un aliado en juego": "_baphomet",
	"tu oponente bota tantas cartas como aliados controles y tu destierras dos cartas de su cementerio": "_mr_smee",
	"tu oponente elige un aliado que controle para que pierda su habilidad y sea destruido": "_diabolista",
	"tu oponente elige entre descartar dos cartas de su mano o destierrar una carta al azar de su mano": "_abadon",
	"un oponente muestra su mano y descarta todas las cartas de ahi que no sean aliado ni oro": "_acuario",
	"mira la mano de tu oponente y descarta los talismanes o totem de ahi": "_dupin",
	"cuando entra en juego, gana el control de las cartas de las que seas dueno": "_regan",
	"puedes convertir un aliado oponente de coste 2 o menos en un aliado sin habilidad y gana su control": "_esfinge",
	"puedes convertir una carta de coste 1 o menos en un aliado sombra de fuerza 0 y sin habilidad. gana su control": "_lucy_westenra",
	"si tu oponente tiene tres o mas cartas en su destierro, convierte un aliado oponente de coste 2 o menos en un aliado sombra sin habilidad de fuerza 1 y gana su control": "_jack",
	"tu oponente convierte una carta que controle que no sea oro en un totem sin habilidad y tu ganas su control": "_rugiaevit",
	"puedes convertir una carta oponente de coste 1 o menos, en una carta del mismo tipo sin habilidad": "_kokudaka",
	"convierte todas las cartas oponentes en cartas del mismo tipo sin habilidad": "_isabel",
	"puedes intercambiar el control de este aliado por un aliado oponente de coste 2 o menos": "_hitotsume",
	"juega hasta dos totem de tu cementerio, cuyos costes sumen 3 o menos, sin pagar su coste": "_monjas",
	"hasta dos heroes ganan 2 de fuerza hasta la fase final": "_heracles",
	"cuando entra en juego, puedes agrupar hasta dos oros que controles": "_veela",
	"si no controlas aliados de coste 1 o menos, puedes poner un oro de tu mano o cementerio en tu oro pagado": "_kuzuryu",
	# Segundo lote.
	"pon en juego bajo tu control la primera carta del castillo oponente como un aliado sombra sin habilidad de fuerza 3": "_mahishi",
	"elige hasta dos aliados para que hagan el doble de dano por el turno": "_shikhandi",
	"puedes subir una carta oponente de coste 2 o menos a la mano de su dueno": "_eurytus",
	"si no controlas mas aliados, bota dos cartas de tu castillo": "_los_umbras",
	"cuando entra en juego, puedes desterrar el cementerio de tu oponente": "_hospital",
	"pon dos cartas del tope o fondo de tu castillo en tu mano": "_escudo_energia",
	"busca hasta dos cartas en el castillo oponente y destierralas": "_templo_uppsala",
	"puedes buscar en el castillo oponente tantas cartas como aliados sombra controles y desterrarlas": "_orcus",
	"puedes buscar en un castillo un oro y ponerlo en tu oro pagado": "_libra",
	"destruye hasta dos cartas cuyos costes sumen hasta 3": "_calchona",
	"destierra hasta tres cartas cuyos costes sumen 4 o menos": "_hastur",
	"puedes desterrar hasta dos cartas cuyos costes sumen 2 o menos y robar una carta": "_yodo_dono",
	"cuando entra en juego, puedes desterrar hasta dos totem o armas": "_vaku",
	"destierra hasta tres aliados en la linea de ataque oponente": "_escorpio",
	"puedes robar tres cartas, descartar dos cartas de tu mano y desterrar tres cartas del tope de un castillo": "_chon_chon",
	"destierra hasta una carta de coste 1 o menos, hasta dos cartas de un cementerio y dos cartas del fondo de un castillo": "_samael",
	"tu oponente bota una carta por cada carta en la mano de un jugador a tu eleccion": "_tauro",
	"tu oponente bota tantas cartas como fuerza tenga un aliado que controles y por cada arma que controles": "_vordenburg",
	"si controlas siete o mas oros, tu oponente bota una carta por cada oro en juego": "_wyrm",
	"a tu oponente le cuesta un oro adicional jugar cartas o utilizar habilidades por el turno": "_randolph",
	"cuando entra en juego, nombra una carta. utilizar habilidades de la carta nombrada cuesta un oro adicional hasta tu proximo turno": "_serafin",
	"un aliado no puede salir del juego hasta tu proximo turno o hasta dos aliados cambian su habilidad por": "_cam",
	"hasta dos aliados de coste 2 o menos pierden su habilidad, ganan indestructible y tienen fuerza 0 por el turno": "_el_cazador",
	"un aliado no puede atacar o bloquear hasta la fase final de tu proximo turno": "_abdul",
	"hasta dos aliados ganan o pierden 2 a la fuerza permanentemente": "_altar",
	"convierte dos cartas de un cementerio y/o tope de un castillo en aliados de fuerza 2 sin habilidad y ponlos en juego": "_casimiro",
	"puedes poner bajo tu control hasta dos cartas de tu cementerio como aliados sin habilidad de fuerza 1": "_plaga_inmunda",
	"puedes robar hasta tantas cartas como coste tenga el portador": "_luthairon",
	"puedes buscar tres armas de distinto nombre en tu castillo o cementerio y ponerlas en tu mano": "_peacemaker",
	"puedes buscar en tu castillo un aliado imbloqueable o caballero, que no sea pipin el breve, o un arma de coste 2 o menos": "_pipin",
	"puedes buscar un arma de coste 2 en tu castillo y ponerla en un mano": "_morro_arica",
	"busca en cualquier castillo o cementerio un arma de coste 1 y juegala sin pagar su coste": "_solomon",
	"puedes cambiar de portador un arma que controles o subir un aliado o arma de tu cementerio a tu mano": "_roderick",
	"mira la mano de tu oponente. elige hasta un talisman o totem de ahi y destierralo": "_erlik",
	"cada jugador bota cuatro cartas. si se botaron oros, pon uno de ellos en tu oro pagado": "_daga_bandido",
	"puedes buscar un oro en tu castillo y ponerlo en tu mano. si entro en juego desde tu cementerio": "_directorium",
	"puedes barajar las demas cartas en juego que no sean oro": "_trentren",
	"puedes mirar las primeras tres cartas de tu castillo. pon una carta de ahi en tu mano, otra en tu cementerio y otra en tu destierro o fondo de tu castillo": "_polvo_hadas",
	"puedes mirar las primeras seis cartas de un castillo. si es el castillo oponente, pon tres cartas de ahi en su destierro": "_nombre_horus",
	"puedes pagar el coste de una carta para que pierda su habilidad y sea destruida": "_koromodako",
	"cada jugador muestra su mano. elige hasta dos talismanes y/o totem de la mano de tu oponente y destierralos": "_fujibayashi",
	"elige entre buscar en tu castillo un totem de coste 2 o menos y jugarlo por dos oros menos o agrupar dos oros": "_amaterasu",
	"si tu oponente tiene dos o mas oros en reserva, puedes generar un oro para jugar aliados": "_armadura_imperial",
	"cuando entre o salga del juego, roba dos cartas y descarta una carta": "_zmeoaica",
	# La otra Zmeoaica (custom_drac_038), otra carta jugable con el mismo nombre.
	"cuando entra en juego, muestra un aliado de coste 3 de tu mano para robar dos cartas": "_zmeoaica_drac",
	# Tercer lote.
	"muestra las primeras cinco cartas de tu castillo, pon una carta o dos armas y/o totem de ahi en tu mano": "_angelus",
	"puedes desterrar dos cartas del tope de tu castillo para buscar en tu castillo una copia de esta carta y jugarla sin pagar su coste": "_daga_bebedora",
	"cuando entra en juego o bloquee, puedes jugar un totem de tu mano o cementerio reduciendo su coste en un oro": "_van_helsing",
	"puedes buscar hasta dos aliados paladin o armas en tu castillo y ponerlas en tu mano o cementerio": "_paladin_esperanza",
	"puedes buscar dos aliados de distinto coste en tu castillo y/o cementerio y ponerlos en tu mano": "_calfucura",
	"muestra cartas de la parte superior de tu castillo hasta mostrar tres aliados sacerdote, pon dos en tu mano y destierra el otro": "_haquika",
	"cuando entra en juego, no recibes dano hasta tu proximo turno y puedes robar tres cartas": "_jupitris",
	"puedes mirar tantas cartas del tope de tu castillo como aliados haya en tu destierro. ordenalas y destierra la primera carta de tu castillo": "_tadg",
	"convierte hasta dos cartas de coste 2 o menos y/o cartas de los cementerios en totem sin habilidad de coste 5": "_valva_bailor",
	"un jugador muestra cartas del tope de su castillo hasta mostrar dos cartas de distinto tipo y las destierra": "_craneos_vivos",
	"hasta dos aliados cuyos costes sumen hasta 2 pierden su habilidad y no pueden atacar o bloquear hasta tu proxima fase final": "_illapa",
	"cuando entra en juego los demas oros pierden su habilidad hasta tu proximo turno": "_tukuturi",
	"cuando entra en juego, puedes convertir una carta en una del mismo tipo sin habilidad, hasta tu proximo turno": "_kingstead",
	"la primera carta de coste 1 o menos que ponga en juego cada jugador en cada turno, cuesta un oro adicional": "_argos",
	"nombra un tipo de carta que no sea oro ni aliado. las cartas de ese tipo cuestan un oro adicional": "_plaza_armas",
	"durante los proximos dos turnos, los jugadores solo pueden jugar una carta de cada tipo por turno": "_perugia",
	"el proximo talisman de coste 1 o menos que juegue tu oponente este turno es anulado": "_nuckelavee",
	"puedes utilizar la habilidad de un totem de coste 2 o menos como si estuviera entrando en juego o generar un oro para jugar totem": "_monjes",
	"puedes disparar la habilidad de un aliado de coste 1 que controles, que no sea rey de los pajaros, como si estuviera entrando en juego": "_rey_pajaros",
	"puedes jugar un talisman de tu cementerio pagando su coste y destierralo": "_shakuhachi",
	"puedes elegir un arma de coste 2 o menos de tu cementerio y jugarla sin pagar su coste en un aliado caballero que controles": "_felipe_augusto",
	"si lo hizo desde tu mano, puedes poner en juego un aliado de coste 4 o menos, desde tu mano o cementerio": "_kiyohime",
	"si entro en juego desde tu mano y no controlas aliados de coste 1 o menos, puedes desterrar hasta una carta oponente de cada tipo": "_ikuchi",
	# Inmunidad a efectos oponentes.
	"puedes robar hasta dos cartas y no puedes ser afectado por efectos oponentes hasta tu proximo turno": "_peter_pan",
	# Oros que ganan o reciben una habilidad.
	"puedes convertir un oro oponente en un oro con la habilidad": "_tres_pascualas",
	"puedes convertir una carta de coste 2 o menos en un oro con la habilidad": "_gokin",
	"elige un aliado oponente para que deba atacar o bloquear este turno si puede": "_juzumaru",
	"para jugar un aliado de coste 2 o menos, debe lanzarse un dado de seis caras": "_manicomio",
	"elige una carta para que a tu oponente le cueste un oro adicional afectarla hasta tu proximo turno": "_corazon_muerte",
	"puedes mostrar las tres primeras cartas de tu castillo y poner un aliado de coste 1 o menos o con furia, o un arma de ahi en tu mano": "_amuleto_serpiente",
	"un oro oponente no puede ser agrupado y una carta no puede utilizar sus habilidades, el proximo turno": "_lanza_juramento",
	"busca un oto en tu castillo y ponlo en tu mano o muestra tu mano y si no tienes mas de un talisman": "_trofeo_cazador",
	"destruye hasta tantas cartas oponentes de coste 2 o menos como oros hayas pagado por este aliado mas uno": "_valac",
	"puedes hacer que un oro que controles gane las habilidades de un oro oponente o buscar un arma en tu castillo y ponerla en tu mano": "_canaan",
	"puedes jugar una carta de tu mano o cementerio reduciendo su coste en un oro, hasta un minimo de 0 y el portador no puede ser afectado por efectos oponentes": "_revolver_webley",
}


static func _kind(full_text: String) -> String:
	var t := CemeteryTriggersScript.normalize(full_text)
	for k in KINDS:
		if k in t:
			return KINDS[k]
	return ""


static func handles(full_text: String) -> bool:
	return not _kind(full_text).is_empty()


## libra ("Cuando entra en juego o salga del juego") y zmeoaica ("Cuando entre o salga del juego"): lo
## mismo al salir (no usan la carta que sale).
const LEAVE_TOO := ["_libra", "_zmeoaica"]


static func handles_leave(full_text: String) -> bool:
	return _kind(full_text) in LEAVE_TOO


static func try_execute(card: Node, full_text: String, controller_id: int) -> bool:
	var fn := _kind(full_text)
	if fn.is_empty() or not is_instance_valid(card):
		return false
	var main := CardQuery.main_node()
	if not main:
		return true
	var pid: int = CardQuery.controller_of(card) if card.get("controller_id") != null else controller_id
	await load("res://scripts/core/effects/mechanics/EnterPatterns.gd").call(fn, main, card, pid)
	return true


# =============================================================================
# AYUDAS
# =============================================================================
static func _name(card) -> String:  # sin tipo: puede llegar ya liberada
	return str(card.get("card_name")) if is_instance_valid(card) else "Carta"


static func _window(card: Node, pid: int) -> bool:
	return await TriggerSystem.open_response_window(card, _name(card), pid)


static func _confirm(main: Node, pid: int, title: String, yes: String) -> bool:
	if PlayerSideScript.is_bot(pid):
		return true
	return await SelectionManager.await_two_choice(main, title, yes, "No", pid)


## Cartas en juego (líneas, sin Oros) de 'side' que pasen 'filter'.
static func _in_play(main: Node, side: int, filter: Callable = Callable()) -> Array:
	var out: Array = []
	for container in PlayerSideScript.line_containers(main, side):
		for c in container.get_children():
			if is_instance_valid(c) and CardQuery.controller_of(c) == side and (not filter.is_valid() or filter.call(c)):
				out.append(c)
	return out


static func _golds(main: Node, sides: Array) -> Array:
	var out: Array = []
	for side in sides:
		for zone in [PlayerSideScript.gold_reserva(main, side), PlayerSideScript.oro_pagado(main, side)]:
			if zone:
				for g in zone.get_children():
					if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO:
						out.append(g)
	return out


static func _pick_from(main: Node, chooser: int, prompt: String, cards: Array, optional: bool) -> Node:
	if cards.is_empty():
		return null
	if PlayerSideScript.is_bot(chooser) or not main.get("_card_interaction"):
		return cards[0]
	return await main._card_interaction.await_target(prompt, func(c: Node) -> bool: return c in cards, optional, chooser)


static func _pick_many(main: Node, chooser: int, prompt: String, cards: Array, count: int, optional: bool) -> Array:
	if cards.is_empty():
		return []
	if PlayerSideScript.is_bot(chooser) or not main.get("_card_interaction"):
		return cards.slice(0, count)
	return await main._card_interaction.await_multi_target(prompt, cards, count, Callable(), Callable(), optional, null, chooser)


## Convertir en "sin habilidad" sin cambiar el tipo (Oros y cartas en juego).
static func _blank(node: Node, source: Node) -> void:
	if not is_instance_valid(node) or await ConvertScript.conversion_prevented(node, source):
		return
	node.is_converted = true
	await KeywordManager.silence_card(node, source, "permanent", true)


static func _cost(c: Node) -> int:
	return int(ContinuousEffectManager.get_modified_cost(c))


static func _hand(main: Node, pid: int) -> Array:
	return PlayerSideScript.hand_cards(main, pid).filter(func(c): return is_instance_valid(c))


static func _exile_from_hand(main: Node, pid: int, cards: Array) -> void:
	# duelo mágico: "ni Descartar y/o Desterrar más de una carta de su mano por turno".
	if RuleState.active("hand_loss_cap_1", pid):
		cards = cards.slice(0, maxi(0, 1 - RuleState.count("hand_cards_lost", pid)))
		RuleState.add("hand_cards_lost", pid, cards.size())
	var lost_cost: int = int(cards[0].get("card_cost")) if not cards.is_empty() and is_instance_valid(cards[0]) and cards[0].get("card_cost") != null else 0
	for c in cards:
		var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, c)
		if not data.is_empty():
			CardManager.append_to_exile(pid, data)
	if not cards.is_empty():
		load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("hand_loss", {"pid": pid, "cost": lost_cost, "by_effect": true})  # inari


## "Sube X a la mano de su dueño": sale del juego (Prevención, sus Armas al Cementerio, dispara "cuando
## salga del juego", como EffectController.destroy_card) y vuelve a la mano de su dueño. No para Oros.
static func bounce_to_owner_hand(main: Node, node: Node, source: Node) -> bool:
	if not is_instance_valid(node) or not (node.get("current_zone") in Constants.ZONES_IN_PLAY) \
			or node.get("card_type") == Constants.CardType.ORO:
		return false
	var owner: int = int(node.owner_id) if node.get("owner_id") != null else CardQuery.controller_of(node)
	if await EffectController._try_consume_leave_play_prevention(owner, node, source):
		return false
	var weapons = node.get("equipped_weapons")
	if weapons is Array:
		for w in weapons.duplicate():
			if is_instance_valid(w):
				await CardManager.destroy_card(int(w.owner_id) if w.get("owner_id") != null else owner, w)
	var wielder = node.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(node)
	var from_zone = node.get("current_zone")
	if node.has_method("on_left_play"):
		node.on_left_play()
	KeywordManager.clear_all_for_card(node)
	EffectController.clear_conversion_on_leave(node)
	var data: Dictionary = node.card_data.duplicate()
	EffectController.emit_signal("on_card_left_play", CardQuery.controller_of(node), node, from_zone)
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		CardManager._disconnect_card_interaction_signals(node)
		node.queue_free()
	PlayerSideScript.put_in_hand(main, owner, data)
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)
	main._update_debug("%s vuelve a la mano de su dueño" % str(data.get("nombre", "")))
	return true


## Un Oro sin habilidad en el Oro Pagado de 'pid' a partir de unos datos (Ángel Barachiel, draig wych).
static func _data_to_paid_gold(main: Node, data: Dictionary, owner: int, pid: int) -> void:
	var gold_data: Dictionary = data.duplicate()
	gold_data["tipo"] = Constants.CardType.ORO
	gold_data["habilidad"] = ""
	var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, gold_data)
	if is_instance_valid(gold):
		gold.owner_id = owner
		gold.is_converted = true
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# =============================================================================
# CARTAS
# =============================================================================
static func _garfio(main: Node, card: Node, pid: int) -> void:
	var wielder = card.get_parent()
	if not is_instance_valid(wielder) or not (wielder.get("equipped_weapons") is Array) or await _window(card, pid):
		return
	EffectController.add_single_card_leave_play_immunity(wielder, pid)
	main._update_debug("%s: %s no puede salir del juego hasta tu próximo turno" % [_name(card), _name(wielder)])


static func _abd_el_kerim(main: Node, card: Node, pid: int) -> void:
	var others := _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO)
	var other: Node = await _pick_from(main, pid, "%s: elige otro Aliado que controles" % _name(card), others, false)
	if await _window(card, pid):
		return
	for c in [card, other]:
		if is_instance_valid(c):
			EffectController.add_single_card_leave_play_immunity(c, pid)
	main._update_debug("%s: no pueden salir del juego hasta tu próximo turno" % _name(card))


static func _turiel(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Un Aliado oponente queda con Fuerza 0"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente" % _name(card), rivals, true)
	if not target or await _window(card, pid) or not is_instance_valid(target):
		return
	ContinuousEffectManager.register_modifier({
		"source": target, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": 0, "operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
		"description": "%s: Fuerza 0" % _name(card),
	})
	target.set_meta("no_leave_turn", GameManager.turn_serial)  # EffectController._try_consume_leave_play_prevention
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()


static func _minamoto(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	await ActionModule.mill(1 - pid, 2, false, _name(card))
	if main._gold_manager:
		main._gold_manager.set_no_more_cards_this_turn(1 - pid)


static func _barachiel(main: Node, card: Node, pid: int) -> void:
	var zone_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		zone_owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: la primera carta de un Castillo pasa a tu Oro Pagado" % _name(card),
			"Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(zone_owner)
	if deck.is_empty() or not main._gold_manager or await _window(card, pid):
		return
	await _data_to_paid_gold(main, deck.pop_front(), zone_owner, pid)


static func _draig(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not main._gold_manager or await _window(card, pid):
		return
	await _data_to_paid_gold(main, deck.pop_front(), pid, pid)


static func _sibila(main: Node, card: Node, pid: int) -> void:
	var golds := _golds(main, [1 - pid]).filter(func(g): return g.get("is_converted") != true)
	var gold: Node = await _pick_from(main, pid, "%s: elige un Oro oponente: queda sin habilidad" % _name(card), golds, false)
	if gold and not await _window(card, pid):
		await _blank(gold, card)


static func _la_muerte(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for g in _golds(main, [0, 1]):
		await _blank(g, card)
	var doomed: Array = []
	for side in [0, 1]:
		doomed.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
			and ContinuousEffectManager.cost_at_most(c, 3)))
	for c in doomed:
		await _blank(c, card)
	if not doomed.is_empty():
		await ActionModule.destroy(doomed, card, true)


static func _zmeu(main: Node, card: Node, pid: int) -> void:
	var golds := _golds(main, [1 - pid, pid])
	if golds.is_empty() or not await _confirm(main, pid, _name(card), "Convertir un Oro y ganar su control"):
		return
	var gold: Node = await _pick_from(main, pid, "%s: elige un Oro" % _name(card), golds, true)
	if not gold or await _window(card, pid) or not is_instance_valid(gold):
		return
	await _blank(gold, card)
	ContinuousEffectManager.gain_control_of_card(gold, pid)


static func _lucy(main: Node, card: Node, pid: int) -> void:
	if CardManager.get_exile(1 - pid).size() < 8:
		return
	var golds := _golds(main, [1 - pid]).filter(func(g): return g.get("is_converted") != true)
	var chosen: Array = await _pick_many(main, pid, "%s: dos Oros oponentes quedan sin habilidad" % _name(card), golds, 2, false)
	if chosen.is_empty() or await _window(card, pid):
		return
	for g in chosen:
		await _blank(g, card)


static func _honengyo(main: Node, card: Node, pid: int) -> void:
	var n: int = _golds(main, [pid]).filter(func(g): return g.get_parent() == PlayerSideScript.oro_pagado(main, pid)).size()
	var who: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		who = 1 - pid if await SelectionManager.await_two_choice(main, "%s: un jugador Bota %d carta(s)" % [_name(card), n],
			"Tu oponente", "Tú", pid) else pid
	if await _window(card, pid):
		return
	if n > 0:
		await ActionModule.mill(who, n, false, _name(card))
	await TriggerSystem._effect_interpreter.try_execute(card, "puedes subir hasta un aliado y un oro de tu cementerio a tu mano", pid)


static func _garras(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var milled_gold := false
	for p in [pid, 1 - pid]:
		var n: int = _golds(main, [1 - p]).size()
		if n <= 0:
			continue
		var res: Dictionary = await ActionModule.mill(p, n, false, _name(card))
		for d in res.get("cards", []):
			if d is Dictionary and int(d.get("tipo", -1)) == Constants.CardType.ORO:
				milled_gold = true
	if not milled_gold or not main._gold_manager:
		return
	var pools: Array = []
	var owners: Array = []
	for p in [pid, 1 - pid]:
		var entries: Array = []
		for d in CardManager.get_cemetery(p):
			entries.append({"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.ORO})
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true})
		owners.append(p)
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: pon un Oro de un Cementerio en tu Oro Pagado" % _name(card), pools, 1, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var data: Dictionary = pools[pi].cards[ci].data
	if CardManager.take_from_cemetery(owners[pi], data):
		var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, data)
		if is_instance_valid(gold):
			gold.owner_id = owners[pi]


static func _lamec(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Cada jugador Destierra dos cartas de su mano") or await _window(card, pid):
		return
	for p in [pid, 1 - pid]:
		var hand := _hand(main, p)
		if hand.size() > 2:
			if PlayerSideScript.is_bot(p):
				hand.sort_custom(func(a, b): return int(a.get("card_cost")) < int(b.get("card_cost")))
			hand = await _pick_many(main, p, "%s: Destierra dos cartas de tu mano" % _name(card), hand, 2, false)
		_exile_from_hand(main, p, hand.slice(0, 2))


static func _jangseung(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for p in [pid, 1 - pid]:
		var picked: Array = []
		if CardManager.get_deck(p).size() >= 2:
			picked = await AttackScript._pick_from_castle(p, p, "%s: busca dos cartas en tu Castillo para tu Cementerio" % _name(card),
				func(_d): return true, 2, 2, false)
		for d in picked:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(p, d)
		if picked.size() < 2:
			await ActionModule.mill(p, 5, false, _name(card))
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _holmwood(main: Node, card: Node, pid: int) -> void:
	var hand := _hand(main, 1 - pid)
	if hand.is_empty() or not main._gold_manager or await _window(card, pid):
		return
	var shown: Node = hand.pick_random()
	main._gold_manager.lock_card_from_playing(shown, pid)
	main._update_debug("%s: tu oponente muestra %s y no puede jugarla hasta tu próximo turno" % [_name(card), _name(shown)])


static func _mina_maldita(main: Node, card: Node, pid: int) -> void:
	var targets := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if targets.is_empty() or await _window(card, pid):
		return
	await ActionModule.banish(targets, card, true)


static func _smaragos(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3))
	if rivals.is_empty():
		return
	var destroy := true
	if not PlayerSideScript.is_bot(pid):
		destroy = await SelectionManager.await_two_choice(main, _name(card), "Destruir", "Desterrar", pid)
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos cartas oponentes de coste 3 o menos" % _name(card), rivals, 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	if destroy:
		await ActionModule.destroy(chosen, card, true)
	else:
		await ActionModule.banish(chosen, card, true)


static func _los_almas(main: Node, card: Node, pid: int) -> void:
	var costs: Dictionary = {}
	for c in _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		costs[_cost(c)] = true
	if costs.is_empty() or await _window(card, pid):
		return
	await ActionModule.draw(pid, costs.size(), _name(card), true)


static func _baphomet(main: Node, card: Node, pid: int) -> void:
	var by_allies: int = _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO).size()
	var all_allies: Array = []
	for side in [0, 1]:
		all_allies.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO))
	var n := by_allies
	if PlayerSideScript.is_bot(pid):
		for a in all_allies:
			n = maxi(n, int(ContinuousEffectManager.get_modified_strength(a)))
	elif not all_allies.is_empty() and not await SelectionManager.await_two_choice(main, _name(card),
			"Tantas como Aliados controlas (%d)" % by_allies, "Tantas como la Fuerza de un Aliado", pid):
		var a: Node = await _pick_from(main, pid, "%s: elige un Aliado en juego" % _name(card), all_allies, false)
		n = int(ContinuousEffectManager.get_modified_strength(a)) if is_instance_valid(a) else 0
	if n <= 0 or await _window(card, pid):
		return
	await ActionModule.mill(1 - pid, n, false, _name(card))


static func _mr_smee(main: Node, card: Node, pid: int) -> void:
	var n: int = _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO).size()
	if await _window(card, pid):
		return
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))
	var cem: Array = CardManager.get_cemetery(1 - pid)
	if cem.is_empty():
		return
	var entries: Array = cem.map(func(d): return {"data": d, "eligible": true})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: Destierra dos cartas del Cementerio oponente" % _name(card),
		[{"is_own": false, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], mini(2, cem.size()), 2)
	var picked: Array = []
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size():
			var d: Dictionary = entries[int(rp[1])].data
			if not picked.has(d) and picked.size() < 2:
				picked.append(d)
	for d in picked:
		if CardManager.take_from_cemetery(1 - pid, d):
			CardManager.append_to_exile(1 - pid, d)


static func _diabolista(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var allies := _in_play(main, opp, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if await _window(card, pid):
		return
	if not allies.is_empty():
		if PlayerSideScript.is_bot(opp):
			allies.sort_custom(func(a, b): return _cost(a) < _cost(b))
		var victim: Node = await _pick_from(main, opp, "%s: elige un Aliado que controles: pierde su habilidad y es Destruido" % _name(card),
			allies, false)
		if is_instance_valid(victim):
			await _blank(victim, card)
			await ActionModule.destroy([victim], card, true)
	if GameManager.active_player_id == opp:
		await ActionModule.mill(opp, 4, false, _name(card))


static func _abadon(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var hand := _hand(main, opp)
	if hand.is_empty() or await _window(card, pid):
		return
	var discard := hand.size() >= 2
	if not PlayerSideScript.is_bot(opp):
		discard = await SelectionManager.await_two_choice(main, _name(card), "Descartar dos cartas de tu mano",
			"Desterrar una carta al azar de tu mano", opp)
	if discard:
		var cards: Array = hand
		if hand.size() > 2:
			cards = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, 2, opp)
		await ActionModule.discard(opp, cards.slice(0, 2), _name(card), true)
	else:
		_exile_from_hand(main, opp, [hand.pick_random()])


static func _discard_from_opp_hand(main: Node, card: Node, pid: int, keep: Callable) -> void:
	var opp: int = 1 - pid
	var hand := _hand(main, opp)
	if not hand.is_empty() and not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	var gone: Array = hand.filter(func(c): return not keep.call(c))
	if gone.is_empty() or await _window(card, pid):
		return
	await ActionModule.discard(opp, gone, _name(card), true)


static func _acuario(main: Node, card: Node, pid: int) -> void:
	await _discard_from_opp_hand(main, card, pid, func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.ORO])


static func _dupin(main: Node, card: Node, pid: int) -> void:
	await _discard_from_opp_hand(main, card, pid, func(c): return not (c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM]))


static func _regan(main: Node, card: Node, pid: int) -> void:
	var mine: Array = []
	for container in PlayerSideScript.line_containers(main, 1 - pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("owner_id") != null and int(c.owner_id) == pid and CardQuery.controller_of(c) != pid:
				mine.append(c)
	for g in _golds(main, [1 - pid]):
		if g.get("owner_id") != null and int(g.owner_id) == pid:
			mine.append(g)
	if mine.is_empty() or await _window(card, pid):
		return
	for c in mine:
		if is_instance_valid(c):
			ContinuousEffectManager.gain_control_of_card(c, pid)


static func _esfinge(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Convertir un Aliado oponente y ganar su control"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, true)
	if not target or await _window(card, pid) or not is_instance_valid(target):
		return
	ContinuousEffectManager.gain_control_of_card(target, pid)
	await _blank(target, card)


## Lucy Westenra / jack: una carta en juego pasa a ser tu Aliado Sombra sin habilidad de Fuerza N.
static func _to_shadow_ally(main: Node, card: Node, pid: int, node: Node, strength: int) -> void:
	if not await ConvertScript._take_and_convert_in_play(node, pid, card):
		return
	node.card_raza = "Sombra"
	await ConvertScript._finish_conversion(node, card, pid, strength, [], false)
	main._update_debug("%s: %s es ahora tu Aliado Sombra de Fuerza %d sin habilidad" % [_name(card), _name(node), strength])


static func _lucy_westenra(main: Node, card: Node, pid: int) -> void:
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c != card and ContinuousEffectManager.cost_at_most(c, 1)))
	if targets.is_empty() or not await _confirm(main, pid, _name(card), "Convertir una carta de coste 1 o menos"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta de coste 1 o menos" % _name(card), targets, true)
	if target and not await _window(card, pid) and is_instance_valid(target):
		await _to_shadow_ally(main, card, pid, target, 0)


static func _jack(main: Node, card: Node, pid: int) -> void:
	if CardManager.get_exile(1 - pid).size() < 3:
		return
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, false)
	if target and not await _window(card, pid) and is_instance_valid(target):
		await _to_shadow_ally(main, card, pid, target, 1)


static func _rugiaevit(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var cards := _in_play(main, opp, func(c): return c.get("card_type") != Constants.CardType.ORO)
	if cards.is_empty() or await _window(card, pid):
		return
	if PlayerSideScript.is_bot(opp):
		cards.sort_custom(func(a, b): return _cost(a) < _cost(b))
	var chosen: Node = await _pick_from(main, opp, "%s: elige una carta que controles: pasa a ser un Tótem sin habilidad del oponente" % _name(card),
		cards, false)
	if is_instance_valid(chosen):
		await ConvertScript.convert_in_play_to_totem(chosen, card, pid)


static func _kokudaka(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return ContinuousEffectManager.cost_at_most(c, 1) and c.get("is_converted") != true)
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Dejar sin habilidad una carta oponente de coste 1 o menos"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta oponente de coste 1 o menos" % _name(card), rivals, true)
	if target and not await _window(card, pid):
		await _blank(target, card)


static func _isabel(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var all: Array = _in_play(main, 1 - pid) + _golds(main, [1 - pid])
	for c in all:
		await _blank(c, card)
	main._update_debug("%s: las cartas oponentes quedan sin habilidad" % _name(card))


static func _hitotsume(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Intercambiar el control con un Aliado oponente"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, true)
	if not target or await _window(card, pid) or not is_instance_valid(target) or not is_instance_valid(card):
		return
	ContinuousEffectManager.gain_control_of_card(target, pid)
	ContinuousEffectManager.gain_control_of_card(card, 1 - pid)


static func _monjas(main: Node, card: Node, pid: int) -> void:
	var entries: Array = []
	for d in CardManager.get_cemetery(pid):
		entries.append({"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.TOTEM and int(d.get("coste", 0)) <= 3})
	if not entries.any(func(e): return e.eligible) or not main._gold_manager:
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta dos Tótem de tu Cementerio cuyos costes sumen 3 o menos" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 2)
	var picked: Array = []
	var total := 0
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size() and entries[int(rp[1])].eligible:
			var d: Dictionary = entries[int(rp[1])].data
			if not picked.has(d) and total + int(d.get("coste", 0)) <= 3:
				picked.append(d)
				total += int(d.get("coste", 0))
	if picked.is_empty() or await _window(card, pid):
		return
	for d in picked:
		if CardManager.take_from_cemetery(pid, d):
			d["esta_oculta"] = false
			if not await main._gold_manager.play_card_for_free(d, pid):
				CardManager.add_to_cemetery(pid, d)


static func _heracles(main: Node, card: Node, pid: int) -> void:
	var heroes: Array = []
	for side in [pid, 1 - pid]:
		heroes.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
			and "heroe" in CemeteryTriggersScript.normalize(str(c.get("card_raza")))))
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Héroes ganan 2 de Fuerza" % _name(card), heroes, 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	for h in chosen:
		if is_instance_valid(h) and not await EffectController.offer_prevention(h, card, "strength_change"):
			ContinuousEffectManager.register_modifier({
				"source": h, "target": h, "type": ContinuousEffectManager.ModifierType.STRENGTH,
				"stat": "strength", "value": 2, "operation": "add",
				"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
				"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
				"description": "%s +2" % _name(card),
			})
			if h.has_method("refresh_strength_badge"):
				h.refresh_strength_badge()


static func _veela(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or PlayerSideScript.oro_pagado(main, pid).get_child_count() == 0:
		return
	if not await _confirm(main, pid, _name(card), "Agrupar hasta dos Oros") or await _window(card, pid):
		return
	await main._gold_manager.agrupar_oros(pid, 2)


static func _kuzuryu(main: Node, card: Node, pid: int) -> void:
	var small := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and c != card \
		and ContinuousEffectManager.cost_at_most(c, 1))
	if not small.is_empty():
		return
	await TriggerSystem._effect_interpreter.try_execute(card, "puedes poner un oro de tu mano o cementerio en tu oro pagado", pid)


# =============================================================================
# SEGUNDO LOTE
# =============================================================================
## Elige cartas de Cementerios (pick_in_zones). 'owners' = de quién se ofrecen. Devuelve [{owner, data}].
static func _pick_cemetery(pid: int, owners: Array, title: String, min_count: int, max_count: int,
		eligible: Callable = Callable()) -> Array:
	var pools: Array = []
	for p in owners:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": not eligible.is_valid() or eligible.call(d)})})
	if not pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		return []
	var raw: Array = await ActionModule.pick_in_zones(pid, title, pools, min_count, max_count)
	var out: Array = []
	for rp in raw:
		if not (rp is Array) or rp.size() != 2:
			continue
		var pi := int(rp[0])
		var ci := int(rp[1])
		if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			continue
		var d: Dictionary = pools[pi].cards[ci].data
		if out.size() < max_count and not out.any(func(o): return is_same(o.data, d)):
			out.append({"owner": owners[pi], "data": d})
	return out


## Cada jugador Bota per_player(jugador) cartas; si se Botaron Oros, uno de un Cementerio a tu Oro Pagado.
static func _mill_milled_gold_to_paid(main: Node, card: Node, pid: int, per_player: Callable) -> void:
	var milled_gold := false
	for p in [pid, 1 - pid]:
		var n: int = per_player.call(p)
		if n <= 0:
			continue
		var res: Dictionary = await ActionModule.mill(p, n, false, _name(card))
		for d in res.get("cards", []):
			if d is Dictionary and int(d.get("tipo", -1)) == Constants.CardType.ORO:
				milled_gold = true
	if not milled_gold or not main._gold_manager:
		return
	var picks := await _pick_cemetery(pid, [pid, 1 - pid], "%s: pon un Oro de un Cementerio en tu Oro Pagado" % _name(card), 1, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, pk.data)
			if is_instance_valid(gold):
				gold.owner_id = pk.owner


static func _set_strength_turn(target: Node, value: int, label: String) -> void:
	ContinuousEffectManager.register_modifier({
		"source": target, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": value, "operation": "set",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": label,
	})
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()


## Cam / el cazador: pierden su habilidad, ganan Indestructible y tienen Fuerza 0 por el turno.
static func _blank_indestructible_zero(card: Node, targets: Array) -> void:
	for t in targets:
		if not is_instance_valid(t):
			continue
		await KeywordManager.silence_card(t, card, "turn")
		KeywordManager.grant_keyword(t, Constants.Keyword.INDESTRUCTIBLE, card, "turn")
		_set_strength_turn(t, 0, "%s: Fuerza 0" % _name(card))


static func _all_allies(main: Node, filter: Callable = Callable()) -> Array:
	var out: Array = []
	for side in [0, 1]:
		out.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
			and (not filter.is_valid() or filter.call(c))))
	return out


static func _mahishi(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(1 - pid)
	if deck.is_empty() or await _window(card, pid):
		return
	var node: Node = await LeavePlayScript._ally_from_data(main, deck.pop_front(), 1 - pid, pid, card, 3, [], "Sombra")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	main._update_debug("%s: %s es ahora tu Aliado Sombra de Fuerza 3 sin habilidad" % [_name(card), _name(node)])


static func _shikhandi(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados hacen el doble de daño por el turno" % _name(card),
		_in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO), 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	for c in chosen:
		if is_instance_valid(c):
			c.set_meta("double_combat_damage_turn", GameManager.turn_serial)  # BattleManager


static func _eurytus(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Subir una carta oponente a la mano de su dueño"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta oponente de coste 2 o menos" % _name(card), rivals, true)
	if target and not await _window(card, pid):
		await bounce_to_owner_hand(main, target, card)


static func _los_umbras(main: Node, card: Node, pid: int) -> void:
	if not _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO).is_empty():
		return
	if not await _window(card, pid):
		await ActionModule.mill(pid, 2, false, _name(card))


static func _hospital(main: Node, card: Node, pid: int) -> void:
	var cem: Array = CardManager.get_cemetery(1 - pid)
	if cem.is_empty() or not await _confirm(main, pid, _name(card), "Desterrar el Cementerio de tu oponente") or await _window(card, pid):
		return
	for d in cem.duplicate():
		if CardManager.take_from_cemetery(1 - pid, d):
			CardManager.append_to_exile(1 - pid, d)


static func _escudo_energia(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or await _window(card, pid):
		return
	var from_top := true
	if not PlayerSideScript.is_bot(pid):
		from_top = await SelectionManager.await_two_choice(main, _name(card), "Del tope", "Del fondo", pid)
	for _i in mini(2, deck.size()):
		PlayerSideScript.put_in_hand(main, pid, deck.pop_front() if from_top else deck.pop_back())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _templo_uppsala(_main: Node, card: Node, pid: int) -> void:
	if CardManager.get_deck(1 - pid).is_empty() or await _window(card, pid):
		return
	await ActionModule.search(1 - pid, Constants.Zone.CASTILLO, {}, 2, true, false, false, card, Constants.Zone.DESTIERRO, false, pid)


static func _orcus(main: Node, card: Node, pid: int) -> void:
	var n: int = _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and "sombra" in CemeteryTriggersScript.normalize(str(c.get("card_raza")))).size()
	if n <= 0 or CardManager.get_deck(1 - pid).is_empty() \
			or not await _confirm(main, pid, _name(card), "Buscar %d carta(s) en el Castillo oponente" % n) or await _window(card, pid):
		return
	await ActionModule.search(1 - pid, Constants.Zone.CASTILLO, {}, n, true, false, false, card, Constants.Zone.DESTIERRO, false, pid)


static func _libra(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar un Oro en un Castillo para tu Oro Pagado") or await _window(card, pid):
		return
	await ActionModule.search_either_owner(pid, [Constants.Zone.CASTILLO], {"type": Constants.CardType.ORO}, 1, true, card,
		Constants.Zone.ORO_PAGADO)


static func _cost_sum_then(main: Node, card: Node, pid: int, count: int, max_sum: int, verb: String, optional: bool) -> Array:
	if optional and not await _confirm(main, pid, _name(card), "%s hasta %d cartas cuyos costes sumen %d o menos" % [verb, count, max_sum]):
		return []
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, count, max_sum,
		"%s: %s hasta %d cartas cuyos costes sumen %d o menos" % [_name(card), verb, count, max_sum])
	if chosen.is_empty() or await _window(card, pid):
		return []
	return chosen


static func _calchona(main: Node, card: Node, pid: int) -> void:
	var chosen := await _cost_sum_then(main, card, pid, 2, 3, "Destruye", false)
	if not chosen.is_empty():
		await ActionModule.destroy(chosen, card, true)


static func _hastur(main: Node, card: Node, pid: int) -> void:
	var chosen := await _cost_sum_then(main, card, pid, 3, 4, "Destierra", false)
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)


static func _yodo_dono(main: Node, card: Node, pid: int) -> void:
	var chosen := await _cost_sum_then(main, card, pid, 2, 2, "Desterrar", true)
	if chosen.is_empty():
		return
	await ActionModule.banish(chosen, card, true)
	await ActionModule.draw(pid, 1, _name(card), true)


static func _vaku(main: Node, card: Node, pid: int) -> void:
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.TOTEM))
		targets.append_array(CardQuery.weapons_in_play(side))
	targets = targets.filter(func(c): return is_instance_valid(c) and (not PlayerSideScript.is_bot(pid) or CardQuery.controller_of(c) != pid))
	var chosen: Array = await _pick_many(main, pid, "%s: puedes Desterrar hasta dos Tótem o Armas" % _name(card), targets, 2, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.banish(chosen, card, true)


static func _escorpio(main: Node, card: Node, pid: int) -> void:
	var lines: Array = PlayerSideScript.ally_containers(main, 1 - pid)
	if lines.size() < 2:
		return
	var targets: Array = lines[1].get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Array = await _pick_many(main, pid, "%s: Destierra hasta tres Aliados de la Línea de Ataque oponente" % _name(card), targets, 3, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.banish(chosen, card, true)


static func _discard_own(main: Node, card: Node, pid: int, count: int) -> void:
	var hand := _hand(main, pid)
	if hand.is_empty():
		return
	var to_discard: Array = hand
	if hand.size() > count:
		if PlayerSideScript.is_bot(pid):
			hand.sort_custom(func(a, b): return int(a.get("card_cost")) < int(b.get("card_cost")))
			to_discard = hand.slice(0, count)
		else:
			to_discard = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, count, pid)
	if not to_discard.is_empty():
		await ActionModule.discard(pid, to_discard.slice(0, count), _name(card), true)


static func _chon_chon(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Robar tres, Descartar dos y Desterrar tres del tope de un Castillo") or await _window(card, pid):
		return
	await ActionModule.draw(pid, 3, _name(card), true)
	await _discard_own(main, card, pid, 2)
	var castle_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		castle_owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	await ActionModule.mill(castle_owner, 3, true, _name(card))


static func _samael(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var small: Array = []
	for side in [1 - pid, pid]:
		small.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
			and ContinuousEffectManager.cost_at_most(c, 1)))
	var one: Array = await _pick_many(main, pid, "%s: Destierra hasta una carta de coste 1 o menos" % _name(card), small, 1, true)
	if not one.is_empty():
		await ActionModule.banish(one, card, true)
	var picks := await _pick_cemetery(pid, [1 - pid, pid], "%s: Destierra hasta dos cartas de un Cementerio" % _name(card), 0, 2)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			CardManager.append_to_exile(pk.owner, pk.data)
	var castle_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		castle_owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: dos cartas del fondo de un Castillo" % _name(card),
			"Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(castle_owner)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(castle_owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _tauro(main: Node, card: Node, pid: int) -> void:
	var mine: int = _hand(main, pid).size()
	var theirs: int = _hand(main, 1 - pid).size()
	var n: int = maxi(mine, theirs)
	if not PlayerSideScript.is_bot(pid):
		n = mine if await SelectionManager.await_two_choice(main, "%s: tu oponente Bota una carta por cada carta en la mano de…" % _name(card),
			"Tu mano (%d)" % mine, "Su mano (%d)" % theirs, pid) else theirs
	if n > 0 and not await _window(card, pid):
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _vordenburg(main: Node, card: Node, pid: int) -> void:
	var allies := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if PlayerSideScript.is_bot(pid):
		allies.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var ally: Node = await _pick_from(main, pid, "%s: elige un Aliado que controles (su Fuerza)" % _name(card), allies, false)
	var n: int = (int(ContinuousEffectManager.get_modified_strength(ally)) if is_instance_valid(ally) else 0) + CardQuery.weapons_in_play(pid).size()
	if n > 0 and not await _window(card, pid):
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _wyrm(main: Node, card: Node, pid: int) -> void:
	if _golds(main, [pid]).size() < 7:
		return
	var n: int = _golds(main, [0, 1]).size()
	if not await _window(card, pid):
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _randolph(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var opp: int = 1 - pid
	# Jugar cartas: oros_mas_modifiers se vacía al empezar el próximo turno. Habilidades: TriggerTollPatterns.
	PaymentManager.agregar_oros_mas(card, 1, func(c: Node) -> bool: return c.get("owner_id") != null and int(c.owner_id) == opp)
	RuleState.set_until("any_ability_toll", opp, GameManager.turn_serial + 1)
	main._update_debug("%s: a tu oponente le cuesta un Oro más jugar cartas o utilizar habilidades este turno" % _name(card))


static func _serafin(main: Node, card: Node, pid: int) -> void:
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var rivals := _in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return _cost(a) > _cost(b))
		named = _name(rivals[0]) if not rivals.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"%s: nombra una carta: utilizar sus habilidades cuesta un Oro más hasta tu próximo turno" % _name(card), pid)
		named = str(picked.get("nombre", ""))
	if named.is_empty() or await _window(card, pid):
		return
	for p in [0, 1]:
		RuleState.set_until("name_ability_toll:" + named.to_lower(), p, RuleState.next_own_turn(pid))
	main._update_debug("%s: utilizar habilidades de %s cuesta un Oro más hasta tu próximo turno" % [_name(card), named])


static func _cam(main: Node, card: Node, pid: int) -> void:
	var protect := true
	if not PlayerSideScript.is_bot(pid):
		protect = await SelectionManager.await_two_choice(main, _name(card), "Un Aliado no puede salir del juego",
			"Hasta dos Aliados: Indestructible, sin habilidad y Fuerza 0", pid)
	if protect:
		var ally: Node = await _pick_from(main, pid, "%s: un Aliado no puede salir del juego hasta tu próximo turno" % _name(card),
			_all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)), false)
		if is_instance_valid(ally) and not await _window(card, pid):
			EffectController.add_single_card_leave_play_immunity(ally, pid)
		return
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados" % _name(card), _all_allies(main), 2, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await _blank_indestructible_zero(card, chosen)


static func _el_cazador(main: Node, card: Node, pid: int) -> void:
	var targets := _all_allies(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	if PlayerSideScript.is_bot(pid):
		targets = targets.filter(func(c): return CardQuery.controller_of(c) != pid)
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados de coste 2 o menos" % _name(card), targets, 2, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await _blank_indestructible_zero(card, chosen)


static func _abdul(main: Node, card: Node, pid: int) -> void:
	var rivals := _all_allies(main, func(c): return CardQuery.controller_of(c) != pid or not PlayerSideScript.is_bot(pid))
	var target: Node = await _pick_from(main, pid,
		"%s: un Aliado no puede atacar ni bloquear hasta la Fase Final de tu próximo turno" % _name(card), rivals, false)
	if not is_instance_valid(target) or await _window(card, pid):
		return
	# Fines de turno hasta la Fase Final de tu próximo turno incluida.
	var turns: int = 3 if GameManager.active_player_id == pid else 2
	for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
		ContinuousEffectManager.register_modifier({
			"source": target, "target": target, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
			"restriction_type": restriction, "duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": turns,
			"description": "%s: no ataca ni bloquea" % _name(card),
		})


static func _altar(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await _pick_many(main, pid, "%s: hasta dos Aliados ganan o pierden 2 de Fuerza permanentemente" % _name(card),
		_all_allies(main), 2, true)
	if chosen.is_empty() or await _window(card, pid):
		return
	for c in chosen:
		if not is_instance_valid(c) or await EffectController.offer_prevention(c, card, "strength_change"):
			continue
		var gain: bool = CardQuery.controller_of(c) == pid
		if not PlayerSideScript.is_bot(pid):
			gain = await SelectionManager.await_two_choice(main, "%s: %s" % [_name(card), _name(c)], "Gana 2 de Fuerza", "Pierde 2 de Fuerza", pid)
		ContinuousEffectManager.register_modifier({
			"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 2 if gain else -2, "operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY, "description": "%s %+d" % [_name(card), 2 if gain else -2],
		})
		if c.has_method("refresh_strength_badge"):
			c.refresh_strength_badge()


static func _casimiro(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for i in 2:
		var source := 3  # 0 tu Cementerio, 1 Cementerio oponente, 2 tope de tu Castillo, 3 tope del Castillo oponente
		if not PlayerSideScript.is_bot(pid):
			source = await SelectionManager.await_choice(main, "%s: carta %d de 2, ¿de dónde?" % [_name(card), i + 1],
				["Tu Cementerio", "Cementerio oponente", "Tope de tu Castillo", "Tope del Castillo oponente"], pid)
		var owner: int = pid if source in [0, 2] else 1 - pid
		var data: Dictionary = {}
		if source >= 2:
			var deck: Array = CardManager.get_deck(owner)
			if deck.is_empty():
				continue
			data = deck.pop_front()
		else:
			var picks := await _pick_cemetery(pid, [owner], "%s: elige una carta del Cementerio" % _name(card), 1, 1)
			if picks.is_empty() or not CardManager.take_from_cemetery(owner, picks[0].data):
				continue
			data = picks[0].data
		await LeavePlayScript._ally_from_data(main, data, owner, pid, card, 2, [], "")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _plaga_inmunda(main: Node, card: Node, pid: int) -> void:
	var picks := await _pick_cemetery(pid, [pid], "%s: hasta dos cartas de tu Cementerio como Aliados de Fuerza 1 sin habilidad" % _name(card), 0, 2)
	if picks.is_empty() or await _window(card, pid):
		return
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			await LeavePlayScript._ally_from_data(main, pk.data, pid, pid, card, 1, [], "")


static func _luthairon(main: Node, card: Node, pid: int) -> void:
	var wielder = card.get_parent()
	var n: int = _cost(wielder) if is_instance_valid(wielder) and wielder.get("equipped_weapons") is Array else 0
	if n <= 0:
		return
	var amount := n
	if not PlayerSideScript.is_bot(pid):
		var options: Array = []
		for i in n + 1:
			options.append("Robar %d" % i)
		amount = await SelectionManager.await_choice(main, "%s: puedes Robar hasta %d cartas" % [_name(card), n], options, pid)
	if amount > 0 and not await _window(card, pid):
		await ActionModule.draw(pid, amount, _name(card), true)


static func _peacemaker(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar tres Armas de distinto nombre") or await _window(card, pid):
		return
	await ActionModule.search_zones(pid, [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO], {"type": Constants.CardType.ARMA}, 3, true,
		false, false, card, Constants.Zone.MANO, true)


static func _castle_to_hand(main: Node, card: Node, pid: int, title: String, eligible: Callable) -> void:
	if CardManager.get_deck(pid).is_empty() or not await _confirm(main, pid, _name(card), title) or await _window(card, pid):
		return
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: %s" % [_name(card), title], eligible, 0, 1, false)
	for d in picked:
		PlayerSideScript.put_in_hand(main, pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _pipin(main: Node, card: Node, pid: int) -> void:
	await _castle_to_hand(main, card, pid, "Buscar un Aliado Imbloqueable o Caballero, o un Arma de coste 2 o menos", func(d):
		var t := int(d.get("tipo", -1))
		if t == Constants.CardType.ARMA:
			return int(d.get("coste", 0)) <= 2
		return t == Constants.CardType.ALIADO and str(d.get("nombre", "")).to_lower() != "pipin el breve" \
			and ("imbloqueable" in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))) \
				or "caballero" in CemeteryTriggersScript.normalize(str(d.get("raza", "")))))


static func _morro_arica(main: Node, card: Node, pid: int) -> void:
	await _castle_to_hand(main, card, pid, "Buscar un Arma de coste 2",
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) == 2)


static func _solomon(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or await _window(card, pid):
		return
	var is_weapon_1 := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) == 1
	var pools: Array = []
	var where: Array = []
	for p in [pid, 1 - pid]:
		for zone in [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO]:
			var arr: Array = CardManager.get_deck(p) if zone == Constants.Zone.CASTILLO else CardManager.get_cemetery(p)
			pools.append({"is_own": p == pid, "zone": zone, "exclusive": true,
				"cards": arr.map(func(d): return {"data": d, "eligible": is_weapon_1.call(d)})})
			where.append({"owner": p, "zone": zone})
	var info: Dictionary = {}
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Arma de coste 1 de cualquier Castillo o Cementerio" % _name(card),
		pools, 1, 1, false, [], info)
	for ci in info.get("opened_castles", []):
		CardManager.shuffle_deck(where[ci].owner)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var idx := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or idx < 0 or idx >= pools[pi].cards.size() or not pools[pi].cards[idx].eligible:
		return
	var d: Dictionary = pools[pi].cards[idx].data
	var w: Dictionary = where[pi]
	if w.zone == Constants.Zone.CASTILLO:
		CardManager.get_deck(w.owner).erase(d)
		CardManager.shuffle_deck(w.owner)
	elif not CardManager.take_from_cemetery(w.owner, d):
		return
	d["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(d, pid):
		CardManager.add_to_cemetery(w.owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _roderick(main: Node, card: Node, pid: int) -> void:
	var weapons: Array = CardQuery.weapons_in_play(pid)
	var move := not weapons.is_empty()
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, _name(card),
			["Cambiar de portador un Arma", "Subir un Aliado o Arma de tu Cementerio a tu mano", "No"], pid)
		if pick < 0 or pick > 1:
			return
		move = pick == 0
	elif CardManager.get_cemetery(pid).any(func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA]):
		move = false
	if move:
		var w: Node = await _pick_from(main, pid, "%s: elige un Arma que controles" % _name(card), weapons, true)
		if not is_instance_valid(w) or not main._gold_manager:
			return
		var allies := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and c != w.get_parent())
		var new_wielder: Node = await _pick_from(main, pid, "%s: elige su nuevo portador" % _name(card), allies, true)
		if not is_instance_valid(new_wielder) or await _window(card, pid) or not is_instance_valid(w):
			return
		var old = w.get_parent()
		if old and old.get("equipped_weapons") is Array:
			old.equipped_weapons.erase(w)
		await main._gold_manager._equip_weapon(w, new_wielder, false)
		return
	var picks := await _pick_cemetery(pid, [pid], "%s: sube un Aliado o Arma de tu Cementerio a tu mano" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA])
	if picks.is_empty() or await _window(card, pid):
		return
	if CardManager.take_from_cemetery(pid, picks[0].data):
		PlayerSideScript.put_in_hand(main, pid, picks[0].data)


## Mira la mano rival (respetando Fisión Nuclear y Colapso Global) y elige hasta 'count' cartas que
## pasen 'filter' para Desterrarlas. 'who' = quien mira (por defecto pid).
static func _peek_banish(main: Node, card: Node, who: int, filter: Callable, count: int) -> void:
	var opp: int = 1 - who
	if EffectController.fision_hides_zones_of(opp, who, Constants.Zone.MANO) or await EffectController.offer_colapso_global(who):
		return
	var all: Array = _hand(main, opp)
	if all.is_empty():
		return
	if not PlayerSideScript.is_bot(who):
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), who)
	for _i in count:
		var options: Array = all.filter(func(c): return is_instance_valid(c) and filter.call(c))
		if options.is_empty():
			return
		var idx := 0
		if not PlayerSideScript.is_bot(who):
			var labels: Array = options.map(func(c): return _name(c))
			labels.append("Ninguna más")
			idx = await SelectionManager.await_choice(main, "%s: elige una carta para Desterrar" % _name(card), labels, who)
			if idx < 0 or idx >= options.size():
				return
		var chosen: Node = options[idx]
		all.erase(chosen)
		_exile_from_hand(main, opp, [chosen])


static func _erlik(main: Node, card: Node, pid: int) -> void:
	if not await _window(card, pid):
		await _peek_banish(main, card, pid, func(c): return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM], 1)


static func _fujibayashi(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var tt := func(c): return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM]
	await _peek_banish(main, card, pid, tt, 2)
	await _peek_banish(main, card, 1 - pid, tt, 2)  # luego tu oponente, de tu mano


static func _daga_bandido(main: Node, card: Node, pid: int) -> void:
	if not await _window(card, pid):
		await _mill_milled_gold_to_paid(main, card, pid, func(_p): return 4)


static func _directorium(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar un Oro en tu Castillo") or await _window(card, pid):
		return
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ORO}, 1, true, false, false, card)


static func _trentren(main: Node, card: Node, pid: int) -> void:
	var all: Array = []
	for side in [0, 1]:
		all.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO))
	if all.is_empty() or not await _confirm(main, pid, _name(card), "Barajar las demás cartas en juego que no sean Oro") or await _window(card, pid):
		return
	for c in all:
		if is_instance_valid(c):
			await PlayerSideScript.shuffle_into_castle(c, card, _name(card))


## Reparte cartas miradas (ya fuera del mazo) entre destinos, una por destino ("mano", "cementerio",
## "destierro", "fondo"). Lo que sobra vuelve al tope en el mismo orden.
static func _look_place(main: Node, card: Node, pid: int, owner: int, cards: Array, dests: Array) -> void:
	var left: Array = cards.duplicate()
	for dest in dests:
		if left.is_empty():
			break
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and left.size() > 1:
			var label: String = {"mano": "tu mano", "cementerio": "el Cementerio", "destierro": "el Destierro",
				"fondo": "el fondo del Castillo"}.get(dest, dest)
			idx = await SelectionManager.await_choice(main, "%s: ¿qué carta va a %s?" % [_name(card), label],
				left.map(func(d): return str(d.get("nombre", "?"))), pid)
			idx = clampi(idx, 0, left.size() - 1)
		var d: Dictionary = left.pop_at(idx)
		match dest:
			"mano":
				PlayerSideScript.put_in_hand(main, pid, d)
			"cementerio":
				d["esta_oculta"] = false
				CardManager.add_to_cemetery(owner, d)
			"destierro":
				d["esta_oculta"] = false
				CardManager.append_to_exile(owner, d)
			"fondo":
				d["esta_oculta"] = true
				CardManager.get_deck(owner).append(d)
	var deck: Array = CardManager.get_deck(owner)
	for i in range(left.size() - 1, -1, -1):
		deck.push_front(left[i])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _polvo_hadas(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not await _confirm(main, pid, _name(card), "Mirar las primeras tres cartas de tu Castillo") or await _window(card, pid):
		return
	var seen: Array = []
	for _i in mini(3, deck.size()):
		seen.append(deck.pop_front())
	var last := "destierro"
	if not PlayerSideScript.is_bot(pid):
		last = "destierro" if await SelectionManager.await_two_choice(main, _name(card), "La tercera, al Destierro",
			"La tercera, al fondo del Castillo", pid) else "fondo"
	await _look_place(main, card, pid, pid, seen, ["mano", "cementerio", last])


static func _nombre_horus(main: Node, card: Node, pid: int) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, "%s: puedes mirar las primeras seis cartas de un Castillo" % _name(card),
			["Castillo oponente", "Tu Castillo", "No"], pid)
		if pick < 0 or pick > 1:
			return
		owner = 1 - pid if pick == 0 else pid
	var deck: Array = CardManager.get_deck(owner)
	if deck.is_empty() or await _window(card, pid):
		return
	var seen: Array = []
	for _i in mini(6, deck.size()):
		seen.append(deck.pop_front())
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(seen, "%s: las primeras cartas" % _name(card), pid)
	await _look_place(main, card, pid, owner, seen,
		["destierro", "destierro", "destierro"] if owner != pid else ["mano", "cementerio", "cementerio"])


static func _koromodako(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
			and main._gold_manager.puede_pagar(_cost(c), -1, "", -1, pid)))
	if targets.is_empty() or not await _confirm(main, pid, _name(card), "Pagar el coste de una carta para Destruirla"):
		return
	if PlayerSideScript.is_bot(pid):
		targets = targets.filter(func(c): return CardQuery.controller_of(c) != pid)
		targets.sort_custom(func(a, b): return _cost(a) > _cost(b))
	var target: Node = await _pick_from(main, pid, "%s: elige una carta (pagas su coste)" % _name(card), targets, true)
	if not is_instance_valid(target) or not await PlayerSideScript.pay(main, pid, _cost(target)) or await _window(card, pid):
		return
	if is_instance_valid(target):
		await _blank(target, card)
		await ActionModule.destroy([target], card, true)


static func _amaterasu(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Tótem de coste 2 o menos y jugarlo por dos Oros menos",
			"Agrupar dos Oros", pid)
	if await _window(card, pid):
		return
	if search:
		await ActionModule.search_zones(pid, [Constants.Zone.CASTILLO], {"type": Constants.CardType.TOTEM, "cost_max": 2}, 1, true,
			false, true, card, Constants.Zone.MANO, false, -1, 2)
	elif main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 2)


static func _armadura_imperial(main: Node, card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(1 - pid) < 2 or not main._gold_manager:
		return
	if not await _confirm(main, pid, _name(card), "Generar un Oro para jugar Aliados") or await _window(card, pid):
		return
	main._gold_manager.generar_oro_virtual_restringido(1, func(t, _r, _c): return t == Constants.CardType.ALIADO,
		"%s: Oro para Aliados" % _name(card), pid)


static func _zmeoaica(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	await ActionModule.draw(pid, 2, _name(card), true)
	await _discard_own(main, card, pid, 1)


# Zmeoaica (custom_drac_038): "Cuando entra en juego, muestra un Aliado de coste 3 de tu mano para Robar
# dos cartas." Mostrarlo es el costo (opcional): sin uno, no Roba.
static func _zmeoaica_drac(main: Node, card: Node, pid: int) -> void:
	var shown: Node = await PlayerSideScript.pick_from_hand(main, pid,
		"%s: puedes mostrar un Aliado de coste 3 de tu mano para Robar dos cartas (N: no)" % _name(card),
		func(c): return c.get("card_type") == Constants.CardType.ALIADO and int(c.get("card_cost")) == 3)
	if not is_instance_valid(shown):
		return
	main._update_debug("%s: muestra %s" % [_name(card), _name(shown)])
	if CombatLog and CombatLog.has_method("log_action"):
		CombatLog.log_action("%s: muestra %s" % [_name(card), _name(shown)])
	if not await _window(card, pid):
		await ActionModule.draw(pid, 2, _name(card), true)


# =============================================================================
# TERCER LOTE
# =============================================================================
## Último turn_serial antes de tu próximo turno ("hasta tu próximo turno").
static func _until_before_next_turn(pid: int) -> int:
	return RuleState.next_own_turn(pid) - 1


## Elige una carta de una lista de datos con await_choice (el bot, la primera). -1 = ninguna.
static func _choose_data(main: Node, pid: int, title: String, datas: Array, allow_none: bool) -> int:
	if datas.is_empty():
		return -1
	if PlayerSideScript.is_bot(pid):
		return 0
	var labels: Array = datas.map(func(d): return str(d.get("nombre", "?")))
	if allow_none:
		labels.append("Ninguna")
	var idx: int = await SelectionManager.await_choice(main, title, labels, pid)
	return idx if idx >= 0 and idx < datas.size() else -1


static func _shuffle_back(main: Node, owner: int, datas: Array, label: String) -> void:
	var deck: Array = CardManager.get_deck(owner)
	for d in datas:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(owner)
	AnimationQueue.queue_shuffle(owner, "Barajar mazo (%s)" % label)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _angelus(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or await _window(card, pid):
		return
	var shown: Array = []
	for _i in mini(5, deck.size()):
		shown.append(deck.pop_front())
	RevealedCardsScript.record(pid, shown, _name(card))
	var is_wt := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ARMA, Constants.CardType.TOTEM]
	var wt: Array = shown.filter(is_wt)
	var two := wt.size() >= 2
	if not PlayerSideScript.is_bot(pid) and two:
		two = not await SelectionManager.await_two_choice(main, _name(card), "Una carta a tu mano", "Dos Armas y/o Tótem a tu mano", pid)
	var take: Array = []
	if two:
		for i in 2:
			var idx := await _choose_data(main, pid, "%s: Arma o Tótem %d de 2" % [_name(card), i + 1], wt, false)
			if idx >= 0:
				take.append(wt.pop_at(idx))
	else:
		var idx := await _choose_data(main, pid, "%s: una carta a tu mano" % _name(card), shown, false)
		if idx >= 0:
			take.append(shown[idx])
	for d in take:
		shown.erase(d)
		PlayerSideScript.put_in_hand(main, pid, d)
	await _shuffle_back(main, pid, shown, _name(card))


static func _daga_bebedora(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.size() < 2 or not main._gold_manager:
		return
	if not await _confirm(main, pid, _name(card), "Desterrar dos cartas del tope de tu Castillo para buscar otra copia") or await _window(card, pid):
		return
	for _i in 2:
		var d: Dictionary = deck.pop_front()
		d["esta_oculta"] = false
		CardManager.append_to_exile(pid, d)
	var name := str(card.get("card_name")).to_lower()
	var found: Dictionary = {}
	for d in deck:
		if str(d.get("nombre", "")).to_lower() == name:
			found = d
			break
	if not found.is_empty():
		deck.erase(found)
	await _shuffle_back(main, pid, [], _name(card))
	if found.is_empty():
		main._update_debug("%s: no hay otra copia en tu Castillo" % _name(card))
		return
	found["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(found, pid):
		CardManager.add_to_cemetery(pid, found)


## Dr. Van Helsing: "puedes jugar un Tótem de tu mano o Cementerio reduciendo su coste en un Oro, hasta un
## mínimo de 0".
static func _van_helsing(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.TOTEM and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)
	var hand_nodes: Array = _hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return
	if not await _confirm(main, pid, _name(card), "Jugar un Tótem de tu mano o Cementerio por un Oro menos"):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Tótem de tu mano o Cementerio" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var data: Dictionary = {}
	var from_hand: Node = null
	if int(raw[0][0]) == -1:
		var hi := int(raw[0][1])
		if hi < 0 or hi >= hand_nodes.size():
			return
		from_hand = hand_nodes[hi]
		data = from_hand.card_data
	else:
		var ci := int(raw[0][1])
		if ci < 0 or ci >= entries.size() or not entries[ci].eligible:
			return
		data = entries[ci].data
	if await _window(card, pid) or not await PlayerSideScript.pay(main, pid, price.call(data)):
		return
	if from_hand:
		data = PlayerSideScript.take_from_hand(main, pid, from_hand)
	elif not CardManager.take_from_cemetery(pid, data):
		return
	data["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(data, pid):
		CardManager.add_to_cemetery(pid, data)


static func _paladin_esperanza(main: Node, card: Node, pid: int) -> void:
	var ok := func(d) -> bool:
		var t := int(d.get("tipo", -1))
		return t == Constants.CardType.ARMA or (t == Constants.CardType.ALIADO and "paladin" in CemeteryTriggersScript.normalize(str(d.get("raza", ""))))
	if CardManager.get_deck(pid).is_empty() or not await _confirm(main, pid, _name(card), "Buscar hasta dos Aliados Paladín o Armas") \
			or await _window(card, pid):
		return
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: hasta dos Aliados Paladín o Armas" % _name(card), ok, 0, 2, false)
	var draws := 0
	for d in picked:
		var to_hand := true
		if not PlayerSideScript.is_bot(pid):
			to_hand = await SelectionManager.await_two_choice(main, str(d.get("nombre", "")), "A tu mano", "A tu Cementerio", pid)
		elif int(d.get("tipo", -1)) == Constants.CardType.ARMA:
			to_hand = false
		if to_hand:
			PlayerSideScript.put_in_hand(main, pid, d)
		else:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(pid, d)
			if int(d.get("tipo", -1)) == Constants.CardType.ARMA:
				draws += 1
	if draws > 0 and await _confirm(main, pid, _name(card), "Robar %d carta(s)" % draws):
		await ActionModule.draw(pid, draws, _name(card), true)


static func _calfucura(main: Node, card: Node, pid: int) -> void:
	if not await _confirm(main, pid, _name(card), "Buscar dos Aliados de distinto coste") or await _window(card, pid):
		return
	var used_cost := -1
	for i in 2:
		var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) != used_cost
		var pools: Array = [
			{"is_own": true, "zone": Constants.Zone.CASTILLO, "exclusive": false, "cards": CardManager.get_deck(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
			{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "exclusive": false, "cards": CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
		]
		var raw: Array = await ActionModule.pick_in_zones(pid, "%s: Aliado %d de 2 (de distinto coste)" % [_name(card), i + 1], pools, 0, 1)
		if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
			break
		var pi := int(raw[0][0])
		var ci := int(raw[0][1])
		if pi < 0 or pi > 1 or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
			break
		var d: Dictionary = pools[pi].cards[ci].data
		if pi == 0:
			CardManager.get_deck(pid).erase(d)
		elif not CardManager.take_from_cemetery(pid, d):
			break
		used_cost = int(d.get("coste", 0))
		PlayerSideScript.put_in_hand(main, pid, d)
	await _shuffle_back(main, pid, [], _name(card))


static func _haquika(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var is_priest := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and "sacerdote" in CemeteryTriggersScript.normalize(str(d.get("raza", "")))
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = []
	var priests: Array = []
	while not deck.is_empty() and priests.size() < 3:
		var d: Dictionary = deck.pop_front()
		shown.append(d)
		if is_priest.call(d):
			priests.append(d)
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	for d in priests:
		shown.erase(d)
	if priests.size() == 3:
		var idx := await _choose_data(main, pid, "%s: ¿qué Aliado Sacerdote se Destierra?" % _name(card), priests, false)
		var gone: Dictionary = priests.pop_at(maxi(idx, 0))
		gone["esta_oculta"] = false
		CardManager.append_to_exile(pid, gone)
	for d in priests:
		PlayerSideScript.put_in_hand(main, pid, d)
	await _shuffle_back(main, pid, shown, _name(card))
	# "No puedes recibir daño de combate hasta tu próximo turno" (RuleState, como Linaje Maldito).
	RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))


static func _jupitris(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for kind in ["no_combat_damage", "no_direct_damage"]:
		RuleState.set_until(kind, pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: no recibes daño hasta tu próximo turno" % _name(card))
	if await _confirm(main, pid, _name(card), "Robar tres cartas"):
		await ActionModule.draw(pid, 3, _name(card), true)


static func _tadg(main: Node, card: Node, pid: int) -> void:
	var n: int = CardManager.get_exile(pid).filter(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO).size()
	var deck: Array = CardManager.get_deck(pid)
	if n <= 0 or deck.is_empty() or not await _confirm(main, pid, _name(card), "Mirar %d carta(s) del tope de tu Castillo" % n) \
			or await _window(card, pid):
		return
	var seen: Array = []
	for _i in mini(n, deck.size()):
		seen.append(deck.pop_front())
	# Ordénalas: se eligen de arriba hacia abajo.
	var ordered: Array = []
	while not seen.is_empty():
		var idx: int = 0
		if seen.size() > 1:
			idx = maxi(await _choose_data(main, pid, "%s: ¿cuál va arriba? (%d de %d)" % [_name(card), ordered.size() + 1, n], seen, false), 0)
		ordered.append(seen.pop_at(idx))
	for i in range(ordered.size() - 1, -1, -1):
		deck.push_front(ordered[i])
	var top: Dictionary = deck.pop_front()
	top["esta_oculta"] = false
	CardManager.append_to_exile(pid, top)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _valva_bailor(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var made := 0
	while made < 2:
		var option := 0  # 0 en juego, 1 de un Cementerio, 2 listo
		if PlayerSideScript.is_bot(pid):
			option = 0 if made == 0 else 2
		else:
			option = await SelectionManager.await_choice(main, "%s: Tótem %d de 2" % [_name(card), made + 1],
				["Una carta de coste 2 o menos en juego", "Una carta de un Cementerio", "Listo"], pid)
		if option == 0:
			var targets: Array = []
			for side in [1 - pid, pid]:
				targets.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO \
					and ContinuousEffectManager.cost_at_most(c, 2)))
			var t: Node = await _pick_from(main, pid, "%s: elige una carta de coste 2 o menos" % _name(card), targets, true)
			if not is_instance_valid(t) or not await ConvertScript.convert_in_play_to_totem(t, card, pid):
				break
			t.card_cost = 5
		elif option == 1:
			var picks := await _pick_cemetery(pid, [pid, 1 - pid], "%s: una carta de un Cementerio" % _name(card), 0, 1)
			if picks.is_empty() or not CardManager.take_from_cemetery(picks[0].owner, picks[0].data):
				break
			var data: Dictionary = picks[0].data.duplicate()
			data["tipo"] = Constants.CardType.TOTEM
			data["coste"] = 5
			data["habilidad"] = ""
			data["esta_oculta"] = false
			var node: Node = main._create_card(data, false)
			node.owner_id = picks[0].owner
			node.controller_id = pid
			main._connect_card_signals(node)
			PlayerSideScript.line_containers(main, pid)[2].add_child(node)
			node.set_zone(Constants.Zone.LINEA_APOYO)
			node.can_interact = (pid == 0)
			node.is_converted = true
		else:
			break
		made += 1


static func _craneos_vivos(main: Node, card: Node, pid: int) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: un jugador muestra cartas del tope de su Castillo" % _name(card),
			"Tu oponente", "Tú", pid) else pid
	if CardManager.get_deck(owner).is_empty() or await _window(card, pid):
		return
	var deck: Array = CardManager.get_deck(owner)
	var shown: Array = []
	while not deck.is_empty():
		shown.append(deck.pop_front())
		if shown.size() >= 2 and int(shown[-1].get("tipo", -1)) != int(shown[0].get("tipo", -1)):
			break
	main._update_debug("%s muestra y Destierra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(owner, shown, _name(card))
	for d in shown:
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _illapa(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 2, 2, "%s: hasta dos Aliados cuyos costes sumen hasta 2" % _name(card))
	chosen = chosen.filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	if chosen.is_empty() or await _window(card, pid):
		return
	# Hasta tu próxima Fase Final (incluida).
	var own_turn: bool = GameManager.active_player_id == pid
	var until: int = GameManager.turn_serial + (2 if own_turn else 1)
	for c in chosen:
		c.set_meta("silenced_until", until)
		for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
			ContinuousEffectManager.register_modifier({
				"source": c, "target": c, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
				"restriction_type": restriction, "duration": ContinuousEffectManager.ModifierDuration.TIMED,
				"duration_value": 3 if own_turn else 2, "description": "%s: no ataca ni bloquea" % _name(card),
			})


static func _tukuturi(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for g in _golds(main, [0, 1]):
		if g != card:
			g.set_meta("silenced_until", _until_before_next_turn(pid))
	main._update_debug("%s: los demás Oros pierden su habilidad hasta tu próximo turno" % _name(card))


static func _kingstead(main: Node, card: Node, pid: int) -> void:
	var all: Array = []
	for side in [1 - pid, pid]:
		all.append_array(_in_play(main, side, func(c): return c != card))
	all.append_array(_golds(main, [1 - pid, pid]))
	if all.is_empty() or not await _confirm(main, pid, _name(card), "Dejar una carta sin habilidad hasta tu próximo turno"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta" % _name(card), all, true)
	if is_instance_valid(target) and not await _window(card, pid):
		target.set_meta("silenced_until", _until_before_next_turn(pid))


static func _argos(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	for p in [0, 1]:
		RuleState.set_until("argos_tax", p, RuleState.next_own_turn(pid))  # PaymentManager._static_type_and_cheap_surcharge
	main._update_debug("%s: la primera carta de coste 1 o menos de cada turno cuesta un Oro más" % _name(card))


const PLAZA_TYPES := [["Arma", Constants.CardType.ARMA], ["Tótem", Constants.CardType.TOTEM], ["Talismán", Constants.CardType.TALISMAN]]


static func _plaza_armas(main: Node, card: Node, pid: int) -> void:
	var idx := 2  # el bot nombra Talismán
	if not PlayerSideScript.is_bot(pid):
		idx = clampi(await SelectionManager.await_choice(main, "%s: nombra un tipo de carta" % _name(card),
			PLAZA_TYPES.map(func(p): return p[0]), pid), 0, PLAZA_TYPES.size() - 1)
	card.set_meta("named_type", PLAZA_TYPES[idx][1])  # PaymentManager._static_type_and_cheap_surcharge
	main._update_debug("%s: las cartas de tipo %s cuestan un Oro adicional" % [_name(card), PLAZA_TYPES[idx][0]])


static func _perugia(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	# "Durante los próximos dos turnos": el siguiente y el que le sigue (no el actual).
	for p in [0, 1]:
		RuleState.set_window("one_per_type", p, GameManager.turn_serial + 1, GameManager.turn_serial + 3)  # GoldManager._card_play_locked
	main._update_debug("%s: durante los próximos dos turnos, una carta de cada tipo por turno" % _name(card))


static func _nuckelavee(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	TriggerSystem._totem_patterns.register_kotoku_in_talisman_fizzle(1 - pid, 1)
	main._update_debug("%s: el próximo Talismán de coste 1 o menos de tu oponente este turno es Anulado" % _name(card))


## Dispara el "cuando entra en juego" de otra carta tuya (Monjes Ortodoxos, rey de los pájaros).
static func _retrigger_enter(card: Node, pid: int, target: Node) -> void:
	if not is_instance_valid(target):
		return
	var token: int = load("res://scripts/core/effects/EffectContext.gd").push(target, pid, "disparada", "pending")
	await TriggerSystem._resolution._execute_trigger_effect(target, "on_enter_play", {"card": target, "player_id": pid})
	load("res://scripts/core/effects/EffectContext.gd").pop(token)


static func _monjes(main: Node, card: Node, pid: int) -> void:
	var totems := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM and ContinuousEffectManager.cost_at_most(c, 2) \
		and c.has_method("has_trigger") and c.has_trigger("on_enter_play") and not KeywordManager.is_silenced(c))
	var reuse := not totems.is_empty()
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, _name(card),
			["Utilizar la habilidad de un Tótem de coste 2 o menos al entrar", "Generar un Oro para jugar Tótem", "No"], pid)
		if pick < 0 or pick > 1:
			return
		reuse = pick == 0
	if await _window(card, pid):
		return
	if reuse:
		await _retrigger_enter(card, pid, await _pick_from(main, pid, "%s: elige un Tótem de coste 2 o menos" % _name(card), totems, true))
	elif main._gold_manager:
		main._gold_manager.generar_oro_virtual_restringido(1, func(t, _r, _c): return t == Constants.CardType.TOTEM, "%s: Oro para Tótem" % _name(card), pid)


static func _rey_pajaros(main: Node, card: Node, pid: int) -> void:
	var allies := _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO \
		and str(c.get("card_name")).to_lower() != str(card.get("card_name")).to_lower() and int(c.get("card_cost")) == 1 \
		and c.has_method("has_trigger") and c.has_trigger("on_enter_play") and not KeywordManager.is_silenced(c))
	if allies.is_empty() or not await _confirm(main, pid, _name(card), "Disparar la habilidad de entrada de un Aliado de coste 1"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige un Aliado de coste 1" % _name(card), allies, true)
	if is_instance_valid(target) and not await _window(card, pid):
		await _retrigger_enter(card, pid, target)


static func _shakuhachi(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var picks := await _pick_cemetery(pid, [pid], "%s: puedes jugar un Talismán de tu Cementerio pagando su coste" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid))
	if picks.is_empty() or await _window(card, pid) or not await PlayerSideScript.pay(main, pid, int(picks[0].data.get("coste", 0))):
		return
	if CardManager.take_from_cemetery(pid, picks[0].data):
		picks[0].data["esta_oculta"] = false
		await main._gold_manager.play_card_for_free(picks[0].data, pid, true)


static func _felipe_augusto(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var knights := _in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and "caballero" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	if knights.is_empty():
		return
	var picks := await _pick_cemetery(pid, [pid], "%s: puedes jugar un Arma de coste 2 o menos de tu Cementerio en un Caballero" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) <= 2)
	if picks.is_empty():
		return
	var knight: Node = await _pick_from(main, pid, "%s: elige el Aliado Caballero que la porta" % _name(card), knights, false)
	if not is_instance_valid(knight) or await _window(card, pid) or not CardManager.take_from_cemetery(pid, picks[0].data):
		return
	var data: Dictionary = picks[0].data.duplicate()
	data["esta_oculta"] = false
	var weapon: Node = main._create_card(data, false)
	weapon.owner_id = pid
	weapon.controller_id = pid
	main._connect_card_signals(weapon)
	await main._gold_manager._equip_weapon(weapon, knight)


static func _kiyohime(main: Node, card: Node, pid: int) -> void:
	if not card.get_meta("entered_from_hand", false) or not main._gold_manager:
		return
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 4
	var hand_nodes: Array = _hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return
	if not await _confirm(main, pid, _name(card), "Poner en juego un Aliado de coste 4 o menos de tu mano o Cementerio"):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Aliado de coste 4 o menos" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2 or await _window(card, pid):
		return
	var data: Dictionary = {}
	if int(raw[0][0]) == -1:
		var hi := int(raw[0][1])
		if hi < 0 or hi >= hand_nodes.size():
			return
		data = PlayerSideScript.take_from_hand(main, pid, hand_nodes[hi])
	else:
		var ci := int(raw[0][1])
		if ci < 0 or ci >= entries.size() or not entries[ci].eligible or not CardManager.take_from_cemetery(pid, entries[ci].data):
			return
		data = entries[ci].data.duplicate()
	data["esta_oculta"] = false
	var node: Node = main._create_card(data, false)
	node.owner_id = pid
	node.controller_id = pid
	main._connect_card_signals(node)
	await main._gold_manager._play_card_to_field(node)


static func _ikuchi(main: Node, card: Node, pid: int) -> void:
	if not card.get_meta("entered_from_hand", false):
		return
	if not _in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 1)).is_empty():
		return
	var rivals: Array = _in_play(main, 1 - pid) + _golds(main, [1 - pid])
	if rivals.is_empty() or not await _confirm(main, pid, _name(card), "Desterrar hasta una carta oponente de cada tipo"):
		return
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		var seen_types: Dictionary = {}
		for c in rivals:
			if not seen_types.has(c.get("card_type")):
				seen_types[c.get("card_type")] = true
				chosen.append(c)
	else:
		var one_per_type := func(so_far: Array, c: Node) -> bool: return not so_far.any(func(x): return x.get("card_type") == c.get("card_type"))
		chosen = await main._card_interaction.await_multi_target("%s: hasta una carta oponente de cada tipo" % _name(card),
			rivals, -1, Callable(), one_per_type, true, null, pid)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.banish(chosen, card, true)


# =============================================================================
# INMUNIDAD A EFECTOS OPONENTES (EffectController.opp_immune_card / player_opp_immune)
# =============================================================================
static func _peter_pan(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	RuleState.set_until("opp_effect_immune", pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: no puedes ser afectado por efectos oponentes hasta tu próximo turno" % _name(card))
	var n := 2
	if not PlayerSideScript.is_bot(pid):
		n = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta dos cartas" % _name(card), ["Robar 0", "Robar 1", "Robar 2"], pid), 0)
	if n > 0:
		await ActionModule.draw(pid, n, _name(card), true)


## Juega una carta de tu mano o Cementerio pagando su coste menos 'discount' (mínimo 'floor'). Los Oros no
## se juegan. Devuelve true si se jugó.
static func _play_from_hand_or_cemetery(main: Node, card: Node, pid: int, discount: int, floor_cost: int, filter: Callable = Callable()) -> bool:
	if not main._gold_manager:
		return false
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - discount, floor_cost)
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) != Constants.CardType.ORO and (not filter.is_valid() or filter.call(d)) 		and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)
	var hand_nodes: Array = _hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return false
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: puedes jugar una carta de tu mano o Cementerio" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return false
	var data: Dictionary = {}
	var hand_node: Node = null
	if int(raw[0][0]) == -1:
		if int(raw[0][1]) < 0 or int(raw[0][1]) >= hand_nodes.size():
			return false
		hand_node = hand_nodes[int(raw[0][1])]
		data = hand_node.card_data
	else:
		var ci := int(raw[0][1])
		if ci < 0 or ci >= entries.size() or not entries[ci].eligible:
			return false
		data = entries[ci].data
	var cost: int = price.call(data)
	if cost > 0 and not await PlayerSideScript.pay(main, pid, cost):
		return false
	if hand_node:
		data = PlayerSideScript.take_from_hand(main, pid, hand_node)
	elif not CardManager.take_from_cemetery(pid, data):
		return false
	data["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(data, pid):
		CardManager.add_to_cemetery(pid, data)
		return false
	return true


static func _revolver_webley(main: Node, card: Node, pid: int) -> void:
	var wielder = card.get_parent()
	if await _window(card, pid):
		return
	await _play_from_hand_or_cemetery(main, card, pid, 1, 0)
	if is_instance_valid(wielder) and wielder.get("equipped_weapons") is Array:
		wielder.set_meta("opp_immune_until", _until_before_next_turn(pid))
		main._update_debug("%s: %s no puede ser afectado por efectos oponentes hasta tu próximo turno" % [_name(card), _name(wielder)])


# =============================================================================
# OROS QUE GANAN O RECIBEN UNA HABILIDAD
# =============================================================================
## Le pone 'text' como habilidad (Card.card_ability reparsea sus disparadores; las auras se leen del texto).
static func set_ability(node: Node, text: String) -> void:
	if not is_instance_valid(node):
		return
	if node.get("card_data") is Dictionary:
		node.card_data["habilidad"] = text
	node.is_converted = false
	node.card_ability = text
	KeywordManager.scan_and_apply_keywords(node)
	ContinuousEffectManager.request_strength_badge_refresh()


## tres pascualas: "puedes convertir un Oro oponente en un Oro con la habilidad "Tus Aliados pierden 1 de
## Fuerza"" (la habilidad nueva reemplaza la suya).
static func _tres_pascualas(main: Node, card: Node, pid: int) -> void:
	var rx := RegEx.create_from_string("con la habilidad [\"“”]([^\"“”]+)[\"“”]")
	var m := rx.search(str(card.get("card_ability")))
	var golds := _golds(main, [1 - pid])
	if m == null or golds.is_empty() or not await _confirm(main, pid, _name(card), "Convertir un Oro oponente"):
		return
	var gold: Node = await _pick_from(main, pid, "%s: elige un Oro oponente" % _name(card), golds, true)
	if is_instance_valid(gold) and not await _window(card, pid):
		set_ability(gold, m.get_string(1).strip_edges())
		main._update_debug("%s: %s ahora tiene \"%s\"" % [_name(card), _name(gold), m.get_string(1)])


static func _canaan(main: Node, card: Node, pid: int) -> void:
	var mine := _golds(main, [pid])
	var theirs := _golds(main, [1 - pid]).filter(func(g): return not str(g.get("card_ability")).strip_edges().is_empty() and not KeywordManager.is_silenced(g))
	var copy := not mine.is_empty() and not theirs.is_empty()
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, _name(card),
			["Un Oro tuyo gana las habilidades de un Oro oponente", "Buscar un Arma en tu Castillo", "No"], pid)
		if pick < 0 or pick > 1:
			return
		copy = pick == 0
	if await _window(card, pid):
		return
	if copy:
		var own: Node = await _pick_from(main, pid, "%s: elige un Oro que controles" % _name(card), mine, false)
		var other: Node = await _pick_from(main, pid, "%s: elige un Oro oponente (sus habilidades)" % _name(card), theirs, false)
		if is_instance_valid(own) and is_instance_valid(other):
			var base: String = str(own.get("card_ability")).strip_edges()
			set_ability(own, (base + " " if not base.is_empty() else "") + str(other.get("card_ability")).strip_edges())
		return
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ARMA}, 1, true, false, false, card)



## Valac: "Destruye hasta tantas cartas oponentes de coste 2 o menos como Oros hayas pagado por este Aliado
## más uno." Lo pagado lo anota GoldManager.play_card() (meta "gold_paid"; si entró sin jugarse, 0).
static func _valac(main: Node, card: Node, pid: int) -> void:
	var n: int = int(card.get_meta("gold_paid", 0)) + 1
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return _cost(a) > _cost(b))
	var chosen: Array = await _pick_many(main, pid, "%s: Destruye hasta %d cartas oponentes de coste 2 o menos" % [_name(card), n], rivals, n, true)
	if not chosen.is_empty() and not await _window(card, pid):
		await ActionModule.destroy(chosen, card, true)



## gokin: "puedes convertir una carta de coste 2 o menos en un Oro con la habilidad "Sólo puedes usar este
## Oro para pagar el coste de una carta de coste 3 o más" y ponlo en tu Reserva". La restricción la
## respeta el pago (meta "only_cost_min", GoldManager.gold_usable_for()).
static func _gokin(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(_in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO 			and ContinuousEffectManager.cost_at_most(c, 2)))
	if targets.is_empty() or not await _confirm(main, pid, _name(card), "Convertir una carta de coste 2 o menos en un Oro"):
		return
	var target: Node = await _pick_from(main, pid, "%s: elige una carta de coste 2 o menos" % _name(card), targets, true)
	if not is_instance_valid(target) or await _window(card, pid) or not is_instance_valid(target):
		return
	var owner: int = int(target.owner_id) if target.get("owner_id") != null else CardQuery.controller_of(target)
	var weapons = target.get("equipped_weapons")
	if weapons is Array:
		for w in weapons.duplicate():
			if is_instance_valid(w):
				await CardManager.destroy_card(int(w.owner_id) if w.get("owner_id") != null else owner, w)
	var wielder = target.get_parent()
	if wielder and wielder.get("equipped_weapons") is Array:
		wielder.equipped_weapons.erase(target)
	var data: Dictionary = target.card_data.duplicate()
	data["tipo"] = Constants.CardType.ORO
	data["habilidad"] = "Sólo puedes usar este Oro para pagar el coste de una carta de coste 3 o más."
	data["esta_oculta"] = false
	if target.get_parent():
		target.get_parent().remove_child(target)
	CardManager._disconnect_card_interaction_signals(target)
	target.queue_free()
	var gold: Node = await main._gold_manager.put_gold_directly_in_reserva(pid, data)
	if is_instance_valid(gold):
		gold.owner_id = owner
		gold.set_meta("only_cost_min", 3)
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)
	main._update_debug("%s: %s es ahora un Oro en tu Reserva (solo para cartas de coste 3 o más)" % [_name(card), str(data.get("nombre", ""))])



# =============================================================================
# OBLIGAR A COMBATIR, DADO, RECARGOS
# =============================================================================
static func _juzumaru(main: Node, card: Node, pid: int) -> void:
	var rivals := _in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var target: Node = await _pick_from(main, pid, "%s: un Aliado oponente debe atacar o bloquear este turno si puede" % _name(card), rivals, false)
	if is_instance_valid(target) and not await _window(card, pid):
		target.set_meta("must_fight_turn", GameManager.turn_serial)  # GameManager._declare_forced_attackers/_blockers
		main._update_debug("%s: %s debe atacar o bloquear este turno si puede" % [_name(card), _name(target)])


## Manicomio: su regla la aplica GoldManager._roll_manicomio_die(); al entrar no hace nada.
static func _manicomio(_main: Node, _card: Node, _pid: int) -> void:
	pass


static func _corazon_muerte(main: Node, card: Node, pid: int) -> void:
	if not card.get_meta("entered_from_hand", false):
		return
	var all: Array = _in_play(main, pid) + _golds(main, [pid])
	var target: Node = await _pick_from(main, pid, "%s: a tu oponente le cuesta un Oro más afectar esta carta" % _name(card), all, false)
	if is_instance_valid(target) and not await _window(card, pid):
		target.set_meta("affect_toll_until", _until_before_next_turn(pid))  # EffectController.offer_prevention


static func _amuleto_serpiente(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not await _confirm(main, pid, _name(card), "Mostrar las tres primeras cartas de tu Castillo") or await _window(card, pid):
		return
	var shown: Array = []
	for _i in mini(3, deck.size()):
		shown.append(deck.pop_front())
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	var ok: Array = shown.filter(func(d):
		var t := int(d.get("tipo", -1))
		return t == Constants.CardType.ARMA or (t == Constants.CardType.ALIADO and (int(d.get("coste", 0)) <= 1 \
			or "furia" in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))))))
	var idx := await _choose_data(main, pid, "%s: un Aliado de coste 1 o menos o con Furia, o un Arma, a tu mano" % _name(card), ok, true)
	if idx >= 0:
		shown.erase(ok[idx])
		PlayerSideScript.put_in_hand(main, pid, ok[idx])
		# "Si lo haces, hasta tu próximo turno jugar Talismanes cuesta un Oro adicional si ese jugador ha
		# jugado Talismanes en el turno." (PaymentManager._static_type_and_cheap_surcharge)
		for p in [0, 1]:
			RuleState.set_until("talisman_repeat_tax", p, RuleState.next_own_turn(pid))
	# Las demás mostradas vuelven al Castillo y se Baraja.
	RevealedCardsScript.shuffle_back(main, pid, shown, _name(card))


static func _lanza_juramento(main: Node, card: Node, pid: int) -> void:
	if await _window(card, pid):
		return
	var next_turn: int = GameManager.turn_serial + 1
	var golds := _golds(main, [1 - pid])
	var gold: Node = await _pick_from(main, pid, "%s: un Oro oponente no puede ser agrupado el próximo turno" % _name(card), golds, false)
	if is_instance_valid(gold):
		gold.set_meta("no_regroup_turn", next_turn)  # GoldManager._reset_gold / EasyBot.reset_gold
	var all: Array = _in_play(main, 1 - pid) + _in_play(main, pid) + _golds(main, [0, 1])
	var bot_pool: Array = _in_play(main, 1 - pid) + _golds(main, [1 - pid])
	var target: Node = await _pick_from(main, pid, "%s: una carta no puede utilizar sus habilidades el próximo turno" % _name(card),
		bot_pool if PlayerSideScript.is_bot(pid) else all, false)
	if is_instance_valid(target):
		target.set_meta("silenced_on_turn", next_turn)  # KeywordManager.is_silenced


static func _trofeo_cazador(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Oto en tu Castillo",
			"Mostrar tu mano (si no tienes más de un Talismán, tu oponente solo juega un Talismán en esta Vigilia)", pid)
	if await _window(card, pid):
		return
	if search:
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"name_contains": "oto"}, 1, true, false, false, card)
		return
	var hand := _hand(main, pid)
	main._update_debug("%s: muestra su mano: %s" % [_name(card), ", ".join(hand.map(func(c): return _name(c)))])
	if hand.filter(func(c): return c.get("card_type") == Constants.CardType.TALISMAN).size() <= 1:
		RuleState.set_turn_data("one_talisman:%d" % (1 - pid), {"on": true})  # GoldManager._card_play_locked
