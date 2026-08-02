extends Node2D
@onready var menu_layer = $MenuLayer
@onready var menu_btn = $MenuLayer/MenuButton
@onready var menu_panel = $MenuLayer/MenuPanel
@onready var restart_btn = $MenuLayer/MenuPanel/VBoxContainer/RestartBtn
@onready var close_btn = $MenuLayer/MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn = $MenuLayer/MenuPanel/VBoxContainer/QuitBtn
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
	global_position = Vector2(640, 360)

func _on_quit_game():
	get_tree().quit()
