extends Control

# 菜单已迁移到 res://场景/menu.tscn（全局复用）

@onready var menu_control = $MenuControl
@onready var main_node = $Main
@onready var start_button = $MenuControl/VBoxContainer/Start
@onready var quit_button = $MenuControl/VBoxContainer/Quit

@onready var dialog_ui = $Main/DialogUI
@onready var left_box = $"Main/DialogUI/1"
@onready var left_name = $Main/DialogUI/LeftName
@onready var left_text = $Main/DialogUI/LeftText
@onready var right_box = $"Main/DialogUI/2"
@onready var right_name = $Main/DialogUI/RightName
@onready var right_text = $Main/DialogUI/RightText
@onready var dialog_close_btn = $Main/DialogUI/CloseBtn

@onready var interact_btn = $Main/InteractBtn
@onready var interact_btn1 = $Main/InteractBtn1
@onready var interact_btn2 = $Main/InteractBtn2

var character_path = "res://changjing/fashi.tscn"
var character: CharacterBody2D = null

var coin := 0
var can_move := true

var dialogs = [
	["left", "生命行者", "医生说查不出病因，现代医学…… 已经无能为力了。"],
	["left", "生命行者", "身体还在呼吸，可意识像被什么东西拽进了无底的黑暗，再也醒不过来。"],
	["right", "导师", "别放弃，孩子。你的意识从未消失，只是被困在了「内境」。"],
	["left", "生命行者", "内境？那是什么？您是谁？"],
	["right", "导师", "我是前任生命行者，你可以叫我导师。"],
	["right", "导师", "而你，拥有罕见的「意识投射」体质 —— 这是成为生命行者的天赋。"],
	["right", "导师", "只有踏入内境，净化那些滋生的病魔，才能把你的意识拉回现实。"],
	["left", "生命行者", "生命行者？讨伐病魔？"],
	["left", "生命行者", "我…… 我从来不知道自己有这样的能力，我该怎么做？"],
	["right", "导师", "跟我来。我会带你前往生命行者的大本营，教你所有你需要知道的事。"],
	["right", "导师", "你的救赎，从成为真正的生命行者开始。"]
]

var current = 0
var is_typing = false
var type_speed = 0.02

func _ready():
	start_button.pressed.connect(_on_start_game)
	quit_button.pressed.connect(_on_quit_game)
	dialog_close_btn.pressed.connect(_close_dialog)
	interact_btn.pressed.connect(_on_interact)
	interact_btn1.pressed.connect(_on_interact1)
	interact_btn2.pressed.connect(_on_interact2)

	main_node.visible = false
	menu_control.visible = true
	dialog_ui.visible = false
	interact_btn.visible = false
	interact_btn1.visible = false
	interact_btn2.visible = false
	$Main/SkillBook.visible = false
	$Main/CoinLabel.visible = false
	$Main/door.visible = false

	var skill_book = $Main/SkillBook
	skill_book.body_entered.connect(_on_skill_book_body_entered)
	skill_book.body_exited.connect(_on_skill_book_body_exited)

	var door = $Main/door
	door.body_entered.connect(_on_door_body_entered)
	door.body_exited.connect(_on_door_body_exited)


# --- 技能书 ---
func show_interact_button():
	if dialog_ui.visible:
		return
	interact_btn.visible = true

func hide_interact_button():
	interact_btn.visible = false

func _on_skill_book_body_entered(body):
	if body.name == "wanjia":
		show_interact_button()

func _on_skill_book_body_exited(body):
	if body.name == "wanjia":
		hide_interact_button()

# --- 传送门 ---
func show_interact_button1():
	if dialog_ui.visible:
		return
	interact_btn1.visible = true
	interact_btn2.visible = true

func hide_interact_button1():
	interact_btn1.visible = false
	interact_btn2.visible = false

func _on_door_body_entered(body):
	if body.name == "wanjia":
		show_interact_button1()

func _on_door_body_exited(body):
	if body.name == "wanjia":
		hide_interact_button1()

func _on_interact_btn_1_button_down() -> void:
	get_tree().change_scene_to_file("res://changjing/第一关.tscn")

func _on_interact_btn_2_button_down() -> void:
	get_tree().change_scene_to_file("res://changjing/第二关.tscn")

# --- 对话 ---
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
		$Main/door.visible = true
		$Main/CoinLabel.visible = true
		$Main/InteractBtn.visible = false
		$Main/InteractBtn1.visible = false
		$Main/InteractBtn2.visible = false
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

func _on_interact1():
	hide_interact_button1()

func _on_interact2():
	hide_interact_button1()

func _on_quit_game():
	get_tree().quit()
