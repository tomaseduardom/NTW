extends RefCounted
class_name EffectCompiler
## EffectCompiler — compila el texto de UNA habilidad (disparada, activada o Talismán) a un plan de
## pasos atómicos (arquitectura.md §54).
## Por qué: en vez de una función try_execute_*_pattern() por carta (encadenadas en
## TriggerResolution, gana la primera que calza sobre el texto completo), el efecto se arma con
## piezas reutilizables; una carta nueva suele ser una combinación de piezas existentes.
## Regla de oro: el plan solo es válido (ok = true) si se entendió TODO el texto. Si queda un resto
## sin entender, ok = false y el llamador sigue con la cadena de patrones: nunca se ejecuta un
## efecto a medias.
## Clase pura: sin autoloads ni nodos (tipos y zonas van como texto; EffectInterpreter los traduce a
## Constants). Se prueba headless con tools/test_effect_compiler.gd y se audita el catálogo con
## tools/audit_cards.gd.
##
## Plan: {ok, optional, activated, steps: [paso], unparsed: String}
## activated = el texto traía momento/frecuencia de habilidad ACTIVADA ("En tu Vigilia, una vez por
## turno, ..."): el clic en su botón ya fue la confirmación del "puedes".
## Pasos (todos llevan "then": true si van después de "Luego,": solo corren si el anterior se
## resolvió por completo, DAR):
## {op: "draw", amount} — Roba N cartas
## {op: "draw_to_match"} — Roba cartas hasta tener tantas en la mano como tu oponente (virgo)
## {op: "mill", who: "self"|"opponent"|"both", amount} — Bota N cartas
## {op: "discard", who, amount, random} — Descarta N cartas
## {op: "shuffle_from_hand", amount, up_to} — Baraja N cartas de tu mano
## {op: "search", zones, card_type, amount, up_to} — Busca ... y ponla en tu mano
## {op: "target", verb, count, up_to, target} — Destruye/Destierra/Baraja/Sube N cartas en juego
## {op: "mass", verb, target} — Destruye todos los Aliados ...
## {op: "choice", options: [[pasos], ...]} — "A, o B"
## {op: "shuffle_from_cemetery", amount, up_to} — Baraja N cartas de tu Cementerio en tu Castillo
## {op: "self", verb} — Destrúyelo / Destiérralo (la propia carta)
## {op: "if", cond, steps} — "si no fue declarado atacante este turno, ..."
## {op: "cemetery_cleanup", mode, amount} — Baraja y/o Destierra hasta N de los Cementerios (mode:
## "both" | "banish" | "shuffle")
## {op: "gold", amount} — Genera N Oros (por el turno, sin restricción)
## {op: "buff", count, up_to, amount, keywords, to_exile, permanent, turn_only, target} — Un Aliado
## gana Furia, N de Fuerza y hace daño al Destierro
## {op: "reveal_until", specs: [{count, types, race, types_not, name_not, cost_val, cost_cmp, str_val,
## str_cmp, ability, keyword, distinct}], dest, dist: [{count, dest}]} — Muestra del tope hasta mostrar
## ... y ponlos en tu mano / juégalos / ponlos en juego / en tu Oro pagado, o reparte ("pon uno en tu
## mano, tres en tu Cementerio y baraja el resto")
## {op: "reveal_top", count, pick, pick_types, up_to, dest, reduce, rest} — Muestra N cartas del tope,
## pon (hasta) K de ahí en tu mano (o juega una por N Oros menos) y el resto se baraja / va a otra zona
## {op: "if", cond: {kind: "controls", count, type, race, other, min_strength, attack_line}, steps}
## — "si controlas (otro) (N o más) <tipo/raza>, ..."
## {op: "pay", amount} — costo "pagar N Oros para ..." (se paga antes)
## {op: "hand_peek", verb, count, types, types_not, cost_val, cost_cmp} — Mira la mano de tu
## oponente y Destierra/Descarta/Baraja ...
## {op: "annul", text} — Anula / Cancela la habilidad de ... en la Pila (StackAnnul.try_from_text)
## {op: "talisman_fizzle"} — el próximo Talismán que juegue tu oponente este turno se resuelve sin
## efecto (kotoku-in)
## "buff" admite keyword_choice (elige una de varias) y duration "until_next_turn" ("hasta tu
## próximo turno"); el ítem "no puede ser barajado" es no_shuffle.
## "A o B" sin coma: si ", o " no parte la oración, se prueba cada " o " y vale si los dos lados
## compilan enteros.
## "search" admite además card_types (varios), types_not ("que no sea X ni Y") y cost_val/cost_cmp.
## "Elige un efecto: - A. - B." se compila como "choice" con N opciones. Las oraciones de regla
## (RULE_SKIP_RX) se saltean: las aplica otro sistema.
## Extras de "target"/"mass": silence_first (pierde su habilidad y es Destruido),
## replace_if_keyword: {keyword, verb} ("Si tiene Exhumar, en vez de eso, Destiérralo"). Extra de
## "mill": per (Bota una carta por cada Aliado en tu Línea de Defensa / Tótem en juego / ...).
## verb: "destroy" | "banish" | "shuffle" | "bounce"
## target: {card_types: ["aliado", ...] (vacío = cualquier tipo en juego), controller:
## "any"|"opponent", exclude_gold, stat: ""|"fuerza"|"coste", cmp: "<="|">=", value}
## card_type / card_types: "aliado", "arma", "totem", "talisman", "oro" ("" = cualquier carta).
## zones: "castillo", "cementerio".

const NUMBER_WORDS := {
	"un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
	"seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
}
const NUM := "(?:\\d+|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)"

## Prefijos de disparador que se quitan antes de compilar — el disparador
## en sí ya lo decidió quien llama (Card.TRIGGER_KEYWORDS/TriggerResolution).
## Los más largos primero.
const TRIGGER_PREFIXES := [
	# Disparadores combinados: el compilador solo ve el efecto; cuándo dispara lo decide quien llama.
	"cuando entra en juego o ataques con un solo aliado", "cuando entra en juego o ataques con tres o mas aliados",
	"cuando entra en juego o el portador ataque", "cuando entra en juego o el portador haga dano de combate",
	"cuando una carta sea descartada", "cuando sea descartado por un aliado",
	"cuando entra en juego o haga dano", "cuando entra en juego o bloquee", "cuando entra en juego o salga del juego",
	"cuando entra en juego o al comienzo de tu vigilia", "cuando entra en juego y al comienzo de tu vigilia",
	"cuando entra en juego y al comienzo de la vigilia oponente", "cuando entra en juego y al comienzo de cada vigilia",
	"cuando entra en juego y al comienzo de tu turno",
	"cuando entra en juego o ataca", "cuando entra en juego o ataque", "cuando entra o sale del juego",
	"cuando entra o salga del juego", "cuando entra en juego", "cuando entre en juego", "al entrar en juego",
	# Las condiciones de cantidad de atacantes y de primera vez las revisa TriggerResolution
	# (_attack_condition_met).
	"cuando ataques con un solo aliado", "cuando ataque solo", "cuando ataques", "cuando ataque, entre o salga del juego",
	"si porta armas, cuando ataque por primera vez en el juego", "cuando ataque por primera vez en el juego",
	"cuando ataca", "cuando ataque", "al atacar", "cuando bloquea", "cuando bloquee", "cuando lo juegues",
	# "Cuando juegues un Arma, tu oponente descarta una carta" (camael, fonda, keshalyi): el tipo lo filtra
	# quien dispara.
	"cuando juegues un totem de coste 2 o mas", "cuando juegues un arma", "cuando juegues un talisman",
	"cuando juegues un aliado", "cuando juegues un totem",
	# Hospital San José; moraleda (la otra mitad del disparador la decide quien llama).
	"en la fase final oponente o cuando salga del juego",
	"cuando salga del juego o sea puesto en tu destierro por la habilidad de un aliado sacerdote",
	"cuando salga del juego", "cuando sale del juego", "al salir del juego",
	"cuando sea destruido", "al ser destruido",
	"cuando hace dano al castillo oponente", "cuando haga dano al castillo oponente",
	"cuando haga dano de combate", "cuando haga dano",
	"en tu fase final", "al comienzo de tu vigilia", "al comienzo de la vigilia",
	"al comienzo del ataque",
	"al comienzo del turno oponente", "al comienzo del turno de tu oponente", "al comienzo de tu turno",
	"al comienzo del turno",
]

## Oraciones que empiezan como un disparador pero son un efecto diferido de la misma resolución.
const DELAYED_SENTENCES := ["en tu fase final, tus aliados pierden su habilidad hasta tu proximo turno"]

## Momento/frecuencia de las habilidades ACTIVADAS — lo controla
## ActionPipeline (once_per_turn, ventana), no es parte del efecto.
const TIMING_PREFIXES := [
	"en tu vigilia", "en guerra de talismanes", "una vez por turno", "una vez al turno", "una vez en tu turno",
	"hasta dos veces por turno", "hasta tres veces por turno",
	# Habilidades desde otra zona: "Si está en tu Reserva, puedes Barajarlo para..." (huitzilin, carro de
	# sol, miroku, dr frankenstein). Dónde puede usarse lo decide quien ofrece el botón.
	"si esta en tu reserva", "si esta en tu cementerio", "si esta en tu destierro",
]

## Oraciones al INICIO del texto que no son parte del efecto: keywords y
## "Cuando lo juegues, Destiérralo" de los Talismanes (eso lo aplica
## GoldManager._play_talisman() al mandar el Talismán al Destierro).
const LEADING_SKIP_RX := "^(?:(?:furia|imbloqueable|indestructible|indesterrable|unica|exhumar|errante|retador" \
	+ "|oro inicial)[ ,y]*)+$|^cuando lo juegues, (?:destierralo|destierrala)$"

## Oraciones de REGLA (no son efecto), en cualquier parte del bloque: se saltean porque las aplica
## otro sistema — Anular (StackAnnul.protected_from_annul), autodestierro del Talismán
## (GoldManager._play_talisman), cuándo se puede jugar (PhaseStartWindow), copias (Errante/Única),
## etc.
const RULE_SKIP_RX := [
	"^no (?:puede|se puede) ser anulad[oa](?: ni (?:su habilidad )?cancelad[oa])?$",
	"^no se puede anular ni cancelar su habilidad$",
	"^las habilidades de (?:este|esta) (?:oro|carta|aliado|totem|arma) no pueden ser canceladas$",
	"^esta habilidad no puede ser cancelada(?: ni prevenida)?$",
	"^cuando (?:lo|la) juegues, (?:destierralo|destierrala)$",
	"^cuando juegues (?:este|esta) (?:talisman|carta|aliado|totem|arma), (?:destierralo|destierrala)$",
	"^(?:puedes jugarlo|puedes jugarla|se puede jugar) al comienzo de cualquier fase(?: o paso del juego)?" \
		+ "(?: y cuando (?:lo|la) juegues, (?:destierralo|destierrala))?$",
	"^(?:puedes jugarlo|puedes jugarla) en la fase final(?: oponente)?$",
	"^solo puedes controlar una copia de esta carta$",
	# "Si es Anulado, ..." es otra habilidad (vale cuando la Anulan), no
	# parte del efecto al resolverse.
	"^si es anulad[oa],? .+$",
	"^puedes tener mas de tres copias de esta carta en tu castillo$",
	# Habilidades de la carta desde otra zona (vision heroica: "Puedes pagar un Oro para subir esta
	# carta de tu Cementerio a tu mano y Robar una carta"): no son parte del efecto al resolverse.
	"^(?:puedes )?pagar (?:un|una|dos|tres) oros? para subir (?:esta carta|este talisman) de tu cementerio a tu mano.*$",
	# Coste y cuándo se puede jugar (los Talismanes): lo decide el pago/PhaseStartWindow, no el efecto.
	"^(?:este talisman|esta carta) no puede ser anulad[oa]$",
	"^(?:en batalla mitologica )?reduce su coste en (?:un|dos) oros?.*$",
	"^(?:este talisman |esta carta )?(?:te )?cuesta (?:un|dos) oros? (?:menos|adicional).*$",
	"^solo (?:puedes jugar|puede ser jugad[oa]|se puede jugar|puedes jugarlo|puedes jugarla).*$",
	"^no puedes jugar (?:esta carta|este talisman) si .*$",
	"^(?:puedes )?jugarl[oa] (?:sin pagar su coste )?en respuesta a .*$",
	"^en respuesta a .+, (?:puedes .+ para )?(?:jugarl[oa]|juegal[oa]|jugar este talisman) .*$",
	"^jugar este talisman en respuesta a .*$",
	"^no puedes tener mas de tres copias.*$",
	"^si .+, (?:cuesta un oro menos|puedes jugarlo sin pagar su coste)(?: y destierralo)?$",
	# avaricia: habilidad desde el Cementerio, no parte del efecto al resolverse.
	"^cuando pongas un oro en juego, puedes subir este talisman de tu cementerio a tu mano$",
]

## "Elige un efecto: - A. - B." — cada viñeta es una opción.
const CHOOSE_ONE_RX := "^elige (?:un|uno) efecto:?\\s*(?<rest>.*)$"

## Costes al comienzo de una oración, antes de "para (que) ...": "pagar un Oro para Robar dos cartas",
## "Desterrarlo de tu Cementerio y pagar un Oro para...", "Descartar una carta para que un Aliado
## gane...". Se pagan antes de declarar (EffectInterpreter._pay_costs()); si alguno no se puede
## pagar, no se resuelve nada. El Oro sale como {op: "pay"}; el resto como {op: "cost", kind}.
## La carta misma: self_banish (de donde esté: la zona desde la que se puede usar la decide
## CardInspectionLayer), self_discard (desde la mano), self_pay / self_convert (los Oros:
## "pagarlo" = a tu Oro Pagado, "convertirlo en un Oro sin habilidad" = pierde su habilidad).
const COST_PIECES := [
	["self_banish", "desterrarl[oa](?: (?:en juego o )?(?:de|desde) tu (?:mano|cementerio)(?: o (?:de tu |tu )?(?:mano|cementerio|en juego))?)?"],
	["self_discard", "descartarl[oa]"],
	["self_pay", "(?:pagarl[oa]|pagar este oro)"],
	["self_convert", "convertirl[oa] en un oro sin habilidad"],
	# "puedes Destruirlo para que tu oponente Bote tres cartas" (Cementerio de Kingstead).
	["self_destroy", "destruirl[oa]"],
	# "puedes Barajarlo (en tu Castillo) para..." (rafael, miguel grau, amaterasu, illapa).
	["self_shuffle", "barajarl[oa](?: (?:de|desde) tu (?:mano|cementerio|destierro|reserva))?(?: en tu castillo)?"],
	["gold", "(?:pagar|paga) (?<n>" + NUM + ") oros?"],
	["discard", "descartar (?:(?<dn>" + NUM + ") cartas?(?: de tu mano)?|(?:un|una) (?<types>" + TALT + ")(?: de tu mano)?)"],
	# "Desterrar (otra) una/dos cartas de tu Cementerio para..." (udjat, grendel, argos, rosa pincheira,
	# forma canina). Nunca la carta misma. No "de tu Cementerio o mano" (van helsing, sigue en su patrón).
	["banish_cemetery", "desterrar (?:otra |otras )?(?<cn>" + NUM + ") cartas? de tu cementerio(?! o )"],
	# "Desterrar una carta de tu mano para..." (hijo de la tierra, melmoth, yekamus...). No "de tu mano o
	# cementerio" ni "o que controles": esos siguen en sus patrones.
	["banish_hand", "desterrar (?:(?<bn>" + NUM + ") cartas?|(?:un|una) (?<types>" + TALT + ")) de tu mano(?! o )"],
	["mill", "botar (?<n>" + NUM + ")(?: cartas?)?"],
	["reveal", "mostrar (?:un|una) (?<types>" + T1 + ")(?: (?<race>" + RACE + "))? de tu mano"],
	["sacrifice", "destruir otro aliado que controles"],
	# "Destruir/Desterrar/Barajar un Oro / una carta / un Aliado de coste 1 o más que controles para..."
	# (veles, piedra de la iglesia, dodomeki, molotok, arco patagon...). Puede ser la carta misma.
	["sacrifice_any", "(?<sv>destruir|desterrar|barajar) (?<sn>un|una|dos|tres) (?<types>" + TALT + ")" \
		+ "(?: de coste (?<cval>\\d+) o (?<ccmp>mas|menos))? que controles"],
	# "subir este Oro a tu mano" (hem hem real): la carta misma, de juego a la mano.
	["self_bounce", "(?:subir (?:este oro|esta carta|este aliado|esta arma|este totem)|subirlo|subirla) a tu mano"],
	["shuffle_hand", "barajar (?<n>" + NUM + ") cartas? de tu mano(?: en tu castillo)?"],
]

## La carta misma del Cementerio a la mano (átomo self_raise; ver _is_cemetery_self_ability()).
const SELF_RAISE_RX := "sub(?:irlo|irla|elo|ela|ir esta carta|ir esta arma|ir este aliado|ir este talisman) (?:de|desde) tu cementerio a tu mano"

## Subjuntivo → indicativo tras "para que" / "hacer que" (solo el primer verbo: "tantas como Fuerza
## tenga" más adelante queda como está).
const SUBJUNCTIVE := {
	"gane": "gana", "ganen": "ganan", "pierda": "pierde", "pierdan": "pierden", "tenga": "tiene",
	"tengan": "tienen", "bote": "bota", "descarte": "descarta", "destierre": "destierra", "sea": "es",
	"sean": "son", "pueda": "puede", "puedan": "pueden", "puedas": "puedes", "haga": "hace", "hagan": "hacen",
	"muestre": "muestra", "recibas": "recibes", "bloquee": "bloquea", "roben": "roban", "robe": "roba",
}

## "Si controlas (otro) (N o más) <tipo/raza> (de Fuerza N o más) (en Línea de Ataque), (además)
## efecto". Se evalúa al resolver.
const CONTROL_COND_RX := "^si controlas (?<other>otro |otra )?(?:(?<n>" + NUM + ") o mas )?" \
	+ "(?<what>[a-z]+(?: [a-z]+)?)(?: de fuerza (?<sv>\\d+) o mas)?(?<atk> en (?:tu )?linea de ataque)?" \
	+ ", (?:ademas )?(?<rest>.+)$"

