extends Area2D

@export var zidan_speed: float = 500
@export var zidan_shanghai: float = 10
var direction: Vector2

# 撕裂普攻 —— 流血 DoT（伤害和频率已加倍）
var can_rend: bool = false
var bleed_damage: float = 1.0       # 每跳伤害
var bleed_interval: float = 0.5     # 跳间隔（提高一倍）
var bleed_duration: float = 3.0     # 总持续


func _ready() -> void:
	direction = Vector2.RIGHT.rotated(rotation)
	await get_tree().create_timer(5).timeout
	queue_free()


func _process(delta: float) -> void:
	position += direction * zidan_speed * delta


# 碰到敌人 Area2D → 造成伤害 + 撕裂流血
func _on_area_entered_rend(area: Area2D) -> void:
	var parent = area.get_parent()
	if not parent or not parent.is_in_group("enemy"):
		return

	# 基础伤害
	if parent.has_method("take_bullet_damage"):
		parent.take_bullet_damage(zidan_shanghai)

	# 撕裂普攻 —— 附加流血 DoT
	if can_rend and parent.has_method("apply_bleed"):
		var mult = 2.0 if parent.is_in_group("werewolf") else 1.0
		parent.apply_bleed(bleed_damage * mult, bleed_interval, bleed_duration)

	queue_free()


# 撞墙销毁
func _on_body_entered(body: Node2D) -> void:
	if body is TileMapLayer or body is StaticBody2D:
		queue_free()
