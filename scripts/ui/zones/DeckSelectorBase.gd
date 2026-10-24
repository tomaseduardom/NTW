extends Node
## DeckSelectorBase — base de DeckSelector.gd: constantes, tablas y ayudas compartidas por todas las familias.
## Cadena: DeckSelectorBase <- DeckSelectorPublicos <- DeckSelectorCarga <- DeckSelectorCarrusel <- DeckSelector. Lo de afuera usa solo DeckSelector.gd (hereda todo).

## DeckSelector — Interfaz diegética de selección de mazos antes de la partida.
## Altar rúnico ancestral con las 9 razas oficiales en alta definición:
## - Caballero, Bestia, Dragón, Imp, Héroe, Guerrero, Faerie, Sacerdote, Sombra.
## - Carrusel sobre la meseta del altar entre los monolitos rúnicos.
## - Pedestales de piedra interactivos que se funden 100% con la ilustración original.
## - Sin cajas verdes ni marcos intrusivos. Solo interacción orgánica y pura.

signal decks_selected(player_data: Dictionary, opponent_data: Dictionary, player_is_external: bool, opponent_is_external: bool)

signal selection_cancelled

const CARD_SIZE := Vector2(196, 266)

const GOLD := Color(0.83, 0.69, 0.22, 1.0)

const GOLD_HOVER := Color(0.88, 0.76, 0.35, 1.0)

const GOLD_SELECTION := Color(0.86, 0.72, 0.30, 0.90)

const RUNIC_CYAN := Color(0.40, 0.92, 0.90, 1.0)

const FONT_MEDIEVAL := preload("res://assets/fonts/Marcellus-Regular.ttf")

const FONT_TITLE := preload("res://assets/fonts/Cinzel-Bold.ttf")

# Texturas HD de las 9 Razas oficiales
const TEX_CABALLERO := preload("res://assets/ui/deck_selector/card_caballero.png")

const TEX_BESTIA := preload("res://assets/ui/deck_selector/card_bestia.png")

const TEX_DRAGON := preload("res://assets/ui/deck_selector/card_dragon.png")

const TEX_IMP := preload("res://assets/ui/deck_selector/card_imp.png")

const TEX_HEROE := preload("res://assets/ui/deck_selector/card_heroe.png")

const TEX_GUERRERO := preload("res://assets/ui/deck_selector/card_guerrero.png")

const TEX_FAERIE := preload("res://assets/ui/deck_selector/card_faerie.png")

const TEX_SACERDOTE := preload("res://assets/ui/deck_selector/card_sacerdote.png")

const TEX_SOMBRA := preload("res://assets/ui/deck_selector/card_sombra.png")

# Fondo diegético y spinner de carga
const BACKGROUND_TEXTURE := preload("res://assets/ui/deck_selector/altar_deck_selector.jpg")

const SpinnerDrawerScript := preload("res://scripts/ui/zones/SpinnerDrawer.gd")

# Texturas de Encuadernación y Botones Diegéticos
const TEX_LEATHER := preload("res://assets/ui/deck_selector/card_base_leather.png")

const TEX_BTN_CONFIRM := preload("res://assets/ui/deck_selector/pedestal_confirm_exact.png")

const TEX_BTN_RANDOM := preload("res://assets/ui/deck_selector/pedestal_random_exact.png")

const TEX_BTN_PLAQUE_BLANK := preload("res://assets/ui/deck_selector/pedestal_plaque_blank.png")

const TEX_DECK_INFO_PLATE := preload("res://assets/ui/deck_selector/deck_info_plate.png")

const TEX_SHIMMER_CURVED := preload("res://assets/ui/deck_selector/shimmer_curved_beam.png")

# =============================================================================
# CLASES AUXILIARES DE RENDERIZADO VISUAL
# =============================================================================

## Dibuja remaches / tachas metálicas doradas en las 4 esquinas de la encuadernación de cuero
class StudsDrawer extends Control:
	var card_size: Vector2 = Vector2(196, 266)
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w = size.x if size.x > 0 else card_size.x
		var h = size.y if size.y > 0 else card_size.y
		var studs = [
			Vector2(11, 12),
			Vector2(w - 11, 12),
			Vector2(11, h - 12),
			Vector2(w - 11, h - 12)
		]
		for pt in studs:
			# Anillo exterior de bronce oscuro
			draw_circle(pt, 4.5, Color(0.24, 0.16, 0.08, 0.95))
			# Núcleo de oro antiguo
			draw_circle(pt, 3.2, Color(0.88, 0.72, 0.28, 1.0))
			# Reflejo especular blanco
			draw_circle(pt - Vector2(1.0, 1.0), 1.2, Color(1.0, 0.98, 0.90, 0.95))

