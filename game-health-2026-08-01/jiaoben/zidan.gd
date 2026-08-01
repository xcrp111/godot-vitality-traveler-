extends Area2D

@export var zidan_speed: float = 500
@export var zidan_shanghai: float = 10
var direction: Vector2
var can_rend: bool = false  # 撕裂普攻标记

# 撕裂参数
var rend_bleed_damage: float = 3.0
var rend_bleed_interval: float = 0.5
var rend_bleed_duration: float = 3.0
var rend_werewolf_mult: float = 2.0

func _ready() -> void:
	direction = Vector2.RIGHT.rotated(rotation)
<<<<<<< Updated upstream
	# 刚生成时禁用碰撞监测，等飞出一段距离后再启用，防止被自身/地面图块秒杀
	monitoring = false
	await get_tree().process_frame
	monitoring = true
	if not area_entered.is_connected(_on_area_entered_rend):
		area_entered.connect(_on_area_entered_rend)
=======
	# 刚生成时禁用碰撞监测，等飞出一段距离后再启用，防止与自身/地面图块碰撞
	monitoring = false
	await get_tree().process_frame
	monitoring = true
	# 连接 area_entered 信号（可能已在场景中连接，先尝试断开再连接）
	if area_entered.is_connected(_on_area_entered_rend):
		area_entered.disconnect(_on_area_entered_rend)
	area_entered.connect(_on_area_entered_rend)
	# 5 秒后自动销毁
>>>>>>> Stashed changes
	await get_tree().create_timer(5).timeout
	queue_free()


func _process(delta: float) -> void:
	position += direction * zidan_speed * delta


func _on_body_entered(body: Node2D) -> void:
	# 被墙壁阻挡（StaticBody2D 或 wall 分组的 TileMapLayer）
	if body is StaticBody2D:
		queue_free()
<<<<<<< Updated upstream


func _on_area_entered_rend(area: Area2D) -> void:
	if area.is_in_group("zidan"):
		return
	# 跳过玩家自己的 Area2D，防止子弹刚生成就自毁
	if area.get_parent() and area.get_parent().is_in_group("player"):
		return
	var enemy: Node = area.get_parent() if area.get_parent() else area
	if enemy.is_in_group("enemy") and can_rend and enemy.has_method("apply_bleed"):
=======
	if body.is_in_group("wall"):
		queue_free()


func _on_area_entered_rend(area: Area2D) -> void:
	# 不与其他子弹碰撞
	if area.is_in_group("zidan"):
		return
	# 跳过玩家自己的 Area2D
	if area.get_parent() and area.get_parent().is_in_group("player"):
		return

	var enemy: Node = area.get_parent() if area.get_parent() else area

	# 只对敌人造成伤害并销毁，非敌人 Area2D（如传送门）不销毁子弹
	if not enemy.is_in_group("enemy"):
		return

	# 撕裂普攻：施加减益
	if can_rend and enemy.has_method("apply_bleed"):
>>>>>>> Stashed changes
		var bleed_dmg: float = rend_bleed_damage
		if enemy.is_in_group("werewolf"):
			bleed_dmg *= rend_werewolf_mult
		enemy.apply_bleed(bleed_dmg, rend_bleed_interval, rend_bleed_duration)
<<<<<<< Updated upstream
=======

	# 命中敌人后销毁子弹
>>>>>>> Stashed changes
	queue_free()
