extends RefCounted
## ActivatedPatternsBase — base de ActivatedPatterns.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: ActivatedPatternsBase <- ActivatedPatternsControl <- ActivatedPatternsZonas <- ActivatedPatternsManoCementerio <- ActivatedPatterns. Lo de afuera usa solo ActivatedPatterns.gd (hereda todo).

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

## tundra viva / isla de gigantes: cartas del Cementerio ganan una habilidad (permanente) que se usa desde ahí.
const TUNDRA_GRANT := "Destierra dos cartas de tu Cementerio para subirlo a tu mano."

const ISLA_GRANT := "Destierra tres cartas de tu Cementerio para jugarlo pagando su coste y Destiérralo."

## Caos: "Una vez en tu turno, un Oro gana la habilidad "Cuando lo pagues, conviértelo en un Aliado de Fuerza 3.
## Cuando haga daño, convierte este Aliado en un Oro y ponlo a tu Oro Pagado."" Al pagarlo:
## GoldManager._mover_oro_a_pagado() → caos_to_ally(); al hacer daño (BattleManager) → caos_back_to_gold().
const CAOS_GRANT := "Cuando lo pagues, conviértelo en un Aliado de Fuerza 3. Cuando haga daño, convierte este Aliado en un Oro y ponlo a tu Oro Pagado."

## Disparadores al comienzo de la Vigilia que no están en el campo del jugador activo
## (TriggerSystem.resolve_vigilia_triggers): pulsera de energia (desde tu Cementerio) y París (en juego del
## rival: "Al comienzo de la Vigilia oponente").
const PULSERA_VIGILIA := "al comienzo de tu vigilia, si esta en tu cementerio, puedes desterrar dos cartas de tu cementerio para subirlo a tu mano"

const PARIS_VIGILIA := "al comienzo de la vigilia oponente, puedes jugar un arma o totem de tu mano pagando su coste"

const COMPENDIUM_VIGILIA := "si este oro esta en tu cementerio, puedes desterrar otra carta de tu cementerio para ponerlo en tu mano"

const GUMYOCHO_VIGILIA := "si controlas tres o mas aliados de coste 1 o mas, puedes jugar este aliado de tu cementerio sin pagar su coste"

const VEINTE_MIL_VIGILIA := "puedes descartar una carta para subir este u otro oro de tu cementerio a tu mano"

const ORIGENES_AGRUPACION := "en tu agrupacion, puedes descartar una carta para subirlo de tu cementerio a tu mano"
