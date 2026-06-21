extends Button

# 缩放参数（可自行调整）
var base_scale: Vector2 = Vector2(1, 1)
var hover_scale: Vector2 = Vector2(0.9, 0.9)  # 悬浮放大10%
var press_scale: Vector2 = Vector2(1.1, 1.1)   # 点击缩小10%

func _ready():
	base_scale = scale
	# 绑定信号
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	pressed.connect(_on_press)
	button_up.connect(_on_release)

# 鼠标悬浮：放大
func _on_hover():
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", hover_scale, 0.1)

# 鼠标离开：还原
func _on_exit():
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", base_scale, 0.1)

# 鼠标按下：缩小
func _on_press():
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", press_scale, 0.05)

# 鼠标松开：恢复
func _on_release():
	if is_hovered():
		_on_hover()
	else:
		_on_exit()
