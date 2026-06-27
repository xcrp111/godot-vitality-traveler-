@tool
extends Node2D
## 一键修复：给 TileMapLayer2 的 tileset 中所有缺少碰撞的砖块补上完整碰撞体积。
## 挂到场景根 → 勾 Fix → 所有砖都有碰撞了 → 保存 → 删节点。

@export var fix: bool = false:
	set(v):
		if v and Engine.is_editor_hint():
			_fix_collision()
			fix = false


func _fix_collision() -> void:
	var tl_parent := get_parent().get_node_or_null("TileMapLayer")
	if not tl_parent:
		push_error("找不到 TileMapLayer")
		return
	var tl := tl_parent.get_node_or_null("TileMapLayer2") as TileMapLayer
	if not tl:
		push_error("找不到 TileMapLayer2")
		return

	var ts := tl.tile_set
	if not ts:
		push_error("TileMapLayer2 没有 TileSet")
		return

	var src := ts.get_source(0) as TileSetAtlasSource
	if not src:
		push_error("找不到 source 0")
		return

	var fixed := 0
	var region := src.get_tile_size()
	var half := Vector2(region) / 2.0
	var poly := PackedVector2Array([
		-half,
		Vector2(half.x, -half.y),
		half,
		Vector2(-half.x, half.y),
	])

	for tx in range(src.get_atlas_grid_size().x):
		for ty in range(src.get_atlas_grid_size().y):
			var coords := Vector2i(tx, ty)
			if not src.has_tile_at(coords):
				continue
			var data := src.get_tile_data(coords, 0)
			if data.get_collision_polygons_count(0) == 0:
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, poly)
				fixed += 1

	print("FixCollision: 已为 %d 个砖块添加碰撞体积" % fixed)
