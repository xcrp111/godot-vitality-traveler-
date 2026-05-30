extends CharacterBody2D
# 导出变量，方便在编辑器中调整
@export var speed: float = 70.0
@export var hp: float = 15
@export var death_duration: float = 0.6
var mouse_pos: Vector2 = get_global_mouse_position()
# 内部状态
var is_dead: bool = false
var direction: int = -1 # -1 向左, 1 向右
@export var shilaimu_scene: PackedScene #死亡掉落预设？
func _ready():
	add_to_group("enemy")
	# 初始方向向左
	direction = -1
	velocity.x = speed * direction
func _physics_process(delta: float) -> void:
	if is_dead:
		return
	# 移动角色
	move_and_slide()
	# 简单的边界检查与转向逻辑
	# 如果超出屏幕左边界或右边界，或者检测到墙壁碰撞，则转向
	check_wall_collision()
	# 如果因为碰撞改变了方向，更新速度
	if velocity.x == 0:
		# 如果速度为0（被卡住或刚转向），重新赋予速度
		direction *= -1
		velocity.x = speed * direction
	if $AnimatedSprite2D:
		if direction == -1:
			$AnimatedSprite2D.flip_h = true
		else:
			$AnimatedSprite2D.flip_h = false
# 检测墙壁碰撞并转向
func check_wall_collision():
	if position.x < mouse_pos.x - 1000:
		queue_free() # 超出左边界销毁
	elif position.x > mouse_pos.x + 1000: # 假设右边界
		queue_free()
	# 基于 RayCast2D 或 get_slide_collision 的更精确转向
	# 这里使用 move_and_slide 后的碰撞信息来判断是否撞墙
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		# 如果撞到的是静态身体或砖块等障碍物
		if collider is TileMap :
			if !collider.is_in_group("zidan"):
			# 简单的转向逻辑：反转方向
				direction *= -1
				velocity.x = speed * direction
			# 稍微推开一点防止粘连
				position.x += direction * 2 
				break
# 处理与其他身体的碰撞（如玩家）

	if is_dead: return
# 避免怪物死亡后仍能触发伤害和逻辑（比如可能导致计分错误）
func _on_area_2d_area_entered(area: Area2D) -> void:
	if is_dead:
		return
	if area.is_in_group("zidan"):
		hp -= 10
		area.queue_free() # 子弹销毁
	elif area.is_in_group("hanbingjian"):
		hp -= 10
		# 减速效果
		speed *= 0.75
		velocity.x = speed * direction
	if hp <= 0:
		is_dead = true
		$AnimatedSprite2D.play("siwang")
		# 增加分数
		if get_tree().current_scene.has_method("add_score"):
			get_tree().current_scene.add_score(1)
		elif get_tree().current_scene.has_node("ScoreLabel"): # 假设场景中有分数标签
			pass # 具体加分逻辑依主场景而定
		# 停止移动
		velocity = Vector2.ZERO
		# 延迟销毁
		await get_tree().create_timer(death_duration).timeout
		queue_free()
		
