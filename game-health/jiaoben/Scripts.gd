extends CharacterBody2D

@export var move_speed: float = 300
@export var hp_p: float = 20
@export var max_mp: float = 100
@export var current_mp: float = 100
@export var mp_regen_per_sec: float = 1.25
@export var mp_regen_delay: float = 0.5
@export var invincible_duration: float = 1.0
@export var knockback_force: float = 250.0

@export var zidan_scene: PackedScene
@export var hanbingjian_scene: PackedScene
@export var shilaimu_scene: PackedScene

@onready var marker2d := $Marker2D
@onready var hp_bar: ProgressBar = $HUD_Layer/StatusUI/HP_Bar_Container/HP_Bar
@onready var mp_bar: ProgressBar = $HUD_Layer/StatusUI/MP_Bar_Container/MP_Bar

var is_game_over: bool = false
var is_invincible: bool = false
var invincible_timer: float = 0.0
var mp_regen_cooldown: float = 0.0
var is_knocked_back: bool = false
var knockback_timer: float = 0.0
const KNOCKBACK_DURATION: float = 0.15

# HP 条低血量闪烁
@export var hp_flash_threshold: float = 0.5
@export var hp_flash_speed: float = 0.3
var hp_flash_timer: float = 0.0

# HP 条受伤抖动
var hp_shake_tween: Tween
@export var hp_shake_duration: float = 0.15
@export var hp_shake_strength: float = 5.0


func _ready() -> void:
	hp_bar.max_value = hp_p
	hp_bar.value = hp_p
	mp_bar.max_value = max_mp
	mp_bar.value = current_mp


func _physics_process(delta: float) -> void:
	if is_game_over:
		return

	# 击退倒计时：击退期间跳过输入覆盖，让击退速度完全生效
	if is_knocked_back:
		knockback_timer -= delta
		if knockback_timer <= 0.0:
			is_knocked_back = false
			velocity = Vector2.ZERO
	else:
		# 正常移动 —— 仅非击退时由输入驱动速度
		velocity = Input.get_vector("left", "right", "up", "down") * move_speed

	if Input.is_action_pressed("right"):
		marker2d.scale = Vector2(1, 1)
	elif Input.is_action_pressed("left"):
		marker2d.scale = Vector2(-1, 1)
	move_and_slide()

	# 碰撞检测：碰到敌人 → 用碰撞法线弹开，方向精确
	if not is_knocked_back:
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var col_obj: Node2D = col.get_collider()
			if col_obj.is_in_group("enemy"):
				# 用碰撞法线计算弹开方向（引擎真实碰撞方向，不受 shape 偏移影响）
				var normal := col.get_normal()
				# 立即物理分离：沿法线推开，杜绝粘连
				global_position += normal * 8
				# 玩家击退（速度 + 保护期）
				take_damage(5, normal)
				break  # 一帧只触发一次


	# 无敌倒计时
	if is_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0.0:
			is_invincible = false

	# HP 条低血量闪烁
	if hp_p / hp_bar.max_value <= hp_flash_threshold and not is_game_over:
		hp_flash_timer += delta
		if hp_flash_timer >= hp_flash_speed:
			hp_flash_timer = 0.0
			hp_bar.modulate.a = 0.3 if hp_bar.modulate.a > 0.5 else 1.0
	else:
		hp_bar.modulate.a = 1.0

	# 蓝量回复
	if current_mp < max_mp:
		if mp_regen_cooldown > 0.0:
			mp_regen_cooldown -= delta
		else:
			current_mp = min(current_mp + mp_regen_per_sec * delta, max_mp)
			mp_bar.value = current_mp


# ============================================================
# 伤害 & 无敌
# ============================================================

func take_damage(amount: float, knockback_normal: Vector2) -> void:
	if is_invincible or is_game_over:
		return

	hp_p -= amount
	hp_bar.value = hp_p
	shake_hp_bar()

	# 击退：沿碰撞法线方向弹开（真实碰撞方向）
	velocity = knockback_normal * knockback_force
	is_knocked_back = true
	knockback_timer = KNOCKBACK_DURATION

	# 进入无敌
	is_invincible = true
	invincible_timer = invincible_duration

	if hp_p <= 0:
		game_over()


func shake_hp_bar() -> void:
	if hp_shake_tween:
		hp_shake_tween.kill()
	hp_shake_tween = create_tween()
	hp_shake_tween.set_ease(Tween.EASE_OUT)
	var dur := hp_shake_duration / 4.0
	hp_shake_tween.tween_property(hp_bar, "position:x", hp_bar.position.x + hp_shake_strength, dur)
	hp_shake_tween.tween_property(hp_bar, "position:x", hp_bar.position.x - hp_shake_strength, dur)
	hp_shake_tween.tween_property(hp_bar, "position:x", hp_bar.position.x, dur)


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("enemy"):
		# Area2D 没有碰撞法线，用位置差做近似
		var dir := (global_position - body.global_position).normalized()
		take_damage(5, dir)
		$Marker2D/AnimatedSprite2D.play("hurt")
		await get_tree().create_timer(1).timeout
		$Marker2D/AnimatedSprite2D.play("move")

# ============================================================
# 攻击
# ============================================================

func _on_fire() -> void:
	if is_game_over:
		return
	if Input.is_action_pressed("attack"):
		fire_bullet()
	if Input.is_action_pressed("hanbingjian"):
		if current_mp >= 20:
			$Marker2D/AnimatedSprite2D.play('hbj')
			current_mp -= 20
			mp_bar.value = current_mp
			mp_regen_cooldown = mp_regen_delay
			var node := hanbingjian_scene.instantiate()
			node.position = position + Vector2(60, 60)
			get_tree().current_scene.add_child(node)
			await get_tree().create_timer(1).timeout
			$Marker2D/AnimatedSprite2D.play("move")

func fire_bullet() -> void:
	if not zidan_scene:
		return
	var zidan: Node2D = zidan_scene.instantiate()
	zidan.global_position = global_position + Vector2(60, 60)
	var target_dir := get_global_mouse_position() - zidan.global_position
	zidan.rotation = target_dir.angle()
	get_parent().add_child(zidan)


func game_over() -> void:
	is_game_over = true
	await get_tree().create_timer(4).timeout
	get_tree().reload_current_scene()
