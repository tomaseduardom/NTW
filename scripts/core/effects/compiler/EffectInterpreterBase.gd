extends RefCounted
## EffectInterpreterBase — base de EffectInterpreter.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: EffectInterpreterBase <- EffectInterpreterAuxiliares <- EffectInterpreterCostes <- EffectInterpreterDeclaracion <- EffectInterpreterEjecucion <- EffectInterpreterCadaJugador <- EffectInterpreterOponente <- EffectInterpreterEspeciales <- EffectInterpreter. Lo de afuera usa solo EffectInterpreter.gd (hereda todo).

## EffectInterpreter — ejecuta los planes de EffectCompiler (arquitectura.md §54).
## Orden: se declara todo (el "puedes", la rama de una elección "A, o B", los objetivos en juego) y
## después se ejecutan los pasos en orden, "en la medida de lo posible". Un paso "then" (tras
## "Luego,") solo corre si el anterior se resolvió por completo.
## Ventana de respuesta (§59): tras declarar llama a EffectContext.ensure_window(): si el efecto aún
## no le dio su ventana al rival, se abre ahí; si ya la tuvo (Talismanes, activadas en la Pila), no
## se abre otra.
## Quién elige: el jugador 0 con clic en el tablero; el Remoto (1 con sala) por red
## (await_target()/await_multi_target()/await_choice() delegan solos); el bot (1 sin sala) aquí, con
## una heurística simple.
## Solo ejecuta planes cuyos pasos sabe resolver (EffectCompiler.EXECUTABLE_OPS/VERBS); si no,
## devuelve false y sigue la cadena de patrones. Al agregar una pieza aquí, sumarla también a esas
## listas.

const VERB_LABELS := {
	"destroy": "destruir", "banish": "desterrar", "shuffle": "barajar en el Castillo de su dueño",
	"bounce": "subir a la mano de su dueño", "buff": "cambiar su Fuerza", "cost_shift": "cambiar su coste", "silence": "que pierda su habilidad",
}

const TYPE_LABELS := {
	"aliado": ["Aliado", "Aliados"], "arma": ["Arma", "Armas"], "totem": ["Tótem", "Tótems"],
	"talisman": ["Talismán", "Talismanes"], "oro": ["Oro", "Oros"], "": ["carta", "cartas"],
}

const BOARD_CONTAINERS := ["player_field", "player_linea_ataque", "player_linea_apoyo",
	"opponent_field", "opponent_linea_ataque", "opponent_linea_apoyo"]

const GOLD_CONTAINERS := ["player_gold", "opponent_gold", "player_oro_pagado", "opponent_oro_pagado"]

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")

const StackAnnulScript = preload("res://scripts/core/effects/StackAnnul.gd")

var _ts: Node  # TriggerSystem (dueño de este intérprete)

## La carta tocada directamente al elegir una opción de "A o B" en la mesa (BoardChoice): es el objetivo
## del primer paso de esa opción (_declare_targets()).
var _preselected_target: Node = null

## Lo que hicieron los pasos anteriores del mismo efecto, para las oraciones "de esta forma" que siguen
## (EffectInterpreterCadaJugador / EffectInterpreterOponente): "moved" {jugador: cartas movidas}, "shown",
## "duel", "drawn", "milled", "strength_lost", "paid_strength" (el Aliado pagado como coste), "toll_card".
## Se vacía al empezar cada efecto (execute_plan()).
var _each: Dictionary = {}


func setup(trigger_system: Node) -> void:
	_ts = trigger_system
