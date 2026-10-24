extends RefCounted
## TalismanPatterns — Talismanes de una sola carta que el compilador no entiende pero que se arman con
## piezas que ya existen (las ayudas de EnterPatterns). Solo los que se resuelven completos.
## Se usa con preload desde TriggerResolution._resolve_look_and_play_patterns() (la cadena de los
## Talismanes). Sin ventana propia: el Talismán ya tuvo la suya al jugarse (TriggerSystem.resolve_talisman).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const ConvertScript = preload("res://scripts/core/effects/mechanics/ConvertPatterns.gd")
const AttackScript = preload("res://scripts/core/effects/mechanics/AttackPatterns.gd")
const EnterScript = preload("res://scripts/core/effects/mechanics/EnterPatterns.gd")
const LeavePlayScript = preload("res://scripts/core/effects/triggers/LeavePlayPatterns.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")

const KINDS := {
	"tu oponente muestra su mano y descarta todos los talismanes de ahi": "_caceria_brujas",
	"mira la mano de tu oponente, elige una carta de ahi que no sea oro y destierrala": "_caminar_tablon",
	"sube a la mano de su dueno una carta oponente de coste 3 o menos. si esa carta era un aliado o totem": "_abduccion",
	"sube una carta de coste 2 o menos en juego a la mano de su dueno. tu oponente no puede jugar cartas con el nombre": "_maestro_go",
	"sube hasta una carta de tu cementerio a tu mano y hasta un aliado oponente de coste 2 o menos en juego a la mano de su dueno": "_justa",
	"sube un aliado oponente a la mano de su dueno y hasta una carta de tu cementerio a tu mano": "_renace_fe",
	"roba hasta tener ocho cartas en tu mano": "_artilleria",
	"tu oponente bota tantas cartas como fuerza tenga un aliado oponente de coste 2 o menos y destruye ese aliado": "_juicio",
	"tu oponente muestra cartas del tope de su castillo hasta mostrar un oro y pone todas esas cartas en su cementerio": "_semilla",
	"tu oponente muestra cartas del tope de su castillo hasta mostrar dos aliados de distinto coste": "_whitby",
	"los jugadores suben a la mano de su dueno las cartas que no sean oro que controlen, de las que no sean dueno": "_desembarco",
	"cada jugador elige un aliado de su cementerio y lo pone en juego bajo su control": "_momificar",
	"hasta dos aliados oponentes pierden su habilidad y tienen fuerza 0 hasta la fase final": "_de_rodillas",
	"destierra dos cartas del fondo o del tope del castillo oponente": "_gusano",
	"elige un aliado en juego. roba tantas cartas como coste tenga ese aliado": "_choque_colosos",
	"juega un aliado de coste 2 o menos desde un cementerio bajo tu control": "_juramento",
	"cada jugador convierte los oros en su reserva en oros sin habilidad": "_bojutsu",
	"pon en tu oro pagado hasta dos oros desde tu cementerio": "_festin_orco",
	"convierte una carta de coste 2 o menos en un totem sin habilidad y gana su control. muestra cartas del tope de tu castillo hasta mostrar un aliado y ponlo en tu mano": "_stevenson",
	"muestra la primera carta de tu castillo. si es un aliado, ponlo en tu cementerio y tu oponente bota dos cartas": "_falso_profeta",
	"busca un talisman en tu castillo de coste 3 o menos y un talisman en el castillo oponente. juega uno sin pagar su coste y destierra el otro": "_conocimiento",
	"destierra hasta dos arma y/o totem cuyos costes sumen hasta 4": "_combate_naval",
	# Segundo lote.
	"sube una carta oponente en juego que no sea oro a la mano de su dueno": "_favor_corte",
	"sube un aliado oponente de coste 3 o menos a la mano de su dueno. si esta en tu mano": "_descarnados",
	"sube hasta tres aliados oponentes de coste 1 o menos a la mano de su dueno": "_trafalgar",
	"muestra cinco cartas de la parte superior de un castillo. pon dos cartas de ahi en la mano o destierro de su dueno": "_aliento_letal",
	"hasta dos aliados no hacen dano de combate este turno o hasta dos aliados ganan 2 de fuerza por el turno": "_cadena_negra",
	"sube un aliado oponente de fuerza 4 o mas a la mano y elige hasta cinco cartas de tu cementerio": "_caceria_impia",
	"mira las primeras seis cartas de tu castillo y pon cualquier cantidad en tu cementerio": "_ritual_bestia",
	"un aliado gana 2 de fuerza permanentemente y no puede salir del juego ni cambiar de controlador hasta tu proximo turno": "_duelo_ganryu",
	"un aliado gana 1 de fuerza permanentemente y 1 de fuerza adicional por cada copia de este talisman en tu cementerio": "_kabuki",
	"juega un aliado de tu cementerio pagando su coste. un aliado gana 1 de fuerza por cada copia de este talisman": "_ubagabi",
	"si es un daikaiju en vez de eso juegalo reduciendo su coste en dos oros": "_aplastar",
	"si es un tenshi en vez de eso juegalo reduciendo su coste en dos oros": "_luz_desafiante",
	"elige efectos segun las razas que controles": "_rugido_origen",
	"hasta tres aliados cuyos costes sumen 3 o menos pierden su habilidad, tienen fuerza 0 y no pueden ser destruidos este turno": "_depredar",
	"elige hasta dos aliados que porten armas para que ganen furia, 1 de fuerza por cada arma que controles": "_oriflama",
	"juega un aliado de coste 2 o menos desde tu mano o cementerio sin pagar su coste": "_conan_doyle",
	"tu oponente descarta tres cartas de su mano y puedes buscar un aliado sherlock holmes": "_elemental",
	"mira las primeras seis cartas de tu castillo, pon dos cartas de ahi en tu mano y ordena el resto": "_murcielagos",
	"convierte una carta en juego en una carta del mismo tipo sin habilidad y gana el control de una carta de coste 2 o menos": "_atacar_vampiro",
	"por cada aliado de coste 1 o mas en juego, convierte la primera carta de tu castillo en un aliado de raza a tu eleccion": "_comite_animales",
	"nombra una carta. no se pueden utilizar habilidades de cartas con ese nombre por el turno": "_sombra_eterea",
	"busca dos armas que cuyos costes sumen hasta 3 en tu castillo y/o cementerio y juegalas sin pagar su coste": "_cancha_rayada",
	"hasta dos aliados en juego ganan o pierden 3 de fuerza. si tienen fuerza 0 son desterrados": "_descanso_solar",
	"convierte una carta de cualquier cementerio en un aliado de fuerza 0, con la habilidad": "_abordaje",
	# Tercer lote.
	"las armas y totem oponentes en juego pierden su habilidad hasta el final de tu proximo turno": "_silenciar_mundo",
	"hasta el final de tu proximo turno, solo se puede jugar hasta dos cartas de cada tipo por turno": "_aklo",
	"muestra cartas de la parte superior tu castillo hasta mostrar dos aliados. puedes jugar uno por un oro menos": "_cancer",
	"el proximo aliado que juegues este turno reduce su coste en un oro hasta un minimo de 0": "_corrupcion_alma",
	"mira la mano de tu oponente, y elige un aliado de ahi de coste 2 o menos": "_humpty",
	"tus aliados ganan 1 de fuerza y los oponentes pierden 1 de fuerza, permanentemente": "_remate_mortal",
	"gana el control de un aliado o totem del que seas dueno y descarta tantas cartas de tu mano como su coste": "_transformacion_lucy",
	"busca hasta un carta de cada tipo en el castillo oponente y destierralas": "_hijos_noche",
	"muestra la primera carta de tu castillo y si es un aliado, elige ambos": "_avistamientos",
	"busca un bandido en tu castillo y ponlo en tu mano o juega un arma o totem de tu cementerio o destierro pagando su coste": "_ataque_bandido",
	"juega sin pagar su coste hasta dos aliados de tu cementerio cuyos costes sumen 2": "_vigilia_armas",
	"juega un arma desde tu mano o cementerio reduciendo su coste en un oro hasta un minimo de 0": "_proteger_botin",
	"elige un aliado que controles de coste 2 o mas y un aliado que controle tu oponente de igual o menor fuerza": "_amarre_bruja",
	# Inmunidad a efectos oponentes.
	"por el turno, tus aliados ganan imbloqueable, 1 de fuerza y no se puede cancelar el ataque": "_jugando_demonio",
	"al finalizar este turno, gana un turno extra. ese turno tu oponente no puede recibir dano": "_viaje_temporal",
	# En respuesta a algo: la carta rival en la pila (StackAnnul.find_target).
	"esa carta entra en juego sin habilidad por el turno. si es un talisman": "_expulsion",  # "sin efecti" (errata)
	"ese aliado entra en juego sin habilidad": "_descubrir_zorro",
	"tu oponente solo puede jugar una carta mas de ese mismo tipo este turno y tu no puedes jugar mas cartas este turno": "_iluminar",
	"busca hasta dos cartas con distinto nombre en un castillo y destierralas o preven que tu oponente busque cartas en tu castillo": "_ofrenda_abuelos",
	"reduce a 0 el proximo dano que fueras a recibir este turno y tu oponente bota dos cartas por cada aliado en su linea de ataque": "_puertas",
	"preven todo el dano a tu castillo. tu oponente destierra tantas cartas de su castillo como dano hayas prevenido": "_arlequin",
	# Límites y textos nuevos.
	"mira la mano de tu oponente y destierra hasta dos cartas de coste 2 o menos de ahi": "_sabiduria_oruga",
	"preven un efecto y tu oponente solo puede atacar con hasta dos aliados este turno": "_concilio",
	"preven un efecto y tus aliados ganan 1 de fuerza permanentemente": "_camino_guerrero",
	"los proximos dos turnos, no se puede atacar y no puedes jugar mas de una carta por turno": "_pereza",
	"por el resto del juego, jugar talismanes y cartas sin pagar su coste cuesta un oro adicional": "_no_mas_magia",
	"los jugadores no pueden buscar, mirar, ni mostrar cartas de la mano ni los castillos por efectos hasta tu proxima fase final": "_escudo_estelar",
	"un aliado que controles gana la habilidad de un aliado de tu cementerio de coste 2 o menos": "_a_traves_espejo",
	"convierte un aliado de coste 2 o menos que controles en una copia de otro aliado controles del mismo coste": "_todos_locos",
	"el aliado con menor fuerza entre los dos no puede atacar ni bloquear y reemplaza su habilidad por": "_captura_colosal",
	"convierte los aliados en aliados de fuerza 1 con la habilidad": "_dia_muertos",
	"anula un arma o totem de coste 3 o menos y destierra esa carta": "_identidad_secreta",
	"cada vez que un aliado fuera a ganar fuerza en vez de eso gana el doble, hasta un maximo de 4 de fuerza por vez": "_marca_justos",
	"juega hasta un aliado angel de tu cementerio reduciendo su coste en un oro, hasta un minimo de 0 y tu oponente juega mostrando su mano": "_invocar_angeles",
	"las cartas que sean puestas en el cementerio este turno pierden su habilidad por el turno": "_niebla_muerte",
	"destruye hasta dos cartas con habilidad de coste 1 o mas que controles": "_comer_insectos",
	"tu oponente solo puede jugar una carta mas o utilizar una habilidad mas por el turno": "_anillo_tierra",
	"cada jugador muestra su mano. el jugador con el coste total de cartas mas alto en su mano": "_duelo_magico",
	"cada vez que tu oponente ponga cartas en su mano por un efecto, puedes poner esa misma cantidad de cartas del tope de tu castillo en tu mano": "_sesion_espiritista",
	"un aliado duplica su fuerza y si ataca o bloquea debes botar tantas cartas como fuerza tenga": "_terremoto",
	"elige un aliado que controles. hasta tu proximo turno, si esta en tu linea de ataque no puede salir del juego por efectos": "_furia_titan",
	"un aliado de coste 2 o menos gana furia, indestructible, debe atacar este turno": "_marca_bestia",
	"al final de esta batalla mitologica agrupa tus aliados y ganas una batalla mitologica adicional": "_ta_kona",
	"convierte tus oros en aliados de fuerza 3 que no pueden salir del juego este turno y en la fase final muevelos a tu oro pagado": "_nuevas_tierras",
	"sube una carta de tu cementerio a tu mano. cuando este talisman se resuelva, conviertelo en un oro con la habilidad": "_alma_viento",
	"utiliza una habilidad activada de una carta de coste 2 o menos en un cementerio o destierro como si la controlaras": "_estaca",
	"ambos jugadores muestran su mano, comenzando por ti cada jugador elige una carta de la mano oponente y la coloca en su mano": "_corromper",
	"sube cualquier cantidad de aliados que controles a tu mano. al comienzo de tu proximo turno juegalos sin pagar su coste": "_julio_verne",
	"preven que una carta que controles sea afectada por un efecto oponente": "_fuego_purificador",
	"preven que una carta de nombre ignis o titan sea anulada, cancelada o afectada por un efecto oponente": "_rugido_titan",
}


