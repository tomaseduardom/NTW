# Revisión del mazo 170 (Talisman - Control)

Lista de lo que falta implementar o revisar, carta por carta. Se actualiza a
medida que se avanza. Estado: ✅ hecho · 🔧 en curso · ⏳ pendiente · ❓ dudoso
(revisar en partida) · ⏸ para después (pedido del usuario).

## Pendiente "para después"

- ⏸ **"Puedes jugarlo al comienzo de cualquier Fase"** (Nyssara Cautiva ×2,
  Rey de los Loñolicos ×3) y **"Puedes jugarlo en la Fase Final"**
  (Sombrerero Loco ×3). El usuario lo verá luego.

## Cartas sin implementación (no aparecen en el código)

| Carta | Cant. | Qué falta | Estado |
|---|---|---|---|
| Reina Nyssara | 2 | Una vez por turno: busca un Talismán en un Castillo, juégalo -1 Oro (mín 0) y Roba dos. Ganar habilidades de Aliado oponente que sale por Talismán. | ⏳ |
| Nyssara Cautiva | 2 | Entra o sale: puedes buscar un Talismán en un Castillo, juégalo pagando su coste y Roba una. En tu Vigilia, una vez por turno: el oponente Bota una por cada Aliado que controles. | ⏳ |
| Rey de los Loñolicos | 3 | Entra: el próximo Talismán del turno -1 Oro (mín 1) y no puede ser Anulado; Roba una; los jugadores Barajan una carta de su mano. | ⏳ |
| Ursitoare | 2 | Entra: puedes Barajar un Aliado tuyo y una carta oponente de coste igual o menor; Roba dos; los jugadores Barajan una carta de su mano. | ⏳ |
| Matriz V | 1 | Entra: Roba una y hasta dos cartas tuyas ganan Indesterrable. En Reserva: el oponente no dispara habilidades de coste 0-1 salvo que Destierre una de su mano. | ⏳ |
| Alicanto | 1 | Respuesta a recibir daño: Desterrarlo para prevenir; luego convertir una carta de la mano en Oro sin habilidad a tu Oro Pagado. Aliados de coste 2+ pagados con él no pueden ser Anulados. | ⏳ |
| Escritura Sagrada | 1 | Entra: juegas mostrando las dos primeras del Castillo y puedes jugar las de coste 1+ pagando; Oros mostrados al fondo. Subirlo a la mano o convertirlo para prevenir daño. | ⏳ |
| Yomiel | 1 | Cuando sea Barajado desde tu mano: busca un Talismán de coste 1+ en tu Castillo, juégalo pagando y Baraja una de tu mano. | ⏳ |
| Visión de Enoc | 1 | Se baraja en tu Castillo al resolverse. Anula un Talismán de coste 2- o previene que un Aliado sea afectado. Al Botarla por daño: Baraja hasta cinco de los Cementerios. | ⏳ |
| El Gran Descenso | 1 | El oponente Descarta tres al azar; por cada una puede Desterrar cuatro del tope para recuperarla y tú Robas una. Solo pagando su coste impreso. | ⏳ |
| Envidia | 1 | Anula una carta de coste 3-, juégala bajo tu control gratis. En Cementerio: si tienes menos cartas en mano, Desterrarlo para Robar. | ⏳ |
| Colapso Global | 1 | Respuesta a que el oponente mire tu mano o busque: Desterrar una de tu mano para jugarlo gratis. Previene eso y Robas una. | ⏳ |

## Cartas con partes por revisar

| Carta | Qué revisar | Estado |
|---|---|---|
| Red de Plata | "Si tenía coste 2 o menos, Destierra ese Aliado"; desde el Cementerio, Aliado pierde la habilidad por el turno. | ⏳ |
| Cuervo Nocturno | "Si atacaste en tu turno anterior, tiene Exhumar en tu Cementerio". | ⏳ |
| Escarapela Nacional | "Al comienzo de la Vigilia oponente... puedes ponerlo en juego". | ⏳ |
| Drácula | "Desterrarlo de tu mano o Cementerio para cancelar el ataque de hasta dos Aliados". | ⏳ |
| Signo Amarillo | Convertirlo para cancelar la habilidad de una carta fuera del juego o un Oro. | ⏳ |
| Espada Vikinga | Pagar un Oro y Desterrarla de la mano para Anular una carta de coste 1. | ⏳ |
| Diadema Celestial | Entra: muestra hasta un Aliado y un Talismán a la mano. | ⏳ |

## Hecho

(se va llenando)
