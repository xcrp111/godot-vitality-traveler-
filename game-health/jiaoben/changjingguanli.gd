extends Node2D
## 第一关场景管理器 — 负责菜单、重新开始、分数等关卡逻辑。
## 敌人生成已迁移到 EnemySpawner 组件（res://jiaoben/enemy_spawner.gd），
## 请在编辑器中给场景添加 EnemySpawner 节点并配置房间区域和敌人类型。

@export var score : int = 0

@onready var menu_layer = $MenuLayer
@onready var menu_btn = $MenuLayer/MenuButton
@onready var menu_panel = $MenuLayer/MenuPanel
@onready var restart_btn = $MenuLayer/MenuPanel/VBoxContainer/RestartBtn
@onready var close_btn = $MenuLayer/MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn = $MenuLayer/MenuPanel/VBoxContainer/QuitBtn
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
	get_tree().reload_current_scene()

func _on_quit_game():
	get_tree().quit()


## 加分方法（供敌人死亡时调用）
func add_score(amount: int) -> void:
	score += amount
