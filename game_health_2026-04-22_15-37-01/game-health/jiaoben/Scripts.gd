extends CharacterBody2D

@export var move_speed : float = 300

@onready var marker2d = $Marker2D
# 当前输入方向向量（单位化前的原始输入）
var direction = Input.get_vector("left","right","up","down")
var zidan_dir = Vector2.ZERO
var is_game_over : bool = false
@export var zidan_scene : PackedScene
@export var hanbingjian_scene :PackedScene
@export var shilaimu_scene : PackedScene
var attack_enemies = []
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if not is_game_over:
		velocity = Input.get_vector("left","right","up","down") * move_speed
		if Input.is_action_pressed("right"):
			marker2d.scale = Vector2(1,1)
		elif Input.is_action_pressed("left"):
			marker2d.scale = Vector2(-1,1)
	move_and_slide()
	var mouse_pos: Vector2 = get_global_mouse_position()
	look_at(mouse_pos)
func game_over():
	is_game_over = true
	await get_tree().create_timer(4).timeout
	get_tree().reload_current_scene()


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
		zidan.rotation = rotation
		# 将子弹添加到父节点（通常是主场景或关卡节点）
		get_parent().add_child(zidan)
		


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group('enemy') and !attack_enemies.has(body):
		attack_enemies.append(body)
		
func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group('enemy') and attack_enemies.has(body):
		attack_enemies.remove_at(attack_enemies.find(body))
