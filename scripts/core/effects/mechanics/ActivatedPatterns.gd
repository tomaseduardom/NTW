extends RefCounted
## ActivatedPatterns — habilidades activadas ("Una vez por turno, puedes...") que el compilador no entiende
## pero que se arman con piezas que ya existen. Se usa con preload desde
## TriggerResolution._resolve_look_and_play_patterns() (el camino de TriggerSystem.resolve_ability_effect,
## que usa la Pila para las activadas).
## Costos: el Oro de "puedes pagar N Oros para..." ya lo cobró el Paso B de la Pila (EffectContext
## "gold_paid"); los demás (Descartar, Desterrarlo, pagarlo, Botar...) los paga cada handler. La ventana de
## respuesta ya la abrió la Pila (Paso D): aquí no se abre otra.

const RevealedCardsScript = preload("res://scripts/core/effects/mechanics/RevealedCards.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const ConvertScript = preload("res://scripts/core/effects/mechanics/ConvertPatterns.gd")
const AttackScript = preload("res://scripts/core/effects/mechanics/AttackPatterns.gd")
const EnterScript = preload("res://scripts/core/effects/mechanics/EnterPatterns.gd")
const TalismanScript = preload("res://scripts/core/effects/mechanics/TalismanPatterns.gd")
const LeavePlayScript = preload("res://scripts/core/effects/triggers/LeavePlayPatterns.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")
const DamageShieldsScript = preload("res://scripts/core/effects/mechanics/DamageShields.gd")
const CastleLookScript = preload("res://scripts/core/effects/CastleLook.gd")

const KINDS := {
	# Control y Botar
	"convierte el aliado oponente de mayor fuerza en un aliado sin habilidad de raza heroe y gana su control": "_el_emperador",
	"puedes hacer que cada jugador destruya uno de sus aliados": "_tue_tue",
	"puedes ganar el control de un aliado de fuerza 1 o menos": "_tanuki",
	"puedes ganar el control de una carta en juego que no sea oro": "_gabriel_ultra",
	"tu oponente bota tantas cartas como aliados controles": "_ur_nammu",
	"un jugador bota cartas igual a los aliados de distinta fuerza en juego": "_murcielago",
	"tu oponente bota tantas cartas como coste total tengan otras dos cartas que controles": "_lupus_b7",
	"puedes destruir todos los aliados de fuerza 0 en juego": "_sargento_orok",
	"puedes desterrar el aliado oponente de menor fuerza": "_troll_soberano",
	"puedes hacer que tu oponente bote una carta por cada otra carta de nombre leyaden en juego": "_leyaden",
	# Generar Oro
	"puedes generar un oro para jugar aliados o armas por el turno": "_calfucura",
	"puedes generar un oro para jugar cartas de coste 3 o mas y robar dos cartas": "_don_quijote",
	"puedes pagarlo para generar dos oros por el turno para jugar cartas de coste 4 o mas": "_kultrung",
	"puedes buscar en tu castillo una carta que no sea talisman, ponerla en tu mano y generar un oro": "_ryugu_jo",
	"puedes buscar un arma o totem de coste 2 o mas o generar un oro para jugar armas o totem de coste 2 o mas": "_cueva_xalpen",
	"si esta en tu linea de ataque, una vez por turno, puedes generar un oro": "_akashi_oro",
	# Oros en juego
	"puedes poner un oro de tu mano o de un cementerio en tu reserva": "_gusano_blanco",
	"puedes poner un oro de cualquier cementerio o del destierro oponente en tu oro pagado": "_tenebris",
	"puedes mostrar la primera carta de tu castillo, si es un oro o una carta de coste 2 o menos, puedes ponerla en tu mano": "_veela",
	"muestra la primera carta de tu castillo. si es un oro, puedes ponerlo en tu mano y robar una carta": "_rueda_fortuna",
	"puedes pagar un oro para convertir la carta del fondo de tu castillo en un oro sin habilidad y ponerlo en tu oro pagado": "_el_mundo",
	"una vez por partida, puedes pagar un oro para convertir una carta del tope de un castillo en un oro sin habilidad": "_huevos_oro",
	# Fuerza
	"puedes elegir robar dos cartas o que un aliado que controles sea imbloqueable por el turno": "_tauro",
	"si tienes cuatro o menos cartas en tu mano, una vez por turno puedes hacer que un aliado que controles gane 2 de fuerza por el turno": "_hibridos",
	"si tienes cuatro o menos cartas en tu mano, una vez por turno, puedes buscar un aliado en tu castillo y ponerlo en tu cementerio": "_gnoll",
	"puedes buscar un aliado bestia en tu castillo y ponerlo en tu cementerio para que este aliado gane 2 de fuerza hasta la fase final": "_sabuesos_arawn",
	"puedes buscar un aliado bestia en tu castillo y ponerlo en tu cementerio para que un aliado gane o pierda 2 de fuerza": "_cerbero",
	"puedes buscar un aliado en tu castillo y ponerlo en tu cementerio. un aliado en juego gana tanta fuerza como coste tenga el aliado buscado": "_cahuelche",
	"puedes elegir un aliado oponente para que pierda 2 de fuerza hasta la fase final": "_dodomeki",
	"un aliado heroe gana 1 de fuerza por cada oro en el oro pagado oponente": "_endimion",
	"un aliado gana furia y 1 de fuerza por cada tipo de carta en tu destierro": "_oolaf",
	"un aliado gana 1 de fuerza por cada carta de distinto nombre en tu destierro": "_black_ursa",
	"puedes duplicar la fuerza del portador": "_maza",
	"un aliado es imbloqueable y hace dano al destierro este turno": "_metalmorfo",
	"un aliado que controles gana furia por el turno y su dano es enviado al destierro este turno": "_laboratorio_siniestro",
	"otro aliado gana 1 de fuerza y hace el doble de dano este turno": "_faraon_negro_2",
	"un aliado o tus aliados bandido ganan 1 de fuerza permanentemente": "_bandido_medieval",
	"un aliado que controles no puede salir del juego hasta tu proximo turno": "_sirinia",
	"hasta dos aliados de menor fuerza que este aliado, pierden su habilidad y tienen fuerza 0 hasta tu proximo turno": "_iki_balam",
	"un aliado gana furia, 2 de fuerza permanentemente y puedes robar hasta tantas cartas como coste tenga mas una": "_machete_abuelo",
	"un aliado gana 1 de fuerza por el turno o paga un oro para subir una carta de coste 2 o menos a la mano de su dueno": "_qualmi",
	# Exhumar
	"puedes hacer que una carta de tu cementerio que no sea talisman gane exhumar por el turno": "_animita",
	"puedes hacer que un arma en tu cementerio gane exhumar por el turno": "_arturo_bretana",
	"puedes hacer que un aliado de tu cementerio gane exhumar por el turno": "_laboratorio_maldito",
	"hasta dos aliados en tu cementerio ganan exhumar por el turno": "_voragh",
	"las cartas de ese tipo de coste 1 o mas en tu cementerio ganan exhumar por el turno": "_cementerio_maldito",
	"una carta tu cementerio gana exhumar y no recibes dano de combate": "_quicavi",
	"puedes hacer que hasta dos aliados de coste 1 de tu cementerio ganen exhumar y las habilidades de tus aliados no puedan ser canceladas": "_pulpo_colosal",
	# Jugar desde zonas
	"juega un aliado de coste 1 de tu mano o cementerio sin pagar su coste y en la fase final puedes subirlo a tu mano": "_muma_padurii",
	"puedes jugar un aliado de un cementerio por un oro menos": "_omukade",
	"puedes jugar un aliado o arma de un cementerio reduciendo su coste en un oro, hasta un minimo de 0": "_vampiro_rancagua",
	"puedes jugar un arma de tu cementerio o destierro pagando su coste": "_mateo_toro",
	"puedes jugar un arma o un aliado, que no sea general washington, de tu mano o cementerio, por un oro menos": "_general_washington",
	"puedes pagar dos oros para poner en juego un aliado desde tu mano": "_kuzuryu_activa",
	"si no controlas aliados, puedes poner en juego bajo tu control un aliado de coste 2 o menos de tu cementerio como un aliado sin habilidad": "_miguel_cervantes",
	"si no controlas mas aliados que tu oponente, pon bajo tu control la primera carta de un castillo como un aliado de fuerza 2 sin habilidad": "_frederick_ransom",
	"puedes convertir la primera carta de un castillo en un aliado con la habilidad": "_bistritz",
	"puedes poner en juego un aliado de cualquier cementerio como un aliado bestia sin habilidad": "_behemot",
	"puedes jugar un aliado de tu mano o cementerio por dos oros menos. luego, puedes robar hasta tantas cartas como coste tenga ese aliado": "_daikaiju",
	"puedes jugar un totem de tu mano o cementerio por dos oros menos y robar tantas cartas como su coste": "_ten_no_senshi",
	"puedes buscar dos aliados de distinto nombre en tu castillo, pon uno en tu mano y juega el otro reduciendo su coste en un oro": "_nyssara_busca",
	"puedes descartar una carta para buscar un aliado o arma en tu castillo y jugarla pagando su coste": "_gabriel_ernest",
	"puedes jugar hasta un aliado del destierro oponente, desterrar dos cartas del fondo de su castillo y robar una carta": "_lucifer",
	"juega una carta que no sea talisman del destierro oponente reduciendo su coste en un oro, hasta un minimo de 1": "_alucard_juega",
	# Convertir y control
	"puedes convertir una carta oponente de coste 3 o menos en un totem sin habilidad y ganar su control": "_pachamama",
	"si solo controlas eternos, puedes convertir un aliado en un totem sin habilidad": "_shango",
	"si controlas dos o mas totem, convierte una carta de coste 2 o menos en un totem sin habilidad y gana su control": "_valva_apei",
	"puedes convertir una carta de coste 2 o menos en un oro sin habilidad y ponlo en tu oro pagado": "_espada_magog",
	"puedes descartar una carta para convertir una carta de coste 2 o menos en un oro sin habilidad y moverlo a tu oro pagado o robar dos cartas": "_zmey",
	"puedes destruir dos armas que controles para convertir una carta en una carta del mismo tipo pero sin habilidad": "_los_sastres",
	"puedes desterrarlo para convertir una carta en una carta del mismo tipo sin habilidad": "_trofeo_activa",
	"puedes pagarlo y convertirlo en un oro sin habilidad para convertir un oro o carta de coste 2 o menos en una carta del mismo tipo sin habilidad": "_estrella_kirin",
	"puedes intercambiar el control de una carta que controles con una carta oponente del mismo o menor coste": "_nodens",
	"puedes intercambiar el control de una carta que controles por una oponente que cueste hasta un oro mas": "_arturo_prat_sp",
	"hasta una carta en juego y hasta una carta de un cementerio o destierro pierden su habilidad hasta tu proximo turno": "_pnyx",
	"puedes nombrar una carta. hasta tu proximo turno, no se pueden utilizar las habilidades de esa carta": "_margaret",
	"elige una carta. tu oponente no puede utilizar su habilidad este turno a menos que pague un oro": "_koto",
	"puedes elegir un aliado para que bloquee este turno si puede": "_el_demeter",
	"puedes destruir o anular una carta de coste 0": "_tumba_esperanza",
	"puedes anular una carta de coste 0 o jugada sin pagar su coste": "_nyssara_anula",
	# Buscar y mirar
	"si controlas aliados con furia, puedes pagarlo para mirar la mano de tu oponente. elige un talisman o totem de ahi y barajalo": "_muneco_vudu",
	"puedes mirar la mano de tu oponente y poner un oro desde tu mano o cementerio en tu oro pagado": "_gran_dragon",
	"nombra una carta que no sea oro. busca en la mano o castillo oponente una copia de esa carta y destierrala": "_carmilla",
	"descarta o destruye otra de tus cartas para buscar dos cartas de distinto nombre en un castillo y desterrarlas": "_strigoi",
	"puedes buscar en un castillo dos cartas de distinto nombre y destierralas": "_seth_destructor",
	"puedes buscar un aliado en tu castillo y desterrarlo": "_juan_patmos",
	"busca hasta dos cartas de distinto tipo en cada castillo, ponlas en el cementerio y/o destierro de su dueno": "_lord_ruthven",
	"puedes pagarlo para buscar dos cartas en cada castillo y ponerlas en el cementerio": "_estandarte",
	"puedes buscar en cada castillo dos cartas": "_hacha_seth",
	"puedes descartar una carta que no sea talisman para buscar en tu castillo una carta del mismo tipo y ponerla en tu mano": "_luxor",
	"puedes botar tres cartas para subir hasta una carta de coste 2 o menos a la mano de su dueno y hasta una carta que no sea talisman de tu cementerio a tu mano": "_horda_tenebris",
	"puedes desterrar hasta dos cartas cuyos costes sumen hasta 2 y robar dos cartas": "_ivi_atua",
	"destierra hasta dos cartas oponentes cuyos costes sumen hasta 4": "_akuma",
	"destierra cinco cartas del tope del castillo oponente o hasta dos cartas en juego cuyos costes sumen hasta 3": "_alucard_destierra",
	"tu oponente bota tantas cartas como fuerza tenga un aliado que controle y subelo a la mano de su dueno": "_faraon_negro_1",
	"puedes robar dos cartas y descartar una carta. luego, hasta dos aliados imbloqueable ganan furia por el turno": "_castillo_kumamoto",
	"puedes pagar un oro para robar dos cartas y descartar una": "_parche_pirata",
	"puedes descartar una carta y decir": "_empanada",
	"puedes poner cualquier cantidad de cartas de tu mano en el fondo de tu castillo y poner esa misma cantidad de cartas del tope de tu castillo en tu mano": "_cueva_salamanca",
	"puedes poner hasta dos cartas de tu mano en el fondo de tu castillo para robar esa misma cantidad de cartas": "_necronomicon",
	"puedes poner una carta de tu mano en el tope de tu castillo y dos cartas del fondo castillo en tu mano": "_paris",
	"puedes poner una carta de tu mano en el tope de tu castillo y la carta del fondo de tu castillo en tu mano": "_craneo_duvel",
	"puedes mostrar las tres primeras cartas de tu castillo. por cada aliado mostrado de esta forma un aliado gana 1 de fuerza permanentemente": "_ultimo_hombre",
	"puedes mostrar un aliado de tu mano. tu oponente muestra cartas del tope de su castillo hasta mostrar dos aliados y pone todas esas cartas en su cementerio": "_long_john",
	"muestra un aliado de tu mano para que tu oponente bote cartas igual a la fuerza de ese aliado": "_sandokan_activa",
	"tu oponente muestra tantas cartas del tope de su castillo como fuerza tenga un aliado que porte armas y las pone en su cementerio": "_prendick",
	"puedes mostrar un arma de tu mano para poner una carta del tope de tu castillo en juego como un aliado sin habilidad de fuerza 0": "_monitor_araucano",
	"muestra cartas del tope de tu castillo hasta mostrar aliados cuya fuerza sumen 4 o menos y ponlos en tu mano": "_ziroonderel",
	"muestra cartas del tope de tu castillo hasta mostrar dos aliados. pon uno en tu mano y el otro en tu destierro": "_azrael",
	"cada jugador bota dos cartas. luego, si todos los aliados que controlas son de raza sombra, puedes robar una carta": "_lamia",
	"cada jugador bota tres cartas. luego, pon en juego tres cartas de los cementerios como aliados sombra sin habilidad de fuerza 3": "_el_diablo",
	"puedes activar la habilidad de un totem en juego o en tu cementerio": "_inti",
	"puedes pagar un oro para que hasta tu proximo turno no recibas dano de combate o no puedas ser afectado por efectos oponentes, o para que el bote cinco cartas": "_castillo_dracula",
	"puedes anular un talisman, robar dos cartas o hacer que un aliado gane furia por el turno. destierra dos cartas del fondo de un castillo": "_conde_dracula",
	"puedes desterrarlo para que hasta tres aliados ganen 1 de fuerza y sean imbloqueables": "_cabeza_mimir",
	# Octavo lote: Fase Final
	"en tu fase final, puedes desterrar la primera carta de tu castillo para agrupar este oro": "_amuleto_thor",
	"en tu fase final, si el portador hizo dano de combate este turno, puedes buscar un oro en tu castillo y ponerlo en tu oro pagado": "_atlatl",
	"en tu fase final, puedes botar las primeras dos carta de tu castillo para agrupar un oro": "_canon_naval_final",
	"en tu fase final, si no pusiste oros en juego este turno, pon un oro de tu mano o cementerio en tu reserva": "_craneo_cristal",
	"en tu fase final, destierra hasta dos cartas del cementerio oponente": "_dietrich",
	"en tu fase final, destierra hasta dos cartas de cualquier cementerio": "_midgard_final",
	"en la fase final oponente, tu oponente bota una carta": "_midgard_opp_final",
	"en tu fase final, si controlas a raijin, puedes agrupar un oro": "_fujin",
	"en tu fase final, si controlas a fujin, puedes robar una carta": "_raijin",
	"en tu fase final, si no controlas aliados con furia o imbloqueable, agrupa un oro y muestra cartas del tope": "_guadana",
	"en tu fase final, si el portador ataco este turno, puedes agrupar una carta o desterrar hasta cuatro cartas de los cementerios": "_katana_kogitsunemaru",
	"en tu fase final, puedes agrupar un aliado que controles y hacer que una carta en juego pierda su habilidad": "_leo_final",
	"en tu fase final, puedes destruir esta carta para agrupar un oro": "_odachi_final",
	"en tu fase final, destierra tantas cartas de un cementerio como fuerza tenga este aliado": "_rostam_final",
	"en tu fase final, destierra hasta tantas cartas de un cementerio como aliados hayan modificado su fuerza": "_shakar_raj",
	"en tu fase final, si no tienes oros en reserva, sube un aliado de tu cementerio a tu mano": "_snagov",
	"en tu fase final, si el portador hizo dano este turno, elige un aliado para que no pueda ser agrupado": "_vorpal",
	"en tu fase final, destierra este aliado": "_zmeu_final",
	"en tu fase final, si declaraste ataque este turno, puedes barajar y/o desterrar hasta dos cartas de los cementerios": "_armadura_final",
	"en tu fase final si no tienes oros en tu reserva, puedes desterrar una carta de un cementerio y robar una carta": "_guitarra_final",
	"en tu fase final, si esta en tu destierro, puedes ver las primeras tres cartas": "_noop",  # miroku: turn_end_extras()
	"en tu fase final, baraja esa carta": "_noop",  # ebikame: schedule_next_final_phase_effect
	"en tu fase final, baraja o destierra una carta de un cementerio": "_azi_gold_final",
	"en la fase final, si hizo dano al castillo oponente, gana uno de fuerza permanentemente": "_senalados",
	# Octavo lote: activadas
	"convierte este aliado hasta tu proximo turno en un oro con la habilidad": "_azi_demoniaco",
	"una vez por turno, tu oponente bota tantas cartas como coste tenga una carta en juego": "_chamuel",
	"puedes destruirlo para que tu oponente bote cuatro cartas o descarte una carta": "_cueva_montesinos",
	"puedes ganar el control de una carta de coste 2 o menos. si es un aliado gana furia": "_ebikame",
	"puedes mirar la mano de tu oponente y nombrar dos cartas que no sean talisman": "_gehena",
	"puedes buscar una carta que no sea talisman en un castillo y ponla en el tope o fondo del castillo de su dueno": "_guitarra_andaluza",
	"si atacaste en tu anterior turno puedes pagar dos oros para jugarlo sin pagar su coste": "_gurzil",
	"una vez por turno, puedes mostrar cuatro cartas del tope de tu castillo": "_hrunting",
	"puedes desterrar cartas oponentes cuyos costes sumen hasta 3": "_lanza_exorcista",
	"puedes buscar en un castillo dos cartas con distinto nombre y destierralas": "_seth_destructor",
	# Octavo lote: daño
	"cuando haga dano de combate, un oponente destierra la primera carta de su castillo por cada carta en su mano": "_escorpio_damage",
	"cuando haga dano de combate a un castillo, puedes robar una carta y un jugador debe descartar una carta de su mano": "_malafar",
	"cuando haga dano por primera vez en el juego, el primer aliado o totem que juegue tu oponente": "_nagaraja",
	"cuando haga dano, tu oponente elige entre descartar dos cartas o una carta al azar": "_vinci_yang",
	# Octavo lote: Vigilia, Fase Final oponente, comienzo de turno, Destruido, Agrupación
	"al comienzo de tu vigilia, roba hasta tener dos cartas en tu mano": "_salmon",
	"al comienzo de tu vigilia, puedes jugar un talisman de tu cementerio pagando su coste y destierralo": "_shakuhachi",
	"al comienzo de tu vigilia, si tu oponente tiene dos o mas oros en reserva, puedes generar un oro para jugar aliados": "_armadura_vigilia",
	"al comienzo de tu vigilia, puedes mostrar las tres primeras cartas de tu castillo y poner un aliado de coste 1 o menos": "_amuleto_serpiente_vigilia",
	"en la fase final oponente, si no controlas aliados, puedes subir un aliado de tu cementerio a tu mano": "_incienso",
	"al comienzo del turno oponente, baraja y/o destierra hasta dos cartas de los cementerios": "_armeria",
	"si al comienzo del turno no tenias oros en reserva, cuando tu oponente ponga en juego su tercera carta": "_noop",  # GoldManager
	"cuando sea destruido, subelo a tu mano": "_caicai_destroyed",
	"cuando sea destruido, puedes convertirlo en un aliado de fuerza 1 con la habilidad": "_santiaguillo_destroyed",
	"en tu agrupacion, puedes descartar una carta para subirlo de tu cementerio a tu mano": "_noop",  # agrupacion_cemetery_extras()
	# Séptimo lote: Fase Final y Destruido
	"en tu fase final, agrupa al portador": "_regroup_bearer",
	"en tu fase final, agrupa tus aliados": "_regroup_own_allies",
	"tus aliados que porten armas pueden ser agrupados en tu fase final": "_ayyappan_regroup",
	"si el portador hizo dano de combate este turno, puedes desterrar hasta cinco cartas de un cementerio": "_mjolnir_final",
	"tu oponente bota cartas igual a la fuerza de un aliado en juego": "_cahuelche_destroyed",
	# Sexto lote
	"mira tantas cartas del tope de tu castillo como armas y totem controles y ordenalas": "_baculo_eternos",
	"puedes mostrar un aliado caballero de tu mano para activar la habilidad de un arma que hayas activado este turno": "_ayyappan",
	"un oro gana la habilidad \"cuando lo pagues, conviertelo en un aliado de fuerza 3": "_caos",
	# Quinto lote
	"si controlas aliados con furia puedes convertirlo hasta tu proximo turno en un aliado de fuerza 3": "_colmillo_arcano",
	"si controlas aliados de coste 2 o mas puedes convertirlo hasta tu proximo turno en un aliado de fuerza 4": "_gema_grifo",
	"si jugaste dos o mas talismanes puedes convertirlo hasta tu proximo turno en un aliado de fuerza 5": "_amuleto_cazador",
	"puedes convertirlo hasta tu proximo turno en un arma con la habilidad": "_arpon_sagrado",
	"puedes mover un aliado a la linea de ataque y subir un aliado de coste 2 o menos a la mano de su dueno": "_akashi",
	"puedes moverlo a tu linea de ataque y un aliado no puede bloquear este turno": "_batallon_ovejas",
	"hasta tres aliados y/o armas de coste 1 o mas en tu cementerio ganan la habilidad": "_tundra_viva",
	"hasta tres talismanes de coste 1 o mas en tu cementerio ganan la habilidad": "_isla_gigantes",
	"destierra dos cartas de tu cementerio para subirlo a tu mano": "_tundra_granted",
	"destierra tres cartas de tu cementerio para jugarlo pagando su coste y destierralo": "_isla_granted",
	# Cuarto lote: desde la mano, el Cementerio o el Oro Pagado
	"puedes botar dos cartas para jugarlo de tu cementerio": "_hikari_no_ga",
	"puedes pagar un oro para jugarlo desde tu cementerio": "_el_carro",
	"si atacaste en tu anterior turno puedes pagar un oro para jugarlo sin pagar su coste": "_attacked_free_play",
	"si atacaste en tu turno anterior, puedes pagar un oro para jugar este aliado sin pagar su coste desde tu mano o cementerio": "_attacked_free_play",
	"si esta en tu cementerio, puedes pagar un oro para convertirlo en un oro sin habilidad y ponerlo en tu oro pagado": "_daikaiju_furioso",
	"si esta en tu cementerio, puedes pagar 1 oro para convertirlo en un oro sin habilidad y ponerlo en tu oro pagado": "_daikaiju_furioso",
	"si esta en tu cementerio, puedes desterrarlo para que un aliado pierda 2 de fuerza": "_orco_alpino",
	"puedes pagar un oro y desterrarlo de tu cementerio para que la proxima habilidad que utilice tu oponente este turno sea cancelada": "_gusano_haftvad",
	"puedes desterrarlo de tu cementerio para poner en juego otro aliado de tu cementerio como un aliado sin habilidad de nombre titan": "_ignis_azotamundos",
	"puedes desterrarlo de tu mano o cementerio y un aliado de coste 1 o menos que controles": "_jared",
	"puedes desterrarlo de tu mano y pagar dos oros para que hasta dos aliados no puedan salir del juego": "_jafet",
	"puedes desterrarlo de tu mano para jugar un aliado de tu mano pagando su coste": "_pablo_pincheira",
	"puedes descartar una carta de tu mano para para reducir su coste en un oro": "_baphomet",
	"si esta en tu oro pagado, una vez por turno puedes descartar una carta para subir un aliado de tu cementerio a tu mano": "_palo_del_caos",
	"puedes descartarlo para que un oro oponente pierda su habilidad por el turno": "_stegosaurus",
	"puedes desterrarlo en juego o de tu cementerio para que tu oponente no pueda declarar mas de dos aliados bloqueadores": "_los_marcados",
	"si no controlas mas oros que tu oponente, puedes pagar un oro para ponerlo desde tu mano en tu oro pagado": "_alicia",
	"puedes pagar el coste de una carta oponente de la que seas dueno para subirla a tu mano y jugarla sin pagar su coste": "_altar_moloch",
	"si el aliado que bloquea o es bloqueado por el portador tiene coste 2 o menos, puedes destruirlo": "_hacha_perun",
	"si porta armas, puedes jugar un aliado de tu mano que no sea hangaku gozen de coste 2 o menos sin pagar su coste": "_hangaku_gozen",
	"puedes cambiar de portador un arma que controles o subir un arma de tu cementerio a tu mano": "_lord_john_roxton",
	# Tercer lote
	"puedes descartar un oro para cancelar el ataque de hasta dos aliados de coste 2 o menos": "_flor_de_lis",
	"puedes destruirlo para cancelar el ataque": "_pulsera_energia",
	"puedes subir un totem que controles a la mano para cancelar una habilidad": "_abadon",
	"puedes descartar tantas cartas de tu mano como coste tenga una carta para cancelar su habilidad": "_nido_dragon",
	"si tu oponente controla dos o mas oros que tu, puedes convertir este oro en un oro sin habilidad para subir a la mano de su dueno un oro en el oro pagado": "_libro_obras",
	"puedes pagarlo y convertirlo en un oro sin habilidad para subir otro oro que controles a la mano": "_don_belial",
	"puedes pagar un oro para anular una carta o jugar un aliado de tu cementerio reduciendo su coste en un oro": "_ultima_bestia",
	"puedes convertir un totem en un aliado de fuerza igual a su coste y con la habilidad": "_puerta_firmamento",
	"puedes convertir un totem que controles en un aliado con fuerza igual a su coste hasta la fase final": "_yggdrasil",
	"descarta un aliado o totem para mostrar cartas del tope de tu castillo hasta mostrar un talisman y ponlo en tu mano": "_monte_hermon",
	"muestra cartas del tope de tu castillo hasta mostrar un aliado de coste 2 o menos y ponlo en tu mano": "_manicomio_activa",
	"puedes desterrarlo de tu cementerio para mostrar cartas del tope de tu castillo hasta mostrar un aliado de fuerza 5 o mas y ponlo en tu cementerio": "_tuyango",
	"puedes mostrar cartas del tope de tu castillo hasta mostrar un arma, ponerla en tu mano y generar un oro para jugar armas de coste 2 o mas": "_plaza_armas_activa",
	"puedes desterrarlo para subir del cementerio a tu mano hasta dos cartas al azar": "_altar_juramento",
	"puedes desterrarlo para anular un talisman": "_principe_orion",
	"puedes desterrarlo para que no puedas ser afectado por efectos oponentes este turno": "_pazuzu",
	"muestra las primeras cuatro cartas de tu castillo, elige un aliado u oro de ahi y ponlo en tu mano": "_garshasp",
	"puedes jugar un aliado de tu mano o cementerio reduciendo su coste en un oro, hasta un minimo de 1 o de tu destierro pagando su coste": "_desafiante",
	"puedes jugar un arma de tu mano o cementerio, reduciendo su coste en un oro, hasta un minimo de 0": "_milena",
	"puedes jugar un arma de tu cementerio pagando su coste": "_husar_cazador",
	"mira tres cartas de la mano de tu oponente y elige una para que no pueda ser jugada hasta tu proximo turno": "_taka_no_me",
	"puedes destruirlo para generar un oro para jugar aliados de coste 3 o mas": "_wani",
	"si atacaste o bloqueaste este turno, puedes desterrarlo para generar un oro para jugar talismanes": "_shamisen",
	"puedes generar un oro para jugar un totem": "_la_luna",
	"puedes hacer que cada jugador muestre la primera carta de su castillo y la ponga en su mano": "_castillo_edo",
	"puedes mostrar un aliado de tu mano para que tu oponente bote tres cartas": "_karl_red",
	"puedes pagar el coste de una carta oponente para que pierda su habilidad y sea destruida": "_el_fantasma_activa",
	"puedes convertir un talisman de tu cementerio en un aliado de fuerza 1 de nombre leyaden": "_lord_blagrot",
	"puedes buscar en tu castillo o cementerio un aliado y ponerlo en tu mano. los siguientes dos aliados de coste 2 o mas": "_fusil_patriota",
	"puedes robar dos cartas o elige una carta al azar de la mano oponente. conviertela en un oro sin habilidad": "_mina_maldita",
	"puedes pagar un oro para buscar en tu castillo una carta que no sea talisman y ponla en tu mano": "_estrella_solitaria",
	"puedes convertirlo en un oro sin habilidad, pagar un oro y mostrar dos aliados de tu mano para anular un talisman": "_primer_escudo",
	"una carta que no sea oro pierde la habilidad y es destruida": "_allan_quatermain",
	"muestra un arma de tu mano o cementerio para convertir una carta de coste 3 o menos o de un cementerio en un aliado de fuerza 2 sin habilidad": "_otto_lidenbrock",
	"si tu oponente jugo cartas y/o utilizo habilidades mas de una vez este turno, puedes agrupar un oro": "_ahab",
	"si tu oponente jugo cartas y/o utilizo habilidades mas de dos veces este turno y controlas aliados con furia": "_medalla_legba",
	"puedes destruir otro aliado que controles para prevenir el proximo dano que fueras a recibir": "_james_moriarty",
	"puedes subirlo a tu mano o convertirlo en un oro sin habilidad para prevenir recibir dano": "_escritura_sagrada",
	"puedes buscar un aliado en tu castillo y jugarlo reduciendo su coste en un oro, hasta un minimo de 0, bajo el control de tu oponente": "_dulgruss",
	"busca un talisman en tu castillo y ponlo en tu cementerio. ese talisman gana exhumar": "_zagovornik",
	"puedes pagarlo y convertirlo en un oro sin habilidad para que tu oponente bote tantas cartas como cartas de distinto tipo": "_craneos_vivos",
}


static func _kind(text: String) -> String:
	var t := CemeteryTriggersScript.normalize(text)
	for k in KINDS:
		if k in t:
			return KINDS[k]
	return ""


static func try_execute(card: Node, text: String, controller_id: int) -> bool:
	var fn := _kind(text)
	if fn.is_empty() or not is_instance_valid(card):
		return false
	var main := CardQuery.main_node()
	if main:
		await load("res://scripts/core/effects/mechanics/ActivatedPatterns.gd").call(fn, main, card, controller_id)
	return true


# =============================================================================
# AYUDAS
# =============================================================================
static func _name(card) -> String:  # sin tipo: puede llegar ya liberada
	return str(card.get("card_name")) if is_instance_valid(card) else "Carta"


## "puedes pagar N Oros para...": si el Paso B ya lo cobró (EffectContext "gold_paid"), no se vuelve a cobrar.
static func _pay_gold(main: Node, pid: int, n: int) -> bool:
	if int(EffectContextScript.current().get("gold_paid", 0)) >= n:
		return true
	if not main._gold_manager or not main._gold_manager.puede_pagar(n, -1, "", -1, pid):
		main._update_debug("No tienes %d Oro(s) para pagar" % n)
		return false
	return await PlayerSideScript.pay(main, pid, n)


static func _allies(main: Node, pid: int) -> Array:
	return EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO)


