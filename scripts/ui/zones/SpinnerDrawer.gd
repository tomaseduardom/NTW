extends Node2D
## SpinnerDrawer — dibuja el spinner dorado del loading de DeckSelector. Es un archivo .gd normal
## precargado (un script generado desde un string en tiempo de ejecución daba "Parse error" al
## cargar DeckSelector.gd).

func _draw() -> void:
	var gold = Color(1.0, 0.86, 0.42, 0.95)
	var dim = Color(0.7, 0.55, 0.25, 0.35)
	draw_arc(Vector2.ZERO, 22, 0, TAU, 32, dim, 2.0)
	draw_arc(Vector2.ZERO, 22, -PI * 0.5, PI * 0.7, 24, gold, 3.5)
	for i in range(4):
		var angle = i * (PI / 2.0)
		var p1 = Vector2.from_angle(angle) * 11.0
		var p2 = Vector2.from_angle(angle) * 18.0
		draw_line(p1, p2, gold, 2.0)
	draw_circle(Vector2.ZERO, 4.0, gold)