## Condiciones al comienzo de una oración ("si X, efecto").
const CONDITIONS := [
	["not_attacked_this_turn", "si no fue declarado atacante este turno, "],
	# "Si es el turno oponente, además tú Robas dos cartas" (kukri) / "si es tu turno, genera un Oro".
	["opponent_turn", "si es el turno oponente, ademas "],
	["opponent_turn", "si es el turno oponente, "],
	["own_turn", "si es tu turno, ademas "],
	["own_turn", "si es tu turno, "],
	# duelo nocturno / ensamble: leen lo que hizo el paso "cada jugador" anterior (EffectInterpreterCadaJugador).
	["duel_win", "si tu aliado tiene mas fuerza, "],
	["duel_lose", "si tiene igual o menor fuerza, "],
	["drew_less_3", "si robas menos de tres cartas, "],
	# vampiro eterno: lo que Botó el paso anterior ("Tu oponente Bota la mitad de su Castillo").
	["milled_less_10", "si bota menos de diez cartas, "],
]

## Reemplazo sobre el paso anterior: "Si tiene Exhumar, en vez de eso, Destiérralo".
const REPLACE_RX := "^si tiene (?<kw>exhumar|furia|indestructible|imbloqueable|indesterrable|unica), en vez de eso, " \
	+ "(?<v>destierralo|destierrala|destruyelo|destruyela)$"

## Oraciones que son reglas estáticas (auras, keywords, permisos) — no son
## parte del efecto de esta habilidad: el compilador corta el bloque ahí
## (TriggerResolution._isolate_all_trigger_clauses() a veces las pega al
## final del bloque de un disparador).
const STATIC_STARTS := [
	"el portador", "los aliados", "tus aliados", "tus demas aliados", "los totem", "las armas", "los talismanes",
	"puede atacar", "puedes jugar", "no puede", "no pueden", "mientras", "furia", "imbloqueable",
	"indestructible", "indesterrable", "unica", "exhumar", "errante", "retador", "oro inicial",
	"reduce su coste", "tu oponente no puede", "a tu oponente le cuesta",
	# Otra habilidad condicional de la misma carta (p.ej. Draig Ifang: "Si este
	# Aliado es Destruido o Barajado desde el juego...") — no es continuación.
	"si este aliado", "si esta carta", "si este totem", "si esta arma", "si es anulado",
	# Reglas estáticas que el parser pega al final de una activada (metatron, zmey, garshasp, ogun,
	# jangseung, piedra del chaman, sirinia...): no son parte del efecto.
	"este aliado", "esta carta", "este oro", "este totem", "esta arma", "los oros", "tus cartas",
	"tu aliado de mayor", "cancelar las habilidades", "cancelar habilidad", "anular tus", "el dano directo",
	"jugar talismanes cuesta", "jugar aliados cuesta", "si controlas aliados de fuerza", "si esta en tu reserva",
	"si esta en tu cementerio", "si esta en juego", "los jugadores solo pueden", "cada jugador solo puede",
	# Reglas que siguen a un "mostrar" (anillo de vacío, shurijo, castillo matsumoto).
	"no se pueden", "los jugadores deben", "a los jugadores les cuesta",
	# Otra habilidad de la misma carta (miguel grau: "Si botas esta carta desde tu Castillo por daño...").
	"si botas esta carta",
	"solo puedes utilizar", "mientras este totem", "a tu oponente le cuesta",
	# Reglas pegadas a una activada (abel: "Convertir cartas y Barajar Aliados Héroe... cuesta un Oro adicional"; mug ruith:
	# "Si hay diez o más cartas en los Destierros, tus Aliados ganan...").
	"convertir cartas y barajar", "si hay diez o mas cartas en los destierros",
]

const TYPE_WORDS := {
	"aliado": "aliado", "aliados": "aliado", "arma": "arma", "armas": "arma",
	"totem": "totem", "totems": "totem", "talisman": "talisman", "talismanes": "talisman",
	"oro": "oro", "oros": "oro", "carta": "", "cartas": "",
}

## Frase de objetivo en juego — usada por los verbos destruir/desterrar/
## barajar/subir. Grupos con nombre (PCRE2).
const TARGET_RX := "(?<det>(?:hasta )?" + NUM + ") (?<kind>aliados?|cartas?|totems?|armas?)" \
	+ "(?<opp> oponentes?)?(?: en juego)?(?<nogold> que no sean? (?:un )?oro)?" \
	+ "(?: de (?<stat>fuerza|coste) (?<val>\\d+)(?: o (?<cmp>menos|mas))?)?"

## "de Fuerza 3 o menos" / "de coste 2 o más" tras el sujeto ("Un Aliado de coste 2 o menos gana...").
const STAT_FILTER := "(?: de (?<stat>fuerza|coste) (?<val>\\d+) o (?<cmp>menos|mas))?"
## Tipo de carta, y una lista de alternativas ("un Aliado, Arma u Oro").
const T1 := "(?:aliados?|armas?|totems?|talisman(?:es)?|oros?|cartas?)"
const TALT := T1 + "(?:(?:, | o | u )(?:un |una )?" + T1 + ")*"
## "Gana ..." — lo que un Aliado puede ganar en una misma oración.
## "hace el doble de daño" / "no hace daño de combate": metas por el turno que lee BattleManager
## (double_combat_damage_turn, no_damage_turn).
const GRANT_ITEM := "(?:\\d+ de fuerza|furia|imbloqueable|indestructible|indesterrable|hace dano al destierro" \
	+ "|ha(?:ce|ga) (?:el )?doble de dano|no ha(?:ce|ga) dano de combate)"
## Lo que se elige en "gana A, B o C" (grant_choice).
const CHOICE_ITEM := "(?:furia|imbloqueable|indestructible|indesterrable|[\"“”]?no puede ser barajado[\"“”]?" \
	+ "|ha(?:ce|ga) (?:el )?doble de dano)"
## Razas que aparecen en "busca un Aliado Dragón" / "un Ángel, Eterno o Tótem" (sin tildes, como
## normalize()).
const RACE := "(?:angel(?:es)?|eternos?|dragon(?:es)?|caballeros?|paladin(?:es)?|titan(?:es)?|ignis|bandidos?" \
	+ "|sacerdotes?|guerreros?|heroes?|bestias?|sombras?|faeries?|demonios?|olimpicos?|defensor(?:es)?|faraon(?:es)?" \
	+ "|jinetes?|samurais?|ninjas?|vampiros?|cazador(?:es)?|piratas?|brujos?|chaman(?:es)?|orcos?|dinosaurios?)"
## Objetos de "busca / sube": "un Aliado Dragón", "un Ángel, Eterno o Tótem", "un Aliado y un Tótem"
## (" y " = una carta de cada grupo, ver _object_groups()).
const OBJ1 := "(?:(?:hasta )?" + NUM + " )?(?:" + T1 + "(?: " + RACE + "(?: o " + RACE + ")*)?|" + RACE + ")"
const OBJS := OBJ1 + "(?:(?:, y |, | o | u | y/o | y )" + OBJ1 + ")*"
## "hasta mostrar un Oro y un Arma o Tótem de coste 2 o menos"
## Tipos dentro de "hasta mostrar": la coma separa cartas pedidas ("un Aliado, un Arma y un Tótem",
## megumi), no alternativas como en TALT.
const TALT_R := T1 + "(?:(?: o | u )(?:un |una )?" + T1 + ")*"
const REVEAL_KW := "(?:furia|imbloqueable|indestructible|indesterrable|guardian|retador)"
## "un Aliado Guerrero de coste 2 o menos", "un Oro con habilidad", "un Aliado con Furia", "dos Aliados
## Héroe que no sean Odiseo", "un Aliado de fuerza 4 o más", "dos Oros de distinto nombre".
const REVEAL_SPEC := NUM + " " + TALT_R + "(?: " + RACE + ")?(?: (?:con|sin) habilidad)?(?: con " + REVEAL_KW + ")?" \
	+ "(?: que no sean? (?:un |una )?[a-z]+)?" \
	+ "(?: (?:de )?coste \\d+(?: o (?:menos|mas))?)?"  \
	+ "(?: de fuerza \\d+(?: o (?:menos|mas))?)?(?: de distinto nombre)?"  # "un Arma coste 1" (fat-frumos)
## Un destino del reparto de reveal_until: "pon uno en tu mano", "tres en tu Cementerio", "la otra en tu
## Cementerio", "juega uno sin pagar su coste", "baraja el otro".
const REVEAL_DIST_ITEM := "(?:(?:pon )?(?:" + NUM + "|otro|otra|el otro|la otra)(?: carta)? en tu (?:mano|cementerio|destierro)" \
	+ "|juega (?:uno|una|el otro|la otra) sin pagar su coste|baraja (?:el otro|la otra))"

