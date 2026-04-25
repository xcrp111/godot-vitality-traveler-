
#extends Control
#
#@onready var menu_control = $MenuControl
#@onready var main_node = $Main
#@onready var start_button = $MenuControl/VBoxContainer/Start
#@onready var quit_button = $MenuControl/VBoxContainer/Quit
#
#@onready var dialog_ui = $Main/DialogUI
#@onready var left_box = $Main/DialogUI/LeftBox
#@onready var left_name = $Main/DialogUI/LeftName
#@onready var left_text = $Main/DialogUI/LeftText
#@onready var right_box = $Main/DialogUI/RightBox	
#@onready var right_name = $Main/DialogUI/RightName
#@onready var right_text = $Main/DialogUI/RightText
#@onready var dialog_close_btn = $Main/DialogUI/CloseBtn
#
#@onready var interact_btn = $Main/InteractBtn
#@onready var coin_label = $Main/CoinLabel
#
#@onready var exit_button = $ExitLayer/ExitButton
#
#var character_path = "res://场景/character_body_2d.tscn"
#var character: CharacterBody2D = null
#
#var coin := 0
#var can_move := true
#
#var dialogs = [
	#["left", "生命行者", "对对对"],
	#["right", "导师", "错错错"],
	#["left", "生命行者", "对对对"],
	#["right", "导师", "错错错"],
	#["left", "生命行者", "对对对"],
	#["right", "导师", "错错错"]
#]
#
#var current = 0
#var is_typing = false
#var type_speed = 0.02
#
## ------------------------------
## 初始化
## ------------------------------
#func _ready():
	## 绑定按钮信号
	#start_button.pressed.connect(_on_start_game)
	#quit_button.pressed.connect(_on_quit_game)
	#exit_button.pressed.connect(_on_quit_game)
	#dialog_close_btn.pressed.connect(_close_dialog)
	#interact_btn.pressed.connect(_on_interact)
#
	## 初始状态设置
	#main_node.visible = false
	#menu_control.visible = true
	#dialog_ui.visible = false
	#interact_btn.visible = false
	#$Main/SkillBook.visible = false
	#$Main/CoinLabel.visible = false
#
	## 【关键】在 control.gd 里直接监听 SkillBook 的碰撞信号！
	#var skill_book = $Main/SkillBook
	#skill_book.body_entered.connect(_on_skill_book_body_entered)
	#skill_book.body_exited.connect(_on_skill_book_body_exited)
#
## ------------------------------
## 开始游戏
## ------------------------------
## 角色碰到技能书时调用
#
#func show_interact_button():
	#print(2)
	#if dialog_ui.visible:
		#return
	#interact_btn.visible = true
#
## 隐藏交互按钮
#func hide_interact_button():
	#interact_btn.visible = false
#
#func _on_skill_book_body_entered(body):
	#print("【碰撞】角色碰到了技能书：", body.name)
	#if body.name == "player":
		#show_interact_button()
		#print("【UI】调用 show_interact_button() 成功，打印2")
#
## 角色离开技能书时调用
#func _on_skill_book_body_exited(body):
	#print("【碰撞】角色离开了技能书：", body.name)
	#if body.name == "player":
		#hide_interact_button()
#
#func _on_start_game():
	#menu_control.visible = false
	#main_node.visible = true
	#dialog_ui.visible = true
#
	#dialog_ui.modulate = Color(1,1,1,0)
	#main_node.modulate = Color(1,1,1,0)
#
	#var fade = create_tween()
	#fade.tween_property(dialog_ui, "modulate:a", 1, 0.4)
	#fade.tween_property(main_node, "modulate:a", 1, 0.4)
	#fade.finished.connect(func(): show_next())
#
## ------------------------------
## 对话核心
## ------------------------------
#func show_next():
	#can_move = false
#
	#if current >= dialogs.size():
		#dialog_ui.visible = false
		#$Main/SkillBook.visible = true
		#$Main/CoinLabel.visible = true
		#$Main/InteractBtn.visible = false
		#can_move = true
		#spawn_character()
		#return
#
	#hide_all_dialog()
	#var side = dialogs[current][0]
	#@warning_ignore("shadowed_variable_base_class")
	#var name = dialogs[current][1]
	#var text = dialogs[current][2]
