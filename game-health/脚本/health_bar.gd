extends ProgressBar

signal health_changed(current_health: int, max_health: int)
signal color_changed(new_color: Color)

const LOW_HEALTH_THRESHOLD := 3
const HIGH_HEALTH_THRESHOLD := 7

const COLOR_RED := Color(1.0, 0.2, 0.2)
const COLOR_YELLOW := Color(1.0, 0.9, 0.2)
const COLOR_GREEN := Color(0.2, 1.0, 0.2)

@export var current_health: int = 10:
	set(val):
		current_health = clampi(val, 0, max_health)
		value = current_health
		update_fill_color()
		health_changed.emit(current_health, max_health)

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

	var sb := StyleBoxFlat.new()
	sb.bg_color = new_color
	add_theme_stylebox_override(&"fill", sb)
	color_changed.emit(new_color)


func set_health(val: int) -> void: current_health = val
func increase_health(amount: int) -> void: current_health += amount
func decrease_health(amount: int) -> void: current_health -= amount
func reset_health() -> void: current_health = max_health
func get_health_percentage() -> float: return float(current_health) / float(max_health)
