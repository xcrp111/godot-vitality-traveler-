extends Node2D

# 预加载敌人场景，确保路径正确
@export var enemy_scene: PackedScene = preload("res://Enemy/enemy.tscn")
@export var shilaimu_scene : PackedScene

# 引用 TileMapLayer 节点，请确保在编辑器中正确绑定或路径正确
@onready var tile_map_layer: TileMapLayer = $YourTileMapLayerNode

# 定时器节点引用，假设场景中有一个 Timer 节点名为 "SpawnTimer"
@onready var spawn_timer: Timer = $SpawnTimer

func _ready() -> void:
	# 确保 Timer 已启动
	if spawn_timer:
		spawn_timer.start()
	else:
		push_error("SpawnTimer node not found!")

func _on_spawn_timer_timeout() -> void:
	# 检查 TileMapLayer 是否有效
	if not tile_map_layer:
		return

	# 获取图层 0 的所有已使用单元格坐标
	# get_used_cells(0) 返回 Array[Vector2i]
	var used_cells: Array[Vector2i] = tile_map_layer.get_used_cells()
	
	# 如果没有可用单元格，则不生成
	if used_cells.is_empty():
		return

	# 创建随机数生成器
	var rng = RandomNumberGenerator.new()
	rng.randomize() # 确保每次随机性不同
	
	# 随机选择一个单元格的索引
	var random_index: int = rng.randi_range(0, used_cells.size() - 1)
	
	# 获取选中的单元格坐标 (Vector2i)
	var selected_cell: Vector2i = used_cells[random_index]
	
	# 将单元格坐标转换为全局/本地位置
	# map_to_local 将地图单元格坐标转换为相对于 TileMapLayer 的位置
	var local_position: Vector2 = tile_map_layer.map_to_local(selected_cell)
	
	# 实例化敌人
	if enemy_scene:
		var enemy_instance: Node2D = enemy_scene.instantiate() as Node2D
		
		# 设置敌人位置
		# 注意：如果敌人是添加到当前节点(self)，位置是相对于 self 的
		# 如果 TileMapLayer 和 self 在同一层级且无额外变换，可能需要调整
		# 通常建议将敌人添加为 TileMapLayer 的子节点或者使用全局位置
		enemy_instance.position = local_position
		
		# 将敌人添加到场景中
		# 建议添加到 TileMapLayer 的父节点或专门的管理节点，避免层级混乱
		self.add_child(enemy_instance)
	else:
		push_error("Enemy scene is not assigned!")
