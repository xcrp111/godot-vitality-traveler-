extends CharacterBody2D
# 哥布林 — 左右巡逻，撞墙反弹，碰到玩家视为墙壁反弹

@export var speed: float = 70.0
@export var hp: float = 15
@export var death_duration: float = 0.6
@export var contact_damage: float = 5.0

var is_dead: bool = false
var direction: int = -1  # -1 向左, 1 向右
var flip_count: int = 0          # 方向切换计数
var flip_reset_timer: float = 0.0 # 切换计数重置倒计时
@export var shilaimu_scene: PackedScene

# ============================================================
# 流血系统
# ============================================================
var _bleeding: bool = false
var _bleed_timer: float = 0.0
var _bleed_damage: float = 0.0
var _bleed_interval: float = 0.5
var _bleed_remaining: float = 0.0

func apply_bleed(damage: float, interval: float, duration: float) -> void:
	_bleeding = true
	_bleed_damage = damage
	_bleed_interval = interval
	_bleed_remaining = duration
	_bleed_timer = 0.0

# 击退支持（供野性蓄力调用）
var _knockback_velocity: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0

func apply_knockback(force: Vector2) -> void:
	_knockback_velocity = force
	_knockback_timer = 0.3
	velocity = force

func _ready() -> void:
	direction = -1
	velocity.x = speed * direction
	add_to_group("enemy")


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 击退处理
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity = _knockback_velocity
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, speed * 3 * delta)
		move_and_slide()
		if _knockback_timer <= 0.0:
			velocity.x = speed * direction
		return

	# 流血 tick
	if _bleeding:
		_bleed_timer += delta
		_bleed_remaining -= delta
		if _bleed_timer >= _bleed_interval:
			_bleed_timer = 0.0
			hp -= _bleed_damage
			if hp <= 0:
				die()
				return
		if _bleed_remaining <= 0.0:
			_bleeding = false

	move_and_slide()        # 先移动，产生碰撞
	_process_collisions()   # 再处理碰撞结果

	# 被阻挡后速度归零 → 恢复巡逻
	if velocity.x == 0:
		_reverse_direction()

	# 频繁来回反弹 → 加随机扰动跳出死循环
	if flip_count > 4:
		direction = 1 if randf() > 0.5 else -1
		velocity.x = speed * direction
		position.y += randf_range(-8, 8)   # 上下随机偏移，打破对称
		flip_count = 0

	# 重置切换计数（每秒递减）
	if flip_reset_timer > 0.0:
		flip_reset_timer -= delta
	else:
		flip_count = 0

	# 更新朝向动画
	if $AnimatedSprite2D:
		$AnimatedSprite2D.flip_h = direction == -1


func _reverse_direction() -> void:
	direction *= -1
	velocity.x = speed * direction
	flip_count += 1
	flip_reset_timer = 2.0  # 2秒内累计计数


func _process_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var col_obj: Node2D = col.get_collider()

		# 撞墙 / 玩家 → 视为墙壁反弹，沿碰撞法线推开
		if col_obj is TileMap or col_obj is StaticBody2D or col_obj.is_in_group("player"):
			if not col_obj.is_in_group("zidan"):
				var normal := col.get_normal()
				position += normal * 5
				_reverse_direction()
				break

		# 撞到其他敌人 → 沿法线推开，各自反转方向
		if col_obj.is_in_group("enemy") and col_obj != self:
			var normal := col.get_normal()
			position += normal * 6
			_reverse_direction()
			break


# ============================================================
# 受击 & 死亡
# ============================================================

func _on_area_2d_area_entered(area: Area2D) -> void:
	if is_dead:
		return
	if area.is_in_group("zidan"):
		hp -= 10
		area.queue_free()
	elif area.is_in_group("hanbingjian"):
		hp -= 10
		speed *= 0.75
		velocity.x = speed * direction

	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	$AnimatedSprite2D.play("siwang")
	if get_tree().current_scene.has_method("add_score"):
		get_tree().current_scene.add_score(1)
	velocity = Vector2.ZERO
	await get_tree().create_timer(death_duration).timeout
	queue_free()