static func _buff(target: Node, card: Node, amount: int, permanent: bool = false, until_final: bool = false) -> void:
	await TalismanScript._buff_turn(target, card, amount, permanent)


static func _restricted_gold(main: Node, pid: int, amount: int, predicate: Callable, label: String) -> void:
	if main._gold_manager:
		main._gold_manager.generar_oro_virtual_restringido(amount, predicate, label, pid)


static func _grant_exhumar(datas: Array) -> void:
	for d in datas:
		d["_exhumar_until"] = GameManager.turn_serial  # ExhumarSystem._card_has_exhumar
	PaymentManager.invalidate_cache()


# =============================================================================
# CONTROL Y BOTAR
# =============================================================================
static func _el_emperador(main: Node, card: Node, pid: int) -> void:
	var rivals := _allies(main, 1 - pid)
	if rivals.is_empty():
		return
	rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) > ContinuousEffectManager.get_modified_strength(b))
	var top: int = int(ContinuousEffectManager.get_modified_strength(rivals[0]))
	var tied: Array = rivals.filter(func(c): return int(ContinuousEffectManager.get_modified_strength(c)) == top)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: el Aliado oponente de mayor Fuerza" % _name(card), tied, false)
	if not is_instance_valid(target) or not await ConvertScript._take_and_convert_in_play(target, pid, card):
		return
	target.card_raza = "Héroe"
	target.is_converted = true
	await KeywordManager.silence_card(target, card, "permanent", true)


static func _tue_tue(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		var mine := _allies(main, p)
		if mine.is_empty():
			continue
		if PlayerSideScript.is_bot(p):
			mine.sort_custom(func(a, b): return EnterScript._cost(a) < EnterScript._cost(b))
		var victim: Node = await EnterScript._pick_from(main, p, "%s: Destruye uno de tus Aliados" % _name(card), mine, false)
		if is_instance_valid(victim):
			await ActionModule.destroy([victim], card, true)


static func _tanuki(main: Node, card: Node, pid: int) -> void:
	var weak := _allies(main, 1 - pid).filter(func(c): return int(ContinuousEffectManager.get_modified_strength(c)) <= 1)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: gana el control de un Aliado de Fuerza 1 o menos" % _name(card), weak, true)
	if is_instance_valid(target):
		ContinuousEffectManager.gain_control_of_card(target, pid)


static func _gabriel_ultra(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: gana el control de una carta que no sea Oro" % _name(card), rivals, true)
	if is_instance_valid(target):
		ContinuousEffectManager.gain_control_of_card(target, pid)


static func _ur_nammu(main: Node, card: Node, pid: int) -> void:
	var n := _allies(main, pid).size()
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _murcielago(main: Node, card: Node, pid: int) -> void:
	var strengths: Dictionary = {}
	for c in EnterScript._all_allies(main):
		strengths[int(ContinuousEffectManager.get_modified_strength(c))] = true
	var who: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		who = 1 - pid if await SelectionManager.await_two_choice(main, "%s: un jugador Bota %d carta(s)" % [_name(card), strengths.size()],
			"Tu oponente", "Tú", pid) else pid
	if strengths.size() > 0:
		await ActionModule.mill(who, strengths.size(), false, _name(card))


static func _lupus_b7(main: Node, card: Node, pid: int) -> void:
	var mine: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	if PlayerSideScript.is_bot(pid):
		mine.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
	var two: Array = await EnterScript._pick_many(main, pid, "%s: otras dos cartas que controles (su coste total)" % _name(card), mine, 2, false)
	var n := 0
	for c in two:
		n += EnterScript._cost(c)
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _sargento_orok(main: Node, card: Node, _pid: int) -> void:
	var zeros: Array = EnterScript._all_allies(main, func(c): return int(ContinuousEffectManager.get_modified_strength(c)) <= 0)
	if not zeros.is_empty():
		await ActionModule.destroy(zeros, card, true)


static func _troll_soberano(main: Node, card: Node, pid: int) -> void:
	var rivals := _allies(main, 1 - pid)
	if rivals.is_empty():
		return
	rivals.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) < ContinuousEffectManager.get_modified_strength(b))
	var low: int = int(ContinuousEffectManager.get_modified_strength(rivals[0]))
	var tied: Array = rivals.filter(func(c): return int(ContinuousEffectManager.get_modified_strength(c)) == low)
	var target: Node = await EnterScript._pick_from(main, pid, "%s: Destierra el Aliado oponente de menor Fuerza" % _name(card), tied, true)
	if is_instance_valid(target):
		await ActionModule.banish([target], card, true)


static func _leyaden(main: Node, card: Node, pid: int) -> void:
	var n := 0
	for side in [0, 1]:
		n += EnterScript._in_play(main, side, func(c): return c != card and "leyaden" in CemeteryTriggersScript.normalize(str(c.get("card_name")))).size()
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


# =============================================================================
# GENERAR ORO
# =============================================================================
static func _calfucura(main: Node, card: Node, pid: int) -> void:
	_restricted_gold(main, pid, 1, func(t, _r, _c): return t in [Constants.CardType.ALIADO, Constants.CardType.ARMA], "%s: Oro para Aliados o Armas" % _name(card))


static func _don_quijote(main: Node, card: Node, pid: int) -> void:
	_restricted_gold(main, pid, 1, func(_t, _r, c): return int(c) >= 3, "%s: Oro para cartas de coste 3 o más" % _name(card))
	await ActionModule.draw(pid, 2, _name(card), true)


static func _kultrung(main: Node, card: Node, pid: int) -> void:
	await LeavePlayScript._gold_to_paid(main, card)  # el costo: pagarlo
	_restricted_gold(main, pid, 2, func(_t, _r, c): return int(c) >= 4, "%s: Oros para cartas de coste 4 o más" % _name(card))


static func _ryugu_jo(main: Node, card: Node, pid: int) -> void:
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"types_not": [Constants.CardType.TALISMAN]}, 1, true, false, false, card)
	if main._gold_manager:
		main._gold_manager.generar_oros_virtuales(1, pid)


static func _cueva_xalpen(main: Node, card: Node, pid: int) -> void:
	var search := true
	if not PlayerSideScript.is_bot(pid):
		search = await SelectionManager.await_two_choice(main, _name(card), "Buscar un Arma o Tótem de coste 2 o más",
			"Generar un Oro para Armas o Tótem de coste 2 o más", pid)
	if search:
		await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": [Constants.CardType.ARMA, Constants.CardType.TOTEM], "cost_min": 2}, 1, true, false, false, card)
	else:
		_restricted_gold(main, pid, 1, func(t, _r, c): return t in [Constants.CardType.ARMA, Constants.CardType.TOTEM] and int(c) >= 2,
			"%s: Oro para Armas o Tótem de coste 2 o más" % _name(card))


static func _akashi_oro(main: Node, card: Node, pid: int) -> void:
	var lines: Array = PlayerSideScript.ally_containers(main, pid)
	if lines.size() > 1 and card.get_parent() == lines[1] and main._gold_manager:
		main._gold_manager.generar_oros_virtuales(1, pid)


