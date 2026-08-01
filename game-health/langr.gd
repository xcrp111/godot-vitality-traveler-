extends CharacterBody2D
# 狼人 — 追击玩家，受击死亡，超出范围返回出生点
# 碰撞处理遵循6.13规范：碰撞法线推开、敌人互斥、玩家视为墙壁

@export var move_speed: float = 60.0
@export var hp: float = 30
@export var death_duration: float = 0.6
@export var contact_damage: float = 12.0
@export var detection_range: float = 600.0
@export var max_roam_distance: float = 500.0

var is_dead: bool = false
var player: Node2D
var spawn_position: Vector2


func _ready() -> void:
	spawn_position = global_position
	player = $"../wanjia"
	if not player:
		push_warning("Wolf: Player node not found!")
	add_to_group("enemy")
	add_to_group("werewolf")
<<<<<<< Updated upstream:game-health/langr.gd

=======
>>>>>>> Stashed changes:game-health-2026-08-01/langr.gd

func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if not player:
		return

	var distance_to_player = global_position.distance_to(player.global_position)
	var distance_from_spawn = global_position.distance_to(spawn_position)

	if distance_to_player < detection_range and distance_from_spawn < max_roam_distance:
		# 追击玩家
		var direction := (player.global_position - global_position).normalized()
		velocity = direction * move_speed
	else:
		# 超出侦测范围或离出生点太远 → 返回出生点
		if distance_from_spawn > 10.0:
			var dir_to_spawn := (spawn_position - global_position).normalized()
			velocity = dir_to_spawn * move_speed * 0.6
		else:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed)

	move_and_slide()
	_process_collisions()

	# 更新朝向：追逐时面向玩家，返回时面向移动方向
	if $AnimatedSprite2D:
		if distance_to_player < detection_range and distance_from_spawn < max_roam_distance:
			$AnimatedSprite2D.flip_h = player.global_position.x < global_position.x
		elif distance_from_spawn > 10.0:
			$AnimatedSprite2D.flip_h = velocity.x < 0


func _process_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var col_obj: Node2D = col.get_collider()

		# 撞墙 / 玩家 → 沿碰撞法线推开（6.13规范）
		if col_obj is TileMap or col_obj is StaticBody2D or col_obj.is_in_group("player"):
			if not col_obj.is_in_group("zidan"):
				var normal := col.get_normal()
				position += normal * 5
				break

		# 撞到其他敌人 → 沿法线推开，互斥分离（6.13规范）
		if col_obj.is_in_group("enemy") and col_obj != self:
			var normal := col.get_normal()
			position += normal * 6
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
		move_speed *= 0.75

	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	$AnimatedSprite2D.play("siwang")
	if get_tree().current_scene.has_method("add_score"):
		get_tree().current_scene.add_score(1)
<<<<<<< Updated upstream:game-health/langr.gd
	# 嗜血回调：通知玩家击杀狼人
=======
	# 嗜血回调
>>>>>>> Stashed changes:game-health-2026-08-01/langr.gd
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_method("on_werewolf_killed"):
		p.on_werewolf_killed()
	velocity = Vector2.ZERO
	await get_tree().create_timer(death_duration).timeout
	queue_free()