#
	#is_typing = true
#
	#if side == "left":
		#left_box.visible = true
		#left_name.text = name
		#left_text.text = ""
		#@warning_ignore("redundant_await")
		#await get_tree().create_timer(0.05)
		#type_text(left_text, text)
	#else:
		#right_box.visible = true
		#right_name.text = name
		#right_text.text = ""
		#@warning_ignore("redundant_await")
		#await get_tree().create_timer(0.05)
		#type_text(right_text, text)
#
	#is_typing = false
	#current += 1
#
## ------------------------------
## 打字机效果
## ------------------------------
#func type_text(label, full):
	#for i in range(full.length()):
		#if not is_typing:
			#label.text = full
			#return
		#label.text = full.substr(0, i+1)
		#@warning_ignore("redundant_await")
		#await get_tree().create_timer(type_speed)
#
## ------------------------------
## 隐藏所有对话气泡
## ------------------------------
#func hide_all_dialog():
	#left_box.visible = false
	#right_box.visible = false
	#left_text.text = ""
	#right_text.text = ""
#
## ------------------------------
## 鼠标点击继续对话
## ------------------------------
#func _input(event: InputEvent) -> void:
	#if not dialog_ui.visible:
		#return
	#if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		#if is_typing:
			#is_typing = false
		#else:
			#show_next()
#
## ------------------------------
## 生成角色
## ------------------------------
#func spawn_character():
	#if character != null and is_instance_valid(character):
		#print("角色已经存在，跳过重复生成")
		#return
	#var s = load(character_path)
	#if s:
		#character = s.instantiate()
		#main_node.add_child(character)
		#character.global_position = Vector2(640, 360)
#
## ------------------------------
## 关闭对话
## ------------------------------
#func _close_dialog():
	#dialog_ui.visible = false
	#can_move = true
#
## ------------------------------
## 交互按钮（暂时空着，后面用）
## ------------------------------
#func _on_interact():
	#hide_interact_button()
	#can_move = false
	#dialog_ui.visible = true
	## 这里可以放你想要的技能书对话
	#dialogs = [["left", "技能书", "你获得了新能力！"]]
	#current = 0
	#show_next()
	#
#
## 显示交互按钮
#
## ------------------------------
## 退出游戏
## ------------------------------
#func _on_quit_game():
	#get_tree().quit()
extends Control

# 菜单 CanvasLayer（固定右下角）
# 菜单相关
@onready var menu_layer = $MenuLayer
@onready var menu_btn = $MenuLayer/MenuButton
@onready var menu_panel = $MenuLayer/MenuPanel
@onready var restart_btn = $MenuLayer/MenuPanel/VBoxContainer/RestartBtn
@onready var close_btn = $MenuLayer/MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn = $MenuLayer/MenuPanel/VBoxContainer/QuitBtn

# 你原来的引用
@onready var menu_control = $MenuControl
@onready var main_node = $Main
@onready var start_button = $MenuControl/VBoxContainer/Start
@onready var quit_button = $MenuControl/VBoxContainer/Quit

@onready var dialog_ui = $Main/DialogUI
@onready var left_box = $Main/DialogUI/LeftBox
@onready var left_name = $Main/DialogUI/LeftName
@onready var left_text = $Main/DialogUI/LeftText
@onready var right_box = $Main/DialogUI/RightBox	
@onready var right_name = $Main/DialogUI/RightName
@onready var right_text = $Main/DialogUI/RightText
@onready var dialog_close_btn = $Main/DialogUI/CloseBtn

@onready var interact_btn = $Main/InteractBtn
@onready var coin_label = $MenuLayer/MenuButton



var character_path = "res://场景/character_body_2d.tscn"
var character: CharacterBody2D = null

var coin := 0
var can_move := true

var dialogs = [
	["left", "生命行者", "对对对"],
	["right", "导师", "错错错"],
	["left", "生命行者", "对对对"],
	["right", "导师", "错错错"],
	["left", "生命行者", "对对对"],
	["right", "导师", "错错错"]
]

var current = 0
var is_typing = false
var type_speed = 0.02

