extends CharacterBody2D
# 史莱姆 — 慢速巡逻，血量较高，撞墙反弹

@export var speed: float = 50.0
@export var hp: float = 20
@export var death_duration: float = 0.6
@export var contact_damage: float = 8.0

var is_dead: bool = false
var direction: int = -1
var flip_count: int = 0
var flip_reset_timer: float = 0.0
@export var shilaimu_scene: PackedScene

# 流血 DoT
var is_bleeding: bool = false
var bleed_tick_timer: float = 0.0
var bleed_damage_per_tick: float = 0.0
var bleed_interval: float = 0.0
var bleed_remaining: float = 0.0

# 头顶血条
var hp_bar: ProgressBar
var hp_max: float
var player: Node2D


func _ready() -> void:
	direction = -1
	velocity.x = speed * direction
	add_to_group("enemy")
	player = get_tree().get_first_node_in_group("player")
	hp_max = hp
	_create_hp_bar()


func _create_hp_bar() -> void:
	hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.max_value = hp_max
	hp_bar.value = hp
	hp_bar.size = Vector2(58, 8)
	hp_bar.position = Vector2(-29, -130)

	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.75)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.2, 0.2, 1.0)

	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_bar.add_theme_constant_override("outline_size", 0)
	hp_bar.show_percentage = false

	add_child(hp_bar)


func _update_hp_bar() -> void:
	if hp_bar:
		hp_bar.value = hp
		var ratio = hp / hp_max
		var fill = hp_bar.get_theme_stylebox("fill", "ProgressBar")
		if fill is StyleBoxFlat:
			if ratio > 0.5:
				fill.bg_color = Color(0.2, 0.85, 0.2, 1.0)
			elif ratio > 0.25:
				fill.bg_color = Color(0.9, 0.75, 0.1, 1.0)
			else:
				fill.bg_color = Color(0.9, 0.2, 0.2, 1.0)


func _show_damage_number(amount: float, color: Color = Color.WHITE) -> void:
	var label = Label.new()
	label.text = "-%d" % int(amount)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(-15 + randf_range(-12, 12), -150)
	add_child(label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 35, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 流血处理
	if is_bleeding:
		bleed_remaining -= delta
		bleed_tick_timer -= delta
		if bleed_tick_timer <= 0.0:
			bleed_tick_timer = bleed_interval
			hp -= bleed_damage_per_tick
			_update_hp_bar()
			_show_damage_number(bleed_damage_per_tick, Color(1.0, 0.3, 0.1))
			if $AnimatedSprite2D:
				$AnimatedSprite2D.modulate = Color(1.0, 0.2, 0.2, 1.0)
				await get_tree().create_timer(0.1).timeout
				$AnimatedSprite2D.modulate = Color.WHITE
		if bleed_remaining <= 0.0:
			is_bleeding = false
		if hp <= 0:
			die()
			return

	move_and_slide()
	_process_collisions()

	if velocity.x == 0:
		_reverse_direction()

	if flip_count > 4:
		direction = 1 if randf() > 0.5 else -1
		velocity.x = speed * direction
		position.y += randf_range(-8, 8)
		flip_count = 0

	if flip_reset_timer > 0.0:
		flip_reset_timer -= delta
	else:
		flip_count = 0

	if $AnimatedSprite2D:
		$AnimatedSprite2D.flip_h = direction == -1


func _reverse_direction() -> void:
	direction *= -1
	velocity.x = speed * direction
	flip_count += 1
	flip_reset_timer = 2.0


func _process_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var col_obj = col.get_collider()

		if col_obj is TileMap or col_obj is StaticBody2D or col_obj.is_in_group("player"):
			if not col_obj.is_in_group("zidan"):
				var normal = col.get_normal()
				position += normal * 5
				_reverse_direction()
				break

		if col_obj.is_in_group("enemy") and col_obj != self:
			var normal = col.get_normal()
			position += normal * 6
			_reverse_direction()
			break


# ============================================================
# 受击 & 死亡
# ============================================================

func take_bullet_damage(amount: float) -> void:
	if is_dead:
		return
	hp -= amount
	_update_hp_bar()
	_show_damage_number(amount, Color.WHITE)
	if hp <= 0:
		die()


func _on_area_2d_area_entered(area: Area2D) -> void:
	if is_dead:
		return
	if area.is_in_group("zidan"):
		hp -= 10
		area.queue_free()
		_update_hp_bar()
		_show_damage_number(10, Color.WHITE)
	elif area.is_in_group("hanbingjian"):
		hp -= 10
		speed *= 0.75
		velocity.x = speed * direction
		_update_hp_bar()
		_show_damage_number(10, Color(0.4, 0.7, 1.0))

	if hp <= 0:
		die()


func apply_bleed(damage: float, interval: float, duration: float) -> void:
	is_bleeding = true
	bleed_damage_per_tick = damage
	bleed_interval = interval
	bleed_remaining = duration
	bleed_tick_timer = 0.0


func apply_knockback(force: Vector2) -> void:
	velocity = force


func die() -> void:
	is_dead = true
	if hp_bar:
		hp_bar.visible = false
	# 嗜血回血
	if player and player.has_method("on_enemy_killed"):
		player.on_enemy_killed()
	$AnimatedSprite2D.play("siwang")
	if get_tree().current_scene.has_method("add_score"):
		get_tree().current_scene.add_score(1)
	velocity = Vector2.ZERO
	await get_tree().create_timer(death_duration).timeout
	queue_free()