## Átomos en orden de prioridad (los más específicos primero: p.ej.
## 'descarta... de la mano de tu oponente al azar' antes que 'descarta N
## cartas'). Cada uno se ancla al inicio del texto restante.
const ATOMS := [
	["draw", "(?:tu )?roba(?:s|r)? (?<upto>hasta )?(?<n>" + NUM + ") cartas?(?: de tu castillo)?"],
	["draw_to_match", "roba(?:r)? cartas hasta tener la misma cantidad de cartas en (?:(?:la|tu) )?mano que tu oponente"],
	# Piezas sueltas de una o pocas cartas (EffectInterpreterEspeciales).
	# estirpe maldita (con "Por cada Aliado que controles, ..."): la carta del tope entra como Aliado sin habilidad.
	["special:castle_top_ally", "pon una carta del tope de un castillo en juego como un aliado de fuerza (?<v>\\d+) sin habilidad"],
	# chivateo del mandinga: lo que destruyó el paso anterior, por controlador.
	["special:draw_per_destroyed_ctrl", "por cada aliado que haya sido destruido de esta manera, su controlador roba una carta"],
	# forma de araña.
	["special:next_ally_discount_furia", "el proximo aliado que juegues este turno reduce su coste en un oro y gana furia"],
	# mug ruith.
	["special:name_lock_attack", "un aliado y todas sus copias no pueden atacar ni tu oponente puede utilizar sus habilidades hasta tu proximo turno"],
	# murciélago.
	["special:drain_distribute", "un aliado oponente pierde tanta fuerza como aliados controles y distribuye esa misma cantidad de fuerza" \
		+ " entre tus aliados permanentemente"],
	# Habilidad entre comillas que gana un Aliado (hp lovecraft, soberbia, gran escape): el texto sale de la carta
	# original, con mayúsculas y tildes.
	["special:grant_quoted", "(?:un|una) aliado(?: de coste (?<cv>\\d+) o (?<cc>mas|menos))?(?<own> que controles)? gana la habilidad" \
		+ " [\"“”¨][^\"“”¨]+[\"“”¨](?:,? (?:por el resto del juego|mientras este en juego))?"],
	# efigie: la habilidad del Aliado Desterrado por el paso anterior.
	["special:grant_affected", "un aliado de coste (?<cv>\\d+) o (?<cc>mas|menos)(?<own> que controles) gana su habilidad por el resto del juego"],
	# soberbia (la habilidad que da): "Barajar todos los Aliados de menor Fuerza que este Aliado".
	["special:shuffle_weaker", "barajar todos los aliados de menor fuerza que este aliado"],
	# abel: "un Aliado gana Fuerza igual a la cantidad de Aliados que controles o que controle tu oponente".
	["buff_eq_allies", "un aliado gana fuerza igual a la cantidad de aliados que controles o que controle tu oponente"],
	# kuji-in.
	["kuji_buff", "un aliado que controles gana furia, tanta fuerza como aliados de coste (?<cv>\\d+) o mas hayan en tu cementerio" \
		+ " y no puede salir del juego este turno"],
	# hp lovecraft (la habilidad que da): "tu oponente Destierra una carta de su mano".
	["opp_hand_exile", "tu oponente destierra (?<n>" + NUM + ") cartas? de su mano"],
	# Lo que hace (o elige) tu oponente sobre lo suyo, y reglas que le pones (EffectInterpreterOponente).
	["opp:mill_half", "tu oponente bota la mitad de su castillo,? redondeado hacia arriba"],
	["opp:discard_or_shuffle", "tu oponente (?:debe |deba )?descartar una carta o barajar una carta que controle que no (?:sea|es) oro"],
	["opp:silence_golds", "tu oponente elige (?<n>" + NUM + ") oros con habilidad que controle y los convierte en oros sin habilidad"],
	["opp:convert_match", "tu oponente convierte aliados y oros que controle en totem sin habilidad,? hasta tener la misma cantidad" \
		+ " de aliados y oros que controlas"],
	["opp:convert_steal", "si se convierten (?<n>\\d+|" + NUM + ") o menos cartas de esa manera, gana su control"],
	["opp:next_turn_lock", "tu oponente en su siguiente turno no puede atacar ni jugar mas de una carta de cada tipo"],
	["opp:ability_toll", "tu oponente no puede utilizar las habilidades de esa carta este turno a menos que pague un oro"],
	["opp:toll_reward_draw", "cuando tu oponente pague un oro de esta forma,? tu robas una carta"],
	["opp:name_lock", "nombra una carta,? las cartas con ese nombre no pueden ser jugadas en su proximo turno"],
	# "tu oponente Destierra cartas del tope de su Castillo como Oros tenga en su Reserva" (leng).
	["castle_exile_reserve", "tu oponente destierra cartas del tope de su castillo como oros tenga en su reserva"],
	["mill_per", "tu oponente bota (?<n>" + NUM + ") cartas? por cada (?<per>aliado en tu linea de defensa" \
		+ "|aliado que controles|totem en juego y en tu destierro|totem en juego|totem que controles|oro que controles)"],
	# Cantidad según una Fuerza o una mano: "un jugador Bota tantas cartas como Fuerza tenga un Aliado
	# que controles" (el cuero), "tu oponente Bota cartas igual a la Fuerza del portador" (gran
	# khopesh), "tu oponente Bota tantas cartas como Aliados tenga en su mano" (mu), "Destierra tantas
	# cartas del tope del Castillo oponente como Fuerza tenga un Aliado que porte Arma" (watson).
	["mill_x", "(?<who>tu oponente|un jugador) bota tantas cartas como fuerza tenga (?<src>un aliado que controles|un aliado que porte armas?)"],
	["mill_x", "(?<who>tu oponente|un jugador) bota cartas igual a la fuerza (?<src>del portador)"],
	["mill_x", "(?<who>tu oponente) bota tantas cartas como (?<src>aliados tenga en su mano)"],
	# Más fuentes: la Fuerza de este Aliado (Kuchiku El Cazador, satanas), la de un Aliado en juego
	# (cahuelche), el coste de una carta en juego (chamuel) o de otra que controles (kib), los Oros de tu
	# Oro Pagado (honengyo).
	["mill_x", "(?<who>tu oponente|un jugador) bota (?:cartas igual a la fuerza de|tantas cartas como fuerza tenga) (?<src>este aliado|un aliado en juego)(?![a-z])"],
	["mill_x", "(?<who>tu oponente|un jugador) bota tantas cartas como (?<src>su fuerza)"],
	["mill_x", "(?<who>tu oponente|un jugador) bota tantas cartas como coste tenga (?<src>una carta en juego|otra carta que controles)"],
	["mill_x", "(?<who>tu oponente|un jugador) bota tantas cartas como (?<src>oros haya en tu oro pagado)"],
	# "Tu oponente Bota tantas cartas como Aliados controles" (principe ur nammu, mr smee).
	["mill_x", "(?<who>tu oponente|un jugador) bota tantas cartas como (?<src>aliados controles)(?! o )"],
	# La Fuerza del Aliado pagado como coste (taira no masakado: "Desterrar un Aliado... para que tu oponente
	# Bote tantas cartas como Fuerza tenga ese Aliado") y la que perdió el paso anterior (armas campesinas).
	["mill_x", "(?<who>tu oponente) bota tantas cartas como fuerza (?:tenga|tiene) (?<src>ese aliado)"],
	["mill_x", "(?<who>tu oponente) bota tantas cartas como (?<src>fuerza haya perdido de esta forma)"],
	["mill_x", "(?<exile>destierra) tantas cartas del tope del castillo oponente como fuerza tenga (?<src>un aliado que porte armas?|un aliado que controles)"],
	["mill_opp", "tu oponente bota (?<n>" + NUM + ") cartas?"],
	["mill_both", "(?:cada jugador bota|los jugadores botan) (?<n>" + NUM + ") cartas?(?: de su castillo)?"],
	["mill_self", "bota(?:s|r)? (?<n>" + NUM + ") cartas?"],
	["discard_opp_random", "descarta(?:r)? (?<n>" + NUM + ") cartas? de la mano de tu oponente al azar"],
	# "Pon en juego un Aliado de tu Cementerio como un Aliado sin habilidad" (carcancho) / "pon hasta
	# dos Aliados de tu Cementerio en juego, sin habilidad" (mocha dick): como Alto Prime
	# (CemeteryRevivePatterns), entra con el texto vacío.
	["revive_blank", "(?:pon|poner) (?:en juego )?(?:bajo tu control )?(?<det>(?:hasta )?" + NUM + ") aliados?" \
		+ "(?: de coste (?<cval>" + NUM + ") o (?<ccmp>menos|mas))? de tu cementerio(?: en juego)?,? (?:como (?:un )?aliados? )?sin habilidad"],
	# "Mover un Oro oponente a su Oro Pagado" (Legión de Honor).
	["opp_gold_to_paid", "(?:mover un oro oponente a su oro pagado|paga(?:r)? un oro oponente)"],  # forma de araña: "paga un Oro oponente"
	# "...para subirlo de tu Cementerio a tu mano" (Belial, sai): la carta misma vuelve a la mano.
	["self_raise", SELF_RAISE_RX],
	# "Cancela el ataque de un Aliado (oponente)" / "de hasta dos Aliados" (Drácula, zawbaa, perun).
	["cancel_attack", "cancela(?:r)? el ataque de (?<det>(?:hasta )?" + NUM + ") aliados?(?<opp> oponentes?)?"],
	# "Tu oponente (debe) Descarta(r) una carta (de su mano) (al azar)": elige él, salvo al azar.
	["discard_opp", "tu oponente (?:descarta|debe descartar) (?<n>" + NUM + ") cartas?(?: de su mano)?(?<rnd> al azar)?"],
	# "Tu oponente Destierra dos cartas del tope de su Castillo" / "Destierra cinco cartas del tope del
	# Castillo oponente" (CardManager.banish_from_deck()).
	["castle_exile", "(?:tu oponente destierra (?<n>" + NUM + ") cartas? del (?<pos>tope|fondo) de su castillo" \
		+ "|(?:destierra|desterrar) (?<n2>" + NUM + ") cartas? (?:del (?<pos2>tope|fondo)|de la parte superior) del castillo oponente" \
		+ "|(?:tu oponente )?destierra las primeras (?<n3>" + NUM + ") cartas de su castillo)"],
	["discard_self", "descarta(?:s|r)? (?<n>" + NUM + ") cartas?(?: de tu mano)?(?! de la mano)"],
	["shuffle_from_hand", "baraja(?:r)? (?<upto>hasta )?(?<n>" + NUM + ") cartas? de tu mano(?: en tu castillo)?"],
	# "Baraja (hasta) N cartas de tu Cementerio" ya es en tu Castillo (Barajar = al Castillo de su dueño).
	["shuffle_from_cemetery", "baraja(?:r)? (?<upto>hasta )?(?<n>" + NUM + ") cartas? de tu cementerio(?: en tu castillo)?"],
	# "Tu oponente baraja una carta de su mano" (kukri): la elige él.
	["shuffle_from_hand_opp", "tu oponente baraja (?<n>" + NUM + ") cartas? de su mano(?: en su castillo)?"],
	# Buscar: varios tipos, "que no sea X ni Y", "de coste N o más/menos". El destino va tras "y" o tras una
	# coma ("busca un Aliado, ponlo en tu mano y roba una carta").
	# "...y jugarlo sin pagar su coste / reduciendo su coste en un Oro / por dos Oros menos".
	# "en un Castillo" / "en el Castillo oponente" (el horla, sin tregua, chashkel): solo para Desterrar o
	# mandar al Cementerio de su dueño (no pasa a tu mano). "con distinto nombre" (espectros vindicantes).
	# Destino a elegir ("ponlo en tu mano o Destierro", "juégalo sin pagar su coste o ponlo en tu mano") y
	# reparto ("busca tres Aliados, pon uno en tu mano y dos en tu Cementerio", kurai ketsugo).
	["search", "busca(?:r)? (?:(?:en tu (?<z1>castillo|cementerio)(?: (?:o|y/o) (?:tu )?(?<z2>castillo|cementerio))?|en (?<zx1>un castillo|el castillo oponente)),? )?" \
		+ "(?:(?<copy>una copia de (?:esta carta|este oro|este aliado|esta arma|este totem|este talisman))" \
		+ "|(?<objs>" + OBJS + ")(?: (?!(?:de|del|que|y|o|u|en|con|sin|al|a)\\b)(?<nm>[a-z]+(?: (?!(?:de|del|que|y|o|u|en|con|sin|al|a)\\b)[a-z]+){0,2}?))?" \
		+ "(?<same> del mismo tipo)?)" \
		+ "(?: que no sean? (?:un |una )?(?<n1>" + T1 + ")(?: ni (?:un |una )?(?<n2>" + T1 + "))?)?" \
		+ "(?:,? que no sean? (?<nnot>(?!un |una )[a-z]+(?: [a-z]+){0,3}?))?" \
		+ "(?:,? de coste (?<cval>" + NUM + ")(?: o (?<ccmp>menos|mas))?)?" \
		+ "(?:,? de fuerza (?<sval>\\d+) o (?<scmp>menos|mas))?" \
		+ "(?<nohab> sin habilidad)?" \
		+ "(?<distinct>,? (?:con|de) (?:distinto|diferente) nombre,?)?" \
		+ "(?: en tu (?<z3>castillo|cementerio)(?: (?:o|y/o) (?:tu )?(?<z4>castillo|cementerio))?| en (?<zx2>un castillo|el castillo oponente))?" \
		+ "(?:,? y |, )(?:(?:ponla|ponlo|ponerla|ponerlo|ponlas|ponlos|ponerlas|ponerlos) en (?:tu (?<dest>mano|oro pagado|cementerio)" \
		+ "(?: (?:o|y/o) (?:tu )?(?<alt>cementerio|destierro)s?)?|(?<owncem>el cementerio de su dueno))" \
		+ "|(?<exile>destierralos|destierralas|destierralo|destierrala)" \
		+ "|(?<putplay>ponlo|ponla|ponerlo|ponerla) en juego" \
		+ "|(?<sdist>pon (?:" + NUM + ") en tu (?:mano|cementerio|destierro)(?:(?:, | y )(?:" + NUM + ") en tu (?:mano|cementerio|destierro))+)" \
		+ "|(?<play>jugarlo|jugarla|juegalo|juegala|jugarlos|jugarlas|juegalos|juegalas)(?: (?<free>sin pagar su coste)" \
		+ "| reduciendo su coste en (?<red>" + NUM + ") oros?(?:, hasta un minimo de (?<floor>\\d+))?" \
		+ "| reduciendo su coste en tantos oros como (?<redq>totems? controles)(?:, hasta un minimo de (?<floor2>\\d+))?" \
		+ "| por (?<red2>" + NUM + ") oros? menos)(?<orhand> o (?:ponlos|ponlas|ponlo|ponla|ponerlos|ponerlas|ponerlo|ponerla) en tu mano)?)"],
	# rey de amarillo: "Busca en un Castillo una carta por cada Aliado que controles más una y Destiérralas".
	["search_per_ally_plus", "busca en un castillo una carta por cada aliado que controles mas una y destierralas"],
	# pebre: "Busca en tu Castillo una Empanada, un Anticucho y ponlos en tu mano" (dos nombres).
	["search_named_two", "busca(?:r)? en tu castillo (?:un|una) (?<a>[a-z' -]+?),? (?:y )?(?:un|una) (?<b>[a-z' -]+?),? y (?:ponlos|ponlas) en tu mano"],
	# perseguir el sol: "Busca en tu Castillo un Oro y otra carta, pon el Oro en tu Oro Pagado y la otra carta en tu mano".
	["search_gold_and_other", "busca en tu castillo un oro y otra carta, pon el oro en tu oro pagado y la otra carta en tu mano"],
	# avaricia: "Busca en tu Castillo tres Oros. Pon dos de ellos en tu Oro Pagado, sin habilidad por el turno, y el
	# otro en tu mano" (las dos oraciones las junta _split_sentences()).
	["search_gold_split", "busca en tu castillo (?<n>" + NUM + ") oros, pon (?<k>" + NUM + ") de ellos en tu oro pagado, sin habilidad por el turno, y el otro en tu mano"],
	# oda nobunaga: "Busca en el Castillo oponente tres cartas de coste 2 o menos con distinto nombre. Conviértelas en
	# Armas sin habilidad y pórtalas sobre Aliados en juego".
	["search_as_weapons", "busca en el castillo oponente (?<n>" + NUM + ") cartas de coste (?<cv>\\d+) o menos con distinto nombre," \
		+ " conviertelas en armas sin habilidad y portalas sobre aliados en juego"],
	# "Busca un Leyaden/una Empanada en tu Castillo y ponlo en tu mano": una carta por su nombre (leyaden,
	# empanada, yekamus).
	["search_named", "busca(?:r)? (?:un|una) (?<name>[a-z' -]+?) en tu castillo y (?:ponlo|ponla|ponerlo|ponerla) en tu mano"],
	# "Busca en tu Castillo un Pincheira y ponlo en tu mano" (rosa pincheira): el nombre después de la zona.
	# Un nombre, no un tipo ("una carta del mismo tipo", "un Aliado Mochizuki" son otra cosa).
	["search_named", "busca(?:r)? en tu castillo (?:un|una) (?!(?:aliados?|armas?|totems?|talisman(?:es)?|oros?|cartas?|copia)\\b)" \
		+ "(?<name>[a-z' -]+?)(?:,? y |, )(?:ponlo|ponla|ponerlo|ponerla) en tu mano"],
	# "Sube un Aliado y un Arma de tu Cementerio a tu mano": búsqueda en el Cementerio propio.
	# "...a tu mano que no sea Talismán" (strut): la exclusión también puede ir al final (nt).
	["raise", "sub(?:e|ir) (?<objs>" + OBJS + ")(?: que no sean? (?:un |una )?(?<n1>" + T1 + "))?" \
		+ "(?: de coste (?<cval>" + NUM + ")(?: o (?<ccmp>menos|mas))?)? (?:de|desde) tu cementerio a (?:tu|la) mano" \
		+ "(?: que no sean? (?:un |una )?(?<nt>" + T1 + "))?"],
	# "Pon un Oro de tu mano o Cementerio en tu Oro Pagado" / "poner un Oro en juego desde tu mano o
	# Cementerio" (a la Reserva).
	["gold_to_paid", "(?:pon|poner) un oro (?<injuego>en juego )?(?:de|desde) tu (?<z1>mano|cementerio)" \
		+ "(?: o (?:tu )?(?<z2>mano|cementerio))?(?: en tu (?<dest>oro pagado|reserva))?"],
	# "Pon dos cartas del fondo de tu Castillo en tu mano" / "muestra la última carta de tu Castillo y
	# ponla en tu mano" / "pon la primera y la última carta de tu Castillo en tu mano".
	["deck_to_hand", "(?:(?:pon|poner) (?:(?<one>la carta)|(?<n>" + NUM + ") cartas) del (?<from>fondo|tope) de tu castillo" \
		+ "|muestra la (?<from2>ultima|primera) carta de tu castillo y ponla|(?:pon|poner) la (?<both>primera y la ultima)" \
		+ " carta de tu castillo) en tu mano"],
	# "Jugar un Aliado de coste 2 o menos desde tu mano o Cementerio sin pagar su coste / reduciendo su
	# coste en un Oro, hasta un mínimo de 0 / pagando su coste (y Destiérralo)".
	# "...una carta que no sea Talismán de tu Cementerio..." (corazón de muerte).
	["play_from", "(?:juega|jugar) (?<objs>" + OBJS + ")(?: que no sean? (?:un |una )?(?<n1>" + T1 + "))?" \
		+ "(?: de coste (?<cval>" + NUM + ")(?: o (?<ccmp>menos|mas))?)?" \
		+ " (?:de|desde) tu (?<z1>mano|cementerio)(?: o (?:tu )?(?<z2>mano|cementerio))?,?" \
		+ " (?:(?<free>sin pagar su coste)|reduciendo su coste en (?<red>" + NUM + ") oros?(?:, hasta un minimo de (?<floor>\\d+))?" \
		+ "|por (?<red2>" + NUM + ") oros? menos|(?<pay>pagando su coste))(?<exile> y destierralo| y destierrala)?"],
	# "Mira la mano de tu oponente" / "Muestra tu mano", sin nada más (después de hand_peek, que lleva
	# verbo).
	["peek_hand", "mira(?:r)? la mano de tu oponente(?=$|,? y luego|, luego)"],
	# "Tu oponente muestra su mano" (semyazza): la ve quien controla el efecto, como mirarla.
	["peek_hand", "tu oponente (?:te )?muestra su mano(?=$|,? y |, )(?!,? y tu (?:descartas|elige))"],
	["show_hand", "muestra(?:r)? tu mano(?=$|,? y |, )"],
	# "No recibes daño (de combate) hasta tu próximo turno".
	["no_damage", "no (?:recibes|puedes recibir) dano(?<combat> de combate)? hasta tu proximo turno"],
	# "Mira la mano de tu oponente y Destierra/Descarta/Baraja una carta de coste 2 o menos (que no sea
	# Oro) de ahí".
	["hand_peek", "mira(?:r)? la mano de tu oponente(?:,| y) (?<v>destierra|desterrar|descarta|descartar|baraja|barajar)" \
		+ " (?<det>" + NUM + ") (?<type>" + TALT + ")(?: de coste (?<cval>\\d+)(?: o (?<ccmp>menos|mas))?)?" \
		+ "(?: de ahi)?(?: de coste (?<cval2>\\d+)(?: o (?<ccmp2>menos|mas))?)?" \
		+ "(?: que no sean? (?:un |una )?(?<n1>" + T1 + ")(?: ni (?:un |una )?(?<n2>" + T1 + "))?)?(?: de ahi)?"],
	# "Tu oponente muestra su mano y tú Descartas un Talismán de ahí" (camahueto): como hand_peek.
	["hand_show_discard", "tu oponente muestra su mano y tu descartas (?<det>" + NUM + ") (?<type>" + TALT + ") de ahi"],
	# "Muestra cartas del tope de tu Castillo hasta mostrar un Oro y un Aliado
	# y ponlos en tu mano (y baraja el resto)" — el resto siempre se baraja.
	# También "puedes mostrar cartas de tu Castillo hasta mostrar dos Aliados Guerrero y ponerlos en tu
	# mano", "...que no sean Talismán" y "...un Tótem de coste 1 y juégalo sin pagar su coste".
	# Destinos: a la mano, "juégalo sin pagar su coste", "ponlo en juego" (anillo de vacío), "ponlos en tu
	# Oro pagado" (cae megido) o un reparto (nace la furia, monte fuji, megumi, ataque feérico, papa legba).
	["reveal_until", "(?:muestra|muestras|mostrar) cartas (?:del tope |de la parte superior )?de tu castillo hasta (?:mos(?:tr|t)a(?:r|s)|que muestres) (?<specs>" \
		+ REVEAL_SPEC + "(?:(?:,| y) " + REVEAL_SPEC + ")*)(?:,? y |, )(?:(?:ponlos|ponlas|ponlo|ponla|ponerlos|ponerlas|ponerlo|ponerla|pon esa carta|pon esas cartas|pon ese [a-z]+)" \
		+ " en tu mano|(?<gold>ponlos|ponlas|ponlo|ponla) en tu oro pagado|(?<put>ponlo|ponla|ponlos|ponlas) en juego" \
		+ "|(?<play>juegalo|juegala|jugarlo|jugarla|juegalos|jugarlos|juega ese aliado|juega esa carta) sin pagar su coste" \
		+ "|(?<dist>" + REVEAL_DIST_ITEM + "(?:(?:, | y )" + REVEAL_DIST_ITEM + ")+))(?:(?:,? y |, )baraja el resto)?"],
	# "Muestra cuatro cartas del tope de tu Castillo. Pon dos cartas de ahí en tu mano y el resto en tu
	# Destierro" (warlock), "muestra las primeras cinco cartas de tu Castillo, pon hasta dos Aliados u Oros
	# de ahí en tu mano y baraja el resto" (castillo matsumoto, frasco canópico), "mostrar seis cartas del
	# tope de tu Castillo, elige un Aliado de ahí, ponlo en tu mano" (shurijo), "juega un Aliado de ahí por
	# un Oro menos y pon el resto en tu mano" (yari).
	["reveal_top", "(?:muestra|mostrar) (?:las primeras (?<n>" + NUM + ") cartas de tu castillo|(?<n2>" + NUM + ") cartas del tope de tu castillo)" \
		+ "(?:,? y |, )(?:elige (?<ek>" + NUM + ") (?<et>" + TALT + ") de ahi, (?:ponlo|ponla|ponlos|ponlas) en tu mano" \
		+ "|pon (?<upto>hasta )?(?<k>" + NUM + ") (?<kt>" + TALT + ") de ahi en tu mano" \
		+ "|juega (?<pk>" + NUM + ") (?<pt>" + TALT + ") de ahi por (?<red>" + NUM + ") oros? menos)" \
		+ "(?:,? y (?:pon )?el resto en tu (?<rd>mano|destierro|cementerio)|(?:,? y |, )baraja el resto)?"],
	# "Destruye todas las cartas en juego que no sean Oro" (enoc): los Oros nunca entran (exclude_gold).
	["mass", "(?<verb>destruye|destierra) (?:todos los (?<kind>aliados|totems|armas)|todas las cartas)(?<opp> oponentes)?(?: en juego)?" \
		+ "(?: que no sean? oros?)?" \
		+ "(?: de (?<stat>fuerza|coste) (?<val>\\d+) o (?<cmp>menos|mas))?"],
	["bounce", "sub(?:e|ir) " + TARGET_RX + " a la mano de su dueno"],
	# "Un Aliado oponente pierde su habilidad y es Destruido" (Guardia Gozosa)
	# / "Los Tótem de coste 2 o menos pierden su habilidad y son Destruidos"
	# (Destruir Refugio) — pierde la habilidad ANTES, así no dispara su
	# "cuando salga del juego".
	["target_silence", "(?<det>un|una) (?<kind>aliado|carta|totem|arma)(?<opp> oponente)?(?: en juego)?" \
		+ " pierde su habilidad y es (?<v>destruid[oa]|desterrad[oa])"],
	["mass_silence", "(?:los|las) (?<kind>totems?|aliados|armas)(?<opp> oponentes)?(?: en juego)?" \
		+ "(?: de (?<stat>fuerza|coste) (?<val>\\d+) o (?<cmp>menos|mas))? pierden su habilidad y son" \
		+ " (?<v>destruid[oa]s|desterrad[oa]s)"],
	# "Gana 1 de Fuerza por cada carta en el Destierro oponente" (udug) / "...por cada Aliado en tu Destierro"
	# (brujo mendigo): la propia carta, por el turno.
	["self_buff_per", "gana (?<n>" + NUM + ") de fuerza por cada (?<per>carta en el destierro oponente|aliado en tu destierro)"],
	["self", "(?<v>destruyelo|destruyela|destierralo|destierrala|barajalo|barajala|barajarlo|barajarla)(?: en tu castillo)?"],
	# "Cada jugador roba una carta / descarta una carta / destierra una carta de su mano" (forma de
	# leopardo, danel, okyo, geminis): cada uno elige la suya.
	["each_draw", "cada jugador roba (?<n>" + NUM + ") cartas?"],
	# Reglas con duración ("hasta tu próximo turno, ..."): cada frase es una regla del motor que se anota en
	# RuleState (o su equivalente) al resolver; quien la hace cumplir está en EffectInterpreter._apply_rule().
	["rule:ally_affect_tax", "hasta tu proximo turno, (?:afectar a tus aliados cuesta un oro adicional" \
		+ "|a tu oponente le cuesta un oro adicional afectar a tus aliados)"],
	["rule:trigger_gold_toll", "hasta tu proximo turno,? tu oponente no puede utilizar habilidades disparadas a menos que pague un oro"],
	["rule:open_hands", "hasta tu proximo turno, los jugadores juegan con su mano descubierta y no pueden descartar cartas por efectos"],
	["rule:search_toll", "hasta tu proximo turno, cuando busques cartas en el castillo oponente, tu oponente destierra una carta del tope de su castillo"],
	["rule:talisman_to_exile", "hasta tu proximo turno, los talismanes que fueran a ser puestos en el cementerio, en vez de eso son desterrados"],
	["rule:attack_cap_2", "hasta tu proximo turno, solo se puede atacar con hasta dos aliados por turno"],
	["rule:two_per_type", "hasta tu proximo turno, no se pueden poner en juego mas de dos cartas de cada tipo por turno"],
	["rule:shuffle_banish_tax", "hasta tu proximo turno, tu oponente debe pagar un oro adicional para barajar y/o desterrar tus cartas en juego"],
	["rule:no_hand_limit", "hasta tu proximo turno,? no tienes limite de cartas en tu mano"],
	["rule:opp_immune_turn", "no puedes ser afectado por efectos oponentes este turno"],
	["rule:zombie", "hasta tu proximo turno, cada vez que recibas dano oponente, tu oponente bota esa misma cantidad y tu pones en juego" \
		+ " un aliado de un cementerio como un aliado sin habilidad"],
	["rule:allies_no_leave", "hasta tu proximo turno, tus aliados no pueden salir del juego y anularlos cuesta un oro adicional"],
	["rule:final_silence_allies", "en tu fase final, tus aliados pierden su habilidad hasta tu proximo turno"],
	["rule:castle_lock", "hasta tu proximo turno, no se puede botar, desterrar cartas de los castillos ni descartar cartas, por efectos"],
	["rule:cemetery_shuffle_cap", "por el resto del juego, los jugadores solo pueden barajar hasta tres cartas de los cementerios cada turno"],
	["rule:cemetery_exile_lock", "por el resto del juego, tu oponente no puede desterrar cartas de tu cementerio que no sean talisman(?:es)?"],
	# "Hasta tu próximo turno, tus Aliados no pueden ser Destruidos ni Desterrados (y ganan 1 de Fuerza
	# permanentemente)" (susurro de los bosques): Indestructible e Indesterrable hasta tu próximo turno.
	["own_allies_protect", "hasta tu proximo turno, tus aliados no pueden ser destruidos ni desterrados" \
		+ "(?: y ganan (?<n>" + NUM + ") de fuerza permanentemente)?"],
	# "Cada jugador elige (hasta) N Aliados/Oros que controle y baraja el resto / sus demás Aliados en
	# juego" (bomba eléctrica, biwa, herido peleó mejor).
	["keep_shuffle", "cada jugador elige (?<upto>hasta )?(?<n>" + NUM + ") (?<kind>aliados?|oros?|cartas?)(?<pc> de cada coste)? que controle" \
		+ " y baraja (?:el resto|sus demas (?:aliados|oros|cartas)(?: en juego)?)"],
	# armagedon: "Cada jugador elige una carta que controle y las demás cartas que no sean Oro pierden su
	# habilidad y son Barajadas".
	["keep_silence_shuffle", "cada jugador elige una carta que controle y las demas cartas que no sean oros? pierden su habilidad y son barajadas"],
	# Lo que hace cada jugador sobre lo suyo (EffectInterpreterCadaJugador). Las oraciones "de esta forma" que
	# siguen leen lo que movió.
	["each:shuffle_all", "cada jugador baraja las cartas que controle que no sean oros?"],
	["each:hand_to", "los jugadores barajan cartas de su mano o roban cartas,? hasta tener (?<n>" + NUM + ") cartas en su mano"],
	["each:duel_put", "cada jugador pone desde su mano en juego un aliado de coste (?<n>\\d+) o menos y entran sin habilidad por el turno"],
	["each:duel_destroy", "destruye el aliado oponente"],
	["each:duel_shuffle", "baraja ambos aliados"],
	["each:reveal_top", "cada jugador muestra (?<n>" + NUM + ") cartas del tope de su castillo"],
	["each:fog_banish", "por cada aliado que hayas mostrado de esta forma,? elige una carta mostrada por tu oponente y destierrala"],
	["each:random_split", "tu oponente destierra una al azar entre sus " + NUM + " cartas y tu pones en tu mano una al azar entre tus " + NUM + " cartas"],
	["each:hand_discard_cost", "cada jugador muestra su mano y descarta todas las cartas de coste (?<n>\\d+) o menos de ahi"],
	["each:draw_per_discarded", "por cada carta descartada de tu mano de esta forma,? roba una carta"],
	["each:hand_show_exile", "cada jugador muestra su mano y destierra un aliado de ahi"],
	["each:foreign_shuffle", "cada jugador baraja los aliados y totems? que controle de las que no sea dueno y destierra (?<n>" + NUM \
		+ ") cartas del tope de su castillo por cada carta que barajo de esta forma"],
	["each:equalize_allies", "cada jugador baraja aliados hasta controlar la misma cantidad"],
	["each_discard", "cada jugador descarta (?<n>" + NUM + ") cartas?(?: de su mano)?"],
	["each_hand_exile", "cada jugador destierra (?<n>" + NUM + ") cartas? de su mano"],
	# Cementerios: "Baraja y/o Destierra hasta N cartas de los Cementerios" y sus formas de un solo
	# verbo.
	["cemetery_both", "(?:baraja|barajar) y/o (?:destierra|desterrar) (?:hasta )?(?<n>" + NUM + ") cartas? de los cementerios"],
	# "de un Cementerio" (Carro Szgany, shoki): todas del mismo Cementerio.
	# Sin "hasta" (suzaku: "Desterrar dos cartas de un Cementerio") igual se eligen hasta N: un
	# Cementerio con menos no impide resolverlo.
	["cemetery_banish", "(?:destierra|desterrar) (?:hasta )?(?<n>" + NUM + ") cartas? de (?:los cementerios|(?<one>un cementerio))"],
	["cemetery_shuffle", "(?:baraja|barajar) hasta (?<n>" + NUM + ") cartas? de (?:los cementerios|(?<one>un cementerio))"],
	# "Genera un Oro (por el turno)" — sin restricción ("para jugar ..." queda
	# sin consumir y el bloque no compila).
	["gold", "genera(?:r)? (?<n>" + NUM + ") oros?(?: por el turno)?(?: para jugar (?<for>aliados|un aliado|armas|un arma|talismanes|un talisman|totems?|un totem))?"],
	# "Agrupa un Oro": del Oro Pagado a la Reserva.
	["regroup_gold", "agrupa(?:r)? (?<n>" + NUM + ") oros?"],
	# "Agrupa dos cartas" (iga ryu): Oros Pagados y/o Aliados de Línea de Ataque (DAR 5.1).
	["regroup_cards", "agrupa(?:r)? (?<n>" + NUM + ") cartas?"],
	# "Un Aliado gana Furia, Imbloqueable, 3 de Fuerza y hace daño al Destierro
	# por el turno" / "Hasta dos Aliados pierden 1 de Fuerza permanentemente".
	# Duración sin escribir (regla del usuario): la Fuerza es por el turno, las
	# keywords son permanentes.
	# "Tus (demás) Aliados ganan 1 de Fuerza permanentemente" / "Los Aliados oponentes pierden 1 de
	# Fuerza": todos los de un lado, sin elegir.
	# "Anula un Talisman oponente" / "Cancela la habilidad de una carta" — sobre la Pila real.
	# "Cancelar una habilidad" / "Anular una carta o cancelar una habilidad" (huitzilin, rafael, espíritu
	# desafiante): cualquier habilidad en la Pila.
	["annul_any", "(?<both>anula(?:r)? una carta o )?cancela(?:r)? una habilidad"],
	["annul", "(?<v>anula(?:r)? o cancela(?:r)? la habilidad de|anula(?:r)?|cancela(?:r)? la habilidad de) (?:(?<any>una carta)|(?:un|una) " \
		+ "(?<kind>aliado|talisman|totem|arma)(?: o (?:un )?(?<kind2>aliado|talisman|totem|arma))?)(?<opp> oponente)?" \
		+ ",?(?: de coste (?<val>" + NUM + ") o menos)?"],
	# "Una carta en juego aumenta o reduce su coste en un Oro" (Titán Abismal): se elige la carta y el
	# sentido; permanente (no es Fuerza).
	["cost_shift", "(?<det>un|una) (?<kind>carta|aliado|totem|arma)(?<opp> oponente)?(?: en juego)? aumenta o reduce su coste" \
		+ " en (?<n>" + NUM + ") oros?"],
	["talisman_fizzle", "(?:hacer que )?el (?:proximo|siguiente) talisman que juegue tu oponente este turno se (?:resuelva|resuelve) sin efecto"],
	# "Un Aliado gana Indestructible, Indesterrable o "No puede ser Barajado", hasta tu próximo turno"
	# (Sarcófago Impío): elige UNA. Antes que "buff", que se quedaría con la lista hasta la "o".
	# "Un Aliado o Tótem gana Indestructible o Indesterrable, mientras esté en juego" (Mina Murray):
	# "mientras esté en juego" = permanente (lo pierde al salir, como todo).
	["grant_choice", "(?<det>un|una) aliado(?<tot> o totem)?(?<opp> oponente)?(?: en juego)?" + STAT_FILTER + " gana (?<opts>" + CHOICE_ITEM \
		+ "(?:, " + CHOICE_ITEM + ")* o " + CHOICE_ITEM + "),?(?<dur> hasta tu proximo turno| por el turno| mientras este en juego)?"],
	["mass_buff", "(?:tus (?<oth>demas )?aliados(?: que controlas)?|los aliados (?<opp>oponentes?))(?: en juego)?" \
		+ " (?<v>ganan|pierden) (?<list>" + GRANT_ITEM + "(?:(?:, y |, | y |,? e )" + GRANT_ITEM + ")*)" \
		+ "(?<perm> permanentemente)?(?<turn> por el turno| este turno)?"],
	# "Hasta dos Aliados tienen Fuerza 0 por el turno" / "Un Aliado de coste 2 o menos tiene Fuerza 0
	# hasta tu próximo turno" / "Un Aliado tiene Fuerza 0 o duplica su Fuerza por el turno" (se elige).
	# Sin duración escrita: por el turno (es Fuerza).
	["set_strength", "(?<det>(?:hasta )?" + NUM + ") (?<kind>aliados?)(?: (?<race>" + RACE + "))?(?<opp> oponentes?)?(?: en juego)?" + STAT_FILTER \
		+ " (?:tiene|tienen) fuerza (?<sv>\\d+)(?<dbl> o duplica su fuerza)?" \
		+ "(?<dur> por el turno| este turno| hasta tu proximo turno| hasta la fase final)?"],
	# "Un Aliado hace el doble de daño este turno" / "Un Aliado no hace daño de combate este turno",
	# sin "gana": mismo paso buff (las metas de BattleManager).
	["combat_flag", "(?<det>(?:hasta )?" + NUM + ") (?<kind>aliados?)(?: (?<race>" + RACE + "))?(?<opp> oponentes?)?(?: en juego)?" + STAT_FILTER \
		+ " (?<what>ha(?:ce|ga) (?:el )?doble (?:de )?dano(?: de combate)?|no ha(?:ce|ga) dano de combate" \
		+ "|no (?:puede|pueda) bloquear(?: ni hacer dano(?: de combate)?)?)(?: este turno| por el turno)?"],
	# "Un Aliado de coste 2 o menos gana..." / "Un Aliado gana o pierde 2 de Fuerza" (se elige).
	["buff", "(?<det>(?:hasta )?" + NUM + ") (?<kind>aliados?)(?: (?<race>" + RACE + "))?(?<opp> oponentes?)?(?: en juego)?" + STAT_FILTER \
		+ " (?<v>gana o pierde|ganan o pierden|gana|ganan|pierde|pierden) (?<list>" + GRANT_ITEM + "(?:(?:, y |, | y |,? e )" + GRANT_ITEM + ")*)" \
		+ "(?<perm> permanentemente)?(?<turn> por el turno| este turno| hasta la fase final)?" \
		+ "(?<exile2> y su dano es enviado al destierro)?"],  # juan jose carrera
	# "Una carta pierda su habilidad por el turno" (londres): sin duración, permanente (regla del
	# usuario: lo que no es Fuerza dura para siempre). "hasta tu próximo turno" no se compila.
	["silence", TARGET_RX + " (?:pierde|pierden|pierda|pierdan) su habilidad(?<dur> por el turno| este turno| hasta tu proximo turno)?"],
	# Barajar/Desterrar sin zona explícita = en juego (ver
	# DSR_ShuffleDrawCombos.try_execute_draw_and_shuffle_opponent_card_pattern()); por eso se rechaza
	# si sigue "de tu/los...".
	# (?![a-z]): sin cortar una palabra ("hasta cinco carta|s de tu Cementerio").
	["target", "(?<verb>destruye|destruir|destierra|desterrar|baraja|barajar) " + TARGET_RX + "(?![a-z])(?! de (?:tu|los|un|su) )"],
]

