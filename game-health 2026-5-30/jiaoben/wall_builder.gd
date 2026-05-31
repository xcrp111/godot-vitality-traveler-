@tool
extends Node2D
## 墙壁生成器 — 在编辑器中勾选 build 即可自动在 TileMapLayer2 上生成墙壁。
## 使用：挂到场景根节点，勾选 Build，墙壁自动画出，然后保存场景，删除本节点。

@export var build: bool = false:
	set(v):
		if v and Engine.is_editor_hint():
			_do_build()
			build = false

var _wall_layer: TileMapLayer
const SRC := 0  # source_id
const FULL := Vector2i(1, 1)  # 实心墙砖
const HALF := Vector2i(0, 0)  # 装饰砖


func _find_wall_layer() -> bool:
	var tl := get_parent().get_node_or_null("TileMapLayer")
	if tl:
		_wall_layer = tl.get_node_or_null("TileMapLayer2") as TileMapLayer
	return _wall_layer != null


func _put(x: int, y: int, atlas := FULL) -> void:
	_wall_layer.set_cell(Vector2i(x, y), SRC, atlas)


func _hline(x: int, y: int, w: int, atlas := FULL) -> void:
	for i in range(w):
		_put(x + i, y, atlas)


func _vline(x: int, y: int, h: int, atlas := FULL) -> void:
	for i in range(h):
		_put(x, y + i, atlas)


func _rect(x: int, y: int, w: int, h: int, atlas := FULL) -> void:
	for i in range(w):
		for j in range(h):
			_put(x + i, y + j, atlas)


func _do_build() -> void:
	if not _find_wall_layer():
		push_error("WallBuilder: 找不到 TileMapLayer/TileMapLayer2！")
		return

	print("WallBuilder: 开始生成墙壁...")

	# ============= Room1 完善围墙（x=-35~29, y=-2~40 对应世界 x=-560~464, y=-32~640）=============

	# Room1 内部障碍：中央石柱 (世界坐标 ≈ 50, 350)
	var cx := 50 / 16
	var cy := 350 / 16
	_rect(cx - 1, cy - 1, 3, 3, FULL)

	# L形墙角 (世界坐标 ≈ 200, 80)
	var lx := 200 / 16
	var ly := 80 / 16
	_hline(lx - 6, ly, 13, FULL)
	_vline(lx + 6, ly, 8, FULL)

	# ============= Room2 完善围墙（x=42~105, y=-3~40 对应世界 x=672~1680）=============

	# 三根石柱
	_rect(850 / 16 - 1, 180 / 16 - 1, 3, 3, FULL)
	_rect(1050 / 16 - 1, 200 / 16 - 1, 3, 3, FULL)
	_rect(950 / 16 - 1, 420 / 16 - 1, 3, 3, FULL)

	# 横向路障
	_hline(1350 / 16 - 8, 260 / 16, 16, FULL)

	# 短墙
	_hline(800 / 16 - 4, 480 / 16, 9, FULL)

	# ============= Room3 完善围墙（x=119~185, y=-2~40 对应世界 x=1904~2960）=============

	# C形围墙
	var cx3 := 2330 / 16
	var cy3 := 150 / 16
	_hline(cx3 - 7, cy3, 15, FULL)  # 上横
	_vline(cx3 + 7, cy3, 10, FULL)  # 右竖
	_hline(cx3 - 7, cy3 + 10, 15, FULL)  # 下横

	# 石柱
	_rect(2050 / 16 - 1, 300 / 16 - 1, 3, 3, FULL)
	_rect(2180 / 16 - 1, 430 / 16 - 1, 3, 3, FULL)

	# 窄走廊
	_vline(2670 / 16, 130 / 16, 11, FULL)
	_vline(2790 / 16, 130 / 16, 11, FULL)

	print("WallBuilder: 墙壁生成完毕！请保存场景，然后删除本 WallBuilder 节点。")
