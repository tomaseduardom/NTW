# Bitácora del código

Copia textual de los comentarios con historia (fechas, "bug real", "a pedido del usuario"...) que
había en `scripts/` el 2026-10-19, antes de condensarlos (punto 5 de la revisión de código). En el
código queda un comentario corto (qué hace y por qué); el detalle de cada decisión y cada bug está aquí.
Ordenado por archivo y, dentro de cada uno, por función (con la línea de entonces).

## `scripts/core/ai/EasyBotController.gd`

### `(nivel de archivo)` — línea 3

> EasyBotController — IA fácil para el jugador 1 (oponente): decisiones al
> azar entre las jugadas legales, sin estrategia. Primera IA real del motor
> (2026-09-07) — antes PhaseFlowController._opponent_auto_pass() saltaba
> directo a Fase Final sin jugar nada.
>
> Alcance v1 (a propósito, no es que falte terminar): solo pone Oro y juega
> Aliados de la mano — Armas/Talismanes/Tótems quedan fuera (requieren
> elegir portador, tienen restricciones de solo-respuesta, o son poco
> frecuentes). Nunca actúa en ventanas de prioridad instantáneas (Guerra de
> Talismanes/respuesta) ni bloquea — sigue el patrón ya establecido en
> decenas de cartas ("el bot no usa esta habilidad/elección todavía").
>
> GoldManager.play_card()/_place_card_as_gold()/_play_card_to_field() están
> hardcodeados a jugador 0 (confirmado por grep, sin costuras para
> generalizar) — a propósito NO se tocan. Esta clase escribe su propia
> lógica, paralela y más simple, operando directo sobre los contenedores
> opponent_*/_opponent_fan y GameState/CardManager (ya genéricos por
> player_id), mismo criterio que put_gold_directly_in_reserva/_pagado()
> (GoldManager.gd) ya usa para el jugador que sea. Sí reutiliza los
> chequeos/registros de GoldManager que SON genéricos (_no_more_cards_
> violation, _card_play_locked, _errante_violation, _play_limit_violation,
> _register_talisman_totem_tax, _register_talisman_second_play_tax,
> _register_gold_placed, update_gold_containers_spacing) en vez de
> reimplementarlos — auditoría 2026-09-07 encontró que la primera versión
> de este archivo se los saltaba todos en silencio.

### `_wait_until_settled` — línea 34

> Espera a que termine lo que se está resolviendo (2026-10-17, bug real
> reportado por el usuario: respondió con Dragón Dorado y, mientras elegía
> qué Barajar de su mano, el bot siguió atacando y pasando de turno). Hay
> algo en curso si hay un efecto resolviéndose (EffectContext), la Pila
> está procesando, o el humano está eligiendo una carta/búsqueda.

### `_place_gold_card` — línea 108

> Coloca 'gold_card' (ya validada por el llamador) como Oro del
> jugador 1 — extraído de _place_gold_if_possible() (2026-09-11,
> multiplayer remoto) para que RemotePlayerController pueda reusar la
> misma mecánica con una carta ELEGIDA por la persona real, en vez de
> 'la primera encontrada' que asume el bot.

### `_place_gold_card` — línea 114

> Las cartas en _opponent_fan están esta_oculta=true (dorso, mano oculta
> del rival) — hay que voltearla al entrar en juego, igual que cualquier
> Oro en Reserva es visible cara arriba para ambos jugadores (2026-09-08,
> bug real reportado por el usuario: no se veían las cartas del bot).

### `_place_gold_card` — línea 135

> Consistente con _play_ally()/play_free_ally_from_data()/
> put_free_gold_in_pagado_from_data() (las 3 SÍ lo emiten) — sin esto,
> GameStateBroadcaster (multiplayer remoto, 2026-09-11) no se enteraba de
> que el Oro del jugador 1 entró en juego, y ContinuousEffectManager/
> CardEffectSystem tampoco recalculaban nada para él.

### `_pay_oro_for_bot` — línea 144

> Paga 'coste' Oro real del bot (2026-09-09, bug real reportado por el
> usuario: al jugar el bot una carta, GameState.pagar_oro() actualizaba el
> contador pero nunca movía ninguna carta de Oro física de Reserva a Oro
> Pagado — a diferencia del camino humano, GoldManager.pagar_coste(), que
> sí mueve nodos reales. Sin esto, la Reserva del bot se vaciaba
> numéricamente pero se veía exactamente igual en pantalla para siempre).
> El bot no elige CUÁL Oro gastar (no tiene cartas que dependan de eso,
> tipo Monitor Araucano) — toma los primeros que encuentra en su Reserva.

### `_play_ally` — línea 223

> 2026-09-19 (arquitectura.md §10.53, bug real reportado por el usuario:
> "el bot jugó una carta y no me saltó la ventana para poder anular").
> GoldManager.play_card() (línea ~1421, 2026-09-10) ya abre la Pila de
> Respuesta Universal para CUALQUIER Aliado/Arma/Tótem/Oro que juegue el
> HUMANO, justo antes de que dispare su propio "Cuando entra en juego" —
> esta función (el camino equivalente del BOT) nunca se actualizó para
> hacer lo mismo, así que ninguna carta que jugara el bot abría nunca
> ventana real para el humano, con o sin disparador de entrada. Mismo
> criterio exacto que GoldManager: si se anula/cancela aquí, la carta va
> directo al Cementerio sin llegar a disparar su ETB.

### `_play_ally` — línea 250

> Almirante Akari — "cuando tu oponente juegue cartas, puedes Anular"
> (2026-09-09): el bot juega esta carta, así que el HUMANO (su rival) es
> quien puede responder con Akari — ver EffectController.offer_counter_annul().

### `play_free_ally_from_data` — línea 258

> Variante de _play_ally() para triggers que juegan un Aliado del bot
> SIN pasar por su mano ni pagar su coste (2026-09-09, p.ej. Tangata Manu/
> Perder la Razón revelando el tope del propio Castillo) — el llamador
> (LookRevealPatternsA.gd) ya sacó card_data de donde corresponda, aquí solo
> falta crear el nodo y ponerlo en juego. Bug real reportado por el
> usuario: estos patrones antes llamaban GoldManager.play_card_for_free(),
> que está hardcodeado a jugador 0 (card.owner_id=0, contenedores
> player_*), así que el Aliado del bot terminaba apareciendo del lado del
> humano. Solo Aliados (mismo alcance v1 que el resto de esta clase — el
> llamador ya filtra por tipo antes de elegir).

### `play_free_ally_from_data` — línea 291

> 2026-09-19, §10.53 — mismo motivo que _play_ally() (ver comentario ahí):
> GoldManager.play_card_for_free() sí abre esta misma ventana para el
> humano vía _trigger_enter_play() compartido; este camino del bot nunca
> lo tuvo.

### `put_free_gold_in_pagado_from_data` — línea 311

> Variante de la rama Oro de GoldManager._trigger_enter_play() para el
> bot (2026-09-09, Perder la Razón: 'pon un Oro de ahí en tu Oro Pagado')
> — _trigger_enter_play() está hardcodeado a jugador 0 (emit_signal/evento
> con player_id=0 fijo, ver comentario en play_free_ally_from_data()), así
> que no se puede reusar directo para el bot.

### `put_free_gold_in_pagado_from_data` — línea 330

> 2026-09-19, §10.53 — mismo motivo que _play_ally()/play_free_ally_from_data():
> la carta ya está colocada visualmente (mismo criterio que GoldManager.
> _trigger_enter_play() con el humano — la ventana no bloquea la
> colocación física, solo los efectos de estado que siguen), pero
> agregar_oro_pagado() queda DESPUÉS de la ventana para no tener que
> revertirlo si se anula/cancela aquí.

### `try_respond_with_activated_ability` — línea 352

> Capa 2 de la Pila de Respuesta Universal (2026-09-09): dentro de la
> ventana de respuesta genérica (ver ResponseWindowHandler._bot_pass_
> after()), el bot busca una habilidad ACTIVADA legal entre sus propias
> cartas en juego y decide, al azar, si la usa — mismo criterio simple
> que el resto de sus decisiones (sin heurística de "conviene o no").
> Devuelve true si activó algo (empuja un objeto a ActionPipeline, que ya
> lo detecta solo como "hubo respuesta" y le abre su propia ventana de
> vuelta al rival — no hace falta orquestar nada más aquí).
>
> Alcance: habilidades sin coste, "una vez por turno", Oro o Girar.
> ActionPipeline.activate_ability()/can_activate_ability() ya distinguen
> controller_id 0 (humano, GoldManager con Oro Virtual/restringido) de
> cualquier otro (Oro físico simple vía GameState — 2026-09-10). Girar
> (TAP) no depende de qué jugador es, siempre actuó sobre el Node de la
> carta. Descarte queda FUERA todavía: el bot no tiene su mano
> representada como Nodos, así que no hay de dónde elegir qué
> descartar.

### `try_respond_with_activated_ability` — línea 393

> "Una vez EN tu turno" (2026-09-13, ver arquitectura.md §10.11):
> esta función SOLO corre dentro de una ventana de respuesta
> (ver docstring arriba), así que por definición nunca es el
> momento correcto para esta variante — más restrictiva que
> "una vez por turno" en cuándo se puede usar, no solo en
> frecuencia.

### `try_respond_with_activated_ability` — línea 412

> Don de Amma (2026-09-13, bug real reportado por el usuario): este
> escaneo genérico solo mira cost_type (NONE/ONCE_PER_TURN/GOLD/TAP), no
> si la habilidad necesita el manejador especial de
> AbilityButtonPatternsA.gd — "Puedes Desterrar un Oro con habilidad de
> tu Reserva. Luego, busca un Oro..." calza en ONCE_PER_TURN igual que
> cualquier otra, así que caía en ActionPipeline.activate_ability()
> genérico → TargetedEffectExecutor._execute_targeted_banish(), que
> SIEMPRE apunta a un Aliado ("Elige un Aliado para desterrar") sin
> saber que el objeto real es un Oro con habilidad de la Reserva.
> _activate_don_de_amma() (SearchAbilityHandler_AI.gd) ya soporta
> owner_id 1 desde que se escribió — solo faltaba que este scan lo
> invocara en vez del genérico.

### `take_ataque_actions` — línea 453

> _declare_attacker() ya es agnóstico de jugador (controller_id
> decide el contenedor) y hace TODO lo necesario: valida,
> reparenta a Línea de Ataque real (set_zone incluido) y marca
> el tinte visual de "atacando" — reusarlo evita reimplementar
> ese avance a mano y desincronizar zona/visual (auditoría
> 2026-09-07: la primera versión solo llamaba a GameManager.
> declare_attacker(), sin mover la carta de contenedor).

### `reset_gold` — línea 478

> el huascar (2026-10-18): "no puede ser agrupado el próximo turno"

## `scripts/core/ai/RemotePlayerController.gd`

### `(nivel de archivo)` — línea 5

> RemotePlayerController — reemplaza a EasyBotController cuando el jugador 1
> es una PERSONA real conectada por red (NetworkClient), no una IA sin
> estrategia. Extiende EasyBotController y sobreescribe cada punto de
> DECISIÓN (Vigilia, Ataque, respuesta con habilidad activada) para que en
> vez de elegir al azar, le pregunte al Remoto por red y espere su
> respuesta — misma superficie pública que la clase base, así que ningún
> llamador existente (PhaseFlowController, ActionPipeline,
> ResponseWindowHandler, LookRevealPatternsA.gd — todos invocan
> `_main._easy_bot.<método>` sin saber qué hay del otro lado) necesitó
> cambiar una sola línea. Ver docs/plans/2026-09-09-multiplayer-remoto-
> design.md e iterative-booping-abelson.md (Fase B).
>
> Alcance de ESTE incremento (Fase B, "bucle de turno básico" — mismo techo
> que el bot hoy, pero una persona real detrás): poner Oro, jugar Aliados de
> la mano, declarar atacantes, responder ventanas con habilidades activadas
> sin costo de Descarte, y el mulligan inicial real (que hoy ni siquiera
> existe como decisión para el jugador 1). La paridad completa (cualquier
> carta, cualquier elección de SelectionManager) es Fase C, todavía no
> empezada — reset_gold()/_pay_oro_for_bot()/play_free_ally_from_data()/
> put_free_gold_in_pagado_from_data() se heredan tal cual de la clase base
> (no hay decisión real que preguntar en Agrupación, y los triggers "juega
> gratis" siguen sin alcanzar al jugador 1 por network hasta Fase C).
>
> Protocolo: cada método manda al Remoto un mensaje {"op":"prompt",
> "kind":...} con los datos que la persona necesita ver — su propia mano/
> campo NO está oculta para ella (aunque en la pantalla del Anfitrión se
> vea como 'oponente' con esta_oculta=true, eso es solo la vista LOCAL del
> Anfitrión) — y espera un {"op":"intent","kind":...} de vuelta. Las
> cartas se identifican por get_instance_id() (mismo criterio ya usado por
> turn_registry en otras partes del proyecto para distinguir copias
> físicas durante la sesión) — estable mientras el Node exista, no
> persiste entre partidas ni hace falta que persista.
>
> Decisión de alcance (2026-09-11, sin protocolo de instrucciones
> incremental completo todavía): en vez de streaming continuo de
> move_card/reveal_card por cada transición de zona (la forma "completa"
> descrita en el diseño), cada prompt de este archivo embebe un snapshot
> de los datos que el Remoto necesita en ESE momento (su propia mano/
> campo, más lo público). Esto respeta la niebla de guerra (nunca se
> manda la mano/mazo ocultos del Anfitrión) y alcanza para que el Remoto
> tome decisiones legales, pero significa que el Remoto no ve en tiempo
> real lo que el Anfitrión hace en SU PROPIO turno (solo se entera en el
> próximo prompt que le toque). El streaming incremental completo (fidelidad
> visual total) queda pendiente — ver nota en el plan.

### `_await_intent` — línea 51

> 2026-09-30: lógica movida a NetworkClient.await_intent() (la necesita
> también SelectionManager.gd para la Fase 3 del plan de paridad) — este
> wrapper se deja tal cual para no tocar los 5 llamadores existentes de
> este archivo.

### `_card_public_data` — línea 72

> Datos de UNA carta propia del Remoto para mandarle por red — no está
> oculta para su propio dueño, aunque en la pantalla del Anfitrión se vea
> con esta_oculta=true (eso es solo la vista LOCAL del Anfitrión, no un
> límite real de información para la persona a la que pertenece).
> 2026-10-07, a pedido del usuario ("no sale mi mulligan bonito, el
> abanico de cartas está todo escrito"): antes mandaba solo 5 campos
> curados (nombre/coste/tipo/habilidad), suficientes para los prompts de
> puro texto pero no para dibujar la carta real — ahora manda el
> card_data COMPLETO (mismo dict que usa Card.load_from_data() en
> cualquier otro popup del proyecto, p.ej. GoldManagerTax._open_cemetery_
> reveal_popup()), con card_id agregado encima para las respuestas por
> red (no es un campo nativo de card_data).

### `_affordable_cards_in_hand` — línea 115

> =============================================================================
> MULLIGAN (2026-09-11 — no existe llamador base: MulliganController._end_
> mulligan_phase() llama aquí directo, con chequeo de tipo, solo si hay un
> Remoto conectado; si no, sigue con draw_initial_hand() como siempre)
> =============================================================================

### `run_mulligan` — línea 150

> =============================================================================
> JUGAR ARMA/TALISMÁN/TÓTEM — mismo criterio que EasyBotController._play_ally()
> (heredado tal cual, arriba en este archivo no — vive en la clase base), pero
> para los 3 tipos de carta que el bot todavía no juega. Task 1.1-1.4,
> docs/plans/2026-09-20-remote-multiplayer-parity.md, Fase 1.
> =============================================================================

### `_play_talisman_remote` — línea 258

> GoldManager._play_talisman() (2026-10-13, §64): el mismo camino que el
> Anfitrión — antes este resolvía el efecto pero el Talismán se quedaba
> en la Línea de Apoyo (nunca iba al Cementerio/Destierro/Castillo).

### `take_vigilia_actions` — línea 310

> Habilidades activadas en su propia Vigilia (2026-10-12): antes el
> Remoto solo podía activarlas en ventanas de respuesta, así que las
> de "una vez en tu turno" (p.ej. Miguel) nunca le aparecían.

### `try_respond_with_activated_ability` — línea 409

> Camino viejo de respuesta (prompt 'response_window'). Desde 2026-10-11
> ya no lo usa ResponseWindowHandler contra un Remoto (ver
> on_priority_received()), pero se conserva por si algún otro llamador de
> la clase base lo invoca.

### `_collect_activatable_abilities` — línea 423

> Habilidades activadas que el Remoto puede usar ahora mismo: [{card, ability}].
> 2026-10-12: mismo filtro que los botones del Anfitrión
> (CardInspectionLayer.usable_abilities_for(card, 1)) — turno, prioridad,
> zona, costo, una vez por turno, Anular/Cancelar en turno rival. Incluye
> cartas de su mano con habilidades usables desde ahí.

### `_collect_activatable_abilities` — línea 452

> Cartas del Cementerio del Remoto con habilidad usable desde ahí
> (2026-10-13, Duelo Espacial; también Espada del Juicio, Visión Heroica,
> Drácula): el Cementerio no tiene Nodos, así que se crean Nodos temporales
> (fuera del árbol, igual que el visor del Cementerio del Anfitrión). Viven
> hasta la próxima consulta para que el intent pueda ubicarlos por card_id.

### `_abilities_payload` — línea 480

> 2026-10-07: card_data completo (no solo nombre/coste curados) para
> que RemoteMirrorController pueda mostrar la carta real, mismo
> criterio que el resto de los prompts (ver _card_public_data()).

### `_activate_chosen_ability` — línea 503

> Misma lógica que el botón del Anfitrión (patrones especiales incluidos,
> p.ej. Miguel) — 2026-10-12.

### `_activate_chosen_ability` — línea 513

> =============================================================================
> BOTÓN DE PASO SIMÉTRICO ONLINE (2026-10-11, a pedido del usuario)
> =============================================================================
> Cada vez que el J2 (el Remoto) recibe la prioridad en CUALQUIER ventana, el
> Anfitrión decide aquí qué hacer, con la misma regla que usa para el J1
> (PriorityManager.needs_real_decision()):
> - sin decisión real (respuesta a su propia carta, atacante en Bloqueo,
> pila recién vaciada) → pasa solo;
> - Ventana de Respuesta real → el Remoto ve su botón de paso con cuenta
> regresiva de 5s y puede responder con un Talismán instantáneo o una
> habilidad activada; al vencer el plazo, el Anfitrión pasa por él;
> - Guerra de Talismanes → puede jugar Talismanes/habilidades, sin plazo;
> - Bloqueo (defensor) → elige bloqueadores, sin plazo.
> El prompt viaja con window_id (= PriorityManager._window_generation) y la
> respuesta debe traer el mismo id: una respuesta tardía de una ventana que
> ya cerró se descarta sola, nunca se aplica sobre la ventana siguiente.

### `on_priority_received` — línea 561

> Comienzo de fase (2026-10-18): las cartas que su texto deja
> jugar ahora (PhaseStartWindow), cualquier tipo. 5 s, como el
> Anfitrión.

## `scripts/core/cards/CardDatabase.gd`

### `load_cards_from_external_api` — línea 77

> Carga cartas desde la nueva API externa. Ver ExternalApiClient.gd para
> el detalle del host/auth — load_cards_from_api() apunta al host viejo
> (localhost:3000), ya no disponible.
>
> Ediciones confirmadas por el dueño de la API (2026-08-18): imp, pb, fx,
> esc. Antes solo se pedían imp/esc (~2426 cartas) — pb y fx devuelven 0
> sin autenticar, así que probablemente requieren el token Bearer (ver
> ExternalApiClient.fetch_cards()).

### `load_cards_from_external_api` — línea 93

> state es Dictionary a propósito (2026-08-22): los lambdas de
> GDScript capturan variables locales POR VALOR — 'login_attempt_done'
> suelto nunca se actualizaba de verdad afuera del lambda y el 'while'
> colgaba para siempre en silencio (confirmado con un test aislado
> en Godot).

### `_create_card_from_api` — línea 257

> 2026-10-14, usuario: Zadquiel no dispara al atacar sino al hacer daño
> de combate (se distingue a propósito de "daño" a secas).

### `_parse_keywords` — línea 311

> Solo "Exhumar" o jugarse a sí misma desde el Cementerio (2026-10-17, bug
> real reportado por el usuario: Alto Prime decía tener Exhumar — antes
> bastaba "desde tu Cementerio" en cualquier parte, p.ej. "Desterrarlo
> desde tu Cementerio" o "poner este Aliado en juego desde tu Cementerio
> como un Aliado sin habilidad", que son otras habilidades).

### `load_cards_from_bundled` — línea 347

> 2026-10-12: el bundle viaja en el zip (tools/bundle_cards.ps1) y es la
> fuente común para Anfitrión y Remoto; las cartas del cache local que
> NO estén en el bundle (p.ej. bajadas con sync_cards.ps1 después de
> exportar) se suman igual, en vez de quedar ignoradas para siempre.

### `get_all_cards` — línea 475

> Mapea el número de edición embebido en el nombre de archivo CDN (p.ej. el
> "162" en ".../162_001_transformacion_secreta.webp") a la carpeta local en
> cartas_descargadas/. Solo estas 12 ediciones están descargadas localmente
> — el resto cae a dorso hasta que se descarguen (ver docs/audit-2026-08-13.html,
> "la mitad de las cartas no cargan visualización").
>
> IMPORTANTE — esta función asumía que `imagen` traía una carpeta
> ("{edicion}_{CARPETA}/archivo.webp"), pero el dato real es una URL PLANA
> sin carpeta ("https://.../{edicion}_{carta}_{slug}[_rareza].webp"). Por
> eso NINGUNA imagen local resolvía antes de este fix, para ninguna carta.

### `get_card_image` — línea 609

> 2026-09-11 (bug real reportado por el usuario: cartas cacheadas
> hace semanas se volvían a descargar de la red) — antes solo
> chequeaba "if image:", que es cierto para cualquier Image no-nulo
> aunque haya quedado vacío por una carga fallida; ahora exige que
> además tenga contenido real antes de darla por válida.

### `_build_cdn_url` — línea 702

> Recortes pendientes de aplicar tras descargar (2026-08-25): {card_id: Rect2i}
> — ver _unwrap_broken_cloudinary_fetch()/_on_image_request_completed().

### `_unwrap_broken_cloudinary_fetch` — línea 707

> Desenvuelve un proxy Cloudinary 'fetch' roto a la URL real de origen
> (2026-08-25): la cuenta de Cloudinary usada para las cartas custom/
> homebrew (drw7y27sm) bloquea el fetch remoto sin firmar (401 en TODAS
> sus imágenes, confirmado en vivo) — pero la imagen de origen (Shopify
> CDN) responde 200 directo.
>
> Cuando el fetch trae un recorte ('c_crop,x_X,y_Y,w_W,h_H/https://...'),
> varias cartas comparten UNA sola imagen de origen (una lámina con 2-3
> cartas lado a lado — confirmado: 'azi_1.png' aparece con x_0/x_256/x_512,
> tres cartas en la misma lámina) — no se puede usar la imagen de origen
> tal cual. El recorte real se reconstruye del lado del juego con
> Image.get_region() en _on_image_request_completed(), así que aquí se
> guarda el Rect2i en _pending_crops[card_id] para que ese callback lo
> recupere cuando la descarga termine.

### `_start_image_download` — línea 752

> [DIAG-TIMING] instrumentación temporal (2026-09-11) para confirmar si la
> demora percibida al robar cartas es de verdad tiempo de red (CDN) y no
> código — sacar una vez confirmado.

### `_on_image_request_completed` — línea 804

> [DIAG-TIMING] ver _download_card_image() — confirmado (2026-09-11): la
> demora es de red real, no código. Gateado, ya no hace falta por defecto.

### `_on_image_request_completed` — línea 831

> Reconstruir el recorte que hacía el proxy Cloudinary roto (2026-08-25):
> varias cartas custom comparten UNA imagen de origen con 2-3 cartas
> lado a lado — sin este recorte se vería la lámina completa en vez de
> solo esta carta. Ver _unwrap_broken_cloudinary_fetch().

### `run_smoke_test` — línea 993

> Detecta el formato real por los bytes mágicos (2026-10-11): antes se
> probaba webp → png → jpg a ciegas, y cada intento fallido imprimía
> ERRORs del motor en la consola (ERR_FILE_CORRUPT, "Not a PNG file")
> aunque la imagen terminara cargando bien como JPG.

## `scripts/core/cards/CardFactory.gd`

### `(nivel de archivo)` — línea 12

> (2026-08-28, corrección de terminología real de Mitos y Leyendas, a
> pedido del usuario): "cuando deje/dejar/abandona el juego" no existe
> como frase real — es "al salir del juego"/"cuando salga del
> juego"/"cuando sale del juego". Algunas cartas mezclan ambos conceptos
> en una sola oración ("cuando entra o salga del juego") — se agrega esa
> frase completa a los dos, pero OJO: esto solo la CLASIFICA en el
> primer tipo que la detecte, no dispara ambos triggers a la vez (eso
> necesitaría lógica aparte, no implementada todavía).

### `(nivel de archivo)` — línea 24

> "cuando muera"/"al morir" no existen como concepto real en el juego —
> se eliminaron (2026-08-28, a pedido del usuario).

### `(nivel de archivo)` — línea 31

> "infligir"/"inflija"/"inflige" no es terminología real (2026-08-28) —
> se reemplazó por "cuando haga daño de combate", la forma más común en
> el texto real de las cartas junto a "cuando haga daño" a secas.

### `(nivel de archivo)` — línea 35

> "cuando reciba daño"/"al recibir daño" no son la frase real — es
> "cuando fueras a recibir daño" (2026-08-28, a pedido del usuario).

### `_scan_and_apply_keywords` — línea 106

> KeywordManager es autoload — siempre existe (2026-08-28, "módulos
> gordos" punto 1: el fallback manual de abajo, _apply_keyword_flag_
> fallback(), era inalcanzable siempre; se sacó).

## `scripts/core/cards/DeckLoader.gd`

### `_ready` — línea 32

> (2026-08-28, "módulos gordos" punto 1): CardDatabase/CardFactory/
> GameManager son autoloads garantizados — se saca el cacheo redundante
> vía get_node_or_null() (CardFactory y GameManager tampoco se usaban
> en este archivo más allá de la asignación).

### `load_deck_from_external_data` — línea 53

> Carga un mazo obtenido de ExternalApiClient (API nueva, ver hallazgo
> de integración en docs/audit-2026-08-13.html). Usa un parser más
> defensivo que load_deck_from_data() porque la forma exacta de la
> respuesta de /external/my-decks/ no se pudo verificar sin credenciales.

### `_process_deck_data` — línea 122

> Alternativa: {"entries": [{"card_detail": {"myl_id": ...}, "quantity"}, ...]}
> (2026-08-24, mazos preset descargados de /decks/public/{id}/ — ver
> DeckSelector._get_preset_decks()). Mismo fallback que ya tenía
> _process_external_deck_data() para /external/my-decks/, pero aquí
> faltaba: los mazos locales solo miraban datos_json.main y fallaban con
> 'El mazo no tiene cartas en el main deck' aunque el archivo sí tuviera
> cartas, solo que en forma de entries en vez de datos_json.main.
>
> 2026-09-23, bug real confirmado con curl contra la API real: "id" en
> cada entry es la fila de ShadowForge (DeckEntry.id, ej. 25652), NO la
> carta — el myl_id real está anidado en entry.card_detail.myl_id (ej.
> "20584"). Usarlo directamente hacía que ningún mazo de ShadowForge
> cargara nunca sus propias cartas (caía siempre al mazo aleatorio de
> respaldo, en silencio).

## `scripts/core/cards/ExternalApiClient.gd`

### `(nivel de archivo)` — línea 2

> ExternalApiClient - Cliente para la nueva API de cartas/mazos (ShadowForge)
>
> Reemplaza la fuente vieja (localhost:3000, a la que ya no hay acceso).
> El dominio que se usaba como referencia (shadow-forge-deck.vercel.app) es
> solo el frontend Angular; el backend real es un Django/DRF aparte:
> https://iterva.pythonanywhere.com/api
> (encontrado inspeccionando el bundle JS compilado del frontend).
>
> CREDENCIALES: nunca hardcodeadas. Al arrancar, este autoload busca
> user://shadowforge_credentials.json   →  {"username": "...", "password": "..."}
> Si no existe, crea una plantilla vacía y avisa por consola dónde está
> (fuera del repo — la carpeta de datos de usuario de Godot). El token
> obtenido se guarda en user://shadowforge_token.json y se reutiliza hasta
> que expire (7 días) o falle con 401, momento en que se reautentica solo.
>
> FORMA DE RESPUESTA: el endpoint de cartas se verificó en vivo (campos:
> myl_id, name, cost, damage, ability, race, type, image_url). Los
> endpoints de mazos (fetch_my_decks/fetch_public_decks/
> fetch_public_deck_entries) usan /api/decks/*, confirmados 2026-09-22
> leyendo el bundle JS compilado real del frontend Angular de ShadowForge
> (no adivinados) — ver comentarios de cada función para el detalle.

### `(nivel de archivo)` — línea 30

> 2026-09-22, a pedido del usuario ("que te conectes con tu cuenta de
> shadowforge y salgan tus mazos privados... mazos públicos también"):
> señales nuevas para la pantalla de login real y el buscador de mazos
> públicos — ver ShadowForgeLogin.gd y DeckSelector.gd.

### `(nivel de archivo)` — línea 40

> 2026-09-22, a pedido del usuario ("que el botón mis mazos te muestre los
> mazos privados y públicos"): fetch_my_decks()/fetch_public_decks() solo
> traen datos resumidos por mazo (sin "entries") — señales separadas de las
> de mazos públicos para poder distinguir qué llamada resolvió qué, ver
> DeckSelector._resolve_deck_entries().

### `login` — línea 165

> 2026-09-23: subido de 15s a 30s — ver nota completa en _authed_request()
> (el mismo backend gratuito puede tardar en "despertar").

### `_authed_request` — línea 239

> 2026-09-23, bug real: /decks/my/{id}/ se cuelga 20s exactos en partida
> real incluso con un solo pedido, sin concurrencia (ya descartada, ver
> arquitectura.md §13.15/§13.16) — sospecha: el backend gratuito de
> PythonAnywhere puede tardar en "despertar" tras estar inactivo, más de
> lo que alcanzaban a cubrir 20s. Subido a 60s para confirmar si es
> lentitud real (completa tarde) o un colgado de verdad (nunca completa
> ni con más margen) — ver también el ajuste correspondiente en
> DeckSelector._resolve_deck_entries().

### `fetch_my_decks` — línea 284

> Trae los mazos propios del jugador logueado (privados y públicos que
> haya creado). Endpoint real confirmado 2026-09-22 leyendo el DeckService
> del frontend Angular compilado de ShadowForge (chunk-B2Q7O27F.js):
> GET /api/decks/my/ → {results: [...], count: N} (paginación DRF
> estándar) — reemplaza /external/my-decks/, que nunca se pudo verificar
> sin credenciales reales y cuya forma de respuesta era una adivinanza.

### `fetch_my_deck_entries` — línea 301

> Trae uno de TUS propios mazos completo (con .entries[] para cargarlo
> de verdad) — GET /api/decks/my/{id}/, requiere Bearer (vía
> _authed_request(), mismo criterio que fetch_my_decks() de arriba: se
> reautentica solo si el token venció). Mismo DeckService real del sitio
> confirmado 2026-09-22 que fetch_public_deck_entries() — se espera el
> mismo shape (.entries[].card_detail.myl_id + .quantity, .name), aunque
> esta ruta puntual (/decks/my/{id}/, no /decks/public/{id}/) no se
> verificó línea por línea contra una cuenta real.

### `fetch_public_decks` — línea 315

> Busca/lista mazos públicos de ShadowForge, paginado. Endpoint real
> confirmado 2026-09-22 (mismo DeckService que fetch_my_decks() de
> arriba): GET /api/decks/public/?search=&page=&format=&race=&ordering=
> → {results: [...], count: N}. No requiere login (los mazos públicos son
> públicos) — se manda el Bearer solo si ya hay uno disponible, mismo
> criterio que fetch_cards().

### `fetch_my_profile` — línea 398

> =============================================================================
> CARTAS — algunas ediciones (imp, esc) responden sin autenticación; otras
> (pb, fx, confirmadas por el dueño de la API el 2026-08-18) devolvían 0
> cartas sin token — se manda el Bearer si hay uno disponible, por las dudas.
> =============================================================================

## `scripts/core/cards/UniversalCardParser.gd`

### `(nivel de archivo)` — línea 207

> Cubre dígito o palabra ('un', 'dos'...) y el calificador opcional
> 'por el turno'/'virtual(es)' (2026-08-28, p.ej. Lobo Sagrado:
> 'Cuando ataques, genera un Oro por el turno') — antes exigía la
> palabra literal 'virtual' y solo dígitos, así que nunca matcheaba
> el texto real de ninguna carta. Ejecución real en
> TargetedEffectExecutor.execute_parsed_action() (case "GOLD"), no
> via manager_path/method (GoldManager no es autoload de /root).

### `(nivel de archivo)` — línea 272

> "Una vez en tu turno, cuando este u otro de tus Aliados salga del juego"
> (Vlad el Empalador, 2026-10-17): disparada, no un botón.

### `(nivel de archivo)` — línea 278

> "al morir" no es terminología real del juego (2026-08-28, a pedido
> del usuario) — se sacó, queda "cuando es destruida" para DIE.

### `(nivel de archivo)` — línea 298

> Cuántas veces se usó en ese turno ("Hasta dos veces por turno", 2026-10-18).

### `(nivel de archivo)` — línea 307

> Envoltorio de register() que extrae ability_index/turno y usa el
> instance_id de source_card como clave — extraído (2026-08-30) de las
> mismas 4 líneas que se repetían copiadas en prácticamente todas las
> funciones _activate_* de CardInspectionLayer.gd (Don de Amma, Tesoro
> de los Césares, Miguel, las dos de Tyet, Ramón Freire).
> instance_id, NO card_data.id (2026-08-30, corrección: card_data.id es
> el ID de la CARTA/impresión, compartido por TODAS las copias en juego
> — con 2 Aho en juego, usar uno marcaba el cupo de 'una vez por turno'
> también para el otro, un bug real reportado por el usuario. Cada copia
> física necesita su propio cupo).

### `_on_turn_started_reset_registry` — línea 355

> turn_serial (2026-10-18): el registro cuenta turnos de jugador, no rondas.

### `_detect_target` — línea 388

> resolve_chain()/play_card_with_response_window() (ActionChainResolver.gd/
> AbilityRegistry.gd) se eliminaron aquí (2026-08-27, limpieza — sin ningún
> llamador real, ver ActionPipeline.gd para el detalle completo).

### `_detect_target` — línea 393

> =============================================================================
> PARSE_ABILITIES — Compilador Fase 1 (entrada pública unificada)
> =============================================================================
> get_activated_abilities() se eliminó aquí (2026-08-28, "módulos gordos"):
> cero llamadores reales — solo aparecía nombrada en un comentario de
> ActionPipeline.gd, nunca invocada. parse_abilities() de abajo es la que de
> verdad usa CardInspectionLayer para los botones de habilidad activada.

### `parse_abilities` — línea 401

> Compilador Fase 1: analiza el texto de una carta y retorna habilidades estructuradas.
>
> Divide el texto por puntos y clasifica cada oración:
> - TRIGGER   : Se activa automáticamente por un evento ("Cuando entra", "Al atacar"…)
> - ACTIVATED : El jugador la activa desde el Zoom (tiene coste o "Una vez por turno")
>
> Flags especiales:
> is_optional   — La oración contiene "Puedes". Para ACTIVATED no pide
> confirmación aparte (clickear el botón ya es la
> confirmación, 2026-08-28); para TRIGGER, el "declinar"
> lo ofrece el propio can_cancel del SelectionManager que
> abre TriggerResolution/LookAndPlayResolver.
> once_per_turn — Contiene "Una vez por turno". Se registra en TurnRegistry para
> impedir múltiples usos por turno.
> once_per_turn_own_turn_only — Además "una vez EN tu/su turno" específicamente
> (no solo "una vez por/al turno"): más restrictiva en CUÁNDO se
> puede activar, no solo en frecuencia — ver §10.11 de
> arquitectura.md. Consultado en CardInspectionLayer._build_
> ability_buttons() para ocultar el botón durante una ventana
> de prioridad anidada (Guerra de Talismanes, respuesta a un
> trigger) aunque siga siendo tu turno.
>
> Cada elemento retornado:
> {raw_text, ability_type, trigger_event,
> cost_text, cost_type, cost_amount,
> effect_text, actions,
> is_optional, once_per_turn, once_per_turn_own_turn_only,
> ability_index, card_id,
> manager_path, method}

### `parse_abilities` — línea 444

> ── Continuación encadenada ("Luego, busca...") ────────────────────────
> Una oración que empieza con un conector de encadenamiento (Luego/
> Después/A continuación/Entonces) no es una habilidad nueva — es la
> continuación de la anterior (2026-08-29, p.ej. Don de Amma: "...puedes
> Desterrar un Oro con habilidad de tu Reserva. Luego, busca un Oro en
> tu Castillo y ponlo en tu Reserva."). Antes cada oración se evaluaba
> aislada y ésta, sin trigger ni coste propio, se descartaba en
> silencio — ni el raw_text que usa CardInspectionLayer para detectar
> patrones especiales por botón, ni el effect_text que llega a
> ActionPipeline.activate_ability(), veían nunca el "Luego...". Se
> concatena a la última entrada agregada en vez de perderse.

### `parse_abilities` — línea 468

> "una vez EN tu/su turno" (p.ej. Padre de la Patria, 2026-08-28) es
> una tercera variante real de esta cláusula que no matcheaba antes.

### `parse_abilities` — línea 474

> "una vez EN tu/su turno" es MÁS restrictiva que "una vez por/al
> turno" en CUÁNDO se puede activar, no solo en la frecuencia
> (2026-09-13, a pedido del usuario, ver arquitectura.md §10.11):
> "una vez por turno"/"puedes" sin más calificación = activable en tu
> turno normal Y durante cualquier ventana de prioridad abierta
> (Guerra de Talismanes, respuesta a un trigger, etc. — así está
> implementado hoy). "una vez EN tu/su turno" = SOLO durante tu turno
> normal, NUNCA en una ventana de prioridad anidada, aunque la propia
> habilidad pueda Anular/Cancelar (p.ej. paladín bestiarium: su
> segunda habilidad puede Anular pero el propio texto la restringe a
> "una vez en tu turno" — esa restricción explícita pesa más que la
> convención general de que Anular/Cancelar es de respuesta
> instantánea).

### `parse_abilities` — línea 489

> "Hasta dos/tres veces por turno" (2026-10-18): mismo registro, con
> más usos (TurnRegistry.is_exhausted).

### `parse_abilities` — línea 499

> "Sólo puedes utilizar la habilidad de X una vez por turno" (2026-08-30,
> p.ej. Ramón Freire) — oración de CIERRE que solo reafirma la
> restricción de la habilidad ACTIVADA anterior, no una habilidad
> nueva. Sin este chequeo, 'una vez por turno' la clasificaba como su
> propia entrada ACTIVATED separada y espuria, sin ninguna acción
> real asociada (un botón que no hacía nada con sentido al clickear).

### `parse_abilities` — línea 510

> "Sólo puedes utilizar ESTA habilidad de X una vez por turno"
> (2026-09-06, p.ej. Cuervo Nocturno) — variante con "utilizar" +
> "esta" que faltaba: ninguna de las 4 combinaciones de arriba la
> cubría ("utilizar" solo se chequeaba con "la", "esta" solo con
> "usar"), así que esta oración de cierre quedaba como su propia
> entrada ACTIVATED espuria en vez de fusionarse con la anterior.

### `parse_abilities` — línea 540

> "Puedes pagarlo..." (2026-08-30, corrección: el texto real de Tyet en
> caché/API es "Puedes pagarlo para que..." con pronombre, no "pagar
> este Oro" — el chequeo original nunca matcheaba el texto real de la
> carta, así que esta oración (y por lo tanto también la siguiente,
> que dependía de que ÉSTA llegara a ACTIVATED para poder encadenarse)
> quedaban fuera de 'result' por completo, sin ningún botón.

### `parse_abilities` — línea 548

> "Puedes Desterrarlo/Desterrarla..." (2026-08-30, p.ej. Legión
> Paladín, Ramón Freire — masculino; Estaca: 'Puedes Desterrarla
> para prevenir...' — femenino, "la Estaca") — coste de
> autodesterrarse, tampoco tiene 'una vez por turno' ni ':'. Sin
> este chequeo la oración quedaba fuera de 'result' igual que el
> caso de arriba — Legión Paladín parece no haber disparado nunca
> su botón real hasta este fix (el patrón especial que lo maneja en
> CardInspectionLayer nunca era alcanzable porque esta oración
> jamás llegaba a ability_type ACTIVATED).

### `parse_abilities` — línea 558

> "Puedes poner esta y otra carta de tu mano en el fondo de tu
> Castillo..." (2026-08-30, p.ej. Tyet) — coste de mandar esta carta
> (+ otra) al fondo del mazo, tampoco tiene 'una vez por turno' ni
> ':'. Sin este chequeo caía en la rama de "sin coste ni trigger", y
> como la oración ANTERIOR (la de pagarlo como Oro) no es ACTIVATED
> hasta el fix de arriba, tampoco encadenaba como continuación —
> quedaba fuera de 'result' por completo, sin botón.

### `parse_abilities` — línea 566

> "Barajar esta carta desde tu mano"/"Barajarla de tu mano"/
> "Barajarla" a secas (2026-09-06, bug real reportado por el
> usuario: Sacrificio Solar — 'Puedes pagar un Oro y Barajar esta
> carta desde tu mano para...' — no matcheaba NINGÚN cost_type,
> así que la oración entera quedaba fuera de 'result' sin
> ability_type ACTIVATED, y _build_ability_buttons() nunca le
> mostraba botón al jugador: la habilidad, literal, no se podía
> usar. skofnung tiene el mismo patrón ('Puedes Barajarla de tu
> mano para...') y compartía el mismo problema.

### `parse_abilities` — línea 577

> "Puedes convertirlo/la en un Oro sin habilidad para..." (2026-09-07,
> bug real reportado por el usuario: Perla de Sangre — dos habilidades
> ACTIVADAS separadas, pero la segunda no tiene 'una vez por turno' ni
> ':' ni ningún otro cost_type reconocido, así que caía en la rama de
> 'oración sin coste que sigue a una ACTIVATED abierta' y se fusionaba
> como continuación de la PRIMERA habilidad en vez de ser su propia
> entrada — solo se mostraba/podía usar el primer botón).

### `parse_abilities` — línea 586

> "Puedes Barajarlo..." (2026-09-07, bug real encontrado en auditoría:
> Tótem del Dragón Ancestral — variante MASCULINA de pays_self_shuffle,
> que solo cubría "barajarla"/"barajar esta carta...mano").

### `parse_abilities` — línea 590

> "Puedes Descartarlo/Descartarla..." (2026-09-07, bug real encontrado
> en auditoría: Sumi — coste de autodescartarse, mismo molde que
> pays_self_banish pero con Descartar).

### `parse_abilities` — línea 594

> "Puedes Destruir esta Arma..." (2026-09-07, bug real encontrado en
> auditoría: Lanza Argenta — coste de autodestruirse).

### `parse_abilities` — línea 597

> "Puedes pagar un/N Oro(s) para..." SIN ':' (2026-09-07, bug real
> encontrado en auditoría: Sandraudiga, Visión Heroica — distinto de
> pays_self_as_gold ('puedes pagarlo', la carta SE PAGA A SÍ MISMA
> como Oro): aquí se paga Oro GENÉRICO de la Reserva como costo de un
> efecto, la carta de texto no es un Oro. El formato con ':' ya cubre
> esto cuando la carta lo imprime así; esta es la variante en prosa.
> Habilidad de Vigilia sin coste con condición (2026-10-13, Patria
> Vieja: "En tu Vigilia, si no has puesto Oros en juego este turno,
> puedes mirar...") y habilidad que la carta GANA en el Cementerio
> (Duelo Espacial: "En tu Cementerio... gana la habilidad 'En tu
> Vigilia, puedes Robar una carta'"). Sin esto ninguna llegaba a
> ACTIVATED y no tenían botón.
> Solo la variante "puedes mirar..." (Patria Vieja): las otras cartas con
> esta condición (Fuente de Ladurum, Karesansui, Corazón de Dragón...)
> son "ponerlo desde tu mano o Cementerio en tu Reserva", otra mecánica.

### `parse_abilities` — línea 719

> Errata retroactiva de Cuervo Nocturno/Tyet (2026-09-13, a pedido del
> usuario): la ÚLTIMA impresión de "Puedes poner esta y otra carta de
> tu mano en el fondo de tu Castillo y Robar dos cartas" agrega
> "Sólo puedes utilizar esta habilidad de [Nombre] una vez por turno".
> El usuario indica que en Mitos y Leyendas la versión más reciente de
> una habilidad rige para TODAS las impresiones de esa carta, no solo
> la que trae el texto actualizado — así que se fuerza el límite aquí
> (pays_self_to_deck_bottom detecta la habilidad por texto, sin
> depender de edición) en vez de solo confiar en que la oración de
> cierre esté impresa en esa copia puntual.

### `parse_abilities` — línea 759

> Regex de robo canónico — cubre "Roba dos cartas", "Robas 3 cartas", etc.
> "(?:hasta\s+)?" agregado (2026-09-06, p.ej. Mecha-Daikaiju: "Roba hasta
> tres cartas") — "hasta N" no reduce el robo real (nunca hay motivo para
> robar menos de lo permitido), así que tratarlo igual que "Roba N cartas"
> a secas es una simplificación segura.

### `extract_action` — línea 768

> Ver _extract_action_impl(). Agrega "source_text": el texto que se
> analizó (2026-10-14, bug real reportado por el usuario: Akari Musashi —
> la búsqueda genérica releía el texto COMPLETO de la carta, encontraba
> "oponente" en otra habilidad y buscaba en el Castillo rival, eligiendo
> el bot).

### `_extract_action_impl` — línea 798

> ── 0. Patrones compuestos "puedes [costo] y Roba N cartas" (2026-08-22) ──
> Van ANTES que todo lo demás, incluido el robo canónico (sección 1): si
> no, 'puedes barajar... y Roba dos cartas' se adelanta y ejecuta 'Roba
> dos cartas' suelto, ignorando el 'puedes' y el costo que lo condiciona
> — bug real visto con Bernardo O'Higgins y Lobo Sagrado. extract_action()
> solo soporta UN grupo de cantidad genérico y estos casos necesitan
> varios números a la vez, así que se resuelven aparte.

### `_extract_action_impl` — línea 838

> Variante con portador restringido (2026-10-14, Zadquiel: "puedes jugar
> un Arma sobre este Aliado o uno oponente, reduciendo su coste en un
> Oro, hasta un mínimo de 1"). No dice "de tu mano": también Armas del
> Cementerio que tengan Exhumar (usuario, 2026-10-14); no se destierran
> al salir del juego, eso es solo para Talismanes.

### `_extract_action_impl` — línea 878

> Patrón "sube un Arma que controles a la mano de su dueño para jugar un
> Arma del mismo o menor coste desde tu mano sin pagar su coste" (p.ej.
> Padre de la Patria, 2026-08-28) — swap de Armas, no descuento fijo
> como Lobo Sagrado/Hanta, por eso no reusa weapon_draw_rx/weapon_hand_rx.

### `_extract_action_impl` — línea 896

> Patrón "convertir un Oro o una carta de coste N o menos en una carta
> del mismo tipo sin habilidad" (DAR Sección 8 - Convertir, p.ej.
> Capitán O'Brien, 2026-08-28) — misma carta física, misma
> tipo/coste/Fuerza, solo pierde la habilidad. Objetivo: dentro del
> juego (propio o enemigo), salvo que el texto diga lo contrario.

### `_extract_action_impl` — línea 964

> parse_text()/TRIGGER_RX/COST_RX/ACTION_RX/debug_parse() se eliminaron aquí
> (2026-08-27, limpieza a pedido del usuario): sin ningún llamador real —
> era una implementación paralela y más vieja de lo que parse_abilities()
> hace hoy (que es lo que CardInspectionLayer usa de verdad para los
> botones de habilidad activada, pese a que el docstring de parse_text()
> decía que ERA esa fuente).

## `scripts/core/config/Constants.gd`

### `(nivel de archivo)` — línea 5

> =============================================================================
> LOGGING
> =============================================================================
> 2026-09-23, a pedido del usuario ("eliminar tanto log innecesario, quiero
> entender lo que está pasando"): varios prints "[DIAG]" (gui_input de cada
> click, estado del botón ¿Paso? en cada cambio de prioridad, etc.) se
> agregaron para cazar bugs puntuales de la fase de Guerra de Talismanes
> (ver arquitectura.md §12/§13.4/§13.6) y quedaron encendidos siempre,
> inundando la consola en cualquier partida normal. En vez de borrarlos (esa
> visibilidad ya sirvió para arreglar varios bugs reales), se apagan por
> defecto aquí — si vuelve a hacer falta cazar algo similar, alcanza con
> poner esto en `true`, sin tener que reescribir el logging desde cero.

### `(nivel de archivo)` — línea 150

> Confirmadas como reales en Mitos y Leyendas (2026-08-20, corrección del
> usuario — el set anterior mezclaba keywords de otros CCG que no existen
> en este juego; ver docs/audit-2026-08-13.html para el historial).

### `(nivel de archivo)` — línea 187

> NOTA (2026-08-20): "Inmune a X" y "portar múltiples armas" NO son keywords
> fijas en Mitos y Leyendas — son texto libre de cada carta ("no puede ser
> afectada por talismanes", "tus aliados pueden portar un arma adicional").
> Se detectan por texto donde hace falta (ver TriggerSystem._target_text_denies
> y GoldManager._player_has_ally_in_play/lógica de Armas), no como Keyword.

## `scripts/core/effects/CastleLook.gd`

### `(nivel de archivo)` — línea 2

> CastleLook — motor único de "mira N cartas del tope/fondo de un Castillo"
> (2026-10-13, a pedido del usuario, arquitectura.md §69).
>
> Regla (usuario, DAR): mirar en un Castillo siempre deja ordenar las cartas
> que vuelven, aunque el texto no lo diga; vuelven al mismo lado del que se
> miraron (tope → tope, fondo → fondo) salvo que el efecto diga otra cosa
> (Infernum Vox: "tope y/o fondo"). "Muestra" NO entra aquí (es público).
>
> Todo en UNA ventana (CastleLookWindow): repartir a los destinos y ordenar el
> resto. Nada se mueve hasta confirmar, y los destinos que pueden disparar
> efectos (Oros a la Reserva/Oro Pagado, p.ej. Drácula) se aplican AL FINAL,
> con el resto del efecto ya terminado — orden incluido.
>
> Quien elige: Anfitrión (ventana local), Remoto (la misma ventana por red,
> prompt "castle_look") o bot local (reparto automático).
>
> boxes: [{key, label, dest, min = 0, max = -1, ordered = false,
> filter = Callable(card_data) -> bool}]
> dest: "top" | "bottom" | "shuffle" (vuelven al Castillo) | "hand" |
> "cemetery" | "exile" | "reserva" | "pagado" | "custom" (lo aplica el
> llamador con lo que devuelve look()).
> La primera zona con ordered = true (o start = true, sin flechas de orden)
> es donde empiezan todas las cartas.
> Devuelve {key: [card_data...]} (vacío si no había nada que mirar).
>
> Se usa con preload (sin class_name global), ver §54.

## `scripts/core/effects/EffectContext.gd`

### `(nivel de archivo)` — línea 3

> EffectContext — qué carta y qué jugador controlan el efecto que se está
> resolviendo AHORA, y el detector de paridad (2026-10-12, arquitectura.md
> §56, a pedido del usuario).
>
> Lo empujan los tres puntos donde se resuelve un efecto: TriggerResolution.
> resolve_next_trigger() (habilidades disparadas), TriggerSystem.
> resolve_talisman() y StackStepResolver._resolve_ability() (activadas).
>
> Detector: las funciones de selección (CardInteractionModule.await_*,
> SelectionManager.await_*/open_*, ZoneViewerModule.open_cemetery_target_
> picker(), ActionSearch) y GoldManager.pagar_coste() llaman a check_*().
> Si el efecto es del jugador 1 (Remoto o bot) pero elige/paga el jugador
> 0, imprime una línea "[PARIDAD]" con la carta y qué se pidió — casi
> siempre es un patrón viejo escrito solo para el Anfitrión. Es una
> heurística: hay casos legítimos ("tu oponente elige", prevenciones que
> ofrece el rival), por eso solo avisa, nunca cambia nada.
>
> Funciona también contra el bot: jugando una partida local, cada línea
> [PARIDAD] marca una carta que con un Remoto real fallaría.
>
> Ventana de respuesta única por efecto (2026-10-12, §59, opción B elegida
> por el usuario: el rival responde DESPUÉS de que se declaran los
> objetivos). Cada entrada lleva 'window': "pending" (todavía no se le dio
> la ventana al rival), "done" o "cancelled". TriggerSystem.
> open_response_window() la consulta cuando la pide la propia carta del
> efecto: si ya se abrió, no abre otra; si estaba pendiente, esa ES la
> ventana. Si el patrón nunca la pide, ensure_window() la abre justo antes
> de la primera acción real (ActionModule, poner Oros en juego, jugar
> gratis). Si el rival la cancela, las acciones siguientes no se ejecutan.

## `scripts/core/effects/StackAnnul.gd`

### `(nivel de archivo)` — línea 2

> StackAnnul — Anular / Cancelar sobre la PILA real (2026-10-14, revisión del
> mazo 170, docs/revision-mazo-170.md).
>
> Antes, "Anula X" destruía una carta que ya estaba en juego: un Talismán de
> respuesta nunca podía anular la carta o habilidad a la que respondía (esa
> carta todavía estaba en la pila, esperando su ventana). Ahora, si hay en la
> pila un objeto del rival que el texto puede anular/cancelar, se marca y el
> dueño de esa ventana lo maneja:
> - Anular una carta jugada (Aliado, Arma, Tótem, Oro con ventana,
> Talismán): no resuelve; el Aliado ya en el tablero se destruye (sin su
> "Cuando entra en juego") y el Talismán va al Cementerio
> (GoldManager._trigger_enter_play / TriggerSystem.open_response_window).
> - Cancelar una habilidad (disparada o activada): no ocurre.
> Si no hay nada en la pila que calce, cada patrón sigue con su
> comportamiento de antes.
>
> Tipo de cada objeto: context.window_kind ("carta", "Talismán",
> "disparada", "activada"), que TriggerSystem.open_response_window() anota;
> los objetos ACTIVATED_ABILITY de ActionPipeline son "activada".
> Se usa con preload (ver §54).

### `protected_from_cancel` — línea 79

> nu-galahad (2026-10-18): "Tus Armas no pueden ser canceladas" protege
> a las Armas, no a sus propias habilidades.

### `try_from_text` — línea 151

> Un Oro no tiene coste (2026-10-17): nunca es "de coste N o menos".

## `scripts/core/effects/actions/ActionBanish.gd`

### `banish` — línea 15

> Destierra cartas, enviándolas al Destierro (zona de exilio)
> Las cartas desterradas no pueden ser recuperadas por medios normales
>
> Args:
> targets: Array de cartas a desterrar
> source: Carta/efecto que causa el destierro
> skip_validation: Si omitir validación previa
> can_be_prevented: Si puede ser prevenida por Estaca — false cuando
> el llamador YA resolvió su propia Prevención específica antes
> de llegar aquí (2026-09-09, p.ej. TargetedEffectExecutor.
> _execute_targeted_annul(): Anular solo lo previene Drácula, no
> Estaca, así que pasa false para no volver a preguntar aquí).
> AL FINAL a propósito, no antes de skip_validation: los ~15
> llamadores existentes ya pasan 'true' como tercer argumento
> posicional para skip_validation — insertar un parámetro ANTES
> de esa posición correría ese 'true' a can_be_prevented sin que
> ningún llamador lo pidiera, dejando skip_validation=false en
> todos ellos por accidente.
>
> Returns: {success, banished, failed}

### `banish` — línea 65

> Prevención reactiva real (2026-09-09 — Estaca), mismo chequeo que
> destroy(). can_be_prevented=false cuando el llamador ya resolvió
> su propia Prevención específica (ver docstring de arriba).

### `banish` — línea 71

> Indesterrable, Nefandos, dulce canasta (2026-10-18).

## `scripts/core/effects/actions/ActionDestroy.gd`

### `_check_destruction_prevention` — línea 132

> Verificar indestructible — vía KeywordManager.can_be_destroyed(),
> no card.has_keyword() directo (2026-09-02, refactor: mismo motivo ya
> documentado en ActionValidator._can_be_destroyed() — un silenciado
> que le quite Indestructible por KeywordManager no se respetaba aquí,
> porque card.has_keyword() no mira los overrides de KeywordManager).

### `_check_destruction_prevention` — línea 149

> Prevención reactiva real (2026-09-09, "sistema de respuestas" —
> Estaca): se pregunta al jugador EN EL MOMENTO, no una carga previa.

## `scripts/core/effects/actions/ActionDraw.gd`

### `draw` — línea 76

> (2026-08-28): 'GameManager.trigger_loss' nunca existió — el
> fallback de abajo era código muerto siempre (DamageManager
> es autoload garantizado y check_defeat_condition() sí existe).

## `scripts/core/effects/actions/ActionModule.gd`

### `_get_references` — línea 95

> (2026-08-28, "módulos gordos" punto 1): TriggerSystem/AnimationQueue/
> DamageManager son autoloads garantizados — se sacó el cacheo redundante
> vía get_node_or_null() (EffectController se cacheaba pero nunca se
> usaba en este archivo).

### `draw_up_to` — línea 128

> 'Roba hasta N cartas' (2026-10-17, a pedido del usuario, p.ej.
> Mecha-Daikaiju): tu Castillo brilla y cada clic en él roba una carta;
> N (o ESC) para no robar más. El bot roba todas. En el Remoto, el mismo
> prompt de "carta o Castillo" que ya usa await_target_or_castillo_pick().

### `shuffle_deck` — línea 153

> Baraja el Castillo (mazo) de un jugador — vía CardManager, sincronizado
> por referencia con Main.player_deck/opponent_deck (ver sync_from_main).
> Barajar no cambia el TAMAÑO del mazo, pero sí cambia qué carta queda en
> el tope (índice 0) — refresca ZoneManager._update_castillo_counts() aquí
> (2026-09-14, a pedido del usuario: La Ouija, 'del tope de tu Castillo',
> quedaba mostrando la carta vieja tras un barajado que pasaba por este
> wrapper genérico en vez del CardManager.shuffle_deck() + refresco manual
> que ya usa la mayoría de los archivos de triggers) — único punto de
> verdad para TODOS los llamadores de esta función, actuales y futuros.

### `search` — línea 174

> Búsqueda en varias zonas a la vez con el selector del tablero (2026-10-11,
> ver ActionSearch.search_zones()).

### `search_zones` — línea 186

> 'Busca en UN Castillo/Cementerio' (sin posesivo): selector con las zonas de
> los dos jugadores, atado al primer Castillo que se mira (2026-10-14, ver
> ActionSearch.search_either_owner()).

### `search_either_owner` — línea 198

> Selector de zonas (+ cartas de la mano) para quien elige: Anfitrión,
> Remoto o bot (2026-10-12, ver ActionSearch.pick_in_zones()).

### `pick_in_zones` — línea 205

> BanishOpponentPatterns ya llamaba a esto vía ActionModule, pero la fachada
> no existía (2026-10-11).

### `mill` — línea 219

> Pan de Muerto (2026-10-18): hasta quince por Castillo por turno.

### `_apply_card_filter` — línea 382

> Filtro por tipo — admite un tipo único o una lista ("busca un Arma
> o un Oro", p.ej. Tyet, 2026-08-22)

### `_apply_card_filter` — línea 387

> int() (2026-10-17): el tipo de los datos viene de JSON como
> float (2.0) y `2.0 in [2]` es false — "busca un Arma o un
> Oro" no encontraba nada.

### `_apply_card_filter` — línea 395

> Filtro por raza — admite una raza única o una lista ("busca... una
> carta Ignis o Titán", p.ej. ignis desatado, 2026-09-04)

### `_apply_card_filter` — línea 406

> Filtro por coste máximo
> Un Oro no tiene coste (2026-10-17): no cumple filtros de coste.

### `_apply_card_filter` — línea 433

> Filtro de exclusión por nombre exacto (2026-09-04, p.ej. Aurora de
> Chile: "busca... dos Oros que no sean Aurora de Chile" — evita que
> la propia carta buscadora, si hay otra copia en el Castillo, se
> encuentre a sí misma)

### `_apply_card_filter` — línea 442

> Tipos excluidos: "una carta que no sea Aliado ni Talismán" (2026-10-18).

### `_apply_card_filter` — línea 447

> Nombre exacto dentro de una lista (2026-10-18, Dos de Cada Uno).

## `scripts/core/effects/actions/ActionPipeline.gd`

### `_connect_signals` — línea 128

> (2026-08-28, "módulos gordos" punto 1): PriorityManager/GameManager son
> autoloads garantizados — se saca el cacheo redundante vía get_node_or_null().

### `_connect_signals` — línea 132

> Resetear uso de habilidades al inicio de cada turno.
> GameManager es el único conductor de turnos (ver consolidación 2026-08-19).

### `_get_name_from_data` — línea 214

> =============================================================================
> API PRINCIPAL - JUGAR CARTA
> =============================================================================
> play_card()/add_response_to_stack() (StackObjectType.CARD_PLAYED/
> RESPONSE_CARD) se eliminaron aquí (2026-08-27, limpieza a pedido del
> usuario): sin ningún llamador real en el juego — el camino que de verdad
> juega cartas es GoldManager (_play_card_to_field/_place_card_as_gold/
> _equip_weapon/_play_talisman), no ActionPipeline. Quedaban como un
> segundo sistema paralelo sin terminar (_resolve_talisman_effects() tenía
> hasta un TODO sin implementar) que podía confundir a futuro. Las
> habilidades disparadas/activadas SÍ están vivas y no se tocaron —
> add_triggered_ability_to_stack()/activate_ability() siguen igual.

### `_add_to_stack` — línea 250

> Una habilidad (activada o disparada) no es "jugar" la carta: el log no
> debe decir "juega X — COSTE: 0" (2026-10-14, a pedido del usuario).

### `add_triggered_ability_to_stack` — línea 295

> (2026-09-09, bug real encontrado al preparar la migración de la Pila de
> Respuesta Universal): esta función NUNCA arrancaba _process_stack() por
> su cuenta — solo activate_ability() lo hacía. El único llamador real de
> hasta ahora (SelectionModule._on_exhume_card_selected(), Exhumar) quedaba
> esperando un stack_object_resolved que jamás llegaba salvo que otra
> habilidad activada ya estuviera procesándose al mismo tiempo por
> coincidencia. Mismo guard que activate_ability() ya usa.

### `add_triggered_ability_to_stack_and_await` — línea 322

> 2026-09-12 (bug real reportado por el usuario: TODAS las cartas con
> habilidad de entrada tardaban ~8 segundos, siempre, sin excepción).
> Causa: las lambdas de GDScript capturan las variables locales de la
> función envolvente POR VALOR, no por referencia — "done = true" dentro
> de un closure reasigna la copia local del closure, nunca la variable
> "done" de la función de afuera, así que el "while not done" jamás se
> enteraba de que el objeto ya había resuelto y esperaba siempre el
> timeout completo de 8s. Los Diccionarios SÍ se comparten por
> referencia (por eso "outcome.resolved = true" ya funcionaba bien) —
> fix: "done" pasa a vivir como un campo más de ese mismo Dictionary
> compartido, en vez de una variable bool aparte.

### `add_triggered_ability_to_stack_and_await` — línea 357

> Salvaguarda con timeout (2026-09-11, bug real reportado por el usuario:
> el juego quedaba congelado para siempre en Fase Final, sin ningún log
> posterior — TriggerSystem.awaiting_response/is_resolving atascados,
> consistente con que este objeto puntual NUNCA llegó a recibir su Paso
> D/E, probablemente porque _process_stack() no se relanzó cuando hacía
> falta). Sin una salida de emergencia, cualquier causa que impida que
> ESTE objeto puntual resuelva deja el juego entero sin poder avanzar —
> mismo criterio de "no fricción, seguir igual" que ya usa
> _wait_for_response_window() (Signo Amarillo, timeout de 8s) en vez de
> arriesgar un cuelgue permanente. Si esto se dispara, es evidencia real
> de un bug más profundo por perseguir después — el push_warning deja
> rastro concreto (antes no había NINGÚN log en este punto de cuelgue).

### `activate_ability` — línea 400

> instance_id, no source_card_data.id — mismo motivo que en
> can_activate_ability() (2026-08-30, bug de copias compartiendo cupo).

### `activate_ability` — línea 408

> Sistema "Puedes" ELIMINADO para habilidades ACTIVADAS (2026-08-28, a
> pedido del usuario): clickear el botón de la habilidad YA ES la
> confirmación — pedir un "¿seguro?" aparte era redundante ("se entiende
> que si le doy al botón utilizo la habilidad"). Los triggers ("puedes"
> en 'Cuando entra/ataca/...', resueltos por TriggerResolution/
> LookAndPlayResolver/TargetedEffectExecutor, que no pasan por aquí) ya
> ofrecen su propio "declinar" via can_cancel en el SelectionManager que
> abren — nunca dependieron de este diálogo.

### `activate_ability` — línea 423

> ── Paso B: Pagar el costo ────────────────────────────────────────────────
> El oro real vive en GoldManager (hijo de Main), no en ActionModule/
> GameManager — ver docs/audit y consolidación 2026-08-19/2026-08-20.

### `activate_ability` — línea 430

> 2026-10-06 (ver arquitectura.md §33): GoldManager.pagar_coste()
> ya es por jugador (Oro Virtual/restringido + elegir Oro físico
> interactivo) — antes el jugador 1 pagaba siempre por un camino
> aparte (_easy_bot._pay_oro_for_bot(), solo Oro físico simple,
> porque "el bot no tiene Oro Virtual/restringido" ya no es
> cierto). Unificado a un solo camino para los dos jugadores.

### `activate_ability` — línea 442

> 2026-10-12 (§57): la mano del jugador 1 SÍ existe como Nodos
> (_opponent_fan) — antes este costo se rechazaba para él. El
> Remoto elige por red; el bot descarta la de menor coste.

### `can_activate_ability` — línea 509

> instance_id de la carta VIVA cuando está disponible, no
> source_card_data.id (2026-08-30, corrección: ese id es el de la
> carta/impresión, compartido por TODAS las copias en juego — con 2
> copias de una misma carta, usar el 'una vez por turno' de una marcaba
> también el cupo de la otra, bug real reportado por el usuario). Cae a
> source_card_data.id solo si de verdad no hay Nodo (no debería pasar en
> los dos caminos reales que llaman a esta función).

### `can_activate_ability` — línea 533

> NO se exige 'active_player_id == controller_id' (2026-09-10, corregido):
> el DAR permite activar habilidades instantáneas en Vigilia/Guerra de
> Talismanes seas o no el jugador activo — es justo lo que hace falta
> para responder dentro de la Pila de Respuesta Universal en el turno
> rival. El chequeo viejo bloqueaba esto tanto al humano como al bot.

### `_process_stack` — línea 619

> Anulado mientras esperaba (StackAnnul, 2026-10-14): no abre otra
> ventana.

### `_handle_cancelled_object` — línea 802

> (2026-08-28): 'move_to_zone' nunca existió en ActionModule.gd — este
> guard siempre daba falso y la carta NUNCA iba al cementerio al
> cancelarse/fizzlear, quedaba en limbo fuera de la pila. La API real
> para mover una carta (por Dictionary) al cementerio es
> CardManager.add_to_cemetery(player_id, card_data).

### `_handle_fizzled_object` — línea 825

> (2026-08-28): 'move_to_zone' nunca existió en ActionModule.gd — este
> guard siempre daba falso y la carta NUNCA iba al cementerio al
> cancelarse/fizzlear, quedaba en limbo fuera de la pila. La API real
> para mover una carta (por Dictionary) al cementerio es
> CardManager.add_to_cemetery(player_id, card_data).

### `_handle_annulled_object` — línea 902

> Mover al cementerio sin resolver (2026-08-28: 'move_to_zone' no existe
> en ActionModule.gd — ver mismo fix en _handle_cancelled_object/_handle_fizzled_object).
> 2026-10-14: si la ventana es de una carta real (source_card_node), quien
> la abrió la manda a su destino al recibir object_annulled
> (GoldManager._trigger_enter_play/_play_talisman) — agregarla aquí la
> duplicaba en el Cementerio.

### `_handle_annulled_object` — línea 911

> (2026-08-28): 'trigger_event' no existe en TriggerSystem.gd — este
> disparo de on_card_annulled nunca ocurrió realmente. Documentado, no
> se inventa un trigger nuevo fuera del alcance de esta limpieza.

### `_get_player_name` — línea 927

> Obtiene el nombre del jugador
> (2026-08-28: GameManager no expone get_player_name() — ver mismo hallazgo
> en PaymentManager.gd)

## `scripts/core/effects/actions/ActionReturnDiscard.gd`

### `return_to_deck` — línea 15

> Devuelve una carta que está EN JUEGO a su Castillo (tope o fondo del
> mazo — 'devuelve al mazo'/'pon en el fondo del mazo'). El patrón real de
> ABILITY_PATTERNS['RETURN_DECK'] ya existía pero apuntaba a esta función,
> que nunca se había escrito. Si tenía Armas equipadas, también vuelven al
> mazo con ella (el Arma sigue al portador, igual que al destruir/desterrar
> — ver CardManager.destroy_card()/exile_card()).
>
> source (2026-09-09, "sistema de respuestas" — a pedido del usuario,
> cerrando un hueco real: esto no chequeaba NADA de Prevención antes):
> tag "leave_play" — Legión Paladín puede prevenir esto (Estaca NO,
> 'barajar de vuelta al mazo' no es destruir/desterrar/debuff/silenciar,
> su alcance confirmado no lo cubre). Se revisa ANTES de tocar las Armas
> equipadas — si se previene, la carta y sus Armas se quedan exactamente
> como estaban.

### `return_to_deck` — línea 46

> on_card_returned_to_deck estaba declarada en EffectController.gd pero
> nunca se emitía desde ningún lado (2026-09-11, encontrado al construir
> GameStateBroadcaster para el multiplayer remoto — sin esto, una carta
> "barajada de vuelta al mazo" dejaba un fantasma visual permanente del
> lado del Remoto, sin ninguna instrucción de red que la sacara del
> tablero). Se emite ANTES de desconectar/liberar, mismo orden que
> destroy_card()/exile_card() en EffectController.gd.

### `return_to_deck` — línea 59

> Desconectar señales de interacción ANTES de liberar (2026-08-29, mismo
> bug que CardManager.destroy_card()/exile_card()) — sin esto, un hover
> que sigue apuntando al nodo después de queue_free() tira "Invalid
> access... on a base object of type previously freed" al tocar
> .modulate en el próximo evento de mouse.

## `scripts/core/effects/actions/ActionSearch.gd`

### `search` — línea 36

> Busca cartas en el Castillo o Cementerio que cumplan el filtro (DAR
> Sección 8). El jugador elige cuáles llevarse. Si may_play es true, por
> cada carta encontrada se ofrece jugarla (pagando su coste) o dejarla en
> la mano (si no se puede pagar, queda en la mano — nunca se pierde).
>
> Args:
> player_id: ID del jugador dueño de la zona buscada (el destino
> también es SUYO — buscar en el Castillo rival y desterrar manda
> al Destierro del rival, no al propio; DAR: la carta sigue siendo
> del jugador de quien salió)
> chooser_id (2026-09-30, Fase 3 del plan de paridad remota): quién
> HACE la elección — no siempre es player_id. 'Busca en el Castillo
> OPONENTE y destiérralas' tiene player_id=oponente (es SU zona/
> destino) pero quien elige qué desterrar es el CONTROLADOR de la
> habilidad, no la víctima. Default -1 = usar player_id.
> zone: Zona donde buscar (CASTILLO o CEMENTERIO — únicas zonas con datos)
> filter: Filtro de cartas {type, raza, cost_max, cost_min, strength_min,
> name_contains, keyword}
> amount: Cantidad máxima a seleccionar
> can_fail: Si puede fallar sin encontrar (false = obligatorio)
> skip_validation: Si omitir validación previa
> destination: Zona final de las cartas encontradas (2026-08-25).
> Constants.Zone.MANO (default, puede jugarse si may_play) o
> Constants.Zone.DESTIERRO (p.ej. Rey de Amarillo: 'busca en un
> Castillo... y Destiérralas' — va directo, sin pasar por la mano).
> distinct_names: Si true, las cartas elegidas no pueden repetir nombre
> entre sí (2026-08-25, p.ej. necro-titan: 'busca... dos cartas de
> distinto nombre').
> may_play: Si true, ofrece jugar cada carta encontrada en vez de solo
> guardarla en mano (DAR: 'puedes ponerla en juego pagando su coste')
> source_card: Carta que causa la búsqueda (para triggers/log)
>
> Returns: {success, selected, matching, searched_zone, searched_zones}

### `search_zones` — línea 80

> Como search(), pero sobre VARIAS zonas del mismo jugador a la vez
> (2026-10-11, a pedido del usuario — p.ej. Arturo de Bretaña: 'busca en
> tu Castillo y/o Cementerio hasta dos Armas'): el jugador mira cada zona
> en el selector del tablero (ZoneBrowsePicker), puede mezclar cartas de
> ambas y confirma una sola vez. Reemplaza al viejo "¿Dónde buscar?"
> (Castillo o Cementerio) + lista de una sola zona.
> 'cost_reduction': con may_play, descuento al jugarla ('reduciendo su
> coste en un Oro'), con el piso 1 de siempre de PaymentManager.

### `search_zones` — línea 123

> Sidhes del Bosque (2026-10-18): respuesta a buscar en un Castillo.

### `search_zones` — línea 148

> Terminal P-12 (2026-10-18): hasta dos cartas buscadas por turno.

### `search_zones` — línea 191

> 2026-09-14, a pedido del usuario (La Ouija): buscar en el Castillo saca
> cartas y después lo baraja (arriba), pero esta función genérica nunca
> llamaba a ZoneManager._update_castillo_counts(), el único punto de
> verdad real para refrescar tanto el contador visible del Castillo como
> el revelado del tope de La Ouija (ver ZoneViewerModule.
> refresh_castillo_top_reveal()).

### `_deliver` — línea 209

> Lleva una carta encontrada a su destino (del dueño 'player_id').
> destination < 0 (2026-10-14): no la lleva a ningún lado — el llamador la
> usa (p.ej. jugar un Talismán encontrado en un Castillo); se anota de
> quién era en result.selected_owners.

### `_deliver` — línea 219

> Va directo al Destierro, sin pasar por la mano ni crear un
> nodo Card (2026-08-25, p.ej. Rey de Amarillo).

### `_deliver` — línea 226

> Va directo a la Reserva de Oro, sin pasar por la mano ni pagar
> coste (2026-08-29, p.ej. Don de Amma: 'busca un Oro en tu
> Castillo y ponlo en tu Reserva').

### `_deliver` — línea 234

> Va directo al Cementerio, sin pasar por la mano ni crear un
> nodo Card (2026-09-04, p.ej. kitsune - sp: 'busca en tu
> Castillo un Aliado y ponlo en tu mano o Cementerio') — mismo
> patrón que DESTIERRO de arriba.

### `_deliver` — línea 243

> "Baraja N cartas de tu Cementerio en tu Castillo" (2026-10-12,
> EffectInterpreter, p.ej. Cathach) — vuelve al mazo oculta y se
> baraja abajo, mismo selector de zonas que el resto de búsquedas.

### `_deliver` — línea 250

> Va directo al Oro Pagado (ya-gastado), sin pasar por la mano
> (2026-09-04, p.ej. Aurora de Chile: 'pon uno en tu Oro Pagado y
> otro en tu mano') — mismo patrón que RESERVA_ORO de arriba, pero
> usando put_gold_directly_in_pagado() en vez de _in_reserva().

### `search_either_owner` — línea 268

> 'Busca en UN Castillo / un Cementerio' sin posesivo (2026-10-14, a
> pedido del usuario — voragh el devorador: elegía el rival y el bot se
> quedaba con las 2 primeras sin mostrarte nada). El selector del tablero
> con las zonas de LOS DOS jugadores: quien elige mira lo que quiera, pero
> al abrir un Castillo queda atado a ese (los Cementerios son públicos y se
> pueden seguir mirando). Cada carta va al destino de SU dueño (DAR) y todo
> Castillo mirado se baraja.
> 'one_zone' (2026-10-14, "dos cartas de UN Cementerio", p.ej. shoki):
> todas las elegidas de la misma zona (pools 'exclusive').

### `search_either_owner` — línea 306

> Terminal P-12 (2026-10-18): hasta dos cartas buscadas por turno.

### `_pick_from_zones` — línea 362

> Elección real de las cartas (2026-10-11): siempre con ZoneBrowsePicker
> — en la pantalla del Anfitrión si elige él, por red si elige un Remoto
> real (el Remoto corre el mismo selector y devuelve índices), o automática
> para el bot local. Devuelve [{zone, zone_data, data}].

### `pick_in_zones` — línea 388

> Selector de zonas para QUIEN elige (2026-10-12, a pedido del usuario:
> "todos los cambios siempre tienen que ser para el Remoto igual"): en la
> pantalla del Anfitrión, por red en la del Remoto (corre el mismo
> ZoneBrowsePicker, también con sus cartas de la mano), o automático para
> el bot local. 'pools' con is_own relativo a 'chooser'; 'hand_nodes'
> (opcional) = cartas de la mano de 'chooser' también elegibles. Devuelve
> [[pool_idx, card_idx]], con pool_idx -1 para una carta de hand_nodes.
> El llamador revalida (por red puede llegar cualquier cosa).
> 'out_info' (2026-10-14): se llena con "opened_castles" = índices de los
> pools de Castillo que quien elige llegó a mirar (hay que barajarlos).

### `_put_found_card_into_play` — línea 474

> Instancia la carta encontrada y la mete en la mano. Con may_play
> (2026-10-11: ahora pregunta — 'puedes jugarla' es opcional, y Arturo de
> Bretaña dice 'puedes jugarlas... y/o ponerlas en tu mano'), ofrece
> jugarla de inmediato pagando su coste (con 'cost_reduction' si el efecto
> lo da). Si no se puede pagar o se elige la mano, se queda en la mano —
> nunca se pierde.

### `_put_found_card_into_play` — línea 488

> 2026-09-14, mismo bug real que ZoneManager.draw_card() (ver ese
> comentario) — faltaba aquí también.

### `_put_found_card_into_play` — línea 504

> 2026-10-12 (§57): play_card() es solo del Anfitrión ("No es
> tu turno" para el jugador 1).

## `scripts/core/effects/actions/ActionValidator.gd`

### `_validate_search` — línea 94

> _get_searchable_zone_data() vive en ActionSearch.gd (submódulo de
> ActionModule), no en ActionModule.gd mismo — mismo patrón de bug que
> arquitectura.md §2 ("_main.<propiedad> inexistente"), aquí con un
> submódulo hermano en vez de un padre equivocado (2026-09-11, bug real
> reportado por el usuario: "Invalid call. Nonexistent function
> '_get_searchable_zone_data' in base 'Node (ActionModule.gd)'").

## `scripts/core/effects/actions/AnimationEffects.gd`

### `_update_card_zone_properties` — línea 94

> (2026-08-28, "módulos gordos" punto 1): aquí había un intento de emitir
> 'card_left_zone'/'card_entered_zone' en TriggerSystem — ninguna de las
> dos señales existe ni existió nunca ahí, el has_signal() que las
> envolvía siempre daba falso. Se sacó.

## `scripts/core/effects/actions/AnimationQueue.gd`

### `_connect_to_action_module` — línea 133

> _connect_to_action_executor() y sus 8 handlers (_on_ability_started,
> _on_ability_completed, _on_executor_action, _on_cost_paid,
> _get_cost_display_name, _on_executor_damage, _on_executor_buff,
> _on_executor_heal, _on_executor_token) eliminados (2026-08-17): escuchaban
> señales de ActionExecutor.execute_ability()/execute_ability_blocks(),
> que resultaron tener cero llamadores en todo el proyecto y ya se
> eliminaron de ActionExecutor.gd — estos handlers nunca se disparaban.
> =============================================================================
> HANDLERS DE ACTIONMODULE - Con animaciones automáticas
> =============================================================================

### `queue_shuffle` — línea 712

> Encola la animación de barajado del Castillo — atajo del bloque de 4
> líneas add_command(CUSTOM, {callable: animate_shuffle, description})
> que se repetía 49 veces en los patrones (2026-10-13, §62).

## `scripts/core/effects/actions/StackStepResolver.gd`

### `_execute_step_d` — línea 114

> ─────────────────────────────────────────────────────────────────────────
> Abrir ventana de prioridad (oponente primero)
> ─────────────────────────────────────────────────────────────────────────
> 2026-09-11 (bug real reportado por el usuario: la consola mostraba
> "Guerra de Talismanes" al resolver Paso D de una habilidad cualquiera,
> sin relación con esa fase). El número mágico "1" no es RESPONSE_WINDOW
> — el enum real es NONE=0, GUERRA_TALISMANES=1, RESPONSE_WINDOW=2,
> DISCARD_PHASE=3, BLOCK_DECLARATION=4 (PriorityManager.gd) — así que esta
> ventana se abría con el contexto equivocado. Sin impacto en quién tiene
> prioridad primero (aquí siempre se pasa starting_player explícito) ni en
> valid_actions (sin llamadores reales hoy), pero sí rompía el auto-pase
> "no hay nada que decidir" del humano (PhaseFlowController._on_priority_
> changed_glow()), que a propósito solo actúa en RESPONSE_WINDOW real para
> no auto-pasar una Guerra de Talismanes genuina.

### `_execute_step_d` — línea 157

> 2026-09-25, a pedido del usuario ("elimina logs redundantes"): "Ambos
> pasaron" es el resultado normal en casi TODA resolución (el bot nunca
> responde nada todavía) — no aporta información nueva repetido en cada
> carta. Una respuesta real sí es noticia y se mantiene visible.

### `_execute_step_e` — línea 284

> CARD_PLAYED/RESPONSE_CARD ya no llegan aquí (2026-08-27, limpieza —
> ver ActionPipeline.gd: play_card()/add_response_to_stack() se
> eliminaron, nada los crea más).

### `_resolve_ability` — línea 335

> Resuelve una habilidad disparada o activada: parsea el texto del efecto
> (stack_obj.card_data.habilidad, que activate_ability() ya dejó como el
> effect_text de la habilidad) y lo ejecuta vía el mismo resolutor que usan
> los triggers 'al entrar en juego' y los Talismanes (2026-08-27): primero
> los patrones compuestos ("mira/muestra N... elige qué hacer con una de
> ahí"), y si ninguno matchea, extract_action() simple como antes. Antes
> esto último era lo ÚNICO que se probaba aquí — una habilidad ACTIVADA con
> un efecto compuesto nunca resolvía bien, a diferencia de una disparada
> con el mismo texto. Reutiliza selección de objetivo y todos los tipos de
> acción ya conectados (DRAW, DESTROY, BANISH, DISCARD, SHUFFLE, MILL,
> SEARCH, LOOK, REVEAL, BUFF, DEBUFF, SILENCE, ANNUL, PREVENT_DAMAGE) sin
> duplicar nada.

## `scripts/core/effects/compiler/EffectCompiler.gd`

### `(nivel de archivo)` — línea 3

> EffectCompiler — compila el texto de UNA habilidad (disparada, activada o
> Talismán) a un plan de pasos atómicos (2026-10-12, "paso B" acordado con
> el usuario, ver arquitectura.md §54).
>
> Por qué existe: hasta aquí cada carta nueva se resolvía con su propia
> función try_execute_*_pattern() (252 en el proyecto, 144 encadenadas en
> TriggerResolution, gana la primera que matchea sobre el texto completo).
> Este compilador arma el efecto con piezas reutilizables: una carta nueva
> casi siempre es una combinación de piezas que ya existen, o una pieza
> nueva que sirve para muchas cartas.
>
> Regla de oro: el plan solo es válido (ok = true) si se entendió TODO el
> texto del efecto. Si queda cualquier resto sin entender, ok = false y el
> llamador sigue con la cadena de patrones vieja — nunca se ejecuta un
> efecto a medias.
>
> Clase pura: no usa autoloads ni nodos (los tipos y zonas van como texto,
> EffectInterpreter los traduce a Constants) — así se prueba headless con
> tools/test_effect_compiler.gd y se audita el catálogo completo con
> tools/audit_cards.gd.
>
> Plan: {ok, optional, activated, steps: [paso], unparsed: String}
> activated = el texto traía momento/frecuencia de habilidad ACTIVADA ("En
> tu Vigilia, una vez por turno, ..."): el clic en su botón ya fue la
> confirmación del "puedes".
> Pasos (todos llevan además "then": true si van después de "Luego," — solo
> corren si el paso anterior se resolvió por completo, DAR):
> {op: "draw", amount}                            — Roba N cartas
> {op: "mill", who: "self"|"opponent", amount}    — Bota N cartas
> {op: "discard", who, amount, random}            — Descarta N cartas
> {op: "shuffle_from_hand", amount, up_to}        — Baraja N cartas de tu mano
> {op: "search", zones, card_type, amount, up_to} — Busca ... y ponla en tu mano
> {op: "target", verb, count, up_to, target}      — Destruye/Destierra/Baraja/Sube N cartas en juego
> {op: "mass", verb, target}                      — Destruye todos los Aliados ...
> {op: "choice", options: [[pasos], [pasos]]}     — "A, o B"
> {op: "shuffle_from_cemetery", amount, up_to}    — Baraja N cartas de tu Cementerio en tu Castillo
> {op: "self", verb}                              — Destrúyelo / Destiérralo (la propia carta)
> {op: "if", cond, steps}                         — "si no fue declarado atacante este turno, ..."
> {op: "cemetery_cleanup", mode, amount}          — Baraja y/o Destierra hasta N de los Cementerios
> (mode: "both" | "banish" | "shuffle")
> {op: "gold", amount}                            — Genera N Oros (por el turno, sin restricción)
> {op: "buff", count, up_to, amount, keywords, to_exile, permanent, turn_only, target}
> — Un Aliado gana Furia, N de Fuerza y hace daño al Destierro
> {op: "reveal_until", specs: [{count, types, cost_val, cost_cmp}]}
> — Muestra del tope hasta mostrar ... y ponlos en tu mano
> {op: "if", cond: {kind: "controls", count, type, race, other, min_strength, attack_line}, steps}
> — "si controlas (otro) (N o más) <tipo/raza>, ..."
> {op: "pay", amount}                             — costo "pagar N Oros para ..." (se paga antes)
> {op: "hand_peek", verb, count, types, types_not, cost_val, cost_cmp}
> — Mira la mano de tu oponente y Destierra/Descarta/Baraja ...
> "mill" admite who "both" (Cada jugador Bota N). "search" admite además
> card_types (varios), types_not ("que no sea X ni Y"), cost_val/cost_cmp.
> "Elige un efecto: - A. - B." se compila como "choice" con N opciones.
> Las oraciones de regla (RULE_SKIP_RX: "No puede ser Anulado", "Cuando
> juegues este Talismán, Destiérralo", "Puedes jugarlo al comienzo de
> cualquier Fase"...) se saltean: las aplica otro sistema.
> Extras de "target"/"mass": silence_first (pierde su habilidad y es
> Destruido), replace_if_keyword: {keyword, verb} ("Si tiene Exhumar, en
> vez de eso, Destiérralo"). Extra de "mill": per (Bota una carta por cada
> Aliado en tu Línea de Defensa / Tótem en juego / ...).
> verb: "destroy" | "banish" | "shuffle" | "bounce"
> target: {card_types: ["aliado", ...] (vacío = cualquier tipo en juego),
> controller: "any"|"opponent", exclude_gold, stat: ""|"fuerza"|"coste",
> cmp: "<="|">=", value}
> card_type / card_types usan: "aliado", "arma", "totem", "talisman", "oro"
> ("" = cualquier carta). zones: "castillo", "cementerio".

### `(nivel de archivo)` — línea 102

> Oraciones de REGLA (no son efecto) que pueden ir en cualquier parte del
> bloque y se saltean (2026-10-18, punto 4 de la revisión): las aplica otro
> sistema — Anular (StackAnnul.protected_from_annul), autodestierro del
> Talismán (GoldManager._play_talisman), cuándo se puede jugar
> (PhaseStartWindow), copias (Errante/Única), etc. Antes cortaban la
> compilación de todo el bloque.

### `(nivel de archivo)` — línea 125

> "Elige un efecto: - A. - B." — cada viñeta es una opción (2026-10-18).

### `(nivel de archivo)` — línea 128

> Costo en Oros al comienzo de una oración: "pagar un Oro para Robar dos
> cartas" (2026-10-18). Se paga antes de resolver; sin Oro, no pasa nada.

### `(nivel de archivo)` — línea 132

> "Si controlas (otro) (N o más) <tipo/raza> (de Fuerza N o más) (en Línea de
> Ataque), (además) efecto" (2026-10-18). Se evalúa al resolver.

### `(nivel de archivo)` — línea 195

> Buscar (2026-10-18: varios tipos, "que no sea X ni Y", "de coste N o más/menos").

### `(nivel de archivo)` — línea 202

> "Mira la mano de tu oponente y Destierra/Descarta/Baraja una carta de
> coste 2 o menos (que no sea Oro) de ahí" (2026-10-18).

### `(nivel de archivo)` — línea 224

> Cementerios (2026-10-18): "Baraja y/o Destierra hasta N cartas de los
> Cementerios" y sus formas de un solo verbo.

### `(nivel de archivo)` — línea 239

> Barajar/Desterrar sin zona explícita = en juego (regla del usuario
> 2026-08-30, ver DSR_ShuffleDrawCombos.try_execute_draw_and_shuffle_
> opponent_card_pattern()) — por eso se rechaza si sigue 'de tu/los...'.

### `compile_clause` — línea 319

> "Luego, puedes barajar una carta..." (2026-10-18): un "puedes" en medio
> del efecto deja elegir no hacerlo — el objetivo/búsqueda pasa a "hasta".

## `scripts/core/effects/compiler/EffectInterpreter.gd`

### `(nivel de archivo)` — línea 3

> EffectInterpreter — ejecuta los planes de EffectCompiler (2026-10-12, ver
> arquitectura.md §54).
>
> Orden: se declara todo (opcional "puedes", rama de una elección "A, o
> B", objetivos en juego) y después se ejecutan los pasos en orden, "en la
> medida de lo posible". Un paso marcado "then" (impreso tras "Luego,")
> solo corre si el anterior se resolvió por completo.
>
> Ventana de respuesta (§59): tras declarar llama a EffectContext.
> ensure_window() — si el efecto todavía no le dio su ventana al rival
> (triggers: ya no se abre por adelantado), se abre ahí; si ya la tuvo
> (Talismanes, activadas en la Pila), no se abre otra.
>
> Quién elige: el jugador local (0) con clic en el tablero; el Remoto real
> (1 con sala abierta) por red — await_target()/await_multi_target()/
> await_choice() ya delegan solos; el bot local (1 sin sala) elige aquí
> mismo con una heurística simple.
>
> Solo ejecuta planes cuyos pasos sabe resolver (EffectCompiler.
> EXECUTABLE_OPS/VERBS): si el compilador entendió algo que el intérprete
> todavía no sabe hacer (p.ej. "Sube ... a la mano de su dueño"), devuelve
> false y sigue la cadena de patrones vieja. Al agregar una pieza nueva
> aquí, sumarla también a esas listas.

### `execute_plan` — línea 73

> ── Declarar ──────────────────────────────────────────────────────────
> "Puedes": si el primer paso ya se puede rechazar en el propio
> selector (búsqueda con mínimo 0, objetivo con ESC), no se agrega un
> popup Sí/No aparte — a pedido del usuario, la elección va en el
> tablero siempre que se pueda (§49-§53).

### `execute_plan` — línea 87

> Costo en Oros ("pagar N Oros para ...", 2026-10-18): antes de declarar
> objetivos; si no se puede pagar, no se resuelve nada.

### `_declare_targets` — línea 166

> Ganar Fuerza: el bot prefiere sus propios Aliados (2026-10-18).

## `scripts/core/effects/continuous/CardEffectSystem.gd`

### `_connect_to_effect_controller` — línea 49

> (2026-08-28, "módulos gordos" punto 1): EffectController es autoload y
> carga ANTES que CardEffectSystem (ver orden en project.godot), así que
> el retry con call_deferred nunca se disparaba — se saca el lookup y el
> fallback muerto.

### `_on_card_entered_play` — línea 73

> 2026-09-25, a pedido del usuario ("redundante"): para las 4 zonas
> monitoreadas de abajo, el handler específico (_handle_*_entry) ya
> imprime su propia línea más clara — este mensaje genérico solo
> quedaba duplicando esa info. Para zonas fuera de esa lista sigue
> siendo la única traza de que la carta entró a algún lado.

### `_on_card_entered_play` — línea 99

> NO llamar aquí a _process_etb_trigger(): TriggerSystem también escucha
> esta misma señal (on_card_entered_play) y ejecuta el texto de habilidad
> vía UniversalCardParser → ActionModule, que es el camino más completo
> (respeta conectores Y/Luego/O, orden APNAP entre jugadores). Si ambos
> se ejecutaran, un "roba 2" robaría el doble. _process_etb_trigger()
> queda como código muerto a propósito — ver docs/audit, hallazgo de
> efectos de carta (sesión 2026-08-16).

### `_handle_attack_line_entry` — línea 168

> =============================================================================
> SISTEMA ETB / PIPELINE DE EJECUCIÓN DE ACCIONES — ELIMINADO (2026-08-17)
> =============================================================================
> Todo lo que vivía aquí (cola de habilidades ETB/activadas/disparadas,
> execute_draw/execute_search/execute_look/execute_mill/execute_discard/
> execute_return_to_deck, execute_action_pipeline y su parser de texto
> propio) tenía CERO llamadores en todo el proyecto — código muerto desde
> antes de esta sesión. _on_card_entered_play() ya documentaba (más abajo)
> que _process_etb_trigger() no se llama a propósito: TriggerSystem
> escucha la misma señal on_card_entered_play y resuelve el texto de
> habilidad vía UniversalCardParser → ActionModule, que es el camino real.
> Auditado función por función (68 funciones revisadas) antes de recortar
> — lo único que SÍ estaba vivo de este archivo (el sistema de habilidades
> continuas de Oro y los handlers on_card_entered_play/on_card_left_play)
> sigue más abajo, intacto.
> =============================================================================
> LISTENER DE SALIDA DE ZONAS
> =============================================================================

### `_on_card_left_play` — línea 192

> 2026-09-23, a pedido del usuario: este mensaje solo duplicaba lo que ya
> informa EffectController ("X fue destruida"/"X resuelve su efecto y va
> al Cementerio") — 3 líneas distintas para el mismo evento de salida de
> juego. Se mantiene gateado para depuración profunda.

### `_get_continuous_ability_targets` — línea 421

> Un Aliado puede estar en Defensa o en Ataque (consolidación 2026-08-20)

### `recalculate_all_continuous_effects` — línea 615

> =============================================================================
> ACTION PIPELINE (DAR 7.1) — ELIMINADO (2026-08-17): execute_action_pipeline()
> y todo lo que colgaba de ahí (_execute_pipeline_action, _execute_destroy_
> targets, _execute_exile_targets, _execute_damage, _execute_buff,
> _execute_shuffle, parse_ability_to_actions, _split_by_connectors,
> _parse_single_action, is_pipeline_running, get_pipeline_progress) no
> tenía NINGÚN llamador en todo el proyecto — el camino real de ejecución
> de acciones es TriggerSystem → UniversalCardParser → ActionModule.
> =============================================================================

## `scripts/core/effects/continuous/ContinuousEffectManager.gd`

### `_connect_signals` — línea 129

> Conectar a GameManager (el único conductor de turnos, ver consolidación
> 2026-08-19) para limpiar modificadores temporales al final de cada turno.

### `_on_effect_controller_card_entered` — línea 146

> "este turno" desde que entró (shade, 2026-10-18).

### `get_modified_cost` — línea 185

> "Carta de coste N o menos" (2026-10-17, regla confirmada por el usuario):
> un Oro NO tiene coste salvo que esté en juego como Aliado, así que nunca
> cumple un filtro de coste. get_modified_cost() sigue igual (pagos, badge).

### `_get_card_id` — línea 339

> Obtiene un ID único para una carta (2026-09-06, bug real reportado
> por el usuario: dos copias de la misma carta impresa compartían buffs
> de Fuerza — 'card_id' es el ID de la CARTA IMPRESA en la base de datos
> (myl_id, p.ej. '17757' para Espada del Juicio), igual en TODAS las
> copias físicas de esa carta. Usarlo como clave de _calculated_cache
> hacía que el valor calculado de UNA copia (con sus propios
> modificadores) quedara cacheado bajo una clave que la OTRA copia (sin
> esos modificadores) también consultaba, heredando el mismo resultado.
> El instance_id de Godot SIEMPRE es único por Node, incluso entre
> copias idénticas — es la única clave correcta aquí.

### `_get_card_id` — línea 355

> is_instance_valid() PRIMERO (2026-09-19, misma clase de bug que
> ContinuousVisualSync.gd — "Left operand of 'is' is a previously freed
> instance"): un 'is Node' bare sobre una carta ya liberada (destruida/
> desterrada sin limpiar el modificador que la referencia) revienta aquí
> — is_instance_valid() es seguro sobre cualquier Variant, incluida una
> referencia liberada, así que corta ANTES de que 'is Node' llegue a
> evaluarse sobre ella.

### `_get_card_owner` — línea 406

> Obtiene el jugador que CONTROLA la carta ahora mismo (pese al nombre
> histórico de la función) — usado para targeting ALLIES/ENEMIES real.
> Preferir controller_id (2026-09-04, a pedido del usuario: 'ganar el
> control' ya es un mecanismo real — ver ContinuousEffectManager.
> gain_control_of_card()) — controller_id se inicializa igual a owner_id
> en el setter de Card.gd y SOLO diverge cuando un efecto de robo de
> control lo cambia explícitamente, así que este cambio es transparente
> para toda carta que nunca haya cambiado de controlador.

### `gain_control_of_card` — línea 436

> 'Gana el control de' una carta EN JUEGO (2026-09-04, a pedido del
> usuario — p.ej. shedo titan: 'gana el control de un Aliado') —
> reparenta el nodo al contenedor del NUEVO controlador (Aliado → Línea
> de Defensa, Tótem → Línea de Apoyo, Oro → Reserva) y actualiza
> controller_id, NO owner_id (DAR: la carta sigue siendo del dueño
> original — vuelve a su Cementerio/Destierro si sale del juego, ya que
> CardManager.destroy_card()/exile_card() reciben el player_id de
> destino como parámetro explícito del llamador, no lo leen de la carta).
> _get_card_owner() ya prefiere controller_id sobre owner_id, así que
> todo target ALLIES/ENEMIES y aura 'tus Aliados' ve el cambio de
> inmediato, sin tocar cada consumidor uno por uno.

### `gain_control_of_card` — línea 452

> Abu Simbel (2026-10-18): "Los jugadores no pueden ganar el control de
> cartas de las que no sean dueño."

### `count_other_copies_in_play` — línea 487

> Cuenta cuántas OTRAS copias (mismo nombre, EXCLUYENDO a 'card' misma)
> del mismo controlador de 'card' hay ahora mismo EN JUEGO — usado por
> restricciones tipo 'si no controla otra copia de esa carta' (2026-09-04,
> Tamales). Es relativo a LA COPIA PUNTUAL cuya habilidad se quiere usar,
> confirmado con el ejemplo completo del usuario (Drácula, 2026-09-04):
> con 3 copias en el Castillo y 1 jugada (controlada, en juego), la que
> está en juego SÍ puede usar su habilidad (0 OTRAS copias en juego), pero
> las 2 que quedan fuera de juego (mano/Cementerio/Castillo) NO PUEDEN —
> para ellas, la que sí está en juego cuenta como 'otra copia controlada'.
> Si se juega una segunda copia, cada una de las dos ve a la otra como
> 'otra copia' y ambas quedan bloqueadas (ni la que entra roba/dispara su
> 'Cuando entra en juego', ni ninguna de las dos puede usar su activada).
> Incluye Reserva/Oro Pagado además de las 3 líneas de campo (a diferencia
> de _get_all_cards_in_play(), pensada solo para auras ALLIES/ENEMIES) —
> Tamales habla explícitamente de 'Oros', que viven ahí.

### `tamales_ability_restriction_reason` — línea 528

> 'Tu oponente sólo puede utilizar las habilidades de Oros y cartas de
> coste 2 o más si no controla otra copia de esa carta' (2026-09-04,
> Tamales — texto de errata confirmado por el usuario) — combina el
> chequeo de JUGADOR (¿hay un Tamales de mi oponente en juego? si no,
> esta restricción ni me toca) y el de CARTA: relativo a la COPIA
> PUNTUAL que intenta usar la habilidad (count_other_copies_in_play),
> confirmado con el ejemplo completo del usuario (Drácula, 2026-09-04):
> con 1 copia en juego (0 otras copias controladas) esa copia funciona
> normal, pero cualquier OTRA copia del mismo nombre (en mano/Cementerio/
> Castillo) queda bloqueada — para ELLA, la que sí está en juego cuenta
> como 'otra copia controlada'. Con 2 copias en juego, cada una ve a la
> otra como 'otra copia' y ambas quedan bloqueadas (ni dispara su 'Cuando
> entra en juego' la que recién entra, ni puede usar su activada
> ninguna de las dos). Usado tanto para habilidades ACTIVADAS
> (CardInspectionLayer._validate_ability()) como DISPARADAS (TriggerSystem.
> _check_trigger_conditions(), 'ni disparar'); las auras/efectos
> CONTINUOS no pasan por ninguno de esos dos choke points, así que
> quedan afuera por construcción (confirmado por el usuario: 'las
> continuas siguen estando en pie').
> Returns: '' si no aplica, si no un motivo legible.

### `_get_all_cards_in_play` — línea 583

> Todas las cartas de ambos jugadores en las 3 líneas del campo
> (2026-08-25) — usado para refrescar el badge visual de TODOS los
> afectados cuando se registra/quita un aura de target dinámico (ALL/
> ALLIES/ENEMIES/OTHER), ya que _resolve_targets() no las enumera (se
> resuelven carta por carta en _get_applicable_modifiers(), no aquí).

### `_controls_n_allies_of_same_race` — línea 602

> ¿'player_id' controla al menos 'threshold' Aliados que compartan UNA
> misma Raza? (2026-09-03, p.ej. Trono del Dragón: 'Si controlas tres o
> más Aliados de la misma Raza') — no es 'threshold Aliados en total',
> necesitan compartir Raza entre sí. Se recuenta desde cero en cada
> llamada (sin cache): se usa como condition Callable de un modificador
> CONDITIONAL, que ContinuousEffectManager reevalúa en cada consulta.

### `_get_card_zone` — línea 627

> Obtiene la zona actual de una carta.
>
> 2026-09-04, bug real encontrado (Armería del Guerrero no daba su aura):
> esto usaba 'if card.get("current_zone"):' — un chequeo de verdad/falsedad,
> no de null. Constants.Zone.RESERVA_ORO es el PRIMER valor del enum (= 0),
> y en GDScript 'if 0:' es false — así que CUALQUIER carta en Reserva de
> Oro (incluida cualquier carta de tipo Oro con aura continua, no solo
> Armería) se trataba como sin zona, _is_card_in_play() la daba por fuera
> de juego, y _is_modifier_active() rechazaba su modificador PERMANENT
> entero (exige que la fuente esté en juego).

### `_resolve_targets` — línea 682

> is_instance_valid() PRIMERO — mismo motivo que _get_card_id()/
> _get_card_name() arriba: modifier.target puede ser una carta que ya
> salió de juego sin que este modificador se haya limpiado de
> _modifiers/_modifiers_by_target (2026-09-19, bug real de la misma
> familia reportado por el usuario en ContinuousVisualSync.gd).

## `scripts/core/effects/continuous/ContinuousEffectParser.gd`

### `_register_card_continuous_effects` — línea 24

> 2026-08-25: antes leía card.get_meta("card_data", {}) — metadata de
> Godot que NUNCA se asigna en el juego real (solo en TestScene.gd, una
> escena de prueba vieja). Siempre volvía {}, así que ability_text
> siempre estaba vacío y este detector nunca encontraba nada, para
> ninguna carta — confirmado con Patria Vieja, que no aplicaba su aura
> a pesar de tener el patrón ya soportado.

### `_parse_and_register_continuous_effects` — línea 47

> 'Hace doble daño de combate al Destierro' EN PRIMERA PERSONA/pasiva
> propia (2026-09-04, p.ej. manuel rodriguez: 'Furia. Hace doble daño
> de combate al Destierro.') — flag propio de la carta, consultado por
> BattleManager durante ASIGNACION_DANIO. Excluye la variante delegada
> a un Aliado ELEGIDO por una activada ('Una vez por turno, un Aliado
> hace doble daño...', p.ej. atenea en wonderland) — esa NO es
> autoaplicación, se resuelve aparte como target puntual temporal (ver
> CardInspectionLayer/PreventionAbilityHandler), todavía sin
> implementar para ese caso.

### `_parse_and_register_continuous_effects` — línea 79

> Detectar buffs a aliados con calificador de coste, forma "ganan N de
> Fuerza" (2026-08-24, p.ej. Patria Vieja: "Tus Aliados de coste 1 o más
> ganan 1 de Fuerza") — distinto del patrón de arriba, que solo cubre
> "obtienen +N" sin calificador de coste.
> "(?:que controlas)?" agregado (2026-08-30, p.ej. Sable de Napoleón:
> "Los Aliados que controlas ganan 1 de Fuerza") — antes exigía "aliados"
> seguido DIRECTO de "ganan" (salvo el calificador de coste), así que
> "que controlas" en el medio rompía el match y esta variante quedaba
> sin ningún patrón que la reconociera.
> "Tus Aliados Titán ganan 1 de Fuerza" (2026-09-06, p.ej. Cuerno de
> Titán) — calificador de RAZA en vez de coste, patrón separado a
> propósito para no reordenar los grupos de captura de
> qualified_buff_regex (varios llamadores de abajo dependen de que el
> grupo 1 sea el coste mínimo).

### `_parse_and_register_continuous_effects` — línea 123

> "Si controlas N o más Aliados de la misma Raza" (2026-09-03, p.ej.
> Trono del Dragón: 'Si controlas tres o más Aliados de la misma
> Raza, tus Aliados ganan 1 de Fuerza...') — qualified_buff_regex
> de arriba NO ve este prefijo condicional: matchea sobre la
> SEGUNDA mención de 'Aliados' (la del propio buff, 'tus Aliados
> ganan'), ignorando la condición racial que la antecede. Sin este
> chequeo, el buff se registraría PERMANENT incondicional. Aquí se
> detecta aparte y, si está presente, el modificador pasa a
> CONDITIONAL con un Callable que recuenta por Raza en cada
> consulta (_is_modifier_active() lo reevalúa siempre, nunca
> cachea el resultado) — a diferencia de PERMANENT, CONDITIONAL no
> chequea solo que la fuente siga en juego, así que el propio
> Callable lo verifica también.

### `_parse_and_register_continuous_effects` — línea 166

> Cláusula adicional: "...y no pueden ser afectados por habilidades
> de cartas fuera del juego mientras atacan" (2026-09-03, Trono del
> Dragón) — el recorte 'mientras atacan' es POR ALIADO puntual (no
> tiene sentido en el condition Callable de arriba, que no recibe
> la carta objetivo), así que solo se registra la mitad 'racial' aquí
> (protection_type OFF_BOARD_WHILE_ATTACKING) y el chequeo real de
> 'está atacando ahora' vive en el punto de consulta
> (TargetedEffectExecutor._select_ally_target(), igual que la
> inmunidad a Talismanes de Kotaix más abajo).

### `_parse_and_register_continuous_effects` — línea 210

> Cláusula adicional: "...y no pueden perder su habilidad" SIN
> calificador de Arma (2026-09-04, p.ej. Abu Simbel: "Tus Aliados
> ganan 1 de Fuerza y no pueden perder su habilidad") — a diferencia
> de "Aliados que porten Arma no pueden perder su habilidad" (Manuel
> Bulnes, ya cubierto por register_weapon_wielder_silence_immunity()
> en otra parte de este mismo archivo), esta protege a TODOS los
> Aliados del controlador, consultada desde KeywordManager.silence_
> card() vía register_all_allies_silence_immunity().

### `_parse_and_register_continuous_effects` — línea 221

> Cláusula adicional: "...Furia..." en la misma oración (2026-09-02,
> p.ej. Espíritu Kotaix: "Tus Aliados ganan 2 de Fuerza, Furia y no
> pueden ser afectados por Talismanes") — mismo criterio que la
> cláusula de BLOCK_DESTROY de arriba, pero para el patrón de
> keyword_regex más abajo (que exige 'tienen', no matchea 'ganan...
> Furia' en lista separada por comas).

### `_parse_and_register_continuous_effects` — línea 242

> Cláusula adicional: "...no pueden ser afectados por Talismanes"
> (2026-09-02, Espíritu Kotaix) — protección otorgada a OTRAS cartas
> (a diferencia de Constants.gd/TargetedEffectExecutor._target_text_denies(),
> que solo detecta cuando una carta se protege a SÍ MISMA con su
> propio texto impreso). ContinuousEffectManager.has_protection(card,
> "TALISMAN") es la consulta; TargetedEffectExecutor._select_ally_target()
> la respeta cuando source_card es un Talismán.

### `_parse_and_register_continuous_effects` — línea 264

> Cláusula independiente (fuera del bloque qualified_match, no exige
> "ganan N de Fuerza" en la misma oración): "En tu turno, tus Aliados no
> pueden ser afectados por Talismanes oponentes" (2026-09-04, Aurora de
> Chile) — protección de Talismanes acotada SOLO al turno del propio
> controlador, vía duration CONDITIONAL (a diferencia de la protección
> permanente de Espíritu Kotaix de más arriba).

### `_parse_and_register_continuous_effects` — línea 289

> Cláusula independiente: "...No puede perder su habilidad" EN SINGULAR
> referido a sí misma (2026-09-04, p.ej. lagrima del dragon: "Oro
> Inicial. Indesterrable. No puede perder su habilidad.") — distinto de
> "no pueden perder su habilidad" en plural de más arriba (protege a
> Aliados de TERCEROS); aquí "puede" en singular protege a la PROPIA
> carta. "no puede" nunca matchea dentro de "no pueden" (falta el
> espacio tras "puede"), así que no hay colisión entre ambas cláusulas.

### `_parse_and_register_continuous_effects` — línea 299

> "Tus Armas no pueden perder su habilidad" (2026-09-04, p.ej.
> skofnung) — variante de la cláusula de Abu Simbel pero para Armas en
> vez de Aliados.

### `_parse_and_register_continuous_effects` — línea 305

> "Los Oros oponentes pierden su habilidad" (2026-09-06, p.ej. Daikaiju
> Furioso) — inverso de las inmunidades de arriba: FUERZA el silencio en
> vez de proteger contra él.

### `_parse_and_register_continuous_effects` — línea 311

> "No puedes recibir daño" (2026-09-06, p.ej. Cetro Demoniaco) —
> prevención TOTAL y continua para el controlador de 'card' mientras
> siga en juego (DamageManager.add_damage_prevention con source=card,
> one_shot=false; el chequeo de 'source' en juego en
> _apply_damage_prevention() la limpia sola cuando 'card' sale).
> 'tu oponente no puede Desterrar cartas de tu Castillo' (segunda mitad
> de la misma oración) NO implementada: no hay un choke point único
> donde interceptar todos los "Destierra del tope del Castillo" del
> proyecto (cada patrón manipula CardManager.get_deck() directo).

### `_parse_and_register_continuous_effects` — línea 324

> Cláusula independiente: "Si está en tu Reserva, las cartas que
> controles no pueden perder su habilidad por habilidades y efectos
> oponentes" (2026-09-04, p.ej. Terminal P-12) — protección amplia
> (TODAS las cartas del controlador, no solo Aliados) pero condicionada
> a que 'card' esté específicamente en Reserva de Oro, no en juego en
> general (a diferencia de las otras variantes de silence-immunity de
> más arriba, todas PERMANENT mientras la fuente esté en juego).

### `_parse_and_register_continuous_effects` — línea 335

> Cláusula independiente: "Tus Aliados Ignis o Titán ganan Fuerza igual
> a su coste y Furia" (2026-09-04, shedo titan) — valor DINÁMICO por
> carta (no un número fijo, por eso no matchea qualified_buff_regex),
> vía Callable en 'value' (_calculate_modifier_value() ya lo soporta).

### `_parse_and_register_continuous_effects` — línea 395

> "Los Aliados oponentes pierden N de Fuerza" (2026-09-06, p.ej. amazona
> desafiante) — misma idea que enemy_debuff_regex de arriba ("obtienen
> -N"), pero con la fórmula "pierden N de Fuerza" en vez de "obtienen -N".

### `_parse_and_register_continuous_effects` — línea 399

> "(?: [^.]*?,)?" (2026-10-14, Sariel: "Los Aliados oponentes no pueden
> portar Armas, pierden 1 de Fuerza").

### `_parse_and_register_continuous_effects` — línea 417

> "Los Aliados en juego pierden N de Fuerza" (2026-10-18, Escudo de Vlad
> III): todos, los tuyos y los del oponente.

### `_parse_and_register_continuous_effects` — línea 437

> "Las cartas oponentes en juego reducen su coste en N Oro(s)" (2026-
> 09-04, p.ej. Samael) — debuff de COSTE (no Fuerza) mientras la
> fuente siga en juego, a diferencia de un descuento de UN SOLO USO al
> jugarse (GoldManager._get_reveal_cost_reduction_pattern() y
> similares): este es un modificador PERMANENT sobre el stat "cost",
> que get_modified_cost() ya soporta (_get_modified_stat(), floor 0).
> Importante para cualquier filtro 'de coste N o menos' sobre una carta
> YA EN JUEGO (Destruir/Anular/Convertir/etc., ver TargetedEffectExecutor)
> — esos deben leer get_modified_cost(c), no card_cost crudo, para ver
> este debuff.
> "Tus cartas en juego aumentan su coste en un Oro" (2026-09-06, p.ej.
> Asmodeus) / "Tus Aliados en juego aumentan su coste en un Oro"
> (Belcebú, calificado a solo Aliados) — espejo del debuff de coste
> rival de abajo, pero como autoimpuesto (ALLIES en vez de ENEMIES,
> "aumentan" en vez de "reducen"). Aplica a cartas futuras tuyas
> también (stat "cost" vía get_modified_cost(), no solo a lo ya en juego).

### `_parse_and_register_continuous_effects` — línea 515

> "Gana N de Fuerza por cada Arma que controles" (2026-08-30, p.ej.
> Manuel Bulnes) — buff a SÍ MISMA (no 'tus Aliados'), con valor
> DINÁMICO que se recalcula solo (value como Callable, ya soportado por
> _calculate_modifier_value()). Cuenta Armas equipadas en cualquier
> Aliado del mismo controlador — las Armas son hijas de su portador,
> no children directos del campo, así que no alcanza con
> _get_all_cards_in_play() + filtro de tipo.

### `_parse_and_register_continuous_effects` — línea 549

> "Gana N de Fuerza por cada otro Aliado que controles" (2026-09-04,
> p.ej. La Torre) — mismo mecanismo que el de Arma de Manuel Bulnes de
> arriba, pero contando Aliados (excluyendo a la carta misma, 'otro')
> en las tres zonas de campo del mismo controlador.

### `_parse_and_register_continuous_effects` — línea 581

> "Tus Aliados que porten Arma no pueden perder su habilidad" (2026-08-30,
> Manuel Bulnes) — protección contra KeywordManager.silence_card(),
> consultada directo desde ahí (choke point único).

## `scripts/core/effects/continuous/ContinuousVisualSync.gd`

### `update_all_card_visuals` — línea 112

> 2026-09-19, bug real reportado por el usuario: "Left operand
> of 'is' is a previously freed instance" — is_instance_valid()
> DEBE ir primero: 'is' se evalúa antes que el 'and' de la
> derecha (orden de evaluación normal, sin cortocircuito a
> favor), y a diferencia de is_instance_valid(), el operador
> 'is' de GDScript revienta si el objeto ya fue liberado, no
> devuelve false. Un modificador cuyo target salió de juego sin
> limpiarse de _modifiers/_modifiers_by_target (carta destruida/
> desterrada con un buff/debuff activo todavía registrado) deja
> exactamente esa referencia colgante aquí.

## `scripts/core/effects/continuous/KeywordManager.gd`

### `_init_keyword_map` — línea 26

> Inicializa el mapeo de texto → Constants.Keyword.
> Solo keywords reales de Mitos y Leyendas (corrección 2026-08-20) —
> "Inmune a X"/"portar múltiples armas" son texto libre, no keywords.

### `_init_keyword_patterns` — línea 76

> Bloqueo de habilidad POR NOMBRE, no por instancia — DAR "nombra una
> carta para que pierda su habilidad" (2026-08-29, p.ej. Alicia en
> Wonderland: "en todas las Zonas mientras este Aliado esté en juego").
> A diferencia de _silenced_cards (una carta puntual ya en juego), esto
> afecta CUALQUIER copia del nombre, en cualquier zona, incluso una que
> todavía no exista como Node (una copia en el mazo que se robe después).
> {nombre_lower: [source_node, ...]} — no se limpia con un unregister
> explícito: is_name_locked() valida en cada consulta si el source sigue
> vivo y en juego (auto-expira solo cuando el que nombró sale de juego).

### `_init_keyword_patterns` — línea 87

> Bloqueo de habilidad de UNA carta puntual, mientras una fuente concreta
> siga en juego (2026-09-03, p.ej. Kuchiku Kan: "una carta pierda su
> habilidad... mientras este Aliado esté en juego") — análogo instance-
> based de _named_ability_locks (mismo criterio de auto-expiración
> perezosa), a diferencia de silence_card(..., "permanent") que es
> indefinido de verdad y no debe usarse aquí (rompería cartas como
> Convertir/_execute_targeted_silence, que SÍ son permanentes sin
> condición). {card_instance_id: [source_node, ...]}

### `_init_keyword_patterns` — línea 102

> "Tus Aliados que porten Arma no pueden perder su habilidad" (2026-08-30,
> p.ej. Manuel Bulnes) — lista de fuentes activas de esta protección.
> Array[Node] — sin unregister explícito, se auto-limpia comparando
> is_instance_valid()/is_in_play() en cada consulta.

### `_init_keyword_patterns` — línea 108

> 'Tus Aliados... no pueden perder su habilidad' SIN calificador de Arma
> (2026-09-04, p.ej. Abu Simbel) — versión más amplia de
> _weapon_wielder_silence_immunity_sources, protege a TODOS los Aliados
> del controlador de la fuente, no solo a los que porten Arma.

### `_init_keyword_patterns` — línea 114

> '...No puede perder su habilidad' EN SINGULAR referido a sí misma
> (2026-09-04, p.ej. lagrima del dragon: 'Oro Inicial. Indesterrable. No
> puede perder su habilidad.') — a diferencia de las dos listas de arriba
> (que protegen a TERCEROS mientras 'source' siga en juego), aquí 'source'
> se protege a SÍ MISMA.

### `_init_keyword_patterns` — línea 121

> 'Si está en tu Reserva, las cartas que controles no pueden perder su
> habilidad...' (2026-09-04, p.ej. Terminal P-12) — protege TODAS las
> cartas del controlador de 'source' (sin restringir a Aliados, a
> diferencia de _all_allies_silence_immunity_sources), pero SOLO mientras
> 'source' esté específicamente en Reserva de Oro (no en juego en general).

### `_ready` — línea 130

> Conectar a señales de fin de turno para limpiar temporales.
> GameManager es el único conductor de turnos (ver consolidación 2026-08-19).

### `_check_inherent_keyword` — línea 309

> Verifica keywords inherentes de la carta
>
> Orden de verificación:
> 1. Cache de keywords parseados (más eficiente)
> 2. Método card.has_keyword() si existe — ya incluye las keywords que
> transmiten las Armas equipadas (ver Card.has_keyword(), 2026-08-24)
> 3. Array de keywords en la carta
> 4. Flags booleanos directos
> 5. Parsing en tiempo real (fallback)

### `_check_inherent_keyword` — línea 321

> Método 1: Verificar cache (resultado de scan_and_apply_keywords) — solo
> como atajo cuando SÍ encuentra el keyword. El cache son las keywords
> propias de la carta, calculadas una vez al entrar en juego, y no se
> actualiza si después se le equipa un Arma — un "no está en cache" aquí
> NO es definitivo, hay que seguir a Método 2 (2026-08-26: Cañón Helios
> daba Furia al portador, pero este corte impedía que TurnManager.
> can_attack() lo viera nunca, porque nunca llegaba a Método 2, que sí
> revisa las Armas equipadas).

### `can_be_blocked` — línea 408

> "los Aliados oponentes pierden Imbloqueable" (Diadema Celestial, 2026-10-14)

### `register_weapon_wielder_silence_immunity` — línea 427

> 'Tus Aliados que porten Arma no pueden perder su habilidad' (2026-08-30,
> p.ej. Manuel Bulnes) — mientras 'source' siga en juego, protege de
> silence_card() a los Aliados equipados con un Arma que controle el
> MISMO jugador que controla 'source' (no a los del rival).

### `register_all_allies_silence_immunity` — línea 460

> 'Tus Aliados... no pueden perder su habilidad' SIN calificador de
> Arma (2026-09-04, p.ej. Abu Simbel) — mientras 'source' siga en juego,
> protege de silence_card() a TODOS los Aliados del MISMO controlador de
> 'source' (a diferencia de register_weapon_wielder_silence_immunity(),
> que solo protege a los que porten Arma).

### `_is_protected_from_silence_by_all_allies_source` — línea 490

> 'Tus Armas no pueden perder su habilidad' (2026-09-04, p.ej. skofnung) —
> mismo criterio que _all_allies_silence_immunity_sources, pero para Armas.

### `register_all_weapons_silence_immunity` — línea 496

> 'Tus Armas... no pueden perder su habilidad' (2026-09-04, p.ej.
> skofnung) — mientras 'source' siga en juego, protege de silence_card()
> a TODAS las Armas del MISMO controlador de 'source'.

### `register_self_silence_immunity` — línea 524

> 'No puede perder su habilidad' en singular, referido a la propia
> carta (2026-09-04, p.ej. lagrima del dragon).

### `register_reserva_conditional_full_silence_immunity` — línea 550

> 'Si está en tu Reserva, las cartas que controles no pueden perder su
> habilidad...' (2026-09-04, p.ej. Terminal P-12) — protege TODAS las
> cartas del mismo controlador de 'source' (no solo Aliados), pero solo
> mientras 'source' esté en Constants.Zone.RESERVA_ORO específicamente.

### `silence_card` — línea 580

> Silencia una carta: pierde todas sus keywords (vía remove_keyword, así
> respeta la misma limpieza por duración/salida de juego que cualquier otra
> remoción) y deja de disparar sus habilidades activadas/disparadas — eso lo
> filtra TriggerSystem._check_trigger_conditions() consultando is_silenced().
> Respeta la protección de 'Aliados que porten Arma no pueden perder su
> habilidad' (2026-08-30, Manuel Bulnes), 'Tus Aliados... no pueden perder
> su habilidad' sin calificador (2026-09-04, Abu Simbel) y la de 'prevenir
> que una carta sea afectada por un efecto oponente' (2026-08-30, Estaca)
> — si cualquiera aplica, no hace nada.

### `silence_card` — línea 606

> Prevención reactiva real (2026-09-09 — Estaca, tag "silence"): los
> ~20 llamadores de silence_card() ya se actualizaron con 'await' para
> soportar esto (a pedido del usuario).
> skip_prevention: el llamador ya ofreció la Prevención antes de todo el
> efecto (p.ej. Padre Dagón) — no se vuelve a preguntar.

### `silence_card` — línea 617

> Solo los keywords que la carta REALMENTE tiene (2026-09-04, bug
> reportado: silenciar un Oro base imprimía 'perdió FURIA'/'perdió
> INDESTRUCTIBLE'/etc. para los ~8 keywords del juego enteros, sin
> importar si la carta los tenía o no — puro ruido de debug engañoso,
> no afectaba is_silenced() en sí (que solo mira si hay ENTRADA en
> _silenced_cards, no cuántos keywords se sacaron).

### `_notify_abilities_changed` — línea 643

> 'Los Oros oponentes pierden su habilidad' (2026-09-06, p.ej. Daikaiju
> Furioso) — a diferencia de _silenced_cards (silencio puntual ya
> resuelto), esto es una condición CONTINUA: cualquier Oro rival del
> controlador de 'source', presente o futuro, mientras 'source' siga en
> juego (mismo criterio de auto-limpieza perezosa que _named_ability_locks).

### `_is_card_in_play_generic` — línea 683

> 'los Aliados que estén o entren en juego... si tienen Fuerza 0 no pueden
> disparar sus habilidades' (Tercer Sello, 2026-09-20) — a diferencia de
> _opponent_type_silence_sources (ligado a que 'source' siga en juego), un
> Talismán como Tercer Sello resuelve y se va al Cementerio de inmediato,
> así que este efecto no puede depender de una fuente viva: se apaga solo
> por CONTEO DE TURNOS, igual que el modificador de Fuerza -3 que lo
> acompaña (ver SearchOwnZonePatterns.try_execute_tercer_sello_pattern(),
> mismo valor de 2 pasado a ambos para que se apaguen juntos). GLOBAL
> (ambos jugadores) y sin registrar cartas puntuales — se evalúa la Fuerza
> efectiva de cada carta en el momento de la consulta, vía
> ContinuousEffectManager.get_modified_strength().

### `_is_silenced_by_zero_strength_lock` — línea 711

> 'Los Aliados oponentes ... si tienen Fuerza N o menos no pueden utilizar su
> habilidad' (Sariel, 2026-10-14) — mientras la fuente siga en juego y con
> habilidad. Se busca en las cartas en juego del rival del Aliado.

### `is_silenced` — línea 746

> Verifica si una carta está silenciada (no debe disparar habilidades).
> Incluye el silencio por instancia (_silenced_cards) Y el bloqueo por
> nombre (_named_ability_locks, 2026-08-29) — ambos comparten el mismo
> indicador visual (giro 180°, ver Card._refresh_disabled_rotation()) y el
> mismo choke point real (TriggerSystem._check_trigger_conditions()).

### `lock_ability_by_name` — línea 773

> Registra que TODAS las copias de 'card_name' (en cualquier zona,
> presentes o futuras) pierden su habilidad mientras 'source' siga vivo y
> en juego — DAR 'nombra una carta para que pierda su habilidad' (2026-08-29,
> p.ej. Alicia en Wonderland). No hace falta un unregister explícito:
> is_name_locked() descarta solo las fuentes que ya no son válidas.

### `lock_ability_by_name` — línea 790

> "Tu oponente no puede utilizar más habilidades de cartas con ese nombre este
> turno" (Culto a la Muerte, 2026-10-14): {nombre: {player, turn, active}}.

### `lock_ability_by_instance` — línea 841

> Registra que ESTA carta puntual (no todas las copias del nombre,
> ver lock_ability_by_name) pierde su habilidad mientras 'source' siga
> vivo y en juego (2026-09-03, DAR 'pierda su habilidad... mientras
> [esta carta] esté en juego', p.ej. Kuchiku Kan). Sin unregister
> explícito: is_instance_locked() descarta solo las fuentes que ya no
> son válidas, mismo criterio que is_name_locked().

### `_on_turn_ended` — línea 962

> Tercer Sello (2026-09-20) — mismo criterio de conteo que el modificador
> de Fuerza -3 hermano (ContinuousEffectManager, duration=TIMED): se
> descuenta en CADA fin de turno de cualquier jugador, no solo el propio.

### `_cleanup_by_duration` — línea 1016

> Ya no está silenciada — restaurar el giro visual si tampoco
> está convertida (2026-08-26, ver Card._refresh_disabled_rotation).

### `_get_card_name` — línea 1041

> is_instance_valid() PRIMERO (2026-09-19, misma familia de bug que
> ContinuousEffectManager._get_card_id()/_get_card_name()/_resolve_
> targets() y ContinuousVisualSync.update_all_card_visuals() — 'is Node'
> bare sobre una referencia ya liberada revienta con "Left operand of
> 'is' is a previously freed instance").

## `scripts/core/effects/continuous/ModifierRegistry.gd`

### `register_modifier` — línea 107

> Recalcular y actualizar visuales de las cartas afectadas. Con target
> dinámico (ALL/ALLIES/ENEMIES/OTHER, un String) _resolve_targets()
> devuelve vacío a propósito — se resuelve carta por carta en
> _get_applicable_modifiers(), no aquí — así que sin esto el badge de
> Fuerza de los Aliados YA en juego nunca se refrescaba al entrar un
> aura nueva (2026-08-25, confirmado con Patria Vieja: el bonus se
> calculaba bien pero no se veía hasta que algo más recalculaba esa
> carta puntual).

### `_get_modified_stat` — línea 257

> 2026-09-15, bug real reportado por el usuario: "Invalid operands
> 'String' and 'int' in operator '!='" — algo dejó un valor no-int
> en _previous_values (probablemente vía _get_base_stat()'s rama
> genérica '_:', que devuelve card.get(stat) SIN castear a int para
> cualquier stat que no sea strength/cost/damage). Se castea aquí
> como salvaguarda y se deja rastro si pasa, en vez de romper la
> comparación de abajo.

### `_get_modified_stat` — línea 304

> Debug — acumulado, no impreso todavía (2026-09-11, bug real
> reportado por el usuario: esta función recalcula TODOS los
> modificadores de la carta cada vez que CUALQUIER cosa dispara
> un recálculo global, no solo cuando esta carta cambia — sin
> este acumulador, cada modificador ya aplicado se reimprimía
> idéntico en cada pasada aunque el resultado final no cambiara).
> Se imprime más abajo solo si el valor final de verdad cambió.

### `_get_base_stat` — línea 390

> 2026-09-15: cast defensivo — a diferencia de las ramas de
> arriba (strength/cost, que leen propiedades típicamente
> numéricas de Card), aquí 'stat' es un nombre arbitrario y
> card.get(stat) es Variant sin garantía de tipo; devolver
> un String directo aquí (declarado -> int) fue la causa real
> de "Invalid operands 'String' and 'int' in operator '!='"
> más adelante en _get_modified_stat()/ModifierRegistry.

### `_card_matches_global_target` — línea 441

> Mismo controlador que la fuente (2026-08-24): antes esto comparaba
> mitologia/faccion, no dueno real -- "Tus Aliados" en el texto real
> de las cartas significa "los que tu controlas", sin importar su
> mitologia; con la comparacion vieja, un aura como la de Patria Vieja
> habria afectado a Aliados rivales de la misma mitologia y ninguno de
> los propios de otra.
> EN JUEGO (2026-09-02, bug reportado por el usuario: Sable de
> Napoleón le daba Fuerza a Aliados en la MANO) — "Tus Aliados"
> significa los que controlas EN JUEGO, nunca los de la mano/
> Castillo/Cementerio. _is_card_in_play() ya existía (usado solo
> para registrar/desregistrar la fuente al entrar/salir de juego
> ella misma) pero nunca se consultaba aquí, del lado del OBJETIVO.

### `_card_matches_filter` — línea 483

> 2026-10-17, bug real reportado por el usuario ("Invalid operands
> 'String' and 'int' in operator '!='"): _get_card_type() devuelve el
> nombre ("ALIADO") pero varios registros pasan el enum
> (Constants.CardType.ALIADO). Se comparan los dos como nombre.

### `_card_matches_filter` — línea 528

> Filtro por raza — admite una raza única o una lista (2026-09-04, p.ej.
> shedo titan: "Tus Aliados Ignis o Titán ganan...")

### `_is_modifier_active` — línea 621

> 2026-10-13 (§63, Alicia en Wonderland nombrando Patria Vieja):
> una fuente silenciada o con su nombre bloqueado pierde también
> sus habilidades estáticas, no solo los botones y los triggers.

## `scripts/core/effects/mechanics/CardQuery.gd`

### `(nivel de archivo)` — línea 2

> CardQuery — Consultas comunes de las mecánicas: cartas en juego con un texto, controlador, Armas en juego,
> la oración "al comienzo del turno" que vale en este turno.
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

### `cards_in_play_with` — línea 37

> La oración "al comienzo del turno" que vale en ESTE turno (2026-10-18,
> ngenechen/Carcosa): "al comienzo de tu turno" solo en el tuyo, "al comienzo
> del turno oponente" solo en el del rival y "al comienzo del turno" a secas
> en los dos. "" si ninguna aplica.

## `scripts/core/effects/mechanics/CastleTopPlay.gd`

### `(nivel de archivo)` — línea 2

> CastleTopPlay — Jugar desde el tope del Castillo (Escritura Sagrada).
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

### `(nivel de archivo)` — línea 10

> -----------------------------------------------------------------------------
> Escritura Sagrada: "Cuando entra en juego, juega mostrando las primeras dos
> cartas de tu Castillo y puedes jugar cartas de coste 1 o más de ahí pagando
> su coste, por el turno. Si muestras Oros, puedes ponerlos en el fondo de tu
> Castillo."
> Anfitrión (2026-10-18, a pedido del usuario): al tocar tu Castillo se abre
> un visor con las dos primeras, como el del Cementerio (ZoneViewerModule), y
> los Oros van solos al fondo. Remoto: botón sobre el texto de la carta
> (habilidad "sintética", CardInspectionLayer.usable_abilities_for).
> -----------------------------------------------------------------------------

## `scripts/core/effects/mechanics/ConvertPatterns.gd`

### `(nivel de archivo)` — línea 2

> ConvertPatterns — Convertir cartas: en Tótem sin habilidad (tenshi z, Ángel Jeremiel) o en Aliado
> (Viejo del Saco, Vampiro de Rancagua).
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/InPlayAbilities.gd`

### `(nivel de archivo)` — línea 2

> InPlayAbilities — Habilidades al entrar y botones: Aegishjalmur, Ciudad de los Césares, Quicaví,
> fortaleza hoshi (Desterrar del tope).
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/MechanicPatterns.gd`

### `(nivel de archivo)` — línea 2

> MechanicPatterns — Despachador: qué texto de carta va a qué mecánica (lo llama TriggerResolution).
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/PreventionCosts.gd`

### `(nivel de archivo)` — línea 2

> PreventionCosts — Prevención desde la mano o desterrando el Arma, y sus costos (Armadura Dorada,
> Dos de Cada Uno, ngenechen). Registro: EffectController._build_prevention_registry().
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/ProtectionRules.gd`

### `(nivel de archivo)` — línea 2

> ProtectionRules — Reglas de protección: no puede ser cancelado / Desterrado, daño al Destierro,
> Indestructible mientras bloquea, Armas que no pueden ser canceladas.
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/SearchPatterns.gd`

### `(nivel de archivo)` — línea 2

> SearchPatterns — Buscar y jugar desde el Castillo: fortaleza hoshi, Pan de Muerto, Ángel Redentor,
> Dos de Cada Uno, Supremacia Kaiju.
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/TurnLimits.gd`

### `(nivel de archivo)` — línea 2

> TurnLimits — Límites por turno: Terminal P-12 (buscar, habilidades fuera del juego, mirar mano/Castillo)
> y Pan de Muerto (quince cartas Botadas/Desterradas por Castillo).
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/mechanics/TurnStartPatterns.gd`

### `(nivel de archivo)` — línea 2

> TurnStartPatterns — Comienzo del turno y Agrupación: la esmeralda, el Oro de Ángel Redentor, Carcosa.
> (2026-10-18: separado de PresetDeckPatterns.gd por mecánica, punto 2 de la revisión de código.)
> Se usa con preload.

## `scripts/core/effects/targeting/SelectionDialogs.gd`

### `await_single_pick` — línea 23

> Abre un panel CUSTOM de 1-sola-elección y espera la respuesta —
> extraído (2026-08-30) del mismo bloque de 15-20 líneas que se repetía
> copiado en Don de Amma, Tesoro de los Césares, Miguel, las dos de Tyet,
> Bernardo O'Higgins y varias más: open_selection() + Dictionary de
> estado (los lambdas de GDScript capturan variables locales por VALOR,
> así que 'var picked'/'var done' sueltos nunca se enteraban de la
> elección real — ver el resto de este archivo para más detalle de ese
> bug ya conocido) + conectar card_selected/selection_completed/
> selection_cancelled + esperar + desconectar.
> max_selections=1 siempre; min_selections=1 por defecto (con eso,
> SelectionManager emite 'card_selected' apenas se elige la primera, no
> hace falta escuchar 'selection_completed'). min_selections=0 (p.ej.
> costo opcional tipo Bernardo O'Higgins: 'Puedes Barajar...') SÍ puede
> terminar en 'selection_completed' con array vacío (confirmó sin elegir
> nada) — se escuchan las dos señales siempre, la de más no molesta.
> 'chooser_id' (2026-10-07, a pedido del usuario: "arranca con await_
> single_pick" — ver arquitectura.md §39): el puente de red para esto ya
> estaba COMPLETO desde Fase 3 — open_selection()/_delegate_selection_to_
> remote() ya saben mandarlo por red y emiten las mismas 3 señales que
> esta función ya escucha más abajo. Solo faltaba exponer el parámetro
> hasta aquí; nadie lo había necesitado porque hasta hoy todo llamador de
> await_single_pick() se quedaba con el default 0 (bloqueado para el
> Remoto por un guard explícito en cada carta).
> Returns: el card_data elegido, o {} si se canceló o confirmó vacío.

### `await_card_pair_choice` — línea 96

> Modal de Selección Visual entre 2 Cartas (p.ej. La Ouija: tope vs fondo de Castillo).
> Presenta las dos cartas niveladas en pantalla con estética de Altar Catedralicio limpia y directa.
> 'chooser_id' (2026-10-07, ver arquitectura.md §41): mismo criterio que
> await_castillo_pick() — esto es un modal visual con Nodos reales de ESTA
> pantalla, no tiene sentido tal cual para el Remoto. Se delega a await_
> choice() (ya con puente de red) con label_a/label_b como texto en vez
> de construir un sistema nuevo — se pierde el arte de las cartas en la
> pantalla del Remoto, pero la elección en sí es la misma.

### `await_choice` — línea 332

> Modal de Elección estilizado Fantasy TCG con fondo de altar catedralicio,
> shader de viñeta suave y botones dorados de alta legibilidad (sin emojis).
> Returns: el índice (0-based) de la opción elegida.
>
> 'chooser_id' (2026-09-30, Fase 3 del plan de paridad remota — mismo
> criterio que SelectionManager._delegate_selection_to_remote()): si quien
> elige es el jugador 1 y hay un Remoto real conectado, se le pregunta a
> él por red en vez de abrir este popup local (que de otro modo lo
> mostraría en la pantalla del Anfitrión, quien terminaría eligiendo por
> una decisión que no es suya).

### `start_castillo_pick` — línea 521

> Versión 'start' de await_castillo_pick() (2026-09-06, a pedido del
> usuario) — separada para poder correr EN CARRERA contra otro tipo de
> selección (p.ej. CardInteractionModule.start_target_selection(), usada
> por Sherlock Holmes para elegir entre 'cartas en juego' o 'un Castillo'
> con el primer click real, sin preguntar antes). El que resuelve primero
> debe cancelar al otro (ver cancel_castillo_pick()). callback recibe
> true/false (propio/rival).

### `start_castillo_pick` — línea 548

> Cursor de mano + pulso suave de brillo (2026-08-30, a pedido del
> usuario: "también ponerle un efecto o hacerlo 'cliqueable' para mayor
> visual" — el borde estático ya avisaba que había que elegir, pero no
> se sentía interactivo hasta clickear). Se para al resolver, junto con
> todo lo demás.

### `start_castillo_pick` — línea 593

> Solo tu Castillo (2026-10-17, p.ej. "Roba hasta N"): el rival no
> brilla ni se puede clickear.

### `await_castillo_pick` — línea 633

> Espera un click directo sobre el Panel del Castillo propio o del
> rival en el tablero — reemplaza el popup de 2 botones de texto para
> elegir 'tu Castillo o el del oponente' (2026-08-30, a pedido del
> usuario: 'estaría bueno poder hacer click al castillo para hacerlo más
> interactivo', p.ej. Infernum Vox, Aho, Espada del Juicio). Resalta
> ambos paneles con un borde celeste mientras espera. Sin cancelar —
> mismo criterio que await_two_choice(), es una elección obligatoria
> entre dos zonas, no un 'puedes'. Envoltorio de start_castillo_pick()
> (2026-09-06, mismo split que start_target_selection()/await_target()).
> 'chooser_id' (2026-10-07, ver arquitectura.md §40): esto es un click
> sobre un Panel real de ESTA pantalla — no tiene sentido para el Remoto,
> que no ve el tablero del Anfitrión. En vez de construir un sistema de
> red nuevo, se delega a await_choice() (ya tiene puente de red completo,
> "choose_option") con las mismas dos opciones en texto — misma elección
> A/B, otro medio.
> Returns: true si se eligió el Castillo propio, false si el rival.

### `await_multi_pick` — línea 676

> Selección múltiple (0 a max_selections) y espera la respuesta —
> extraído (2026-08-30) del mismo bloque repetido en
> _resolve_search_cemetery_to_hand()/_select_hand_cards_for_discard()
> (TargetedEffectExecutor.gd) y _resolve_reveal_cost_reduction()
> (GoldManager.gd). A diferencia de await_single_pick(), aquí 'canceló
> del todo' y 'confirmó sin elegir nada' son resultados DISTINTOS a
> propósito (algunos llamadores necesitan diferenciarlos: declinar el
> 'puedes' entero vs. aceptarlo pero no encontrar nada que valga la
> pena elegir) — por eso devuelve un Dictionary con las dos señales en
> vez de colapsarlas en un Array vacío como haría await_single_pick().
> 'chooser_id' (2026-10-07, mismo arreglo que await_single_pick(), ver
> arquitectura.md §40): el puente ya existe en open_selection(), solo
> faltaba exponerlo. OJO — límite real para quien lo use del lado del
> Remoto: RemoteMirrorController._show_select_cards_prompt() resuelve la
> multi-selección con checkboxes, no con orden de click, así que cualquier
> llamador que dependa de 'el orden en que se clickeó' (p.ej. Infernum
> Vox, que reordena el tope del Castillo) NO preserva ese orden para el
> Remoto — vuelve siempre en el orden original en que se mostraron. 'Mira
> y elige cuáles' funciona igual para los dos lados; 'en QUÉ ORDEN' solo
> para el Anfitrión.
> Returns: {"cancelled": bool, "picked": Array[Dictionary]}.

## `scripts/core/effects/targeting/SelectionManager.gd`

### `open_selection` — línea 318

> Abre el panel de selección con las cartas especificadas
>
> Args:
> card_data_list: Array de diccionarios con datos de cartas
> mode: SelectionMode (REVEAL, EXHUMAR, SEARCH, etc.) o int
> config: {
> title: String,
> max_selections: int,
> min_selections: int,
> filter: Callable,  # (card_data) -> bool
> can_cancel: bool
> }
> chooser_id: quién debe elegir (0 = jugador local/Anfitrión, el único
> caso que existía antes de esto; 1 = jugador 1). 2026-09-30, Fase 3
> del plan de paridad remota (docs/plans/2026-09-20-remote-
> multiplayer-parity.md) — default 0 a propósito: ningún llamador
> existente (~100 sitios reales) necesita cambiar, solo los que se
> conviertan a propósito para que el Remoto decida sus propias
> cartas pasan chooser_id=1 explícito.

### `open_selection` — línea 385

> Solo aquí 'displayed_cards' ya tiene las cartas instanciadas — antes se
> llamaba ANTES del loop de arriba y el label de modo REVEAL siempre
> decía "Mostrando 0 carta(s)" sin importar cuántas se pasaran
> (2026-08-26, visto con Tangata Manu mostrando 6 cartas).

### `_create_selection_card` — línea 580

> Inspección con click derecho (2026-08-30, a pedido del usuario: poder
> leer de cerca las cartas de un pool de selección — p.ej. elegir cuáles
> desterrar de los Cementerios con Espada de O'Higgins — antes no
> conectaba nada, así que el click derecho no hacía nada aquí). current_zone
> por defecto es Constants.Zone.MANO (Card.gd) y esta instancia nunca pasa
> por set_zone(): sin corregirlo, _build_ability_buttons() la trataría
> como si estuviera en la mano y podría ofrecer botones de habilidades
> 'usables desde la mano' (Ramón Freire/Tyet) que no deberían aparecer
> para una carta que solo se está mostrando en un pool de elección.

### `_clear_cards` — línea 664

> Desconectar señales de interacción ANTES de liberar (2026-08-29,
> mismo bug que CardManager.destroy_card()/exile_card()) — estas
> cartas del panel se conectan a card_clicked/card_hovered/
> card_unhovered (ver _display_card() más arriba) y sin
> desconectar, un hover que sigue apuntando al nodo después de
> queue_free() tira "Invalid access... on a base object of type
> previously freed" al tocar .modulate en el próximo evento de
> mouse (reportado: pasaba justo al elegir un Oro del Castillo
> en la búsqueda de Don de Amma, que cierra este panel).

### `_on_card_clicked` — línea 732

> Al llegar al máximo ya no queda ninguna elección posible (2026-08-28,
> a pedido del usuario: clickear la carta que quiero elegir alcanza,
> sin tener que apretar Confirmar aparte) — confirma solo. Si
> min_selections < max_selections (p.ej. "hasta 2") el botón
> Confirmar sigue disponible para cerrar con MENOS del máximo.

## `scripts/core/effects/triggers/AziPatterns.gd`

### `(nivel de archivo)` — línea 2

> Azi del Abismo (2026-10-17, bug real reportado por el usuario: "ese azi no
> se transformó en oro" — solo se resolvía el "Descarta una carta"):
> "Una vez por turno, Descarta una carta de tu mano para convertir este
> Aliado hasta tu próximo turno en un Oro con la habilidad "Reduce el daño
> recibido por tu Castillo en 1 por cada Oro Azi que controles.""
> La conversión y la vuelta a Aliado están en GoldManager
> (convert_ally_to_gold_until_next_turn / revert_converted_golds).
> Se usa con preload.

## `scripts/core/effects/triggers/BanishOpponentPatterns.gd`

### `(nivel de archivo)` — línea 3

> BanishOpponentPatterns — 3 de 7 mitades de LookAndPlayResolver.gd, dividido
> por tamaño el 2026-09-06 ("módulos gordos"). Cubre banish/destierro/mill/
> anulación dirigidos al oponente, removal-oriented: ignis desatado, shoki,
> colaborador titan, Ngenechén, ea poe, Asmodeus, cuervo nocturno,
> resistencia de acero, Duelo de Dragones (banish), Culto a la Muerte,
> Ciempiés-SP, Dragón Dorado, Carcosa, estacion gaia, templo de hatshepsut,
> necro-titan, akuma el terrible, akari musashi. Incluye el helper compartido
> _register_talisman_surcharge_once (solo lo usa una función de este archivo).
> Llamada solo desde LookAndPlayResolver.gd (facade) — ver ese archivo para
> la lista completa de las 7 mitades hermanas.

### `try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern` — línea 22

> 'Destierra un Aliado oponente de coste 3 o menos y busca en tu
> Castillo o Cementerio una carta Ignis o Titán, juégalo reduciendo su
> coste en un Oro hasta un mínimo de 0' (ignis desatado, 2026-09-04) —
> dispara tanto en 'entra en juego' como en 'ataca'.

### `try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern` — línea 42

> 2026-09-12: current_zone (no get_parent()) — un Arma equipada, por
> ejemplo, es hija de su portador, no de la línea, así que el chequeo
> viejo de parent nunca la hubiera aceptado (bug real reportado por
> el usuario, ver arquitectura.md §10.5).

### `try_execute_banish_opponent_ally_search_ignis_titan_discount_pattern` — línea 53

> 2026-10-14, a pedido del usuario: el selector del tablero con tu
> Castillo y tu Cementerio a la vez, en vez del popup "¿Dónde buscar?".
> El Destierro de arriba ya consultó Prevención por su cuenta (banish()) —
> esta ventana es para la búsqueda+juego con descuento, sin cobertura propia.

### `try_execute_banish_two_from_one_cemetery_then_draw_pattern` — línea 86

> 'En tu Fase Final, Destierra dos cartas de un Cementerio. Luego,
> Roba una carta' (shoki, 2026-09-04) — 'un Cementerio' (sin posesivo,
> singular) = el jugador elige DE CUÁL de los dos, luego saca ambas de
> ESE MISMO (a diferencia de 'los Cementerios', que mezcla el pool de
> ambos).

### `try_execute_banish_two_from_one_cemetery_then_draw_pattern` — línea 98

> Pila de Respuesta Universal (2026-09-09, piloto de migración — ver
> docs/plans/2026-09-09-pila-respuesta-universal-design.md): ya se
> declaró todo lo que hacía falta (de qué Cementerio), solo aquí se abre
> la ventana real para el rival antes de ejecutar el efecto.

### `try_execute_banish_two_from_one_cemetery_then_draw_pattern` — línea 104

> Selector con los dos Cementerios, las dos de UNO solo (2026-10-14).

### `try_execute_banish_opponent_castillo_by_titan_ignis_cost_draw_pattern` — línea 114

> 'Destierra tantas cartas del tope del Castillo oponente como coste
> sumen los Aliados Titán o Ignis que controles y Roba dos cartas'
> (colaborador titan, 2026-09-04) — solo esta cláusula; el descuento
> opcional por Destruir/Descartar un Aliado Titán o Ignis propio NO
> implementado.

### `try_execute_banish_opponent_cost_sum_six_pattern` — línea 148

> 'Cuando entra en juego Destierra cartas oponentes cuyos costes sumen
> hasta 6' (Ngenechén, 2026-09-06) — solo esta cláusula; 'Al comienzo del
> turno oponente, genera un Oro por el turno y Roba dos cartas' (trigger
> recurrente en CADA turno del rival, no solo una vez) y 'Una vez por
> turno, puedes Barajar una carta de tu mano para prevenir un efecto'
> (activada) NO implementadas.

### `try_execute_banish_opponent_cost_sum_six_pattern` — línea 170

> 2026-09-13, a pedido del usuario: click directo con presupuesto en
> vivo (dynamic_filter, ver arquitectura.md §10.20/Tempilcahue) en vez
> del modal viejo que reintentaba toda la selección si te pasabas de 6.

### `try_execute_banish_opponent_cost_sum_six_pattern` — línea 182

> Sin ventana genérica aquí a propósito (2026-09-09): banish() con
> can_be_prevented=true (default) ya consulta Prevención adentro —
> agregar la ventana genérica antes duplicaría la pregunta para el
> mismo efecto. Ver docs/plans/2026-09-09-pila-respuesta-universal-design.md.

### `try_execute_pay_x_banish_opponent_castillo_draw_per_talisman_totem_pattern` — línea 193

> 'Cuando lo juegues, puedes pagar cualquier cantidad de Oros. Destierra
> tantas cartas del tope del Castillo oponente como Oros hayas pagado por
> este Talismán más dos. Por cada Talismán o Tótem Desterrado de esta
> forma, Roba una carta' (ea poe, 2026-09-06). El '+2' del texto queda fijo
> en el código (no se parsea el número): el texto real de esta carta
> específica llega con codificación rota en el cache local ('m�s dos'), así
> que el ancla de detección evita esos caracteres y solo confirma la parte
> sin corromper.
>
> No usa ActionModule.mill() para el Destierro: su fallback sin GameBoard
> (EffectController._mill_cards_fallback(), ver su comentario) deja
> 'milled_cards' SIEMPRE vacío para Destierro, así que no hay forma de
> saber qué tipo tenía cada carta desterrada — aquí se mueve carta por
> carta a mano, igual que el resto de patrones que ya manipulan
> CardManager.get_deck()/get_exile() directamente (p.ej. Tyet).

### `try_execute_opponent_hand_cost_max_to_bottom_pattern` — línea 253

> 'Cuando entra en juego, tu oponente pone sus cartas de coste 2 o
> menos en el fondo del Castillo' (Asmodeus, 2026-09-06) — TODAS las
> cartas de coste ≤2 de la mano rival, sin elección (no dice 'puedes'),
> al fondo de su propio mazo.

### `try_execute_opponent_mill_six_exile_pattern` — línea 293

> 'Tu oponente Destierra seis cartas del tope de su Castillo' (cuervo
> nocturno, 2026-09-04) — solo la cláusula incondicional; 'Puedes poner
> esta y otra carta de tu mano en el fondo de tu Castillo y Robar dos
> cartas' NO implementada (conflicto real con el destino post-resolución
> que decide GoldManager._play_talisman() después de que este patrón ya
> terminó — mover la carta aquí duplicaría el manejo).

### `try_execute_search_three_opponent_castillo_banish_draw_pattern` — línea 313

> 'Busca tres cartas de distinto tipo en el Castillo oponente,
> Destiérralas y Roba una carta' (resistencia de acero, 2026-09-04) —
> simplificación conocida: no se fuerza 'de distinto tipo' (ActionModule.
> search() no tiene ese filtro, solo distinct_names por NOMBRE).

### `try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern` — línea 331

> 'Sube una carta oponente de coste 2 o menos a la mano o Destruye
> hasta dos cartas de coste 1 o menos. Roba dos cartas' (cruzar el
> bosque, 2026-09-04) — elección A/B + Robo incondicional. NO cubre la
> variante de reingreso desde el Destierro (Barajarla en su Castillo en
> vez de ir al Cementerio al resolver) — play_card_from_exile() no
> tiene un override de destino post-resolución todavía.

### `try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern` — línea 350

> 2026-09-13, a pedido del usuario: click directo en el
> Cementerio rival en vez del modal de lista viejo.

### `try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern` — línea 367

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_annul_non_ally_banish_or_cancel_ability_pattern` — línea 394

> 'Elige un efecto: - Anula una carta de coste 2 o menos que no sea
> Aliado y Destierra esa carta. - Cancela la habilidad de una carta y tu
> oponente no puede utilizar más habilidades de cartas con ese nombre
> este turno' (Culto a la Muerte, 2026-09-04) — elección A/B. La
> restricción 'no puede utilizar más habilidades de cartas con ese
> nombre este turno' de la rama B NO implementada (no hay candado
> 'por el resto del turno' por nombre, solo 'mientras la fuente siga en
> juego' — y un Talismán no se queda en juego).

### `try_execute_annul_non_ally_banish_or_cancel_ability_pattern` — línea 416

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_annul_non_ally_banish_or_cancel_ability_pattern` — línea 426

> Sin ventana genérica aquí (2026-09-09): banish()/silence_card()
> ya consultan Prevención adentro por su cuenta.

### `try_execute_annul_non_ally_banish_or_cancel_ability_pattern` — línea 431

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_annul_cost_max_pattern` — línea 446

> 'Anula una carta de coste N o menos' (2026-09-04, p.ej. Ciempiés-SP/
> cienpies sp: 'Única. Anula una carta de coste 3 o menos.') — el genérico
> ANNUL de UniversalCardParser solo reconoce 'anula un/el Aliado'
> (sin filtro de coste ni otros tipos), así que este patrón cubre la
> forma con tope de coste sobre cualquier objetivo (Aliado/Arma/Tótem).
> Reusa _select_annul_target_cost_filter() (Paladín Bestiarium).

### `try_execute_annul_cost_max_pattern` — línea 469

> Sin ventana genérica aquí (2026-09-09): destroy() con can_be_prevented=
> true (4to arg) ya consulta Prevención (Estaca) adentro.

### `try_execute_annul_then_shuffle_hand_by_cost_pattern` — línea 478

> 'Anula una carta. Luego, Baraja tantas cartas de tu mano como coste
> tenga' (Dragón Dorado, 2026-09-04) — 'Anula una carta' SIN tope de
> coste (a diferencia de try_execute_annul_cost_max_pattern), y 'Luego'
> depende de que la anulación haya resuelto de verdad (se lee el coste
> de la carta anulada, DAR: si no se anuló nada, 'Luego' no corre).

### `try_execute_annul_then_shuffle_hand_by_cost_pattern` — línea 505

> 2026-09-13, a pedido del usuario: click directo en la mano en
> vez del modal de lista viejo. Costo TODO o NADA de 'amount'
> cartas exactas (mismo criterio que Belta, §10.19): si elige
> menos, no se mueve nada.

### `try_execute_opponent_mill_four_pattern` — línea 531

> 'Al comienzo de tu turno y cuando salga del juego, tu oponente Bota
> cuatro cartas' (Carcosa, 2026-09-04) — dispara tanto en on_turn_start
> como en on_leave_play (mismo dispatcher compartido).

### `try_execute_draw_discard_opponent_mill_exile_pattern` — línea 546

> 'Cuando entra en juego, Roba dos cartas, Descarta una carta y tu
> oponente Destierra dos cartas del tope de su Castillo' (estacion gaia,
> 2026-09-04).

### `try_execute_shuffle_or_banish_opponent_cost_max_pattern` — línea 580

> 'Cuando entra en juego, Baraja o Destierra una carta oponente de
> coste N o menos' (templo de hatshepsut, 2026-09-04) — objetivo único,
> elección A/B sobre el MISMO objetivo (se elige el objetivo primero,
> después qué hacerle — 'baraja o destierra' aplica a la misma carta).

### `try_execute_shuffle_or_banish_opponent_cost_max_pattern` — línea 599

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_shuffle_or_banish_opponent_cost_max_pattern` — línea 609

> Sin ventana genérica aquí (2026-09-09): banish()/return_to_deck() ya
> consultan Prevención adentro por su cuenta en las dos ramas.

### `try_execute_search_two_distinct_names_banish_or_cemetery_pattern` — línea 623

> 'Cuando entra en juego, busca en un Castillo dos cartas de distinto
> nombre y ponlas en el Destierro o Cementerio de su dueño' (necro-titan,
> 2026-09-04) — 'de su dueño' = el destino es del dueño de CADA carta
> buscada (search() ya lo hace así, ver docstring de ActionModule.search:
> 'el destino también es SUYO'). 'Destierro o Cementerio' = una elección
> para ambas cartas.

### `try_execute_banish_cost_or_search_two_banish_pattern` — línea 648

> 'Cuando entra en juego, Destierra una carta de coste 2 o menos o
> busca dos cartas en un Castillo y Destiérralas' (akuma el terrible,
> 2026-09-04) — elección A/B.

### `try_execute_banish_cost_or_search_two_banish_pattern` — línea 662

> Sin ventana genérica aquí (2026-09-09): banish() ya consulta Prevención adentro.

### `try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern` — línea 675

> 'Cuando entra en juego o ataque, Destierra una carta oponente que no
> sea Oro. ... A tu oponente le cuesta un Oro adicional jugar Talismanes'
> (akari musashi, 2026-09-04) — esta función solo cubre el Destierro
> dirigido (la sobretasa de Talismanes se registra aparte, una sola vez,
> desde el mismo llamador vía _register_talisman_surcharge_once).

### `try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern` — línea 693

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern` — línea 695

> Sin cartas válidas no se pide objetivo (2026-10-17, bug real reportado
> por el usuario: pedía elegir aunque el oponente no tuviera cartas).

### `try_execute_banish_opponent_non_gold_and_talisman_surcharge_pattern` — línea 707

> Sin ventana genérica aquí (2026-09-09): banish() ya consulta Prevención adentro.

## `scripts/core/effects/triggers/CemeteryRevivePatterns.gd`

### `(nivel de archivo)` — línea 2

> Alto Prime (2026-10-17, a pedido del usuario): "Puedes Descartar una carta
> para poner este Aliado en juego desde tu Cementerio como un Aliado sin
> habilidad." — habilidad usable desde el Cementerio (no es Exhumar). Mismo
> "sin habilidad" que Belta: entra con el texto vacío. Se usa con preload.

### `discard_to_revive_without_ability` — línea 50

> Kaitai (2026-10-17, bug real reportado por el usuario: en la Fase Final
> resolvía "Roba tres cartas y Descarta dos", que es la de entrada):
> "En tu Fase Final, una vez por turno, puedes Desterrar hasta tantas cartas
> de los Cementerios como Fuerza tenga este Aliado."

### `try_execute` — línea 75

> Antonio Pincheira (2026-10-17, a pedido del usuario): "tu oponente Bota
> seis cartas. Pon hasta un Oro de su Cementerio en tu Reserva [y busca dos
> Aliados en tu Castillo y ponlos en tu mano]." — las dos versiones de la
> carta. El Oro sigue siendo de su dueño (vuelve a SU Cementerio) pero lo
> controlas tú.

## `scripts/core/effects/triggers/CemeteryTriggers.gd`

### `(nivel de archivo)` — línea 2

> CemeteryTriggers — "Cuando sea puesta en tu Cementerio, ..." (2026-10-14,
> a pedido del usuario: Lanza Argenta y las demás cartas con este disparador
> no lo tenían en ningún lado).
>
> Toda carta que entra a un Cementerio pasa por CardManager._append_to_cemetery()
> (y al Destierro por append_to_exile()), que emiten card_put_in_cemetery /
> card_put_in_exile. Aquí se anota QUÉ entró, POR QUÉ (efecto/daño de quién,
> en el turno de quién) y el disparador se resuelve recién cuando NO queda
> nada resolviéndose (la regla que pidió el usuario: "Signo Amarillo descarta
> Lanza Argenta → Signo termina primero, después dispara la Lanza").
>
> Dos clases de cartas:
> - la propia carta que entra al Cementerio (Lanza Argenta, kultrung,
> piedra del chaman, haka pei, daiksuke, serpiente verde, manzana
> envenenada): su texto vive en el Cementerio (es un Dictionary), así que
> para la ventana de respuesta del rival se arma un Node temporal;
> - cartas EN JUEGO que miran tu Cementerio (manu tara, fudo-myo), una vez
> por turno.

### `_manu_tara` — línea 483

> --- Escudo de Vlad III (en juego, 2026-10-18): "Una vez por turno, cuando
> una carta sea puesta en un Cementerio, puedes Desterrarla."

## `scripts/core/effects/triggers/ConvertAndMiscResolver.gd`

### `(nivel de archivo)` — línea 2

> ConvertAndMiscResolver — Patrones compuestos de Convertir/transformar
> cartas (Sherlock Holmes, Jormundgander), destierro por cantidad dinámica
> de Aliados (Espada del Juicio), descarte+robo del oponente (Miguel) y
> silencio por nombre (Alicia en Wonderland). Cada uno detecta su propio
> texto por regex y resuelve lo que extract_action() no puede manejar solo
> (esa función reconoce UNA acción por texto, la primera que matchea).
> Opera sobre TriggerSystem via _executor._main (mismo Node que
> TargetedEffectExecutor._main — ver ese archivo).
> Extraído de TargetedEffectExecutor.gd (2026-08-30, "módulos gordos" —
> mismo corte que ya separó LookAndPlayResolver.gd).

### `try_execute_mill_convert_to_ally_pattern` — línea 27

> Detecta el patrón único de Sherlock Holmes (2026-08-29, verificado
> contra la API — 2 reimpresiones idénticas). Las cartas 'convertidas' NO
> se juegan ni se pagan, aparecen directo en juego bajo el control del
> jugador del efecto.
>
> 2026-09-06, a pedido del usuario — relectura de 'convierte hasta dos
> cartas que no sean Oro O del tope de un Castillo': el 'o' separa DOS
> fuentes alternativas (elección del jugador), no es un filtro de tipo
> sobre una sola fuente como se había asumido el 2026-08-29:
> - 'cartas en juego que no sean Oro': el jugador elige a mano hasta N
> cartas YA EN JUEGO (de cualquier lado, sin posesivo — ver
> [[project_no_zone_means_in_play]]) para convertir in-place.
> - 'del tope de un Castillo': comportamiento original — se sacan a
> ciegas del tope del mazo elegido, sin filtrar por tipo.
> SIN preguntar antes cuál (a pedido del usuario, 2026-09-06): ambas
> fuentes quedan clickeables A LA VEZ — una carta en juego (no Oro) o
> cualquiera de los dos Paneles de Castillo — y el PRIMER click real
> decide la fuente para el resto de la resolución; la otra deja de ser
> clickeable en cuanto se resuelve la carrera (SelectionManager.
> start_castillo_pick()/cancel_castillo_pick() en carrera contra
> CardInteractionModule.start_target_selection()/cancel_target_selection(),
> mismo split ya usado por await_target()/await_castillo_pick()).
>
> Ambas ramas terminan en el mismo Convertir real de DAR Sección 8
> (is_converted + KeywordManager.silence_card — mismo mecanismo que
> Capitán O'Brien/Signo Amarillo, giro visual 180°) y la misma Fuerza fija
> como modificador CONTINUO (ContinuousEffectManager, capa
> LAYER_7A_CHAR_SETTING, operación 'set', sin source real — permanente de
> verdad, no atado a que Sherlock siga en juego) para que el badge de
> Fuerza muestre el valor EFECTIVO aunque la carta impresa diga otra cosa.
> Returns: true si el patrón aplicaba.

### `try_execute_mill_convert_to_ally_pattern` — línea 61

> Viejo del Saco (2026-10-18) tiene su propio patrón (mechanics/ConvertPatterns.gd).

### `try_execute_mill_convert_to_ally_pattern` — línea 112

> Autorreferenciable (2026-09-06, a pedido del usuario: las cartas de
> Imperio SÍ pueden targetear/afectarse a sí mismas salvo que digan lo
> contrario) — Sherlock puede convertirse a sí mismo.

### `try_execute_mill_convert_to_ally_pattern` — línea 117

> Carrera: castillo activo en paralelo mientras se espera el primer
> click de carta. El que resuelva primero cancela al otro.
> 2026-09-23: guardado en un Dictionary, no en variables sueltas — un
> lambda de GDScript captura las locales por VALOR, así que
> "race_done = true" adentro del callback nunca se veía desde este
> bucle (ver misma causa raíz en arquitectura.md §13.17 y en
> CardInteractionModule.await_target_or_castillo_pick()). Un Dictionary
> sí se captura por referencia.

### `try_execute_convert_ally_to_gold_pattern` — línea 228

> Detecta 'puedes convertirlo en un Oro y moverlo a tu Oro Pagado'
> (Jormundgander, 2026-08-29, verificado contra la API — única
> reimpresión, sin discrepancias) — un Aliado en juego se transforma en
> Oro y se reubica directo en Oro Pagado. La otra mitad de esta misma
> carta ('si esta carta es un Oro, cuando lo pagues para jugar un
> Aliado, conviértela en un Aliado y muévela a tu Línea de Defensa') se
> resuelve del lado de GoldManager._mover_oro_a_pagado(), que revisa
> card.revert_to_data al pagar cualquier Oro — no hace falta detectarla
> aquí aparte.
> Returns: true si el patrón aplicaba.

### `try_execute_convert_ally_to_gold_pattern` — línea 243

> 2026-09-30, bug real reportado por el usuario: _executor._main acá es
> TriggerSystem (ver TargetedEffectExecutor.gd:441-445, mismo patrón de
> bug ya documentado en arquitectura.md §2), no el Main real del juego
> — _gold_manager/_card_interaction no existen ahí y tiraban "Invalid
> access to property or key". Mismo fix de indirección que ya usa
> try_execute_jabberwocky_convert_opponent_top_pattern() más abajo.

### `try_execute_convert_ally_to_gold_pattern` — línea 253

> 2026-09-13, a pedido del usuario: en vez de un modal de confirmación
> con un solo candidato, clickear la carta misma (ya está en juego,
> visible) confirma; ESC declina — mismo mecanismo que cualquier otro
> await_target(), sin necesidad de un panel aparte para un "sí/no" de
> una sola carta conocida de antemano.

### `try_execute_jabberwocky_convert_opponent_top_pattern` — línea 277

> 'Cuando entra en juego o ataca, convierte la primera carta del
> Castillo oponente en un Oro sin habilidad y ponlo en tu Oro Pagado'
> (Jabberwocky, 2026-09-30) — mismo mecanismo de conversión real a Oro
> que try_execute_no_allies_convert_castillo_top_pattern() (Biblioteca de
> Caballería, más abajo) y convert_ally_to_gold_in_pagado() (Jormundgander,
> arriba), pero sobre el tope del Castillo RIVAL y con destino Oro Pagado
> en vez de Línea de Defensa. La carta nunca llega a existir como Node
> con su habilidad real — 'tipo'/'habilidad' se pisan en los datos crudos
> ANTES de crear el Node (mismo criterio que new_data['tipo'] = ORO de
> la función hermana), así que 'sin habilidad' queda resuelto de forma
> más simple que silence_card() (pensada para una carta que YA existe en
> juego). Se registró también 'cuando entra en juego o ataca' (con
> 'ataca', no 'ataque') en Card.TRIGGER_KEYWORDS — el texto real de esta
> carta usa esa conjugación, distinta de la plantilla DAR estándar que
> ya cubrían esas listas.

### `try_execute_no_allies_convert_castillo_top_pattern` — línea 317

> 'En la Fase Final oponente, si no controlas Aliados o si en tu turno
> anterior un Aliado fue Anulado o su habilidad fue cancelada, Roba una
> carta y pon bajo tu control la primera carta de un Castillo como un
> Aliado de Fuerza 2 sin habilidad' (Biblioteca de Caballería, 2026-09-04).
>
> LIMITACIÓN CONOCIDA: solo se implementa la mitad 'si no controlas
> Aliados' de la condición. La otra mitad ('en tu turno anterior un Aliado
> fue Anulado o su habilidad fue cancelada') exigiría un historial de
> eventos por turno que el motor no tiene todavía — no hay ningún registro
> de 'a este jugador le anularon/cancelaron un Aliado el turno pasado' en
> ninguna parte del código. Mientras no exista, esa rama del 'o' nunca se
> evalúa como verdadera; el efecto solo dispara con el campo propio vacío
> de Aliados.
>
> Reusa el mecanismo de conversión real de try_execute_mill_convert_to_
> ally_pattern (Sherlock Holmes): is_converted + KeywordManager.
> silence_card + Fuerza fijada por modificador CONTINUO (LAYER_7A_CHAR_
> SETTING, 'set'), no un token de datos en blanco.

### `try_execute_no_allies_convert_castillo_top_pattern` — línea 359

> Sin ventana genérica aquí (2026-09-09): silence_card() (más abajo) ya
> consulta Prevención adentro por su cuenta.

### `try_execute_banish_top_by_ally_count_and_draw_pattern` — línea 399

> Detecta 'Destierra N cartas del tope de un Castillo y Roba una
> carta' (Espada del Juicio — dispara tanto en 'Cuando entra en juego'
> como 'en tu Agrupación'). Cantidad FIJA, parseada del texto (2026-09-06,
> a pedido del usuario: la carta real dice 'tantas cartas... como
> Aliados controles' — cantidad dinámica —, pero se simplificó a un
> número fijo para esta partida; ver [[feedback_api_is_source_of_truth]]
> para el texto real si se revierte este cambio). 'un Castillo' sin
> posesivo = a elección (mismo criterio ya confirmado para 'un
> Cementerio' de Miguel). El 'Roba una carta' es independiente y
> siempre ocurre.
> Returns: true si el patrón aplicaba.

### `try_execute_banish_top_by_ally_count_and_draw_pattern` — línea 428

> 2026-10-07 (ver arquitectura.md §40): await_castillo_pick() ya
> tiene puente de red — antes esto se saltaba entero para el
> Remoto (controller_id == 0 fijo), asumiendo su propio Castillo
> sin preguntar en vez de ofrecerle la elección real.

### `try_execute_opponent_discard_and_draw_pattern` — línea 452

> Detecta 'tu oponente Descarta N cartas y tú Robas [hasta] M cartas'
> (2026-08-29, p.ej. Miguel) — dos acciones en una sola oración que
> extract_action() no puede encadenar (solo reconoce UNA acción por
> texto, la primera que matchea). Reusa _execute_targeted_discard() tal
> cual (ya resuelve 'oponente' y le da a elegir al jugador humano si es
> su propia mano la que descarta) seguido de un robo directo.
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

### `try_execute_name_a_card_pattern` — línea 486

> Detecta 'nombra una carta para que pierda(n) su habilidad en todas
> las Zonas mientras esta carta esté en juego' (2026-08-29, Alicia en
> Wonderland). Distinto de un silencio puntual (KeywordManager.
> silence_card(), que apunta a UNA carta ya en juego): aquí se nombra un
> NOMBRE, y afecta cualquier copia de ese nombre en cualquier zona, esté
> ya en juego o aparezca después (mazo, mano) — KeywordManager.
> lock_ability_by_name()/is_name_locked(), consultado desde is_silenced().
> Solo cubre esta variante concreta (silenciar por nombre); el 'nombra una
> carta' de Tesoro de los Césares es un efecto DISTINTO (sube el coste,
> no silencia) y es una habilidad ACTIVADA, no pasa por aquí.
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

## `scripts/core/effects/triggers/DSR_CemeteryBanishDraw.gd`

### `(nivel de archivo)` — línea 2

> DSR_CemeteryBanishDraw — Slice de DrawShuffleResolver.gd: patrones que
> operan sobre uno o ambos Cementerios (Destierro, Barajado de vuelta al
> Castillo, o subida a la mano), a veces encadenados con un Robo de cartas
> (aku aku, Espada de O'Higgins, Campanita, Tamales, Quantum Megumi, Hanta
> el Samurai, Mariano Osorio). Uno de 4 hermanos separados de
> DrawShuffleResolver.gd (2026-09-06, "módulos gordos") — ver también
> DSR_ShuffleDrawCombos.gd, DSR_SearchGoldCombos.gd y
> DSR_DiscardChoicePatterns.gd. Opera sobre TriggerSystem via
> _executor._main (mismo Node que TargetedEffectExecutor._main — ver ese
> archivo). DrawShuffleResolver.gd queda como FACADE — cada función de este
> archivo es llamada por un reenvío de una sola línea desde ahí, con el
> mismo nombre y firma de siempre, así que TriggerResolution.gd (único
> llamador) no necesitó cambiar una sola línea por este split.

### `try_execute_banish_cemeteries_equal_to_own_strength_pattern` — línea 24

> 'Cuando hagas daño de combate, Destierra tantas cartas de los
> Cementerios como Fuerza tenga un Aliado' (aku aku, 2026-09-04) — 'un
> Aliado' sin más calificador se interpreta como la propia carta (la que
> hizo el daño), autoreferencial como el resto de disparadores 'cuando
> hagas/haga daño' de una sola carta. También cubre 'puedes Desterrar
> hasta tantas cartas de los Cementerios como Fuerza tenga este Aliado'
> (kaitai, En tu Fase Final — autoreferencial explícito con 'este').

### `try_execute_banish_cemeteries_equal_to_own_strength_pattern` — línea 43

> 2026-09-13, a pedido del usuario: click directo con ambos Cementerios
> visibles en vez del modal de lista viejo — pool combinado, sin lock
> (mismo caso que Espada de O'Higgins, arquitectura.md §10.14/§10.27).

### `try_execute_banish_cemeteries_equal_to_own_strength_pattern` — línea 61

> try_execute_banish_up_to_n_cemeteries_then_draw_pattern() ELIMINADA
> (2026-09-13, a pedido del usuario — "la habilidad del Bernardo O'Higgins
> no es esa, revísalo bien" llevó a revisar TODO lo tocado en la misma
> tanda). Detectaba "Destierra hasta N cartas de los Cementerios y Roba M
> cartas" (Espada de O'Higgins) con un regex ESTRICTO, pero
> TriggerResolution.gd prueba los patrones EN ORDEN y
> try_execute_banish_from_cemeteries_and_draw_pattern() (más abajo en este
> mismo archivo, chequeo SUELTO: solo "de los cementerios" + "destierra"
> en el texto) corre ANTES y matchea cualquier texto que la versión
> estricta también matchearía — así que esta función NUNCA se alcanzaba
> para NINGUNA carta posible, no solo para O'Higgins. La conversión a
> click-directo de esta función (§10.14) se aplicó código muerto; la
> conversión real que sí importa está en
> MiscTargetedPatterns._resolve_banish_from_both_cemeteries() (la que de
> verdad ejecuta try_execute_banish_from_cemeteries_and_draw_pattern()),
> convertida en la misma revisión — ver arquitectura.md §10.21.

### `try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern` — línea 80

> 'Puedes Barajar hasta cuatro cartas de los Cementerios o subir un
> Aliado o Tótem de tu Cementerio a tu mano' (Campanita, 2026-09-04) —
> elección A/B.

### `try_execute_shuffle_cemeteries_or_raise_ally_totem_pattern` — línea 91

> 2026-09-13, a pedido del usuario: la elección A/B en sí ('Barajar' vs
> 'Subir') sigue siendo un modal de dos botones (son dos EFECTOS
> distintos, no dos cartas — no es candidato al reemplazo por click, ver
> arquitectura.md §10.16). Lo que cambió es CÓMO se elige la carta
> DESPUÉS de esa decisión: ambas ramas ahora usan
> ZoneViewerModule.open_cemetery_target_picker() en vez del modal de
> lista viejo.

### `try_execute_shuffle_up_to_n_cemeteries_pattern` — línea 142

> 'Puedes Barajar hasta N cartas de los Cementerios' (2026-09-04, p.ej.
> Tamales: 'En tu Fase Final, puedes Barajar hasta tres cartas de los
> Cementerios') — sin Desterrar (a diferencia de Armería del Guerrero/
> Colmillo de Vampiro, que ofrecen Barajar Y/O Desterrar). 'Los
> Cementerios' = ambos jugadores ([[project_no_zone_means_in_play]]),
> 'puedes' = opcional, cancelar el picker = 0 elegidas.
> 'and not "desterrar" in lower' (2026-09-15, bug real reportado por el
> usuario: Capitán O'Brien — 'puedes Barajar y/o Desterrar tantas cartas
> de los Cementerios como Fuerza tenga este Aliado' — caía AQUÍ por error
> ('puedes barajar' es substring de esa frase), resolviendo solo Barajar
> 1 carta en vez de la elección real Barajar/Desterrar por hasta Fuerza
> cartas). Ver try_execute_shuffle_or_banish_cemeteries_equal_to_strength_
> pattern más abajo, que ahora cubre el texto real.

### `try_execute_shuffle_up_to_n_cemeteries_pattern` — línea 167

> 2026-09-13, a pedido del usuario: click directo con ambos Cementerios
> visibles en vez del modal de lista viejo.

### `try_execute_banish_up_to_n_cemeteries_pattern` — línea 187

> 'Puedes Desterrar hasta N cartas de los Cementerios' (2026-09-04,
> p.ej. Quantum Megumi: 'En tu Fase Final, puedes Desterrar hasta dos
> cartas de los Cementerios') — versión Desterrar (no Barajar) de
> try_execute_shuffle_up_to_n_cemeteries_pattern. 'Los Cementerios' =
> ambos jugadores ([[project_no_zone_means_in_play]]), 'puedes' =
> opcional, cancelar el picker = 0 elegidas. 'and not "barajar" in lower'
> (2026-09-15, mismo motivo que try_execute_shuffle_up_to_n_cemeteries_
> pattern — ver ese comentario): evita un falso-positivo simétrico si
> alguna carta real dice 'puedes Desterrar y/o Barajar...'.

### `try_execute_banish_up_to_n_cemeteries_pattern` — línea 208

> 2026-09-13, a pedido del usuario: click directo con ambos Cementerios
> visibles en vez del modal de lista viejo.

### `try_execute_shuffle_or_banish_cemeteries_equal_to_strength_pattern` — línea 226

> 'En tu Fase Final, puedes Barajar y/o Desterrar tantas cartas de los
> Cementerios como Fuerza tenga este Aliado' (Capitán O'Brien, 2026-09-15
> — bug real reportado por el usuario: sin patrón propio hasta ahora,
> caía por error en try_execute_shuffle_up_to_n_cemeteries_pattern
> de arriba — 'puedes barajar' es substring de esta frase — resolviendo
> solo Barajar 1 carta en vez de la elección real Barajar/Desterrar por
> carta, hasta tantas cartas como Fuerza efectiva tenga este Aliado).
> Cantidad DINÁMICA (a diferencia de Armería del Guerrero/Belta/Uriel/
> Torre de Babel, que son un número fijo) — reusa GoldManager.
> _resolve_armeria_barajar_desterrar() con el amount calculado, mismo
> criterio que esos llamadores: la ventana de respuesta se abre ANTES de
> arrancar toda la resolución (el helper compartido resuelve elección
> intercalada carta-por-carta sin un punto limpio de 'declarar todo
> antes de ejecutar', ver el comentario del propio helper en
> GoldManager.gd).

### `try_execute_banish_from_cemeteries_and_draw_pattern` — línea 261

> Detecta 'Destierra hasta N cartas de los Cementerios y Roba M
> cartas' (2026-08-30, Espada de O'Higgins — primera carta con trigger
> 'en tu Fase Final' que realmente resuelve algo). 'los Cementerios' en
> plural sin posesivo = AMBOS Cementerios en un solo pool combinado
> (mismo criterio ya confirmado por el usuario para 'un Cementerio' de
> Miguel: sin posesivo = cualquiera de los dos). Sin 'Luego' entre las
> dos partes (misma oración unida por 'y', no oraciones separadas por
> punto), así que Robar sucede siempre, sin importar cuántas cartas se
> hayan elegido Desterrar (incluso cero).
> Returns: true si el patrón aplicaba.

### `try_execute_weapon_count_banish_cemetery_pattern` — línea 295

> Detecta 'En tu Fase Final, Destierra hasta tantas cartas de un
> Cementerio como Armas controles, más uno' (Hanta el Samurai,
> 2026-09-02 — bug reportado por el usuario: sin patrón propio, esta
> habilidad caía al extractor genérico de UniversalCardParser, que no
> entiende una cantidad DINÁMICA 'tantas...como...' ni 'de un
> Cementerio' en esta forma exacta, y terminaba desterrando cartas EN
> JUEGO — se llevó puesta la Espada de O'Higgins equipada, con su bono
> de Fuerza y todo). 'Un Cementerio' sin posesivo = eliges CUÁL de los
> dos (mismo criterio ya confirmado con Miguel — ver
> [[project_y_o_means_choose_one_zone]]), NO es un pool combinado como
> 'los Cementerios' de Espada de O'Higgins (plural). La cantidad es
> dinámica: Armas equipadas en cualquiera de los Aliados en juego del
> controlador, más uno.
> Returns: true si el patrón aplicaba.

### `try_execute_weapon_count_banish_cemetery_pattern` — línea 335

> 2026-09-13, a pedido del usuario: ver ambos Cementerios lado a lado y
> elegir con click directo, en vez de preguntar primero 'de cuál
> Cementerio' con un modal — 'un Cementerio' (sin posesivo, singular) en
> el texto real sigue significando UN SOLO Cementerio para toda esta
> habilidad, no un pool combinado (a diferencia de Espada de O'Higgins,
> 'los Cementerios' en plural) — lock_to_one_side=true lo hace cumplir:
> tras el primer click, el otro Cementerio deja de ser elegible.

### `try_execute_vigilia_or_final_banish_opponent_cemetery_pattern` — línea 362

> Detecta 'En tu Vigilia o Fase Final, Destierra hasta tres cartas
> del Cementerio oponente' (Mariano Osorio, custom_mig_14, 2026-09-03 —
> carta custom, sin myl_id real, no está en la API externa, el cache
> local es la única fuente). Dispara en AMBOS momentos por turno
> (Vigilia Y Fase Final, no 'una vez por turno' combinado) — cada vez
> que TriggerSystem.resolve_vigilia_triggers()/resolve_turn_end_
> triggers() llega hasta aquí, el mismo texto completo se revisa de
> nuevo, así que el patrón matchea las dos veces por diseño. 'Cementerio
> oponente' con posesivo explícito = siempre el del rival, sin elección
> de zona.
> Returns: true si el patrón aplicaba.

### `try_execute_vigilia_or_final_banish_opponent_cemetery_pattern` — línea 384

> 2026-09-13, a pedido del usuario: click directo en el Cementerio rival
> en vez del modal de lista viejo.

## `scripts/core/effects/triggers/DSR_DiscardChoicePatterns.gd`

### `(nivel de archivo)` — línea 2

> DSR_DiscardChoicePatterns — Slice de DrawShuffleResolver.gd: patrones de
> descarte compuesto y dispatchers de elección A/B (Tempilcahue, Golpe
> Solar, Escamas de Dragón). Uno de 4 hermanos separados de
> DrawShuffleResolver.gd (2026-09-06, "módulos gordos") — ver también
> DSR_ShuffleDrawCombos.gd, DSR_CemeteryBanishDraw.gd y
> DSR_SearchGoldCombos.gd. Opera sobre TriggerSystem via _executor._main
> (mismo Node que TargetedEffectExecutor._main — ver ese archivo).
> DrawShuffleResolver.gd queda como FACADE — cada función de este archivo es
> llamada por un reenvío de una sola línea desde ahí, con el mismo nombre y
> firma de siempre, así que TriggerResolution.gd (único llamador) no
> necesitó cambiar una sola línea por este split.

### `try_execute_tempilcahue_choice_pattern` — línea 24

> 'Cuando lo juegues, Destiérralo. Elige un efecto:
> - Busca una carta en tu Castillo, ponla en tu mano y Roba una carta. No
> puedes jugar más cartas este turno.
> - Paga dos Oros para Barajar cartas cuyos costes sumen hasta 4 y Robar
> dos cartas.' (Tempilcahue, 2026-08-30) — Talismán, se resuelve directo
> vía TriggerSystem.resolve_talisman(). El autodestierro ya lo maneja
> GoldManager._play_talisman() genérico (self_exile detecta 'destierr'
> en el texto completo de la carta) — aquí solo se resuelve la elección
> entre las dos ramas. 'Barajar cartas cuyos costes sumen...' sin 'de tu
> mano' = cartas EN JUEGO de cualquier lado (ver
> [[project_no_zone_means_in_play]]), no de la mano — a diferencia de
> try_execute_shuffle_hand_and_draw_plus_two_pattern() (Aaru), cuyo texto
> SÍ dice 'de tu mano' explícito.

### `try_execute_tempilcahue_choice_pattern` — línea 44

> Los botones muestran el texto EXACTO de cada opción de la carta
> (2026-10-12, a pedido del usuario: el texto del botón no coincidía con
> la carta); si no se encuentra, quedan los resúmenes de siempre.

### `try_execute_tempilcahue_choice_pattern` — línea 64

> 2026-10-14, a pedido del usuario: sin popup. Si no puede pagar los dos
> Oros (o no hay nada que barajar), busca directo. Si puede, brillan su
> Castillo (buscar) y las cartas en juego que se pueden barajar; la
> primera carta elegida ya cuenta para la suma de 4.

### `try_execute_tempilcahue_choice_pattern` — línea 80

> Sin ventana genérica aquí (2026-09-09): Tempilcahue es un Talismán —
> TriggerSystem.resolve_talisman() ya abrió UNA ventana para toda la
> carta antes de llegar hasta aquí (Pila de Respuesta Universal).

### `try_execute_tempilcahue_choice_pattern` — línea 90

> 2026-09-13, a pedido del usuario: click directo sobre las cartas
> reales en juego (ya son Nodos visibles, sin necesidad de popup) en
> vez del modal viejo que reintentaba toda la selección si te pasabas
> del presupuesto. Aquí el presupuesto se hace cumplir EN EL MOMENTO:
> dynamic_filter apaga el brillo de cualquier carta que haría superar
> la suma de 4 con lo ya elegido, en vez de dejar elegir de más y
> rechazar solo al final.

### `try_execute_tempilcahue_choice_pattern` — línea 109

> Sin ventana genérica aquí (2026-09-09): return_to_deck() (dentro del
> loop) ya consulta Prevención adentro por cada carta.

### `try_execute_shuffle_ally_or_search_castle_pattern` — línea 129

> 'Puedes Barajar un Aliado de Fuerza N o menos o buscar una carta en tu
> Castillo y ponerla en tu mano' (Sombrerero Loco, 2026-10-14). Sin popup:
> brillan los Aliados que se pueden barajar (de los dos lados, sin zona =
> en juego) y tu Castillo; al elegir uno, lo otro se apaga. ESC = no hacer
> nada (es opcional).

### `try_execute_shuffle_ally_or_search_castle_pattern` — línea 152

> Bot (2026-10-18, bug real: la elección aparecía en la pantalla del
> Anfitrión): busca en su Castillo, sin preguntar.

### `try_execute_golpe_solar_pattern` — línea 180

> 'Cuando juegues esta carta, Destiérralo. Descarta hasta dos cartas y
> juega un Aliado de tu mano o Cementerio reduciendo su coste en tantos
> Oros como cartas hayas Descartado, hasta un mínimo de 0. Baraja hasta
> una carta oponente de coste 2 o menos.' (Golpe Solar, 2026-08-31,
> confirmado contra la API — Ángeles y Demonios: Vigilantes / su Mazo
> Dragón / Kaiju vs Mecha: Titanes, mismo texto en las tres). Talismán,
> se resuelve directo vía TriggerSystem.resolve_talisman(). El
> autodestierro ya lo maneja GoldManager._play_talisman() genérico
> (self_exile detecta 'destierr' en el texto completo de la carta) — aquí
> solo se resuelve el efecto en sí, en el orden impreso.
>
> El descuento de coste reusa el mismo molde que
> TargetedEffectExecutor._execute_play_weapon_discount_draw() (Lobo
> Sagrado): calcular con un modificador temporal, sacarlo enseguida, y
> pagar el número fijo resultante a mano — pero para un Aliado (sin
> elegir portador) en vez de un Arma.
>
> 'Baraja... una carta oponente...' sin 'de tu mano'/'de tu Castillo' =
> carta EN JUEGO (ver [[project_no_zone_means_in_play]]), mismo criterio
> y candidatos que Espada Vikinga
> (try_execute_draw_and_shuffle_opponent_card_pattern), pero con umbral
> de coste fijo (2) en vez de por cantidad de Aliados, y OPCIONAL ('hasta
> una', no 'una') — se puede declinar con ESC (await_target).
>
> Reordenado (2026-09-09, Pila de Respuesta Universal — ver docs/plans/
> 2026-09-09-pila-respuesta-universal-design.md, caso de estudio original
> del usuario): las 3 elecciones del texto (qué descartar, qué Aliado
> jugar, qué carta rival barajar) se DECLARAN primero, sin tocar nada
> todavía — solo con las 3 ya decididas se abre UNA sola ventana de
> respuesta real, y solo si nadie anula/cancela se ejecutan las 3 partes,
> en el orden impreso. Antes se elegía y ejecutaba de a una, sin ninguna
> ventana real entremedio.

### `try_execute_golpe_solar_pattern` — línea 223

> 2026-10-17, a pedido del usuario: el objetivo a Barajar se elige PRIMERO
> (N para no barajar ninguna), luego el descarte y el Aliado. Se resuelve
> igual en el orden impreso.
> --- Declarar "Baraja hasta una carta oponente de coste 2 o menos" ---

### `try_execute_golpe_solar_pattern` — línea 231

> Sin Oros (confirmado por el usuario 2026-10-14: Golpe Solar no
> puede barajar Oros).

### `try_execute_golpe_solar_pattern` — línea 254

> --- Declarar "Descarta hasta dos cartas" (0-2, elección del jugador) ---
> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo.

### `try_execute_golpe_solar_pattern` — línea 265

> --- Declarar "juega un Aliado de tu mano o Cementerio" con ese descuento ---
> Un Aliado recién descartado por ESTE mismo efecto no puede ser el
> elegido aquí (2026-08-31, a pedido del usuario): _discard() lo manda
> directo al Cementerio, así que sin esta exclusión aparecía como
> candidata de 'Cementerio' en la misma resolución que lo descartó.

### `try_execute_golpe_solar_pattern` — línea 286

> 2026-09-13, a pedido del usuario: click directo — mano (Nodos ya
> visibles) + un popup liviano con el Cementerio propio (mismo
> patrón que Sake, arquitectura.md §10.23) — en vez del modal de
> lista viejo combinando ambas zonas.

### `try_execute_golpe_solar_pattern` — línea 320

> Sin ventana genérica aquí (2026-09-09): Golpe Solar es un Talismán —
> TriggerSystem.resolve_talisman() ya abrió UNA ventana para toda la
> carta antes de siquiera llegar a este patrón (si hubiera anulado/
> cancelado ahí, esta función ni se habría llamado — el "declarar todo
> primero" de arriba sigue siendo correcto, solo cambió DÓNDE se
> pregunta, no el orden de las partes).
> ============ RESOLVER, en el orden impreso ============

### `try_execute_each_player_discard_then_draw_pattern` — línea 363

> 'Cada jugador Bota N carta(s) y tú Robas M carta(s)' (2026-09-04,
> p.ej. Escamas de Dragón: 'cada jugador Bota tres cartas y tú Robas una
> carta') — mandatorio, sin 'puedes'. Cada jugador Bota del tope de su
> Castillo (no de la mano).

### `try_execute_each_player_discard_then_draw_pattern` — línea 384

> "Bota" = las cartas del tope del Castillo al Cementerio, NO descartar de
> la mano (2026-10-18, bug real reportado por el usuario: Escamas de
> Dragón pedía descartar tres cartas de la mano).

## `scripts/core/effects/triggers/DSR_SearchGoldCombos.gd`

### `(nivel de archivo)` — línea 2

> DSR_SearchGoldCombos — Slice de DrawShuffleResolver.gd: patrones que
> combinan buscar/subir una carta (del Castillo, la mano o el Cementerio) o
> generar Oro Virtual restringido, con un Robo u otro efecto secundario
> (Legión Paladín, Levisterio, La Ouija, Shiji). Uno de 4 hermanos separados
> de DrawShuffleResolver.gd (2026-09-06, "módulos gordos") — ver también
> DSR_ShuffleDrawCombos.gd, DSR_CemeteryBanishDraw.gd y
> DSR_DiscardChoicePatterns.gd. Opera sobre TriggerSystem via
> _executor._main (mismo Node que TargetedEffectExecutor._main — ver ese
> archivo). DrawShuffleResolver.gd queda como FACADE — cada función de este
> archivo es llamada por un reenvío de una sola línea desde ahí, con el
> mismo nombre y firma de siempre, así que TriggerResolution.gd (único
> llamador) no necesitó cambiar una sola línea por este split.

### `try_execute_free_play_weapon_or_totem_cost1_hand_cemetery_pattern` — línea 69

> 2026-09-14, a pedido del usuario: click directo — mano (Nodos ya
> visibles) + un popup liviano con el Cementerio propio (mismo patrón
> que Golpe Solar, ver DSR_DiscardChoicePatterns.gd), en vez del modal
> de lista viejo combinando ambas zonas.

### `try_execute_draw_gold_search_pattern` — línea 109

> Detecta 'Roba N carta(s), genera un Oro para jugar Aliados o Armas de
> coste X o más y sube hasta M carta(s) de tu Cementerio a tu mano' (Legión
> Paladín — 2026-08-29: texto reconfirmado en vivo contra la API, que
> resultó ser INESTABLE entre fetches para esta carta específica; esta es
> la versión que la API acaba de devolver, la misma que ya se había
> usado en una implementación anterior de este mismo desarrollo. Ver
> [[feedback_api_is_source_of_truth]] — se sincronizó también el cache
> local (user://card_cache/cards.json, id 20857) a este texto). Tres
> efectos encadenados SIN 'puedes' (no son opcionales, y el trigger es
> SOLO 'cuando entra en juego' — no incluye salir del juego). Se detecta
> por texto y se ejecutan los tres en orden.
> Returns: true si el patrón aplicaba.

### `try_execute_draw_gold_search_pattern` — línea 154

> 2026-10-06 (ver arquitectura.md §33): generar_oro_virtual_restringido()
> y _resolve_search_cemetery_to_hand() ya son por jugador — el guard
> 'controller_id == 0' de 2026-09-11 (bug real: el Oro restringido del
> rival aparecía del lado del Anfitrión) ya no hace falta.

### `try_execute_draw_reveal_talisman_gold_pattern` — línea 172

> Detecta 'Roba una carta y puedes mostrar tu mano. Si no tienes más de
> un Talismán, genera un Oro para jugar Armas y Roba una carta adicional'
> (Levisterio, 2026-08-31). El 'mostrar tu mano' es cómo el jugador
> demuestra que cumple la condición del Talismán — no hay sistema de
> revelado-verificable de mano en este motor (SelectionCanvas.
> reveal_hand_cards() existe pero está huérfana/sin instanciar, ver
> arquitectura.md), así que se resuelve leyendo la mano directamente y
> dejando constancia en el log en vez de abrir una UI de revelado nueva
> para un único caso. El bonus condicional solo se evalúa para
> controller_id == 0 (mismo alcance ya usado por search_amount en
> try_execute_draw_gold_search_pattern) — no hay mano de IA modelada
> carta por carta para poder contar sus Talismanes.
> Returns: true si el patrón aplicaba.

### `try_execute_draw_reveal_talisman_gold_pattern` — línea 201

> 2026-10-06 (ver arquitectura.md §33): generar_oro_virtual_restringido()
> ya es por jugador — el guard 'controller_id == 0' de arriba ya no hace
> falta; la mano a contar es la del jugador real que activó la carta.

### `try_execute_deck_top_or_bottom_to_hand_pattern` — línea 225

> Detecta 'pon la primera o la última carta de tu Castillo en tu mano'
> (La Ouija, 2026-08-31 — carta promocional de 'IMP - Chile Oscuro 2', sin
> myl_id real, no está en la API externa; ver nota de fuente en
> _activate_ouija_play_from_cemetery_or_deck_top(), HandCementerioAbilityHandler.gd).
> Sin 'puedes': mandatorio, pero con una elección real entre las dos
> cartas (no 'la que sea al azar'). 'primera' = tope (índice 0, ver
> convención real documentada en CardManager.add_to_deck_top()), 'última'
> = fondo.
> Returns: true si el patrón aplicaba.

### `try_execute_deck_top_or_bottom_to_hand_pattern` — línea 246

> El revelado del tope (segunda mitad del texto de La Ouija: 'Juega
> mostrando la primera carta de tu Castillo') arranca DESDE EL PRIMER
> SEGUNDO que entra en juego (2026-08-31, corrección a pedido del
> usuario: antes esto solo se aplicaba a la habilidad de una vez por
> turno) — refrescar AQUÍ, antes de ofrecer la elección tope/fondo, para
> que el jugador ya sepa cuál es la del tope al decidir (la de fondo
> sigue a ciegas). La carta ya es hija de player_gold con zona
> RESERVA_ORO en este punto (_trigger_enter_play() se llama después de
> _place_card_as_gold() la deja en su lugar), así que la detección por
> texto en refresh_castillo_top_reveal() ya la encuentra.

## `scripts/core/effects/triggers/DSR_ShuffleDrawCombos.gd`

### `(nivel de archivo)` — línea 2

> DSR_ShuffleDrawCombos — Slice de DrawShuffleResolver.gd: patrones compuestos
> "baraja... y roba..." / "roba... y baraja..." que combinan barajar cartas
> (de la mano, del Destierro, o una carta oponente en juego) con un robo de
> cartas en la misma oración (El Rey y el Verdugo, Aaru, Manuel Bulnes,
> Espada Vikinga, Trono del Dragón). Uno de 4 hermanos separados de
> DrawShuffleResolver.gd (2026-09-06, "módulos gordos") — ver también
> DSR_CemeteryBanishDraw.gd, DSR_SearchGoldCombos.gd y
> DSR_DiscardChoicePatterns.gd. Opera sobre TriggerSystem via
> _executor._main (mismo Node que TargetedEffectExecutor._main — ver ese
> archivo). DrawShuffleResolver.gd queda como FACADE — cada función de este
> archivo es llamada por un reenvío de una sola línea desde ahí, con el
> mismo nombre y firma de siempre, así que TriggerResolution.gd (único
> llamador) no necesitó cambiar una sola línea por este split.

### `try_execute_shuffle_exile_and_draw_pattern` — línea 28

> Detecta 'Baraja todas las X de tu Destierro y Roba N carta(s)'
> (2026-08-29, p.ej. El Rey y el Verdugo: '...todas las Armas de tu
> Destierro...') — mueve del Destierro de vuelta al Castillo las cartas
> que cumplan el tipo, baraja, y roba. Sin 'puedes': mandatorio.
> Returns: true si el patrón aplicaba.

### `try_execute_shuffle_exile_and_draw_pattern` — línea 64

> 2026-09-30, mismo criterio que el fix de Azi Sruvara: sin esto no
> había ninguna retroalimentación visual del barajado.

### `try_execute_shuffle_hand_and_draw_plus_two_pattern` — línea 82

> Detecta 'Baraja cualquier cantidad de cartas de tu mano en tu
> Castillo. Luego, pon la misma cantidad de cartas de la parte superior
> de tu Castillo en tu mano más dos cartas' (2026-08-30, Aaru — Talismán,
> se resuelve directo al jugarse vía TriggerSystem.resolve_talisman(), no
> dispara). Sin 'puedes': mandatorio, pero 'cualquier cantidad' incluye
> 0 como resolución COMPLETA (no parcial) — el 'Luego' siempre corre,
> sin importar cuántas cartas se hayan barajado (incluso ninguna).
> Returns: true si el patrón aplicaba.

### `try_execute_shuffle_hand_and_draw_plus_two_pattern` — línea 100

> 2026-09-30, bug real expuesto al convertir esto a la Fase 3: 'main.
> player_hand' hardcodeado sin mirar controller_id — para el jugador 1
> (bot/Remoto) había que usar _opponent_fan en su lugar.

### `try_execute_shuffle_hand_and_draw_plus_two_pattern` — línea 107

> 2026-09-13, a pedido del usuario: click directo en la mano en vez
> del modal de lista viejo.

### `try_execute_draw_and_shuffle_hand_pattern` — línea 128

> Detecta 'Roba N carta(s) y Baraja M carta(s) de tu mano en tu
> Castillo' (2026-08-30, p.ej. Manuel Bulnes: 'Cuando entra en juego,
> Roba una carta y Baraja una carta de tu mano en tu Castillo') — dos
> acciones encadenadas con 'y' que extract_action() no puede resolver
> juntas (solo reconoce UNA acción, la primera que matchea). El jugador
> elige QUÉ carta(s) barajar de la mano. Sin 'puedes': mandatorio en las
> dos partes, en el orden impreso (roba primero, después baraja).
> Returns: true si el patrón aplicaba.

### `try_execute_draw_and_shuffle_hand_pattern` — línea 158

> 2026-09-30, mismo bug que Aaru más arriba: hardcodeado a player_hand
> sin mirar controller_id.

### `try_execute_draw_and_shuffle_hand_pattern` — línea 164

> 2026-09-13, a pedido del usuario: click directo en la mano en
> vez del modal de lista viejo. Mandatorio (sin "puedes"): se
> pide sin ESC ("cancellable=false", mismo criterio que
> _select_hand_cards_for_discard(), §10.29) — no debería poder
> esquivarse un barajado mandatorio de la mano.

### `try_execute_draw_and_shuffle_opponent_card_pattern` — línea 188

> Detecta 'Roba N carta(s) y Baraja una carta oponente de coste igual
> o menor a la cantidad de Aliados que controles' (2026-08-30, p.ej.
> Espada Vikinga). El texto NO dice 'de tu mano' ni 'de tu Castillo' —
> regla general confirmada por el usuario (2026-08-30): si un efecto de
> 'barajar'/'destierra'/etc. no menciona una zona explícita, sucede sobre
> una carta EN JUEGO, no en la mano (mismo criterio ya corregido antes
> para 'Barajar una carta que no sea Oro' de Espada de O'Higgins). Como
> las cartas en juego son información PÚBLICA (a diferencia de una mano
> oculta), el jugador humano elige con clic en vez de al azar.
> A diferencia del resto de la familia 'y' de esta sesión (Manuel
> Bulnes, Aaru — ambas partes ocurren siempre), aquí el orden LÓGICO real
> es al revés del orden impreso: el 'Barajar' es la parte que puede
> fallar (si el rival no controla ninguna carta de ese coste o menos), y
> si falla, el 'Robar' NO se ejecuta — regla confirmada explícitamente
> por el usuario (2026-08-30), mismo espíritu que 'Luego' (DAR: el
> siguiente efecto solo corre si el anterior resolvió al 100%) aunque el
> texto una las dos partes con 'y'.
> Returns: true si el patrón aplicaba.

### `try_execute_draw_and_shuffle_opponent_card_pattern` — línea 229

> Reserva de Oro / Oro Pagado quedan FUERA (2026-08-30, a pedido del
> usuario): un Oro ahí "es Oro" nomás, no tiene un coste comparable
> para este tipo de filtro — solo cuenta si por algún efecto raro
> terminara en Línea de Defensa/Ataque/Apoyo, donde sí valdría 0.

### `try_execute_draw_and_shuffle_opponent_card_pattern` — línea 253

> 'Barajar' no encuentra objetivo válido — 'Robar' NO corre (regla
> del usuario, 2026-08-30).

### `try_execute_draw_and_shuffle_opponent_card_pattern` — línea 269

> Sin ventana genérica aquí (2026-09-09): return_to_deck() ya consulta
> Prevención adentro por su cuenta.

### `try_execute_shuffle_hand_then_draw_pattern` — línea 282

> Detecta 'Baraja N carta(s) de tu mano y Roba M carta(s)' (2026-09-03,
> p.ej. Trono del Dragón: 'Cuando entra en juego, Baraja dos cartas de tu
> mano y Roba tres cartas') — orden INVERSO al ya existente try_execute_
> draw_and_shuffle_hand_pattern() (Manuel Bulnes: 'Roba... y Baraja... de
> tu mano EN TU CASTILLO', roba primero) — aquí el texto imprime Barajar
> primero, así que se resuelve en ese orden (el jugador elige QUÉ cartas
> barajar antes de robar; DAR: sin 'puedes', mandatorio en las dos
> partes). Gate distinto ('de tu mano y roba', sin 'en tu castillo') para
> no colisionar con el patrón de Manuel Bulnes.
> Returns: true si el patrón aplicaba.

### `try_execute_shuffle_hand_then_draw_pattern` — línea 311

> 2026-09-30, mismo bug que Aaru/Manuel Bulnes más arriba: hardcodeado
> a player_hand sin mirar controller_id.

### `try_execute_shuffle_hand_then_draw_pattern` — línea 317

> 2026-09-13, a pedido del usuario: click directo en la mano en
> vez del modal de lista viejo. Mandatorio, sin ESC (§10.29).

## `scripts/core/effects/triggers/DagonPatterns.gd`

### `(nivel de archivo)` — línea 2

> Padre Dagón (2026-10-17, a pedido del usuario): dos habilidades en un solo
> texto, como Bernardo O'Higgins, que comparten el "Una vez por turno":
> - Activada (tu turno o Guerra de Talismanes), global, sin objetivo: "las
> cartas oponentes que no sean Oro pierden su habilidad y son
> Destruidas". Primero pierden la habilidad, así que lo que dirían al
> salir del juego no ocurre.
> - Prevención (EffectController._prevention_registry, "Padre Dagón"):
> "prevén que uno o más Aliados sean afectados por un efecto oponente",
> como Estaca o Cañón Helios.
> Se usa con preload.

### `try_execute` — línea 62

> 0) Antes de que pase nada (2026-10-17, a pedido del usuario): el
> oponente puede prevenir que cada carta sea afectada (Estaca, Cañón
> Helios...) — la que se previene no pierde su habilidad ni es Destruida.

## `scripts/core/effects/triggers/Deck170Patterns.gd`

### `(nivel de archivo)` — línea 2

> Deck170Patterns — efectos que faltaban del mazo 170 (Talisman - Control),
> 2026-10-14, ver docs/revision-mazo-170.md. Cada patrón reconoce su propio
> texto; try_execute() los prueba en orden. Se usa con preload (ver §54).

### `on_vigilia_started` — línea 134

> Texto claro (2026-10-17, a pedido del usuario: se confundía con
> lo que estaba jugando el oponente en ese momento).

### `on_vigilia_started` — línea 141

> 2026-10-17, bug real reportado por el usuario: antes se bloqueaba el
> próximo turno y se sacaba la carta de la mano ANTES de ponerla en
> juego — si eso fallaba, la Escarapela desaparecía y el bloqueo
> quedaba igual. Ahora solo si de verdad entró en juego; si no, la
> carta sigue en la mano.

### `on_card_left_play` — línea 195

> 2026-10-17, a pedido del usuario: al inspeccionarla, la carta
> muestra su texto original y las habilidades ganadas se apilan a
> la derecha (CardInspectionLayer._build_gained_abilities_panel()).

### `_play_annulled_under_control` — línea 487

> Envidia (2026-10-14): espera a que la carta Anulada llegue al
> Cementerio de su dueño y la juega bajo tu control sin pagar su coste
> (sigue siendo de su dueño). Si es un Talismán, elige objetivos de nuevo
> al resolverse.

## `scripts/core/effects/triggers/DrawShuffleResolver.gd`

### `(nivel de archivo)` — línea 2

> DrawShuffleResolver — Facade de Familia de patrones compuestos "roba N /
> baraja M / busca..." que combinan más de una acción en una sola oración
> (El Rey y el Verdugo, Aaru, Tempilcahue, Manuel Bulnes, Espada Vikinga,
> Legión Paladín, Espada de O'Higgins). Cada uno detecta su propio texto por
> regex y resuelve las acciones encadenadas que extract_action() no puede
> manejar solo (esa función reconoce UNA acción por texto, la primera que
> matchea). Opera sobre TriggerSystem via _executor._main (mismo Node que
> TargetedEffectExecutor._main — ver ese archivo).
> Extraído de TargetedEffectExecutor.gd (2026-08-30, "módulos gordos" —
> mismo corte que ya separó LookAndPlayResolver.gd).
>
> Dividido en 4 archivos por tamaño (2026-09-06, "módulos gordos"):
> DSR_ShuffleDrawCombos.gd (shuffle+draw), DSR_CemeteryBanishDraw.gd
> (Cementerio-destierro/barajado + draw), DSR_SearchGoldCombos.gd
> (buscar/subir carta + Oro Virtual) y DSR_DiscardChoicePatterns.gd
> (descarte compuesto / dispatchers de elección A-B). Este archivo queda
> como FACADE — cada función de abajo es un reenvío de una sola línea a la
> mitad que corresponda, con el mismo nombre y firma de siempre, así que
> TriggerResolution.gd (único llamador, vía
> `_main._draw_shuffle_resolver.try_execute_X(...)`) no necesitó cambiar
> una sola línea por este split.

## `scripts/core/effects/triggers/EffectController.gd`

### `(nivel de archivo)` — línea 2

> EffectController - Procesa efectos de cartas sobre el mazo
> Implementa validación "En medida de lo posible" (DAR - regla general)
>
> ESTADO REAL (2026-08-17, ver docs/audit-2026-08-13.html hallazgo 2 y 4):
> Casi todo aquí abajo está gateado por _validate_board(), que depende de
> `game_board` (poblado solo por GameBoard.gd — código huérfano de un layout
> de tablero anterior, nunca adjunto a ningún nodo de la escena actual).
> Con fallback hacia CardManager (que SÍ está vivo y sincronizado con Main):
> draw_cards(), mill_cards(), destroy_card(), exile_card()
> search_cards()/discard_cards()/return_to_deck()/return_to_hand()/
> shuffle_deck()/convert_card_type() y todo lo que colgaba exclusivamente de
> ellas se ELIMINARON (2026-08-17): auditadas función por función, cero
> llamadores en todo el proyecto — implementaciones duplicadas y abandonadas
> de lo que ActionModule.gd (el camino real: TriggerSystem →
> UniversalCardParser → ActionModule) ya hace de verdad. Antes de añadir un
> efecto nuevo, aplicarle a game_board el mismo tratamiento que draw_cards/
> mill_cards/destroy_card/exile_card (fallback a CardManager) en vez de
> asumir que va a aparecer solo — pero solo si algo realmente lo va a llamar.

### `draw_cards` — línea 96

> El GameBoard legacy no está activo en la escena actual (ver
> docs/audit-2026-08-13.html, hallazgo 2) — usar el camino real del
> juego en su lugar en vez de fallar en silencio.

### `_draw_cards_fallback` — línea 177

> search_cards()/_card_matches_filter() eliminados (2026-08-17): cero
> llamadores en todo el proyecto — ActionModule.search() es la búsqueda real.
> =============================================================================
> 3. BOTAR CARTAS - MILL (DAR Sección 8 - Botar)
> =============================================================================

### `_mill_cards_fallback` — línea 287

> Una línea con los nombres (2026-10-17, a pedido del usuario: el log
> del daño repetía 2 líneas por carta). El daño de combate lo resume
> BattleManager al final (log_it=false).

### `_mill_cards_fallback` — línea 300

> shuffle_deck()/discard_cards() eliminados (2026-08-17): cero llamadores
> en todo el proyecto. ActionModule.discard() es el descarte real; el
> barajado real lo hacen CardManager.shuffle_deck()/_zone_manager/GameManager
> directamente (varios sitios ya usan esos, no EffectController).
> =============================================================================
> 6/7. return_to_deck()/play_card_to_zone() eliminados (2026-08-17): cero
> llamadores en todo el proyecto. GoldManager._trigger_enter_play() ya
> documentaba por qué evita play_card_to_zone() (depende del game_board
> muerto) y mueve la carta directo — ver ese comentario para el camino real.
> =============================================================================
> 8. DESTRUIR CARTA (DAR 7.3 - Triggers de destrucción)
> =============================================================================

### `destroy_card` — línea 313

> Destruye una carta, enviándola al Cementerio (o al Destierro si fue
> exhumada, regla que respeta CardManager.destroy_card()).
> Emite on_card_left_play y on_card_destroyed.
>
> is_being_destroyed (2026-09-04, bug reportado: 'el texto de la consola
> de los Talismanes, estas no se destruyen') — GoldManager._play_talisman()
> reusa esta función para mandar un Talismán ya resuelto a su Cementerio
> por defecto (mismo camino real de salida de juego, mismos contadores/
> señales), pero un Talismán resolviendo NO es una 'destrucción' en
> términos DAR — pasar false solo cambia el texto de consola a algo
> preciso, sin tocar prevención de salida de juego ni las señales (que
> siguen siendo el mismo choke point real para ambos casos).
>
> Returns: true si se destruyó

### `exile_card` — línea 378

> Destierra una carta, enviándola al Destierro
> Emite on_card_left_play (si estaba en juego) y on_card_exiled
>
> bypass_prevention (2026-08-28): true cuando desterrar ES el costo que el
> propio jugador eligió pagar (p.ej. 'Puedes Desterrarlo para...', Legión
> Paladín) — la Prevención protege contra remoción del RIVAL, no debe
> poder bloquear que pagues tu propio costo (y si el jugador tiene otra
> copia de la misma carta con una carga de Prevención ya activa, sin esto
> quedaría sin poder pagar el costo de la segunda nunca).
>
> Returns: true si se desterró

### `exile_card` — línea 392

> Indesterrable, Nefandos, dulce canasta (2026-10-18). Un costo propio
> (bypass_prevention) tampoco puede Desterrar lo que no puede ser Desterrado.

### `exile_card` — línea 430

> =============================================================================
> 10. return_to_hand() eliminado (2026-08-17): cero llamadores en todo el
> proyecto (Card.return_to_hand() es un método distinto y no relacionado —
> la animación de "volver a la posición" al cancelar un drag).
> =============================================================================
> 11. CONVERTIR TIPO DE CARTA (DAR Sección 8 - Convertir) — eliminado
> (2026-08-17): convert_card_type(), revert_card_type() y todo lo que
> colgaba exclusivamente de ellas (_validate_persistent_abilities,
> _unequip_weapon, _handle_zone_movement_on_conversion, can_use_ability,
> _update_card_faculties, _set_card_property, _register_conversion_duration,
> _on_turn_end_revert_conversion, _on_combat_end_revert_conversion,
> _revert_card_type, _notify_type_change, is_card_converted,
> get_original_type) tenían CERO llamadores en todo el proyecto — la
> palabra clave Convertir (DAR Sección 8) nunca se conectó a nada real. Se
> conserva clear_conversion_on_leave() (y _converted_cards) porque
> destroy_card()/exile_card() SÍ la llaman, aunque hoy sea un no-op — si
> se reimplementa Convertir en el futuro, ahí queda el punto de enganche.
> =============================================================================

### `clear_conversion_on_leave` — línea 457

> =============================================================================
> PREVENCIÓN "SALE DEL JUEGO" (DAR - Utilizar Habilidades: Prevenir. P.ej.
> Legión Paladín: "Puedes Desterrarlo para prevenir que un Aliado que
> controles salga del juego", 2026-08-28)
> =============================================================================
> Inmunidad TEMPORAL de "no pueden salir del juego" para TODOS los Aliados
> de un jugador, con vencimiento por TURNO (no por carga) — distinto de
> Legión Paladín (Prevención reactiva real por carta, ver
> offer_prevention()/_prevention_registry más abajo): esto es una
> inmunidad OTORGADA por otro efecto, no una carta de Prevención. 2026-08-29,
> p.ej. Sherlock Holmes: "los Aliados que controlas no pueden salir del
> juego hasta tu próximo turno" — protege a TODOS a la vez, sin límite de
> cantidad, hasta que vuelva a empezar el turno de ese jugador.

### `add_blanket_leave_play_immunity` — línea 491

> Inmunidad TEMPORAL de "no puede salir del juego" para UNA carta puntual
> (2026-08-30, p.ej. Garfio Pirata: "Cuando entra en juego, el portador no
> puede salir del juego hasta tu próximo turno") — distinta de
> _blanket_leave_play_immunity (esa protege a TODOS los Aliados de un
> jugador a la vez, no una carta elegida). {card_instance_id: true}

### `_try_consume_leave_play_prevention` — línea 548

> =============================================================================
> PREVENCIÓN REACTIVA (DAR — Utilizar Habilidades: Prevenir), 2026-09-09
> =============================================================================
> Registro genérico de cartas de Prevención — reemplaza los 3 mecanismos de
> "carga previa" que existían antes (uno por Estaca, otro por Legión
> Paladín, otro por Drácula/Ángel Redentor) por UN solo punto de entrada
> reactivo: se pregunta al jugador EN EL MOMENTO en que el efecto está por
> resolverse, no antes (diseño validado en docs/plans/2026-09-02-
> prevention-response-window-design.md, roster real re-auditado 2026-09-09
> contra la API — Paladín Bestiarium NO es una carta de Prevención, estaba
> en la lista original por error; Almirante Akari queda fuera a propósito,
> su costo compartido con una segunda habilidad (Anular) no encaja limpio
> en este registro todavía).
>
> Cada entry: {name, detect: Callable(text)->bool, effect_tags:
> Array[String], opponent_only: bool, applies: Callable(target)->bool
> (target puede ser Node o Dictionary o null — ver Drácula), is_available:
> Callable(card)->bool, on_used: Callable(card) -> (awaitable)}.
> No hace falta un contador de cargas separado: la disponibilidad de cada
> carta es simplemente "¿sigue existiendo sin usar en una zona de juego?" —
> las 4 se autoconsumen (destierro o conversión) al usarse, salvo Ángel
> Redentor (sin costo), que usa el turn_registry ya existente para su
> candado real de "una vez por turno".

### `_build_prevention_registry` — línea 580

> OJO: NO incluye "leave_play" — destroy_card()/exile_card() son el
> funnel final por el que TAMBIÉN pasa cualquier "destroy"/"exile"
> ya resuelto por ActionDestroy/ActionBanish más arriba en la
> pila; si Estaca tuviera "leave_play" aquí, preguntaría DOS veces
> por la misma acción (una vez como "destroy"/"exile", otra como
> "leave_play" al llegar a destroy_card()/exile_card()). Legión
> 2026-09-09, corregido a pedido del usuario: Estaca SÍ cubre
> "barajar de vuelta al mazo" — su alcance real es "cualquier
> efecto oponente que afecte a una carta", no una lista cerrada
> de verbos. Con "leave_play" en su lista, ambas cartas (Estaca
> y Legión Paladín) quedan candidatas en destroy_card()/
> exile_card()/return_to_deck() — pero eso NO duplica la
> pregunta para un Destruir/Desterrar normal: esos ya se
> resuelven en el paso "destroy"/"exile" de ActionDestroy/
> ActionBanish, que NO pasa 'source' al llamar a destroy_card()/
> exile_card() después — sin 'source' real, el chequeo
> opponent_only de Estaca no puede confirmarse y no vuelve a
> preguntar ahí. Solo return_to_deck() (nuevo choke point,
> 2026-09-09) llama con 'source' real desde varios call sites,
> así que ahí Estaca sí puede ofrecerse de verdad.

### `_build_prevention_registry` — línea 618

> Su texto es específico de "un Aliado" (2026-09-09, corregido —
> se filtraba antes SOLO en _try_consume_leave_play_prevention(),
> que no cubre el choke point nuevo de return_to_deck(); ahora
> vive aquí, en el registro mismo, así que aplica sin importar
> desde dónde se llame offer_prevention()).

### `_build_prevention_registry` — línea 638

> opponent_only=false (2026-09-09, corregido): el texto real de
> Drácula no dice "oponente" en ningún lado ("prevenir que una
> habilidad sea cancelada o un Aliado de coste 1 sea Anulado"),
> a diferencia de Estaca que sí lo dice explícito.

### `_build_prevention_registry` — línea 702

> 'Una vez por turno, puedes Barajar una carta de tu mano o que
> controles para Anular una carta de coste 2 o menos o prevenir
> que un Aliado sea afectado por un efecto oponente' (Almirante
> Akari, 2026-09-04) — reactiva de verdad (2026-09-09, corregido
> a pedido del usuario): SIN botón de activación, dos disparadores
> reactivos distintos que comparten un único candado de una vez
> por turno y un único costo (barajar 1 carta propia) pagado
> solo al confirmar cuál de los dos usa. La mitad "Prevenir"
> entra aquí (mismo registro que Estaca, pero solo Aliados); la
> mitad "Anular cuando el rival juega una carta" vive en
> offer_counter_annul() más abajo — comparte is_available/costo
> vía el mismo helper _pay_akari_shuffle_cost().

### `_build_prevention_registry` — línea 734

> Padre Dagón (2026-10-17): "...o prevén que uno o más Aliados
> sean afectados por un efecto oponente" — comparte el "Una vez
> por turno" con su habilidad activada (DagonPatterns.gd). "Uno o
> más": una sola vez cubre a todos tus Aliados afectados por ESE
> mismo efecto (_dagon_shield, ver offer_prevention()).

### `_build_prevention_registry` — línea 763

> Armadura Dorada (2026-10-18): "...para prevenir que tus Aliados
> sean afectados" — una vez cubre a todos tus Aliados que afecte ese
> mismo efecto (mismo escudo que Padre Dagón).

### `_build_prevention_registry` — línea 807

> ngenechen (2026-10-18): "Una vez por turno, puedes Barajar carta
> de tu mano para prevenir un efecto."

### `_build_prevention_registry` — línea 829

> Dos de Cada Uno (2026-10-18): "hasta dos cartas de coste 1 o
> menos de un mismo tipo" — la segunda del mismo tipo que afecte
> ese mismo efecto también queda cubierta.

### `_pay_akari_shuffle_cost` — línea 923

> 2026-09-13, a pedido del usuario: click directo sobre la mano/campo en
> vez del modal de lista viejo.

### `offer_counter_annul` — línea 996

> "Una vez por turno, puedes subir una carta que controles a la mano de su
> dueño para Anular un Talismán o Tótem de coste 2 o menos" (flechar xoon,
> 2026-09-20, arquitectura.md "539 cartas sin cobertura") — mismo mecanismo
> real que offer_counter_annul()/Almirante Akari arriba: este motor no
> modela un stack de resolución interceptable, así que "Anular X de coste
> N" en la práctica se implementa como "cuando esa carta termina de entrar/
> resolver, puedes Destruirla" (offer_counter_annul() es el precedente
> verificado para esto, ver arquitectura.md §2 sobre LinkedEffectRegistry/
> TargetSelector — ese clúster con un verdadero targeting-en-la-pila está
> marcado como código muerto, no es lo que usan las cartas reales). Llamar
> desde el mismo choke point que offer_counter_annul() (después de que
> played_card termina de entrar en juego), del lado de quien la jugó.

### `offer_prevention_for_player` — línea 1115

> Cartas en juego (y las Armas equipadas, 2026-10-18) y, para las
> entradas con "zones" que incluye la mano, las de la mano.

### `offer_prevention_for_player` — línea 1165

> Una sola respuesta por efecto (2026-10-17, a pedido del usuario — DAR):
> aunque tengas 3 Estacas, contra un mismo efecto solo previenes con una;
> las demás cartas quedan afectadas.

### `_offer_prevention_choice` — línea 1180

> Remoto real (2026-10-18): elige él, por red, en vez de decidir al azar.

### `_offer_prevention_choice` — línea 1192

> Capa 2 de la Pila de Respuesta Universal (2026-09-09): el bot ya
> puede usar Prevención de verdad — sin diálogo, decide solo, al azar
> entre usar una de las candidatas disponibles o no usar ninguna
> (mismo criterio simple que el resto de las decisiones de
> EasyBotController — no hay heurística de "conviene o no", solo la
> posibilidad real de reaccionar en vez de nunca hacerlo).

### `_offer_prevention_choice` — línea 1203

> Fusión con la Pila de Respuesta Universal (2026-09-09): un solo panel
> visual para "responder a algo" en todo el juego — mismo título/timer/
> 'Pasar' que ResponseWindowHandler usa para la ventana genérica, en vez
> del diálogo aparte (await_two_choice/await_single_pick) que Prevención
> tenía antes. No pasa por ActionPipeline (esto es una pregunta puntual
> con N candidatas + Pasar, no un objeto de pila que pueda ser anulado a
> su vez), pero se ve y se siente igual para el jugador.

### `offer_prevention` — línea 1316

> Puente temporal (2026-09-09) — para cartas con el modelo VIEJO de carga
> previa que quedaron fuera de este rediseño (Fisión Nuclear/Transformación,
> MiscUniquePatterns.gd: aproximan una protección "burbuja"/repartida con
> una carga por carta, sin pregunta reactiva — no encajan en el registro de
> _prevention_registry, que asume UNA carta de Prevención real detectada
> por texto). Almirante Akari YA NO usa este puente (ver
> _prevention_registry/offer_counter_annul() — se pasó a reactivo de
> verdad). Aislado del registro reactivo a propósito, se consulta primero
> en offer_prevention().
> {card_instance_id: count}

### `try_consume_legacy_targeted_prevention` — línea 1351

> Fisión Nuclear (2026-10-14, a pedido del usuario: "carta importante que
> tiene varios efectos complicados"). "Hasta tu próximo turno, no puedes ser
> afectado por efectos oponentes y para afectar tus cartas en juego tu
> oponente debe Desterrar una carta de su mano":
> - el JUGADOR protegido: los efectos del rival que lo afectan a él
> (Descartar de su mano, Botar de su Castillo) no ocurren — ver
> fision_blocks_player_effect(), consultado en ActionModule.discard/mill;
> - su Castillo y su mano (el Cementerio NO, usuario 2026-10-14): el rival
> no puede buscar ni mirar cartas en su Castillo (fision_hides_zones_of(),
> en ActionSearch y CastleLook) ni en su mano, ni hacerle daño por
> efecto (DamageManager);
> en combate, el daño "al Destierro" de habilidades rivales va como daño
> normal (BattleManager);
> - sus cartas EN JUEGO (también las que entren después): cada vez que un
> efecto del rival fuera a afectar una, el rival elige si Destierra una
> carta de su mano para que la afecte; si no puede o no quiere, no la
> afecta — en offer_prevention() (destruir, desterrar, barajar/devolver,
> debilitar, silenciar, ganar el control). Anular NO es afectar la carta
> (usuario, 2026-10-14).
> Quién controla el efecto: EffectContext (el efecto en curso) o, si no hay,
> el controlador de la carta fuente. Dura hasta que empieza el siguiente
> turno del jugador protegido.

### `fision_hides_zones_of` — línea 1424

> Terminal P-12 (2026-10-18): "Si está en tu Reserva, ... él no puede
> mirar tu mano ni tu Castillo."

### `_fision_toll_prevents` — línea 1476

> Colapso Global (2026-10-14, mazo 170): "En respuesta a que tu oponente
> fuera a mirar tu mano o buscar cartas en un Castillo, puedes Desterrar una
> carta de tu mano para jugarlo sin pagar su coste. Prevén que tu oponente
> mire tu mano o busque cartas y tú Robas una carta."
> Se ofrece en las búsquedas (ActionSearch) y en los efectos que miran la
> mano rival. true = la búsqueda/mirada no ocurre. Se juega pagando su coste
> o Desterrando una carta de la mano; va al Cementerio y Robas una.
> Sidhes del Bosque (2026-10-18): "Puedes jugarlo en respuesta a que tu
> oponente fuera a buscar cartas en un Castillo. Nombra dos cartas. Este
> turno tu oponente debe mostrar las cartas que busca y no puede buscar las
> cartas nombradas. Roba una carta o sube un Aliado de tu Cementerio a tu
> mano." ActionSearch lo ofrece antes de buscar en un Castillo y aplica el
> candado (sidhes_blocked_names) y el mostrar (sidhes_reveal_to).

### `offer_sidhes` — línea 1524

> Efecto de Sidhes del Bosque, jugado en respuesta (offer_sidhes) o como
> un Talismán normal en tu Vigilia / Guerra de Talismanes (2026-10-18, a
> pedido del usuario: "puedes jugarlo en respuesta" no impide jugarlo
> normal). 'victim' = quien juega Sidhes; el candado es para su oponente.

### `offer_colapso_global` — línea 1639

> Prevenir daño al Castillo con un Oro (2026-10-14, mazo 170):
> - Alicanto: "En respuesta a que fueras a recibir daño, puedes Desterrar
> este Oro para prevenirlo. Luego, puedes convertir una carta de tu mano
> en un Oro sin habilidad y ponerla en tu Oro Pagado."
> - Escritura Sagrada: "Puedes subirlo a tu mano o convertirlo en un Oro sin
> habilidad para prevenir recibir daño."
> Se ofrece en BattleManager antes de aplicar el daño de combate. Previene
> todo ese daño.

### `_alicanto_convert_hand_card` — línea 1719

> Efectos suspendidos que resuelven en la PRÓXIMA Fase Final de un jugador
> puntual, de una sola vez (2026-09-06, a pedido del usuario — p.ej. Fisión
> Nuclear: 'En la próxima Fase Final oponente, Baraja una carta de coste 2
> o menos o Roba dos cartas') — a diferencia de un trigger real en juego
> (on_opponent_turn_end, que dispara TODOS los turnos mientras la fuente
> siga en juego), esto es un Talismán que ya se resolvió y fue Desterrado:
> no hay ninguna carta en juego a la que consultarle has_trigger() después.
> 'No se puede responder con nada' (aclarado por el usuario) = se resuelve
> directo, sin pasar por ningún sistema de prevención.

## `scripts/core/effects/triggers/GoldConversionPatterns.gd`

### `(nivel de archivo)` — línea 2

> GoldConversionPatterns — 5 de 7 mitades de LookAndPlayResolver.gd, dividido
> por tamaño el 2026-09-06 ("módulos gordos"). Cubre generación de Oro
> Virtual restringido y conversión carta-a-carta: Acabar la Esperanza,
> Garfio Pirata, manuel rodriguez (Oro/Barajar), leon indiferente,
> peripillan, almirante akari, Espíritu de la Máquina. Incluye una copia
> privada de _remove_data_from_array (idéntica a la de LookRevealPatterns.gd
> — duplicada a propósito porque try_execute_convert_then_reveal_until_
> same_type_pattern es la única función de este archivo que la necesita, y
> las 7 mitades no se referencian entre sí). Llamada solo desde
> LookAndPlayResolver.gd (facade) — ver ese archivo para la lista completa de
> las 7 mitades hermanas.

### `try_execute_convert_then_reveal_until_same_type_pattern` — línea 22

> 'Convierte un Oro o carta de coste N o menos en una carta del mismo
> tipo, sin habilidad. Muestra cartas del tope de tu Castillo hasta
> mostrar hasta dos cartas de ese tipo, ponlas en tu mano y Baraja el
> resto.' (Acabar la Esperanza, myl_id 20613, edición kvsm_titanes /
> reprint promo custom_mid_33, 'Ángeles y Demonios: Vigilantes - Mazo
> Dragón'). Las dos oraciones están LIGADAS: 'ese tipo' en la segunda es
> el tipo de la carta elegida como objetivo de Convertir en la primera
> (Oro, Aliado, Arma, Talismán o Tótem) — no se puede resolver aparte con
> el patrón genérico 'muestra/mira N...', necesita el objetivo ya
> elegido. 'Hasta mostrar hasta DOS' = revela de a una del tope hasta
> encontrar 2 de ese tipo o vaciar el Castillo (mismo molde que Alicia en
> Wonderland, try_execute_reveal_until_distinct_cost_allies_pattern más
> arriba), el resto se baraja de vuelta.
>
> 'Si es Anulado, genera un Oro y Roba una carta' (primera cláusula real
> de esta carta, antes de 'Exhumar') queda SIN implementar a propósito:
> los Talismanes en este motor resuelven directo (TriggerSystem.
> resolve_talisman(), sin pasar por la Pila/una ventana de respuesta
> real), así que hoy no existe ningún punto en el que un Talismán pueda
> ser Anulado A MITAD de su propia resolución — esa cláusula no tiene
> todavía un evento real al que engancharse (mismo hueco que el sistema
> de Prevención real, diseño pendiente en docs/plans/2026-09-02-
> prevention-response-window-design.md).

### `try_execute_convert_then_reveal_until_same_type_pattern` — línea 66

> Sin ventana genérica aquí (2026-09-09): Acabar la Esperanza es un
> Talismán — TriggerSystem.resolve_talisman() ya abrió UNA ventana para
> toda la carta antes de siquiera llegar a este patrón.

### `try_execute_wielder_attack_gold_or_draw_pattern` — línea 106

> 'Cuando el portador ataque, si es de coste 1 o más, genera un Oro o
> Roba una carta' (Garfio Pirata, 2026-09-06, bug reportado por el
> usuario) — 'es' se refiere al PORTADOR (el Aliado que porta esta
> Arma), no a esta Arma misma. Elección A/B.

### `try_execute_wielder_attack_gold_or_draw_pattern` — línea 126

> 2026-10-06: generar_oros_virtuales() ya es por jugador (ver
> arquitectura.md §33).

### `try_execute_gold_for_allies_or_shuffle_cost_max_pattern` — línea 137

> 'Al comienzo del turno, genera un Oro para Aliados o Baraja una
> carta de coste 3 o menos' (manuel rodriguez, 2026-09-04) — elección
> A/B. Dispara en CUALQUIER 'al comienzo del turno' (propio o rival, sin
> calificador 'tu' en el texto — TriggerSystem.resolve_agrupacion_
> triggers() solo llama esto para el jugador activo, así que en la
> práctica equivale a 'en tu turno').

### `try_execute_gold_for_allies_or_shuffle_cost_max_pattern` — línea 162

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador
> (ver arquitectura.md §33).

### `try_execute_gold_for_allies_or_shuffle_cost_max_pattern` — línea 169

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_gold_for_allies_or_shuffle_cost_max_pattern` — línea 174

> Sin ventana genérica aquí (2026-09-09): return_to_deck() ya consulta
> Prevención adentro por su cuenta.

### `try_execute_convert_two_top_castillo_to_allies_pattern` — línea 187

> 'Convierte dos cartas del tope de un Castillo en Aliados de Fuerza 2
> sin habilidad, ponlos bajo tu control y no pueden salir del juego ni
> cambiar de controlador hasta tu próximo turno' (leon indiferente,
> 2026-09-04) — mismo mecanismo de conversión real que Sherlock Holmes/
> Biblioteca de Caballería (is_converted + silence_card + Fuerza fijada
> por modificador). 'No pueden cambiar de controlador' queda satisfecho
> por construcción: no hay ningún efecto de robo de control que pueda
> tocarlos en el medio de resolver este mismo Talismán.

### `try_execute_convert_two_top_castillo_to_allies_pattern` — línea 203

> Sin ventana genérica aquí (2026-09-09): silence_card() (dentro del loop
> de abajo) ya consulta Prevención adentro por su cuenta.

### `try_execute_convert_gold_or_opponent_cost_max_draw_pattern` — línea 249

> 'Cuando entra en juego, convierte un Oro o una carta oponente de
> coste 2 o menos en una carta del mismo tipo sin habilidad y Roba una
> carta' (peripillan, 2026-09-04) — 'un Oro' sin calificador (cualquier
> jugador), 'una carta' SÍ calificada 'oponente'.

### `try_execute_gold_for_allies_until_next_turn_pattern` — línea 295

> 'Una vez por turno, genera un Oro para jugar Aliados. Puedes usar ese
> Oro hasta el comienzo de tu próximo turno' (Sariel, 2026-10-14). Antes
> caía en el GOLD genérico: Oro sin restricción, siempre del Anfitrión y
> que vencía al empezar el turno rival.

### `try_execute_gold_for_allies_or_weapons_pattern` — línea 314

> 'Al comienzo del Ataque, genera un Oro por el turno para jugar
> Aliados o Armas' (almirante akari, 2026-09-04).

### `try_execute_gold_for_allies_or_weapons_pattern` — línea 327

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador (ver
> arquitectura.md §33).

### `try_execute_espiritu_maquina_conditional_gold_pattern` — línea 336

> 'Cuando entra en juego, si no es tu primer turno, genera un Oro
> para jugar Armas o Tótem de coste 2 o más' (Espíritu de la Máquina,
> 2026-09-04). 'Tu primer turno' = turno de jugador 1 o 2 (turn_serial:
> el primero de cada jugador, empiece quien empiece).

### `try_execute_espiritu_maquina_conditional_gold_pattern` — línea 355

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador (ver
> arquitectura.md §33) — esta habilidad se desbloquea.

## `scripts/core/effects/triggers/LookAndPlayResolver.gd`

### `(nivel de archivo)` — línea 3

> LookAndPlayResolver — Familia de patrones "mira/muestra N cartas del tope
> de tu Castillo y [elige qué hacer con ellas]": Signo Amarillo (1 a mano, 1
> a Cementerio), Tangata Manu (juega una gratis), Presente (juega una gratis
> o llévate todas a la mano), Perder la Razón (juega una gratis o un Oro
> directo a Oro Pagado). Opera sobre TriggerSystem via _main.
> Extraído de TargetedEffectExecutor.gd (2026-08-28, "módulos gordos" —
> a pedido del usuario, mismo tipo de corte que separó TriggerResolution/
> TriggerRestrictions/TemporaryBuffSystem de TriggerSystem.gd).
>
> Dividido en 7 archivos por tamaño (2026-09-06, "módulos gordos" —
> el archivo llegó a ~3200 líneas, el más grande del proyecto). Este
> archivo queda como FACADE — cada función de abajo es un reenvío de una
> sola línea a la mitad que corresponda, con el mismo nombre y firma de
> siempre, así que TriggerResolution.gd (único llamador, vía
> `_main._look_and_play.try_execute_X(...)`) no necesitó cambiar una sola
> línea por este split. Mismo idioma que SearchAbilityHandler.gd/
> SearchAbilityHandler_AI.gd/SearchAbilityHandler_JV.gd.
>
> Las 7 mitades, por mecánica dominante:
> - LookRevealPatterns.gd: familia "mira/muestra N... elige destino(s)".
> - SearchOwnZonePatterns.gd: busca/relocaliza/convierte en zonas propias.
> - BanishOpponentPatterns.gd: destierra/destruye/anula/bota al oponente.
> - ShuffleDrawPatterns.gd: combos de Barajar/Robar sobre recursos propios.
> - GoldConversionPatterns.gd: genera Oro Virtual / convierte carta-a-carta.
> - PlayFromCemeteryPatterns.gd: juega un Aliado del Cementerio con descuento.
> - MiscUniquePatterns.gd: 4 patrones únicos (burbuja+Fase Final, respuesta+
> exilio+elección, robo de control+renombrado, candado de nombre).

## `scripts/core/effects/triggers/LookRevealPatterns.gd`

### `(nivel de archivo)` — línea 2

> LookRevealPatterns — 1 de 7 mitades de LookAndPlayResolver.gd, dividido por
> tamaño el 2026-09-06 ("módulos gordos"). Esta cubre la familia "mira/muestra
> N cartas del tope de tu Castillo... elige destino(s)": Signo Amarillo,
> Tangata Manu, Presente, Perder la Razón, Tesoro de los Césares, Alicia en
> Wonderland, y toda la familia "reveal_until_X_and_Y" agregada 2026-09-04 en
> adelante (Cabeza de Mimir, atenea en wonderland, metalmorfo, akari, Duelo de
> Dragones, gran kraken, kitsune - sp, etc.). Llamada solo desde
> LookAndPlayResolver.gd (facade) — ver ese archivo para la lista completa de
> las 7 mitades hermanas (SearchOwnZonePatterns, BanishOpponentPatterns,
> ShuffleDrawPatterns, GoldConversionPatterns, PlayFromCemeteryPatterns,
> MiscUniquePatterns).
>
> Dividida a su vez en dos mitades por tamaño (2026-09-06, "módulos gordos",
> split anidado — facade de facade): LookRevealPatternsA.gd (alfabético
> dynamic_gold_count..play_or_hand, 6 patrones — concentra los 3
> try_execute_look_play_* con su filtro compartido, los más largos del
> grupo) y LookRevealPatternsB.gd (look_two_hand_convert_gold..
> weapon_or_totem_and_ally, 10 patrones). Este archivo queda como FACADE —
> cada función de abajo es un reenvío de una sola línea a la mitad que
> corresponda, con el mismo nombre y firma de siempre, así que
> LookAndPlayResolver.gd (único llamador, vía `_look_reveal.try_execute_X_pattern(...)`)
> no necesitó cambiar una sola línea por este split.

## `scripts/core/effects/triggers/LookRevealPatternsA.gd`

### `(nivel de archivo)` — línea 2

> LookRevealPatternsA — mitad A (alfabética) de LookRevealPatterns.gd,
> dividido por tamaño el 2026-09-06 ("módulos gordos", split anidado: este
> archivo es una de las 2 mitades de una de las 7 mitades de
> LookAndPlayResolver.gd). Cubre de try_execute_look_dynamic_gold_count_pattern
> a try_execute_look_play_or_hand_pattern (alfabético) — el corte no cae
> justo a la mitad de los 16 patrones (6 aquí, 10 en la mitad B) porque los
> try_execute_look_play_* (free/or_gold/or_hand) son, con su filtro
> compartido _make_look_play_free_filter(), los 3 patrones más largos de
> todo el grupo; agruparlos aquí balancea el tamaño real de ambos archivos
> en vez del simple conteo de funciones. Llamada solo desde
> LookRevealPatterns.gd (facade) — ver ese archivo para la lista completa y
> la mitad hermana (LookRevealPatternsB.gd).

### `try_execute_look_dynamic_gold_count_pattern` — línea 28

> Detecta 'Mira cartas del tope de tu Castillo como Oros controles. Pon
> dos cartas de ahí en tu mano y ordena el resto' (2026-08-29, Tesoro de
> los Césares) — a diferencia de try_execute_look_pick_pattern() (cantidad
> FIJA a mirar, reparto 1 mano/1 Cementerio), aquí la cantidad a MIRAR es
> dinámica (= Oros que el jugador controla, Reserva + Oro Pagado) y las no
> elegidas vuelven TODAS al Castillo, no hay Cementerio involucrado.
> 'Ordena el resto' queda pendiente (mismo gap ya documentado en
> try_execute_look_pick_pattern) — vuelven al tope en su orden actual.
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

### `_resolve_look_pick_hand_only` — línea 91

> 2026-09-14, a pedido del usuario: click directo sobre las cartas
> reveladas (open_reveal_picker) en vez del modal de lista viejo.

### `try_execute_look_opponent_hand_discard_then_search_ally_pattern` — línea 117

> 'Cuando entra en juego, mira la mano de tu oponente y Descarta una
> carta que no sea Oro. Si Descartaste un Aliado, busca en tu Castillo un
> Aliado y ponlo en tu mano o Cementerio' (kitsune - sp, 2026-09-04) —
> mismo picker de mano rival que _activate_chakram_look_and_lock()
> (SearchAbilityHandler.gd), aquí sin costo/candado, con Descarte real.

### `try_execute_look_opponent_hand_discard_then_search_ally_pattern` — línea 146

> 2026-09-14, a pedido del usuario: click directo sobre la mano rival
> (Nodos ya visibles en el abanico) en vez del modal de lista viejo.

### `_resolve_look_pick_hand_and_mill` — línea 226

> 2026-09-14, a pedido del usuario: click directo sobre las cartas
> reveladas (open_reveal_picker) en vez del modal de lista viejo.

### `try_execute_look_play_free_pattern` — línea 267

> Detecta y resuelve 'Muestra N cartas del tope de tu Castillo y juega
> una carta de coste X o menos de ahí sin pagar su coste' (2026-08-25,
> p.ej. Tangata Manu). Simplificaciones a propósito, documentadas al
> usuario: no cuenta Oros entre las candidatas (su 'coste' no es
> numérico en los datos de la API) y no hay tracking de 'una vez por
> turno' para esta habilidad EN CONCRETO — es un disparador de 'cuando
> entra en juego', que ya solo se dispara una vez por entrada normalmente.
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

### `try_execute_look_play_free_pattern` — línea 275

> 2026-08-25: la palabra antes de "de tu Castillo" NO se exige literal
> ("tope") — los datos de la API traen typos reales (Tangata Manu:
> "del topde de tu Castillo", con la 'd' de más). Se tolera cualquier
> palabra ahí (\\S+) para no depender de que la fuente esté bien escrita.

### `try_execute_look_play_free_pattern` — línea 308

> 2026-10-12 (§58): el Remoto real también elige (antes elegía el bot al
> azar por él, y solo Aliados).

### `try_execute_look_play_free_pattern` — línea 311

> Una sola ventana (2026-08-26, a pedido del usuario — "más visual,
> menos texto"): antes eran dos ventanas seguidas, una de solo mirar
> (sin poder hacer click en nada) y solo en la segunda se podía
> elegir. Ahora se ven las N cartas reveladas de una — es información
> pública (DAR) — con las que cumplen coste ya clickeables a color, y
> el resto atenuada como cualquier carta no seleccionable.
> 2026-09-14, a pedido del usuario: click directo (open_reveal_picker)
> en vez del modal de lista viejo.

### `try_execute_look_play_free_pattern` — línea 327

> El bot resuelve solo, sin abrir el diálogo al jugador humano
> (2026-09-09, bug real reportado por el usuario: SelectionManager no
> distingue de quién es la carta, así que este trigger del BOT
> terminaba dejando elegir al humano en su lugar). Solo Aliados
> (mismo alcance v1 que EasyBotController — un Arma aquí necesitaría
> elegir portador, algo que el bot no resuelve todavía), al azar
> entre lo elegible.

### `try_execute_look_play_free_pattern` — línea 343

> El resto se baraja de vuelta al mazo (2026-08-26, regla del usuario):
> "Muestra"/"revela" del tope sin instrucción explícita de orden
> obliga a barajar el Castillo después — a diferencia de "Mira", que sí
> deja al jugador elegir el orden en el que vuelven, y de Destierra/
> Bota, que no importa porque esas cartas ya no vuelven al mazo.

### `try_execute_look_play_free_pattern` — línea 356

> play_card_for_free() ya sabe jugar cualquier tipo para cualquier
> jugador (§25: Arma con portador elegido por quien corresponde) — el
> bot local sigue con su camino propio (solo Aliados) porque elegir
> portador le abriría la selección al Anfitrión (2026-10-12, §58).

### `_make_look_play_free_filter` — línea 372

> Filtro de elegibilidad compartido por los patrones 'muestra N... juega
> una de coste ≤X sin pagar su coste' (Tangata Manu, Presente, y
> cualquier otro con el mismo molde): sin Oros (su 'coste' no es
> comparable en los datos de la API), sin Talismanes de solo-respuesta
> (Red de Plata, Sacrificio Solar, etc. — misma detección que
> GoldManager._is_response_only_talisman(), adaptada a Dictionary porque
> aquí todavía no existe el nodo Card). exclude_self controla si además se
> excluye una copia de la carta fuente misma entre lo revelado — por
> defecto sí (Tangata Manu, Presente), pero Perder la Razón sí puede
> jugarse a sí mismo (2026-08-27, a pedido del usuario).

### `_make_look_play_free_filter` — línea 386

> Un Arma sin ningún Aliado libre en juego para portarla no es una
> jugada válida (2026-08-29, a pedido del usuario) — antes se ofrecía
> igual como clickeable, y GoldManager.play_card_for_free() la
> rechazaba solo AL EJECUTAR (chequea _player_has_ally_in_play()),
> momento en el que la carta ya se había sacado de 'remaining' dando
> por hecho que la jugada iba a funcionar — quedaba destruida
> (card.queue_free()) sin ir a ningún lado. Se descarta aquí antes,
> para que ni siquiera aparezca como opción.

### `try_execute_look_play_or_gold_pattern` — línea 423

> Detecta y resuelve 'Muestra seis cartas del tope de tu Castillo.
> Puedes jugar una carta de coste X o menos de ahí sin pagar su coste o
> poner un Oro de ahí en tu Oro Pagado' (2026-08-27, p.ej. Perder la
> Razón). Variante de look_play_free: la alternativa aquí es tomar UN Oro
> puntual de lo revelado y ponerlo directo en la Reserva, no toda la
> pila ni a la mano. Misma ventana única: los no-Oro jugables (coste ≤X)
> y CUALQUIER Oro revelado quedan clickeables a la vez — según qué tipo
> sea la carta elegida se resuelve como 'jugar gratis' o 'a Oro Pagado'.
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

### `try_execute_look_play_or_gold_pattern` — línea 457

> Igual que Presente (2026-08-29, a pedido del usuario): el 'Puedes' aquí
> también autoriza la alternativa de jugar gratis, no autoriza declinar
> el efecto entero — mientras exista AL MENOS UNA acción legal (un Oro
> revelado, o una carta jugable gratis), can_cancel queda en false. Pero
> a diferencia de Presente, aquí no hay un tercer botón de respaldo tipo
> 'Poner' — si de las 6 reveladas ninguna es un Oro y ninguna es jugable
> gratis (p.ej. 6 Armas sin ningún portador libre), no hay NINGUNA acción
> legal posible. Ahí can_cancel SÍ va en true (2026-08-29, corregido a
> pedido del usuario: mostrar igual el panel con lo revelado, para que
> el jugador tenga certeza de qué salió, en vez de resolver en silencio
> sin mostrar nada — Cancelar queda como única salida posible, no como
> alternativa a una acción legal disponible).

### `try_execute_look_play_or_gold_pattern` — línea 477

> 2026-10-12 (§57/§58): el Remoto real también elige (antes elegía el
> bot al azar por él). Las dos opciones del texto son distintas: JUGAR
> gratis una carta (Aliado/Arma/Tótem/Talismán, abajo con play_card_
> for_free()) o PONER EN JUEGO un Oro en el Oro Pagado — un Oro nunca se
> "juega" (regla confirmada por el usuario).

### `try_execute_look_play_or_gold_pattern` — línea 483

> 2026-09-14, a pedido del usuario: click directo (open_reveal_picker)
> en vez del modal de lista viejo.

### `try_execute_look_play_or_gold_pattern` — línea 540

> Va directo a Oro Pagado, NO a Reserva (2026-08-28, corrección —
> el texto de la carta dice literal 'poner un Oro de ahí en tu
> Oro Pagado', no en la Reserva; a diferencia de _place_card_as_gold()
> este Oro nunca estuvo disponible para pagar nada, entra ya-gastado).

### `try_execute_look_play_or_gold_pattern` — línea 557

> Los Oros también pueden disparar "cuando entra en juego", sea
> cual sea la zona donde entren (2026-08-26, regla del usuario) —
> mismo camino que _place_card_as_gold().

### `try_execute_look_play_or_hand_pattern` — línea 574

> Detecta y resuelve 'Muestra las primeras N cartas de tu Castillo.
> Puedes jugar una carta de coste X o menos de ahí sin pagar su coste o
> ponerlas en tu mano' (2026-08-26, p.ej. Presente). Variante de
> try_execute_look_play_free_pattern() con una alternativa extra: en vez
> de jugar una gratis, el jugador puede llevarse las N cartas completas a
> la mano — o declinar del todo (nada gratis en 'Puedes').
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

### `try_execute_look_play_or_hand_pattern` — línea 600

> exclude_self=false (2026-09-19, bug real reportado por el usuario: "no
> puedo jugar presente con el presente"). Texto real (card_cache/cards.json,
> id 19936): "Puedes jugar una carta de coste 3 o menos de ahí sin pagar su
> coste o ponerlas en tu mano" — sin ninguna cláusula que excluya otra
> copia de sí misma. El default true de _make_look_play_free_filter()
> (pensado originalmente para Presente, según el comentario de la función)
> no tiene base en el texto real de la carta — mismo caso que Perder la
> Razón, que ya pasa false explícito. No se tocó el default compartido de
> la función ni el llamador de Tangata Manu (línea ~293): ese sí usa el
> default sin haberse verificado todavía contra su propio texto — no
> cambiar sin que el usuario lo confirme primero (mismo criterio que
> arquitectura.md §10.3).

### `try_execute_look_play_or_hand_pattern` — línea 617

> Una sola ventana (2026-08-27, a pedido del usuario): las N cartas se
> ven de una — las que cumplen coste ya clickeables a color para jugar
> gratis (mismo filtro/estilo que Tangata Manu) — y se agrega un botón
> extra "Poner en tu mano" al panel de SelectionManager para la otra
> alternativa, sin abrir un popup de elección aparte primero.
> DEJADO A PROPÓSITO en SelectionManager (2026-09-14, barrido de
> pickers modales → click directo): este panel inyecta un tercer
> botón custom ("Poner", ver más abajo) que open_reveal_picker() no
> soporta (solo pick-por-click puro) — mismo criterio de complejidad
> real que Duelo de Dragones/Ofrendas al Dragón en el barrido de
> triggers (ver docs/plans/2026-09-09-pila-respuesta-universal-design.md).

### `try_execute_look_play_or_hand_pattern` — línea 632

> can_cancel=false a propósito (2026-08-29, a pedido del usuario): el
> 'Puedes' del texto de esta carta autoriza la alternativa de jugar
> gratis, NO autoriza declinar el efecto entero — la obligación real
> es elegir UNA de las dos acciones (jugar gratis o llevarse todo a
> la mano). Antes, con can_cancel=true, "Cancelar" resolvía exacto
> igual que 0 elegidas + no tocar 'Poner' — un tercer camino ilegal
> que no debería existir. El botón 'Poner' de abajo sigue siendo
> obligatorio si nada es elegible para jugar gratis.

### `try_execute_look_play_or_hand_pattern` — línea 655

> Ocultar el botón "Confirmar" base (2026-08-29, a pedido del usuario:
> 'debe tener 1 botón nada más que diga Poner'): con min_selections=0 y
> max_selections=1, Confirmar con 0 elegidas y Cancelar terminaban en
> EXACTAMENTE el mismo resultado (to_play/to_hand ambos vacíos, el resto
> se baraja de vuelta) — un botón redundante de más. Clickear una carta
> ya auto-confirma sola (elige y juega gratis); Cancelar cubre 'declinar
> del todo'; el único botón propio que aporta algo distinto es 'Poner en
> tu mano'. Se restaura la visibilidad al cerrar — es el mismo botón
> compartido por TODOS los diálogos de SelectionManager.

### `try_execute_look_play_or_hand_pattern` — línea 698

> 2026-10-12 (§58): el panel de arriba es local (botón "Poner"
> agregado a mano) y no viaja por red. El Remoto elige con clic en
> las cartas reveladas; si no elige ninguna, se le ofrece la otra
> opción del texto (llevárselas a la mano) o declinar.

### `try_execute_look_play_or_hand_pattern` — línea 714

> El bot resuelve solo (2026-09-09, mismo bug real que ya se corrigió
> en Tangata Manu/Perder la Razón: esto abría el mismo diálogo de
> arriba sin fijarse de quién era la carta, dejando elegir al humano
> en su lugar). Solo Aliados para jugar gratis (mismo alcance v1 que
> el resto del bot); si no hay ninguno elegible, la única alternativa
> legal es llevarse todo a la mano.

### `try_execute_look_play_or_hand_pattern` — línea 767

> play_card_for_free() ya sabe jugar cualquier tipo para cualquier
> jugador (§25: Arma con portador elegido por quien corresponde) — el
> bot local sigue con su camino propio (solo Aliados) porque elegir
> portador le abriría la selección al Anfitrión (2026-10-12, §58).

## `scripts/core/effects/triggers/LookRevealPatternsB.gd`

### `(nivel de archivo)` — línea 2

> LookRevealPatternsB — mitad B (alfabética) de LookRevealPatterns.gd,
> dividido por tamaño el 2026-09-06 ("módulos gordos", split anidado: este
> archivo es una de las 2 mitades de una de las 7 mitades de
> LookAndPlayResolver.gd). Cubre de try_execute_look_two_hand_convert_gold_pattern
> a try_execute_reveal_until_weapon_or_totem_and_ally_pattern (alfabético) —
> 10 patrones aquí contra 6 en la mitad A, porque A concentra los 3
> try_execute_look_play_* (los más largos del grupo, con su filtro
> compartido) — ver la nota de balance en LookRevealPatternsA.gd. Llamada
> solo desde LookRevealPatterns.gd (facade) — ver ese archivo para la lista
> completa y la mitad hermana (LookRevealPatternsA.gd).

### `try_execute_look_two_hand_convert_gold_pattern` — línea 57

> 2026-09-14, mismo bug real que ZoneManager.draw_card()
> (ver ese comentario) — faltaba aquí también.

### `try_execute_name_reveal_until_match_then_gold_to_pagado_pattern` — línea 73

> 'Nombra un Aliado o Tótem. Muestra cartas de tu Castillo hasta
> mostrar una carta con ese nombre, ponla en tu mano y Baraja el resto.
> Pon un Oro de tu mano en tu Oro Pagado' (contra el caos, 2026-09-04) —
> 'Cuando este Talismán se resuelva, puedes pagar un Oro para repetir su
> efecto' NO implementado (bucle de repetición pagada, fuera de alcance
> por ahora).

### `try_execute_name_reveal_until_match_then_gold_to_pagado_pattern` — línea 113

> 2026-09-13, a pedido del usuario: click directo en la mano en vez
> del modal viejo.

### `try_execute_peek_hand_banish_search_castillo_cemetery_draw_pattern` — línea 129

> 'Mira la mano de tu oponente y Destierra una carta de coste 2 o
> menos de ahí. Busca una carta en un Castillo y hasta dos cartas de un
> Cementerio y Destiérralas. Si Destierras dos o menos cartas de esta
> forma, Roba dos cartas' (Duelo de Dragones, 2026-09-04) — no cubre 'al
> comienzo de cualquier Fase' (solo jugable en las ventanas normales de
> Talismán).

### `try_execute_peek_hand_banish_search_castillo_cemetery_draw_pattern` — línea 157

> 2026-09-14, a pedido del usuario: click directo sobre la mano rival
> (Nodos ya visibles) en vez del modal de lista viejo.

### `try_execute_reveal_gold_to_pagado_weapon_or_totem_to_hand_pattern` — línea 186

> 'Muestra cartas del tope de tu Castillo hasta mostrar un Oro y un
> Arma o Tótem. Pon el Oro en tu Oro Pagado, la otra carta en tu mano y
> Baraja el resto' (Activar Tenshi Z, 2026-09-04).
>
> 2026-10-12, bug real reportado por el usuario: Estrella de Kirin ('...
> hasta mostrar un Oro y un Arma o Tótem y ponlos en tu mano') caía en
> este mismo patrón (comparten la frase de revelado) y el Oro terminaba
> en la Reserva — y además disparaba su 'Cuando entra en juego' (p.ej.
> Drácula). El destino del Oro sale ahora del texto: 'ponlos en tu mano'
> → ambos a la mano; 'pon el Oro en tu Oro Pagado' → Oro Pagado (antes
> también iba a la Reserva por error, contra el propio texto de Tenshi Z).

### `try_execute_reveal_gold_weapon_totem_split_pattern` — línea 254

> 'Muestra cartas del tope de tu Castillo hasta mostrar un Oro, un
> Arma y un Tótem. Pon uno en tu mano, dos en tu Cementerio y Baraja el
> resto' (akari, 2026-09-04) — el jugador elige CUÁL de los tres
> encontrados va a la mano; los otros dos van al Cementerio.

### `try_execute_reveal_gold_weapon_totem_split_pattern` — línea 289

> 2026-09-14, a pedido del usuario: click directo (open_reveal_picker)
> en vez del modal de lista viejo.

### `try_execute_reveal_until_ally_and_gold_pattern` — línea 318

> 'Muestra cartas del tope de tu Castillo hasta mostrar un Aliado y
> un Oro, ponlos en tu mano y Baraja el resto' (2026-09-04, p.ej. Cabeza
> de Mimir) — revela de a una del tope hasta encontrar AMBOS (un Aliado
> Y un Oro, en cualquier orden), pone los dos en la mano, el resto se
> baraja de vuelta. Si el Castillo se vacía sin encontrar alguno de los
> dos, se pone en la mano el que sí se haya encontrado ('en la medida de
> lo posible', DAR Sección 8).

### `try_execute_reveal_until_ally_and_weapon_pattern` — línea 366

> 'Muestra cartas del tope de tu Castillo hasta mostrar un Aliado y un
> Arma, ponlos en tu mano y Baraja el resto' (metalmorfo, 2026-09-04).

### `try_execute_reveal_until_ally_and_talisman_pattern` — línea 408

> 'Muestra cartas del tope de tu Castillo hasta mostrar un Aliado y un
> Talismán y ponlos en tu mano' (Diadema Celestial, 2026-09-15 — bug real
> reportado por el usuario: "no disparó la diadema", sin patrón propio
> hasta ahora). Mismo molde que try_execute_reveal_until_ally_and_weapon_
> pattern (metalmorfo), solo Talismán en vez de Arma. Las otras dos
> cláusulas de esta carta (Aliados bloqueadores ganan Fuerza/rival pierde
> Imbloqueable; Destierro al Botarse por daño) NO cubiertas aquí.

### `try_execute_reveal_until_distinct_cost_allies_pattern` — línea 462

> Detecta 'Muestra cartas del tope de tu Castillo hasta mostrar dos
> Aliados de distinto coste y ponlos en tu mano' (2026-08-29, Alicia en
> Wonderland) — a diferencia de toda la familia 'muestra/mira N...' de
> arriba, aquí la cantidad a revelar NO es fija: se revela de a una carta
> del tope hasta encontrar dos Aliados cuyo coste entre sí sea distinto (o
> hasta vaciar el Castillo). El resto de lo revelado en el camino (no
> Aliados, o un Aliado del mismo coste que el primero ya encontrado) se
> baraja de vuelta al mazo (mismo criterio que Tangata Manu: 'muestra' sin
> instrucción de orden obliga a barajar después). Si el Castillo se vacía
> sin encontrar dos Aliados de coste distinto, no se pone nada en la mano
> ('en medida de lo posible', DAR Sección 8) y todo lo revelado igual se
> baraja de vuelta.
> Returns: true si el patrón aplicaba (se haya podido resolver o no).

### `try_execute_reveal_until_three_cost1_allies_play_one_pattern` — línea 531

> 'Muestra cartas del tope de tu Castillo hasta mostrar tres Aliados de
> coste 1, juega uno de ellos sin pagar su coste y Baraja el resto' (gran
> kraken, 2026-09-04) — dispara tanto en 'entra en juego' como en
> 'ataca' (mismo dispatcher compartido para el primero; registrado
> también en la rama on_attack, ver TriggerResolution.gd).

### `try_execute_reveal_until_three_cost1_allies_play_one_pattern` — línea 553

> 2026-09-14, a pedido del usuario: click directo (open_reveal_picker)
> en vez del modal de lista viejo.

### `try_execute_reveal_until_weapon_or_totem_and_ally_pattern` — línea 574

> 'Muestra cartas del tope de tu Castillo hasta mostrar un Arma o Tótem
> y un Aliado y ponlos en tu mano' (atenea en wonderland, 2026-09-04) —
> mismo patrón que try_execute_reveal_until_ally_and_gold_pattern, pero el
> segundo tipo buscado es Arma O Tótem (cualquiera de los dos) en vez de
> Oro. Dispara tanto en 'entra' como en 'sale del juego' (mismo
> dispatcher compartido, ver _resolve_look_and_play_patterns()).

## `scripts/core/effects/triggers/MiscTargetedPatterns.gd`

### `(nivel de archivo)` — línea 2

> MiscTargetedPatterns — Slice de TargetedEffectExecutor.gd dividido por
> tamaño (2026-09-06, "módulos gordos"). Agrupa los patrones sueltos que no
> encajan ni en el toolkit genérico de selección de un solo objetivo (que se
> quedó en TargetedEffectExecutor.gd) ni en el cluster compuesto de
> Arma/Buscar/Barajar (WeaponSearchShuffleExecutor.gd):
> _resolve_search_cemetery_to_hand, _resolve_banish_from_both_cemeteries y
> _refresh_rotation_for_name. Ninguna de las tres depende de otro método de
> TargetedEffectExecutor — cada una opera directo sobre CardManager/
> SelectionManager o recibe 'main' como parámetro, así que no hace falta el
> back-reference _main salvo para el primer caso. Opera sobre TriggerSystem
> via _main (mismo Node que TargetedEffectExecutor._main — ver ese archivo
> para el facade que reune este slice y el resto del split).

### `_resolve_search_cemetery_to_hand` — línea 23

> Elige hasta max_amount cartas del Cementerio propio (filtradas por
> tipo si se pasa type_filter) y las sube a la mano.
> 2026-09-13, a pedido del usuario: click directo con ZoneViewerModule.
> open_cemetery_target_picker() en vez del modal de lista viejo — filtro
> restringido al lado propio (mismo criterio que la rama "Subir" de
> Campanita, ver arquitectura.md §10.18/§10.21). El único llamador
> (DSR_SearchGoldCombos.gd) ignora el valor de retorno, así que la vieja
> distinción 'false=canceló del todo / true=aceptó eligiendo 0' ya no
> tenía ningún efecto real — se simplifica a bool fijo true salvo el
> caso 'no hay Main'.
> Returns: false solo si no se pudo resolver Main (error), true en
> cualquier otro caso, incluso sin candidatos o sin elegir nada.

### `_resolve_banish_from_both_cemeteries` — línea 64

> Destierra hasta max_amount cartas combinadas entre ambos Cementerios
> (Espada de O'Higgins — VERIFICADO 2026-09-13: esta es la función que
> realmente se ejecuta para "Destierra hasta N cartas de los Cementerios y
> Roba M cartas", ver arquitectura.md §10.21 — try_execute_banish_up_to_n_
> cemeteries_then_draw_pattern(), convertida antes en §10.14 pensando que
> era esta, resultó ser código muerto por orden de chequeo).
>
> 2026-09-13, a pedido del usuario: reemplaza las DOS selecciones
> SEPARADAS (primero rival, después propio, con modales de lista — así se
> evitaba la confusión de "¿de cuál Cementerio salió esta carta?") por
> ZoneViewerModule.open_cemetery_target_picker(), que ya muestra ambos
> Cementerios en columnas separadas y etiquetadas — resuelve esa misma
> confusión mostrando de dónde es cada carta, sin necesitar dos pasos.
>
> Reordenado (2026-09-09, Pila de Respuesta Universal): la selección se
> declara primero, sin tocar nada — solo con lo elegido se abre UNA
> ventana de respuesta, y solo si nadie anula/cancela se ejecutan los
> destierros.

## `scripts/core/effects/triggers/MiscUniquePatterns.gd`

### `(nivel de archivo)` — línea 2

> MiscUniquePatterns — 7 de 7 mitades de LookAndPlayResolver.gd, dividido por
> tamaño el 2026-09-06 ("módulos gordos"). Cuatro patrones únicos que no
> encajaban limpio en ninguna de las otras 6 categorías: Fisión Nuclear
> (burbuja de protección + programación de Fase Final), Transformación
> (ventana de respuesta + exilio + elección multi-rama), shedo titan (robo de
> control + renombrado), Malleus Maleficarum (candado de nombre). Llamada
> solo desde LookAndPlayResolver.gd (facade) — ver ese archivo para la lista
> completa de las 7 mitades hermanas.

### `try_execute_bubble_protection_and_schedule_final_phase_pattern` — línea 21

> Fisión Nuclear: 'Hasta tu próximo turno, no puedes ser afectado por
> efectos oponentes y para afectar tus cartas en juego tu oponente debe
> Desterrar una carta de su mano. En la próxima Fase Final oponente,
> Baraja una carta de coste 2 o menos o Roba dos cartas.'
> Rehecha el 2026-10-14 (a pedido del usuario). El escudo vive en
> EffectController (activate_fision_shield, ver su comentario): protege al
> jugador y cobra el Destierro al rival por cada carta en juego que quiera
> afectar, también las que entren después. Antes eran 99 cargas sobre las
> cartas que ya estaban en juego, que frenaban hasta tus propios efectos.
> Fase Final oponente, sin popup: brillan las cartas en juego de coste 2 o
> menos (no Oros) y tu Castillo; tu Castillo = Robar dos cartas. Sin
> cartas que barajar, roba directo.

### `try_execute_transformacion_pattern` — línea 96

> 'Puedes jugarlo en respuesta a que tu oponente juegue una carta o
> utilice una habilidad y Destiérralo. Elige un efecto: - Prevén que una
> carta que controles sea afectada y Roba una carta. - Prevén un efecto
> que fuera a afectarte, busca un Aliado en tu Castillo y ponlo en tu
> mano' (Transformación, 2026-09-06). El 'Destiérralo' lo maneja el
> destino post-resolución genérico de GoldManager._play_talisman()
> (self_exile), aquí solo la elección A/B.
>
> Rama A usa el mismo mecanismo de cargas por carta que ya protege a
> Estaca (EffectController.add_opponent_effect_prevention() +
> try_consume_opponent_effect_prevention(), consultado en TODOS los
> choque genéricos: destroy/banish/debuff/silence — ver
> ActionModule.destroy()/banish(), TargetedEffectExecutor, KeywordManager).
> Rama B ('Prevén un efecto que fuera a afectarte', sin carta puntual que
> elegir) se aproxima con la misma idea pero repartida en TODAS las
> cartas propias en juego a la vez, un solo cargo cada una — mismo
> principio de aproximación ya usado y documentado en Fisión Nuclear
> (bubble de protección), aquí a escala de un solo efecto en vez de 'hasta
> tu próximo turno'. Límite conocido, igual que en Fisión Nuclear: no
> cubre daño directo al Castillo (jugador), solo efectos que apunten a
> una carta en juego.

### `try_execute_gain_control_ally_rename_titan_pattern` — línea 161

> 'Cuando entra en juego, gana el control de un Aliado y cambia su
> nombre a Titán. Tu oponente Bota cartas igual a su coste' (shedo
> titan, 2026-09-04) — usa ContinuousEffectManager.gain_control_of_card(),
> el primer uso real de robo de control en el motor.

### `try_execute_gain_control_ally_rename_titan_pattern` — línea 175

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_malleus_name_lock_pattern` — línea 204

> 'Cuando entra en juego, nombra una carta que no sea Malleus
> Maleficarum. Si está en tu Reserva, las cartas nombradas con este Oro
> pierden su habilidad' (Malleus Maleficarum, 2026-09-04) — reusa
> KeywordManager.lock_ability_by_name()/is_name_locked() (Alicia en
> Wonderland). Simplificación: is_name_locked() valida 'mientras la
> fuente siga EN JUEGO' en general (Reserva u Oro Pagado), no
> específicamente 'en tu Reserva' — el texto real excluye Oro Pagado, no
> implementado por ahora (caso borde poco común).

### `try_execute_look_hand_name_play_lock_pattern` — línea 229

> 'Cuando ataca, mira la mano de tu oponente y nombra una carta. Esa
> carta no puede ser jugada hasta tu próximo turno' (Zadquiel, 2026-10-14).
> Candado por NOMBRE (GoldManager.lock_name_from_playing): cubre toda copia
> del rival, también las que robe después. El bot nombra al azar una carta
> que no sea Oro de la mano rival.

## `scripts/core/effects/triggers/NoePatterns.gd`

### `(nivel de archivo)` — línea 2

> Noé (2026-10-17, a pedido del usuario):
> "Cuando entra en juego o bloquee, muestra cartas del tope de tu Castillo
> hasta mostras dos Aliados y ponlos en tu mano. Si tenían costes
> distintos, puedes jugar uno reduciendo su coste en un Oro, hasta un
> mínimo de 1."  ("mostras" es errata de la carta)
> "Una vez por turno, un Aliado gana Furia." (por el turno)
> Se usa con preload.

### `try_execute` — línea 27

> Kai Piloto Prodigio (2026-10-17): "puedes hacer que un Aliado gane 1 de
> Fuerza, Furia y haga doble daño de combate este turno".

### `try_execute` — línea 32

> Javiera Carrera (2026-10-17).

### `try_execute` — línea 41

> Antonio Pincheira (2026-10-17): "En tu Fase Final, agrupa hasta dos
> Aliados" — vuelven de la Línea de Ataque a la de Defensa.

### `try_execute` — línea 46

> Ira (2026-10-17): "Un Aliado gana Furia, Imbloqueable, 3 de Fuerza y
> hace daño al Destierro por el turno."

### `try_execute` — línea 51

> el monstruo (2026-10-18): "puedes Botar dos cartas para que hasta dos
> Aliados ganen Furia y 1 de Fuerza por el turno."

### `try_execute` — línea 56

> Maldición Vudú (2026-10-18).

### `try_execute` — línea 60

> Seducción (2026-10-18).

### `try_execute` — línea 64

> el huascar (2026-10-18): al entrar, un Oro no se agrupa el próximo turno;
> una vez por turno, Desterrar hasta un Arma o Tótem en juego y Robar dos.

### `try_execute` — línea 72

> Linaje Maldito (2026-10-18).

### `try_execute` — línea 76

> Abu Simbel (2026-10-18): "Cuando entra en juego, cada jugador gana el
> control de todas las cartas de las que sea dueño."

### `_grant_furia` — línea 170

> Permanente (2026-10-17, regla del usuario: sin duración escrita, solo
> los cambios de Fuerza son "por el turno"; lo demás es permanente).

## `scripts/core/effects/triggers/OroAbilityPatterns.gd`

### `(nivel de archivo)` — línea 2

> OroAbilityPatterns — Patrones "try_execute_*_pattern" para cartas Oro
> detectadas sin cobertura en la auditoría de 539 cartas (2026-09-20, ver
> arquitectura.md "Auditoría completa de habilidades faltantes"). Mismo
> criterio que TotemAbilityPatterns.gd/WeaponAbilityPatterns.gd: detección
> por substring del texto de habilidad, no por nombre de carta, en su
> propio archivo porque estas cartas Oro no calzaban en ningún parser
> genérico existente. Instanciado directo en TriggerSystem._ready() como
> _oro_patterns (mismo patrón que _totem_patterns/_weapon_patterns),
> llamado desde TriggerResolution.gd en los branches on_agrupacion/
> on_turn_end (llamadas explícitas con la cláusula YA AISLADA — ver nota
> de arquitectura.md 2026-09-20 sobre el riesgo de registrar una función
> de una sola cláusula en el despachador compartido _resolve_look_and_
> play_patterns(), que recorre con el texto COMPLETO sin aislar).

### `(nivel de archivo)` — línea 20

> torii (2026-09-20): "Si lo haces, no Robas al finalizar tu turno" —
> bandera de una sola vez por jugador, consumida por PhaseFlowController.
> _resolve_fase_final() ANTES del bucle de robo normal. Se guarda el
> número de turno junto a la bandera (mismo criterio que _kotoku_in_
> talisman_fizzle en TotemAbilityPatterns.gd) para que nunca sobreviva
> al turno siguiente si por algún motivo nunca se consume.

### `try_execute_udjat_vigilia_pattern` — línea 84

> 'Una vez por turno, dos Aliados ganan y/o pierden 1 de Fuerza por el
> turno o Baraja una carta de tu mano para Robar una carta' (udjat).
> Habilidad ACTIVADA — mismo camino compartido que kotoku-in/sable
> corto. Guardia 'en tu fase final' (su otra cláusula, distinta): sin
> esto, el despachador compartido también prueba este texto durante el
> branch on_turn_end de la Fase Final (ver arquitectura.md 2026-09-20,
> §12.9), disparando esta elección ahí en vez de solo en una activación
> real. Simplificación: 'dos Aliados ganan y/o pierden 1 de Fuerza' se
> implementa como un solo Aliado elegido gana o pierde 1 de Fuerza (no
> dos independientes con signos distintos) — cubre el caso de uso
> principal sin la complejidad de una selección de signo por Aliado.

### `try_execute_libro_de_thoth_pay_pattern` — línea 185

> 'Una vez por turno, puedes pagar un Oro para Robar una carta y elegir
> entre que un Aliado gane Furia, duplique su Fuerza, o su daño sea
> enviado al Destierro este turno' (libro de thoth). Habilidad ACTIVADA.
> No tiene guardia contra su otra cláusula ('Cuando bloquees, genera un
> Oro por el turno') porque esa otra cláusula NO se implementó — ver
> docstring de más abajo, el trigger on_block no existe en el motor
> todavía, así que nunca se prueba este texto desde ese camino.
>
> 2026-10-05: a diferencia de GoldManager.puede_pagar()/pagar_coste()
> (de un solo jugador, ver arquitectura.md §22), GameState.puede_pagar()/
> pagar_oro() SÍ reciben player_id real y leen/escriben oro_reserva[player_id]/
> oro_pagado[player_id] — Dictionaries indexados por jugador, no una
> variable única. Esta carta paga por ese camino (no por el Oro Virtual de
> GoldManager), así que no hace falta excluirla del puente de red.

### `try_execute_libro_de_thoth_pay_pattern` — línea 245

> 2026-09-20, bug real encontrado en revisión de código: el mismo
> mecanismo de Segundo Sello (SearchOwnZonePatterns.gd) tenía un
> filtro `started_player_id != owner_id` que esperaba a que
> volviera a ser TU turno para limpiar el flag, dejándolo vivo un
> turno de más (todo el turno del oponente). Se limpia en el
> PRÓXIMO turn_started sin importar de quién sea — corregido en
> ambos lugares a la vez, ver esa misma nota en SearchOwnZonePatterns.gd.

### `try_execute_carro_szgany_final_pattern` — línea 321

> 'En tu Fase Final, Destierra hasta dos cartas de un Cementerio, mira
> tantas cartas del tope de tu Castillo como Aliados controles y
> ordénalas' (Carro Szgany, 2026-10-14). EffectCompiler no entiende la
> frase entera y la cadena vieja hacía solo una parte. Destierro: selector
> del tablero con los dos Cementerios, todas de UNO (one_zone). Mirar:
> CastleLook con la segunda mitad del texto.

## `scripts/core/effects/triggers/PlayFromCemeteryPatterns.gd`

### `(nivel de archivo)` — línea 2

> PlayFromCemeteryPatterns — 6 de 7 mitades de LookAndPlayResolver.gd,
> dividido por tamaño el 2026-09-06 ("módulos gordos"). Cubre patrones de
> jugar un Aliado directo del Cementerio, gratis o con descuento: Titán
> Abismal, aku aku, sumi el terrible. Llamada solo desde
> LookAndPlayResolver.gd (facade) — ver ese archivo para la lista completa de
> las 7 mitades hermanas.

### `try_execute_titan_abismal_conditional_play_or_draw_pattern` — línea 18

> 'Cuando entra en juego, si sólo controlas Aliados Titán o Ignis,
> juega una carta Titán de coste 1 o menos de tu Cementerio sin pagar su
> coste o Roba una carta' (Titán Abismal, 2026-09-06) — solo esta
> cláusula condicional A/B; 'Cuando entra en juego o ataca, una carta en
> juego aumenta o reduce su coste en un Oro' NO implementada.

### `try_execute_titan_abismal_conditional_play_or_draw_pattern` — línea 55

> 2026-09-13, a pedido del usuario: click directo en el propio
> Cementerio en vez del modal de lista viejo.

### `try_execute_play_cemetery_ally_discounted_min1_pattern` — línea 80

> 'Cuando entra en juego, puedes jugar un Aliado de tu Cementerio
> reduciendo su coste en un Oro, hasta un mínimo de 1' (aku aku,
> 2026-09-04) — mismo mecanismo de búsqueda-a-mano + descuento que
> _activate_kuchiku_cazador_search_and_play_discount() (SearchAbility
> Handler.gd), pero DISPARADO (ETB) y desde el propio Cementerio sin
> elección de zona.

### `try_execute_play_cemetery_ally_discounted_min1_pattern` — línea 90

> 2026-10-12 (§57): antes cortaba para el jugador 1 — gold_manager.
> play_card() es solo del Anfitrión ("No es tu turno"). Ahora juega con
> PlayerSide.play_from_hand(), que usa el camino propio del jugador 1.

### `try_execute_play_cemetery_ally_free_or_draw_three_pattern` — línea 135

> 'Cuando entra en juego, puedes jugar un Aliado de coste 2 o menos de
> tu Cementerio sin pagar su coste o Roba tres cartas' (sumi el
> terrible, 2026-09-04) — elección A/B.

### `try_execute_play_cemetery_ally_free_or_draw_three_pattern` — línea 156

> 2026-09-13, a pedido del usuario: click directo en vez del modal
> de lista viejo.

## `scripts/core/effects/triggers/RatPlaguePatterns.gd`

### `(nivel de archivo)` — línea 2

> Plaga de Ratas (2026-10-17, a pedido del usuario):
> "Cuando entra en juego, puedes buscar un Plaga de Ratas en tu Castillo o
> Cementerio y juégalo sin pagar su coste.
> Puedes Destruirlo para Barajar hasta dos cartas de los Cementerios o que
> un Aliado gane 1 de Fuerza permanentemente."
> Se usa con preload.

## `scripts/core/effects/triggers/SearchOwnZonePatterns.gd`

### `(nivel de archivo)` — línea 2

> SearchOwnZonePatterns — 2 de 7 mitades de LookAndPlayResolver.gd, dividido
> por tamaño el 2026-09-06 ("módulos gordos"). Cubre patrones de "busca en tu
> Castillo/Cementerio (o el de cualquiera, sin apuntar al oponente)" que
> relocalizan o convierten cartas sin banish/destierro dirigido: Kuchiku Kan,
> La Torre, Dulce Canasta, Azi Sruvara, duelo espacial, alto prime, Belta,
> Aurora de Chile, Danza de Dragones, asedio naval. Llamada solo desde
> LookAndPlayResolver.gd (facade) — ver ese archivo para la lista completa de
> las 7 mitades hermanas.

### `try_execute_search_oro_castillo_or_cementerio_pattern` — línea 134

> 'Busca un Oro en tu Castillo o Cementerio y ponlo en tu mano'
> (2026-09-04, p.ej. Dulce Canasta) — 'Castillo o Cementerio' es 'y/o'
> entre zonas ([[project_y_o_means_choose_one_zone]]), el jugador elige
> UNA.

### `try_execute_raise_up_to_one_ally_or_gold_from_cemetery_pattern` — línea 156

> 'Prevén un efecto y puedes subir hasta un Aliado u Oro de tu
> Cementerio a tu mano' (Danza de Dragones, 2026-09-06) — solo la parte
> de subir a la mano; 'Prevén un efecto' y la condición de juego
> 'controlas y/o muestras al menos cinco Oros' NO implementadas.

### `try_execute_raise_up_to_one_ally_or_gold_from_cemetery_pattern` — línea 174

> 2026-09-14, a pedido del usuario: click directo sobre el Cementerio
> propio (open_cemetery_target_picker) en vez del modal de lista viejo.

### `try_execute_raise_same_type_gold_and_search_banish_pattern` — línea 198

> 'Sube una o dos cartas de un mismo tipo que no sea Talismán de tu
> Cementerio a tu mano. Genera un Oro para jugar cartas del mismo tipo y
> busca en un Castillo una carta y Destiérrala' (asedio naval,
> 2026-09-06) — el jugador elige el TIPO implícitamente al elegir las
> cartas (deben compartir tipo); el Oro restringido queda atado a ese
> mismo tipo.

### `try_execute_raise_same_type_gold_and_search_banish_pattern` — línea 214

> 2026-09-14, a pedido del usuario: click directo sobre el Cementerio
> propio, con el candado de "mismo tipo que la primera" resuelto vía
> lock_group_key de await_multi_target() (mismo mecanismo que Hanta el
> Samurai usa para 'un solo Cementerio'), en vez del modal de lista viejo.

### `try_execute_search_azi_ally_to_hand_pattern` — línea 262

> 'Cuando entra en juego, busca en tu Castillo un Aliado Azi, ponlo en
> tu mano y convierte una carta de coste 1 o menos en un Oro con la
> habilidad "Cancelar la habilidad de tus Aliados de coste 4 o más
> cuesta un Oro adicional" y muévelo a tu Oro Pagado' (Azi Sruvara,
> 2026-09-06/2026-09-30) — ambas mitades implementadas ahora:
>
> 1) Búsqueda del Aliado Azi (por nombre, ya que "Azi" es un prefijo
> compartido entre estos Aliados, no una Raza impresa). 2026-09-30, bug
> real reportado por el usuario: esto manipula CardManager.get_deck()
> directo (sin pasar por ActionModule.search()) y barajaba los datos sin
> disparar NUNCA la animación de barajado — se sentía como "aparece una
> carta sola, automática", sin la retroalimentación visual que cualquier
> otra búsqueda en el Castillo sí muestra (ver ActionSearch.search(),
> 'Barajar si buscó en el Castillo'). Agregado el mismo AnimationQueue.CUSTOM.
>
> 2) Conversión de una carta de coste 1 o menos EN JUEGO (propia — el
> texto no dice "oponente") en un Oro con la habilidad de texto nueva, a
> Oro Pagado — mismo mecanismo de conversión real que GoldManager.
> convert_ally_to_gold_in_pagado() (Jormundgander): re-tipar los datos
> ('tipo' = ORO) y crear el nodo desde cero, no silenciar uno existente
> (la carta original SALE del juego, no se queda silenciada ahí).
> IMPORTANTE — límite conocido, mismo motivo que antes de esta sesión: el
> TEXTO de la habilidad nueva queda bien asignado en la carta resultante,
> pero no hay ningún chequeo funcional en el motor que de verdad cobre
> ese Oro adicional al cancelar una habilidad (requeriría un hook nuevo
> en el camino de "cancelar" que usa Drácula,
> LinkedEffectRegistry._execute_cancel() — no auditado en esta sesión).

### `try_execute_search_castillo_or_cemetery_to_pagado_pattern` — línea 350

> 'Busca una carta en un Castillo o Cementerio y ponlo en tu Oro
> Pagado como un Oro sin habilidad. Este efecto no puede ser prevenido'
> (duelo espacial, 2026-09-04) — 'un Castillo o Cementerio' es elegir
> UNA zona ([[project_y_o_means_choose_one_zone]]), luego de quién. 'No
> puede ser prevenido' ya se cumple: search() no pasa por el sistema de
> prevención (solo destroy()/banish() lo consultan).

### `try_execute_search_castillo_or_cemetery_to_pagado_pattern` — línea 363

> 2026-10-13, a pedido del usuario: en vez de dos popups ("¿Castillo o
> Cementerio?" y "¿de quién?" — que además no dejaba elegir bien el
> Castillo rival), el selector del tablero con las 4 zonas a la vez
> (ActionModule.pick_in_zones(): Anfitrión, Remoto por red o bot).

### `try_execute_search_castillo_or_cemetery_to_pagado_pattern` — línea 378

> Abrir un Castillo ata la búsqueda a ese (ZoneBrowsePicker._locked_castle,
> 2026-10-14) y todo Castillo mirado se baraja, se tome o no la carta de ahí.

### `try_execute_search_each_castillo_two_to_cemetery_pattern` — línea 426

> 'Cuando entra o sale del juego, busca en cada Castillo dos cartas y
> ponlas en el Cementerio' (alto prime, 2026-09-04) — 'cada Castillo' =
> AMBOS jugadores, cada uno a su propio Cementerio (destino CEMENTERIO
> nuevo en ActionModule.search()).

### `try_execute_search_each_castillo_two_to_cemetery_pattern` — línea 437

> Elige quien controla la carta, también en el Castillo rival (2026-10-14).

### `try_execute_optional_search_totem_castillo_pattern` — línea 446

> 'Puedes buscar un Tótem en tu Castillo y ponerlo en tu mano'
> (2026-09-04, p.ej. Belta).

### `try_execute_search_two_oros_split_destination_pattern` — línea 465

> 'Cuando salga del juego, busca en tu Castillo dos Oros que no sean
> Aurora de Chile, pon uno en tu Oro Pagado y otro en tu mano' (Aurora de
> Chile, 2026-09-04) — dos búsquedas secuenciales de a 1 (cada una remueve
> la carta encontrada del Castillo, así que la segunda nunca puede repetir
> la misma copia), con name_not para excluirse a sí misma.

### `try_execute_search_two_oros_split_destination_pattern` — línea 485

> =============================================================================
> FAMILIA "SELLO" (Ángeles y Demonios: Vigilantes) — 2026-09-20, auditoría de
> cartas sin implementar del usuario. Ciclo completo de 7 Sellos + "Los Siete
> Sellos" (un Oro, ver GoldManager._check_los_siete_sellos_trigger()) —
> primera tanda (Primer/Segundo/Tercer Sello) a pedido explícito del usuario
> ("Familia de los Sellos primero"), segunda tanda (Cuarto/Quinto/Sexto/
> Séptimo Sello) a pedido explícito de seguir ("sigue con el resto de la
> familia de sellos").
> =============================================================================

### `try_execute_segundo_sello_pattern` — línea 595

> 2026-09-20, bug real encontrado en revisión de código (al revisar
> libro de thoth, que copió este mismo mecanismo): "este turno"
> debe expirar en la MISMA frontera que el modificador de Fuerza de
> arriba (UNTIL_END_TURN, que limpia en _on_turn_ended() sin
> filtrar por jugador — ver ContinuousEffectManager.gd). El filtro
> `started_player_id != owner_id` de abajo esperaba a que volviera
> a ser TU turno para limpiar, dejando el efecto vivo durante todo
> el turno del oponente de más (un turno extra de lo que dice el
> texto). Se limpia en el PRÓXIMO turn_started sin importar de
> quién sea, igual que cualquier otro efecto "este turno".

### `try_execute_cuarto_sello_pattern` — línea 722

> 'Puedes jugarlo al comienzo de cualquier Fase. Busca un Sello en tu
> Castillo y ponlo en tu mano. Destruye hasta una carta de coste 4 o menos.
> Puedes pagar un Oro y Descartarlo para que un Aliado pierda su habilidad
> y 4 de Fuerza por el turno. Roba dos cartas.' (Cuarto Sello, 2026-09-20).
> Primera cláusula ('Puedes jugarlo al comienzo de cualquier Fase') no
> necesita código: no existe en el proyecto ninguna restricción de
> horario/fase para jugar un Talismán (grep confirmado, sin resultados) —
> el motor ya deja jugar cualquier Talismán en cualquier momento en que el
> jugador tenga la palabra, así que esta cláusula ya se cumple sola.
> Segunda: búsqueda compartida. Tercera: Destruye hasta una carta (0 o 1)
> de coste ≤4, cualquier tipo/jugador en juego — mismo filtro de zona +
> ContinuousEffectManager.get_modified_cost() que BanishOpponentPatterns.
> try_execute_raise_opponent_cemetery_or_destroy_cost1_draw_pattern().
> Cuarta: costo adicional OPCIONAL ('Puedes') — pagar 1 Oro y Descartarlo
> (no existe en el proyecto un camino genérico para 'descartar un Oro de
> Reserva', ver GoldManager._discard_oro_from_reserva(), nuevo) para que
> UN Aliado (sin calificador 'tuyo'/'oponente' en el texto — se interpreta
> como cualquier Aliado en juego de cualquier lado, igual que el objetivo
> de Convertir de _select_convert_target()) pierda su habilidad (Keyword
> Manager.silence_card(..., 'turn')) y 4 de Fuerza este turno. 'Roba dos
> cartas' se interpretó como parte del mismo costo opcional (misma oración,
> sin 'de todas formas' que la desligue) — no se resuelve si no se paga.
> SIN ventana de respuesta propia a propósito (mismo motivo que el resto de
> la familia — ya la abre resolve_talisman()).

### `try_execute_cuarto_sello_pattern` — línea 767

> 2026-10-05, bug real encontrado al convertir más cartas: main.gold_cards
> es un Array GLOBAL con el Oro físico de AMBOS jugadores — sin filtrar
> por owner_id, "own_oros" en realidad devolvía cualquier Oro en Reserva
> de cualquiera de los dos (bug preexistente, no solo de red).

### `try_execute_quinto_sello_pattern` — línea 816

> 'Busca un Sello en tu Castillo y ponlo en tu mano. Baraja hasta cinco
> cartas de los Cementerios y juega un Aliado de tu Cementerio reduciendo
> su coste en un Oro, hasta un mínimo de 0 o un Sello pagando su coste. Si
> está en tu Cementerio, no se pueden jugar más de cinco cartas por turno.'
> (Quinto Sello, 2026-09-20). Segunda cláusula: _shuffle_up_to_from_
> cemeteries() (nueva, variante 'solo Barajar' de _resolve_armeria_
> barajar_desterrar()) + elección A/B — jugar un Aliado del Cementerio a
> -1 Oro (mínimo 0, allow_zero=true, mismo mecanismo que aku aku en
> PlayFromCemeteryPatterns.gd pero con mínimo 0 en vez de 1) O jugar un
> Sello del Cementerio pagando su coste completo (mismo camino de
> búsqueda-a-mano + play_card() de GoldManager, sin descuento). Tercera
> cláusula: habilidad DESDE EL CEMENTERIO, tope GLOBAL de cartas jugadas
> por turno — ver TurnManager.cards_played_count_this_turn y GoldManager.
> _quinto_sello_cap_violation() (gatea play_card(), NO play_card_from_
> exile()/play_card_from_cemetery()/play_card_for_free() — limitación
> conocida, ver arquitectura.md §12.5).
> SIN ventana de respuesta propia a propósito (mismo motivo que el resto
> de la familia — ya la abre resolve_talisman()).

### `try_execute_sexto_sello_pattern` — línea 897

> 'No puede ser Anulado. Busca un Sello en tu Castillo y ponlo en tu
> mano. Destruye o Destierra todas las cartas que no sean Oro. Cada
> jugador Bota seis cartas y por cada Sello que se haya Botado de esta
> forma, tu oponente Bota una carta adicional.' (Sexto Sello, 2026-09-20).
> 'No puede ser Anulado': protección estática incondicional agregada en
> LinkedEffectRegistry._execute_annul() (nueva, mismo criterio que 'no
> pueden ser canceladas' de Drácula en _execute_cancel()) — cubre esta
> carta automáticamente, sin código aparte aquí. Elección A/B única para
> TODAS las cartas (no por carta) — Destruir o Desterrar, ambos jugadores,
> cualquier carta que no sea Oro en juego. Mill 6 a cada jugador (source
> 'Sexto Sello'); el bono 'una carta adicional por cada Sello Botado de
> esta forma' cuenta los Sello entre las 12 cartas molidas en total (ambos
> jugadores) — interpretación: 'de esta forma' se lee como 'por este
> efecto', no solo del Cementerio del controlador, ya que el texto no dice
> 'tuyos'.

### `_apply_septimo_sello_convert` — línea 966

> Convertir + Fuerza 0 (Séptimo Sello, 2026-09-20) — 'Convertir'
> estándar del proyecto (is_converted + KeywordManager.silence_card, ver
> TargetedEffectExecutor._execute_targeted_convert()) NO fuerza Fuerza a 0
> ('conserva tipo/coste/Fuerza' según su propio docstring); esta carta
> exige explícitamente 'de Fuerza 0' además, así que se agrega un
> modificador STRENGTH separado con operation='set' (soportado por
> ModifierRegistry._apply_operation(), no usado hasta ahora en el
> proyecto) en vez de 'add'. Duración UNTIL_LEAVES (no PERMANENT — PERMANENT
> dura 'mientras la FUENTE esté en juego', pero Séptimo Sello es un
> Talismán que se va al Cementerio apenas resuelve; UNTIL_LEAVES ata la
> duración al OBJETIVO, que es lo que corresponde a un Convertir de
> verdad: dura hasta que la carta convertida sale de juego).

### `try_execute_septimo_sello_pattern` — línea 998

> 'No puede ser Anulado. Convierte un Oro y hasta una carta oponente de
> cada coste en cartas del mismo tipo, de Fuerza 0 y sin habilidad. Una
> carta que controles gana Indestructible e Indesterrable. Roba dos
> cartas o tu oponente Bota una carta por cada Sello en tu Cementerio,
> hasta siete.' (Séptimo Sello, 2026-09-20) — el único de los 7 SIN
> cláusula 'busca un Sello'. 'No puede ser Anulado' — mismo motivo que
> Sexto Sello (protección estática genérica, sin código aparte aquí).
> 'Hasta una carta oponente de CADA coste' — recorre los costes DISTINTOS
> presentes entre las cartas oponentes en juego (no solo Aliados — el
> texto no dice 'Aliado', cualquier tipo) y convierte hasta una por cada
> valor de coste, eligiendo cuál si hay más de una al mismo coste — sin
> precedente exacto en el proyecto (_select_convert_target() es de UN
> objetivo, coste ≤N; aquí es potencialmente MUCHOS objetivos, uno por
> cada coste exacto distinto).

### `try_execute_septimo_sello_pattern` — línea 1020

> 2026-10-05, mismo bug que Cuarto Sello: gold_cards es global, hay que
> filtrar por owner_id para que "own_oros" sea de verdad el Oro propio.

### `try_execute_search_up_to_n_castillo_and_or_cementerio_play_discount_pattern` — línea 1090

> 'Puedes buscar en tu Castillo y/o Cementerio hasta dos Armas. Puedes
> jugarlas reduciendo su coste en un Oro, hasta un mínimo de 1, y/o
> ponerlas en tu mano' (Arturo de Bretaña, id 21135 — 2026-10-11, texto de
> la API de ShadowForge vía cache). Antes no lo tomaba nadie: el regex
> genérico de SEARCH dice 'busca en', no 'buscar en'. Selector de ambas
> zonas a la vez, se pueden mezclar (a pedido del usuario); por cada carta,
> jugarla con el descuento o dejarla en la mano.

## `scripts/core/effects/triggers/ShuffleDrawPatterns.gd`

### `(nivel de archivo)` — línea 2

> ShuffleDrawPatterns — 4 de 7 mitades de LookAndPlayResolver.gd, dividido por
> tamaño el 2026-09-06 ("módulos gordos"). Cubre combos de Barajar/Robar sobre
> recursos propios (sin apuntar al oponente): Caín (x2), vision heroica, el
> caleuche, manuel rodriguez (ataca solo), amazona desafiante, Abrazo de
> Maipú, Príncipe Orión, blanca nieves, kaitai, rafael, Escarapela Nacional,
> Tótem del Dragón Ancestral. Llamada solo desde LookAndPlayResolver.gd
> (facade) — ver ese archivo para la lista completa de las 7 mitades
> hermanas.

### `try_execute_shuffle_or_draw_choice_pattern` — línea 50

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_cain_damage_shuffle_search_pattern` — línea 96

> 2026-09-14, a pedido del usuario: click directo (open_reveal_picker)
> en vez del modal de lista viejo.

### `try_execute_cain_damage_shuffle_search_pattern` — línea 116

> 2026-09-14, a pedido del usuario: click directo (open_reveal_picker)
> en vez del modal de lista viejo.

### `try_execute_shuffle_cost_max_three_pattern` — línea 148

> 'Baraja una carta de coste 3 o menos o Anula un Talismán oponente'
> (vision heroica, 2026-09-06) — SOLO la primera rama ('Anula un
> Talismán oponente' es contramagia real de pila, no implementada); no
> se ofrece elección, siempre Baraja.

### `try_execute_shuffle_cost_max_three_pattern` — línea 159

> 2026-10-14 (StackAnnul): si hay un Talismán oponente en la pila, se
> puede elegir Anularlo.

### `try_execute_shuffle_cost_max_three_pattern` — línea 171

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_shuffle_cost_max_two_draw_two_pattern` — línea 187

> 'Elige un efecto: - En respuesta a que se juegue una carta sin pagar
> su coste... - Baraja una carta de coste 2 o menos y Roba dos cartas'
> (el caleuche, 2026-09-06) — SOLO se implementa la segunda rama (la
> primera depende de la ventana de respuesta reactiva, que no existe);
> no se ofrece elección, se resuelve siempre como la rama B.

### `try_execute_shuffle_cost_max_two_draw_two_pattern` — línea 199

> Rama A (2026-10-14, StackAnnul): en la pila, una carta oponente jugada
> sin pagar su coste o que no puede ser Anulada: entra sin habilidad por
> el turno; si es Talismán, se resuelve sin efecto.

### `try_execute_shuffle_cost_max_two_draw_two_pattern` — línea 221

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_attacks_alone_draw_pattern` — línea 240

> 'Cuando ataque solo, Roba una carta...' (manuel rodriguez, 2026-09-04)
> — condición 'ataca solo' (único atacante declarado este combate), sin
> precedente en el motor. Solo cubre el Robo; la sobretasa 'a tu
> oponente le cuesta un Oro adicional afectar a tus Aliados' queda fuera
> (demasiado ambigua qué cuenta como 'afectar' para modelarla ahora).

### `try_execute_shuffle_one_in_play_and_four_cemetery_pattern` — línea 259

> 'Cuando entra en juego o en tu Fase Final, Baraja hasta una carta de
> coste 2 o menos y hasta cuatro cartas de los Cementerios' (amazona
> desafiante, 2026-09-06) — solo la parte de ETB; el repetir esto TODAS
> las Fases Finales (no solo la primera vez) no está implementado (no
> hay un trigger recurrente de Aliado para Fase Final todavía, solo el
> de un uso de EffectController.schedule_next_final_phase_effect()).

### `try_execute_shuffle_one_in_play_and_four_cemetery_pattern` — línea 284

> 2026-09-13, a pedido del usuario: click directo en vez de los modales
> de lista viejos.

### `try_execute_shuffle_any_cemetery_or_exile_into_castillo_then_draw_pattern` — línea 324

> 'Baraja cualquier cantidad de cartas de tu Cementerio y Destierro en
> tu Castillo y Roba tres cartas' (Abrazo de Maipú, 2026-09-04) — 'tu'
> restringe el pool al propio Cementerio+Destierro (a diferencia de 'los
> Cementerios'), cada carta vuelve a SU Castillo (siempre el mismo,
> propio, aquí).

### `try_execute_shuffle_any_cemetery_or_exile_into_castillo_then_draw_pattern` — línea 335

> 2026-09-13, a pedido del usuario: click directo combinando Cementerio Y
> Destierro propios en un solo popup (zone_type="cemetery_and_exile",
> nuevo en ZoneViewerModule.open_cemetery_target_picker()), con botón
> "Seleccionar todo" — el texto real es 'cualquier cantidad', sin tope,
> y clickear una por una sería tedioso con muchas cartas acumuladas.

### `try_execute_shuffle_banish_four_cemeteries_pattern` — línea 365

> 'Baraja y/o Destierra hasta cuatro cartas de los Cementerios. Si
> Barajaste y/o Desterraste cuatro cartas de distinto tipo, genera un
> Oro por el turno' (Ofrendas al Dragón, 2026-09-04) — solo la primera
> oración; el bono condicionado a 4 tipos distintos NO implementado
> (_resolve_armeria_barajar_desterrar() no informa qué tipos se
> eligieron).

### `try_execute_shuffle_banish_cemeteries_then_destroy_or_draw_pattern` — línea 384

> 'Cuando entra en juego, Baraja y/o Destierra hasta tres cartas de
> los Cementerios y elige entre Destruir una carta de coste 2 o menos o
> Robar dos cartas' (Tótem del Dragón Ancestral, 2026-09-04).

### `try_execute_draw_or_raise_cemetery_ally_pattern` — línea 413

> 'Cuando entra en juego, Roba una carta o sube un Aliado de tu
> Cementerio a tu mano' (Príncipe Orión, 2026-09-04) — elección A/B.

### `try_execute_draw_or_raise_cemetery_ally_pattern` — línea 429

> 2026-09-13, a pedido del usuario: click directo en el propio
> Cementerio en vez del modal de lista viejo.

### `try_execute_shuffle_up_to_one_ally_pattern` — línea 450

> 'Cuando entra en juego, Baraja hasta un Aliado' (blanca nieves,
> 2026-09-04) — objetivo opcional (0 o 1), cualquier Aliado en juego.

### `try_execute_shuffle_up_to_one_ally_pattern` — línea 463

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_shuffle_up_to_one_ally_pattern` — línea 465

> Sin ventana genérica aquí (2026-09-09): return_to_deck() ya consulta
> Prevención adentro por su cuenta.

### `try_execute_draw_then_discard_pattern` — línea 478

> 'Roba N carta(s) y Descarta M carta(s)' (2026-09-04, p.ej. kaitai:
> 'Cuando entra en juego, Roba tres cartas y Descarta dos cartas') — el
> genérico extract_action() solo reconoce la PRIMERA acción de una
> oración compuesta, así que sin esto el Descarte se perdía siempre.

### `try_execute_shuffle_non_gold_or_draw_two_pattern` — línea 511

> 'Cuando entra en juego, Baraja hasta una carta que no sea Oro o Roba
> dos cartas' (rafael, 2026-09-04) — elección A/B; 'hasta una' = el
> Barajar es opcional (cancelar el picker = 0 elegidas).

### `try_execute_shuffle_non_gold_or_draw_two_pattern` — línea 528

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `try_execute_shuffle_non_gold_or_draw_two_pattern` — línea 531

> Sin ventana genérica aquí (2026-09-09): return_to_deck() ya consulta
> Prevención adentro por su cuenta.

### `try_execute_draw_or_search_ally_or_gold_pattern` — línea 546

> 'Roba dos cartas o busca un Aliado u Oro en tu Castillo y ponlo en
> tu mano' (2026-09-04, p.ej. Escarapela Nacional) — elección A/B.

## `scripts/core/effects/triggers/TalismanSearchPatterns.gd`

### `(nivel de archivo)` — línea 2

> TalismanSearchPatterns — "busca un Talismán en un Castillo y juégalo"
> (2026-10-14, revisión del mazo 170, docs/revision-mazo-170.md).
>
> Reina Nyssara: "busca un Talismán en un Castillo y juégalo reduciendo su
> coste en un Oro, hasta un mínimo de 0 y Roba dos cartas".
> Nyssara Cautiva: "puedes buscar un Talismán en un Castillo, juégalo pagando
> su coste y Roba una carta".
>
> Se elige en el selector del tablero (los dos Castillos, o solo el tuyo si
> dice "tu Castillo"); solo son elegibles los Talismanes que puedes pagar. El
> Talismán se juega bajo tu control pero sigue siendo de su dueño (vuelve a
> SU Cementerio). Se usa con preload, sin class_name global (ver §54).

## `scripts/core/effects/triggers/TargetedEffectExecutor.gd`

### `(nivel de archivo)` — línea 3

> TargetedEffectExecutor — Ejecución de acciones ETB extraídas por texto
> (extract_action()) que requieren elegir UN objetivo con clic (destruir,
> desterrar, anular, silenciar, buff/debuff, devolver al mazo) y los
> patrones compuestos "puedes [costo] y Roba N" / weapon-discount-draw /
> shuffle-for-draw. Opera sobre TriggerSystem via _main.
> Extraído de TriggerSystem.gd (Fase 4 de reestructuración). Los patrones
> "mira/muestra N... elige qué hacer con ellas" (Signo Amarillo, Tangata
> Manu, Presente, Perder la Razón) se sacaron aparte a
> LookAndPlayResolver.gd (2026-08-28, "módulos gordos" — este archivo solo
> sigue en TriggerSystem._targeted_executor; el nuevo vive en
> TriggerSystem._look_and_play).
> Dividido en dos slices más por tamaño (2026-09-06, "módulos gordos"):
> WeaponSearchShuffleExecutor.gd (cluster compuesto Buscar/Barajar-para-robar/
> Arma-con-descuento) y MiscTargetedPatterns.gd (patrones sueltos:
> búsqueda de Cementerio a mano, destierro combinado de ambos Cementerios,
> refresco visual de "pierde habilidad" por nombre). El dispatcher
> (execute_parsed_action) y el toolkit genérico de selección de UN objetivo
> (_select_*_target, _target_text_denies, _choose_search_zone_owner,
> _select_hand_cards_for_discard, y los _execute_targeted_* de un solo
> objetivo) se quedaron AQUÍ sin extraer a propósito: es el cluster de mayor
> tráfico externo de todo este archivo (decenas de call sites en
> PreventionAbilityHandler_*.gd, SearchAbilityHandler_*.gd,
> BanishOpponentPatterns.gd, GoldConversionPatterns.gd,
> LookRevealPatterns.gd, ShuffleDrawPatterns.gd, SearchOwnZonePatterns.gd,
> TriggerResolution.gd), así que moverlo no reducía riesgo — solo lo
> concentraba en otro archivo.

### `execute_parsed_action` — línea 61

> Confirmación visual de que esta carta está disparando/activando una
> habilidad (a pedido del usuario) — punto único para ambos casos:
> disparadas (llamado desde _collect_triggers_for_event) y activadas
> (llamado desde ActionPipeline._resolve_ability()).

### `execute_parsed_action` — línea 70

> ActionModule es autoload — siempre existe, sin necesidad de
> get_node_or_null/has_method (2026-08-28, "módulos gordos" punto
> 1: esos guards solo escondían un fallback roto, ver abajo).

### `execute_parsed_action` — línea 127

> Igual que LOOK pero es información pública (DAR): ambos
> jugadores "ven" las cartas reveladas, no solo el controlador.
> El overlay es local (SelectionManager no distingue jugadores en
> red), así que la diferencia real es el título mostrado.
>
> A diferencia de LOOK, aquí SÍ hay que barajar después (2026-08-26,
> regla del usuario): "Muestra/Revela del tope" sin instrucción
> de orden deja saber a los dos jugadores qué cartas y en qué
> orden están arriba del mazo — barajar borra esa ventaja, cosa
> que "Mira" no necesita porque es privado y deja reordenar.

### `_select_ally_target` — línea 175

> Pide al jugador elegir un Aliado en juego (propio o enemigo) con clic,
> reutilizando el modo de selección que ya usa 'colocar Oro'
> (CardInteractionModule.is_selecting_target). Devuelve null si no hay
> forma de abrir el modo de selección (Main/CardInteractionModule ausentes).
> source_card (2026-08-30, p.ej. Aho: 'el portador gana... y no puede ser
> afectado por Aliados oponentes') — si se pasa, se excluyen los Aliados
> inmunes a esta fuente en particular (ver _is_immune_to_enemy_ally).

### `_select_ally_target` — línea 190

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_select_ally_target` — línea 195

> Inmunidad a Talismanes otorgada por otra carta (2026-09-02, p.ej.
> Espíritu Kotaix: "Tus Aliados ganan... y no pueden ser afectados
> por Talismanes") — a diferencia de _target_text_denies(), que solo
> ve el texto propio del objetivo, esto consulta los modificadores
> de protección registrados por AURAS (ContinuousEffectManager).
> Solo aplica cuando la fuente de este efecto es un Talismán — un
> Aliado inmune a Talismanes sigue siendo objetivo legal de
> Silenciar/Convertir/etc. de otras cartas.

### `_select_ally_target` — línea 206

> "No pueden ser afectados por habilidades de cartas fuera del
> juego mientras atacan" (2026-09-03, Trono del Dragón, condicional
> a 3+ Aliados de la misma Raza — la parte racial ya la resuelve el
> condition Callable del modificador PROTECTION registrado en
> ContinuousEffectManager). 'Mientras atacan' es un estado POR
> CARTA que no tiene sentido meter en ese Callable (no recibe el
> objetivo), así que se chequea aquí, en el único punto real donde
> se elige un objetivo para una habilidad de OTRA carta. 'Fuera del
> juego' = la fuente de ESTE efecto está en Mano/Destierro/
> Cementerio/Castillo (mismo criterio ya usado para Signo Amarillo,
> ver ResponseWindowHandler.gd/TriggerResolution.gd).

### `_select_annul_target_cost_filter` — línea 228

> Como _select_ally_target() pero para 'una carta' genérica en juego
> (no solo Aliados) con tope de coste — 2026-08-30, p.ej. Paladín
> Bestiarium: 'Anular una carta de coste 1 o menos'. Incluye Aliados,
> Armas y Tótems en cualquiera de las tres zonas de campo de ambos
> jugadores; no Oro (no tiene sentido 'anular' un Oro) ni Talismanes
> (ya se resolvieron al jugarse, no quedan en juego).

### `_select_annul_target_cost_filter` — línea 240

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_select_annul_target_cost_filter` — línea 243

> get_modified_cost(), no card_cost crudo (2026-09-04) — ver nota en
> _select_convert_target() más arriba.

### `_select_destroy_target_cost_filter` — línea 250

> Como _select_banish_target_cost_filter() pero para Destruir (va al
> Cementerio) — 2026-09-04, p.ej. gran kraken: 'Destruir una carta de
> coste 3 o menos'.

### `_select_destroy_target_cost_filter` — línea 259

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_select_banish_target_cost_filter` — línea 267

> Como _select_annul_target_cost_filter() pero para Desterrar (en vez de
> Anular/destruir) — 2026-09-04, p.ej. akuma el terrible: 'Destierra una
> carta de coste 2 o menos'. Mismo alcance (Aliados/Armas/Tótems en
> cualquier zona de campo de ambos jugadores, filtro por coste efectivo).

### `_select_banish_target_cost_filter` — línea 277

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_select_ally_or_totem_target` — línea 285

> Como _select_ally_target() pero incluye Tótems además de Aliados —
> 2026-08-30, p.ej. Aho: 'Destierra un Aliado o Tótem'. Cualquiera de los
> dos jugadores, en cualquiera de sus tres zonas de campo.

### `_select_ally_or_totem_target` — línea 294

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_is_immune_to_enemy_ally` — línea 302

> 'No puede ser afectado por Aliados oponentes' (2026-08-30, p.ej. Aho —
> el Arma le da esta protección a su portador). Solo bloquea cuando la
> FUENTE del efecto es un Aliado enemigo del target (un Arma/Talismán/Oro
> rival, o un Aliado propio, siguen afectándolo igual — el texto protege
> específicamente de Aliados oponentes, no de todo). La protección puede
> estar en el propio target o en un Arma que tenga equipada.

### `_execute_targeted_buff` — línea 344

> Prevención reactiva real (2026-09-09 — Estaca) — solo aplica a debuffs
> (un buff no es un efecto hostil que valga la pena bloquear).

### `_select_hand_cards_for_discard` — línea 439

> Pide al jugador humano elegir qué cartas descartar de su propia mano —
> click directo sobre las cartas reales (2026-09-13, a pedido del usuario,
> ver arquitectura.md §10.16), en vez del modal de lista viejo. Costo TODO
> o NADA de 'amount' cartas exactas (mismo criterio que Belta, §10.19):
> si el jugador elige menos (ESC), se devuelve Array vacío — ningún
> llamador de los 6 que reusan esta función debe tratar un resultado
> parcial como válido.

### `_select_hand_cards_for_discard` — línea 446

> 2026-09-14, bug real reportado por el usuario: _main aquí ES TriggerSystem
> (ver TriggerSystem._ready(): '_targeted_executor.setup(self)'), no el
> Main real — _main._card_interaction tiraba 'Invalid access to property
> or key' porque esa propiedad no existe en TriggerSystem.gd (mismo
> patrón de bug documentado en arquitectura.md §2). El resto de esta
> clase ya resuelve esto bien con 'var main := _main.get_node_or_null(
> "/root/Main")' antes de usar main._card_interaction (ver _select_
> banish_target_cost_filter() más arriba) — esta función se saltó ese
> paso.

### `_select_hand_cards_for_discard` — línea 458

> cancellable=false (2026-09-13): este descarte es MANDATORIO (sin
> "puedes" en las llamadoras) — ESC no debe dejar al jugador esquivarlo,
> a diferencia del resto de conversiones de esta sesión que sí son
> costos opcionales.

### `_execute_targeted_convert` — línea 513

> 'Convertir un Oro o una carta de coste N o menos en una carta del
> mismo tipo sin habilidad' (DAR Sección 8 - Convertir, p.ej. Capitán
> O'Brien, 2026-08-28). Misma carta física — solo pierde la habilidad,
> conserva tipo/coste/Fuerza. Reusa el flag Card.is_converted (ya
> establecido por Signo Amarillo — ver ResponseWindowHandler.gd, es el
> que da el giro visual de 180° y "vacía" la caja de texto) más
> await KeywordManager.silence_card() para que de verdad deje de disparar sus
> habilidades — is_converted por sí solo es solo visual, lo que consulta
> TriggerSystem._check_trigger_conditions() es is_silenced().

### `_select_convert_target` — línea 540

> Objetivo válido para Convertir: un Oro, o cualquier carta (Aliado,
> Tótem, Arma) de coste ≤ max_cost, EN JUEGO (propio o enemigo) — usa
> current_zone en vez de coincidir contenedor padre para que un Arma ya
> equipada (hija de su portador, no de una línea) también cuente.
> source_card (2026-08-30, p.ej. Aho) — excluye Aliados inmunes a esta
> fuente, ver _is_immune_to_enemy_ally.

### `_select_convert_target` — línea 564

> get_modified_cost(), no card_cost crudo (2026-09-04, a pedido del
> usuario): una carta YA EN JUEGO puede tener su coste reducido de
> forma continua (p.ej. Samael, 'las cartas oponentes en juego
> reducen su coste en un Oro') — el filtro tiene que verlo.

### `_select_convert_target` — línea 570

> Chequeo defensivo ANTES de abrir la selección (2026-09-03, bug
> reportado: sin ningún Oro en juego en ese momento — max_cost=-1
> sentinel, solo Oro qualifica — el picker se abría de todos modos con
> CERO candidatos posibles, dejando is_selecting_target pegado para
> siempre; el jugador ni siquiera podía declarar atacantes después,
> porque cada click le caía a este filtro colgado. Mismo criterio ya
> aplicado a _select_weapon_wielder()/_get_eligible_weapon_wielders()."""

### `_choose_search_zone_owner` — línea 603

> Elige a quién buscarle cuando el texto es ambiguo ('un Castillo', sin
> posesivo — p.ej. Rey de Amarillo) (2026-08-25). Para Castillo, click
> directo sobre el Panel del Castillo propio/rival en el tablero
> (2026-08-30, a pedido del usuario); Cementerio sigue con el popup de 2
> botones — no tiene un Panel fijo equivalente en el tablero. Devuelve el
> player_id elegido; declinar/cerrar = el propio.
> 'action_verb' personaliza el texto del prompt (2026-09-06, bug real
> reportado por el usuario: Sherlock Holmes CONVIERTE cartas del tope de
> un Castillo, no las busca — el prompt genérico decía 'buscar' igual,
> confundiendo la acción real).

### `_execute_targeted_annul` — línea 661

> Protección otorgada por OTRA carta (2026-09-02, Crono Diamante: "tu
> primer Aliado o Tótem de coste 2 o más no puede ser Anulado") — a
> diferencia de _target_text_denies(), que solo mira el texto propio
> del objetivo, esto es un flag que GoldManager._apply_crono_diamante_
> annul_protection() marcó al jugarlo, si su controlador tenía Crono
> Diamante en Reserva en ese momento.

### `_execute_targeted_annul` — línea 677

> "destiérralo"/"destiérrala" (2026-09-08, mismo hueco encontrado en
> GoldManager._play_talisman(): el pronombre enclítico "-lo"/"-la" pegado
> al verbo lleva tilde en español correcto, y "destierr" sin tilde no
> matchea esa forma) — se agrega "destiérr" por las dudas, igual que ahí.

### `_execute_targeted_annul` — línea 683

> Anular solo lo previene Drácula (tag "annul", con su propio chequeo de
> coste 1 en el registro), NUNCA Estaca — su propio texto no cubre
> Anular/Cancelar (2026-09-09, bug real de alcance encontrado en
> auditoría: antes esto pasaba por destroy()/banish() con
> can_be_prevented=true, dejando que Estaca bloqueara una Anulación por
> accidente). can_be_prevented=false en los dos llamados de abajo para
> que el chequeo genérico de "destroy"/"exile" no vuelva a preguntar.

## `scripts/core/effects/triggers/TotemAbilityPatterns.gd`

### `(nivel de archivo)` — línea 2

> TotemAbilityPatterns — Patrones "try_execute_*_pattern" para Tótems
> detectados sin cobertura en la auditoría de 539 cartas (2026-09-20, ver
> arquitectura.md). Mismo criterio que las 7 mitades de LookAndPlayResolver.gd
> (detección por substring, no por nombre de carta) pero en su propio archivo
> porque ninguna de esas 7 mitades cubría este tipo de carta todavía.
> Instanciado directo en TriggerSystem._ready() como _totem_patterns (mismo
> patrón que _convert_misc_resolver/_draw_shuffle_resolver), llamado desde
> TriggerResolution.gd en los branches on_enter_play/on_leave_play.

### `(nivel de archivo)` — línea 14

> kotoku-in (2026-09-20): "hacer que el próximo Talismán que juegue tu
> oponente este turno se resuelva sin efecto" — flag de una sola vez por
> controller_id afectado, consumida por TriggerSystem.resolve_talisman() al
> principio de la resolución (mismo canal de retorno que Anular/Cancelar:
> true = no resuelve, va directo al Cementerio). Se guarda el número de
> turno junto al flag para que nunca sobreviva al cambio de turno si el
> rival no llega a jugar ningún Talismán (chequeado en el consumo, no hace
> falta limpieza activa en TurnManager).

### `(nivel de archivo)` — línea 24

> metropolitan (2026-09-20): "convertirlo en un Aliado con Fuerza 3 hasta la
> Fase Final" — Card -> modifier_id de la Fuerza fija, para revertir tipo/
> zona/modificador cuando la fase cambie a FINAL. GameManager.phase_changed
> se conecta una sola vez (guard _metropolitan_signal_connected) la primera
> vez que se usa esta conversión, no en setup() (evita un listener global
> permanente para una carta que puede no estar nunca en la partida).

### `try_execute_arco_del_triunfo_pattern` — línea 85

> "Su daño de combate es enviado al Destierro" — infraestructura
> MUERTA encontrada (2026-09-20, mismo hallazgo que Segundo Sello con
> Card.damage_goes_to_exile, pero esta vez el otro camino que
> BattleManager._check_damage_to_exile_effect() ya consultaba y
> nadie registraba nunca: TriggerSystem.get_active_continuous_
> effects("damage_to_exile"), filtrado por 'targets contiene
> player_id' donde player_id es SIEMPRE el DEFENSOR (quien recibe el
> daño) — no el atacante. Como esta aura cubre TODOS los Aliados
> propios, presentes y futuros, sin necesitar taggear cada Card, el
> target correcto es el oponente actual (1 - controller_id): "cuando
> el oponente reciba daño de mis Aliados, va al Destierro".

### `try_execute_kotoku_in_enter_pattern` — línea 150

> 2026-10-12 (§57): sin elección de por medio — sirve igual para el
> jugador 1 (Remoto o bot), con su propio Oro Virtual restringido.

### `try_execute_kotoku_in_vigilia_pattern` — línea 193

> 'En tu Vigilia, una vez por turno, puedes Destruir una carta de coste
> 2 o menos o hacer que el próximo Talismán que juegue tu oponente este
> turno se resuelva sin efecto' (kotoku-in, "Espíritu Samurái"). Habilidad
> ACTIVADA — llega aquí vía TriggerSystem.resolve_ability_effect() (el
> mismo _resolve_look_and_play_patterns() que usan los triggers, ver
> arquitectura.md 2026-08-27), el botón y el cupo 'una vez por turno' ya
> los resuelve genéricamente UniversalCardParser/ActionPipeline.
> activate_ability() antes de llegar aquí — no hay que reimplementarlos.
>
> La opción 'destruye coste 2 o menos' es directa (ActionModule.destroy());
> la opción 'próximo Talismán rival sin efecto' es una bandera de una sola
> vez consumida en TriggerSystem.resolve_talisman() (ver
> consume_kotoku_in_talisman_fizzle() arriba) — sin precedente de un
> 'contador de anulación diferida' en el proyecto antes de esto.
>
> Guardia 'genera un oro por el turno' (2026-09-20, bug real encontrado en
> revisión de código, no reportado por el usuario): esta función SÍ está en
> la lista compartida de _resolve_look_and_play_patterns() porque la
> activación real necesita estarlo (StackStepResolver._resolve_ability() la
> invoca con el texto YA AISLADO a esta sola cláusula) — pero esa misma
> lista compartida también se recorre durante on_enter_play con el texto
> COMPLETO de kotoku-in (sin aislar), donde SÍ aparece su otra cláusula
> 'genera un oro por el turno para jugar cartas que no sean Talismán'. Sin
> esta guardia, jugar kotoku-in disparaba esta elección de inmediato en vez
> de esperar a una activación real en Vigilia (mismo patrón de bug ya
> corregido en sable_corto_vigilia, ver WeaponAbilityPatterns.gd).

### `try_execute_metropolitan_vigilia_convert_pattern` — línea 245

> 'En tu Vigilia, puedes convertirlo en un Aliado con Fuerza 3 hasta la
> Fase Final' (metropolitan). Habilidad ACTIVADA — mismo camino genérico
> que kotoku-in arriba. Mecanismo de conversión Tótem→Aliado calcado del
> precedente real ya existente en el proyecto (ConvertAndMiscResolver.
> try_execute_mill_convert_to_ally_pattern, Sherlock Holmes: mover de
> contenedor, card_type = ALIADO, set_zone(LINEA_DEFENSA), modificador de
> Fuerza fija operation='set') — la única diferencia real es que aquí la
> conversión es TEMPORAL (revierte en la Fase Final, no permanente), por
> eso el modificador se registra con source=card (para poder ubicarlo por
> source_id al revertir) y se guarda el Node en _metropolitan_pending_
> reverts hasta que GameManager.phase_changed emita FINAL.
>
> Guardia 'genera un oro para aliados' (2026-09-20, bug real encontrado en
> revisión de código, no reportado por el usuario): mismo motivo exacto que
> la guardia de try_execute_kotoku_in_vigilia_pattern() de arriba — esta
> función está en la lista compartida de _resolve_look_and_play_patterns()
> porque la activación real la necesita ahí (texto ya aislado), pero esa
> misma lista se recorre también durante on_enter_play con el texto
> COMPLETO de metropolitan (sin aislar), donde SÍ aparece su otra cláusula
> de entrada ('genera un oro para Aliados de coste 2 o más o Roba dos
> cartas'). Sin esta guardia, jugar metropolitan lo convertía en Aliado de
> inmediato en vez de esperar una activación real en Vigilia.

## `scripts/core/effects/triggers/TriggerResolution.gd`

### `resolve_next_trigger` — línea 66

> waiting_for_responses YA NO se emite aquí (2026-09-19, §10.53) — su único
> oyente real, ResponseWindowHandler._on_trigger_waiting_for_responses()
> (el diálogo viejo de Signo Amarillo), cancelaba vía TriggerSystem.
> cancel_current_trigger()/pending_cancel_callback, que solo
> _wait_for_response_window() leía — con open_response_window() reemplazándola
> más abajo, ese flag ya no lo consume nadie, así que ese diálogo viejo
> quedaría clickeable pero roto (el 'Sí, cancelar' no cancelaría nada de
> verdad). Signo Amarillo sigue ofreciéndose igual, por el camino nuevo:
> ResponseWindowHandler._on_step_d_waiting()/_offer_signo_amarillo_for_step_d(),
> que ya escucha ActionPipeline.step_d_waiting — la señal que SÍ emite
> open_response_window() de abajo para CUALQUIER objeto de la Pila,
> trigger o no. Ver docstrings actualizados de _wait_for_response_window()
> y _on_trigger_waiting_for_responses() (huérfanos, no borrados).

### `resolve_next_trigger` — línea 80

> 2026-09-19 (arquitectura.md §10.53, a pedido explícito y repetido del
> usuario: "que el sistema se abra por carta jugada o habilidad activada
> o disparada"). Antes esto llamaba _wait_for_response_window(), que —
> a propósito, desde 2026-08-17, cuando el bot no tenía NINGUNA lógica de
> respuesta real — resolvía el trigger casi al instante sin abrir ninguna
> ventana de prioridad real, salvo el caso puntual de Signo Amarillo (ver
> _wait_for_response_window() más abajo, que queda sin llamador después
> de este cambio — no se borró, ver su propio docstring actualizado).
> Ahora reusa el mismo mecanismo genérico que ya usan los ~40 patrones
> "mira/muestra" y CUALQUIER carta jugada (GoldManager._trigger_enter_play(),
> EasyBotController, §10.53) — TriggerSystem.open_response_window(), Pila
> de Respuesta Universal: abre un objeto no-op real en ActionPipeline, así
> que el rival (humano o bot) recibe el mismo Paso D real, con el mismo
> brillo celeste/botón de Anular (§10.51) y el mismo auto-pase (§10.52)
> que cualquier otro objeto de la Pila — para CUALQUIER trigger, no solo
> los ~40 patrones que ya lo llamaban a mano.
>
> 2026-10-12 (§59, opción B elegida por el usuario: el rival responde
> DESPUÉS de que se declaran los objetivos): la ventana ya NO se abre
> aquí adelante. El efecto arranca con la ventana "pendiente" en
> EffectContext; la abre el propio patrón tras declarar (su llamada a
> open_response_window() pasa a ser LA ventana) o, si no la pide,
> EffectContext.ensure_window() justo antes de su primera acción real.
> Antes el rival pasaba hasta 3 veces por la misma carta.

### `resolve_next_trigger` — línea 108

> awaiting_response sigue en true durante TODA la ejecución del efecto
> (2026-09-10, bug real reportado por el usuario: bucle en Fase Final con
> Biblioteca de Caballería, mismo patrón con Drácula en Vigilia) — la
> Pila de Respuesta Universal (open_response_window(), agregada hoy a
> ~40 patrones de trigger) abre una ventana de prioridad REAL desde
> DENTRO de _execute_trigger_effect(). Antes, awaiting_response se
> apagaba AQUÍ ARRIBA, antes de ejecutar el efecto — así que esa ventana
> anidada quedaba fuera de la guardia que PhaseFlowController.
> _on_priority_both_passed_main() ya tenía para "no reacciones a una
> ventana anidada de un trigger, es suya" (comentario propio de ese
> archivo). El 'ambos pasaron' de la ventana nueva SÍ llegaba a la
> lógica de fin de fase, causando resoluciones dobles.
> Matriz V (2026-10-14): habilidades de cartas de coste 0 o 1 del rival
> solo se disparan si Destierra una carta de su mano.

### `resolve_next_trigger` — línea 125

> Mecha-Daikaiju (2026-10-17): pagar un Oro para usar habilidades disparadas.

### `_resolve_look_and_play_patterns` — línea 186

> Prueba en orden los patrones compuestos "muestra/mira N..." (cada uno
> con su propio regex específico, así que reciben el texto COMPLETO, no
> aislado a una oración — ver historial de por qué) y si ninguno matchea
> cae al genérico extract_action() + execute_parsed_action() sobre el
> texto aislado. Compartido entre la resolución de habilidades disparadas
> (on_enter_play/on_ally_enters de Aliados/Armas/Oro) y la resolución
> directa de Talismanes (TriggerSystem.resolve_talisman(), que NO pasa
> por la cola de triggers — 2026-08-27, a pedido del usuario: 'los
> Talismanes no disparan, resuelven').
> Returns: true si algo se ejecutó.

### `_resolve_look_and_play_patterns` — línea 196

> Efecto compilado por piezas (2026-10-12, arquitectura.md §54): si
> EffectCompiler entiende TODO el texto aislado y EffectInterpreter sabe
> ejecutar todos sus pasos, se resuelve por ahí; si no, sigue la cadena
> de patrones de siempre. Va primero a propósito: la cadena vieja busca
> sobre el texto COMPLETO y gana la primera coincidencia, que puede
> quedarse con una parte del efecto y saltarse el resto.
> Anular/Cancelar sobre la pila real (2026-10-14, StackAnnul): antes que
> todo, con el texto completo — si no, "Anula X" caía en patrones que
> destruían una carta en juego o en otra parte del texto (Sacrificio
> Solar barajaba el mazo).

### `_resolve_look_and_play_patterns` — línea 209

> Azi del Abismo (2026-10-17): Descartar para convertirse en Oro hasta tu
> próximo turno — antes del intérprete, que solo veía "Descarta una".

### `_resolve_look_and_play_patterns` — línea 213

> Padre Dagón (2026-10-17): la mitad activada, global.

### `_resolve_look_and_play_patterns` — línea 216

> Plaga de Ratas (2026-10-17).

### `_resolve_look_and_play_patterns` — línea 219

> Kaitai (2026-10-17): su habilidad de Fase Final.

### `_resolve_look_and_play_patterns` — línea 222

> Vlad el Empalador, Dhampir (2026-10-17).

### `_resolve_look_and_play_patterns` — línea 225

> Noé (2026-10-17).

### `_resolve_look_and_play_patterns` — línea 228

> Mazos guardados (2026-10-18): Aegishjalmur...

### `_resolve_look_and_play_patterns` — línea 231

> Golpe Solar (2026-10-18, a pedido del usuario): antes del intérprete,
> que lo resolvía en el orden impreso (descartar primero). Su patrón elige
> primero el objetivo a Barajar, luego el descarte y el Aliado.

### `_resolve_look_and_play_patterns` — línea 238

> "Mira N cartas del tope/fondo de un Castillo" (2026-10-13, §69): una sola
> ventana para repartir y ordenar (CastleLook.gd). Solo si entiende todo el
> bloque; si no, sigue la cadena de siempre.

### `_resolve_look_and_play_patterns` — línea 243

> "Busca un Talismán en un Castillo y juégalo" (2026-10-14, Reina
> Nyssara, Nyssara Cautiva).

### `_resolve_look_and_play_patterns` — línea 247

> Mazo 170 (2026-10-14): Rey de los Loñolicos, Ursitoare, Nyssara Cautiva...

### `_resolve_look_and_play_patterns` — línea 250

> Sombrerero Loco (2026-10-14): elección en el tablero, sin popup.

### `_resolve_look_and_play_patterns` — línea 253

> Habilidades ACTIVADAS de Tótems (2026-09-20, arquitectura.md "539
> cartas sin cobertura") — llegan aquí también vía TriggerSystem.
> resolve_ability_effect() (mismo camino compartido que los triggers,
> ver ese comentario), así que se chequean primero, junto al resto.

### `_resolve_look_and_play_patterns` — línea 267

> Habilidades ACTIVADAS de Armas (2026-09-20, arquitectura.md "539
> cartas sin cobertura") — mismo camino compartido que las de Tótems
> arriba, cada una con su propia guardia 'el portador gana' contra el
> falso positivo de on_enter_play (ver comentarios en WeaponAbilityPatterns.gd).

### `_resolve_look_and_play_patterns` — línea 275

> Habilidades ACTIVADAS de Oros (2026-09-20, arquitectura.md "539 cartas
> sin cobertura") — mismo camino compartido que Tótems/Armas arriba,
> cada una con su propia guardia de texto contra el falso positivo de
> on_enter_play/on_turn_end (ver OroAbilityPatterns.gd).

### `_resolve_look_and_play_patterns` — línea 440

> Estos dos, a diferencia de todos los de arriba, chequean sobre el texto
> YA AISLADO al bloque de este trigger en particular (no el texto
> completo de la carta) — 2026-08-29: una carta puede tener el MISMO
> trigger repetido dos veces (Alicia en Wonderland), y este resolutor se
> llama una vez POR BLOQUE; si estos dos chequearan full_ability_text
> (que no cambia entre llamadas) se dispararían dos veces, una por cada
> bloque de la carta.

### `_resolve_look_and_play_patterns` — línea 495

> try_execute_banish_up_to_n_cemeteries_then_draw_pattern() ELIMINADA
> (2026-09-13) — código muerto, siempre interceptada antes por
> try_execute_banish_from_cemeteries_and_draw_pattern() (línea ~379,
> chequeo más suelto). Ver arquitectura.md §10.21.

### `_execute_trigger_effect` — línea 522

> Verificar si la carta tiene un handler ESPECÍFICO para este trigger
> (Card.effect_handlers) — 'handled' solo queda true si de verdad hizo
> algo. Antes, cualquier Card (TODAS tienen _on_trigger_event definido
> en la clase base) cortaba aquí sin importar el resultado, así que el
> fallback bueno de más abajo (aísla la oración correcta, reconoce
> SEARCH/DESTROY/BUFF/etc.) nunca se ejecutaba — Card._on_trigger_event()
> caía en su propio _resolve_default_effect(), un escaneo de palabras
> clave sobre el texto COMPLETO sin aislar por oración (2026-08-22: por
> esto Tyet, cuyo texto tiene 'busca un Arma...' Y 'Robar dos cartas' de
> una habilidad de Oro totalmente distinta más adelante, terminaba
> robando una carta en vez de buscar). _resolve_default_effect() se
> eliminó y _on_trigger_event() ahora marca no_handler=true cuando no
> hay handler específico, dejando pasar la ejecución hasta aquí.

### `_execute_trigger_effect` — línea 554

> Aislar la(s) oración(es) de ENTRA (2026-08-22, mismo bug que
> on_attack/on_damage_dealt de más abajo, nunca se había
> corregido aquí): una carta puede tener "Cuando entra en juego,
> X.\nEn tu Fase Final, Y." en el mismo bloque — sin aislar,
> extract_action() podía encontrar Y (p.ej. un 'Destierra...' de
> Fase Final) como la PRIMERA acción reconocible del texto
> completo y ejecutarla al entrar en juego, disparando el efecto
> equivocado.
> 2026-08-29: una carta puede tener DOS "Cuando entra en juego"
> independientes (p.ej. Alicia en Wonderland) — se procesa cada
> bloque aislado por separado, no solo el primero.

### `_execute_trigger_effect` — línea 569

> Tótems auditados 2026-09-20 (arquitectura.md, "539 cartas sin
> cobertura") — no calzan en _resolve_look_and_play_patterns()
> porque no son un solo bloque "mira/muestra N... elige qué
> hacer" genérico (arco del triunfo además necesita is_entering
> explícito, ver TotemAbilityPatterns.gd), se chequean aparte,
> ANTES del bucle de cláusulas genérico de abajo.
> 2026-10-12 (arquitectura.md §54): estas cartas tienen UNA sola
> cláusula de entrada y su patrón explícito la resuelve completa. Antes
> el bucle genérico de abajo corría IGUAL después, y la cadena vieja
> (o el extract_action() del final) volvía a ejecutar el mismo efecto
> (p.ej. azusa yumi robaba y hacía Botar dos veces). explicit_done
> corta ese doble disparo.

### `_execute_trigger_effect` — línea 597

> Armas auditadas 2026-09-20 (arquitectura.md "539 cartas sin
> cobertura") — mismo criterio que los Tótems de arriba: no calzan
> en el despachador compartido porque necesitan saber si es
> ENTER u otras condiciones puntuales, se chequean aparte.

### `_execute_trigger_effect` — línea 607

> hidromiel (2026-09-20, arquitectura.md "539 cartas sin
> cobertura") — única cláusula de la carta, sin riesgo de falso
> positivo con otra cláusula propia; se registra igual que los
> Tótems/Armas de arriba por consistencia de estilo.

### `_execute_trigger_effect` — línea 621

> 'Al salir del juego'/'cuando salga del juego'/'cuando entra o
> salga del juego' (2026-08-29, p.ej. Legión Paladín) — hasta aquí
> solo on_enter_play/on_ally_enters tenían fallback genérico por
> texto; on_leave_play nunca resolvía nada por este camino, sin
> importar qué tan bien detectado estuviera el patrón en
> TargetedEffectExecutor/LookAndPlayResolver.

### `_execute_trigger_effect` — línea 637

> arco del triunfo (2026-09-20) — misma función que en on_enter_
> play, is_entering=false: desregistra el efecto continuo de
> daño al Destierro (el aura de Fuerza se limpia sola vía
> ModifierRegistry al salir la carta fuente de juego).
> Mismo corte de doble disparo que en on_enter_play (2026-10-12).

### `_execute_trigger_effect` — línea 646

> Armas auditadas 2026-09-20 (arquitectura.md "539 cartas sin
> cobertura") — mismo criterio que arco del triunfo arriba.

### `_execute_trigger_effect` — línea 677

> "cuando entra en juego o ataque" (2026-08-29, p.ej. Sherlock
> Holmes) es la misma cláusula que el disparador de entrada — no
> tiene 'cuando ataque' como substring literal.

### `_execute_trigger_effect` — línea 685

> Vlad el Empalador, Dhampir, Antonio Pincheira (2026-10-17):
> "Cuando entra en juego o ataca" / "Cuando ataca, entra o sale".

### `_execute_trigger_effect` — línea 689

> Viejo del Saco (2026-10-18): "Cuando entra en juego o ataca".

### `_execute_trigger_effect` — línea 719

> 'Cuando bloquee'/'al bloquear' IMPRESO EN EL PROPIO ALIADO que
> bloquea (2026-09-20, arquitectura.md "539 cartas sin cobertura")
> — primer uso real de este trigger, hasta ahora clasificado en
> Card.TRIGGER_KEYWORDS pero sin ninguna rama de resolución
> (recolectado desde GameManager.confirm_blockers_and_collect_
> triggers(), 'card' = el Aliado bloqueador mismo, camino DIRECTO
> igual que on_attack). NO es el camino de libro de thoth: esa
> carta es un Oro que reacciona a que TÚ bloquees con cualquier
> Aliado, no una habilidad impresa en el bloqueador — se resuelve
> aparte, con un chequeo directo del Oro en juego, mismo criterio
> que Llave del Abismo (ver GoldManager._trigger_enter_play()) —
> el camino 'directo' de _collect_triggers_for_event() solo llega
> a la carta que disparó el evento, nunca a otra carta pasiva en
> una zona distinta (el Oro no está en el campo de Aliados).

### `_execute_trigger_effect` — línea 745

> 'En tu Fase Final'/'Al final del turno' (2026-08-30, p.ej.
> Espada de O'Higgins) — primer trigger de este tipo que
> realmente resuelve algo; hasta ahora TriggerSystem.
> resolve_turn_end_triggers() nunca se llamaba desde ningún lado
> y esta rama no existía, así que ninguna carta con este texto
> había hecho nada jamás. Mismo aislamiento de oración que
> on_attack/on_damage_dealt, por la misma razón (una carta puede
> tener varios disparadores distintos en el mismo bloque).

### `_execute_trigger_effect` — línea 758

> torii (2026-09-20, arquitectura.md "539 cartas sin cobertura")
> — frase NARROW a propósito, ver docstring de try_execute_
> torii_final_pattern() en OroAbilityPatterns.gd (por qué "en
> la fase final" a secas no se puede usar aquí).

### `_execute_trigger_effect` — línea 766

> Cañón Naval (2026-09-20, arquitectura.md "539 cartas sin
> cobertura") — llamada EXPLÍCITA con la cláusula YA AISLADA
> (no el texto completo), a propósito NO registrada en el
> despachador compartido — ver el docstring de la función en
> WeaponAbilityPatterns.gd para el motivo completo.

### `_execute_trigger_effect` — línea 773

> udjat / torii (2026-09-20, arquitectura.md "539 cartas sin
> cobertura") — mismo criterio que Cañón Naval arriba.

### `_execute_trigger_effect` — línea 786

> 'En la Fase Final oponente' (2026-09-04, p.ej. Biblioteca de
> Caballería) — mismo aislamiento que on_turn_end, pero disparado
> por TriggerSystem.resolve_turn_end_triggers() sobre el campo del
> jugador CONTRARIO al que termina turno (ver ese método).

### `_execute_trigger_effect` — línea 802

> 'En tu Agrupación' (2026-08-30, p.ej. Espada del Juicio: 'Cuando
> entra en juego y en tu Agrupación, Destierra...') — misma
> oración puede contener DOS disparadores distintos ('cuando
> entra' Y 'en tu agrupación'); se aísla igual que on_turn_end,
> y se procesa una vez por cada trigger_type que matchee esa
> misma oración (no es un doble-disparo, son dos eventos reales
> distintos que comparten el mismo efecto impreso).

### `_execute_trigger_effect` — línea 814

> torii (2026-09-20, arquitectura.md "539 cartas sin
> cobertura") — su frase real es "al comienzo de tu
> Agrupación", distinta de "en tu agrupación" (ver también
> Card.TRIGGER_KEYWORDS['on_agrupacion'], se agregó ahí
> también para que el trigger se clasifique).

### `_execute_trigger_effect` — línea 823

> torii (2026-09-20) — llamada EXPLÍCITA con la cláusula YA
> AISLADA, mismo criterio que Cañón Naval/udjat en on_turn_end.

### `_execute_trigger_effect` — línea 831

> 'Al comienzo del turno' (2026-09-04, a pedido del usuario —
> p.ej. manuel rodriguez: 'Al comienzo del turno, genera un Oro
> para Aliados o Baraja una carta de coste 3 o menos') — mismo
> aislamiento que on_agrupacion (disparado desde el mismo lugar
> real, ver TriggerSystem.resolve_agrupacion_triggers()).

### `_execute_trigger_effect` — línea 839

> La oración que vale en ESTE turno (2026-10-18, Carcosa: "al
> comienzo del turno oponente" y "al comienzo de tu turno" en
> oraciones distintas — antes tomaba siempre la primera).

### `_execute_trigger_effect` — línea 855

> 'Al comienzo del Ataque' (2026-09-04, a pedido del usuario —
> p.ej. almirante akari: 'Al comienzo del Ataque, genera un Oro
> por el turno para jugar Aliados o Armas').

### `_execute_trigger_effect` — línea 870

> 'Al comienzo de tu/la Vigilia' (2026-09-03, corregido — NO
> 'en tu vigilia' sola: esa es la ventana NORMAL de las
> habilidades activadas ('una vez por turno, puedes X'), así
> que por sí sola no implica disparador real. Ver la nota
> larga en Card.gd TRIGGER_KEYWORDS['on_vigilia']. 'en tu
> vigilia o fase final' queda aparte por Mariano Osorio,
> acotado a esa combinación exacta.

### `_execute_trigger_effect` — línea 889

> 'Cuando haga daño de combate'/'cuando haga daño'/'si hizo daño'
> (DAR) — mismo aislamiento de oración que on_attack, por la
> misma razón: una carta puede tener varios disparadores
> distintos en el mismo bloque de texto. "Infligir"/"inflija"/
> "inflige" no es terminología real del juego (2026-08-28, a
> pedido del usuario) — se sacó de la lista.

### `_execute_trigger_effect` — línea 898

> "cuando hace daño" (2026-10-12, p.ej. Sir Galahad: 'Cuando hace
> daño al Castillo oponente, ...') — on_damage_dealt ya solo se
> dispara por daño al Castillo (PhaseFlowController._fire_damage_
> dealt_triggers()).

### `_execute_trigger_effect` — línea 907

> Zadquiel (2026-10-14): texto completo, la cláusula aislada
> corta antes de "Esa carta no puede ser jugada...".

### `_isolate_all_trigger_clauses` — línea 945

> Como _isolate_trigger_clause() pero devuelve TODOS los bloques que
> empiezan con alguna frase de trigger_phrases, no solo el primero — una
> carta puede repetir el MISMO tipo de trigger dos veces con efectos
> independientes (2026-08-29, p.ej. Alicia en Wonderland: dos 'Cuando
> entra en juego' separados, cada uno con su propio efecto). Cada bloque
> junta las oraciones siguientes hasta que aparece:
> - otra oración que vuelva a matchear trigger_phrases (empieza el
> siguiente bloque), o
> - una oración de habilidad ACTIVADA ('una vez por turno'/'una vez al
> turno'/'una vez en tu turno'/'una vez en su turno') — esas se
> resuelven por un camino totalmente distinto (parse_abilities() +
> ActionPipeline) y no deben mezclarse aquí aunque no matcheen
> trigger_phrases (2026-08-29, p.ej. Tesoro de los Césares: el ETB
> de esta carta son DOS oraciones separadas por punto, seguidas de
> una habilidad activada en el mismo bloque de texto — sin este corte
> el bloque del ETB se comía también la activada).
> Ya NO tiene la limitación que este comentario documentaba antes
> (2026-08-30, bug real encontrado: Garfio Pirata — 'Cuando entra en
> juego, el portador no puede salir del juego hasta tu próximo turno.
> Cuando el portador ataque, ... Roba una carta.' — sin el corte de abajo,
> la oración de 'Cuando el portador ataque' quedaba pegada al bloque de
> 'Cuando entra en juego', y extract_action() encontraba 'Roba una carta'
> y la ejecutaba AL EQUIPARSE en vez de al atacar). Ahora también corta el
> bloque en curso apenas aparece una oración de un trigger de OTRO TIPO
> (cualquier frase de Card.TRIGGER_KEYWORDS que no sea de este mismo
> trigger_phrases).

### `_isolate_all_trigger_clauses` — línea 978

> Frases de cualquier OTRO tipo de trigger (no las de trigger_phrases,
> las que estamos aislando) — ver corrección de 2026-08-30 arriba.

### `_isolate_all_trigger_clauses` — línea 985

> "Al comienzo de cada turno" (2026-10-18, la esmeralda): no es de
> TRIGGER_KEYWORDS, pero es otra habilidad y corta el bloque.

### `_isolate_all_trigger_clauses` — línea 990

> Cada renglón del texto es una habilidad aparte (2026-10-14, bug real
> reportado por el usuario: Signo Amarillo "resolvió pero no hizo nada" —
> su "Cuando entra en juego, mira..." se llevaba pegado el renglón
> siguiente, "Puedes convertir este Oro...", y CastleLook/EffectCompiler
> ya no lo entendían). Un bloque no sigue en el renglón de abajo, salvo
> que éste empiece en minúscula (texto cortado a mitad de oración).

## `scripts/core/effects/triggers/TriggerSystem.gd`

### `(nivel de archivo)` — línea 51

> Patrones "mira/muestra y juega" (Signo Amarillo, Tangata Manu, Presente,
> Perder la Razón) — sacado de TargetedEffectExecutor.gd (2026-08-28,
> "módulos gordos").

### `(nivel de archivo)` — línea 55

> Buscador de cartas por nombre para efectos "nombra una carta" (2026-08-29,
> p.ej. Alicia en Wonderland, Tesoro de los Césares). Cargado con preload()
> en vez del nombre de clase global (a diferencia de los módulos de arriba)
> porque es un script nuevo — el editor todavía no lo había escaneado para
> registrar su class_name, y referenciarlo por nombre tiraba "Could not
> find type" hasta el próximo reimport manual del proyecto.

### `(nivel de archivo)` — línea 63

> Familias de patrones "try_execute_*_pattern" extraídas de
> TargetedEffectExecutor.gd (2026-08-30, "módulos gordos") — mismo corte
> que ya separó LookAndPlayResolver.gd de este mismo archivo. preload()
> en vez del nombre de clase global: son scripts NUEVOS de esta sesión, ver
> el comentario de arriba sobre CardNameSearchDialogScript.
> preload y no el class_name global (2026-10-12): un editor de Godot abierto
> desde antes de crear la clase no la tiene registrada y Main/TriggerSystem
> fallaban con "Could not find type" hasta reabrir el proyecto.

### `(nivel de archivo)` — línea 75

> Patrones de Tótems detectados sin cobertura en la auditoría de 539 cartas
> (2026-09-20, ver arquitectura.md) — script nuevo de esta sesión, preload()
> por el mismo motivo que CardNameSearchDialogScript arriba.

### `(nivel de archivo)` — línea 79

> Patrones de Armas detectados sin cobertura en la misma auditoría de 539
> cartas (2026-09-20) — mismo criterio y mismo motivo de preload() que
> TotemAbilityPatternsScript arriba.

### `(nivel de archivo)` — línea 83

> Patrones de Oros detectados sin cobertura en la misma auditoría de 539
> cartas (2026-09-20) — mismo criterio y mismo motivo de preload() que
> TotemAbilityPatternsScript/WeaponAbilityPatternsScript arriba.

### `(nivel de archivo)` — línea 92

> Efectos compilados por piezas (EffectCompiler + EffectInterpreter,
> 2026-10-12, arquitectura.md §54) — se prueba ANTES de la cadena de
> patrones en TriggerResolution._resolve_look_and_play_patterns().

### `(nivel de archivo)` — línea 96

> "Cuando sea puesta en tu Cementerio" (2026-10-14, Lanza Argenta).

### `end_collecting_and_queue` — línea 171

> Si hay múltiples triggers del jugador activo, ELIGE el orden (DAR 7.4:
> el dueño de varios triggers simultáneos decide en qué orden resuelven
> — 2026-08-30, a pedido del usuario: p.ej. Espada de O'Higgins y
> Capitán O'Brien disparando juntos en Fase Final, donde puede importar
> barajar el Cementerio con uno ANTES de robar con el otro. Antes esto
> era un TODO sin implementar — emitía trigger_ordering_requested pero
> nadie lo escuchaba nunca, así que siempre caía a 'orden de llegada'
> silenciosamente). Solo el jugador humano elige por ahora, mismo
> criterio ya establecido para el resto de decisiones interactivas de
> esta sesión — el oponente sigue en orden de llegada.

### `_prompt_trigger_order` — línea 197

> Deja elegir al jugador el orden de resolución entre varios triggers
> simultáneos propios clickeando DIRECTO sobre las cartas reales que van
> a disparar (2026-09-13, a pedido del usuario: 'hacer click en la carta
> que vaya a disparar... luego en la siguiente y así', en vez del modal
> de lista viejo) — cada carta con un trigger pendiente ya es un Nodo
> real y visible en juego, no hace falta ningún dato intermedio.
> Returns: los mismos triggers, en el orden elegido (o el orden original
> si algo falla, para no perder ningún trigger en el camino).
>
> 2026-09-02: firma corregida de Array genérico a Array[Dictionary] — el
> llamador (end_collecting_and_queue()) asigna el resultado directo a
> pending_active_triggers, que SÍ está tipado Array[Dictionary]; GDScript
> rechaza en tiempo de ejecución asignar un Array sin tipar a una variable
> tipada, aunque el contenido real fueran todo Dictionary.

### `_prompt_trigger_order` — línea 223

> cancellable=false (mismo criterio que descartes mandatorios, ver
> arquitectura.md §10.29): el orden hay que elegirlo entero, ESC a
> mitad de camino perdería triggers reales sin resolver.
> glow_color_override = dorado (2026-09-15, a pedido del usuario): esto
> no es "elegir un objetivo propio/rival" (celeste/rojo, el default) —
> son triggers PROPIOS ya disparados esperando orden, mismo significado
> que el brillo dorado de "habilidad activable disponible".

### `resolve_talisman` — línea 292

> Envoltorio (2026-10-12, §56): marca el contexto de efecto (quién
> controla este Talismán) para el detector de paridad mientras resuelve.
> La lógica real está en _resolve_talisman_impl().

### `_resolve_talisman_impl` — línea 303

> Resuelve el efecto impreso de un Talismán al jugarlo (DAR Sección 8).
> A diferencia de una habilidad disparada (Sección 7.4), un Talismán no
> 'dispara' nada — su texto ES el efecto de jugarlo, se resuelve directo
> aquí, sin pasar por has_trigger(), register_trigger() ni la cola
> compartida de triggers (2026-08-27, a pedido del usuario). Llamado
> desde GoldManager._trigger_enter_play() para cartas tipo TALISMAN.
>
> Pila de Respuesta Universal (2026-09-09): para un Talismán, "jugarlo" y
> "que su efecto resuelva" son EL MISMO momento del DAR (no hay un estado
> intermedio de "en juego" como con un Aliado) — así que este es el ÚNICO
> choke point que hace falta para darle a CUALQUIER Talismán una ventana
> de respuesta real, en vez de que cada patrón (try_execute_*_pattern en
> LookAndPlayResolver y sus mitades) tuviera que abrir la suya por su
> cuenta. Los pocos patrones que ya tenían su propia ventana interna
> (Golpe Solar, Tempilcahue, Acabar la Esperanza — de cuando todavía no
> existía este choke point) se la sacaron para no preguntar dos veces.
> Returns: true si fue anulado/cancelado durante la ventana (no se
> resuelve el efecto — el llamador lo manda al Cementerio sin más).

### `_resolve_talisman_impl` — línea 329

> kotoku-in (2026-09-20): "el próximo Talismán que juegue tu oponente
> este turno se resuelva sin efecto" — se consume ANTES de resolver,
> mismo canal de retorno que Anular/Cancelar (true = va al Cementerio
> sin resolver su efecto).

### `_collect_triggers_for_event` — línea 369

> Recolecta todos los triggers que responden a un evento.
>
> GUARDIA DE REENTRADA (2026-08-16): esta función se llama con 'await' desde
> varios sitios (GoldManager al jugar una carta, GameManager al declarar un
> atacante). trigger_queue/pending_* son variables de módulo COMPARTIDAS —
> si un jugador dispara un segundo evento (p.ej. declara un ataque) mientras
> la ventana de respuesta del trigger anterior (p.ej. 'roba 2' de un oro
> recién jugado) sigue abierta, la segunda llamada empezaba a recolectar y
> encolar SOBRE la misma cola que el primer resolve_all_triggers() todavía
> estaba vaciando en su propio bucle — dos bucles compitiendo por el mismo
> trigger_queue. Resultado real reportado: el efecto del oro se resolvía
> solo al intentar atacar, y la ventana de prioridad quedaba en un estado
> que ya no dejaba pasar. Se espera a que la recolección/resolución anterior
> termine antes de empezar una nueva — así siempre queda serializado.

### `_collect_triggers_for_event` — línea 383

> Reentrada segura (2026-08-23): si esta llamada ocurre DENTRO de la
> resolución de otro trigger (p.ej. Lobo Sagrado equipa un Arma cuyo
> propio 'cuando entra en juego' dispara este mismo camino vía
> _trigger_enter_play), esperar a que is_resolving baje a false es un
> DEADLOCK: is_resolving no baja hasta que ESTA MISMA llamada anidada
> retorne, porque es parte de la cadena de await de la resolución
> externa. Confirmado con log real: Lobo Sagrado nunca robaba las 2
> cartas (el código quedaba después de este punto sin ejecutarse jamás),
> y cualquier otro trigger posterior tampoco podía avanzar. Distinguir
> la reentrada es seguro: is_collecting solo es true durante un tramo
> 100% síncrono (sin ningún await) de esta función, así que una llamada
> anidada real solo puede darse con is_collecting ya en false — se sigue
> esperando si hay una recolección concurrente genuina en curso, pero
> nunca por estar anidada dentro de su propia resolución.

### `_collect_triggers_for_event` — línea 399

> Salvaguarda (2026-08-26): esta espera estaba pensada para durar como
> mucho unos pocos frames (una recolección/resolución concurrente
> real). Causa raíz real encontrada y corregida (ver "camino
> completo" más abajo: _get_related_triggers() recibía una
> event_card ya liberada sin chequeo de validez, tiraba un error de
> tipo y cortaba la función antes de llegar a
> end_collecting_and_queue() — is_collecting quedaba en true para
> siempre y esta espera colgaba TODOS los triggers del resto de la
> partida en silencio). Se deja igual esta salvaguarda de 3s como
> defensa extra ante cualquier otro error no previsto en ese mismo
> tramo síncrono: fuerza el reset y avisa por consola en vez de
> trabar el juego entero.

### `_collect_triggers_for_event` — línea 423

> ── Camino directo: el propio disparador de la carta del evento ────────
> (p.ej. "Cuando entra en juego" de la carta que se acaba de jugar). No
> depende de GameManager.game_board — ese es el GameBoard legacy huérfano
> (docs/audit-2026-08-13.html, hallazgo 2/4), nunca registrado en la
> escena real; exigirlo aquí hacía que NINGUNA carta disparara NUNCA
> ningún trigger por este camino.

### `_collect_triggers_for_event` — línea 434

> ── Camino completo: triggers de OTRAS cartas que reaccionan a este
> evento (p.ej. "Cuando otro Aliado entre al juego..."). Antes dependía
> de GameManager.game_board (el GameBoard legacy huérfano, siempre null)
> y nunca se ejecutaba — usa el campo real de Main (un solo contenedor
> por jugador, no hay zonas separadas de Defensa/Ataque/Apoyo).
>
> CORRECCIÓN (2026-08-17): este bucle también revisaba si OTRAS cartas
> tenían el mismo event_type ("on_enter_play", "on_attack", etc.) que
> la carta que disparó el evento — pero esos triggers son propios de
> CADA carta ("cuando ESTA carta entra en juego"), no algo que otra
> carta deba compartir solo por tener una frase parecida en su propio
> texto. Resultado real: cada vez que se jugaba una carta nueva, TODAS
> las demás cartas del campo con su propio 'cuando entra en juego' (ya
> resuelto hace turnos) volvían a dispararse. Solo debe revisarse
> related_triggers (p.ej. on_ally_enters), que sí está pensado para
> difundirse a otras cartas bajo un trigger_type distinto.

### `_collect_triggers_for_event` — línea 452

> event_card puede llegar ya liberada (p.ej. una carta que salió de
> juego) — _get_related_triggers() declara 'event_card: Node'
> tipado, y pasarle una instancia liberada tira un error de tipo en
> Godot ("previously freed") que corta la función AQUÍ MISMO, antes
> de llegar a end_collecting_and_queue() (2026-08-26 — causa real de
> que is_collecting quedara trabado en true para siempre y ningún
> trigger volviera a dispararse en lo que quedaba de partida). El
> "camino directo" de arriba ya tenía este chequeo, este bloque no.

### `resolve_turn_end_triggers` — línea 499

> Dispara 'En tu Fase Final'/'Al final del turno' (on_turn_end) para
> CADA carta que el jugador controla y tenga este trigger (2026-08-30,
> p.ej. Espada de O'Higgins) — llamar al ENTRAR a Fase Final, antes del
> robo/límite de mano normales (PhaseFlowController._resolve_fase_final()).
> A diferencia de on_enter_play/on_attack/etc. (una carta puntual
> dispara por algo que le pasó a ELLA), Fase Final es un evento de FASE
> que puede afectar a varias cartas en juego a la vez — no tiene sentido
> forzarlo por _collect_triggers_for_event() (pensada para un event_card
> puntual + 'triggers relacionados' de otras cartas, un concepto
> distinto). Reusa los mismos primitivos de siempre (begin_collecting/
> register_trigger/end_collecting_and_queue/resolve_all_triggers) en vez
> de inventar un camino de resolución aparte.

### `resolve_turn_end_triggers` — línea 514

> player_gold/player_oro_pagado agregados (2026-09-04, p.ej. Tamales:
> 'En tu Fase Final, puedes Barajar hasta tres cartas de los
> Cementerios') — un Oro en Reserva/Oro Pagado también puede tener
> 'En tu Fase Final', y antes esta lista solo escaneaba las tres líneas
> de campo, dejando cualquier trigger de Fase Final de un Oro inerte.

### `resolve_turn_end_triggers` — línea 550

> "En la Fase Final oponente" (2026-09-04, p.ej. Biblioteca de
> Caballería) — a diferencia de on_turn_end de arriba (cartas del propio
> player_id, cuya Fase Final es la que ocurre), este dispara sobre las
> cartas del OTRO jugador, que ve la Fase Final de player_id como "la
> Fase Final de su oponente".

### `resolve_agrupacion_triggers` — línea 577

> Dispara 'En tu Agrupación' (on_agrupacion) para CADA carta que el
> jugador controla y tenga este trigger (2026-08-30, p.ej. Espada del
> Juicio: 'Cuando entra en juego y en tu Agrupación, Destierra...') —
> llamar al ENTRAR a la fase Agrupación (PhaseFlowController). Mismo
> patrón que resolve_turn_end_triggers(), copiado tal cual en vez de
> parametrizado: es un evento de FASE distinto (no un event_card puntual
> de _collect_triggers_for_event()).

### `resolve_agrupacion_triggers` — línea 609

> "Al comienzo del turno" (on_turn_start, 2026-09-04, p.ej.
> manuel rodriguez) — mismo momento real que Agrupación (la
> primera fase del turno), así que se dispara desde el mismo
> lugar en vez de duplicar todo resolve_*_triggers() para un
> evento que ocurre exactamente igual. Excepción conocida:
> Turno 1 salta Agrupación (PhaseFlowController), así que un
> "on_turn_start" del jugador que empieza no dispara ese
> primer turno — caso borde poco relevante (efecto de una vez).
> Solo si alguna oración vale en tu turno (2026-10-18: "al comienzo
> del turno oponente" de ngenechen disparaba también en el tuyo).

### `resolve_agrupacion_triggers` — línea 629

> "Al comienzo del turno" SIN "tu" (2026-10-18, a pedido del usuario —
> manuel rodriguez): también dispara al comienzo del turno del oponente.

### `resolve_agrupacion_triggers` — línea 639

> "al comienzo del turno" a secas o "del turno oponente" (Carcosa
> tiene las dos formas en oraciones distintas, 2026-10-18).

### `resolve_agrupacion_triggers` — línea 649

> la esmeralda (2026-10-18): "Al comienzo de cada turno" — Arma equipada,
> en los dos turnos.

### `resolve_ataque_triggers` — línea 655

> Dispara 'Al comienzo del Ataque' (on_ataque_start, 2026-09-04, a
> pedido del usuario — p.ej. almirante akari: 'Al comienzo del Ataque,
> genera un Oro por el turno para jugar Aliados o Armas') — mismo
> patrón que resolve_agrupacion_triggers(), llamar al ENTRAR a la fase
> Ataque (PhaseFlowController).

### `resolve_vigilia_triggers` — línea 692

> Dispara 'En tu Vigilia' (on_vigilia) para CADA carta que el jugador
> controla y tenga este trigger (2026-09-03, p.ej. Mariano Osorio: 'En
> tu Vigilia o Fase Final, Destierra hasta tres cartas del Cementerio
> oponente') — llamar al ENTRAR a la fase Vigilia (PhaseFlowController).
> Mismo patrón que resolve_agrupacion_triggers()/resolve_turn_end_
> triggers(), copiado tal cual en vez de parametrizado: es un evento de
> FASE distinto.

### `_check_trigger_conditions` — línea 759

> Tamales: 'tu oponente... ni disparar' (2026-09-04) — mismo chequeo
> que _validate_ability() usa para habilidades ACTIVADAS, aquí para
> DISPARADAS. No bloquea auras/efectos continuos (esos no pasan por
> este choke point).

### `_named_trigger_already_used_this_turn` — línea 771

> 'Solo puedes utilizar la habilidad de X una vez por turno' aplicado a
> un TRIGGER, no a una habilidad ACTIVADA (2026-08-30, p.ej. Tangata
> Manu: su 'Cuando entra en juego' puede jugar gratis OTRA copia de sí
> mismo desde el Castillo, cuyo propio 'Cuando entra en juego' volvería a
> dispararse sin este chequeo — la restricción del texto es por NOMBRE,
> compartida entre TODAS las copias que entren ese turno, no por
> instancia. turn_registry ya evita el reuso de una habilidad ACTIVADA
> por card_id/ability_index (CardInspectionLayer._validate_ability()),
> pero nunca se consultaba desde aquí para TRIGGERs — este es el único
> choke point real por el que pasa cualquier trigger antes de encolarse
> (ver register_trigger() más abajo), así que alcanza con chequear Y
> registrar aquí mismo, una sola vez por intento de disparo real.

### `_named_trigger_already_used_this_turn` — línea 801

> Prefijo 'trigger_once:' (2026-08-30) para no compartir namespace con
> el registro de habilidades ACTIVADAS, que usa card_id/ability_index
> numéricos — un nombre de carta nunca podría colisionar con esa clave,
> pero el prefijo lo deja explícito.

### `open_response_window` — línea 893

> Punto de entrada de la Pila de Respuesta Universal (2026-09-09, ver
> docs/plans/2026-09-09-pila-respuesta-universal-design.md) para los
> patrones de trigger de LookAndPlayResolver/DSR_*/TargetedEffectExecutor/
> etc.: se llama justo en el límite "ya se declaró todo (objetivos/modo
> elegidos), falta ejecutar el efecto" que ya existe en casi todas esas
> funciones — mismo lugar donde hoy se insertó EffectController.
> offer_prevention() en los choke points de destroy/exile/etc.
>
> Empuja un objeto a ActionPipeline SIN texto de habilidad resoluble
> (deliberado: si llevara 'habilidad', el Paso E llamaría a
> resolve_ability_effect() → _resolve_look_and_play_patterns(), que
> volvería a matchear el MISMO patrón que llamó a esta función — recursión
> infinita. El efecto real se queda donde siempre estuvo, en las líneas del
> patrón que siguen después de este await) — así el Paso E es un no-op
> inofensivo y lo único que de verdad importa es el Paso D (ventana de
> prioridad real para el rival).
>
> Returns: true si el llamador debe ABORTAR su propio efecto (fue anulado o
> cancelado durante la ventana); false si debe seguir normalmente.

### `open_response_window` — línea 914

> Una sola ventana por efecto (2026-10-12, §59): si la pide la carta del
> efecto que se está resolviendo y el rival ya tuvo su ventana para él,
> no se abre otra (antes: hasta 3 seguidas por la misma carta). Si
> estaba pendiente, esta ES la ventana — después de que el patrón ya
> declaró sus objetivos (opción B).

### `open_response_window` — línea 932

> Qué es esta ventana (2026-10-14, StackAnnul): "carta" = una carta
> jugada (Aliado/Arma/Tótem/Oro, se Anula), "Talismán" (se Anula),
> "disparada"/"activada" (habilidades, se Cancelan).

### `resolve_ability_effect` — línea 945

> Resuelve el texto de efecto de una habilidad — disparada o activada
> (2026-08-27, a pedido del usuario: 'las habilidades también se
> resuelven, sean disparadas o activadas', mismo concepto que ya se
> aplicó a Talismanes). Antes StackStepResolver._resolve_ability() (el
> camino real de las habilidades ACTIVADAS, vía ActionPipeline) solo
> probaba extract_action() simple, sin los patrones compuestos ("mira/
> muestra N...") que sí usan las disparadas — una habilidad activada con
> ese tipo de efecto nunca resolvía bien. Ahora las dos comparten
> _resolve_look_and_play_patterns().
> Returns: true si se ejecutó algo.

## `scripts/core/effects/triggers/TriggerTollPatterns.gd`

### `(nivel de archivo)` — línea 2

> Peaje de Oro a habilidades disparadas (2026-10-17, Mecha-Daikaiju: "...y
> hasta tu próximo turno tu oponente no puede utilizar habilidades
> disparadas a menos que pague un Oro."). El estado vive en RuleState
> ("trigger_gold_toll"). Se usa con preload.

## `scripts/core/effects/triggers/VampirePatterns.gd`

### `(nivel de archivo)` — línea 2

> Vlad el Empalador y Dhampir (2026-10-17, a pedido del usuario). Se usa con
> preload.
>
> Vlad el Empalador:
> "Cuando entra en juego o ataca, muestra cartas del tope de tu Castillo
> hasta mostrar un Aliado de coste 1 y juégalo sin pagar su coste."
> "Una vez en tu turno, cuando este u otro de tus Aliados salga del juego,
> Baraja hasta una carta de coste 3 o menos y tu oponente Bota tres
> cartas." — disparada (on_card_left_play), no un botón.
> Dhampir:
> "Cuando ataca, entra o sale del juego, muestra un Aliado de tu mano y
> Destierra hasta una carta de coste 3 o menos o Roba dos cartas."
> "Cuando tu oponente juegue una carta, hasta tres veces por turno, él Bota
> dos cartas. Si es tu turno, en vez de eso las Destierra." (on_card_played)

## `scripts/core/effects/triggers/WeaponAbilityPatterns.gd`

### `(nivel de archivo)` — línea 2

> WeaponAbilityPatterns — Patrones "try_execute_*_pattern" para Armas
> detectadas sin cobertura en la auditoría de 539 cartas (2026-09-20, ver
> arquitectura.md). Mismo criterio que TotemAbilityPatterns.gd (detección
> por substring, no por nombre de carta) pero para el tipo Arma, que tiene
> su propio ciclo de vida (equipar/desequipar, "el portador gana X") ya
> cubierto en su mayor parte por GoldManager._register_weapon_strength_
> bonus() — este archivo cubre las cláusulas ADICIONALES de cada Arma que
> ese parser genérico no toca (triggers de entrada/salida, habilidades
> activadas de Vigilia/Fase Final).
> Instanciado directo en TriggerSystem._ready() como _weapon_patterns (mismo
> patrón que _totem_patterns), llamado desde TriggerResolution.gd.

### `try_execute_canon_naval_shared_pattern` — línea 25

> 'Una vez por turno o cuando salga del juego, tu oponente Bota cinco
> cartas y Destierra hasta tres cartas de un Cementerio' (Cañón Naval,
> 2026-09-20). Un solo efecto compartido entre dos disparadores distintos
> (activada 'una vez por turno' Y trigger automático al salir de juego) —
> el cupo de 'una vez por turno' vía UniversalCardParser.turn_registry solo
> aplica al camino ACTIVADO (llamado desde _resolve_look_and_play_patterns);
> el camino on_leave_play llama directo a _execute_canon_naval_effect() sin
> pasar por el chequeo de cupo, porque salir de juego es un disparador
> aparte, no una segunda activación manual el mismo turno.
>
> Registrada en el despachador compartido (a diferencia de try_execute_
> canon_naval_final_pattern() más abajo) porque ESTA cláusula sí es una
> habilidad ACTIVADA real (vía StackStepResolver._resolve_ability(), que
> aísla el texto antes de llegar aquí) — la guardia 'el portador gana' es
> la misma usada en try_execute_sable_corto_vigilia_pattern(), necesaria
> para no disparar también durante on_enter_play (que pasa el texto
> COMPLETO de la carta, el cual sí contiene esa otra cláusula).

### `try_execute_canon_naval_final_pattern` — línea 89

> 'En tu Fase Final, puedes Botar las primeras dos cartas de tu Castillo
> para agrupar un Oro' (Cañón Naval) — 'agrupar' aquí se interpreta como
> 'generar' (mismo verbo con el que el resto del catálogo describe un Oro
> virtual puntual, p.ej. kotoku-in/metropolitan 'genera un Oro'), SIN
> restricción de para qué sirve (el texto no dice 'para jugar cartas de
> tipo X' como los demás Oro virtuales de esta sesión), así que el
> predicado es siempre-verdadero.
>
> IMPORTANTE (2026-09-20): a diferencia del resto de las funciones de este
> archivo, esta NO está registrada en el despachador compartido
> _resolve_look_and_play_patterns() — se llama EXPLÍCITAMENTE desde el
> branch on_turn_end de TriggerResolution._execute_trigger_effect(), con
> la cláusula ya aislada ('en tu fase final'). Motivo: ese branch, como
> todos los de _execute_trigger_effect(), pasa el texto COMPLETO de la
> carta (sin aislar) como primer argumento a _resolve_look_and_play_
> patterns() — si esta función estuviera en la lista compartida, se
> intentaría también durante on_enter_play (con el texto completo, que
> SÍ contiene esta cláusula como substring), disparando la elección de
> Fase Final apenas se equipa el Arma en vez de en la Fase Final real.
> Ver la guardia real usada en try_execute_sable_corto_vigilia_pattern()
> para el caso INVERSO (habilidad activada real, que sí necesita estar en
> la lista compartida porque StackStepResolver._resolve_ability() aísla el
> texto antes de llegar aquí).

### `try_execute_flechar_xoon_leave_pattern` — línea 137

> 'Cuando salga del juego, puedes Desterrar una carta de coste 2 o
> menos' (flechar xoon, 2026-09-20). La otra cláusula adicional ('Una vez
> por turno, puedes subir una carta que controles a la mano de su dueño
> para Anular un Talismán o Tótem de coste 2 o menos') se implementó aparte
> en EffectController.offer_flechar_xoon_annul() — no es un trigger propio
> de esta carta sino una reacción a que el RIVAL juegue algo, mismo
> mecanismo real de Almirante Akari (offer_counter_annul), así que vive en
> el mismo choke point que esa carta, no aquí.

### `try_execute_sable_corto_vigilia_pattern` — línea 170

> 'En tu Vigilia, una vez por turno, tu oponente muestra tantas cartas
> del tope de su Castillo como Fuerza tenga un Aliado que controles y
> ponlas en su Cementerio' (sable corto, 2026-09-20). Habilidad ACTIVADA
> (mismo camino compartido que kotoku-in/la rueda de la fortuna en
> TotemAbilityPatterns.gd) — elige UN Aliado propio, el oponente mill tantas
> cartas como la Fuerza actual (ya modificada) de ese Aliado.
>
> Guardia 'el portador gana' (2026-09-20): esta función SÍ está en la lista
> compartida de _resolve_look_and_play_patterns() porque una habilidad
> activada real necesita estarlo (StackStepResolver._resolve_ability() la
> invoca con el texto YA AISLADO a esta sola cláusula) — pero esa misma
> lista compartida también se recorre durante on_enter_play con el texto
> COMPLETO de la carta (sin aislar), donde SÍ aparece 'el portador gana 1
> de fuerza e indesterrable' (otra cláusula de sable corto). Sin esta
> guardia, equipar sable corto dispararía esta elección de inmediato en
> vez de esperar a una activación real en Vigilia.

### `try_execute_nehushtan_leave_pattern` — línea 217

> 'Cuando salga del juego, Roba dos cartas' (nehushtan, 2026-09-20). Solo
> esta cláusula — 'Si el portador está en Línea de Defensa los jugadores no
> pueden Desterrar cartas del Castillo de su oponente ni Botar cartas'
> queda SIN implementar a propósito: mismo hallazgo de arquitectura ya
> documentado para hojo-shi en arquitectura.md §12.8 (el bloqueo global vía
> ActionValidator.gd es poco confiable porque la mayoría de las llamadas
> reales a Botar/Desterrar del proyecto pasan skip_validation=true) — no es
> un problema de esta carta puntual, es deuda de arquitectura preexistente.
> 'Puedes jugarla en Guerra de Talismanes' tampoco se implementó: es una
> excepción de fase AUTO-REFERENCIADA (solo sobre sí misma, no un habilitador
> general como Lobo Sagrado — GoldManagerRestrictions._can_play_weapons_in_
> guerra_talismanes() solo detecta el segundo caso), y modificar el punto
> único de verdad de excepciones de fase (has_phase_exception(), compartido
> por TODA carta del juego) no se alcanzó a hacer con la seguridad debida
> en esta tarea.

### `try_execute_azusa_yumi_enter_leave_pattern` — línea 243

> 'Cuando entra o salga del juego, tú Robas una carta y tu oponente Bota
> dos cartas' (azusa yumi, 2026-09-20) — mismo texto cubre AMBOS disparadores
> (on_enter_play y on_leave_play), igual que arco del triunfo. El bono de
> Fuerza dinámico y 'hace daño al Destierro' se resuelven en GoldManager.
> _register_weapon_strength_bonus() al equipar (ver bloque 'azusa_rx' ahí),
> no aquí. 'Puedes jugarla al comienzo de cualquier Fase y puedes tener más
> de tres copias en tu Castillo' queda sin implementar (excepción de fase +
> de construcción de mazo, mismo motivo que la cláusula de fase de
> nehushtan arriba).

### `try_execute_nodachi_enter_pattern` — línea 264

> 'Cuando entra en juego, mira la mano de tu oponente. Descarta de ahí
> hasta dos Talismanes cuyos costes sumen 2 o menos' (nodachi, 2026-09-20).
> 'Los Talismanes cuestan un Oro adicional' se implementó aparte en
> GoldManager._register_weapon_talisman_tax() (efecto ESTÁTICO mientras
> nodachi está equipada, no un trigger de entrada). 'Si el portador es de
> Raza Caballero, Guerrero y/o Héroe, gana 2 de Fuerza y no puede ser
> Barajado' queda SIN implementar a propósito: 'no puede ser Barajado' es
> un tipo de protección que no existe todavía en ningún lado del proyecto
> (grep confirmado, cero resultados) — construir una protección nueva sin
> precedente no alcanzó el tiempo para hacerse con solidez en esta tarea.

### `try_execute_armadura_celestial_leave_pattern` — línea 323

> 'Cuando esta Arma salga del juego, puedes Descartar una carta para
> ponerla en tu mano' (Armadura Celestial, 2026-09-20) — 'ponerla' concuerda
> en género con 'esta Arma' (femenino), no con 'una carta' (también
> femenino, ambigüedad real del español impreso): se interpretó como
> recuperar la PROPIA Armadura Celestial del Cementerio a la mano pagando
> el costo de descartar otra carta — lectura fiel al patrón real de MyL de
> 'reciclar' un Arma que se va al Cementerio, no 'guardar la carta recién
> descartada'. Se resuelve DESPUÉS de que la carta ya está en el
> Cementerio (no intenta interceptar la transición), así que funciona sin
> importar el orden exacto de eventos de salida de juego.
> 'Puedes Destruir el portador para Anular un Talismán de coste 2 o menos o
> cancelar la habilidad de una carta que afecte a un Aliado' queda SIN
> implementar a propósito: es una habilidad ACTIVADA sin disparador fijo
> (el jugador la usa cuando quiera, no en reacción a un evento concreto
> como offer_counter_annul()/flechar xoon), y 'cancelar la habilidad de una
> carta que afecte a un Aliado' no tiene un objetivo claro de a qué
> apuntar en este motor (no hay una cola de efectos-en-curso interceptable,
> ver arquitectura.md §2 sobre el clúster LinkedEffectRegistry/
> TargetSelector) — no alcanzó el tiempo para diseñar esto con solidez.

## `scripts/core/effects/triggers/WeaponSearchShuffleExecutor.gd`

### `(nivel de archivo)` — línea 3

> WeaponSearchShuffleExecutor — Slice de TargetedEffectExecutor.gd dividido
> por tamaño (2026-09-06, "módulos gordos"). Agrupa el cluster compuesto de
> Buscar/Barajar-para-robar/Arma-con-descuento: _execute_targeted_search,
> _execute_shuffle_for_draw (selección de presupuesto de coste vía
> CardInteractionModule.await_multi_target() con dynamic_filter — 2026-09-13,
> reemplazó al helper _select_cards_by_cost_budget() de modal, eliminado por
> quedar sin llamadores),
> _execute_play_weapon_discount_draw, _execute_return_weapon_swap_free (+ su
> helper _return_equipped_weapon_to_hand) y _count_allies_in_play. Opera
> sobre TriggerSystem via _main (mismo Node que TargetedEffectExecutor._main
> — ver ese archivo para el facade que reune este slice, el de
> MiscTargetedPatterns.gd, y el resto del toolkit de selección de un solo
> objetivo que se quedó en TargetedEffectExecutor.gd por ser el cluster de
> mayor tráfico externo de todo este archivo).

### `_execute_targeted_search` — línea 36

> Solo la habilidad que se está resolviendo, si se conoce (2026-10-14,
> Akari Musashi: "Destierra una carta oponente" de OTRA habilidad hacía
> buscar en el Castillo rival).

### `_execute_targeted_search` — línea 41

> Solo la oración de la búsqueda (2026-10-17, bug real reportado por el
> usuario: Mecha-Daikaiju "busca en tu Castillo un Oro, ponlo en tu Oro
> Pagado y hasta tu próximo turno tu oponente no puede..." buscaba en el
> Castillo rival por el "oponente" de la otra parte).

### `_execute_targeted_search` — línea 59

> Dueño de la zona a buscar (2026-08-25): 'tu Castillo'/'tu Cementerio'
> es siempre propio; 'Castillo/Cementerio de tu oponente' (o 'rival') es
> siempre del rival; 'un Castillo' sin posesivo (p.ej. Rey de Amarillo)
> es AMBIGUO — el jugador elige a cuál apunta.

### `_execute_targeted_search` — línea 137

> Tipos mencionados (no 'elif' — 2026-08-22): "busca un Arma o un Oro"
> (p.ej. Tyet) menciona DOS tipos válidos a la vez, un elif que corta en
> el primero que encuentra (antes 'arma' ganaba siempre sobre 'oro')
> dejaba la búsqueda incompleta.

### `_execute_targeted_search` — línea 158

> Raza (2026-10-14, Akari Musashi: "un Aliado Héroe" buscaba cualquier
> Aliado): la palabra con mayúscula justo después de "Aliado(s)".

### `_execute_targeted_search` — línea 166

> Cantidad: fija ("busca 2 cartas") o dinámica "una carta por cada
> Aliado que controles (más N)" (2026-08-25, p.ej. Rey de Amarillo:
> 'una carta por cada Aliado que controles más una').

### `_execute_targeted_search` — línea 192

> Destino: Destierro directo si el texto lo dice (p.ej. 'y Destiérralas'),
> Reserva de Oro directa si dice 'ponlo/ponla en tu Reserva' (2026-08-29,
> p.ej. Don de Amma: 'busca un Oro en tu Castillo y ponlo en tu
> Reserva' — va derecho a Reserva, no a la mano), si no, el default de
> siempre (mano / juego con may_play).

### `_execute_targeted_search` — línea 205

> 'de distinto nombre'/'distintos nombres' (2026-08-25, p.ej. necro-titan:
> 'busca... dos cartas de distinto nombre') — no puede repetirse nombre
> entre las elegidas.

### `_execute_targeted_search` — línea 217

> "un Castillo/un Cementerio" (2026-10-14, a pedido del usuario): el
> selector del tablero con las zonas de los dos jugadores, en vez de
> elegir primero de quién (popup en el caso del Cementerio).

### `_count_allies_in_play` — línea 235

> Cuenta los Aliados que controla un jugador (Línea de Defensa +
> Ataque) — usado por cantidades dinámicas tipo 'por cada Aliado que
> controles' (2026-08-25).

### `_execute_shuffle_for_draw` — línea 254

> 'Puedes Barajar cartas cuyos costes sumen hasta N y Roba M cartas'
> (patrón SHUFFLE_FOR_DRAW, UniversalCardParser.gd — regex "puedes
> barajar cartas? cuyos? costes? sum(en|an) hasta N ... y robar M
> cartas"). 2026-09-13, corrección a pedido del usuario: el comentario
> original decía "p.ej. Bernardo O'Higgins" — VERIFICADO FALSO contra
> cards.json. El texto real de Bernardo O'Higgins (ids 20312/20478) es
> "Una vez por turno, puedes Barajar un Arma o Aliado Caballero de tu
> mano o que controles para cancelar una habilidad o Desterrar una carta
> de coste 3 o menos" — sin ningún "cuyos costes sumen", ya cubierto por
> BernardoAbilityHandler.gd, un patrón totalmente distinto. Se corrió el
> regex de este patrón contra las ~1900 cartas de cards.json: CERO
> coincidencias — no hay ninguna carta conocida en el caché local que lo
> dispare hoy. Puede ser una carta real no incluida en este caché
> puntual, o un patrón agregado por error en algún momento sin una carta
> real verificada detrás — no se investigó más a fondo, se deja
> documentado en vez de borrar por las dudas de que sí exista.
> DAR: como dice 'puedes', el robo queda condicionado a barajar de
> verdad, no es gratis. Solo el jugador humano por ahora (controller_id
> == 0); el bot simplemente declina. NOTA: solo mira main.player_hand —
> si la carta real (si existe) dijera 'cartas EN JUEGO' en vez de 'de tu
> mano', habría que ampliar los candidatos más allá de la mano.

### `_execute_shuffle_for_draw` — línea 289

> 2026-09-13, a pedido del usuario: click directo con presupuesto en
> vivo (dynamic_filter, ver arquitectura.md §10.20/Tempilcahue) en vez
> del modal viejo que reintentaba toda la selección si te pasabas del
> presupuesto.

### `_execute_play_weapon_discount_draw` — línea 329

> 'Puedes jugar un Arma desde tu mano o Cementerio reduciendo su coste
> en N Oros, hasta un mínimo de M, y Robar K cartas' (p.ej. Lobo Sagrado)
> — NO es "hasta" un Arma: jugarla es obligatorio para robar, el texto no
> permite jugar 0 Armas y robar igual (confirmado por el usuario,
> 2026-08-26 — revertido un intento anterior de hacer el robo
> incondicional). Orden: primero se confirma que hay portador y qué Arma
> jugar; solo con eso resuelto se paga y se retira de su zona de
> origen, para que cancelar a mitad de camino no deje nada a medio mover
> ni cobre Oro de más.
>
> Variante 'hand_only' (p.ej. Hanta: 'puedes jugar un Arma de tu mano
> reduciendo su coste...' sin Cementerio ni robo) reusa toda esta lógica
> — solo cambia el origen elegible y si al final se roba o no.
>
> 2026-10-12, bug real reportado por el usuario ("jugué un Lobo Sagrado
> desde el jugador 2 y no sucedió nada"): antes solo el jugador 0. Ahora
> también el Remoto real (elige por red: Arma con clic en su mano o en el
> popup del Cementerio, y portador). El bot local sigue declinando.

### `_execute_play_weapon_discount_draw` — línea 372

> 2026-09-25, bug real reportado por el usuario ("con lobo sagrado no me
> permite jugar armas del cementerio"): confirma qué encontró de verdad
> esta función antes de construir nada — si el Cementerio real tenía un
> Arma pero acá aparece vacío, el problema está en cómo quedó guardada
> esa carta (campo 'tipo'), no en la selección en sí.

### `_execute_play_weapon_discount_draw` — línea 386

> Título corto (2026-08-26, a pedido del usuario — "más visual, menos
> texto"): el botón Cancelar ya cubre "declinar", no hace falta
> explicarlo en el título.

### `_execute_play_weapon_discount_draw` — línea 393

> 2026-09-13, a pedido del usuario: click directo — mano (Nodos ya
> visibles) + un popup liviano con el Cementerio propio (mismo patrón
> que Sake, arquitectura.md §10.23) — en vez del modal de lista viejo.

### `_execute_play_weapon_discount_draw` — línea 402

> 2026-09-25, bug real reportado por el usuario ("con lobo sagrado no me
> permite jugar armas del cementerio"): el jugador seguía clickeando el
> visor de Cementerio de SIEMPRE (no este popup nuevo) y caía en Exhumar
> en vez de elegir el Arma — ver CardInteractionModule.
> try_resolve_cemetery_click()/_cemetery_target_nodes. Registrar los
> Nodos temporales de este popup ahí les da a ambos caminos la misma
> salida real.

### `_execute_return_weapon_swap_free` — línea 481

> 'Puedes subir un Arma que controles a la mano de su dueño para jugar
> un Arma del mismo o menor coste desde tu mano sin pagar su coste'
> (Padre de la Patria, 2026-08-28). Dos elecciones encadenadas: primero
> qué Arma equipada devolver, después qué Arma de la mano (coste ≤ la
> devuelta) jugar gratis con play_card_for_free() — mismo camino final
> que usan los patrones de LookAndPlayResolver.

### `_execute_return_weapon_swap_free` — línea 507

> Hace falta un Arma YA en la mano para que la habilidad tenga algo que
> jugar gratis — sin esto no vale la pena ni ofrecer el "puedes"
> (2026-08-28, a pedido del usuario, mismo criterio que Lobo Sagrado).

### `_execute_return_weapon_swap_free` — línea 521

> 2026-09-13, a pedido del usuario: click directo sobre las Armas
> equipadas en vez del modal de lista viejo.

### `_execute_return_weapon_swap_free` — línea 529

> get_modified_cost(), no card_cost crudo (2026-09-04) — weapon_to_return
> está EN JUEGO en este punto (solo se devuelve a la mano en la línea
> de abajo), así que puede tener el coste reducido de forma continua
> (p.ej. Samael).

### `_execute_return_weapon_swap_free` — línea 536

> 2) Elegir qué Arma de la mano (coste ≤ la devuelta) jugar gratis. Debe
> ser OTRA Arma, distinta de la que se acaba de devolver (2026-08-30, a
> pedido del usuario) — weapon_to_return ya quedó insertada en
> main.player_hand.cards por _return_equipped_weapon_to_hand() (línea de
> arriba), así que sin esta exclusión aparecía como su propio candidato
> válido (cualquier carta cumple costo ≤ su propio costo).

### `_execute_return_weapon_swap_free` — línea 551

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo.

### `_return_equipped_weapon_to_hand` — línea 581

> 2026-09-30, bug real encontrado al convertir más cartas: 'main.player_hand'
> fijo mandaba el Arma del rival a la mano del Anfitrión. owner_id del
> Arma decide la mano real de destino.

## `scripts/core/game/GameBootstrap.gd`

### `_on_deck_selection_cancelled` — línea 72

> 2026-09-30, a pedido del usuario: antes no había forma de cancelar
> esta pantalla — Escape en DeckSelector.gd ahora emite esta señal en vez
> de quedar como código muerto. Vuelve al menú principal (mismo destino
> que el botón 'Volver' de OnlineConnect.gd/DeckManager.gd/BackSelector.gd).

### `_on_decks_selected` — línea 82

> get_node_or_null("/root/...") en vez del identificador global directo
> (2026-08-30): MatchLoadingOverlay SÍ está registrado como autoload en
> project.godot, pero el compilador de GDScript no lo reconocía como
> identificador válido ("Compile Error: Identifier not found") — mismo
> síntoma que CardNameSearchDialog antes (un class_name/autoload nuevo
> que el editor todavía no había terminado de indexar). La búsqueda por
> ruta es una resolución en tiempo de ejecución, no depende de que el
> compilador ya conozca el identificador.

### `_on_decks_selected` — línea 99

> Nadie escuchaba deck_load_failed en este flujo (2026-08-18): si un mazo
> no tenía ninguna carta encontrable en CardDatabase (p.ej. porque el
> catálogo cargado es más chico que el mazo guardado), DeckLoader emitía
> el fallo a la nada y el juego se quedaba esperando para siempre una
> all_decks_ready que nunca iba a llegar — sin ningún error visible.

### `_on_decks_selected` — línea 106

> Jugador y oponente pueden venir de orígenes distintos ahora (2026-08-24):
> tu propio mazo (externo) para uno, un preset por raza (local) para el
> otro — cada lado se enruta según SU propio origen, no uno compartido.

### `_on_decks_selected` — línea 114

> Multiplayer remoto (Fase A — docs/plans/2026-09-09-multiplayer-remoto-
> design.md): el mazo del jugador 1 no sale de aquí si hay una sala de red
> activa. Del lado Anfitrión, llega por red (el mazo real del Remoto, no
> una copia aleatoria del propio). Del lado Remoto, esta misma instancia
> NUNCA corre su propia partida — solo manda su mazo (el que acaba de
> cargar como jugador 0 arriba) y se queda esperando; Fase B reemplaza esa
> espera por la partida reflejada de verdad.

### `_load_opponent_deck_from_network` — línea 144

> 2026-09-20, a pedido del usuario: si el Anfitrión ya eligió su mazo pero
> el Remoto todavía no mandó el suyo, mostrar "esperando jugador" en vez
> de quedar en silencio — mismo overlay/estilo que ya usa el lado Remoto
> en _send_deck_to_host() para el caso simétrico.

### `_setup_oro_inicial` — línea 231

> Extrae el Oro Inicial de ambos mazos y lo coloca en Reserva antes del mulligan.
>
> Resetea GameState.oro_reserva/oro_pagado ANTES de agregar nada (2026-09-06,
> bug real reportado por el usuario): GameState es autoload, así que si se
> vuelve al menú y se arranca una partida nueva SIN cerrar el juego, los
> oros de la partida anterior seguían en memoria — esta función solo
> SUMABA el Oro Inicial encima de lo que ya hubiera, dejando una Reserva
> inicial inflada (p.ej. 6 en vez de 1) que después dejaba pagar cartas
> que no debían ser pagables.

### `_setup_oro_inicial` — línea 275

> set_zone() faltaba aquí (2026-08-29, bug real reportado: el Oro
> Inicial quedaba con current_zone en su valor por defecto, MANO
> — nunca se actualizaba a RESERVA_ORO porque este camino de
> colocación es distinto al de _place_card_as_gold(), que sí lo
> hace. Cualquier efecto que revise 'está en juego/en Reserva'
> vía current_zone —p.ej. Convertir de Capitán O'Brien— rechazaba
> el Oro Inicial como objetivo aunque estuviera ahí a la vista).

### `_setup_oro_inicial` — línea 286

> El Oro Inicial nunca pasa por _trigger_enter_play() (este
> camino de colocación es aparte, ver comentario de más arriba
> sobre set_zone) — sin esto, un Oro Inicial con aura continua
> (p.ej. Armería del Guerrero: 'Tus Aliados de coste 1 o más
> ganan 1 de Fuerza') nunca la registraba (2026-09-04, bug real:
> el aura quedaba inerte toda la partida).

### `_setup_oro_inicial` — línea 295

> El Oro Inicial del oponente ahora también se muestra como carta
> real (2026-08-25, a pedido del usuario) — antes solo sumaba al
> contador, sin ningún nodo visible en OpponentReservaOro. El Oro
> es información pública (DAR): va boca arriba, no oculta como una
> carta de mano (2026-08-26 — se creaba con is_hidden=true por error).

### `_setup_oro_inicial` — línea 302

> can_interact = true (2026-08-28, a pedido del usuario: "necesito
> poder interactuar con él como con mis cartas") — antes estaba en
> false, así que ni el hover corría sobre esta carta (con
> can_interact=false, CardInteraction.process() la ignora entera).

### `_show_dice_roll` — línea 384

> 2026-09-20, a pedido del usuario: en sala online, cada pantalla tiraba
> sus propios 2 dados al azar por separado — 4 dados sin relación entre
> sí, cada lado podía "ganar" su propia tirada. El Anfitrión manda el
> resultado REAL apenas lo decide (result_decided, antes de la animación)
> — RemoteMirrorController.gd escucha "dice_roll" y reproduce la MISMA
> tirada del otro lado, en vez de tirar la suya.

## `scripts/core/game/GoldManager.gd`

### `(nivel de archivo)` — línea 3

> GoldManager — Sistema de pago de costes y gestión de Oro (DAR Secciones 6 y 8).
> Se instancia como hijo de Main en _ready(). Accede a nodos de Main via _main.
>
> Tokens visuales de Oro (conteo disponible, separación entre cartas,
> recorte de click, creación/despawn de tokens de Oro Virtual) extraídos a
> GoldManagerVisuals.gd (2026-09-06, "módulos gordos", Fase 2). Impuestos de
> coste de Talismanes/Tótems/Oro y descuento de coste por "muestra X"
> extraídos a GoldManagerTax.gd, y elegibilidad para jugar una carta
> (Errante, límite de juego por nombre, Talismanes de respuesta instantánea,
> portadores de Arma, excepciones de fase) a GoldManagerRestrictions.gd
> (ambos 2026-09-06, "módulos gordos", Fase 3) — las funciones de abajo
> marcadas como forwarder de una sola línea son esos splits; el resto de
> este archivo sigue sin tocar.

### `(nivel de archivo)` — línea 21

> Emitida cada vez que un jugador realiza la acción DAR de "Colocar un
> Oro" (mano → Reserva, _place_card_as_gold — NO Oro que llega por
> búsqueda/efecto, ver _register_gold_placed()) — count_this_turn es el
> total de esa acción para ESE jugador en el turno actual (2026-08-29,
> p.ej. Don de Amma: "cuando tu oponente ponga su SEGUNDO Oro en juego
> este turno").

### `(nivel de archivo)` — línea 36

> Oros puestos en juego este turno por CUALQUIER vía (colocar el de la mano
> o por efectos) — "si no has puesto Oros en juego este turno" (Patria
> Vieja, 2026-10-13). oro_colocado_conteo solo cuenta la acción de la mano.

### `(nivel de archivo)` — línea 41

> 'Los jugadores no pueden poner Oros en juego por efectos si ya
> pusieron Oros en juego por efectos durante esta partida' (2026-09-04,
> Armería del Guerrero) — a diferencia de oro_colocado_conteo (por
> turno), esto dura TODA LA PARTIDA: no se toca en _reset_gold() ni en
> ningún reset por turno, cada jugador tiene como máximo UNA vez en toda
> la partida (no se resetea nunca hasta la próxima partida nueva).

### `(nivel de archivo)` — línea 50

> Oro Virtual (2026-08-28, p.ej. Lobo Sagrado: "genera un Oro por el turno")
> — por jugador desde 2026-10-06 (antes era un int único, siempre leído/
> escrito como si solo existiera el jugador 0; ver arquitectura.md §33 para
> el porqué y el alcance de este refactor). Usar siempre oros_virtuales[id],
> nunca 'oros_virtuales' sola — no quedó ningún acceso directo al Dictionary
> entero fuera de este archivo.

### `(nivel de archivo)` — línea 57

> Tokens visuales en Reserva de Oro, uno por unidad de oros_virtuales — 1:1,
> para que la Reserva nunca muestre más ni menos Oro del que hay realmente
> disponible (2026-08-28, a pedido del usuario: antes oros_virtuales no
> tenía ningún rastro visual, solo el contador interno). Por jugador desde
> 2026-10-06 (ver nota de oros_virtuales arriba).

### `(nivel de archivo)` — línea 64

> Oro Virtual RESTRINGIDO (2026-08-28, p.ej. Padre de la Patria: "genera un
> Oro para jugar Armas o Aliados Caballero por el turno") — a diferencia de
> oros_virtuales (Lobo Sagrado, sirve para pagar cualquier cosa), cada
> unidad aquí solo paga cartas que cumplan su propio 'predicate'. Varias
> fuentes pueden coexistir (cada una es una entrada separada del Array de
> ESE jugador), por eso cada valor del Dictionary es un Array de pools y no
> un solo contador+predicate. Cada entrada: {"amount": int, "tokens": Array,
> "predicate": Callable, "label": String}. predicate: func(card_type: int,
> card_race: String, card_cost: int) -> bool (card_cost agregado 2026-08-28
> para Legión Paladín: "genera un Oro para jugar Aliados o Armas de coste 2
> o más" — texto reconfirmado 2026-08-29 contra un fetch en vivo de la API,
> ver [[feedback_api_is_source_of_truth]]). Por jugador desde 2026-10-06
> (ver nota de oros_virtuales arriba).

### `(nivel de archivo)` — línea 79

> "No puedes jugar más cartas este turno" (2026-08-30, p.ej. Tempilcahue) —
> bloqueo TOTAL de jugar cartas (Oro incluido, ver play_card() más abajo:
> colocar Oro también pasa por aquí) para el resto del turno actual, por
> jugador. Se limpia en cada turno nuevo, no en "su próximo turno" —
> _on_turn_started_clear_virtual_gold() ya resetea otros estados "por este
> turno" (oro_colocado_conteo, virtuales), mismo criterio aquí.

### `setup` — línea 99

> 'Oro por el turno' (p.ej. Lobo Sagrado) expira al pasar de turno — sin
> esto oros_virtuales nunca se limpiaba y el Oro generado quedaba
> disponible para siempre (2026-08-28).

### `setup` — línea 111

> Reina Nyssara (2026-10-14): Aliado oponente que sale del juego por un
> Talismán.

### `setup` — línea 120

> Vlad el Empalador (2026-10-17): "cuando este u otro de tus Aliados
> salga del juego".

### `_on_phase_changed_deck170` — línea 130

> Escarapela Nacional (2026-10-14): al comienzo de cada Vigilia, el
> rival del jugador activo puede ponerla en juego. Solo donde corre la
> lógica (no en el Remoto).

### `block_gold_next_turn` — línea 152

> Armas de más (2026-10-14, a pedido del usuario): si un Aliado porta más
> Armas de las que hoy puede (p.ej. Levisterio pierde la habilidad o sale
> del juego, o Carro Szgany deja de apuntarle), se destruyen las que entraron
> primero y sobreviven las últimas en ser portadas. equipped_weapons está en
> orden de entrada (con Arturo de Bretaña, la elegida primero entra primero).
> Chequeo de estado cada 0.3 s, solo donde corre la lógica (no en el Remoto).

### `_quinto_sello_cap_violation` — línea 220

> 'Si está en tu Cementerio, no se pueden jugar más de cinco cartas por
> turno' (Quinto Sello, 2026-09-20) — a diferencia de _no_more_cards_
> violation() (candado por JUGADOR, activado por una habilidad puntual),
> este es un tope NUMÉRICO GLOBAL de regla (el texto no dice 'tuyas'/'tu
> oponente', afecta a cualquiera que intente jugar la sexta carta) —
> revisa AMBOS Cementerios, no solo el del jugador que intenta jugar.
> Solo gatea el camino de play_card() (mano) — play_card_from_exile()/
> play_card_from_cemetery()/play_card_for_free() NO pasan por este chequeo
> todavía (limitación conocida, documentada en arquitectura.md §12.5: sin
> un caso de uso real que combine Exhumar/Cementerio/gratis con este tope
> en la misma partida para justificar tocar esos 3 caminos también sin
> poder probarlo).

### `_quinto_sello_cap_violation` — línea 241

> "Elegir una carta de ahí (mano rival) que no sea Oro para que no pueda
> ser jugada hasta tu próximo turno" (2026-08-30, p.ej. Chakram) — candado
> por CARTA puntual (instance_id), a diferencia de _no_more_cards_this_turn
> (esa bloquea TODO, por jugador). Se limpia cuando empieza el próximo
> turno de QUIEN PUSO el candado (el controlador del Arma que activó la
> habilidad, "tu próximo turno" — no el dueño de la carta candada).

### `_card_play_locked` — línea 282

> Candado por NOMBRE (2026-10-14, Zadquiel: "nombra una carta. Esa carta no
> puede ser jugada hasta tu próximo turno") — cubre toda copia con ese nombre
> del jugador afectado, en la mano o en cualquier otra zona desde la que se
> juegue. Los Oros no se juegan (se ponen en juego), así que no les aplica.
> Clave "jugador|nombre en minúsculas"; se limpia al empezar el próximo turno
> de quien lo puso.

### `is_name_play_locked` — línea 311

> Trono del Cielo (2026-10-18): Oros puestos en juego o generados por cada
> jugador en SU turno; al empezar el turno siguiente pasa a "_prev".

### `_check_reactive_second_gold_triggers` — línea 344

> 'Cuando tu oponente ponga su segundo Oro en juego este turno, puedes
> poner este Oro desde tu mano o Cementerio en tu Oro Pagado' (Don de
> Amma, 2026-08-29). Solo importa el SEGUNDO Oro exacto de placer_id este
> turno — no el primero, ni el tercero en adelante (el texto dice 'su
> segundo Oro', no 'a partir del segundo'). Solo se ofrece el diálogo
> cuando el reactor es el jugador humano (reactor_id == 0): el oponente
> no tiene decisiones propias todavía (sin IA), así que si reactor_id
> fuera 1 no habría forma de responder — se detecta igual (conteo
> correcto para ambos jugadores) pero no se le pregunta nada a un bot que
> no puede contestar.
> NOTA — límite conocido: hoy solo GoldManager._place_card_as_gold()
> (jugador 0, desde la mano) llama a _register_gold_placed(). El
> oponente nunca coloca Oro por su cuenta (no hay IA que juegue por él),
> así que en la práctica esta rama solo puede dispararse si en el futuro
> se agrega alguna forma de que el Oro del oponente aumente durante su
> turno — el conteo ya queda listo y correcto para ese momento.

### `_offer_reactive_second_gold_to_pagado` — línea 386

> Sin botón "Confirmar" (2026-08-29, mismo criterio que El Presente/
> Tangata/Perder la Razón): con un solo candidato, Confirmar-con-0 y
> Cancelar son el mismo resultado — clickear la carta ya acepta sola.
> min_selections=0 (2026-08-30, bug real corregido de paso):
> await_single_pick() escucha selection_completed además de
> card_selected/selection_cancelled — la versión manual de aquí no lo
> hacía, así que confirmar con 0 elegidas dejaba el panel colgado.

### `put_gold_directly_in_pagado` — línea 426

> Pone un Oro directo en el Oro Pagado de un jugador — nunca estuvo
> disponible para pagar nada, entra ya-gastado (2026-08-29, p.ej. Don de
> Amma). Mismo patrón que LookAndPlayResolver (Perder la Razón), pero
> generalizado a cualquier player_id en vez de asumir siempre 0.

### `_place_card_as_gold` — línea 455

> controller_id, no owner_id (2026-10-07, ver arquitectura.md §38) — de
> qué lado del tablero/Reserva aparece es cuestión de control.

### `_place_card_as_gold` — línea 492

> Oro más chico en Reserva (2026-08-28, a pedido del usuario — ganar
> espacio en pantalla). Constants.GOLD_CARD_SCALE es el único punto de
> verdad: mismo valor en GameBootstrap (Oro Inicial), _spawn_virtual_
> gold_token() y LookAndPlayResolver (Oro Pagado directo de Perder la
> Razón) — _mover_oro_a_pagado()/_mover_oro_a_reserva() no tocan scale,
> así que solo hay que fijarlo una vez aquí donde se crea/coloca.

### `_place_card_as_gold` — línea 499

> base_scale ANTES del tween, no después (2026-08-28, a pedido del
> usuario): CardInteraction._on_mouse_exited() calcula el tamaño de
> reposo como base_scale * card_scale_normal — si el mouse pasaba por
> encima de la carta durante estos ~0.3s de animación (base_scale
> todavía en Vector2.ONE, el de la mano), el hover la devolvía a tamaño
> completo. Solo en el próximo hover se veía "encoger de más" a su
> tamaño real — no eran dos bugs, era el mismo: base_scale llegaba tarde.

### `_place_card_as_gold` — línea 522

> 'Entra en juego como una copia de un Oro que controle tu oponente'
> (Corazón de Dragón, 2026-09-06, a pedido del usuario: es una CONDICIÓN
> DE JUEGO, no algo a lo que responder — se resuelve aquí, ANTES del ETB
> genérico de abajo, con el jugador eligiendo a qué Oro rival apuntar.
> Como load_from_data() reemplaza nombre/habilidad/keywords de verdad
> antes de que _trigger_enter_play() lea card_ability, si el Oro copiado
> tiene su propio 'Cuando entra en juego' (p.ej. Drácula: 'Roba dos
> cartas'), ese ETB SÍ dispara con normalidad, como pidió el usuario).

### `_resolve_become_opponent_gold_copy` — línea 553

> Reserva Y Oro Pagado del rival (2026-10-17, bug real reportado por el
> usuario: "un Oro que controle tu oponente" incluye los ya pagados; antes
> solo miraba la Reserva). Sin las fichas de Oro Virtual.

### `_resolve_become_opponent_gold_copy` — línea 572

> Condición de juego: no se puede rechazar (no cancelable). El bot elige
> solo (2026-10-17, bug real: cuando el bot jugaba Corazón de Dragón, la
> elección le aparecía al jugador).

### `_has_card_named_in_play` — línea 588

> Busca por nombre (insensible a mayúsculas) entre todas las zonas de
> campo/Oro de ambos jugadores — usado para restricciones 'mientras X
> esté en juego' que dependen de si una carta puntual está presente, no
> de un modificador registrado (2026-09-04, Armería del Guerrero).

### `_register_armeria_opponent_turn_trigger` — línea 604

> 'Al comienzo del turno oponente, Baraja y/o Destierra hasta dos
> cartas de los Cementerios' (2026-09-04, Armería del Guerrero) — el Oro
> Inicial nunca pasa por _trigger_enter_play() (GameBootstrap._setup_
> oro_inicial() lo coloca aparte), así que este trigger se conecta aquí
> directo en vez del molde estándar de triggers de fase (resolve_
> agrupacion_triggers()/resolve_vigilia_triggers(), pensados para cartas
> que SÍ entran en juego normalmente). 'Al comienzo del turno oponente' =
> el turno de CUALQUIERA que no sea el dueño de esta carta — se reevalúa
> en cada turn_started, no una sola vez al registrar.

### `_resolve_armeria_barajar_desterrar` — línea 632

> Elige hasta 'max_amount' cartas de los Cementerios (de cualquiera de
> los dos jugadores, sin zona explícita = en juego, ver
> [[project_no_zone_means_in_play]]) y, para cada una, Barajarla (vuelve
> a su Castillo, barajado) o Desterrarla — elección independiente por
> carta. Genérica desde 2026-09-04 (antes hardcodeada a 2/Armería del
> Guerrero) — reusada por Belta ('hasta dos'), Perla de Sangre, Uriel,
> Torre de Babel y cualquier otra carta con el mismo patrón exacto de
> texto, solo cambia la cantidad.
> 2026-09-13, a pedido del usuario: la elección de CUÁLES cartas ahora es
> click directo (ZoneViewerModule.open_cemetery_target_picker(), pool
> combinado de ambos Cementerios, sin lock) en vez del modal de lista
> viejo — como esto convierte de una sola vez a las 4+ cartas que
> reusan esta función, tiene más impacto que convertir una habilidad
> puntual. La elección Barajar/Desterrar POR CARTA sigue siendo un
> modal de 2 botones (es un efecto distinto, no una carta — no aplica el
> reemplazo, ver arquitectura.md §10.16/§10.18).

### `_resolve_armeria_barajar_desterrar` — línea 667

> 2026-09-30, mismo criterio que el fix de Azi Sruvara: sin esto
> no había ninguna retroalimentación visual del barajado.

### `put_gold_directly_in_reserva` — línea 675

> Pone un Oro directo en la Reserva de un jugador, sin pasar por la
> mano ni pagar coste — sale de una búsqueda ('busca un Oro en tu
> Castillo y ponlo en tu Reserva', 2026-08-29, p.ej. Don de Amma), no de
> jugarlo. Mismo patrón visual que el Oro Inicial de GameBootstrap.gd
> (único otro lugar que coloca Oro en Reserva sin pasar por
> _place_card_as_gold, que exige que la carta ya sea un Node hijo de
> player_hand).
>
> 'Los jugadores no pueden poner Oros en juego por efectos si ya
> pusieron Oros en juego por efectos durante esta partida' (2026-09-04,
> Armería del Guerrero) — este es EL choke point real de 'poner un Oro
> en juego por efectos' (a diferencia de _place_card_as_gold(), que es
> la acción normal de la mano, DAR distinto verbo). Por jugador, toda la
> partida, solo se chequea/aplica si hay una Armería del Guerrero en
> juego (de cualquiera de los dos lados — el texto dice 'los jugadores',
> no 'tu oponente').

### `play_card` — línea 720

> player_id (2026-10-07, refactor de GoldManager.play_card() para que
> deje de asumir siempre jugador 0 — ver arquitectura.md §34): se deriva
> del controller_id real de la carta, no de un parámetro nuevo — todos
> los llamadores existentes (DropZone, BanishOpponentPatterns,
> ActionSearch, etc.) solo pasan 'card', así que esto no les cambia nada
> (sus cartas siempre tienen controller_id 0); el único camino que ahora
> puede llegar con controller_id 1 es el drag-and-drop del propio Remoto
> sobre su mano/zonas.
> controller_id, no owner_id (2026-10-07, ver arquitectura.md §38): quién
> paga/de quién es el turno que se chequea aquí es quien CONTROLA el
> juego de esta carta ahora mismo, no necesariamente su dueño real —
> divergen en Miguel ("juega una carta de tu mano o de un Cementerio",
> el Cementerio puede ser el rival, pero paga y juega el activador).

### `play_card` — línea 734

> Excepciones de fase (2026-08-28): por defecto TODO se restringe a
> Vigilia por los dos gateos de abajo (VIGILIA-only y ventana de
> prioridad activa — Guerra de Talismanes SIEMPRE tiene una abierta,
> PriorityManager.start_priority_window() al entrar a la fase). Dos
> excepciones:
> 1. Arma puntual habilitada por una carta en juego (Lobo Sagrado:
> 'Puedes jugar Armas en Guerra de Talismanes') — ver
> _can_play_weapons_in_guerra_talismanes().
> 2. Talismanes en general (DAR 5.3.3): se pueden jugar en Vigilia O en
> Guerra de Talismanes por defecto, salvo que su propio texto diga
> lo contrario (sin ejemplo concreto todavía — pendiente el día que
> aparezca una carta así) o sean de respuesta (Anular/Cancelar,
> p.ej. Red de Plata) — esos ya quedan bloqueados en CUALQUIER fase
> más abajo por _is_response_only_talisman(), así que no hace falta
> repetir la exclusión aquí.

### `play_card` — línea 750

> Ventana de comienzo de fase (2026-10-18): "Puedes jugarlo al comienzo de
> cualquier Fase" / "en la Fase Final" — en el turno de cualquiera.

### `play_card` — línea 754

> Talismanes de velocidad instantánea (Anula/Cancela, p.ej. Red de Plata,
> Sacrificio Solar — ver _is_response_only_talisman()) son "de respuesta"
> en el sentido de DAR: se juegan EN CUALQUIER MOMENTO en el que el
> jugador tenga la palabra, no solo en Vigilia o con una ventana de
> prioridad puntual abierta (2026-09-06, implementa lo que el comentario
> de más abajo venía dejando pendiente desde 2026-08-25/28). Alcance
> acordado (igual que TargetedEffectExecutor._execute_targeted_annul()):
> no hay pila/interrupción real de la acción del oponente — el motor no
> tiene un oponente que juegue cartas por su cuenta todavía (ver
> comentarios "el bot no actúa de forma independiente" repartidos por
> el proyecto) — así que "instantáneo" aquí significa "juega esto cuando
> quieras mientras sea tu turno", resolviendo sobre algo que YA está en
> juego (su objetivo), no sobre una acción a medio resolver.

### `play_card` — línea 768

> 2026-10-14, a pedido del usuario (Sacrificio Solar jugado en Vigilia
> sin nada que anular): un Talismán de Anular/Cancelar solo se juega en
> respuesta a una carta o habilidad del rival.
> "Sólo puedes jugarlo durante tu turno" (Maldición Vudú, 2026-10-18).

### `play_card` — línea 786

> 2026-09-15, a pedido del usuario ("integrar el sistema de respuestas,
> que pueda responder cartas rivales como estaba planeado"): este chequeo
> bloqueaba SIEMPRE que no fuera tu turno de juego — sin excepción para
> is_instant_response, a diferencia de los otros dos gateos de arriba/
> abajo (fase y ventana de prioridad), que sí la tienen. El comentario de
> 2026-09-06 (línea ~506) ya documentaba la intención real ("se juegan EN
> CUALQUIER MOMENTO en el que el jugador tenga la palabra"), pero el bot
> jugando cartas de forma independiente + la Pila de Respuesta Universal
> (docs/plans/2026-09-09-pila-respuesta-universal-design.md) hicieron que
> esa intención dejara de cumplirse en la práctica: un Talismán de
> respuesta (Red de Plata, Sacrificio Solar) nunca se podía jugar durante
> el turno del rival, exactamente el caso de uso real que existe para
> tenerlos en la mano.
> Guerra de Talismanes (2026-10-13, §64): no importa de quién sea el
> turno — juega quien tiene la prioridad de la Guerra, también el
> defensor (que la tiene primero, DAR 5.C3). Antes el defensor solo podía
> jugar Talismanes de Anular/Cancelar ("No es tu turno").

### `play_card` — línea 850

> Talismanes de respuesta (Anula/Cancela) ya NO se bloquean aquí sin más
> (2026-09-06, implementado): is_instant_response arriba ya los dejó
> pasar las dos ventanas normales de fase/prioridad — de aquí para abajo
> siguen el mismo camino genérico que cualquier Talismán (coste, target,
> _play_talisman()). Si su objetivo (Anular un Aliado/Tótem, Cancelar
> una habilidad) no existe en la mesa, el propio selector de objetivo
> (_execute_targeted_annul()/equivalente) se cancela solo con ESC — no
> hace falta precalcular "hay objetivo válido" aquí.
> "Muestra X para reducir el coste" (2026-08-29, p.ej. El Rey y el
> Verdugo) — se resuelve ANTES de calcular coste_real, porque el
> descuento depende de una elección del jugador hecha en este mismo
> instante (cuántas cartas mostrar), no de un modificador persistente.
> No se remueve el modificador después a mano (2026-08-29: si esta
> carta fuera un Arma habría un SEGUNDO cálculo de coste_real más abajo,
> tras elegir portador, que también necesita verlo activo) — se deja
> que _on_turn_started_clear_modifiers() lo limpie en el próximo turno,
> igual que el resto de cost_modifiers; queda inerte una vez la carta
> ya está en juego (nadie vuelve a pedir su coste después de jugada).

### `play_card` — línea 876

> "Puedes Descartar una carta para reducir su coste en un Oro" (2026-09-20,
> voragh el devorador, bug real reportado por el usuario) — mismo momento
> y mismo criterio que el bloque de arriba (ANTES de calcular coste_real),
> pero la carta entregada se descarta de verdad en vez de solo mostrarse.

### `play_card` — línea 888

> Filtro de asequibilidad ANTES de ofrecer portador (2026-08-28, a pedido
> del usuario): con excepciones de fase tipo Lobo Sagrado (Guerra de
> Talismanes permite Armas de cualquier coste) el jugador podía llegar a
> elegir portador para un Arma que ya sabíamos que no podía pagar (0 Oro
> disponible, Arma de coste 3) — no debía ser siquiera una opción válida,
> igual que Tangata Manu/_make_look_play_free_filter ya filtran por
> asequibilidad antes de mostrar candidatos. Se corta aquí, antes de la
> selección de portador, en vez de solo después.

### `play_card` — línea 901

> Limpiar el descuento de "muestra X" si se rechaza aquí (2026-08-29):
> si no, un segundo intento de jugar la misma carta más tarde este
> turno heredaría el descuento sin haber mostrado nada de nuevo.

### `play_card` — línea 911

> Bloquear el Arma mientras se elige portador (2026-08-21): seguía
> interactiva en la mano durante la selección, así que un segundo
> click/doble-click sobre ELLA MISMA volvía a llamar play_card() y
> pisaba el filtro/callback pendiente en CardInteractionModule (son
> campos únicos, no una cola) — la primera selección quedaba
> colgada para siempre y 'Elige qué Aliado porta el Arma' se repetía
> sin que ningún click a un Aliado la resolviera.

### `play_card_from_exile` — línea 952

> Juega una carta directamente desde el Destierro propio, pagando su
> coste real, como si estuviera en la mano (2026-09-04, a pedido del
> usuario — p.ej. uriel: 'Puedes jugarlo de tu Destierro pagando su
> coste'; batallon de ovejas: 'Si tienes cuatro cartas o menos en tu
> mano, puedes jugarlo desde tu Destierro'; cruzar el bosque: 'Puedes
> jugar esta carta desde tu Destierro'). Espejo casi exacto de
> play_card_from_cemetery(), con el Destierro como origen en vez del
> Cementerio — a diferencia de Exhumar, NO se marca is_exhumed (jugar
> desde el Destierro no es un castigo recurrente: si esta carta vuelve a
> salir del juego después, va al Cementerio normalmente, salvo que su
> propio texto diga otra cosa — no hay ningún caso así todavía).
> discount (2026-09-04, p.ej. rafael: 'reduciendo su coste en un Oro') —
> descuento fijo aplicado ANTES de calcular coste_real, piso 1 (no dice
> 'hasta un mínimo de 0').
> 'owner_id' (2026-10-07, mismo criterio que play_card_for_free() — ver
> arquitectura.md §25/§34): los llamadores existentes (ZoneViewerModule,
> siempre el Anfitrión) no lo pasan, así que conservan el 0 de siempre.

### `play_found_card` — línea 1051

> Juega, como parte de un efecto, una carta ya sacada de su zona (p.ej.
> "busca un Talismán en un Castillo y juégalo", 2026-10-14): sin chequeos
> de fase/turno (lo permite el efecto), pagando su coste con 'discount'.
> La carta queda bajo 'controller_id' pero sigue siendo de 'original_owner'
> (vuelve a SU Cementerio). Si no se puede pagar, vuelve al Castillo de su
> dueño y se baraja.

### `play_card_from_cemetery` — línea 1098

> Juega una carta con Exhumar directamente desde el Cementerio propio,
> como si estuviera en la mano (DAR - Exhumar). Espejo de play_card() pero
> con el Cementerio como origen en vez de la mano — la carta nunca pasa
> por player_hand, así que _play_talisman()/_play_card_to_field()/
> _equip_weapon() deben tolerar que no tenga ese parent (ya corregido).
> Al salir del juego irá al Destierro en vez del Cementerio: la carta se
> marca con is_exhumed = true, que CardManager.destroy_card() y
> GoldManager._play_talisman() ya respetan.
> 'owner_id' (2026-10-07, mismo criterio que play_card_for_free() — ver
> arquitectura.md §25/§34): los llamadores existentes (ZoneViewerModule,
> siempre el Anfitrión) no lo pasan, así que conservan el 0 de siempre.

### `play_card_from_cemetery` — línea 1109

> Mismas excepciones que play_card() — ver su comentario (Arma puntual
> tipo Lobo Sagrado + Talismanes en general en Guerra de Talismanes, y
> Talismanes de respuesta instantánea — Exhumar uno también cuenta como
> jugarlo, 2026-09-06).

### `play_card_from_cemetery` — línea 1144

> Exhumar no destierra al salir del juego salvo los Talismanes (usuario,
> 2026-10-14: "eso solo aplica para talismanes").

### `play_card_from_cemetery` — línea 1162

> Filtro de asequibilidad ANTES de ofrecer portador — ver mismo comentario
> en play_card() (2026-08-28): no ofrecer selección de portador para un
> Arma que ya sabemos que no se puede pagar.

### `play_card_for_free` — línea 1211

> Juega una carta SIN pagar su coste ni pasar por la mano (2026-08-25,
> p.ej. Tangata Manu: 'juega una carta de coste 2 o menos... sin pagar su
> coste'). El llamador ya sacó card_data de su zona de origen — aquí solo
> se crea el nodo y se enruta según su tipo, igual que play_card()/
> play_card_from_cemetery() pero sin pasar por PaymentManager.
>
> 'owner_id' (2026-10-05, bug real encontrado al convertir más cartas —
> ver arquitectura.md §25): antes quedaba SIEMPRE en 0 sin importar quién
> activó el efecto que llama a esta función — cualquier llamador que
> resuelve una habilidad del jugador 1 (La Torre, arco del triunfo, Caín,
> etc.) terminaba poniendo la carta en el campo del Anfitrión por error.
> Los llamadores existentes que no pasan este argumento conservan el
> comportamiento viejo (0) sin cambios.

### `play_card_for_free` — línea 1227

> Un Oro NUNCA se juega, ni gratis — solo se pone en juego por efectos
> (2026-10-12, regla confirmada por el usuario). Si un patrón llegara a
> mandar uno aquí, terminaría como carta "jugada" en una Línea; se
> rechaza para que el error se vea en vez de romper el tablero.

### `play_card_for_free` — línea 1239

> "juégalo ... y Destiérralo" (2026-10-14, haka pei): al salir del juego
> va al Destierro, igual que una carta exhumada.

### `_select_weapon_wielder` — línea 1273

> Abre selección de objetivo para elegir qué Aliado porta el Arma que
> se está jugando — propio O rival (2026-09-03, corregido a pedido del
> usuario: DAR no restringe el portador a Aliados que controlas). Un
> Arma no puede ir suelta, y un Aliado solo porta una a la vez (o más,
> con 'Arma adicional' en juego).
>
> 'chooser_id' (2026-10-05, ver arquitectura.md §25): solo lo usan
> llamadores de play_card_for_free() en nombre del jugador 1 — los
> llamadores de play_card()/play_card_from_cemetery() (siempre el
> Anfitrión, ver sus propios gateos de turno) se quedan en el default 0.

### `_select_weapon_wielder` — línea 1285

> Chequeo defensivo ANTES de abrir la selección (2026-08-28): todos los
> llamadores ya verifican _player_has_ally_in_play() antes de llegar
> aquí, pero si por cualquier motivo (nuevo llamador, estado cambiado
> entre medio) esto se llamara con cero candidatos elegibles, abrir la
> selección de todos modos la dejaba colgada para siempre — cualquier
> click en cualquier carta (incluidas otras de la mano) caía en
> "Objetivo no válido" sin resolver nunca 'done', y el jugador quedaba
> sin poder jugar más cartas hasta reiniciar. Cortar aquí es la última
> red de seguridad, sin importar qué otro chequeo haya fallado antes.
> 'extra_filter' (2026-10-14, Zadquiel: "sobre este Aliado o uno
> oponente"): restringe además quién puede portarla.

### `_equip_weapon` — línea 1309

> Ancla el Arma como hija directa del Aliado portador — no va a ningún
> contenedor de línea. Se puede seguir inspeccionando con clic derecho por
> separado (mismo Card.tscn/Card.gd) y la sigue automáticamente si el
> Aliado se reparenta (ataca) o sale de juego (ver CardManager.destroy_card/
> exile_card, que la mueven al mismo destino que el portador).
>
> fire_enter_play (2026-09-25, bug real reportado por el usuario: 'pude
> jugar un arma en fase de daño, no puedo hacer eso') — CardManager.
> _resolve_weapon_survives_wielder() reusa esta misma función para
> RE-anclar un Arma que YA estaba en juego a un nuevo portador cuando el
> anterior muere (DAR: el Arma sobrevive, no se 'juega' de nuevo). Antes
> esta función llamaba _trigger_enter_play() SIEMPRE, sin distinguir ese
> caso de un Arma genuinamente recién jugada — eso disparaba otra vez su
> 'Cuando entra en juego' (visible en el log como una Espada Vikinga
> resolviendo su habilidad en plena Asignación de Daño), sumaba de más al
> contador de Quinto Sello, y re-evaluaba auras de entrada (Primer
> Sello/Llave del Abismo) para una carta que nunca volvió a entrar.
> Ahora, si fire_enter_play es false (reasignación de portador), se
> saltea _trigger_enter_play() por completo — el Arma sigue en juego, con
> su bono de Fuerza/keywords ya registrados de nuevo para el portador
> nuevo (eso sí corresponde), pero sin re-disparar nada de 'entrar en
> juego'.

### `_equip_weapon` — línea 1347

> 3. Quitar de la mano matando cualquier tween activo en DynamicHand (2026-09-19)
> para evitar que tweens residuales sigan moviendo 'position' a las coordenadas de la mano.

### `_equip_weapon` — línea 1361

> Detrás del Aliado, asomando solo por abajo (2026-08-29, tercera vuelta
> de este mismo ajuste, a pedido del usuario: 'el portador está sobre el
> arma y esta solo se puede ver su caja de texto por abajo'). El primer
> intento (2026-08-26) usó z_index=-1 con un offset chico (30px) — TODO
> el Arma quedaba dentro del rect del Aliado, tapada 100% por su
> CardBase. El segundo intento (más arriba en el historial) sacó la
> superposición por completo (Arma abajo del todo, sin tapar nada) — el
> usuario prefiere la superposición real: portador arriba, Arma
> asomando abajo. La diferencia con el primer intento es el OFFSET: aquí
> es lo bastante grande (125 de 210 de alto) para que la parte de abajo
> del Arma quede FUERA del rect del Aliado (ahí sí se ve, nada del
> Aliado la tapa), y solo la parte de arriba (dentro del rect) queda
> escondida detrás del CardBase.

### `_equip_weapon` — línea 1382

> Mismo tamaño que el Aliado, no una insignia chica (2026-08-29, a pedido
> del usuario: 'el arma debe ser del mismo tamaño que el aliado') —
> escala dinámica (ally.base_scale) en vez de un valor fijo, para seguir
> el tamaño real del Aliado sea cual sea (campo normal vs. Tótem u otra
> escala futura). base_scale junto con scale, no solo scale (misma clase
> de bug que _place_card_as_gold(): CardInteraction usa base_scale como
> referencia para el tamaño de reposo tras el hover, y CardAnimations.
> play_enter_animation() la usa como destino de su tween de entrada).
> Y=125 de 210 de alto de carta — deja ~85px asomando abajo del borde
> inferior del Aliado, la franja donde una carta real imprime su texto.
> Con más de un Arma equipada se van apilando hacia abajo (+Constants.WEAPON_STACK_STEP_Y cada una).

### `_equip_weapon` — línea 1411

> 2026-09-19, bug real reportado por el usuario: "Invalid call. Nonexistent
> function 'to_local' in base 'Control (Card)'" — to_local()/to_global()
> son métodos de Node2D, no de Control (ambos heredan de CanvasItem por
> separado, Control no hereda de Node2D). Equivalente real para Control,
> mismo idioma ya usado en MulliganController.gd:42.

### `_register_weapon_strength_bonus` — línea 1453

> el huascar (2026-10-18): "El portador duplica su Fuerza y tus demás
> Aliados ganan Fuerza igual a su coste." — mientras esté equipada.

### `_register_weapon_strength_bonus` — línea 1485

> "El portador gana Furia y 1 de Fuerza por cada Oro que controles"
> (2026-09-04, skofnung) — bono DINÁMICO (no un número fijo), value
> como Callable recontado en cada consulta (_calculate_modifier_value()
> ya lo soporta, mismo mecanismo que Manuel Bulnes/shedo titan).

### `_register_weapon_strength_bonus` — línea 1525

> "El portador gana 2 de Fuerza por cada Azusa Yumi que controles y hace
> daño al Destierro" (azusa yumi, 2026-09-20, arquitectura.md "539 cartas
> sin cobertura") — mismo mecanismo de value Callable que el bono por Oro
> de arriba, pero contando copias de la MISMA Arma equipadas en cualquier
> Aliado del controlador (no un recurso del jugador). Sin este branch
> específico ANTES del regex genérico de más abajo, "el portador gana 2 de
> fuerza por cada azusa yumi..." matchearía el regex genérico como un
> número FIJO de 2 (ignorando "por cada..."), un bug real detectado al
> escribir este código, no reportado todavía por el usuario.

### `_register_weapon_strength_bonus` — línea 1582

> "En Guerra de Talismanes, una vez por turno, el portador gana 1 de
> Fuerza por cada Aliado en tu Línea de Defensa..." (kabutowari,
> 2026-09-20) — NO es un aura permanente (depende de fase + "una vez por
> turno" + un draw condicional al resultado), así que debe estar excluida
> del regex genérico de más abajo (que la matchearía como +1 Fuerza FIJO
> y PERMANENTE, incorrecto). Igual que kabutowari en el lote de Tótems:
> el mecanismo completo (fase Guerra de Talismanes + cupo por turno +
> draw condicional) queda pendiente, sin implementar todavía — este
> 'return' solo evita el bug de un bono equivocado, no otorga nada.

### `_register_weapon_strength_bonus` — línea 1596

> Captura keywords adicionales otorgadas en la MISMA oración ("e
> Indesterrable"/"y Furia"/etc., 2026-09-04 — a pedido del usuario,
> 'El portador gana 2 de Fuerza e Indesterrable' es el texto más común
> de TODAS las Armas del juego, y hasta ahora esta función solo leía
> el número de Fuerza, ignorando cualquier keyword en la misma frase).
> El grupo de la keyword acepta tanto "e Indesterrable"/"y Furia" (con
> conjunción) como ", Furia" sin conjunción (2026-09-06, p.ej. Daga
> Ritual: "gana 2 de Fuerza, Furia" — antes exigía "y"/"e" literal
> antes de la keyword, así que una lista separada solo por coma nunca
> matcheaba el grupo 2 y la keyword quedaba sin otorgar).

### `_register_wielder_leave_play_immunity` — línea 1651

> 'Cuando entra en juego, el portador no puede salir del juego hasta tu
> próximo turno' (2026-08-30, p.ej. Garfio Pirata) — mismo criterio que
> _register_weapon_strength_bonus(): efecto propio del Arma sobre su
> portador al equiparse, resuelto directo aquí (no por el pipeline genérico
> de triggers) porque necesita saber QUIÉN es el portador, algo que
> ABILITY_PATTERNS no puede extraer solo de un regex.

### `_register_weapon_talisman_tax` — línea 1665

> 'Los Talismanes cuestan un Oro adicional' (nodachi, 2026-09-20,
> arquitectura.md "539 cartas sin cobertura") — texto SIN calificar a
> 'de tu oponente', así que se interpreta literal: sube el COSTE IMPRESO
> (agregar_modificador_coste, no oros_mas — el texto dice 'cuestan', no
> 'pagas X Oro adicional', mismo criterio de la familia A/B documentada en
> PaymentManager.calcular_coste_real()) de CUALQUIER Talismán, de ambos
> jugadores por igual, mientras nodachi esté equipada. Limpieza automática
> ya cubierta por Card._exit_tree() → PaymentManager.remover_modificador_
> coste(self) (ver GoldManagerTax.gd línea ~44) — no hace falta desregistrar
> manualmente al desequipar/salir de juego. Primer uso REAL de un coste
> ADICIONAL (modifier positivo) en todo el proyecto — hasta esta carta,
> agregar_modificador_coste() solo se llamaba con valores negativos.

### `_refresh_dynamic_strength_badges` — línea 1686

> Invalida el cache de ContinuousEffectManager y refresca el badge de
> Fuerza de TODOS los Aliados de player_id (2026-08-30, bug real: Manuel
> Bulnes 'Gana N de Fuerza por cada Arma que controles' es un modificador
> DINÁMICO — value es un Callable que cuenta Armas equipadas en TODO el
> campo de su controlador cada vez que se evalúa. Equipar un Arma en OTRO
> Aliado no registra/desregistra ningún modificador DE Bulnes, así que
> ContinuousEffectManager._get_modified_stat()'s cache (solo se invalida
> en register_modifier()/unregister_modifier(), no cuando cambia el
> CONTEO de Armas de otra carta) nunca se enteraba — el valor calculado
> quedaba pegado al de cuando Bulnes entró en juego, sin importar cuántas
> Armas se equiparan después. Llamar cada vez que el conteo de Armas
> equipadas de un jugador puede haber cambiado (aquí: al equipar una).

### `_fix_mojibake` — línea 1711

> Corrige el patrón de doble-codificación UTF-8→Latin-1→UTF-8 más común
> en español (2026-08-26, visto en el texto de habilidad que trae la API
> de ShadowForge para varias cartas, p.ej. 'TalismÃ¡n' en vez de
> 'Talismán'). No es un fix general de encoding, solo cubre las vocales
> acentuadas + ñ que aparecen en texto de cartas. El orden importa: los
> reemplazos de 2 caracteres van antes que el 'Ã' suelto, si no ese
> genérico los rompe primero.

### `_fix_mojibake` — línea 1731

> Impuestos de coste de Talismanes/Tótems/Oro y descuento de coste por
> "muestra X" — cuerpo movido a GoldManagerTax.gd (2026-09-06, "módulos
> gordos", Fase 3). Forwarders de una sola línea: los cuatro se siguen
> llamando internamente desde play_card()/_trigger_enter_play() más abajo
> con su nombre original.

### `_resolve_discard_cost_reduction` — línea 1760

> Elegibilidad para jugar una carta (Errante, límite de juego por nombre,
> Talismanes de respuesta instantánea, portadores de Arma, excepciones de
> fase) — cuerpo movido a GoldManagerRestrictions.gd (2026-09-06, "módulos
> gordos", Fase 3). Forwarders de una sola línea: _is_response_only_talisman/
> has_phase_exception/get_phase_rejection_reason/_get_eligible_weapon_
> wielders/_player_has_ally_in_play tienen llamadores externos reales
> (CardInteractionModule.gd, DropZone.gd, CardManager.gd,
> LookRevealPatterns.gd, confirmado por grep de todo scripts/); el resto se
> sigue llamando internamente desde play_card()/play_card_from_exile()/
> play_card_from_cemetery()/_select_weapon_wielder() más abajo.

### `_return_card_rejected` — línea 1809

> Restaurar interactividad (2026-08-21): el Arma se deshabilita al abrir
> la selección de portador (ver play_card()) — si esa selección se
> cancela o el pago falla, la carta debe volver a ser clickeable.

### `_play_card_to_field` — línea 1829

> 2026-10-05, bug real encontrado al convertir más cartas (ver
> arquitectura.md §25): esta función asumía SIEMPRE _main.player_hand/
> player_field/player_linea_apoyo (el Anfitrión), sin importar el
> owner_id real de la carta — roto para cualquier carta jugada vía
> play_card_for_free()/play_card_from_cemetery() en nombre del jugador 1
> (p.ej. La Torre, arco del triunfo, Caín). card.controller_id ya está
> asignado antes de llegar aquí en los 3 caminos (play_card/play_card_
> from_cemetery/play_card_for_free), así que se enruta por eso en vez
> de los contenedores fijos.
> 2026-10-07, bug real encontrado al desbloquear Miguel (ver
> arquitectura.md §38): este 'owner_id' decidía DE QUÉ LADO DEL
> TABLERO aparece la carta — eso es controller_id por definición
> (Card.gd líneas ~165-174: "Quién CONTROLA la carta... de qué lado
> del tablero pelea"), no owner_id (dueño real, a quién vuelve si
> muere). Antes no importaba porque en la práctica owner_id ==
> controller_id siempre (el setter de owner_id los sincroniza) salvo
> en el único caso que los separa a propósito (Miguel, jugar una carta
> de un Cementerio ajeno sin volverte su dueño).

### `_play_card_to_field` — línea 1848

> Crono Diamante (2026-09-02): "si jugaste un Aliado de coste 2 o más
> este turno" — condición previa de su otra habilidad. Se registra aquí
> porque es el único lugar real donde un Aliado termina jugado, sin
> importar el origen (mano, Exhumar, gratis) — los tres caminos
> (play_card/play_card_from_cemetery/play_card_for_free) pasan por
> esta misma función para Aliados/Tótems.

### `_play_card_to_field` — línea 1864

> Solo si de verdad sigue en la mano (2026-08-23): un Aliado/Tótem
> jugado via Exhumar (play_card_from_cemetery) nunca estuvo en la mano —
> remove_child() sobre un nodo que no es hijo tira error (mismo bug ya
> corregido en _equip_weapon() para Lobo Sagrado).

### `_play_card_to_field` — línea 1872

> Tótems van a Línea de Apoyo; Aliados y Armas a Línea de Defensa
> (DAR — 3 zonas reales dentro del campo, ver consolidación 2026-08-20).

### `_play_card_to_field` — línea 1888

> Escala del campo (2026-08-29, a pedido del usuario: 'las cartas ahora
> en juego están muy chicas, agrándalas'): los Aliados vuelven a 1.0.
> Los Tótems se quedan en 0.8 — la Línea de Apoyo es más baja que una
> carta a escala 1.0 y terminaba tapada por la Mano (2026-08-26, no se
> tocó la geometría de Main.tscn entonces, revertido a pedido).

### `_play_card_to_field` — línea 1895

> Slot fijo en vez de la posición que el HBoxContainer calculaba
> (2026-08-31, a pedido del usuario: 'cuando 1 ataque, el otro toma su
> puesto' — con el Container reordenando TODO cada vez que entraba/salía
> un hijo, los Aliados/Tótems ya en juego se corrían de lugar solos. Ver
> ZoneManager.pin_card_to_field_slot()).

### `_apply_crono_diamante_annul_protection` — línea 1916

> Segunda habilidad de Crono Diamante (2026-09-02): 'tu primer Aliado
> o Tótem de coste 2 o más [este turno] no puede ser Anulado' — protege
> solo si el controlador tiene un Crono Diamante en su Reserva de Oro, y
> solo la PRIMERA vez por turno (turn_registry, mismo patrón que el
> resto de 'una vez por turno' de este archivo). Marca la carta con
> set_meta(), consultado en TargetedEffectExecutor._execute_targeted_annul().
>
> La otra mitad de esa misma oración ('la primera habilidad de Oro que
> utilices cada turno no puede ser cancelada') queda SIN implementar a
> propósito: este motor todavía no resuelve 'Cancelar' como una acción
> real ejecutable (solo Anular tiene un choque real, ver
> _execute_targeted_annul()) — no hay ningún lugar de verdad donde
> consultar esa protección todavía. Ver docs/plans/2026-09-02-prevention-
> response-window-design.md para el sistema más grande del que esto
> terminaría formando parte.

### `_apply_crono_diamante_annul_protection` — línea 1932

> 2026-10-12 (§57): también para el jugador 1 — su Reserva es opponent_gold.

### `_check_primer_sello_cemetery_trigger` — línea 1951

> 'Si está en tu Cementerio, una vez por turno, cuando juegues una
> carta Sello, tu oponente Bota una carta' (Primer Sello, 2026-09-20 — ver
> SearchOwnZonePatterns.try_execute_primer_sello_pattern()). Habilidad
> DESDE EL CEMENTERIO: sin precedente en el proyecto, así que se engancha
> aquí, el único punto real por el que pasa TODA carta jugada de CUALQUIER
> tipo (arquitectura.md §1 — Aliado/Arma/Tótem/Oro entran por aquí antes
> de disparar su propio 'Cuando entra en juego'; Talismán entra por aquí
> también, antes de la rama que lo manda a resolve_talisman() un poco más
> abajo), en vez de inventar un signal nuevo 'card_played'.
> 'una carta Sello' se identifica por nombre (igual que _search_sello_
> to_hand() en SearchOwnZonePatterns.gd — 'Sello' no es Raza impresa).
> Cuenta también jugar el propio Primer Sello por segunda vez (con otra
> copia ya en el Cementerio) — el texto no lo excluye.

### `_check_los_siete_sellos_trigger` — línea 1981

> 'Los Siete Sellos' (Oro, 2026-09-20): 'Hasta dos veces por turno,
> cuando se resuelva el efecto de uno de tus Talismanes Sello, tu oponente
> Bota dos cartas.' Se llama SOLO cuando un Talismán terminó de resolver
> de verdad (ver _trigger_enter_play(), rama TALISMAN) — 'tus' = el mismo
> controller_id que el Talismán que acaba de resolver, así que "Los Siete
> Sellos" debe pertenecer y estar EN JUEGO (Reserva) del mismo jugador.
> 'no puede ser convertido' ya queda cubierto gratis por la protección
> genérica de Convertir (_target_text_denies() en TargetedEffectExecutor.gd/
> GoldConversionPatterns.gd, que lee el propio texto de la carta objetivo)
> sin necesitar código aparte aquí. 'no pagas costes adicionales mientras
> juegas o utilizas la habilidad de cartas Sello' NO se implementó: no
> existe en el proyecto ningún efecto que imponga un coste adicional al
> OPONENTE por jugar/usar una carta (ver arquitectura.md §12.5) — no hay
> nada real que esta cláusula esté exceptuando todavía.

### `_check_llave_del_abismo_enter_aura` — línea 2026

> 'Tus Aliados ganan 1 de Fuerza e Indestructible' (Llave del Abismo,
> Oro, 2026-09-20, arquitectura.md "539 cartas sin cobertura") — aura
> PERMANENTE mientras esté en juego, mismo mecanismo de auras "Tus
> Aliados" ya usado por arco del triunfo (TotemAbilityPatterns.gd). Se
> engancha aquí (en vez del despachador de triggers) porque Llave del
> Abismo NO tiene ninguna cláusula "cuando entra en juego" propia — su
> única cláusula con disparador es la reactiva de más abajo, así que
> nunca se encolaría para on_enter_play si se intentara por ese camino.
> Se limpia sola al salir de juego (Card._exit_tree() → remove_modifiers_
> from_source(), mismo criterio que cualquier otro modificador con
> source=esta carta).

### `_check_llave_del_abismo_reactive` — línea 2065

> 'Cuando un Aliado con Furia entra en juego bajo tu control, tu
> oponente Bota una carta. Puedes utilizar esta habilidad más de una vez
> por turno' (Llave del Abismo, 2026-09-20) — reactiva a que OTRA carta
> (un Aliado con Furia) entre en juego bajo el mismo controlador que
> tiene Llave del Abismo en Reserva/Oro Pagado. Enganchada aquí (chequeo
> directo sobre la carta recién jugada) en vez de por el sistema de
> trigger_type 'on_ally_enters' — ese camino exige que el texto matchee
> una de las frases fijas de Card.TRIGGER_KEYWORDS['on_ally_enters']
> ('cuando otro aliado entre'/'cuando un aliado entre'), y el texto real
> de esta carta ('cuando un aliado CON FURIA entra en juego BAJO TU
> CONTROL') no calza con ninguna de esas dos por la inserción de 'con
> Furia' — mismo criterio directo que _check_primer_sello_cemetery_
> trigger()/_check_los_siete_sellos_trigger() de arriba, más simple y
> sin depender del parseo de frases. 'Más de una vez por turno' = sin
> tope, dispara cada vez que corresponda.

### `check_libro_de_thoth_block` — línea 2101

> 'Cuando bloquees, genera un Oro por el turno' (libro de thoth, Oro,
> 2026-09-20, arquitectura.md "539 cartas sin cobertura") — reactiva a que
> CUALQUIER Aliado tuyo bloquee, no una habilidad impresa en el propio
> bloqueador. Enganchada desde GameManager.confirm_blockers_and_collect_
> triggers() (una vez por bloqueador confirmado, mismo criterio que
> 'cuando ataque' en confirm_attackers()), con chequeo directo del Oro en
> juego — mismo patrón que _check_llave_del_abismo_reactive() de arriba,
> sin depender del parseo de frases de Card.TRIGGER_KEYWORDS (ese camino
> de trigger_type solo llega a la carta que disparó el evento —aquí, el
> Aliado bloqueador—, nunca a otra carta pasiva en una zona distinta,
> como un Oro en Reserva/Oro Pagado). Sin restricción de para qué sirve
> el Oro generado (el texto no la especifica), mismo criterio que Cañón
> Naval (WeaponAbilityPatterns.gd).

### `_discard_oro_from_reserva` — línea 2131

> Descarta (al Cementerio) un Oro FÍSICO que está en Reserva — no existe
> en el proyecto ningún camino genérico para esto (discard() de
> ActionReturnDiscard.gd es solo desde la MANO, ver su propio docstring).
> Costo de Cuarto Sello ('Puedes pagar un Oro y Descartarlo...', 2026-09-20)
> — mismo orden de limpieza que ActionReturnDiscard.return_to_deck() para
> una carta en juego (desconectar señales antes de queue_free, actualizar
> Reserva/gold_cards y el contador de GameState).

### `_take_gold_out_of_play` — línea 2155

> Saca un Oro de la Reserva u Oro Pagado (contadores incluidos) y
> devuelve sus datos; el llamador decide el destino (2026-10-14).

### `_trigger_enter_play` — línea 2198

> Dispara la entrada al juego (DAR 7.4) para habilidades 'Al entrar' de
> Aliados/Armas/Oro/Tótems. Para Talismanes es distinto (2026-08-27): no
> 'disparan' nada, se resuelven directo vía TriggerSystem.resolve_talisman()
> sin pasar por la cola de triggers — ver el branch de card_type más abajo.
>
> Este método mueve la carta directamente (ver player_field.add_child arriba)
> en vez de pasar por EffectController.play_card_to_zone(), porque esa función
> depende de un GameBoard legacy que no está activo en la escena actual (su
> @onready apunta a nodos de un layout de tablero anterior — BattleField/
> PlayerLineaDefensa/etc. — que ya no existe en Main.tscn).
>
> CardEffectSystem sigue escuchando la señal (fire-and-forget) solo para
> recalcular efectos continuos — su propia ejecución de texto está
> desactivada a propósito para no duplicar el efecto. Pero el trigger en
> sí (TriggerSystem → UniversalCardParser → ActionModule) se llama DIRECTO
> con 'await' en vez de por señal: conectado por señal, quien juega la
> carta no esperaba a que el trigger terminara de resolverse, así que el
> juego seguía de fase mientras el trigger todavía se procesaba en
> segundo plano — se vio con Drácula y Signo Amarillo resolviendo solo
> en la fase de Bloqueo, varios pasos después de jugarse.
>
> Los Talismanes se ramifican ANTES de todo esto (2026-08-28, a pedido
> del usuario): un Talismán nunca 'entra en juego' (DAR Sección 8, ver
> _play_talisman()), así que no pasan por CardFactory.on_card_enters_play()
> ni Card.on_entered_play() (ambos son bookkeeping de 'entró al campo' —
> Furia/summoning sickness, bind a la cola de triggers — que no aplica a
> un Talismán) ni emiten on_card_entered_play (evitaba que CardEffectSystem
> lo logueara como si hubiese entrado a Línea de Apoyo). Antes estos tres
> pasos corrían igual para Talismanes y dejaban logs falsos tipo 'entró en
> juego'/'entró a Línea de Apoyo' incluso jugándolo via Exhumar desde el
> Cementerio, donde nunca pisa una zona de juego real.

### `_trigger_enter_play` — línea 2231

> Llave del Abismo (Oro, 2026-09-20, arquitectura.md "539 cartas sin
> cobertura") — dos chequeos directos sobre TODA carta jugada, mismo
> choke point que los Sellos de arriba: registra su propia aura al
> entrar ella misma, y reacciona cuando OTRO Aliado con Furia entra
> bajo el mismo controlador (ver docstrings de ambas funciones).

### `_trigger_enter_play` — línea 2252

> Un Talismán no dispara nada (DAR Sección 8): su texto ES el efecto
> de jugarlo, se resuelve directo — no pasa por has_trigger() ni por
> la cola compartida de TriggerSystem (2026-08-27, a pedido del
> usuario: "los Talismanes no disparan, resuelven"). resolve_talisman()
> ya abre su propia ventana de respuesta real ANTES de resolver (Pila
> de Respuesta Universal, 2026-09-09) — devuelve true si fue
> anulado/cancelado ahí, para que _play_talisman() lo mande al
> Cementerio sin mirar su propio texto para decidir destino.

### `_trigger_enter_play` — línea 2261

> "Los Siete Sellos" (Oro, 2026-09-20): 'Hasta dos veces por turno,
> cuando se resuelva el efecto de uno de tus Talismanes Sello, tu
> oponente Bota dos cartas' — solo si el efecto REALMENTE resolvió
> (no si fue anulado/cancelado en la ventana de arriba, ver
> TriggerSystem.resolve_talisman()).

### `_trigger_enter_play` — línea 2270

> CARD_PLAYED para Aliado/Arma/Tótem/Oro (2026-09-10, Pila de Respuesta
> Universal). A diferencia de un Talismán, aquí la carta YA está
> físicamente en una zona de juego (jugarla y que entre en juego no son
> el mismo momento del DAR) — reescribir cada camino de juego (play_card,
> _equip_weapon, _place_card_as_gold, las búsquedas que colocan directo)
> para abrir la ventana ANTES de animar/crear el Node hubiera exigido un
> destino nuevo (Cementerio directo desde la mano) sin poder reusar
> destroy_card() (exige zona de juego válida). Aproximación acordada con
> el usuario: la ventana se abre AQUÍ, justo antes de que dispare su
> propio "Cuando entra en juego" — se la ve entrar igual que hoy, pero si
> se anula/cancela aquí su ETB nunca dispara y va directo al Cementerio
> (mismo destino por defecto que cualquier Anular, igual que el Talismán
> de arriba).

### `_trigger_enter_play` — línea 2284

> Dhampir (2026-10-17): "Cuando tu oponente juegue una carta" — los Oros
> se ponen en juego, no se juegan.

### `_trigger_enter_play` — línea 2306

> 2026-09-20 (auditoría de Task 1.3, remote-multiplayer-parity Fase 1):
> estos tres usaban "0" fijo en vez de 'controller_id' (ya calculado un
> poco más arriba, línea 1447, para la ventana de respuesta). Mientras
> _equip_weapon() solo se llamaba para Armas del Anfitrión (owner_id
> siempre 0) esto nunca se notaba — pero _play_weapon_remote() (nuevo,
> RemotePlayerController.gd) llama a _equip_weapon() para Armas del
> jugador 1 (Remoto), y GameStateBroadcaster._on_card_entered_play()
> decide "own"/"opponent" leyendo justo este player_id — con "0" fijo,
> un Arma jugada por el Remoto se mostraba como si la hubiera jugado el
> Anfitrión del otro lado de la red. Mismo bug que la nota de Task 1.2
> ya advertía sobre _trigger_enter_play() en general.

### `_trigger_enter_play` — línea 2324

> Almirante Akari — "cuando tu oponente juegue cartas, puedes Anular"
> (2026-09-09). Se ofrece DESPUÉS de que el ETB propio ya resolvió —
> distinto de la ventana de arriba (esa cubre CUALQUIER anulación antes
> del ETB; esta es la habilidad puntual de Akari, que sigue viviendo
> aquí por si Akari no estaba entre los candidatos de la ventana genérica
> — offer_counter_annul() tiene su propio chequeo interno, no duplica
> la pregunta si ya se resolvió arriba).

### `_trigger_enter_play` — línea 2336

> "El próximo Talismán que juegues este turno reduce su coste en un Oro,
> hasta un mínimo de 1 y no puede ser Anulado" (Rey de los Loñolicos,
> 2026-10-14). Por jugador: {token: Node (fuente del modificador de coste),
> no_annul: bool, turn: int}. Se consume en _play_talisman() y vence al
> cambiar de turno.

### `_play_talisman` — línea 2392

> Rastreo por jugador de 'ya jugó un Talismán este turno' (2026-09-04,
> p.ej. Fuente de la Juventud: 'les cuesta un Oro adicional jugar
> Talismanes SI han jugado Talismanes este turno' — la condición del
> impuesto la consulta _register_talisman_second_play_tax() más abajo).
> 2026-10-07: controller_id, no owner_id — de qué lado del tablero
> aparece es cuestión de CONTROL, no de dueño real (ver arquitectura.md
> §38, mismo arreglo que _play_card_to_field()).

### `_play_talisman` — línea 2402

> 2026-10-05, bug real encontrado al convertir más cartas: esta función
> asumía siempre _main.player_hand/player_field (el Anfitrión) sin
> importar quién controla el Talismán — roto para cualquier Talismán
> jugado vía play_card_for_free()/play_card_from_cemetery() en nombre
> del jugador 1 (ver arquitectura.md §25). Se enruta por talisman_owner,
> el mismo que ya usa el resto de esta función más abajo.

### `_play_talisman` — línea 2425

> _trigger_enter_play() ya queda 'await'-eado hasta el final de verdad
> (resolve_talisman() → _resolve_look_and_play_patterns(), toda la
> cadena incluye cualquier elección anidada del jugador) — la espera
> fija que había aquí después ("dar tiempo a que la habilidad resuelva")
> era pura demora sin motivo real, la carta quedaba pegada en Línea de
> Apoyo un rato de más después de haber terminado (2026-08-30, a pedido
> del usuario: los Talismanes deben irse al Cementerio apenas resuelven,
> no quedarse dando vueltas).

### `_play_talisman` — línea 2436

> Pila de Respuesta Universal (2026-09-09): anulado/cancelado durante
> la ventana de respuesta real que resolve_talisman() ya abrió — su
> efecto NUNCA resolvió, así que no corresponde mirar el propio texto
> de la carta para decidir destino (ni "destiérralo" ni "barájala"
> aplican a un efecto que no ocurrió) — va directo al Cementerio,
> mismo destino por defecto que cualquier Anular.

### `_play_talisman` — línea 2452

> 2026-09-08, bug real reportado por el usuario (Golpe Solar se quedaba
> en juego en vez de desterrarse solo): "destierr" (sin tilde) NO
> matchea "destiérralo"/"destiérrala" — el pronombre enclítico "-lo"/
> "-la" pegado al verbo mueve el acento y SÍ lleva tilde en español
> correcto ("destierra" sola no la lleva, pero "destiérralo" sí),
> aunque el texto esté bien escrito sin ningún mojibake de por medio.
> Solo si se destierra a SÍ MISMO (2026-10-17, bug real reportado por el
> usuario: Cuervo Nocturno, jugado de la mano, se desterraba por su
> "Destierra seis cartas del tope del Castillo oponente").

### `_play_talisman` — línea 2466

> "barájala"/"barajala" (2026-08-30, antes bastaba "baraj" sin más —
> falso positivo real con Aaru: su texto dice 'Baraja cualquier cantidad
> de cartas de tu MANO', un efecto sobre OTRAS cartas, no sobre sí
> mismo, y el check viejo lo mandaba de vuelta al mazo en lugar de al
> Cementerio). El pronombre reflejo "-la" es lo que de verdad distingue
> 'esta carta se baraja a sí misma' de cualquier otro uso del verbo.
> "barájalo" (2026-10-14, Visión de Enoc: "Cuando se resuelva, Barájalo
> en tu Castillo").

### `_play_talisman` — línea 2477

> card.owner_id, no 0 fijo (2026-08-29): esta función asumía siempre
> Talismanes propios (jugados de la mano del jugador humano, owner_id=0
> de por sí), pero con Miguel ('juega una carta de... un Cementerio')
> ahora puede ser un Talismán del RIVAL jugado desde SU Cementerio —
> owner_id sigue siendo suyo (el que controla el efecto es otra cosa,
> ver controller_id), así que debe volver a SU Cementerio/Destierro, no
> al del jugador que lo jugó.

### `_play_talisman` — línea 2494

> self_exile respeta el texto propio de la carta tal cual, sea cual
> sea el camino por el que se jugó (2026-08-29, corregido a pedido
> del usuario): "no tengan condición de juego que te obligue a
> mandarlas al destierro" — si SÍ la tiene (dice "destiérralo"), se
> destierra igual jugada desde el Cementerio o no. La única regla
> que fuerza Destierro PASE LO QUE DIGA el texto es Exhumar de
> verdad (is_exhumed, arriba) — jugar desde el Cementerio por otro
> efecto (Miguel) no agrega ninguna regla nueva aquí, cae en el
> comportamiento normal de siempre.

### `_play_talisman` — línea 2506

> is_being_destroyed=false (2026-09-04, bug reportado: texto de
> consola decía 'fue destruida' — un Talismán que ya resolvió su
> efecto y va al Cementerio por defecto no es una 'destrucción'
> DAR, solo cambia el texto que imprime, mismo camino/señales.

### `pagar_coste` — línea 2532

> card_type/card_race/card_cost identifican QUÉ se está pagando — sin
> esto no hay forma de saber si el Oro Virtual restringido aplica (p.ej.
> Padre de la Patria: 'para jugar Armas o Aliados Caballero' — usa
> card_type/card_race). Pasar -1/"" cuando no corresponda (p.ej. una
> habilidad activada sin carta objetivo) para que el pago ignore los pools
> restringidos de forma segura.
>
> 'player_id' (2026-10-06, ver arquitectura.md §33): de qué jugador se paga
> — Oro Virtual, Oro Virtual restringido y Oro físico son todos por
> jugador ahora. Default 0 preserva el comportamiento de todos los
> llamadores existentes que no lo pasaban (siempre el Anfitrión).

### `pagar_coste` — línea 2580

> Elegir CUÁLES Oros físicos se gastan (2026-09-03, a pedido del
> usuario) — antes se tomaban los primeros N de get_children() sin
> que el jugador eligiera nada, lo que hacía imposible usar cartas
> como Monitor Araucano ('Este Oro genera un Oro adicional cuando
> sea usado para pagar Armas de coste 2 o más'): no había forma de
> saber si FUE ese Oro puntual el que pagó. Los Oros Virtuales
> (restringido y genérico, arriba) siguen siendo los primeros en
> gastarse siempre — esto solo decide el orden DENTRO del Oro
> físico, cuando de verdad hace falta.
>
> Se elige el orden completo UNA SOLA VEZ (bug real: llamar a
> _choose_physical_gold_to_spend() de nuevo en cada vuelta del bucle
> de abajo reabre su propio bucle interno de selección entero cada
> vez, preguntando 3+2+1=6 veces para restante=3 en vez de 3 — esa
> función ya junta por sí sola tantas cartas como pida 'restante',
> no devuelve una sola).
> Solo Oros físicos (2026-10-17, bug real reportado por el usuario:
> con 3 Oros + 1 Oro generado para Armas/Tótems, jugar un Aliado de
> coste 3 te hacía elegir — la Reserva también tiene las fichas de
> Oro Virtual, genérico y restringido, que no se pagan así).

### `pagar_coste` — línea 2607

> 2026-09-11 (a pedido del usuario, corrigiendo un diseño anterior):
> se gasta un Oro físico A LA VEZ (no todos de una) porque "genera un
> Oro adicional CUANDO SEA USADO PARA PAGAR" implica que ese Oro
> nuevo cuenta para ESTA MISMA compra, no que quede de sobrante sin
> tocar — si Monitor Araucano paga un Arma de coste 2, el segundo
> Oro de esa compra lo pone él mismo, no tu Reserva. Por eso antes de
> sacar el siguiente Oro físico (ya elegido arriba) se revisa si ya
> apareció Oro Virtual nuevo que cubra parte de lo que falta.

### `pagar_coste` — línea 2632

> diverted cuenta las unidades que NO terminaron en Oro Pagado de
> verdad (2026-08-29, p.ej. Jormundgander: '...convierte este Oro
> en un Aliado y muévelo a tu Línea de Defensa' en vez del
> movimiento normal) — GameState.pagar_oro() de abajo suma
> physical_spent sin saber esto, así que hay que restar la
> diferencia después o el próximo Reagrupamiento regala Oro de
> más que nunca existió físicamente en la pila.

### `_choose_physical_gold_to_spend` — línea 2656

> Elige qué Oros físicos de Reserva se gastan para pagar 'restante'
> unidades (2026-09-03, a pedido del usuario — ver _resolve_gold_paid_
> reaction()). Sin elección real (hay que gastarlos todos, o solo queda
> uno) no pregunta nada, para no agregar fricción sin necesidad.

### `_choose_physical_gold_to_spend` — línea 2665

> Clic directo sobre las cartas (2026-09-03, a pedido del usuario —
> reemplaza el picker modal de antes): mismo mecanismo de "elegir
> objetivo" que ya usa el resto del juego (Anular, Convertir, banear
> del Cementerio rival, etc.) — CardInteractionModule.await_target(),
> con el brillo celeste de "activable" (Card.set_activatable()) como
> indicador visual de cuáles Oros son válidos para elegir ahora.

### `_resolve_gold_paid_reaction` — línea 2709

> Detecta 'Este Oro genera un Oro adicional cuando sea usado para
> pagar X [de coste N o más]' en el texto del Oro que EFECTIVAMENTE pagó
> (2026-09-03, p.ej. Monitor Araucano) — solo se llama con el nodo físico
> real ya elegido en _choose_physical_gold_to_spend(), así que 'usado
> para pagar' aquí es literal, no una aproximación.

### `_resolve_gold_paid_reaction` — línea 2720

> Trono del Cielo (2026-10-18): "Si en su turno anterior tu oponente
> generó o puso en juego más de un Oro, cuenta como dos Oros para pagar
> el coste de una carta."

### `_resolve_gold_paid_reaction` — línea 2727

> Alicanto (2026-10-14): "Los Aliados de coste 2 o más pagados con este
> Oro no pueden ser Anulados" — se marca y lo toma el próximo Aliado que
> entra (_trigger_enter_play), antes de su ventana de respuesta.

### `limpiar_oros_virtuales` — línea 2772

> Limpia AMBOS jugadores siempre (2026-10-06): "Oro por el turno" expira
> al empezar cualquier turno nuevo, sin importar de quién sea ni quién
> lo generó — mismo criterio que oro_colocado_conteo/_no_more_cards_
> this_turn, que ya se resetean así en _on_turn_started_clear_virtual_gold().

### `generar_oro_virtual_restringido` — línea 2813

> until_own_next_turn (2026-10-14, Sariel: "Puedes usar ese Oro hasta el
> comienzo de tu próximo turno"): sobrevive al comienzo del turno rival.

### `_mover_oro_a_pagado` — línea 2908

> Returns: true si la carta se DESVIÓ del movimiento normal (2026-08-29,
> Jormundgander: revert_to_data marcado por convert_ally_to_gold_in_pagado()
> — en vez de ir a Oro Pagado, vuelve a ser el Aliado original), false si
> se movió a Oro Pagado normalmente. El llamador (pagar_coste()) usa el
> valor de retorno para no contar de más en GameState.oro_pagado.

### `_mover_oro_a_pagado` — línea 2916

> controller_id, no siempre 'player' (2026-08-31, Tyet: 'Puedes pagar
> este Oro para que un Oro pierda su habilidad este turno y muévelo al
> Oro Pagado' — el texto real no dice 'de tu Reserva' ni 'tuyo', así que
> el Oro elegido puede ser del rival; antes esta función asumía siempre
> _main.player_gold/player_oro_pagado y tronaba (remove_child sobre el
> padre equivocado) apenas se probaba con un Oro rival).

### `_revert_gold_to_ally` — línea 2942

> 'Si esta carta es un Oro, cuando lo pagues para jugar un Aliado,
> convierte este Oro en un Aliado y muévelo a tu Línea de Defensa'
> (Jormundgander, 2026-08-29) — la otra mitad de convert_ally_to_gold_in_
> pagado(): en vez de terminar en Oro Pagado como cualquier Oro gastado,
> esta carta específica vuelve a ser el Aliado original y entra en juego
> de nuevo.

### `_revert_gold_to_ally` — línea 2960

> Slot fijo (2026-08-31) — ver ZoneManager.pin_card_to_field_slot() y el
> mismo motivo en GoldManager._play_card_to_field().

### `_revert_gold_to_ally` — línea 2975

> Azi del Abismo (2026-10-17): "convertir este Aliado hasta tu próximo
> turno en un Oro con la habilidad ...". Queda en tu Oro Pagado (fe de
> erratas, confirmado por el usuario; antes era la Reserva) con esa
> habilidad y, al empezar tu próximo turno, vuelve a ser el Aliado original
> en tu Línea de Defensa (revert_converted_golds()). No usa revert_to_data
> (eso es Jormundgander: volver a Aliado al pagarlo).

### `convert_ally_to_gold_in_pagado` — línea 3079

> 'Cuando haga daño, puedes convertirlo en un Oro y moverlo a tu Oro
> Pagado' (Jormundgander, 2026-08-29) — transforma un Aliado en juego en
> un Oro y lo mueve directo a Oro Pagado (ya 'gastado' hasta el próximo
> Reagrupamiento, no disponible para pagar nada este turno). Guarda los
> datos originales en card.revert_to_data — _mover_oro_a_pagado() los usa
> para reconvertir el Oro en Aliado si de verdad se lo paga más adelante
> (la otra mitad del texto de esta misma carta).

### `convert_ally_to_gold_in_pagado` — línea 3089

> 2026-10-12 (§57): también para el jugador 1 (su Oro Pagado).

### `_reset_gold` — línea 3144

> Reagrupamiento del Oro (DAR, Agrupación): todo el Oro Pagado propio
> vuelve a la Reserva al empezar el turno. Llamada desde PhaseFlowController
> en el caso AGRUPACION, pero no existía en ningún lado de este archivo
> (2026-09-02, mismo tipo de corrupción ya encontrado y arreglado en
> update_gold_containers_spacing()/puede_pagar()/_revert_gold_to_ally()/
> get_oro_disponible() — funciones llamadas sin definición). GameState.
> reagrupar_oro() ya existe y resetea los contadores reales; aquí se
> mueven las cartas VISUALES de vuelta una por una con
> _mover_oro_a_reserva(), que ya existe pero no toca GameState (por eso
> el orden: contadores primero, visual después).

### `_reset_gold` — línea 3158

> el huascar (2026-10-18): "no puede ser agrupado el próximo turno"

## `scripts/core/game/GoldManagerRestrictions.gd`

### `(nivel de archivo)` — línea 2

> GoldManagerRestrictions — Elegibilidad para jugar una carta: Errante ('solo
> una copia en juego'), 'Sólo puedes jugar un <Nombre> por turno', Talismanes
> de respuesta instantánea (Anula/Cancela — 'Red de Plata'/'Sacrificio
> Solar'), portadores de Arma disponibles, y las excepciones de fase (Arma/
> Talismán en Guerra de Talismanes, 'Lobo Sagrado'). Extraído de
> GoldManager.gd (2026-09-06, "módulos gordos", Fase 3) — confirmado por grep
> de todo scripts/ que _get_eligible_weapon_wielders() (CardManager.gd),
> _player_has_ally_in_play() (LookRevealPatterns.gd, DropZone.gd),
> _is_response_only_talisman()/has_phase_exception()/get_phase_rejection_
> reason() (CardInteractionModule.gd, DropZone.gd) tienen llamadores reales
> fuera de GoldManager.gd — GoldManager.gd sigue exponiendo esas cinco bajo
> el mismo nombre como forwarder de una sola línea (junto con
> _errante_violation/_play_limit_violation/_register_play_limit/
> _is_response_only_talisman_data, que solo tienen llamadores internos
> propios en play_card()/play_card_from_exile()/play_card_from_cemetery()).
> El resto (_has_play_limit_phrase, _is_response_only_ability_text,
> _ally_weapon_count, _max_weapons_per_ally,
> _can_play_weapons_in_guerra_talismanes) no tiene ningún llamador fuera de
> este mismo módulo, así que no necesita forwarder.
>
> _main es Main (mismo significado que en el resto de GoldManager.gd) — el
> único estado propio de GoldManager que este módulo necesita
> (_fix_mojibake()) se alcanza vía _main._gold_manager, el back-reference
> que Main.gd ya mantiene hacia su propia instancia de GoldManager (mismo
> patrón que ya usan CardInteractionModule/DropZone/CardManager/
> LookRevealPatterns para llamar a GoldManager desde afuera).

### `_errante_violation` — línea 39

> Errante (keyword real de Mitos y Leyendas, corrección 2026-08-20):
> solo puede haber una copia de esta carta en juego a la vez, sin importar
> el controlador. Distinto de Única, que limita copias en el MAZO.

### `_play_limit_violation` — línea 57

> 'Sólo puedes jugar un <Nombre> por turno' (2026-08-30, p.ej. Aaru) —
> restricción de JUGAR la carta en sí (distinta de 'una vez por turno'
> sobre una habilidad ACTIVADA), por NOMBRE y compartida entre todas las
> copias: si ya jugaste un <Nombre> este turno, no puedes jugar un segundo
> aunque sea una copia distinta. Se registra en UniversalCardParser.
> turn_registry con un prefijo propio ('play_limit:') para no compartir
> namespace con el registro de habilidades ACTIVADAS (card_id/ability_index
> numéricos).

### `_allies_shown_violation` — línea 79

> Camino del Guerrero (2026-10-18): 'Sólo puedes jugar esta carta si
> controlas y/o muestras de tu mano al menos cuatro Aliados' — los que
> controlas más los Aliados de tu mano (que muestras) deben sumar cuatro.

### `_has_play_limit_phrase` — línea 104

> 'Sólo puedes jugar un <Nombre> por turno' (p.ej. Aaru), su variante
> en voz pasiva 'Sólo puede ser puesto en juego un <Nombre> por turno'
> (2026-09-04, p.ej. La Torre), o la negativa 'no puedes poner en juego
> más de un <Nombre> por turno' (2026-09-04, p.ej. rafael) — mismo
> concepto DAR, tres formas de imprimirlo.

### `_is_response_only_talisman_data` — línea 148

> Espejo de _is_response_only_talisman() para código que todavía opera
> sobre Dictionary en vez del Node Card (2026-09-06, p.ej.
> play_card_from_cemetery() antes de instanciar la carta) — misma
> detección, mismo criterio.

### `_is_response_only_ability_text` — línea 160

> "Cancela una habilidad o una carta en juego pierde su habilidad"
> (Maldición Vudú, 2026-10-18): la otra opción no es una respuesta.

### `_is_response_only_ability_text` — línea 164

> Sidhes del Bosque (2026-10-18, a pedido del usuario): "Puedes
> jugarlo en respuesta a que tu oponente fuera a buscar..." es un
> momento EXTRA (EffectController.offer_sidhes); también se juega
> normal en tu Vigilia o en Guerra de Talismanes.

### `_player_has_ally_in_play` — línea 177

> Verifica si hay al menos un Aliado en juego (propio o rival, 2026-
> 09-03) SIN Arma ya equipada (requisito para poder jugar un Arma — un
> Aliado solo porta una a la vez, y sin portador libre no tiene
> sentido). Antes solo miraba si había
> CUALQUIER Aliado, sin importar si ya portaba Arma — dejaba pasar a
> _select_weapon_wielder() con cero candidatos elegibles de verdad y esa
> selección se quedaba colgada para siempre (2026-08-28, bug reportado por
> el usuario: intentar jugar un Arma sin portador válido lo dejaba sin
> poder jugar más cartas).

### `_get_eligible_weapon_wielders` — línea 190

> Aliados en juego (propios O RIVALES, 2026-09-03 — DAR no restringe a
> quién controlas: un Arma se puede portar en cualquier Aliado en juego,
> salvo que el propio texto de la carta lo diga) que todavía tienen
> espacio para portar un Arma más (normalmente 1, o más con 'Tus Aliados
> pueden portar un Arma adicional' en juego — ver _max_weapons_per_ally(),
> 2026-08-31, Levisterio).

### `_max_weapons_for` — línea 212

> Cuántas Armas puede portar ESTE Aliado (2026-10-14, a pedido del
> usuario con Carro Szgany). Antes era un número global que solo miraba
> los Aliados del Anfitrión ("Tus Aliados pueden portar un Arma
> adicional") y lo aplicaba a todos, rivales incluidos; los Oros
> (Levisterio, Carro Szgany) no se miraban nunca. Ahora:
> - 1 por defecto;
> - +1 si el propio Aliado dice "puede portar un Arma adicional" (Vinci y
> Yang, Húsar Cazador);
> - +1 por cada carta en juego de SU controlador (Aliados, Armas, Tótems
> y Oros) con "Aliados pueden portar un Arma adicional" (Levisterio,
> Patrulla Nocturna);
> - +1 por Carro Szgany del controlador si controla Caballeros,
> Guerreros o Héroes y este es su Aliado de mayor coste (empates: todos).
> Las cartas sin habilidad (silenciadas/convertidas) no cuentan.

### `_max_weapons_for` — línea 227

> "Los Aliados oponentes no pueden portar Armas" (Sariel, 2026-10-14):
> solo impide equipar Armas nuevas; las que ya portaba se quedan
> (usuario) — por eso no cuenta cuando for_new_weapon es false.

### `_max_weapons_for` — línea 267

> Carro Szgany (2026-10-18, regla del usuario): el Arma adicional es para
> UN solo Aliado de mayor coste (cualquier raza). Empatados: el que ya
> porta más Armas se la queda; si ninguno la usa, cualquiera puede. Si
> entra uno de mayor coste, el anterior deja de serlo y pierde la primera
> Arma que portaba (_enforce_weapon_capacity).

### `_can_play_weapons_in_guerra_talismanes` — línea 311

> Detecta 'Puedes jugar Armas en Guerra de Talismanes' (p.ej. Lobo
> Sagrado) en el propio jugador (2026-08-28) — misma técnica de
> escaneo-de-texto que _register_talisman_totem_tax(), pero como chequeo
> de legalidad puntual en vez de un modificador registrado, porque aquí
> solo importa el instante de jugar el Arma, no algo que deba persistir.
> 'player_id' (2026-10-07, ver arquitectura.md §34): play_card() ya puede
> jugarse en nombre del jugador 1, así que el campo a escanear tiene que
> ser el suyo, no siempre el del Anfitrión.

### `has_phase_exception` — línea 337

> Único punto de verdad para las excepciones de fase (Arma puntual tipo
> Lobo Sagrado + Talismanes en general en Guerra de Talismanes) — antes
> estaba duplicado inline en play_card()/play_card_from_cemetery(), y
> CardInteractionModule._on_card_double_clicked() tenía su PROPIO gateo de
> fase sin conocer esta excepción, así que nunca dejaba ni siquiera
> intentar jugar el Arma/Talismán (2026-08-28, bug reportado por el
> usuario: 'no puedo jugar armas en guerra'). Llamar esto desde cualquier
> punto que decida si una carta se puede jugar fuera de Vigilia.

### `get_phase_rejection_reason` — línea 355

> Mensaje específico de por qué ESTA carta no se puede jugar ahora mismo
> (2026-08-28, a pedido del usuario: el genérico 'Solo puedes jugar cartas
> en Vigilia' no decía si esa carta en particular sí tenía alguna
> excepción posible — un Talismán en Guerra de Talismanes normalmente SÍ
> se puede, un Aliado no puede nunca fuera de Vigilia). Llamar solo cuando
> ya se decidió rechazar (current_phase != VIGILIA and not
> has_phase_exception(card_type)).

## `scripts/core/game/GoldManagerTax.gd`

### `(nivel de archivo)` — línea 2

> GoldManagerTax — Impuestos de coste sobre Talismanes/Tótems/Oro ('jugar
> Talismanes y Tótems cuesta un Oro adicional', Bernardo O'Higgins; 'cuesta
> un Oro adicional si ya jugaste/pusiste uno este turno', Fuente de la
> Juventud) y el descuento de coste por 'muestra X de tu mano/Cementerio/en
> juego' (El Rey y el Verdugo, Shiji). Extraído de GoldManager.gd
> (2026-09-06, "módulos gordos", Fase 3) — confirmado por grep de todo
> scripts/ que ninguna de estas funciones tiene un llamador externo a
> GoldManager.gd. GoldManager.gd sigue exponiendo las cuatro con llamador
> interno propio (_register_talisman_totem_tax/_register_talisman_second_
> play_tax desde _trigger_enter_play(); _get_reveal_cost_reduction_pattern/
> _resolve_reveal_cost_reduction desde play_card()) bajo el mismo nombre,
> como forwarder de una sola línea. _gather_showable_candidates() no tiene
> ningún llamador fuera de _resolve_reveal_cost_reduction() (mismo módulo),
> así que no necesita forwarder.
>
> _main es Main (mismo significado que en el resto de GoldManager.gd) — el
> estado propio de GoldManager que este módulo necesita (oro_colocado_
> conteo, _fix_mojibake()) se alcanza vía _main._gold_manager, el back-
> reference que Main.gd ya mantiene hacia su propia instancia de GoldManager
> (mismo patrón que ya usan CardInteractionModule/DropZone/CardManager/
> LookRevealPatterns para llamar a GoldManager desde afuera).

### `_register_talisman_totem_tax` — línea 34

> Detecta 'jugar Talismanes y Tótems cuesta un Oro adicional' (p.ej.
> Bernardo O'Higgins) y registra el impuesto en PaymentManager — afecta a
> CUALQUIER Talismán/Tótem que se calcule con calcular_coste_real(), del
> dueño que sea (2026-08-26, a pedido del usuario: aplica a los dos
> jugadores por igual).
>
> PaymentManager.cost_modifiers se vacía entero en cada turno nuevo
> (_on_turn_started_clear_modifiers, pensado para descuentos de un solo
> uso como el de Lobo Sagrado) — para que este impuesto dure 'mientras la
> carta esté en juego' (varios turnos), se re-registra en cada
> turn_started mientras la carta siga válida y en juego, y se desconecta
> sola apenas deja de estarlo. La limpieza al salir de juego de verdad la
> hace Card._exit_tree() → PaymentManager.remover_modificador_coste().

### `_register_talisman_totem_tax` — línea 50

> _fix_mojibake() (2026-08-26): la API de ShadowForge trae "TalismÃ¡n"/
> "TÃ³tem" con doble codificación rota para varias cartas (Bernardo
> O'Higgins entre ellas) — sin normalizar, "talismán"/"tótem" nunca
> matcheaban y este impuesto quedaba inerte para esas cartas.

### `_register_talisman_totem_tax` — línea 64

> Afecta a una CATEGORÍA de cartas (todo Talismán/Tótem), no una sola —
> refresca toda la mano, no un solo card_node (2026-08-30).

### `_register_talisman_second_play_tax` — línea 80

> Detecta 'A los jugadores les cuesta un Oro adicional jugar
> Talismanes si han jugado Talismanes este turno y les cuesta un Oro
> adicional poner Oros en juego si han puesto Oros en juego este turno'
> (2026-09-04, p.ej. Fuente de la Juventud). A diferencia de
> _register_talisman_totem_tax() (impuesto FIJO, siempre activo, propio
> de Bernardo O'Higgins), aquí el impuesto es CONDICIONAL por jugador:
> solo la SEGUNDA carta de ese tipo en el mismo turno lo paga, la
> primera sigue gratis. 'A los jugadores' = ambos, no solo el rival —
> la condición mira el owner_id de la carta candidata, no quién controla
> esta fuente.
>
> La mitad de Talismanes tiene un gancho de pago real: _play_talisman()
> registra 'talisman_played:<owner_id>' en turn_registry apenas resuelve
> el primero, ANTES de que un segundo se cotice. La mitad de Oro queda
> registrada como dato correcto pero hoy INERTE: play_card() manda los
> Oro directo a _place_card_as_gold() sin pasar nunca por PaymentManager.
> calcular_coste_real() — no existe en este motor una acción de 'pagar
> para colocar un Oro extra' a la que este impuesto pueda aplicarse (el
> único otro camino para un segundo Oro es un efecto de búsqueda que lo
> coloca directo y gratis, put_gold_directly_in_reserva). Si algún día
> se agrega esa acción, esto ya la cubre sin tocar nada más.

### `_get_reveal_cost_reduction_pattern` — línea 131

> Detecta 'Reduce su coste en un Oro por cada X que muestres de tu
> mano, Cementerio o que controles, hasta un mínimo de N' (2026-08-29,
> p.ej. El Rey y el Verdugo: '...por cada Arma...') — escala con la
> cantidad mostrada. También detecta 'Reduce su coste en un Oro si
> muestras un X (o Y) de tu mano o Cementerio' (2026-09-03, p.ej. Shiji:
> '...si muestras un Arma o Tótem...') — SINGULAR, no escala ('un X', no
> 'por cada X'): tope de 1 carta mostrada (ver max_reveal en
> _resolve_reveal_cost_reduction()), el descuento de -1 sale solo de
> limitar la cuenta a 0 o 1, no hace falta un cálculo de descuento
> distinto. 'Arma o Tótem' es una lista de tipos válidos (no un elif que
> corta en el primero, mismo criterio ya usado en _execute_targeted_
> search() de TargetedEffectExecutor.gd para 'busca un Arma o un Oro').
> A diferencia de _register_talisman_totem_tax()/_register_weapon_
> first_play_discount() (modificadores PERSISTENTES de una carta ya en
> juego, afectando a OTRAS), este es un descuento de UN SOLO USO sobre
> la carta que se está jugando AHORA MISMO — se resuelve en play_card(),
> no como un modifier registrado en turn_started.
> Returns: {} si no aplica, si no {types: Array[Constants.CardType],
> allow_zero: bool, single: bool}.

### `_get_reveal_cost_reduction_pattern` — línea 156

> Enmascarar 'reduce su coste en [un/N] Oro(s)' ANTES de buscar tipos
> (2026-09-04, bug reportado: Shiji — 'si muestras un Arma o Tótem' —
> también ofrecía Oro como tipo mostrable, porque esa frase de arriba
> menciona 'Oro' como la UNIDAD del descuento, no como un tipo de
> carta a revelar. La versión anterior de este detector era un elif
> (un solo tipo posible) y "arma"/"tótem" ganaban SIEMPRE antes de
> llegar a la rama "oro", así que nunca se notó — el cambio a lista
> (2026-09-03, para soportar 'Arma o Tótem' a la vez) sí lo expuso.

### `_get_reveal_cost_reduction_pattern` — línea 183

> Zonas de origen realmente mencionadas (2026-09-03, p.ej. Shiji: 'de tu
> mano o Cementerio', SIN 'que controles' — a diferencia de El Rey y el
> Verdugo que sí ofrece las tres). No ofrecer una zona que el texto no
> menciona.

### `_gather_showable_candidate_nodes` — línea 200

> Igual que la vieja _gather_showable_candidates() pero devuelve los
> NODOS reales (no card_data) para mano/en juego — 2026-09-13, a pedido
> del usuario: reemplaza el modal de lista por click directo sobre las
> cartas reales (ver arquitectura.md §10.14/§10.17). 'mostrar' (DAR) no
> mueve ni gasta nada, la carta se queda donde está. card_types acepta un
> int (un solo tipo) o un Array (2026-09-03, p.ej. Shiji: 'muestra un
> Arma o Tótem' — dos tipos válidos). El Cementerio (source=1) NO se
> resuelve aquí — no tiene nodos persistentes, ver _build_cemetery_reveal_
> candidates() en _resolve_reveal_cost_reduction().

### `_resolve_reveal_cost_reduction` — línea 242

> 2026-09-13, a pedido del usuario (arquitectura.md §10.17): reemplaza
> el modal viejo de "¿desde dónde mostrar?" + lista por click directo
> sobre las cartas reales de TODAS las zonas permitidas A LA VEZ — mano y
> en juego ya son Nodos visibles en pantalla, Cementerio usa un popup
> liviano (sin oscurecer el resto, ver _open_cemetery_reveal_popup()) con
> Nodos temporales. El 'y/o' del texto sigue siendo "elige UNA zona, no
> combines" (2026-08-31): se logra con lock_group_key en vez de preguntar
> antes — el primer click define la zona, el resto de esa vuelta queda
> restringido a esa misma zona (current_zone de cada candidato).
> Returns: cantidad de cartas mostradas (0 si no había candidatos o no se
> eligió ninguna). No remueve nada de su zona ('mostrar' no es 'gastar'
> ni 'desterrar').

### `_resolve_reveal_cost_reduction` — línea 274

> Tope real de cartas ÚTILES a mostrar (2026-09-02, bug reportado por el
> usuario: con base_cost=2 y 'hasta un mínimo de 0', mostrar más de 2
> no reduce nada más). El piso real que aplica calcular_coste_real() es
> 0 con allow_zero, 1 si no (mismo criterio documentado ahí) — más allá
> de coste_base - piso, cada carta adicional mostrada es un no-op.
> 'single' (2026-09-03, p.ej. Shiji: 'si muestras un Arma o Tótem' — no
> escala, tope duro de 1) se aplica ADEMÁS del tope por utilidad, el
> que sea más chico gana.

### `_get_discard_cost_reduction_pattern` — línea 305

> Detecta 'Puedes Descartar una carta para reducir su coste en un Oro'
> (voragh el devorador, id 20588/20598 — 2026-09-20, bug real reportado
> por el usuario: "no puedo jugarlo reduciendo su coste en un oro", la
> habilidad nunca se había implementado). Mismo criterio de detección por
> substring que _get_reveal_cost_reduction_pattern() — costo ALTERNATIVO
> opcional ('Puedes') resuelto al jugar la carta, no un modificador
> persistente ni una habilidad activada aparte.

## `scripts/core/game/GoldManagerVisuals.gd`

### `(nivel de archivo)` — línea 2

> GoldManagerVisuals — Tokens visuales de Oro (Reserva/Oro Pagado): conteo
> disponible, separación dinámica entre cartas de Oro, recorte de click para
> la superposición en cascada, e imagen/creación/despawn de tokens de Oro
> Virtual (genérico y restringido). Ninguna de estas funciones toca estado
> propio de GoldManager (oros_virtuales, restricted_gold_pools,
> virtual_gold_tokens siguen viviendo ahí — aquí solo se opera sobre los
> Arrays de tokens que GoldManager pasa como parámetro, y sobre nodos de
> Main vía _main). Extraído de GoldManager.gd (2026-09-06, "módulos gordos",
> Fase 2) — confirmado por grep de todo scripts/ que ninguna de estas
> funciones tiene un llamador externo a GoldManager.gd salvo
> _update_gold_display() (GameBootstrap.gd, MulliganController.gd), que
> GoldManager.gd sigue exponiendo bajo el mismo nombre como forwarder.
> _despawn_gold_token() usa _main.create_tween()/_main.get_tree(), no un
> create_tween() propio — RefCounted no lo tiene, mismo patrón ya usado en
> AnimationEffects.gd (Fase 4).

### `update_gold_containers_spacing` — línea 43

> Calcula y ajusta la separación dinámica de las cartas de oro en Reserva
> y Oro Pagado para ambos jugadores, evitando que se superpongan en exceso.
>
> Reconstruida (2026-09-02, parse error reportado por el usuario): el
> cuerpo de esta función y el de puede_pagar() (más abajo) aparecieron
> truncados a la mitad — un 'if' sin bloque indentado y un 'return' de
> puede_pagar() pegado como si fuera parte de este 'if', con
> _update_container_gold_spacing(_main.player_gold) directamente
> desaparecido. No hay forma de recuperar los valores originales del
> cálculo de separación (la función que llaman, _update_container_gold_
> spacing(), tampoco existía en ningún lado del archivo), así que su
> implementación de más abajo es una reconstrucción conservadora nueva —
> revisala si la separación visual no queda como esperabas.

### `_spawn_gold_token` — línea 189

> Token visual en Reserva de Oro con ilustración temática de ficha rúnica/éter.
>
> 'player_id' (2026-10-06, ver arquitectura.md §33): a qué Reserva real
> (player_gold u opponent_gold) va el token — antes siempre player_gold,
> sin importar de quién era el Oro Virtual que representaba.

## `scripts/core/game/Main.gd`

### `(nivel de archivo)` — línea 10

> preload y no el class_name global (2026-10-12): un editor de Godot abierto
> desde antes de crear la clase no la tiene registrada y Main/TriggerSystem
> fallaban con "Could not find type" hasta reabrir el proyecto.

### `(nivel de archivo)` — línea 46

> Contenedores ya existían en la escena sin usar (2026-08-25): el Oro del
> oponente solo se mostraba como número en OpponentReservaOroLabel/
> OpponentOroPagadoLabel, nunca como carta real — ni siquiera el Oro
> Inicial con el que arranca la partida (ver GameBootstrap._setup_oro_
> inicial(), que para J1 solo hacía agregar_oro_reserva() sin crear nodo).

### `_ready` — línea 137

> Multiplayer remoto (2026-09-11, Fase B — docs/plans/2026-09-09-
> multiplayer-remoto-design.md): si esta instancia es el Anfitrión de una
> sala de red activa, el jugador 1 lo controla una PERSONA real por
> network, no la IA. RemotePlayerController extiende EasyBotController y
> expone la misma superficie pública — ningún otro archivo que llama a
> _easy_bot.<método> necesitó cambiar.

### `_ready` — línea 150

> Etiqueta superior "Jugador 1" (2026-10-07, bug real reportado por el
> usuario: la pantalla del Remoto seguía diciendo "Jugador 1" arriba a la
> izquierda) — el texto venía fijo en Main.tscn, ningún script lo
> actualizaba nunca según quién mira la pantalla. En una sala online, el
> Remoto es Jugador 2 desde su propia perspectiva; en cualquier otro modo
> (local, contra el bot) la única persona real siempre es Jugador 1.

### `_ready` — línea 204

> PROCESS_MODE_ALWAYS (2026-09-11, bug real reportado por el usuario: ESC
> abre el menú de pausa pero no lo cierra) — pause_menu ya tiene este
> mismo modo (SceneSetupModule.gd) para que sus botones funcionen con el
> árbol pausado, pero este nodo (dueño del _input() que escucha ESC) no lo
> tenía: al pausar (get_tree().paused = true), dejaba de recibir _input()
> por completo, así que una segunda tecla ESC nunca llegaba a procesarse.

### `_sync_oro_ui` — línea 303

> =============================================================================
> DEBUG
> =============================================================================
> Los atajos de teclado F1-F9/ESC y el _input() que los procesa se movieron a
> DebugInputModule.gd (2026-08-28, a pedido del usuario: "el main es para
> arrancar la app", eso es tooling de runtime, no arranque). _update_debug()
> se queda aquí porque es infraestructura mínima usada por TODO el proyecto
> (142 llamadores vía _main._update_debug()) — sacarla implicaría tocar cada
> uno de esos archivos por puro cosmética, sin beneficio real.

### `_update_debug` — línea 317

> 2026-09-25, a pedido del usuario ("quitar el log redundante, hay
> bastante"): un rechazo repetido (clicks fallidos seguidos, p.ej.
> "Objetivo no válido" varias veces) imprimía la misma línea una vez
> por click — la UI ya se actualiza igual (el jugador ve el mensaje en
> pantalla cada vez), solo se evita reimprimir la MISMA línea dos veces
> seguidas en consola.

## `scripts/core/game/PhaseFlowController.gd`

### `_on_phase_state_machine` — línea 87

> "En tu Agrupación" (2026-08-30, p.ej. Espada del Juicio) —
> mismo patrón que resolve_turn_end_triggers() para Fase Final.

### `_on_phase_state_machine` — línea 94

> "En tu Vigilia" (2026-09-03, p.ej. Mariano Osorio) — mismo
> patrón que Agrupación/Fase Final.

### `_on_phase_state_machine` — línea 104

> "Al comienzo del Ataque" (2026-09-04, p.ej. almirante akari) —
> mismo patrón que Agrupación/Vigilia/Fase Final.
> "Al comienzo del Ataque" se resuelve al confirmar atacantes
> (GameManager.confirm_attackers(), 2026-10-17): sin ataque, no hay.
> Sin ningún Aliado que pueda atacar, directo a la Fase Final
> (2026-10-17, a pedido del usuario).

### `_on_priority_changed_bot_autopass` — línea 151

> Comienzo de fase (2026-10-18): el bot juega o pasa, el Anfitrión tiene
> 5 s; el Remoto decide por RemotePlayerController (abajo).

### `_on_priority_changed_bot_autopass` — línea 162

> 2026-10-11: contra un jugador Remoto real, el J2 NO es un bot — antes
> este auto-pase le pasaba la prioridad a los 0.2s en CUALQUIER ventana
> (respuesta, Bloqueo, Guerra de Talismanes), así que el Remoto nunca
> alcanzaba a responder. Ahora decide RemotePlayerController.

### `_on_priority_changed_bot_autopass` — línea 169

> 2026-09-15: se captura la generación de ESTA ventana (ver
> PriorityManager._window_generation) ANTES del await — mismo motivo
> que _human_pass_after()/_bot_pass_after(), ver esos comentarios.

### `_on_priority_changed_bot_autopass` — línea 173

> 0.2s (2026-09-11, bajado de 0.6s — a pedido del usuario: las cadenas de
> varias cartas entrando en juego seguidas acumulaban demasiado con 0.6s
> por ventana). Sigue siendo perceptible, no instantáneo/confuso.

### `_try_recover_stuck_phase_priority_window` — línea 188

> Reabre la ventana de prioridad de FASE (Guerra de Talismanes/Bloqueo)
> si quedó clobbereada (2026-09-04, bug reportado: 'se queda estancado
> en guerra de talismanes') — una ventana anidada de Paso D
> (StackStepResolver._execute_step_d(), que abre su PROPIA
> RESPONSE_WINDOW sobre la misma instancia de PriorityManager cuando algo
> pasa por la pila del ActionPipeline durante la fase) a veces no la
> restaura al cerrar, dejando priority_window_active=false sin que nadie
> vuelva a abrir nada — ni el botón ¿Paso? (gateado a
> priority_window_active) con qué reaccionar. Extraído a función propia
> (2026-09-06, bug reportado: el mismo estancamiento en Bloqueo, esta vez
> SIN pasar por el auto-pase del bot — el botón ¿Paso? del humano caía
> directo en el aviso 'Sin ventana de prioridad activa' sin intentar
> recuperarse) para poder llamarla también desde ahí. Returns true si
> reabrió una ventana.

### `_on_priority_changed_glow` — línea 228

> La visibilidad del botón depende de quién tiene la prioridad AHORA
> (ver update_paso_button_state(), 2026-09-03) — no solo se recalcula
> al cambiar de fase, también hay que refrescarla cada vez que la
> prioridad cambia de jugador DENTRO de la misma fase (p.ej. el bot
> pasa en Guerra de Talismanes y la prioridad vuelve al humano).

### `_on_priority_changed_glow` — línea 236

> 2026-09-11 (bug real reportado por el usuario: quedaba bloqueado
> jugando otra carta — "Resuelve la respuesta pendiente (¿Paso?)" —
> después de que el bot pasara en una ventana que arrancó CON ÉL,
> p.ej. tu propia habilidad entrando a la pila, donde el oponente
> responde primero). Punto único de auto-pase para el humano en
> RESPONSE_WINDOW: cubre tanto que la ventana arranque contigo como
> que la prioridad te llegue apenas a mitad de camino — priority_
> changed se emite en ambos casos, así que no hace falta duplicar
> esta lógica en _on_step_d_waiting()/_on_stack_resolved(). Ver
> ResponseWindowHandler._offer_signo_amarillo_for_step_d() para la
> única decisión real que puede haber aquí (Signo Amarillo), que
> suprime este auto-pase mientras espera tu click (PriorityManager.
> suppress_human_autopass). Restringido a RESPONSE_WINDOW a propósito:
> la Guerra de Talismanes y el Bloqueo REALES (fase, no la reutilización
> de esta misma etiqueta para el Paso D) sí deben esperar tu decisión
> real, nunca auto-pasar.

### `_on_priority_changed_glow` — línea 254

> 2026-09-19 (arquitectura.md §10.51/§10.52): la espera real de 5s
> (has_response == true, ver refresh_activatable_glows()/
> _human_has_instant_response_talisman_in_hand() más abajo) queda
> construida para cuando el oponente sea un jugador REMOTO de
> verdad (esta rama ya excluye RemotePlayerController arriba, así
> que en ese caso ni se llega aquí) — pero contra el EasyBot local,
> a pedido explícito del usuario ("de momento, jugando contra el
> bot, que pase de inmediato"), se mantiene el pase rápido de
> siempre: no tiene sentido hacer esperar al humano 5s reales por
> una decisión del BOT cuando puede decidir con solo mirar el
> tablero. refresh_activatable_glows() se sigue llamando igual
> (glow celeste de qué carta podría responder — informativo, sin
> costo) pero el delay real quedó fijo en 0.2s, como antes de
> §10.52. Si más adelante se conecta un oponente remoto por esta
> misma rama, revisar si corresponde variar el delay según
> `_main._easy_bot is RemotePlayerController` en vez de la
> exclusión total de arriba.

### `_on_priority_changed_glow` — línea 273

> 2026-10-17, a pedido del usuario ("no alcancé a responder" con
> Ciempiés/Dragón Dorado al Yomiel del bot): si la ventana es sobre
> algo del rival y tienes un Talismán de respuesta que puedes
> pagar, se espera como online (5s con cuenta regresiva); si no,
> el pase rápido de siempre.

### `_on_priority_changed_glow` — línea 282

> 2026-09-15: se captura la generación de ESTA ventana (ver
> PriorityManager._window_generation) para que el timer no actúe
> sobre una ventana NUEVA si esta ya cerró sola antes de que pase el delay.

### `_on_priority_changed_glow` — línea 287

> 2026-10-11, botón de paso simétrico online (ver PriorityManager.
> needs_real_decision()): si esta ventana no te pide nada (p.ej. la
> respuesta a TU propia carta, o eres el atacante en Bloqueo), se
> pasa sola; en una Ventana de Respuesta real tienes 5s para
> responder antes de que pase sola; Bloqueo y Guerra de Talismanes
> esperan tu click sin límite.

### `_on_priority_window_closed_glow` — línea 310

> Apaga el brillo del botón ¿Paso? al cerrarse la ventana de prioridad.
>
> 2026-09-11 (bug real reportado por el usuario: después de jugar Tyet —
> Oro con búsqueda — el botón de pasar dejaba de aparecer del todo, sin
> forma de seguir jugando). update_paso_button_state() solo se llamaba en
> dos momentos: al cambiar de fase, o cuando cambia de jugador la
> prioridad (_on_priority_changed_glow) — ninguno de los dos coincide
> necesariamente con el cierre real de la ventana. Si la última vez que
> se recalculó la visibilidad fue con current_priority_player == 1 (bot),
> _paso_button.visible quedaba en false, y como cerrar la ventana no
> recalculaba nada, se quedaba así para siempre aunque siguiera siendo tu
> Vigilia — la regla de respaldo (¿es tu turno en una fase relevante?) de
> update_paso_button_state() nunca llegaba a aplicarse.

### `_on_battle_combat_finished` — línea 346

> NO se desmarca a los atacantes aquí (2026-08-21): DAR — un Aliado que
> atacó se queda en Línea de Ataque (tinte naranja incluido) hasta la
> Agrupación del próximo turno de su controlador, igual que el Oro
> Pagado no vuelve a la Reserva hasta entonces. Ver el caso AGRUPACION
> en _on_phase_state_machine(), que ahora hace ese trabajo.

### `_on_priority_both_passed_main` — línea 380

> Ambos jugadores pasaron con la pila vacía — avanza la fase según contexto.
> DAR Sección 5.C3: Pila vacía + ambos pasan → la fase termina.
>
> GUARDIA (2026-08-17): TriggerSystem._wait_for_response_window() abre su
> propia ventana de prioridad (p.ej. para poder cancelar el 'cuando entra
> en juego' de un Aliado) y espera a que se cierre sondeando
> priority_window_active directamente — no necesita que ESTE handler
> haga nada. Pero como es un listener global de la misma señal
> both_players_passed, antes reaccionaba igual: si esa ventana se cerraba
> mientras la fase actual era VIGILIA, se interpretaba como 'el jugador
> pasó su turno de batalla' y saltaba directo a Fase Final — aunque el
> jugador solo había pasado para resolver el trigger pendiente, nunca
> llegó a declarar su ataque. Si TriggerSystem sigue esperando una
> respuesta, esta ventana es suya, no una señal de fin de fase — no tocar
> nada aquí.

### `_on_priority_both_passed_main` — línea 395

> La ventana de comienzo de fase no termina la fase: la maneja
> PhaseStartWindow.run() (2026-10-18).

### `_on_priority_both_passed_main` — línea 431

> 2026-09-20 (arquitectura.md "539 cartas sin cobertura", libro de
> thoth): antes esto llamaba advance_to_phase() directo, sin
> recolectar 'cuando bloqueas' — primer uso real de ese trigger,
> ver GameManager.confirm_blockers_and_collect_triggers() (mismo
> criterio que ATAQUE arriba, que sí espera confirm_attackers()).

### `_on_priority_both_passed_main` — línea 438

> Constants.Phase.VIGILIA (eliminado 2026-08-17): este caso era
> redundante con _on_paso_pressed()'s propio manejo de VIGILIA (que
> hoy es el botón "Atacar" — GameManager.proceed_to_battle() —, ver
> 2026-08-28 más arriba). Este handler, en cambio,
> reacciona a CUALQUIER ventana que se cierre con ambos pasados
> mientras la fase siga siendo VIGILIA — incluida una ventana de
> respuesta anidada de un trigger 'cuando entra en juego' (o la que
> abre _on_stack_resolved() al vaciarse la pila). Eso hacía que
> resolver un trigger pendiente con ¿Paso? saltara la batalla entera
> sin que el jugador llegara a declarar ningún atacante.

### `_on_stack_resolved` — línea 453

> La pila LIFO (ActionPipeline) quedó vacía — abrir ventana de prioridad si no hay una activa.
>
> 2026-09-11 (bug real reportado por el usuario: bloqueo silencioso de
> 10-30s tras resolver la pila, "Drácula en Vigilia") — esta ventana se abre
> llamando a PriorityManager directo, sin pasar por StackStepResolver.
> _execute_step_d(), pero eso ya alcanza: start_priority_window() emite
> 'priority_changed', que _on_priority_changed_glow() (conectado en setup())
> ya escucha para mostrar y hacer brillar el botón único ¿Paso?/Atacar del
> HUD cuando le toca al humano — no hace falta ningún overlay separado.

### `_on_stack_resolved` — línea 467

> Si arranca contigo (jugador 0), _on_priority_changed_glow() de aquí
> abajo se encarga del auto-pase "no hay nada que decidir" — bug real
> reportado por el usuario: quedaba bloqueado jugando otra carta
> ("Resuelve la respuesta pendiente (¿Paso?)") hasta tocar el botón a
> mano, aunque no hubiera nada real que decidir aquí (esta ventana no
> tiene un stack_obj puntual que ofrecer para cancelar con Signo
> Amarillo, a diferencia del Paso D real — ver ResponseWindowHandler).

### `_human_has_instant_response_talisman_in_hand` — línea 477

> ¿Hay al menos un Talismán de respuesta instantánea (Red de Plata,
> Sacrificio Solar, etc. — GoldManagerRestrictions._is_response_only_
> talisman(), §10.50) en tu mano que además puedes pagar ahora mismo?
>
> 2026-09-19, §10.52: SIN LLAMADOR HOY A PROPÓSITO — junto con el valor de
> retorno de refresh_activatable_glows(), estaba pensada para decidir si el
> auto-pase de Paso D da 5s reales para decidir o pasa casi al toque, pero
> el usuario pidió volver al pase rápido fijo contra el EasyBot local "de
> momento" (no tiene sentido hacer esperar al humano por una decisión del
> bot). Queda lista para cuando la rama de _on_priority_changed_glow() se
> conecte a un oponente REMOTO de verdad (hoy esa rama excluye
> RemotePlayerController por completo, así que ni se llega a llamar esto) —
> no se borró para no perder el trabajo, pero no confundir "sin llamador"
> con "código muerto sin dueño" como el cluster de TargetSelector.gd (§2):
> aquí el dueño futuro ya está identificado.

### `_human_pass_after` — línea 514

> 2026-10-13, bug real reportado por el usuario (quimera voragh: "un
> paso de respuesta medio raro, no entiendo a qué responder"): la
> ventana vacía de "pila recién resuelta" (_on_stack_resolved()) se
> abría mientras elegía la carta del Cementerio — el auto-pase se
> cancelaba y la ventana quedaba abierta bloqueando la siguiente
> carta. Sin nada a qué responder, se espera a que termine la
> elección y se pasa igual.

### `_human_pass_after` — línea 525

> 2026-09-15, bug real reportado por el usuario ("se traba en Guerra de
> Talismanes", confirmado con diagnóstico en vivo: la ventana abría bien
> pero se cerraba sola sin ningún click): si la ventana de RESPONSE_
> WINDOW para la que se programó este timer ya cerró y se abrió una
> ventana NUEVA (p.ej. Guerra de Talismanes) antes de que pasen los
> 0.2s, _window_generation ya cambió — este timer viejo no debe tocar
> la ventana nueva, aunque técnicamente "priority_window_active=true y
> te toca a ti" siga siendo cierto (es cierto de la ventana NUEVA, no
> de la que este timer estaba mirando).

### `_human_pass_after` — línea 536

> Plazo largo (5s online): si al vencer estás en medio de elegir el
> objetivo de tu respuesta, no se te pasa por abajo (2026-10-11).

### `_on_paso_pressed` — línea 549

> 2026-10-11: con el selector de zonas abierto, el botón confirma la
> selección (en ambas pantallas — el Remoto también lo corre localmente).

### `_on_paso_pressed` — línea 554

> 2026-10-11: en el cliente Remoto no corre GameManager propio — el botón
> (y el atajo P) mandan la decisión al Anfitrión por red.

### `_on_paso_pressed` — línea 560

> 2026-09-14, bug real reportado por el usuario: con una selección de
> objetivo pendiente (p.ej. 'Elige un Oro o una carta de coste 2 o menos
> para Convertir', TargetedEffectExecutor._execute_targeted_convert())
> nada impedía presionar ¿Paso? y seguir jugando — el await_target() de
> esa selección queda esperando un click que nunca llega (correcto: una
> decisión humana NO debería tener timeout), pero TriggerSystem.
> awaiting_response/is_resolving se quedan atascados en true para
> siempre, bloqueando el fin de CUALQUIER fase futura (el guard de
> PhaseFlowController._on_priority_both_passed_main() hace su trabajo
> correctamente, pero nunca hay nada que destrabe la causa real). Se
> bloquea aquí en la raíz: mientras is_selecting_target sea true, el
> jugador tiene que resolver el objetivo (o cancelar con ESC, si la
> habilidad lo permite) antes de poder avanzar de fase.

### `_on_paso_pressed` — línea 586

> El botón en Vigilia dice "Atacar" (2026-08-28, reemplaza el
> diseño de 2026-08-23 a pedido del usuario): ya no se declaran
> atacantes apartados DURANTE Vigilia — este botón solo termina
> Vigilia y empieza la Batalla Mitológica. Declarar (o no) queda
> para la fase de Ataque; si nadie ataca, un segundo ¿Paso? ahí
> la salta igual (confirm_attackers() con la lista vacía llama a
> _end_batalla() directo a Fase Final).
> Sin ningún Aliado que pueda atacar, el botón dice "Fase Final"
> y va directo ahí (2026-10-18, a pedido del usuario).

### `_resolve_fase_final` — línea 630

> 'En tu Fase Final' (2026-08-30, p.ej. Espada de O'Higgins) — se
> dispara al ENTRAR a la fase, antes del robo/límite de mano normales
> (mismo orden que cualquier trigger de entrada de fase en el DAR).

### `_resolve_fase_final` — línea 635

> Efectos suspendidos de un solo uso agendados para ESTA Fase Final en
> particular (2026-09-06, p.ej. Fisión Nuclear: 'En la próxima Fase
> Final oponente, Baraja una carta de coste 2 o menos o Roba dos
> cartas') — distinto de resolve_turn_end_triggers() de arriba, que
> consulta cartas EN JUEGO; esto resuelve algo que quedó pendiente de
> un Talismán ya Desterrado hace rato.

### `_resolve_fase_final` — línea 643

> torii (2026-09-20, arquitectura.md "539 cartas sin cobertura"): "Si lo
> haces, no Robas al finalizar tu turno" — bandera de una sola vez,
> consumida ANTES del robo normal de Fase Final (ver OroAbilityPatterns.
> gd, try_execute_torii_agrupacion_pattern()).

### `_discard_excess_by_click` — línea 689

> Descarte por límite de mano (DAR 5.D.4) — click directo sobre las
> cartas reales de la mano (2026-09-13, a pedido del usuario, mismo
> criterio ya usado para el resto de descartes de mano de la sesión, ver
> arquitectura.md §10.16/§10.29), en vez del modal de lista viejo de
> SelectionModule.open_discard_selection(). Reusa el helper compartido de
> TargetedEffectExecutor (mandatorio, cancellable=false).

## `scripts/core/game/PhaseStartWindow.gd`

### `(nivel de archivo)` — línea 2

> PhaseStartWindow — "Puedes jugarlo al comienzo de cualquier Fase" y "en la
> Fase Final" (2026-10-18, diseño acordado con el usuario):
> - Al comienzo de cada fase (Agrupación, Vigilia, Ataque, Bloqueo, Guerra
> de Talismanes, Asignación de Daño, Fase Final), de los dos turnos, se
> abre una ventana SOLO si algún jugador tiene en la mano una carta con
> ese permiso y la puede pagar. Si no, la fase sigue igual que antes.
> - Empieza el jugador activo; cada uno juega una carta habilitada o pasa.
> Después de una carta (con su propia Ventana de Respuesta), la ventana
> vuelve al otro. Termina cuando los dos pasan seguidos. 5 s por turno de
> palabra, para el Anfitrión y para el Remoto.
> - Después la fase sigue con lo que haya en juego (p.ej. un atacante
> Barajado ya no hace daño).
> Textos:
> "al comienzo de cualquier Fase" / "cualquier Fase o Paso" → todas.
> "al comienzo de cualquier Fase Final" → Fase Final de los dos.
> "en la Fase Final oponente" → solo la del rival.
> "en tu Vigilia o Fase Final" → solo tu Fase Final.
> "en la Fase Final" (sin "tu") → la de los dos.
> minamoto no yoritomo: "Puedes jugar este y tus demás Aliados al comienzo
> de cualquier Fase Final".
> Se usa con preload / load.

## `scripts/core/game/PlayerSide.gd`

### `(nivel de archivo)` — línea 3

> PlayerSide — "la mano / las líneas / los Oros / el pago DEL JUGADOR X"
> (2026-10-12, arquitectura.md §56, a pedido del usuario: "cómo podemos
> arreglar esas cartas que solo funcionan con el Anfitrión").
>
> Mucho código de efectos se escribió cuando "jugador 0 = la persona,
> jugador 1 = el bot" y usa directo main.player_hand/player_field/
> GoldManager.pagar_coste() sin jugador. Con un Remoto real eso hace que su
> carta mire o mueva las cartas del Anfitrión, o pague con sus Oros. Estas
> funciones resuelven el lado correcto a partir del player_id; al arreglar
> un patrón viejo, cambiar main.player_hand por PlayerSide.hand(main, pid).
>
> Del lado del Anfitrión el jugador 1 se ve como "opponent_*" (_opponent_fan
> para la mano). Se usa con preload (no con el class_name global) para no
> depender de que el editor ya haya registrado la clase — ver §54.

### `play_from_hand` — línea 135

> =============================================================================
> ELEGIR Y MOVER CARTAS (2026-10-18, punto 1 de la revisión de código: estos
> bloques estaban copiados en cada patrón, cada uno con su propia rama del bot)
> =============================================================================
> Elige una carta EN JUEGO (líneas de los dos jugadores) que pase 'filter'.
> - Anfitrión / Remoto: click en el tablero (await_target; el Remoto elige
> por red). 'optional' = se puede no elegir (N).
> - Bot local: la primera que pase 'bot_filter' (o 'filter') mirando los
> lados de 'bot_sides' en orden (por defecto el rival y después el
> propio). Con 'bot_skip' el bot no elige ninguna ("hasta"/"puedes" que no
> le conviene usar).

## `scripts/core/game/ZoneManager.gd`

### `_on_field_child_entered` — línea 29

> Carta que entra a la Línea de Defensa/Apoyo SIN pasar por
> pin_card_to_field_slot() (2026-10-13, bug real reportado por el usuario:
> la carta que pone en juego quimera voragh quedaba debajo de la propia
> quimera). Jugar normal la acomoda en su casilla al frame siguiente; si
> al rato sigue sin casilla, se compacta la línea.

### `draw_card` — línea 80

> 2026-09-14, bug real reportado por el usuario: "puedo hacer objetivo
> a mis Aliados pero no a los del rival", en TODAS las habilidades de
> objetivo sin excepción. Causa: a diferencia de la rama del jugador
> 0 (arriba), aquí nunca se llamaba _main._connect_card_signals(card)
> — card_clicked/card_double_clicked/etc. quedaban sin NINGÚN listener
> conectado desde el momento en que la carta se roba (incluida la
> mano inicial completa, ver draw_initial_hand() más abajo, que solo
> llama a esta misma función). El click SÍ llegaba a Card._on_gui_
> input() (can_interact quedaba en true vía _force_board_
> interactable()) y emitía la señal, pero nadie escuchaba — la carta
> se veía "brillando" como objetivo válido y el click no hacía nada,
> en cualquier ability que pidiera un objetivo en juego. Se arrastraba
> incluso después de que la carta pasara de la mano al campo (mismo
> Node reparentado, las conexiones de señal no se pierden pero nunca
> existieron para empezar).

### `_update_castillo_counts` — línea 231

> Único punto de verdad para "el Castillo cambió" (robo normal, Destierra
> N del tope de Aho, la habilidad de La Ouija, etc.) — refrescar aquí el
> revelado del tope (2026-08-31) evita tener que llamarlo a mano en cada
> sitio que toca player_deck directo. Ver ZoneViewerModule.
> refresh_castillo_top_reveal().

### `_update_castillo_counts` — línea 238

> Chequeo de victoria por Castillo vacío (DAR 2.1) — mismo motivo: antes
> solo se chequeaba al INTENTAR robar con el mazo ya vacío (2026-08-31,
> reportado por el usuario: desterrar el Castillo rival a 0 con Aho no
> declaraba ganada la partida). Ver GameManager.check_victory() — ya
> tiene su propio guard is_game_active, no hace falta repetirlo aquí.

### `_detach_for_flight` — línea 281

> Saca la carta de la mano/abanico/campo y la deja colgando del tablero
> para animar su vuelo. 2026-10-13, bug real reportado por el usuario (se
> quedaba pegado en la Fase Final al descartar por límite de mano): sacarla
> de la mano la dejaba FUERA del árbol, y un tween de un nodo fuera del árbol
> nunca termina (probado) — el 'await tw.finished' colgaba para siempre.
> Antes eran 3 copias del mismo bloque (Cementerio, Destierro, Castillo).

### `move_card` — línea 545

> =============================================================================
> SLOTS FIJOS DE LÍNEA DE DEFENSA/APOYO (2026-08-31, a pedido del usuario)
> =============================================================================
> Antes Línea de Defensa/Apoyo eran HBoxContainer puro (alignment=CENTER):
> agregar o sacar UN hijo reordenaba TODOS sus hermanos de una — reportado
> como 'cuando 1 ataque, el otro toma su puesto' (el Aliado que se quedaba
> en Defensa se corría solo al vacante el que salió a atacar). No se cambia
> el TIPO de contenedor en la escena — sigue siendo un HBoxContainer real, y
> container.get_children() sigue siendo la fuente de verdad de 'quién está
> en esta zona' para el resto del proyecto (docenas de lugares dependen de
> eso) — solo se desacopla cada carta de su layout automático
> (top_level=true, mismo truco que CardInteraction._start_drag()) y se le
> asigna una posición fija dentro de una grilla de slots imaginaria que el
> Container ya no puede tocar.

### `compact_field_slots` — línea 662

> Sin tipar a propósito: un Arma que salió del juego por un camino
> que no la desequipó deja una referencia liberada, y asignarla a
> una variable 'Node' revienta. Se purga de paso (2026-10-14).

## `scripts/core/logging/CombatLogSignalHandlers.gd`

### `connect_signals` — línea 21

> Conecta a todas las señales relevantes del sistema
> (2026-08-28, "módulos gordos" punto 1): ActionModule/
> GameManager/TurnManager/UniversalCardParser son autoloads garantizados —
> se saca el cacheo redundante vía get_node_or_null(). _safe_connect() ya
> valida has_signal() por su cuenta, así que esto no cambia el
> comportamiento: _connect_module_signals() y _connect_turn_manager_signals()
> seguían (y siguen) sin conectar nada real — ActionModule.gd no tiene
> señales 'card_drawn/discarded/destroyed/banished/milled' y TurnManager.gd
> no emite ninguna señal propia hoy.

## `scripts/core/managers/BattleManager.gd`

### `_ready` — línea 35

> (2026-08-28, "módulos gordos" punto 1): aquí había una conexión a
> 'TurnManager.phase_changed' para auto-disparar calculate_combat_damage()
> en ASIGNACION_DANIO — TurnManager.gd NO tiene (ni tuvo nunca) esa señal,
> así que el 'has_signal()' que la envolvía siempre daba falso y esto
> jamás se conectó. No hacía falta: PhaseFlowController.gd sí llama
> BattleManager.calculate_combat_damage() directo al entrar a esa fase
> (ver PhaseFlowController.gd línea ~273) — ese es el camino real. Se
> sacó la conexión rota y el handler _on_phase_changed() que quedaba
> huérfano sin ella.

### `_ready` — línea 47

> =============================================================================
> CÁLCULO DE DAÑO DE COMBATE (DAR Sección 5.C4)
> =============================================================================
> Último turno de jugador (GameManager.turn_serial) en que cada jugador atacó
> (2026-10-14, Cuervo Nocturno: "Si atacaste en tu turno anterior...").

### `calculate_combat_damage` — línea 90

> Daño de atacantes con "hace doble daño de combate al Destierro"
> (2026-09-04, a pedido del usuario — p.ej. atenea en wonderland,
> manuel rodriguez) — YA VIENE DOBLADO aquí, separado del pool normal
> porque va a una zona distinta (Destierro, no Cementerio) al
> aplicarse más abajo.

### `calculate_combat_damage` — línea 108

> Una carta que salió del juego durante el combate (destruida o
> desterrada por un efecto en la ventana de respuesta) ya no está:
> no hace ni recibe daño (2026-10-14, bug real reportado por el
> usuario: "_get_strength ... previously freed").

### `calculate_combat_damage` — línea 185

> Prevenir el daño al Castillo con un Oro (Alicanto, Escritura Sagrada,
> 2026-10-14) — antes de aplicarlo.

### `calculate_combat_damage` — línea 193

> Fisión Nuclear (2026-10-14): el "doble daño al Destierro" es una
> habilidad del rival — contra un jugador protegido es daño normal.

### `calculate_combat_damage` — línea 199

> Emitir señal con el daño total calculado (ambos pools combinados —
> 2026-09-04: total_damage_to_exile ya viene doblado, ver
> _accumulate_castle_damage())

### `calculate_combat_damage` — línea 252

> Destruir cartas (respetando Indestructible)
>
> Protección "no son Destruidos cuando bloquean" (2026-08-24, p.ej.
> Patria Vieja): solo se filtra de blockers_destroyed, NUNCA de
> attackers_destroyed — la protección es específicamente por bloquear,
> no una Indestructible general.

### `_accumulate_castle_damage` — línea 313

> Suma 'amount' al pool correcto según si 'attacker' tiene 'hace doble
> daño de combate al Destierro' (2026-09-04, a pedido del usuario — p.ej.
> atenea en wonderland, manuel rodriguez): ese daño se DOBLA y va a un
> pool separado que _apply_castle_damage() manda al Destierro en vez del
> Cementerio. El resto de atacantes en el mismo combate sigue sumando al
> pool normal sin verse afectado.

### `_accumulate_castle_damage` — línea 319

> "haga doble daño de combate este turno" (2026-10-17, Kai Piloto
> Prodigio): meta con el turno en que vale.

### `_apply_castle_damage` — línea 377

> Oro de Azi del Abismo (2026-10-17): "Reduce el daño recibido por tu
> Castillo en 1 por cada Oro Azi que controles".
> Linaje Maldito (2026-10-18): "no puedes recibir daño de combate hasta tu
> próximo turno".

### `_has_indestructible` — línea 473

> Verifica si una carta tiene Indestructible (DAR Sección 8)
> Delegado a KeywordManager para centralización.
> (2026-08-28, "módulos gordos" punto 1: esto llamaba a _keyword_mgr, una
> referencia cacheada en _ready() ANTES de que KeywordManager (autoload
> #22) terminara de cargar — BattleManager es autoload #11, así que
> _keyword_mgr quedaba null para siempre y esta función corría el
> fallback manual de abajo toda la partida, nunca la lógica real
> centralizada de KeywordManager. Confirmado y corregido junto con
> can_be_blocked() más abajo, mismo bug.)

### `_get_card_name` — línea 528

> =============================================================================
> CONSULTAS
> =============================================================================
> NOTA (2026-09-08): Se eliminó un segundo sistema de "modificadores de
> combate" (combat_strength_modifiers/add_combat_modifier()/get_modified_
> strength()/clear_combat_modifiers()) que vivía aquí, paralelo y desconectado
> del real: calculate_combat_damage() siempre calculó la Fuerza vía
> ContinuousEffectManager.get_modified_strength(card) (ver _get_strength()
> más arriba), nunca a través de este — auditoría 2026-09-07 confirmó cero
> llamadores reales en todo el proyecto. Cualquier efecto de "+X de Fuerza
> este combate" debe registrarse en ContinuousEffectManager (duration
> UNTIL_END_TURN o similar), no aquí.

### `_get_card_name` — línea 541

> NOTA (2026-08-20): "Golpe Primero" y "Arrollar" no son keywords en Mitos y
> Leyendas — se eliminó has_first_strike()/has_trample()/
> calculate_first_strike_damage() (sin llamadores reales, siempre un TODO
> que devolvía 0). El daño excedente al Castillo ya se aplica por defecto
> en _resolve_combat_pair() (DAR 5.C4), sin necesidad de ninguna keyword.

## `scripts/core/managers/CardManager.gd`

### `(nivel de archivo)` — línea 20

> Cualquier carta que entra a un Cementerio (2026-10-14, disparadores
> "Cuando sea puesta en tu Cementerio", ver CemeteryTriggers.gd).

### `(nivel de archivo)` — línea 58

> "las cartas que estén o sean puestas en los Cementerios este turno pierden
> su habilidad hasta tu próximo turno" (2026-08-30, Sable de Napoleón) —
> mientras esté true, cualquier carta que entre a CUALQUIER Cementerio
> (ver _append_to_cemetery()) queda marcada como silenciada también. Se
> apaga sola al empezar el próximo turno (turno del rival), ver
> silence_all_cemetery_cards().

### `sync_from_main` — línea 90

> Partida nueva (2026-10-17, bug real reportado por el usuario: al
> empezar otra partida seguían las cartas del Cementerio de la anterior).
> CardManager es autoload y sobrevive entre partidas; antes se usaba
> 'if main.get("player_cemetery"):', y un Array VACÍO es falso, así que
> el Cementerio nuevo (vacío) nunca reemplazaba al viejo. El Destierro
> (que solo vive aquí) tampoco se limpiaba nunca.

### `add_to_deck_top` — línea 194

> Añade una carta al tope del mazo.
>
> Convención real del tope (2026-08-30, corregido — estaba al revés): el
> camino de robo que de verdad se usa en la partida es ZoneManager.
> draw_card(), que hace _main.player_deck.pop_front() — el FRENTE del
> array (índice 0) es el tope. _zones[player_id].deck es el MISMO array
> que _main.player_deck (ver sync_from_main(): asignación directa, no una
> copia), así que esta función tiene que insertar al frente para que
> 'tope' signifique lo mismo aquí que en el robo real. draw_card() de este
> mismo archivo (más arriba) usa pop_back() y NUNCA se llama desde
> ningún lado — quedó con la convención vieja/incorrecta, no se tocó
> porque no tiene ningún llamador real que arreglar.

### `add_to_exile` — línea 224

> Añade datos de una carta directo al Destierro (2026-08-25) — para
> efectos que la mandan ahí sin pasar por una carta en juego (p.ej. Rey de
> Amarillo: busca en un Castillo y Destiérralas directo, sin llevárselas a
> la mano primero).

### `append_to_exile` — línea 234

> Punto único para agregar una entrada a un Destierro (2026-10-14, ver
> card_put_in_exile).

### `_append_to_cemetery` — línea 261

> Choke point único para agregar una entrada a un Cementerio (2026-08-30)
> — antes cada llamador hacía _zones[player_id].cemetery.append(card_data)
> por su cuenta; se centraliza aquí para que la 'captura' de Sable de
> Napoleón (silenciar cartas que entren al Cementerio durante la ventana
> activa) no dependa de tocar cada llamador por separado.

### `is_cemetery_card_silenced` — línea 273

> 'Pierde su habilidad' para una carta EN CEMENTERIO (2026-08-30, Sable
> de Napoleón) — KeywordManager._silenced_cards es por instance_id de un
> Node vivo, no aplica a datos de Cementerio (Dictionary puro), así que
> esto vive aquí, junto con el dato mismo.

### `silence_all_cemetery_cards` — línea 281

> 'Las cartas que estén o sean puestas en los Cementerios este turno
> pierden su habilidad hasta tu próximo turno' (Sable de Napoleón,
> 2026-08-30). 'los Cementerios' sin posesivo = AMBOS (mismo criterio ya
> confirmado para 'un Cementerio' de Miguel). Dos ventanas de tiempo
> DISTINTAS:
> 1) La CAPTURA de nuevas entradas dura 'este turno' — se apaga sola en
> cuanto empiece cualquier otro turno (CONNECT_ONE_SHOT, sin
> importar de quién sea: no puedes volver a tu propio turno sin que
> pase el del rival primero).
> 2) El SILENCIO en sí dura 'hasta tu próximo turno' (el de
> activator_player_id específicamente, no el del rival que viene
> primero) — se levanta solo cuando vuelva a empezar SU turno.

### `_unequip_from_wielder` — línea 338

> 2026-09-19, bug real reportado por el usuario ('Trying to assign
> invalid previously freed instance', ZoneManager.gd:535 — desterrando un
> Arma equipada con Bernardo O'Higgins). _move_equipped_weapons_with()
> (arriba) cubre la dirección 'el portador sale del juego, el Arma lo
> sigue' — pero la dirección contraria (el ARMA MISMA sale del juego
> directo, con su portador quedándose en juego) nunca limpiaba
> wielder.equipped_weapons antes de queue_free(). equipped_weapons es un
> Array genérico sin tipar, pero la lectura `var w: Node =
> card.equipped_weapons[w_idx]` en ZoneManager.compact_field_slots() SÍ
> está typada — asignar ahí la referencia ya liberada del
> Arma es justo lo que Godot rechaza con ese error, la próxima vez que
> cualquier acción recompactara el campo (compact_all_fields(), llamado
> DEFERRED dos líneas más abajo en destroy_card()/exile_card(), así que
> nunca fallaba en el mismo frame — el crash aparecía en la próxima
> recompactación real). Llamar ANTES de queue_free() en ambas funciones.

### `_move_equipped_weapons_with` — línea 363

> El Arma sigue a su portador al mismo destino (DAR — no queda suelta en
> juego). Se llama ANTES de queue_free() en destroy_card()/exile_card(),
> pasándose a sí misma (mover) como la función a aplicar a cada Arma.
> Excepción (2026-08-30, p.ej. Aho: 'Cuando el portador fuera a salir del
> juego, súbela a tu mano o cámbiala de portador') — un Arma con ese texto
> NO sigue al portador, el jugador elige entre las dos alternativas.

### `_weapon_survives_wielder_death` — línea 381

> 2026-08-31: se ancla también en 'bela a tu mano' (sin la 'sú' acentuada
> inicial) — la API de cartas puede traer el texto con la doble-
> codificación UTF-8→Latin-1→UTF-8 típica en vocales acentuadas (mismo
> problema ya conocido y corregido aparte en GoldManager._fix_mojibake(),
> p.ej. 'TalismÃ¡n' en vez de 'Talismán'); si 'súbela' llega corrupto aquí
> el check anterior (que exigía el acento exacto) fallaba en silencio y
> Aho terminaba siguiendo a su portador al Cementerio/Destierro en vez de
> ofrecer la elección real.

### `_resolve_weapon_survives_wielder` — línea 395

> 'Cuando el portador fuera a salir del juego, súbela a tu mano o
> cámbiala de portador' (2026-08-30, p.ej. Aho) — reemplaza la regla por
> defecto de que un Arma sigue a su portador al Cementerio/Destierro.
> Solo el jugador humano elige por ahora (mover_placeholder del bot, ver
> llamador: para el rival se sigue aplicando la regla vieja hasta que
> haya IA para esta decisión).

### `_resolve_weapon_survives_wielder` — línea 446

> fire_enter_play=false (2026-09-25, ver comentario en _equip_weapon()):
> el Arma ya estaba en juego, solo cambia de portador porque el
> anterior murió — no es un juego nuevo, no debe re-disparar 'Cuando
> entra en juego' ni sumar al conteo de cartas jugadas este turno.

### `_disconnect_card_interaction_signals` — línea 454

> Desconecta TODAS las conexiones de las señales de interacción de una
> carta antes de queue_free() (2026-08-29) — sin esto, un hover/click que
> sigue apuntando al nodo después de liberarlo tira 'Invalid access...
> on a base object of type previously freed' al tocar .modulate en el
> próximo evento de mouse (reportado con Don de Amma desterrándose a sí
> mismo desde su Reserva). HandManager.remove_card() ya hacía esta
> desconexión para cartas en la MANO, pero destroy_card()/exile_card()
> aquí abajo son el camino real de TODA destrucción/destierro sin
> GameBoard (siempre null en este proyecto) — cartas en Reserva/Oro
> Pagado/líneas de juego, conectadas por Main._connect_card_signals(),
> nunca pasaban por esa limpieza. Desconecta cualquier conexión existente
> sin asumir quién la hizo (Main, HandManager, DynamicHand, MulliganHand,
> SelectionManager conectan las mismas 4 señales cada uno en su propio
> contexto).

### `take_from_cemetery` — línea 521

> Saca esa carta (por referencia) del Cementerio de player_id. Devuelve
> false si ya no estaba — atajo del bloque find/if idx < 0/remove que se
> repetía en los patrones (2026-10-13, §62).

### `take_damage` — línea 638

> pop_front() = tope real (2026-08-30, corregido — antes pop_back()
> tomaba del FONDO; el camino de robo que de verdad usa la partida,
> ZoneManager.draw_card(), confirma que el FRENTE del array es el
> tope). El daño de combate debe consumir cartas del tope del
> Castillo, no del fondo.

### `take_damage` — línea 668

> Log parcial si no se pudo hacer todo el daño
> (2026-08-28, "módulos gordos" punto 1): 'log_partial_damage' espera
> target_name: String como 3er parámetro — se pasaba player_id (int)
> directo, lo que revienta en tiempo de ejecución (error de tipo) cada
> vez que este log se dispara. Se corrige con el mismo formato usado en
> DamageManager._log_partial_damage().

## `scripts/core/managers/DamageManager.gd`

### `(nivel de archivo)` — línea 76

> (2026-08-28, "módulos gordos" punto 1): GameManager/ActionModule/CombatLog/
> TriggerSystem son autoloads garantizados — se sacó el cacheo redundante vía
> get_node_or_null() y se referencian directo. _game_board queda siempre
> null: no existe autoload '/root/GameBoard' ni método
> GameManager.get_game_board() (era el GameBoard.gd huérfano, eliminado).
> _apply_damage_to_castle() (única consumidora real de _get_board()) no la
> llama nadie hoy — el daño de combate real lo resuelve BattleManager, que ya
> usa CardManager.

### `_connect_signals` — línea 92

> GameManager es el único conductor de turnos (ver consolidación 2026-08-19).

### `apply_damage` — línea 231

> ─────────────────────────────────────────────────────────────────────────
> TRIGGERS POST-DAÑO
> ─────────────────────────────────────────────────────────────────────────
> (2026-08-28): 'trigger_event' no existe (nunca existió) en TriggerSystem.gd
> — este bloque nunca se ejecutó realmente (era código muerto detrás de un
> guard `if _trigger_system`). apply_damage()/apply_combat_damage() tampoco
> tienen llamadores reales hoy (ver check_defeat_condition() más abajo, que
> sí es la ruta viva). Se deja documentado, no se inventa un trigger nuevo.

### `_apply_damage_to_castle` — línea 287

> (2026-08-28): 'queue_trigger' tampoco existe en TriggerSystem.gd —
> mismo código muerto que arriba, documentado y no ejecutado nunca.

### `_apply_damage_to_castle` — línea 310

> Notificar al GameManager (2026-08-28: 'end_game' no existe en
> GameManager.gd — la API real es player_loses(); ver el mismo fix
> en check_defeat_condition() más abajo)

### `_apply_damage_prevention` — línea 471

> Prevenciones CONTINUAS ligadas a una fuente en juego (2026-09-06,
> p.ej. Cetro Demoniaco: "No puedes recibir daño" mientras esté en
> juego, one_shot=false, amount=-1) — sin este chequeo, una fuente
> que ya salió de juego seguía previniendo daño para siempre, porque
> el resto de esta función solo remueve entradas one_shot o con
> 'amount' agotado (amount=-1 nunca se agota).

### `_apply_damage_reduction` — línea 531

> Linaje Maldito (2026-10-18): "no recibes daño directo hasta tu próximo
> turno" (el de combate lo corta BattleManager).

### `_apply_damage_reduction` — línea 536

> Oro de Azi del Abismo (2026-10-17): "Reduce el daño recibido por tu
> Castillo en 1 por cada Oro Azi que controles".

### `check_defeat_condition` — línea 700

> (2026-08-28): 'end_game' no existe en GameManager.gd — el
> has_method() de abajo siempre daba falso y esta llamada, la ÚNICA
> ruta real (check_defeat_condition() sí es llamada en vivo desde
> ActionModule.gd), nunca terminaba la partida por mazo vacío fuera
> de combate. La API real es GameManager.player_loses(player_id, reason).

## `scripts/core/managers/ExhumarSystem.gd`

### `setup` — línea 19

> Exhumar condicional por turno (Cuervo Nocturno, 2026-10-14): el cache
> vence al cambiar de turno.

### `scan_cemetery_for_exhumar` — línea 53

> "Si atacaste en tu turno anterior, tiene Exhumar en tu Cementerio"
> (Cuervo Nocturno, 2026-10-14).

### `scan_cemetery_for_exhumar` — línea 66

> 2026-09-25, a pedido del usuario ("elimina logs redundantes"): este
> chequeo corre en CADA ventana de prioridad — con 0 cartas (el caso
> normal la mayor parte de la partida) no dice nada nuevo. Con 1+ sí es
> información real (hay algo jugable esperando).

## `scripts/core/managers/GameManager.gd`

### `(nivel de archivo)` — línea 2

> GameManager - Singleton que controla el estado global del juego
> Maneja turnos, fases, jugadores y el flujo general de la partida
>
> GAME_BOARD (2026-08-16): `game_board` y `game_board_ready` quedan
> declarados pero SIEMPRE null/nunca se emiten a propósito. Poblaban una
> clase GameBoard.gd que resultó ser código huérfano — su @onready apuntaba
> a un layout de tablero de una versión anterior de la escena (líneas de
> ataque/defensa/apoyo separadas) que ya no existe en Main.tscn actual, así
> que nunca se pudo adjuntar a ningún nodo real. Se eliminó ese archivo.
> No se quitó la propiedad de aquí porque ~15 archivos todavía la LEEN (todos
> ya con su propio camino real de respaldo vía CardManager/Main, no
> necesitan el board para funcionar) — quitarla también de ahí es un
> cambio más grande que se hará por partes. El único camino que hoy mueve
> cartas de verdad es CardManager + Main (ver docs/audit-2026-08-13.html).

### `(nivel de archivo)` — línea 32

> Número de turno de jugador (2026-10-18): sube en CADA turno, de los dos
> jugadores. Es el que hay que usar para "este turno" / "hasta tu próximo
> turno" (RuleState). current_turn se comparte entre tu turno y el del rival.

### `_change_phase` — línea 133

> Comienzo de fase (2026-10-18): "Puedes jugarlo al comienzo de cualquier
> Fase" / "en la Fase Final". Solo espera si alguien puede jugar algo; si
> no, esto no llega a ningún await y la fase sigue igual que siempre.

### `_process_vigilia` — línea 199

> Limpiar atacantes/bloqueadores de la ÚLTIMA batalla real (2026-08-22):
> si un turno termina SIN atacar, PhaseFlowController salta directo de
> VIGILIA a FINAL (ver 'Paso: omitiendo batalla → Fase Final') y jamás
> pasa por _start_batalla(), que era el único lugar que vaciaba
> 'attackers' — un Aliado que atacó quedaba en esa lista para siempre
> hasta que OTRO Aliado forzara la fase de Ataque de rebote. Aquí se
> limpia sí o sí al empezar cada Vigilia, haya habido batalla o no.

### `proceed_to_battle` — línea 213

> Pasa de Vigilia a Batalla Mitológica — único disparador ahora es el
> botón "Atacar" (2026-08-28). Si nadie ataca, confirm_attackers() con la
> lista vacía manda directo a Fase Final de todos modos (_end_batalla()),
> así que ya no hace falta un atajo aparte para "saltar la batalla".

### `_start_batalla` — línea 230

> Inicia la Batalla Mitológica — disparada por el botón "Atacar"
> (proceed_to_battle(), 2026-08-28). NO limpiar 'attackers'/'blockers'
> aquí: siguen vacíos porque solo ahora, ya en fase Ataque, se pueden
> declarar (_process_vigilia() ya garantiza que arrancan vacíos al
> empezar cada Vigilia nueva).

### `declare_attacker` — línea 239

> Declara un Aliado como atacante (DAR 5.3.1).
> Único punto de entrada real (vía CardInteractionModule._declare_attacker,
> llamado desde DropZone al soltar en la Línea de Ataque) — antes no validaba
> enfermedad de invocación, así que un Aliado recién jugado podía atacar sin
> Furia con solo arrastrarlo. Ver docs/audit-2026-08-13.html, hallazgo 5.
>
> Devuelve true/false (2026-08-17): antes no devolvía nada, y el llamador
> aplicaba el aspecto visual de 'atacando' (rotación, tinte naranja) SIN
> esperar a saber si esta validación aceptaba el ataque. Si fallaba por
> cualquier motivo (enfermedad de invocación, fase incorrecta, etc.), la
> carta quedaba con el aspecto de atacante para siempre sin haberse
> agregado realmente al combate — nunca hacía daño, y como nada revertía
> ese aspecto, parecía 'desaparecer'/quedar con un color raro.

### `declare_attacker` — línea 252

> Ya no acepta VIGILIA (2026-08-28, reemplaza el diseño de 2026-08-23 a
> pedido del usuario): declarar atacantes requiere haber pasado antes
> por el botón "Atacar" (GameManager.proceed_to_battle()), que es lo
> único que ahora termina Vigilia y empieza la Batalla Mitológica.

### `declare_attacker` — línea 267

> "Cuando ataque" (DAR 5.3.1) YA NO se dispara aquí (2026-08-29, corrige
> exploit real reportado: declarar/desdeclarar el mismo Aliado varias
> veces antes de confirmar disparaba el trigger una vez POR CADA
> declare, generando Oro/robando cartas/etc. de más — p.ej. Lobo
> Sagrado, "Cuando ataques, genera un Oro por el turno", Oro infinito).
> Se dispara una sola vez por Aliado en confirm_attackers(), cuando el
> ataque ya es definitivo — ver ese comentario para el detalle.

### `undeclare_attacker` — línea 278

> Retira un Aliado de la lista de atacantes antes de confirmar
> (2026-08-17, a pedido del usuario): con el clic reemplazando al
> arrastre, declarar un atacante por error es más fácil de lo que era —
> esto permite deshacerlo con otro clic mientras siga en el paso de
> Ataque, antes de presionar ¿Paso? para confirmar a todos juntos.
> No revierte el trigger 'cuando ataque' que ya se disparó (DAR: una vez
> resuelto un trigger no se deshace) — solo saca a la carta del combate
> que está por resolverse. Ya no acepta VIGILIA (2026-08-28): mismo
> cambio que declare_attacker(), ahora solo se declara/deshace una vez
> que la fase ya es Ataque.

### `confirm_attackers` — línea 305

> "Al comienzo del Ataque" (2026-10-17, a pedido del usuario — Almirante
> Akari: "no puede generar si no se declara ataque"): se resuelve recién
> aquí, con atacantes declarados, no al entrar a la fase.

### `confirm_attackers` — línea 310

> "Cuando ataque" (DAR 5.3.1) se dispara AQUÍ, una sola vez por Aliado,
> no en declare_attacker() (2026-08-29, corrige exploit real: declarar/
> desdeclarar el mismo Aliado varias veces antes de confirmar disparaba
> el trigger una vez POR CADA declare — p.ej. Lobo Sagrado, "genera un
> Oro por el turno", permitía Oro infinito). 'attackers' ya es la lista
> final deduplicada — declare_attacker() rechaza duplicados y
> undeclare_attacker() los saca — así que cada Aliado dispara su propio
> 'cuando ataque' exactamente una vez aquí, sin importar cuántas veces
> se declaró/desdeclaró antes de este punto.

### `confirm_attackers` — línea 321

> "si no fue declarado atacante este turno" (2026-10-12, p.ej.
> Guardia Real) — EffectInterpreter consulta esta marca.

### `confirm_attackers` — línea 330

> "Cuando ataques con tres o más Aliados..." (2026-08-30, p.ej. Sable de
> Napoleón) — condición sobre la CANTIDAD TOTAL de atacantes confirmados,
> no un trigger por Aliado individual (el loop de arriba dispara "cuando
> ataque" una vez por cada uno; esto es aparte, una sola vez).

### `_check_wielder_attack_triggers` — línea 346

> 'Cuando el portador ataque, si es de coste 1 o más, genera un Oro o
> Roba una carta' (2026-08-30, p.ej. Garfio Pirata) — trigger propio de un
> Arma equipada sobre el ataque de SU portador. El camino genérico
> (TriggerSystem._collect_triggers_for_event) solo revisa el texto de la
> carta que ataca, no el de sus Armas equipadas (mismo motivo por el que
> _check_attack_count_triggers() existe aparte para Sable de Napoleón) —
> se resuelve aquí, directo, con el mismo criterio.

### `_check_wielder_attack_triggers` — línea 361

> Cañón Helios (2026-10-18): "Cuando el portador ataca, puedes elegir
> un Aliado oponente para que lo bloquee."

### `_check_attack_count_triggers` — línea 427

> 'Cuando ataques con tres o más Aliados, las cartas que estén o sean
> puestas en los Cementerios este turno pierden su habilidad hasta tu
> próximo turno' (2026-08-30, p.ej. Sable de Napoleón). Se resuelve UNA
> SOLA VEZ aquí (no es un trigger por Aliado, es una condición sobre el
> total de atacantes confirmados) — apenas se encuentra una fuente con
> este texto, se aplica y se corta (no tiene sentido aplicar dos veces
> aunque hubiera dos copias).

### `confirm_blockers_and_collect_triggers` — línea 488

> Recolecta el trigger 'cuando bloqueas' (DAR 7.2/7.3) para cada
> bloqueador REALMENTE declarado, luego avanza a Guerra de Talismanes.
> Mismo criterio que confirm_attackers(): la lista ya es la definitiva (un
> bloqueador por atacante, declare_blocker() reescribe la misma clave del
> diccionario, no acumula duplicados si el jugador cambia de bloqueador
> antes de confirmar), así que cada Aliado dispara su propio 'cuando
> bloqueas' una sola vez, aquí, cuando el bloqueo ya es definitivo — no en
> declare_blocker() (mismo motivo del exploit ya documentado para
> confirm_attackers(): declarar/desdeclarar varias veces antes de
> confirmar dispararía el trigger una vez por cada intento).
>
> 2026-09-20 (arquitectura.md "539 cartas sin cobertura", libro de thoth):
> primer uso real del trigger on_block — hasta ahora estaba clasificado en
> Card.TRIGGER_KEYWORDS pero sin ningún código que lo recolectara ni
> resolviera (TriggerResolution._execute_trigger_effect() no tenía rama
> 'on_block'). No se reutiliza confirm_blockers() de arriba porque esa
> función quedó huérfana con lógica de reset que hoy podría pisar el
> estado de PriorityManager — este camino nuevo solo hace lo que el
> camino real (PhaseFlowController → advance_to_phase) ya hacía, más la
> recolección de triggers antes del cambio de fase.

### `confirm_blockers_and_collect_triggers` — línea 509

> Pan de Muerto (2026-10-18): "tus Aliados son Indestructibles mientras bloquean".

### `confirm_blockers_and_collect_triggers` — línea 518

> libro de thoth (Oro, 2026-09-20) — carta pasiva ajena al
> bloqueador, no llega por el camino de trigger_type de arriba
> (ver docstring de GoldManager.check_libro_de_thoth_block()).

### `_process_fase_final` — línea 546

> Fase Final: solo anuncia el cambio de fase.
> El robo de fin de turno y el descarte por límite de mano (DAR 5.D.3/5.D.4)
> se resuelven en PhaseFlowController._resolve_fase_final(), que corre para
> ambos jugadores (humano vía botón ¿Paso?, oponente vía _opponent_auto_pass).
> No dupliques esa lógica aquí — ver docs/audit-2026-08-13.html, hallazgo 1.

### `check_victory` — línea 560

> Verifica si algún jugador se quedó sin cartas en el Castillo (DAR
> 2.1 — perder por Castillo vacío).
>
> 2026-08-31, corrección de un bug real (reportado por el usuario: desterró
> 5 cartas del tope de un Castillo con Aho y el Castillo rival quedó en 0,
> pero el juego nunca declaró ganada la partida): 'players' son dos
> Node.new() vacíos (ver GameBootstrap._prepare_game(): 'Player1'/
> 'Player2' se crean sin script propio), así que
> player.has_method('get_deck_count') daba SIEMPRE false — esta función
> nunca disparó una victoria, ni siquiera en su único llamador real
> (ZoneManager.draw_card() al intentar robar con el mazo ya vacío). El
> camino de victoria por DAÑO DE COMBATE nunca pasó por aquí — BattleManager
> calcula el mazo vacío él mismo y llama GameManager.player_loses()
> directo, por eso ese sí funcionaba. Se lee el tamaño real de
> player_deck/opponent_deck en Main (mismo patrón que el resto de
> autoloads para llegar a Main) en vez de los Nodos dummy.

## `scripts/core/managers/PaymentManager.gd`

### `(nivel de archivo)` — línea 91

> "Esa carta cuesta un Oro adicional el PRÓXIMO turno" — por NOMBRE de
> carta, no por instancia (2026-08-29, p.ej. Tesoro de los Césares: "puedes
> Barajar una carta de tu mano para nombrar una carta. Esa carta cuesta un
> Oro adicional el próximo turno"). Registro APARTE de oros_mas_modifiers a
> propósito: ese Array se limpia entero en CADA turn_started (pensado para
> 'por el turno actual'), pero aquí el efecto todavía NO debe estar activo
> en el momento de registrarse — arranca solo cuando empiece el turno
> siguiente, y dura exactamente ese turno. {nombre_lower: número_de_turno}.

### `refresh_all_hand_cost_badges` — línea 141

> Refresca la insignia de coste (Card.refresh_cost_badge()) de todas
> las cartas en tu mano — llamar después de cualquier cambio que pueda
> afectar el coste de una carta ajena a ella misma (2026-08-30): un
> modificador nuevo, uno que se limpia, o un recargo diferido que
> arranca/expira al cambiar de turno.

### `puede_jugar_carta` — línea 171

> Oro Virtual (genérico + restringido) — 2026-10-06: GoldManager.
> oros_virtuales/restricted_gold_pools ya son por jugador (ver
> arquitectura.md §33), así que esto deja de limitarse al jugador 0.
> 2026-08-28, corrige bug real: aquí se leía 'main.get("oros_virtuales")',
> pero esa propiedad vive en main._gold_manager.oros_virtuales, no en
> Main — siempre daba null/0, así que el Oro Virtual de Lobo Sagrado
> NUNCA contaba para decidir si se podía siquiera INTENTAR jugar una
> carta, aunque GoldManager.pagar_coste() sí lo hubiera cobrado bien
> después.

### `_self_scaling_oro_discount` — línea 250

> '...cuesta un Oro menos por cada Oro que controles' (2026-08-30,
> Aaru) — descuento intrínseco de ESTA carta que escala con el propio
> estado del tablero de su controlador (Reserva + Oro Pagado), no un
> modificador registrado por un efecto externo como el resto de
> oros_menos_modifiers. Se detecta por texto y se recalcula fresco cada
> vez (no se cachea: el conteo de Oro puede cambiar entre llamadas del
> mismo turno).

### `_self_scaling_oro_discount` — línea 260

> "Reduce su coste en un Oro por cada Oro que controles" (2026-09-04,
> Piruquina) — mismo concepto que Aaru, otra forma de imprimirlo. Nota:
> el texto de Piruquina dice 'hasta un mínimo de 1', pero el piso real
> de esta función es 0 (ver calcular_coste_real(), maxi(..., 0) es
> compartido con oros_menos_modifiers) — desviación menor conocida, sin
> caso de prueba a mano que la haga notoria todavía.

### `_conditional_boolean_discount` — línea 274

> Descuentos intrínsecos de 1 Oro condicionados a un booleano del
> tablero (2026-09-06) — a diferencia de _self_scaling_oro_discount()
> (escala con una cantidad), aquí el descuento es 0 o 1 según se cumpla o
> no una condición puntual. Lista chica y explícita, mismo criterio que
> el resto de detectores por texto de este archivo. 'jugaste este turno'
> (Cetro Demoniaco) NO se evalúa — no existe todavía un registro
> genérico de 'jugué un Arma este turno', solo se chequea la mitad
> 'controlas' de la condición.

### `_conditional_boolean_discount` — línea 308

> "Reduce su coste en un Oro si controlas Armas" (sable corto, 2026-09-20,
> arquitectura.md "539 cartas sin cobertura") — las Armas son hijas de su
> portador, no children directos del campo (mismo motivo documentado en
> ContinuousEffectParser.gd para el bono de Manuel Bulnes), así que se
> revisa 'equipped_weapons' de cada Aliado en vez de recorrer field.
> get_children() buscando tipo ARMA directo (eso nunca encontraría nada).

### `_conditional_boolean_discount` — línea 340

> "Si no controlas Aliados de coste 1 o menos, reduce su coste en un
> Oro" (Jabberwocky). 2026-09-30, bug real reportado por el usuario
> ("Stack overflow... en PaymentManager"): usaba calcular_coste_real(c)
> para revisar el coste de cada Aliado — si Jabberwocky mismo ya está
> en el campo (o cualquier otro Aliado cuyo propio coste dependa de
> este mismo chequeo), esa llamada vuelve a entrar a esta función y
> nunca termina. Se revisa el coste BASE (card_cost, sin modificadores)
> en vez del efectivo — mismo criterio que los chequeos hermanos de
> arriba (Armas/Dragones), que tampoco llaman calcular_coste_real().

### `add_named_surcharge_next_turn` — línea 365

> Registra que 'card_name' cuesta 1 Oro adicional durante target_turn
> (2026-08-29, Tesoro de los Césares — quien lo registra ya calculó
> target_turn como GameManager.turn_serial + 1 al activar la habilidad).

### `_connect_signals` — línea 426

> (2026-08-28, "módulos gordos" punto 1): esto apuntaba a GameManager
> buscando señales 'card_moved_to_zone'/'zone_changed' que NUNCA
> existieron ahí (ni existen hoy) — el cache de Exhumar jamás se
> invalidaba tras el primer escaneo, así que las opciones de Exhumar
> quedaban congeladas con el estado del cementerio del primer chequeo.
> La señal real es CardManager.zone_changed. Mismo problema con
> 'priority_given' (no existe en PriorityManager; la real es
> priority_changed).

### `_connect_signals` — línea 440

> Limpiar modificadores al inicio de cada turno.
> GameManager es el único conductor de turnos (ver consolidación 2026-08-19).

### `card_has_exhumar` — línea 475

> Expone el chequeo privado de ExhumarSystem — usado por ZoneViewerModule
> para marcar como clickeables las cartas del Cementerio que se pueden
> jugar via Exhumar (2026-08-23). Respeta el silencio de Cementerio
> (2026-08-30, Sable de Napoleón) — 'pierde su habilidad' incluye Exhumar.

### `card_playable_from_exile` — línea 491

> 'Puedes jugar(lo/la) desde/de tu Destierro' (2026-09-04, a pedido del
> usuario — p.ej. uriel, batallon de ovejas, cruzar el bosque) — usado
> por ZoneViewerModule para marcar como clickeables las cartas del
> Destierro propio jugables vía GoldManager.play_card_from_exile().
> Lista chica y explícita (mismo criterio que card_has_exhumar()/
> _ability_is_hand_usable()), no un permiso genérico por presencia de
> 'Destierro' en el texto (esa palabra aparece en muchísimas habilidades
> sin relación con jugar desde ahí).

### `get_exile_play_discount` — línea 530

> Descuento fijo al jugar desde el Destierro (2026-09-04, p.ej.
> rafael: 'reduciendo su coste en un Oro') — 0 si no aplica (la mayoría,
> p.ej. uriel/batallon de ovejas pagan el coste completo).

### `get_exile_play_discount` — línea 539

> =============================================================================
> VALIDACIÓN DE CARTAS ÚNICAS Y CONSULTAS DE ORO — ver PaymentValidation.gd
> (2026-08-28, "módulos gordos": _card_is_unique/_validate_unique_card/
> _check_unique_in_play/_check_unique_in_stack/_get_cards_in_zone/
> _get_player_cemetery/_get_player_available_gold se movieron ahí, acceso vía
> _validation. Se quedaron aquí porque son consultas sin estado — nada que ver
> con _current_card/_payment_popup/etc., que sí están entrelazados con
> ExhumarSystem.gd/XCostSelector.gd como blackboard compartido.)

### `_get_player_name` — línea 581

> Obtiene el nombre del jugador para logs
> (2026-08-28: GameManager no expone get_player_name() ni una propiedad
> '_players' — esto siempre cayó al fallback genérico. GameManager.players
> es un Array[Node] sin campo de nombre legible hoy, así que se deja el
> fallback como único comportamiento real en vez de simular una lectura
> que nunca funcionó.)

## `scripts/core/managers/PaymentUI.gd`

### `(nivel de archivo)` — línea 3

> PaymentUI — Popup de selección de método de pago y su procesamiento
> (Normal/Exhumar/Sacrificio/Descarte/Vida/Alternativo/X). El estado
> compartido (_current_card/_current_player_id/_current_cost_info/
> _selected_method/_payment_popup/_state) se queda en PaymentManager —
> ExhumarSystem.gd y XCostSelector.gd lo leen/escriben directo sobre
> PaymentManager como blackboard compartido, así que moverlo hubiera
> significado reescribir ese acceso en los 3 archivos para nada (esta
> clase igual lo lee/escribe vía _main, sin ganar nada con relocarlo).
> Opera sobre PaymentManager via _main.
> Extraído de PaymentManager.gd (2026-08-28, "módulos gordos" — mismo corte
> que ya separó ExhumarSystem/CostModifiers/XCostSelector/PaymentValidation).

## `scripts/core/managers/PaymentValidation.gd`

### `(nivel de archivo)` — línea 3

> PaymentValidation — Consultas de solo-lectura para el pago: validación de
> cartas Únicas (DAR Sección 4.1) y disponibilidad de Oro/Cementerio del
> jugador. Ninguna de estas funciones toca el estado de pago en curso
> (_current_card/_payment_popup/etc. se quedan en PaymentManager — están
> entrelazados con ExhumarSystem.gd/XCostSelector.gd como estado compartido,
> sacarlos de ahí sería mucho más riesgo para poco beneficio). Opera sobre
> PaymentManager via _main.
> Extraído de PaymentManager.gd (2026-08-28, "módulos gordos" — mismo corte
> que ya separó ExhumarSystem/CostModifiers/XCostSelector).

### `_get_cards_in_zone` — línea 118

> Obtiene las cartas en juego (campo) de un jugador. Antes buscaba
> métodos que no existen en GameManager (get_zone_cards/get_cards_in_zone)
> y como fallback un '_game_board' que tampoco existe — siempre devolvía
> [], así que la validación de la palabra clave Única jamás encontraba
> una copia ya en juego. Se ignora el parámetro de zona: agrega las 3
> líneas reales (Defensa/Ataque/Apoyo, consolidación 2026-08-20) — Única
> puede aplicar a cualquier tipo de carta en juego.

## `scripts/core/managers/PriorityManager.gd`

### `(nivel de archivo)` — línea 27

> 2026-09-11: true mientras hay un diálogo reactivo real esperando decisión
> del humano (p.ej. Signo Amarillo, ResponseWindowHandler) — el auto-pase
> "no hay nada que decidir aquí" (PhaseFlowController/ResponseWindowHandler)
> lo respeta para no cerrar la ventana por abajo mientras el diálogo sigue
> abierto esperando un click.

### `(nivel de archivo)` — línea 54

> Guerra de Talismanes por turnos (2026-10-13, §64, opción B elegida por el
> usuario). Cada Talismán/habilidad abre su propia Ventana de Respuesta
> (Paso D) sobre esta misma instancia, que pisa la ventana de la Guerra.
> Antes nadie la volvía a abrir: quedaba sin ventana hasta que alguien
> apretaba "Daño" (que la recuperaba siempre con el defensor) y, peor, el
> "ambos pasaron" de la ventana de respuesta podía terminar la Guerra. Ahora,
> cuando la acción termina de resolverse, la Guerra sigue con el OTRO
> jugador (el que no actuó) y los pases vuelven a cero.

### `(nivel de archivo)` — línea 67

> Contador que sube en CADA start_priority_window() (2026-09-15, bug real
> reportado por el usuario: "se traba en Guerra de Talismanes" — con log
> en vivo confirmando visible=true dos veces seguidas y luego, sin ningún
> click del jugador, priority_window_active=false). Causa real:
> PhaseFlowController._human_pass_after()/_bot_pass_after() son timers de
> 0.2s "fire and forget" — si la ventana para la que se programaron (p.ej.
> la Ventana de Respuesta corta de un trigger 'cuando entra en juego') ya
> se cerró SOLA antes de que el timer termine, el timer sigue vivo y
> dispara tarde sobre lo que sea que esté activo en ESE momento — si para
> entonces ya abrió una ventana NUEVA (p.ej. Guerra de Talismanes) con el
> mismo jugador con prioridad, el timer viejo le pasa la prioridad SIN que
> el jugador haya hecho nada. Los llamadores capturan esta generación al
> programarse y la comparan al disparar — si cambió, la ventana para la
> que se programaron ya no es la actual, no hacen nada.

### `(nivel de archivo)` — línea 83

> Jugador que controla el objeto de la pila al que responde esta ventana
> (Paso D de StackStepResolver), o -1 si la ventana no responde a ninguna
> carta/habilidad puntual (fase, pila recién vaciada, etc.). Ver
> needs_real_decision() — 2026-10-11, botón de paso simétrico online.

### `(nivel de archivo)` — línea 89

> Tiempo límite para responder en una Ventana de Respuesta online (2026-10-11,
> a pedido del usuario: "5 segundos nada más por ahora"). Solo aplica a
> RESPONSE_WINDOW — Bloqueo y Guerra de Talismanes esperan sin límite.

### `_ready` — línea 96

> GameManager es el único conductor de fases (ver consolidación
> 2026-08-19, docs/audit-2026-08-13.html) — la ventana de Bloqueo/Guerra
> de Talismanes se abre automáticamente al escuchar su phase_changed.

### `_get_starting_priority_player` — línea 144

> "Tu tienes la prioridad en Guerra de Talismanes" (2026-08-30,
> p.ej. Garfio Pirata) — anula la regla DAR 5.C3 por defecto
> (defensor primero) si algún jugador controla una carta que se
> la otorgue.

### `_player_with_guerra_talismanes_priority` — línea 167

> Busca, entre ambos jugadores, si alguno controla una carta (o Arma
> equipada) cuyo texto le otorga la prioridad en Guerra de Talismanes
> (2026-08-30, p.ej. Garfio Pirata: 'tu tienes la prioridad en Guerra de
> Talismanes'). Devuelve el player_id o -1 si nadie la tiene.

### `needs_real_decision` — línea 317

> ¿Tiene este jugador una decisión real que tomar en la ventana actual,
> o puede pasar automáticamente? (2026-10-11, a pedido del usuario: "el
> jugador activo solo pasa para ir a la guerra o pasar turno; el otro
> debe pasar cada vez que el oponente juegue una carta o use una
> habilidad", y al cambiar de turno se invierten los roles).
> - Ventana de Respuesta: decide solo el rival de quien controla el objeto
> de la pila. Sin objeto puntual (pila recién vaciada) nadie decide.
> - Bloqueo: decide solo el defensor.
> - Guerra de Talismanes (y el resto): deciden ambos.

## `scripts/core/managers/RuleState.gd`

### `(nivel de archivo)` — línea 2

> RuleState — registro único del estado de las reglas especiales (2026-10-18,
> punto 3 de la revisión de código). Antes cada carta guardaba lo suyo como
> metadato del nodo Main (damage_immunity, castle_removed, sidhes_lock...),
> sin un dueño ni un reinicio claros, y contando con current_turn, que sube
> una vez por RONDA. Aquí todo cuenta con GameManager.turn_serial (un número
> por cada turno de jugador) y vence o se reinicia solo:
> - contadores de este turno:     count() / add()
> - efectos "hasta el turno N":   set_until() / active() (next_own_turn())
> - marcas de este turno:          mark() / marked()
> - pendientes de un solo uso:     set_pending() / has_pending() / take_pending()
> - datos que valen este turno:    set_turn_data() / turn_data()
> Se borra todo al empezar una partida (GameManager.game_started). Solo corre
> en el Anfitrión: el Remoto no ejecuta la lógica del juego.
>
> Claves en uso: "searched", "outside_ability", "castle_removed" (TurnLimits),
> "no_combat_damage", "no_direct_damage" (Linaje Maldito, Quicaví),
> "trigger_gold_toll" (Mecha-Daikaiju), "escritura" (Escritura Sagrada),
> "next_gold_silenced" (Supremacia Kaiju), "sidhes_lock" (Sidhes del Bosque).

## `scripts/core/managers/TurnManager.gd`

### `(nivel de archivo)` — línea 2

> TurnManager - Autoload reducido a sus dos responsabilidades reales
> dentro del flujo de turno/fase (DAR Sección 5).
>
> CONSOLIDACIÓN (2026-08-19): este archivo tenía una máquina de fases
> completa propia (change_phase, prioridad, pila de efectos, atacantes/
> bloqueadores declarados, robo y límite de mano) que solo se ejecutaba
> una vez en toda la partida — el arranque del Turno 1 — y nunca volvía a
> dispararse. GameManager._change_phase()/advance_to_phase() es y era el
> único conductor real de fases (ver docs/audit-2026-08-13.html). Esa
> máquina muerta se eliminó junto con active_player_id/current_turn_number,
> que quedaban congelados en el valor del Turno 1 pero se leían como datos
> en vivo desde TriggerSystem (orden APNAP) y AnimationQueue
> (zone_entered_turn) — ahora esos lugares leen GameManager directamente.
> El arranque del Turno 1 ya no pasa por este archivo: GameManager.start_game()
> llama a _start_turn() directamente.
>
> Lo que queda es lo único que tenía llamadores reales:
> - Sistema de Oro (can_place_oro/on_card_played/_reset_oro_tracking),
> usado por GoldManager y CardInteractionModule.
> - Validación de enfermedad de invocación / Furia (can_attack), usada
> por GameManager.declare_attacker() y DropZone.

### `(nivel de archivo)` — línea 33

> 2026-09-20, Quinto Sello ("Si está en tu Cementerio, no se pueden jugar más
> de cinco cartas por turno") — contador GLOBAL de cartas jugadas en el turno
> actual, de CUALQUIER jugador (el texto no dice "tuyas"/"tu oponente", así
> que es una restricción de regla, no un efecto sobre un jugador puntual).
> A diferencia de any_card_played_this_turn (booleano, solo para la regla del
> Oro y solo se marca en Vigilia), este cuenta TODA carta que entra en juego
> en CUALQUIER fase — se incrementa en GoldManager._trigger_enter_play(), el
> único choke point real por el que pasa toda carta jugada (arquitectura.md
> §1), y se consulta en GoldManager.play_card() antes de pagar/mover nada.

### `ignores_oro_chance_lost` — línea 74

> 'En tu Vigilia, si no pusiste Oros en juego este turno, ponlo de tu
> mano en tu Reserva' (2026-08-30, p.ej. Infernum Vox) — a diferencia de
> la regla general (DAR 5.B: el Oro debe ser la PRIMERA carta jugada; si
> juegas cualquier otra cosa antes, se pierde la oportunidad para el resto
> del turno), esta carta se puede colocar como Oro en cualquier momento
> de tu Vigilia mientras tú mismo no hayas puesto un Oro todavía este
> turno — no le importa si ya jugaste otra carta antes. Es una EXCEPCIÓN
> puntual de ESTA carta, no el comportamiento general, así que se detecta
> por texto en vez de agregar un flag nuevo al motor.

### `player_can_attack` — línea 116

> ¿Tiene 'player_id' al menos un Aliado en juego que pueda declarar
> ataque? (botón "Atacar"/"Fase Final" y salto del Ataque, 2026-10-18).

### `can_attack` — línea 136

> Restricción explícita (2026-09-03, p.ej. Kuchiku Kan: 'no pueda
> atacar... mientras este Aliado esté en juego') — ContinuousEffect
> Manager.can_attack() ya existía pero nadie lo consultaba todavía.

### `can_attack` — línea 158

> _has_furia_fallback() se eliminó aquí (2026-08-28, "módulos gordos" punto
> 1): KeywordManager es autoload — siempre existe, esta rama nunca corría.

## `scripts/core/network/GameStateBroadcaster.gd`

### `(nivel de archivo)` — línea 3

> GameStateBroadcaster — instanciado siempre en Main.gd, pero SOLO activo
> cuando esta instancia es el Anfitrión de una sala de red activa
> (NetworkClient.room_code != "" and NetworkClient.is_host). Traduce las
> señales que EffectController YA emite en cada transición de zona real
> (on_card_entered_play/on_card_left_play) a instrucciones de red
> ({"op":"move_card"/"remove_card",...}) para que RemoteMirrorController
> (del lado del cliente Remoto) pueda reflejar el tablero.
>
> Alcance original (2026-09-11, Fase B): las 5 zonas PÚBLICAS "en juego"
> (Constants.ZONES_IN_PLAY — Reserva de Oro, Oro Pagado, Línea de Defensa/
> Ataque/Apoyo), las únicas con Nodos Card visibles en el tablero
> (Cementerio/Destierro solo muestran un contador de texto, sin cartas
> individuales visibles — no hace falta streaming para eso todavía).
> Castillo (privado) queda fuera a propósito — ver GameManager/ZoneManager,
> no tiene Nodos persistentes que mostrar de todos modos (solo un contador).
>
> 2026-10-08 (ver arquitectura.md §45, a pedido del usuario — "revisa la
> mano para que se pueda ver durante toda la partida"): la Mano del
> jugador 1 YA se transmite también, para que el Remoto tenga su propia
> mano real y persistente (player_hand poblado todo el tiempo), no solo
> una fila de cartas dentro de cada prompt puntual. La mano del Anfitrión
> NUNCA viaja por aquí (fog of war real, no solo visual) — solo se
> escuchan las señales de _opponent_fan (jugador 1), nunca las de
> player_hand.

### `_on_castillo_counts_changed` — línea 90

> Cartas que YA estaban en juego antes de conectarnos (2026-10-11, bug real
> reportado por el usuario: "no puedo ver los oros iniciales"): el Oro
> Inicial se coloca con add_child() directo en GameBootstrap._setup_oro_
> inicial(), sin pasar por EffectController.on_card_entered_play, así que
> nunca viajaba al Remoto. Snapshot de las 5 zonas en juego de ambos lados
> al empezar la partida — move_card es idempotente por card_id del lado
> Remoto, así que no duplica nada si alguna ya se había enviado.

### `_sync_cards_already_in_play` — línea 112

> Contenedor en juego -> (jugador, zona). 2026-10-12, bug real reportado por
> el usuario ("jugué una carta desde el jugador 2 y ni siquiera se pagaron
> los Oros"): pagar mueve el Oro de Reserva a Oro Pagado con add_child()
> directo (GoldManager.pagar_coste()/EasyBotController._pay_oro_for_bot()),
> sin pasar por on_card_entered_play — el Remoto nunca se enteraba, ni de
> sus Oros ni de los del Anfitrión (lo mismo al recuperarlos en la
> Agrupación). Vigilar child_entered_tree de los 10 contenedores cubre
> CUALQUIER movimiento entre zonas en juego, venga del código que venga;
> move_card es idempotente del lado Remoto.

### `_on_card_entered_play` — línea 170

> "own" es relativo al RECEPTOR (el Remoto, que del lado del Anfitrión
> siempre es el jugador 1) — ver "perspectiva relativa al receptor" en
> docs/plans/2026-09-09-multiplayer-remoto-design.md.

### `_send_remove_card` — línea 205

> Cartas sin habilidad (silenciadas, con el nombre bloqueado o convertidas)
> — 2026-10-13 (§63, Alicia en Wonderland): el Remoto no tiene esos
> bloqueos (viven en el KeywordManager del Anfitrión), así que nunca veía
> el gris de "sin habilidad". Se manda la lista completa (mesa + la mano
> del Remoto; nunca la del Anfitrión) solo cuando cambia.

## `scripts/core/network/NetworkClient.gd`

### `(nivel de archivo)` — línea 2

> NetworkClient — autoload, capa de red del multiplayer remoto (Fase A,
> docs/plans/2026-09-09-multiplayer-remoto-design.md e
> iterative-booping-abelson.md). Cliente WebSocket crudo (WebSocketPeer,
> builtin de Godot 4 — no MultiplayerAPI/ENet, porque el relay del lado del
> servidor es un reenviador ciego por sala, no un peer de multiplayer real)
> contra `relay-server/` (Node.js + ws, protocolo documentado en su
> server.js). No sabe NADA de reglas de Mitos y Leyendas — solo mueve JSON
> de un lado a otro. Quien interpreta esos mensajes es GameBootstrap/
> RemotePlayerController (fases B/C), no este archivo.
>
> Modo Anfitrión vs Remoto: `is_host` se fija solo al llamar create_room()/
> join_room() — antes de eso no hay ningún modo elegido (partida 100% local
> contra el bot, camino existente intacto).

### `(nivel de archivo)` — línea 30

> Último mensaje de juego recibido por "op" (2026-09-10, Fase A — intercambio
> de mazo): un mensaje puede llegar antes de que el receptor esté listo para
> escucharlo (p.ej. el Remoto manda su mazo apenas confirma, pero el
> Anfitrión solo empieza a escuchar cuando llega a ese punto del flujo) —
> quien lo necesite puede revisar aquí en vez de depender solo de la señal en
> vivo. Se limpia junto con el resto del estado de sala.

### `await_intent` — línea 40

> Espera el próximo {"op":"intent","kind":X,...} con X en expected_kinds.
> Sin timeout — mismo criterio que el resto del motor espera a un jugador
> humano local (SelectionManager). Si la conexión se cae mientras se
> espera, esto queda colgado para siempre — aceptable en v1 (el diseño ya
> decidió 'sin reconexión, la partida termina').
>
> 2026-09-30 — movido aquí desde RemotePlayerController._await_intent()
> (que ahora delega en este) para que SelectionManager.gd/SelectionDialogs.gd
> también puedan esperar un intent del Remoto sin duplicar la lógica
> (Fase 3 del plan de paridad, docs/plans/2026-09-20-remote-multiplayer-
> parity.md).

## `scripts/core/network/RemoteMirrorController.gd`

### `(nivel de archivo)` — línea 3

> RemoteMirrorController — instanciado siempre en Main.gd (Anfitrión y
> Remoto por igual), pero SOLO hace algo si esta instancia concreta es el
> Remoto de una sala de red activa (NetworkClient.room_code != "" and not
> NetworkClient.is_host). En ese caso, GameBootstrap ya se detiene solo
> después de mandar el mazo propio (ver GameBootstrap._send_own_deck_and_
> wait_for_host()) — no hay doble simulación corriendo (el Remoto nunca
> llega a GameManager.setup_game()/start_game() de forma local), pero
> tampoco hay nada más que pase: esta clase es lo que hace que después de
> esa espera, la persona real pueda seguir jugando.
>
> Escucha los mensajes {"op":"prompt","kind":...} que manda
> RemotePlayerController (scripts/core/ai/RemotePlayerController.gd) desde
> el lado del Anfitrión y muestra una UI mínima para que la persona elija,
> devolviendo {"op":"intent","kind":...} — mismo protocolo documentado ahí.
>
> Alcance de este incremento (2026-09-11, Fase B): cubre los 4 tipos de
> prompt que RemotePlayerController ya manda (mulligan/vigilia/ataque/
> response_window), CON diálogos de texto (nombre/coste, sin arte). Además
> aplica las instrucciones "move_card"/"remove_card" que manda
> GameStateBroadcaster desde el lado del Anfitrión — esto SÍ crea Nodos
> Card reales (con arte) en los contenedores correctos del tablero, para
> las 5 zonas públicas "en juego" (Reserva de Oro/Oro Pagado/Línea de
> Defensa/Ataque/Apoyo). Mano/Castillo (privados) y Cementerio/Destierro
> (públicos pero sin Nodos visibles, solo contador) quedan fuera de este
> streaming por ahora — ver GameStateBroadcaster.gd.

### `(nivel de archivo)` — línea 38

> Botón de paso del Remoto (2026-10-11): qué hace el botón del HUD (y el
> atajo P) según el prompt activo, y el window_id de la ventana de
> prioridad que se está respondiendo (-1 si no hay ninguna).

### `(nivel de archivo)` — línea 43

> Tecla N (2026-10-17): qué hace "no hacerlo / terminar" en el prompt de
> objetivo activo (solo selecciones opcionales). Vacío si no hay ninguno.

### `skip_optional` — línea 65

> card_id de un Aliado propio en juego que puede atacar -> si está marcado
> como atacante (Fase de Ataque del Remoto, 2026-10-11).

### `skip_optional` — línea 68

> Bloqueo en el tablero (2026-10-11): blocker_id -> [attacker_id válidos],
> blocker_id -> attacker_id asignado, y el bloqueador que espera que se
> elija su atacante ("" si ninguno).

### `skip_optional` — línea 74

> Selección genérica sobre el tablero/mano (2026-10-11): card_id -> qué hacer
> al clickearla (portador de Arma, objetivo de un efecto, habilidad de
> respuesta). _pick_multi guarda las marcadas en una selección múltiple.

### `_on_message` — línea 102

> 2026-09-23, bug real reportado por el usuario: cualquier prompt
> real que llegue (mulligan/vigilia/ataque/etc.) tiene que tapar
> la pantalla "ESPERANDO JUGADOR" que dejó el duelo de dados — sin
> esto, el diálogo real se construía IGUAL, pero por debajo de esa
> pantalla de carga (otra capa, nunca se ocultaba sola), dejando
> al jugador Remoto viéndola para siempre sin ninguna forma de
> llegar al prompt real ni de que este vuelva a intentarlo.

### `_on_message` — línea 184

> =============================================================================
> DUELO DE DADOS — reproduce del lado Remoto la MISMA tirada que el
> Anfitrión ya resolvió (2026-09-20, a pedido del usuario: antes cada
> pantalla tiraba sus propios dados por separado, sin relación entre sí —
> ver GameBootstrap._show_dice_roll()/DiceDuel3D.forced_result1/2).
> =============================================================================

### `_show_dice_roll_mirror` — línea 209

> 2026-09-23, bug real reportado por el usuario (Anfitrión): el Remoto se
> quedaba pegado para siempre en "ESPERANDO JUGADOR" — causa real: si el
> mensaje "prompt"/"mulligan" (el Anfitrión llama a RemotePlayerController.
> run_mulligan() apenas termina SU PROPIO mulligan) llegaba DURANTE esta
> animación (tarda unos segundos), _show_mulligan_prompt() ya construía
> el diálogo real sobre inspection_layer — pero este callback, un
> instante después, tapaba ese diálogo con la pantalla de carga
> (MatchLoadingOverlay, otra capa por encima), dejando el prompt real
> invisible/inaccesible sin ningún mensaje nuevo en camino que lo
> destapara. Ahora solo se muestra la espera si ningún prompt real llegó
> todavía mientras corría la animación.

### `_apply_move_card` — línea 246

> can_interact queda en false a propósito (2026-09-11): la
> inspección/targeting de cartas mirroreadas es Fase C (todavía no
> hay forma de que un click aquí dispare nada por red) — mostrarlas
> como no-interactivas evita clicks muertos confusos.

### `_apply_remove_card` — línea 291

> =============================================================================
> MANO PROPIA PERSISTENTE (GameStateBroadcaster._on_hand_card_added()/
> _on_hand_card_removed(), 2026-10-08, arquitectura.md §45) — a diferencia
> de _apply_move_card()/_apply_remove_card() (las 5 zonas públicas en
> juego), esto puebla player_hand de verdad, con Nodos que se quedan ahí
> durante TODA la partida, no solo mientras un prompt puntual está abierto.
> 2026-10-11: can_interact = true — la mano física es ahora la ÚNICA forma de
> jugar cartas desde la mano. CardInteractionModule desvía los clicks del
> cliente Remoto a on_card_double_clicked() (nunca llegan a GoldManager.
> play_card() local, que rompería todo al no pasar por el protocolo de intents).
> =============================================================================

### `_build_overlay` — línea 362

> 2026-10-07, bug real reportado por el usuario (probando online por
> primera vez): CardInspectionLayer.tscn arranca con visible=false (solo
> CardInspectionLayer.gd lo prende/apaga al inspeccionar una carta) — sin
> esto, el diálogo se construía bien pero quedaba invisible, el Remoto
> nunca veía ningún prompt (mulligan incluido) y la partida se quedaba
> congelada esperando una respuesta que nunca podía mandar. Mismo
> mecanismo ya usado por BernardoAbilityHandler.gd para su propio diálogo
> ajeno a una inspección real — ver mark_inspection_layer_in_use().

### `_add_row_button` — línea 412

> =============================================================================
> CARTAS REALES EN LOS PROMPTS (2026-10-07, a pedido del usuario: "no sale
> mi mulligan bonito, el abanico de cartas está todo escrito") — mismo
> patrón ya usado en popups livianos del lado del Anfitrión (p.ej.
> GoldManagerTax._open_cemetery_reveal_popup()): Nodos Card.tscn reales con
> arte, no interactivos (el click que de verdad decide pasa por los botones
> de abajo, ya armados con card_id/índice — esto solo reemplaza las listas
> de puro texto por la carta de verdad). Requiere que RemotePlayerController.
> _card_public_data() mande el card_data COMPLETO, no solo nombre/coste.
> =============================================================================

### `_show_mulligan_prompt` — línea 475

> 2026-10-08, a pedido del usuario ("construir el abanico visual real
> como el del Anfitrión" — ver arquitectura.md §44): a diferencia del
> resto de los prompts (que usan _build_overlay()/_build_card_row(), una
> fila de solo lectura + botones de texto aparte), el mulligan reusa los
> Nodos REALES que Main.tscn ya tiene para esto — mulligan_overlay/
> mulligan_hand (MulliganHand, el mismo abanico con curva/hover que ve el
> Anfitrión)/keep_hand_button/mulligan_button — en vez de construir un
> popup aparte. Esos botones ya vienen conectados a MulliganController.
> on_keep_hand_pressed()/on_mulligan_pressed() (para el flujo LOCAL del
> Anfitrión) — hay que desconectarlos antes de reusarlos, porque esos
> handlers terminan en GameManager.start_game() asumiendo una partida
> local que el Remoto nunca corrió (_dice_winner nunca seteado de este
> lado) — dispararían eso por error si se dejaran conectados.

### `_show_mulligan_prompt` — línea 513

> Mulligan simultáneo (2026-10-12): si el Anfitrión todavía está
> eligiendo, se espera aquí; lo tapa el primer mensaje de partida
> iniciada (castillo_counts, ver _on_message()).

### `_show_vigilia_prompt` — línea 532

> 2026-10-11 (a pedido del usuario: "sigue saliendo el texto de la mano y
> al mismo tiempo la mano, la idea es siempre solo usar la mano física"):
> sin popup. Las cartas jugables de la mano real (player_hand, §45)
> brillan y se juegan con doble clic, igual que el Anfitrión; el botón de
> paso del HUD ("Atacar") termina la Vigilia. Ver on_card_double_clicked().

### `_show_vigilia_prompt` — línea 547

> Habilidades activadas de sus cartas en juego (2026-10-12): brillan en
> dorado; clic en la carta para usarla (misma UI que en las ventanas de
> respuesta).

### `_show_ataque_prompt` — línea 570

> 2026-10-11 (a pedido del usuario): sin popup — los Aliados que pueden
> atacar brillan en tu Línea de Defensa (los Nodos espejados de
> _card_nodes, mismo card_id que manda el Anfitrión). Un clic los marca/
> desmarca como atacantes (tinte naranja, como en la pantalla del
> Anfitrión) y el botón de paso del HUD confirma. Ver on_card_clicked().

### `_show_await_multi_target_prompt` — línea 884

> =============================================================================
> CARRERA "OBJETIVO O CASTILLO" (CardInteractionModule.await_target_or_
> castillo_pick(), 2026-10-07, arquitectura.md §41) — junta cartas
> candidatas + Castillo propio/rival en un solo prompt, ya que del lado del
> Remoto no hay carrera real entre dos interacciones simultáneas de UI.
> =============================================================================

### `_show_choose_option_prompt` — línea 943

> =============================================================================
> NOMBRAR UNA CARTA (CardNameSearchDialog.open_and_wait(), 2026-10-07,
> arquitectura.md §42) — a diferencia de los otros 6 puentes, este no manda
> ninguna lista de candidatas: el Remoto ya tiene su propia CardDatabase
> cargada (mismo catálogo que el Anfitrión), así que corre el MISMO
> buscador en vivo con arte real, enteramente local a su pantalla — solo
> el resultado final viaja por red. No usa _build_overlay()/_current_
> overlay (CardNameSearchDialog ya administra su propio CanvasLayer y se
> autodestruye sola al resolverse).
> =============================================================================

### `_show_name_card_prompt` — línea 959

> =============================================================================
> BOTÓN DE PASO DEL REMOTO (2026-10-11, a pedido del usuario: "el botón de
> paso tiene que funcionar para el jugador 1 y el jugador 2") — el mismo
> botón del HUD que usa el Anfitrión. Como este cliente no corre GameManager
> propio, el texto/visibilidad los decide el prompt activo y el click (o la
> tecla P, vía PhaseFlowController._on_paso_pressed()) ejecuta _paso_action.
> =============================================================================

### `_countdown_button_text` — línea 1065

> =============================================================================
> MANO FÍSICA COMO ÚNICA FORMA DE JUGAR (2026-10-11)
> =============================================================================

### `_clear_attack_candidates` — línea 1137

> =============================================================================
> BLOQUEO EN EL TABLERO (2026-10-11, a pedido del usuario) — mismo gesto que
> el Anfitrión (CardInteractionModule._declare_blocker()): clic en tu Aliado
> brillante; si puede bloquear a un solo atacante libre se asigna directo,
> si no los atacantes posibles brillan en rojo y eliges con otro clic. Clic
> en un bloqueador ya asignado lo libera. El botón de paso confirma.
> =============================================================================

### `_clear_board_blocking` — línea 1246

> =============================================================================
> SELECCIÓN SOBRE EL TABLERO/MANO (2026-10-11, a pedido del usuario: "sigamos
> con los demás popups") — portador de Arma, objetivos de efectos y
> habilidades de respuesta se eligen con clic sobre la carta real (brillo
> celeste si es tuya, rojo si es del rival). Si algún candidato no tiene
> Nodo visible en esta pantalla (p.ej. una carta de la mano del Anfitrión),
> se cae al popup de siempre para no esconder una opción válida.
> =============================================================================

### `_clear_board_pick` — línea 1365

> =============================================================================
> SELECTOR DE ZONAS (ActionSearch._delegate_zone_pick_to_remote(), 2026-10-11)
> — el Remoto corre el mismo ZoneBrowsePicker que el Anfitrión, en su propia
> pantalla ('is_own' ya viene relativo a él), y devuelve los índices elegidos.
> =============================================================================

### `_show_zone_pick_prompt` — línea 1382

> Cartas de la mano candidatas (2026-10-12, p.ej. Miguel): los ids son los
> de la mano espejo (_hand_card_nodes). Se guarda el índice original para
> devolverle al Anfitrión la posición en SU lista.

## `scripts/entities/Card.gd`

### `(nivel de archivo)` — línea 66

> Módulos extraídos (Fase 4 de reestructuración; CardTriggerRuntime/
> CardBadges agregados 2026-09-06, "módulos gordos")

### `(nivel de archivo)` — línea 143

> Arrastrar quedó desactivado a pedido del usuario (2026-08-17): era la
> fuente de varios bugs de posicionamiento (top_level sin preservar la
> posición visual, contenedores reordenando de forma diferida, etc.).
> Jugar cartas de la mano ya funciona por doble clic (_on_card_double_
> clicked); declarar un atacante ahora funciona con un solo clic sobre el
> Aliado en el campo (ver CardInteractionModule._on_card_clicked).

### `(nivel de archivo)` — línea 167

> Quién CONTROLA la carta ahora mismo (de qué lado del tablero pelea, quién
> puede atacar/activar sus habilidades) — por defecto sigue a owner_id
> (ver su setter abajo), y solo diverge cuando un efecto te deja jugar o
> controlar una carta ajena sin volverte su dueño (2026-08-29, DAR: jugar
> una carta del rival te vuelve controlador, no dueño — p.ej. Miguel,
> "juega una carta de tu mano o de un Cementerio", donde SÍ puede ser el
> Cementerio rival). Antes este campo existía pero nada lo mantenía
> sincronizado con owner_id — toda carta normal (nunca tocada por un
> efecto así) quedaba en controller_id=0 sin importar su dueño real.

### `(nivel de archivo)` — línea 178

> 'Hace doble daño de combate al Destierro' (2026-09-04, a pedido del
> usuario — p.ej. atenea en wonderland, manuel rodriguez): el daño de
> combate que ESTA carta hace al Castillo se dobla y las cartas Botadas
> por él van al Destierro en vez del Cementerio — ver BattleManager.
> _accumulate_castle_damage(), consultado durante ASIGNACION_DANIO.

### `(nivel de archivo)` — línea 185

> 'Su daño de combate... es enviado al Destierro este turno' (2026-09-20,
> Segundo Sello — sin doblar, a diferencia de doubles_damage_to_exile de
> arriba). BattleManager._check_damage_to_exile_effect() YA consultaba este
> nombre exacto de propiedad vía card.get("damage_goes_to_exile") desde
> antes (comentario "también verificar en cartas en juego del oponente"),
> pero ninguna carta del proyecto lo declaraba ni lo asignaba nunca —
> infraestructura muerta reactivada aquí, sin tocar BattleManager.gd.

### `(nivel de archivo)` — línea 205

> Convertida en una carta (del mismo tipo u otro) SIN habilidad (2026-08-26,
> p.ej. Signo Amarillo convirtiéndose en un Oro sin habilidad). Distinto de
> "perder la habilidad" (silenciada, ver KeywordManager.is_silenced()): son
> dos efectos separados con su propio texto de protección ("no puede ser
> convertida" vs "no puede perder su habilidad"), pero el resultado visible
> es el mismo — pierde su caja de texto, conserva coste y Fuerza, y gira
> 180° (_refresh_disabled_rotation()).

### `(nivel de archivo)` — línea 217

> Datos originales de esta carta cuando su propio efecto la transformó
> reversiblemente en OTRO tipo/zona de verdad (2026-08-29, p.ej.
> Jormundgander: Aliado que se convierte en Oro al hacer daño y vuelve a
> ser Aliado si se lo paga) — {} = no aplica. Distinto de is_converted
> (que es "perdió su habilidad" sin cambiar tipo/zona, DAR otro efecto):
> aquí card_type y la zona cambian de verdad. GoldManager._mover_oro_a_
> pagado() lo revisa al pagar este Oro para saber si debe revertirlo en
> vez de moverlo a Oro Pagado normalmente.

### `_refresh_disabled_rotation` — línea 239

> Gira la carta 180° desde su centro si es del oponente en juego (Mano, Oro, Aliado, Arma, Tótem);
> si está silenciada o convertida, 180° más respecto de esa posición. Además aplica un tinte gris "sin
> habilidad" (2026-09-15, a pedido del usuario) — antes lo único que
> indicaba "silenciada/convertida" era este mismo giro de 180°, pero para
> una carta del RIVAL ese giro ya pasa SIEMPRE (así se muestra cualquier
> carta rival en juego) — silenciar/convertir una carta rival no se veía
> distinto de una carta rival normal, sin ninguna forma de saber a simple
> vista que perdió su habilidad. El tinte es independiente del giro y
> funciona para los dos lados.

### `_refresh_disabled_rotation` — línea 270

> 2026-09-23, a pedido del usuario: un Aliado sin habilidad (silenciado/
> convertido) debe seguir viéndose "apagado" (girado/teñido) SIEMPRE,
> incluso portando un Arma con habilidad propia — antes había una
> excepción aquí que lo hacía ver con habilidad de nuevo apenas
> equipaba un Arma, aunque su PROPIA habilidad siguiera bloqueada de
> verdad (is_silenced() no mira Armas para nada, ver KeywordManager).
> 2026-10-14, a pedido del usuario: "sin habilidad" gira 180° respecto
> de la posición ORIGINAL de la carta, sea propia o rival. Antes era un
> OR: una carta rival en juego ya está a 180°, así que silenciarla o
> convertirla no la giraba (solo el tinte). Ahora es XOR — propia
> 0°→180°, rival 180°→0°. En la mano no aplica (el abanico rival no se
> toca).

### `_refresh_disabled_rotation` — línea 333

> (2026-08-28, misma corrección de terminología que CardFactory.TRIGGER_PATTERNS)

### `_refresh_disabled_rotation` — línea 340

> "cuando entra en juego o ataque" (2026-08-29, p.ej. Sherlock Holmes) es
> UNA sola cláusula con dos disparadores — "cuando ataque" no aparece
> como substring literal ahí ("cuando entra en juego O ataque"), así que
> necesita su propia frase para que has_trigger("on_attack") la detecte.
> "cuando el portador ataque" (2026-09-06, bug real reportado por el
> usuario — p.ej. Garfio Pirata: 'Cuando el portador ataque, si es de
> coste 1 o más, genera un Oro o Roba una carta') — NINGUNA de las
> frases de abajo matchea 'el portador' insertado entre 'cuando' y
> 'ataque', así que _isolate_all_trigger_clauses() no cortaba ahí el
> bloque del ETB y esta oración se ejecutaba AL EQUIPARSE en vez de al
> atacar (mismo síntoma que el bug ya documentado de 2026-08-30, pero
> esta frase puntual seguía sin cubrir).
> "cuando ataca" (2026-10-14, a pedido del usuario con Zadquiel): 41
> cartas lo usan y nunca se registraba el disparador.

### `_refresh_disabled_rotation` — línea 356

> "cuando hace daño" (2026-10-12, p.ej. Sir Galahad).

### `_refresh_disabled_rotation` — línea 360

> "en tu fase final" agregado (2026-08-30, p.ej. Espada de O'Higgins) —
> antes SOLO estaban las frases genéricas de "al final del turno", que
> ninguna carta real usa; "en tu Fase Final" es la frase real del DAR
> para este disparador y no matcheaba nada.
> "en la Fase Final, si tienes" (2026-09-20, p.ej. torii) — frase NARROW
> a propósito: "en la fase final" a secas colisionaría con "en la fase
> final oponente" (Biblioteca de Caballería, on_opponent_turn_end de
> abajo), clasificando esa carta también como on_turn_end por error.

### `_refresh_disabled_rotation` — línea 369

> "en la Fase Final oponente" (2026-09-04, p.ej. Biblioteca de
> Caballería) — distinto de "en tu Fase Final" de arriba: dispara en la
> Fase Final del RIVAL, no la propia. Ver TriggerSystem.
> resolve_turn_end_triggers() para el disparo real (escanea el campo
> del jugador contrario cuando termina el turno de ESE jugador).

### `_refresh_disabled_rotation` — línea 375

> "Al comienzo del Ataque" (2026-09-04, a pedido del usuario — p.ej.
> almirante akari) — fase Ataque, distinta de "al comienzo del turno"
> (on_turn_start, ligado a Agrupación).

### `_refresh_disabled_rotation` — línea 379

> "en tu Agrupación" (2026-08-30, p.ej. Espada del Juicio: "Cuando entra
> en juego y en tu Agrupación, Destierra..."). Sin/con tilde por las
> dudas — la API a veces trae mojibake en palabras acentuadas.
> "al comienzo de tu Agrupación" (2026-09-20, p.ej. torii) — distinta de
> "en tu Agrupación" (Espada del Juicio, arriba): mismo tipo de
> disparador (DAR, inicio de la fase de Agrupación), otra frase real.

### `_refresh_disabled_rotation` — línea 386

> "Al comienzo de tu/la Vigilia" (2026-09-03, corregido a pedido del
> usuario — NO "en tu vigilia" sola: Vigilia es la ventana NORMAL de
> las habilidades activadas ("una vez por turno, puedes X"), así que
> "En tu Vigilia, X" sin más es casi siempre esa ventana, no un
> disparador. Solo "Al comienzo de tu/la Vigilia" es inequívocamente
> un disparador real (p.ej. Colmillo de Vampiro: "Al comienzo de la
> Vigilia, puedes Barajar..." — el "puedes" ahí es sobre el EFECTO
> ofrecido en ese momento, no sobre cuándo activarlo). Con solo
> "en tu vigilia" como frase, la PRIMERA habilidad de Espada de
> O'Higgins ("En tu Vigilia, una vez por turno, puedes Barajar...")
> se habría tratado como disparador automático por error, saltándose
> el "puedes"/cupo de una vez por turno. "en tu vigilia o fase final"
> se agrega aparte, acotado a esa combinación exacta (p.ej. Mariano
> Osorio) — Fase Final SÍ es siempre disparador (no es ventana de
> activadas), así que emparejada con Vigilia en la misma oración
> arrastra a Vigilia también, sin el riesgo de falso positivo de
> "en tu vigilia" sola.

### `_refresh_disabled_rotation` — línea 410

> Recorte del área de CLICK (no del área visual — ver _has_point() más
> abajo), en X local, cuando esta carta está tapada por la derecha por
> otra carta superpuesta de la MISMA fila (2026-09-03, bug reportado:
> en la Reserva de Oro, con muchas cartas la separación del HBoxContainer
> se vuelve negativa (GoldManager._update_container_gold_spacing(), hasta
> -125px) para que quepan todas, así que cartas consecutivas se superponen
> bastante — cada Card sigue siendo un Control de 150×210 completo aunque
> visualmente la carta siguiente (añadida después, dibujada encima) tape
> buena parte de su derecha. Sin este recorte, esa porción tapada seguía
> siendo clicable en la carta de ABAJO — un click ahí (que visualmente
> apunta a la carta de ARRIBA) se lo comía la de abajo en silencio, y
> viceversa en las esquinas/bordes donde la superposición es parcial.
> -1.0 = sin recorte (comportamiento normal, rect completo).

### `_ready` — línea 520

> Configurar mouse
> NO conectar mouse_entered/mouse_exited nativos (2026-08-28, arregla el
> salto infinito reportado por el usuario): el rect que Godot usa para
> esas señales no tiene en cuenta 'scale', así que quedaban desfasadas
> cerca de un borde apenas el hover escalaba la carta y competían con
> CardInteraction.process() (que sí calcula bien la posición con
> get_local_mouse_position()) — las dos fuentes de hover se peleaban y
> producían el loop entra/sale. process() es ahora la única fuente de
> verdad para is_hovered.

### `load_from_data` — línea 672

> Una copia recién creada de un nombre ya bloqueado por
> KeywordManager.lock_ability_by_name() (2026-08-29, p.ej. Alicia en
> Wonderland) debe nacer ya girada 180° — sin esto, una carta robada
> DESPUÉS de que el nombre quedó bloqueado no mostraba el indicador
> hasta que algo más disparara _refresh_disabled_rotation().

### `_on_strength_visual_update_required` — línea 726

> Refresca el badge correspondiente cuando ContinuousEffectManager
> avisa que un modificador cambió el valor calculado de ESTA carta —
> conectado en _ready() (2026-08-30: la función existía referenciada aquí
> en _exit_tree() para desconectarse, pero nunca estuvo declarada ni
> conectada — 'Identifier not declared', corrupción histórica ajena a
> esta sesión).

### `_exit_tree` — línea 749

> Si esta carta era FUENTE de algún modificador continuo (p.ej. un Arma
> dándole Fuerza a su portador), se limpia cuando REALMENTE sale de
> juego — is_queued_for_deletion() es la guarda clave (2026-08-22):
> _exit_tree() también se dispara en un reparenting normal y temporal
> (remove_child + add_child), como cuando un Aliado ataca y se mueve a
> Línea de Ataque — el Arma equipada es su HIJA, así que también salía
> y volvía a entrar al árbol, y sin esta guarda el bono de Fuerza se
> borraba justo al declarar el ataque (el combate usaba la Fuerza base,
> aunque la carta siguiera mostrando el badge ya calculado en verde).

### `_exit_tree` — línea 760

> Invalidar el cache SIEMPRE que una carta sale de juego de verdad, no
> solo cuando ELLA MISMA era fuente de un modificador (2026-09-02, bug
> reportado por el usuario: Manuel Bulnes — 'Gana 1 de Fuerza por cada
> Arma que controles', un valor DINÁMICO recalculado con un Callable —
> seguía mostrando el bono aunque ya no quedara ningún Arma en juego).
> remove_modifiers_from_source() de arriba solo invalida el cache si
> ESTA carta tenía modificadores propios registrados; un Arma sin
> habilidad propia (sin 'El portador gana...') no tiene ninguno, así
> que destruirla nunca disparaba la invalidación — el valor de Manuel
> Bulnes quedaba pegado al último cálculo, sin importar cuántas Armas
> quedaran de verdad en el tablero.

### `_exit_tree` — línea 773

> Misma idea para modificadores de COSTE registrados por esta carta
> mientras estuvo en juego (p.ej. el impuesto de Bernardo O'Higgins a
> Talismanes/Tótems, 2026-08-26) — PaymentManager.cost_modifiers no se
> limpiaba solo al salir de juego, solo al empezar un turno nuevo.

### `select` — línea 802

> Selecciona la carta — solo el borde, sin escala (2026-08-28, a pedido
> del usuario: hacía un 'pop' a Vector2.ONE * card_scale_selected que
> ignoraba base_scale — se veía mal en cartas en juego, sobre todo en
> Tótems (base_scale 0.8) que saltaban a tamaño completo.

### `set_activatable` — línea 846

> 2026-10-12, bug real reportado por el usuario ("Nonexistent function
> 'set_activatable' in base 'Nil'" al buscar con Tempilcahue): el visor
> del selector de zonas crea la carta y le pide el brillo ANTES de
> agregarla a la escena — _badges recién existe tras _ready(). Se aplica
> en cuanto la carta esté lista.

### `has_keyword` — línea 886

> Verifica si la carta tiene una keyword — incluye las que le transmiten
> sus Armas equipadas (2026-08-24, DAR): un Arma con Furia/Imbloqueable/
> etc. se la da a su portador mientras esté equipada. Se lee
> weapon.card_keywords directo (no weapon.has_keyword()) porque un Arma
> nunca porta otras Armas — no hace falta ni tiene sentido recursar.
>
> También consulta ContinuousEffectManager (2026-09-02, bug reportado por
> el usuario con Espíritu Kotaix: 'Tus Aliados ganan... Furia' registraba
> el modificador de keyword bien, pero esta función — la que de verdad
> usa la declaración de ataque, CardInteractionModule.gd — solo miraba
> card_keywords/equipped_weapons, sin ningún cruce con las keywords
> OTORGADAS por auras de otras cartas. Hay un tercer sistema paralelo
> (KeywordManager._temporary_keywords) que tampoco se cruza con ninguno
> de los otros dos — quedó fuera de este fix a propósito, alcance
> acotado al caso reportado.

### `set_zone` — línea 940

> La insignia de coste depende de la zona (CardBadges.refresh_cost_badge(),
> 2026-10-12): al salir de la mano/Cementerio deja de mostrar descuentos e
> impuestos de jugarla.

## `scripts/entities/CardAnimations.gd`

### `play_enter_animation` — línea 70

> Animar hacia base_scale, NO Vector2.ONE fijo (2026-08-29): un Arma
> recién equipada (GoldManager._equip_weapon(), escala 0.45 de insignia
> en la esquina del Aliado) llama a esta misma animación — con el target
> fijo en 1.0 terminaba agrandada a tamaño de mano completa apenas
> entraba en juego, y encima el hover posterior la recalculaba con un
> base_scale que nunca se había actualizado a 0.45, dando la sensación de
> que el Arma 'desaparecía y solo volvía a aparecer al pasar el mouse'.

## `scripts/entities/CardBadges.gd`

### `(nivel de archivo)` — línea 3

> CardBadges — Badges visuales de una carta: el brillo celeste de "habilidad
> activable ahora" y las Placas Heráldicas de Fuerza/Coste efectivos
> (verde=buff/descuento, rojo=debuff/recargo). Opera sobre el nodo Card via
> _card. Card.gd reenvía como wrappers públicos los métodos que otros
> sistemas llaman directamente sobre la carta (refresh_strength_badge,
> refresh_cost_badge, set_activatable — llamados desde muchos managers cada
> vez que un modificador continuo puede haber cambiado el valor mostrado).
> Extraído de Card.gd (2026-09-06, "módulos gordos" — mismo corte que ya
> separó CardInteraction.gd/CardAnimations.gd, Fase 4 de reestructuración).

### `(nivel de archivo)` — línea 16

> Colores del brillo de set_activatable() (2026-09-15, a pedido del usuario):
> antes era SIEMPRE dorado sin importar el motivo — ahora distingue "por qué
> brilla" con 3 colores fijos, usados desde CardInteractionModule.gd/
> TriggerSystem.gd: DORADO = "disparadas" (habilidad activable disponible,
> u orden de triggers a elegir — CardInspectionLayer.refresh_activatable_
> glows()/TriggerSystem._prompt_trigger_order()); CELESTE = objetivo válido
> PROPIO de una selección en curso; ROJO = objetivo válido RIVAL. Ver
> CardInteractionModule._glow_valid_targets()/await_multi_target().

### `(nivel de archivo)` — línea 33

> Motivos independientes de brillo activo (StringName -> Color), 2026-09-30
> fix de revisión: antes un solo is_activatable/color representaba a la vez
> "habilidad activable" (CardInspectionLayer) Y "objetivo de una selección
> en curso" (CardInteractionModule/GoldManager) — apagar uno apagaba el
> otro aunque siguiera vigente. Ver set_activatable() más abajo.

### `refresh_cost_badge` — línea 224

> Recalcula y muestra el Coste efectivo AHORA — llamar después de cualquier acción que pueda cambiarlo.
>
> Según la zona (2026-10-12, a pedido del usuario: "la reducción o aumento
> de coste debe mostrarse solo desde la mano o el Cementerio; en juego no,
> a menos que una carta en juego le cambie el coste"):
> - Mano / Cementerio: lo que costaría JUGARLA ahora (PaymentManager.
> calcular_coste_real(): descuentos, 'cuesta un Oro adicional', etc.).
> - En juego: solo el coste modificado por efectos sobre la carta en juego
> (ContinuousEffectManager.get_modified_cost(), p.ej. Cuerno de Titán
> 'aumentar o disminuir el coste de hasta una carta en juego'); los
> impuestos y descuentos para jugar ya no aplican.
> - Resto (Castillo, Destierro): sin insignia.

### `refresh_cost_badge` — línea 238

> Cementerio: solo si esa carta se puede jugar desde ahí (Exhumar, etc.)
> (2026-10-17, a pedido del usuario: la reducción/aumento de coste se
> muestra solo en cartas que se van a jugar).
> Los Oros no se juegan ni tienen coste: nunca muestran reducción (2026-10-17,
> bug real: Crono Diamante en la mano mostraba -1).

### `set_activatable` — línea 293

> Muestra u oculta el brillo que indica 'esto es relevante ahora mismo'
> — dorado por defecto ('tienes una habilidad activable disponible ahora
> mismo', o el orden de triggers a elegir — distinto del brillo amarillo
> desde CardInspectionLayer.refresh_activatable_glows()).
> 'glow_color' (2026-09-15, a pedido del usuario): CardInteractionModule.
> _glow_valid_targets()/await_multi_target() lo llaman con GLOW_COLOR_
> CELESTE/GLOW_COLOR_RED para distinguir objetivo propio de objetivo
> rival en una selección — el color se re-aplica en cada llamado con
> value=true, incluso si ya estaba prendida (p.ej. una carta que YA
> brillaba dorada por tener una habilidad activable y ahora además es
> objetivo rival de otra selección concurrente pasa a rojo).
>
> 'reason' (2026-09-30, fix de revisión — hallazgo real: un solo bool
> 'is_activatable' representaba a la vez tres motivos independientes
> ["habilidad activable" de CardInspectionLayer, "objetivo propio/rival de
> una selección en curso" de CardInteractionModule, "elegí qué Oro gastar"
> de GoldManager] — apagar UN motivo (value=false) apagaba el brillo
> entero aunque otro motivo siguiera vigente: una carta que brillaba
> dorada por tener una habilidad activable, y que de paso se vuelve
> objetivo válido de una selección en curso, perdía su brillo dorado
> apenas esa selección terminaba, aunque la habilidad siguiera activable.
> Ahora cada motivo se registra por separado en _activatable_reasons y el
> brillo solo se apaga del todo cuando ninguno queda. Los llamadores que no
> son CardInspectionLayer DEBEN pasar su propio 'reason' explícito (p.ej.
> &"target_select") — el default &"ability" es el motivo original de
> CardInspectionLayer, para no tener que tocar sus llamados existentes.

## `scripts/entities/CardImageLoader.gd`

### `(nivel de archivo)` — línea 3

> CardImageLoader — Carga de imagen/placeholder de una carta: aplica los
> datos pendientes tras load_from_data(), muestra el dorso de carga y el
> placeholder legible (nombre/coste) mientras el arte frontal no está
> disponible, y gestiona la descarga async vía CardDatabase.card_image_loaded
> (cache hit inmediato o conexión de señal + callback). Opera sobre el nodo
> Card via _card. Ninguna de estas funciones tiene llamadores fuera de
> Card.gd (verificado por grep en todo scripts/), así que Card.gd NO expone
> wrappers públicos para ellas — solo las llama internamente vía
> _image_loader.X() en los 3 puntos donde antes se llamaban directo
> (esta_oculta.set(), actualizar_aspecto(), _exit_tree()).
> Extraído de Card.gd (2026-09-06, "módulos gordos" — mismo corte que ya
> separó CardInteraction.gd/CardAnimations.gd/CardTriggerRuntime.gd/
> CardBadges.gd, Fase 4 de reestructuración).

## `scripts/entities/CardInteraction.gd`

### `process` — línea 24

> Red de seguridad contra hover perdido (2026-08-22): mouse_entered/
> mouse_exited de Godot a veces no se disparan para estas cartas —
> reparentado entre contenedores al declarar ataque/agrupar, reflow del
> HBoxContainer de la mano al jugar/robar cartas, o movimiento rápido del
> mouse — dejando una carta con la que 'no se puede targetear ni hacer
> zoom' aunque el mouse esté encima. Se corrige el estado cada frame
> comparando contra la posición real del mouse.

### `process` — línea 33

> get_global_rect() NO tiene en cuenta la escala del nodo (limitación
> conocida de Godot) — con pivot_offset != (0,0), escalar en hover corre
> la posición global real para mantener el pivote fijo, pero este rect
> sigue siendo el de antes de escalar. Cerca de un borde (2026-08-26,
> reportado por el usuario: pasaba sobre todo abajo de la carta), ese
> desfase hacía que el rect "viejo" quedara justo afuera del mouse →
> se disparaba mouse_exited → la escala volvía a 1 → el rect volvía a
> su lugar → mouse_entered de nuevo → loop infinito de "salto".
> get_local_mouse_position() sí invierte la transform completa (posición,
> escala, pivote), así que no tiene este problema. _has_point() además respeta
> _click_clip_right cuando las cartas están solapadas (en mano o en escalera de oros).

### `on_gui_input` — línea 141

> 2026-09-14, diagnóstico temporal a pedido del usuario ("no puedo
> hacer objetivo a los Aliados oponentes, mis Aliados sí") — mismo
> criterio que el DIAG de right-click de arriba (§10.7): imprime ANTES
> del corte por can_interact para distinguir "el click nunca llegó aquí"
> de "llegó pero can_interact era false" o "llegó, pasó, pero el
> filtro de la habilidad lo rechazó" (ese último caso ya avisa con su
> propio mensaje en CardInteractionModule._resolve_target_selection()).

### `on_gui_input` — línea 165

> Godot decide 'double_click' por tiempo+posición GLOBAL del
> mouse, no por nodo (2026-08-22): si el jugador acaba de
> doble-clickear OTRA carta (p.ej. jugar un Arma) y enseguida
> hace un solo click en ÉSTA (p.ej. el Aliado pedido como
> portador), Godot puede marcar ese primer press de ESTA
> carta como double_click=true directamente, sin pasar nunca
> por un evento con double_click=false — quien solo escucha
> card_clicked (selección de objetivo) nunca se enteraba.
> Se emite card_clicked también para que ese listener reciba
> su evento igual.
> PERO (2026-08-23): en un doble-click REAL sobre ESTA MISMA carta, el
> primer press (double_click=false) ya emitio card_clicked -- emitirlo
> de nuevo aquí duplica el evento y dispara handlers como
> _declare_attacker() dos veces en paralelo (bug real: un Aliado
> atacando "teletransportado" al bando rival por la carrera entre
> ambas llamadas). Solo se emite el eco si NO hubo un press simple
> reciente de esta misma carta -- cubre el caso huerfano sin
> duplicar el gesto genuino.

### `can_declare_attack_drag` — línea 213

> Verifica si un Aliado en el campo puede arrastrarse para declarar
> ataque.
>
> DAR (2026-08-28, reemplaza el diseño de 2026-08-23 a pedido del
> usuario): ya no existe el atajo Vigilia→Ataque por declarar un atacante
> directo — ahora hay un botón "Atacar" explícito que termina Vigilia y
> empieza la Batalla Mitológica, y declarar atacantes (con o sin Furia)
> solo es posible una vez que la fase YA es Ataque. Furia deja de ser un
> atajo de fase; sigue siendo el keyword que evita la enfermedad de
> invocación, validado por TurnManager.can_attack().

### `return_to_hand` — línea 308

> Rotación de destino real (2026-08-30): _card.target_rotation es siempre
> 0.0 (la inclinación de descanso en la mano), pero si la carta está
> Convertida o Silenciada debe seguir mostrando el giro de 180° — sin esto,
> cualquier llamada a return_to_hand() (p.ej. el 'soltar' genérico que usa
> _declare_attacker() al declarar un atacante) pisaba ese giro y la carta
> 'se enderezaba' sola aunque siguiera convertida/silenciada."""

## `scripts/entities/CardTriggerRuntime.gd`

### `(nivel de archivo)` — línea 3

> CardTriggerRuntime — Sistema de triggers de una carta (DAR 7.2, 7.3, 7.4):
> parseo de triggers desde el texto de habilidad, verificación de
> condiciones, ejecución de efectos vía Callable, y los hooks de
> entrar/salir de juego. Opera sobre el nodo Card via _card. Card.gd
> reenvía como wrappers públicos los métodos que otros sistemas llaman
> directamente sobre la carta (parse_triggers_from_ability, is_in_play,
> has_trigger, _trigger_conditions_met, _on_trigger_event, on_entered_play,
> on_left_play — TriggerSystem/ActionModule/ConvertAndMiscResolver los
> llaman así en varios puntos).
> Extraído de Card.gd (2026-09-06, "módulos gordos" — mismo corte que ya
> separó CardInteraction.gd/CardAnimations.gd, Fase 4 de reestructuración).
> Nota: Card.TRIGGER_KEYWORDS queda en Card.gd (no aquí) porque se accede de
> forma ESTÁTICA vía la clase (Card.TRIGGER_KEYWORDS[...] en
> TriggerResolution.gd) — moverlo rompería ese acceso estático.

### `parse_triggers_from_ability` — línea 61

> Nota (2026-08-27): los Talismanes NO se resuelven por aquí — no
> "disparan" nada (DAR Sección 7.4 es para habilidades disparadas de
> permanentes). Su texto se resuelve directo al jugarlos, ver
> TriggerSystem.resolve_talisman() / GoldManager._trigger_enter_play().

### `_on_trigger_event` — línea 156

> Sin handler específico registrado (2026-08-22): NO usar
> _resolve_default_effect() aquí — es un escaneo de palabras clave sobre
> el texto COMPLETO de la carta (sin aislar por oración), así que una
> carta con VARIAS habilidades en el mismo bloque (p.ej. Tyet: 'Cuando
> entra en juego, busca un Arma o un Oro...' + más adelante 'Robar dos
> cartas' de una habilidad de Oro completamente distinta) disparaba la
> frase equivocada — Tyet buscaba nada y robaba una carta en su lugar.
> TriggerSystem._execute_trigger_effect() ya tiene el parser bueno
> (aísla la oración correcta, reconoce SEARCH/DESTROY/BUFF/etc., no solo
> 'roba') y lo corre él mismo cuando este resultado no aplicó nada.

### `on_left_play` — línea 191

> 2026-09-23, a pedido del usuario: este mensaje solo duplicaba lo que ya
> informa EffectController ("X fue destruida"/"X resuelve su efecto y va
> al Cementerio") — 3 líneas distintas para el mismo evento de salida de
> juego. Se mantiene gateado para depuración profunda.

## `scripts/menu/DeckManager.gd`

### `_fetch_decks` — línea 41

> Obtiene mazos públicos reales de ShadowForge (2026-09-22, bug real
> reportado por el usuario: 'DeckManager fetching from localhost:3000...
> Request failed with result: 2' — esta pantalla nunca se actualizó cuando
> se construyó la integración real con ShadowForge, ExternalApiClient.gd
> (ver arquitectura.md §13); seguía apuntando a la API vieja muerta.
> Mismo endpoint confirmado real que usa DeckSelector.gd:
> GET /api/decks/public/ → {results, count}.

### `_create_deck_card` — línea 221

> Curva de coste (2026-08-28, a pedido del usuario — mostrar el mazo más
> visual): mini histograma de cuántas cartas hay por coste, para juzgar
> de un vistazo si el mazo es agresivo (curva baja) o de control (alta).

### `_build_image_url` — línea 456

> Devuelve la URL de la imagen tal cual. 2026-09-22: 'image_url' de la
> API real de ShadowForge ya viene como URL absoluta (Cloudinary, ver
> arquitectura.md §13) — se sacó el prefijo de CDN relativo que usaba la
> API vieja muerta (CDN_BASE_URL, 'grimorio-cards.b-cdn.net', ya no
> aplica a esta fuente de datos).

### `_on_deck_selected` — línea 465

> Cuando el usuario selecciona un mazo. 2026-09-22, bug real corregido
> junto con _fetch_decks(): los mazos públicos reales de ShadowForge no
> tienen 'slug' (eso era de la API vieja muerta) — tienen 'id' numérico, y
> la lista solo trae datos resumidos, sin las cartas ('entries'). Hay que
> bajarlas aparte antes de poder jugar con este mazo, mismo camino real ya
> usado por DeckSelector.gd (ExternalApiClient.fetch_public_deck_entries()).

## `scripts/menu/MainMenu.gd`

### `_ready` — línea 19

> Carga de la partida en segundo plano (2026-10-17, a pedido del usuario:
> "Jugar contra el bot" tardaba 5-7 s — load() de Main.tscn son ~4,5 s,
> casi todo compilar los scripts). Mientras se mira el menú ya se va
> cargando; al elegir, está lista.

### `_ready` — línea 32

> 2026-10-12, bug real reportado por el usuario ("intenté jugar contra el
> bot y no me cargó el mazo"): al salir de una partida online la sala de
> red quedaba abierta (NetworkClient.room_code seguía seteado), así que
> "Jugar" contra el bot entraba al flujo online y esperaba para siempre
> el mazo del otro jugador. Volver al menú = no hay partida online en
> curso; OnlineConnect va directo a Main sin pasar por aquí.

### `_ready` — línea 47

> 2026-09-22: el botón muestra si ya hay una sesión de ShadowForge

### `_on_shadowforge_pressed` — línea 309

> Abre la pantalla de login real de ShadowForge (2026-09-22, a pedido
> del usuario: conectar tu cuenta para ver tus mazos privados en el
> selector, en vez de editar un archivo a mano).

## `scripts/ui/dice/DiceDuel3D.gd`

### `(nivel de archivo)` — línea 7

> Emitida apenas se decide el resultado (antes de la animación de tirada) —
> 2026-09-20, multiplayer: el Anfitrión escucha esto para mandarle el
> resultado real al Remoto por red, así los dos ven la MISMA tirada en vez
> de cada lado tirando la suya propia por separado.

### `(nivel de archivo)` — línea 13

> Resultado forzado (2026-09-20, multiplayer): si ambos son > 0, se usan
> estos valores en vez de tirar al azar — el Remoto reproduce aquí la MISMA
> tirada que el Anfitrión ya resolvió, en vez de tirar la suya propia
> (antes cada pantalla mostraba 2 dados random sin relación con la otra).
> Dejar en -1 (default) para el camino de siempre (partida local contra el
> bot: cada lado tira de verdad).

### `(nivel de archivo)` — línea 22

> Textos del banner "quién parte" (2026-09-20, multiplayer): "¡TÚ PARTES!"
> solo tiene sentido en la pantalla de quien de verdad controla al jugador 0
> (el Anfitrión) — la vista espejo del Remoto necesita su propio texto,
> ver RemoteMirrorController._show_dice_roll_mirror().

### `start_roll` — línea 381

> 2026-09-20: restaurado el sorteo real (el "DEBUG TEMPORAL" de 2026-09-11
> —resultado fijo 20/1— nunca se sacó pese a la nota de "sacar antes de
> jugar en serio", así que TODO sorteo hasta hoy era 100% determinístico).
> forced_result1/2 (multiplayer, ver docstring arriba) tienen prioridad
> sobre el azar cuando vienen seteados desde afuera.

## `scripts/ui/hand/DynamicHand.gd`

### `_on_card_hovered` — línea 270

> Al hacer hover: la carta no se mueve ni rota (a pedido del usuario),
> solo se trae al frente (z_index = 100) y se libera el recorte para interacción completa.

## `scripts/ui/hand/MulliganController.gd`

### `(nivel de archivo)` — línea 10

> Mulligan del Remoto corriendo en paralelo al propio (2026-10-12, ver
> start_mulligan_phase()).

### `start_mulligan_phase` — línea 39

> 2026-10-12, a pedido del usuario: "los 2 jugadores tienen que poder ver
> su mano al mismo tiempo" — antes el Remoto recién recibía su mulligan
> cuando el Anfitrión terminaba el suyo. Ahora arranca en paralelo (sin
> await) y _end_mulligan_phase() espera a que ambos hayan elegido.

### `_end_mulligan_phase` — línea 117

> Multiplayer remoto (2026-09-11, Fase B): si el jugador 1 es un Remoto
> conectado, corre un mulligan REAL (preguntando mantener/redibujar por
> red) en vez de robarle la mano directo sin ninguna decisión — que es
> lo único que existía hasta ahora para el "oponente".

## `scripts/ui/hand/OpponentFan.gd`

### `(nivel de archivo)` — línea 9

> 2026-10-08 (ver arquitectura.md §45): GameStateBroadcaster se cuelga de
> estas dos para transmitirle al Remoto conectado los cambios reales de SU
> PROPIA mano (nunca la del Anfitrión — fuera de alcance, fog of war real)
> — este Control es el único punto por donde pasa CUALQUIER cambio a la
> mano del jugador 1 en todo el proyecto (decenas de llamadores, ningún
> otro hook posible). card_removed se emite ANTES de queue_free() en
> remove_card(destroy=true), así que el Node sigue siendo válido cuando
> llega al listener.

### `(nivel de archivo)` — línea 27

> 2026-10-07: pública (no "_cards") a propósito — mismo nombre que
> DynamicHand.cards (la mano del Anfitrión), para que el patrón repetido en
> todo el proyecto `hand_container = main.player_hand if owner_id == 0 else
> main._opponent_fan` pueda seguir leyendo/escribiendo `hand_container.cards`
> sin importar cuál de las dos sea — antes era `_cards` (privada) y ese
> acceso crudo fallaba en tiempo de ejecución para cualquier carta del
> Remoto (ver arquitectura.md §34).

## `scripts/ui/hud/CardInteractionModule.gd`

### `(nivel de archivo)` — línea 14

> Traba de reentrada por carta para _declare_attacker() (2026-08-23):
> la función es async con varios await ANTES de llegar a
> GameManager.attackers.append() — un segundo click (p.ej. el eco de
> card_double_clicked sobre un Aliado ya en juego) podía entrar de nuevo
> mientras el primero seguía en vuelo, ganándole la carrera a
> GameManager.declare_attacker() y quedando rechazado con 'no puede
> atacar todavía' aunque el primero sí se hubiera declarado bien.

### `(nivel de archivo)` — línea 33

> Si false, ESC no cancela la selección en curso (2026-09-13, a pedido del
> usuario — ver §10.29: una selección MANDATORIA, p.ej. "Descarta N
> cartas" sin "puedes", no debe poder esquivarse con ESC como si fuera un
> costo opcional). Default true preserva el comportamiento de siempre.

### `(nivel de archivo)` — línea 38

> "Seleccionar todo" para await_multi_target() (2026-09-13, Abrazo de Maipú)
> — ver request_select_all() y el docstring de await_multi_target().

### `(nivel de archivo)` — línea 47

> Cartas a las que start_target_selection() les forzó can_interact=true
> (2026-09-14, bug real reportado por el usuario: eligiendo objetivo para
> Capitán O'Brien —'Convertir un Oro o una carta de coste 2 o menos', DAR
> Sección 8, objetivo propio o enemigo— el click izquierdo sobre el Aliado
> RIVAL no hacía absolutamente nada, ni siquiera el mensaje de "objetivo no
> válido"; tuvo que targetear su propio Aliado como única forma de
> continuar). Causa real: Card.on_gui_input() corta el click IZQUIERDO por
> completo si can_interact es false (línea "Otras interacciones requieren
> can_interact") — el evento nunca llega a _on_card_clicked(), así que ni
> el filtro ni el mensaje de error se ejecutan nunca. Las cartas PROPIAS
> quedan can_interact=true apenas terminan de entrar en juego, pero nada
> garantizaba lo mismo para las del RIVAL en todo momento (a diferencia de
> los pickers de mano/Cementerio, que sí lo fuerzan explícitamente al
> construir sus nodos temporales — ver ZoneViewerModule/HandCementerio
> AbilityHandler/SearchAbilityHandler_JV). Se guarda aquí qué cartas se
> forzaron para poder devolverlas a su estado real al cerrar la selección
> (nunca se toca una carta que YA estaba en true).

### `(nivel de archivo)` — línea 65

> Cartas con el brillo celeste "objetivo válido" prendido por una selección
> de UN solo objetivo (2026-09-15, a pedido del usuario: await_target() no
> tenía ningún indicador visual de candidatos — solo await_multi_target()
> lo tenía — así que no había forma de distinguir a simple vista "no hay
> ningún objetivo rival válido" de "el bug de targeting volvió"). Ver
> _glow_valid_targets()/_unglow_target_cards().

### `(nivel de archivo)` — línea 72

> Puente para selecciones de objetivo cuyos candidatos del Cementerio NO
> viven en ningún contenedor real del tablero (2026-09-25, bug real
> reportado por el usuario: "con lobo sagrado no me permite jugar armas
> del cementerio" — el jugador clickeaba el visor de Cementerio de
> SIEMPRE, que no sabía nada de la selección pendiente y probaba Exhumar
> en su lugar). Nodos temporales tipo Lobo Sagrado (WeaponSearchShuffle
> Executor._execute_play_weapon_discount_draw()) se registran aquí antes
> de abrir la selección — ZoneViewerModule._on_exhumar_card_clicked()
> los consulta ANTES de intentar Exhumar, y si el Dictionary clickeado
> coincide con uno de estos Nodos (misma referencia de card_data),
> resuelve la selección real en vez de la acción de Exhumar.

### `_glow_color_for_owner` — línea 138

> Celeste para tus propias cartas, rojo para las del rival (2026-09-15,
> a pedido del usuario: antes TODO objetivo válido brillaba dorado sin
> distinguir de quién es — ahora el color mismo dice 'tuya' o 'rival' de
> un vistazo, sin tener que leer el owner_id).

### `_glow_valid_targets` — línea 148

> Prende el brillo 'objetivo válido' (CardBadges.set_activatable(), el
> mismo indicador que ya usa await_multi_target()) en toda carta
> candidata real de una selección de UN solo objetivo (2026-09-15, a
> pedido del usuario: sin esto no había forma VISUAL de distinguir 'no hay
> ningún objetivo rival válido ahora mismo' de 'el bug de targeting
> volvió' — await_target() nunca mostraba ningún indicador, a diferencia
> de await_multi_target()). Celeste/rojo según dueño — ver _glow_color_
> for_owner(). A diferencia de _force_board_interactable() (que fuerza
> can_interact de más a propósito, sin mirar el filtro), aquí SÍ se evalúa
> el filtro real — es puramente visual, no cambia qué click es válido.
> Barre las mismas 10 zonas de tablero que _force_board_interactable()
> más mano/abanico rival, ya que await_target() también se usa para
> elegir cartas de la mano (p.ej. Golpe Solar).

### `start_target_selection` — línea 203

> Activa el modo de selección de objetivo.
> filter: Callable(card) -> bool — decide si esa carta es un objetivo legal.
> on_selected: Callable(card) — se llama con la carta elegida al resolver.
> cancellable: false para selecciones MANDATORIAS (ver _selection_
> cancellable arriba) — ESC no hace nada, el jugador tiene que clickear
> un objetivo válido si es que hay alguno disponible.
> 2026-09-14, bug real reportado por el usuario (log en vivo: 'Elige un
> Oro o una carta de coste 2 o menos para Convertir' seguido, ~200ms
> después, de 'Jugador 1 pasa prioridad' → 'Ambos pasaron' →
> awaiting_response atascado en true para siempre): PhaseFlowController.
> _human_pass_after() auto-pasa la prioridad del humano solo mirando
> PriorityManager.suppress_human_autopass — nunca sabía que había una
> selección de objetivo real pendiente, así que la auto-pasaba de
> debajo justo cuando la ventana de prioridad (Paso D del propio
> trigger) coincidía en el tiempo con este await_target(). El fix en
> PhaseFlowController._on_paso_pressed() (mismo día) bloquea el CLICK
> manual del botón ¿Paso?, pero este auto-pase por timer es un camino
> totalmente aparte que no pasa por ahí. Se reusa el mismo flag que ya
> usa ResponseWindowHandler._offer_signo_amarillo_for_step_d() para su
> propio diálogo reactivo — mismo criterio, un caso más de 'hay una
> decisión real esperando, no auto-pases'.

### `await_target` — línea 234

> Envoltorio de start_target_selection() que espera la respuesta —
> extraído (2026-08-30) del mismo bloque de 8 líneas que se repetía
> copiado en _select_ally_target()/_select_convert_target()
> (TargetedEffectExecutor.gd), la elección de portador de Tyet/Aho
> (CardManager.gd) y GoldManager._select_weapon_wielder(). Dictionary de
> estado a propósito, no 'var chosen'/'var done' sueltas — mismo motivo
> de siempre (los lambdas de GDScript capturan variables locales por
> VALOR, ver comentarios de esta clase). Devuelve la carta elegida, o
> null si se canceló (ESC) o no había forma de abrir la selección.
>
> 'chooser_id' (2026-09-30, Fase 3 del plan de paridad remota, cuarto
> sistema — ver docs/plans/2026-09-20-remote-multiplayer-parity.md): si
> quien elige es el jugador 1 y hay un Remoto real conectado, se delega
> por red en vez de activar el modo de selección local (que de otro modo
> esperaría un click en la pantalla del Anfitrión).

### `await_target` — línea 259

> 2026-09-15, a pedido del usuario: brillo celeste en cada candidato real
> (propio o rival) — ver _glow_valid_targets(). Solo aquí, NO dentro de
> start_target_selection() en sí, porque await_multi_target() también
> usa start_target_selection() puertas adentro con su propio manejo de
> brillo por lock_group_key/dynamic_filter — duplicarlo ahí pisaría esa
> lógica más fina.

### `await_multi_target` — línea 272

> Selección de 0 a 'max_count' objetivos (-1 = sin tope) clickeando
> directo sobre las cartas reales, en vez de un modal de lista — extraído
> (2026-09-13, a pedido del usuario) del mismo mecanismo que ya usaba
> GoldManager._choose_physical_gold_to_spend() para elegir qué Oro físico
> gastar (brillo celeste de "activable" + await_target() repetido).
> 'candidates' puede mezclar cartas de VARIAS zonas a la vez (mano,
> Cementerio, en juego) — así el jugador ve y elige directo, sin que el
> juego le pregunte antes 'desde dónde' con un modal separado; DÓNDE está
> cada carta ya se ve con solo mirar la mesa/mano/Cementerio.
> 'lock_group_key' (opcional): Callable(Node) -> Variant — si se pasa,
> tras el PRIMER pick el resto de la selección queda restringida a
> candidatos cuyo key coincida con el del primero (p.ej. Hanta el
> Samurai: 'hasta N cartas de UN Cementerio' — un solo Cementerio, no un
> pool combinado — key = owner_id del candidato).
> 'dynamic_filter' (opcional): Callable(chosen: Array, candidate: Node) ->
> bool — se re-evalúa en CADA click con el 'chosen' acumulado hasta ese
> momento; false excluye al candidato de la vuelta siguiente. Útil para
> presupuestos que se consumen con cada pick (p.ej. Tempilcahue: 'Baraja
> cartas cuyos costes sumen hasta 4' — el filtro rechaza cualquier carta
> que haría superar la suma con lo ya elegido).
> ESC en cualquier punto TERMINA la selección con lo ya elegido hasta
> ahí (no cancela todo) — mismo criterio ya usado en otros flujos
> 'Baraja hasta una carta... ESC para no barajar ninguna'.
> 'Seleccionar todo' (2026-09-13, a pedido del usuario: Abrazo de Maipú,
> 'Baraja CUALQUIER CANTIDAD de cartas de tu Cementerio y Destierro' —
> con muchas cartas disponibles, clickear una por una es tedioso): un
> botón de UI puede llamar a request_select_all() en cualquier momento
> mientras esta función espera un click; en el próximo frame, todo lo
> que quede en 'remaining' (respetando el lock/dynamic_filter vigentes)
> se toma de una sola vez y la selección termina ahí.
> 'glow_color_override' (2026-09-15, a pedido del usuario): por defecto el
> brillo es celeste/rojo según dueño (ver _glow_color_for_owner()) — pasar
> un Color aquí (p.ej. CardBadges.GLOW_COLOR_GOLD) lo fuerza igual para
> TODOS los candidatos, para usos que no son "elegir un objetivo" sino
> otra cosa (p.ej. TriggerSystem._prompt_trigger_order(): elegir el ORDEN
> de resolución entre tus propios triggers ya disparados, no un objetivo
> propio/rival).

### `await_multi_target` — línea 312

> 2026-09-30, Fase 3 del plan de paridad remota, cuarto sistema — mismo
> criterio que await_target(). 2026-10-08: lock_group_key/dynamic_filter
> ya se le pasan a _delegate_multi_target_to_remote(), que los enforcea
> al recibir la respuesta completa (ver su propio comentario) en vez de
> en vivo por click — suficiente para que Tempilcahue/Ngenechén/asedio
> naval se puedan desbloquear de verdad (ver arquitectura.md §43).

### `await_multi_target` — línea 381

> Apagar el brillo de los candidatos que el lock acaba de excluir
> (2026-09-13) — sin esto seguían brillando como "elegibles"
> aunque el filtro ya los rechazara.

### `_delegate_target_to_remote` — línea 429

> Nodos temporales de un popup de Cementerio (2026-10-12, p.ej. Lobo
> Sagrado jugado por el Remoto) — no viven en ningún contenedor; del lado
> Remoto no son visibles en el tablero, así que se muestran en el popup
> con la carta dibujada (RemoteMirrorController._show_await_target_prompt()).

### `_delegate_target_to_remote` — línea 439

> 2026-10-07, a pedido del usuario ("no sale... el abanico de cartas
> está todo escrito"): antes mandaba solo nombre/coste curados — ahora
> el card_data completo (Nodos reales ya lo tienen cargado), para que
> RemoteMirrorController pueda dibujar la carta de verdad en vez de un
> botón de solo texto.

### `_delegate_target_or_castillo_to_remote` — línea 468

> Contraparte en red de await_target_or_castillo_pick() (2026-10-07,
> ver arquitectura.md §41) — junta las dos mitades de la carrera local
> (cartas candidatas + Castillo propio/rival) en un solo prompt de texto,
> ya que del lado del Remoto no hay carrera real entre dos interacciones
> de UI simultáneas, solo una lista de opciones. Mismo criterio de
> identificar candidatas que _delegate_target_to_remote().

### `_delegate_multi_target_to_remote` — línea 520

> Contraparte en red de await_multi_target() — ver _delegate_target_
> to_remote() para el mismo criterio de identificar por get_instance_id().
> 2026-10-08, a pedido del usuario ("dale arreglemoslo" — ver
> arquitectura.md §43): lock_group_key/dynamic_filter YA se enforcean,
> pero del lado del ANFITRIÓN al recibir la respuesta completa, no en
> vivo mientras el Remoto tilda checkboxes (no hay un mecanismo de re-
> evaluar en cada click sin convertir esa UI en algo iterativo). Se
> recorren los card_ids que mandó el Remoto EN EL ORDEN en que vinieron
> y se van aceptando uno por uno solo si siguen pasando el mismo filtro
> que usaría el panel local dado lo YA aceptado hasta ese punto — un pick
> que lo violaría se descarta (no trunca el resto: una carta más cara
> rechazada no bloquea otras más chicas que sí entren después), en vez
> de confiar ciegamente en lo que mandó.

### `_delegate_multi_target_to_remote` — línea 536

> 2026-10-07, mismo motivo/arreglo que _delegate_target_to_remote()
> (await_target) — card_data completo en vez de nombre/coste curados.

### `await_target_or_castillo_pick` — línea 574

> Carrera entre clickear una carta real (que pase 'filter') y clickear
> un Panel de Castillo entero (propio o rival) — extraído (2026-09-13, a
> pedido del usuario, ver arquitectura.md §10.14/La Ouija) del mismo
> mecanismo ya usado a mano por ConvertAndMiscResolver.try_execute_mill_
> convert_to_ally_pattern() (Sherlock Holmes: 'convierte cartas en juego
> O del tope de un Castillo'). Útil para habilidades que ofrecen elegir
> entre una carta visible (mano/campo/Cementerio) y 'el tope/fondo de un
> Castillo' — no hay nada que clickear DENTRO del Castillo (es
> información oculta hasta que se elige), así que el Panel del Castillo
> entero actúa como el objetivo; el primer click real (carta o Castillo)
> decide la fuente, el otro deja de ser clickeable.
> 'allow_cancel': si true (habilidad opcional, 'puedes'), ESC en el
> picker de cartas cancela TODA la elección (incluye el Castillo en
> paralelo) y devuelve {type: "none"}. Si false (habilidad obligatoria,
> sin 'puedes'), ESC solo reintenta el picker de cartas — el Castillo
> sigue esperando en paralelo, la habilidad tiene que resolverse por
> algún lado.
> 'castillo_own_only': si true (p.ej. La Ouija: 'del tope de TU
> Castillo', con posesivo — a diferencia de Sherlock Holmes, 'un
> Castillo' sin posesivo, cualquiera de los dos), un click en el
> Castillo rival se ignora (se re-arma el listener del Castillo, sigue
> esperando) en vez de resolver la carrera con ese lado inválido.
> Devuelve {type: "card", card: Node}, {type: "castillo", own: bool}, o
> {type: "none"} si se canceló sin elegir nada.
> 'chooser_id' (2026-10-07, ver arquitectura.md §41): toda esta carrera
> depende de Paneles y Nodos reales de ESTA pantalla — sin equivalente
> directo para el Remoto. Se delega a _delegate_target_or_castillo_to_
> remote(), que junta ambas opciones (cartas candidatas + Castillo
> propio/rival) en un solo prompt de texto.

### `await_target_or_castillo_pick` — línea 608

> 2026-09-23, bug real reportado ("Attempt to call function 'null::null
> (Callable)' on a null instance"): los lambdas de GDScript capturan las
> variables locales POR VALOR, no por referencia (ver misma causa raíz
> documentada en arquitectura.md §13.17 para el cuelgue de mazos). Un
> lambda auto-referenciado como "arm_castillo_pick = func(): ...
> arm_castillo_pick.call()..." se rompe: adentro del lambda,
> "arm_castillo_pick" es la copia (vacía) de ANTES de la asignación, así
> que reintentar el pick del Castillo llamaba un Callable nulo. Lo mismo
> le pasaba en silencio a race_done/castillo_own/castillo_chosen (se
> reasignaban adentro del lambda sin que el bucle de abajo se enterara
> nunca). Arreglado guardando todo en un Dictionary ("_state"): SÍ se
> captura por referencia (la copia por valor es una copia del puntero al
> mismo objeto), así que mutar sus claves adentro del lambda es visible
> afuera, y el lambda puede llamarse a sí mismo vía _state["arm"].

### `await_target_or_castillo_pick` — línea 644

> Las cartas válidas brillan junto con el Castillo (2026-10-17, a
> pedido del usuario: Espada de O'Higgins solo hacía brillar el
> Castillo, sin mostrar qué cartas se podían Barajar).

### `cancel_target_selection` — línea 671

> Cancela con ESC. Llama al callback con null (en vez de dejarlo sin
> invocar) — quien esperaba con 'while not done: await process_frame'
> (TriggerSystem._select_ally_target, GoldManager._select_weapon_wielder,
> etc.) se quedaba colgado para siempre si el jugador cancelaba, porque
> 'done' nunca se ponía en true.
> No hace nada si la selección actual es NO cancelable (2026-09-13, ver
> _selection_cancellable arriba) — p.ej. un descarte MANDATORIO ('Descarta
> N cartas', sin 'puedes') no debe poder esquivarse con ESC como si fuera
> un costo opcional; el jugador tiene que clickear un objetivo válido.

### `_resolve_target_selection` — línea 697

> 2026-09-06, bug reportado por el usuario: quedarse pegado
> clickeando la mano repetidamente sin saber que ESC cancela la
> selección (p.ej. Golpe Solar: 'Baraja hasta una carta rival...
> ESC para no barajar ninguna' — sin este recordatorio, cada click
> en la mano solo repetía este mensaje para siempre, sin pista de
> cómo salir). El mensaje ahora lo dice explícito.

### `_on_card_clicked` — línea 734

> Selector de zonas con candidatas en la mano (Miguel) — antes que el
> desvío del Remoto y que cualquier otro modo (2026-10-12).

### `_on_card_clicked` — línea 738

> 2026-10-11: el cliente Remoto no corre la partida — un click nunca debe
> llegar a la lógica local (atacar, bloquear, jugar). Ver on_card_double_clicked().

### `_on_card_clicked` — línea 750

> Declarar bloqueador con un clic (2026-09-08, primera vez que se conecta
> GameManager.declare_blocker() a una UI real — existía desde antes pero
> sin ningún llamador, así que Bloqueo nunca dejaba hacer nada más que
> pasar prioridad, bug real reportado por el usuario: "no funcionó el
> sistema de bloqueos"). Solo el propio Aliado en Línea de Defensa del
> jugador humano — si el humano es quien ataca, sus Aliados están en
> Línea de Ataque, no Defensa, así que este bloque no interfiere.

### `_on_card_clicked` — línea 761

> Declarar atacante con un clic (2026-08-17): el arrastre se desactivó
> (Card.drag_enabled = false) por los bugs de posicionamiento que
> causaba — ver Card._can_declare_attack_drag() para la condición real
> (fase de Ataque, ya sin atajo de Vigilia — 2026-08-28). Se reutiliza
> esa función tal cual para no duplicar la lógica de cuándo tiene
> sentido intentar atacar.
> Acepta Defensa (para declarar) o Ataque (para desdeclarar con un
> segundo clic) — desde que declarar mueve de verdad la carta a Línea
> de Ataque (consolidación 2026-08-20), ya no se queda en Defensa.

### `_on_card_clicked` — línea 771

> Si ya está atacando, un segundo clic lo retira del combate en vez
> de rechazar el clic con un mensaje — a pedido del usuario, para
> poder corregir una declaración antes de confirmar con ¿Paso?.

### `_on_card_clicked` — línea 785

> No puede atacar todavía, pero SÍ estamos en una fase donde intentar
> atacar tiene sentido (2026-08-23) — dar la razón real (enfermedad
> de invocación, normalmente) en vez de caer al mensaje genérico de
> selección de más abajo, que no explica nada sobre el ataque.

### `_on_card_double_clicked` — línea 811

> 2026-10-11: en el cliente Remoto, jugar desde la mano física manda la
> jugada al Anfitrión (RemoteMirrorController), nunca GoldManager local.

### `_on_card_double_clicked` — línea 817

> Un click real en Godot (Card._on_gui_input) SIEMPRE dispara card_clicked
> primero (press 1, double_click=false) y LUEGO card_double_clicked (press
> 2 del mismo gesto, double_click=true) — confirmado con logging en vivo
> (2026-08-22). Si press 1 ya resolvió una selección de objetivo pendiente
> (p.ej. elegir portador de un Arma), press 2 llega con is_selecting_target
> ya en false — sin este chequeo caía en 'Solo puedes jugar cartas de la
> mano' como si hubiera fallado, aunque la selección ya se había resuelto
> bien. Se ignora en silencio ese eco (mismo objetivo, <700ms).

### `_on_card_double_clicked` — línea 833

> Un Aliado ya en juego (Defensa/Ataque) no se 'juega' con doble-click —
> tratarlo como el click simple de declarar/desdeclarar ataque en vez de
> caer en el rechazo genérico de abajo (2026-08-23): antes, doble-clickear
> por error un Aliado que no podía atacar todavía mostraba 'Solo puedes
> jugar cartas de la mano', un mensaje que no tiene nada que ver con la
> razón real (enfermedad de invocación, no es su turno, etc.).

### `_on_card_double_clicked` — línea 842

> No usar solo VIGILIA aquí: este gateo corría ANTES de que la carta
> llegara a GoldManager.play_card(), así que un Arma con Lobo Sagrado en
> juego (o cualquier Talismán) en Guerra de Talismanes nunca alcanzaba a
> intentarse siquiera (2026-08-28, bug reportado por el usuario).
> Talismanes de respuesta instantánea (Anula/Cancela) también quedan
> exceptuados aquí, en CUALQUIER fase (2026-09-06) — mismo criterio que
> GoldManager.play_card()'s is_instant_response, este gateo de UI corre
> antes y los habría bloqueado igual sin este chequeo repetido.

### `_on_card_double_clicked` — línea 852

> Ventana de comienzo de fase (2026-10-18).

### `_on_card_double_clicked` — línea 858

> 2026-09-15, mismo bug y mismo motivo que GoldManager.play_card() (ver
> ese comentario) — este gateo de UI corre ANTES de llegar ahí, así que
> sin esta excepción un Talismán de respuesta instantánea quedaba
> bloqueado igual antes de siquiera intentarlo.
> En la Guerra de Talismanes decide la prioridad, no el turno (§64) —
> GoldManager.play_card() lo valida.

### `_declare_attacker` — línea 897

> Declara un Aliado como atacante. Se llama al soltarlo en la Línea de
> Ataque — DropZone solo deja soltar aquí durante el paso de Ataque (DAR
> 5.3.1, ya sin atajo de Vigilia — ver 2026-08-28), y
> GameManager.declare_attacker() valida enfermedad de invocación (Furia
> la evita, pero ya no salta la fase). Antes esta función solo se usaba
> (y nombraba) para Furia, pero el drop de DropZone ya aceptaba ambos
> casos — ver hallazgo 5.
>
> NO abre su propia ventana de prioridad (2026-08-16): antes lo hacía
> siempre, apenas se declaraba UN atacante — eso hacía que, en cuanto se
> pasaba esa ventana, se interpretara como 'atacantes confirmados' y el
> combate arrancaba con un solo Aliado, sin dejar declarar más. Además esa
> ventana se solapaba con la que GameManager.declare_attacker() ya abre
> internamente al resolver el trigger 'cuando ataque' de la propia carta
> (ver TriggerSystem._collect_triggers_for_event), lo que dejaba la
> prioridad en un estado inconsistente. Ahora el jugador puede seguir
> arrastrando más Aliados a la Línea de Ataque, y confirma todos juntos
> presionando ¿Paso? — que ya llama a GameManager.confirm_attackers()
> cuando no hay ninguna ventana de prioridad activa (ver _on_paso_pressed
> en PhaseFlowController), y ESA transición sí abre la ventana real
> (Guerra de Talismanes o Bloqueo).

### `_declare_attacker` — línea 920

> Traba de reentrada (2026-08-23): un segundo click/eco sobre la MISMA
> carta mientras una declaración anterior sigue en vuelo (ver comentario
> de _declaring_attackers) no debe iniciar una segunda declaración en
> paralelo — se ignora en silencio en vez de competir por
> GameManager.attackers.

### `_declare_attacker` — línea 950

> KeywordManager.can_attack_immediately() (2026-09-02, refactor), no
> card.has_keyword() directo — mismo motivo que el resto de checks de
> keyword movidos a KeywordManager: respeta silencio/remociones
> temporales, y ya es la misma función que usa TurnManager.can_attack()
> para la validación real, así que el mensaje ahora no puede
> desincronizarse de si el ataque de verdad contó como 'con Furia'.

### `_declare_blocker` — línea 975

> Declara 'card' como bloqueador de un atacante (fase BLOQUEO, DAR
> 5.3.2). Con exactamente un atacante sin bloquear, se asigna directo sin
> preguntar. Con más de uno, pide clickear DIRECTO sobre el atacante rival
> en el tablero (2026-09-12, a pedido del usuario — antes era una lista de
> texto con nombres, no clickeable). Un segundo clic sobre un bloqueador ya
> declarado no hace nada especial todavía (deselección/reasignación queda
> fuera de alcance de este primer cableado real).

### `_declare_blocker` — línea 999

> 2026-09-12 (a pedido del usuario): click directo sobre el atacante en
> el tablero, no una lista de texto — mismo mecanismo (await_target)
> que usa el resto del juego para elegir objetivo (Anular, Convertir,
> Barajar una carta puntual, etc.), en vez de un modal con nombres.

## `scripts/ui/hud/DebugInputModule.gd`

### `(nivel de archivo)` — línea 3

> DebugInputModule — Atajos de teclado de debug (F1-F9) y ESC (cerrar
> inspección/cancelar selección/pausa). Extraído de Main.gd (2026-08-28, a
> pedido del usuario: "el main es para arrancar la app", esto es tooling de
> runtime, no arranque). Se instancia como hijo de Main en _ready().

### `_input` — línea 64

> 2026-10-01 (a pedido del usuario): atajo 'P' para el botón Pasar/Atacar/Daño del HUD

### `_input` — línea 69

> 2026-10-17, a pedido del usuario: N = no hacer la acción
> opcional ("hasta una", "puedes") o terminar una selección
> múltiple con lo ya elegido. El resto del efecto sigue (p.ej.
> "Destierra hasta una carta y Roba una": Robas igual). Las
> selecciones obligatorias no se pueden saltar.

### `_handle_enter_press` — línea 165

> 6. Panel de selección de cartas activo (SelectionCanvas - Buscar, Descartar, etc.)
> 2026-09-13, bug real reportado por el usuario: "Invalid access to property
> or key 'is_active' on a base object of type 'Node (SelectionModule)'" —
> _main._selection (SelectionModule) nunca tuvo is_active/confirm_button; el
> panel real de selección vive en el autoload SelectionManager (is_open/
> _confirm_button, con guion bajo).

## `scripts/ui/hud/GameHUDModule.gd`

### `(nivel de archivo)` — línea 11

> Generación de la cuenta regresiva del botón (2026-10-11): sube en cada
> start/stop para que un bucle viejo deje de escribir el texto.

### `update_paso_button_state` — línea 138

> Con ventana de prioridad activa (Bloqueo, Guerra de Talismanes,
> cualquier ventana de respuesta) quien debe actuar es quien TIENE la
> prioridad ahora mismo, no necesariamente el dueño del turno (2026-
> 09-03, bug reportado: 'se queda estancado en guerra de talismanes' —
> cuando el humano defiende en el turno del oponente, DAR 5.C3 le da
> la prioridad primero en Guerra de Talismanes, pero la visibilidad
> dependía solo de active_player_id == 0, así que el botón nunca
> aparecía y no había forma de pasar).

### `update_paso_button_state` — línea 147

> 2026-09-25, bug real reportado por el usuario ("el botón de pasar
> dice atacar aunque es para pasar"): el texto se decidía ANTES de
> este chequeo, mirando solo la fase — pero con una ventana de
> prioridad activa, _on_paso_pressed() SIEMPRE solo pasa prioridad
> (PriorityManager.pass_priority()), sin importar la fase, incluso
> si esa ventana se abrió durante tu propia Vigilia (p.ej.
> respondiendo al 'Cuando entra en juego' de una carta). El texto
> tiene que decir lo que el click realmente va a hacer.

### `update_paso_button_state` — línea 157

> 2026-09-15, diagnóstico temporal a pedido del usuario (bug real:
> "se traba en Guerra de Talismanes, no aparece ningún botón" —
> reaparición de un síntoma ya arreglado una vez, 2026-09-03, ver
> comentario de arriba): imprime el estado real detrás de la
> decisión de mostrar/ocultar, para ver en qué falla esta vez.

### `update_paso_button_state` — línea 169

> 2026-09-20, bug real reportado por el usuario ("el botón de paso
> desaparece" quedando pegado en Guerra de Talismanes): Guerra de
> Talismanes/Bloqueo SIN ventana activa es precisamente el estado
> "clobbereado" que _try_recover_stuck_phase_priority_window() ya sabe
> recuperar (ver PhaseFlowController.gd, bugs documentados 2026-09-04 y
> 2026-09-06) — pero antes de este fix el botón se ocultaba en ese
> mismo estado (ni VIGILIA/ATAQUE/FINAL, ni is_player_turn confiable
> mientras defiendes: active_player_id es el oponente aunque la
> prioridad de defensor te toque a ti primero, DAR 5.C3), dejando la
> recuperación sin ninguna forma de dispararse desde la UI. El botón
> ahora se mantiene visible en estas 2 fases sin importar de quién sea
> el turno; al presionarlo, PhaseFlowController._on_paso_pressed() ya
> llama _try_recover_stuck_phase_priority_window() en esta rama — si de
> verdad no hay nada que recuperar, esa función no hace nada y el
> jugador ve "Sin ventana de prioridad activa" en vez de quedar sin
> ningún botón con qué reaccionar.
> 2026-09-13, a pedido del usuario: el botón debe reflejar QUÉ pasa al
> presionarlo, no solo "hiciste una acción" — en Guerra de Talismanes
> (5.3.3), pasar es lo que hace avanzar a Asignación de Daño (5.3.4)
> cuando ambos jugadores pasan seguido, así que el botón dice "Daño" en
> vez del genérico "¿Paso?" aquí, igual que ya decía "Atacar" en Vigilia.

### `update_paso_button_state` — línea 195

> Sin ningún Aliado que pueda atacar: "Fase Final" (2026-10-18).

### `is_paso_button_ready` — línea 224

> ¿El botón ¿Paso?/Atacar está visible y puede clickearse ahora? (2026-09-11,
> a pedido del usuario: atajo de teclado Q — simula el mismo click que el
> mouse, así que solo debe actuar cuando el botón real haría algo).

### `stop_paso_glow` — línea 273

> =============================================================================
> CUENTA REGRESIVA Y CONTROL EXTERNO DEL BOTÓN (2026-10-11, online)
> =============================================================================

## `scripts/ui/hud/SpinnerDrawer.gd`

### `(nivel de archivo)` — línea 2

> SpinnerDrawer — dibuja el anillo místico rotatorio del spinner de carga
> (MatchLoadingOverlay._build_mystic_spinner()). Necesita su propio _draw(),
> así que no puede vivir como función suelta en MatchLoadingOverlay.gd — de
> ahí que se asigne con set_script() en vez de definirse inline.
> Placeholder simple (2026-09-08, arregla un "SpinnerDrawerScript" referenciado
> pero nunca declarado, que rompía la carga del autoload) — reemplazar el
> dibujo si se quiere un diseño más elaborado.

## `scripts/ui/inspection/AbilityButtonPatternsA.gd`

### `(nivel de archivo)` — línea 2

> AbilityButtonPatternsA — primer cuarto (por posición en el archivo
> original) de los patrones especiales de botones de habilidad ACTIVADA
> extraídos de CardInspectionLayer._build_ability_buttons() (2026-09-06,
> "módulos gordos", Fase 2 — ver iterative-booping-abelson.md).
>
> Cada patrón vivía como un bloque `if is_X_pattern: ... continue` dentro
> del for-loop de _build_ability_buttons(). Aquí cada uno es simplemente un
> `if` más dentro de try_build(), que corta en el PRIMER match y devuelve
> true (equivalente al `continue` original) — CardInspectionLayer.gd llama
> a los 4 archivos hermanos (A, B, C, D) EN ORDEN, así que el orden relativo
> de todos los chequeos originales queda exactamente igual, solo que ahora
> repartido en 4 funciones en vez de un if-chain gigante en una sola.
>
> Bernardo O'Higgins, Padre de la Patria, Cetro Demoniaco, quimera voragh
> (mill), voragh el devorador (x2), tenshi Z, dyyavol titán, jinete de la
> peste, sandraudiga, asmodeus, belcebu, cuerno titán, Legión Paladín,
> Don de Amma, Tesoro de los Césares, Miguel, Tyet (primera habilidad).

### `try_build` — línea 28

> Maldición Vudú (2026-10-18): desde el Cementerio, Desterrarla para
> Barajar o Desterrar una carta de un Cementerio. Antes que el patrón de
> Espíritu de la Máquina (grupo B), que tiene el mismo final de texto.

### `try_build` — línea 38

> Patrón especial de Bernardo O'Higgins (2026-08-26): coste alternativo
> (barajar un Arma/Aliado Caballero) + elegir entre dos efectos con
> objetivo (desterrar ≤3 / cancelar habilidad) — no encaja en el
> sistema genérico de costes/acciones de ActionPipeline (un solo tipo
> de coste, sin targeting), así que se resuelve aparte.

### `try_build` — línea 54

> Patrón especial de Padre de la Patria (2026-08-28): "genera un Oro
> para jugar X" es Oro Virtual RESTRINGIDO (GoldManager.
> restricted_gold_pools), un concepto que ActionPipeline no conoce —
> se genera directo aquí, sin pasar por el pipeline genérico.

### `try_build` — línea 68

> Patrón especial de Cetro Demoniaco (2026-09-06): "genera un Oro y
> Destierra cuatro cartas del tope de un Castillo" — Oro SIN
> restringir + Destierro masivo de tope elegido, ActionPipeline no
> resuelve acciones compuestas de dos tipos distintos en una sola
> habilidad.

### `try_build` — línea 82

> Patria Vieja (2026-10-13): "En tu Vigilia, si no has puesto Oros en
> juego este turno, puedes mirar las primeras seis cartas de tu
> Castillo y poner un Oro de ahí en tu Reserva".

### `try_build` — línea 93

> Duelo Espacial en el Cementerio (2026-10-13): gana "En tu Vigilia,
> puedes Robar una carta" (una vez por turno).

### `try_build` — línea 104

> Patrón especial de quimera voragh (2026-09-06): "cada jugador Bota
> tres cartas. Si se Botaron Aliados u Oros, pon en juego una carta
> de un Cementerio como un Aliado de Fuerza 2 con Furia" — botado
> por ambos jugadores con seguimiento de tipos (ActionModule.mill()
> no informa tipos en su fallback), condición sobre lo botado y
> conversión real.

### `try_build` — línea 120

> Patrón especial de voragh el devorador (2026-09-06): "puedes
> Destruir una de tus cartas para generar un Oro para jugar
> Aliados" — costo de Destruir con objetivo (propio), efecto de Oro
> Virtual restringido.

### `try_build` — línea 207

> Legión Paladín removida de aquí (2026-09-09, "sistema de respuestas"):
> ya no es un botón — EffectController.offer_prevention() la detecta y
> ofrece reactivamente (tag "leave_play") en el momento en que un
> Aliado propio está por salir del juego, no antes. El handler viejo
> (_activate_legion_paladin_prevention, PreventionAbilityHandler_EP.gd)
> se eliminó junto con este bloque.

### `try_build` — línea 214

> Patrón especial de Don de Amma (2026-08-29): "Una vez por turno,
> puedes Desterrar un Oro con habilidad de tu Reserva. Luego, busca
> un Oro en tu Castillo y ponlo en tu Reserva." — costo de Desterrar
> UNA carta elegida entre los Oros-con-habilidad propios en Reserva
> (no necesariamente esta misma), seguido de una búsqueda que no va
> a la mano — ActionPipeline no tiene ninguno de los dos conceptos.

### `try_build` — línea 230

> Patrón especial de Tesoro de los Césares (2026-08-29): "Una vez por
> turno, puedes Barajar una carta de tu mano para nombrar una carta.
> Esa carta cuesta un Oro adicional el próximo turno." — costo de
> Barajar (mano → mazo, no descarte) + nombrar una carta CUALQUIERA
> del juego (no un objeto en juego, un NOMBRE) con un recargo de
> coste que arranca solo el turno siguiente — ActionPipeline no
> tiene ninguno de los tres conceptos (costo Barajar, nombrar, tax
> diferido). Requiere el fix de parse_abilities() de esta misma
> sesión que une la segunda oración (sin coste/trigger propio) a la
> ACTIVADA anterior — sin eso 'cuesta un oro adicional' nunca
> aparecía en raw_text y este patrón no matcheaba nunca.

### `try_build` — línea 251

> Patrón especial de Miguel (2026-08-29): "Una vez en tu turno, juega
> una carta de tu mano o de un Cementerio reduciendo su coste en un
> Oro, hasta un mínimo de 0." — elegir entre mano Y Cementerio a la
> vez, con descuento de -1/piso 0 aplicado solo a esa carta, no es
> nada que ActionPipeline sepa hacer solo. Reusa GoldManager.
> play_card() completo (fases, portador de Armas, Talismanes) con el
> mismo mecanismo de descuento puntual que 'Muestra X para reducir
> el coste' (El Rey y el Verdugo, ya en GoldManager.play_card()).

### `try_build` — línea 269

> Patrón especial de Tyet (2026-08-29): "Puedes pagar este Oro para
> que un Oro pierda su habilidad este turno y muévelo al Oro Pagado."
> Costo = esta misma carta (CostType.SELF_AS_GOLD, ActionPipeline no
> lo conoce). Efecto sobre OTRO Oro elegido: silencio temporal
> (KeywordManager.silence_card(..., "turn"), se autolimpia solo al
> empezar el próximo turno) + mover a Oro Pagado.

## `scripts/ui/inspection/AbilityButtonPatternsB.gd`

### `(nivel de archivo)` — línea 2

> AbilityButtonPatternsB — segundo cuarto (por posición en el archivo
> original) de los patrones especiales de botones de habilidad ACTIVADA
> extraídos de CardInspectionLayer._build_ability_buttons() (2026-09-06,
> "módulos gordos", Fase 2). Ver AbilityButtonPatternsA.gd para la
> explicación completa del mecanismo try_build()/orden de evaluación.
>
> Tyet (segunda habilidad), Ramón Freire, Espada de O'Higgins (Vigilia),
> Infernum Vox, Paladín Bestiarium (x2), Crono Diamante, Aho, Kuchiku Kan,
> Kuchiku El Cazador (x2), Quantum Megumi, Sake, Dulce Canasta, Belta (x2),
> Espíritu Máquina, Frankenstein (cancelar).

### `try_build` — línea 21

> Segundo patrón de Tyet (2026-08-30): "Puedes poner esta y otra
> carta de tu mano en el fondo de tu Castillo y Robar dos cartas." —
> usable DESDE LA MANO (ver _ability_is_hand_usable()). Costo:
> esta carta + otra elegida de la mano, ambas al fondo del mazo.

### `try_build` — línea 35

> Patrón especial de Ramón Freire (2026-08-30): "Si controlas
> Aliados de coste 2 o más, puedes Desterrarlo de tu mano o en
> juego para generar un Oro para jugar Armas." — usable DESDE LA
> MANO o ya en juego, con una condición previa (controlar un Aliado
> de coste ≥2) que ActionPipeline no sabe verificar.

### `try_build` — línea 50

> Patrón de Espada de O'Higgins removido de aquí (2026-09-07, bug real
> encontrado en auditoría): este guard ("barajar una carta que no sea
> oro" + "buscar un oro en tu castillo") es un subconjunto estricto del
> guard de AbilityButtonPatternsC.gd ("puedes barajar una carta que no
> sea oro o buscar un oro en tu castillo") — como el despacho es A→B→C→D
> con el primer match ganando, este bloque SIEMPRE se adelantaba al de C
> y dejaba _activate_espada_ohiggins_shuffle_or_search_gold() (el fix
> correcto del 2026-09-04: registra el uso DESPUÉS de confirmar objetivo,
> no antes) permanentemente inalcanzable. _activate_espada_ohiggins_
> vigilia_choice() (SearchAbilityHandler_AI.gd) queda sin llamador —
> handler viejo superado, no se borró por las dudas de que algo más lo
> referencie a futuro.

### `try_build` — línea 63

> Patrón especial de Infernum Vox (2026-08-30): "Una vez por turno,
> puedes mirar seis cartas del tope de un Castillo y devolverlas en
> cualquier orden en el tope y/o fondo del Castillo." — puro
> reordenamiento (no es 'mirar y jugar/quedarte una', es 'mirar y
> repartir+ordenar TODAS'), un concepto que ActionPipeline no tiene.

### `try_build` — línea 79

> Patrón especial de Paladín Bestiarium — habilidad 1 (2026-08-30):
> "Una vez por turno, puedes Descartar una carta para jugar un Arma
> de tu mano reduciendo su coste en un Oro, hasta un mínimo de 0." —
> el costo (descartar CUALQUIER carta) y el efecto (jugar OTRA carta
> distinta con descuento) no coinciden, ActionPipeline solo sabe
> resolver costo+efecto sobre la MISMA carta.

### `try_build` — línea 95

> Patrón especial de Crono Diamante (2026-09-02): "Una vez por
> turno, si jugaste un Aliado de coste 2 o más este turno, puedes
> Descartar una carta para jugar un Aliado reduciendo su coste en
> un Oro, hasta un mínimo de 1." — mismo esqueleto que Paladín
> Bestiarium (descartar + jugar otra con descuento) pero para
> Aliados, con condición previa y piso 1 en vez de 0.

### `try_build` — línea 111

> Patrón especial de Paladín Bestiarium — habilidad 2 (2026-08-30):
> "Una vez en tu turno, puedes Descartar o subir un Arma que
> controles a la mano para Anular una carta de coste 1 o menos." —
> costo con DOS mecanismos alternativos (descartar O devolver a la
> mano) sobre un Arma EN JUEGO (no la propia carta), más un
> objetivo con filtro de coste — nada de esto lo resuelve
> ActionPipeline solo.

### `try_build` — línea 128

> Patrón especial de Aho (2026-08-30): "Una vez por turno, Destierra
> un Aliado o Tótem y cinco cartas del tope de un Castillo." — dos
> destierros independientes (objetivo elegido + N del tope de un
> mazo a elección) unidos por 'y', ninguno de los dos conceptos lo
> resuelve ActionPipeline solo.

### `try_build` — línea 143

> Patrón especial de Kuchiku Kan (2026-09-03): "Una vez por turno,
> puedes Descartar una carta para que una carta pierda su habilidad
> y no pueda atacar ni bloquear mientras este Aliado esté en
> juego." — costo (descartar cualquiera) y objetivo (otra carta en
> juego) no coinciden, y el efecto liga dos sistemas distintos
> (KeywordManager + ContinuousEffectManager) a la duración
> 'mientras esta carta esté en juego'.

### `try_build` — línea 159

> Patrón especial de Kuchiku El Cazador — habilidad 1 (2026-09-03):
> "Una vez en tu turno, busca en tu Castillo o Cementerio un Aliado
> y juégalo reduciendo su coste en un Oro, hasta un mínimo de 0." —
> búsqueda con elección de zona + jugar con descuento, mismo
> esqueleto que Miguel pero con un paso de búsqueda real antes.

### `try_build` — línea 174

> Patrón especial de Kuchiku El Cazador — habilidad 2 (2026-09-03):
> "Una vez en tu turno, puedes Destruir hasta una carta de coste 3 o
> menos y tu oponente Bota cartas igual a la Fuerza de este
> Aliado." — destruir (objetivo opcional, tope de coste) + descarte
> con cantidad dinámica (Fuerza actual), dos efectos independientes
> que ActionPipeline no resuelve juntos.

### `try_build` — línea 189

> Patrón especial de Quantum Megumi (2026-09-04): "Una vez por
> turno, Baraja una carta de tu mano para Barajar hasta tres cartas
> de tu Cementerio y Robar una carta." — costo (barajar CUALQUIER
> carta de la mano) y efecto (barajar del propio Cementerio +
> robar) no coinciden, ActionPipeline no resuelve ambos juntos.

### `try_build` — línea 204

> Patrón especial de Sake (2026-09-04): "En tu Vigilia, una vez por
> turno, si no controlas más Oros que tu oponente, puedes pagar un
> Oro para poner un Oro en juego desde tu mano o Cementerio." —
> condición dinámica (conteo de Oros de ambos jugadores) + costo +
> 'poner en juego' (no 'jugar') desde dos zonas de origen a la vez.

### `try_build` — línea 219

> Patrones especiales de Oros (2026-09-04, tanda de checklist)

## `scripts/ui/inspection/AbilityButtonPatternsC.gd`

### `(nivel de archivo)` — línea 2

> AbilityButtonPatternsC — tercer cuarto (por posición en el archivo
> original) de los patrones especiales de botones de habilidad ACTIVADA
> extraídos de CardInspectionLayer._build_ability_buttons() (2026-09-06,
> "módulos gordos", Fase 2). Ver AbilityButtonPatternsA.gd para la
> explicación completa del mecanismo try_build()/orden de evaluación.
>
> Frankenstein (silencio), Perla de Sangre (x2), Líder del Comité,
> Almirante Akari, Tótem Dragón Ancestral, Torre de Babel, Lanza Argenta,
> Skofnung, Espada de O'Higgins (barajar/buscar), Nu Galahad (x2),
> Visión Heroica, Shub-Niggurath (x2), Piruquina, Akari, quimera voragh
> (anular talismán).

### `try_build` — línea 49

> Patrón especial de akuma el terrible (2026-09-04): "Una vez por
> turno, puedes Desterrar hasta dos cartas de los Cementerio o Roba
> una carta" — elección A/B, ActionPipeline no resuelve un "o" entre
> dos efectos de forma tan distinta (desterrar de Cementerio vs robar).

### `try_build` — línea 62

> Almirante Akari removida de aquí (2026-09-09, "sistema de respuestas" —
> corregido a pedido del usuario): ya no es un botón con elección A/B
> proactiva — son DOS disparadores reactivos distintos que comparten un
> candado de una vez por turno (EffectController._prevention_registry
> para "prevenir"; EffectController.offer_counter_annul() para "anular
> cuando el rival juega una carta").

## `scripts/ui/inspection/AbilityButtonPatternsD.gd`

### `(nivel de archivo)` — línea 2

> AbilityButtonPatternsD — cuarto y último grupo (por posición en el archivo
> original) de los patrones especiales de botones de habilidad ACTIVADA
> extraídos de CardInspectionLayer._build_ability_buttons() (2026-09-06,
> "módulos gordos", Fase 2). Ver AbilityButtonPatternsA.gd para la
> explicación completa del mecanismo try_build()/orden de evaluación.
>
> Uriel, Atenea, Sumi, Gran Kraken, Ereshkigal, Campanita, akuma el
> terrible, Chakram, Estaca (x2), Ángel Redentor, Espada del Juicio,
> Drácula (x2), Espíritu Kotaix, Sacrificio Solar, La Ouija, y los botones
> de scripts/core/effects/mechanics/ (2026-10-18).

### `try_build` — línea 89

> Patrón especial de Chakram (2026-08-30): "Una vez por turno, puedes
> mirar la mano de tu oponente y elegir una carta de ahí que no sea
> Oro para que no pueda ser jugada hasta tu próximo turno y Roba una
> carta." — reveal privado de la mano rival + candado por carta
> puntual (GoldManager.lock_card_from_playing()), ningún concepto que
> ActionPipeline resuelva solo.

### `try_build` — línea 105

> Patrón especial de Estaca (2026-08-30): "Una vez por turno, puedes
> Robar tres cartas, Barajar una carta oponente que no sea Oro y
> tantas cartas de tu mano como coste tenga." — la carta oponente no
> dice zona (EN JUEGO, ver [[project_no_zone_means_in_play]]) y la
> cantidad a barajar de la propia mano es DINÁMICA (el coste de la
> carta rival elegida), nada de esto lo resuelve ActionPipeline solo.

### `try_build` — línea 121

> Estaca (segunda habilidad) y Ángel Redentor removidos de aquí
> (2026-09-09, "sistema de respuestas"): ya no son botones que el
> jugador activa desde el Zoom — EffectController.offer_prevention()
> las detecta y ofrece reactivamente en el momento exacto en que
> corresponde (ver el registro en EffectController.gd). Los handlers
> viejos (_activate_estaca_banish_for_prevention/_activate_angel_
> redentor_prevent en PreventionAbilityHandler_EP.gd/_AE.gd) se
> eliminaron junto con este bloque.

### `try_build` — línea 130

> Patrón especial de Espada del Juicio (2026-08-30): "Puedes
> Desterrarla de tu Cementerio para que un Aliado gane o pierda 2
> de Fuerza permanentemente." — primera habilidad usable DESDE EL
> CEMENTERIO de esta sesión (ver _ability_is_cementerio_usable()),
> costo sobre el DATO real del Cementerio (no sobre este nodo de
> solo vista) + elegir Aliado y signo del bono.
> Envidia (2026-10-14, mazo 170): desde el Cementerio, con menos cartas
> en la mano que el oponente, Desterrarlo para Robar una carta.
> Ira (2026-10-17): desde el Cementerio, Desterrarlo para +1 y ataque
> que no puede ser cancelado.

### `try_build` — línea 148

> Alto Prime (2026-10-17): Descartar una carta para ponerlo en juego
> desde tu Cementerio como un Aliado sin habilidad.

### `try_build` — línea 176

> Drácula (tercera habilidad, "convertirlo... para prevenir...")
> removida de aquí (2026-09-09, "sistema de respuestas") — mismo motivo
> que Estaca/Ángel Redentor arriba: ya no es un botón, es reactiva.

### `try_build` — línea 180

> Patrón especial de Drácula, cuarta habilidad (2026-08-30): "Puedes
> Desterrarlo de tu mano o Cementerio para cancelar el ataque de
> hasta dos Aliados." — usable DESDE LA MANO o el CEMENTERIO (ver
> _ability_is_hand_usable()/_ability_is_cementerio_usable()), primera
> habilidad que cancela un ataque ya declarado (nuevo: sacar de
> GameManager.attackers + revertir el aspecto visual, sin pasar por
> undeclare_attacker() porque no requiere ser el propio turno del
> controlador de ese Aliado).

### `try_build` — línea 198

> Patrón especial de Espíritu Kotaix, segunda habilidad (2026-09-02):
> "Una vez por turno, Roba dos cartas y Baraja una carta oponente que
> no sea Oro. Esta habilidad no puede ser cancelada." — mismo patrón
> que Estaca (Robo incondicional + Baraja de una carta rival en juego
> excluyendo Oro), sin el barajado adicional de la propia mano.

### `try_build` — línea 212

> Patrón especial de Sacrificio Solar (2026-09-02): "Puedes pagar un
> Oro y Barajar esta carta desde tu mano para Desterrar o Barajar
> una carta de coste 2 o menos y Robar una carta." — usable DESDE LA
> MANO (ver _ability_is_hand_usable()), costo de Oro + la propia
> carta (autobarajarse desde la mano, no destierro ni descarte —
> concepto que ActionPipeline no tiene) y elección Destierra/Baraja
> sobre el objetivo, algo que tampoco resuelve solo.

### `try_build` — línea 228

> Patrón especial de La Ouija (2026-08-31): "Una vez por turno, puedes
> jugar una carta de tu Cementerio o del tope de tu Castillo." — dos
> zonas de origen alternativas ('de tu Cementerio' Y 'del tope de tu
> Castillo', ambas con posesivo — solo las propias) que ActionPipeline
> no resuelve solo (solo sabe jugar la carta que ya tienes en mano).
> Botones de scripts/core/effects/mechanics/ (2026-10-18): [texto, módulo,
> función]. Todas reciben (carta, habilidad) salvo Escritura Sagrada, que
> es una habilidad sintética (su texto es exacto).

## `scripts/ui/inspection/AbilityButtonSupport.gd`

### `(nivel de archivo)` — línea 2

> AbilityButtonSupport — validación de habilidades ACTIVADAS + ciclo de
> vida del botón superpuesto de habilidad (creación visual, activación vía
> ActionPipeline, brillo de "habilidad en la pila") extraído de
> CardInspectionLayer.gd (2026-09-06, "módulos gordos", Fase 2 — ver
> iterative-booping-abelson.md). Sin llamadores externos confirmados por
> grep — CardInspectionLayer.gd sigue siendo el único punto de entrada,
> ahora vía _button_support, montado en setup().

### `_tamales_ability_restriction_reason` — línea 21

> Wrapper — la lógica real vive en ContinuousEffectManager.tamales_
> ability_restriction_reason() (2026-09-04, movida ahí para compartirla
> con TriggerSystem._check_trigger_conditions(), que necesita el mismo
> chequeo para 'ni disparar').

### `_is_annul_or_cancel_ability` — línea 29

> Detecta si UNA habilidad ACTIVATED puntual (raw_text ya aislado por
> parse_abilities(), no la carta entera) es de tipo Anular/Cancelar — la
> única categoría de ACTIVATED que CardInspectionLayer._build_ability_
> buttons() ofrece durante el turno RIVAL (2026-09-19, arquitectura.md
> §10.11 caso 4). Mismo criterio de palabra que GoldManagerRestrictions.
> _is_response_only_ability_text() (Talismanes de respuesta), pero por
> 'contains' en vez de 'begins_with': aquí ya operamos sobre el raw_text de
> UNA sola habilidad (p.ej. 'Puedes Desterrarlo para Anular una carta de
> coste 1 o menos que no sea Aliado', Akari), no sobre la carta completa
> con varias oraciones sin relación — el costo casi siempre precede a
> 'anular'/'cancela' en la misma oración, así que 'begins_with' descartaría
> falsos negativos reales. Excluye frases de PROTECCIÓN ('no puede ser
> anulada/cancelada', p.ej. Padre de la Patria) para no ofrecer el botón
> por error en una habilidad que blinda a la propia carta, no que anula al
> rival.

### `_is_responding_to_opponent_action` — línea 51

> ¿Hay ahora mismo una ventana de respuesta real abierta (Paso D,
> PriorityContext.RESPONSE_WINDOW) — es decir, se está reaccionando a algo
> puntual que ya está en la Pila (una carta jugada o una habilidad
> activada/disparada, cualquiera de las dos, §10.53 abre esa ventana para
> TODO) — en vez de actuando proactivamente (tu propia Vigilia, o
> simplemente tener la palabra en Guerra de Talismanes sin responder a
> nada puntual, PriorityContext.GUERRA_TALISMANES)?
>
> 2026-09-19, a pedido del usuario: varias cartas (Bernardo O'Higgins,
> Lanza Argenta, ...) combinan en un mismo botón/costo un efecto
> PROACTIVO (Desterrar, Robar tres cartas) con uno REACTIVO (Cancelar una
> habilidad) — la idea es que la rama se elija SOLA según el momento en
> que se usa, no una elección A/B libre cada vez: "si voy en mi turno o en
> Guerra de Talismanes, siempre la de Desterrar/Robar; si mi oponente jugó
> una carta o usó una habilidad, ahí cancelaría" (cita textual del
> usuario). No mira de quién es el turno (`GameManager.active_player_id`)
> a propósito — mira el CONTEXTO de prioridad, que es lo que realmente
> distingue "estoy respondiendo a algo puntual" de "tengo la palabra en
> general" sin importar de quién sea el turno.

### `_validate_ability` — línea 75

> Valida si una habilidad activada puede ejecutarse ahora.
> Comprueba: prioridad, oro disponible, cartas en mano, carta girada, ActionPipeline.
> 'player_id' (2026-10-12): quién la activaría — el Remoto usa la misma
> validación que los botones del Anfitrión (antes todo asumía jugador 0).

### `_validate_ability` — línea 82

> Silenciada (por instancia o por nombre, ver KeywordManager.is_silenced())
> = pierde TODAS sus habilidades, activadas incluidas — antes esto solo
> se chequeaba para triggers (TriggerSystem._check_trigger_conditions()),
> los botones de habilidad activada seguían mostrándose igual (2026-08-29).

### `_validate_ability` — línea 89

> Restricción de fase por texto propio de la carta (2026-08-30, p.ej.
> Espada de O'Higgins: "En tu Vigilia, una vez por turno, puedes...").
> _build_ability_buttons() ya permite el botón en Vigilia O en ventana
> de prioridad (genérico, para cartas sin restricción de fase) — esto
> cierra el caso más estricto de una carta que solo se puede usar en su
> propia Vigilia, ni siquiera con prioridad abierta en otra fase.

### `_validate_ability` — línea 99

> "Una vez EN tu/su turno" (2026-09-13, a pedido del usuario — ver
> arquitectura.md §10.11): más restrictiva que "una vez por/al turno" en
> CUÁNDO se puede activar, no solo en frecuencia. "una vez por turno"
> genérico ya se permite en cualquier ventana de prioridad de tu turno
> (Guerra de Talismanes incluida, más abajo en can_act()/priority_window_
> active) — esta variante explícita NO, aunque la propia habilidad pueda
> Anular/Cancelar (p.ej. paladín bestiarium: su habilidad de Anular dice
> "una vez en tu turno", más restrictiva que la convención general de
> que Anular/Cancelar es de respuesta instantánea).

### `_validate_ability` — línea 111

> 'Tu oponente sólo puede utilizar las habilidades de Oros y cartas de
> coste 2 o más si no controla más copias de esa carta' (2026-09-04,
> Tamales) — único choke point real de validación de habilidades
> ACTIVADAS, así que basta un chequeo aquí para cubrir cualquier carta.

### `_validate_ability` — línea 139

> instance_id, NO card_data.id (2026-08-30, corrección: card_data.id
> es el ID de la carta/impresión, compartido por TODAS las copias en
> juego — con 2 Aho en juego, usar uno marcaba el cupo también para
> el otro. Cada copia física necesita su propio cupo).

### `_validate_ability` — línea 157

> Verificación adicional con ActionPipeline — source_card_node en el
> context (2026-08-30) para que can_activate_ability() también use el
> instance_id, no el id compartido entre copias.

### `_create_ability_overlay_button` — línea 181

> Botón superpuesto sobre el párrafo de la carta donde está impresa esta
> habilidad. No dibuja texto propio (la carta ya lo muestra); un
> rectángulo de bordes curvos color celeste marca SIEMPRE qué habilidad se
> puede activar y dónde clickear (2026-08-26, a pedido del usuario — antes
> el borde solo aparecía al pasar el mouse, así que no había forma de
> saber de antemano qué parte de la carta era clickeable). Al pasar el
> mouse se resalta más fuerte, y lleva el costo y efecto como tooltip.

## `scripts/ui/inspection/BernardoAbilityHandler.gd`

### `(nivel de archivo)` — línea 3

> BernardoAbilityHandler — Caso especial de Bernardo O'Higgins: coste
> alternativo (Barajar un Arma/Aliado Caballero) + elección de efecto con
> objetivo (Desterrar coste ≤3 o cancelar habilidad). Detectado en
> CardInspectionLayer._build_ability_buttons() (is_bernardo_pattern) y
> ruteado aquí en vez de al pipeline genérico de habilidades activadas.
> Opera sobre CardInspectionLayer via _inspector (y sobre el Main del juego
> via _inspector._main).
> Extraído de CardInspectionLayer.gd (2026-08-28, "módulos gordos").

### `_activate_bernardo_shuffle_removal` — línea 20

> 'Una vez por turno, puedes Barajar un Arma o Aliado Caballero de tu
> mano o que controles para Desterrar una carta de coste 3 o menos o
> cancelar una habilidad. No se pueden Barajar Aliados con Arma.' Texto
> confirmado por el usuario (2026-08-26) — la versión cacheada de la API
> trae la misma idea con las cláusulas reordenadas.

### `_activate_bernardo_shuffle_removal` — línea 52

> 2026-09-13, a pedido del usuario: click directo sobre la mano/campo en
> vez del modal de lista viejo.

### `_activate_bernardo_shuffle_removal` — línea 59

> source_card se usa después de este await (2026-09-13, bug real:
> "Invalid type... (previously freed)" al llamar _bernardo_banish_
> target). Mismo motivo ya documentado en HandCementerioAbilityHandler.
> gd: el await de arriba es tiempo real de espera del jugador — si
> Bernardo salió de juego mientras tanto (destruido/desterrado por
> cualquier vía), queda una referencia colgante.

### `_activate_bernardo_shuffle_removal` — línea 71

> "Una vez por turno" se marca solo ahora que el coste ya se pagó de
> verdad — mismo criterio que ActionPipeline.activate_ability() (Paso B).
> register_ability_use() usa el instance_id de source_card (2026-08-30),
> no card_data.id — cada copia física necesita su propio cupo.

### `_activate_bernardo_shuffle_removal` — línea 77

> 2026-09-19, a pedido explícito del usuario: ya NO se pregunta "Desterrar
> o Cancelar" con un diálogo — la rama se elige SOLA según el momento en
> que se usa Bernardo. En tu propio turno o en Guerra de Talismanes
> (proactivo, sin responder a nada puntual) siempre Desterrar; respondiendo
> a que el rival jugó una carta o usó una habilidad (ventana de respuesta
> real, §10.53) siempre Cancelar. Ver AbilityButtonSupport._is_responding_
> to_opponent_action(). _show_bernardo_effect_choice() queda huérfana (no
> borrada, ver su docstring) por si hace falta volver a una elección
> manual.

### `_bernardo_shuffle_into_deck` — línea 116

> 2026-10-14, bug real ("Trying to assign invalid previously freed
> instance" al Desterrar con Bernardo): Barajar como coste un Arma
> equipada la liberaba sin sacarla de equipped_weapons de su portador;
> el compact_all_fields() del Destierro leía esa referencia liberada.

### `_bernardo_banish_target` — línea 141

> Bernardo SÍ puede ser objetivo válido de su propio Destierro
> (2026-09-06, corregido: el usuario confirmó que puede desterrarse
> a sí mismo/a otra copia con nombre Bernardo con esta habilidad —
> nada en el texto lo prohíbe, revertido un intento anterior de
> excluirlo).

## `scripts/ui/inspection/CardInspectionLayer.gd`

### `(nivel de archivo)` — línea 7

> Manejadores de patrones especiales extraídos de este archivo (2026-08-30,
> "módulos gordos" — mismo corte que BernardoAbilityHandler/
> ResponseWindowHandler). preload() en vez del nombre de clase global: son
> scripts NUEVOS de esta sesión, el editor todavía no los escaneó para
> registrar su class_name (ver el mismo comentario sobre
> CardNameSearchDialogScript en TriggerSystem.gd) — referenciarlos por
> nombre tiraría "Could not find type" hasta el próximo reimport manual.

### `(nivel de archivo)` — línea 18

> Validación de habilidades ACTIVADAS + ciclo de vida del botón superpuesto,
> y los 4 grupos (por posición en el archivo original) del if-chain de
> patrones especiales de _build_ability_buttons() — extraídos de este mismo
> archivo (2026-09-06, "módulos gordos", Fase 2 — ver
> iterative-booping-abelson.md). Mismo motivo de preload() que arriba.

### `setup` — línea 88

> Signo Amarillo (2026-08-26): ventana de respuesta para triggers ETB de
> Oro/fuera del juego — separada de step_d_waiting (esa es para la Pila
> de habilidades activadas/cartas jugadas; los triggers automáticos
> tienen su propia señal en TriggerSystem).

### `refresh_activatable_glows` — línea 104

> Prende/apaga el brillo celeste de 'tiene una habilidad activable
> disponible ahora' en cada carta del jugador humano en juego — sin
> necesidad de abrir el panel de inspección. Reutiliza exactamente la
> misma detección y validación que _build_ability_buttons()/_validate_ability().
> Retorna true si quedó AL MENOS una carta brillando (2026-09-19, §10.52 —
> ver PhaseFlowController._on_priority_changed_glow(), que combina este
> valor con _human_has_instant_response_talisman_in_hand() para decidir si
> el auto-pase de Paso D espera los 5s reales o pasa casi al toque porque
> no hay nada que decidir).

### `refresh_activatable_glows` — línea 116

> 2026-09-19, arquitectura.md §10.11 caso 4 / §10.51: mismo criterio que
> _build_ability_buttons() — en turno rival, el brillo solo tiene sentido
> para Anular/Cancelar (única categoría ofrecida ahí durante una ventana
> de respuesta rival); el resto de las ACTIVATED no son respuesta
> instantánea real aunque técnicamente haya prioridad abierta.

### `refresh_activatable_glows` — línea 143

> Armas equipadas (2026-09-02, a pedido del usuario): son hijas del
> Aliado portador, no de player_field/player_linea_ataque directo, así
> que nunca aparecían aquí — su propia habilidad podía activarse bien
> (vive en el nodo del Arma, ajeno al estado de silenciado del
> portador), pero nunca se le prendía el brillo celeste de "tiene una
> habilidad activable disponible ahora".

### `refresh_activatable_glows` — línea 183

> Estas cartas ya están EN JUEGO (candidates viene solo de
> player_field/player_linea_ataque/player_gold) — mismo filtro que
> _build_ability_buttons() (2026-08-31): una habilidad 'de tu
> mano'/'de tu Cementerio' sin 'en juego' no tiene sentido aquí,
> aunque esté en la lista chica de _ability_is_hand_usable().

### `_open_card_inspection` — línea 217

> 2026-09-13, bug real reportado por el usuario: click derecho sobre un
> Aliado del rival "llega pero no hace nada" — el evento sí alcanzaba
> _on_card_right_clicked (confirmado con el print [DIAG] existente),
> pero esta función cortaba en silencio si ya había OTRA inspección
> abierta (p.ej. se había inspeccionado una carta de la mano un
> instante antes y no se cerró). Ahora cierra la anterior en vez de
> ignorar el click nuevo.

### `_open_card_inspection` — línea 243

> El clon no tiene la zona/dueño reales de 'card', así que sus propios
> badges recién creados en _ready() quedan con el valor base — forzamos
> el recálculo usando el contexto de la carta REAL (2026-08-31, corrige
> a Manuel Bulnes mostrando 1 de Fuerza menos al inspeccionarlo).

### `_build_gained_abilities_panel` — línea 263

> Habilidades ganadas de otras cartas (2026-10-17, Reina Nyssara: "gana
> las habilidades de esa carta"), apiladas a la derecha de la carta
> inspeccionada, una por carta de origen. Si alguna es una habilidad
> activada que puedes usar ahora, lleva su botón "Usar".

### `mark_inspection_layer_in_use` — línea 383

> Llamar SIEMPRE que algo agregue contenido visible a _main.inspection_layer
> (una inspección nueva, el diálogo de elección de Bernardo en
> BernardoAbilityHandler.gd, cualquier overlay futuro que la reutilice).
> 2026-09-13, bug real reportado por el usuario: el diálogo "Elige el
> efecto" de Bernardo (hijo de inspection_layer) no aparecía hasta hacer
> click derecho en otra carta — el cierre diferido de la inspección de
> Bernardo (close_card_inspection(), que espera ~0.2s de tween antes de
> apagar la capa) apagaba inspection_layer DESPUÉS de que el diálogo ya
> se hubiera agregado, dejándolo presente pero invisible. Forzar
> visible=true aquí cubre el caso en que el apagón YA pasó; el contador de
> generación en close_card_inspection() cubre el caso en que el apagón
> pasa DESPUÉS.

### `release_inspection_layer_if_unused` — línea 400

> Contraparte de mark_inspection_layer_in_use() — llamar cuando el
> contenido que forzó visible=true (p.ej. el diálogo "Elige el efecto"
> de Bernardo) YA se usó y no queda ninguna inspección real abierta.
> 2026-09-14, bug real reportado por el usuario: "al elegir Desterrar en
> Bernardo, el juego queda borroso y no puedo hacer nada" — mark_
> inspection_layer_in_use() dejaba inspection_layer (con su blur/backdrop
> de pantalla completa, mouse_filter STOP) forzado visible=true para
> mostrar el diálogo de elección, pero nada lo apagaba después: el único
> lugar que hace inspection_layer.visible=false es el tween diferido de
> close_card_inspection(), que ya había corrido ANTES de este diálogo
> (mismo timing documentado en mark_inspection_layer_in_use()). El blur
> seguía tapando la pantalla y tragándose todos los clicks (los mandaba a
> _on_inspection_blur_input(), que no hacía nada porque inspected_card ya
> era null) justo cuando BernardoAbilityHandler necesitaba que el jugador
> pudiera clickear una carta real del tablero para Desterrar/Cancelar.
> No apaga la capa si mientras tanto se abrió una inspección nueva de
> verdad (inspected_card != null) — mismo criterio de guardia que ya usa
> close_card_inspection().

### `_ability_is_hand_usable` — línea 449

> Lista chica y explícita de habilidades usables DESDE LA MANO (2026-08-30)
> — ver el comentario en _build_ability_buttons() sobre por qué no es un
> permiso genérico por la sola presencia de 'tu mano' en el texto.

### `_ability_is_cementerio_usable` — línea 473

> Lista chica y explícita de habilidades usables DESDE EL CEMENTERIO
> (2026-08-30, p.ej. Espada del Juicio: 'Puedes Desterrarla de tu
> Cementerio para que un Aliado gane o pierda 2 de Fuerza permanentemente')
> — mismo criterio que _ability_is_hand_usable(), un permiso chico y
> explícito en vez de genérico por la sola presencia de 'tu Cementerio'.

### `_ability_is_hand_or_cementerio_only` — línea 497

> true si esta habilidad está en la lista chica de _ability_is_hand_usable()/
> _ability_is_cementerio_usable() (usable desde la mano y/o el Cementerio,
> ANTES de jugar la carta) pero su propio texto NO incluye también 'en
> juego' — o sea, no tiene sentido una vez la carta ya está en juego
> (2026-08-31, p.ej. la primera habilidad de Tyet: 'esta y otra carta de
> tu mano en el fondo de tu Castillo', solo tiene sentido con Tyet
> literalmente en la mano; o la de cancelar ataque de Drácula: 'de tu
> mano o Cementerio', sin 'en juego'). Ramón Freire SÍ dice 'de tu mano o
> EN JUEGO' explícito, así que esa sigue disponible en ambos casos.
>
> REVERTIDO (2026-09-09, a pedido explícito del usuario): entre el
> 2026-08-31 y el 2026-09-06 hubo un vaivén con la segunda habilidad de
> Tyet ('esta y otra carta de tu mano en el fondo de tu Castillo') — se
> restringió a solo-mano, después se abrió también a Reserva de Oro
> razonando que 'esta' no implica zona. El usuario confirmó ahora que la
> restricción original (solo-mano) es la correcta — Tyet YA EN JUEGO no
> puede usar esta habilidad. Se sacó la excepción; vuelve a caer en la
> regla general de abajo (está en _ability_is_hand_usable(), su texto no
> dice 'en juego', así que da true = solo mano).

### `activate_ability_for` — línea 522

> Activa una habilidad con EXACTAMENTE la misma lógica que su botón en
> la inspección de carta (2026-10-12, a pedido del usuario: "todos los
> cambios siempre tienen que ser para el Remoto igual") — los 65 patrones
> especiales de AbilityButtonPatternsA-D (p.ej. Miguel) y, si ninguno
> aplica, la Pila genérica. Lo usa RemotePlayerController para que el
> Remoto no vaya por un camino distinto (antes iba directo a
> ActionPipeline y se salteaba esos patrones). Los patrones conectan su
> lógica al 'pressed' de un botón: aquí se arma un botón sin mostrar y se
> llama y espera (await) esa misma función.

### `_is_response_only_ability` — línea 557

> Cancelar un ATAQUE (Drácula, 2026-10-18): no responde a nada de la
> pila — se usa en Guerra de Talismanes, mientras los Aliados atacan.

### `usable_abilities_for` — línea 574

> Habilidades ACTIVADAS de esta carta que 'player_id' puede usar AHORA:
> [{ability, validation}]. Mismo filtro que los botones de la
> inspección (turno, prioridad, zona, Anular/Cancelar en turno rival,
> costo, una vez por turno) — 2026-10-12: extraído de
> _build_ability_buttons() y parametrizado por jugador para que el
> Remoto vea exactamente las mismas opciones que el Anfitrión.

### `usable_abilities_for` — línea 584

> 2026-09-19, arquitectura.md §10.11 caso 4: en tu propio turno, cualquier
> ACTIVATED puede mostrarse (el resto de la función/validate_ability sigue
> filtrando fase/costo). En el turno RIVAL, solo tiene sentido ofrecer el
> botón si además hay una ventana de prioridad real donde el humano puede
> actuar (PriorityManager.can_act(player_id)) — si no, ni vale la pena parsear
> habilidades. Cuál habilidad puntual se filtra más abajo (solo
> Anular/Cancelar durante el turno rival, ver is_own_turn en el loop).

### `usable_abilities_for` — línea 594

> controller_id, no owner_id (2026-08-29, a pedido del usuario): quién
> puede activar la habilidad de una carta es quién la CONTROLA, no
> necesariamente su dueño — importa para poder usar habilidades de una
> carta ajena que controlas (p.ej. jugada por Miguel desde el Cementerio
> rival). controller_id sigue a owner_id por defecto, así que para toda
> carta normal esto se comporta igual que antes.

### `usable_abilities_for` — línea 604

> Solo cartas EN JUEGO pueden activar habilidades (DAR) — sin esto,
> zoomear una carta en la mano con una habilidad "Una vez por turno"
> también mostraba el botón, aunque no tenía forma real de resolverse
> desde ahí (2026-08-28, reportado por el usuario). Excepción chica y
> explícita (2026-08-30, no un permiso genérico): algunas habilidades
> se pueden usar DESDE LA MANO o EL CEMENTERIO, antes de jugar la carta
> — p.ej. Ramón Freire ("Desterrarlo de tu mano o en juego..."), Tyet
> ("poner esta y otra carta de tu mano en el fondo de tu Castillo...")
> o Espada del Juicio ("Desterrarla de tu Cementerio..."). El chequeo
> real es POR HABILIDAD (más abajo, con el raw_text de CADA una), no
> aquí por carta entera — 2026-08-30, bug real encontrado con Tyet: solo
> UNA de sus dos habilidades es usable desde la mano (la otra necesita
> estar en Reserva de Oro), pero como el gate viejo era "toda la carta
> o nada", estando en la mano ofrecía IGUAL el botón de la que no
> correspondía — clickearlo fallaba con 'ya no está en tu Reserva'.
> Aquí solo se decide si la ZONA en sí es una de las permitidas; cuál
> habilidad puntual aplica se filtra en el loop de usable_abilities.

### `usable_abilities_for` — línea 627

> Terminal P-12 (2026-10-18): hasta dos habilidades de cartas fuera del
> juego por turno.

### `usable_abilities_for` — línea 631

> Silencio de Cementerio (2026-08-30, Sable de Napoleón) — 'pierde su
> habilidad' bloquea también las habilidades usables DESDE el
> Cementerio (p.ej. Espada del Juicio). No aplica a Mano/en juego, solo
> a cartas efectivamente marcadas mientras están en el Cementerio.

### `usable_abilities_for` — línea 655

> Escritura Sagrada (2026-10-18): jugar desde las dos primeras del Castillo.

### `usable_abilities_for` — línea 665

> Turno rival (§10.11 caso 4): solo Anular/Cancelar son respuesta
> instantánea real — el resto de las ACTIVATED (p.ej. 'Paga 1 Oro:
> roba una carta') no tiene sentido como reacción aunque técnicamente
> haya prioridad abierta, y su validate_ability() de todos modos no
> las filtraría por sí solo (no tienen restricción de fase propia).
> Excepción explícita dentro de la excepción: 'en tu turno, puedes...'
> (Tótem Dragón Ancestral) es Anular/Cancelar pero además restringido
> a tu propio turno por su propio texto — UniversalCardParser solo
> tagea once_per_turn_own_turn_only con la frase 'UNA VEZ en tu
> turno', así que sin este chequeo extra local (no se tocó el parser
> compartido a propósito, cambio más chico) _validate_ability() no lo
> habría filtrado.
> Guerra de Talismanes (2026-10-14, a pedido del usuario: Tyet,
> Estaca): los DOS jugadores juegan Talismanes y usan habilidades,
> no solo Anular/Cancelar — mientras la palabra sea de la propia
> Guerra (no una ventana de respuesta a algo puntual).

### `usable_abilities_for` — línea 686

> Solo de respuesta (2026-10-17, a pedido del usuario: Almirante
> Akari "no podría usar su habilidad cuando quiera"): si TODO lo que
> hace es Anular/Cancelar/prevenir, el botón aparece solo mientras
> respondes a algo del oponente (la prevención ya la ofrece el juego
> sola cuando corresponde).

### `usable_abilities_for` — línea 699

> 2026-08-31, corrección a pedido del usuario: el chequeo de zona
> de arriba solo corría cuando la carta NO estaba en juego — una
> vez en juego, CUALQUIER habilidad ACTIVATED pasaba sin más,
> aunque su propio texto dijera 'de tu mano'/'de tu Cementerio'
> SIN 'o en juego' (p.ej. la primera de Tyet o la de cancelar
> ataque de Drácula) — esas solo tienen sentido con la carta
> literalmente en esa zona, no ya jugada.

### `_build_ability_buttons` — línea 930

> Patrones especiales de habilidades activadas — extraídos a 4 archivos
> hermanos por posición en el archivo original (2026-09-06, "módulos
> gordos", Fase 2 — ver iterative-booping-abelson.md): cada grupo
> revisa el mismo tramo de condiciones que tenía aquí, en el MISMO
> ORDEN relativo (A, luego B, luego C, luego D), así que el primer
> match sigue ganando exactamente igual que antes de la extracción.
> Ver AbilityButtonPatternsA.gd/_B.gd/_C.gd/_D.gd.

### `_build_ability_buttons` — línea 953

> Validación de habilidades ACTIVADAS + ciclo de vida del botón superpuesto
> (creación visual, activación vía ActionPipeline, brillo de "habilidad en
> la pila") se movieron a AbilityButtonSupport.gd (2026-09-06, "módulos
> gordos", Fase 2) — ver _button_support, montado en setup().

### `_build_ability_buttons` — línea 958

> El caso especial de Bernardo O'Higgins (coste alternativo + elección de
> efecto con objetivo) se movió a BernardoAbilityHandler.gd (2026-08-28,
> "módulos gordos") — ver _bernardo, montado en setup().

### `_build_ability_buttons` — línea 962

> Ventanas de respuesta (Paso D genérico + Signo Amarillo) y
> _show_puedes_confirm() (sin llamadores, código muerto) se movieron a
> ResponseWindowHandler.gd (2026-08-28, "módulos gordos") — ver
> _response_window, montado en setup().

## `scripts/ui/inspection/HandCementerioAbilityHandler.gd`

### `(nivel de archivo)` — línea 2

> HandCementerioAbilityHandler — Patrones especiales de habilidades
> ACTIVADAS usables DESDE LA MANO o el CEMENTERIO, antes de jugar la carta
> (Tyet — 2 habilidades, Ramón Freire, Espada del Juicio, Drácula —
> cancela ataque, Estaca — robo+barajado). Detectados en
> CardInspectionLayer._build_ability_buttons() y ruteados aquí en vez de al
> pipeline genérico de habilidades activadas. Opera sobre CardInspectionLayer
> via _inspector (y sobre el Main del juego via _inspector._main).
> Extraído de CardInspectionLayer.gd (2026-08-30, "módulos gordos" — mismo
> corte que ya separó BernardoAbilityHandler/ResponseWindowHandler).

### `_activate_tyet_silence_and_pay` — línea 20

> 'Puedes pagar este Oro para que un Oro pierda su habilidad este turno
> y muévelo al Oro Pagado' (Tyet, 2026-08-29). Costo: esta misma carta (un
> Oro) se gasta como pago del turno — CostType.SELF_AS_GOLD, un concepto
> que ActionPipeline no conoce. Efecto sobre OTRO Oro elegido: pierde su
> habilidad SOLO este turno (KeywordManager.silence_card(..., 'turn') —
> se autolimpia sola al empezar el próximo turno, sin hook aparte) y se
> mueve a SU PROPIO Oro Pagado. 'un Oro' sin calificar (2026-08-31,
> corrige: el texto real no dice 'de tu Reserva' ni 'tuyo' — antes esta
> función restringía por error a la Reserva propia) — cualquier Oro en
> Reserva, propio o rival, ver [[project_no_zone_means_in_play]].
> GoldManager._mover_oro_a_pagado() ya resuelve la Reserva/Oro Pagado
> correctos según el controller_id del Oro elegido.

### `_activate_tyet_silence_and_pay` — línea 60

> 2026-09-06, bug real reportado por el usuario: validado 'source_card' UNA
> sola vez al entrar, pero el await de arriba es tiempo real de espera del
> jugador — si la carta salió de juego mientras el selector estaba abierto,
> quedaba una referencia colgante que crasheaba más abajo (turn_registry,
> _mover_oro_a_pagado). Mismo fix aplicado a todas las funciones de este
> archivo que usan 'source_card' después de un await.

### `_activate_tyet_mill_and_draw` — línea 76

> 'Puedes poner esta y otra carta de tu mano en el fondo de tu Castillo
> y Robar dos cartas' (Tyet). Solo usable DESDE LA MANO (2026-09-09,
> revertido a pedido explícito del usuario — hubo un vaivén: se restringió
> a solo-mano el 2026-08-31, se abrió también a Reserva de Oro el
> 2026-09-06 razonando que 'esta' no implica zona, y ahora se confirma que
> la restricción original era la correcta: Tyet ya en juego NO puede usar
> esta habilidad). Costo: esta misma carta + una elegida de la mano, ambas
> al FONDO del mazo (deck.append(), no pop_front() — el índice 0 es el
> tope).

### `_activate_tyet_mill_and_draw` — línea 103

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo.

### `_activate_sandraudiga_banish_pair_and_peek` — línea 131

> 'Puedes pagar un Oro para Desterrar este y otro Aliado Sacerdote de
> tu mano. Mira la mano de tu oponente, Destierra una carta que no sea
> Aliado ni Oro de ahí' (sandraudiga, 2026-09-06) — usable DESDE LA MANO
> (ver _ability_is_hand_usable()). 'Si está en tu Destierro, puedes
> Desterrar una carta de tu mano para Barajarlo en tu Castillo' NO
> implementado (necesitaría una categoría nueva de zona-usable: desde el
> Destierro).

### `_activate_sandraudiga_banish_pair_and_peek` — línea 159

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo.

### `_activate_sandraudiga_banish_pair_and_peek` — línea 168

> Ventana ANTES del auto-costo (2026-09-10): source_card se destierra a sí
> misma como parte del costo un poco más abajo, y open_response_window()
> exige que 'source_card' siga siendo un Node válido — abrirla aquí, con la
> carta todavía en la mano, es lo único seguro (después de esto queue_free()
> la invalida, y el picker de la mano rival que sigue tarda varios frames).

### `_activate_ramon_freire_banish_for_gold` — línea 223

> 'Si controlas Aliados de coste 2 o más, puedes Desterrarlo de tu mano
> o en juego para generar un Oro para jugar Armas. Sólo puedes utilizar
> la habilidad de Ramón Freire una vez por turno' (2026-08-30). Usable
> DESDE LA MANO o ya en juego (ver _ability_is_hand_usable()). Condición
> previa (controlar un Aliado de coste ≥2) que ActionPipeline no sabe
> verificar. Oro Virtual RESTRINGIDO — mismo mecanismo que Padre de la
> Patria (GoldManager.generar_oro_virtual_restringido).

### `_activate_ramon_freire_banish_for_gold` — línea 256

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador (ver
> arquitectura.md §33) — esta habilidad se desbloquea.

### `_activate_espada_juicio_banish_cemetery_for_buff` — línea 272

> 'Puedes Desterrarla de tu Cementerio para que un Aliado gane o
> pierda 2 de Fuerza permanentemente' (Espada del Juicio, 2026-08-30) —
> primera habilidad usable DESDE EL CEMENTERIO de esta sesión. source_card
> aquí es un Card node de SOLO VISTA (ZoneViewerModule lo arma fresco a
> partir de los datos crudos del Cementerio, no es el mismo objeto que
> vive en CardManager._zones[player_id].cemetery) — el costo (Desterrar)
> tiene que operar sobre el DATO real de esa lista, no sobre este nodo
> descartable. 'Permanentemente' con la Espada ya desterrada (fuente que
> ya no está en juego): el modificador se autorreferencia al Aliado
> elegido (source=target), dura mientras ÉL siga en juego — no tiene
> sentido atarlo a una fuente que ya no existe.

### `_activate_dracula_cancel_attacks` — línea 326

> 'Puedes Desterrarlo de tu mano o Cementerio para cancelar el ataque
> de hasta dos Aliados' (Drácula, 2026-08-30) — usable DESDE LA MANO o el
> CEMENTERIO (ver _ability_is_hand_usable()/_ability_is_cementerio_usable()).
> Costo sobre la carta REAL de la zona correspondiente (mismo criterio que
> _activate_espada_juicio_banish_cemetery_for_buff() para Cementerio,
> _activate_ramon_freire_banish_for_gold() para mano). Efecto: sacar hasta
> 2 Aliados de GameManager.attackers (cualquier bando — el texto no dice
> 'que controla tu oponente') y revertir su aspecto visual de 'atacando'
> vía CardInteractionModule.unmark_attackers(), sin pasar por
> undeclare_attacker() (ese exige que sea el turno del propio controlador
> del atacante).

### `_activate_dracula_cancel_attacks` — línea 350

> 2026-09-13, a pedido del usuario: click directo sobre los Aliados
> atacando en vez del modal de lista viejo.

### `_activate_dracula_cancel_attacks` — línea 354

> "su ataque no puede ser cancelado" (Ira, 2026-10-17; shade, 2026-10-18)

### `_activate_estaca_draw_and_shuffle` — línea 390

> 'Una vez por turno, puedes Robar tres cartas, Barajar una carta
> oponente que no sea Oro y tantas cartas de tu mano como coste tenga'
> (Estaca, 2026-08-30). La carta oponente no menciona zona — es EN JUEGO
> (regla general del proyecto: sin 'de tu mano'/'de tu Castillo' =
> sucede en juego), excluyendo Oro. El robo (3) es independiente y
> siempre ocurre; el barajado de la carta rival y el de tu propia mano
> (tantas cartas como el COSTE de esa carta rival) están LIGADOS: sin
> objetivo rival válido, ninguno de los dos barajados ocurre.

### `_activate_estaca_draw_and_shuffle` — línea 401

> Ventana única para toda la habilidad (2026-09-10): sin declare real
> todavía en este punto (el objetivo rival se elige solo más abajo) —
> se gatea aquí, al principio, igual que el resto de efectos compuestos
> sin un punto de declare limpio antes de arrancar.

### `_activate_estaca_draw_and_shuffle` — línea 452

> 2026-09-13, a pedido del usuario: click directo en la mano en vez
> del modal de lista viejo. Costo TODO o NADA de 'pick_amount'
> cartas exactas (mismo criterio que Belta, §10.19).

### `_activate_ouija_play_from_cemetery_or_deck_top` — línea 468

> 'Una vez por turno, puedes jugar una carta de tu Cementerio o del
> tope de tu Castillo. Juega mostrando la primera carta de tu Castillo.'
> (La Ouija, 2026-08-31 — carta promocional de 'IMP - Chile Oscuro 2', sin
> myl_id real: no está en la API externa — ver [[reference_myl_external_api]],
> el cache local es la única fuente para esta carta). 'de tu Cementerio' y
> 'del tope de tu Castillo' llevan posesivo (solo el propio, a diferencia
> de Miguel, cuyo 'un Cementerio' sin posesivo sí incluye el rival — ver
> _activate_miguel_discount_play() en SearchAbilityHandler.gd, mismo
> esqueleto de esta función). La segunda oración es el aviso de que jugar
> desde el tope revela esa carta al hacerlo — no hay sistema de revelado
> real conectado en este motor (mismo caso ya resuelto para Levisterio:
> 'puedes mostrar tu mano'), así que se deja constancia en el log en vez
> de abrir una UI de revelado nueva para un único caso. Reusa
> GoldManager.play_card() completo, igual que Miguel.

### `_activate_ouija_play_from_cemetery_or_deck_top` — línea 489

> 2026-09-13, a pedido del usuario: reemplaza el modal de lista viejo por
> click directo sobre cartas reales — un popup con las cartas del propio
> Cementerio MÁS una carta temporal extra representando 'el tope de tu
> Castillo' (revelada de una: el propio texto de La Ouija dice 'Juega
> mostrando la primera carta de tu Castillo', así que no hay nada oculto
> que preservar mostrándola en el picker). Todo vive en UN solo
> await_multi_target() — evita el problema de correr dos mecanismos de
> selección en carrera a la vez (ver arquitectura.md §10.14).

### `_activate_sacrificio_solar_self_shuffle_banish_or_shuffle` — línea 600

> 'Puedes pagar un Oro y Barajar esta carta desde tu mano para
> Desterrar o Barajar una carta de coste 2 o menos y Robar una carta'
> (Sacrificio Solar, 2026-09-02 — verificado contra la API, sin
> discrepancias con el cache local). Costo: 1 Oro + esta misma carta,
> barajada desde la mano de vuelta al Castillo (no destierro ni
> descarte — mismo mecanismo que Aaru/Manuel Bulnes: remove_card(...,
> true) + CardManager.get_deck().append() + shuffle_deck()). 'Una carta
> de coste 2 o menos' sin zona ni dueño = EN JUEGO, de cualquier lado
> (ver [[project_no_zone_means_in_play]]) — se elige el objetivo Y si
> termina Desterrado o Barajado, la misma elección para ambos efectos.
> 'Puedes X para Y' es atómico (ver [[project_puedes_x_para_y_atomic]]):
> no se ofrece nada si falta el Oro o no hay ningún objetivo válido —
> el pago y el autobarajado de esta carta se resuelven AL FINAL, después
> de resolver el objetivo, para no quedarse con una referencia a un nodo
> ya en cola de borrado mientras todavía hace falta.

### `_activate_sacrificio_solar_self_shuffle_banish_or_shuffle` — línea 621

> 2026-10-06: GoldManager.puede_pagar()/pagar_coste() ya son por jugador
> (ver arquitectura.md §33) — esta habilidad se desbloquea.

## `scripts/ui/inspection/PreventionAbilityHandler.gd`

### `(nivel de archivo)` — línea 2

> PreventionAbilityHandler — Facade de Patrones especiales de habilidades
> ACTIVADAS de protección/prevención y descuentos ligados a un Arma (Legión
> Paladín, Estaca — prevención, Drácula — autoconvertirse, Paladín
> Bestiarium — 2 habilidades, y todas las cartas agregadas 2026-09-06 en
> adelante). Detectados en CardInspectionLayer._build_ability_buttons() y
> ruteados aquí en vez de al pipeline genérico de habilidades activadas.
>
> Dividido en tres archivos por tamaño (2026-09-06, "módulos gordos" — mismo
> corte que ya separó SearchAbilityHandler.gd en SearchAbilityHandler_AI.gd/
> SearchAbilityHandler_JV.gd): PreventionAbilityHandler_AE.gd (A-E),
> PreventionAbilityHandler_EP.gd (E-P) y PreventionAbilityHandler_PV.gd
> (P-V). Este archivo queda como FACADE — cada función de abajo es un
> reenvío de una sola línea a la parte que corresponda, con el mismo nombre
> y firma de siempre, así que CardInspectionLayer.gd (único llamador, vía
> `_prevention_handler._activate_X(...)`) no necesitó cambiar una sola línea
> por este split.

## `scripts/ui/inspection/PreventionAbilityHandler_AE.gd`

### `(nivel de archivo)` — línea 2

> PreventionAbilityHandler_AE — Mitad A-E (alfabético por nombre de carta) de
> PreventionAbilityHandler.gd, dividido por tamaño (2026-09-06, "módulos
> gordos" — mismo corte que ya separó SearchAbilityHandler_AI.gd/
> SearchAbilityHandler_JV.gd del propio SearchAbilityHandler.gd). Ver
> PreventionAbilityHandler.gd para el facade que reune esta parte con
> PreventionAbilityHandler_EP.gd y PreventionAbilityHandler_PV.gd bajo los
> mismos nombres públicos que antes — CardInspectionLayer.gd no cambió una
> sola línea por este split. Opera sobre CardInspectionLayer via _inspector
> (y sobre el Main del juego via _inspector._main).

### `_activate_akari_banish_annul_non_ally` — línea 20

> 'Puedes Desterrarlo para Anular una carta de coste 1 o menos que no
> sea Aliado' (akari, 2026-09-04) — 'Anular' ~ destruir (misma
> simplificación usada en todo el proyecto), objetivo Arma/Tótem (no
> Aliado, no Oro) de coste efectivo ≤1.

### `_activate_akari_banish_annul_non_ally` — línea 34

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_akuma_banish_or_draw` — línea 52

> 'Una vez por turno, puedes Desterrar hasta dos cartas de los
> Cementerio o Roba una carta' (akuma el terrible, 2026-09-04) —
> elección A/B; 'los Cementerios' = ambos jugadores
> ([[project_no_zone_means_in_play]]).

### `_activate_akuma_banish_or_draw` — línea 64

> 2026-09-13, a pedido del usuario: click directo sobre ambos
> Cementerios en vez del modal de lista viejo — pool combinado, sin
> lock (mismo caso que Espada de O'Higgins, ver arquitectura.md
> §10.14/§10.19).

### `_activate_akuma_banish_or_draw` — línea 91

> _activate_almirante_akari_shuffle_annul_or_prevent() eliminada
> (2026-09-09, "sistema de respuestas" — corregido a pedido del usuario:
> Akari no es una elección A/B proactiva, son dos disparadores reactivos
> distintos). "Prevenir" ahora vive en EffectController._prevention_registry
> (mismo mecanismo que Estaca, solo Aliados); "Anular cuando el rival juega
> una carta" vive en EffectController.offer_counter_annul(), llamado desde
> GoldManager._trigger_enter_play()/EasyBotController._play_ally() justo
> después de que la carta jugada entra en juego. Ambas comparten el costo
> (barajar 1 carta propia) vía EffectController._pay_akari_shuffle_cost().

### `_activate_akuma_banish_or_draw` — línea 102

> _activate_angel_redentor_prevent() eliminada (2026-09-09, "sistema de
> respuestas"): ya no es un botón — EffectController.offer_prevention()
> la detecta y ofrece reactivamente (tags "annul"/"cancel"), con su propio
> candado de una vez por turno vía turn_registry en el 'is_available' del
> registro (ver EffectController.gd).

### `_activate_atenea_grant_double_damage_exile` — línea 110

> 'Una vez por turno, un Aliado hace doble daño de combate al
> Destierro este turno' (atenea en wonderland, 2026-09-04) — otorga
> Card.doubles_damage_to_exile TEMPORALMENTE (solo este turno) a un
> Aliado elegido (propio o rival, el texto no lo restringe), vía
> GameManager.turn_started para limpiarlo (mismo patrón que el Exhumar
> temporal de sumi el terrible).

### `_activate_atenea_grant_double_damage_exile` — línea 126

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_belta_barajar_desterrar` — línea 148

> 'Una vez por turno, Baraja y/o Destierra hasta dos cartas de los
> Cementerios' (Belta, 2026-09-04) — reusa GoldManager._resolve_armeria_
> barajar_desterrar() genérica, sin costo (a diferencia de Armería, aquí
> no hay condición previa).

### `_activate_belta_self_banish_revive` — línea 167

> 'Puedes Desterrar dos cartas de tu Cementerio para ponerlo en juego
> desde tu Cementerio como un Aliado sin habilidad de Fuerza 2' (Belta,
> 2026-09-04) — costo: desterrar 2 cartas CUALQUIERA de tu Cementerio
> (no incluye a Belta misma, que está siendo jugada desde ahí). Efecto:
> Belta deja de ser el Oro y pasa a ser un Aliado Fuerza 2 sin
> habilidad, en juego.

### `_activate_belta_self_banish_revive` — línea 188

> 2026-09-13, a pedido del usuario: click directo en vez del modal de
> lista viejo — 'tu Cementerio' (solo propio) + excluir a la propia
> Belta, lock_to_one_side=true de paso restringe al lado propio (mismo
> efecto que filtrar por owner, reutiliza el parámetro ya existente en
> vez de duplicar la exclusión en el filtro). Costo TODO o NADA: si
> cancela antes de elegir las 2, no se mueve nada (el picker no muta
> estado — solo aquí se toca el Cementerio).

### `_activate_campanita_banish_cancel_or_draw` — línea 224

> 'Puedes Desterrarlo para cancelar una habilidad o Robar dos cartas'
> (Campanita, 2026-09-04) — elección A/B. 'Cancelar la habilidad' ~
> silenciar (misma simplificación de Frankenstein/Red de Plata/Sheut),
> sin restricción de coste ni tipo (a diferencia de Frankenstein, que sí
> las tiene en su propio texto).

### `_activate_campanita_banish_cancel_or_draw` — línea 242

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_campanita_banish_cancel_or_draw` — línea 249

> Rama "roba dos": a diferencia de la de cancelar (protegida después por
> silence_card()), el Robo no tiene cobertura propia — la ventana va AQUÍ,
> antes del autodestierro de más abajo (2026-09-10), porque después
> source_card queda inválida para open_response_window().

### `_activate_crono_diamante_discard_ally_discount` — línea 269

> 'Una vez por turno, si jugaste un Aliado de coste 2 o más este
> turno puedes Descartar una carta para jugar un Aliado reduciendo su
> coste en un Oro, hasta un mínimo de 1' (Crono Diamante, 2026-09-02 —
> verificado contra la API, sin discrepancias con el cache local).
> Condición previa (GoldManager._play_card_to_field() registra
> 'played_ally_cost2plus:0' cada vez que se juega un Aliado de coste ≥2,
> sin importar el origen — mano/Exhumar/gratis). Costo: descartar 1
> carta CUALQUIERA de la mano. Efecto: jugar OTRA carta de la mano (un
> Aliado) con -1 Oro, piso 1 — a diferencia de Paladín Bestiarium
> (_activate_paladin_bestiarium_discard_weapon_discount(), mismo
> esqueleto), el texto NO dice 'hasta un mínimo de 0', así que
> allow_zero queda en false. 'Puedes X para Y' es atómico (2026-08-31,
> mismo criterio ya aplicado a Padre de la Patria/Paladín Bestiarium):
> solo se ofrecen como candidatas las Aliados que YA son pagables con
> el descuento aplicado, filtrado antes de preguntar qué descartar.

### `_activate_crono_diamante_discard_ally_discount` — línea 312

> 2026-09-13, a pedido del usuario: click directo en la mano en vez de
> los dos modales de lista viejos.

### `_activate_crono_diamante_discard_ally_discount` — línea 341

> _activate_dracula_convert_for_prevention() eliminada (2026-09-09,
> "sistema de respuestas"): ya no es un botón — EffectController.
> offer_prevention()/offer_prevention_for_player() detecta a Drácula
> (sin convertir, en juego) y ofrece reactivamente (tags "cancel"/"annul")
> en el momento exacto; el 'on_used' del registro hace el auto-convertir +
> silenciar que antes pasaba aquí.

### `_activate_dulce_canasta` — línea 350

> 'Una vez por turno, un Aliado gana o pierde 2 de Fuerza
> permanentemente' (Dulce Canasta, 2026-09-04). Sin costo. Cualquier
> Aliado en juego, propio o rival (sin calificador de dueño en el
> texto). 'permanentemente' = mismo molde que Espada del Juicio:
> source=target, sobrevive aunque Dulce Canasta salga de juego.

### `_activate_dulce_canasta` — línea 364

> Solo el débuff es prevenible (2026-09-09 — Estaca, tag "strength_change")
> — un buff no es un efecto hostil que valga la pena bloquear.

### `_activate_ereshkigal_banish_cost1_or_cemeteries` — línea 383

> 'Una vez por turno, puedes Desterrar una carta de coste 1 o menos o
> Barajar y/o Desterrar dos cartas de los Cementerios' (ereshkigal,
> 2026-09-04) — elección A/B; B reusa GoldManager._resolve_armeria_
> barajar_desterrar() genérica (ya generalizada para Belta/Perla de
> Sangre).

### `_activate_espada_ohiggins_shuffle_or_search_gold` — línea 410

> 'En tu Vigilia, una vez por turno, puedes Barajar una carta que no
> sea Oro o buscar un Oro en tu Castillo y ponerlo en tu mano' (Espada
> de O'Higgins, 2026-09-04) — elección A/B.
> 2026-09-14, a pedido del usuario: en vez de preguntar antes "¿qué
> quieres hacer?" con un diálogo A/B, ahora es una carrera de click
> directo (`CardInteractionModule.await_target_or_castillo_pick()`,
> mismo mecanismo ya usado por Sherlock Holmes/La Ouija — ver
> arquitectura.md §10.14): el Castillo PROPIO brilla como objetivo
> clickeable (buscar un Oro) AL MISMO TIEMPO que las cartas en juego que
> no sean Oro brillan como objetivo (barajar) — el primer click real
> decide cuál de las dos ramas resuelve; la otra deja de ofrecerse.
> `castillo_own_only=true` porque el texto dice 'tu Castillo' con
> posesivo (a diferencia de Sherlock Holmes, 'un Castillo' sin
> posesivo).

### `_activate_espada_ohiggins_shuffle_or_search_gold` — línea 431

> 2026-09-12 (bug real reportado por el usuario: no dejaba elegir un
> Aliado del rival — 5 clicks seguidos rechazados como "objetivo no
> válido"). El filtro comparaba c.get_parent() contra los contenedores
> de zona directo, en vez de current_zone (la propiedad que el motor
> ya usa para esto en todo el resto del código, p.ej.
> _select_convert_target()) — un Arma equipada, por ejemplo, es hija
> de su portador, no de la línea, así que ese chequeo de parent NUNCA
> la hubiera aceptado ni a ella ni a cualquier carta cuya jerarquía de
> nodos no calzara 1:1 con la zona lógica.

### `_activate_espiritu_maquina_shuffle_or_banish_cemetery` — línea 466

> 'Una vez por turno, puedes Barajar o Desterrar una carta de un
> Cementerio' (Espíritu de la Máquina, 2026-09-04) — 'un Cementerio' =
> elige CUÁL (propio o rival), no ambos ([[project_y_o_means_choose_one_zone]]
> mismo criterio aplicado a 'un' singular). Macu comparte el mismo texto
> ('Una vez en tu turno, ...') y este mismo handler (2026-09-07, bug real
> encontrado en auditoría: el diálogo de Barajar/Desterrar tenía el título
> 'Espíritu de la Máquina' hardcodeado, mostrándose igual cuando activaba
> Macu — ahora usa el nombre real de la carta).

### `_activate_espiritu_maquina_shuffle_or_banish_cemetery` — línea 480

> 2026-09-13, a pedido del usuario: click directo con ambos Cementerios
> visibles en vez de preguntar antes "¿en cuál?" — "un Cementerio"
> (elige uno) se resuelve con lock_to_one_side=true, mismo criterio que
> Hanta el Samurai (aunque aquí el tope es 1 carta, el lock no cambia
> nada práctico salvo dejar el resto sin brillo tras el primer click).

## `scripts/ui/inspection/PreventionAbilityHandler_EP.gd`

### `(nivel de archivo)` — línea 2

> PreventionAbilityHandler_EP — Mitad E-P (alfabético por nombre de carta) de
> PreventionAbilityHandler.gd, dividido por tamaño (2026-09-06, "módulos
> gordos" — mismo corte que ya separó SearchAbilityHandler_AI.gd/
> SearchAbilityHandler_JV.gd del propio SearchAbilityHandler.gd). Ver
> PreventionAbilityHandler.gd para el facade que reune esta parte con
> PreventionAbilityHandler_AE.gd y PreventionAbilityHandler_PV.gd bajo los
> mismos nombres públicos que antes — CardInspectionLayer.gd no cambió una
> sola línea por este split. Opera sobre CardInspectionLayer via _inspector
> (y sobre el Main del juego via _inspector._main).

### `setup` — línea 19

> _activate_estaca_banish_for_prevention() eliminada (2026-09-09, "sistema
> de respuestas"): Estaca ya no se activa por botón — EffectController.
> offer_prevention() (registro en EffectController.gd) la detecta y ofrece
> reactivamente en el momento exacto en que un efecto rival amenaza a una
> carta, con el mismo costo (autodestierro) resuelto en su 'on_used'.

### `_activate_frankenstein_discard_silence_turn` — línea 27

> 'Una vez por turno, puedes Descartar una carta para que una carta
> pierda su habilidad por el turno' (Frankenstein o El Moderno
> Prometeo, 2026-09-04). Costo: descartar 1 carta CUALQUIERA. Objetivo:
> cualquier carta en juego, sin restricción de tipo/coste. Duración:
> solo este turno (KeywordManager.silence_card(..., 'turn')).

### `_activate_frankenstein_discard_silence_turn` — línea 43

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_frankenstein_discard_silence_turn` — línea 54

> 2026-09-13, a pedido del usuario: click directo en la mano (ya son
> Nodos visibles, sin popup) en vez del modal de lista viejo. Filtro
> restringido a owner_id (mismo bug que gran kraken, ver más abajo).

### `_activate_frankenstein_pay_shuffle_cancel` — línea 70

> 'En tu turno, puedes pagarlo y Barajar una carta de tu mano para
> cancelar la habilidad de un Oro o carta de coste 2 o menos'
> (Frankenstein o El Moderno Prometeo, 2026-09-04). Costo: gastar este
> Oro (a Oro Pagado, GoldManager._mover_oro_a_pagado(), mismo mecanismo
> que Tyet) + barajar 1 carta de la mano. Efecto: la objetivo pierde su
> habilidad de forma permanente ('cancela la habilidad' ~ silenciar,
> misma simplificación ya usada en Red de Plata/Sheut).

### `_activate_frankenstein_pay_shuffle_cancel` — línea 93

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_frankenstein_pay_shuffle_cancel` — línea 104

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (mismo bug que
> gran kraken, ver más abajo).

### `_activate_gran_kraken_discard_destroy` — línea 125

> 'Una vez en tu turno, puedes Descartar una carta para Destruir una
> carta de coste 3 o menos' (gran kraken, 2026-09-04). Costo: Descartar 1
> carta propia. Efecto: destruir una carta (Aliado/Arma/Tótem) de coste
> efectivo ≤3.

### `_activate_gran_kraken_discard_destroy` — línea 139

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (2026-09-30, bug
> real encontrado al convertir más cartas): sin esto, current_zone ==
> MANO solo también deja elegir cartas de la mano del RIVAL.

### `_activate_kuchiku_kan_discard_to_disable` — línea 161

> 'Una vez por turno, puedes Descartar una carta para que una carta
> pierda su habilidad y no pueda atacar ni bloquear mientras este Aliado
> esté en juego' (Kuchiku Kan, 2026-09-03). 'Una carta' sin zona (DAR:
> sin zona explícita = en juego, [[project_no_zone_means_in_play]]) —
> cualquier carta en juego de cualquier jugador, no solo Aliados (Armas/
> Tótems/Oros también pueden 'perder su habilidad'; 'no pueda atacar ni
> bloquear' solo tiene efecto real sobre Aliados, pero no hace falta
> filtrar por tipo para el resto — simplemente no cambia nada visible).
> Costo: descartar 1 carta CUALQUIERA de la mano, sin relación con el
> objetivo. Efecto ligado a que ESTE Aliado se quede en juego: pérdida de
> habilidad vía KeywordManager.lock_ability_by_instance() (nuevo,
> 2026-09-03 — NO el 'permanent' de silence_card(), que es indefinido de
> verdad) + dos modificadores RESTRICTION (CANT_ATTACK/CANT_BLOCK) con
> duration PERMANENT y source=source_card, que Continuous
> EffectManager._is_modifier_active() ya trata como 'mientras la fuente
> siga en juego'. El bloqueo de ataque queda realmente wireado (Turn
> Manager.can_attack() consulta ContinuousEffectManager.can_attack());
> el de bloqueo queda como dato correcto a la espera de que exista un
> flujo real de declarar bloqueadores (ver docs/audit — GameManager.
> declare_blocker()/blockers no está conectado a ninguna UI todavía).

### `_activate_kuchiku_kan_discard_to_disable` — línea 194

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_kuchiku_kan_discard_to_disable` — línea 206

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (mismo bug que
> gran kraken).

### `_activate_kuchiku_kan_discard_to_disable` — línea 215

> lock_ability_by_instance()/las 2 restricciones CANT_ATTACK-CANT_BLOCK de
> abajo NO pasan por silence_card() ni por ningún choque protegido por
> Prevención (2026-09-10) — a diferencia del resto de esta familia de
> handlers, aquí sí corresponde la ventana genérica.

### `_activate_lanza_argenta_destroy_self_cancel_or_draw` — línea 238

> 'Puedes Destruir esta Arma para cancelar una habilidad o Robar tres
> cartas' (lanza argenta, 2026-09-04) — autodestrucción (va al
> Cementerio, no al Destierro).
>
> 2026-09-19, a pedido del usuario (mismo criterio que Bernardo O'Higgins,
> ver AbilityButtonSupport._is_responding_to_opponent_action()): ya NO se
> pregunta con un diálogo A/B — la rama se elige sola según el momento.
> Respondiendo a que el rival jugó una carta o usó una habilidad (ventana
> de respuesta real) → Cancelar. En tu turno o en Guerra de Talismanes
> (proactivo) → Robar tres.

### `_activate_lanza_argenta_destroy_self_cancel_or_draw` — línea 260

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_lanza_argenta_destroy_self_cancel_or_draw` — línea 267

> Rama "roba tres": a diferencia de la de cancelar (protegida después por
> silence_card()), el Robo no tiene cobertura propia — la ventana tiene
> que abrirse AQUÍ, antes de la autodestrucción de más abajo (2026-09-10):
> source_card se destruye a sí misma como costo, y open_response_window()
> exige que siga siendo un Node válido.

### `_activate_lanza_argenta_destroy_self_cancel_or_draw` — línea 287

> _activate_legion_paladin_prevention() eliminada (2026-09-09, "sistema de
> respuestas"): igual que Estaca — ya no es un botón, EffectController.
> offer_prevention() la detecta y ofrece reactivamente (tag "leave_play").

### `_activate_nu_galahad_look_play_weapon_and_ally_free` — línea 293

> 'Una vez por turno, mira tantas cartas del tope de tu Castillo como
> Armas controles, juega un Arma y un Aliado de Fuerza 4 o menos de ahí,
> sin pagar su coste y Baraja el resto' (nu-galahad el bastion,
> 2026-09-05) — 'Armas controles' cuenta TODAS las equipadas en
> cualquiera de tus Aliados, no solo las de esta carta.

### `_activate_nu_galahad_wear_cemetery_as_weapons` — línea 350

> 'Una vez por turno, porta hasta tres cartas de un Cementerio como
> Armas sin habilidad' (nu-galahad el bastion, 2026-09-05) — 'porta' sin
> otro sujeto = ÉL mismo las porta (coherente con su pasivo 'Tus
> Aliados no tienen límite de Armas', ya moot: el motor no impone
> ningún límite de Armas por Aliado de por sí). Convierte cada carta
> elegida en un Arma sin habilidad (is_converted + silence_card, mismo
> mecanismo de conversión real usado en todo el proyecto) y la equipa
> de verdad vía GoldManager._equip_weapon().

### `_activate_nu_galahad_wear_cemetery_as_weapons` — línea 365

> 2026-09-13, a pedido del usuario: click directo con ambos Cementerios
> visibles en vez de preguntar antes "¿de cuál?" — 'un Cementerio'
> (singular, sin posesivo) sigue significando "uno solo, no mezcles"
> (mismo criterio que Hanta el Samurai, arquitectura.md §10.14), ahora
> resuelto con lock_to_one_side=true en vez de _choose_search_zone_owner().

### `_activate_paladin_bestiarium_discard_weapon_discount` — línea 397

> 'Una vez por turno, puedes Descartar una carta para jugar un Arma de
> tu mano reduciendo su coste en un Oro, hasta un mínimo de 0' (Paladín
> Bestiarium, 2026-08-30). Costo: descartar 1 carta CUALQUIERA de la
> mano — no tiene que ser el Arma que se juega. Efecto: jugar OTRA carta
> de la mano (un Arma) con -1 Oro (piso 0), mismo mecanismo puntual que
> 'Muestra X para reducir el coste' (El Rey y el Verdugo,
> GoldManager.play_card()).
>
> 'Puedes X para Y' es atómico (2026-08-31, reportado por el usuario: con
> 0 Oro en Reserva, intentar jugar un Arma de coste 2 con esta habilidad
> igual descartaba la carta de costo aunque play_card() rechazara el Arma
> después por Oro insuficiente — el jugador perdía la carta descartada
> sin obtener nada. Ver [[project_puedes_x_para_y_atomic]], mismo criterio
> ya aplicado a Padre de la Patria/Lobo Sagrado/Espada Vikinga): solo se
> ofrecen como candidatas las Armas que el jugador YA puede pagar con el
> descuento de -1 aplicado (piso 0), y esa asequibilidad se filtra ANTES
> de pedir qué carta descartar — no después.

### `_activate_paladin_bestiarium_discard_weapon_discount` — línea 436

> 2026-09-13, a pedido del usuario: click directo en la mano en vez de
> los dos modales de lista viejos.

### `_activate_paladin_bestiarium_weapon_annul` — línea 467

> 'Una vez en tu turno, puedes Descartar o subir un Arma que controles
> a la mano para Anular una carta de coste 1 o menos' (Paladín
> Bestiarium, 2026-08-30). Costo: elegir un Arma que controles (en
> cualquiera de tus Aliados) y decidir si se descarta o vuelve a la
> mano. Efecto: Anular una carta en juego (Aliado/Arma/Tótem, de
> cualquier jugador) de coste ≤1 — mismo destino por defecto que
> _execute_targeted_annul() (Cementerio; Destierro solo si esta carta
> dijera 'destiérrala', que no es el caso aquí).

### `_activate_paladin_bestiarium_weapon_annul` — línea 494

> 2026-09-13, a pedido del usuario: click directo sobre las Armas
> equipadas en vez del modal de lista viejo.

### `_activate_paladin_bestiarium_weapon_annul` — línea 515

> Desvincular del Aliado portador ANTES de mandarla al Cementerio
> (2026-08-30) — CardManager.add_card_to_cemetery() no sabe de
> equipped_weapons, así que sin esto el Aliado se quedaba con una
> referencia colgante a un nodo ya liberado.

## `scripts/ui/inspection/PreventionAbilityHandler_PV.gd`

### `(nivel de archivo)` — línea 2

> PreventionAbilityHandler_PV — Mitad P-V (alfabético por nombre de carta) de
> PreventionAbilityHandler.gd, dividido por tamaño (2026-09-06, "módulos
> gordos" — mismo corte que ya separó SearchAbilityHandler_AI.gd/
> SearchAbilityHandler_JV.gd del propio SearchAbilityHandler.gd). Ver
> PreventionAbilityHandler.gd para el facade que reune esta parte con
> PreventionAbilityHandler_AE.gd y PreventionAbilityHandler_EP.gd bajo los
> mismos nombres públicos que antes — CardInspectionLayer.gd no cambió una
> sola línea por este split. Opera sobre CardInspectionLayer via _inspector
> (y sobre el Main del juego via _inspector._main).

### `_open_cemetery_reveal_popup_oro` — línea 22

> Popup liviano (sin oscurecer el resto de la pantalla, mano sigue
> clickeable) mostrando los Oros del Cementerio propio como Nodos
> temporales interactivos — mismo patrón que GoldManagerTax._open_
> cemetery_reveal_popup() (2026-09-13, El Rey y el Verdugo/Shiji, ver
> arquitectura.md §10.17), usado aquí para Sake ('Oro de tu mano o
> Cementerio'). Returns: {popup: CanvasLayer, nodes: Array[Node]}.

### `_activate_perla_de_sangre_convert_barajar_desterrar_draw` — línea 37

> 'Puedes convertirlo en un Oro sin habilidad para Barajar y/o
> Desterrar hasta cuatro cartas de los Cementerios y Robar hasta dos
> cartas' (Perla de Sangre, 2026-09-04). Costo: convertirse (is_converted
> + silenciarse permanentemente, mismo molde que Capitán O'Brien).
> Efecto: reusa GoldManager._resolve_armeria_barajar_desterrar(4) +
> Roba hasta 2 (ActionModule.draw ya maneja un mazo con menos cartas
> disponibles sin problema).

### `_activate_perla_de_sangre_search_hand_or_play` — línea 58

> 'En tu Vigilia, una vez por turno, puedes pagarlo para buscar en tu
> Castillo un Aliado y ponerlo en tu mano o jugarlo reduciendo su coste
> en un Oro, hasta un mínimo de 1' (Perla de Sangre, 2026-09-04). Costo:
> gastar este Oro (GoldManager._mover_oro_a_pagado()). Efecto: buscar un
> Aliado en el Castillo y elegir entre ponerlo en la mano o jugarlo con
> -1 Oro (piso 1, allow_zero=false — el texto NO dice 'hasta un mínimo
> de 0').

### `_activate_perla_de_sangre_search_hand_or_play` — línea 85

> Ventana única para todo lo que sigue (2026-09-10): la rama "jugarlo" ya
> queda cubierta por play_card() más abajo (CARD_PLAYED), pero la rama "a
> la mano" no tiene ninguna cobertura propia — se gatea AQUÍ, antes de
> sacar la carta encontrada del Castillo, para no tener que revertir una
> búsqueda ya completa si se anula después.

### `_activate_piruquina_pay_bottom_deck_prevent` — línea 115

> 'Si está en tu mano, puedes pagar un Oro y ponerlo en el fondo de tu
> Castillo para reducir a cero el próximo daño a tu Castillo' (Piruquina,
> 2026-09-04) — costo: 1 Oro real (PaymentManager). Efecto: ella misma
> va al fondo del Castillo (no al Cementerio) y se registra una
> prevención de daño total, un solo uso (DamageManager.
> add_damage_prevention, amount=-1/one_shot=true).

### `_activate_piruquina_pay_bottom_deck_prevent` — línea 130

> 2026-10-06: GoldManager.puede_pagar()/pagar_coste() ya son por jugador
> (ver arquitectura.md §33) — esta habilidad se desbloquea.

### `_activate_piruquina_pay_bottom_deck_prevent` — línea 138

> Ventana ANTES de que se vaya al fondo del Castillo (2026-09-10): después
> de remove_card(..., true) queda inválida para open_response_window().

### `_activate_quantum_megumi` — línea 151

> 'Una vez por turno, Baraja una carta de tu mano para Barajar hasta
> tres cartas de tu Cementerio y Robar una carta' (Quantum Megumi,
> 2026-09-04). Costo: barajar 1 carta CUALQUIERA de la mano al Castillo.
> Efecto: elegir hasta 3 cartas del propio Cementerio para barajar de
> vuelta, y robar 1.

### `_activate_quantum_megumi` — línea 164

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (mismo bug que
> gran kraken, ver PreventionAbilityHandler_EP.gd).

### `_activate_quantum_megumi` — línea 185

> 2026-09-13: click directo en el propio Cementerio en vez del modal
> de lista viejo.

### `_activate_quimera_voragh_banish_annul_talisman_draw` — línea 212

> 'Puedes Desterrarlo para Anular un Talismán de coste 1 o menos y
> Roba una carta' (quimera voragh, 2026-09-06) — mismo molde que akari
> (auto-Destierro como costo + Anular ~ destruir un objetivo de coste
> efectivo ≤1), aquí el objetivo es un Talismán específicamente y se suma
> un Robo al final. Los Talismanes se resuelven y van al Cementerio de
> inmediato (DAR Sección 8), así que 'un Talismán' en juego solo tiene
> sentido durante su propia ventana de resolución — en la práctica el
> objetivo real disponible normalmente es uno YA en el Cementerio/
> Destierro esperando Exhumar, pero el texto no lo dice explícito, así
> que el filtro busca en las mismas zonas de campo que el resto de estos
> patrones por consistencia.

### `_activate_quimera_voragh_banish_annul_talisman_draw` — línea 233

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_quimera_voragh_banish_annul_talisman_draw` — línea 240

> Ventana ANTES del autodestierro (2026-09-10): el Robo de más abajo no
> tiene cobertura propia, y después de banish() source_card ya no sirve
> como referencia válida para open_response_window().

### `_activate_sake` — línea 257

> 'En tu Vigilia, una vez por turno, si no controlas más Oros que tu
> oponente, puedes pagar un Oro para poner un Oro en juego desde tu mano
> o Cementerio' (Sake, 2026-09-04). Condición: tu total de Oros
> (Reserva+Oro Pagado) <= el del oponente. Costo: pagar 1 Oro. Efecto:
> elegir un Oro de tu mano o Cementerio y ponerlo directo en tu Reserva
> (GoldManager.put_gold_directly_in_reserva() — DAR 'poner en juego', no
> 'jugar', ver [[reference_myl_external_api]] y la conversación con el
> usuario 2026-09-04 sobre 'jugar' vs 'poner en juego').
>
> 'Tu oponente debe pagar un Oro adicional para afectar a tus demás
> Oros' queda SIN implementar: sería un impuesto sobre AFECTAR (targeting
> de un efecto ajeno), no sobre JUGAR — un tipo de restricción que este
> motor no modela todavía (los impuestos existentes, Bernardo O'Higgins/
> Fuente de la Juventud, son siempre sobre jugar/usar una habilidad
> propia, nunca sobre que el rival te apunte).

### `_activate_sake` — línea 288

> 2026-10-06: GoldManager.puede_pagar()/pagar_coste() ya son por jugador
> (ver arquitectura.md §33) — esta habilidad se desbloquea.

### `_activate_sake` — línea 296

> 2026-09-13, a pedido del usuario: click directo — mano (Nodos ya
> visibles) + un popup liviano con el Cementerio propio (mismo patrón
> que El Rey y el Verdugo, arquitectura.md §10.17), en vez del modal de
> lista viejo combinando ambas zonas.

### `_activate_shub_niggurath_gold_for_totem_draw` — línea 340

> 'En tu Vigilia, una vez por turno, puedes generar un Oro para jugar
> un Tótem de coste 2 o más y Robar una carta' (Shub-Niggurath,
> 2026-09-04).

### `_activate_shub_niggurath_gold_for_totem_draw` — línea 355

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador (ver
> arquitectura.md §33) — esta habilidad se desbloquea.

### `_activate_shub_niggurath_shuffle_or_mill_opponent` — línea 362

> 'Una vez en tu turno, Baraja una carta de coste 3 o menos o tu
> oponente Bota dos cartas por cada Aliado y/o Tótem que controles'
> (Shub-Niggurath, 2026-09-04) — elección A/B.

### `_activate_shub_niggurath_shuffle_or_mill_opponent` — línea 377

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_skofnung_shuffle_self_search_gold` — línea 405

> 'Puedes Barajarla de tu mano para buscar un Oro en tu Castillo y
> ponerlo en tu mano' (skofnung, 2026-09-04) — costo: ella misma vuelve
> al mazo (barajada) desde la mano.

### `_activate_skofnung_shuffle_self_search_gold` — línea 416

> Ventana ANTES del autobarajado (2026-09-10): sin esto, source_card queda
> inválida (remove_card(..., true)) para cuando haría falta abrirla.

### `_activate_sumi_discard_grant_exhumar` — línea 430

> 'Puedes Descartarlo de tu mano para que una carta de coste 1 en tu
> Cementerio gane Exhumar por el turno' (sumi el terrible, 2026-09-04) —
> habilidad usable desde la MANO (esta carta se descarta a sí misma como
> costo). Exhumar temporal: se agrega al array 'keywords' del propio
> Dictionary de datos en el Cementerio (ExhumarSystem._card_has_exhumar()
> ya lo detecta ahí) y se saca al terminar el turno.

### `_activate_sumi_discard_grant_exhumar` — línea 441

> 2026-09-13, a pedido del usuario: click directo en el propio
> Cementerio en vez del modal de lista viejo.

### `_activate_sumi_discard_grant_exhumar` — línea 452

> Ventana ANTES del autodescarte (2026-09-10): después de discard(),
> source_card queda inválida para open_response_window().

### `_activate_torre_babel_shuffle_hand_for_cemeteries_draw` — línea 481

> 'Una vez por turno, puedes Barajar una carta de tu mano para
> Barajar y/o Desterrar hasta cinco cartas de los Cementerios y Robar
> dos cartas' (Torre de Babel, 2026-09-04).

### `_activate_torre_babel_shuffle_hand_for_cemeteries_draw` — línea 494

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (mismo bug que
> gran kraken, ver PreventionAbilityHandler_EP.gd).

### `_activate_totem_dragon_ancestral_shuffle_self_annul_or_cancel` — línea 518

> 'En tu turno, puedes Barajarlo para Anular un Aliado o cancelar una
> habilidad' (Tótem del Dragón Ancestral, 2026-09-04) — autobarajar
> (vuelve al Castillo del dueño), elección A/B.

### `_activate_totem_dragon_ancestral_shuffle_self_annul_or_cancel` — línea 536

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_totem_dragon_ancestral_shuffle_self_annul_or_cancel` — línea 541

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_uriel_shuffle_banish_draw_discard` — línea 567

> 'Una vez por turno, Baraja y/o Destierra hasta tres cartas de los
> Cementerios, Roba una carta y Destierra una carta de tu mano' (uriel,
> 2026-09-04) — reusa GoldManager._resolve_armeria_barajar_desterrar()
> genérica para la primera cláusula, luego Roba 1 y Destierra 1 de la
> propia mano (elegida por el jugador).

### `_activate_uriel_shuffle_banish_draw_discard` — línea 585

> 2026-09-13, a pedido del usuario: click directo en la mano en vez
> del modal de lista viejo. Filtro restringido a owner_id (mismo
> bug que gran kraken, ver PreventionAbilityHandler_EP.gd).

### `_activate_vision_heroica_pay_raise_draw` — línea 604

> 'Puedes pagar un Oro para subir esta carta de tu Cementerio a tu
> mano y Robar una carta' (vision heroica, 2026-09-06) — usable desde el
> Cementerio.

### `_activate_vision_heroica_pay_raise_draw` — línea 613

> 2026-10-06 (ver arquitectura.md §33): GoldManager.puede_pagar()/
> pagar_coste() ya son por jugador — esta habilidad se desbloquea.

## `scripts/ui/inspection/ResponseWindowHandler.gd`

### `(nivel de archivo)` — línea 3

> ResponseWindowHandler — Overlays de "ventana de respuesta": Paso D
> genérico (ActionPipeline.step_d_waiting, para habilidades activadas/cartas
> jugadas en la Pila) y el caso especial de Signo Amarillo (2026-08-26,
> TriggerSystem.waiting_for_responses, para triggers ETB de Oro/fuera del
> juego — señal separada porque TriggerResolution._wait_for_response_window()
> solo la emite cuando de verdad hay algo que pueda responder).
> Opera sobre CardInspectionLayer via _inspector (y sobre el Main del juego
> via _inspector._main).
> Extraído de CardInspectionLayer.gd (2026-08-28, "módulos gordos").

### `_on_step_d_waiting` — línea 21

> Pila de Respuesta Universal (2026-09-09, Capa 1 — ver docs/plans/
> 2026-09-09-pila-respuesta-universal-design.md): con la migración de los
> patrones de trigger, esta ventana ya puede abrirse para CUALQUIERA de
> los dos jugadores (antes, en la práctica, priority_player siempre
> terminaba siendo el humano, porque nada disparado por el bot llegaba
> hasta aquí). Si le toca al bot, todavía no tiene ninguna lógica real de
> "¿quiero responder con algo?" (Capa 2, pendiente) — pasa siempre, pero
> por el camino REAL de PriorityManager (no el auto-pase ciego de antes),
> para no romper la secuencia de "ambos pasan consecutivamente" que
> ActionPipeline espera.

### `_on_step_d_waiting` — línea 32

> 2026-10-11: un jugador Remoto real decide por su cuenta (lo maneja
> PhaseFlowController._on_priority_changed_bot_autopass() →
> RemotePlayerController.on_priority_received()) — sin este return
> había dos caminos pasando por él a la vez.

### `_on_step_d_waiting` — línea 38

> 2026-09-15: se captura la generación de ESTA ventana (ver
> PriorityManager._window_generation) — mismo motivo que
> PhaseFlowController._human_pass_after(), ver ese comentario.

### `_on_step_d_waiting` — línea 44

> 2026-09-11 (a pedido del usuario): el botón único ¿Paso?/Atacar del HUD
> (GameHUDModule) ya se pone visible y brilla solo apenas la prioridad es
> tuya, y PhaseFlowController._on_priority_changed_glow() ya se encarga
> del auto-pase "no hay nada que decidir" — dejó de hacer falta un panel
> propio aquí solo para pasar. Lo único que sigue necesitando UI propia es
> la oferta de Signo Amarillo (cancelar convirtiendo un Oro): es una
> decisión real, así que se ofrece como diálogo reactivo, y suprime ese
> auto-pase mientras espera tu click (ver _offer_signo_amarillo_for_step_d).

### `_offer_signo_amarillo_for_step_d` — línea 60

> Suprime cualquier auto-pase "no hay nada que decidir" mientras este
> diálogo real está esperando un click — ver PriorityManager.
> suppress_human_autopass (2026-09-11).
>
> 'scheduled_for_generation' (mismo motivo que _bot_pass_after(), ver su
> comentario): si se abre una ventana NUEVA mientras este diálogo
> esperaba el click (dos oportunidades de Signo Amarillo seguidas), esa
> ventana nueva puede haber puesto suppress_human_autopass=true para SU
> PROPIO diálogo — resetearlo sin este chequeo lo apaga por debajo.

### `_bot_pass_after` — línea 89

> Capa 2 de la Pila de Respuesta Universal (2026-09-09): antes de pasar,
> el bot intenta responder de verdad con una habilidad activada propia
> (ver EasyBotController.try_respond_with_activated_ability(), alcance v1
> documentado ahí) — Prevención se maneja aparte, en su propio choke point
> (EffectController.offer_prevention_for_player()), no aquí. Si usó algo,
> ese objeto ya quedó en el tope de ActionPipeline y el propio loop de
> StackStepResolver lo detecta solo como "hubo respuesta" — no corresponde
> pasar. Si no, pasa por el camino REAL de PriorityManager (no un atajo
> que ignore de quién es el turno), con un pequeño delay solo para que no
> se sienta instantáneo/confuso en pantalla — sin ninguna intención de
> ocultar información (el usuario confirmó que el timing contra el bot no
> importa).
> 'scheduled_for_generation' (2026-09-15, bug real reportado por el
> usuario: "se traba en Guerra de Talismanes" sin ningún click — ver
> PriorityManager._window_generation): si la ventana para la que se
> programó este timer ya cerró y se abrió una ventana NUEVA antes de que
> termine la espera, no hay que tocarla — aunque priority_window_active
> siga siendo true, es de la ventana NUEVA, no la que este timer estaba
> mirando.

### `_qualifies_for_signo_amarillo` — línea 123

> ¿La fuente de este objeto de la Pila es un Oro, o una carta fuera del
> juego (Mano/Destierro/Cementerio/Castillo)? Esas dos categorías son las
> que Signo Amarillo puede cancelar (2026-08-26, texto real de la carta).

### `_on_trigger_waiting_for_responses` — línea 154

> Ventana de respuesta para triggers ETB de Oro/fuera del juego
> (2026-08-26).
>
> 2026-09-19, §10.53: SIN LLAMADOR HOY A PROPÓSITO — TriggerSystem.
> waiting_for_responses ya no se emite (TriggerResolution.resolve_next_
> trigger() pasó a abrir una ventana real vía open_response_window(), a
> pedido del usuario), así que esta función no se vuelve a llamar. NO
> BORRAR sin más: si volviera a emitirse esa señal por error, el 'Sí,
> cancelar' de este diálogo llamaría a TriggerSystem.cancel_current_
> trigger(), que solo _wait_for_response_window() (huérfana también, ver su
> docstring) llegaba a leer — quedaría un diálogo clickeable que no cancela
> nada de verdad. Signo Amarillo para triggers se sigue ofreciendo bien hoy
> por el camino nuevo: _offer_signo_amarillo_for_step_d() más abajo, que
> escucha ActionPipeline.step_d_waiting (open_response_window() sí la
> emite, para cualquier objeto de la Pila).
>
> Antes (2026-08-26 a 2026-09-19): TriggerResolution._wait_for_response_
> window() solo emitía esta señal cuando de verdad había algo que pudiera
> responder (un Signo Amarillo sin convertir), así que si no lo encontraba
> aquí algo había cambiado de estado entremedio.
>
> 2026-09-11 (a pedido del usuario): reemplazó el panel flotante por un
> diálogo reactivo (mismo criterio que _offer_signo_amarillo_for_step_d) —
> esta ventana no tenía botón ¿Paso? propio (se resolvía sola a los 8s vía
> TriggerResolution._wait_for_response_window()), así que responder "No"
> ahí adelantaba ese pase en vez de forzar la espera completa.

## `scripts/ui/inspection/SearchAbilityHandler.gd`

### `(nivel de archivo)` — línea 2

> SearchAbilityHandler — Facade de Patrones especiales de habilidades
> ACTIVADAS que buscan/miran/reordenan cartas del Castillo, generan Oro
> Virtual restringido, o juegan otra carta con descuento (Padre de la
> Patria, Don de Amma, Tesoro de los Césares, Miguel, Espada de O'Higgins,
> Infernum Vox, Aho, y todas las cartas agregadas 2026-09-06 en adelante).
> Detectados en CardInspectionLayer._build_ability_buttons() y ruteados aquí
> en vez de al pipeline genérico de habilidades activadas.
>
> Dividido en dos archivos por tamaño (2026-09-06, "módulos gordos"):
> SearchAbilityHandler_AI.gd (nombres de carta A-I) y
> SearchAbilityHandler_JV.gd (J-V). Este archivo queda como FACADE — cada
> función de abajo es un reenvío de una sola línea a la mitad que
> corresponda, con el mismo nombre y firma de siempre, así que
> CardInspectionLayer.gd (único llamador, vía `_search_handler._activate_X(...)`)
> no necesitó cambiar una sola línea por este split.

## `scripts/ui/inspection/SearchAbilityHandler_AI.gd`

### `(nivel de archivo)` — línea 2

> SearchAbilityHandler_AI — Mitad A-I (alfabético por nombre de carta) de
> SearchAbilityHandler.gd, dividido por tamaño (2026-09-06, "módulos gordos"
> — mismo corte que ya separó BernardoAbilityHandler/HandCementerioAbilityHandler
> del propio CardInspectionLayer.gd). Ver SearchAbilityHandler.gd para el
> facade que reune esta mitad y SearchAbilityHandler_JV.gd bajo los mismos
> nombres públicos que antes — CardInspectionLayer.gd no cambió una sola
> línea por este split. Opera sobre CardInspectionLayer via _inspector (y
> sobre el Main del juego via _inspector._main).

### `_activate_aho_banish_ally_and_deck` — línea 19

> 'Una vez por turno, Destierra un Aliado o Tótem y cinco cartas del
> tope de un Castillo' (Aho, 2026-08-30). Sin 'puedes': mandatorio una
> vez activada — clickear el botón ya es la confirmación de uso, mismo
> criterio que el resto de ACTIVATED. 'Un Aliado o Tótem'/'un Castillo'
> sin posesivo = cualquiera de los dos jugadores, a elección (mismo
> criterio ya confirmado para 'un Cementerio' de Miguel). Dos destierros
> independientes unidos por 'y' (no 'Luego'): ambos ocurren sin
> condicionarse entre sí, aunque el objetivo elegido no exista.

### `_activate_aho_banish_ally_and_deck` — línea 49

> El contador visual del Castillo no se refresca solo al vaciar el Array
> del mazo a mano (2026-08-31, a pedido del usuario: 'destierro 5 del
> tope pero el contador del castillo sigue igual') — mismo llamado que
> ya usan el resto de patrones que tocan el mazo directo (ver
> LookAndPlayResolver/DrawShuffleResolver, _update_castillo_counts()).

### `_activate_asmodeus_gold_and_banish_bottom` — línea 59

> 'Una vez en tu turno, genera un Oro y Destierra hasta dos cartas del
> fondo de un Castillo' (Asmodeus, 2026-09-06) — 'del fondo' (no del
> tope): se sacan desde el FINAL del array del mazo (pop_back), no el
> inicio. 'un Castillo' sin posesivo = a elección.

### `_activate_asmodeus_gold_and_banish_bottom` — línea 70

> 2026-10-06: generar_oros_virtuales() ya es por jugador (ver
> arquitectura.md §33) — esta habilidad se desbloquea.

### `_activate_belcebu_banish_bottom_and_steal` — línea 87

> 'Una vez por turno, Destierra tres cartas del fondo de un Castillo y
> gana el control de hasta una carta de coste 3 o menos. En la Fase
> Final, Ponla en el fondo del Castillo y Roba una carta' (Belcebú,
> 2026-09-06). 'ganar el control' reusa ContinuousEffectManager.
> gain_control_of_card() (primer uso: shedo titan); el retorno al fondo
> del mazo + Robo se agenda como efecto de un solo uso para la PRÓXIMA
> Fase Final propia (EffectController.schedule_next_final_phase_effect,
> mecanismo de Fisión Nuclear).

### `_activate_belcebu_banish_bottom_and_steal` — línea 116

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_cetro_demoniaco_gold_and_banish` — línea 143

> 'Una vez por turno, genera un Oro y Destierra cuatro cartas del tope
> de un Castillo' (Cetro Demoniaco, 2026-09-06). 'Un Castillo' sin
> posesivo = a elección (_choose_search_zone_owner()). Oro sin restringir
> (genera_oros_virtuales), no genérico como Padre de la Patria — el
> texto no dice 'para jugar X'.

### `_activate_cetro_demoniaco_gold_and_banish` — línea 155

> 2026-10-06: generar_oros_virtuales() ya es por jugador (ver
> arquitectura.md §33) — esta habilidad se desbloquea.

### `_activate_chakram_look_and_lock` — línea 163

> 'Una vez por turno, puedes mirar la mano de tu oponente y elegir una
> carta de ahí que no sea Oro para que no pueda ser jugada hasta tu
> próximo turno y Roba una carta' (Chakram, 2026-08-30). 'Mirar' no
> necesita un overlay de revelado aparte — el picker de SelectionManager
> ya muestra el arte/nombre real de cada candidata, alcanza para 'ver' la
> mano rival y elegir. main._opponent_fan.get_cards() son Nodos reales
> (mismo camino que usa _execute_targeted_discard() para la mano rival),
> así que el elegido se candada como Nodo puntual, no por nombre —
> GoldManager.lock_card_from_playing().
>
> Se muestra la mano COMPLETA, Oro incluido (2026-08-31, a pedido del
> usuario: 'mirar' debería mostrar toda la información real, no solo lo
> elegible) — antes los Oro se sacaban de la lista antes de abrir el
> picker, así que ni se veían. Ahora se pasan todos y el filtro de
> SelectionManager.await_single_pick() los deja visibles pero sin poder
> clickearlos (mismo patrón gris/no-interactivo que cualquier otro picker
> con 'filter' — ver SelectionManager._create_selection_card()).

### `_activate_cuerno_titan_discard_search_cost_adjust` — línea 227

> 'Una vez por turno, puedes Descartar una carta de tu mano para busca
> una carta Titán en tu Castillo, ponerla en tu mano y aumentar o
> disminuir el coste de hasta una carta en juego en un Oro' (Cuerno de
> Titán, 2026-09-06) — costo: Descartar UNA carta de la mano elegida por
> el jugador; efecto: buscar un Titán (cualquier tipo con raza 'Titán',
> no solo Aliado) + ajustar el coste de una carta en juego (elegida) en
> ±1 de forma PERMANENTE mientras Cuerno de Titán siga en juego.

### `_activate_cuerno_titan_discard_search_cost_adjust` — línea 242

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (mismo bug que
> gran kraken, ver PreventionAbilityHandler_EP.gd).

### `_activate_cuerno_titan_discard_search_cost_adjust` — línea 277

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_cuerno_titan_discard_search_cost_adjust` — línea 287

> ContinuousEffectManager, no PaymentManager (2026-09-06): los
> modificadores de PaymentManager.cost_modifiers se vacían enteros en
> cada turno nuevo (pensados para descuentos de un solo uso al jugar
> una carta) — este ajuste de coste no dice "por el turno", así que
> debe persistir mientras Cuerno de Titán siga en juego, igual que el
> resto de auras de coste de esta sesión (Asmodeus/Belcebú).

### `_activate_don_de_amma` — línea 309

> 'Una vez por turno, puedes Desterrar un Oro con habilidad de tu
> Reserva. Luego, busca un Oro en tu Castillo y ponlo en tu Reserva' (Don
> de Amma — texto verificado 2026-08-29 contra la API, estable en 7
> reimpresiones). El Oro a Desterrar puede ser cualquier Oro-con-habilidad
> en Reserva, no necesariamente esta misma carta — si hay más de uno se
> elige; si solo hay uno (lo normal: esta misma) se ahorra el diálogo. La
> búsqueda posterior reutiliza _execute_targeted_search() genérico (ya
> entiende 'ponlo en tu Reserva' como destino RESERVA_ORO, agregado para
> esta misma carta) en vez de un camino separado.

### `_activate_don_de_amma` — línea 334

> 2026-09-13, a pedido del usuario: click directo en la Reserva en
> vez del modal de lista viejo.

### `_activate_don_de_amma` — línea 343

> Registrar ANTES de Desterrar (2026-08-29): to_exile suele ser la propia
> source_card — tras exile_card() el Node puede quedar inválido, así que
> no se puede seguir leyendo de source_card/ability después de este punto.
> Misma razón por la que la ventana de respuesta (2026-09-10) va AQUÍ y no
> más abajo, antes del search() sin cobertura propia.

### `_activate_dyyavol_titan_draw_discard_mill` — línea 363

> 'Una vez por turno, Roba una carta y Descarta una carta. ... Si la
> carta Descartada es un Ignis o Titán cada jugador Bota tres cartas'
> (dyyavol titan, 2026-09-06) — solo Robar+Descartar+el Bote condicional
> por raza; 'Aumenta el coste de hasta dos Aliados Titán en juego en dos
> Oros mientras estén en juego' (targeting aparte, modificador de coste
> persistente por carta) NO implementado.

### `_activate_dyyavol_titan_draw_discard_mill` — línea 378

> 2026-09-30, bug real expuesto al levantar la guarda de arriba: esto
> leía SIEMPRE player_hand sin mirar owner_id — para el jugador 1
> (bot/Remoto) había que leer _opponent_fan en su lugar.

### `_activate_espada_ohiggins_vigilia_choice` — línea 396

> 'En tu Vigilia, una vez por turno, puedes Barajar una carta que no
> sea Oro o buscar un Oro en tu Castillo y ponerlo en tu mano' (Espada de
> O'Higgins, 2026-08-30). Elección A/B entre dos efectos que no comparten
> nada — ActionPipeline solo resuelve un tipo de acción por habilidad, no
> una elección genérica entre dos. Restricción de fase ('en tu Vigilia')
> ya validada de forma genérica en _validate_ability(). Clickear el botón
> ya es la confirmación de uso (mismo criterio que el resto de
> ACTIVATED), así que el uso se registra apenas se resuelve la elección
> A/B, sin importar si la rama elegida después no encuentra objetivos.

### `_activate_espada_ohiggins_vigilia_choice` — línea 416

> "Barajar una carta que no sea Oro" — sin 'que controles' ni
> 'oponente', así que es CUALQUIER carta EN JUEGO, de cualquiera de
> los dos jugadores (2026-09-02, corrección del usuario: la primera
> vez se había restringido de más a solo el propio lado — mismo
> criterio ya confirmado para Aho/Miguel, sin calificador de dueño
> = cualquiera de los dos). Reserva de Oro y Oro Pagado quedan
> FUERA del barrido en ambos lados (la propia carta ya lo dice —
> 'que no sea Oro' — esas dos zonas solo contienen Oro); Campo,
> Línea de Ataque y Línea de Apoyo de AMBOS jugadores, más las
> Armas equipadas de cada Aliado.

### `_activate_espada_ohiggins_vigilia_choice` — línea 432

> 2026-09-13, a pedido del usuario: click directo sobre las cartas
> reales en juego en vez del modal de lista viejo.

### `_activate_espada_ohiggins_vigilia_choice` — línea 442

> El mazo de destino es el del DUEÑO real de la carta elegida, no el
> del jugador que activó la habilidad (2026-09-02: con el pool ya
> abierto a ambos lados, barajar una carta rival tenía que volver
> al Castillo del rival, no al propio).

### `_activate_infernum_vox_look_reorder` — línea 456

> 'Una vez por turno, puedes mirar seis cartas del tope de un Castillo
> y devolverlas en cualquier orden en el tope y/o fondo del Castillo'
> (Infernum Vox, 2026-08-30). 'Un Castillo' sin posesivo = el propio o el
> rival, a elección (mismo criterio ya confirmado para 'un Cementerio' de
> Miguel). El orden se resuelve con DOS selecciones múltiples de
> SelectionManager.await_multi_pick(), reutilizando que selected_cards
> preserva el ORDEN DE CLICK (ver SelectionManager._select_card()) — no
> hace falta ninguna UI de arrastrar/reordenar. (La que ya existía en el
> proyecto, SelectionCanvas.gd/SelectionReorder.gd con su SelectionMode.
> LOOK/REORDER, resultó ser código MUERTO al revisarla — no es autoload,
> no está en ninguna escena, y OpponentUI.gd la busca en /root/
> SelectionCanvas reintentando para siempre sin encontrarla nunca; no se
> tocó, pero tampoco se reusó aquí.)
> 1) Elegir cuáles de las 6 van al FONDO, EN EL ORDEN que se quieran
> (0 a todas) — el orden de click ya es el orden final de ese grupo
> (primero clickeado = más arriba DENTRO del grupo que va al fondo).
> 2) Con las que quedan (van al TOPE), una segunda selección forzando
> TODAS (min = max = las que quedan) solo para capturar el orden de
> click — ya no hay 'elegir cuáles', quedaron decididas por descarte
> del paso 1.

### `_activate_infernum_vox_look_reorder` — línea 479

> 2026-10-07 (ver arquitectura.md §40): await_castillo_pick()/await_
> multi_pick() ya tienen puente de red. Límite conocido para el Remoto
> específicamente en ESTA carta: la UI remota de multi-selección usa
> checkboxes, no orden de click, así que el reordenamiento en sí no se
> respeta de su lado (siempre vuelve en el orden que ya tenía) — "mirar
> y elegir cuáles van al fondo" sí funciona igual para los dos lados.

### `_activate_infernum_vox_look_reorder` — línea 492

> Ventana única para todo el reordenamiento (2026-09-10) — sin objetivo
> puntual que declarar todavía (las 6 salen del tope, en orden), gatea
> toda la resolución de una vez, igual que el resto de patrones "mira/
> revela N... reordena" sin punto de declare limpio.

### `_activate_infernum_vox_look_reorder` — línea 501

> pop_front() = tope real (2026-08-30, corregido — el camino de robo
> que de verdad usa la partida es ZoneManager.draw_card(), que hace
> pop_front() sobre este mismo array; CardManager.draw_card() con
> pop_back() nunca se llama desde ningún lado, quedó con la
> convención vieja). La primera carta sacada es la más arriba del
> mazo, la sexta la más profunda de las 6.

### `_activate_infernum_vox_look_reorder` — línea 526

> add_to_deck_bottom() = append (2026-08-30, tras corregir CardManager):
> el ÚLTIMO en agregarse queda como fondo absoluto — pasando
> ordered_bottom en su orden tal cual (primero = más arriba del grupo)
> el último en insertarse (ordered_bottom.back()) termina siendo el
> fondo absoluto. Correcto.

## `scripts/ui/inspection/SearchAbilityHandler_JV.gd`

### `(nivel de archivo)` — línea 2

> SearchAbilityHandler_JV — Mitad J-V (alfabético por nombre de carta) de
> SearchAbilityHandler.gd, dividido por tamaño (2026-09-06, "módulos gordos"
> — mismo corte que ya separó BernardoAbilityHandler/HandCementerioAbilityHandler
> del propio CardInspectionLayer.gd). Ver SearchAbilityHandler.gd para el
> facade que reune esta mitad y SearchAbilityHandler_AI.gd bajo los mismos
> nombres públicos que antes — CardInspectionLayer.gd no cambió una sola
> línea por este split. Opera sobre CardInspectionLayer via _inspector (y
> sobre el Main del juego via _inspector._main).

### `_activate_jinete_peste_search_banish_two` — línea 22

> 'Una vez por turno, busca en un Castillo dos cartas de distinto
> nombre y Destiérralas. Si controlas otro Jinete, además Roba una
> carta' (Jinete de la Peste, 2026-09-06) — 'un Castillo' sin posesivo =
> a elección. 'Si controlas cuatro Aliados Jinete, tu oponente no puede
> poner cartas en su mano por efectos' NO implementado (restricción
> global nueva).

### `_activate_kotaix_draw_and_shuffle_opponent` — línea 54

> 'Una vez por turno, Roba dos cartas y Baraja una carta oponente que
> no sea Oro. Esta habilidad no puede ser cancelada.' (Espíritu Kotaix,
> 2026-09-02 — segunda habilidad, verificada contra la API, sin
> discrepancias con el cache local). 'Una carta oponente' sin zona = EN
> JUEGO (ver [[project_no_zone_means_in_play]]), excluyendo Oro. Sin
> 'puedes': el Robo es incondicional; unido por 'y' (no 'Luego'), así que
> sucede siempre sin importar si hay o no un objetivo rival válido para
> barajar — mismo criterio ya usado en Estaca (idéntico patrón, ver
> _activate_estaca_draw_and_shuffle() en HandCementerioAbilityHandler.gd)
> y en Espada de O'Higgins/Aho. 'No puede ser cancelada' queda satisfecho
> por construcción: esta habilidad se resuelve directo aquí, sin pasar por
> la Pila/ActionPipeline (igual que el resto de patrones especiales de
> este archivo), así que nunca entra al camino que StackVisualizer.gd usa
> para poder cancelar una habilidad de la pila.

### `_activate_kotaix_draw_and_shuffle_opponent` — línea 71

> Ventana única para toda la habilidad (2026-09-10): sin declare real
> todavía aquí (el objetivo rival se elige solo más abajo), mismo
> criterio que Estaca (HandCementerioAbilityHandler.gd).

### `_activate_kuchiku_cazador_search_and_play_discount` — línea 134

> 2026-10-14, a pedido del usuario: tu Castillo y tu Cementerio en el
> selector del tablero, en vez del popup "¿Dónde buscar?".

### `_activate_kuchiku_cazador_destroy_and_discard` — línea 188

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_kuchiku_cazador_destroy_and_discard` — línea 192

> get_modified_cost(), no card_cost crudo (2026-09-04, a pedido del
> usuario: una carta en juego puede tener el coste reducido de forma
> continua, p.ej. Samael — el filtro tiene que verlo).

### `_activate_lider_del_comite_discard_look_name_lock` — línea 211

> 'En tu Vigilia, una vez por turno, puedes Descartar una carta para
> mirar la mano de tu oponente y nombrar una carta. Las cartas con ese
> nombre pierden su habilidad y tu oponente no puede jugarlas el próximo
> turno' (lider del comite, 2026-09-04). Costo: Descartar 1 carta propia.
> Efecto: revelado informativo de la mano rival (SelectionManager.
> open_reveal, no interactivo — 'mirar' no exige elegir de ahí, el nombre
> puede ser cualquier carta) + KeywordManager.lock_ability_by_name()
> (TODAS las copias, presentes o futuras, mientras esta carta siga en
> juego) + GoldManager.lock_card_from_playing() sobre cada copia YA
> visible en la mano rival con ese nombre (las que lleguen después vía
> robo no quedan bloqueadas — límite conocido, caso borde poco común).

### `_activate_lider_del_comite_discard_look_name_lock` — línea 231

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo.

### `_activate_miguel_discount_play` — línea 279

> 'Una vez en tu turno, juega una carta de tu mano o de un Cementerio
> reduciendo su coste en un Oro, hasta un mínimo de 0' (Miguel,
> 2026-08-29). 'Un Cementerio' sin posesivo = cualquiera de los dos, el
> propio o el rival (confirmado por el usuario) — jugarla te vuelve su
> CONTROLADOR; si sale de juego vuelve al Cementerio/Destierro de su dueño.
>
> 2026-10-12, a pedido del usuario: se elige desde el tablero, igual para
> el Anfitrión y el Remoto ("todos los cambios siempre tienen que ser para
> el Remoto igual") — las cartas jugables de la mano brillan (clic
> directo) y los Cementerios brillan y se abren con clic (ZoneBrowsePicker
> vía ActionModule.pick_in_zones(), el mismo selector de las búsquedas,
> §53). Antes era un popup con los dos Cementerios. Nunca ofrece Oros: un
> Oro no se juega, y "reduciendo su coste" solo aplica a cartas con coste.

### `_activate_padre_patria_gold` — línea 377

> 'Una vez en tu turno, genera un Oro para jugar Armas o Aliados
> Caballero por el turno' (Padre de la Patria, 2026-08-28). Sin coste ni
> objetivo — se genera directo como Oro Virtual restringido
> (GoldManager.restricted_gold_pools) y se marca usada este turno.

### `_activate_padre_patria_gold` — línea 392

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador (ver
> arquitectura.md §33) — el guard que se le había agregado en §27 (por
> el motivo documentado abajo) ya no hace falta.

### `_activate_padre_patria_gold` — línea 397

> instance_id (2026-08-30), no card_data.id — cada copia física necesita
> su propio cupo de 'una vez por turno'.

### `_activate_patria_vieja_look_six` — línea 403

> 'En tu Vigilia, si no has puesto Oros en juego este turno, puedes mirar
> las primeras seis cartas de tu Castillo y poner un Oro de ahí en tu
> Reserva. Esta habilidad no puede ser cancelada' (Patria Vieja,
> 2026-10-13). Sin ventana de respuesta (no puede ser cancelada). La
> ventana de mirar es la misma de todas las cartas que miran el Castillo
> (CastleLook, §69): el Oro a la Reserva y las demás se ordenan en el tope.
> La versión IMP agrega 'como un Oro sin habilidad'.

### `_activate_cemetery_granted_draw` — línea 426

> Duelo Espacial en el Cementerio (2026-10-13): 'gana la habilidad "En
> tu Vigilia, puedes Robar una carta. Sólo puedes utilizar esta habilidad
> de Duelo Espacial una vez por turno"'.

### `_activate_quimera_voragh_mill_and_revive` — línea 449

> 'Una vez en tu turno, cada jugador Bota tres cartas. Si se Botaron
> Aliados u Oros, pon en juego una carta de un Cementerio como un Aliado
> de Fuerza 2 con la habilidad "Furia"' (quimera voragh, 2026-09-06).
> Botar (mill a Cementerio) manipulado directo sobre CardManager, no
> ActionModule.mill() — su fallback sin GameBoard no informa tipos por
> carta (ver el comentario de ea poe), y aquí SÍ hace falta saber si algo
> Aliado/Oro cayó para condicionar el resto. La conversión reusa el
> mismo mecanismo que leon indiferente/Sherlock Holmes (Fuerza fijada +
> KeywordManager.silence_card para quitar la habilidad original +
> Furia).

### `_activate_quimera_voragh_mill_and_revive` — línea 489

> 2026-09-13, a pedido del usuario: click directo con ambos Cementerios
> visibles en vez del modal de lista viejo.

### `_activate_tenshi_z_shuffle_hand_to_annul` — línea 543

> 'Una vez por turno, puedes Barajar una carta de tu mano para Anular
> una carta' (Tenshi Z, 2026-09-06) — costo: barajar UNA carta elegida
> de la propia mano de vuelta al mazo; efecto: Anular (~destruir, misma
> simplificación de todo el proyecto) cualquier carta en juego. Se
> confirma primero que hay objetivo válido antes de cobrar el costo
> (mismo orden que el resto de habilidades con costo+objetivo de esta
> sesión).

### `_activate_tenshi_z_shuffle_hand_to_annul` — línea 566

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo. Filtro restringido a owner_id (mismo bug que
> gran kraken, ver PreventionAbilityHandler_EP.gd).

### `_activate_tesoro_cesares_name_tax` — línea 587

> 'Una vez por turno, puedes Barajar una carta de tu mano para nombrar
> una carta. Esa carta cuesta un Oro adicional el próximo turno' (Tesoro
> de los Césares, 2026-08-29). Costo: barajar (no descartar) 1 carta
> elegida de la mano de vuelta al mazo. Efecto: nombrar cualquier carta
> del juego (buscador de texto, CardNameSearchDialog — mismo mecanismo
> que Alicia en Wonderland) con un recargo de +1 Oro que arranca solo
> el turno SIGUIENTE (PaymentManager.add_named_surcharge_next_turn(),
> registro aparte de oros_mas_modifiers porque ese Array se limpia entero
> en cada turno y aquí el efecto todavía no debe estar activo ahora).

### `_activate_tesoro_cesares_name_tax` — línea 603

> 2026-09-13, a pedido del usuario: click directo en la mano en vez del
> modal de lista viejo.

### `_activate_tesoro_cesares_name_tax` — línea 611

> HandManager.remove_card(card, true) en vez de sacarla a mano (2026-08-29,
> corrige bug real: remove_child()+queue_free() manual, copiado del
> patrón de GoldManager._equip_weapon(), no desconectaba las señales de
> la carta (card_hovered/card_clicked/etc.) antes de liberarla — un
> hover que seguía apuntando a este nodo después de queue_free() tiraba
> "Invalid access... on a base object of type 'previously freed'" al
> tocar .modulate. remove_card() sí desconecta todo antes de destruir.

### `_activate_voragh_devorador_search_to_cemetery` — línea 642

> 'En tu Vigilia, una vez por turno, busca en un Castillo dos cartas y
> ponlas en el Cementerio' (voragh el devorador, 2026-09-06) — 'un
> Castillo' sin posesivo = a elección.

### `_activate_voragh_devorador_search_to_cemetery` — línea 654

> 2026-10-14, bug real reportado por el usuario: al elegir el Castillo
> rival, el que elegía era el rival (el bot tomaba las 2 primeras). Ahora
> elige siempre quien activa, en el selector con los dos Castillos.

### `_activate_voragh_devorador_destroy_own_for_gold` — línea 662

> 'Una vez por turno, puedes Destruir una de tus cartas para generar
> un Oro para jugar Aliados' (voragh el devorador, 2026-09-06) — costo
> de Destruir una carta PROPIA (elegida, cualquier zona de campo/Oro),
> efecto: Oro Virtual restringido a Aliados (mismo mecanismo que Padre de
> la Patria).

### `_activate_voragh_devorador_destroy_own_for_gold` — línea 675

> 2026-09-12: current_zone en vez de get_parent() (ver §10.5)

### `_activate_voragh_devorador_destroy_own_for_gold` — línea 688

> 2026-10-06: generar_oro_virtual_restringido() ya es por jugador (ver
> arquitectura.md §33) — esta habilidad se desbloquea.

## `scripts/ui/inspection/StackVisualizer.gd`

### `_can_be_cancelled` — línea 661

> Protección explícita en el propio texto de la carta (2026-08-29, p.ej.
> Miguel: "Cuando entra en juego... Esta habilidad no puede ser
> cancelada.") — antes esta función solo miraba estado estructural de
> la pila, nunca el texto de la carta, así que esta protección nunca se
> aplicaba de verdad.

## `scripts/ui/selection/SelectionCanvas.gd`

### `await_show_to_opponent` — línea 795

> INTEGRACIÓN CON CardEffectSystem — eliminada (2026-08-17): connect_to_
> effect_system() no la llamaba nadie, y las señales a las que se conectaba
> (search_selection_required/look_reorder_required) eran parte del pipeline
> de CardEffectSystem.gd eliminado por ser código muerto (cero llamadores
> en todo el proyecto). El camino real de búsqueda/mirar es TriggerSystem →
> UniversalCardParser → ActionModule → SelectionManager.

## `scripts/ui/selection/SelectionModule.gd`

### `_on_exhume_card_selected` — línea 50

> 2026-10-06 (ver arquitectura.md §33): GoldManager.pagar_coste() ya
> es por jugador — antes esto solo pasaba por ahí para el jugador 0
> (Oro Virtual/restringido + elegir QUÉ Oro físico gastar) y le
> debitaba directo al jugador 1 sin pasar por ninguno de los dos.

### `_on_exhume_resolved` — línea 93

> Slot fijo (2026-08-31) — ver ZoneManager.pin_card_to_field_slot() y el
> mismo motivo en GoldManager._play_card_to_field(): sin esto, un Aliado
> exhumado reordenaba (vía el HBoxContainer) a los que ya estaban en
> Línea de Defensa.

## `scripts/ui/zones/CastleLookWindow.gd`

### `(nivel de archivo)` — línea 2

> CastleLookWindow — ventana única para "mira N cartas del tope/fondo de un
> Castillo" (2026-10-13, a pedido del usuario, arquitectura.md §69): en la
> MISMA ventana se reparten las cartas miradas a sus destinos (mano,
> Cementerio, Reserva...) y se ordenan las que vuelven al Castillo. Nada se
> mueve hasta confirmar — ver CastleLook.gd (el motor) para el resto.
>
> Corre igual en la pantalla del Anfitrión y en la del Remoto (el Remoto la
> abre con el prompt "castle_look" y devuelve el resultado por red), así que
> todo lo que recibe es serializable: cartas como Dictionary y, por zona, qué
> cartas son elegibles (no Callables).
>
> config = {
> title: String,
> cards: [card_data...],
> boxes: [{key, label, min, max (-1 = sin tope), ordered: bool,
> eligible: [bool por carta]}],
> start: key de la zona donde empiezan todas (una zona ordenada),
> }
> Devuelve {key: [índices de cards en orden]} (en una zona ordenada, el
> primero es el que queda más arriba).
>
> Se usa con preload (sin class_name global), ver §54.

### `_build` — línea 157

> Sin autowrap (2026-10-14, bug real: Tesoro de los Césares mostraba "un
> recuadro enorme sin nada" — un Label con autowrap dentro del VBox pedía
> un alto gigante y el panel quedaba casi todo fuera de la pantalla).

## `scripts/ui/zones/CemeteryRevealPopup.gd`

### `(nivel de archivo)` — línea 2

> CemeteryRevealPopup — popup liviano con cartas del Cementerio como Nodos
> temporales clickeables, en una esquina de la pantalla y SIN oscurecer el
> resto (la mano y el campo siguen clickeables al mismo tiempo). Los Nodos
> se usan como candidatos de CardInteractionModule.await_target()/
> await_multi_target() junto con las cartas de la mano.
>
> 2026-10-13 (§62): era un bloque de ~44 líneas copiado casi idéntico en 6
> lugares (Golpe Solar, Shiji, la búsqueda Aliado/Tótem del Cementerio,
> Lobo Sagrado, GoldManagerTax y Prevención con Oro). La posición usa el
> arreglo de Lobo Sagrado (2026-09-25, "el popup del Cementerio ni
> aparece"): coordenadas absolutas del viewport, no anchors, que con el
> panel todavía sin tamaño podían dejarlo fuera de pantalla.
> Se usa con preload (sin class_name global), ver §54.

## `scripts/ui/zones/DeckSelector.gd`

### `(nivel de archivo)` — línea 110

> 2026-09-23, bug real reportado por el usuario ("no se pudo cargar este
> mazo (revisa tu conexión)"): _on_confirm_pressed() no tenía ninguna
> guarda contra re-entrada — el botón seguía clickeable mientras
> _resolve_deck_entries() esperaba una respuesta lenta de ShadowForge, y el
> log real mostró 3 llamadas simultáneas a _resolve_deck_entries() para el
> mismo mazo (3 clicks de impaciencia sin feedback visible), saturando el
> backend gratuito de PythonAnywhere (probablemente un solo worker) hasta
> que las 3 quedaban sin respuesta. Ver arquitectura.md §13.15.

### `(nivel de archivo)` — línea 137

> 2026-09-22, bug real reportado por el usuario: "se queda cargando y nunca
> termina" — la cadena real de fetches (mazos privados -> mazos públicos ->
> _populate_options()) tiene 3 pasos encadenados, cada uno con su propio
> timeout de red, pero ningún límite GLOBAL sobre la cadena completa. Si
> cualquier eslabón se cuelga (señal que nunca llega, conexión que nunca
> resuelve), el "Invocando grimorios ancestrales..." queda ahí para siempre
> y no hay ningún camino que lleve a mostrar presets o el aviso de "no se
> encontraron mazos". _mazos_load_resolved corta esto: se marca en TODO
> camino terminal real (_populate_options()/_populate_with_error()) y un
> vigía de 25s (más que cualquier timeout HTTP individual, todos en 15-20s)
> fuerza el fallback local si para entonces nada resolvió solo.

### `_build_clean_action_buttons` — línea 698

> =========================================================================
> 4. BOTÓN "MAZOS PÚBLICOS" (2026-09-22, a pedido del usuario: buscar y
> jugar mazos públicos de otros jugadores de ShadowForge). Botón plano
> simple, sin pedestal a medida como los de arriba (no hay textura para
> esto) — abre un popup de búsqueda encima del altar.
> =========================================================================

### `_on_external_decks_failed` — línea 832

> =============================================================================
> FUSIÓN DE MAZOS PRIVADOS + PÚBLICOS (2026-09-22, a pedido del usuario:
> "la idea es que el botón mis mazos te muestre los mazos privados y
> públicos") — antes los públicos solo aparecían detrás del popup de
> búsqueda aparte (_open_public_deck_browser más abajo, que sigue
> disponible para buscar algo puntual más allá de esta primera página).
> =============================================================================

### `_get_preset_decks` — línea 889

> 2026-09-23, bug real reportado por el usuario ("no encontró los
> mazos" en 2 PCs distintas): esto usaba get_local_decks() — lee
> user://decks/, una carpeta POR MÁQUINA que empieza VACÍA en cualquier
> instalación nueva del .exe. En la máquina de desarrollo "funcionaba" de
> casualidad porque ahí se acumularon 183 mazos de prueba durante toda la
> sesión; en una PC recién instalada da 0, dejando el carrusel sin ningún
> preset. Los presets reales van embebidos en el propio .exe
> (res://data/decks/*.json, ver arquitectura.md §12.1/§12) y se leen con
> get_bundled_decks() — SIEMPRE disponible, sin depender de nada por
> máquina. Se combinan ambas fuentes (bundled primero, garantizado; local
> como extra si la máquina tiene algo guardado) en vez de usar una sola,
> deduplicando por slug.

### `_populate_options` — línea 958

> 2026-09-22, a pedido del usuario ("que estén separados los mazos
> públicos y privados, primero los míos, en otra columna los
> públicos"): el orden real de _mazos YA es privados+preset primero,
> públicos al final (ver _on_external_decks_received() ->
> _fetch_and_merge_public_decks()) — aquí solo se agrega el separador
> visual entre los dos grupos, detectando la transición por
> "_shadowforge_kind" (todo lo que NO sea "public" cuenta como "mío":
> mazos privados de ShadowForge y presets locales por igual). El
> separador es un Control aparte, nunca se agrega a _player_cards, así
> que los índices de selección (_selected_player_idx / _mazos) no se
> desalinean con los mazos reales.

### `_build_section_divider` — línea 1016

> Separador visual entre el grupo de mazos 'míos' (privados de
> ShadowForge + presets locales) y el grupo de mazos públicos, dentro del
> mismo carrusel horizontal (2026-09-22, a pedido del usuario). Un Control
> angosto, no un mazo — nunca se agrega a _player_cards ni participa de la
> selección.

### `_build_deck_card` — línea 1186

> 2026-09-22, a pedido del usuario ("que los mazos muestren la imagen
> como de portada"): para mazos de ShadowForge con "image_url" real
> (privados y públicos, ver arquitectura.md §13), se reemplaza la
> ilustración genérica de raza por la portada real del mazo en cuanto
> termina de bajar — mismo mecanismo ya usado en DeckManager.gd
> (_load_cover_image), sin duplicar: la genérica queda de placeholder
> mientras carga, no hay hueco en blanco.

### `_load_deck_cover_image` — línea 1257

> Baja la portada real de un mazo de ShadowForge y reemplaza la
> ilustración genérica de raza en cuanto termina. 2026-09-23, bug real
> reportado por el usuario ("no se pudo cargar este mazo (revisa tu
> conexión)" al confirmar): con el carrusel mostrando hasta ~20 mazos
> públicos de golpe, esto disparaba hasta 20 HTTPRequest simultáneos hacia
> Cloudinary — sospecha fuerte (no confirmada con certeza, pero es la
> única diferencia real entre las pruebas sintéticas, que SIEMPRE
> funcionaron, y la partida real, que SIEMPRE se cuelga 20s exactos) de
> que eso satura algún límite de conexiones concurrentes y deja sin
> respuesta al pedido de /decks/my/{id}/ que se dispara después, al
> confirmar un mazo. Se pone en cola con un tope de
> MAX_CONCURRENT_COVER_DOWNLOADS en vez de lanzar todas de una — las
> portadas fuera de pantalla de todos modos no se ven todavía.

### `_cancel_all_cover_image_downloads` — línea 1308

> Cancela de verdad los HTTPRequest de portadas que ya estén en vuelo
> (no solo los que siguen en cola) — 2026-09-23, se llama al confirmar un
> mazo para liberar cualquier capacidad de red antes del pedido crítico
> de /decks/my/{id}/. cancel_request() deja el nodo reusable, pero como no
> se va a reusar, se libera directo.

### `_unhandled_input` — línea 1410

> 2026-09-30, a pedido del usuario: antes no había forma de salir de
> esta pantalla sin elegir un mazo. Si el popup de búsqueda de mazos
> públicos está abierto, Escape lo cierra a ÉL primero (un nivel por
> vez) — recién si no hay nada más abierto cancela la selección
> completa y vuelve al menú principal.

### `_on_confirm_pressed` — línea 1517

> 2026-09-23: cortar (de verdad, no solo la cola) las descargas de
> portada pendientes al confirmar — lo que no bajó todavía ya no hace
> falta (se sale de esta pantalla), y libera de inmediato cualquier
> capacidad de red para el pedido importante que sigue (bajar las
> cartas reales del mazo elegido).

### `_on_confirm_pressed` — línea 1532

> Mazo del bot (2026-10-17, bug real reportado por el usuario: salió con un
> mazo de 5 cartas — se elegía al azar entre TODOS los mazos, incluidos
> los personales incompletos). Ahora al azar entre los presets (los mazos
> públicos importados) completos; si no hubiera ninguno, como antes.

### `_on_confirm_pressed` — línea 1549

> 2026-09-22, a pedido del usuario (fusión de mazos privados/públicos en
> el carrusel principal, ver _fetch_and_merge_public_decks() arriba): los
> mazos de ShadowForge que vienen de la lista resumida (privados o
> públicos) no traen "entries" todavía — se resuelve solo aquí, cuando
> de verdad se confirma uno, para no bajar las cartas de mazos que el
> jugador ni siquiera eligió.

### `_resolve_deck_entries` — línea 1619

> Baja las 'entries' reales de un mazo de ShadowForge (privado o
> público) que todavía no las tiene — ver _needs_entries_fetch(). Devuelve
> el Dictionary completo con 'entries' pobladas, o {} si falló (HTTP,
> desconexión, o ninguna señal llegó dentro del timeout de salvaguarda).
>
> 2026-09-23, CAUSA RAÍZ REAL encontrada tras reproducir el cuelgue en
> este mismo equipo (headless y con ventana, ver arquitectura.md §13.17):
> la petición HTTP SIEMPRE se completaba casi al instante — el problema
> nunca fue de red ni de backend. Los lambdas de GDScript capturan las
> variables locales POR VALOR, no por referencia: "done = true" dentro
> de on_ok/on_fail modificaba una copia propia del lambda, nunca la
> variable "done" de esta función, así que el bucle de espera de abajo
> jamás se enteraba de que la señal ya había llegado y agotaba siempre
> los 60s completos. Arreglado guardando el estado en un Dictionary
> ("_state"): un Dictionary SÍ se captura por referencia (la copia por
> valor es una copia del puntero al mismo Dictionary), así que mutar sus
> claves adentro del lambda es visible afuera.

### `_on_random_pressed` — línea 1692

> 2026-09-20, bug real reportado por el usuario: en una sala online,
> "Mazos aleatorios" emitía {}/{} incondicionalmente — GameBootstrap.
> _on_decks_selected() trata datos vacíos como "usar el flujo de prueba
> local" y se salta ENTERO el intercambio de mazos por red (nunca llega a
> preguntar NetworkClient.room_code), así que la partida arrancaba sola
> sin esperar al otro jugador. En sala online no tiene sentido "aleatorio
> para los dos lados" de todos modos — el mazo del jugador remoto tiene
> que ser el suyo real, elegido por él, no uno inventado aquí. Se
> interpreta como "elige un mazo al azar para mi lado" y se resuelve
> igual que un click de Confirmar, así pasa por el mismo camino de
> intercambio por red.

### `_close` — línea 1720

> =============================================================================
> MAZOS PÚBLICOS DE SHADOWFORGE (2026-09-22, a pedido del usuario)
> =============================================================================
> Popup simple (no un browser gráfico elaborado — alcanza con lista +
> búsqueda + paginación) sobre el altar existente. Al elegir un mazo, se
> arma un Dictionary con la MISMA forma que ya consume _populate_options()/
> _build_deck_card() (nombre, arquetipo/raza, formato, entries, _is_external)
> y se agrega a _mazos — reusa 100% el carrusel, la selección y
> _on_confirm_pressed() ya existentes, no duplica ningún camino de carga.

## `scripts/ui/zones/DropZone.gd`

### `_play_card_fallback` — línea 171

> Intento alternativo de jugar la carta (2026-08-28, "módulos gordos"
> punto 1: antes intentaba GameManager.play_card(), que nunca existió —
> esta rama era inalcanzable siempre. GoldManager.play_card() es el
> camino real, ya intentado antes de llegar aquí — ver el llamador).

### `_player_has_ally_in_play` — línea 255

> Verifica si hay al menos un Aliado libre en juego (propio O rival,
> 2026-09-03: DAR no restringe el portador de un Arma a Aliados que
> controlas) para portar un Arma (sin una ya equipada) — delega siempre
> a GoldManager._player_has_ally_in_play(), que ya escanea ambos lados,
> para que el highlight del arrastre no diga 'legal' cuando GoldManager
> lo va a rechazar. _p_id ya no importa (la elegibilidad no depende de
> quién arrastra la carta), se mantiene solo para no romper la firma
> del único llamador.

### `_check_card_legality` — línea 282

> ZONA DE BATALLA: Aliados desde LINEA_DEFENSA, sin enfermedad de
> invocación, durante el paso de Ataque (DAR 5.3.1) — ya sin atajo de
> Vigilia (2026-08-28). El drop en sí (on_card_dropped → _can_accept_card)
> ya lo aceptaba; esto solo hace que el brillo de "legal/ilegal" diga la
> verdad. Ver hallazgo 5.

### `_check_card_legality` — línea 294

> Ya no hay atajo Vigilia→Ataque (2026-08-28, a pedido del usuario):
> declarar atacantes requiere el botón "Atacar" primero, incluso con
> Furia — ese keyword solo evita la enfermedad de invocación.

## `scripts/ui/zones/SpinnerDrawer.gd`

### `(nivel de archivo)` — línea 2

> SpinnerDrawer — dibuja el spinner místico dorado del loading de DeckSelector.
> Extraído (2026-08-30) de un script dinámico creado en tiempo de ejecución
> desde un string ("class _SpinnerDrawerScript extends GDScript: ... source_code
> = \"\"\"...\"\"\"; reload()") — esa técnica causaba "Failed to load script
> DeckSelector.gd... Parse error" al cargar el archivo. Un archivo .gd normal
> precargado con preload() es la misma técnica ya usada en el resto del
> proyecto (ver CardNameSearchDialogScript en TriggerSystem.gd) y no depende
> de compilar código en tiempo real.

## `scripts/ui/zones/ZoneBrowsePicker.gd`

### `(nivel de archivo)` — línea 3

> ZoneBrowsePicker — selector de cartas en zonas apiladas (Castillo,
> Cementerio, Destierro) directamente sobre el tablero (2026-10-11, a pedido
> del usuario: "el mazo y el castillo también tiene que ser un selector y no
> un popup, además si la opción es en el castillo y/o cementerio la idea es
> poder ver el castillo, luego hacer click afuera, ver el cementerio y
> después confirmar toda la acción" — ejemplo: Arturo de Bretaña).
>
> Las zonas que participan brillan en el tablero; clic en una abre un visor
> con TODAS sus cartas (las elegibles destacadas, el resto atenuadas), clic
> en una carta la marca/desmarca, clic afuera cierra el visor SIN perder lo
> elegido, y el botón de paso del HUD (o el del visor) confirma la acción
> completa. Corre siempre en la pantalla de quien elige: el Anfitrión lo usa
> directo (ActionSearch) y el Remoto lo corre al recibir el prompt
> "zone_pick" (RemoteMirrorController) — en ambos casos "own" es relativo a
> esa pantalla.

### `(nivel de archivo)` — línea 20

> Escala de las cartas del visor: se calcula con el alto de la pantalla
> (2026-10-14, a pedido del usuario: "te muestra casi todo el mazo con las
> cartas muy pequeñas"), entre estos dos topes.

### `(nivel de archivo)` — línea 54

> Cartas de la mano que también son candidatas (2026-10-12, Miguel: "juega
> una carta de tu mano o de un Cementerio"). Brillan en la mano y un clic
> en una la elige de inmediato (devuelve [-1, índice]).

### `(nivel de archivo)` — línea 58

> Un solo Castillo (2026-10-14, a pedido del usuario — Duelo Espacial /
> voragh el devorador: "en caso de escoger un castillo ya no puedo cambiar
> el castillo... pero sí puedo volver a ver los cementerios"): con más de un
> Castillo en juego, el primero que se abre es el único que se puede mirar.

### `pick` — línea 91

> Abre el selector y espera la confirmación. 'pools': [{is_own, zone,
> cards: [{data, eligible}]}]. Devuelve [[pool_idx, card_idx], ...] en el
> orden en que se eligieron (vacío si se confirmó sin elegir nada).
> 'hand_nodes' (opcional, 2026-10-12): cartas de la mano que también son
> elegibles — brillan y un clic en una termina la selección con
> [[-1, índice_en_hand_nodes]] (pensado para elegir UNA carta, p.ej.
> Miguel). El clic llega por try_hand_click(); en el Remoto los Nodos son
> los de su mano espejo (ver ActionSearch.pick_in_zones()).

### `skip_optional` — línea 180

> Tecla N (2026-10-17, a pedido del usuario): fallar la búsqueda — se
> cierra sin elegir ninguna carta, aunque haya alguna válida. Solo si la
> búsqueda puede fallar (mínimo 0).

### `_build_viewer_card` — línea 407

> Zona real ANTES del dueño (2026-10-14, bug real: las cartas del
> Castillo rival salían giradas 180° — current_zone arranca en MANO y
> Card gira toda carta rival "en la mano o en juego").

### `_toggle` — línea 491

> "de un Cementerio" (2026-10-14, Lanza Argenta): todas de la misma zona.

### `_toggle` — línea 503

> Con la última carta que se puede elegir se cierra solo, sin Confirmar
> (2026-10-14, a pedido del usuario: "si me piden 2 cartas, al hacerle
> clic a la segunda que se cierre la ventana").

## `scripts/ui/zones/ZoneViewerModule.gd`

### `setup_public_zone_viewers` — línea 201

> Con el selector de zonas activo (ZoneBrowsePicker), el clic en
> el panel abre SU visor, no este (2026-10-11).

### `setup_public_zone_viewers` — línea 215

> Revelado del tope del Castillo (La Ouija, 2026-08-31) — a diferencia de
> Cementerio/Destierro (siempre públicos), el Castillo es zona OCULTA por
> defecto: el TopCardPreview de PlayerCastillo solo se muestra mientras
> haya una carta propia en Reserva con 'Juega mostrando la primera carta
> de tu Castillo' (ver refresh_castillo_top_reveal()), y se apaga solo si
> esa carta sale de juego. No hay popup de todo el mazo (a diferencia de
> Cementerio/Destierro) — el efecto solo revela el TOPE, nunca el resto.

### `setup_public_zone_viewers` — línea 232

> Escritura Sagrada (2026-10-18, a pedido del usuario): al tocar tu
> Castillo se abren las dos primeras cartas, como el Cementerio.

### `setup_public_zone_viewers` — línea 247

> 2026-09-14, a pedido del usuario (La Ouija): CardManager.take_damage()
> (alias mill_cards(), usado por daño de combate normal Y por 'Botar N
> cartas') saca del TOPE real (pop_front()) pero solo emitía
> deck_count_changed — nadie escuchaba esa señal para refrescar el
> revelado del tope, solo UIManager.update_castillo_count() (el número).
> Conectar aquí cubre de una ese caso Y cualquier otro sitio que ya siga
> la convención de CardManager (_emit_deck_changed()/take_damage()) sin
> tener que parchear cada uno a mano (a diferencia de ActionSearch.gd/
> ActionModule.shuffle_deck(), que tocan el mazo SIN pasar por esa señal
> — esos se arreglaron aparte, llamando _update_castillo_counts() directo).

### `_on_exhumar_card_clicked` — línea 585

> Click en una carta con Exhumar dentro del popup del Cementerio propio
> (2026-08-23): valida Oro disponible, cierra el popup y la juega vía
> GoldManager.play_card_from_cemetery() — mismo camino real que jugar
> desde la mano, no el ActionPipeline/ExhumarSystem huérfanos.

### `_on_exhumar_card_clicked` — línea 591

> 2026-09-25, bug real reportado por el usuario ("con lobo sagrado no me
> permite jugar armas del cementerio"): si hay una selección de objetivo
> real esperando esta misma carta (p.ej. Lobo Sagrado eligiendo un Arma
> del Cementerio), resolverla ahí en vez de intentar Exhumar — el
> jugador clickea el visor de Cementerio de siempre, no un popup nuevo
> que no conoce. Ver CardInteractionModule.try_resolve_cemetery_click().

### `_on_exile_card_clicked` — línea 612

> Click en una carta jugable desde el Destierro propio dentro de su
> popup (2026-09-04) — cierra el popup y la juega vía GoldManager.
> play_card_from_exile() (paga el coste real, no un pago especial como
> Exhumar). GoldManager.play_card_from_exile() ya valida fase/prioridad/
> Oro disponible y avisa por _update_debug() si algo falla, así que aquí
> no hace falta duplicar esos chequeos.

### `open_cemetery_target_picker` — línea 627

> Popup de selección de objetivo mostrando AMBOS Cementerios (o
> Destierros, o ambas zonas combinadas) lado a lado, con click directo
> sobre las cartas reales — reemplaza el patrón viejo de 'modal
> preguntando primero de cuál Cementerio, después otro modal con la
> lista de cartas' (2026-09-13, a pedido del usuario: Espada de
> O'Higgins, Hanta el Samurai — 'poder ver los cementerios por mi cuenta
> y hacer objetivos, para mejor visibilidad y control del efecto').
> Reutiliza CardInteractionModule.await_multi_target() para la mecánica
> de click + brillo celeste — las cartas aquí son Nodos TEMPORALES que
> solo existen mientras el popup está abierto (a diferencia de player_
> field/mano), su card_data es la fuente de verdad real; 'filter' recibe
> estos Nodos temporales, no los permanentes del campo.
> 'zone_type': "cemetery", "exile", o "cemetery_and_exile" (2026-09-13,
> Abrazo de Maipú: 'Baraja cualquier cantidad de cartas de tu Cementerio
> Y Destierro' — ambas zonas en el MISMO pool, no una elección aparte).
> 'filter' decide qué cartas son objetivo válido (recibe el Card Node
> temporal — usar card.get('card_type')/card.get('card_data'), etc.).
> 'show_select_all' (2026-09-13, mismo pedido: 'que no tenga que elegir
> una a una si tuviera 20 cartas') agrega un botón que llama a
> CardInteractionModule.request_select_all() — toma TODO lo que quede
> elegible de una sola vez. Ver la advertencia sobre 'lock_to_one_side +
> select_all antes del primer click' en el docstring de await_multi_
> target() antes de combinar ambas opciones en un caso nuevo.
> Devuelve un Array de {data: Dictionary, owner_id: int, zone_type:
> "cemetery"/"exile"} en el orden en que se clickearon o, con select-all,
> en el orden en que estaban listadas (vacío si no había candidatos o se
> canceló sin elegir ninguna).

### `open_cemetery_target_picker` — línea 676

> Fase 3 del plan de paridad remota (docs/plans/2026-09-20-remote-
> multiplayer-parity.md), mismo criterio que SelectionManager._delegate_
> selection_to_remote(): si quien elige es el jugador 1 y hay un Remoto
> real conectado, no se abre esta UI local (que igual asume SIEMPRE
> "jugador 0 = propio, jugador 1 = rival", sin mirar chooser_id) — se
> delega por red.

### `open_reveal_picker` — línea 887

> Popup de una sola fila mostrando cartas YA REVELADAS (miradas del
> tope del Castillo con 'Mira'/'Muestra' — Dictionaries sueltos, sin
> Nodo ni zona real hasta este popup) con click directo — reemplaza el
> patrón viejo de SelectionManager.open_selection()/await_single_pick()/
> await_multi_pick() sobre una lista de card_data (2026-09-14,
> continuación del barrido de pickers modales → click directo, ver
> docs/plans/2026-09-09-pila-respuesta-universal-design.md). Mismo
> mecanismo que open_cemetery_target_picker() pero de un solo pool (no
> hay 'lado rival' para cartas reveladas del propio Castillo).
> 'filter' (opcional): Callable(Node) -> bool, recibe el Nodo temporal —
> mismo criterio que open_cemetery_target_picker().
> 'max_count'==1 usa await_target() (single pick); >1 o -1 usa
> await_multi_target() (mismo criterio 'hasta N'/'exacto N' que ya
> documenta esa función — pasar cancellable=false para forzar exacto
> max_count, igual que el viejo min=max=N/can_cancel=false).
> Devuelve un Array de card_data (Dictionary) elegidos, en orden de
> click (vacío si no había candidatos o se canceló sin elegir ninguno).

### `open_reveal_picker` — línea 998

> 2026-09-19, a pedido del usuario ("restringir las cartas que no
> puedo jugar, como Oros o cartas de coste 3 o más" — Tangata
> Manu): el filtro YA excluía estas cartas de poder elegirse
> (candidates más abajo), pero visualmente quedaban idénticas a
> las elegibles — el jugador solo se enteraba de que una era
> inválida al clickearla y leer "Objetivo no válido". Mismo
> tratamiento que SelectionManager._create_selection_card() ya
> usaba para 'cartas no seleccionables' antes del barrido de
> pickers modales → click directo (2026-09-14, §10.14) — se
> perdió al migrar a este popup nuevo. can_interact=false evita
> también el hover/hand-cursor en cartas que de todos modos
> nunca se pueden elegir.

### `refresh_castillo_top_reveal` — línea 1163

> Muestra la carta del tope del Castillo propio (índice 0, ver
> convención real documentada en CardManager.add_to_deck_top()) en vez del
> dorso, mientras haya una carta propia en Reserva de Oro con 'Juega
> mostrando la primera carta de tu Castillo' (La Ouija, 2026-08-31 —
> detección por texto, mismo patrón que _max_weapons_per_ally() en
> GoldManager.gd). Llamar tras cualquier cambio al Castillo (robo, la
> propia habilidad de La Ouija) y cuando una carta puede haber salido de
> Reserva. Solo jugador 0 — el resto de estos efectos puntuales tampoco
> corren para el rival todavía.
