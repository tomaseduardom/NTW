# WTN

Simulador para jugar el TCG chileno **Mitos y Leyendas**: contra un bot o en línea contra otra persona.

- **Motor:** Godot 4.6 (renderer Forward Plus), GDScript.
- **Plataforma:** Windows (`build/windows/WTN.exe`).
- **Cartas:** ~2.700 en `data/cards.json`; las imágenes se descargan y se guardan en caché en `user://`.
- **Reglas:** basadas en el DAR (Documento de Arbitraje y Reglas). Las habilidades de las cartas se resuelven con un compilador de texto genérico y handlers por familia (cobertura en `docs/cobertura-handlers.md`).

## Abrir el proyecto

1. Instalar **Godot 4.6** (https://godotengine.org/).
2. En Godot: *Importar* → seleccionar `project.godot` → *Importar y editar*.
3. La escena principal es `scenes/menu/MainMenu.tscn` (F5 para jugar).

## Modos de juego

- **Contra el bot:** desde el menú principal (`scripts/core/ai/EasyBotController.gd`).
- **En línea:** un jugador crea una sala (Anfitrión) y comparte el código; el otro se une (Remoto). El Anfitrión corre toda la partida; el Remoto ve la misma UI y responde. Por defecto se conecta al relay `wss://mitos-relay-server-production.up.railway.app` (se puede cambiar en la pantalla de conexión).
- **Mazos:** presets en `data/decks/`, armado en el gestor de mazos e importación de mazos públicos de ShadowForge.

## Estructura

```
MitosOnline/
├── project.godot
├── scenes/            # menu/, game/ (Main.tscn), cards/, ui/
├── scripts/
│   ├── core/
│   │   ├── config/    # Constants, GameState, GameSettings
│   │   ├── cards/     # CardDatabase, parsers de texto, DeckLoader, DeckValidator
│   │   ├── managers/  # GameManager, TurnManager, PriorityManager, BattleManager, PaymentManager…
│   │   ├── effects/   # compiler/, triggers/, mechanics/, continuous/, actions/, targeting/
│   │   ├── game/      # Main, GameBootstrap, PhaseFlowController, GoldManager, ZoneManager
│   │   ├── network/   # NetworkClient, controladores de Anfitrión/Remoto, TurnClock
│   │   ├── ai/        # bot y controlador del jugador remoto
│   │   └── logging/   # CombatLog
│   ├── entities/      # Card
│   ├── menu/          # menú principal, conexión en línea, gestor de mazos
│   └── ui/            # HUD, mano, inspección, visores de zonas, selección
├── data/              # cards.json y mazos preset
├── assets/            # audio, fondos, dorsos, dados, fuentes, UI
├── relay-server/      # relay WebSocket en Node.js (ver su README)
├── tools/             # pruebas, sondas de cobertura, scripts de cartas y mazos
└── docs/              # bitácora, cobertura de handlers, reglas de UI, planes
```

La descripción completa del sistema (autoloads, flujo de una partida, motor de efectos, red) está en **`arquitectura.md`**. Para agregar una carta nueva, ver la sección "Cómo se resuelve el texto de una carta" de ese documento y `docs/plans/2026-09-04-card-integration-checklist.md`.

## Pruebas

```powershell
powershell -File tools/run_tests.ps1 [-Godot "ruta\Godot_v4.6-stable_win64_console.exe"]
```

Corre en modo headless cuatro suites:

- `tools/tests/test_core.tscn`: mazos, texto, reloj, historial y compilador.
- `tools/test_keywords_strength.tscn`: palabras clave y Fuerza en el tablero.
- `tools/tests/test_pila_prioridad.tscn`: quién tiene la prioridad, qué pasa cuando ambos pasan y la Pila (respuestas encadenadas, Anular, Cancelar).
- `tools/tests/test_escenarios.tscn`: cartas jugadas en una partida real contra el bot, con el resultado verificado (robar, destruir, desterrar, descartar, pagar y reagrupar Oros…).

La cobertura de habilidades se mide con `tools/probe_handlers.tscn`.

Las partidas simuladas buscan bugs que las suites no cubren:

```powershell
powershell -File tools/sim/run_sim.ps1 -Partidas 20 -Paralelo 4    # bot contra bot, con invariantes
powershell -File tools/sim/run_sim_online.ps1 -Partidas 5          # Anfitrión y Remoto por un relay local
```

Cada una deja un `resumen.md` con invariantes rotas, trabas, desincronizaciones y errores de script.

## Exportar

1. Correr las pruebas (todo en verde).
2. En Godot: *Proyecto → Exportar → Windows Desktop* → `build/windows/WTN.exe`.

## Relay en línea

```
cd relay-server
npm install
npm start          # ws://localhost:8080
npm test           # salas, reenvío, reconexión sin perder ni repetir mensajes, límites
```

Para jugar en local con dos instancias, apuntar ambas a `ws://localhost:8080`. El despliegue y el protocolo están en `relay-server/README.md`.

## Teclas de depuración (en partida)

| Tecla | Acción |
|---|---|
| F1 / F2 / F3 | Fase actual / turno y jugador / cartas cargadas |
| F4 / F6 | Oro disponible / tamaño de Castillo y mano |
| F5 | Robar una carta |
| F7 / F8 | Abrir Exhumar / mostrar el tope del Castillo (con Shift: animación de daño) |
| F9 | Prueba rápida de la base de cartas |
| F10 / F11 | Previsualizar Victoria / Derrota |
| Enter | Acción principal (pasar / confirmar) |

## Reglas del proyecto

- Todo en **español neutro**: código, comentarios, UI y commits.
- Toda función debe funcionar igual para el **Remoto** que para el Anfitrión.
- Más convenciones de reglas en `arquitectura.md` → "Reglas del usuario que valen siempre".
