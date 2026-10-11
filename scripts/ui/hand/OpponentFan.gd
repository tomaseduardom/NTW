extends Control
class_name OpponentFan
## OpponentFan — Mano del oponente en fila horizontal limpia (Opción 3).
##
## Cartas centradas horizontalmente con rotación recta (0°), solapadas
## de manera uniforme y elegante en el borde superior de la pantalla.

signal hand_changed(count: int)
## 2026-10-08 (ver arquitectura.md §45): GameStateBroadcaster se cuelga de
## estas dos para transmitirle al Remoto conectado los cambios reales de SU
## PROPIA mano (nunca la del Anfitrión — fuera de alcance, fog of war real)
## — este Control es el único punto por donde pasa CUALQUIER cambio a la
## mano del jugador 1 en todo el proyecto (decenas de llamadores, ningún
## otro hook posible). card_removed se emite ANTES de queue_free() en
## remove_card(destroy=true), así que el Node sigue siendo válido cuando
## llega al listener.
signal card_added(card: Node)
signal card_removed(card: Node)

@export var card_scale:    float = 0.50
@export var card_overlap:  float = -40.0   ## Solapamiento base entre cartas
@export var anim_duration: float = 0.20

const CARD_W: float = 150.0  # Ancho base de carta (sin escalar)
const CARD_H: float = 210.0  # Alto base de carta (sin escalar)

## 2026-10-07: pública (no "_cards") a propósito — mismo nombre que
## DynamicHand.cards (la mano del Anfitrión), para que el patrón repetido en
## todo el proyecto `hand_container = main.player_hand if owner_id == 0 else
## main._opponent_fan` pueda seguir leyendo/escribiendo `hand_container.cards`
## sin importar cuál de las dos sea — antes era `_cards` (privada) y ese
## acceso crudo fallaba en tiempo de ejecución para cualquier carta del
## Remoto (ver arquitectura.md §34).
var cards: Array[Node] = []


# =============================================================================
# INICIALIZACIÓN
# =============================================================================
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_arrange)


# =============================================================================
# API PÚBLICA
# =============================================================================
func add_card(card: Node) -> void:
	cards.append(card)
	add_child(card)
	_init_card(card)
	card.modulate.a = 0.0
	_arrange()
	emit_signal("hand_changed", cards.size())
	emit_signal("card_added", card)


func remove_card(card: Node, destroy: bool = true) -> void:
	if card not in cards:
		return
	cards.erase(card)
	emit_signal("card_removed", card)
	if destroy:
		card.queue_free()
	else:
		remove_child(card)
	_arrange()
	emit_signal("hand_changed", cards.size())


func clear_hand() -> void:
	for card in cards:
		if is_instance_valid(card):
			emit_signal("card_removed", card)
			card.queue_free()
	cards.clear()
	emit_signal("hand_changed", 0)


func get_card_count() -> int:
	return cards.size()


func get_cards() -> Array[Node]:
	return cards


func _arrange_cards(_animated: bool = true) -> void:
	"""Alias de _arrange() con la firma de DynamicHand._arrange_cards()
	(mismo motivo que la propiedad 'cards' arriba — compatibilidad con el
	código que trata player_hand/_opponent_fan de forma intercambiable).
	'_animated' se ignora: _arrange() de esta clase siempre anima igual."""
	_arrange()


# =============================================================================
# CONFIGURACIÓN DE CARTA
# =============================================================================
func _init_card(card: Node) -> void:
	card.owner_id      = 1
	card.controller_id = 1
	card.esta_oculta   = true
	card.can_interact  = false
	card.scale         = Vector2(card_scale, card_scale)
	card.base_scale    = Vector2(card_scale, card_scale)
	card.pivot_offset  = Vector2(CARD_W / 2.0, 0.0)
	card.actualizar_aspecto()
	if card.has_method("_refresh_disabled_rotation"):
		card._refresh_disabled_rotation()


# =============================================================================
# DISPOSICIÓN HORIZONTAL RECTA (OPCIÓN 3)
# =============================================================================
func _arrange() -> void:
	var n := cards.size()
	if n == 0:
		return

	# Centro horizontal de la pantalla
	var cx := size.x / 2.0
	if cx < 50.0:
		var vp := get_viewport()
		cx = vp.get_visible_rect().size.x / 2.0 if vp else 960.0

	var effective_width := CARD_W * card_scale  # 75px
	
	# Solapamiento dinámico: si hay muchas cartas se comprime suavemente
	var overlap := card_overlap
	var max_available_width := 420.0
	if n > 1:
		var natural_total := effective_width + float(n - 1) * (effective_width + overlap)
		if natural_total > max_available_width:
			var max_step := (max_available_width - effective_width) / float(n - 1)
			overlap = max_step - effective_width

	var step := effective_width + overlap
	var total_w := effective_width + float(n - 1) * step if n > 1 else effective_width
	var start_x := cx - total_w / 2.0

	for i in range(n):
		var card := cards[i]
		var px := start_x + float(i) * step
		var py := 8.0  # Posicionada limpiamente bajo el borde superior sin cortarse

		card.z_index = i

		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "position",         Vector2(px, py), anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(card, "rotation_degrees", 0.0,             anim_duration).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "modulate:a",       1.0,             anim_duration * 0.6)
		if card.has_method("_refresh_disabled_rotation"):
			card._refresh_disabled_rotation()


func get_card_target_position(card: Node) -> Vector2:
	"""Calcula la posición local de destino de una carta en la mano del oponente."""
	var idx := cards.find(card)
	if idx < 0:
		idx = cards.size() - 1
	if idx < 0:
		idx = 0
	var n := maxi(1, cards.size())
	var cx := size.x / 2.0
	if cx < 50.0:
		var vp := get_viewport()
		cx = vp.get_visible_rect().size.x / 2.0 if vp else 960.0

	var effective_width := CARD_W * card_scale
	var overlap := card_overlap
	var max_available_width := 420.0
	if n > 1:
		var natural_total := effective_width + float(n - 1) * (effective_width + overlap)
		if natural_total > max_available_width:
			var max_step := (max_available_width - effective_width) / float(n - 1)
			overlap = max_step - effective_width

	var step := effective_width + overlap
	var total_w := effective_width + float(n - 1) * step if n > 1 else effective_width
	var start_x := cx - total_w / 2.0
	var target_x := start_x + float(idx) * step
	return Vector2(target_x, 8.0)