# =============================================================================
# OROS EN JUEGO
# =============================================================================
static func _gusano_blanco(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var is_gold := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO
	var hand_nodes: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
	var pools: Array = []
	var owners: Array = []
	for p in [pid, 1 - pid]:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": is_gold.call(d)})})
		owners.append(p)
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Oro de tu mano o de un Cementerio a tu Reserva" % _name(card), pools, 0, 1, false, hand_nodes)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var data: Dictionary = {}
	var owner: int = pid
	if int(raw[0][0]) == -1:
		if int(raw[0][1]) >= 0 and int(raw[0][1]) < hand_nodes.size():
			data = PlayerSideScript.take_from_hand(main, pid, hand_nodes[int(raw[0][1])])
	else:
		var pi := int(raw[0][0])
		var ci := int(raw[0][1])
		if pi >= 0 and pi < pools.size() and ci >= 0 and ci < pools[pi].cards.size() and pools[pi].cards[ci].eligible:
			data = pools[pi].cards[ci].data
			owner = owners[pi]
			if not CardManager.take_from_cemetery(owner, data):
				data = {}
	if data.is_empty():
		return
	var gold: Node = await main._gold_manager.put_gold_directly_in_reserva(pid, data)
	if is_instance_valid(gold):
		gold.owner_id = owner


static func _tenebris(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var is_gold := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO
	var pools: Array = []
	var where: Array = []
	for p in [pid, 1 - pid]:
		pools.append({"is_own": p == pid, "zone": Constants.Zone.CEMENTERIO, "exclusive": true,
			"cards": CardManager.get_cemetery(p).map(func(d): return {"data": d, "eligible": is_gold.call(d)})})
		where.append({"owner": p, "zone": Constants.Zone.CEMENTERIO})
	pools.append({"is_own": false, "zone": Constants.Zone.DESTIERRO, "exclusive": true,
		"cards": CardManager.get_exile(1 - pid).map(func(d): return {"data": d, "eligible": is_gold.call(d)})})
	where.append({"owner": 1 - pid, "zone": Constants.Zone.DESTIERRO})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: un Oro de un Cementerio o del Destierro oponente" % _name(card), pools, 0, 1)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return
	var pi := int(raw[0][0])
	var ci := int(raw[0][1])
	if pi < 0 or pi >= pools.size() or ci < 0 or ci >= pools[pi].cards.size() or not pools[pi].cards[ci].eligible:
		return
	var d: Dictionary = pools[pi].cards[ci].data
	var w: Dictionary = where[pi]
	if w.zone == Constants.Zone.CEMENTERIO:
		if not CardManager.take_from_cemetery(w.owner, d):
			return
	else:
		CardManager.get_exile(w.owner).erase(d)
		CardManager._emit_exile_changed(w.owner)
	var gold: Node = await main._gold_manager.put_gold_directly_in_pagado(pid, d)
	if is_instance_valid(gold):
		gold.owner_id = w.owner


static func _veela(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var top: Dictionary = deck.pop_front()
	main._update_debug("%s muestra: %s" % [_name(card), str(top.get("nombre", "?"))])
	RevealedCardsScript.record(pid, [top], _name(card))
	var ok: bool = int(top.get("tipo", -1)) == Constants.CardType.ORO or (int(top.get("tipo", -1)) != Constants.CardType.ORO and int(top.get("coste", 0)) <= 2)
	if ok and await EnterScript._confirm(main, pid, _name(card), "Poner %s en tu mano" % str(top.get("nombre", ""))):
		PlayerSideScript.put_in_hand(main, pid, top)
		if main.get("_zone_manager"):
			main._zone_manager._update_castillo_counts()
	else:
		RevealedCardsScript.shuffle_back(main, pid, [top], _name(card))


static func _rueda_fortuna(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var top: Dictionary = deck.pop_front()
	main._update_debug("%s muestra: %s" % [_name(card), str(top.get("nombre", "?"))])
	RevealedCardsScript.record(pid, [top], _name(card))
	if int(top.get("tipo", -1)) == Constants.CardType.ORO and await EnterScript._confirm(main, pid, _name(card), "Poner el Oro en tu mano y Robar una carta"):
		PlayerSideScript.put_in_hand(main, pid, top)
		await ActionModule.draw(pid, 1, _name(card), true)
	else:
		RevealedCardsScript.shuffle_back(main, pid, [top], _name(card))


static func _el_mundo(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty() or not main._gold_manager or not await _pay_gold(main, pid, 1):
		return
	await EnterScript._data_to_paid_gold(main, deck.pop_back(), pid, pid)


static func _huevos_oro(main: Node, card: Node, pid: int) -> void:
	if card.get_meta("used_once_per_game", false) or not main._gold_manager:
		main._update_debug("%s: esta habilidad ya se usó en la partida" % _name(card))
		return
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	if deck.is_empty() or not await _pay_gold(main, pid, 1):
		return
	card.set_meta("used_once_per_game", true)
	await EnterScript._data_to_paid_gold(main, deck.pop_front(), owner, pid)


# =============================================================================
# FUERZA Y PROTECCIÓN
# =============================================================================
static func _tauro(main: Node, card: Node, pid: int) -> void:
	var draw := true
	if not PlayerSideScript.is_bot(pid):
		draw = await SelectionManager.await_two_choice(main, _name(card), "Robar dos cartas", "Un Aliado que controles es Imbloqueable por el turno", pid)
	if draw:
		await ActionModule.draw(pid, 2, _name(card), true)
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles" % _name(card), _allies(main, pid), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.IMBLOQUEABLE, card, "turn")


static func _hibridos(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).size() > 4:
		main._update_debug("%s: tienes más de cuatro cartas en tu mano" % _name(card))
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles gana 2 de Fuerza" % _name(card), _allies(main, pid), false)
	await _buff(ally, card, 2)


static func _search_to_cemetery(main: Node, card: Node, pid: int, eligible: Callable, title: String) -> Dictionary:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: %s" % [_name(card), title], eligible, 0, 1, false)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return picked[0] if not picked.is_empty() else {}


static func _is_ally(d) -> bool:
	return int(d.get("tipo", -1)) == Constants.CardType.ALIADO


static func _is_beast(d) -> bool:
	return _is_ally(d) and "bestia" in CemeteryTriggersScript.normalize(str(d.get("raza", "")))


static func _gnoll(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).size() > 4:
		main._update_debug("%s: tienes más de cuatro cartas en tu mano" % _name(card))
		return
	await _search_to_cemetery(main, card, pid, func(d): return _is_ally(d), "un Aliado de tu Castillo a tu Cementerio")


static func _sabuesos_arawn(main: Node, card: Node, pid: int) -> void:
	var found := await _search_to_cemetery(main, card, pid, func(d): return _is_beast(d), "un Aliado Bestia de tu Castillo a tu Cementerio")
	if not found.is_empty():
		await _buff(card, card, 2)


static func _cerbero(main: Node, card: Node, pid: int) -> void:
	var found := await _search_to_cemetery(main, card, pid, func(d): return _is_beast(d), "un Aliado Bestia de tu Castillo a tu Cementerio")
	if found.is_empty():
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana o pierde 2 de Fuerza" % _name(card), EnterScript._all_allies(main), false)
	if not is_instance_valid(ally):
		return
	var gain: bool = CardQuery.controller_of(ally) == pid
	if not PlayerSideScript.is_bot(pid):
		gain = await SelectionManager.await_two_choice(main, _name(card), "Gana 2 de Fuerza", "Pierde 2 de Fuerza", pid)
	await _buff(ally, card, 2 if gain else -2)


static func _cahuelche(main: Node, card: Node, pid: int) -> void:
	var found := await _search_to_cemetery(main, card, pid, func(d): return _is_ally(d), "un Aliado de tu Castillo a tu Cementerio")
	if found.is_empty():
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana %d de Fuerza" % [_name(card), int(found.get("coste", 0))],
		EnterScript._all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)), false)
	await _buff(ally, card, int(found.get("coste", 0)))


static func _dodomeki(main: Node, card: Node, pid: int) -> void:
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado oponente pierde 2 de Fuerza" % _name(card), _allies(main, 1 - pid), true)
	if not is_instance_valid(target):
		return
	await _buff(target, card, -2)
	if is_instance_valid(target) and int(ContinuousEffectManager.get_modified_strength(target)) <= 0 \
			and await EnterScript._confirm(main, pid, _name(card), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(card), true)


static func _endimion(main: Node, card: Node, pid: int) -> void:
	var heroes: Array = EnterScript._all_allies(main, func(c): return "heroe" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	var n: int = PlayerSideScript.oro_pagado(main, 1 - pid).get_child_count()
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Héroe gana %d de Fuerza" % [_name(card), n], heroes, false)
	await _buff(ally, card, n)


static func _oolaf(main: Node, card: Node, pid: int) -> void:
	var types: Dictionary = {}
	for d in CardManager.get_exile(pid):
		types[int(d.get("tipo", -1))] = true
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia y %d de Fuerza" % [_name(card), types.size()], EnterScript._all_allies(main), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "permanent")
		await _buff(ally, card, types.size())


static func _black_ursa(main: Node, card: Node, pid: int) -> void:
	var names: Dictionary = {}
	for d in CardManager.get_exile(pid):
		names[str(d.get("nombre", "")).to_lower()] = true
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana %d de Fuerza" % [_name(card), names.size()], EnterScript._all_allies(main), false)
	await _buff(ally, card, names.size())


static func _maza(main: Node, card: Node, _pid: int) -> void:
	var wielder = card.get_parent()
	if is_instance_valid(wielder) and wielder.get("equipped_weapons") is Array:
		await _buff(wielder, card, int(ContinuousEffectManager.get_modified_strength(wielder)))


static func _metalmorfo(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado es Imbloqueable y hace daño al Destierro este turno" % _name(card),
		EnterScript._all_allies(main), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.IMBLOQUEABLE, card, "turn")
		ally.set_meta("damage_to_exile_turn", GameManager.turn_serial)


static func _laboratorio_siniestro(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles gana Furia y hace daño al Destierro" % _name(card), _allies(main, pid), false)
	if is_instance_valid(ally):
		KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "turn")
		ally.set_meta("damage_to_exile_turn", GameManager.turn_serial)


static func _faraon_negro_2(main: Node, card: Node, pid: int) -> void:
	var others: Array = EnterScript._all_allies(main, func(c): return c != card)
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: otro Aliado gana 1 de Fuerza y hace el doble de daño" % _name(card), others, false)
	if is_instance_valid(ally):
		await _buff(ally, card, 1)
		ally.set_meta("double_combat_damage_turn", GameManager.turn_serial)


static func _bandido_medieval(main: Node, card: Node, pid: int) -> void:
	var bandits: Array = _allies(main, pid).filter(func(c): return "bandido" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	var all_bandits := not bandits.is_empty()
	if not PlayerSideScript.is_bot(pid) and not bandits.is_empty():
		all_bandits = await SelectionManager.await_two_choice(main, _name(card), "Tus Aliados Bandido ganan 1 de Fuerza permanentemente",
			"Un Aliado gana 1 de Fuerza permanentemente", pid)
	if all_bandits:
		for b in bandits:
			await _buff(b, card, 1, true)
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza permanentemente" % _name(card), EnterScript._all_allies(main), false)
	await _buff(ally, card, 1, true)


static func _sirinia(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles no puede salir del juego hasta tu próximo turno" % _name(card), _allies(main, pid), false)
	if is_instance_valid(ally):
		EffectController.add_single_card_leave_play_immunity(ally, pid)


static func _iki_balam(main: Node, card: Node, pid: int) -> void:
	var mine: int = int(ContinuousEffectManager.get_modified_strength(card))
	var weaker: Array = EnterScript._all_allies(main, func(c): return c != card and int(ContinuousEffectManager.get_modified_strength(c)) < mine)
	if PlayerSideScript.is_bot(pid):
		weaker = weaker.filter(func(c): return CardQuery.controller_of(c) != pid)
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados de menor Fuerza" % _name(card), weaker, 2, true)
	var until: int = RuleState.next_own_turn(pid) - 1
	for c in chosen:
		if not is_instance_valid(c):
			continue
		c.set_meta("silenced_until", until)
		ContinuousEffectManager.register_modifier({
			"source": null, "target": c, "type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength", "value": 0, "operation": "set",
			"duration": ContinuousEffectManager.ModifierDuration.TIMED, "duration_value": 2 if GameManager.active_player_id == pid else 1,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "%s: Fuerza 0" % _name(card),
		})


static func _machete_abuelo(main: Node, card: Node, pid: int) -> void:
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia y 2 de Fuerza permanentemente" % _name(card), EnterScript._all_allies(main), false)
	if not is_instance_valid(ally):
		return
	KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "permanent")
	await _buff(ally, card, 2, true)
	var n: int = EnterScript._cost(ally) + 1
	var amount := n
	if not PlayerSideScript.is_bot(pid):
		var options: Array = []
		for i in n + 1:
			options.append("Robar %d" % i)
		amount = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta %d cartas" % [_name(card), n], options, pid), 0)
	if amount > 0:
		await ActionModule.draw(pid, amount, _name(card), true)


static func _qualmi(main: Node, card: Node, pid: int) -> void:
	var buff := true
	if not PlayerSideScript.is_bot(pid):
		buff = await SelectionManager.await_two_choice(main, _name(card), "Un Aliado gana 1 de Fuerza por el turno",
			"Pagar un Oro: subir una carta de coste 2 o menos a la mano de su dueño", pid)
	if buff:
		var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza" % _name(card), EnterScript._all_allies(main), false)
		await _buff(ally, card, 1)
		return
	if not await _pay_gold(main, pid, 1):
		return
	var targets: Array = []
	for side in [1 - pid, pid]:
		targets.append_array(EnterScript._in_play(main, side, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2)))
	var t: Node = await EnterScript._pick_from(main, pid, "%s: sube una carta de coste 2 o menos a la mano de su dueño" % _name(card), targets, false)
	if is_instance_valid(t):
		await EnterScript.bounce_to_owner_hand(main, t, card)


# =============================================================================
# EXHUMAR POR EL TURNO (meta "_exhumar_until" en los datos del Cementerio)
# =============================================================================
static func _grant_from_cemetery(main: Node, card: Node, pid: int, count: int, eligible: Callable, title: String) -> Array:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: %s" % [_name(card), title], 0, count, eligible)
	var datas: Array = picks.map(func(p): return p.data)
	_grant_exhumar(datas)
	if not datas.is_empty():
		main._update_debug("%s: %s gana Exhumar por el turno" % [_name(card), ", ".join(datas.map(func(d): return str(d.get("nombre", ""))))])
	return datas


static func _animita(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 1, func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN, "una carta que no sea Talismán gana Exhumar")


static func _arturo_bretana(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 1, func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA, "un Arma gana Exhumar")


static func _laboratorio_maldito(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 1, func(d): return _is_ally(d), "un Aliado gana Exhumar")


static func _voragh(main: Node, card: Node, pid: int) -> void:
	await _grant_from_cemetery(main, card, pid, 2, func(d): return _is_ally(d), "hasta dos Aliados ganan Exhumar")


static func _cementerio_maldito(main: Node, card: Node, pid: int) -> void:
	var options := [["Aliado", Constants.CardType.ALIADO], ["Arma", Constants.CardType.ARMA], ["Tótem", Constants.CardType.TOTEM]]
	var idx := 0
	if not PlayerSideScript.is_bot(pid):
		idx = clampi(await SelectionManager.await_choice(main, "%s: elige un tipo de carta" % _name(card), options.map(func(o): return o[0]), pid), 0, 2)
	var t: int = options[idx][1]
	_grant_exhumar(CardManager.get_cemetery(pid).filter(func(d): return int(d.get("tipo", -1)) == t and int(d.get("coste", 0)) >= 1))
	main._update_debug("%s: las cartas de tipo %s de coste 1 o más en tu Cementerio ganan Exhumar por el turno" % [_name(card), options[idx][0]])


static func _quicavi(main: Node, card: Node, pid: int) -> void:
	var datas := await _grant_from_cemetery(main, card, pid, 1, func(_d): return true, "una carta gana Exhumar hasta tu próximo turno")
	var until: int = RuleState.next_own_turn(pid) - 1
	for d in datas:
		d["_exhumar_until"] = until
	RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))


static func _pulpo_colosal(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).size() > 4:
		main._update_debug("%s: tienes más de cuatro cartas en tu mano" % _name(card))
		return
	await _grant_from_cemetery(main, card, pid, 2, func(d): return _is_ally(d) and int(d.get("coste", 0)) == 1, "hasta dos Aliados de coste 1 ganan Exhumar")
	for c in _allies(main, pid):
		c.set_meta("protected_from_cancel_turn", GameManager.turn_serial)  # StackAnnul.protected_from_cancel


# =============================================================================
# SEGUNDO LOTE: JUGAR DESDE ZONAS
# =============================================================================
## Elige una carta de unos pools (pick_in_zones) y la saca de su zona. {data, owner, zone} o {}.
static func _take_from_pools(main: Node, pid: int, title: String, specs: Array, hand_ok: Callable = Callable()) -> Dictionary:
	# specs: [{owner, zone, eligible: Callable}]
	var pools: Array = []
	for sp in specs:
		var arr: Array
		match int(sp.zone):
			Constants.Zone.CEMENTERIO: arr = CardManager.get_cemetery(sp.owner)
			Constants.Zone.DESTIERRO: arr = CardManager.get_exile(sp.owner)
			_: arr = CardManager.get_deck(sp.owner)
		pools.append({"is_own": sp.owner == pid, "zone": sp.zone, "exclusive": true,
			"cards": arr.map(func(d): return {"data": d, "eligible": sp.eligible.call(d)})})
	var hand_nodes: Array = []
	if hand_ok.is_valid():
		hand_nodes = EnterScript._hand(main, pid).filter(func(c): return c.get("card_data") != null and hand_ok.call(c.card_data))
	if hand_nodes.is_empty() and not pools.any(func(pl): return pl.cards.any(func(e): return e.eligible)):
		return {}
	var info: Dictionary = {}
	var raw: Array = await ActionModule.pick_in_zones(pid, title, pools, 0, 1, false, hand_nodes, info)
	for ci in info.get("opened_castles", []):
		CardManager.shuffle_deck(specs[ci].owner)
	if raw.is_empty() or not (raw[0] is Array) or raw[0].size() != 2:
		return {}
	var pi := int(raw[0][0])
	var idx := int(raw[0][1])
	if pi == -1:
		if idx < 0 or idx >= hand_nodes.size():
			return {}
		return {"data": PlayerSideScript.take_from_hand(main, pid, hand_nodes[idx]), "owner": pid, "zone": Constants.Zone.MANO}
	if pi < 0 or pi >= pools.size() or idx < 0 or idx >= pools[pi].cards.size() or not pools[pi].cards[idx].eligible:
		return {}
	var d: Dictionary = pools[pi].cards[idx].data
	var sp: Dictionary = specs[pi]
	match int(sp.zone):
		Constants.Zone.CEMENTERIO:
			if not CardManager.take_from_cemetery(sp.owner, d):
				return {}
		Constants.Zone.DESTIERRO:
			CardManager.get_exile(sp.owner).erase(d)
			CardManager._emit_exile_changed(sp.owner)
		_:
			CardManager.get_deck(sp.owner).erase(d)
			CardManager.shuffle_deck(sp.owner)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return {"data": d, "owner": sp.owner, "zone": sp.zone}


## Devuelve una carta tomada con _take_from_pools si no se pudo jugar.
static func _give_back(main: Node, taken: Dictionary) -> void:
	if taken.is_empty():
		return
	match int(taken.zone):
		Constants.Zone.MANO: PlayerSideScript.put_in_hand(main, taken.owner, taken.data)
		Constants.Zone.DESTIERRO: CardManager.append_to_exile(taken.owner, taken.data)
		_: CardManager.add_to_cemetery(taken.owner, taken.data)


static func _play_taken(main: Node, pid: int, taken: Dictionary, price: int) -> bool:
	if taken.is_empty():
		return false
	if await TalismanScript._play_paying(main, pid, taken.data, price):
		return true
	_give_back(main, taken)
	return false


static func _payable(main: Node, pid: int, price: Callable) -> Callable:
	return func(d) -> bool: return main._gold_manager != null and main._gold_manager.puede_pagar(price.call(d), -1, "", -1, pid)


static func _muma_padurii(main: Node, card: Node, pid: int) -> void:
	var ok := func(d): return _is_ally(d) and int(d.get("coste", 0)) == 1
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de coste 1 de tu mano o Cementerio" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	var name := str(taken.get("data", {}).get("nombre", ""))
	if not await _play_taken(main, pid, taken, 0):
		return
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		for c in _allies(main, pid):
			if EnterScript._name(c) == name and await EnterScript._confirm(main, pid, "Muma Padurii", "Subir %s a tu mano" % name):
				await EnterScript.bounce_to_owner_hand(main, c, null)
				break)


static func _omukade(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return _is_ally(d) and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de un Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}, {"owner": 1 - pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _vampiro_rancagua(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado o Arma de un Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}, {"owner": 1 - pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _mateo_toro(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return int(d.get("coste", 0))
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma de tu Cementerio o Destierro" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}, {"owner": pid, "zone": Constants.Zone.DESTIERRO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _general_washington(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] \
		and CemeteryTriggersScript.normalize(str(d.get("nombre", ""))) != "general washington" and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma o Aliado de tu mano o Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _put_into_play(main: Node, pid: int, data: Dictionary, owner: int) -> Node:
	data["esta_oculta"] = false
	var node: Node = main._create_card(data, false)
	node.owner_id = owner
	node.controller_id = pid
	main._connect_card_signals(node)
	await main._gold_manager._play_card_to_field(node)
	return node


static func _kuzuryu_activa(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 2) or not main._gold_manager:
		return
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: pon en juego un Aliado de tu mano" % _name(card), allies, false)
	if is_instance_valid(chosen):
		await _put_into_play(main, pid, PlayerSideScript.take_from_hand(main, pid, chosen), pid)


static func _miguel_cervantes(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).is_empty() or not main._gold_manager:
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: un Aliado de coste 2 o menos como Aliado sin habilidad" % _name(card), 0, 1,
		func(d): return _is_ally(d) and int(d.get("coste", 0)) <= 2)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["habilidad"] = ""
			await _put_into_play(main, pid, data, pid)


static func _castle_top_to_ally(main: Node, card: Node, pid: int, strength: int, keywords: Array) -> Node:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	if deck.is_empty():
		return null
	var node: Node = await LeavePlayScript._ally_from_data(main, deck.pop_front(), owner, pid, card, strength, keywords, "")
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return node


static func _frederick_ransom(main: Node, card: Node, pid: int) -> void:
	if _allies(main, pid).size() > _allies(main, 1 - pid).size():
		return
	var node := await _castle_top_to_ally(main, card, pid, 2, [])
	if is_instance_valid(node):
		KeywordManager.grant_keyword(node, Constants.Keyword.FURIA, card, "turn")  # "puede atacar el turno que entra en juego"


static func _bistritz(main: Node, card: Node, pid: int) -> void:
	await _castle_top_to_ally(main, card, pid, 4, [Constants.Keyword.FURIA])


static func _behemot(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: un Aliado de cualquier Cementerio como Aliado Bestia sin habilidad" % _name(card), 0, 1,
		func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["habilidad"] = ""
			data["raza"] = "Bestia"
			await _put_into_play(main, pid, data, pk.owner)


static func _daikaiju(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 2, 0)
	var ok := func(d): return _is_ally(d) and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de tu mano o Cementerio por dos Oros menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	var cost: int = int(taken.get("data", {}).get("coste", 0))
	if not await _play_taken(main, pid, taken, price.call(taken.get("data", {}))) or cost <= 0:
		return
	var amount := cost
	if not PlayerSideScript.is_bot(pid):
		var options: Array = []
		for i in cost + 1:
			options.append("Robar %d" % i)
		amount = maxi(await SelectionManager.await_choice(main, "%s: puedes Robar hasta %d cartas" % [_name(card), cost], options, pid), 0)
	if amount > 0:
		await ActionModule.draw(pid, amount, _name(card), true)


static func _ten_no_senshi(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 2, 0)
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.TOTEM and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Tótem de tu mano o Cementerio por dos Oros menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	var cost: int = int(taken.get("data", {}).get("coste", 0))
	if await _play_taken(main, pid, taken, price.call(taken.get("data", {}))) and cost > 0:
		await ActionModule.draw(pid, cost, _name(card), true)


static func _nyssara_busca(main: Node, card: Node, pid: int) -> void:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: dos Aliados de distinto nombre" % _name(card), func(d): return _is_ally(d), 0, 2, true)
	if picked.is_empty():
		return
	var to_play: Dictionary = picked[0]
	if picked.size() == 2 and not PlayerSideScript.is_bot(pid):
		to_play = picked[0] if await SelectionManager.await_two_choice(main, "%s: ¿cuál juegas por un Oro menos?" % _name(card),
			str(picked[0].get("nombre", "")), str(picked[1].get("nombre", "")), pid) else picked[1]
	for d in picked:
		if d != to_play:
			PlayerSideScript.put_in_hand(main, pid, d)
	if not await TalismanScript._play_paying(main, pid, to_play, maxi(int(to_play.get("coste", 0)) - 1, 0)):
		PlayerSideScript.put_in_hand(main, pid, to_play)


static func _gabriel_ernest(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	var ok := func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] \
		and _payable(main, pid, func(x): return int(x.get("coste", 0))).call(d)
	var taken := await _take_from_pools(main, pid, "%s: un Aliado o Arma de tu Castillo para jugar pagando su coste" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": ok}])
	if not taken.is_empty() and not await TalismanScript._play_paying(main, pid, taken.data, int(taken.data.get("coste", 0))):
		PlayerSideScript.put_in_hand(main, pid, taken.data)


static func _lucifer(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var ok := func(d): return _is_ally(d) and _payable(main, pid, func(x): return int(x.get("coste", 0))).call(d)
	var taken := await _take_from_pools(main, pid, "%s: puedes jugar un Aliado del Destierro oponente" % _name(card),
		[{"owner": opp, "zone": Constants.Zone.DESTIERRO, "eligible": ok}])
	await _play_taken(main, pid, taken, int(taken.get("data", {}).get("coste", 0)))
	var deck: Array = CardManager.get_deck(opp)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(opp, d)
	await ActionModule.draw(pid, 1, _name(card), true)


static func _alucard_juega(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
	var ok := func(d): return int(d.get("tipo", -1)) not in [Constants.CardType.TALISMAN, Constants.CardType.ORO] and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega una carta del Destierro oponente por un Oro menos" % _name(card),
		[{"owner": 1 - pid, "zone": Constants.Zone.DESTIERRO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


# =============================================================================
# SEGUNDO LOTE: CONVERTIR Y CONTROL
# =============================================================================
static func _pick_in_play(main: Node, pid: int, title: String, filter: Callable, bot_rivals: bool = true) -> Node:
	var all: Array = []
	for side in [1 - pid, pid]:
		all.append_array(EnterScript._in_play(main, side, filter))
	if PlayerSideScript.is_bot(pid) and bot_rivals:
		all = all.filter(func(c): return CardQuery.controller_of(c) != pid)
	return await EnterScript._pick_from(main, pid, title, all, true)


static func _pachamama(main: Node, card: Node, pid: int) -> void:
	var target: Node = await EnterScript._pick_from(main, pid, "%s: una carta oponente de coste 3 o menos" % _name(card),
		EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3)), true)
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, pid)


static func _shango(main: Node, card: Node, pid: int) -> void:
	var mine := _allies(main, pid)
	if mine.is_empty() or mine.any(func(c): return not ("eterno" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))):
		main._update_debug("%s: solo si controlas únicamente Eternos" % _name(card))
		return
	var target: Node = await _pick_in_play(main, pid, "%s: convierte un Aliado en Tótem sin habilidad" % _name(card), func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, CardQuery.controller_of(target))


static func _valva_apei(main: Node, card: Node, pid: int) -> void:
	if EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM).size() < 2:
		main._update_debug("%s: necesitas controlar dos o más Tótem" % _name(card))
		return
	var target: Node = await _pick_in_play(main, pid, "%s: una carta de coste 2 o menos pasa a ser tu Tótem sin habilidad" % _name(card),
		func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if is_instance_valid(target):
		await ConvertScript.convert_in_play_to_totem(target, card, pid)


static func _espada_magog(main: Node, card: Node, pid: int) -> void:
	var target: Node = await _pick_in_play(main, pid, "%s: una carta de coste 2 o menos pasa a ser un Oro sin habilidad en tu Oro Pagado" % _name(card),
		func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if is_instance_valid(target) and not await ConvertScript.conversion_prevented(target, card):
		await LeavePlayScript._in_play_to_paid_gold(main, target, pid, card)


static func _zmey(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	var convert := true
	if not PlayerSideScript.is_bot(pid):
		convert = await SelectionManager.await_two_choice(main, _name(card), "Convertir una carta de coste 2 o menos en Oro", "Robar dos cartas", pid)
	if not convert:
		await ActionModule.draw(pid, 2, _name(card), true)
		return
	await _espada_magog(main, card, pid)


static func _blank_one(main: Node, card: Node, pid: int, filter: Callable = Callable()) -> void:
	var target: Node = await _pick_in_play(main, pid, "%s: una carta queda sin habilidad" % _name(card),
		func(c): return c != card and (not filter.is_valid() or filter.call(c)))
	if is_instance_valid(target):
		await EnterScript._blank(target, card)


static func _los_sastres(main: Node, card: Node, pid: int) -> void:
	var weapons: Array = CardQuery.weapons_in_play(pid)
	if weapons.size() < 2:
		return
	var two: Array = await EnterScript._pick_many(main, pid, "%s: Destruye dos Armas que controles" % _name(card), weapons, 2, false)
	if two.size() < 2:
		return
	await ActionModule.destroy(two, card, true)
	await _blank_one(main, card, pid)


static func _trofeo_activa(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	if not await EffectController.exile_card(owner, card, true, card):
		return
	await _blank_one(main, null, pid)


static func _estrella_kirin(main: Node, card: Node, pid: int) -> void:
	await LeavePlayScript._gold_to_paid(main, card)  # pagarlo
	await EnterScript._blank(card, card)  # y convertirlo en un Oro sin habilidad
	await _blank_one(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ORO or ContinuousEffectManager.cost_at_most(c, 2))


static func _swap_control(main: Node, card: Node, pid: int, allowed: Callable) -> void:
	var mine: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	var give: Node = await EnterScript._pick_from(main, pid, "%s: una carta que controles" % _name(card), mine, true)
	if not is_instance_valid(give):
		return
	var theirs: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO and allowed.call(give, c))
	var take: Node = await EnterScript._pick_from(main, pid, "%s: la carta oponente" % _name(card), theirs, true)
	if not is_instance_valid(take):
		return
	ContinuousEffectManager.gain_control_of_card(take, pid)
	ContinuousEffectManager.gain_control_of_card(give, 1 - pid)


static func _nodens(main: Node, card: Node, pid: int) -> void:
	await _swap_control(main, card, pid, func(give, c): return EnterScript._cost(c) <= EnterScript._cost(give))


static func _arturo_prat_sp(main: Node, card: Node, pid: int) -> void:
	await _swap_control(main, card, pid, func(give, c): return EnterScript._cost(c) <= EnterScript._cost(give) + 1)


static func _pnyx(main: Node, card: Node, pid: int) -> void:
	var until: int = RuleState.next_own_turn(pid) - 1
	var target: Node = await _pick_in_play(main, pid, "%s: hasta una carta en juego pierde su habilidad" % _name(card), func(c): return c != card)
	if is_instance_valid(target):
		target.set_meta("silenced_until", until)
	var specs: Array = []
	for p in [1 - pid, pid]:
		specs.append({"owner": p, "zone": Constants.Zone.CEMENTERIO, "eligible": func(_d): return true})
		specs.append({"owner": p, "zone": Constants.Zone.DESTIERRO, "eligible": func(_d): return true})
	var pools: Array = []
	for sp in specs:
		var arr: Array = CardManager.get_cemetery(sp.owner) if sp.zone == Constants.Zone.CEMENTERIO else CardManager.get_exile(sp.owner)
		pools.append({"is_own": sp.owner == pid, "zone": sp.zone, "exclusive": true, "cards": arr.map(func(d): return {"data": d, "eligible": true})})
	var raw: Array = await ActionModule.pick_in_zones(pid, "%s: hasta una carta de un Cementerio o Destierro pierde su habilidad" % _name(card), pools, 0, 1)
	if not raw.is_empty() and raw[0] is Array and raw[0].size() == 2:
		var pi := int(raw[0][0])
		var ci := int(raw[0][1])
		if pi >= 0 and pi < pools.size() and ci >= 0 and ci < pools[pi].cards.size():
			pools[pi].cards[ci].data["_silenced_until"] = until  # CardManager.is_cemetery_card_silenced


static func _margaret(main: Node, card: Node, pid: int) -> void:
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var rivals := EnterScript._in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		named = EnterScript._name(rivals[0]) if not rivals.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait("%s: nombra una carta" % _name(card), pid)
		named = str(picked.get("nombre", ""))
	if not named.is_empty():
		KeywordManager.lock_name_until_next_turn(named, -1)
		main._update_debug("%s: hasta tu próximo turno no se pueden utilizar las habilidades de %s" % [_name(card), named])


static func _koto(main: Node, card: Node, pid: int) -> void:
	var all: Array = EnterScript._in_play(main, 1 - pid) + EnterScript._golds(main, [1 - pid])
	var target: Node = await EnterScript._pick_from(main, pid, "%s: elige una carta: usar su habilidad le cuesta un Oro a tu oponente" % _name(card), all, false)
	if is_instance_valid(target):
		target.set_meta("ability_toll_turn", GameManager.turn_serial)  # TriggerTollPatterns.ability_toll


static func _el_demeter(main: Node, card: Node, pid: int) -> void:
	var target: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado debe bloquear este turno si puede" % _name(card), _allies(main, 1 - pid), true)
	if is_instance_valid(target):
		target.set_meta("must_fight_turn", GameManager.turn_serial)


static func _tumba_esperanza(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.cost_of(o) == 0)
	var annul := not obj.is_empty()
	var zeros: Array = []
	for side in [1 - pid, pid]:
		zeros.append_array(EnterScript._in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and EnterScript._cost(c) == 0))
	if annul and not zeros.is_empty() and not PlayerSideScript.is_bot(pid):
		annul = await SelectionManager.await_two_choice(main, _name(card), "Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "")),
			"Destruir una carta de coste 0", pid)
	if annul:
		StackAnnulScript.apply(obj, card)
		return
	var target: Node = await EnterScript._pick_from(main, pid, "%s: Destruye una carta de coste 0" % _name(card), zeros, true)
	if is_instance_valid(target):
		await ActionModule.destroy([target], card, true)


static func _nyssara_anula(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o):
		var node = StackAnnulScript.card_of(o)
		return StackAnnulScript.cost_of(o) == 0 or (node != null and is_instance_valid(node) and node.get_meta("played_free", false)))
	if obj.is_empty():
		main._update_debug("%s: no hay una carta de coste 0 o jugada sin pagar su coste que Anular" % _name(card))
		return
	StackAnnulScript.apply(obj, card)


# =============================================================================
# SEGUNDO LOTE: BUSCAR, MIRAR, MOSTRAR
# =============================================================================
static func _muneco_vudu(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).any(func(c): return KeywordManager.has_keyword(c, Constants.Keyword.FURIA)):
		main._update_debug("%s: necesitas controlar Aliados con Furia" % _name(card))
		return
	await LeavePlayScript._gold_to_paid(main, card)  # pagarlo
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid):
		return
	var all: Array = EnterScript._hand(main, opp)
	if not PlayerSideScript.is_bot(pid) and not all.is_empty():
		SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	var options: Array = all.filter(func(c): return c.get("card_type") in [Constants.CardType.TALISMAN, Constants.CardType.TOTEM])
	if options.is_empty():
		return
	var idx := 0
	if not PlayerSideScript.is_bot(pid) and options.size() > 1:
		idx = clampi(await SelectionManager.await_choice(main, "%s: elige un Talismán o Tótem para Barajarlo" % _name(card),
			options.map(func(c): return EnterScript._name(c)), pid), 0, options.size() - 1)
	PlayerSideScript.shuffle_from_hand(main, opp, options[idx], _name(card))


static func _gran_dragon(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if not (EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO) or await EffectController.offer_colapso_global(pid)):
		var all: Array = EnterScript._hand(main, opp)
		if not PlayerSideScript.is_bot(pid) and not all.is_empty():
			SelectionManager.open_reveal(all.map(func(c): return c.card_data), "%s: la mano de tu oponente" % _name(card), pid)
	await TriggerSystem._effect_interpreter.try_execute(card, "puedes poner un oro de tu mano o cementerio en tu oro pagado", pid)


static func _carmilla(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var hand: Array = EnterScript._hand(main, opp).filter(func(c): return c.get("card_type") != Constants.CardType.ORO)
		named = EnterScript._name(hand[0]) if not hand.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait("%s: nombra una carta que no sea Oro" % _name(card), pid)
		if int(picked.get("tipo", -1)) != Constants.CardType.ORO:
			named = str(picked.get("nombre", ""))
	if named.is_empty():
		return
	for c in EnterScript._hand(main, opp):
		if EnterScript._name(c).to_lower() == named.to_lower():
			EnterScript._exile_from_hand(main, opp, [c])
			main._update_debug("%s: Destierra %s de la mano oponente" % [_name(card), named])
			return
	if not EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.CASTILLO):
		var deck: Array = CardManager.get_deck(opp)
		for d in deck:
			if str(d.get("nombre", "")).to_lower() == named.to_lower():
				deck.erase(d)
				d["esta_oculta"] = false
				CardManager.append_to_exile(opp, d)
				main._update_debug("%s: Destierra %s del Castillo oponente" % [_name(card), named])
				break
		CardManager.shuffle_deck(opp)


static func _banish_from_a_castle(main: Node, card: Node, pid: int, count: int, distinct: bool, eligible: Callable = Callable()) -> void:
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: cartas para Desterrar" % _name(card),
		eligible if eligible.is_valid() else func(_d): return true, 0, count, distinct)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _strigoi(main: Node, card: Node, pid: int) -> void:
	var discard := not EnterScript._hand(main, pid).is_empty()
	var mine: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	if not PlayerSideScript.is_bot(pid) and discard and not mine.is_empty():
		discard = await SelectionManager.await_two_choice(main, _name(card), "Descartar una carta", "Destruir otra de tus cartas", pid)
	if discard:
		await EnterScript._discard_own(main, card, pid, 1)
	else:
		var victim: Node = await EnterScript._pick_from(main, pid, "%s: Destruye otra de tus cartas" % _name(card), mine, false)
		if not is_instance_valid(victim):
			return
		await ActionModule.destroy([victim], card, true)
	await _banish_from_a_castle(main, card, pid, 2, true)


static func _seth_destructor(main: Node, card: Node, pid: int) -> void:
	await _banish_from_a_castle(main, card, pid, 2, true)


static func _juan_patmos(main: Node, card: Node, pid: int) -> void:
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": Constants.CardType.ALIADO}, 1, true, false, false, card, Constants.Zone.DESTIERRO)


static func _each_castle(main: Node, card: Node, pid: int, count: int, title: String, eligible: Callable, place: Callable) -> void:
	for owner in [1 - pid, pid]:
		var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: %s (Castillo %s)" % [_name(card), title, "oponente" if owner != pid else "propio"],
			eligible, 0, count, false)
		await place.call(owner, picked)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _lord_ruthven(main: Node, card: Node, pid: int) -> void:
	await _each_castle(main, card, pid, 2, "hasta dos cartas de distinto tipo", func(_d): return true, func(owner: int, picked: Array) -> void:
		var types: Dictionary = {}
		for d in picked:
			if types.has(int(d.get("tipo", -1))):
				CardManager.get_deck(owner).append(d)  # mismo tipo: vuelve
				continue
			types[int(d.get("tipo", -1))] = true
			var to_exile := false
			if not PlayerSideScript.is_bot(pid):
				to_exile = not await SelectionManager.await_two_choice(main, str(d.get("nombre", "")), "Al Cementerio de su dueño", "Al Destierro de su dueño", pid)
			d["esta_oculta"] = false
			if to_exile:
				CardManager.append_to_exile(owner, d)
			else:
				CardManager.add_to_cemetery(owner, d))


static func _estandarte(main: Node, card: Node, pid: int) -> void:
	await LeavePlayScript._gold_to_paid(main, card)  # pagarlo
	await _each_castle(main, card, pid, 2, "dos cartas al Cementerio", func(_d): return true, func(owner: int, picked: Array) -> void:
		for d in picked:
			d["esta_oculta"] = false
			CardManager.add_to_cemetery(owner, d))


static func _hacha_seth(main: Node, card: Node, pid: int) -> void:
	await _each_castle(main, card, pid, 2, "dos cartas", func(_d): return true, func(owner: int, picked: Array) -> void:
		if picked.is_empty():
			return
		var idx := 0
		if picked.size() == 2 and not PlayerSideScript.is_bot(pid):
			idx = 0 if await SelectionManager.await_two_choice(main, "%s: ¿cuál va al Cementerio?" % _name(card),
				str(picked[0].get("nombre", "")), str(picked[1].get("nombre", "")), pid) else 1
		var to_cem: Dictionary = picked[idx]
		to_cem["esta_oculta"] = false
		CardManager.add_to_cemetery(owner, to_cem)
		if picked.size() == 2:
			var other: Dictionary = picked[1 - idx]
			var to_hand: bool = owner == pid
			if not PlayerSideScript.is_bot(pid):
				to_hand = await SelectionManager.await_two_choice(main, str(other.get("nombre", "")), "A la mano de su dueño", "Al Destierro de su dueño", pid)
			if to_hand:
				PlayerSideScript.put_in_hand(main, owner, other)
			else:
				other["esta_oculta"] = false
				CardManager.append_to_exile(owner, other))


static func _luxor(main: Node, card: Node, pid: int) -> void:
	var hand: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") != Constants.CardType.TALISMAN)
	var cost_card: Node = await EnterScript._pick_from(main, pid, "%s: Descarta una carta que no sea Talismán" % _name(card), hand, true)
	if not is_instance_valid(cost_card):
		return
	var t: int = int(cost_card.get("card_type"))
	await ActionModule.discard(pid, [cost_card], _name(card), true)
	await ActionModule.search(pid, Constants.Zone.CASTILLO, {"type": t}, 1, true, false, false, card)


static func _horda_tenebris(main: Node, card: Node, pid: int) -> void:
	await ActionModule.mill(pid, 3, false, _name(card))  # el costo
	var small: Array = []
	for side in [1 - pid, pid]:
		small.append_array(EnterScript._in_play(main, side, func(c): return c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2)))
	var t: Node = await EnterScript._pick_from(main, pid, "%s: hasta una carta de coste 2 o menos a la mano de su dueño" % _name(card), small, true)
	if is_instance_valid(t):
		await EnterScript.bounce_to_owner_hand(main, t, card)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: hasta una carta que no sea Talismán de tu Cementerio a tu mano" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


