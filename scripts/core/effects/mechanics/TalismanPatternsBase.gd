extends RefCounted
## TalismanPatternsBase — base de TalismanPatterns.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: TalismanPatternsBase <- TalismanPatternsCartas <- TalismanPatternsLote2 <- TalismanPatternsLote3 <- TalismanPatterns. Lo de afuera usa solo TalismanPatterns.gd (hereda todo).

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

const RACES := ["Bestia", "Dragón", "Sombra", "Héroe", "Caballero", "Guerrero", "Eterno", "Faerie", "Sacerdote", "Bandido"]

const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")

const DamageShieldsScript = preload("res://scripts/core/effects/mechanics/DamageShields.gd")
