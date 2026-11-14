class_name RoomWaves
extends Node
## 挂在房间 Area2D 下，定义该房间专属的波次配置。
## 如果不添加此节点，则使用 EnemySpawner 的全局默认波次。

@export var wave_1: Array[PackedScene] = []
@export var wave_2: Array[PackedScene] = []
@export var wave_3: Array[PackedScene] = []