static func _kind(text: String) -> String:
	var t := CemeteryTriggersScript.normalize(text)
	for k in KINDS:
		if k in t:
			return KINDS[k]
	return ""


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var fn := _kind(text)
	if fn.is_empty():
		return false
	var main := CardQuery.main_node()
	if main:
		await load("res://scripts/core/effects/mechanics/TalismanPatterns.gd").call(fn, main, card, controller_id)
	return true


static func _name(card) -> String:  # sin tipo: puede llegar ya liberada
	return str(card.get("card_name")) if is_instance_valid(card) else "Talismán"


static func _in_play_both(main: Node, filter: Callable) -> Array:
	return EnterScript._in_play(main, 0, filter) + EnterScript._in_play(main, 1, filter)


## Una carta de un Cementerio a la mano de su dueño (pick_in_zones: Remoto por red, bot la primera).
static func _raise_one(main: Node, pid: int, title: String, optional: bool) -> void:
	var cem: Array = CardManager.get_cemetery(pid)
	if cem.is_empty():
		return
	var entries: Array = cem.map(func(d): return {"data": d, "eligible": true})
	var raw: Array = await ActionModule.pick_in_zones(pid, title,
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0 if optional else 1, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2 or int(raw[0][0]) != 0:
		return
	var ci := int(raw[0][1])
	if ci < 0 or ci >= entries.size():
		return
	var d: Dictionary = entries[ci].data
	if CardManager.take_from_cemetery(pid, d):
		PlayerSideScript.put_in_hand(main, pid, d)


## Muestra del tope de un Castillo hasta que 'done' diga basta (o se vacíe). Devuelve lo mostrado,
## ya fuera del mazo.
static func _reveal_until(main: Node, owner: int, title: String, done: Callable) -> Array:
	var deck: Array = CardManager.get_deck(owner)
	var shown: Array = []
	while not deck.is_empty() and not done.call(shown):
		shown.append(deck.pop_front())
	var names: String = ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))
	main._update_debug("%s muestra: %s" % [title, names])
	load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(owner, shown, title)
	if CombatLog and CombatLog.has_method("log_action"):
		CombatLog.log_action("%s muestra: %s" % [title, names])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return shown


# =============================================================================
# CARTAS
# =============================================================================
static func _caceria_brujas(main: Node, card: Node, pid: int) -> void:
	await EnterScript._discard_from_opp_hand(main, card, pid, func(c): return c.get("card_type") != Constants.CardType.TALISMAN)


static func _caminar_tablon(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid):
		return
	var all: Array = EnterScript._hand(main, opp)
	var hand: Array = all.filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
	if all.is_empty():
		return
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	if hand.is_empty():
		return
	var idx := 0
	if PlayerSideScript.is_bot(pid):
		hand.sort_custom(func(a, b): return int(a.get("card_cost")) > int(b.get("card_cost")))
	elif hand.size() > 1:
		idx = await SelectionManager.await_choice(main, "%s: elige una carta que no sea Oro para Desterrarla" % _name(card),
			hand.map(func(c): return EnterScript._name(c)), pid)
	var chosen: Node = hand[clampi(idx, 0, hand.size() - 1)]
	if is_instance_valid(chosen):
		EnterScript._exile_from_hand(main, opp, [chosen])
		main._update_debug("%s: Destierra %s de la mano oponente" % [_name(card), EnterScript._name(chosen)])


static func _abduccion(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return ContinuousEffectManager.cost_at_most(c, 3) and c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube una carta oponente de coste 3 o menos a la mano de su dueño" % _name(card), rivals, false)
	if not is_instance_valid(target):
		return
	var was_ally_or_totem: bool = target.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM]
	var target_name := EnterScript._name(target)
	if not await EnterScript.bounce_to_owner_hand(main, target, card) or not was_ally_or_totem:
		return
	if main._gold_manager:
		main._gold_manager.lock_name_from_playing(target_name, 1 - pid, pid)
		main._gold_manager.generar_oro_virtual_restringido(1, func(t, _r, _c): return t in [Constants.CardType.ARMA, Constants.CardType.TOTEM],
			"%s: Oro para Armas o Tótem" % _name(card), pid)


static func _maestro_go(main: Node, card: Node, pid: int) -> void:
	var targets := _in_play_both(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2) and c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube una carta de coste 2 o menos a la mano de su dueño" % _name(card), targets, false)
	if not is_instance_valid(target):
		return
	var target_name := EnterScript._name(target)
	if await EnterScript.bounce_to_owner_hand(main, target, card) and main._gold_manager:
		main._gold_manager.lock_name_from_playing(target_name, 1 - pid, pid)


static func _bounce_opp_ally(main: Node, card: Node, pid: int, max_cost: int, optional: bool) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and (max_cost < 0 or ContinuousEffectManager.cost_at_most(c, max_cost)))
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube un Aliado oponente a la mano de su dueño" % _name(card), rivals, optional)
	if is_instance_valid(target):
		await EnterScript.bounce_to_owner_hand(main, target, card)


static func _justa(main: Node, card: Node, pid: int) -> void:
	await _raise_one(main, pid, "%s: puedes subir una carta de tu Cementerio a tu mano" % _name(card), true)
	await _bounce_opp_ally(main, card, pid, 2, true)


static func _renace_fe(main: Node, card: Node, pid: int) -> void:
	await _bounce_opp_ally(main, card, pid, -1, false)
	await _raise_one(main, pid, "%s: puedes subir una carta de tu Cementerio a tu mano" % _name(card), true)


static func _artilleria(main: Node, card: Node, pid: int) -> void:
	var n: int = 8 - EnterScript._hand(main, pid).size()
	if n <= 0:
		return
	await ActionModule.draw(pid, n, _name(card), true)
	if n > 4 and main._gold_manager:
		main._gold_manager.set_no_more_cards_this_turn(pid)
		main._update_debug("%s: robaste más de cuatro cartas; no puedes jugar más cartas este turno" % _name(card))


static func _juicio(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 2))
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var target: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado oponente de coste 2 o menos" % _name(card), rivals, false)
	if not is_instance_valid(target):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(target))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))
	if is_instance_valid(target):
		await ActionModule.destroy([target], card, true)


static func _semilla(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	while true:
		var shown := _reveal_until(main, opp, _name(card), func(s): return not s.is_empty() and int(s[-1].get("tipo", -1)) == Constants.CardType.ORO)
		for d in shown:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(opp, d)
		# "Cuando se resuelva, puedes pagar un Oro para repetir su efecto."
		if CardManager.get_deck(opp).is_empty() or not main._gold_manager or not main._gold_manager.puede_pagar(1, -1, "", -1, pid):
			return
		if not await EnterScript._confirm(main, pid, _name(card), "Pagar un Oro para repetir el efecto") \
				or not await PlayerSideScript.pay(main, pid, 1):
			return


static func _whitby(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var costs: Array = []
	var shown := _reveal_until(main, opp, _name(card), func(s):
		if s.is_empty():
			return false
		var last: Dictionary = s[-1]
		if int(last.get("tipo", -1)) == Constants.CardType.ALIADO and not costs.has(int(last.get("coste", 0))):
			costs.append(int(last.get("coste", 0)))
		return costs.size() >= 2)
	var deck: Array = CardManager.get_deck(opp)
	for d in shown:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(opp)
	AnimationQueue.queue_shuffle(opp, "Barajar mazo (%s)" % _name(card))
	if costs.size() < 2:
		return
	if costs.max() > 0:
		await ActionModule.mill(opp, costs.max(), false, _name(card))
	if costs.min() > 0:
		await ActionModule.draw(pid, costs.min(), _name(card), true)


static func _desembarco(main: Node, card: Node, _pid: int) -> void:
	var borrowed := _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and c.get("owner_id") != null and int(c.owner_id) != CardQuery.controller_of(c))
	for c in borrowed:
		await EnterScript.bounce_to_owner_hand(main, c, card)


static func _momificar(main: Node, card: Node, pid: int) -> void:
	if not main.get("_gold_manager"):
		return
	for p in [pid, 1 - pid]:
		var entries: Array = CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.ALIADO})
		if not entries.any(func(e): return e.eligible):
			continue
		var raw: Array = await ActionModule.pick_in_zones(p, "%s: elige un Aliado de tu Cementerio para ponerlo en juego" % _name(card),
			[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 1, 1)
		if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2 or int(raw[0][1]) < 0 or int(raw[0][1]) >= entries.size():
			continue
		var e: Dictionary = entries[int(raw[0][1])]
		if not e.eligible or not CardManager.take_from_cemetery(p, e.data):
			continue
		var data: Dictionary = e.data.duplicate()
		data["esta_oculta"] = false
		var node: Node = main._create_card(data, false)
		node.owner_id = p
		node.controller_id = p
		main._connect_card_signals(node)
		await main._gold_manager._play_card_to_field(node)


static func _de_rodillas(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados oponentes" % _name(card), rivals, 2, true)
	for c in chosen:
		if not is_instance_valid(c):
			continue
		await KeywordManager.silence_card(c, card, "turn")
		ContinuousEffectManager.register_modifier({
			"source": c, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 0, "operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING,
			"description": "%s: Fuerza 0" % _name(card),
		})
		if c.has_method("refresh_strength_badge"):
			c.refresh_strength_badge()


static func _gusano(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty():
		return
	var from_top := true
	if not PlayerSideScript.is_bot(pid):
		from_top = await SelectionManager.await_two_choice(main, _name(card), "Del tope", "Del fondo", pid)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_front() if from_top else deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _choque_colosos(main: Node, card: Node, pid: int) -> void:
	var allies := _in_play_both(main, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado en juego" % _name(card), allies, false)
	if not is_instance_valid(chosen):
		return
	var budget: int = EnterScript._cost(chosen)
	if budget > 0:
		await ActionModule.draw(pid, budget, _name(card), true)
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and EnterScript._cost(c) >= 1 and EnterScript._cost(c) <= budget)
	if rivals.is_empty():
		return
	var picked: Array = []
	if PlayerSideScript.is_bot(pid):
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		var total := 0
		for c in rivals:
			if total + EnterScript._cost(c) <= budget:
				picked.append(c)
				total += EnterScript._cost(c)
	else:
		var fits := func(so_far: Array, c: Node) -> bool:
			var total := 0
			for x in so_far:
				total += EnterScript._cost(x)
			return total + EnterScript._cost(c) <= budget
		picked = await main._card_interaction.await_multi_target(
			"%s: Destruye cartas oponentes cuyos costes sumen %d o menos" % [_name(card), budget], rivals, -1, Callable(), fits, true, null, pid)
	if not picked.is_empty():
		await ActionModule.destroy(picked, card, true)


static func _juramento(main: Node, card: Node, pid: int) -> void:
	if not main.get("_gold_manager"):
		return
	var pools: Array = []
	var owners: Array = []
	for p in [pid, 1 - pid]:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d,
				"eligible": int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2})})
		owners.append(p)
	if not pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: juega un Aliado de coste 2 o menos de un Cementerio" % _name(card), pools, 1, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var d: Dictionary = pools[pi].cards[ci].data
	if CardManager.take_from_cemetery(owners[pi], d):
		d["esta_oculta"] = false
		if not await main._gold_manager.play_card_for_free(d, pid):
			CardManager.add_to_cemetery(owners[pi], d)


static func _bojutsu(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		for g in PlayerSideScript.gold_reserva(main, p).get_children():
			if is_instance_valid(g) and g.get("card_type") == Constants.CardType.ORO:
				await EnterScript._blank(g, card)
	for p in [pid, 1 - pid]:
		await ActionModule.search_zones(p, [Constants.Zone.CASTILLO, Constants.Zone.CEMENTERIO], {"type": Constants.CardType.ORO}, 1, true)


static func _festin_orco(main: Node, card: Node, pid: int) -> void:
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": int(d.get("tipo", -1)) == Constants.CardType.ORO})
	if not entries.any(func(e): return e.eligible) or not main._gold_manager:
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta dos Oros de tu Cementerio a tu Oro Pagado" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 0, 2)
	var picked: Array = []
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size() \
				and entries[int(rp[1])].eligible and not picked.has(entries[int(rp[1])].data) and picked.size() < 2:
			picked.append(entries[int(rp[1])].data)
	for d in picked:
		if CardManager.take_from_cemetery(pid, d):
			await main._gold_manager.put_gold_directly_in_pagado(pid, d)


static func _stevenson(main: Node, card: Node, pid: int) -> void:
	var targets := _in_play_both(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2) and c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await PlayerSideScript.pick_in_play(main, pid,
		"%s: convierte una carta de coste 2 o menos en tu Tótem sin habilidad" % _name(card), func(c: Node) -> bool: return c in targets,
		false, [1 - pid])
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, pid)
	await TriggerSystem._effect_interpreter.try_execute(card, "muestra cartas del tope de tu castillo hasta mostrar un aliado y ponlo en tu mano", pid)


