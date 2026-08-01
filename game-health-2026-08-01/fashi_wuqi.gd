extends Node2D
<<<<<<< Updated upstream:game-health/fashi_wuqi.gd
=======

#菜单按钮
@onready var menu_layer = $MenuLayer
@onready var menu_btn = $MenuLayer/MenuButton
@onready var menu_panel = $MenuLayer/MenuPanel
@onready var restart_btn = $MenuLayer/MenuPanel/VBoxContainer/RestartBtn
@onready var close_btn = $MenuLayer/MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn = $MenuLayer/MenuPanel/VBoxContainer/QuitBtn
@onready var 角色 = $wanjia

>>>>>>> Stashed changes:game-health-2026-08-01/fashi_wuqi.gd
var zidan_dir = Vector2.ZERO
var is_game_over : bool = false
@export var zidan_scene : PackedScene
@export var hanbingjian_scene :PackedScene
@export var shilaimu_scene : PackedScene

<<<<<<< Updated upstream:game-health/fashi_wuqi.gd
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
=======
func _ready() -> void:
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


>>>>>>> Stashed changes:game-health-2026-08-01/fashi_wuqi.gd
func _physics_process(delta: float) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	look_at(mouse_pos)

func _on_fire() -> void:
	if is_game_over:
		return
	if Input.is_action_pressed("attack"):
		fire_bullet()
	if Input.is_action_pressed("hanbingjian"):
		var hanbingjian_node = hanbingjian_scene.instantiate()
		hanbingjian_node.position = position + Vector2(60,60)
		get_tree().current_scene.add_child(hanbingjian_node)


func fire_bullet() -> void:
	if zidan_scene:
		var zidan: Node2D = zidan_scene.instantiate()
		zidan.global_position = global_position + Vector2(60,60)
		zidan.rotation = rotation
		get_parent().add_child(zidan)
