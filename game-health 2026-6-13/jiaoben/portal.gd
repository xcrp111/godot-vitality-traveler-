#extends Area2D
#
### 传送门 — 激活后玩家走进来即可传送。
### auto_start=true:  进入场景自动倒计时（用于房间1的传送门）
### auto_start=false: 等待外部调用 start_countdown()（玩家进入某房间后触发）
### target_scene 非空: 传送时切换到目标场景而非同场景位移
#
#@export var activation_delay: float = 10.0
#@export var auto_start: bool = true
#@export var target_scene: String = ""  # 例: "res://场景/control.tscn"
#
#var is_active: bool = false
#
#@onready var timer: Timer = $Timer
#@onready var destination: Node2D = $DestinationPoint
#@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
#
#
#func _ready() -> void:
	#sprite.visible = false
#
	#if timer:
		#timer.wait_time = activation_delay
		#timer.one_shot = true
		#timer.timeout.connect(_on_timer_timeout)
		#if auto_start:
			#start_countdown()
	#else:
		#push_error("Portal: 缺少 Timer 子节点")
#
#
### 开始倒计时（外部可调用）
#func start_countdown() -> void:
	#if is_active or not timer:
		#return
	#timer.start()
	#print("[Portal] %s 开始 %ds 倒计时" % [name, activation_delay])
#
#
#func _on_timer_timeout() -> void:
	#is_active = true
	#sprite.visible = true
	#print("[Portal] %s 已激活" % name)
#
#
#func _on_body_entered(body: Node2D) -> void:
	#if not is_active:
		#return
#
	#if body.is_in_group("player"):
		#if target_scene != "":
			## 跨场景传送 — 设置标记让目标场景跳过主菜单
			#print("[Portal] %s → 切换场景: %s" % [name, target_scene])
			#get_tree().change_scene_to_file(target_scene)
		#elif destination:
			## 同场景瞬移
			#body.global_position = destination.global_position
		#else:
			#push_warning("Portal: 无目标场景也无 DestinationPoint!")
extends Area2D

@export var activation_delay: float = 10.0
@export var auto_start: bool = true
@export var target_scene: String = ""

var is_active: bool = false
var is_selecting: bool = false

@onready var timer: Timer = $Timer
@onready var destination: Node2D = $DestinationPoint
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# 导出变量，编辑器拖拽绑定，不用写路径
@export var select_panel: Panel
@export var btn_effect1: Button
@export var btn_effect2: Button
@export var btn_effect3: Button

var player_node: Node2D = null


func _ready() -> void:
	sprite.visible = false

	if select_panel:
		select_panel.visible = false
		select_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	if timer:
		timer.wait_time = activation_delay
		timer.one_shot = true
		timer.timeout.connect(_on_timer_timeout)
		if auto_start:
			start_countdown()
	else:
		push_error("Portal: 缺少 Timer 子节点")

	_bind_button_signal()

	# 调试打印
	print("是否找到Panel: ", select_panel != null)
	print("是否找到按钮1: ", btn_effect1 != null)


func start_countdown() -> void:
	if is_active or not timer:
		return
	timer.start()
	print("[Portal] %s 开始 %ds 倒计时" % [name, activation_delay])


func _on_timer_timeout() -> void:
	is_active = true
	sprite.visible = true
	print("[Portal] %s 已激活" % name)


func _bind_button_signal():
	if btn_effect1:
		btn_effect1.pressed.connect(_choose_effect1)
	if btn_effect2:
		btn_effect2.pressed.connect(_choose_effect2)
	if btn_effect3:
		btn_effect3.pressed.connect(_choose_effect3)


func _on_body_entered(body: Node2D) -> void:
	if not is_active or is_selecting:
		return

	if body.is_in_group("player"):
		print("玩家进入传送门，准备打开面板")
		is_selecting = true
		player_node = body
		
		Engine.time_scale = 0.0
		
		if select_panel:
			select_panel.visible = true
			print("面板已设置为显示")
		else:
			_do_transport()


func _choose_effect1():
	if player_node:
		print("选择了加血效果")
		# 你的加血逻辑
	player_node.hp_p += 5
	player_node.hp_bar.max_value = player_node.hp_p
	player_node.hp_bar.value = player_node.hp_p
	_close_ui_and_transport()

func _choose_effect2():
	if player_node:
		print("选择了加蓝效果")
		# 你的加蓝逻辑
	player_node.max_mp += 20
	player_node.current_mp += 20
	player_node.mp_bar.max_value = player_node.max_mp
	player_node.mp_bar.value = player_node.current_mp
	_close_ui_and_transport()

func _choose_effect3():
	if player_node:
		print("选择了加移速效果")
		# 你的移速逻辑
	player_node.move_speed *= 1.3
	_close_ui_and_transport()


func _close_ui_and_transport():
	if select_panel:
		select_panel.visible = false
	Engine.time_scale = 1.0
	
	_do_transport()

	# 正确的延时写法
	var delay_timer = get_tree().create_timer(0.3)
	await delay_timer.timeout

	is_selecting = false
	player_node = null


func _do_transport():
	if target_scene != "":
		print("[Portal] %s → 切换场景: %s" % [name, target_scene])
		get_tree().change_scene_to_file(target_scene)
	elif destination and player_node:
		player_node.global_position = destination.global_position
		print("[Portal] %s → 同场景瞬移" % name)
	else:
		push_warning("Portal: 无目标场景也无 DestinationPoint!")
