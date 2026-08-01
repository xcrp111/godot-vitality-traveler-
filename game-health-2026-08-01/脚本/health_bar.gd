extends ProgressBar

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
	set(val):
		current_health = clampi(val, 0, max_health)
		value = current_health
		update_fill_color()
		health_changed.emit(current_health, max_health)

# 最大血量值
@export var max_health: int = 10:
	set(val):
		max_health = maxi(val, 1)
		max_value = max_health


func _ready() -> void:
	max_value = max_health
	value = current_health
	update_fill_color()


func update_fill_color() -> void:
	var new_color: Color
	if current_health < LOW_HEALTH_THRESHOLD:
		new_color = COLOR_RED
	elif current_health < HIGH_HEALTH_THRESHOLD:
		new_color = COLOR_YELLOW
	else:
		new_color = COLOR_GREEN

	# 动态创建或更新 fill 样式
	var sb := StyleBoxFlat.new()
	sb.bg_color = new_color
	add_theme_stylebox_override(&"fill", sb)

	color_changed.emit(new_color)


func set_health(val: int) -> void:
	current_health = val


func increase_health(amount: int) -> void:
	current_health += amount


func decrease_health(amount: int) -> void:
	current_health -= amount


func reset_health() -> void:
	current_health = max_health


func get_health_percentage() -> float:
	return float(current_health) / float(max_health)
