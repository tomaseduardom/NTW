# Revisión del mazo 170 (Talisman - Control)

Lista de lo que faltaba implementar, carta por carta, y el estado de cada cosa.
Nada de esto se probó en una partida real: hay que verificarlo jugando.

Estado: ✅ hecho · ⏳ pendiente · ⏸ para después (pedido del usuario)

## Cambio grande: Anular y Cancelar sobre la pila

Antes, "Anula X" destruía una carta que ya estaba en juego: un Talismán de
respuesta nunca anulaba la carta o habilidad a la que respondía. Ahora
(`scripts/core/effects/StackAnnul.gd`):

- Los Talismanes de Anular/Cancelar buscan en la pila el objeto del oponente
  que su texto permite (tipo y coste). Una **carta jugada** se Anula: el
  Aliado se destruye sin su "Cuando entra en juego", el Talismán va al
  Cementerio. Una **habilidad** se Cancela: no ocurre.
- Si no hay nada válido en la pila, el Talismán no hace nada (y de todos modos
  solo se puede jugar en respuesta a algo del oponente).
- Respeta "No puede ser Anulado" y "sus habilidades no pueden ser canceladas".

Cartas que lo usan: Cienpiés, Sacrificio Solar, Red de Plata, Dragón Dorado,
Culto a la Muerte, Envidia, Visión Heroica, Visión de Enoc, El Caleuche,
Signo Amarillo, Espada Vikinga.

## Para después

- ⏸ **"Puedes jugarlo al comienzo de cualquier Fase"** (Nyssara Cautiva ×2,
  Rey de los Loñolicos ×3) y **"Puedes jugarlo en la Fase Final"**
  (Sombrerero Loco ×3).

## Hecho

| Carta | Qué se hizo |
|---|---|
| Reina Nyssara | ✅ Una vez por turno: busca un Talismán en un Castillo (selector del tablero, solo los que puedes pagar), juégalo -1 Oro (mín 0), Roba dos. ✅ Gana las habilidades de un Aliado oponente que sale del juego por un Talismán (una vez por turno). |
| Nyssara Cautiva | ✅ Entra o sale: puedes buscar un Talismán en un Castillo, jugarlo pagando y Robar una. ✅ Vigilia: el oponente Bota una por cada Aliado tuyo. |
| Rey de los Loñolicos | ✅ Próximo Talismán del turno -1 (mín 1) y no puede ser Anulado; Roba una; los jugadores Barajan una de su mano. |
| Ursitoare | ✅ Barajar un Aliado tuyo y una carta oponente de igual o menor coste (opcional); Roba dos; Barajan una de la mano. |
| Matriz V | ✅ Entra: Roba una y hasta dos cartas tuyas ganan Indesterrable. ✅ En Reserva: habilidades disparadas de cartas oponentes de coste 0-1 solo si Destierra una de su mano. |
| Alicanto | ✅ Antes del daño de combate: Desterrarlo para prevenirlo; luego puedes convertir una carta de tu mano en Oro sin habilidad en tu Oro Pagado. ✅ Aliados de coste 2+ pagados con él no pueden ser Anulados. |
| Escarapela Nacional | ✅ Al comienzo de la Vigilia oponente, si no controlas más Oros, puedes ponerla en juego desde la mano; en tu próximo turno no puedes poner Oros desde la mano. |
| Escritura Sagrada | ✅ Prevenir el daño de combate subiéndola a la mano o convirtiéndola. |
| Yomiel | ✅ Al ser Barajado desde tu mano (por los efectos de Barajar de la mano de este mazo): busca un Talismán de coste 1+ y juégalo pagando; Baraja una de tu mano. |
| Visión de Enoc | ✅ Anular un Talismán de coste 2- en la pila o proteger un Aliado tuyo del próximo efecto oponente; se Baraja en tu Castillo al resolverse; al Botarla por daño, Barajar hasta cinco de los Cementerios. |
| El Gran Descenso | ✅ El oponente Descarta tres al azar; por cada una puede Desterrar cuatro del tope para recuperarla y tú Robas una. |
| Envidia | ✅ Anula una carta de coste 3- y la juegas bajo tu control gratis. ✅ Desde el Cementerio, con menos cartas en mano: Desterrarla para Robar. |
| Colapso Global | ✅ Cuando el oponente va a buscar o mirar tu mano: jugarlo Desterrando una de tu mano (o pagando); se previene y Robas una. |
| Red de Plata | ✅ Anula/cancela; si costaba 2 o menos, Destierra ese Aliado. |
| Culto a la Muerte | ✅ Anular+Desterrar (no Aliado, coste 2-) o Cancelar + el oponente no puede usar habilidades de cartas con ese nombre este turno. |
| Diadema Celestial | ✅ Tus bloqueadores +1; los Aliados oponentes pierden Imbloqueable; si la Botas por daño, se deja de Botar y se Destierra. |
| Cuervo Nocturno | ✅ Exhumar solo si atacaste en tu turno anterior. |
| Signo Amarillo | ✅ Convertirlo para cancelar la habilidad de una carta fuera del juego o de un Oro. |
| Espada Vikinga | ✅ Desde la mano: pagar un Oro y Desterrarla para Anular una carta de coste 1. |
| El Caleuche | ✅ Rama de respuesta: carta oponente jugada sin pagar su coste o que no puede ser Anulada entra sin habilidad (Talismán: sin efecto). |
| Fisión Nuclear, Sariel, Sombrerero Loco, Tempilcahue, Sacrificio Solar | ✅ (sesión anterior) |

## Pendiente

| Carta | Qué falta |
|---|---|
| Yomiel | Otros efectos que Barajan desde la mano (fuera de este mazo) todavía no avisan a Yomiel. |
| Matriz V | El peaje solo aplica a habilidades disparadas, no a activadas. |

## Nota: arreglo ajeno

El commit `2edfb87` (hover en el buscador de Alicia, retorno a la mano) no
compilaba y el juego no arrancaba: `get("hover_enabled", true)` (get() acepta
un solo argumento) y `to_global()` en un Control. Se corrigió en `0199c3c`
con el cambio mínimo.