static func _ivi_atua(main: Node, card: Node, pid: int) -> void:
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 2, 2, "%s: hasta dos cartas cuyos costes sumen hasta 2" % _name(card))
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)
	await ActionModule.draw(pid, 2, _name(card), true)


static func _akuma(main: Node, card: Node, pid: int) -> void:
	var rivals := EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO)
	var picked: Array = []
	if PlayerSideScript.is_bot(pid):
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
		picked = await main._card_interaction.await_multi_target("%s: hasta dos cartas oponentes cuyos costes sumen hasta 4" % _name(card),
			rivals, 2, Callable(), fits, true, null, pid)
	if not picked.is_empty():
		await ActionModule.banish(picked, card, true)


static func _alucard_destierra(main: Node, card: Node, pid: int) -> void:
	var top := true
	if not PlayerSideScript.is_bot(pid):
		top = await SelectionManager.await_two_choice(main, _name(card), "Desterrar cinco cartas del tope del Castillo oponente",
			"Desterrar hasta dos cartas en juego cuyos costes sumen hasta 3", pid)
	if top:
		await ActionModule.mill(1 - pid, 5, true, _name(card))
		return
	var chosen: Array = await AttackScript._pick_cost_sum(main, card, pid, 2, 3, "%s: hasta dos cartas cuyos costes sumen hasta 3" % _name(card))
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)


static func _faraon_negro_1(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var theirs := _allies(main, opp)
	if PlayerSideScript.is_bot(opp):
		theirs.sort_custom(func(a, b): return ContinuousEffectManager.get_modified_strength(a) < ContinuousEffectManager.get_modified_strength(b))
	var chosen: Node = await EnterScript._pick_from(main, opp, "%s: elige un Aliado que controles" % _name(card), theirs, false)
	if not is_instance_valid(chosen):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(chosen))
	if n > 0:
		await ActionModule.mill(opp, n, false, _name(card))
	await EnterScript.bounce_to_owner_hand(main, chosen, card)


static func _castillo_kumamoto(main: Node, card: Node, pid: int) -> void:
	await ActionModule.draw(pid, 2, _name(card), true)
	await EnterScript._discard_own(main, card, pid, 1)
	var unblockable: Array = EnterScript._all_allies(main, func(c): return KeywordManager.has_keyword(c, Constants.Keyword.IMBLOQUEABLE) \
		and (CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid)))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados Imbloqueable ganan Furia" % _name(card), unblockable, 2, true)
	for c in chosen:
		KeywordManager.grant_keyword(c, Constants.Keyword.FURIA, card, "turn")


static func _parche_pirata(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	await ActionModule.draw(pid, 2, _name(card), true)
	await EnterScript._discard_own(main, card, pid, 1)


static func _empanada(main: Node, card: Node, pid: int) -> void:
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	main._update_debug("¡Viva Chile!")
	await ActionModule.draw(pid, 1, _name(card), true)


static func _hand_to_bottom(main: Node, card: Node, pid: int, max_count: int) -> int:
	var hand := EnterScript._hand(main, pid)
	if hand.is_empty():
		return 0
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: cartas de tu mano al fondo de tu Castillo" % _name(card), hand, mini(max_count, hand.size()), true)
	if PlayerSideScript.is_bot(pid):
		chosen = []
	var deck: Array = CardManager.get_deck(pid)
	for c in chosen:
		var d: Dictionary = PlayerSideScript.take_from_hand(main, pid, c)
		d["esta_oculta"] = true
		deck.append(d)
	return chosen.size()


static func _cueva_salamanca(main: Node, card: Node, pid: int) -> void:
	var n := await _hand_to_bottom(main, card, pid, 99)
	var deck: Array = CardManager.get_deck(pid)
	for _i in mini(n, deck.size()):
		PlayerSideScript.put_in_hand(main, pid, deck.pop_front())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _necronomicon(main: Node, card: Node, pid: int) -> void:
	var n := await _hand_to_bottom(main, card, pid, 2)
	if n > 0:
		await ActionModule.draw(pid, n, _name(card), true)


static func _top_from_hand_bottom_to_hand(main: Node, card: Node, pid: int, bottom_count: int) -> void:
	var hand := EnterScript._hand(main, pid)
	if hand.is_empty():
		return
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: una carta de tu mano al tope de tu Castillo" % _name(card), hand, true)
	if not is_instance_valid(chosen):
		return
	var deck: Array = CardManager.get_deck(pid)
	var d: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	d["esta_oculta"] = true
	deck.push_front(d)
	for _i in mini(bottom_count, deck.size() - 1):
		PlayerSideScript.put_in_hand(main, pid, deck.pop_back())
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _paris(main: Node, card: Node, pid: int) -> void:
	await _top_from_hand_bottom_to_hand(main, card, pid, 2)


static func _craneo_duvel(main: Node, card: Node, pid: int) -> void:
	await _top_from_hand_bottom_to_hand(main, card, pid, 1)


static func _ultimo_hombre(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = deck.slice(0, mini(3, deck.size()))
	if shown.is_empty():
		return
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	for d in shown:
		if _is_ally(d):
			var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana 1 de Fuerza permanentemente" % _name(card), EnterScript._all_allies(main), false)
			await _buff(ally, card, 1, true)
	# "Devuelve las cartas mostradas en cualquier orden": quedan en el tope, en el mismo orden.


static func _show_from_hand(main: Node, card: Node, pid: int, filter: Callable, title: String) -> Node:
	var hand: Array = EnterScript._hand(main, pid).filter(filter)
	var shown: Node = await EnterScript._pick_from(main, pid, "%s: %s" % [_name(card), title], hand, true)
	if is_instance_valid(shown):
		main._update_debug("%s: muestra %s" % [_name(card), EnterScript._name(shown)])
	return shown


static func _long_john(main: Node, card: Node, pid: int) -> void:
	if not is_instance_valid(await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO, "muestra un Aliado de tu mano")):
		return
	var opp: int = 1 - pid
	var count := [0]
	var shown := TalismanScript._reveal_until(main, opp, _name(card), func(s):
		if not s.is_empty() and _is_ally(s[-1]):
			count[0] += 1
		return count[0] >= 2)
	for d in shown:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(opp, d)


static func _sandokan_activa(main: Node, card: Node, pid: int) -> void:
	var shown: Node = await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO, "muestra un Aliado de tu mano")
	if is_instance_valid(shown) and int(shown.get("card_strength")) > 0:
		await ActionModule.mill(1 - pid, int(shown.get("card_strength")), false, _name(card))


static func _prendick(main: Node, card: Node, pid: int) -> void:
	var armed: Array = EnterScript._all_allies(main, func(c): return c.get("equipped_weapons") is Array and not c.equipped_weapons.is_empty())
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que porte Armas (su Fuerza)" % _name(card), armed, false)
	if not is_instance_valid(ally):
		return
	var n: int = int(ContinuousEffectManager.get_modified_strength(ally))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


static func _monitor_araucano(main: Node, card: Node, pid: int) -> void:
	if not is_instance_valid(await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ARMA, "muestra un Arma de tu mano")):
		return
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	await LeavePlayScript._ally_from_data(main, deck.pop_front(), pid, pid, card, 0, [], "")


