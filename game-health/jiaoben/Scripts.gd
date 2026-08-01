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

# ============================================================
# 增益状态
# ============================================================
var has_rending_attack: bool = false
var has_wild_charge: bool = false
var has_bloodthirst: bool = false

# 野性蓄力
var is_charging: bool = false
var charge_time: float = 0.0
@export var charge_threshold: float = 1.2
@export var charge_speed_mult: float = 3.0
var charge_dashing: bool = false
var charge_dash_timer: float = 0.0
@export var charge_dash_duration: float = 0.4
@export var charge_knockback_force: float = 600.0

# 撕裂普攻参数
@export var bleed_dmg_per_tick: float = 3.0
@export var bleed_tick_interval: float = 0.5
@export var bleed_duration: float = 3.0
@export var werewolf_damage_mult: float = 2.0

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

<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
=======
# ============================================================
# Dash 闪避系统
# ============================================================
@export var dash_speed: float = 400
@export var dash_duration: float = 0.4
@export var dash_cooldown: float = 5.0
@onready var dash_timer: Timer = $dash_timer
var direction = Input.get_vector("left", "right", "up", "down")
var is_dashing: bool = false
var can_dash: bool = true
var dash_direction: Vector2 = Vector2.ZERO

# ============================================================
# 增益状态
# ============================================================
var has_rending_attack: bool = false
var has_wild_charge: bool = false
var has_bloodthirst: bool = false

# 野性蓄力（右键长按）
var is_charging: bool = false
var charge_time: float = 0.0
@export var charge_threshold: float = 1.2
@export var charge_speed_mult: float = 3.0
var charge_dashing: bool = false
var charge_dash_timer: float = 0.0
@export var charge_dash_duration: float = 0.4
@export var charge_knockback_force: float = 600.0

# 撕裂普攻参数
@export var bleed_dmg_per_tick: float = 3.0
@export var bleed_tick_interval: float = 0.5
@export var bleed_duration: float = 3.0
@export var werewolf_damage_mult: float = 2.0

>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
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
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
=======
	if dash_timer:
		dash_timer.one_shot = true
	# 设置攻击间隔（Timer 默认 1 秒太慢）
	if $Timer:
		$Timer.wait_time = 0.25
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd


func _physics_process(delta: float) -> void:
	if is_game_over:
		return

	# 冲锋冲刺计时
	if charge_dashing:
		charge_dash_timer -= delta
		if charge_dash_timer <= 0.0:
			charge_dashing = false
			velocity = Vector2.ZERO
		move_and_slide()
		# 冲锋期间碰撞检测——巨量击退
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var col_obj: Node2D = col.get_collider()
			if col_obj.is_in_group("enemy"):
				var knockback_dir := (col_obj.global_position - global_position).normalized()
				if col_obj is CharacterBody2D:
					col_obj.velocity = knockback_dir * charge_knockback_force
					if col_obj.has_method("apply_knockback"):
						col_obj.apply_knockback(knockback_dir * charge_knockback_force)
		return

<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
	# 击退倒计时：击退期间跳过输入覆盖，让击退速度完全生效
=======
	# 击退倒计时
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
	if is_knocked_back:
		knockback_timer -= delta
		if knockback_timer <= 0.0:
			is_knocked_back = false
			velocity = Vector2.ZERO
	else:
		velocity = Input.get_vector("left", "right", "up", "down") * move_speed

	if Input.is_action_pressed("right"):
		marker2d.scale = Vector2(1, 1)
	elif Input.is_action_pressed("left"):
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
		marker2d.scale = Vector2(-1, 1)
	move_and_slide()

	# 碰撞检测：碰到敌人 → 用碰撞法线弹开，方向精确
=======
		$Marker2D/AnimatedSprite2D.flip_h = true
	move_and_slide()

	# Dash 闪避
	if Input.is_action_just_pressed("dash") and can_dash:
		start_dash(direction)
	if is_dashing:
		velocity = Input.get_vector("left", "right", "up", "down") * dash_speed
		$Marker2D/AnimatedSprite2D.play("dash")
		await get_tree().create_timer(0.4).timeout
		_on_dash_finished()
		$Marker2D/AnimatedSprite2D.play("move")
	move_and_slide()

	# 碰撞检测：碰到敌人 → 弹开
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
	if not is_knocked_back:
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var col_obj: Node2D = col.get_collider()
			if col_obj.is_in_group("enemy"):
				var normal := col.get_normal()
				global_position += normal * 8
				take_damage(5, normal)
				break

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

	velocity = knockback_normal * knockback_force
	is_knocked_back = true
	knockback_timer = KNOCKBACK_DURATION

	is_invincible = true
	invincible_timer = invincible_duration

	if hp_p <= 0:
		game_over()


