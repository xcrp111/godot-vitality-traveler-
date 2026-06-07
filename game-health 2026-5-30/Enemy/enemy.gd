extends CharacterBody2D
# 哥布林 — 左右巡逻，撞墙反弹，碰到玩家造成伤害

@export var speed: float = 70.0
@export var hp: float = 15
@export var death_duration: float = 0.6
@export var bounce_force: float = 80.0
@export var contact_damage: float = 5.0

var is_dead: bool = false
var direction: int = -1  # -1 向左, 1 向右
@export var shilaimu_scene: PackedScene

func _ready() -> void:
	direction = -1
	velocity.x = speed * direction
	add_to_group("enemy")


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	move_and_slide()        # 先移动，产生碰撞
	_process_collisions()   # 再处理碰撞结果

	# 被击退后速度归零 → 恢复巡逻
	if velocity.x == 0:
		direction *= -1
		velocity.x = speed * direction

	# 更新朝向动画
	if $AnimatedSprite2D:
		$AnimatedSprite2D.flip_h = direction == -1


func _process_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var col_obj: Node2D = col.get_collider()

		# 撞墙反弹（TileMap / StaticBody2D）
		if col_obj is TileMap or col_obj is StaticBody2D:
			if not col_obj.is_in_group("zidan"):
				direction *= -1
				velocity.x = speed * direction
				position.x += direction * 2  # 推开防粘连
				break

		# 撞到玩家 → 弹开
		if col_obj.is_in_group("player"):
			var push_dir := (global_position - col_obj.global_position).normalized()
			velocity = push_dir * bounce_force


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
