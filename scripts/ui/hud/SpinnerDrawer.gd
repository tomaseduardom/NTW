extends Node2D
## SpinnerDrawer — dibuja el anillo rotatorio del spinner de carga
## (MatchLoadingOverlay._build_mystic_spinner()). Necesita su propio _draw(), por eso se asigna con
## set_script(). Dibujo simple; reemplazarlo si se quiere algo más elaborado.

const RADIUS := 28.0
const RING_COLOR := Color(0.83, 0.69, 0.22, 1.0)
const GLOW_COLOR := Color(1.0, 0.88, 0.45, 0.65)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU * 0.75, 48, RING_COLOR, 3.0, true)
	for i in range(4):
		var angle: float = i * (TAU / 4.0)
		var point: Vector2 = Vector2(cos(angle), sin(angle)) * RADIUS
		draw_circle(point, 3.0, GLOW_COLOR)