# ------------------------------
# 初始化
# ------------------------------
func _ready():
	start_button.pressed.connect(_on_start_game)
	quit_button.pressed.connect(_on_quit_game)
	dialog_close_btn.pressed.connect(_close_dialog)
	interact_btn.pressed.connect(_on_interact)

	# 菜单按钮绑定
	menu_btn.pressed.connect(_open_menu)      
	restart_btn.pressed.connect(_on_restart)
	quit_btn.pressed.connect(_on_quit_game)
	close_btn.pressed.connect(_close_menu)

	# 初始状态
	main_node.visible = false
	menu_control.visible = true
	dialog_ui.visible = false
	interact_btn.visible = false
	$Main/SkillBook.visible = false
	$Main/CoinLabel.visible = false
	menu_panel.visible = false  # 菜单默认隐藏

	# 技能书碰撞
	var skill_book = $Main/SkillBook
	skill_book.body_entered.connect(_on_skill_book_body_entered)
	skill_book.body_exited.connect(_on_skill_book_body_exited)

# ------------------------------
# 打开 / 关闭菜单（CanvasLayer）
# ------------------------------
func _open_menu():
	menu_panel.visible = true
	can_move = false

func _close_menu():
	menu_panel.visible = false
	can_move = true

# ------------------------------
# 重新开始 → 回到游戏主界面
# ------------------------------
func _on_restart():
	_close_menu()
	dialog_ui.visible = false
	$Main/SkillBook.visible = true
	$Main/CoinLabel.visible = true
	can_move = true
	current = dialogs.size()

	if not is_instance_valid(character):
		spawn_character()
	character.global_position = Vector2(640, 360)

# ------------------------------
# 技能书交互
# ------------------------------
func show_interact_button():
	if dialog_ui.visible or menu_panel.visible:
		return
	interact_btn.visible = true

func hide_interact_button():
	interact_btn.visible = false

func _on_skill_book_body_entered(body):
	if body.name == "player":
		show_interact_button()

func _on_skill_book_body_exited(body):
	if body.name == "player":
		hide_interact_button()

# ------------------------------
# 下面全部是你原来的逻辑，不动
# ------------------------------
func _on_start_game():
	menu_control.visible = false
	main_node.visible = true
	dialog_ui.visible = true

	dialog_ui.modulate = Color(1,1,1,0)
	main_node.modulate = Color(1,1,1,0)

	var fade = create_tween()
	fade.tween_property(dialog_ui, "modulate:a", 1, 0.4)
	fade.tween_property(main_node, "modulate:a", 1, 0.4)
	fade.finished.connect(func(): show_next())

func show_next():
	can_move = false

	if current >= dialogs.size():
		dialog_ui.visible = false
		$Main/SkillBook.visible = true
		$Main/CoinLabel.visible = true
		$Main/InteractBtn.visible = false
		can_move = true
		spawn_character()
		return

	hide_all_dialog()
	var side = dialogs[current][0]
	var name = dialogs[current][1]
	var text = dialogs[current][2]

	is_typing = true
	if side == "left":
		left_box.visible = true
		left_name.text = name
		left_text.text = ""
		await get_tree().create_timer(0.05)
		type_text(left_text, text)
	else:
		right_box.visible = true
		right_name.text = name
		right_text.text = ""
		await get_tree().create_timer(0.05)
		type_text(right_text, text)

	is_typing = false
	current += 1

func type_text(label, full):
	for i in range(full.length()):
		if not is_typing:
			label.text = full
			return
		label.text = full.substr(0, i+1)
		await get_tree().create_timer(type_speed)

func hide_all_dialog():
	left_box.visible = false
	right_box.visible = false
	left_text.text = ""
	right_text.text = ""

func _input(event: InputEvent) -> void:
	if dialog_ui.visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_typing:
			is_typing = false
		else:
			show_next()

func spawn_character():
	if character != null and is_instance_valid(character):
		return
	var s = load(character_path)
	if s:
		character = s.instantiate()
		main_node.add_child(character)
		character.global_position = Vector2(640, 360)

func _close_dialog():
	dialog_ui.visible = false
	can_move = true

func _on_interact():
	hide_interact_button()
	can_move = false
	dialog_ui.visible = true
	dialogs = [["left", "技能书", "你获得了新能力！"]]
	current = 0
	show_next()

func _on_quit_game():
	get_tree().quit()