## Dibuja gemas rúnicas turquesas con halo radial brillante y pulsación viva
class GemGlowDrawer extends Control:
	var pulse_alpha: float = 0.6:
		set(v):
			pulse_alpha = v
			queue_redraw()
	var gem_color: Color = Color(0.05, 0.95, 0.85)
	var gem_positions: Array = []
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for pt in gem_positions:
			# Resplandor difuso exterior
			draw_circle(pt, 13.0, Color(gem_color.r, gem_color.g, gem_color.b, 0.22 * pulse_alpha))
			# Halo medio brillante
			draw_circle(pt, 7.5, Color(gem_color.r, gem_color.g, gem_color.b, 0.50 * pulse_alpha))
			# Núcleo intenso
			draw_circle(pt, 3.8, Color(0.75, 1.0, 0.95, 0.90 * pulse_alpha))
			# Punto especular
			draw_circle(pt - Vector2(1.0, 1.0), 1.3, Color(1.0, 1.0, 1.0, min(1.0, pulse_alpha)))

## Reflejo de luz curvado y orgánico (sin esquinas puntiagudas) para el barrido Shimmer
class ShimmerBeam extends TextureRect:
	func _init() -> void:
		texture = preload("res://assets/ui/deck_selector/shimmer_curved_beam.png")
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		mouse_filter = Control.MOUSE_FILTER_IGNORE

var _canvas_layer: CanvasLayer = null

var _overlay: Control = null

var _btn_available_decks: Control = null

var _btn_available_decks_clicker: Button = null

var _scroll_container: ScrollContainer = null

var _player_row: HBoxContainer = null

var _btn_confirm: Control = null

var _btn_confirm_clicker: Button = null

# ("no se pudo cargar este mazo (revisa tu conexión)"): _on_confirm_pressed no tenía ninguna guarda
# contra re-entrada — el botón seguía clickeable mientras _resolve_deck_entries esperaba una
# respuesta lenta de ShadowForge, y el log real mostró 3 llamadas simultáneas a
# _resolve_deck_entries para el mismo mazo (3 clicks de impaciencia sin feedback visible), saturando
# el backend gratuito de PythonAnywhere (probablemente un solo worker) hasta que las 3 quedaban sin
# respuesta. Ver arquitectura.md §13.15.
var _confirming: bool = false

var _confirm_flash: ColorRect = null

var _btn_random: Control = null

var _btn_random_clicker: Button = null

var _btn_prev: Button = null

var _btn_next: Button = null

# Cartel dinámico de mazo activo en el centro del altar
var _deck_banner: Label = null

var _deck_sub_banner: Label = null

# Pergamino inferior izquierdo
var _parchment_label: Label = null

var _mazos: Array = []

var _selected_player_idx: int = -1

var _player_cards: Array = []

var _loading_box: Control = null

# La carga de mazos es una cadena de 3 fetches (privados → públicos → _populate_options()), cada uno
# con su timeout, pero sin límite global. _mazos_load_resolved se marca en todo camino terminal
# (_populate_options()/_populate_with_error()) y un vigía de 25 s (más que cualquier timeout HTTP,
# 15-20 s) fuerza el fallback local si nada resolvió.
var _mazos_load_resolved: bool = false

const MAX_CONCURRENT_COVER_DOWNLOADS := 3

var _cover_image_queue: Array = []  # Array de {"tex_rect": TextureRect, "url": String}

var _cover_images_in_flight: int = 0

var _cover_image_active_requests: Array = []  # HTTPRequest en vuelo, para poder cancelarlos

# Popup simple (lista + búsqueda + paginación) sobre el altar. Al elegir un mazo se arma un
# Dictionary con la misma forma que consume _populate_options()/_build_deck_card() (nombre,
# arquetipo/raza, formato, entries, _is_external) y se agrega a _mazos: reusa el carrusel, la
# selección y _on_confirm_pressed().
var _public_browser_overlay: Control = null

var _public_search_edit: LineEdit = null

var _public_results_box: VBoxContainer = null

var _public_status_label: Label = null

var _public_page_label: Label = null

var _public_page: int = 1

var _public_total: int = 0

var _public_signals_connected: bool = false