## Piezas que EffectInterpreter sabe ejecutar HOY. Viven aquí (y no en el
## intérprete) para que el auditor headless las consulte sin cargar
## autoloads. El compilador puede entender más de lo que se ejecuta (p.ej.
## "bounce"): esos planes se dejan a la cadena de patrones vieja.
const EXECUTABLE_OPS := ["each", "opp", "special", "repeat", "castle_look", "draw", "draw_to_match", "mill", "discard", "shuffle_from_hand", "search", "target", "mass", "choice",
	"shuffle_from_cemetery", "self", "hand_exile", "keep_shuffle", "rule", "if", "cemetery_cleanup", "gold", "regroup_gold", "buff", "mass_buff", "reveal_until", "reveal_top", "pay", "hand_peek", "annul", "talisman_fizzle",
	"regroup_cards", "gold_to_paid", "deck_to_hand", "no_damage", "play_from", "peek_hand", "show_hand", "cost", "castle_exile", "cancel_attack", "self_raise", "mill_x", "opp_gold_to_paid", "revive_blank", "self_buff_per"]
const EXECUTABLE_VERBS := ["destroy", "banish", "shuffle", "silence", "cost_shift"]

static var _compiled_atoms: Array = []
static var _connector_rx: RegEx = null


static func compile_clause(text: String) -> Dictionary:
	"""Compila el bloque de texto de una habilidad. Ver el docstring de la
	clase para el formato del plan."""
	var looked := _compile_with_castle_look(text)
	if not looked.is_empty():
		return looked
	var plan := {"ok": false, "optional": false, "activated": false, "steps": [], "unparsed": ""}
	var norm := normalize(text)
	if norm.is_empty():
		plan.unparsed = "(vacío)"
		return plan

	var steps: Array = []
	var sentences := _split_sentences(norm)
	var skip_rx := RegEx.new()
	skip_rx.compile(LEADING_SKIP_RX)
	while not sentences.is_empty() and skip_rx.search(sentences[0]) != null:
		sentences.remove_at(0)
	sentences = sentences.filter(func(s): return not _is_rule_sentence(s))
	# "Puedes pagar un Oro para subirlo de tu Cementerio a tu mano. Destruye..." (voces de hielo): la
	# primera es una habilidad desde el Cementerio, no parte del efecto que sigue. Sola sí se compila
	# (es el effect_text de esa activada).
	if sentences.size() > 1 and _is_cemetery_self_ability(sentences[0]):
		sentences.remove_at(0)
	sentences = _fold_choose_one(sentences)
	if sentences.is_empty():
		plan.unparsed = norm
		return plan
	var replace_rx := RegEx.new()
	replace_rx.compile(REPLACE_RX)
	for i in range(sentences.size()):
		var s: String = sentences[i]
		var then := false
		if i == 0:
			var stripped := _strip_trigger_prefix(s)
			plan.activated = _had_timing_prefix(s)
			s = stripped
		else:
			var rm := replace_rx.search(s)
			if rm:
				# Modifica el paso anterior (debe ser un objetivo en juego).
				if steps.is_empty() or steps[-1].op not in ["target", "mass"]:
					plan.unparsed = s
					return plan
				var v: String = rm.get_string("v")
				steps[-1]["replace_if_keyword"] = {"keyword": rm.get_string("kw"),
					"verb": "banish" if v.begins_with("destierr") else "destroy"}
				continue
			if _is_static(s):
				break  # el resto es texto estático pegado al bloque
			# Otra habilidad, activada, pegada al bloque (danza del cuchillo: "Destruye... . Puedes
			# Desterrarlo de tu Cementerio y pagar un Oro para..."; jinja: "... Una vez por turno, ...").
			if _starts_activated(s):
				break
			# Otra habilidad disparada pegada al bloque (simurg: "...a tu mano. Cuando sea Destruido, ...").
			# Salvo un efecto diferido del mismo Talismán (paso de la plaga: "...En tu Fase Final, tus Aliados
			# pierden su habilidad hasta tu próximo turno"): se agenda al resolver (rule:final_silence_allies).
			if i > 0 and _strip_trigger_prefix(s) != s and not (s in DELAYED_SENTENCES):
				break
			if s.begins_with("luego"):
				s = s.trim_prefix("luego").trim_prefix(",").strip_edges()
				then = true
		var may := false
		if s.begins_with("puedes "):
			s = s.substr(7)
			if i == 0:
				plan.optional = true
			else:
				may = true
		var sub := _compile_sentence(s)
		if not sub.ok:
			plan.unparsed = sub.unparsed
			return plan
		# "si controlas X, puedes ..." — el "puedes" quedó dentro de la condición.
		if sub.get("optional", false):
			if i == 0:
				plan.optional = true
			else:
				may = true
		# "Luego, puedes barajar una carta...": un "puedes" en medio del efecto deja elegir no hacerlo —
		# el objetivo/búsqueda pasa a "hasta".
		if may:
			for st in sub.steps:
				if st.op in ["target", "buff", "search"]:
					st["up_to"] = true
		if then and not sub.steps.is_empty():
			sub.steps[0]["then"] = true
		steps.append_array(sub.steps)

	plan.steps = steps
	plan.ok = not steps.is_empty()
	if not plan.ok:
		plan.unparsed = norm
	return plan


const _LOOK_RX := "(?:^|[\\s,])(mira(?:r|s)?\\s+(?:hasta\\s+)?(?:las\\s+)?(?:\\S+\\s+){0,2}cartas\\s+" \
	+ "(?:del\\s+(?:tope|fondo)\\s+|de\\s+la\\s+parte\\s+superior\\s+)?de\\s+(?:tu|un)\\s+castillo)"


