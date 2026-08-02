extends Node2D
## 关卡场景管理器 — 菜单已迁移到 res://场景/menu.tscn（全局复用）。
## 这里只保留关卡专属逻辑（如分数）。

@export var score : int = 0


## 加分方法（供敌人死亡时调用）
func add_score(amount: int) -> void:
	score += amount