static func _ziroonderel(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = []
	var allies: Array = []
	var total := 0
	while not deck.is_empty():
		var d: Dictionary = deck[0]
		if _is_ally(d) and total + int(d.get("fuerza", 0)) > 4:
			break
		shown.append(deck.pop_front())
		if _is_ally(d):
			allies.append(d)
			total += int(d.get("fuerza", 0))
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(x): return str(x.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	for d in shown:
		if d in allies:
			PlayerSideScript.put_in_hand(main, pid, d)
		else:
			d["esta_oculta"] = true
			deck.append(d)
	CardManager.shuffle_deck(pid)


static func _azrael(main: Node, card: Node, pid: int) -> void:
	var allies: Array = []
	var shown := TalismanScript._reveal_until(main, pid, _name(card), func(s):
		if not s.is_empty() and _is_ally(s[-1]):
			allies.append(s[-1])
		return allies.size() >= 2)
	var deck: Array = CardManager.get_deck(pid)
	for d in shown:
		if not (d in allies):
			d["esta_oculta"] = true
			deck.append(d)
	if not allies.is_empty():
		var idx := 0
		if allies.size() == 2 and not PlayerSideScript.is_bot(pid):
			idx = 0 if await SelectionManager.await_two_choice(main, "%s: ¿cuál va a tu mano?" % _name(card), str(allies[0].get("nombre", "")),
				str(allies[1].get("nombre", "")), pid) else 1
		PlayerSideScript.put_in_hand(main, pid, allies[idx])
		if allies.size() == 2:
			allies[1 - idx]["esta_oculta"] = false
			CardManager.append_to_exile(pid, allies[1 - idx])
	CardManager.shuffle_deck(pid)


static func _lamia(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		await ActionModule.mill(p, 2, false, _name(card))
	var mine := _allies(main, pid)
	if not mine.is_empty() and mine.all(func(c): return "sombra" in CemeteryTriggersScript.normalize(str(c.get("card_raza")))) \
			and await EnterScript._confirm(main, pid, _name(card), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(card), true)


static func _el_diablo(main: Node, card: Node, pid: int) -> void:
	for p in [pid, 1 - pid]:
		await ActionModule.mill(p, 3, false, _name(card))
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: tres cartas de los Cementerios como Aliados Sombra de Fuerza 3" % _name(card), 3, 3)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			await LeavePlayScript._ally_from_data(main, pk.data, pk.owner, pid, card, 3, [], "Sombra")


static func _inti(main: Node, card: Node, pid: int) -> void:
	var options: Array = []  # [{node?, data, clause}]
	for t in EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM):
		var cl: String = LeavePlayScript._activated_clause(t.card_data)
		if not cl.is_empty():
			options.append({"node": t, "data": t.card_data, "clause": cl})
	for d in CardManager.get_cemetery(pid):
		if int(d.get("tipo", -1)) == Constants.CardType.TOTEM:
			var cl2: String = LeavePlayScript._activated_clause(d)
			if not cl2.is_empty():
				options.append({"node": null, "data": d, "clause": cl2})
	if options.is_empty():
		main._update_debug("%s: no hay un Tótem con una habilidad que se pueda activar" % _name(card))
		return
	var idx := 0
	if not PlayerSideScript.is_bot(pid) and options.size() > 1:
		idx = clampi(await SelectionManager.await_choice(main, "%s: ¿la habilidad de qué Tótem?" % _name(card),
			options.map(func(o): return str(o.data.get("nombre", ""))), pid), 0, options.size() - 1)
	var o: Dictionary = options[idx]
	var source: Node = o.node
	var proxy: Node = null
	if not is_instance_valid(source):
		proxy = main._create_card(o.data, false)
		proxy.visible = false
		main.add_child(proxy)
		proxy.owner_id = pid
		proxy.controller_id = pid
		source = proxy
	await TriggerSystem._effect_interpreter.try_execute(source, o.clause, pid)
	if is_instance_valid(proxy):
		proxy.queue_free()


static func _castillo_dracula(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	var pick := 2
	if not PlayerSideScript.is_bot(pid):
		pick = await SelectionManager.await_choice(main, _name(card), ["No recibes daño de combate hasta tu próximo turno",
			"No puedes ser afectado por efectos oponentes hasta tu próximo turno", "Tu oponente Bota cinco cartas"], pid)
	match pick:
		0: RuleState.set_until("no_combat_damage", pid, RuleState.next_own_turn(pid))
		1: RuleState.set_until("opp_effect_immune", pid, RuleState.next_own_turn(pid))
		_: await ActionModule.mill(1 - pid, 5, false, _name(card))


static func _conde_dracula(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN)
	var options: Array = ["Robar dos cartas", "Un Aliado gana Furia por el turno"]
	if not obj.is_empty():
		options.push_front("Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "el Talismán")))
	var pick := 0
	if not PlayerSideScript.is_bot(pid):
		pick = clampi(await SelectionManager.await_choice(main, _name(card), options, pid), 0, options.size() - 1)
	var choice: String = options[pick]
	if choice.begins_with("Anular"):
		StackAnnulScript.apply(obj, card)
	elif choice.begins_with("Robar"):
		await ActionModule.draw(pid, 2, _name(card), true)
	else:
		var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado gana Furia" % _name(card), EnterScript._all_allies(main), false)
		if is_instance_valid(ally):
			KeywordManager.grant_keyword(ally, Constants.Keyword.FURIA, card, "turn")
	var owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, "%s: dos cartas del fondo de un Castillo" % _name(card), "Castillo oponente", "Tu Castillo", pid) else pid
	var deck: Array = CardManager.get_deck(owner)
	for _i in mini(2, deck.size()):
		var d: Dictionary = deck.pop_back()
		d["esta_oculta"] = false
		CardManager.append_to_exile(owner, d)


static func _cabeza_mimir(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var buff := true
	if not PlayerSideScript.is_bot(pid):
		buff = await SelectionManager.await_two_choice(main, _name(card), "Hasta tres Aliados ganan 1 de Fuerza e Imbloqueable",
			"Subir un Talismán de tu Cementerio a tu mano", pid)
	if not await EffectController.exile_card(owner, card, true, card):  # el costo: Desterrarlo
		return
	if buff:
		var chosen: Array = await EnterScript._pick_many(main, pid, "Cabeza de Mímir: hasta tres Aliados", _allies(main, pid), 3, true)
		for c in chosen:
			await _buff(c, null, 1)
			KeywordManager.grant_keyword(c, Constants.Keyword.IMBLOQUEABLE, null, "turn")
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Cabeza de Mímir: un Talismán de tu Cementerio a tu mano", 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


# =============================================================================
# TERCER LOTE
# =============================================================================
static func _interp(card: Node, text: String, pid: int) -> bool:
	return await TriggerSystem._effect_interpreter.try_execute(card, text, pid)


static func _exile_self(card: Node, pid: int) -> bool:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	return await EffectController.exile_card(owner, card, true, card)


## "puedes pagarlo y convertirlo en un Oro sin habilidad": al Oro Pagado y sin habilidad.
static func _pay_self_blank(main: Node, card: Node) -> void:
	await LeavePlayScript._gold_to_paid(main, card)
	await EnterScript._blank(card, card)


static func _flor_de_lis(main: Node, card: Node, pid: int) -> void:
	var golds: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
	var gold: Node = await EnterScript._pick_from(main, pid, "%s: Descarta un Oro" % _name(card), golds, true)
	if not is_instance_valid(gold):
		return
	await ActionModule.discard(pid, [gold], _name(card), true)
	# Sólo los de coste 2 o menos pueden ser cancelados: el resto se aparta mientras se elige.
	var keep: Array = GameManager.attackers.filter(func(a): return is_instance_valid(a) and EnterScript._cost(a) > 2)
	for a in keep:
		GameManager.attackers.erase(a)
	await _interp(card, "cancela el ataque de hasta 2 aliados", pid)
	for a in keep:
		if is_instance_valid(a) and not (a in GameManager.attackers):
			GameManager.attackers.append(a)


static func _pulsera_energia(main: Node, card: Node, pid: int) -> void:
	await ActionModule.destroy([card], card, false, true)
	await _interp(card, "cancela el ataque de 1 aliado", pid)


static func _abadon(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, false, true)
	if obj.is_empty():
		main._update_debug("%s: no hay una habilidad que cancelar" % _name(card))
		return
	var totems: Array = EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	var t: Node = await EnterScript._pick_from(main, pid, "%s: sube un Tótem que controles a la mano" % _name(card), totems, true)
	if not is_instance_valid(t) or not await EnterScript.bounce_to_owner_hand(main, t, card):
		return
	StackAnnulScript.apply(obj, card)


static func _nido_dragon(main: Node, card: Node, pid: int) -> void:
	var hand_size: int = EnterScript._hand(main, pid).size()
	var obj: Dictionary = StackAnnulScript.find_target(pid, false, true, func(o): return StackAnnulScript.cost_of(o) <= hand_size)
	if obj.is_empty():
		main._update_debug("%s: no hay una habilidad que puedas cancelar" % _name(card))
		return
	var n: int = StackAnnulScript.cost_of(obj)
	if n > 0:
		await EnterScript._discard_own(main, card, pid, n)
	StackAnnulScript.apply(obj, card)


static func _libro_obras(main: Node, card: Node, pid: int) -> void:
	if EnterScript._golds(main, [1 - pid]).size() < EnterScript._golds(main, [pid]).size() + 2:
		main._update_debug("%s: tu oponente debe controlar dos o más Oros que tú" % _name(card))
		return
	await EnterScript._blank(card, card)
	var paid: Array = []
	for side in [1 - pid, pid]:
		var cont: Node = main.player_oro_pagado if side == 0 else main.opponent_oro_pagado
		if cont:
			paid.append_array(cont.get_children().filter(func(c): return is_instance_valid(c)))
	var g: Node = await EnterScript._pick_from(main, pid, "%s: un Oro del Oro Pagado a la mano de su dueño" % _name(card), paid, true)
	if is_instance_valid(g):
		await EnterScript.bounce_to_owner_hand(main, g, card)


static func _don_belial(main: Node, card: Node, pid: int) -> void:
	await _pay_self_blank(main, card)
	var others: Array = EnterScript._golds(main, [pid]).filter(func(g): return g != card)
	var g: Node = await EnterScript._pick_from(main, pid, "%s: sube otro Oro que controles a la mano" % _name(card), others, true)
	if not is_instance_valid(g) or not await EnterScript.bounce_to_owner_hand(main, g, card):
		return
	var golds: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ORO)
	var put: Node = await EnterScript._pick_from(main, pid, "%s: pon un Oro de tu mano en tu Oro Pagado" % _name(card), golds, false)
	if is_instance_valid(put) and main._gold_manager:
		await main._gold_manager.put_gold_directly_in_pagado(pid, PlayerSideScript.take_from_hand(main, pid, put))


static func _ultima_bestia(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false)
	var annul := not obj.is_empty()
	if annul and not PlayerSideScript.is_bot(pid):
		annul = await SelectionManager.await_two_choice(main, _name(card), "Anular %s" % str(StackAnnulScript.data_of(obj).get("nombre", "")),
			"Jugar un Aliado de tu Cementerio por un Oro menos", pid)
	if annul:
		StackAnnulScript.apply(obj, card)
		return
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
	var ok := func(d): return _is_ally(d) and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de tu Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _totem_to_ally_until_final(main: Node, card: Node, pid: int, furia: bool) -> void:
	var totems: Array = EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.TOTEM)
	var t: Node = await EnterScript._pick_from(main, pid, "%s: un Tótem pasa a ser Aliado de Fuerza igual a su coste" % _name(card), totems, true)
	if not is_instance_valid(t) or await ConvertScript.conversion_prevented(t, card):
		return
	var tp = TriggerSystem._totem_patterns
	tp._convert_totem_to_ally(t, pid, EnterScript._cost(t), "%s: Fuerza igual a su coste" % _name(card))
	tp._metropolitan_pending_reverts[t] = true  # vuelve a ser Tótem en la Fase Final
	if furia:
		KeywordManager.grant_keyword(t, Constants.Keyword.FURIA, card, "turn")


static func _puerta_firmamento(main: Node, card: Node, pid: int) -> void:
	await _totem_to_ally_until_final(main, card, pid, true)


static func _yggdrasil(main: Node, card: Node, pid: int) -> void:
	await _totem_to_ally_until_final(main, card, pid, false)


## Muestra cartas del tope hasta que 'match' se cumple; esa va a la mano y el resto se baraja.
static func _reveal_until_to_hand(main: Node, card: Node, pid: int, match: Callable, dest: int = Constants.Zone.MANO) -> Dictionary:
	var shown := TalismanScript._reveal_until(main, pid, _name(card), func(s): return not s.is_empty() and match.call(s[-1]))
	var found: Dictionary = shown[-1] if not shown.is_empty() and match.call(shown[-1]) else {}
	if not found.is_empty():
		await load("res://scripts/ui/zones/RevealWindow.gd").show_cards(main, pid, [found], _name(card),
			"Va a tu Cementerio" if dest == Constants.Zone.CEMENTERIO else "Va a tu mano")
	var deck: Array = CardManager.get_deck(pid)
	for d in shown:
		if d != found:
			d["esta_oculta"] = true
			deck.append(d)
	if not found.is_empty():
		if dest == Constants.Zone.CEMENTERIO:
			found["esta_oculta"] = false
			CardManager.add_to_cemetery(pid, found)
		else:
			PlayerSideScript.put_in_hand(main, pid, found)
	CardManager.shuffle_deck(pid)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	return found


static func _monte_hermon(main: Node, card: Node, pid: int) -> void:
	var hand: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM])
	var cost_card: Node = await EnterScript._pick_from(main, pid, "%s: Descarta un Aliado o Tótem" % _name(card), hand, true)
	if not is_instance_valid(cost_card):
		return
	await ActionModule.discard(pid, [cost_card], _name(card), true)
	await _reveal_until_to_hand(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)


static func _manicomio_activa(main: Node, card: Node, pid: int) -> void:
	await _reveal_until_to_hand(main, card, pid, func(d): return _is_ally(d) and int(d.get("coste", 0)) <= 2)


