extends Area2D
@onready var 面板按钮 = $Button
var panel_scene = preload("res://场景/人物面板.tscn")
func _on_body_entered(body: Node2D) -> void:
	面板按钮.visible = true # Replace with function body.

func _on_body_exited(body: Node2D) -> void:
	面板按钮.visible = false # Replace with function body.

func _on_button_pressed() -> void:
	
	get_tree().change_scene_to_file("res://场景/人物面板.tscn") # Replace with function body.
