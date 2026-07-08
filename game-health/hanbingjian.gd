extends Area2D

@export var hanbingjian_speed : float = 400
@export var hanbingjian_shanghai = 10

func _ready() -> void:
	await get_tree().create_timer(7).timeout
	queue_free()


func _physics_process(delta: float) -> void:
	position += Vector2(hanbingjian_speed, 0) * delta


## 碰到墙壁或障碍物 → 销毁
func _on_body_entered(body: Node2D) -> void:
	if body is TileMapLayer or body is StaticBody2D:
		queue_free()
