extends CharacterBody2D

@export var move_speed: float = 200
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
@export var yunshishu_scene: PackedScene

# ============================================================
# 增益状态
# ============================================================
var has_rending_attack: bool = false
var has_wild_charge: bool = false
var has_bloodthirst: bool = false

# 野性蓄力
var is_charging: bool = false
var charge_time: float = 0.0
@export var charge_threshold: float = 0.3
@export var charge_speed_mult: float = 3.0
var charge_dashing: bool = false
var charge_dash_timer: float = 0.0
@export var charge_dash_duration: float = 0.4
@export var charge_knockback_force: float = 600.0
# 野性蓄力视觉
var charge_pulse_tween: Tween
@export var charge_glow_color: Color = Color(1.0, 0.5, 0.0, 1.0)

# 攻击冷却（点击立即发射 + 冷却防连点过快）
var attack_cooldown: float = 0.0
const ATTACK_RATE: float = 0.25

@onready var marker2d = $Marker2D
@onready var hp_bar: ProgressBar = $HUD_Layer/StatusUI/HP_Bar_Container/HP_Bar
@onready var mp_bar: ProgressBar = $HUD_Layer/StatusUI/MP_Bar_Container/MP_Bar
@onready var base_sprite_scale: Vector2 = $Marker2D/AnimatedSprite2D.scale
var hp_label: Label
var mp_label: Label

var is_game_over: bool = false
var is_invincible: bool = false
var invincible_timer: float = 0.0
var mp_regen_cooldown: float = 0.0
var is_knocked_back: bool = false
var knockback_timer: float = 0.0
const KNOCKBACK_DURATION: float = 0.15

@export var dash_speed: float = 400
@export var dash_duration: float = 0.4
@export var dash_cooldown: float = 5.0
@onready var dash_timer: Timer = $dash_timer
var direction = Input.get_vector("left", "right", "up", "down")
var is_dashing: bool = false
var can_dash: bool = true
var dash_direction: Vector2 = Vector2.ZERO

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

	# 关掉进度条自带百分比 + 加高
	hp_bar.show_percentage = false
	mp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(100, 24)
	mp_bar.custom_minimum_size = Vector2(100, 24)

	# 创建数值标签 — HP（居中覆盖在血条上）
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label.size = hp_bar.size
	hp_bar.add_child(hp_label)

	# 创建数值标签 — MP
	mp_label = Label.new()
	mp_label.add_theme_font_size_override("font_size", 14)
	mp_label.add_theme_color_override("font_color", Color.WHITE)
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_label.size = mp_bar.size
	mp_bar.add_child(mp_label)

	if dash_timer:
		dash_timer.one_shot = true
	if $Timer:
		$Timer.wait_time = 0.25

func _physics_process(delta: float) -> void:
	if is_game_over:
		return

	# 更新 HP/MP 数值显示
	hp_label.text = " %d / %d" % [int(hp_p), int(hp_bar.max_value)]
	mp_label.text = " %d / %d" % [int(current_mp), int(max_mp)]

	# 攻击冷却递减
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# 野性蓄力视觉更新（每帧）
	_update_charge_visuals(delta)

	# 冲锋冲刺计时（野性蓄力触发）
	if charge_dashing:
		charge_dash_timer -= delta
		if charge_dash_timer <= 0.0:
			charge_dashing = false
			velocity = Vector2.ZERO
		move_and_slide()
		# 冲锋期间碰撞检测——巨量击退
		for i in range(get_slide_collision_count()):
			var col = get_slide_collision(i)
			var col_obj = col.get_collider()
			if col_obj.is_in_group("enemy"):
				var knockback_dir = (col_obj.global_position - global_position).normalized()
				if col_obj is CharacterBody2D:
					col_obj.velocity = knockback_dir * charge_knockback_force
					if col_obj.has_method("apply_knockback"):
						col_obj.apply_knockback(knockback_dir * charge_knockback_force)
				# 撞击震屏 + 闪白
				_trigger_camera_shake(18.0, 0.25)
				$Marker2D/AnimatedSprite2D.modulate = Color(2.0, 2.0, 2.0, 1.0)
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
		$Marker2D/AnimatedSprite2D.flip_h = false
	elif Input.is_action_pressed("left"):
		$Marker2D/AnimatedSprite2D.flip_h = true
	move_and_slide()
	if Input.is_action_just_pressed("dash") and can_dash:
		start_dash(direction)
	if is_dashing:
		# 冲刺期间强制移动
		velocity = Input.get_vector("left", "right", "up", "down") * dash_speed
		print(velocity)
		$Marker2D/AnimatedSprite2D.play("dash")
		await get_tree().create_timer(0.4).timeout
		_on_dash_finished()
		$Marker2D/AnimatedSprite2D.play("move")
	move_and_slide()
	# 碰撞检测：碰到敌人 → 用碰撞法线弹开，方向精确
	if not is_knocked_back:
		for i in range(get_slide_collision_count()):
			var col = get_slide_collision(i)
			var col_obj = col.get_collider()
			if col_obj.is_in_group("enemy"):
				# 用碰撞法线计算弹开方向（引擎真实碰撞方向，不受 shape 偏移影响）
				var normal = col.get_normal()
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
		$Marker2D/AnimatedSprite2D.play("siwang")
		game_over()

