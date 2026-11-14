extends Button
# 悬浮放大倍数
@export var scale_rate: float = 1.15
# 缩放过渡速度
@export var tween_speed: float = 0.1

func _ready():
	# 监听鼠标进入、离开信号
	mouse_entered.connect(on_hover)
	mouse_exited.connect(on_leave)

func on_hover():
	# 悬浮放大
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2(scale_rate, scale_rate), tween_speed)

func on_leave():
	# 离开还原
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2(1, 1), tween_speed)
