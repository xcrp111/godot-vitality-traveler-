class_name EnemySpawner
extends Node2D
## 房间波次敌人生成器 + 传送门触发器。
## - 玩家进入房间后，按波次依次生成敌人
## - 当前波敌人全部击杀后才进入下一波
## - 全部波次清空后激活传送门
## - 玩家离开房间时暂停，回来后继续

# ============================================================
# 波次配置 —— 在编辑器中拖入敌人场景即可调整
# ================================================sada============
@export var wave_1_enemies: Array[PackedScene] = []   # 第一波敌人列表
@export var wave_2_enemies: Array[PackedScene] = []   # 第二波敌人列表
@export var wave_3_enemies: Array[PackedScene] = []   # 第三波敌人列表
@export var spawn_interval: float = 2.0               # 同波内敌人生成间隔（秒）
@export var wave_interval: float = 2.0                # 击杀完一波后，等待多久开始下一波（秒）
@export var min_spawn_distance_from_player: float = 180.0
@export var min_spawn_distance_between_enemies: float = 60.0
@export var wave_label_x: float = 1000.0              # 波次标签 X 位置（屏幕坐标）
@export var wave_label_y: float = 8.0                 # 波次标签 Y 位置

# 状态：生成中 → 等待击杀 → 间隔 → 下一波 → ... → 完成
const STATE_SPAWNING  := 0   # 正在逐个生成敌人
const STATE_FIGHTING  := 1   # 全部生成完毕，等待玩家击杀
const STATE_WAITING   := 2   # 本波击杀完毕，等待间隔后开始下一波
const STATE_COMPLETED := 3   # 全部波次完成（等击杀完后激活传送门）

var _zones: Array[Area2D] = []
var _player: Node2D
var _waves: Array = []  # Array[Array[PackedScene]]
var _wave_label: Label = null

# 每个房间独立的状态
var _wave_idx: Array[int] = []          # 当前波次 (-1=未开始)
var _spawn_count: Array[int] = []       # 当前波已生成数量
var _state: Array[int] = []             # SPAWNING / FIGHTING / WAITING / COMPLETED
var _timer: Array[float] = []           # 倒计时
var _entered: Array[bool] = []          # 是否首次进入
var _portal_triggered: Array[bool] = [] # 传送门是否已激活
var _current_room: int = -1
var _tick_count: int = 0


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

	# 收集非空波次
	var raw := [wave_1_enemies, wave_2_enemies, wave_3_enemies]
	for w in raw:
		if not w.is_empty():
			_waves.append(w)

	if _waves.is_empty():
		push_warning("EnemySpawner: 没有配置任何波次敌人！请在编辑器中给 wave_X_enemies 拖入场景。")
		return

	# 初始化每个房间的状态
	for _i in range(_zones.size()):
		_wave_idx.append(-1)
		_spawn_count.append(0)
		_state.append(STATE_SPAWNING)
		_timer.append(0.0)
		_entered.append(false)
		_portal_triggered.append(false)

	print("========== EnemySpawner 初始化 ==========")
	print("  波次总数: %d" % _waves.size())
	for wi in range(_waves.size()):
		print("  第%d波: %d 个敌人" % [wi + 1, (_waves[wi] as Array).size()])
	print("  生成间隔: %.1fs    波次间隔: %.1fs" % [spawn_interval, wave_interval])
	for z in _zones:
		var r := _get_room_rect(z)
		print("  %s: %s" % [z.name, r])
	print("==========================================")

	# 创建波次显示 Label（自己的 CanvasLayer，不依赖玩家节点）
	var canvas := CanvasLayer.new()
	canvas.name = "WaveCanvas"
	add_child(canvas)
	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.position = Vector2(wave_label_x, wave_label_y)
	_wave_label.size = Vector2(200, 36)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.add_theme_font_size_override("font_size", 22)
	_wave_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))  # 金色
	canvas.add_child(_wave_label)


func _process(delta: float) -> void:
	if _zones.is_empty() or _waves.is_empty():
		return

	var room_idx := _find_room_index()

	# 首次进入某房间
	if room_idx >= 0 and room_idx != _current_room:
		_current_room = room_idx
		if not _entered[room_idx]:
			_entered[room_idx] = true
			print("[EnemySpawner] 玩家首次进入 %s！" % _zones[room_idx].name)

	# 玩家不在任何房间 → 暂停
	if room_idx < 0:
		return

	# 全部波次完成 → 检查敌人是否全部消灭，触发传送门
	if _state[room_idx] == STATE_COMPLETED:
		if not _portal_triggered[room_idx]:
			_check_room_clear_for_portal(room_idx)
		return

	# 首次进入房间 → 开始第一波
	if _wave_idx[room_idx] == -1:
		_start_wave(room_idx, 0)
		# 不 return，本帧即生成第一个敌人

	# ── 状态机 ──
	match _state[room_idx]:
		STATE_SPAWNING:
			_process_spawning(room_idx, delta)

		STATE_FIGHTING:
			_process_fighting(room_idx)

		STATE_WAITING:
			_process_waiting(room_idx, delta)


# ============================================================
# 状态处理
# ============================================================

