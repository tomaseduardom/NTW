# Revisión de los mazos guardados (presets)

Mazos revisados: 169 (ezequiel), 170 (talisman-control), 164 (sombra), 174 (heroe),
175 (bestia-plaga) y 176 (douglas). Son 132 cartas distintas.

Método: busqué en el código rastros de cada frase de cada carta. Las que no tienen ninguno
aparecen abajo. Revisé una por una para descartar falsas alarmas (por ejemplo, "Cuando
juegues este Talismán, Destiérralo" o "Roba una carta" las resuelve una regla general).

Nada de esto se probó en una partida: hay que verificarlo jugando.

Estado: ✅ hecho · ⏳ falta · ⏸ para después (pedido del usuario)

## Faltan

Nada de la lista original. Falta probarlo todo jugando.

## Comienzo de fase (hecho 2026-10-18)

✅ "Puedes jugarlo al comienzo de cualquier Fase" (nyssara cautiva, Supremacia Kaiju, ~40 cartas) y
"Puedes jugarlo en la Fase Final" (sombrerero loco y otras): ventana de comienzo de fase
(scripts/core/game/PhaseStartWindow.gd). Se abre al comienzo de cada fase de los dos turnos solo
si alguien tiene una carta así y la puede pagar; empieza el activo, se alterna tras cada carta,
termina cuando los dos pasan; 5 s por turno de palabra (Anfitrión y Remoto). "En la Fase Final"
sin "tu" = la de los dos; "en tu Vigilia o Fase Final" = la tuya; "Fase Final oponente" = la del rival.
⏳ Falta: el descuento de pegana/leng/casa de opio en el turno oponente.
## Hecho

| Carta | Qué se hizo |
|---|---|
| Ira | ✅ Un Aliado gana Furia, Imbloqueable, 3 de Fuerza y hace daño al Destierro por el turno. ✅ Desde el Cementerio: Desterrarla para +1 de Fuerza y que su ataque no pueda ser cancelado. |
| el monstruo | ✅ Botar dos cartas: hasta dos Aliados ganan Furia y 1 de Fuerza por el turno. |
| Maldición Vudú | ✅ Solo en tu turno. ✅ Cancela una habilidad (si hay una del oponente en la pila) o una carta en juego pierde su habilidad por el turno. ✅ En tu Fase Final tus Oros van al Oro Pagado. ✅ Desde el Cementerio: Desterrarla para Barajar o Desterrar una carta de un Cementerio. |
| Seducción | ✅ Elegir: cada jugador Roba hasta tres (el oponente Destierra dos del tope por cada una), o cada jugador pone un Oro de su mano en su Oro Pagado (el del oponente sin habilidad por el turno). |
| el huascar | ✅ El portador duplica su Fuerza y tus demás Aliados ganan Fuerza igual a su coste. ✅ Al entrar, un Oro no se agrupa el próximo turno. ✅ Una vez por turno, Desterrar hasta un Arma o Tótem en juego y Robar dos. |
| Linaje Maldito | ✅ Dado: par = sin daño de combate hasta tu próximo turno y el oponente Destierra cuatro; impar = sin daño directo y hasta dos Aliados +2 (por el turno) y Furia. |
| Trono del Cielo | ✅ Cuenta como dos Oros si el oponente generó o puso más de un Oro en su turno anterior. |
| Abu Simbel | ✅ Al entrar, cada jugador recupera el control de sus cartas; mientras esté, nadie gana el control de cartas ajenas. |
| Sidhes del Bosque | ✅ Respuesta a buscar en un Castillo: nombrar dos cartas que no puede buscar, ver lo que busca, Robar una o subir un Aliado. |
| manuel rodriguez | ✅ "Al comienzo del turno" también en el turno del oponente. |
| shade | ✅ El ataque de tus Aliados no puede ser cancelado el turno en que entra. |
| nu-galahad | ✅ Las habilidades de tus Armas no pueden ser canceladas. |
| Nefandos | ✅ Tus demás Aliados no pueden ser Desterrados y hacen daño de combate al Destierro. |
| dulce canasta | ✅ En tu Reserva, los Aliados de coste 1 o menos (de ambos jugadores) no pueden ser Desterrados. |
| sable corto | ✅ Indesterrable ahora se respeta al Desterrar (antes no se revisaba en ningún lado). |
| Camino del Guerrero | ✅ Solo se juega si los Aliados que controlas más los de tu mano suman cuatro. |
| Cañón Helios | ✅ Cuando el portador ataca, eliges un Aliado oponente que lo bloquea (se asigna al entrar a Bloqueo). |
| la esmeralda | ✅ Al comienzo de cada turno (los dos), el oponente Baraja una de su mano; con otra Arma, Robas dos. |
| Aegishjalmur | ✅ Se eligen dos efectos distintos. |
| Armadura Dorada | ✅ Prevención desde el juego (Desterrarla) o desde la mano (pagar un Oro): tus Aliados afectados por ese efecto, o un Aliado Anulado. |
| Dos de Cada Uno | ✅ Buscas una carta (no Talismán) con otra copia en tu Castillo y la otra copia sale sola. ✅ Prevención desde la mano (pagar un Oro): hasta dos cartas de coste 1 o menos del mismo tipo. |
| Supremacia Kaiju | ✅ Barajar y/o Desterrar hasta tres de los Cementerios, buscar cualquier carta y el próximo Oro del oponente entra sin habilidad. |
| Viejo del Saco | ✅ Al entrar o atacar: convierte el tope de un Castillo o una carta de coste 1 o menos en un Aliado de Fuerza 2 con Furia, Imbloqueable y daño al Destierro, bajo tu control (antes caía en el patrón de Sherlock Holmes). |
| Escritura Sagrada | ✅ Ese turno, al tocar tu Castillo ves las dos primeras (como el Cementerio) y juegas las de coste 1 o más pagando su coste; los Oros van solos al fondo. El Remoto lo hace con un botón sobre la carta. |

Además: la Prevención ahora le pregunta al Remoto (antes el jugador 1 decidía al azar, como el bot) y también encuentra Armas equipadas y cartas de la mano.

## Mazo 177 (eterno estandar) — 2026-10-18

36 entradas; 23 ya estaban en los mazos de arriba. De las 13 nuevas, ya funcionaban:
Ciempiés-SP, Shub-Niggurath, Terminal P-12 (la protección) y la entrada de ngenechen,
Escudo de Vlad III y Carcosa (su "Bota cuatro").

| Carta | Qué se hizo |
|---|---|
| fortaleza hoshi | ✅ Al entrar muestra hasta dos Tótem de coste 2 o menos de distinto nombre y los juega gratis (el resto se baraja). ✅ Botón: Desterrar del tope de un Castillo tantas como Tótem controles. |
| tenshi z | ✅ Botón: convertir hasta dos cartas de coste 2 o menos en Tótem sin habilidad y ganar su control (las Armas de un Aliado convertido van al Cementerio). |
| ngenechen | ✅ Al comienzo del turno oponente (solo ese): genera un Oro y Roba dos. ✅ Prevención: Barajar una carta de tu mano, una vez por turno. |
| Quicaví | ✅ Botón: una carta de tu Cementerio gana Exhumar y no recibes daño de combate, hasta tu próximo turno. |
| Ángel Redentor | ✅ Al entrar o salir: Descartar para buscar una del mismo tipo. ✅ Un Oro por el turno en cada Agrupación (las dos). |
| Ciudad de los Césares | ✅ Al entrar o salir: Barajar hasta una carta oponente de coste 3 o menos y Robar dos. ✅ Botón: Barajar de la mano para Anular o Desterrar una de coste 1 o menos, o pagar un Oro para Anular una de coste 2 o más. |
| Carcosa | ✅ Al entrar y al comienzo del turno oponente: Desterrar una carta que no sea Oro, o mirar la mano y Desterrar un Talismán; Roba una. |
| Terminal P-12 | ✅ En tu Reserva, el oponente no puede mirar tu mano ni tu Castillo. ✅ Por turno: hasta dos cartas buscadas y dos habilidades usadas fuera del juego. |
| Ángel Jeremiel | ✅ Al entrar: el oponente elige dos de su mano, quedan como tus Tótem sin habilidad en tu Línea de Defensa. ✅ Botón: Destruir un Tótem tuyo para ganar el control de una carta oponente de igual o menor coste. |
| Pan de Muerto | ✅ Botón: pagarlo para buscar un Talismán o Tótem de coste 2 o más y jugarlo con un Oro menos. ✅ Hasta quince cartas Botadas/Desterradas por Castillo por turno. ✅ Tus Aliados son Indestructibles mientras bloquean. |
| Escudo de Vlad III | ✅ Cuando una carta va a un Cementerio, puedes Desterrarla (una vez por turno). ✅ Todos los Aliados en juego pierden 1 de Fuerza. |

Además: "al comienzo del turno" ahora distingue "de tu turno" / "del turno oponente" / a secas (antes ngenechen disparaba en los dos turnos y Carcosa tomaba siempre la primera oración).
