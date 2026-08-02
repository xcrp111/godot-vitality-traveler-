extends TextureProgressBar



# 信号：当血量变化时发出
signal health_changed(current_health: int, max_health: int)
# 信号：当血量颜色变化时发出
signal color_changed(new_color: Color)

# 血量阈值常量
const LOW_HEALTH_THRESHOLD := 3
const HIGH_HEALTH_THRESHOLD := 7

# 颜色常量
const COLOR_RED := Color(1.0, 0.2, 0.2)      # 红色
const COLOR_YELLOW := Color(1.0, 0.9, 0.2)   # 黄色
const COLOR_GREEN := Color(0.2, 1.0, 0.2)    # 绿色

# 当前血量值
@export var current_health: int = 10:
	set(value):
		# 限制血量在有效范围内
		current_health = clamp(value, 0, max_health)
		# 更新进度条显示
		value = current_health
		# 更新颜色
		update_color()
		# 发出信号
		health_changed.emit(current_health, max_health)

# 最大血量值
@export var max_health: int = 10:
	set(value):
		max_health = max(value, 1)  # 确保最大血量至少为1
		max_value = max_health

# 进度条前景节点（用于修改颜色）
@onready var progress_bar: TextureRect = $Progress

func _ready() -> void:
	# 初始化进度条
	max_value = max_health
	value = current_health
	# 初始颜色设置
	update_color()

# 更新血量颜色
func update_color() -> void:
	var new_color: Color
	
	# 根据当前血量选择颜色
	if current_health <= LOW_HEALTH_THRESHOLD:
		new_color = COLOR_RED
	elif current_health <= HIGH_HEALTH_THRESHOLD:
		new_color = COLOR_YELLOW
	else:
		new_color = COLOR_GREEN
	
	# 应用颜色修改
	if progress_bar:
		# 方法1：直接修改前景纹理的模组颜色
		progress_bar.modulate = new_color
		
		# 方法2：如果有自定义着色器，可以这样设置
		# material.set_shader_parameter("progress_color", new_color)
		
		# 发出颜色变化信号
		color_changed.emit(new_color)

# 设置血量（外部调用）
func set_health(value: int) -> void:
	current_health = value

# 增加血量
func increase_health(amount: int) -> void:
	current_health += amount

# 减少血量
func decrease_health(amount: int) -> void:
	current_health -= amount

# 重置血量到最大值
func reset_health() -> void:
	current_health = max_health

# 获取当前血量百分比
func get_health_percentage() -> float:
	return float(current_health) / float(max_health)

# 测试用：演示颜色变化
func test_color_change() -> void:
	# 测试不同血量下的颜色
	print("测试血量颜色变化：")
	
	current_health = 10
	print("血量10：", get_health_color_string())
	
	current_health = 5
	print("血量5：", get_health_color_string())
	
	current_health = 2
	print("血量2：", get_health_color_string())

func get_health_color_string() -> String:
	match current_health:
		var _h when _h <= LOW_HEALTH_THRESHOLD:
			return "红色（危险）"
		var _h when _h <= HIGH_HEALTH_THRESHOLD:
			return "黄色（警告）"
		_:
			return "绿色（安全）"
