extends RefCounted
## EnterPatternsBase — base de EnterPatterns.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: EnterPatternsBase <- EnterPatternsCartas <- EnterPatternsLote2 <- EnterPatternsLote3 <- EnterPatterns. Lo de afuera usa solo EnterPatterns.gd (hereda todo).

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

const PLAZA_TYPES := [["Arma", Constants.CardType.ARMA], ["Tótem", Constants.CardType.TOTEM], ["Talismán", Constants.CardType.TALISMAN]]
