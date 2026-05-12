extends Area2D
@export var gebul_sudu : float = -70
@export var gebul_scene : PackedScene
@export var gebul_xueliang : float = 15
var is_dead : bool = false
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if not is_dead:
		position += Vector2(gebul_sudu,0) * delta #delta=1/每秒帧数
	if position.x < -880:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		await get_tree().create_timer(0.8).timeout
		body.game_over()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("zidan"):
		gebul_xueliang -= 10
		print("mingzhong")
		area.queue_free() #如果想要贯穿的子弹就删掉这行
	if area.is_in_group('hanbingjian'):
		gebul_xueliang -=10
		gebul_sudu = gebul_sudu * 0.75
	if gebul_xueliang <= 0:
		$AnimatedSprite2D.play("siwang") #如果绿色名称被修改就会报错
		is_dead = true
		get_tree().current_scene.score += 1
		#0.6秒后删除史莱姆节点
		await get_tree().create_timer(0.6).timeout
		queue_free()
