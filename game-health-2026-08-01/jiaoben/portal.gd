extends Area2D

## 传送门 — 激活后玩家走进来即可传送。
## auto_start=true:  进入场景自动倒计时（用于房间1的传送门）
## auto_start=false: 等待外部调用 start_countdown()（玩家进入某房间后触发）
## target_scene 非空: 传送时切换到目标场景而非同场景位移
signal open_ui()
var already_trigger: bool = true


@export var activation_delay: float = 10.0
@export var auto_start: bool = true
@export var target_scene: String = ""  # 例: "res://场景/control.tscn"

var is_active: bool = false

@onready var timer: Timer = $Timer
@onready var destination: Node2D = $DestinationPoint
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.visible = false

	if timer:
		timer.wait_time = activation_delay
		timer.one_shot = true
		timer.timeout.connect(_on_timer_timeout)
		if auto_start:
			start_countdown()
	else:
		push_error("Portal: 缺少 Timer 子节点")


## 开始倒计时（外部可调用）
func start_countdown() -> void:
	if is_active or not timer:
		return
	timer.start()
	print("[Portal] %s 开始 %ds 倒计时" % [name, activation_delay])


func _on_timer_timeout() -> void:
	is_active = true
	sprite.visible = true
	print("[Portal] %s 已激活" % name)


func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return
	
	if body.is_in_group("player"):
		
		if already_trigger :
			emit_signal("open_ui")
			already_trigger = false
		if target_scene != "":
			# 跨场景传送 — 设置标记让目标场景跳过主菜单
			print("[Portal] %s → 切换场景: %s" % [name, target_scene])
			get_tree().change_scene_to_file(target_scene)
		elif destination:
			# 同场景瞬移
			body.global_position = destination.global_position
		else:
			push_warning("Portal: 无目标场景也无 DestinationPoint!")
			

func _on_body_exited(body: Node2D):
	if body.is_in_group("player"):
		emit_signal("close_ui")