static func _falso_profeta(main: Node, card: Node, pid: int) -> void:
	while true:
		var deck: Array = CardManager.get_deck(pid)
		if deck.is_empty():
			return
		var d: Dictionary = deck.pop_front()
		main._update_debug("%s muestra: %s" % [_name(card), str(d.get("nombre", "?"))])
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(pid, [d], _name(card))
		d["esta_oculta"] = false
		if int(d.get("tipo", -1)) != Constants.CardType.ALIADO:
			PlayerSideScript.put_in_hand(main, pid, d)
			if main.get("_zone_manager"):
				main._zone_manager._update_castillo_counts()
			return
		CardManager.add_to_cemetery(pid, d)
		await ActionModule.mill(1 - pid, 2, false, _name(card))
		# "Puedes repetir este efecto hasta que Robes una carta que no sea Aliado."
		if not await EnterScript._confirm(main, pid, _name(card), "Repetir el efecto"):
			return


static func _conocimiento(main: Node, card: Node, pid: int) -> void:
	var is_tal := func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN
	var mine: Array = await AttackScript._pick_from_castle(pid, pid, "%s: un Talismán de coste 3 o menos de tu Castillo" % _name(card),
		func(d): return is_tal.call(d) and int(d.get("coste", 0)) <= 3, 1, 1, false)
	var theirs: Array = await AttackScript._pick_from_castle(1 - pid, pid, "%s: un Talismán del Castillo oponente" % _name(card),
		is_tal, 1, 1, false)
	var found: Array = []
	for d in mine:
		found.append({"data": d, "owner": pid})
	for d in theirs:
		found.append({"data": d, "owner": 1 - pid})
	if found.is_empty():
		return
	var play_idx := 0
	if found.size() == 2 and not PlayerSideScript.is_bot(pid):
		play_idx = 0 if await SelectionManager.await_two_choice(main, "%s: ¿cuál juegas sin pagar su coste?" % _name(card),
			str(found[0].data.get("nombre", "")), str(found[1].data.get("nombre", "")), pid) else 1
	for i in found.size():
		var f: Dictionary = found[i]
		f.data["esta_oculta"] = false
		if i != play_idx:
			CardManager.append_to_exile(f.owner, f.data)
	if main._gold_manager and not await main._gold_manager.play_card_for_free(found[play_idx].data, pid):
		CardManager.add_to_cemetery(found[play_idx].owner, found[play_idx].data)


static func _combate_naval(main: Node, card: Node, pid: int) -> void:
	var candidates: Array = []
	for side in [1 - pid, pid]:
		candidates.append_array(EnterScript._in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.TOTEM))
		candidates.append_array(CardQuery.weapons_in_play(side))
	candidates = candidates.filter(func(c): return is_instance_valid(c) and EnterScript._cost(c) <= 4)
	if candidates.is_empty():
		return
	var picked: Array = []
	if PlayerSideScript.is_bot(pid):
		var rivals: Array = candidates.filter(func(c): return CardQuery.controller_of(c) != pid)
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		var total := 0
		for c in rivals:
			if picked.size() < 2 and total + EnterScript._cost(c) <= 4:
				picked.append(c)
				total += EnterScript._cost(c)
	else:
		var fits := func(so_far: Array, c: Node) -> bool:
			var total := 0
			for x in so_far:
				total += EnterScript._cost(x)
			return so_far.size() < 2 and total + EnterScript._cost(c) <= 4
		picked = await main._card_interaction.await_multi_target(
			"%s: Destierra hasta dos Armas y/o Tótem cuyos costes sumen hasta 4" % _name(card), candidates, 2, Callable(), fits, true, null, pid)
	if not picked.is_empty():
		await ActionModule.banish(picked, card, true)


# =============================================================================
# SEGUNDO LOTE
# =============================================================================
static func _buff_turn(target: Node, card, amount: int, permanent: bool = false) -> void:
	if not is_instance_valid(target) or amount == 0 \
			or await EffectController.offer_prevention(target, card if is_instance_valid(card) else null, "strength_change"):
		return
	ContinuousEffectManager.register_modifier({
		"source": null if permanent else target, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": amount, "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.PERMANENT if permanent else ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY, "description": "%s %+d" % [_name(card), amount],
	})
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()


static func _bounce_up_to(main: Node, card: Node, pid: int, filter: Callable, count: int, prompt: String) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, filter)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: %s" % [_name(card), prompt], rivals, count, true)
	for c in chosen:
		await EnterScript.bounce_to_owner_hand(main, c, card)


static func _favor_corte(main: Node, card: Node, pid: int) -> void:
	await _bounce_up_to(main, card, pid, func(c): return c.get("card_type") != Constants.CardType.ORO, 1,
		"sube una carta oponente que no sea Oro a la mano de su dueño")


static func _descarnados(main: Node, card: Node, pid: int) -> void:
	await _bounce_up_to(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 3), 1,
		"sube un Aliado oponente de coste 3 o menos a la mano de su dueño")


static func _trafalgar(main: Node, card: Node, pid: int) -> void:
	await _bounce_up_to(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.cost_at_most(c, 1), 3,
		"sube hasta tres Aliados oponentes de coste 1 o menos a la mano de su dueño")


static func _aliento_letal(main: Node, card: Node, pid: int) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: muestra cinco cartas de un Castillo" % _name(card),
			"Castillo oponente", "Tu Castillo", pid) else pid
	var shown := _reveal_until(main, owner, _name(card), func(s): return s.size() >= 5)
	if shown.is_empty():
		return
	for i in mini(2, shown.size()):
		var idx := 0
		var to_hand := owner == pid
		if not PlayerSideScript.is_bot(pid):
			if shown.size() > 1:
				idx = clampi(await SelectionManager.await_choice(main, "%s: carta %d de 2" % [_name(card), i + 1],
					shown.map(func(d): return str(d.get("nombre", "?"))), pid), 0, shown.size() - 1)
			to_hand = await SelectionManager.await_two_choice(main, str(shown[idx].get("nombre", "")),
				"A la mano de su dueño", "Al Destierro de su dueño", pid)
		var d: Dictionary = shown.pop_at(idx)
		if to_hand:
			PlayerSideScript.put_in_hand(main, owner, d)
		else:
			d["esta_oculta"] = false
			CardManager.append_to_exile(owner, d)
	for d in shown:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(owner, d)


static func _cadena_negra(main: Node, card: Node, pid: int) -> void:
	var no_damage := false
	if not PlayerSideScript.is_bot(pid):
		no_damage = await SelectionManager.await_two_choice(main, _name(card), "Hasta dos Aliados no hacen daño de combate",
			"Hasta dos Aliados ganan 2 de Fuerza", pid)
	var pool: Array = EnterScript._all_allies(main)
	if PlayerSideScript.is_bot(pid):
		pool = pool.filter(func(c): return CardQuery.controller_of(c) == pid)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados" % _name(card), pool, 2, true)
	for c in chosen:
		if not is_instance_valid(c):
			continue
		if no_damage:
			c.set_meta("no_damage_turn", GameManager.turn_serial)  # BattleManager
		else:
			await _buff_turn(c, card, 2)


static func _caceria_impia(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and int(ContinuousEffectManager.get_modified_strength(c)) >= 4)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: sube un Aliado oponente de Fuerza 4 o más a la mano" % _name(card), rivals, false)
	if is_instance_valid(target):
		await EnterScript.bounce_to_owner_hand(main, target, card)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: hasta cinco cartas de tu Cementerio al fondo de tu Castillo" % _name(card), 0, 5)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			pk.data["esta_oculta"] = true
			CardManager.get_deck(pid).append(pk.data)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _ritual_bestia(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var seen: Array = []
	for _i in mini(6, deck.size()):
		seen.append(deck.pop_front())
	if seen.is_empty():
		return
	var to_cem: Array = []
	if PlayerSideScript.is_bot(pid):
		to_cem = seen.filter(func(d): return int(d.get("tipo", -1)) != Constants.CardType.ORO)
	else:
		SelectionManager.open_reveal(seen, "%s: las primeras seis cartas de tu Castillo" % _name(card), pid)
		var left: Array = seen.duplicate()
		while not left.is_empty():
			var labels: Array = left.map(func(d): return str(d.get("nombre", "?")))
			labels.append("Listo")
			var idx: int = await SelectionManager.await_choice(main, "%s: elige las que van a tu Cementerio" % _name(card), labels, pid)
			if idx < 0 or idx >= left.size():
				break
			to_cem.append(left.pop_at(idx))
	var rest: Array = seen.filter(func(d): return not to_cem.has(d))
	for d in to_cem:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(pid, d)
	for i in range(rest.size() - 1, -1, -1):
		deck.push_front(rest[i])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if to_cem.size() <= 2:
		var small := _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
		if PlayerSideScript.is_bot(pid):
			small = small.filter(func(c): return CardQuery.controller_of(c) != pid)
		var one: Array = await EnterScript._pick_many(main, pid, "%s: Destruye hasta una carta de coste 2 o menos" % _name(card), small, 1, true)
		if not one.is_empty():
			await ActionModule.destroy(one, card, true)


static func _duelo_ganryu(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid))
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 2 de Fuerza permanentemente" % _name(card), allies, false)
	if not is_instance_valid(target):
		return
	await _buff_turn(target, card, 2, true)
	EffectController.add_single_card_leave_play_immunity(target, pid)
	target.set_meta("no_control_change_until", RuleState.next_own_turn(pid) - 1)


static func _copies_in_cemetery(pid: int, card) -> int:  # sin tipo: puede llegar ya liberada
	var name := _name(card).to_lower()
	return CardManager.get_cemetery(pid).filter(func(d): return str(d.get("nombre", "")).to_lower() == name).size()


static func _kabuki(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Fuerza permanentemente" % _name(card), allies, false)
	if is_instance_valid(target):
		await _buff_turn(target, card, 1 + _copies_in_cemetery(pid, card), true)


static func _ubagabi(main: Node, card: Node, pid: int) -> void:
	var n := _copies_in_cemetery(pid, card)  # antes de jugar nada (la carta puede liberarse)
	if main._gold_manager:
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega un Aliado de tu Cementerio pagando su coste" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid))
		for pk in picks:
			if await PlayerSideScript.pay(main, pid, int(pk.data.get("coste", 0))) and CardManager.take_from_cemetery(pid, pk.data):
				pk.data["esta_oculta"] = false
				if not await main._gold_manager.play_card_for_free(pk.data, pid):
					CardManager.add_to_cemetery(pid, pk.data)
	if n > 0:
		var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
		var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana %d de Fuerza" % [_name(card), n], allies, false)
		await _buff_turn(target, card, n)


## aplastar / luz desafiante: juega un Aliado de tu Cementerio por un Oro menos (dos si es de la raza),
## mínimo 1; luego Destierra Aliados de esas razas cuyos costes sumen hasta 3.
static func _revive_and_banish_races(main: Node, card: Node, pid: int, bonus_race: String, races: Array) -> void:
	if main._gold_manager:
		var price := func(d) -> int:
			var red: int = 2 if bonus_race in CemeteryTriggersScript.normalize(str(d.get("raza", ""))) else 1
			return maxi(int(d.get("coste", 0)) - red, 1)
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega un Aliado de tu Cementerio con descuento" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid))
		for pk in picks:
			if await PlayerSideScript.pay(main, pid, price.call(pk.data)) and CardManager.take_from_cemetery(pid, pk.data):
				pk.data["esta_oculta"] = false
				if not await main._gold_manager.play_card_for_free(pk.data, pid):
					CardManager.add_to_cemetery(pid, pk.data)
	var of_race := func(c) -> bool:
		var r := CemeteryTriggersScript.normalize(str(c.get("card_raza")))
		return c.get("card_type") == Constants.CardType.ALIADO and races.any(func(x): return x in r)
	var pool := _in_play_both(main, of_race)
	if PlayerSideScript.is_bot(pid):
		pool = pool.filter(func(c): return CardQuery.controller_of(c) != pid)
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		pool.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		var total := 0
		for c in pool:
			if total + EnterScript._cost(c) <= 3:
				chosen.append(c)
				total += EnterScript._cost(c)
	elif not pool.is_empty():
		var fits := func(so_far: Array, c: Node) -> bool:
			var total := 0
			for x in so_far:
				total += EnterScript._cost(x)
			return total + EnterScript._cost(c) <= 3
		chosen = await main._card_interaction.await_multi_target("%s: Destierra Aliados cuyos costes sumen hasta 3" % _name(card),
			pool, -1, Callable(), fits, true, null, pid)
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)


