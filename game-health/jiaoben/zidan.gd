extends Area2D

@export var zidan_speed : float = 500
@export var zidan_shanghai : float = 10
var direction : Vector2

func _ready() -> void:
	direction = Vector2.RIGHT.rotated(rotation)
	await get_tree().create_timer(5).timeout
	queue_free()


func _process(delta: float) -> void:
	position += direction * zidan_speed * delta


## 碰到墙壁或障碍物 → 销毁
func _on_body_entered(body: Node2D) -> void:
	if body is TileMapLayer or body is StaticBody2D:
		queue_free()
