extends CharacterBody2D
# 史莱姆 — 慢速巡逻，血量较高，撞墙反弹

@export var speed: float = 50.0
@export var hp: float = 20
@export var death_duration: float = 0.6
@export var bounce_force: float = 60.0
@export var contact_damage: float = 8.0

var is_dead: bool = false
var direction: int = -1
@export var shilaimu_scene: PackedScene


func _ready() -> void:
	direction = -1
	velocity.x = speed * direction
	add_to_group("enemy")


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	move_and_slide()
	_process_collisions()

	if velocity.x == 0:
		direction *= -1
		velocity.x = speed * direction

	if $AnimatedSprite2D:
		$AnimatedSprite2D.flip_h = direction == -1


func _process_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var col_obj: Node2D = col.get_collider()

		if col_obj is TileMap or col_obj is StaticBody2D:
			if not col_obj.is_in_group("zidan"):
				direction *= -1
				velocity.x = speed * direction
				position.x += direction * 2
				break

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
	$AnimatedSprite2D.play("death")
	if get_tree().current_scene.has_method("add_score"):
		get_tree().current_scene.add_score(1)
	velocity = Vector2.ZERO
	await get_tree().create_timer(death_duration).timeout
	queue_free()