static func _tuyango(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self(card, pid):
		return
	await _reveal_until_to_hand(main, card, pid, func(d): return _is_ally(d) and int(d.get("fuerza", 0)) >= 5, Constants.Zone.CEMENTERIO)


static func _plaza_armas_activa(main: Node, card: Node, pid: int) -> void:
	await _reveal_until_to_hand(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA)
	_restricted_gold(main, pid, 1, func(t, _r, c): return t == Constants.CardType.ARMA and int(c) >= 2, "%s: Oro para Armas de coste 2 o más" % _name(card))


static func _altar_juramento(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self(card, pid):
		return
	var cem: Array = CardManager.get_cemetery(pid).duplicate()
	cem.shuffle()
	for d in cem.slice(0, 2):
		if CardManager.take_from_cemetery(pid, d):
			PlayerSideScript.put_in_hand(main, pid, d)


static func _principe_orion(main: Node, card: Node, pid: int) -> void:
	var ok: bool = EnterScript._in_play(main, pid, func(c): return c.get("current_zone") == Constants.Zone.LINEA_ATAQUE).size() > 0 \
		or _allies(main, pid).any(func(c): return c.get("equipped_weapons") is Array and c.equipped_weapons.any(func(w): return is_instance_valid(w) and EnterScript._cost(w) >= 1))
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN)
	if not ok or obj.is_empty():
		main._update_debug("%s: no se cumple la condición o no hay un Talismán que Anular" % _name(card))
		return
	if await _exile_self(card, pid):
		StackAnnulScript.apply(obj, card)


static func _pazuzu(main: Node, card: Node, pid: int) -> void:
	if await _exile_self(card, pid):
		RuleState.set_until("opp_effect_immune", pid, GameManager.turn_serial)


static func _garshasp(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	var shown: Array = []
	for _i in mini(4, deck.size()):
		shown.append(deck.pop_front())
	if shown.is_empty():
		return
	main._update_debug("%s muestra: %s" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?"))))])
	RevealedCardsScript.record(pid, shown, _name(card))
	var options: Array = shown.filter(func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ORO])
	if not options.is_empty():
		var idx := 0
		if not PlayerSideScript.is_bot(pid) and options.size() > 1:
			idx = clampi(await SelectionManager.await_choice(main, "%s: un Aliado u Oro a tu mano" % _name(card),
				options.map(func(d): return str(d.get("nombre", ""))), pid), 0, options.size() - 1)
		shown.erase(options[idx])
		PlayerSideScript.put_in_hand(main, pid, options[idx])
	# Las demás mostradas vuelven al Castillo y se Baraja.
	RevealedCardsScript.shuffle_back(main, pid, shown, _name(card))


static func _desafiante(main: Node, card: Node, pid: int) -> void:
	var cheap := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 1)
	var full := func(d) -> int: return int(d.get("coste", 0))
	var ok_cheap := func(d): return _is_ally(d) and _payable(main, pid, cheap).call(d)
	var ok_full := func(d): return _is_ally(d) and _payable(main, pid, full).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Aliado de tu mano o Cementerio (un Oro menos) o de tu Destierro" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok_cheap}, {"owner": pid, "zone": Constants.Zone.DESTIERRO, "eligible": ok_full}], ok_cheap)
	if taken.is_empty():
		return
	var price: int = full.call(taken.data) if int(taken.zone) == Constants.Zone.DESTIERRO else cheap.call(taken.data)
	await _play_taken(main, pid, taken, price)


static func _milena(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma de tu mano o Cementerio por un Oro menos" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}], ok)
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _husar_cazador(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return int(d.get("coste", 0))
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA and _payable(main, pid, price).call(d)
	var taken := await _take_from_pools(main, pid, "%s: juega un Arma de tu Cementerio pagando su coste" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": ok}])
	await _play_taken(main, pid, taken, price.call(taken.get("data", {})))


static func _taka_no_me(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if EffectController.fision_hides_zones_of(opp, pid, Constants.Zone.MANO):
		return
	var hand: Array = EnterScript._hand(main, opp).duplicate()
	hand.shuffle()
	var seen: Array = hand.slice(0, 3)
	if seen.is_empty():
		return
	var chosen: Node = seen[0]
	if not PlayerSideScript.is_bot(pid):
		var idx: int = clampi(await SelectionManager.await_choice(main, "%s: no podrá ser jugada hasta tu próximo turno" % _name(card),
			seen.map(func(c): return EnterScript._name(c)), pid), 0, seen.size() - 1)
		chosen = seen[idx]
	else:
		seen.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		chosen = seen[0]
	if main._gold_manager and is_instance_valid(chosen):
		main._gold_manager.lock_card_from_playing(chosen, pid)


static func _wani(main: Node, card: Node, pid: int) -> void:
	await ActionModule.destroy([card], card, false, true)
	_restricted_gold(main, pid, 1, func(t, _r, c): return t == Constants.CardType.ALIADO and int(c) >= 3, "%s: Oro para Aliados de coste 3 o más" % _name(card))


static func _shamisen(main: Node, card: Node, pid: int) -> void:
	if GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
		main._update_debug("%s: sólo en Guerra de Talismanes" % _name(card))
		return
	if await _exile_self(card, pid):
		_restricted_gold(main, pid, 1, func(t, _r, _c): return t == Constants.CardType.TALISMAN, "%s: Oro para Talismanes" % _name(card))


static func _la_luna(main: Node, card: Node, pid: int) -> void:
	_restricted_gold(main, pid, 1, func(t, _r, _c): return t == Constants.CardType.TOTEM, "%s: Oro para jugar un Tótem" % _name(card))


static func _castillo_edo(main: Node, card: Node, pid: int) -> void:
	var opp_type := -1
	for p in [pid, 1 - pid]:
		var deck: Array = CardManager.get_deck(p)
		if deck.is_empty():
			continue
		var d: Dictionary = deck.pop_front()
		main._update_debug("%s: J%d muestra %s" % [_name(card), p + 1, str(d.get("nombre", "?"))])
		RevealedCardsScript.record(p, [d], _name(card))
		if p != pid:
			opp_type = int(d.get("tipo", -1))
		if p != pid and opp_type == Constants.CardType.ORO and main._gold_manager:
			await main._gold_manager.put_gold_directly_in_pagado(pid, d)  # "si mostró un Oro, ponlo en tu Oro Pagado"
		else:
			PlayerSideScript.put_in_hand(main, p, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()
	if opp_type >= 0:
		RuleState.set_until("type_play_toll:%d" % opp_type, 1 - pid, RuleState.next_own_turn(pid) - 1)  # PaymentManager


static func _karl_red(main: Node, card: Node, pid: int) -> void:
	if not is_instance_valid(await _show_from_hand(main, card, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO, "muestra un Aliado de tu mano")):
		return
	var opp: int = 1 - pid
	var before: int = CardManager.get_cemetery(opp).size()
	await ActionModule.mill(opp, 3, false, _name(card))
	var milled: Array = CardManager.get_cemetery(opp).slice(before)
	if milled.any(func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ORO, Constants.CardType.ALIADO]):
		await _interp(card, "puedes poner un oro de un cementerio en tu oro pagado", pid)


static func _el_fantasma_activa(main: Node, card: Node, pid: int) -> void:
	var opp_cards: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var t: Node = await EnterScript._pick_from(main, pid, "%s: paga el coste de una carta oponente" % _name(card), opp_cards, true)
	if not is_instance_valid(t) or not await _pay_gold(main, pid, EnterScript._cost(t)):
		return
	var data: Dictionary = t.card_data.duplicate() if t.get("card_data") is Dictionary else {}
	var owner: int = int(t.owner_id) if t.get("owner_id") != null else 1 - pid
	await EnterScript._blank(t, card)
	await ActionModule.destroy([t], card, true)
	if data.is_empty():
		return
	for d in CardManager.get_cemetery(owner):
		if str(d.get("nombre", "")) == str(data.get("nombre", "")):
			if CardManager.take_from_cemetery(owner, d):
				if not await TalismanScript._play_paying(main, pid, d, 0):
					CardManager.add_to_cemetery(owner, d)
			break


static func _lord_blagrot(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: un Talismán de tu Cementerio pasa a ser Leyaden" % _name(card), 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["nombre"] = "Leyaden"
			data["habilidad"] = "Una vez por turno, tu oponente Bota una carta."
			await LeavePlayScript._ally_from_data(main, data, pid, pid, card, 1, [], "")


static func _fusil_patriota(main: Node, card: Node, pid: int) -> void:
	var taken := await _take_from_pools(main, pid, "%s: un Aliado de tu Castillo o Cementerio a tu mano" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": func(d): return _is_ally(d)},
		{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": func(d): return _is_ally(d)}])
	if not taken.is_empty():
		PlayerSideScript.put_in_hand(main, pid, taken.data)
	RuleState.set_turn_data("fusil_patriota:%d" % pid, {"base": RuleState.count("ally2_played", pid)})  # PaymentManager
	PaymentManager.invalidate_cache()


static func _mina_maldita(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var hand: Array = EnterScript._hand(main, opp)
	var draw := hand.is_empty()
	if not draw and not PlayerSideScript.is_bot(pid):
		draw = await SelectionManager.await_two_choice(main, _name(card), "Robar dos cartas", "Una carta al azar de la mano oponente a tu Oro Pagado", pid)
	if draw:
		await ActionModule.draw(pid, 2, _name(card), true)
		return
	var c: Node = hand[randi() % hand.size()]
	var data: Dictionary = PlayerSideScript.take_from_hand(main, opp, c)
	data["habilidad"] = ""
	data["tipo"] = Constants.CardType.ORO
	if main._gold_manager:
		await main._gold_manager.put_gold_directly_in_pagado(pid, data)


static func _estrella_solitaria(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	var taken := await _take_from_pools(main, pid, "%s: una carta que no sea Talismán de tu Castillo" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN}])
	if not taken.is_empty():
		PlayerSideScript.put_in_hand(main, pid, taken.data)


static func _primer_escudo(main: Node, card: Node, pid: int) -> void:
	var obj: Dictionary = StackAnnulScript.find_target(pid, true, false, func(o): return StackAnnulScript.type_of(o) == Constants.CardType.TALISMAN)
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO)
	if obj.is_empty() or allies.size() < 2:
		main._update_debug("%s: necesitas un Talismán que Anular y dos Aliados en tu mano" % _name(card))
		return
	await EnterScript._blank(card, card)
	if not await _pay_gold(main, pid, 1):
		return
	var two: Array = await EnterScript._pick_many(main, pid, "%s: muestra dos Aliados de tu mano" % _name(card), allies, 2, false)
	main._update_debug("%s: muestra %s" % [_name(card), ", ".join(two.map(func(c): return EnterScript._name(c)))])
	StackAnnulScript.apply(obj, card)


static func _allan_quatermain(main: Node, card: Node, pid: int) -> void:
	var t: Node = await _pick_in_play(main, pid, "%s: una carta que no sea Oro pierde la habilidad y es Destruida" % _name(card),
		func(c): return c != card and c.get("card_type") != Constants.CardType.ORO)
	if is_instance_valid(t):
		await EnterScript._blank(t, card)
		await ActionModule.destroy([t], card, true)


static func _otto_lidenbrock(main: Node, card: Node, pid: int) -> void:
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA
	var hand_weapons: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ARMA)
	var cem_weapons: Array = CardManager.get_cemetery(pid).filter(ok)
	if hand_weapons.is_empty() and cem_weapons.is_empty():
		return
	main._update_debug("%s: muestra un Arma" % _name(card))
	var in_play: Array = []
	for side in [1 - pid, pid]:
		in_play.append_array(EnterScript._in_play(main, side, func(c): return c != card and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 3)))
	var from_play := not in_play.is_empty()
	if from_play and not PlayerSideScript.is_bot(pid):
		from_play = await SelectionManager.await_two_choice(main, _name(card), "Una carta en juego de coste 3 o menos", "Una carta de un Cementerio", pid)
	if from_play:
		var t: Node = await _pick_in_play(main, pid, "%s: pasa a ser tu Aliado de Fuerza 2 sin habilidad" % _name(card), func(c): return c in in_play)
		if not is_instance_valid(t) or await ConvertScript.conversion_prevented(t, card):
			return
		var data: Dictionary = t.card_data.duplicate()
		var owner: int = int(t.owner_id) if t.get("owner_id") != null else pid
		await ActionModule.banish([t], card, true)  # deja el juego para volver convertida
		var ex: Array = CardManager.get_exile(owner)
		for d in ex:
			if str(d.get("nombre", "")) == str(data.get("nombre", "")):
				ex.erase(d)
				CardManager._emit_exile_changed(owner)
				break
		await LeavePlayScript._ally_from_data(main, data, owner, pid, card, 2, [], "")
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: una carta de un Cementerio como Aliado de Fuerza 2" % _name(card), 0, 1)
	for pk in picks:
		if CardManager.take_from_cemetery(pk.owner, pk.data):
			await LeavePlayScript._ally_from_data(main, pk.data, pk.owner, pid, card, 2, [], "")


static func _ahab(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if RuleState.count("played_any", opp) + RuleState.count("abilities_used", opp) <= 1:
		main._update_debug("%s: tu oponente no jugó cartas ni utilizó habilidades más de una vez este turno" % _name(card))
		return
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)


static func _medalla_legba(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	if RuleState.count("played_any", opp) + RuleState.count("abilities_used", opp) <= 2 \
			or not _allies(main, pid).any(func(c): return KeywordManager.has_keyword(c, Constants.Keyword.FURIA)):
		main._update_debug("%s: no se cumple la condición" % _name(card))
		return
	var deck: Array = CardManager.get_deck(opp)
	if deck.is_empty() or not main._gold_manager:
		return
	var data: Dictionary = deck.pop_front()
	data["habilidad"] = ""
	data["tipo"] = Constants.CardType.ORO
	await main._gold_manager.put_gold_directly_in_pagado(pid, data)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _james_moriarty(main: Node, card: Node, pid: int) -> void:
	if CardManager.get_exile(1 - pid).size() < 8:
		main._update_debug("%s: tu oponente necesita ocho o más cartas en su Destierro" % _name(card))
		return
	var others: Array = _allies(main, pid).filter(func(c): return c != card)
	var victim: Node = await EnterScript._pick_from(main, pid, "%s: Destruye otro Aliado que controles" % _name(card), others, true)
	if not is_instance_valid(victim):
		return
	await ActionModule.destroy([victim], card, true)
	DamageShieldsScript.add_next_zero(pid)


static func _escritura_sagrada(main: Node, card: Node, pid: int) -> void:
	var to_hand := true
	if not PlayerSideScript.is_bot(pid):
		to_hand = await SelectionManager.await_two_choice(main, _name(card), "Subirlo a tu mano", "Convertirlo en un Oro sin habilidad", pid)
	if to_hand:
		if not await EnterScript.bounce_to_owner_hand(main, card, card):
			return
	else:
		await EnterScript._blank(card, card)
	DamageShieldsScript.add_next_zero(pid)


static func _dulgruss(main: Node, card: Node, pid: int) -> void:
	var price := func(d) -> int: return maxi(int(d.get("coste", 0)) - 1, 0)
	var taken := await _take_from_pools(main, pid, "%s: un Aliado de tu Castillo para jugarlo bajo el control de tu oponente" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CASTILLO, "eligible": func(d): return _is_ally(d) and _payable(main, pid, price).call(d)}])
	if taken.is_empty():
		return
	var name := str(taken.data.get("nombre", ""))
	if not await _play_taken(main, pid, taken, price.call(taken.data)):
		return
	for c in _allies(main, pid):
		if EnterScript._name(c) == name:
			ContinuousEffectManager.gain_control_of_card(c, 1 - pid)
			break


static func _zagovornik(main: Node, card: Node, pid: int) -> void:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: un Talismán al Cementerio" % _name(card),
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN, 0, 1, false)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(pid, d)
		_grant_exhumar([d])
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _craneos_vivos(main: Node, card: Node, pid: int) -> void:
	await _pay_self_blank(main, card)
	var types: Dictionary = {}
	for p in [0, 1]:
		for d in CardManager.get_exile(p):
			types[int(d.get("tipo", -1))] = true
	if not types.is_empty():
		await ActionModule.mill(1 - pid, types.size(), false, _name(card))


# =============================================================================
# CUARTO LOTE: DESDE LA MANO, EL CEMENTERIO O EL ORO PAGADO
# =============================================================================
## Saca la propia carta de su zona (mano, Cementerio, Destierro) y devuelve sus datos. {} si ya no está
## (p.ej. el Paso B de la Pila ya pagó "Desterrarlo de tu Cementerio"); 'already' dice si ya no estaba.
static func _take_self(main: Node, card: Node, pid: int) -> Dictionary:
	if not is_instance_valid(card) or card.get("card_data") == null:
		return {}
	var zone = card.get("current_zone")
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	match zone:
		Constants.Zone.MANO:
			return PlayerSideScript.take_from_hand(main, owner, card)
		Constants.Zone.CEMENTERIO:
			var d: Dictionary = _find_data(CardManager.get_cemetery(owner), card.card_data)
			if not d.is_empty() and CardManager.take_from_cemetery(owner, d):
				return d
		Constants.Zone.DESTIERRO:
			var ex: Array = CardManager.get_exile(owner)
			var d2: Dictionary = _find_data(ex, card.card_data)
			if not d2.is_empty():
				ex.erase(d2)
				CardManager._emit_exile_changed(owner)
				return d2
	return {}


static func _find_data(arr: Array, data: Dictionary) -> Dictionary:
	for d in arr:
		if d == data or (str(d.get("id", "-")) == str(data.get("id", "+")) and str(d.get("nombre", "")) == str(data.get("nombre", ""))):
			return d
	return {}


## "Desterrarlo" (de la mano / Cementerio / en juego) como costo. true si se pagó o ya estaba pagado.
static func _exile_self_cost(main: Node, card: Node, pid: int) -> bool:
	if not is_instance_valid(card):
		return true  # ya lo pagó el Paso B
	var zone = card.get("current_zone")
	if zone in Constants.ZONES_IN_PLAY:
		return await _exile_self(card, pid)
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return zone != Constants.Zone.MANO  # del Cementerio ya no estaba: pagado
	d["esta_oculta"] = false
	CardManager.append_to_exile(owner, d)
	return true


## "Jugarlo" desde la mano o el Cementerio pagando 'price'.
static func _play_self(main: Node, card: Node, pid: int, price: int) -> void:
	var zone = card.get("current_zone") if is_instance_valid(card) else null
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return
	if not await TalismanScript._play_paying(main, pid, d, price):
		if zone == Constants.Zone.MANO:
			PlayerSideScript.put_in_hand(main, pid, d)
		else:
			CardManager.add_to_cemetery(pid, d)


static func _hikari_no_ga(main: Node, card: Node, pid: int) -> void:
	await ActionModule.mill(pid, 2, false, _name(card))
	await _play_self(main, card, pid, int(card.card_data.get("coste", 0)))


static func _el_carro(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1):
		return
	await _play_self(main, card, pid, int(card.card_data.get("coste", 0)))


## andras, iki balam, los korgors: "Si atacaste en tu turno anterior, puedes pagar un Oro para jugarlo sin
## pagar su coste".
static func _attacked_free_play(main: Node, card: Node, pid: int) -> void:
	if not BattleManager.attacked_in_previous_own_turn(pid):
		main._update_debug("%s: no atacaste en tu turno anterior" % _name(card))
		return
	if not await _pay_gold(main, pid, 1):
		return
	await _play_self(main, card, pid, 0)


static func _daikaiju_furioso(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1) or not main._gold_manager:
		return
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return
	var gold: Dictionary = d.duplicate()
	gold["habilidad"] = ""
	gold["tipo"] = Constants.CardType.ORO
	await main._gold_manager.put_gold_directly_in_pagado(pid, gold)


static func _orco_alpino(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "Orco Alpino: un Aliado pierde 2 de Fuerza", EnterScript._all_allies(main), false)
	if is_instance_valid(ally):
		await _buff(ally, null, -2)


static func _gusano_haftvad(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 1) or not await _exile_self_cost(main, card, pid):
		return
	RuleState.set_turn_data("cancel_next_ability:%d" % (1 - pid), {"by": pid})  # TriggerTollPatterns.consume_cancel_next
	main._update_debug("Gusano de Haftvad: la próxima habilidad que utilice tu oponente este turno será cancelada")


static func _ignis_azotamundos(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Ignis Azotamundos: otro Aliado de tu Cementerio como Titán sin habilidad", 0, 1,
		func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			var data: Dictionary = pk.data.duplicate()
			data["habilidad"] = ""
			data["nombre"] = "Titán"
			await _put_into_play(main, pid, data, pid)


static func _no_leave_until_next_turn(node: Node, pid: int) -> void:
	node.set_meta("no_leave_until", RuleState.next_own_turn(pid) - 1)  # EffectController.can_leave_play


static func _jared(main: Node, card: Node, pid: int) -> void:
	var small: Array = _allies(main, pid).filter(func(c): return ContinuousEffectManager.cost_at_most(c, 1))
	if small.is_empty() or _allies(main, pid).size() < 2:
		main._update_debug("Jared: necesitas un Aliado de coste 1 o menos y otro Aliado")
		return
	if not await _exile_self_cost(main, card, pid):
		return
	var cost_ally: Node = await EnterScript._pick_from(main, pid, "Jared: Destierra un Aliado de coste 1 o menos que controles", small, false)
	if not is_instance_valid(cost_ally):
		return
	await ActionModule.banish([cost_ally], null, true)
	var other: Node = await EnterScript._pick_from(main, pid, "Jared: otro Aliado queda sin habilidad y no puede salir del juego", _allies(main, pid), false)
	if is_instance_valid(other):
		await EnterScript._blank(other, null)
		other.set_meta("silenced_until", RuleState.next_own_turn(pid) - 1)
		_no_leave_until_next_turn(other, pid)


static func _jafet(main: Node, card: Node, pid: int) -> void:
	if not await _pay_gold(main, pid, 2) or not await _exile_self_cost(main, card, pid):
		return
	var chosen: Array = await EnterScript._pick_many(main, pid, "Jafet: hasta dos Aliados no pueden salir del juego hasta tu próximo turno",
		EnterScript._all_allies(main), 2, true)
	for c in chosen:
		_no_leave_until_next_turn(c, pid)


static func _pablo_pincheira(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var chosen: Node = await EnterScript._pick_from(main, pid, "Pablo Pincheira: juega un Aliado de tu mano pagando su coste", allies, true)
	if not is_instance_valid(chosen):
		return
	var pincheira: bool = "pincheira" in CemeteryTriggersScript.normalize(EnterScript._name(chosen))
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	if pincheira:
		main._gold_manager._alicanto_paid_pending[pid] = true  # no puede ser Anulado (como Alicanto)
	if not await TalismanScript._play_paying(main, pid, data, int(data.get("coste", 0))):
		main._gold_manager._alicanto_paid_pending.erase(pid)
		PlayerSideScript.put_in_hand(main, pid, data)
		return
	if pincheira:
		for c in _allies(main, pid):
			if EnterScript._name(c) == str(data.get("nombre", "")):
				c.set_meta("protected_from_cancel_turn", GameManager.turn_serial)  # ni sus habilidades canceladas
				break


static func _baphomet(main: Node, card: Node, pid: int) -> void:
	var others: Array = EnterScript._hand(main, pid).filter(func(c): return c != card)
	var cost_card: Node = await EnterScript._pick_from(main, pid, "Baphomet: Descarta una carta de tu mano", others, true)
	if not is_instance_valid(cost_card):
		return
	await ActionModule.discard(pid, [cost_card], _name(card), true)
	await _play_self(main, card, pid, maxi(int(card.card_data.get("coste", 0)) - 1, 0))


static func _palo_del_caos(main: Node, card: Node, pid: int) -> void:
	if card.get("current_zone") != Constants.Zone.ORO_PAGADO:
		main._update_debug("Palo del Caos: solo si está en tu Oro Pagado")
		return
	if EnterScript._hand(main, pid).is_empty():
		return
	await EnterScript._discard_own(main, card, pid, 1)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Palo del Caos: un Aliado de tu Cementerio a tu mano", 0, 1, func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


static func _stegosaurus(main: Node, card: Node, pid: int) -> void:
	if is_instance_valid(card) and card.get("current_zone") == Constants.Zone.MANO:
		await ActionModule.discard(pid, [card], "Dinosaurio Stegosaurus", true)
	var g: Node = await EnterScript._pick_from(main, pid, "Dinosaurio Stegosaurus: un Oro oponente pierde su habilidad por el turno",
		EnterScript._golds(main, [1 - pid]), false)
	if is_instance_valid(g):
		g.set_meta("silenced_on_turn", GameManager.turn_serial)


static func _los_marcados(main: Node, card: Node, pid: int) -> void:
	if not await _exile_self_cost(main, card, pid):
		return
	RuleState.set_turn_data("block_cap:%d" % (1 - pid), {"n": 2})  # GameManager.declare_blocker
	main._update_debug("Los Marcados: tu oponente no puede declarar más de dos bloqueadores este turno")


static func _alicia(main: Node, card: Node, pid: int) -> void:
	if EnterScript._golds(main, [pid]).size() > EnterScript._golds(main, [1 - pid]).size():
		main._update_debug("Alicia: controlas más Oros que tu oponente")
		return
	if not await _pay_gold(main, pid, 1) or not main._gold_manager:
		return
	var d := _take_self(main, card, pid)
	if not d.is_empty():
		await main._gold_manager.put_gold_directly_in_pagado(pid, d)


static func _altar_moloch(main: Node, card: Node, pid: int) -> void:
	var mine_there: Array = EnterScript._in_play(main, 1 - pid, func(c): return c.get("card_type") != Constants.CardType.ORO \
		and int(c.get("owner_id")) == pid and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var t: Node = await EnterScript._pick_from(main, pid, "Altar de Moloch: paga el coste de una carta tuya que controle tu oponente", mine_there, true)
	if not is_instance_valid(t):
		return
	var name := EnterScript._name(t)
	if not await _pay_gold(main, pid, EnterScript._cost(t)) or not await EnterScript.bounce_to_owner_hand(main, t, card):
		return
	for c in EnterScript._hand(main, pid):
		if EnterScript._name(c) == name:
			var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, c)
			if not await TalismanScript._play_paying(main, pid, data, 0):
				PlayerSideScript.put_in_hand(main, pid, data)
			return


static func _hacha_perun(main: Node, card: Node, pid: int) -> void:
	var bearer = card.get("wielder") if is_instance_valid(card) else null
	var rivals: Array = []
	for attacker in GameManager.blockers:
		var b = GameManager.blockers[attacker]
		if not (is_instance_valid(attacker) and is_instance_valid(b)):
			continue
		if attacker == bearer:
			rivals.append(b)
		elif b == bearer:
			rivals.append(attacker)
	rivals = rivals.filter(func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	var t: Node = await EnterScript._pick_from(main, pid, "Hacha de Perun: Destruye el Aliado de coste 2 o menos", rivals, true)
	if is_instance_valid(t):
		await ActionModule.destroy([t], card, true)
	elif rivals.is_empty():
		main._update_debug("Hacha de Perun: el portador no bloquea ni es bloqueado por un Aliado de coste 2 o menos")


static func _hangaku_gozen(main: Node, card: Node, pid: int) -> void:
	if not (card.get("equipped_weapons") is Array and card.equipped_weapons.any(func(w): return is_instance_valid(w))):
		main._update_debug("Hangaku Gozen: solo si porta Armas")
		return
	var allies: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and EnterScript._cost(c) <= 2 and not ("hangaku gozen" in CemeteryTriggersScript.normalize(EnterScript._name(c))))
	var chosen: Node = await EnterScript._pick_from(main, pid, "Hangaku Gozen: juega un Aliado de coste 2 o menos sin pagar su coste", allies, true)
	if not is_instance_valid(chosen):
		return
	var name := EnterScript._name(chosen)
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	if not await TalismanScript._play_paying(main, pid, data, 0):
		PlayerSideScript.put_in_hand(main, pid, data)
		return
	var played: Node = null
	for c in _allies(main, pid):
		if EnterScript._name(c) == name:
			played = c
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		if is_instance_valid(played) and played.get("current_zone") in Constants.ZONES_IN_PLAY:
			await EnterScript._blank(played, null)
			await ActionModule.banish([played], null, true))


static func _lord_john_roxton(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Lord John Roxton: un Arma de tu Cementerio a tu mano", 0, 1,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ARMA)
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)
	# "cambiar de portador un Arma que controles": pendiente (no hay una pieza para mover un Arma portada).


# =============================================================================
# QUINTO LOTE
# =============================================================================
## colmillo arcano, gema del grifo, amuleto de cazador: el Oro pasa a ser un Aliado de Fuerza N con la habilidad
## entre comillas hasta tu próximo turno (al empezarlo vuelve a ser ese Oro, en tu Oro Pagado).
static func _gold_to_ally_until_next_turn(main: Node, card: Node, pid: int, strength: int, ability: String) -> void:
	if card.get("card_type") != Constants.CardType.ORO or not (card.get("current_zone") in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]):
		return
	var original: String = str(card.card_data.get("habilidad", ""))
	if card.get("current_zone") == Constants.Zone.ORO_PAGADO:
		GameState.agregar_oro_pagado(pid, -1)
	else:
		GameState.agregar_oro_reserva(pid, -1)
	card.get_parent().remove_child(card)
	card.card_type = Constants.CardType.ALIADO
	card.scale = Vector2.ONE
	card.base_scale = Vector2.ONE
	card.modulate = Color.WHITE
	PlayerSideScript.ally_containers(main, pid)[0].add_child(card)
	card.set_zone(Constants.Zone.LINEA_DEFENSA)
	EnterScript.set_ability(card, ability)
	ContinuousEffectManager.register_modifier({
		"source": card, "target": card, "type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
		"value": strength, "operation": "set", "duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "%s: Aliado de Fuerza %d" % [_name(card), strength],
	})
	if card.has_method("refresh_strength_badge"):
		card.refresh_strength_badge()
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	main._update_debug("%s pasa a ser un Aliado de Fuerza %d hasta tu próximo turno" % [_name(card), strength])
	_revert_on_next_turn(main, card, pid, original)


static func _revert_on_next_turn(main: Node, card: Node, pid: int, original: String) -> void:
	var revert: Callable
	revert = func(started: int, _turn: int) -> void:
		if started != pid:
			return
		if GameManager.turn_started.is_connected(revert):
			GameManager.turn_started.disconnect(revert)
		if not is_instance_valid(card) or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
			return
		ContinuousEffectManager.remove_modifiers_from_source(card)
		var wielder = card.get("wielder")
		if is_instance_valid(wielder):
			CardManager._unequip_from_wielder(card)
			card.wielder = null
		if card.get_parent():
			card.get_parent().remove_child(card)
		card.card_type = Constants.CardType.ORO
		KeywordManager.clear_all_for_card(card)
		EnterScript.set_ability(card, original)
		PlayerSideScript.oro_pagado(main, pid).add_child(card)
		card.set_zone(Constants.Zone.ORO_PAGADO)
		card.scale = Constants.GOLD_CARD_SCALE
		card.base_scale = Constants.GOLD_CARD_SCALE
		card.modulate = Color(0.6, 0.6, 0.6, 1.0)
		GameState.agregar_oro_pagado(pid, 1)
		if main._gold_manager:
			main._gold_manager._update_gold_display()
		main._update_debug("%s vuelve a ser un Oro" % _name(card))
	GameManager.turn_started.connect(revert)


static func _quoted(card: Node) -> String:
	var m := RegEx.create_from_string("con la habilidad [\"“”]([^\"“”]+)[\"“”]").search(str(card.card_data.get("habilidad", "")))
	return m.get_string(1) if m else ""


static func _colmillo_arcano(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).any(func(c): return KeywordManager.has_keyword(c, Constants.Keyword.FURIA)):
		main._update_debug("%s: necesitas controlar Aliados con Furia" % _name(card))
		return
	await _gold_to_ally_until_next_turn(main, card, pid, 3, _quoted(card))


static func _gema_grifo(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).any(func(c): return EnterScript._cost(c) >= 2):
		main._update_debug("%s: necesitas controlar Aliados de coste 2 o más" % _name(card))
		return
	await _gold_to_ally_until_next_turn(main, card, pid, 4, _quoted(card))


static func _amuleto_cazador(main: Node, card: Node, pid: int) -> void:
	if RuleState.count("played_type:%d" % Constants.CardType.TALISMAN, pid) < 2:
		main._update_debug("%s: necesitas haber jugado dos o más Talismanes este turno" % _name(card))
		return
	await _gold_to_ally_until_next_turn(main, card, pid, 5, _quoted(card))


## arpon sagrado: el Oro pasa a ser un Arma con la habilidad entre comillas hasta tu próximo turno y la porta un
## Aliado que controles.
static func _arpon_sagrado(main: Node, card: Node, pid: int) -> void:
	if not (card.get("current_zone") in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]) or not main._gold_manager:
		return
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado que controles porta el Arma" % _name(card), _allies(main, pid), true)
	if not is_instance_valid(ally):
		return
	var original: String = str(card.card_data.get("habilidad", ""))
	if card.get("current_zone") == Constants.Zone.ORO_PAGADO:
		GameState.agregar_oro_pagado(pid, -1)
	else:
		GameState.agregar_oro_reserva(pid, -1)
	card.card_type = Constants.CardType.ARMA
	card.modulate = Color.WHITE
	EnterScript.set_ability(card, _quoted(card))
	await main._gold_manager._equip_weapon(card, ally, false)
	main._gold_manager._update_gold_display()
	_revert_on_next_turn(main, card, pid, original)


static func _to_attack_line(main: Node, ally: Node, pid: int) -> void:
	var line: Node = PlayerSideScript.ally_containers(main, pid)[1] if PlayerSideScript.ally_containers(main, pid).size() > 1 else null
	if not line or not is_instance_valid(ally) or ally.get_parent() == line:
		return
	ally.get_parent().remove_child(ally)
	ally.set_meta("idle_attack_line", true)  # azul hielo mientras no ataque (CardInteractionModule)
	line.add_child(ally)
	ally.set_zone(Constants.Zone.LINEA_ATAQUE)
	main._update_debug("%s pasa a la Línea de Ataque" % EnterScript._name(ally))


static func _akashi(main: Node, card: Node, pid: int) -> void:
	var defenders: Array = _allies(main, pid).filter(func(c): return c.get("current_zone") == Constants.Zone.LINEA_DEFENSA)
	var mover: Node = await EnterScript._pick_from(main, pid, "Akashi: mueve un Aliado a la Línea de Ataque", defenders, true)
	if is_instance_valid(mover):
		_to_attack_line(main, mover, pid)
	var small: Array = EnterScript._all_allies(main, func(c): return ContinuousEffectManager.cost_at_most(c, 2))
	var t: Node = await EnterScript._pick_from(main, pid, "Akashi: sube un Aliado de coste 2 o menos a la mano de su dueño", small, true)
	if is_instance_valid(t):
		await EnterScript.bounce_to_owner_hand(main, t, card)


static func _batallon_ovejas(main: Node, card: Node, pid: int) -> void:
	_to_attack_line(main, card, pid)
	var t: Node = await EnterScript._pick_from(main, pid, "Batallón de Ovejas: un Aliado no puede bloquear este turno", _allies(main, 1 - pid), true)
	if not is_instance_valid(t):
		return
	ContinuousEffectManager.register_modifier({
		"source": t, "target": t, "type": ContinuousEffectManager.ModifierType.RESTRICTION, "restriction_type": "CANT_BLOCK",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN, "description": "No puede bloquear este turno (Batallón de Ovejas)",
	})
	main._update_debug("%s no puede bloquear este turno" % EnterScript._name(t))


## tundra viva / isla de gigantes: cartas del Cementerio ganan una habilidad (permanente) que se usa desde ahí.
const TUNDRA_GRANT := "Destierra dos cartas de tu Cementerio para subirlo a tu mano."
const ISLA_GRANT := "Destierra tres cartas de tu Cementerio para jugarlo pagando su coste y Destiérralo."


static func _grant_in_cemetery(main: Node, card: Node, pid: int, filter: Callable, text: String, title: String) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: %s" % [_name(card), title], 0, 3, filter)
	for pk in picks:
		var d: Dictionary = pk.data
		if not (text in str(d.get("habilidad", ""))):
			d["habilidad"] = (str(d.get("habilidad", "")) + "\n" + text).strip_edges()
	if not picks.is_empty():
		main._update_debug("%s: %d carta(s) de tu Cementerio ganan \"%s\"" % [_name(card), picks.size(), text])


static func _tundra_viva(main: Node, card: Node, pid: int) -> void:
	await _grant_in_cemetery(main, card, pid, func(d): return int(d.get("tipo", -1)) in [Constants.CardType.ALIADO, Constants.CardType.ARMA] \
		and int(d.get("coste", 0)) >= 1, TUNDRA_GRANT, "hasta tres Aliados y/o Armas de coste 1 o más")


static func _isla_gigantes(main: Node, card: Node, pid: int) -> void:
	await _grant_in_cemetery(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN \
		and int(d.get("coste", 0)) >= 1, ISLA_GRANT, "hasta tres Talismanes de coste 1 o más")


## El costo de las habilidades ganadas: Desterrar N otras cartas de tu Cementerio.
static func _exile_other_cemetery(main: Node, card: Node, pid: int, n: int) -> bool:
	var own: Dictionary = card.card_data if is_instance_valid(card) and card.get("card_data") is Dictionary else {}
	var others: Array = CardManager.get_cemetery(pid).filter(func(d): return _find_data([d], own).is_empty())
	if others.size() < n:
		main._update_debug("Necesitas otras %d cartas en tu Cementerio" % n)
		return false
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "Destierra %d cartas de tu Cementerio" % n, n, n,
		func(d): return _find_data([d], own).is_empty())
	if picks.size() < n:
		return false
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			pk.data["esta_oculta"] = false
			CardManager.append_to_exile(pid, pk.data)
	return true


static func _tundra_granted(main: Node, card: Node, pid: int) -> void:
	if not await _exile_other_cemetery(main, card, pid, 2):
		return
	var d := _take_self(main, card, pid)
	if not d.is_empty():
		PlayerSideScript.put_in_hand(main, pid, d)


static func _isla_granted(main: Node, card: Node, pid: int) -> void:
	if not await _exile_other_cemetery(main, card, pid, 3):
		return
	var d := _take_self(main, card, pid)
	if d.is_empty():
		return
	if not await TalismanScript._play_paying(main, pid, d, int(d.get("coste", 0))):
		CardManager.add_to_cemetery(pid, d)
		return
	# "y Destiérralo": el Talismán resuelto pasa del Cementerio al Destierro.
	var cem: Array = CardManager.get_cemetery(pid)
	for i in range(cem.size() - 1, -1, -1):
		if str(cem[i].get("nombre", "")) == str(d.get("nombre", "")):
			var t: Dictionary = cem[i]
			if CardManager.take_from_cemetery(pid, t):
				CardManager.append_to_exile(pid, t)
			break


# =============================================================================
# SEXTO LOTE: Báculo de los Eternos, ayyappan, Caos
# =============================================================================
static func _baculo_eternos(main: Node, card: Node, pid: int) -> void:
	var n: int = EnterScript._in_play(main, pid, func(c): return c.get("card_type") in [Constants.CardType.ARMA, Constants.CardType.TOTEM]).size()
	for a in _allies(main, pid):
		if a.get("equipped_weapons") is Array:
			n += a.equipped_weapons.filter(func(w): return is_instance_valid(w)).size()
	if n > 0:
		await CastleLookScript.look(pid, pid, n, true, CastleLookScript.rest_box(true), "%s: ordena las cartas del tope de tu Castillo" % _name(card))
	if await EnterScript._confirm(main, pid, _name(card), "Robar una carta (no Robas al finalizar tu turno)"):
		await ActionModule.draw(pid, 1, _name(card), true)
		TriggerSystem._oro_patterns.register_torii_skip_final_draw(pid)


## ayyappan: "puedes mostrar un Aliado Caballero de tu mano para activar la habilidad de un Arma que hayas
## activado este turno" (otra vez, sin su límite por turno).
static func _ayyappan(main: Node, card: Node, pid: int) -> void:
	var options: Array = []  # [{weapon, ability}]
	var weapons: Array = CardQuery.weapons_in_play(pid)
	for w in weapons:
		if not is_instance_valid(w) or w.get("card_data") == null:
			continue
		for ab in UniversalCardParser.parse_abilities(str(w.card_data.get("habilidad", "")), str(w.card_data.get("id", ""))):
			if ab.get("ability_type", "") == "ACTIVATED" and UniversalCardParser.turn_registry.was_used(
					str(w.get_instance_id()), int(ab.get("ability_index", 0)), GameManager.turn_serial):
				options.append({"weapon": w, "ability": ab})
	if options.is_empty():
		main._update_debug("Ayyappan: no activaste la habilidad de un Arma este turno")
		return
	var knights: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and "caballero" in CemeteryTriggersScript.normalize(str(c.get("card_raza"))))
	var shown: Node = await EnterScript._pick_from(main, pid, "Ayyappan: muestra un Aliado Caballero de tu mano", knights, true)
	if not is_instance_valid(shown):
		return
	main._update_debug("Ayyappan: muestra %s" % EnterScript._name(shown))
	var idx := 0
	if options.size() > 1 and not PlayerSideScript.is_bot(pid):
		idx = clampi(await SelectionManager.await_choice(main, "Ayyappan: ¿qué habilidad activas otra vez?",
			options.map(func(o): return "%s: %s" % [EnterScript._name(o.weapon), str(o.ability.get("raw_text", "")).substr(0, 50)]), pid), 0, options.size() - 1)
	var chosen: Dictionary = options[idx]
	if main.get("_card_inspector") and main._card_inspector.has_method("activate_ability_for"):
		await main._card_inspector.activate_ability_for(chosen.weapon, chosen.ability, pid)