func _process_spawning(room_idx: int, delta: float) -> void:
	_timer[room_idx] -= delta
	if _timer[room_idx] > 0.0:
		return

	var wave_enemies: Array = _waves[_wave_idx[room_idx]] as Array
	if _spawn_count[room_idx] < wave_enemies.size():
		# 还有敌人未生成 → 生成下一个
		_spawn_enemy(room_idx, wave_enemies[_spawn_count[room_idx]] as PackedScene)
		_spawn_count[room_idx] += 1
		_timer[room_idx] = spawn_interval
	else:
		# 本波敌人生成完毕 → 进入"等待击杀"状态
		_state[room_idx] = STATE_FIGHTING
		print("[EnemySpawner] %s 第%d波生成完毕，等待玩家消灭..." % [_zones[room_idx].name, _wave_idx[room_idx] + 1])


func _process_fighting(room_idx: int) -> void:
	# 检查房间内是否还有存活的敌人
	if _room_has_enemies(room_idx):
		return  # 还有敌人，继续等

	# 全部击杀！
	print("[EnemySpawner] %s 第%d波敌人全部消灭！" % [_zones[room_idx].name, _wave_idx[room_idx] + 1])

	if _wave_idx[room_idx] + 1 < _waves.size():
		# 还有下一波 → 进入等待间隔
		_state[room_idx] = STATE_WAITING
		_timer[room_idx] = wave_interval
		print("[EnemySpawner] %s %.1fs 后开始第%d波" % [_zones[room_idx].name, wave_interval, _wave_idx[room_idx] + 2])
	else:
		# 最后一波也清完了 → 进入完成状态
		_state[room_idx] = STATE_COMPLETED
		print("[EnemySpawner] %s 全部波次生成完毕，等待消灭所有敌人..." % _zones[room_idx].name)


func _process_waiting(room_idx: int, delta: float) -> void:
	_timer[room_idx] -= delta
	if _timer[room_idx] > 0.0:
		return

	# 间隔结束 → 开始下一波
	_start_wave(room_idx, _wave_idx[room_idx] + 1)


# ============================================================
# 内部方法
# ============================================================

func _start_wave(room_idx: int, wave: int) -> void:
	_wave_idx[room_idx] = wave
	_spawn_count[room_idx] = 0
	_state[room_idx] = STATE_SPAWNING
	_timer[room_idx] = 0.0  # 立即生成第一个敌人
	var total := (_waves[wave] as Array).size()
	print("[EnemySpawner] %s 第%d/%d波开始 (%d个敌人)" % [_zones[room_idx].name, wave + 1, _waves.size(), total])
	# 更新波次显示
	if _wave_label:
		_wave_label.text = "第 %d / %d 波" % [wave + 1, _waves.size()]


func _spawn_enemy(room_idx: int, scene: PackedScene) -> void:
	_tick_count += 1
	var target := _zones[room_idx]
	var enemy: Node2D = scene.instantiate()
	var r := _get_room_rect(target)
	const MARGIN := 40.0
	const MAX_RETRIES := 15

	var spawn_pos: Vector2
	for _attempt in range(MAX_RETRIES):
		spawn_pos = Vector2(
			randf_range(r.position.x + MARGIN, r.end.x - MARGIN),
			randf_range(r.position.y + MARGIN, r.end.y - MARGIN)
		)
		if _player and spawn_pos.distance_to(_player.global_position) < min_spawn_distance_from_player:
			continue
		var too_close := false
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and spawn_pos.distance_to(e.global_position) < min_spawn_distance_between_enemies:
				too_close = true
				break
		if not too_close:
			break

	enemy.global_position = spawn_pos
	get_tree().current_scene.add_child(enemy)
	print("[EnemySpawner #%d] %s 第%d波 [%d/%d] %s  pos: %s" % [
		_tick_count, target.name, _wave_idx[room_idx] + 1,
		_spawn_count[room_idx] + 1, (_waves[_wave_idx[room_idx]] as Array).size(),
		enemy.name, spawn_pos
	])


func _room_has_enemies(room_idx: int) -> bool:
	var r := _get_room_rect(_zones[room_idx])
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and r.has_point(e.global_position):
			return true
	return false


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


# ============================================================
# 房间清空检测 & 传送门触发
# ============================================================

func _check_room_clear_for_portal(room_idx: int) -> void:
	if _room_has_enemies(room_idx):
		return

	# 全部消灭！
	_portal_triggered[room_idx] = true
	print("[EnemySpawner] %s 敌人全部消灭！激活传送门" % _zones[room_idx].name)
	if _wave_label:
		_wave_label.text = "✓ 已清空"
	match room_idx:
		0:
			_start_portal("portal")
			_start_portal("portal2")
		1:
			_start_portal("portal3")
		2:
			_start_portal("portal4")
			_start_portal("portal5")


func _start_portal(p_name: String) -> void:
	var p := get_parent().get_node_or_null("portal/" + p_name)
	if p and p.has_method("start_countdown"):
		p.start_countdown()
		print("[EnemySpawner] 传送门 %s 开始倒计时" % p_name)
	else:
		push_warning("EnemySpawner: 找不到传送门 " + p_name)
