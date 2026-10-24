# Cobertura real de handlers (2026-10-23, undécima pasada)

Generado con `tools/probe_handlers.tscn`: resuelve cada disparador, Talismán y activada del catálogo con el bot (jugador 1) en un tablero de relleno y anota si el juego encontró quién lo resolviera (`no_handler` de `TriggerResolution._execute_trigger_effect()`).

- **sin_handler**: ningún camino lo tomó. Puede haber falsos negativos: cartas que se resuelven por otra vía (señales de CemeteryTriggers, `GameManager.confirm_attackers()`, auras).
- **espera**: quedó esperando más de 240 frames. Suele ser una elección del Anfitrión (legítima si elige el rival) o la ventana de respuesta de una carta jugada gratis; también efectos lentos del bot.
- No cuentan como pendientes: **liberar esclavos** (baneada) y la entrada `20479` de **Trentren Vilu** (texto que no es el real).

Pasadas anteriores: 1664/870/177, 1717/795/199, 1761/738/205, 1770/726/206, 1788/730/210, 1852/748/219, 2186/361/262, 2442/69/285, 2500/4/292 y 2594/2/200 (resuelto/sin_handler/espera). Como las anteriores, se corrió en cuatro tramos en paralelo: cada tramo descarta textos repetidos solo dentro de sí, así que la tabla cuenta algunos textos dos veces. Las listas de abajo van sin duplicados.


| Tipo | resuelto | sin_handler | espera |
|---|---|---|---|
| activada | 931 | 0 | 13 |
| on_enter_play | 835 | 1 | 17 |
| Talismán | 547 | 1 | 7 |
| on_attack | 115 | 0 | 2 |
| on_leave_play | 109 | 0 | 2 |
| on_turn_end | 105 | 0 | 0 |
| on_vigilia | 38 | 0 | 0 |
| on_damage_dealt | 22 | 0 | 2 |
| on_turn_start | 18 | 0 | 0 |
| on_opponent_turn_end | 9 | 0 | 0 |
| on_destroyed | 7 | 0 | 0 |
| on_block | 4 | 0 | 2 |
| on_agrupacion | 6 | 0 | 0 |
| on_ataque_start | 3 | 0 | 0 |
| **Total** | **2749** | **2** | **45** |

## Sin handler (2, sin duplicados)

### Talismán (1)

- **liberar esclavos**

### on_enter_play (1)

- **trentren vilu**

## Esperando (43, sin duplicados)

### activada (13)

- **beauchef** — Hasta dos veces por turno, cuando juegues un Arma, tu oponente Descart ⟶ elige J0: Descarta 1 carta(s)
- **Camael** — Hasta dos veces por turno, cuando juegues un Arma tu oponente Descarta ⟶ elige J0: Descarta 1 carta(s)
- **Ezequiel** — Una vez por turno, puedes buscar un Aliado que no sea Ezequiel en tu C ⟶ elige J0: Descarta 1 carta(s)
- **faraon negro** — Una vez en tu turno, tu oponente Bota tantas cartas como Fuerza tenga  ⟶ elige J0: faraon negro: elige un Aliado que controles
- **guardian del tiempo** — Una vez por turno, tu oponente Descarta una carta de su mano. Si contr ⟶ elige J0: Descarta 1 carta(s)
- **inari** — En tu Vigilia, una vez por turno, puedes hacer que tu oponente Descart ⟶ elige J0: Descarta 1 carta(s)
- **Mot** — Cuando pongas en juego un Aliado o Tótem, hasta dos veces por turno, B ⟶ elige J0: Descarta 1 carta(s)
- **ngel jofiel** — Una vez por turno, Descarta una carta para mostrar cartas del tope de  ⟶ elige J0: Descarta 1 carta(s)
- **ngel jofiel** — Una vez por turno, cuando juegues un Tótem de coste 2 o más, tu oponen ⟶ elige J0: Descarta 1 carta(s)
- **Paladín del Tiempo** — Una vez por turno, tu oponente Descarta una carta de su mano. Si contr ⟶ elige J0: Descarta 1 carta(s)
- **tue tue** — En tu Vigilia, una vez por turno, puedes hacer que cada jugador Destru ⟶ elige J0: tue tue: Destruye uno de tus Aliados
- **Vâlve Negre** — En tu Vigilia, una vez por turno, puedes Descartar dos cartas para que ⟶ elige J0: Descarta 1 carta(s)
- **yamata no orochi** — Una vez por turno, si no controlas Aliados de coste 1 o menos, mira la ⟶ elige J0: Descarta 1 carta(s)

### on_enter_play ⟶ elige J0 (13)

- **abadon** — abadon
- **akari** — Elige cuál de estas cartas va a tu mano (el resto va al Cementerio)
- **capitan obrien** — Elige un Oro o una carta de coste 2 o menos para Convertir
- **Diabolista de Ébano** — Diabolista de Ébano: elige un Aliado que controles: pierde su habilidad y es Destruido
- **gran kraken** — Juega uno de estos Aliados de coste 1 sin pagar su coste
- **Lamec** — Lamec: Destierra dos cartas de tu mano
- **miguel** — Descarta 2 carta(s)
- **Rey de los Loçolicos** — Rey de los Loçolicos: Baraja una carta de tu mano en tu Castillo
- **rogue mecha** — Descarta 1 carta(s)
- **Rugiaevit** — Rugiaevit: elige una carta que controles: pasa a ser un Tótem sin habilidad del oponente
- **Ursitoare** — Ursitoare: Baraja una carta de tu mano en tu Castillo
- **Vâlve Albe** — Descarta 1 carta(s)
- **Ángel Jeremiel** — Ángel Jeremiel: elige 2 cartas de tu mano — se convierten en Tótem del oponente

### Talismán ⟶ elige J0 (5)

- **Corromper** — Corromper: elige una carta de la mano oponente
- **espectros vindicantes** — Descarta 1 carta(s)
- **koi dragon** — Mazo 0-1
- **Seducción** — Roba hasta 3 cartas (0 robadas): clic en tu Castillo para robar una — N para no robar más
- **viaje al oeste** — Descarta 2 carta(s)

### on_enter_play ⟶ sin selección abierta (3)

- **Alicia en Wonderland**
- **jangseung**
- **malleus maleficarum**

### on_attack ⟶ elige J0 (2)

- **gran kraken** — Juega uno de estos Aliados de coste 1 sin pagar su coste
- **Remiel** — Descarta 1 carta(s)

### Talismán ⟶ sin selección abierta (2)

- **contra el caos**
- **momificar**

### on_damage_dealt ⟶ elige J0 (2)

- **malafar sp** — Descarta 1 carta(s)
- **vinci y yang** — vinci y yang

### on_leave_play ⟶ elige J0 (2)

- **apsara** — Descarta 1 carta(s)
- **baron de gossler** — Descarta 1 carta(s)

### on_block ⟶ elige J0 (1)

- **al-ahmar** — Descarta 1 carta(s)