## Caos: "Una vez en tu turno, un Oro gana la habilidad "Cuando lo pagues, conviértelo en un Aliado de Fuerza 3.
## Cuando haga daño, convierte este Aliado en un Oro y ponlo a tu Oro Pagado."" Al pagarlo:
## GoldManager._mover_oro_a_pagado() → caos_to_ally(); al hacer daño (BattleManager) → caos_back_to_gold().
const CAOS_GRANT := "Cuando lo pagues, conviértelo en un Aliado de Fuerza 3. Cuando haga daño, convierte este Aliado en un Oro y ponlo a tu Oro Pagado."


static func _caos(main: Node, card: Node, pid: int) -> void:
	var golds: Array = EnterScript._golds(main, [pid]).filter(func(g): return not g.get_meta("caos_gold", false))
	var g: Node = await EnterScript._pick_from(main, pid, "Caos: un Oro gana la habilidad", golds, false)
	if not is_instance_valid(g):
		return
	g.set_meta("caos_original", str(g.card_data.get("habilidad", "")))
	g.set_meta("caos_gold", true)
	EnterScript.set_ability(g, (str(g.card_data.get("habilidad", "")) + "\n" + CAOS_GRANT).strip_edges())
	main._update_debug("Caos: %s gana \"%s\"" % [EnterScript._name(g), CAOS_GRANT])


static func caos_to_ally(main: Node, g: Node) -> void:
	var pid: int = int(g.controller_id) if g.get("controller_id") != null else 0
	if g.get_parent():
		g.get_parent().remove_child(g)
	g.card_type = Constants.CardType.ALIADO
	g.scale = Vector2.ONE
	g.base_scale = Vector2.ONE
	g.modulate = Color.WHITE
	g.can_interact = pid == 0
	PlayerSideScript.ally_containers(main, pid)[0].add_child(g)
	g.set_zone(Constants.Zone.LINEA_DEFENSA)
	g.set_meta("caos_ally", true)
	ContinuousEffectManager.register_modifier({
		"source": g, "target": g, "type": ContinuousEffectManager.ModifierType.STRENGTH, "stat": "strength",
		"value": 3, "operation": "set", "duration": ContinuousEffectManager.ModifierDuration.PERMANENT,
		"layer": ContinuousEffectManager.ModifierLayer.LAYER_7A_CHAR_SETTING, "description": "Caos: Aliado de Fuerza 3",
	})
	if g.has_method("refresh_strength_badge"):
		g.refresh_strength_badge()
	main._update_debug("%s pasa a ser un Aliado de Fuerza 3 (Caos)" % EnterScript._name(g))


static func caos_back_to_gold(main: Node, g: Node) -> void:
	if not is_instance_valid(g) or not g.get_meta("caos_ally", false) or not (g.get("current_zone") in Constants.ZONES_IN_PLAY):
		return
	var pid: int = int(g.controller_id) if g.get("controller_id") != null else 0
	ContinuousEffectManager.remove_modifiers_from_source(g)
	GameManager.attackers.erase(g)
	if g.get_parent():
		g.get_parent().remove_child(g)
	g.card_type = Constants.CardType.ORO
	g.remove_meta("caos_ally")
	g.remove_meta("caos_gold")
	EnterScript.set_ability(g, str(g.get_meta("caos_original", "")))
	PlayerSideScript.oro_pagado(main, pid).add_child(g)
	g.set_zone(Constants.Zone.ORO_PAGADO)
	g.scale = Constants.GOLD_CARD_SCALE
	g.base_scale = Constants.GOLD_CARD_SCALE
	g.modulate = Color(0.6, 0.6, 0.6, 1.0)
	GameState.agregar_oro_pagado(pid, 1)
	if main._gold_manager:
		main._gold_manager._update_gold_display()
	main._update_debug("%s hizo daño: vuelve a ser un Oro en tu Oro Pagado (Caos)" % EnterScript._name(g))



# =============================================================================
# SÉPTIMO LOTE: Fase Final, Vigilia y Destruido
# =============================================================================
## Agrupar un Aliado (DAR 5.1): de la Línea de Ataque vuelve a la Línea de Defensa.
static func _regroup(main: Node, allies: Array) -> void:
	var in_atk: Array = allies.filter(func(a): return is_instance_valid(a) and a.get("current_zone") == Constants.Zone.LINEA_ATAQUE)
	if not in_atk.is_empty() and main.get("_card_interaction"):
		await main._card_interaction.unmark_attackers(in_atk)


## hacha de perun: "En tu Fase Final, agrupa al portador."
static func _regroup_bearer(main: Node, card: Node, _pid: int) -> void:
	var bearer = card.get("wielder")
	if is_instance_valid(bearer):
		await _regroup(main, [bearer])


## espada de akmallah: "En tu Fase Final, agrupa tus Aliados."
static func _regroup_own_allies(main: Node, _card: Node, pid: int) -> void:
	await _regroup(main, _allies(main, pid))


## ayyappan: "Tus Aliados que porten Armas pueden ser agrupados en tu Fase Final" (opcional, los que elijas).
static func _ayyappan_regroup(main: Node, card: Node, pid: int) -> void:
	var armed: Array = _allies(main, pid).filter(func(a): return a.get("current_zone") == Constants.Zone.LINEA_ATAQUE \
		and a.get("equipped_weapons") is Array and a.equipped_weapons.any(func(w): return is_instance_valid(w)))
	if armed.is_empty():
		return
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: agrupa tus Aliados que porten Armas" % _name(card), armed, armed.size(), true)
	await _regroup(main, chosen)


## ayyappan: "...y no pueden ser Destruidos en Asignación de Daño" (BattleManager).
static func ayyappan_protects(ally: Node) -> bool:
	if not is_instance_valid(ally) or not (ally.get("equipped_weapons") is Array) \
			or not ally.equipped_weapons.any(func(w): return is_instance_valid(w)):
		return false
	return not CardQuery.cards_in_play_with(CardQuery.controller_of(ally), "tus aliados que porten armas pueden ser agrupados en tu fase final").is_empty()


## martillo mjlnir: "En tu Fase Final, si el portador hizo daño de combate este turno, puedes Desterrar hasta
## cinco cartas de un Cementerio." (meta "combat_damage_turn", GoldManager)
static func _mjolnir_final(main: Node, card: Node, pid: int) -> void:
	var bearer = card.get("wielder")
	if not is_instance_valid(bearer) or int(bearer.get_meta("combat_damage_turn", -1)) != GameManager.turn_serial:
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid, 1 - pid], "%s: Destierra hasta cinco cartas de un Cementerio" % _name(card), 0, 5)
	for pk in picks:
		var owner: int = int(pk.get("owner", pid))
		if CardManager.take_from_cemetery(owner, pk.data):
			CardManager.append_to_exile(owner, pk.data)
	if not picks.is_empty():
		main._update_debug("%s: Destierras %d carta(s) de un Cementerio" % [_name(card), picks.size()])


## cahuelche: "Cuando sea Destruido, tu oponente Bota cartas igual a la Fuerza de un Aliado en juego."
static func _cahuelche_destroyed(main: Node, card: Node, pid: int) -> void:
	var allies: Array = EnterScript._all_allies(main, func(_c): return true)
	var t: Node = await EnterScript._pick_from(main, pid, "%s: tu oponente Bota cartas igual a la Fuerza de un Aliado en juego" % _name(card), allies, false)
	if not is_instance_valid(t):
		return
	var n: int = maxi(0, int(ContinuousEffectManager.get_modified_strength(t)))
	if n > 0:
		await ActionModule.mill(1 - pid, n, false, _name(card))


## Disparadores al comienzo de la Vigilia que no están en el campo del jugador activo
## (TriggerSystem.resolve_vigilia_triggers): pulsera de energia (desde tu Cementerio) y París (en juego del
## rival: "Al comienzo de la Vigilia oponente").
const PULSERA_VIGILIA := "al comienzo de tu vigilia, si esta en tu cementerio, puedes desterrar dos cartas de tu cementerio para subirlo a tu mano"
const PARIS_VIGILIA := "al comienzo de la vigilia oponente, puedes jugar un arma o totem de tu mano pagando su coste"


static func vigilia_start_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_cemetery(pid).duplicate():
		if PULSERA_VIGILIA in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))):
			await _pulsera_vigilia(main, pid, d)
	for c in EnterScript._in_play(main, 1 - pid, func(x): return PARIS_VIGILIA in CemeteryTriggersScript.normalize(CardQuery.ability_of(x))):
		if not KeywordManager.is_silenced(c):
			await _paris_vigilia(main, c, 1 - pid)


static func _pulsera_vigilia(main: Node, pid: int, data: Dictionary) -> void:
	var name := str(data.get("nombre", "Pulsera de Energía"))
	var others: Array = CardManager.get_cemetery(pid).filter(func(x): return not is_same(x, data))
	if others.size() < 2 or not await EnterScript._confirm(main, pid, name, "Desterrar dos cartas de tu Cementerio para subirla a tu mano"):
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: Destierra dos cartas de tu Cementerio" % name, 2, 2, func(x): return not is_same(x, data))
	if picks.size() < 2:
		return
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			CardManager.append_to_exile(pid, pk.data)
	if CardManager.take_from_cemetery(pid, data):
		PlayerSideScript.put_in_hand(main, pid, data)
		main._update_debug("%s vuelve a tu mano" % name)


static func _paris_vigilia(main: Node, card: Node, pid: int) -> void:
	var options: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") in [Constants.CardType.ARMA, Constants.CardType.TOTEM] \
		and main._gold_manager and main._gold_manager.puede_pagar(EnterScript._cost(c), -1, "", -1, pid))
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: puedes jugar un Arma o Tótem de tu mano pagando su coste" % _name(card), options, true)
	if not is_instance_valid(chosen):
		return
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	if not await TalismanScript._play_paying(main, pid, data, int(data.get("coste", 0))):
		PlayerSideScript.put_in_hand(main, pid, data)



# =============================================================================
# OCTAVO LOTE: los últimos sin handler (Fase Final, Vigilia, daño, Agrupación, activadas sueltas)
# =============================================================================
static func _noop(_main: Node, _card: Node, _pid: int) -> void:
	pass


static func _bearer(card: Node) -> Node:
	var w = card.get("wielder")
	return w if is_instance_valid(w) else null


static func _exile_cemetery_picks(picks: Array) -> void:
	for pk in picks:
		var owner: int = int(pk.get("owner", 0))
		if CardManager.take_from_cemetery(owner, pk.data):
			CardManager.append_to_exile(owner, pk.data)


## "Destierra hasta N cartas de un/cualquier Cementerio" (uno solo).
static func _exile_from_a_cemetery(main: Node, card: Node, pid: int, n: int, min_n: int = 0, owners: Array = []) -> void:
	if owners.is_empty():
		owners = [1 - pid, pid]
	var picks: Array = await EnterScript._pick_cemetery(pid, owners, "%s: Destierra hasta %d carta(s) de un Cementerio" % [_name(card), n], min_n, n)
	_exile_cemetery_picks(picks)
	if not picks.is_empty():
		main._update_debug("%s: Destierras %d carta(s) de un Cementerio" % [_name(card), picks.size()])


static func _silence_until_next_turn(target: Node, pid: int) -> void:
	if is_instance_valid(target):
		target.set_meta("silenced_until", RuleState.next_own_turn(pid) - 1)  # KeywordManager.is_silenced
		KeywordManager._notify_abilities_changed()


