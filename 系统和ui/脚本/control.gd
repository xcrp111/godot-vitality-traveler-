extends Control

# 节点引用
@onready var menu_control = $MenuControl
@onready var main_node = $Main
@onready var start_button = $MenuControl/VBoxContainer/Start
@onready var quit_button = $MenuControl/VBoxContainer/Quit

# 1. 定义场景路径（单独抽离，方便修改）
var character_scene_path: String = "res://场景/character_body_2d.tscn"
# 2. 用于存储实例化后的角色节点（全局可用）
var character_body: CharacterBody2D = null

func _ready():
	# 绑定按钮信号
	start_button.pressed.connect(_on_start_game)
	quit_button.pressed.connect(_on_quit_game)
	
	# 初始状态
	main_node.visible = false
	menu_control.visible = true
	
	# 绑定悬停动画
	start_button.mouse_entered.connect(func(): _on_button_hover(start_button))
	start_button.mouse_exited.connect(func(): _on_button_unhover(start_button))
	quit_button.mouse_entered.connect(func(): _on_button_hover(quit_button))
	quit_button.mouse_exited.connect(func(): _on_button_unhover(quit_button))
	
	# 界面初始淡入
	modulate = Color(1, 1, 1, 0)
	var fade_in_tween = create_tween()
	fade_in_tween.tween_property(self, "modulate:a", 1, 0.5)
	fade_in_tween.set_ease(Tween.EASE_OUT)

	# ★ 删掉这行错误代码：_ready里不能直接add_child字符串路径
	# main_node.add_child(character_body)

# 开始游戏逻辑：实例化角色+添加子节点+界面切换
func _on_start_game():
	print("开始游戏，隐藏开始界面")
	
	# 1. MenuControl平滑淡出后隐藏
	var menu_fade_tween = create_tween()
	menu_fade_tween.tween_property(menu_control, "modulate:a", 0, 0.3)
	menu_fade_tween.set_ease(Tween.EASE_IN)
	menu_fade_tween.finished.connect(func():
		menu_control.visible = false
	)
	
	# 2. Main节点延迟显示并淡入
	main_node.visible = true
	main_node.modulate = Color(1, 1, 1, 0)
	var main_fade_tween = create_tween()
	main_fade_tween.tween_interval(0.1)
	main_fade_tween.tween_property(main_node, "modulate:a", 1, 0.3)
	main_fade_tween.set_ease(Tween.EASE_OUT)

	# ---------------- 核心：实例化角色场景并添加为Main的子节点 ----------------
	# 3. 加载场景资源（检查路径是否正确）
	var character_scene = load(character_scene_path)
	if character_scene == null:
		print("错误：加载角色场景失败！请检查路径：", character_scene_path)
		return
	
	# 4. 实例化场景（创建节点对象）
	character_body = character_scene.instantiate()
	if character_body == null:
		print("错误：实例化角色节点失败！")
		return
	
	# 5. 可选：设置角色初始位置（根据你的需求调整）
	character_body.global_position = Vector2(400, 300)  # 示例坐标，可改
	
	# 6. 添加为Main节点的子节点（终于正确了！）
	main_node.add_child(character_body)
	print("角色节点已成功实例化并添加为Main的子节点！")

# 退出游戏逻辑
func _on_quit_game():
	print("退出游戏")
	get_tree().quit()

# 按钮悬停动画
func _on_button_hover(button: Button):
	button.modulate = Color(1.05, 1.05, 1.05)
	button.scale = Vector2(1.03, 1.03)

func _on_button_unhover(button: Button):
	button.modulate = Color(1, 1, 1)
	button.scale = Vector2(1, 1)