static func _aplastar(main: Node, card: Node, pid: int) -> void:
	await _revive_and_banish_races(main, card, pid, "daikaiju", ["caballero", "eterno", "guerrero", "heroe"])


static func _luz_desafiante(main: Node, card: Node, pid: int) -> void:
	await _revive_and_banish_races(main, card, pid, "tenshi", ["bestia", "dragon", "faerie", "sombra"])


static func _rugido_origen(main: Node, card: Node, pid: int) -> void:
	var races: Dictionary = {}
	for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		races[CemeteryTriggersScript.normalize(str(c.get("card_raza")))] = true
	var has := func(r: String) -> bool: return races.keys().any(func(k): return r in k)
	if has.call("bestia") and await EnterScript._confirm(main, pid, _name(card), "Bestia: tus Aliados ganan 1 de Fuerza"):
		for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
			await _buff_turn(c, card, 1)
	if has.call("dragon") and main._gold_manager and await EnterScript._confirm(main, pid, _name(card), "Dragón: una carta de tu Cementerio a tu Oro Pagado"):
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: una carta de tu Cementerio como Oro sin habilidad" % _name(card), 1, 1)
		for pk in picks:
			if CardManager.take_from_cemetery(pid, pk.data):
				await EnterScript._data_to_paid_gold(main, pk.data, pid, pid)
	if has.call("sombra") and await EnterScript._confirm(main, pid, _name(card), "Sombra: tu oponente Destierra cuatro cartas del tope de su Castillo"):
		await ActionModule.mill(1 - pid, 4, true, _name(card))


static func _depredar(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 3, 3,
		"%s: hasta tres Aliados cuyos costes sumen 3 o menos" % _name(card))
	chosen = chosen.filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO)
	if not chosen.is_empty():
		await EnterScript._blank_indestructible_zero(card, chosen)


static func _oriflama(main: Node, card: Node, pid: int) -> void:
	var armed := EnterScript._all_allies(main, func(c): return c.get("equipped_weapons") is Array and not c.equipped_weapons.is_empty() \
		and (CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados que porten Armas" % _name(card), armed, 2, true)
	var weapons: int = CardQuery.weapons_in_play(pid).size()
	for c in chosen:
		if not is_instance_valid(c):
			continue
		KeywordManager.grant_keyword(c, Constants.Keyword.FURIA, card, "permanent")
		await _buff_turn(c, card, weapons)
		EffectController.add_single_card_leave_play_immunity(c, pid)


static func _conan_doyle(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var small := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2
	var hand_nodes: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_data") != null and small.call(c.card_data))
	var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": small.call(d)})
	if hand_nodes.is_empty() and not entries.any(func(e): return e.eligible):
		return
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: juega un Aliado de coste 2 o menos de tu mano o Cementerio" % _name(card),
		[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 1, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
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
		data = entries[ci].data
	data["esta_oculta"] = false
	if not await main._gold_manager.play_card_for_free(data, pid):
		CardManager.add_to_cemetery(pid, data)


static func _elemental(main: Node, card: Node, pid: int) -> void:
	var hand := EnterScript._hand(main, 1 - pid)
	if not hand.is_empty():
		var cards: Array = hand
		if hand.size() > 3:
			cards = await TriggerSystem._targeted_executor._select_hand_cards_for_discard(hand, 3, 1 - pid)
		await ActionModule.discard(1 - pid, cards.slice(0, 3), _name(card), true)
	if await EnterScript._confirm(main, pid, _name(card), "Buscar un Aliado Sherlock Holmes en tu Castillo"):
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ALIADO, "name_contains": "sherlock holmes"}, 1, true,
			false, false, card)


static func _murcielagos(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var seen: Array = []
	for _i in mini(6, deck.size()):
		seen.append(deck.pop_front())
	if seen.is_empty():
		return
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(seen, "%s: las primeras seis cartas de tu Castillo" % _name(card), pid)
	await EnterScript._look_place(main, card, pid, pid, seen, ["mano", "mano"])


static func _atacar_vampiro(main: Node, card: Node, pid: int) -> void:
	var all := _in_play_both(main, func(c): return c.get("is_converted") != true)
	var bot_rivals: Array = all.filter(func(c): return CardQuery.controller_of(c) != pid)
	var blank: Node = await EnterScript._pick_from(main, pid, "%s: una carta en juego queda sin habilidad" % _name(card),
		bot_rivals if PlayerSideScript.is_bot(pid) else all, false)
	if is_instance_valid(blank):
		await EnterScript._blank(blank, card)
	var small := EnterScript._in_play(main, 1 - pid, func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	var steal: Node = await EnterScript._pick_from(main, pid, "%s: gana el control de una carta de coste 2 o menos" % _name(card), small, false)
	if is_instance_valid(steal):
		ContinuousEffectManager.gain_control_of_card(steal, pid)


const RACES := ["Bestia", "Dragón", "Sombra", "Héroe", "Caballero", "Guerrero", "Eterno", "Faerie", "Sacerdote", "Bandido"]


static func _comite_animales(main: Node, card: Node, pid: int) -> void:
	var n: int = EnterScript._all_allies(main, func(c): return not ContinuousEffectManager.cost_at_most(c, 0)).size()
	for i in n:
		var deck: Array = CardManager.get_deck(pid)
		if deck.is_empty():
			break
		var race := "Bestia"
		if not PlayerSideScript.is_bot(pid):
			race = RACES[clampi(await SelectionManager.await_choice(main, "%s: Aliado %d de %d, elige su Raza" % [_name(card), i + 1, n], RACES, pid),
				0, RACES.size() - 1)]
		await LeavePlayScript._ally_from_data(main, deck.pop_front(), pid, pid, card, 2, [Constants.Keyword.FURIA], race)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _sombra_eterea(main: Node, card: Node, pid: int) -> void:
	var named := ""
	var named_type := -1
	if PlayerSideScript.is_bot(pid):
		var rivals := EnterScript._in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		if not rivals.is_empty():
			named = EnterScript._name(rivals[0])
			named_type = int(rivals[0].get("card_type"))
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"%s: nombra una carta: no se pueden utilizar sus habilidades por el turno" % _name(card), pid)
		named = str(picked.get("nombre", ""))
		named_type = int(picked.get("tipo", -1))
	if named.is_empty():
		return
	KeywordManager.lock_name_this_turn(named, -1)
	main._update_debug("%s: no se pueden utilizar habilidades de %s por el turno" % [_name(card), named])
	var shown := _reveal_until(main, pid, _name(card), func(s): return not s.is_empty() and int(s[-1].get("tipo", -1)) == named_type)
	if shown.is_empty():
		return
	var deck: Array = CardManager.get_deck(pid)
	if int(shown[-1].get("tipo", -1)) == named_type:
		PlayerSideScript.put_in_hand(main, pid, shown.pop_back())
	for d in shown:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(pid)
	AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % _name(card))


static func _cancha_rayada(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		var is_w := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and int(d.get("coste", 0)) <= 3
		var pools: Array = [
			{"is_own": true, "zone": Constants.Zone.CASTILLO, "exclusive": false, "cards": CardManager.get_deck(pid).map(func(d): return {"data": d, "eligible": is_w.call(d)})},
			{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "exclusive": false, "cards": CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": is_w.call(d)})},
		]
		var raw: Array = await ActionModule.pick_in_zones(pid, "%s: dos Armas cuyos costes sumen hasta 3" % _name(card), pools, 0, 2)
		var picked: Array = []
		var total := 0
		for rp in raw:
			if rp is Array and rp.size() == 2 and int(rp[0]) in [0, 1]:
				var e: Dictionary = pools[int(rp[0])].cards[int(rp[1])] if int(rp[1]) >= 0 and int(rp[1]) < pools[int(rp[0])].cards.size() else {}
				if not e.is_empty() and e.eligible and total + int(e.data.get("coste", 0)) <= 3 and picked.size() < 2:
					picked.append({"zone": int(rp[0]), "data": e.data})
					total += int(e.data.get("coste", 0))
		for pk in picked:
			if pk.zone == 0:
				CardManager.get_deck(pid).erase(pk.data)
			elif not CardManager.take_from_cemetery(pid, pk.data):
				continue
			pk.data["esta_oculta"] = false
			if not await main._gold_manager.play_card_for_free(pk.data, pid):
				CardManager.add_to_cemetery(pid, pk.data)
		CardManager.shuffle_deck(pid)
	EffectController.add_blanket_leave_play_immunity(pid)


static func _descanso_solar(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados ganan o pierden 3 de Fuerza" % _name(card),
		EnterScript._all_allies(main), 2, true)
	for c in chosen:
		if not is_instance_valid(c):
			continue
		var gain: bool = CardQuery.controller_of(c) == pid
		if not PlayerSideScript.is_bot(pid):
			gain = await SelectionManager.await_two_choice(main, "%s: %s" % [_name(card), EnterScript._name(c)], "Gana 3 de Fuerza", "Pierde 3 de Fuerza", pid)
		await _buff_turn(c, card, 3 if gain else -3)
		if is_instance_valid(c) and int(ContinuousEffectManager.get_modified_strength(c)) <= 0:
			await ActionModule.banish([c], card, true)
	var fighters: Array = []
	fighters.append_array(GameManager.attackers)
	fighters.append_array(GameManager.blockers.values())
	for c in fighters:
		if is_instance_valid(c):
			KeywordManager.grant_keyword(c, Constants.Keyword.INDESTRUCTIBLE, card, "turn")


static func _abordaje(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [1 - pid, pid], "%s: una carta de cualquier Cementerio" % _name(card), 1, 1)
	if picks.is_empty() or not CardManager.take_from_cemetery(picks[0].owner, picks[0].data):
		return
	var data: Dictionary = picks[0].data.duplicate()
	data["tipo"] = Constants.CardType.ALIADO
	data["fuerza"] = 0
	data["habilidad"] = "Indestructible. Tus Aliados pierden 2 de Fuerza."
	data["esta_oculta"] = false
	var node: Node = main._create_card(data, false)
	node.owner_id = picks[0].owner
	node.controller_id = 1 - pid
	main._connect_card_signals(node)
	PlayerSideScript.ally_containers(main, 1 - pid)[0].add_child(node)
	node.set_zone(Constants.Zone.LINEA_DEFENSA)
	node.can_interact = (1 - pid == 0)
	if CardFactory and CardFactory.has_method("on_card_enters_play"):
		CardFactory.on_card_enters_play(node)
	KeywordManager.scan_and_apply_keywords(node)
	main._update_debug("%s: %s es ahora un Aliado oponente de Fuerza 0" % [_name(card), str(data.get("nombre", ""))])


# =============================================================================
# TERCER LOTE
# =============================================================================
static func _silenciar_mundo(main: Node, card: Node, pid: int) -> void:
	var targets: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	targets.append_array(CardQuery.weapons_in_play(1 - pid))
	var until: int = GameManager.turn_serial + (2 if GameManager.active_player_id == pid else 1)  # hasta el final de tu próximo turno
	var total := 0
	for c in targets:
		if is_instance_valid(c):
			c.set_meta("silenced_until", until)  # KeywordManager.is_silenced
			total += EnterScript._cost(c)
	main._update_debug("%s: las Armas y Tótem oponentes pierden su habilidad" % _name(card))
	if total <= 3:
		var options: Array = ["Robar 0", "Robar 1", "Robar 2"]
		var n := 2
		if not PlayerSideScript.is_bot(pid):
			n = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta dos cartas" % _name(card), options, pid), 0)
		if n > 0:
			await ActionModule.draw(pid, n, _name(card), true)


static func _aklo(main: Node, card: Node, pid: int) -> void:
	var until: int = GameManager.turn_serial + (2 if GameManager.active_player_id == pid else 1) + 1
	for p in [0, 1]:
		RuleState.set_until("two_per_type", p, until)  # GoldManager._card_play_locked
	main._update_debug("%s: hasta el final de tu próximo turno, hasta dos cartas de cada tipo por turno" % _name(card))


## Juega una carta (datos ya fuera de su zona) pagando 'price'. false si no se pudo: el llamador la devuelve.
static func _play_paying(main: Node, pid: int, data: Dictionary, price: int) -> bool:
	if not main._gold_manager or not main._gold_manager.puede_pagar(price, -1, "", -1, pid):
		return false
	if price > 0 and not await PlayerSideScript.pay(main, pid, price):
		return false
	data["esta_oculta"] = false
	return await main._gold_manager.play_card_for_free(data, pid)


static func _cancer(main: Node, card: Node, pid: int) -> void:
	var allies: Array = []
	var shown := _reveal_until(main, pid, _name(card), func(s):
		if not s.is_empty() and int(s[-1].get("tipo", -1)) == Constants.CardType.ALIADO:
			allies.append(s[-1])
		return allies.size() >= 2)
	for a in allies:
		shown.erase(a)
	if not allies.is_empty():
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and allies.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: ¿cuál puedes jugar por un Oro menos? (el otro va a tu mano)" % _name(card),
				allies.map(func(d): return str(d.get("nombre", "?"))), pid), 0, allies.size() - 1)
		var to_play: Dictionary = allies.pop_at(idx)
		for d in allies:
			PlayerSideScript.put_in_hand(main, pid, d)
		var price: int = maxi(int(to_play.get("coste", 0)) - 1, 0)
		var play_it: bool = main._gold_manager and main._gold_manager.puede_pagar(price, -1, "", -1, pid)
		if play_it and not PlayerSideScript.is_bot(pid):
			play_it = await SelectionManager.await_two_choice(main, str(to_play.get("nombre", "")), "Jugarlo (coste %d)" % price, "A tu mano", pid)
		if not play_it or not await _play_paying(main, pid, to_play, price):
			PlayerSideScript.put_in_hand(main, pid, to_play)
	var deck: Array = CardManager.get_deck(pid)
	for d in shown:
		d["esta_oculta"] = true
		deck.append(d)
	CardManager.shuffle_deck(pid)
	AnimationQueue.queue_shuffle(pid, "Barajar mazo (%s)" % _name(card))


## corrupción del alma: "El próximo Aliado que juegues este turno reduce su coste en un Oro hasta un mínimo
## de 0..." (cost_modifiers se vacía al empezar el turno siguiente). "No puede ser Anulado ni sus
## habilidades canceladas" no se aplica.
static func _corrupcion_alma(main: Node, card: Node, pid: int) -> void:
	var serial: int = GameManager.turn_serial
	PaymentManager.agregar_modificador_coste(card, -1, func(c: Node) -> bool:
		return c.get("card_type") == Constants.CardType.ALIADO and c.get("owner_id") != null and int(c.owner_id) == pid \
			and int(TurnManager.ally_played_serial.get(pid, -1)) != serial, true)
	var deck: Array = CardManager.get_deck(pid)
	if not deck.is_empty():
		PlayerSideScript.put_in_hand(main, pid, deck.pop_back())
	var opp_deck: Array = CardManager.get_deck(1 - pid)
	for _i in mini(2, opp_deck.size()):
		var d: Dictionary = opp_deck.pop_front()
		d["esta_oculta"] = false
		CardManager.append_to_exile(1 - pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _humpty(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid):
		return
	var all: Array = EnterScript._hand(main, opp)
	if all.is_empty():
		return
	if not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	var allies: Array = all.filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO and int(c.get("card_cost")) <= 2)
	var chosen: Dictionary = {}
	if not allies.is_empty():
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and allies.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: elige un Aliado de coste 2 o menos" % _name(card),
				allies.map(func(c): return EnterScript._name(c)), pid), 0, allies.size() - 1)
		chosen = allies[idx].card_data.duplicate()
	var copy := not chosen.is_empty() and not CardManager.get_deck(pid).is_empty()
	if copy and not PlayerSideScript.is_bot(pid):
		copy = await SelectionManager.await_two_choice(main, _name(card), "Convertir la primera carta de tu Castillo en una copia de %s" % str(chosen.get("nombre", "")),
			"Generar un Oro por el turno", pid)
	if copy:
		CardManager.get_deck(pid).pop_front()  # esa carta pasa a ser la copia
		chosen["esta_oculta"] = false
		var node: Node = main._create_card(chosen, false)
		node.owner_id = pid
		node.controller_id = pid
		main._connect_card_signals(node)
		await main._gold_manager._play_card_to_field(node)
		if main.get("_zone_manager"):
			main._zone_manager._update_castillo_counts()
	elif main._gold_manager:
		main._gold_manager.generar_oros_virtuales(1, pid)


