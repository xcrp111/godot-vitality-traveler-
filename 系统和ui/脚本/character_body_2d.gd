extends CharacterBody2D

# 可调节的移动参数（70偏小，建议调高，检查器可修改）
@export var speed: float = 300.0  # 调高速度，避免“看似不动”
@onready var animated_sprite = $AnimatedSprite2D
func _physics_process(delta: float) -> void:
	# 1. 获取方向输入（Input.get_axis参数：负方向，正方向）
	# x轴：左=负，右=正；y轴：上=负，下=正（符合Godot坐标系）
	var dir_x: float = Input.get_axis("move_left", "move_right")
	var dir_y: float = Input.get_axis("move_up", "move_down")
	var dir: Vector2 = Vector2(dir_x, dir_y)

	# 2. 设置移动速度（无输入时速度为0）
	if dir != Vector2.ZERO:
		velocity = dir.normalized() * speed  # 归一化避免斜移过快
	else:
		velocity = Vector2.ZERO  # 无输入时清空速度，避免漂移

	# 3. 执行物理移动（核心：必须有碰撞形状才会生效）
	move_and_slide()
	if dir.x != 0:  # 仅在有水平输入时触发翻转
		# 向右移动：scale.x为正（正向）；向左移动：scale.x为负（镜像）
		# abs(sprite.scale.x) 保留精灵原本的缩放大小，避免越翻越小
		animated_sprite.scale.x = abs(animated_sprite.scale.x) * dir.x
