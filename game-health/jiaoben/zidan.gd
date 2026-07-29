extends Area2D

@export var zidan_speed: float = 500
@export var zidan_shanghai: float = 10
var direction: Vector2
var can_rend: bool = false  # 撕裂普攻标记

# 撕裂参数（由玩家脚本设置，或使用默认值）
var rend_bleed_damage: float = 3.0
var rend_bleed_interval: float = 0.5
var rend_bleed_duration: float = 3.0
var rend_werewolf_mult: float = 2.0

func _ready() -> void:
	direction = Vector2.RIGHT.rotated(rotation)
	# 连接 area_entered 信号（如果场景中未连接）
	if not area_entered.is_connected(_on_area_entered_rend):
		area_entered.connect(_on_area_entered_rend)
	await get_tree().create_timer(5).timeout
	queue_free()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position += direction * zidan_speed * delta


func _on_area_entered_rend(area: Area2D) -> void:
	# 忽略与其他子弹的碰撞
	if area.is_in_group("zidan"):
		return

	# 找到敌人父节点（可能是 Area2D 的父节点）
	var enemy: Node = area.get_parent()
	if enemy == null:
		enemy = area

	# 检测是否为敌人
	if enemy.is_in_group("enemy"):
		# 基础伤害
		var base_damage: float = zidan_shanghai

		# 撕裂普攻：施加流血
		if can_rend and enemy.has_method("apply_bleed"):
			var bleed_dmg: float = rend_bleed_damage
			# 对狼人伤害翻倍
			if enemy.is_in_group("werewolf"):
				bleed_dmg *= rend_werewolf_mult
			enemy.apply_bleed(bleed_dmg, rend_bleed_interval, rend_bleed_duration)

		queue_free()