static func _remate_mortal(main: Node, card: Node, pid: int) -> void:
	var has_descanso := false
	for d in CardManager.get_cemetery(pid) + CardManager.get_exile(pid):
		if CemeteryTriggersScript.normalize(str(d.get("nombre", ""))) == "descanso solar":
			has_descanso = true
	var buff := true
	var revive := has_descanso
	if not has_descanso:
		buff = PlayerSideScript.is_bot(pid) or await SelectionManager.await_two_choice(main, _name(card),
			"Tus Aliados +1 y los oponentes -1 de Fuerza, permanentemente", "Juega una carta de tu Cementerio por un Oro menos", pid)
		revive = not buff
	if buff:
		for side in [pid, 1 - pid]:
			for c in EnterScript._in_play(main, side, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
				await _buff_turn(c, card, 1 if side == pid else -1, true)
	if revive and main._gold_manager:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega una carta de tu Cementerio por un Oro menos" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) != Constants.CardType.ORO and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid))
		for pk in picks:
			if CardManager.take_from_cemetery(pid, pk.data) and not await _play_paying(main, pid, pk.data, price.call(pk.data)):
				CardManager.add_to_cemetery(pid, pk.data)


static func _transformacion_lucy(main: Node, card: Node, pid: int) -> void:
	var mine: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM] \
		and c.get("owner_id") != null and int(c.owner_id) == pid)
	var steal := not mine.is_empty()
	if not PlayerSideScript.is_bot(pid):
		steal = await SelectionManager.await_two_choice(main, _name(card), "Ganar el control de un Aliado o Tótem del que seas dueño",
			"Al final del turno, un Aliado gana 2 de Fuerza permanentemente e Indesterrable", pid)
	if steal:
		var target: Node = await EnterScript._pick_from(main, pid, "%s: elige una carta de la que seas dueño" % _name(card), mine, false)
		if not is_instance_valid(target):
			return
		var cost: int = EnterScript._cost(target)
		ContinuousEffectManager.gain_control_of_card(target, pid)
		await EnterScript._discard_own(main, card, pid, cost)
		return
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
		var ally: Node = await EnterScript._pick_from(main, pid, "Transformación de Lucy: un Aliado gana 2 de Fuerza e Indesterrable", allies, false)
		if is_instance_valid(ally):
			await _buff_turn(ally, null, 2, true)
			KeywordManager.grant_keyword(ally, Constants.Keyword.INDESTERRABLE, null, "permanent"))


static func _hijos_noche(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty():
		return
	var entries: Array = deck.map(func(d): return {"data": d, "eligible": true})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta una carta de cada tipo del Castillo oponente" % _name(card),
		[{"is_own": false, "zone": Constants.Zone.CASTILLO, "cards": entries, "exclusive": true}], 0, 5)
	var banished: Array = []
	var types: Dictionary = {}
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size():
			var d: Dictionary = entries[int(rp[1])].data
			if not types.has(int(d.get("tipo", -1))) and not banished.has(d):
				types[int(d.get("tipo", -1))] = true
				banished.append(d)
	for d in banished:
		deck.erase(d)
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	CardManager.shuffle_deck(opp)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if banished.size() > 3 or not main._gold_manager:
		return
	var gold_here: Array = banished.filter(func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO)
	var pick: int = 0 if not gold_here.is_empty() else 1
	if not PlayerSideScript.is_bot(pid):
		pick = await SelectionManager.await_choice(main, _name(card),
			["Un Oro de ahí a tu Oro Pagado y Robar dos cartas", "Jugar una carta del Destierro oponente por un Oro menos", "Nada"], pid)
	if pick == 0 and not gold_here.is_empty():
		var g: Dictionary = gold_here[0]
		var exile: Array = CardManager.get_exile(opp)
		if exile.has(g):
			exile.erase(g)
			CardManager._emit_exile_changed(opp)
			var node: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, g)
			if is_instance_valid(node):
				node.owner_id = opp
		await ActionModule.draw(pid, 2, _name(card), true)
	elif pick == 1:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
		var exile: Array = CardManager.get_exile(opp)
		var e2: Array = exile.map(func(d): return {"data": d, "eligible": int(d.get("tipo", -1)) not in [Constants.CardType.TALISMAN, Constants.CardType.ORO] \
			and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)})
		var raw2: Array = await ActionModule.pick_in_zones(pid, "%s: una carta del Destierro oponente" % _name(card),
			[{"is_own": false, "zone": Constants.Zone.DESTIERRO, "cards": e2, "exclusive": true}], 0, 1)
		if raw2.is_empty() or not (raw2[0] is Array) or raw2[0].size() != 2:
			return
		var ci := int(raw2[0][1])
		if ci < 0 or ci >= e2.size() or not e2[ci].eligible:
			return
		var d2: Dictionary = e2[ci].data
		exile.erase(d2)
		CardManager._emit_exile_changed(opp)
		if not await _play_paying(main, pid, d2, price.call(d2)):
			CardManager.append_to_exile(opp, d2)


static func _avistamientos(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var both := false
	if not deck.is_empty():
		var top: Dictionary = deck[0]
		main._update_debug("%s muestra: %s" % [_name(card), str(top.get("nombre", "?"))])
		both = int(top.get("tipo", -1)) == Constants.CardType.ALIADO
		# La carta mostrada sigue en el Castillo, que se Baraja.
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(pid, [top], _name(card))
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").shuffle_back(main, pid, [], _name(card))
	var first := true
	if not both and not PlayerSideScript.is_bot(pid):
		first = await SelectionManager.await_two_choice(main, _name(card), "Barajar una carta de la mano oponente que no sea Oro",
			"En la próxima Fase Final oponente, mover un Oro oponente a su Oro Pagado", pid)
	if both or first:
		var opp: int = 1 - pid
		if not (EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid)):
			var all: Array = EnterScript._hand(main, opp)
			var options: Array = all.filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
			if not PlayerSideScript.is_bot(pid) and not all.is_empty():
				SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
			if not options.is_empty():
				var idx := 0
				if not PlayerSideScript.is_bot(pid) and options.size() > 1:
					idx = clampi(await SelectionManager.await_choice(main, "%s: elige una carta para Barajarla en su Castillo" % _name(card),
						options.map(func(c): return EnterScript._name(c)), pid), 0, options.size() - 1)
				PlayerSideScript.shuffle_from_hand(main, opp, options[idx], _name(card))
	if both or not first:
		var opp2: int = 1 - pid
		EffectController.schedule_next_final_phase_effect(opp2, func() -> void:
			var golds: Array = EnterScript._golds(main, [opp2]).filter(func(g): return g.get_parent() == PlayerSideScript.gold_reserva(main, opp2))
			if golds.is_empty() or not await EnterScript._confirm(main, pid, "Avistamientos", "Mover un Oro oponente a su Oro Pagado"):
				return
			var g: Node = await EnterScript._pick_from(main, pid, "Avistamientos: elige un Oro oponente", golds, true)
			if is_instance_valid(g):
				await LeavePlayScript._gold_to_paid(main, g))


static func _ataque_bandido(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Bandido en tu Castillo",
			"Jugar un Arma o Tótem de tu Cementerio o Destierro pagando su coste", pid)
	if search:
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"raza": "Bandido"}, 1, true, false, false, card)
		return
	if not main._gold_manager:
		return
	var ok := func(d) -> bool: return int(d.get("tipo", -1)) in [Constants.CardType.ARMA, Constants.CardType.TOTEM] \
		and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid)
	var pools: Array = [
		{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "exclusive": true, "cards": CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
		{"is_own": true, "zone": Constants.Zone.DESTIERRO, "exclusive": true, "cards": CardManager.get_exile(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})},
	]
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Arma o Tótem de tu Cementerio o Destierro" % _name(card), pools, 0, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi > 1 or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var d: Dictionary = pools[pi].cards[ci].data
	if pi == 0:
		if not CardManager.take_from_cemetery(pid, d):
			return
	else:
		CardManager.get_exile(pid).erase(d)
		CardManager._emit_exile_changed(pid)
	if not await _play_paying(main, pid, d, int(d.get("coste", 0))):
		if pi == 0:
			CardManager.add_to_cemetery(pid, d)
		else:
			CardManager.append_to_exile(pid, d)


