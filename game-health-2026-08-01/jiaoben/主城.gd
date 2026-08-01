extends Control
@onready var menu_layer = $MenuLayer
@onready var menu_btn = $MenuLayer/MenuButton
@onready var menu_panel = $MenuLayer/MenuPanel
@onready var restart_btn = $MenuLayer/MenuPanel/VBoxContainer/RestartBtn
@onready var close_btn = $MenuLayer/MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn = $MenuLayer/MenuPanel/VBoxContainer/QuitBtn
@onready var 角色 = $wanjia
@onready var 传送门 = $"传送门"

func _ready():
	# 菜单按钮绑定
	menu_btn.pressed.connect(_open_menu)
	restart_btn.pressed.connect(_on_restart)
	quit_btn.pressed.connect(_on_quit_game)
	close_btn.pressed.connect(_close_menu)
	menu_panel.visible = false  # 菜单默认隐藏

func _open_menu():
	menu_panel.visible = true

func _close_menu():
	menu_panel.visible = false

func _on_restart():
	_close_menu()
	角色.global_position = Vector2(-100, 200)

func _on_quit_game():
	get_tree().quit()


func _on_door_body_entered(body: Node2D) -> void:
	传送门.visible = true # Replace with function body.


func _on_door_body_exited(body: Node2D) -> void:
	传送门.visible = false # Replace with function body.


func _on_传送门_pressed() -> void:
	get_tree().change_scene_to_file("res://changjing/第一关.tscn") # Replace with function body.
