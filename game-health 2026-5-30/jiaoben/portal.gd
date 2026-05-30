extends Area2D

# 导出变量：在编辑器中设置倒计时时长（秒）
# 前两个传送门设为 10.0，后两个设为 20.0（比前两个晚 10 秒开启）
@export var activation_delay: float = 10.0

# 内部状态：标记传送门是否已激活
var is_active: bool = false

# 每个传送门使用自己内部的子节点（不再引用父节点或兄弟节点的共享资源）
@onready var timer: Timer = $Timer
@onready var destination: Node2D = $DestinationPoint
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	# 激活前隐形：隐藏传送门动画和碰撞体
	sprite.visible = false

	# 初始化定时器
	if timer:
		timer.wait_time = activation_delay
		timer.one_shot = true  # 只触发一次
		timer.timeout.connect(_on_timer_timeout)
		start_countdown()
	else:
		push_error("Portal script requires a child Timer node named 'Timer'")

# 开始倒计时的公共方法
func start_countdown() -> void:
	if not is_active and timer:
		is_active = false  # 确保状态为关闭
		timer.start()

# 倒计时结束回调 —— 传送门激活，变为可见
func _on_timer_timeout() -> void:
	is_active = true
	sprite.visible = true  # 激活后显示传送门

# 身体进入区域信号处理
func _on_body_entered(body: Node2D) -> void:
	# 只有当传送门处于激活状态时才执行传送
	if not is_active:
		return  # 如果未激活，直接返回，不执行任何操作

	if body.is_in_group("player"):
		if destination:
			body.global_position = destination.global_position
		else:
			push_warning("DestinationPoint node not found!")
