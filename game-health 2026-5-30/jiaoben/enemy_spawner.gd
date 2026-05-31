class_name EnemySpawner
extends Node2D
## 房间敌人生成器 — 玩家在哪个房间，就在哪个房间生成敌人。
##
## 编辑器中操作：
## 1. 添加 Area2D 子节点(Room1, Room2, Room3...)
## 2. 每个 Area2D 里放一个 CollisionShape2D，shape 选 RectangleShape2D
## 3. 拖动 CollisionShape2D 的矩形四角来框出房间范围（对齐墙壁内侧）
## 4. 在 enemy_scenes 中拖入敌人 .tscn

@export var spawn_interval: float = 1.0
@export var max_enemies_per_room: int = 10
@export var enemy_scenes: Array[PackedScene] = []

var _zones: Array[Area2D] = []
var _timer: Timer
var _player: Node2D
var _tick_count: int = 0


func _ready() -> void:
	# 查找真正的玩家（CharacterBody2D + group "player"，避免拿到地图层等误标节点）
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody2D:
			_player = node
			break
	if not _player:
		push_error("EnemySpawner: 找不到 group='player' 的 CharacterBody2D！")
		return

	for child in get_children():
		if child is Area2D:
			_zones.append(child)

	if _zones.is_empty():
		push_warning("EnemySpawner: 没有 Area2D 子节点！")
		return

	# 打印每个房间的边界信息
	print("========== EnemySpawner 初始化 ==========")
	for z in _zones:
		var r := _get_room_rect(z)
		print("  %s: %s (中心: %s)" % [z.name, r, r.get_center()])
	print("  玩家初始位置: %s" % _player.global_position)
	print("  玩家所在房间: %s" % _find_room_name())
	print("==========================================")

	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.one_shot = false
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()


func _get_room_rect(zone: Area2D) -> Rect2:
	for c in zone.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var shape := c.shape as RectangleShape2D
			var center: Vector2 = zone.global_position + c.position
			var half: Vector2 = shape.size / 2.0
			return Rect2(center - half, shape.size)
	return Rect2()


func _find_room_name() -> String:
	for i in range(_zones.size() - 1, -1, -1):
		if _get_room_rect(_zones[i]).has_point(_player.global_position):
			return _zones[i].name
	return "无"


func _tick() -> void:
	_tick_count += 1
	if enemy_scenes.is_empty() or _zones.is_empty():
		return

	# 从后往前找玩家所在房间
	var target: Area2D = null
	for i in range(_zones.size() - 1, -1, -1):
		if _get_room_rect(_zones[i]).has_point(_player.global_position):
			target = _zones[i]
			break

	if not target:
		if _tick_count <= 3 or _tick_count % 10 == 0:
			print("[EnemySpawner #%d] 玩家(%s) 不在任何房间！" % [_tick_count, _player.global_position])
		return

	# 统计目标房间内现存敌人数量
	var count := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and _get_room_rect(target).has_point(e.global_position):
			count += 1

	if count >= max_enemies_per_room:
		return

	# 生成敌人
	var scene: PackedScene = enemy_scenes[randi() % enemy_scenes.size()]
	var enemy: Node2D = scene.instantiate()
	var r := _get_room_rect(target)
	const M := 40.0
	enemy.global_position = Vector2(
		randf_range(r.position.x + M, r.end.x - M),
		randf_range(r.position.y + M, r.end.y - M)
	)
	get_tree().current_scene.add_child(enemy)
	print("[EnemySpawner #%d] %s 生成敌人 (存活: %d/%d)  玩家坐标: %s" % [_tick_count, target.name, count + 1, max_enemies_per_room, _player.global_position])