static func _vigilia_armas(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	# "Dos Oros: juega sin pagar su coste hasta dos Aliados de tu Cementerio cuyos costes sumen 2."
	if main._gold_manager.puede_pagar(2, -1, "", -1, pid) and await EnterScript._confirm(main, pid, _name(card),
			"Pagar dos Oros: jugar hasta dos Aliados de tu Cementerio cuyos costes sumen 2") and await PlayerSideScript.pay(main, pid, 2):
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: hasta dos Aliados cuyos costes sumen 2" % _name(card), 0, 2,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2)
		var total := 0
		for pk in picks:
			if total + int(pk.data.get("coste", 0)) > 2 or not CardManager.take_from_cemetery(pid, pk.data):
				continue
			total += int(pk.data.get("coste", 0))
			pk.data["esta_oculta"] = false
			if not await main._gold_manager.play_card_for_free(pk.data, pid):
				CardManager.add_to_cemetery(pid, pk.data)
	# "Un Oro: tus Aliados ganan 1 de Fuerza y hacen daño al Destierro este turno."
	if main._gold_manager.puede_pagar(1, -1, "", -1, pid) and await EnterScript._confirm(main, pid, _name(card),
			"Pagar un Oro: tus Aliados +1 de Fuerza y daño al Destierro este turno") and await PlayerSideScript.pay(main, pid, 1):
		for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
			await _buff_turn(c, card, 1)
			c.set_meta("damage_to_exile_turn", GameManager.turn_serial)


static func _proteger_botin(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
		var ok := func(d) -> bool: return int(d.get("tipo", -1)) == Constants.CardType.ARMA and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)
		var hand_nodes: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_data") != null and ok.call(c.card_data))
		var entries: Array = CardManager.get_cemetery(pid).map(func(d): return {"data": d, "eligible": ok.call(d)})
		if not hand_nodes.is_empty() or entries.any(func(e): return e.eligible):
			var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Arma de tu mano o Cementerio por un Oro menos" % _name(card),
				[{"is_own": true, "zone": Constants.Zone.CEMENTERIO, "cards": entries, "exclusive": true}], 1, 1, false, hand_nodes)
			if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2:
				var data: Dictionary = {}
				if int(raw[0][0]) == -1 and int(raw[0][1]) >= 0 and int(raw[0][1]) < hand_nodes.size():
					data = PlayerSideScript.take_from_hand(main, pid, hand_nodes[int(raw[0][1])])
				elif int(raw[0][0]) == 0 and int(raw[0][1]) >= 0 and int(raw[0][1]) < entries.size() and entries[int(raw[0][1])].eligible \
						and CardManager.take_from_cemetery(pid, entries[int(raw[0][1])].data):
					data = entries[int(raw[0][1])].data
				if not data.is_empty() and not await _play_paying(main, pid, data, price.call(data)):
					CardManager.add_to_cemetery(pid, data)
		# "Puedes cambiar cualquier cantidad de Armas que controles de portador."
		while not CardQuery.weapons_in_play(pid).is_empty() and not PlayerSideScript.is_bot(pid) \
				and await SelectionManager.await_two_choice(main, _name(card), "Cambiar un Arma de portador", "Listo", pid):
			var w: Node = await EnterScript._pick_from(main, pid, "%s: elige un Arma" % _name(card), CardQuery.weapons_in_play(pid), true)
			if not is_instance_valid(w):
				break
			var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and c != w.get_parent())
			var nw: Node = await EnterScript._pick_from(main, pid, "%s: su nuevo portador" % _name(card), allies, true)
			if not is_instance_valid(nw):
				break
			var old = w.get_parent()
			if old and old.get("equipped_weapons") is Array:
				old.equipped_weapons.erase(w)
			await main._gold_manager._equip_weapon(w, nw, false)
	# "Los Aliados que porten Armas no pueden salir de juego este turno."
	for c in EnterScript._in_play(main, pid, func(c): return c.get("equipped_weapons") is Array and not c.equipped_weapons.is_empty()):
		c.set_meta("no_leave_turn", GameManager.turn_serial)


## Amarre de Bruja: "Gana el control del Aliado oponente, mientras tu Aliado esté en juego." Cuando tu
## Aliado sale del juego, el otro vuelve a su dueño.
static func _amarre_bruja(main: Node, card: Node, pid: int) -> void:
	var mine := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) >= 2)
	var anchor: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado que controles de coste 2 o más" % _name(card), mine, false)
	if not is_instance_valid(anchor):
		return
	var limit: int = int(ContinuousEffectManager.get_modified_strength(anchor))
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and int(ContinuousEffectManager.get_modified_strength(c)) <= limit)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado oponente de Fuerza %d o menos" % [_name(card), limit], rivals, false)
	if not is_instance_valid(target):
		return
	ContinuousEffectManager.gain_control_of_card(target, pid)
	var release: Callable
	release = func(_p: int, left: Node, _z: int) -> void:
		if left != anchor:
			return
		if EffectController.on_card_left_play.is_connected(release):
			EffectController.on_card_left_play.disconnect(release)
		if is_instance_valid(target) and target.get("current_zone") in Constants.ZONES_IN_PLAY and target.get("owner_id") != null:
			ContinuousEffectManager.gain_control_of_card(target, int(target.owner_id))
	EffectController.on_card_left_play.connect(release)


# =============================================================================
# INMUNIDAD A EFECTOS OPONENTES
# =============================================================================
static func _jugando_demonio(main: Node, card: Node, pid: int) -> void:
	for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		KeywordManager.grant_keyword(c, Constants.Keyword.IMBLOQUEABLE, card, "turn")
		await _buff_turn(c, card, 1)
		c.set_meta("attack_uncancellable_turn", GameManager.turn_serial)  # ProtectionRules.attack_uncancellable


## Fuego Purificador / Rugido de Titán: "Prevén que una carta sea afectada por un efecto oponente" — en el
## momento: la carta elegida no es afectada por el efecto rival que está en la pila (meta
## "prevent_effect_of", que mira EffectController.opp_immune_card()). Sin efecto rival en la pila, no hace
## nada.
static func _protect_one(main: Node, card: Node, pid: int, filter: Callable, prompt: String) -> Node:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, true)
	var source = StackAnnulScript.card_of(obj) if not obj.is_empty() else null
	var mine := EnterScript._in_play(main, pid, filter) + EnterScript._golds(main, [pid]).filter(filter)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: %s" % [_name(card), prompt], mine, false)
	if not is_instance_valid(target):
		return null
	if source != null and is_instance_valid(source):
		target.set_meta("prevent_effect_of", {"source_id": source.get_instance_id(), "turn": GameManager.turn_serial})
		main._update_debug("%s: %s no será afectada por %s" % [_name(card), EnterScript._name(target), EnterScript._name(source)])
	else:
		main._update_debug("%s: no hay un efecto oponente en curso que prevenir" % _name(card))
	return target


static func _fuego_purificador(main: Node, card: Node, pid: int) -> void:
	await _protect_one(main, card, pid, func(_c): return true, "elige una carta que controles")


static func _rugido_titan(main: Node, card: Node, pid: int) -> void:
	var is_named := func(c) -> bool:
		var n := CemeteryTriggersScript.normalize(str(c.get("card_name")))
		return "ignis" in n or "titan" in n
	# "...sea Anulada, cancelada": si la carta Ignis o Titán está en la pila (jugándose o con su habilidad),
	# no puede ser Anulada ni cancelada este turno.
	for obj in ActionPipeline.get_stack():
		var node = StackAnnulScript.card_of(obj)
		if node != null and is_instance_valid(node) and is_named.call(node) and CardQuery.controller_of(node) == pid:
			node.set_meta("protected_from_annul_this_turn", true)
			node.set_meta("protected_from_cancel_turn", GameManager.turn_serial)
	await _protect_one(main, card, pid, is_named, "elige una carta de nombre Ignis o Titán")



## viaje temporal: "Al finalizar este turno, gana un turno extra. Ese turno tu oponente no puede recibir
## daño." GameManager.end_turn() consume el pendiente "extra_turn" y no cambia de jugador.
static func _viaje_temporal(main: Node, card: Node, pid: int) -> void:
	RuleState.set_pending("extra_turn", pid, true)
	var until: int = GameManager.turn_serial + 2  # vale hasta que termina el turno extra
	for kind in ["no_combat_damage", "no_direct_damage"]:
		RuleState.set_until(kind, 1 - pid, until)
	main._update_debug("%s: al finalizar este turno ganas un turno extra" % _name(card))



# =============================================================================
# EN RESPUESTA A ALGO
# =============================================================================
const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")
const DamageShieldsScript = preload("res://scripts/core/effects/mechanics/DamageShields.gd")


## La carta rival que se está jugando (la más cercana al tope de la pila). {} si no hay.
static func _opponent_card_on_stack(pid: int, filter: Callable = Callable()) -> Dictionary:
	return StackAnnulScript.find_target(pid, true, false, filter)


static func _expulsion(main: Node, card: Node, pid: int) -> void:
	var obj := _opponent_card_on_stack(pid)
	if obj.is_empty():
		main._update_debug("%s: no hay una carta oponente jugándose" % _name(card))
		return
	if StackAnnulScript.type_of(obj) == Constants.CardType.TALISMAN:
		TriggerSystem._totem_patterns.register_kotoku_in_talisman_fizzle(1 - pid)  # se resuelve sin efecto
	else:
		var node = StackAnnulScript.card_of(obj)
		if node != null and is_instance_valid(node):
			node.set_meta("silenced_until", GameManager.turn_serial)  # entra sin habilidad por el turno
	main._update_debug("%s: %s queda sin habilidad" % [_name(card), str(StackAnnulScript.data_of(obj).get("nombre", "esa carta"))])


static func _descubrir_zorro(main: Node, card: Node, pid: int) -> void:
	var obj := _opponent_card_on_stack(pid, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.ALIADO)
	var node = StackAnnulScript.card_of(obj) if not obj.is_empty() else null
	if node == null or not is_instance_valid(node):
		main._update_debug("%s: no hay un Aliado oponente entrando en juego" % _name(card))
		return
	node.set_meta("silenced_until", 1 << 30)  # sin habilidad (permanente)
	main._update_debug("%s: %s entra en juego sin habilidad" % [_name(card), EnterScript._name(node)])


static func _iluminar(main: Node, card: Node, pid: int) -> void:
	var obj := _opponent_card_on_stack(pid)
	var opp: int = 1 - pid
	if not obj.is_empty():
		var t: int = StackAnnulScript.type_of(obj)
		# La carta en la pila todavía no se contó: esa y una más.
		RuleState.set_turn_data("iluminar:%d" % opp, {"type": t, "allowed": RuleState.count("played_type:%d" % t, opp) + 2})
	if main._gold_manager:
		main._gold_manager.set_no_more_cards_this_turn(pid)


static func _ofrenda_abuelos(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar hasta dos cartas de distinto nombre en un Castillo y Desterrarlas",
			"Prevenir que tu oponente busque cartas en tu Castillo", pid)
	if not search:
		RuleState.set_turn_data("castle_search_block:%d" % pid, {"on": true})  # EffectController.fision_hides_zones_of
		main._update_debug("%s: tu oponente no puede buscar cartas en tu Castillo este turno" % _name(card))
		return
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	await ActionModule.search(owner, Constants.Zone.CASTILLO, {}, 2, true, false, false, card, Constants.Zone.DESTIERRO, true, pid)


static func _puertas(main: Node, card: Node, pid: int) -> void:
	DamageShieldsScript.add_next_zero(pid)
	var lines: Array = PlayerSideScript.ally_containers(main, 1 - pid)
	var n: int = lines[1].get_children().filter(func(c): return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO).size() 		if lines.size() > 1 else 0
	if n > 0:
		await ActionModule.mill(1 - pid, 2 * n, false, _name(card))


static func _arlequin(main: Node, card: Node, pid: int) -> void:
	DamageShieldsScript.add_arlequin(pid)
	main._update_debug("%s: se previene todo el daño a tu Castillo este turno" % _name(card))


# =============================================================================
# LÍMITES Y TEXTOS NUEVOS
# =============================================================================
## Último turn_serial (exclusivo, para RuleState.set_until) de "hasta el final de tu próximo turno".
static func _end_of_next_own_turn(pid: int) -> int:
	return GameManager.turn_serial + (2 if GameManager.active_player_id == pid else 1) + 1


