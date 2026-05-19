extends Area2D

# 导出变量：在编辑器中设置倒计时时长（秒）
@export var activation_delay: float = 5.0

# 内部状态：标记传送门是否已激活
var is_active: bool = false

# 引用子节点
# 注意：确保场景中有一个名为 "Timer" 的 Timer 节点
# 和一个名为 "DestinationPoint" 的 Node2D (或 Marker2D) 节点
@onready var timer: Timer = $"../Timer"
@onready var destination: Node2D = $"../portal4/DestinationPoint"

func _ready() -> void:
	# 初始化定时器
	if timer:
		timer.wait_time = activation_delay
		timer.one_shot = true # 只触发一次
		# 连接 timeout 信号到激活函数
		timer.timeout.connect(_on_timer_timeout)
		# 如果希望场景加载后立即开始倒计时，取消下面这行的注释
		start_countdown()
	else:
		push_error("Portal script requires a child Timer node named 'Timer'")

# 开始倒计时的公共方法
func start_countdown() -> void:
	if not is_active and timer:
		is_active = false # 确保状态为关闭
		timer.start()

# 倒计时结束回调
func _on_timer_timeout() -> void:
	is_active = true

# 身体进入区域信号处理
func _on_body_entered(body: Node2D) -> void:
	# 关键修改：只有当传送门处于激活状态时才执行传送
	if not is_active:
		return # 如果未激活，直接返回，不执行任何操作
		
	if body.is_in_group("player"):
		if destination:
			body.global_position = destination.global_position
		else:
			push_warning("DestinationPoint node not found!")
