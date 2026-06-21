extends Node2D
@export var shilaimu_scene : PackedScene
@export var enemy_scene : PackedScene
@export var score : int = 0

@onready var menu_layer = $"菜单"
@onready var menu_btn = $"菜单/MenuButton"
@onready var menu_panel = $"菜单/MenuPanel"
@onready var restart_btn = $"菜单/MenuPanel/VBoxContainer/RestartBtn"
@onready var close_btn = $菜单/MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn = $菜单/MenuPanel/VBoxContainer/QuitBtn
@onready var 角色 = $wanjia
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

# Called when the node enters the scene tree for the first time.



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