## "Prevén un efecto" (Concilio de los Eternos, Camino del Guerrero): el efecto rival más cercano al tope
## de la pila no se resuelve (StackAnnul.prevent: no es Cancelar, vale aunque no pueda ser cancelado).
static func _prevent_an_effect(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_preventable(pid)
	if obj.is_empty():
		main._update_debug("%s: no hay un efecto oponente que prevenir" % _name(card))
		return
	StackAnnulScript.prevent(obj)


static func _sabiduria_oruga(main: Node, card: Node, pid: int) -> void:
	await EnterScript._peek_banish(main, card, pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and int(c.get("card_cost")) <= 2, 2)
	var until := _end_of_next_own_turn(pid)
	for p in [0, 1]:
		RuleState.set_until("attack_cap_1", p, until)  # GameManager.attack_cap
		RuleState.set_until("draw_cap_3", p, until)  # ActionModule.draw
	main._update_debug("%s: hasta el final de tu próximo turno, un solo atacante y hasta tres robos por efectos por turno" % _name(card))


static func _concilio(main: Node, card: Node, pid: int) -> void:
	await _prevent_an_effect(main, card, pid)
	RuleState.set_turn_data("attack_cap_2:%d" % (1 - pid), {"on": true})


static func _camino_guerrero(main: Node, card: Node, pid: int) -> void:
	await _prevent_an_effect(main, card, pid)
	for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
		await _buff_turn(c, card, 1, true)


static func _pereza(main: Node, card: Node, pid: int) -> void:
	# "Los próximos dos turnos": el siguiente y el que le sigue (no el actual).
	var from: int = GameManager.turn_serial + 1
	var until: int = GameManager.turn_serial + 3
	for p in [0, 1]:
		RuleState.set_window("no_attacks", p, from, until)
	RuleState.set_window("one_card_turn", pid, from, until)
	main._update_debug("%s: los próximos dos turnos no se puede atacar y no puedes jugar más de una carta por turno" % _name(card))


static func _no_mas_magia(main: Node, card: Node, _pid: int) -> void:
	for p in [0, 1]:
		RuleState.set_until("no_mas_magia", p, 1 << 30)
	main._update_debug("%s: jugar Talismanes y cartas sin pagar su coste cuesta un Oro adicional por el resto del juego" % _name(card))


static func _escudo_estelar(main: Node, card: Node, pid: int) -> void:
	# Hasta tu próxima Fase Final: si es tu turno, la de este turno.
	var until: int = GameManager.turn_serial + (1 if GameManager.active_player_id == pid else 2)
	for p in [0, 1]:
		RuleState.set_until("zones_hidden", p, until)  # EffectController.fision_hides_zones_of
	main._update_debug("%s: nadie puede buscar ni mirar la mano o los Castillos por efectos hasta tu próxima Fase Final" % _name(card))


static func _a_traves_espejo(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: un Aliado de coste 2 o menos de tu Cementerio (su habilidad)" % _name(card), 1, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and int(d.get("coste", 0)) <= 2 and not str(d.get("habilidad", "")).strip_edges().is_empty())
	if not allies.is_empty() and not picks.is_empty():
		var target: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado que controles" % _name(card), allies, false)
		if is_instance_valid(target):
			var base: String = str(target.get("card_ability")).strip_edges()
			EnterScript.set_ability(target, (base + " " if not base.is_empty() else "") + str(picks[0].data.get("habilidad", "")).strip_edges())
	var exhumar_or_furia := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and (KeywordManager.has_keyword(c, Constants.Keyword.FURIA) or "exhumar" in CemeteryTriggersScript.normalize(str(c.get("card_ability")))))
	if exhumar_or_furia.is_empty():
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia o Imbloqueable" % _name(card), allies, false)
	if not is_instance_valid(ally):
		return
	var kw: int = Constants.Keyword.FURIA
	if not PlayerSideScript.is_bot(pid) and not await SelectionManager.await_two_choice(main, _name(card), "Furia", "Imbloqueable", pid):
		kw = Constants.Keyword.IMBLOQUEABLE
	KeywordManager.grant_keyword(ally, kw, null, "permanent")


static func _todos_locos(main: Node, card: Node, pid: int) -> void:
	var small := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) <= 2)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado de coste 2 o menos que controles" % _name(card), small, false)
	if not is_instance_valid(target):
		return
	var cost: int = EnterScript._cost(target)
	var models := EnterScript._in_play(main, pid, func(c): return c != target and c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) == cost)
	var model: Node = await EnterScript._pick_from(main, pid, "%s: el Aliado que copia" % _name(card), models, false)
	if not is_instance_valid(model):
		return
	var data: Dictionary = model.card_data.duplicate()
	data["esta_oculta"] = false
	var owner = target.get("owner_id")
	var ctrl = target.get("controller_id")
	target.load_from_data(data)
	target.owner_id = owner
	target.controller_id = ctrl
	EnterScript.set_ability(target, str(data.get("habilidad", "")))
	main._update_debug("%s: ahora es una copia de %s" % [_name(card), EnterScript._name(model)])


static func _captura_colosal(main: Node, card: Node, pid: int) -> void:
	var mine := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var theirs := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var a: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles" % _name(card), mine, false)
	var b: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado oponente" % _name(card), theirs, false)
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var sa: int = int(ContinuousEffectManager.get_modified_strength(a))
	var sb: int = int(ContinuousEffectManager.get_modified_strength(b))
	var losers: Array = [a] if sa < sb else ([b] if sb < sa else [a, b])  # empate: los dos
	for c in losers:
		EnterScript.set_ability(c, "En tu Fase Final, Destierra las primeras dos cartas de tu Castillo.")
		for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
			ContinuousEffectManager.register_modifier({
				"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.RESTRICTION,
				"restriction_type": restriction, "duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
				"description": "%s: no ataca ni bloquea" % _name(card),
			})


static func _dia_muertos(main: Node, card: Node, _pid: int) -> void:
	for c in EnterScript._all_allies(main):
		EnterScript.set_ability(c, "No puede portar Armas.")  # GoldManagerRestrictions._max_weapons_for
		ContinuousEffectManager.register_modifier({
			"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 1, "operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "%s: Fuerza 1" % _name(card),
		})
		if c.has_method("refresh_strength_badge"):
			c.refresh_strength_badge()


static func _identidad_secreta(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		return StackAnnulScript.type_of(o) in [Constants.CardType.ARMA, Constants.CardType.TOTEM] and StackAnnulScript.cost_of(o) <= 3)
	var annul := not obj.is_empty()
	if annul and not PlayerSideScript.is_bot(pid):
		annul = await SelectionManager.await_two_choice(main, _name(card), "Anular %s y Desterrarla" % str(StackAnnulScript.data_of(obj).get("nombre", "")),
			"Desterrar las Armas en juego o un Tótem", pid)
	if annul:
		# "...y Destierra esa carta": la Anulada va al Destierro y no al Cementerio (meta annul_to_exile,
		# la misma de Red de Plata, que mira GoldManager al recibir la anulación).
		var node = StackAnnulScript.card_of(obj)
		if node != null and is_instance_valid(node) and not StackAnnulScript.protected_from_annul(obj):
			node.set_meta("annul_to_exile", true)
		StackAnnulScript.apply(obj, card)
		return
	var weapons: Array = CardQuery.weapons_in_play(0) + CardQuery.weapons_in_play(1)
	var totems := _in_play_both(main, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	var all_weapons := not weapons.is_empty()
	if not PlayerSideScript.is_bot(pid) and not weapons.is_empty() and not totems.is_empty():
		all_weapons = await SelectionManager.await_two_choice(main, _name(card), "Desterrar las Armas en juego", "Desterrar un Tótem", pid)
	if all_weapons:
		await ActionModule.banish(weapons, card, true)
	else:
		var t: Node = await EnterScript._pick_from(main, pid, "%s: Destierra un Tótem" % _name(card),
			totems.filter(func(c): return CardQuery.controller_of(c) != pid) if PlayerSideScript.is_bot(pid) else totems, false)
		if is_instance_valid(t):
			await ActionModule.banish([t], card, true)


## julio verne: "Sube cualquier cantidad de Aliados que controles a tu mano. Al comienzo de tu próximo
## turno juégalos sin pagar su coste, y ganan 1 de Fuerza permanentemente."
static func _julio_verne(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: Aliados que suben a tu mano" % _name(card), allies, allies.size(), true)
	var names: Array = []
	for c in chosen:
		if is_instance_valid(c):
			names.append(EnterScript._name(c))
			await EnterScript.bounce_to_owner_hand(main, c, card)
	if names.is_empty():
		return
	var replay: Callable
	replay = func(started: int, _turn: int) -> void:
		if started != pid:
			return
		GameManager.turn_started.disconnect(replay)
		for n in names:
			var node: Node = null
			for h in PlayerSideScript.hand_cards(main, pid):
				if is_instance_valid(h) and EnterScript._name(h) == n:
					node = h
					break
			if node == null:
				continue
			var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, node)
			if await main._gold_manager.play_card_for_free(data, pid):
				for c in EnterScript._in_play(main, pid, func(x): return EnterScript._name(x) == n):
					await _buff_turn(c, null, 1, true)
					break
	GameManager.turn_started.connect(replay)



## Marca de los Justos: ContinuousEffectManager.register_modifier() duplica las ganancias de Fuerza que
## vengan después (máximo 4 por vez) e ignora cualquier otra modificación, por el turno.
static func _marca_justos(main: Node, card: Node, _pid: int) -> void:
	RuleState.set_turn_data("marca_justos", {"on": true})
	main._update_debug("%s: este turno, cada ganancia de Fuerza es el doble (máximo 4)" % _name(card))



# =============================================================================
# CUARTO LOTE
# =============================================================================
static func _niebla_muerte(main: Node, card: Node, pid: int) -> void:
	# "Las cartas que sean puestas en el Cementerio este turno pierden su habilidad por el turno."
	var serial: int = GameManager.turn_serial
	var mark: Callable
	mark = func(_owner: int, data: Dictionary) -> void:
		if GameManager.turn_serial != serial:
			CardManager.card_put_in_cemetery.disconnect(mark)
			return
		data["_silenced_turn"] = serial  # CardManager.is_cemetery_card_silenced
	CardManager.card_put_in_cemetery.connect(mark)
	var small := _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3))
	if PlayerSideScript.is_bot(pid):
		small = small.filter(func(c): return CardQuery.controller_of(c) != pid)
	var one: Array = await EnterScript._pick_many(main, pid, "%s: Destruye hasta una carta de coste 3 o menos" % _name(card), small, 1, true)
	if not one.is_empty():
		await ActionModule.destroy(one, card, true)
	await ActionModule.mill(1 - pid, 7, false, _name(card))


static func _comer_insectos(main: Node, card: Node, pid: int) -> void:
	var mine := _in_play_both(main, func(c): return CardQuery.controller_of(c) == pid and c.get("card_type") != Constants.CardType.ORO \
		and not str(c.get("card_ability")).strip_edges().is_empty() and not KeywordManager.is_silenced(c) and EnterScript._cost(c) >= 1)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: Destruye hasta dos cartas con habilidad de coste 1 o más que controles" % _name(card),
		mine, 2, true)
	var destroyed := 0
	if not chosen.is_empty():
		var res: Dictionary = await ActionModule.destroy(chosen, card, true)
		destroyed = chosen.filter(func(c): return not is_instance_valid(c) or not (c.get("current_zone") in Constants.ZONES_IN_PLAY)).size() \
			if res.get("success", true) else 0
	if destroyed > 0:
		for c in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO):
			await _buff_turn(c, card, destroyed)
	RuleState.set_turn_data("unpreventable_damage:%d" % pid, {"on": true})  # BattleManager._apply_castle_damage


