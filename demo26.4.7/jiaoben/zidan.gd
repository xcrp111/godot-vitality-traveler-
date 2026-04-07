extends Area2D

@export var zidan_speed : float = 500

func _ready() -> void:
	await get_tree().create_timer(5).timeout
	queue_free()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position += Vector2(zidan_speed,0) *delta