func start_dash(input_direction: Vector2):
	is_dashing = true
	can_dash = false
	is_invincible = true  # 开启无敌
	dash_direction = input_direction.normalized()
	# 启动翻滚计时器
	if dash_timer:
		dash_timer.start()
	# 简单的冷却处理
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true

func _on_dash_finished():
	is_dashing = false
	is_invincible = false # 关闭无敌
	velocity = move_speed * direction

func shake_hp_bar() -> void:
	if hp_shake_tween:
		hp_shake_tween.kill()
	hp_shake_tween = create_tween()
	hp_shake_tween.set_ease(Tween.EASE_OUT)
	var dur = hp_shake_duration / 4.0
	hp_shake_tween.tween_property(hp_bar, "position:x", hp_bar.position.x + hp_shake_strength, dur)
	hp_shake_tween.tween_property(hp_bar, "position:x", hp_bar.position.x - hp_shake_strength, dur)
	hp_shake_tween.tween_property(hp_bar, "position:x", hp_bar.position.x, dur)


# ============================================================
# 野性蓄力视觉
# ============================================================

func _update_charge_visuals(_delta: float) -> void:
	var sprite = $Marker2D/AnimatedSprite2D

	# 冲锋冲刺中——亮蓝白闪光
	if charge_dashing:
		sprite.modulate = Color(1.4, 1.4, 2.2, 1.0)
		return

	# 蓄力中——渐渐变金色
	if has_wild_charge and Input.is_action_pressed("attack") and not is_knocked_back:
		var progress = charge_time / charge_threshold
		if progress > 1.0:
			progress = 1.0
		sprite.modulate = Color.WHITE.lerp(charge_glow_color, progress)
	else:
		sprite.modulate = Color.WHITE


func _start_charge_pulse() -> void:
	_stop_charge_pulse()
	charge_pulse_tween = create_tween()
	charge_pulse_tween.set_loops(0)
	var sprite = $Marker2D/AnimatedSprite2D
	var tw1 = charge_pulse_tween.tween_property(sprite, "scale", base_sprite_scale * 1.25, 0.1)
	tw1.set_ease(Tween.EASE_OUT)
	var tw2 = charge_pulse_tween.tween_property(sprite, "scale", base_sprite_scale, 0.1)
	tw2.set_ease(Tween.EASE_IN)


func _stop_charge_pulse() -> void:
	if charge_pulse_tween:
		charge_pulse_tween.kill()
	$Marker2D/AnimatedSprite2D.scale = base_sprite_scale


func _trigger_camera_shake(strength: float, duration: float) -> void:
	var cam = $Camera2D
	if not cam:
		return
	var t = create_tween()
	var orig = cam.offset
	var step = duration / 8.0
	for _i in range(8):
		t.tween_property(cam, "offset", orig + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), step)
	var last = t.tween_property(cam, "offset", orig, step)
	last.set_ease(Tween.EASE_OUT)


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("enemy"):
		# Area2D 没有碰撞法线，用位置差做近似
		var dir = (global_position - body.global_position).normalized()
		take_damage(5, dir)
		$Marker2D/AnimatedSprite2D.play("hurt")
		await get_tree().create_timer(1).timeout
		$Marker2D/AnimatedSprite2D.play("move")

