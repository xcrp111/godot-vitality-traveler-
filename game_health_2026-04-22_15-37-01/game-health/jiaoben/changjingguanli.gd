extends Node2D
@export var shilaimu_scene : PackedScene
@export var enemy_scene : PackedScene
@export var score : int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_shilaimushengcheng_timer_timeout() -> void:
	var shilaimu_node = shilaimu_scene.instantiate()
	shilaimu_node.position = Vector2(randf_range(-700,650),randf_range(50,300))
	get_tree().current_scene.add_child(shilaimu_node)
func _on_enemyspown_timer_timeout() -> void:
	var enemy_node = enemy_scene.instantiate()
	enemy_node.position = Vector2(randf_range(-700,650),randf_range(50,300))
	get_tree().current_scene.add_child(enemy_node)