static func _compile_with_castle_look(text: String) -> Dictionary:
	"""Efecto antes de "mira N cartas de tu Castillo..." (camilo henriquez: "Destierra hasta una carta
	de coste 2 o menos y mira las primeras cuatro cartas de tu Castillo. Pon dos en tu Destierro y el
	resto en tu mano"; Carro Szgany). Lo de antes se compila como siempre y lo de "mira" hasta el fin
	del párrafo es un paso castle_look que ejecuta CastleLook.try_execute_text() con el texto
	original. Sin efecto previo devuelve {}: lo resuelve CastleLook solo, más adelante en la cadena.
	Si CastleLook entiende el "mira..." lo verifica EffectInterpreter.try_execute() (dry_run):
	CastleLook usa autoloads y no carga en los tests de consola. Otro párrafo detrás se agrega si
	compila; si no, es otra habilidad o texto estático (camilo henriquez: "Las cartas de coste 0
	pierden su habilidad...") y se ignora."""
	var flat := text.replace("\r", "")
	var m := RegEx.create_from_string(_LOOK_RX).search(flat.to_lower().replace("\n", " "))
	if m == null:
		return {}
	var start := m.get_start(1)
	var prefix := RegEx.create_from_string("(?:,|\\s+y)?\\s*$").sub(flat.substr(0, start), "")
	var para_end := flat.find("\n", start)
	var look_text := flat.substr(start, (para_end - start) if para_end >= 0 else -1).strip_edges()
	var after := flat.substr(para_end + 1).strip_edges() if para_end >= 0 else ""
	var pre_norm := normalize(prefix)
	if pre_norm.is_empty() or _strip_trigger_prefix(pre_norm).strip_edges().is_empty() or "\n" in prefix:
		return {}
	var plan := compile_clause(prefix)
	if not plan.ok:
		return {}
	plan.steps.append({"op": "castle_look", "text": look_text})
	if not after.is_empty():
		var tail := compile_clause(after)
		if tail.ok:
			plan.steps.append_array(tail.steps)
	return plan


static func is_executable(steps: Array) -> bool:
	"""true si EffectInterpreter sabe ejecutar todos los pasos (ver
	EXECUTABLE_OPS/EXECUTABLE_VERBS)."""
	for st in steps:
		if st.op not in EXECUTABLE_OPS:
			return false
		if st.op in ["target", "mass"] and st.verb not in EXECUTABLE_VERBS:
			return false
		if st.op == "choice":
			for option in st.options:
				if not is_executable(option):
					return false
		if st.op in ["if", "repeat"] and not is_executable(st.steps):
			return false
	return true


static func normalize(text: String) -> String:
	"""Minúsculas, sin tildes ni ñ, espacios colapsados, sin punto
	final. Los saltos de línea de la API valen como fin de oración."""
	var t: String = preload("res://scripts/core/cards/CardText.gd").fold(text.replace("\r", "").replace("\n", ". ")).strip_edges()
	t = t.replace(" de de ", " de ")  # erratas impresas ("del tope de de tu Castillo", fat-frumos)
	var dots := RegEx.new()
	dots.compile("(?:\\.\\s*){2,}")
	t = dots.sub(t, ". ", true).strip_edges()
	while t.ends_with("."):
		t = t.substr(0, t.length() - 1).strip_edges()
	return t


static func parse_amount(word: String) -> int:
	word = word.strip_edges()
	if word.is_valid_int():
		return int(word)
	return NUMBER_WORDS.get(word, 1)


static func _split_sentences(t: String) -> Array:
	var out: Array = []
	for raw in t.split(". "):
		var s: String = raw.strip_edges().trim_suffix(".").strip_edges()
		if s.is_empty():
			continue
		# Una habilidad entre comillas con varias oraciones ("gana la habilidad ¨Imbloqueable. Una vez por turno, ...¨",
		# gran escape) es una sola oración.
		if not out.is_empty() and _open_quote(out.back()):
			out[out.size() - 1] = out.back() + ". " + s
			continue
		# "...hasta mostrar un Aliado de coste 2. Ponlo en tu mano y Baraja el resto" (mochizuki
		# chiyome): el destino de reveal_until en la oración siguiente va con la anterior.
		# También el reparto ("...hasta mostrar cuatro Aliados. Pon uno en tu mano, tres en tu Cementerio",
		# nace la furia) y "Muestra cuatro cartas del tope de tu Castillo. Pon dos cartas de ahí" (warlock).
		if not out.is_empty() and ("hasta mostrar" in out.back() or "hasta que muestres" in out.back()) \
				and RegEx.create_from_string("^(?:(?:ponlos|ponlas|ponlo|ponla|pon esa carta|pon esas cartas) en tu mano" \
					+ "|pon (?:un|una|uno|dos|tres|el otro|la otra)\\b|juega (?:uno|una)\\b)").search(s) != null:
			out[out.size() - 1] = out.back() + " y " + s
			continue
		# "Busca en tu Castillo tres Aliados de diferente nombre. Pon uno en tu mano, dos en tu Cementerio" (pulso
		# kaiju, avaricia) / "...con distinto nombre. Conviértelas en Armas..." (oda nobunaga): el destino de la
		# búsqueda va en la oración siguiente.
		if not out.is_empty() and RegEx.create_from_string("(?:^|, )busca en ").search(out.back()) != null \
				and not (" pon" in out.back() or "ponl" in out.back()) \
				and RegEx.create_from_string("^(?:pon (?!el |la )|conviertelas en armas)").search(s) != null:
			out[out.size() - 1] = out.back() + ", " + s
			continue
		if not out.is_empty() and RegEx.create_from_string("(?:^|, )(?:puedes )?(?:muestra|mostrar) (?:las primeras [a-z0-9]+ cartas de tu castillo" \
					+ "|[a-z0-9]+ cartas del tope de tu castillo)$").search(out.back()) != null \
				and RegEx.create_from_string("^(?:pon|juega|elige) ").search(s) != null:
			out[out.size() - 1] = out.back() + " y " + s
			continue
		out.append(s)
	return out


static func _open_quote(s: String) -> bool:
	var n := 0
	for ch in ["\"", "“", "”", "¨"]:
		n += s.count(ch)
	return n % 2 == 1


static func _strip_trigger_prefix(s: String) -> String:
	"""Quita el disparador y, en las activadas, el momento/frecuencia ("En tu
	Vigilia, una vez por turno, ..."), que pueden venir encadenados."""
	var changed := true
	while changed:
		changed = false
		for p in TRIGGER_PREFIXES + TIMING_PREFIXES:
			if s.begins_with(p + ", "):
				s = s.substr(p.length() + 2)
				changed = true
				break
			# Sin coma: "Cuando ataca tus Aliados ganan..." (moby dick), "Cuando entra en juego baraja hasta
			# cuatro cartas..." (libro de las obras). Solo si lo que sigue empieza un efecto: "cuando entra
			# en juego desde tu Cementerio" es parte del disparador.
			if s.begins_with(p + " "):
				var after := s.substr(p.length() + 1)
				for w in NO_COMMA_EFFECT_STARTS:
					if after.begins_with(w + " "):
						s = after
						changed = true
						break
				if changed:
					break
	return s


## Primeras palabras de un efecto tras un disparador sin coma (_strip_trigger_prefix()).
const NO_COMMA_EFFECT_STARTS := ["tus", "los", "baraja", "destierra", "destruye", "roba", "busca", "mira",
	"muestra", "genera", "pon", "sube", "descarta", "bota", "agrupa", "anula", "cancela", "convierte", "juega",
	"puedes", "tu oponente", "cada jugador", "un aliado", "una carta", "gana", "elige"]


static func _had_timing_prefix(s: String) -> bool:
	"""¿El texto empieza (tras el disparador) con momento/frecuencia de
	habilidad activada? Un disparador en la cadena ("Una vez por turno, cuando juegues un Arma, puedes...")
	la hace disparada: su "puedes" se sigue preguntando."""
	var rest := s
	var timing := false
	var changed := true
	while changed:
		changed = false
		for p in TRIGGER_PREFIXES + TIMING_PREFIXES:
			if rest.begins_with(p + ", ") or rest.begins_with(p + " "):
				if p in TRIGGER_PREFIXES:
					return false
				if rest.begins_with(p + ", "):
					timing = true
					rest = rest.substr(p.length() + 2)
					changed = true
				break
	return timing


static func _is_static(s: String) -> bool:
	for p in STATIC_STARTS:
		if s.begins_with(p):
			return true
	return false


static var _rule_rxs: Array = []
static var _control_rx: RegEx = null


static func _control_condition(s: String) -> Dictionary:
	"""{cond, rest} si la oración empieza con "si controlas ..., ". La
	condición: {kind: "controls", count, type, race, other, min_strength,
	attack_line}. {} si no calza o es ambigua ("si controlas o jugaste...")."""
	if _control_rx == null:
		_control_rx = RegEx.new()
		_control_rx.compile(CONTROL_COND_RX)
	var m := _control_rx.search(s)
	if m == null and s.begins_with("si controlas ") and not "," in s:
		# "Si controlas Armas tus Aliados ganan..." (prendick), sin coma.
		for subject in [" tus aliados ", " los aliados "]:
			if subject in s:
				m = _control_rx.search(s.replace(subject, "," + subject))
				break
	if m == null:
		return {}
	var words: PackedStringArray = m.get_string("what").split(" ")
	# "Si controlas una Fonda, ..." (pie de cueca): una carta por su nombre.
	if words[0] in ["un", "una"] and words.size() == 2 and not TYPE_WORDS.has(words[1]) and m.get_string("n").is_empty():
		return {"rest": m.get_string("rest"), "cond": {"kind": "controls", "count": 1, "type": "", "race": "",
			"name": words[1], "other": not m.get_string("other").is_empty(), "min_strength": -1, "attack_line": false}}
	if words[0] in ["o", "menos", "mas", "un", "una"]:
		return {}
	var type_word: String = TYPE_WORDS.get(words[0], "?")
	var race := ""
	if type_word == "?":
		type_word = "aliado"  # "si controlas otro Jinete" / "Dragones": Aliados de esa raza
		race = words[0]
		if words.size() > 1:
			return {}
	elif words.size() > 1:
		race = words[1]
	elif type_word == "":
		type_word = ""  # "cartas": cualquier tipo
	return {"rest": m.get_string("rest"), "cond": {"kind": "controls",
		"count": parse_amount(m.get_string("n")) if not m.get_string("n").is_empty() else 1,
		"type": type_word, "race": race, "other": not m.get_string("other").is_empty(),
		"min_strength": int(m.get_string("sv")) if not m.get_string("sv").is_empty() else -1,
		"attack_line": not m.get_string("atk").is_empty()}}


static func _is_rule_sentence(s: String) -> bool:
	if _rule_rxs.is_empty():
		for pat in RULE_SKIP_RX:
			var r := RegEx.new()
			r.compile(pat)
			_rule_rxs.append(r)
	var core := _strip_trigger_prefix(s)
	for r in _rule_rxs:
		if r.search(core) != null:
			return true
	return false


static func _fold_choose_one(sentences: Array) -> Array:
	"""Junta "Elige un efecto: - A. - B." en una sola oración marcada
	"\u0001choose\u0001A\u0001B" que _compile_sentence() convierte en una
	elección. Las viñetas pueden venir en la misma oración (" - ") o como
	oraciones siguientes que empiezan con "-"."""
	var rx := RegEx.new()
	rx.compile(CHOOSE_ONE_RX)
	var out: Array = []
	var i := 0
	while i < sentences.size():
		var s: String = sentences[i]
		var prefix := ""
		var core := _strip_trigger_prefix(s)
		if core != s:
			prefix = s.substr(0, s.length() - core.length())
		var m := rx.search(core)
		if m == null:
			# "Tu oponente muestra su mano y tú elige un efecto: - A. - B." (flechero): lo de antes es su propia
			# oración.
			m = RegEx.create_from_string("^(?<pre>.+?)(?:,| y) (?:tu )?elige (?:un|uno) efecto:?\\s*(?<rest>.*)$").search(core)
			if m == null:
				out.append(s)
				i += 1
				continue
			out.append(prefix + m.get_string("pre"))
			prefix = ""
		var options: Array = []
		for part in m.get_string("rest").split(" - "):
			var p: String = part.strip_edges().trim_prefix("-").strip_edges()
			if not p.is_empty():
				options.append(p)
		i += 1
		while i < sentences.size() and str(sentences[i]).begins_with("-"):
			for part in str(sentences[i]).split(" - "):
				var p2: String = part.strip_edges().trim_prefix("-").strip_edges()
				if not p2.is_empty():
					options.append(p2)
			i += 1
			# "- Nombra una carta. Las cartas con ese nombre..." (flechero): la oración siguiente es de la opción.
			if not options.is_empty() and str(options.back()).ends_with("nombra una carta") and i < sentences.size() \
					and str(sentences[i]).begins_with("las cartas con ese nombre"):
				options[options.size() - 1] = str(options.back()) + ", " + str(sentences[i])
				i += 1
		out.append(prefix + "\u0001choose\u0001" + "\u0001".join(options))
	return out


static func _compile_sentence(s: String) -> Dictionary:
	"""Una oración: primero intenta la secuencia completa; si no, una
	elección 'A, o B' de nivel superior. Una condición inicial ('si X, ...')
	envuelve toda la oración en un paso 'if'."""
	if s.begins_with("\u0001choose\u0001"):
		var options: Array = []
		for opt in s.substr(8).split("\u0001"):
			if opt.is_empty():
				continue
			var sub := _compile_sentence(opt)
			if not sub.ok:
				return sub
			if sub.steps.size() == 1 and sub.steps[0].op == "choice":
				options.append_array(sub.steps[0].options)  # "- Anula o Destierra un Tótem": una opción más
			else:
				options.append(sub.steps)
		if options.size() < 2:
			return {"ok": false, "steps": [], "unparsed": s}
		return {"ok": true, "steps": [{"op": "choice", "options": options}], "unparsed": ""}
	var costs := _parse_costs(s)
	if not costs.is_empty():
		var paid := _compile_sentence(costs.rest)
		if not paid.ok:
			return paid
		return {"ok": true, "steps": costs.steps + paid.steps, "unparsed": ""}
	# "Hacer que un Aliado gane Furia" / "elegir un Aliado oponente para que pierda 2 de Fuerza": el
	# subjuntivo pasa a indicativo y se compila como "un Aliado gana Furia".
	if s.begins_with("hacer que ") and not s.begins_with("hacer que el proximo talisman"):
		return _compile_sentence(_indicative(s.substr(10)))
	var choose_m := RegEx.create_from_string("^elegir (?<obj>(?:un|una) [a-z ]+?) para que (?<rest>.+)$").search(s)
	if choose_m:
		return _compile_sentence(choose_m.get_string("obj") + " " + _indicative(choose_m.get_string("rest")))
	var ctl := _control_condition(s)
	if not ctl.is_empty():
		var rest: String = ctl.rest
		var optional := rest.begins_with("puedes ")
		if optional:
			rest = rest.substr(7)
		var cond_inner := _compile_sentence(rest)
		if not cond_inner.ok:
			return cond_inner
		return {"ok": true, "optional": optional,
			"steps": [{"op": "if", "cond": ctl.cond, "steps": cond_inner.steps}], "unparsed": ""}
	# "Si buscaste un Dinosaurio, adicionalmente busca..." (monstruo de la laguna, ignacio de la carrera):
	# mira la raza/nombre de lo que encontró la búsqueda anterior del mismo efecto.
	var searched_m := RegEx.create_from_string("^si buscaste (?:un |una )?(?<w>[a-z]+), (?:adicionalmente,? )?(?<rest>.+)$").search(s)
	if searched_m:
		var s_inner := _compile_sentence(searched_m.get_string("rest"))
		if not s_inner.ok:
			return s_inner
		return {"ok": true, "optional": s_inner.get("optional", false),
			"steps": [{"op": "if", "cond": {"kind": "searched", "word": searched_m.get_string("w")}, "steps": s_inner.steps}], "unparsed": ""}
	# "Si tu oponente Barajó dos o menos Aliados de esta forma, ... y si tú Barajaste dos o más Aliados de esta
	# forma, ..." (visión de noé): cuenta lo que movió el paso "cada jugador" anterior.
	var moved_m := RegEx.create_from_string("^si (?<who>tu oponente|tu) (?:barajo|barajaste) (?<n>" + NUM + ") o (?<cmp>menos|mas) (?:aliados|cartas) de esta forma, (?<rest>.+)$").search(s)
	if moved_m:
		var body: String = moved_m.get_string("rest")
		var tail := ""
		var cut_at := body.find(" y si ")
		if cut_at > 0:
			tail = body.substr(cut_at + 3)
			body = body.substr(0, cut_at)
		var m_inner := _compile_sentence(body)
		if not m_inner.ok:
			return m_inner
		var m_steps: Array = [{"op": "if", "cond": {"kind": "moved", "who": "opponent" if moved_m.get_string("who") == "tu oponente" else "self",
			"n": parse_amount(moved_m.get_string("n")), "cmp": moved_m.get_string("cmp")}, "steps": m_inner.steps}]
		if not tail.is_empty():
			var m_tail := _compile_sentence(tail)
			if not m_tail.ok:
				return m_tail
			m_steps.append_array(m_tail.steps)
		return {"ok": true, "steps": m_steps, "unparsed": ""}
	# "Por cada Aliado que controles, pon una carta..." (estirpe maldita) / "Por cada carta Destruida, Baraja hasta dos
	# cartas de los Cementerios" (rey del camino) / "Por cada Talismán Botado de esta forma, busca... o paga..." (forma de
	# araña): la cantidad multiplica los pasos que la admiten; si no, se repiten enteros (op "repeat").
	var per_m := RegEx.create_from_string("^por cada (?<q>.+?), (?<rest>.+)$").search(s)
	if per_m:
		var per_q := _parse_quantity(per_m.get_string("q"))
		if not per_q.is_empty() and per_q.len == per_m.get_string("q").length():
			var per_inner := _compile_sentence(per_m.get_string("rest"))
			if not per_inner.ok:
				return per_inner
			var simple: bool = per_inner.steps.all(func(st): return QTY_KEYS.has(st.op) and not st.has("qty") and not st.has("per"))
			if simple:
				for st in per_inner.steps:
					st["qty"] = {"mode": "per", "q": per_q.q, "key": QTY_KEYS[st.op]}
				return per_inner
			return {"ok": true, "steps": [{"op": "repeat", "q": per_q.q, "steps": per_inner.steps}], "unparsed": ""}
	# "Un Aliado es Indestructible por el turno" (luis carrera) = "gana Indestructible".
	var is_kw := RegEx.create_from_string("^((?:un|una) aliado(?: que controles)?) es (furia|imbloqueable|indestructible|indesterrable)\\b").search(s)
	if is_kw:
		return _compile_sentence(is_kw.get_string(1) + " gana " + is_kw.get_string(2) + s.substr(is_kw.get_end()))
	# "Anula o Destierra un Tótem de coste 3 o menos" (jurado descontento): una elección entre los dos verbos.
	var ad_m := RegEx.create_from_string("^anula o destierra (?<obj>.+)$").search(s)
	if ad_m:
		return _compile_sentence("anula %s, o destierra %s" % [ad_m.get_string("obj"), ad_m.get_string("obj")])
	for c in CONDITIONS:
		if s.begins_with(c[1]):
			var inner := _compile_sentence(s.substr(c[1].length()))
			if not inner.ok:
				return inner
			return {"ok": true, "steps": [{"op": "if", "cond": c[0], "steps": inner.steps}], "unparsed": ""}
	var seq := _compile_sequence(s)
	if seq.ok:
		return seq
	var cut := s.rfind(", o ")
	if cut > 0:
		var a := _compile_sequence(s.substr(0, cut))
		var b := _compile_sequence(s.substr(cut + 4))
		if a.ok and b.ok:
			return {"ok": true, "steps": [{"op": "choice", "options": [a.steps, b.steps]}], "unparsed": ""}
	# "Baraja una carta de coste 3 o menos o Anula un Talismán oponente": sin coma. Cada " o " (la de
	# "3 o menos" no parte nada entero).
	var at := s.find(" o ")
	while at > 0:
		var left := _compile_sequence(s.substr(0, at))
		if left.ok:
			var right := _compile_sequence(s.substr(at + 3))
			if right.ok:
				return {"ok": true, "steps": [{"op": "choice", "options": [left.steps, right.steps]}], "unparsed": ""}
		at = s.find(" o ", at + 3)
	return seq


