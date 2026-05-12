extends Area2D
@export var hanbingjian_speed : float = 400
@export var hanbingjian_shanghai = 10
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().create_timer(7).timeout
	queue_free()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	position += Vector2(hanbingjian_speed,0) * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		body.hp -= 10
		if body.hp <= 0:
			body.queue_free()
		self.queue_free()
