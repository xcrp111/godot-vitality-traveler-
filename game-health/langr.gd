extends CharacterBody2D

# 导出变量，方便在编辑器中调整
@export var move_speed: float = 100.0
@export var detection_range: float = 400.0

# 引用玩家节点
# 注意：在实际项目中，建议通过组(Group)或单例来获取玩家，这里假设场景中有一个名为 "Player" 的节点
var player: Node2D

func _ready():
	# 尝试获取玩家引用
	# 如果玩家不在根节点，请修改路径，例如: get_node("/root/Level/Player")
	player = $"../wanjia"
	
	# 如果找不到玩家，打印警告并禁用此脚本的逻辑部分
	if not player:
		push_warning("Enemy: Player node not found! Ensure a node named 'Player' exists at /root/Player.")

func _physics_process(delta):
	if not player:
		return
		
	# 计算怪物与玩家之间的距离
	var distance_to_player = global_position.distance_to(player.global_position)
	
	# 简单的状态判断：如果在检测范围内，则追击
	if distance_to_player < detection_range:
		chase_player(delta)
	else:
		# 超出范围可以停止或执行巡逻逻辑，这里设为停止
		velocity = velocity.move_toward(Vector2.ZERO, move_speed)
		move_and_slide()

func chase_player(delta):
	# 1. 计算指向玩家的方向向量
	var direction = (player.global_position - global_position).normalized()
	
	# 2. 设置速度
	velocity = direction * move_speed
	
	# 3. 移动角色
	move_and_slide()
	
	# 4. (可选) 让怪物精灵朝向玩家
	# 如果有 Sprite2D 子节点，可以取消下面注释来实现翻转
	# if $Sprite2D:
	#     $Sprite2D.flip_h = direction.x < 0
