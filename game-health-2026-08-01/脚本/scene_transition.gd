#门切换逻辑
extends Node

#标记切换场景是否在进行，防止连按
var _busy = false
var _spawn_target = ""

func go_to(scene_path : String, spawn_target : String):
	if _busy or scene_path.is_empty():
		return
	_busy = true
	_spawn_target = spawn_target
	get_tree().change_scene_to_file(scene_path)
	_busy = false
	
	
func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)
	
func _on_scene_changed():
	await get_tree().process_frame
	var root = get_tree().current_scene
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
		
	var marker = root.find_child(_spawn_target,true,false)
	if !marker == null:
		player.global_position = marker.global_position
		#切换场景速度归零
		if player is CharacterBody2D:
			player.velocity = Vector2.ZERO
	
	_spawn_target = ""
