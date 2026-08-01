extends Area2D

var max_duration: float = 3.0
var dps: float = 20.0
var damage_tick: float = 0.5 # 每0.5秒造成一次伤害
var tick_accumulator: float = 0.0
@export var shilaimu_scene: PackedScene
@export var langr_scene: PackedScene
@export var gebul_scene: PackedScene
@export var yunshishu_scene: PackedScene
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
		# 处理持续伤害
		tick_accumulator += delta
		if tick_accumulator >= damage_tick:
			tick_accumulator = 0.0

func start_burning(duration: float, damage_per_sec: float):
	max_duration = duration
	dps = damage_per_sec
	# 这里可以添加一个Timer或者在_process中处理逻辑

func spawn_yunshishu_at_mouse():
	var yunshishu = yunshishu_scene.instantiate()
	add_child(yunshishu)
	# 获取鼠标在视口中的位置，并转换为全局坐标
	# get_global_mouse_position() 会自动处理相机偏移和缩放
	var mouse_pos = get_global_mouse_position()
	yunshishu.global_position = mouse_pos
	await get_tree().create_timer(3).timeout
	queue_free()

		