static func _is_cemetery_self_ability(s: String) -> bool:
	var core := _strip_trigger_prefix(s)
	return core.begins_with("puedes ") and not _parse_costs(core.substr(7)).is_empty() \
		and RegEx.create_from_string(SELF_RAISE_RX).search(core) != null


static func _starts_activated(s: String) -> bool:
	"""¿La oración es una habilidad activada propia? "Una vez por turno, ..." / "En tu Vigilia, ..." o
	"Puedes <coste> para ..." (Desterrarlo, Descartar una carta, pagar un Oro...)."""
	for p in TIMING_PREFIXES:
		if s.begins_with(p + ", "):
			return true
	# Cualquier "Puedes X para Y" es su propia activada (X = coste), aunque el coste no se entienda.
	return s.begins_with("puedes ") and " para " in s


static var _cost_rxs: Array = []


static func _parse_costs(s: String) -> Dictionary:
	"""{steps, rest} si la oración empieza con uno o más costes (COST_PIECES, unidos por " y " o ", ")
	seguidos de " para (que) ": rest es el efecto (en indicativo tras "para que"). {} si no."""
	if _cost_rxs.is_empty():
		for piece in COST_PIECES:
			_cost_rxs.append({"name": piece[0], "rx": RegEx.create_from_string("^(?:" + piece[1] + ")")})
	var rest := s
	var steps: Array = []
	while true:
		var hit := false
		for piece in _cost_rxs:
			var m: RegExMatch = piece.rx.search(rest)
			if m == null:
				continue
			steps.append(_cost_step(piece.name, m))
			rest = rest.substr(m.get_end())
			hit = true
			break
		if not hit:
			return {}
		if rest.begins_with(" y "):
			rest = rest.substr(3)
		elif rest.begins_with(", "):
			rest = rest.substr(2)
		elif rest.begins_with(" para que "):
			return {"steps": steps, "rest": _indicative(rest.substr(10))}
		elif rest.begins_with(" para "):
			return {"steps": steps, "rest": rest.substr(6)}
		else:
			return {}
	return {}


static func _cost_step(kind: String, m: RegExMatch) -> Dictionary:
	match kind:
		"gold":
			return {"op": "pay", "amount": parse_amount(m.get_string("n"))}
		"discard":
			if not m.get_string("dn").is_empty():
				return {"op": "cost", "kind": "discard", "amount": parse_amount(m.get_string("dn")), "types": []}
			return {"op": "cost", "kind": "discard", "amount": 1, "types": _type_list(m.get_string("types"))}
		"mill", "shuffle_hand":
			return {"op": "cost", "kind": kind, "amount": parse_amount(m.get_string("n"))}
		"sacrifice_any":
			var sv: String = m.get_string("sv")
			return {"op": "cost", "kind": "sacrifice_any", "amount": parse_amount(m.get_string("sn")),
				"types": _type_list(m.get_string("types")),
				"verb": "destroy" if sv == "destruir" else ("banish" if sv == "desterrar" else "shuffle"),
				"cost_val": int(m.get_string("cval")) if not m.get_string("cval").is_empty() else -1,
				"cost_cmp": m.get_string("ccmp")}
		"banish_cemetery":
			return {"op": "cost", "kind": "banish_cemetery", "amount": parse_amount(m.get_string("cn"))}
		"banish_hand":
			if not m.get_string("bn").is_empty():
				return {"op": "cost", "kind": "banish_hand", "amount": parse_amount(m.get_string("bn")), "types": []}
			return {"op": "cost", "kind": "banish_hand", "amount": 1, "types": _type_list(m.get_string("types"))}
		"reveal":
			return {"op": "cost", "kind": "reveal", "amount": 1, "types": _type_list(m.get_string("types")),
				"race": m.get_string("race")}
	return {"op": "cost", "kind": kind, "amount": 1}


static func _indicative(s: String) -> String:
	"""Pasa a indicativo el primer verbo en subjuntivo (SUBJUNCTIVE)."""
	var words := s.split(" ")
	for i in range(words.size()):
		if SUBJUNCTIVE.has(words[i]):
			words[i] = SUBJUNCTIVE[words[i]]
			# "gane o pierda 2 de Fuerza": los dos verbos de la alternativa.
			if i + 2 < words.size() and words[i + 1] == "o" and SUBJUNCTIVE.has(words[i + 2]):
				words[i + 2] = SUBJUNCTIVE[words[i + 2]]
			break
	return " ".join(words)


static func _compile_sequence(s: String) -> Dictionary:
	"""Consume átomos de izquierda a derecha, unidos por ', ', ' y ',
	', y luego, '. Falla si queda cualquier resto sin consumir."""
	if _connector_rx == null:
		_connector_rx = RegEx.new()
		_connector_rx.compile("^(?:,\\s*)?(?:y luego,?\\s*|luego,?\\s*|y\\s+)?")
	var steps: Array = []
	var rest := s.strip_edges()
	var next_is_then := false
	while not rest.is_empty():
		# "Robar dos cartas y hacer que un Aliado gane 2 de Fuerza" (hem hem real): a indicativo.
		if rest.begins_with("hacer que ") and not rest.begins_with("hacer que el proximo talisman"):
			rest = _indicative(rest.substr(10))
		var step := {}
		var consumed := 0
		for atom in _get_atoms():
			var m: RegExMatch = atom.rx.search(rest)
			if m == null:
				continue
			step = _build(atom.name, m)
			if not step.is_empty():
				consumed = m.get_end()
				break
		# "Baraja hasta tantas cartas de tu Cementerio como Fuerza tenga este Aliado": si ningún átomo lo
		# entiende entero (mill_x sí entiende algunos), se compila como "hasta una carta" y el paso lleva la
		# cantidad a contar al resolver (qty).
		var set_qty := {}
		var tm: RegExMatch = null
		if step.is_empty():
			tm = RegEx.create_from_string("^(?<a>(?:(?!, | y ).)*?)\\btantas (?<b>(?:(?!, | y ).)*?) como (?<q>.+)$").search(rest)
		if tm:
			var tq := _parse_quantity(tm.get_string("q"))
			if not tq.is_empty():
				set_qty = tq.q
				rest = tm.get_string("a") + "una " + tm.get_string("b") + tm.get_string("q").substr(tq.len)
				for atom in _get_atoms():
					var m2: RegExMatch = atom.rx.search(rest)
					if m2 == null:
						continue
					step = _build(atom.name, m2)
					if not step.is_empty():
						consumed = m2.get_end()
						break
		if step.is_empty():
			return {"ok": false, "steps": [], "unparsed": rest}
		var expanded: Array = step.steps if step.op == "multi" else [step]  # "busca un Aliado y un Tótem"
		if next_is_then:
			expanded[0]["then"] = true
		steps.append_array(expanded)
		rest = rest.substr(consumed).strip_edges()
		# "Roba una carta por cada Aliado que controles", "tu oponente Bota dos cartas por cada Aliado Faerie".
		var per_qty := {}
		if rest.begins_with("por cada "):
			var pq := _parse_quantity(rest.substr(9))
			if pq.is_empty():
				return {"ok": false, "steps": [], "unparsed": rest}
			per_qty = pq.q
			rest = rest.substr(9 + pq.len).strip_edges()
			# "...por cada Aliado oponente de Fuerza 3 o menos y por cada Aliado Orco que controles" (orco alpino) /
			# "...por cada Aliado que controles y una adicional por cada Carrera que controles" (luis carrera): se suman.
			var more := RegEx.create_from_string("^y (?<extra>una adicional )?por cada ").search(rest)
			if more:
				var tail: String = rest.substr(more.get_end())
				var pq2 := _parse_quantity(tail)
				if pq2.is_empty() and not more.get_string("extra").is_empty():
					# Un nombre de carta: "por cada Carrera que controles".
					var nm2 := RegEx.create_from_string("^(?<nm>[a-z]+) que controles(?![a-z])").search(tail)
					if nm2 and not TYPE_WORDS.has(nm2.get_string("nm")):
						pq2 = {"q": {"kind": "named_count", "name": nm2.get_string("nm")}, "len": nm2.get_end()}
				if not pq2.is_empty():
					per_qty = {"kind": "sum", "parts": [per_qty, pq2.q]}
					rest = tail.substr(pq2.len).strip_edges()
		for q_pair in [[set_qty, "set"], [per_qty, "per"]]:
			if q_pair[0].is_empty():
				continue
			if expanded.size() != 1 or not QTY_KEYS.has(expanded[0].op) or expanded[0].has("per"):
				return {"ok": false, "steps": [], "unparsed": rest if not rest.is_empty() else s}
			expanded[0]["qty"] = {"mode": q_pair[1], "q": q_pair[0], "key": QTY_KEYS[expanded[0].op]}
		var c := _connector_rx.search(rest)
		next_is_then = c != null and "luego" in c.get_string()
		if c and c.get_end() > 0:
			rest = rest.substr(c.get_end()).strip_edges()
	return {"ok": not steps.is_empty(), "steps": steps, "unparsed": ""}


## Pasos que aceptan una cantidad variable y qué campo cambia (ver _parse_quantity()). Los objetivos en
## juego no: se eligen antes de resolver, con la cantidad impresa.
const QTY_KEYS := {"special": "amount", "draw": "amount", "mill": "amount", "discard": "amount", "cemetery_cleanup": "amount",
	"shuffle_from_cemetery": "amount", "shuffle_from_hand": "amount", "castle_exile": "amount", "buff": "amount"}
static var _qty_rxs: Array = []


static func _parse_quantity(t: String) -> Dictionary:
	"""{q, len}: la cantidad que empieza en 't' ("Aliados Titán controles", "Fuerza tenga este Aliado",
	"tipo de carta en tu Destierro", "Aliados haya en tu Cementerio y Destierro") y cuánto texto ocupa.
	{} si no se entiende. La cuenta la hace EffectInterpreter._quantity_value() al resolver."""
	if _qty_rxs.is_empty():
		for pair in [
			["moved", "cartas? barajadas? de esta forma"],
			# Lo que hizo un paso anterior del mismo efecto (EffectInterpreterEspeciales._quantity_value).
			["exiled", "(?<t>" + T1 + ") desterrad[oa]s? de esta forma"],
			["milled", "(?<t>" + T1 + ") botad[oa]s? de esta forma"],
			["destroyed", "cartas? destruidas?"],
			["paid_self", "oros? que hayas pagado por este aliado"],
			["totem_left", "totems? que haya salido de tu linea de apoyo este turno(?:, maximo (?<max>" + NUM + "))?"],
			["types", "tipos? de cartas? en tu destierro"],
			["zone", "(?<t>" + T1 + ")(?: (?<race>" + RACE + "))?(?: de coste (?<zcv>\\d+) o (?<zcc>menos|mas))? (?:haya |hayan )?en tu (?<z>cementerio|destierro)" \
				+ "(?: y (?:en )?(?:tu )?(?<z2>cementerio|destierro))?"],
			["stat", "(?<stat>fuerza impresa|fuerza|coste) tenga (?<of>este aliado|esta carta|un aliado que controles" \
				+ "|un aliado en juego|un aliado|una carta que controles|una carta en juego)(?![a-z])"],
			["play", "(?<t>" + T1 + ")(?: (?<race>" + RACE + "))?(?<opp> oponentes?)?(?: que no sean? (?<nt>" + T1 + "))?" \
				+ "(?: (?<kw>exhumar|furia|imbloqueable|indestructible))?(?<dc> de distinto coste)?" \
				+ "(?: de fuerza (?<sv>\\d+) o (?<sc>menos|mas))?(?: de coste (?<cv>\\d+) o (?<cc>menos|mas))?" \
				+ "(?: (?<w>que controles|controles|que controle tu oponente|controle tu oponente|controle un jugador|en juego" \
				+ "|en tu linea de defensa|atacantes?))?(?![a-z])"],
		]:
			_qty_rxs.append({"kind": pair[0], "rx": RegEx.create_from_string("^" + pair[1])})
	for pat in _qty_rxs:
		var m: RegExMatch = pat.rx.search(t)
		if m == null:
			continue
		var q := {}
		match pat.kind:
			"moved":
				q = {"kind": "moved"}  # nahualismo: lo que barajó el paso "cada jugador" anterior
			"exiled", "milled":  # takiyasha hime / forma de araña: los datos que movió el paso anterior
				q = {"kind": "each_list", "key": "exiled" if pat.kind == "exiled" else "milled_cards", "types": _type_list(m.get_string("t"))}
			"destroyed":  # rey del camino
				q = {"kind": "each_count", "key": "destroyed"}
			"paid_self":  # nguruvilu (GoldManager: meta "gold_paid")
				q = {"kind": "paid_self"}
			"totem_left":  # vâlve albe (RuleState "totem_left_support")
				q = {"kind": "totem_left", "max": parse_amount(m.get_string("max")) if not m.get_string("max").is_empty() else -1}
			"types":
				q = {"kind": "distinct_types", "zones": ["destierro"]}
			"zone":
				var zs: Array = [m.get_string("z")]
				if not m.get_string("z2").is_empty():
					zs.append(m.get_string("z2"))
				q = {"kind": "zone_count", "zones": zs, "types": _type_list(m.get_string("t")), "race": m.get_string("race"),
					"cost_val": int(m.get_string("zcv")) if not m.get_string("zcv").is_empty() else -1, "cost_cmp": m.get_string("zcc")}
			"stat":
				q = {"kind": "stat", "stat": "coste" if m.get_string("stat") == "coste" else "fuerza",
					"printed": m.get_string("stat") == "fuerza impresa", "of": m.get_string("of")}
			"play":
				var w: String = m.get_string("w")
				if w.is_empty() and m.get_string("opp").is_empty():
					continue
				var who := "any"
				if w in ["que controles", "controles", "en tu linea de defensa"]:
					who = "self"
				elif not m.get_string("opp").is_empty() or "tu oponente" in w:
					who = "opponent"
				elif w == "controle un jugador":
					who = "choose"
				var nt: String = TYPE_WORDS.get(m.get_string("nt"), "")
				q = {"kind": "play_count", "who": who, "defense": w == "en tu linea de defensa", "attacking": w.begins_with("atacante"),
					"types": _type_list(m.get_string("t")), "race": m.get_string("race"), "types_not": [nt] if nt != "" else [],
					"keyword": m.get_string("kw"), "distinct_cost": not m.get_string("dc").is_empty(),
					"str_val": int(m.get_string("sv")) if not m.get_string("sv").is_empty() else -1, "str_cmp": m.get_string("sc"),
					"cost_val": int(m.get_string("cv")) if not m.get_string("cv").is_empty() else -1, "cost_cmp": m.get_string("cc")}
		if not q.is_empty():
			return {"q": q, "len": m.get_end()}
	return {}


static func _get_atoms() -> Array:
	if _compiled_atoms.is_empty():
		for a in ATOMS:
			var r := RegEx.new()
			var err := r.compile("^" + a[1])
			if err != OK:
				push_error("EffectCompiler: regex inválido en el átomo '%s'" % a[0])
				continue
			_compiled_atoms.append({"name": a[0], "rx": r})
	return _compiled_atoms