static func _gold_from_castle_to_paid(main: Node, card: Node, pid: int) -> void:
	var picked: Array = await AttackScript._pick_from_castle(pid, pid, "%s: busca un Oro en tu Castillo y ponlo en tu Oro Pagado" % _name(card),
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO, 0, 1, false)
	for d in picked:
		d["esta_oculta"] = false
		await main._gold_manager.put_gold_directly_in_pagado(pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# --- Fase Final -----------------------------------------------------------------
## amuleto de thor: "puedes Desterrar la primera carta de tu Castillo para agrupar este Oro".
static func _amuleto_thor(main: Node, card: Node, pid: int) -> void:
	if card.get("current_zone") != Constants.Zone.ORO_PAGADO or CardManager.get_deck(pid).is_empty() or not main._gold_manager:
		return
	if not await EnterScript._confirm(main, pid, _name(card), "Desterrar la primera carta de tu Castillo para agrupar este Oro"):
		return
	await ActionModule.mill(pid, 1, true, _name(card))
	await main._gold_manager._agrupar_oro(pid, card)
	main._gold_manager._update_gold_display()


## atlatl: "si el portador hizo daño de combate este turno, puedes buscar un Oro en tu Castillo y ponerlo en tu Oro Pagado".
static func _atlatl(main: Node, card: Node, pid: int) -> void:
	var b := _bearer(card)
	if b and int(b.get_meta("combat_damage_turn", -1)) == GameManager.turn_serial:
		await _gold_from_castle_to_paid(main, card, pid)


## cañón naval: "puedes Botar las primeras dos carta de tu Castillo para agrupar un Oro".
static func _canon_naval_final(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or not await EnterScript._confirm(main, pid, _name(card), "Botar las dos primeras cartas de tu Castillo para agrupar un Oro"):
		return
	await ActionModule.mill(pid, 2, false, _name(card))
	await main._gold_manager.agrupar_oros(pid, 1)


## Cráneo de Cristal: "si no pusiste Oros en juego este turno, pon un Oro de tu mano o Cementerio en tu Reserva. Ese
## Oro entra en juego sin habilidad hasta tu próximo turno".
static func _craneo_cristal(main: Node, card: Node, pid: int) -> void:
	if GameManager.oro_played_this_turn or not main._gold_manager:
		return
	var is_gold := func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO
	var taken := await _take_from_pools(main, pid, "%s: pon un Oro de tu mano o Cementerio en tu Reserva" % _name(card),
		[{"owner": pid, "zone": Constants.Zone.CEMENTERIO, "eligible": is_gold}], is_gold)
	if taken.is_empty():
		return
	var gold: Node = await main._gold_manager.put_gold_directly_in_reserva(pid, taken.data)
	_silence_until_next_turn(gold, pid)
	main._gold_manager._update_gold_display()


## dietrich von bern: "Destierra hasta dos cartas del Cementerio oponente".
static func _dietrich(main: Node, card: Node, pid: int) -> void:
	await _exile_from_a_cemetery(main, card, pid, 2, 0, [1 - pid])


## reino de midgard: "Destierra hasta dos cartas de cualquier Cementerio" / "En la Fase Final oponente, tu oponente Bota una carta".
static func _midgard_final(main: Node, card: Node, pid: int) -> void:
	await _exile_from_a_cemetery(main, card, pid, 2)


static func _midgard_opp_final(_main: Node, card: Node, pid: int) -> void:
	await ActionModule.mill(1 - pid, 1, false, _name(card))


static func _controls_named(main: Node, pid: int, name: String) -> bool:
	return _allies(main, pid).any(func(a): return name in CemeteryTriggersScript.normalize(EnterScript._name(a)))


## fujin / raijin: "si controlas a Raijin, puedes agrupar un Oro" / "si controlas a Fujin, puedes Robar una carta".
static func _fujin(main: Node, card: Node, pid: int) -> void:
	if _controls_named(main, pid, "raijin") and main._gold_manager \
			and await EnterScript._confirm(main, pid, _name(card), "Agrupar un Oro"):
		await main._gold_manager.agrupar_oros(pid, 1)


static func _raijin(main: Node, card: Node, pid: int) -> void:
	if _controls_named(main, pid, "fujin") and await EnterScript._confirm(main, pid, _name(card), "Robar una carta"):
		await ActionModule.draw(pid, 1, _name(card), true)


## Guadaña de Santa Muerte: "si no controlas Aliados con Furia o Imbloqueable, agrupa un Oro y muestra cartas del tope de
## tu Castillo hasta mostrar un Talismán y ponlo en tu mano".
static func _guadana(main: Node, card: Node, pid: int) -> void:
	if _allies(main, pid).any(func(a): return KeywordManager.has_keyword(a, Constants.Keyword.FURIA) or KeywordManager.has_keyword(a, Constants.Keyword.IMBLOQUEABLE)):
		return
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)
	await _reveal_until_to_hand(main, card, pid, func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN)


## katana kogitsunemaru: "si el portador atacó este turno, puedes agrupar una carta o Desterrar hasta cuatro cartas de los Cementerios".
static func _katana_kogitsunemaru(main: Node, card: Node, pid: int) -> void:
	var b := _bearer(card)
	if not b or int(b.get_meta("declared_attacker_turn", -1)) != GameManager.turn_serial:
		return
	var regroup := true
	if not PlayerSideScript.is_bot(pid):
		regroup = await SelectionManager.await_two_choice(main, _name(card), "Agrupar una carta", "Desterrar hasta cuatro cartas de los Cementerios", pid)
	if regroup and main._gold_manager:
		await main._gold_manager.agrupar_cartas(pid, 1)
	else:
		await _interp(card, "Destierra hasta cuatro cartas de los Cementerios", pid)


## leo: "puedes agrupar un Aliado que controles y hacer que una carta en juego pierda su habilidad hasta tu próximo turno".
static func _leo_final(main: Node, card: Node, pid: int) -> void:
	if not await EnterScript._confirm(main, pid, _name(card), "Agrupar un Aliado y que una carta pierda su habilidad"):
		return
	var atk: Array = _allies(main, pid).filter(func(a): return a.get("current_zone") == Constants.Zone.LINEA_ATAQUE)
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: agrupa un Aliado que controles" % _name(card), atk, true)
	if is_instance_valid(ally):
		await _regroup(main, [ally])
	var t: Node = await _pick_in_play(main, pid, "%s: una carta en juego pierde su habilidad hasta tu próximo turno" % _name(card), func(_c): return true)
	_silence_until_next_turn(t, pid)


## odachi: "puedes Destruir esta carta para agrupar un Oro".
static func _odachi_final(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager or not await EnterScript._confirm(main, pid, _name(card), "Destruir esta carta para agrupar un Oro"):
		return
	await ActionModule.destroy([card], card, false, true)
	await main._gold_manager.agrupar_oros(pid, 1)


## rostam: "Destierra tantas cartas de un Cementerio como Fuerza tenga este Aliado".
static func _rostam_final(main: Node, card: Node, pid: int) -> void:
	# Exactamente tantas como su Fuerza (en medida de lo posible), de un Cementerio a elección.
	var n: int = maxi(0, int(ContinuousEffectManager.get_modified_strength(card)))
	var owners: Array = [1 - pid, pid].filter(func(p): return not CardManager.get_cemetery(p).is_empty())
	if n <= 0 or owners.is_empty():
		return
	var owner: int = owners[0]
	if owners.size() > 1 and not PlayerSideScript.is_bot(pid):
		owner = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Cementerio oponente", "Tu Cementerio", pid) else pid
	var take: int = mini(n, CardManager.get_cemetery(owner).size())
	await _exile_from_a_cemetery(main, card, pid, take, take, [owner])


## Shakar Raj: "Destierra hasta tantas cartas de un Cementerio como Aliados hayan modificado su Fuerza este turno más uno"
## (los que tienen Fuerza distinta de la impresa).
static func _shakar_raj(main: Node, card: Node, pid: int) -> void:
	# Cualquier Aliado en juego (de los dos) cuya Fuerza modificó un efecto este turno (meta "strength_mod_turn",
	# ContinuousEffectManager.register_modifier()) o con Fuerza distinta de la impresa por una continua.
	var modified: int = EnterScript._all_allies(main, func(a): return a.get("card_data") != null \
		and (int(a.get_meta("strength_mod_turn", -1)) == GameManager.turn_serial \
			or int(ContinuousEffectManager.get_modified_strength(a)) != int(a.card_data.get("fuerza", 0)))).size()
	await _exile_from_a_cemetery(main, card, pid, modified + 1)


## Snagov: "si no tienes Oros en Reserva, sube un Aliado de tu Cementerio a tu mano".
static func _snagov(main: Node, card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(pid) > 0:
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: sube un Aliado de tu Cementerio a tu mano" % _name(card), 1, 1, func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


## vorpal: "si el portador hizo daño este turno, elige un Aliado para que no pueda ser agrupado ni utilizar su habilidad
## hasta tu próximo turno. Agrupa un Oro y un Aliado que controles".
static func _vorpal(main: Node, card: Node, pid: int) -> void:
	var b := _bearer(card)
	if not b or int(b.get_meta("combat_damage_turn", -1)) != GameManager.turn_serial:
		return
	var t: Node = await EnterScript._pick_from(main, pid, "%s: un Aliado no puede ser agrupado ni utilizar su habilidad hasta tu próximo turno" % _name(card),
		EnterScript._all_allies(main, func(_c): return true), false)
	if is_instance_valid(t):
		if CardQuery.controller_of(t) != pid:
			t.set_meta("no_regroup_turn", GameManager.turn_serial + 1)  # su próxima Agrupación (PhaseFlowController)
		_silence_until_next_turn(t, pid)
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)
	var atk: Array = _allies(main, pid).filter(func(a): return a.get("current_zone") == Constants.Zone.LINEA_ATAQUE)
	var ally: Node = await EnterScript._pick_from(main, pid, "%s: agrupa un Aliado que controles" % _name(card), atk, false)
	if is_instance_valid(ally):
		await _regroup(main, [ally])


## zmeu: "En tu Fase Final, Destierra este Aliado".
static func _zmeu_final(_main: Node, card: Node, _pid: int) -> void:
	if card.get("current_zone") in Constants.ZONES_IN_PLAY:
		await ActionModule.banish([card], card)


## armadura imperial: "si declaraste ataque este turno, puedes Barajar y/o Desterrar hasta dos cartas de los Cementerios".
static func _armadura_final(_main: Node, card: Node, pid: int) -> void:
	if int(BattleManager.attacked_on_turn.get(pid, -1)) == GameManager.turn_serial:
		await _interp(card, "puedes Barajar y/o Desterrar hasta dos cartas de los Cementerios", pid)


## guitarra andaluza: "si no tienes Oros en tu Reserva, puedes Desterrar una carta de un Cementerio y Robar una carta".
static func _guitarra_final(main: Node, card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(pid) > 0 or not await EnterScript._confirm(main, pid, _name(card), "Desterrar una carta de un Cementerio y Robar una carta"):
		return
	await _exile_from_a_cemetery(main, card, pid, 1, 1)
	await ActionModule.draw(pid, 1, _name(card), true)


## Gehena (su Fase Final) y Azi Demoniaco (el Oro): ya resueltos por el intérprete o aquí.
static func _gehena_final(main: Node, card: Node, pid: int) -> void:
	if main._gold_manager:
		await main._gold_manager.agrupar_oros(pid, 1)
	await ActionModule.draw(pid, 1, _name(card), true)


static func _azi_gold_final(main: Node, card: Node, pid: int) -> void:
	var picks: Array = await EnterScript._pick_cemetery(pid, [1 - pid, pid], "%s: Baraja o Destierra una carta de un Cementerio" % _name(card), 1, 1)
	for pk in picks:
		var owner: int = int(pk.owner)
		var shuffle := false
		if not PlayerSideScript.is_bot(pid):
			shuffle = await SelectionManager.await_two_choice(main, _name(card), "Barajarla en su Castillo", "Desterrarla", pid)
		if CardManager.take_from_cemetery(owner, pk.data):
			if shuffle:
				pk.data["esta_oculta"] = true
				CardManager.get_deck(owner).append(pk.data)
				CardManager.shuffle_deck(owner)
			else:
				CardManager.append_to_exile(owner, pk.data)


## Los Señalados: "En la Fase Final, si hizo daño al Castillo oponente, gana uno de Fuerza permanentemente" (meta
## "castle_damage_turn", GoldManager). turn_end_extras() lo llama en la Fase Final de su controlador.
static func _senalados(_main: Node, card: Node, _pid: int) -> void:
	if GameManager.current_phase == Constants.Phase.FINAL and int(card.get_meta("castle_damage_turn", -1)) == GameManager.turn_serial:
		_buff(card, card, 1, true)


# --- Activadas -------------------------------------------------------------------
## Azi Demoniaco: "convierte este Aliado hasta tu próximo turno en un Oro con la habilidad "..." y ponlo en tu Oro Pagado".
static func _azi_demoniaco(main: Node, card: Node, _pid: int) -> void:
	if main._gold_manager and card.get("current_zone") in Constants.ZONES_IN_PLAY:
		await main._gold_manager.convert_ally_to_gold_until_next_turn(card, _quoted_any(card))


static func _quoted_any(card: Node) -> String:
	var m := RegEx.create_from_string("[\"“”]([^\"“”]+)[\"“”]").search(str(card.card_data.get("habilidad", "")))
	return m.get_string(1) if m else ""


## chamuel: "tu oponente Bota tantas cartas como coste tenga una carta en juego".
static func _chamuel(main: Node, card: Node, pid: int) -> void:
	var t: Node = await _pick_in_play(main, pid, "%s: tu oponente Bota tantas cartas como coste tenga una carta en juego" % _name(card),
		func(c): return c.get("card_type") != Constants.CardType.ORO, false)
	if is_instance_valid(t) and EnterScript._cost(t) > 0:
		await ActionModule.mill(1 - pid, EnterScript._cost(t), false, _name(card))


## cueva de montesinos: "Puedes Destruirlo para que tu oponente Bote cuatro cartas o Descarte una carta" (eliges tú).
static func _cueva_montesinos(main: Node, card: Node, pid: int) -> void:
	if card.get("current_zone") in Constants.ZONES_IN_PLAY:
		await ActionModule.destroy([card], card, false, true)
	var mill := true
	if not PlayerSideScript.is_bot(pid):
		mill = await SelectionManager.await_two_choice(main, _name(card), "Tu oponente Bota cuatro cartas", "Tu oponente Descarta una carta", pid)
	if mill:
		await ActionModule.mill(1 - pid, 4, false, _name(card))
	else:
		await EnterScript._discard_own(main, card, 1 - pid, 1)


## ebikame: "ganar el control de una carta de coste 2 o menos. Si es un Aliado gana Furia. En tu Fase Final, Baraja esa carta".
static func _ebikame(main: Node, card: Node, pid: int) -> void:
	var t: Node = await _pick_in_play(main, pid, "%s: gana el control de una carta de coste 2 o menos" % _name(card),
		func(c): return CardQuery.controller_of(c) != pid and c.get("card_type") != Constants.CardType.ORO and ContinuousEffectManager.cost_at_most(c, 2))
	if not is_instance_valid(t):
		return
	ContinuousEffectManager.gain_control_of_card(t, pid)
	if CardQuery.controller_of(t) != pid:
		return
	if t.get("card_type") == Constants.CardType.ALIADO:
		KeywordManager.grant_keyword(t, Constants.Keyword.FURIA, card, "permanent")
	EffectController.schedule_next_final_phase_effect(GameManager.active_player_id, func() -> void:
		if is_instance_valid(t) and t.get("current_zone") in Constants.ZONES_IN_PLAY:
			var owner: int = int(t.owner_id) if t.get("owner_id") != null else pid
			await ActionModule.return_to_deck(t, owner, false, card)
			ActionModule.shuffle_deck(owner))


## Gehena: "mirar la mano de tu oponente y nombrar dos cartas que no sean Talismán. Busca una de ellas en el Castillo
## oponente y Destiérrala y busca la otra en tu Castillo y ponla en tu mano".
static func _gehena(main: Node, card: Node, pid: int) -> void:
	var opp_hand: Array = PlayerSideScript.hand_cards(main, 1 - pid).filter(func(c): return is_instance_valid(c)).map(func(c): return c.card_data)
	if not EffectController.fision_hides_zones_of(1 - pid, pid, Constants.Zone.MANO) and not opp_hand.is_empty() and not PlayerSideScript.is_bot(pid):
		SelectionManager.open_reveal(opp_hand, "%s: la mano de tu oponente" % _name(card), pid)
		await SelectionManager.selection_completed
	var names: Array = []
	for i in 2:
		var named := ""
		if PlayerSideScript.is_bot(pid):
			var pool: Array = CardManager.get_deck(1 - pid) if i == 0 else CardManager.get_deck(pid)
			for d in pool:
				if int(d.get("tipo", -1)) != Constants.CardType.TALISMAN:
					named = str(d.get("nombre", ""))
					break
		else:
			var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait("%s: nombra una carta que no sea Talismán (%d de 2)" % [_name(card), i + 1], pid)
			if int(picked.get("tipo", -1)) == Constants.CardType.TALISMAN:
				main._update_debug("%s: no puedes nombrar Talismanes" % _name(card))
				return
			named = str(picked.get("nombre", ""))
		if named.is_empty():
			return
		names.append(named)
	var to_exile: int = 0
	if not PlayerSideScript.is_bot(pid):
		to_exile = await SelectionManager.await_choice(main, "%s: ¿cuál buscas en el Castillo oponente para Desterrarla?" % _name(card), names, pid)
	to_exile = clampi(to_exile, 0, 1)
	var exile_name: String = names[to_exile]
	var hand_name: String = names[1 - to_exile]
	var found: Array = await AttackScript._pick_from_castle(1 - pid, pid, "%s: busca %s en el Castillo oponente" % [_name(card), exile_name],
		func(d): return str(d.get("nombre", "")) == exile_name, 0, 1, false)
	for d in found:
		d["esta_oculta"] = false
		CardManager.append_to_exile(1 - pid, d)
	var mine: Array = await AttackScript._pick_from_castle(pid, pid, "%s: busca %s en tu Castillo" % [_name(card), hand_name],
		func(d): return str(d.get("nombre", "")) == hand_name, 0, 1, false)
	for d in mine:
		PlayerSideScript.put_in_hand(main, pid, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


## guitarra andaluza: "buscar una carta que no sea Talismán en un Castillo y ponla en el tope o fondo del Castillo de su dueño".
static func _guitarra_andaluza(main: Node, card: Node, pid: int) -> void:
	var owner: int = pid
	if not PlayerSideScript.is_bot(pid):
		owner = pid if await SelectionManager.await_two_choice(main, _name(card), "Buscar en tu Castillo", "Buscar en el Castillo oponente", pid) else 1 - pid
	var picked: Array = await AttackScript._pick_from_castle(owner, pid, "%s: busca una carta que no sea Talismán" % _name(card),
		func(d): return int(d.get("tipo", -1)) != Constants.CardType.TALISMAN, 0, 1, false)
	if picked.is_empty():
		return
	var top := true
	if not PlayerSideScript.is_bot(pid):
		top = await SelectionManager.await_two_choice(main, _name(card), "Ponerla en el tope", "Ponerla en el fondo", pid)
	var d: Dictionary = picked[0]
	d["esta_oculta"] = true
	var deck: Array = CardManager.get_deck(owner)
	if top:
		deck.push_front(d)
	else:
		deck.append(d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


## Gurzil: "Si atacaste en tu anterior turno puedes pagar dos Oros para jugarlo sin pagar su coste".
static func _gurzil(main: Node, card: Node, pid: int) -> void:
	if not BattleManager.attacked_in_previous_own_turn(pid):
		main._update_debug("%s: no atacaste en tu turno anterior" % _name(card))
		return
	if not await _pay_gold(main, pid, 2):
		return
	await _play_self(main, card, pid, 0)


## hrunting: "mostrar cuatro cartas del tope de tu Castillo. El portador gana tanta Fuerza como sumen sus costes por el
## turno, devuélvelas en cualquier orden y Roba una carta".
static func _hrunting(main: Node, card: Node, pid: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	if deck.is_empty():
		return
	var shown: Array = deck.slice(0, 4)
	var total := 0
	for d in shown:
		total += int(d.get("coste", 0)) if int(d.get("tipo", -1)) != Constants.CardType.ORO else 0
	RevealedCardsScript.record(pid, shown, _name(card))
	main._update_debug("%s muestra %s (suman %d)" % [_name(card), ", ".join(shown.map(func(d): return str(d.get("nombre", "?")))), total])
	var b := _bearer(card)
	if b and total > 0:
		_buff(b, card, total)
	await CastleLookScript.look(pid, pid, shown.size(), true, CastleLookScript.rest_box(true), "%s: devuélvelas en cualquier orden" % _name(card))
	await ActionModule.draw(pid, 1, _name(card), true)


## Lanza de Exorcista: "Desterrar cartas oponentes cuyos costes sumen hasta 3" (Oros no: no tienen coste).
static func _lanza_exorcista(main: Node, card: Node, pid: int) -> void:
	var budget := 3
	var chosen: Array = []
	while budget > 0:
		var options: Array = EnterScript._in_play(main, 1 - pid,
			func(c): return c.get("card_type") != Constants.CardType.ORO and not (c in chosen) and EnterScript._cost(c) <= budget)
		var t: Node = await EnterScript._pick_from(main, pid, "%s: Destierra cartas oponentes cuyos costes sumen hasta 3 (quedan %d)" % [_name(card), budget], options, true)
		if not is_instance_valid(t):
			break
		chosen.append(t)
		budget -= EnterScript._cost(t)
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card)


# --- Daño ------------------------------------------------------------------------
## escorpio: "un oponente Destierra la primera carta de su Castillo por cada carta en su mano".
static func _escorpio_damage(main: Node, card: Node, pid: int) -> void:
	var n: int = EnterScript._hand(main, 1 - pid).size()
	if n > 0:
		await ActionModule.mill(1 - pid, n, true, _name(card))


## malafar sp: "puedes Robar una carta y un jugador debe Descartar una carta de su mano".
static func _malafar(main: Node, card: Node, pid: int) -> void:
	if not await EnterScript._confirm(main, pid, _name(card), "Robar una carta y que un jugador Descarte una"):
		return
	await ActionModule.draw(pid, 1, _name(card), true)
	var victim: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		victim = 1 - pid if await SelectionManager.await_two_choice(main, _name(card), "Descarta tu oponente", "Descartas tú", pid) else pid
	await EnterScript._discard_own(main, card, victim, 1)


## nagaraja: "Si porta Armas, cuando haga daño por primera vez en el juego, el primer Aliado o Tótem que juegue tu oponente
## en su próximo turno entra en juego bajo tu control" (GoldManager lo aplica al entrar en juego).
static func _nagaraja(main: Node, card: Node, pid: int) -> void:
	if card.get_meta("nagaraja_used", false) or not (card.get("equipped_weapons") is Array and card.equipped_weapons.any(func(w): return is_instance_valid(w))):
		return
	card.set_meta("nagaraja_used", true)
	var opp_next: int = GameManager.turn_serial + (1 if GameManager.active_player_id == pid else 2)
	RuleState.set_turn_data("nagaraja_steal:%d" % (1 - pid), {})
	RuleState.set_pending("nagaraja_steal", 1 - pid, {"thief": pid, "turn": opp_next})
	main._update_debug("%s: el primer Aliado o Tótem que juegue tu oponente en su próximo turno entra bajo tu control" % _name(card))


static func nagaraja_on_entered(pid: int, node: Node) -> void:
	if not RuleState.has_pending("nagaraja_steal", pid) or not is_instance_valid(node) \
			or not (node.get("card_type") in [Constants.CardType.ALIADO, Constants.CardType.TOTEM]):
		return
	var info = RuleState.take_pending("nagaraja_steal", pid)
	if not (info is Dictionary) or int(info.get("turn", -1)) != GameManager.turn_serial:
		if info is Dictionary and int(info.get("turn", -1)) > GameManager.turn_serial:
			RuleState.set_pending("nagaraja_steal", pid, info)  # todavía no es su próximo turno
		return
	ContinuousEffectManager.gain_control_of_card(node, int(info.thief))


## vinci y yang: "tu oponente elige entre Descartar dos cartas o una carta al azar".
static func _vinci_yang(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var hand: Array = EnterScript._hand(main, opp)
	if hand.is_empty():
		return
	var two := false
	if not PlayerSideScript.is_bot(opp):
		two = await SelectionManager.await_two_choice(main, _name(card), "Descartar dos cartas", "Descartar una carta al azar", opp)
	if two:
		await EnterScript._discard_own(main, card, opp, 2)
	else:
		await ActionModule.discard(opp, [hand[randi() % hand.size()]], _name(card), true)


# --- Vigilia, Fase Final oponente, comienzo de turno, Destruido, Agrupación ----------
## salmon del saber: "Al comienzo de tu Vigilia, Roba hasta tener dos cartas en tu mano".
static func _salmon(main: Node, card: Node, pid: int) -> void:
	var n: int = 2 - EnterScript._hand(main, pid).size()
	if n > 0:
		await ActionModule.draw(pid, n, _name(card), true)


## shakuhachi: "puedes jugar un Talismán de tu Cementerio pagando su coste y Destiérralo".
static func _shakuhachi(main: Node, card: Node, pid: int) -> void:
	if not main._gold_manager:
		return
	var ok := func(d): return int(d.get("tipo", -1)) == Constants.CardType.TALISMAN and main._gold_manager.puede_pagar(int(d.get("coste", 0)), -1, "", -1, pid)
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: juega un Talismán de tu Cementerio pagando su coste (luego se Destierra)" % _name(card), 0, 1, ok)
	for pk in picks:
		if not CardManager.take_from_cemetery(pid, pk.data):
			continue
		var price: int = int(pk.data.get("coste", 0))
		if price > 0 and not await PlayerSideScript.pay(main, pid, price):
			CardManager.add_to_cemetery(pid, pk.data)
			continue
		pk.data["esta_oculta"] = false
		await main._gold_manager.play_card_for_free(pk.data, pid, true)


## armadura imperial: "si tu oponente tiene dos o más Oros en Reserva, puedes generar un Oro para jugar Aliados".
static func _armadura_vigilia(main: Node, _card: Node, pid: int) -> void:
	if GameState.get_oro_reserva(1 - pid) >= 2 and main._gold_manager:
		main._gold_manager.generar_oro_virtual_restringido(1, func(t: int, _r: String, _c: int) -> bool: return t == Constants.CardType.ALIADO,
			"Aliados", pid)


## Amuleto de Serpiente: la misma habilidad que al entrar en juego.
static func _amuleto_serpiente_vigilia(main: Node, card: Node, pid: int) -> void:
	await EnterScript._amuleto_serpiente(main, card, pid)


## incienso sagrado: "En la Fase Final oponente, si no controlas Aliados, puedes subir un Aliado de tu Cementerio a tu mano".
static func _incienso(main: Node, card: Node, pid: int) -> void:
	if not _allies(main, pid).is_empty():
		return
	var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: sube un Aliado de tu Cementerio a tu mano" % _name(card), 0, 1, func(d): return _is_ally(d))
	for pk in picks:
		if CardManager.take_from_cemetery(pid, pk.data):
			PlayerSideScript.put_in_hand(main, pid, pk.data)


## Armería del Guerrero: "Al comienzo del turno oponente, Baraja y/o Destierra hasta dos cartas de los Cementerios".
static func _armeria(_main: Node, card: Node, pid: int) -> void:
	await _interp(card, "Baraja y/o Destierra hasta dos cartas de los Cementerios", pid)


## trapezoedro: "Si al comienzo del turno no tenías Oros en Reserva, cuando tu oponente ponga en juego su tercera carta en
## el turno, agrupa un Oro" (GoldManager: on_turn_start_trapezoedro / on_card_put_trapezoedro).
static func trapezoedro_turn_start() -> void:
	for p in [0, 1]:
		var armed: bool = GameState.get_oro_reserva(p) == 0 and not CardQuery.cards_in_play_with(p, "cuando tu oponente ponga en juego su tercera carta en el turno, agrupa un oro").is_empty()
		RuleState.set_turn_data("trapezoedro:%d" % p, {"armed": armed, "done": false} if armed else {})


static func trapezoedro_on_put(main: Node, putter: int) -> void:
	var p: int = 1 - putter
	var td: Dictionary = RuleState.turn_data("trapezoedro:%d" % p)
	if td.is_empty() or td.get("done", false):
		return
	RuleState.add("trapezoedro_put", putter)
	if RuleState.count("trapezoedro_put", putter) == 3 and main._gold_manager:
		td["done"] = true
		RuleState.set_turn_data("trapezoedro:%d" % p, td)
		await main._gold_manager.agrupar_oros(p, 1)
		main._update_debug("trapezoedro: tu oponente puso en juego su tercera carta, agrupas un Oro")


## caicai vilu: "Cuando sea Destruido, súbelo a tu mano".
static func _caicai_destroyed(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var d: Dictionary = _find_data(CardManager.get_cemetery(owner), card.card_data)
	if not d.is_empty() and CardManager.take_from_cemetery(owner, d):
		PlayerSideScript.put_in_hand(main, owner, d)


## tesoro del santiaguillo: "Cuando sea Destruido, puedes convertirlo en un Aliado de Fuerza 1 con la habilidad "...""
## (vuelve del Cementerio a juego como ese Aliado).
static func _santiaguillo_destroyed(main: Node, card: Node, pid: int) -> void:
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	var d: Dictionary = _find_data(CardManager.get_cemetery(owner), card.card_data)
	if d.is_empty() or not main._gold_manager or not await EnterScript._confirm(main, pid, _name(card), "Convertirlo en un Aliado de Fuerza 1"):
		return
	var ability := _quoted_any(card)
	if not CardManager.take_from_cemetery(owner, d):
		return
	var ally_data: Dictionary = d.duplicate()
	ally_data["tipo"] = Constants.CardType.ALIADO
	ally_data["fuerza"] = 1
	ally_data["habilidad"] = ability
	var node: Node = await _put_into_play(main, pid, ally_data, owner)
	if is_instance_valid(node):
		node.is_converted = true


## Cartas en el Cementerio con disparo al comienzo de tu Vigilia / Agrupación (data-based).
static func _discard_or_exile_to_raise(main: Node, pid: int, data: Dictionary, cost: String) -> void:
	var name := str(data.get("nombre", "Carta"))
	if cost == "discard":
		var hand: Array = EnterScript._hand(main, pid)
		if hand.is_empty() or not await EnterScript._confirm(main, pid, name, "Descartar una carta para subirla de tu Cementerio a tu mano"):
			return
		var pick: Node = await EnterScript._pick_from(main, pid, "%s: Descarta una carta" % name, hand, true)
		if not is_instance_valid(pick):
			return
		await ActionModule.discard(pid, [pick], name, true)
	else:
		var others: Array = CardManager.get_cemetery(pid).filter(func(x): return not is_same(x, data))
		if others.is_empty() or not await EnterScript._confirm(main, pid, name, "Desterrar otra carta de tu Cementerio para ponerla en tu mano"):
			return
		var picks: Array = await EnterScript._pick_cemetery(pid, [pid], "%s: Destierra otra carta de tu Cementerio" % name, 1, 1, func(x): return not is_same(x, data))
		if picks.is_empty():
			return
		_exile_cemetery_picks(picks)
	if CardManager.take_from_cemetery(pid, data):
		PlayerSideScript.put_in_hand(main, pid, data)


const COMPENDIUM_VIGILIA := "si este oro esta en tu cementerio, puedes desterrar otra carta de tu cementerio para ponerlo en tu mano"
const GUMYOCHO_VIGILIA := "si controlas tres o mas aliados de coste 1 o mas, puedes jugar este aliado de tu cementerio sin pagar su coste"
const VEINTE_MIL_VIGILIA := "puedes descartar una carta para subir este u otro oro de tu cementerio a tu mano"
const ORIGENES_AGRUPACION := "en tu agrupacion, puedes descartar una carta para subirlo de tu cementerio a tu mano"


static func vigilia_cemetery_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_cemetery(pid).duplicate():
		var t := CemeteryTriggersScript.normalize(str(d.get("habilidad", "")))
		if COMPENDIUM_VIGILIA in t:
			await _discard_or_exile_to_raise(main, pid, d, "exile")
		elif GUMYOCHO_VIGILIA in t and _allies(main, pid).filter(func(a): return EnterScript._cost(a) >= 1).size() >= 3 \
				and await EnterScript._confirm(main, pid, str(d.get("nombre", "")), "Jugarlo de tu Cementerio sin pagar su coste"):
			if CardManager.take_from_cemetery(pid, d):
				d["esta_oculta"] = false
				await main._gold_manager.play_card_for_free(d, pid)
	# veinte mil leguas de viaje submarino: "Al comienzo de la Vigilia" (de cualquiera), en juego o en tu Cementerio.
	for p in [0, 1]:
		var sources: Array = CardManager.get_cemetery(p).filter(func(x): return VEINTE_MIL_VIGILIA in CemeteryTriggersScript.normalize(str(x.get("habilidad", ""))))
		sources.append_array(CardQuery.cards_in_play_with(p, VEINTE_MIL_VIGILIA))
		if sources.is_empty():
			continue
		var golds: Array = CardManager.get_cemetery(p).filter(func(x): return int(x.get("tipo", -1)) == Constants.CardType.ORO)
		if golds.is_empty() or EnterScript._hand(main, p).is_empty():
			continue
		var hand: Array = EnterScript._hand(main, p)
		if not await EnterScript._confirm(main, p, "veinte mil leguas de viaje submarino", "Descartar una carta para subir un Oro de tu Cementerio a tu mano"):
			continue
		var pick: Node = await EnterScript._pick_from(main, p, "Descarta una carta", hand, true)
		if not is_instance_valid(pick):
			continue
		await ActionModule.discard(p, [pick], "veinte mil leguas de viaje submarino", true)
		var gp: Array = await EnterScript._pick_cemetery(p, [p], "Sube un Oro de tu Cementerio a tu mano", 1, 1, func(x): return int(x.get("tipo", -1)) == Constants.CardType.ORO)
		for pk in gp:
			if CardManager.take_from_cemetery(p, pk.data):
				PlayerSideScript.put_in_hand(main, p, pk.data)


static func agrupacion_cemetery_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_cemetery(pid).duplicate():
		if ORIGENES_AGRUPACION in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))):
			await _discard_or_exile_to_raise(main, pid, d, "discard")


## Fase Final: miroku (en tu Destierro) y Los Señalados ("En la Fase Final", sin "tu").
static func turn_end_extras(main: Node, pid: int) -> void:
	for d in CardManager.get_exile(pid).duplicate():
		if "en tu fase final, si esta en tu destierro, puedes ver las primeras tres cartas de tu castillo y ordenarlas" in CemeteryTriggersScript.normalize(str(d.get("habilidad", ""))) \
				and not CardManager.get_deck(pid).is_empty() and await EnterScript._confirm(main, pid, str(d.get("nombre", "")), "Ver las primeras tres cartas de tu Castillo y ordenarlas"):
			await CastleLookScript.look(pid, pid, 3, true, CastleLookScript.rest_box(true), "%s: ordena las primeras tres cartas de tu Castillo" % str(d.get("nombre", "")))
	for a in CardQuery.cards_in_play_with(pid, "en la fase final, si hizo daño al castillo oponente, gana uno de fuerza permanentemente"):
		_senalados(main, a, pid)
