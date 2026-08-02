extends CharacterBody2D
@export var is_dead = false
@export var hp: float = 200
@export var death_duration: float = 1
var is_burning = false
var damage_amount = 5           # 每次扣血量
var timer_accumulator = 0.0     # 时间累加器
var damage_interval = 0.5

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_to_group("enemy")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_dead:
		return
	if is_burning:
		timer_accumulator += delta
		if timer_accumulator >= damage_interval:
			take_damage(damage_amount)
			timer_accumulator = 0.0 # 重置计时器，准备下一次扣血
	move_and_slide()
	_process_collisions()


func _on_area_2d_area_entered(area: Area2D) -> void:
	if is_dead:
		return
	if area.is_in_group("zidan"):
		hp -= 10
		area.queue_free()
	elif area.is_in_group("hanbingjian"):
		hp -= 10
	elif area.is_in_group("yunshishu"):
		is_burning = true
	if hp <= 0:
		die()

func die() -> void:
	is_dead = true
	$AnimatedSprite2D.play("siwang")
	if get_tree().current_scene.has_method("add_score"):
		get_tree().current_scene.add_score(1)
	await get_tree().create_timer(death_duration).timeout
	queue_free()

func take_damage(amount):
	hp -= amount

func _on_area_2d_area_exited(area: Area2D) -> void:
	if area.is_in_group("yunshishu"):
		is_burning = false

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


func _on_timer_timeout() -> void:
	pass # Replace with function body.
	#之后用来写技能代码
	#$AnimatedSprite2D.play("jineng1")