static func _build(atom_name: String, m: RegExMatch) -> Dictionary:
	"""Arma el paso de un átomo reconocido. Devuelve {} si el texto calzó
	pero el caso es ambiguo (que lo resuelva la cadena vieja)."""
	if atom_name.begins_with("rule:"):
		return {"op": "rule", "kind": atom_name.trim_prefix("rule:")}
	if atom_name.begins_with("each:") or atom_name.begins_with("opp:") or atom_name.begins_with("special:"):
		var prefix: String = atom_name.get_slice(":", 0)
		var each := {"op": prefix, "kind": atom_name.trim_prefix(prefix + ":")}
		if m.names.has("n") and not m.get_string("n").is_empty():
			each["amount"] = parse_amount(m.get_string("n"))
		if prefix == "special":
			each["amount"] = int(each.get("amount", 1))
			for g in ["v", "cv", "cc", "own"]:  # Fuerza, filtro de coste y "que controles" del objetivo
				if m.names.has(g) and not m.get_string(g).is_empty():
					each[g] = m.get_string(g)
		return each
	match atom_name:
		"own_allies_protect":
			var protect := {"op": "mass_buff", "verb": "buff", "side": "own", "others": false, "amount": 0,
				"keywords": ["indestructible", "indesterrable"], "to_exile": false, "permanent": false, "turn_only": false,
				"duration": "until_next_turn"}
			if m.get_string("n").is_empty():
				return protect
			return {"op": "multi", "steps": [protect, {"op": "mass_buff", "verb": "buff", "side": "own", "others": false,
				"amount": parse_amount(m.get_string("n")), "keywords": [], "to_exile": false, "permanent": true, "turn_only": false}]}
		"draw":
			return {"op": "draw", "amount": parse_amount(m.get_string("n")), "up_to": not m.get_string("upto").is_empty()}
		"draw_to_match":
			return {"op": "draw_to_match"}
		"castle_exile_reserve":
			return {"op": "castle_exile", "amount": 0, "bottom": false, "per": "opp_reserve"}
		"mill_per":
			var per_map := {
				"aliado en tu linea de defensa": "own_allies_defense", "aliado que controles": "own_allies",
				"totem en juego": "totems_in_play", "totem que controles": "own_totems",
				"totem en juego y en tu destierro": "totems_in_play_and_exile", "oro que controles": "own_golds",
			}
			return {"op": "mill", "who": "opponent", "amount": parse_amount(m.get_string("n")),
				"per": per_map.get(m.get_string("per"), "")}
		"mill_opp":
			return {"op": "mill", "who": "opponent", "amount": parse_amount(m.get_string("n"))}
		"mill_self":
			return {"op": "mill", "who": "self", "amount": parse_amount(m.get_string("n"))}
		"discard_opp_random":
			return {"op": "discard", "who": "opponent", "amount": parse_amount(m.get_string("n")), "random": true}
		"combat_flag":
			var fdet: String = m.get_string("det")
			var flag_step := {"op": "buff", "verb": "buff", "count": parse_amount(fdet.trim_prefix("hasta ")),
				"up_to": fdet.begins_with("hasta "), "amount": 0, "keywords": [], "to_exile": false,
				"double_damage": "doble" in m.get_string("what"),
				"no_damage": not ("doble" in m.get_string("what")) and (not ("bloquear" in m.get_string("what")) or "dano" in m.get_string("what")),
				"no_block": "bloquear" in m.get_string("what"),
				"permanent": false, "turn_only": true, "target": _target_from(m)}
			flag_step.target.card_types = ["aliado"]
			return flag_step
		"self_raise":
			return {"op": "self_raise"}
		"opp_gold_to_paid":
			return {"op": "opp_gold_to_paid"}
		"revive_blank":
			var rdet: String = m.get_string("det")
			return {"op": "revive_blank", "amount": parse_amount(rdet.trim_prefix("hasta ")), "up_to": rdet.begins_with("hasta "),
				"cost_val": parse_amount(m.get_string("cval")) if not m.get_string("cval").is_empty() else -1,
				"cost_cmp": m.get_string("ccmp")}
		"mill_x":
			var src_word: String = _group(m, "src")
			var src := "own_ally"
			if "porte" in src_word:
				src = "armed_ally"
			elif src_word == "del portador":
				src = "bearer"
			elif "mano" in src_word:
				src = "opp_hand_allies"
			elif src_word == "aliados controles":
				src = "own_allies_count"
			elif src_word in ["este aliado", "su fuerza"]:
				src = "self_strength"
			elif src_word == "un aliado en juego":
				src = "any_ally"
			elif src_word == "una carta en juego":
				src = "any_card_cost"
			elif src_word == "otra carta que controles":
				src = "own_other_card_cost"
			elif src_word == "oros haya en tu oro pagado":
				src = "own_paid_gold"
			elif src_word == "ese aliado":
				src = "paid_ally"
			elif "perdido" in src_word:
				src = "lost_strength"
			return {"op": "mill_x", "who": "choose" if _group(m, "who") == "un jugador" else "opponent", "src": src,
				"exile": not _group(m, "exile").is_empty()}
		"cancel_attack":
			return {"op": "cancel_attack", "count": parse_amount(m.get_string("det").trim_prefix("hasta ")),
				"opponent": not m.get_string("opp").is_empty()}
		"set_strength":
			var sdet: String = m.get_string("det")
			var set_step := {"op": "buff", "verb": "buff", "count": parse_amount(sdet.trim_prefix("hasta ")),
				"up_to": sdet.begins_with("hasta "), "amount": 0, "keywords": [], "to_exile": false,
				"permanent": false, "turn_only": true, "target": _target_from(m), "set_strength": int(m.get_string("sv")),
				"duration": "until_next_turn" if m.get_string("dur").strip_edges() == "hasta tu proximo turno" else ""}
			set_step.target.card_types = ["aliado"]
			if m.get_string("dbl").is_empty():
				return set_step
			var dbl_step: Dictionary = set_step.duplicate(true)
			dbl_step.erase("set_strength")
			dbl_step["double"] = true
			return {"op": "choice", "options": [[set_step], [dbl_step]]}
		"discard_opp":
			return {"op": "discard", "who": "opponent", "amount": parse_amount(m.get_string("n")),
				"random": not m.get_string("rnd").is_empty()}
		"castle_exile":
			var ce_n: String = m.get_string("n") if not m.get_string("n").is_empty() else m.get_string("n2")
			if ce_n.is_empty():
				ce_n = m.get_string("n3")  # "las primeras N cartas de su Castillo" (cadenas de titán)
			var ce_pos: String = m.get_string("pos") if not m.get_string("pos").is_empty() else m.get_string("pos2")
			return {"op": "castle_exile", "amount": parse_amount(ce_n), "bottom": ce_pos == "fondo"}
		"discard_self":
			return {"op": "discard", "who": "self", "amount": parse_amount(m.get_string("n")), "random": false}
		"shuffle_from_hand":
			return {"op": "shuffle_from_hand", "amount": parse_amount(m.get_string("n")),
				"up_to": not m.get_string("upto").is_empty()}
		"shuffle_from_hand_opp":
			return {"op": "shuffle_from_hand", "amount": parse_amount(m.get_string("n")), "up_to": false, "who": "opponent"}
		"keep_shuffle":
			return {"op": "keep_shuffle", "amount": parse_amount(m.get_string("n")), "up_to": not m.get_string("upto").is_empty(),
				"card_type": TYPE_WORDS.get(m.get_string("kind"), ""), "per_cost": not m.get_string("pc").is_empty()}
		"keep_silence_shuffle":
			return {"op": "keep_shuffle", "amount": 1, "up_to": false, "card_type": "", "exclude_gold": true, "silence_first": true}
		"shuffle_from_cemetery":
			return {"op": "shuffle_from_cemetery", "amount": parse_amount(m.get_string("n")),
				"up_to": not m.get_string("upto").is_empty()}
		"target_silence":
			var ts_target := {"card_types": [], "controller": "opponent" if not m.get_string("opp").is_empty() else "any",
				"exclude_gold": true, "stat": "", "cmp": "<=", "value": 0}
			var ts_type: String = TYPE_WORDS.get(m.get_string("kind"), "")
			if not ts_type.is_empty():
				ts_target.card_types = [ts_type]
			return {"op": "target", "verb": "banish" if m.get_string("v").begins_with("desterrad") else "destroy",
				"count": 1, "up_to": false, "target": ts_target, "silence_first": true}
		"mass_silence":
			var ms_target := _target_from(m)
			ms_target.exclude_gold = true
			return {"op": "mass", "verb": "banish" if m.get_string("v").begins_with("desterrad") else "destroy",
				"target": ms_target, "silence_first": true}
		"search_named":
			return {"op": "search", "zones": ["castillo"], "card_type": "", "card_types": [], "types_not": [], "cost_val": -1,
				"cost_cmp": "", "dest": "mano", "amount": 1, "up_to": false, "name": m.get_string("name").strip_edges()}
		"buff_eq_allies":
			var abel_q := {"kind": "play_count", "who": "choose", "defense": false, "types": ["aliado"], "race": "", "types_not": [],
				"keyword": "", "distinct_cost": false, "str_val": -1, "str_cmp": "", "cost_val": -1, "cost_cmp": ""}
			return {"op": "buff", "verb": "buff", "count": 1, "up_to": false, "amount": 1, "keywords": [], "to_exile": false,
				"permanent": false, "turn_only": false, "target": {"card_types": ["aliado"], "controller": "any", "exclude_gold": false,
				"stat": "", "cmp": ">=", "value": 0}, "qty": {"mode": "set", "q": abel_q, "key": "amount"}}
		"kuji_buff":
			var kuji_q := {"kind": "zone_count", "zones": ["cementerio"], "types": ["aliado"], "race": "",
				"cost_val": int(m.get_string("cv")), "cost_cmp": "mas"}
			return {"op": "buff", "verb": "buff", "count": 1, "up_to": false, "amount": 0, "keywords": ["furia"], "to_exile": false,
				"permanent": false, "turn_only": true, "no_leave": true, "target": {"card_types": ["aliado"], "controller": "own",
				"exclude_gold": false, "stat": "", "cmp": ">=", "value": 0}, "qty": {"mode": "set", "q": kuji_q, "key": "amount"}}
		"opp_hand_exile":
			return {"op": "hand_exile", "who": "opponent", "amount": parse_amount(m.get_string("n"))}
		"search_named_two":
			var named: Array = []
			for g in ["a", "b"]:
				named.append({"op": "search", "zones": ["castillo"], "card_type": "", "card_types": [], "types_not": [], "cost_val": -1,
					"cost_cmp": "", "dest": "mano", "amount": 1, "up_to": false, "name": m.get_string(g).strip_edges()})
			return {"op": "multi", "steps": named}
		"search_per_ally_plus":
			var allies_q := {"kind": "play_count", "who": "self", "defense": false, "types": ["aliado"], "race": "", "types_not": [],
				"keyword": "", "distinct_cost": false, "str_val": -1, "str_cmp": "", "cost_val": -1, "cost_cmp": ""}
			return {"op": "search", "zones": ["castillo"], "card_type": "", "card_types": [], "types_not": [], "cost_val": -1,
				"cost_cmp": "", "dest": "destierro", "amount": 1, "up_to": false, "owner": "any",
				"qty": {"mode": "set", "q": allies_q, "key": "amount", "plus": 1}}
		"search_gold_and_other":
			var base := {"op": "search", "zones": ["castillo"], "card_types": [], "types_not": [], "cost_val": -1, "cost_cmp": "",
				"amount": 1, "up_to": false}
			return {"op": "multi", "steps": [base.merged({"card_type": "oro", "dest": "pagado"}), base.merged({"card_type": "", "dest": "mano"})]}
		"search_gold_split":
			var k: int = parse_amount(m.get_string("k"))
			return {"op": "search", "zones": ["castillo"], "card_type": "oro", "card_types": [], "types_not": [], "cost_val": -1,
				"cost_cmp": "", "dest": "mano", "amount": parse_amount(m.get_string("n")), "up_to": false,
				"dist": [{"count": k, "dest": "gold_silenced"}, {"count": 1, "dest": "hand"}]}
		"search_as_weapons":
			return {"op": "search", "zones": ["castillo"], "card_type": "", "card_types": [], "types_not": [],
				"cost_val": int(m.get_string("cv")), "cost_cmp": "menos", "dest": "armas", "amount": parse_amount(m.get_string("n")),
				"up_to": false, "owner": "opponent", "distinct": true}
		"self_buff_per":
			return {"op": "self_buff_per", "amount": parse_amount(m.get_string("n")),
				"per": "opp_exile" if m.get_string("per").begins_with("carta") else "own_exile_allies"}
		"self":
			var sv: String = m.get_string("v")
			return {"op": "self", "verb": "banish" if sv.begins_with("destierr") else ("shuffle" if sv.begins_with("baraj") else "destroy")}
		"each_draw":
			return {"op": "draw", "amount": parse_amount(m.get_string("n")), "up_to": false, "who": "both"}
		"each_discard":
			return {"op": "discard", "who": "both", "amount": parse_amount(m.get_string("n")), "random": false}
		"each_hand_exile":
			return {"op": "hand_exile", "who": "both", "amount": parse_amount(m.get_string("n"))}
		"search":
			var zones: Array = []
			for g in ["z1", "z2", "z3", "z4"]:
				var z: String = m.get_string(g)
				if not z.is_empty() and z not in zones:
					zones.append(z)
			var foreign: String = m.get_string("zx1") if not m.get_string("zx1").is_empty() else m.get_string("zx2")
			if not foreign.is_empty():
				if not zones.is_empty():
					return {}
				zones.append("castillo")
			if zones.is_empty():
				return {}  # sin zona explícita: ambiguo
			var play := {}
			if not m.get_string("play").is_empty():
				if not m.get_string("free").is_empty():
					play = {"free": true}
				elif not m.get_string("redq").is_empty():
					# "reduciendo su coste en tantos Oros como Tótem controles, hasta un mínimo de 0" (los khanta).
					play = {"reduce": 0, "reduce_per": "own_totems",
						"floor": int(m.get_string("floor2")) if not m.get_string("floor2").is_empty() else 1}
				else:
					var red: String = m.get_string("red") if not m.get_string("red").is_empty() else m.get_string("red2")
					play = {"reduce": parse_amount(red), "floor": int(m.get_string("floor")) if not m.get_string("floor").is_empty() else 1}
			if not m.get_string("putplay").is_empty():
				play = {"free": true}  # "ponlo en juego" (ninjato): entra sin pagar su coste
			var dest_word: String = m.get_string("dest")
			var dest_key: String = {"oro pagado": "pagado", "cementerio": "cementerio"}.get(dest_word, "mano")
			if not m.get_string("exile").is_empty():
				dest_key = "destierro"
			if not m.get_string("owncem").is_empty():
				dest_key = "cementerio"  # el Cementerio de su dueño: es el destino normal de search_zones()
			# Desde un Castillo ajeno solo a su Destierro o Cementerio (pasar a tu mano o a tu Oro pagado
			# es cambiar de dueño: lo resuelve la cadena vieja).
			if not foreign.is_empty() and (dest_key not in ["destierro", "cementerio"] or not play.is_empty()):
				return {}
			var dest_alts: Array = []
			if not m.get_string("alt").is_empty():
				dest_alts = [dest_key, m.get_string("alt")]
			elif not m.get_string("orhand").is_empty() and play.get("free", false):
				dest_alts = ["jugar", "mano"]
			var sdist: Array = []
			if not m.get_string("sdist").is_empty():
				var sd_rx := RegEx.create_from_string("(?<n>" + NUM + ") en tu (?<z>mano|cementerio|destierro)")
				for sd in sd_rx.search_all(m.get_string("sdist")):
					sdist.append({"count": parse_amount(sd.get_string("n")),
						"dest": {"mano": "hand", "cementerio": "cemetery", "destierro": "exile"}[sd.get_string("z")]})
			var found: Dictionary = _search_steps(m, zones, dest_key, play)
			# "una copia de esta carta": su propio nombre (lo resuelve el intérprete). Nombre suelto tras el
			# tipo ("una carta Drácula", "un Aliado Azi"), "que no sea Ahab", "de Fuerza 2 o menos".
			if not m.get_string("copy").is_empty():
				found = {"op": "search", "zones": zones, "card_type": "", "card_types": [], "types_not": [],
					"cost_val": -1, "cost_cmp": "", "no_ability": false, "dest": dest_key, "amount": 1, "up_to": false,
					"name": "@self"}
				if not play.is_empty():
					found["play"] = play
			for fs in (found.steps if found.get("op", "") == "multi" else [found]):
				if fs.is_empty():
					continue
				if not m.get_string("nm").is_empty() and not TYPE_WORDS.has(m.get_string("nm")):
					fs["name"] = m.get_string("nm")
				if not m.get_string("nnot").is_empty():
					fs["name_not"] = m.get_string("nnot")
				if not m.get_string("sval").is_empty():
					fs["str_val"] = int(m.get_string("sval"))
					fs["str_cmp"] = m.get_string("scmp")
				if not foreign.is_empty():
					fs["owner"] = "any" if foreign == "un castillo" else "opponent"
				if not m.get_string("distinct").is_empty():
					fs["distinct"] = true
				if not m.get_string("same").is_empty():
					fs["same_type"] = true  # "una carta del mismo tipo": el de la carta Descartada antes (kitsune)
				if not dest_alts.is_empty():
					fs["dest_alts"] = dest_alts
				if not sdist.is_empty():
					fs["dist"] = sdist
			if found.get("op", "") == "multi" and (not sdist.is_empty() or not dest_alts.is_empty()):
				return {}  # el reparto/elección vale para una sola búsqueda
			return found
		"raise":
			var raised: Dictionary = _search_steps(m, ["cementerio"], "mano", {})
			var tail_not: String = TYPE_WORDS.get(m.get_string("nt"), "")
			if not tail_not.is_empty():
				for rs in (raised.steps if raised.get("op", "") == "multi" else [raised]):
					rs.types_not.append(tail_not)
			return raised
		"gold_to_paid":
			var gz: Array = []
			for g in ["z1", "z2"]:
				if not m.get_string(g).is_empty():
					gz.append(m.get_string(g))
			var gdest: String = m.get_string("dest")
			if gdest.is_empty():
				if m.get_string("injuego").is_empty():
					return {}
				gdest = "reserva"
			return {"op": "gold_to_paid", "zones": gz, "dest": "pagado" if gdest == "oro pagado" else "reserva"}
		"deck_to_hand":
			if not m.get_string("both").is_empty():
				return {"op": "deck_to_hand", "from": "both", "amount": 1}
			if not m.get_string("from2").is_empty():
				return {"op": "deck_to_hand", "from": "bottom" if m.get_string("from2") == "ultima" else "top", "amount": 1}
			return {"op": "deck_to_hand", "from": "bottom" if m.get_string("from") == "fondo" else "top",
				"amount": 1 if not m.get_string("one").is_empty() else parse_amount(m.get_string("n"))}
		"no_damage":
			return {"op": "no_damage", "combat_only": not m.get_string("combat").is_empty()}
		"peek_hand":
			return {"op": "peek_hand"}
		"show_hand":
			return {"op": "show_hand"}
		"play_from":
			var pz: Array = []
			for g in ["z1", "z2"]:
				if not m.get_string(g).is_empty():
					pz.append(m.get_string(g))
			var how := {"free": true} if not m.get_string("free").is_empty() else \
				({"reduce": 0} if not m.get_string("pay").is_empty() else {"reduce": parse_amount(m.get_string("red")
					if not m.get_string("red").is_empty() else m.get_string("red2"))})
			how["exile_after"] = not m.get_string("exile").is_empty()
			how["floor"] = int(m.get_string("floor")) if not m.get_string("floor").is_empty() else 1
			var found := _search_steps(m, pz, "jugar", how)
			if found.is_empty():
				return {}
			# Mismo formato que la búsqueda, con op propio (de la mano o el Cementerio, se juega).
			for st in (found.steps if found.get("op", "") == "multi" else [found]):
				st.op = "play_from"
				# Un Oro nunca se juega (solo se pone en juego): "jugar una carta" no lo ofrece.
				if "oro" not in st.types_not and (st.card_types.is_empty() or "oro" not in st.card_types):
					st.types_not.append("oro")
			return found
		"mass":
			var mass_target := _target_from(m)
			mass_target.exclude_gold = true
			return {"op": "mass", "verb": "destroy" if m.get_string("verb") == "destruye" else "banish",
				"target": mass_target}
		"cemetery_both", "cemetery_banish", "cemetery_shuffle":
			return {"op": "cemetery_cleanup", "mode": atom_name.trim_prefix("cemetery_"),
				"amount": parse_amount(m.get_string("n")),
				"one_zone": atom_name != "cemetery_both" and not m.get_string("one").is_empty()}
		"gold":
			var for_word: String = m.get_string("for").trim_prefix("un ")
			return {"op": "gold", "amount": parse_amount(m.get_string("n")),
				"for": {"aliados": "aliado", "aliado": "aliado", "armas": "arma", "arma": "arma", "talismanes": "talisman",
					"talisman": "talisman", "totems": "totem", "totem": "totem"}.get(for_word, "")}
		"regroup_gold":
			return {"op": "regroup_gold", "amount": parse_amount(m.get_string("n"))}
		"regroup_cards":
			return {"op": "regroup_cards", "amount": parse_amount(m.get_string("n"))}
		"mass_buff":
			var mass_amount := 0
			var mass_keywords: Array = []
			var mass_to_exile := false
			var mass_item_rx := RegEx.new()
			mass_item_rx.compile(GRANT_ITEM)
			for im in mass_item_rx.search_all(m.get_string("list")):
				var item: String = im.get_string()
				if item.ends_with("de fuerza"):
					mass_amount += int(item.split(" ")[0])
				elif item == "hace dano al destierro":
					mass_to_exile = true
				elif "dano" in item:
					return {}  # doble / sin daño a todos: no hay paso masivo para eso
				else:
					mass_keywords.append(item)
			var mass_loses: bool = m.get_string("v") == "pierden"
			if mass_loses and (not mass_keywords.is_empty() or mass_to_exile):
				return {}  # "pierden Furia": aura, no efecto (KeywordAuras)
			return {"op": "mass_buff", "verb": "buff", "side": "opponent" if not m.get_string("opp").is_empty() else "own",
				"others": not m.get_string("oth").is_empty(), "amount": -mass_amount if mass_loses else mass_amount,
				"keywords": mass_keywords, "to_exile": mass_to_exile,
				"permanent": not m.get_string("perm").is_empty(), "turn_only": not m.get_string("turn").is_empty()}
		"buff":
			var buff_det: String = m.get_string("det")
			var loses: bool = m.get_string("v").begins_with("pierde")
			var amount := 0
			var keywords: Array = []
			var to_exile := false
			var double_damage := false
			var no_damage := false
			var item_rx := RegEx.new()
			item_rx.compile(GRANT_ITEM)
			for im in item_rx.search_all(m.get_string("list")):
				var item: String = im.get_string()
				if item.ends_with("de fuerza"):
					amount += int(item.split(" ")[0])
				elif item == "hace dano al destierro":
					to_exile = true
				elif "doble de dano" in item:
					double_damage = true
				elif "dano de combate" in item:
					no_damage = true
				else:
					keywords.append(item)
			if not m.get_string("exile2").is_empty():
				to_exile = true
			if loses and (not keywords.is_empty() or to_exile or double_damage or no_damage):
				return {}  # "pierde Furia" etc.: que lo resuelva la cadena vieja
			var buff_step := {"op": "buff", "verb": "buff", "count": parse_amount(buff_det.trim_prefix("hasta ")),
				"up_to": buff_det.begins_with("hasta "), "amount": -amount if loses else amount,
				"keywords": keywords, "to_exile": to_exile, "double_damage": double_damage, "no_damage": no_damage,
				"permanent": not m.get_string("perm").is_empty(), "turn_only": not m.get_string("turn").is_empty(),
				"target": _target_from(m)}
			if " o " in m.get_string("v"):
				# "gana o pierde N de Fuerza": el sentido se elige al declarar.
				if not keywords.is_empty() or to_exile or double_damage or no_damage:
					return {}
				var lose_step: Dictionary = buff_step.duplicate(true)
				lose_step.amount = -amount
				return {"op": "choice", "options": [[buff_step], [lose_step]]}
			return buff_step
		"silence":
			var dur: String = m.get_string("dur").strip_edges()
			if dur == "hasta tu proximo turno":
				return {}
			var silence_step := _target_step("silence", m)
			silence_step["duration"] = "turn" if dur != "" else "permanent"
			return silence_step
		"mill_both":
			return {"op": "mill", "who": "both", "amount": parse_amount(m.get_string("n"))}
		"hand_peek":
			var hv: String = m.get_string("v")
			var hp_not: Array = []
			for g3 in ["n1", "n2"]:
				var hn: String = TYPE_WORDS.get(m.get_string(g3), "")
				if not hn.is_empty():
					hp_not.append(hn)
			return {"op": "hand_peek", "verb": "banish" if hv.begins_with("destierra") or hv.begins_with("desterrar")
					else ("discard" if hv.begins_with("descarta") else "shuffle"),
				"count": parse_amount(m.get_string("det")), "types": _type_list(m.get_string("type")), "types_not": hp_not,
				# "de coste N" antes o después de "de ahí" (rogue mecha: "una carta de ahí de coste 1").
				"cost_val": int(m.get_string("cval")) if not m.get_string("cval").is_empty()
					else (int(m.get_string("cval2")) if not m.get_string("cval2").is_empty() else -1),
				"cost_cmp": m.get_string("ccmp") if not m.get_string("cval").is_empty() else m.get_string("ccmp2")}
		"hand_show_discard":
			return {"op": "hand_peek", "verb": "discard", "count": parse_amount(m.get_string("det")),
				"types": _type_list(m.get_string("type")), "types_not": [], "cost_val": -1, "cost_cmp": ""}
		"reveal_until":
			var specs: Array = []
			var spec_rx := RegEx.new()
			spec_rx.compile("(?<n>" + NUM + ") (?<types>" + TALT_R + ")(?: (?<race>" + RACE + "))?(?: (?<hab>con|sin) habilidad)?" \
				+ "(?: con (?<kw>" + REVEAL_KW + "))?(?: que no sean? (?:un |una )?(?<nt>[a-z]+))?" \
				+ "(?: (?:de )?coste (?<cval>\\d+)(?: o (?<ccmp>menos|mas))?)?" \
				+ "(?: de fuerza (?<sval>\\d+)(?: o (?<scmp>menos|mas))?)?(?<dn> de distinto nombre)?")
			for sm in spec_rx.search_all(m.get_string("specs")):
				var nt_word: String = sm.get_string("nt")
				var nt: String = TYPE_WORDS.get(nt_word, "?") if not nt_word.is_empty() else ""
				specs.append({"count": parse_amount(sm.get_string("n")), "types": _type_list(sm.get_string("types")),
					"race": sm.get_string("race"), "types_not": [nt] if nt != "" and nt != "?" else [],
					"name_not": nt_word if nt == "?" else "",  # "que no sean Odiseo"
					"cost_val": int(sm.get_string("cval")) if not sm.get_string("cval").is_empty() else -1,
					"cost_cmp": sm.get_string("ccmp"),
					"str_val": int(sm.get_string("sval")) if not sm.get_string("sval").is_empty() else -1,
					"str_cmp": sm.get_string("scmp"), "ability": sm.get_string("hab"), "keyword": sm.get_string("kw"),
					"distinct": not sm.get_string("dn").is_empty()})
			if specs.is_empty():
				return {}
			var dest := "hand"
			if not m.get_string("play").is_empty():
				dest = "play_free"
			elif not m.get_string("put").is_empty():
				dest = "put"
			elif not m.get_string("gold").is_empty():
				dest = "gold"
			var dist: Array = []
			if not m.get_string("dist").is_empty():
				dest = "dist"
				var item_rx := RegEx.create_from_string("(?:pon )?(?<n>" + NUM + "|otro|otra|el otro|la otra)(?: carta)? en tu (?<z>mano|cementerio|destierro)" \
					+ "|(?<play>juega) (?<pn>uno|una|el otro|la otra) sin pagar su coste|(?<sh>baraja) (?:el otro|la otra)")
				for im in item_rx.search_all(m.get_string("dist")):
					if not im.get_string("play").is_empty():
						dist.append({"count": 1, "dest": "play_free"})
					elif not im.get_string("sh").is_empty():
						dist.append({"count": 1, "dest": "shuffle"})
					else:
						var nw: String = im.get_string("n")
						dist.append({"count": 1 if nw in ["otro", "otra", "el otro", "la otra"] else parse_amount(nw),
							"dest": {"mano": "hand", "cementerio": "cemetery", "destierro": "exile"}[im.get_string("z")]})
			return {"op": "reveal_until", "specs": specs, "play_free": dest == "play_free", "dest": dest, "dist": dist}
		"reveal_top":
			var rt_n: String = m.get_string("n") if not m.get_string("n").is_empty() else m.get_string("n2")
			var rt := {"op": "reveal_top", "count": parse_amount(rt_n), "up_to": not m.get_string("upto").is_empty(),
				"dest": "hand", "reduce": 0, "rest": m.get_string("rd") if not m.get_string("rd").is_empty() else "shuffle"}
			if not m.get_string("ek").is_empty():
				rt["pick"] = parse_amount(m.get_string("ek"))
				rt["pick_types"] = _type_list(m.get_string("et"))
			elif not m.get_string("k").is_empty():
				rt["pick"] = parse_amount(m.get_string("k"))
				rt["pick_types"] = _type_list(m.get_string("kt"))
			else:
				rt["pick"] = parse_amount(m.get_string("pk"))
				rt["pick_types"] = _type_list(m.get_string("pt"))
				rt["dest"] = "play"
				rt["reduce"] = parse_amount(m.get_string("red"))
			return rt
		"bounce":
			return _target_step("bounce", m)
		"annul_any":
			return {"op": "annul", "text": "anula o cancela la habilidad de una carta" if not m.get_string("both").is_empty()
				else "cancela la habilidad de una carta"}
		"annul":
			# Texto con tildes para StackAnnul.try_from_text() (el normalizado no las tiene).
			var accents := {"talisman": "talismán", "totem": "tótem"}
			var kind_word: String = accents.get(m.get_string("kind"), m.get_string("kind"))
			if not m.get_string("kind2").is_empty():
				kind_word += " o " + str(accents.get(m.get_string("kind2"), m.get_string("kind2")))
			var annul_verb: String = m.get_string("v").replace("anular", "anula").replace("cancelar", "cancela")
			var annul_text: String = annul_verb + (" una carta" if not m.get_string("any").is_empty() else " un " + kind_word) \
				+ m.get_string("opp")
			if not m.get_string("val").is_empty():
				annul_text += " de coste %d o menos" % parse_amount(m.get_string("val"))
			return {"op": "annul", "text": annul_text}
		"talisman_fizzle":
			return {"op": "talisman_fizzle"}
		"cost_shift":
			var shift := _target_step("cost_shift", m)
			shift.target.exclude_gold = true  # un Oro no tiene coste
			shift["amount"] = parse_amount(m.get_string("n"))
			return shift
		"grant_choice":
			var dur: String = m.get_string("dur").strip_edges()
			if dur == "mientras este en juego":
				dur = ""
			var options: Array = []
			var item_rx := RegEx.new()
			item_rx.compile(CHOICE_ITEM)
			for im in item_rx.search_all(m.get_string("opts")):
				var item: String = im.get_string().replace("\"", "").replace("“", "").replace("”", "")
				var is_double: bool = "doble de dano" in item
				var step := {"op": "buff", "verb": "buff", "count": 1, "up_to": false, "amount": 0,
					"keywords": [] if item == "no puede ser barajado" or is_double else [item],
					"no_shuffle": item == "no puede ser barajado", "double_damage": is_double,
					"to_exile": false, "permanent": dur == "", "turn_only": dur == "por el turno",
					"duration": "until_next_turn" if dur == "hasta tu proximo turno" else "",
					"target": _target_from(m)}
				step.target.card_types = ["aliado", "totem"] if not m.get_string("tot").is_empty() else ["aliado"]
				step.target.exclude_gold = true
				options.append([step])
			if options.size() < 2:
				return {}
			return {"op": "choice", "options": options}
		"target":
			var verb_word: String = m.get_string("verb")
			var verb := "destroy"
			if verb_word.begins_with("destierra") or verb_word.begins_with("desterrar"):
				verb = "banish"
			elif verb_word.begins_with("baraj"):
				verb = "shuffle"
			return _target_step(verb, m)
	return {}


