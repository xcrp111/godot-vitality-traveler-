extends Control

@onready var 第一关按钮 = $"第一关"
@onready var 第二关按钮 = $"第二关"


func _on_door_body_entered(body: Node2D) -> void:
	第一关按钮.visible = true
	第二关按钮.visible = true


func _on_door_body_exited(body: Node2D) -> void:
	第一关按钮.visible = false
	第二关按钮.visible = false


func _on_第一关_pressed() -> void:
	get_tree().change_scene_to_file("res://changjing/第一关.tscn")


func _on_第二关_pressed() -> void:
	get_tree().change_scene_to_file("res://changjing/第二关.tscn")
