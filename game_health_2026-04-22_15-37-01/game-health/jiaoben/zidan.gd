extends Area2D

@export var zidan_speed : float = 500
@export var zidan_shanghai : float = 10
var direction : Vector2
func _ready() -> void:
	direction = Vector2.RIGHT.rotated(rotation)
	await get_tree().create_timer(5).timeout
	queue_free()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position += direction * zidan_speed * delta
			
