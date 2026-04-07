extends CharacterBody2D

@export var move_speed : float = 300

var is_game_over : bool = false
@export var zidan_scene : PackedScene
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if not is_game_over:
		velocity = Input.get_vector("left","right","up","down") * move_speed
		
		move_and_slide()

func game_over():
	is_game_over = true
	await get_tree().create_timer(4).timeout
	get_tree().reload_current_scene()


func _on_fire() -> void:
	if is_game_over:
		return
	
	var zidan_node = zidan_scene.instantiate()
	zidan_node.position = position + Vector2(130,130)#想要子弹发射位置在法杖 枪管等处就在后面加上vector2
	get_tree().current_scene.add_child(zidan_node)