# ============================================================
# 攻击
# ============================================================

func _input(event: InputEvent) -> void:
	if is_game_over:
		return
	# 点击攻击键立即发射（冷却控制射速）
	if event.is_action_pressed("attack") and attack_cooldown <= 0.0:
		fire_bullet()
		attack_cooldown = ATTACK_RATE

func _on_fire() -> void:
	if is_game_over:
		return
	if charge_dashing:
		return

	# 野性蓄力：长按攻击蓄力
	if has_wild_charge and Input.is_action_pressed("attack"):
		charge_time += get_physics_process_delta_time()
		if charge_time >= charge_threshold and not is_charging:
			is_charging = true
			_start_charge_pulse()
		if is_charging:
			return

	# 松开攻击键——如果蓄满则触发冲锋
	if is_charging:
		_stop_charge_pulse()
		var dir = Vector2($Marker2D/AnimatedSprite2D.flip_h and -1 or 1, 0).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(1, 0)
		velocity = dir * move_speed * charge_speed_mult
		charge_dashing = true
		charge_dash_timer = charge_dash_duration
		is_charging = false
		charge_time = 0.0
		# 冲锋发动震屏
		_trigger_camera_shake(12.0, 0.3)
		$Marker2D/AnimatedSprite2D.play("move")
		return

	# 没蓄力或没野性蓄力——正常射击
	if not (has_wild_charge and Input.is_action_pressed("attack")):
		charge_time = 0.0
		if is_charging:
			_stop_charge_pulse()
		is_charging = false

	if Input.is_action_pressed("attack") and attack_cooldown <= 0.0:
		fire_bullet()
		attack_cooldown = ATTACK_RATE
	if Input.is_action_pressed("hanbingjian"):
		if current_mp >= 20:
			current_mp -= 20
			mp_bar.value = current_mp
			mp_regen_cooldown = mp_regen_delay
			var node = hanbingjian_scene.instantiate()
			node.position = position + Vector2(0, -10)
			get_tree().current_scene.add_child(node)
	if Input.is_action_pressed("yunshishu"):
		spawn_yunshishu_at_mouse()

func fire_bullet() -> void:
	if not zidan_scene:
		return
	var zidan = zidan_scene.instantiate()
	var target_dir = get_global_mouse_position() - global_position
	zidan.global_position = global_position + target_dir.normalized() * 50
	zidan.rotation = target_dir.angle()
	if has_rending_attack:
		zidan.set("can_rend", true)
	get_parent().add_child(zidan)

func spawn_yunshishu_at_mouse():
	var yunshishu = yunshishu_scene.instantiate()
	get_tree().current_scene.add_child(yunshishu)
	yunshishu.global_position = get_global_mouse_position()
	await get_tree().create_timer(3).timeout
	yunshishu.queue_free()

func game_over() -> void:
	is_game_over = true
	await get_tree().create_timer(4).timeout
	get_tree().reload_current_scene()


func 加血() -> void:
	hp_bar.max_value += 10
	hp_p += 20

func 加蓝() -> void:
	max_mp += 50
	current_mp += 50

func 加移速() -> void:
	move_speed += 200

# ============================================================
# 新增益
# ============================================================

func 撕裂普攻() -> void:
	has_rending_attack = true

func 野性蓄力() -> void:
	has_wild_charge = true

func 嗜血() -> void:
	has_bloodthirst = true

# 击杀普通怪物回血
func on_enemy_killed() -> void:
	if has_bloodthirst:
		hp_p = min(hp_p + 5, hp_bar.max_value)
		hp_bar.value = hp_p

# 击杀狼人双倍回血
func on_werewolf_killed() -> void:
	if has_bloodthirst:
		hp_p = min(hp_p + 10, hp_bar.max_value)
		hp_bar.value = hp_p
