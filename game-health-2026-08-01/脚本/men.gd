extends Area2D

@export_file(".tscn") var target_scene : String = ""
@export var spawn_target :String = ""


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not _is_player_near():
		return
	SceneTransition.go_to(target_scene,spawn_target)
	
func _is_player_near():
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false
