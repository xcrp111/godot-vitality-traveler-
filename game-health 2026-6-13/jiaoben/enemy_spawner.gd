class_name EnemySpawner
extends Node2D
## 房间敌人生成器 + 传送门触发器。
## - 玩家在哪个房间，就在哪个房间生成敌人
## - 玩家首次进入某房间时，触发该房间对应的传送门开始倒计时

@export var spawn_interval: float = 1.0
@export var max_enemies_per_room: int = 10
@export var enemy_scenes: Array[PackedScene] = []
@export var min_spawn_distance_from_player: float = 180.0  # 生成点离玩家的最小距离
@export var min_spawn_distance_between_enemies: float = 60.0  # 敌人之间的最小生成距离

var _zones: Array[Area2D] = []
var _timer: Timer
var _player: Node2D
var _tick_count: int = 0
var _current_room: int = -1
var _entered: Array[bool] = [false, false, false]  # 记录首次进入


func _ready() -> void:
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

	print("========== EnemySpawner 初始化 ==========")
	for z in _zones:
		var r := _get_room_rect(z)
		print("  %s: %s (中心: %s)" % [z.name, r, r.get_center()])
	print("  玩家初始位置: %s" % _player.global_position)
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


func _find_room_index() -> int:
	for i in range(_zones.size() - 1, -1, -1):
		if _get_room_rect(_zones[i]).has_point(_player.global_position):
			return i
	return -1


func _tick() -> void:
	_tick_count += 1
	if _zones.is_empty():
		return

	# 检测当前房间
	var room_idx := _find_room_index()

	# 首次进入房间 → 触发传送门
	if room_idx >= 0 and room_idx != _current_room:
		_current_room = room_idx
		if not _entered[room_idx]:
			_entered[room_idx] = true
			_on_first_enter(room_idx)

	if enemy_scenes.is_empty():
		return

	if room_idx < 0:
		if _tick_count <= 3 or _tick_count % 10 == 0:
			print("[EnemySpawner #%d] 玩家(%s) 不在任何房间！" % [_tick_count, _player.global_position])
		return

	var target := _zones[room_idx]
	var count := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and _get_room_rect(target).has_point(e.global_position):
			count += 1

	if count >= max_enemies_per_room:
		return

	var scene: PackedScene = enemy_scenes[randi() % enemy_scenes.size()]
	var enemy: Node2D = scene.instantiate()
	var r := _get_room_rect(target)
	const M := 40.0

	# 尝试在安全位置生成（远离玩家和其他敌人）
	var spawn_pos: Vector2
	var is_safe := false
	const MAX_RETRIES := 15

	for attempt in range(MAX_RETRIES):
		spawn_pos = Vector2(
			randf_range(r.position.x + M, r.end.x - M),
			randf_range(r.position.y + M, r.end.y - M)
		)

		# 检查离玩家是否足够远
		if _player and spawn_pos.distance_to(_player.global_position) < min_spawn_distance_from_player:
			continue

		# 检查离其他敌人是否足够远
		var too_close_to_enemy := false
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and spawn_pos.distance_to(e.global_position) < min_spawn_distance_between_enemies:
				too_close_to_enemy = true
				break

		if not too_close_to_enemy:
			is_safe = true
			break

	if not is_safe:
		print("[EnemySpawner #%d] 警告：%d 次重试后未找到安全位置，使用最后位置" % [_tick_count, MAX_RETRIES])

	enemy.global_position = spawn_pos
	get_tree().current_scene.add_child(enemy)
	print("[EnemySpawner #%d] %s 生成敌人 (存活: %d/%d)  pos: %s  玩家: %s" % [_tick_count, target.name, count + 1, max_enemies_per_room, spawn_pos, _player.global_position])


# ============================================================
# 传送门触发
# ============================================================

func _on_first_enter(room_idx: int) -> void:
	print("[EnemySpawner] 玩家首次进入 %s！" % _zones[room_idx].name)
	match room_idx:
		0:  # Room1 — 传送门1/2 已 auto_start，无需操作
			pass
		1:  # Room2 — 启动传送门3（Room2→Room3）
			_start_portal("portal3")
		2:  # Room3 — 启动传送门4（Room3→Room2）+ 传送门5（Room3→家园）
			_start_portal("portal4")
			_start_portal("portal5")


func _start_portal(p_name: String) -> void:
	var p := get_parent().get_node_or_null("portal/" + p_name)
	if p and p.has_method("start_countdown"):
		p.start_countdown()
	else:
		push_warning("EnemySpawner: 找不到传送门 " + p_name)