static func _search_steps(m: RegExMatch, zones: Array, dest: String, play: Dictionary) -> Dictionary:
	"""Paso(s) de búsqueda de "busca/sube <objs>". Cada grupo unido por " y " es una búsqueda aparte
	("un Aliado y un Tótem": uno de cada); varios grupos vuelven como {"op": "multi"} y
	_compile_sequence() los despliega. Costo, "que no sea" y destino valen para todos."""
	var types_not: Array = []
	for g2 in ["n1", "n2"]:
		var nt: String = TYPE_WORDS.get(m.get_string(g2), "")
		if not nt.is_empty():
			types_not.append(nt)
	var steps: Array = []
	for group in _object_groups(m.get_string("objs")):
		var types: Array = []
		var any_type := false
		var races := false
		for alt in group.alts:
			if alt.race != "":
				races = true
			if alt.type == "" and alt.race == "":
				any_type = true
			elif alt.type != "" and alt.type not in types:
				types.append(alt.type)
		if any_type:
			types = []
		var st := {"op": "search", "zones": zones, "card_type": types[0] if types.size() == 1 and not races else "",
			"card_types": types if not races else [], "types_not": types_not,
			"cost_val": parse_amount(m.get_string("cval")) if not m.get_string("cval").is_empty() else -1,
			"cost_cmp": m.get_string("ccmp"), "no_ability": not m.get_string("nohab").is_empty() if m.names.has("nohab") else false,
			"dest": dest, "amount": group.amount, "up_to": group.up_to}
		if races:
			st["alts"] = group.alts
		if not play.is_empty():
			st["play"] = play
		steps.append(st)
	if steps.is_empty():
		return {}
	return steps[0] if steps.size() == 1 else {"op": "multi", "steps": steps}


static func _object_groups(text: String) -> Array:
	"""'un aliado y un totem' → [{amount 1, alts [{type aliado}]}, {amount 1, alts [{type totem}]}];
	'un angel, eterno o totem' → un grupo con alts [{aliado, angel}, {aliado, eterno}, {totem}];
	'un aliado dragon o caballero' → alts [{aliado, dragon}, {aliado, caballero}]. Una raza sola es un
	Aliado de esa raza."""
	var race_rx := RegEx.create_from_string("^" + RACE + "$")
	var det_rx := RegEx.create_from_string("^(?<det>(?:hasta )?" + NUM + ") ")
	var groups: Array = []
	# "un Aliado, un Talismán y un Tótem": la coma seguida de artículo también separa grupos (sin
	# artículo, "un Ángel, Eterno o Tótem", son alternativas).
	var list_text: String = text.replace(", y ", " y ")
	if " y " in list_text:
		list_text = RegEx.create_from_string(", (?=(?:un|una) )").sub(list_text, " y ", true)
	var first_up_to := false
	for gtext in list_text.split(" y "):
		var g: String = gtext.strip_edges()
		var amount := 1
		var up_to := false
		var dm := det_rx.search(g)
		if dm:
			var det: String = dm.get_string("det")
			up_to = det.begins_with("hasta ")
			amount = parse_amount(det.trim_prefix("hasta "))
			g = g.substr(dm.get_end())
		var alts: Array = []
		var last_type := ""
		for part in RegEx.create_from_string("(?:, | o | u | y/o )").sub(g, "|", true).split("|"):
			var words: PackedStringArray = part.strip_edges().trim_prefix("un ").trim_prefix("una ").split(" ", false)
			if words.is_empty():
				continue
			var t: String = TYPE_WORDS.get(words[0], "?")
			if t != "?":
				last_type = t
				var race: String = words[1] if words.size() > 1 and race_rx.search(words[1]) != null else ""
				alts.append({"type": t, "race": race})
			elif race_rx.search(words[0]) != null:
				# "Aliado Dragón o Caballero": la raza suelta hereda el tipo de la anterior; sola, Aliado.
				alts.append({"type": last_type if last_type != "" else "aliado", "race": words[0]})
		if not alts.is_empty():
			# "hasta un Aliado y un Arma": el "hasta" vale para toda la lista.
			if groups.is_empty():
				first_up_to = up_to
			groups.append({"amount": amount, "up_to": up_to or first_up_to, "alts": alts})
	return groups


static func _type_list(text: String) -> Array:
	"""'aliado o totem' / 'aliado, arma u oro' → ["aliado", "totem"]. Vacío
	si alguna es 'carta' (cualquier tipo)."""
	var out: Array = []
	var sep := RegEx.new()
	sep.compile("(?:, | o | u )")
	for part in sep.sub(text, "|", true).split("|"):
		var w: String = part.strip_edges().trim_prefix("un ").trim_prefix("una ").strip_edges()
		var t: String = TYPE_WORDS.get(w, "?")
		if t == "":
			return []
		if t != "?" and t not in out:
			out.append(t)
	return out


static func _target_step(verb: String, m: RegExMatch) -> Dictionary:
	var det: String = m.get_string("det")
	return {"op": "target", "verb": verb, "count": parse_amount(det.trim_prefix("hasta ")),
		"up_to": det.begins_with("hasta "), "target": _target_from(m)}


static func _group(m: RegExMatch, name: String) -> String:
	# get_string() con un nombre que el regex no tiene da error — no todos
	# los átomos que arman objetivos definen los mismos grupos.
	return m.get_string(name) if m.names.has(name) else ""


static func _target_from(m: RegExMatch) -> Dictionary:
	var t := {
		"card_types": [],
		"controller": "opponent" if not _group(m, "opp").is_empty() else "any",
		"exclude_gold": not _group(m, "nogold").is_empty(),
		"stat": _group(m, "stat"),
		"cmp": {"menos": "<=", "mas": ">="}.get(_group(m, "cmp"), "==" if not _group(m, "val").is_empty() else ">="),
		"value": int(_group(m, "val")) if not _group(m, "val").is_empty() else 0,
	}
	var tw: String = TYPE_WORDS.get(_group(m, "kind"), "")
	if not tw.is_empty():
		t.card_types = [tw]
	if not _group(m, "race").is_empty():
		t["race"] = _group(m, "race")
	return t