<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
=======
func start_dash(input_direction: Vector2):
	is_dashing = true
	can_dash = false
	is_invincible = true
	dash_direction = input_direction.normalized()
	if dash_timer:
		dash_timer.start()
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true

func _on_dash_finished():
	is_dashing = false
	is_invincible = false
	velocity = move_speed * direction


>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
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
	if charge_dashing:
		return

<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
	# 野性蓄力：长按攻击蓄力
	if has_wild_charge and Input.is_action_pressed("attack"):
		charge_time += get_physics_process_delta_time()
		if charge_time >= charge_threshold and not is_charging:
			is_charging = true
			$Marker2D/AnimatedSprite2D.play("hbj")  # 蓄力特效
		return

	# 松开攻击键——如果蓄满则触发冲锋
	if is_charging:
		var dir := Vector2(marker2d.scale.x, 0).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(1, 0)
=======
	# 野性蓄力：长按鼠标右键蓄力
	if has_wild_charge and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		charge_time += get_physics_process_delta_time()
		if charge_time >= charge_threshold and not is_charging:
			is_charging = true
			$Marker2D/AnimatedSprite2D.play("hbj")
		return

	# 松开右键——如果蓄满则触发冲锋
	if is_charging:
		var dir := Vector2(1, 0)
		if $Marker2D/AnimatedSprite2D.flip_h:
			dir = Vector2(-1, 0)
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
		velocity = dir * move_speed * charge_speed_mult
		charge_dashing = true
		charge_dash_timer = charge_dash_duration
		is_charging = false
		charge_time = 0.0
		$Marker2D/AnimatedSprite2D.play("move")
		return

<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
	# 没蓄力或没野性蓄力——轻点攻击则正常射击
=======
	# 没蓄力或没野性蓄力——正常攻击
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
	charge_time = 0.0
	is_charging = false

	if Input.is_action_pressed("attack"):
		fire_bullet()
	if Input.is_action_pressed("hanbingjian"):
		if current_mp >= 20:
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
			$Marker2D/AnimatedSprite2D.play('hbj')
=======
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
			current_mp -= 20
			mp_bar.value = current_mp
			mp_regen_cooldown = mp_regen_delay
			var node := hanbingjian_scene.instantiate()
			node.position = position + Vector2(60, 60)
			get_tree().current_scene.add_child(node)
			await get_tree().create_timer(1).timeout
			$Marker2D/AnimatedSprite2D.play("move")
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
=======
	if Input.is_action_pressed("yunshishu"):
		spawn_yunshishu_at_mouse()

>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd

func fire_bullet() -> void:
	if not zidan_scene:
		return
	var zidan: Node2D = zidan_scene.instantiate()
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
	zidan.global_position = global_position + Vector2(60, 60)
	var target_dir := get_global_mouse_position() - zidan.global_position
=======
	var target_dir := get_global_mouse_position() - global_position
	# 子弹生成在玩家前方 50 像素处，避免与自身 Area2D 重叠导致自毁
	zidan.global_position = global_position + target_dir.normalized() * 50
>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
	zidan.rotation = target_dir.angle()
	# 撕裂普攻——子弹标记
	if has_rending_attack:
		zidan.set("can_rend", true)
	get_parent().add_child(zidan)


<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
=======
func spawn_yunshishu_at_mouse():
	var yunshishu = yunshishu_scene.instantiate()
	get_tree().current_scene.add_child(yunshishu)
	yunshishu.global_position = get_global_mouse_position()
	await get_tree().create_timer(3).timeout
	yunshishu.queue_free()


>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
func game_over() -> void:
	is_game_over = true
	await get_tree().create_timer(4).timeout
	get_tree().reload_current_scene()
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
	
=======


# ============================================================
# 增益函数
# ============================================================

>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
func 加血() -> void:
	hp_bar.max_value += 10
	hp_p += 20

func 加蓝() -> void:
	max_mp += 50
	current_mp += 50
<<<<<<< Updated upstream:game-health/jiaoben/Scripts.gd
	
func 加移速() -> void:
	move_speed += 200

# ============================================================
# 新增益
# ============================================================

=======

func 加移速() -> void:
	move_speed += 200

>>>>>>> Stashed changes:game-health-2026-08-01/jiaoben/Scripts.gd
func 撕裂普攻() -> void:
	has_rending_attack = true

func 野性蓄力() -> void:
	has_wild_charge = true

func 嗜血() -> void:
	has_bloodthirst = true

# 由狼人死亡时回调
func on_werewolf_killed() -> void:
	if has_bloodthirst:
		hp_p = hp_bar.max_value
		hp_bar.value = hp_p
