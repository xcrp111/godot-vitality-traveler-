extends Node2D

@onready var menu_layer = $MenuLayer
@onready var menu_btn = $MenuLayer/MenuButton

func _on_menu_button_pressed() -> void:
	
	get_tree().change_scene_to_file("res://场景/主城.tscn")
	