static func _anillo_tierra(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	RuleState.set_turn_data("one_more_action:%d" % opp, {"cards": RuleState.count("played_any", opp), "abilities": RuleState.count("abilities_used", opp)})
	var next_turn: int = RuleState.next_own_turn(pid)
	RuleState.set_window("one_card_turn", pid, next_turn, next_turn + 1)  # "Sólo puedes jugar una carta el próximo turno"
	main._update_debug("%s: tu oponente solo puede jugar una carta más o utilizar una habilidad más este turno" % _name(card))


static func _duelo_magico(main: Node, card: Node, pid: int) -> void:
	var totals: Array = [0, 0]
	for p in [0, 1]:
		var hand: Array = EnterScript._hand(main, p)
		for c in hand:
			totals[p] += int(c.get("card_cost")) if c.get("card_cost") != null else 0
		main._update_debug("%s: mano del jugador %d: %s (coste total %d)" % [_name(card), p + 1,
			", ".join(hand.map(func(c): return EnterScript._name(c))), totals[p]])
	var losers: Array = [0] if totals[0] > totals[1] else ([1] if totals[1] > totals[0] else [0, 1])
	for p in losers:
		RuleState.set_until("mill_cap_10", p, 1 << 30)  # ActionModule.mill
		RuleState.set_until("hand_loss_cap_1", p, 1 << 30)  # ActionModule.discard / EnterPatterns._exile_from_hand


## Sesión Espiritista: la reducción del daño de combate (DamageShields) y, hasta tu próximo turno, cuando tu
## oponente Roba por un efecto, puedes poner la misma cantidad del tope de tu Castillo en tu mano
## (ActionModule.draw → on_opponent_effect_draw). Otras formas de "poner cartas en su mano" no se cuentan.
static func _sesion_espiritista(main: Node, card: Node, pid: int) -> void:
	DamageShieldsScript.add_permanent_reduction(pid)
	RuleState.set_until("sesion_espiritista", pid, RuleState.next_own_turn(pid))
	main._update_debug("%s: el daño de combate a tu Castillo se reduce en dos por el resto del juego" % _name(card))


static func on_opponent_effect_draw(drawer: int, amount: int) -> void:
	var watcher: int = 1 - drawer
	if amount <= 0 or not RuleState.active("sesion_espiritista", watcher):
		return
	var main := CardQuery.main_node()
	if not main or not await EnterScript._confirm(main, watcher, "Sesión Espiritista", "Poner %d carta(s) del tope de tu Castillo en tu mano" % amount):
		return
	var deck: Array = CardManager.get_deck(watcher)
	for _i in mini(amount, deck.size()):
		PlayerSideScript.put_in_hand(main, watcher, deck.pop_front())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _terremoto(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._all_allies(main)
	if PlayerSideScript.is_bot(pid):
		allies = allies.filter(func(c): return CardQuery.controller_of(c) == pid)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado duplica su Fuerza hasta tu próximo turno" % _name(card), allies, false)
	if not is_instance_valid(target):
		return
	var anticucho: bool = false
	var weapons = target.get("equipped_weapons")
	if weapons is Array:
		anticucho = weapons.any(func(w): return is_instance_valid(w) and "anticucho" in CemeteryTriggersScript.normalize(str(w.get("card_name"))))
	var strength: int = int(ContinuousEffectManager.get_modified_strength(target))
	var turns: int = 2 if GameManager.active_player_id == pid else 1  # fines de turno hasta tu próximo turno
	ContinuousEffectManager.register_modifier({
		"source": null, "target": target, "type": ContinuousEffectManager.ModifierType.STRENGTH,
		"stat": "strength", "value": strength * (2 if anticucho else 1), "operation": "add",
		"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": turns,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY, "description": "%s: Fuerza %s" % [_name(card), "triple" if anticucho else "doble"],
	})
	if target.has_method("refresh_strength_badge"):
		target.refresh_strength_badge()
	target.set_meta("terremoto", {"until": RuleState.next_own_turn(pid) - 1, "pid": pid, "printed": anticucho})  # GameManager._terremoto_mill


static func _furia_titan(main: Node, card: Node, pid: int) -> void:
	var allies := EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: elige un Aliado que controles" % _name(card), allies, false)
	if not is_instance_valid(target):
		return
	var lines: Array = PlayerSideScript.ally_containers(main, pid)
	var until: int = RuleState.next_own_turn(pid) - 1
	if lines.size() > 1 and target.get_parent() == lines[1]:
		EffectController.add_single_card_leave_play_immunity(target, pid)
		target.set_meta("damage_to_exile_turn", GameManager.turn_serial)
		main._update_debug("%s: %s no puede salir del juego por efectos y su daño va al Destierro" % [_name(card), EnterScript._name(target)])
	else:
		GameManager.attack_strength_caps[1 - pid] = {"node": target, "until": until}  # TurnManager.can_attack
		main._update_debug("%s: tu oponente no puede atacar con Aliados de mayor Fuerza que %s" % [_name(card), EnterScript._name(target)])


static func _marca_bestia(main: Node, card: Node, pid: int) -> void:
	var small := EnterScript._all_allies(main, func(c): return EnterScript._cost(c) <= 2)
	if PlayerSideScript.is_bot(pid):
		small = small.filter(func(c): return CardQuery.controller_of(c) == pid)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado de coste 2 o menos" % _name(card), small, false)
	if not is_instance_valid(target):
		return
	for kw in [Constants.Keyword.FURIA, Constants.Keyword.INDESTRUCTIBLE]:
		KeywordManager.grant_keyword(target, kw, null, "until_next_turn")
	target.set_meta("must_fight_turn", GameManager.turn_serial)  # GameManager._declare_forced_attackers
	var until: int = RuleState.next_own_turn(pid) - 1
	target.set_meta("no_control_change_until", until)  # ContinuousEffectManager.gain_control_of_card
	target.set_meta("no_convert_until", until)


static func _ta_kona(main: Node, card: Node, pid: int) -> void:
	RuleState.set_pending("extra_battle", pid, true)  # PhaseFlowController._on_battle_combat_finished
	main._update_debug("%s: al final de esta Batalla Mitológica ganas una adicional" % _name(card))


## nuevas tierras: tus Oros pasan a ser Aliados de Fuerza 3 sin habilidad que no pueden salir del juego este
## turno; en la Fase Final vuelven a ser Oros, en tu Oro Pagado.
static func _nuevas_tierras(main: Node, card: Node, pid: int) -> void:
	var golds: Array = EnterScript._golds(main, [pid])
	if golds.is_empty():
		return
	var field: Node = PlayerSideScript.ally_containers(main, pid)[0]
	var converted: Array = []
	for g in golds:
		var was_paid: bool = g.get_parent() == PlayerSideScript.oro_pagado(main, pid)
		if was_paid:
			GameState.agregar_oro_pagado(pid, -1)
		else:
			GameState.agregar_oro_reserva(pid, -1)
		g.get_parent().remove_child(g)
		g.card_type = Constants.CardType.ALIADO
		g.scale = Vector2.ONE
		g.base_scale = Vector2.ONE
		g.modulate = Color.WHITE
		field.add_child(g)
		g.set_zone(Constants.Zone.LINEA_DEFENSA)
		await ConvertScript._finish_conversion(g, card, pid, 3, [], false)
		g.set_meta("no_leave_turn", GameManager.turn_serial)
		converted.append(g)
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	EffectController.schedule_next_final_phase_effect(pid, func() -> void:
		for g in converted:
			if is_instance_valid(g) and g.get("current_zone") in Constants.ZONES_IN_PLAY:
				ContinuousEffectManager.remove_modifiers_from_source(g)
				g.get_parent().remove_child(g)
				g.card_type = Constants.CardType.ORO
				g.is_converted = false
				KeywordManager.clear_all_for_card(g)  # vuelve a tener su habilidad de Oro
				PlayerSideScript.oro_pagado(main, pid).add_child(g)
				g.set_zone(Constants.Zone.ORO_PAGADO)
				g.scale = Constants.GOLD_CARD_SCALE
				g.base_scale = Constants.GOLD_CARD_SCALE
				g.modulate = Color(0.6, 0.6, 0.6, 1.0)
				GameState.agregar_oro_pagado(pid, 1)
		if main._gold_manager:
			main._gold_manager._update_gold_display()
		main._update_debug("nuevas tierras: los Aliados vuelven a ser Oros en tu Oro Pagado"))


static func _alma_viento(main: Node, card: Node, pid: int) -> void:
	await _raise_one(main, pid, "%s: sube una carta de tu Cementerio a tu mano" % _name(card), false)
	# "Cuando este Talismán se resuelva, conviértelo en un Oro con la habilidad ... y ponlo en el Oro Pagado
	# oponente": cuando llega al Cementerio después de resolverse, sale de ahí como ese Oro.
	var data: Dictionary = card.card_data if is_instance_valid(card) else {}
	var name := str(data.get("nombre", ""))
	var once: Callable
	once = func(owner_id: int, d: Dictionary) -> void:
		if str(d.get("nombre", "")) != name:
			return
		CardManager.card_put_in_cemetery.disconnect(once)
		if not CardManager.take_from_cemetery(owner_id, d) or not main._gold_manager:
			return
		var gold_data: Dictionary = d.duplicate()
		gold_data["tipo"] = Constants.CardType.ORO
		gold_data["habilidad"] = "No puede ser agrupado. Los Aliados oponentes ganan 1 de Fuerza y tus Aliados pierden 1 de Fuerza."
		var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(1 - pid, gold_data)
		if is_instance_valid(gold):
			gold.owner_id = owner_id
			gold.set_meta("never_regroup", true)  # GoldManager._reset_gold / EasyBot.reset_gold
	CardManager.card_put_in_cemetery.connect(once)


static func _estaca(main: Node, card: Node, pid: int) -> void:
	# "Utiliza una habilidad activada de una carta de coste 2 o menos en un Cementerio o Destierro como si la
	# controlaras": una que el compilador entiende entera, sobre un Nodo temporal (como los farsarios).
	var pools: Array = []
	var clauses: Array = []
	for p in [pid, 1 - pid]:
		for zone in [Constants.Zone.CEMENTERIO, Constants.Zone.DESTIERRO]:
			var arr: Array = CardManager.get_cemetery(p) if zone == Constants.Zone.CEMENTERIO else CardManager.get_exile(p)
			var entries: Array = []
			for d in arr:
				var clause: String = LeavePlayScript._activated_clause(d) if int(d.get("coste", 0)) <= 2 and int(d.get("tipo", -1)) != Constants.CardType.ORO else ""
				entries.append({"data": d, "eligible": not clause.is_empty()})
				clauses.append(clause)
			pools.append({"is_own": p == pid, "zone": zone, "cards": entries, "exclusive": true})
	if pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		var raw: Array = await ActionModule.pick_in_zones(pid, "%s: una habilidad activada de una carta de coste 2 o menos" % _name(card), pools, 0, 1)
		if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2:
			var pi := int(raw[0][0])
			var ci := int(raw[0][1])
			if pi >= 0 and pi < pools.size() and ci >= 0 and ci < pools[pi].cards.size() and pools[pi].cards[ci].eligible:
				var offset := 0
				for k in pi:
					offset += pools[k].cards.size()
				var d: Dictionary = pools[pi].cards[ci].data
				var proxy: Node = main._create_card(d, false)
				proxy.visible = false
				main.add_child(proxy)
				proxy.owner_id = pid
				proxy.controller_id = pid
				await TriggerSystem._effect_interpreter.try_execute(proxy, clauses[offset + ci], pid)
				if is_instance_valid(proxy):
					proxy.queue_free()
	# "Los jugadores ganan el control de las cartas en juego que no sean Oro de las que sean dueños."
	for c in _in_play_both(main, func(c): return c.get("card_type") != Constants.CardType.ORO and c.get("owner_id") != null \
			and int(c.owner_id) != CardQuery.controller_of(c)):
		ContinuousEffectManager.gain_control_of_card(c, int(c.owner_id))


static func _corromper(main: Node, card: Node, pid: int) -> void:
	# "Ambos jugadores muestran su mano, comenzando por ti cada jugador elige una carta de la mano oponente y la
	# coloca en su mano."
	for chooser in [pid, 1 - pid]:
		var from: int = 1 - chooser
		var hand: Array = EnterScript._hand(main, from)
		if hand.is_empty():
			continue
		if not PlayerSideScript.is_bot(chooser):
			SelectionManager.open_reveal(hand.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), chooser)
		var idx := 0
		if PlayerSideScript.is_bot(chooser):
			hand.sort_custom(func(a, b): return int(a.get("card_cost")) > int(b.get("card_cost")))
		elif hand.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: elige una carta de la mano oponente" % _name(card),
				hand.map(func(c): return EnterScript._name(c)), chooser), 0, hand.size() - 1)
		var data: Dictionary = PlayerSideScript.take_from_hand(main, from, hand[idx])
		if not data.is_empty():
			PlayerSideScript.put_in_hand(main, chooser, data)



static func _invocar_angeles(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: puedes jugar un Aliado Ángel de tu Cementerio por un Oro menos" % _name(card), 0, 1,
			func(d): return int(d.get("tipo", -1)) == Constants.CardType.ALIADO and "angel" in CemeteryTriggersScript.normalize(str(d.get("raza", ""))) 				and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid))
		for pk in picks:
			if CardManager.take_from_cemetery(pid, pk.data) and not await _play_paying(main, pid, pk.data, price.call(pk.data)):
				CardManager.add_to_cemetery(pid, pk.data)
	RuleState.set_until("hand_revealed", 1 - pid, 1 << 30)  # HandReveal: por el resto del juego
	load("res://scripts/core/effects/mechanics/HandReveal.gd").refresh()
	main._update_debug("%s: tu oponente juega mostrando su mano por el resto del juego" % _name(card))
