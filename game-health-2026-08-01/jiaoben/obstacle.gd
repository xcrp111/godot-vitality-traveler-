class_name Obstacle
extends StaticBody2D
## 简单的障碍物 — 自动根据 CollisionShape2D 绘制矩形色块

@export var color: Color = Color(0.35, 0.28, 0.22, 1.0)  # 深棕色墙壁
@export var border_color: Color = Color(0.2, 0.15, 0.1, 1.0)

func _draw() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var shape := child.shape as RectangleShape2D
			var rect := Rect2(child.position - shape.size / 2.0, shape.size)
			draw_rect(rect, color)
			draw_rect(rect, border_color, false, 2.0)
