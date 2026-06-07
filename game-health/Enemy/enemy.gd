extends CharacterBody2D
# 导出变量，方便在编辑器中调整
@export var speed: float = 70.0
@export var hp: float = 15
@export var death_duration: float = 0.6
@export var bounce_force: float = 60.0 # 碰撞时的额外反弹力
# 内部状态
var is_dead: bool = false
var direction: int = -1 # -1 向左, 1 向右
@export var shilaimu_scene: PackedScene #死亡掉落预设？
func _ready():
	# 初始方向向左
	direction = -1
	velocity.x = speed * direction
	add_to_group("enemy")
func _physics_process(delta: float) -> void:
	handle_collisions()
	move_and_slide()
	if is_dead:
		return
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
		
func handle_collisions():
	# 遍历所有发生的碰撞
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		# 情况 A: 撞到墙壁/静态障碍物 (StaticBody2D, TileMap 等)
		# 排除子弹组，防止被子弹触发转向
		if collider is TileMap:
			if not collider.is_in_group("zidan"):
				handle_wall_collision(collision)
				break # 一次物理帧只处理一次主要转向，避免多次反转
		# 情况 B: 撞到玩家 (Player)
		elif collider.is_in_group("player") or collider.is_in_group("enemy"):
			handle_player_collision(collider)
	if is_dead:
		return
func handle_wall_collision(collision: KinematicCollision2D):
	direction *= -1
	velocity.x = speed * direction
func handle_player_collision(player_node: Node2D):
	# 这里处理与玩家的交互
	var push_direction = (global_position - player_node.global_position).normalized()
	# 暂时停止自动移动，施加冲击力
	velocity = push_direction * bounce_force
