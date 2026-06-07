extends CharacterBody2D

@export var move_speed : float = 300
@export var hp_p :float = 20
@onready var marker2d = $Marker2D
# 当前输入方向向量（单位化前的原始输入）
var direction = Input.get_vector("left","right","up","down")
var zidan_dir = Vector2.ZERO
var is_game_over : bool = false
@export var zidan_scene : PackedScene
@export var hanbingjian_scene :PackedScene
@export var shilaimu_scene : PackedScene
# Called every frame. 'delta' is the elapsed time since the previous frame.
var max_mp = 100
var current_mp = 100
@onready var hp_bar: ProgressBar = $HUD_Layer/StatusUI/HP_Bar_Container/HP_Bar
@onready var mp_bar: ProgressBar = $HUD_Layer/StatusUI/MP_Bar_Container/MP_Bar
@export var mp_regen_per_sec := 1.25
@export var mp_regen_delay := 0.5
var mp_regen_cooldown := 0.0

var hp_shake_tween: Tween = null
@export var hp_shake_duration: float = 0.15
@export var hp_shake_strength: float = 5
@export var hp_flash_threshold: float = 0.5  
@export var hp_flash_speed: float = 0.3     
var hp_flash_timer: float = 0.0
var hp_flash_on: bool = true
var mp_shake_tween: Tween = null
@export var mp_shake_duration: float = 0.15
@export var mp_shake_strength: float = 5
@export var mp_flash_threshold: float = 0.2
@export var mp_flash_speed: float = 0.3
var mp_flash_timer: float = 0.0
var mp_flash_on: bool = true

func _ready():
	
	hp_bar.max_value = hp_p
	hp_bar.value = hp_p
	mp_bar.max_value = max_mp
	mp_bar.value = current_mp

func _physics_process(delta: float) -> void:
	if not is_game_over:
		velocity = Input.get_vector("left","right","up","down") * move_speed
		if Input.is_action_pressed("right"):
			marker2d.scale = Vector2(1,1)
		elif Input.is_action_pressed("left"):
			marker2d.scale = Vector2(-1,1)
	move_and_slide()
	if current_mp < max_mp:
		if mp_regen_cooldown > 0.0:
			mp_regen_cooldown -= delta
		else:
			current_mp += mp_regen_per_sec * delta
			current_mp = min(current_mp, max_mp)
			mp_bar.value = current_mp
	
	if hp_p / hp_bar.max_value <= hp_flash_threshold and not is_game_over:
		hp_flash_timer += delta
		if hp_flash_timer >= hp_flash_speed:
			hp_flash_timer = 0
			hp_flash_on = !hp_flash_on
			hp_bar.modulate.a = 1 if hp_flash_on else 0.3
	else:
		hp_bar.modulate.a = 1  # 血量正常时恢复不透明
	
	if current_mp / max_mp <= mp_flash_threshold and not is_game_over:
		mp_flash_timer += delta
		if mp_flash_timer >= mp_flash_speed:
			mp_flash_timer = 0
			mp_flash_on = !mp_flash_on
			mp_bar.modulate.a = 1 if mp_flash_on else 0.3
	else:
		mp_bar.modulate.a = 1
	
	var mouse_pos: Vector2 = get_global_mouse_position()
	
func game_over():
	is_game_over = true
	await get_tree().create_timer(4).timeout
	get_tree().reload_current_scene()

func shake_hp_bar():
	if hp_shake_tween:
		hp_shake_tween.kill()
	hp_shake_tween = create_tween()
	hp_shake_tween.set_ease(Tween.EASE_OUT)
	hp_shake_tween.tween_property(hp_bar, "position", hp_bar.position + Vector2(hp_shake_strength, 0), hp_shake_duration / 4)
	hp_shake_tween.tween_property(hp_bar, "position", hp_bar.position + Vector2(-hp_shake_strength, 0), hp_shake_duration / 4)
	hp_shake_tween.tween_property(hp_bar, "position", hp_bar.position + Vector2(hp_shake_strength * 0.7, 0), hp_shake_duration / 4)
	hp_shake_tween.tween_property(hp_bar, "position", hp_bar.position, hp_shake_duration / 4)

# 蓝条抖动函数
func shake_mp_bar():
	if mp_shake_tween:
		mp_shake_tween.kill()
	mp_shake_tween = create_tween()
	mp_shake_tween.set_ease(Tween.EASE_OUT)
	mp_shake_tween.tween_property(mp_bar, "position", mp_bar.position + Vector2(mp_shake_strength, 0), mp_shake_duration / 4)
	mp_shake_tween.tween_property(mp_bar, "position", mp_bar.position + Vector2(-mp_shake_strength, 0), mp_shake_duration / 4)
	mp_shake_tween.tween_property(mp_bar, "position", mp_bar.position + Vector2(mp_shake_strength * 0.7, 0), mp_shake_duration / 4)
	mp_shake_tween.tween_property(mp_bar, "position", mp_bar.position, mp_shake_duration / 4)


func _on_fire() -> void:
	if is_game_over:
		return
	if Input.is_action_pressed("attack"):
		var zidan_node = zidan_scene.instantiate()
		zidan_node.position = position + Vector2(60,60)#想要子弹发射位置在法杖 
		#枪管等处就在后面加上vector2
		zidan_node.position = zidan_node.global_position
		#get_tree().root.add_child(zidan_node)
		fire_bullet()
	if Input.is_action_pressed("hanbingjian"):
		if current_mp >= 20:
			current_mp -= 20
			mp_bar.value = current_mp
			var hanbingjian_node = hanbingjian_scene.instantiate()
			hanbingjian_node.position = position + Vector2(60,60)
			get_tree().current_scene.add_child(hanbingjian_node)



func fire_bullet() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	if zidan_scene:
		var zidan: Node2D = zidan_scene.instantiate()
		# 设置子弹初始位置为当前节点位置
		zidan.global_position = global_position + Vector2(60,60)
		# 设置子弹方向为当前朝向
		var target_dir = get_global_mouse_position() - zidan.global_position
		zidan.rotation = target_dir.angle()
		# 将子弹添加到父节点（通常是主场景或关卡节点）
		get_parent().add_child(zidan)


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("enemy"):
		hp_p -= 5
		hp_bar.value = hp_p
		shake_hp_bar()
	if hp_p <= 0:
		game_over()

		
