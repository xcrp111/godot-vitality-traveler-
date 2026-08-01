extends CanvasLayer

var ui_opened: bool = false

<<<<<<< Updated upstream
=======

>>>>>>> Stashed changes
# 供外部信号调用，显示面板
func show_ui():
	if ui_opened:
		return
	visible = true
	get_tree().paused = true
	ui_opened = true
	_randomize_buffs()
<<<<<<< Updated upstream

# 从6个增益中随机选3个显示
func _randomize_buffs():
	var hbox = $HBoxContainer
	if not hbox:
		return
	var buttons: Array = hbox.get_children()
	buttons.shuffle()
	for i in buttons.size():
		buttons[i].visible = (i < 3)
=======
>>>>>>> Stashed changes


# 随机打乱6个按钮，只显示前3个
func _randomize_buffs():
	var hbox = $HBoxContainer
	if not hbox:
		return
	var buttons: Array = hbox.get_children()
	# Fisher-Yates 洗牌
	var n = buttons.size()
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		var tmp = buttons[i]
		buttons[i] = buttons[j]
		buttons[j] = tmp
	# 重新按洗牌顺序排列子节点并只显示前3个
	for idx in range(buttons.size()):
		var btn = buttons[idx]
		btn.visible = (idx < 3)
		hbox.move_child(btn, idx)


<<<<<<< Updated upstream
# 3. 移速提升按钮函数（永久基础移速）
func speed_up():
	if not ui_opened:
		return
	close_ui_base()

# 4. 撕裂普攻
func rending_attack():
	if not ui_opened:
		return
	close_ui_base()

# 5. 野性蓄力
func wild_charge():
	if not ui_opened:
		return
	close_ui_base()

# 6. 嗜血
func bloodthirst():
	if not ui_opened:
		return
	close_ui_base()

# 公共关闭UI、恢复游戏
=======
>>>>>>> Stashed changes
func close_ui_base():
	visible = false
	get_tree().paused = false
	ui_opened = false


<<<<<<< Updated upstream
func _on_portal_open_ui() -> void:
	show_ui()
=======
# ============================================================
# 增益方法 —— 双连信号：wanjia.增益函数() + CanvasLayer.close()
# ============================================================
>>>>>>> Stashed changes

# 1. 加蓝
func add_mana():
	if not ui_opened:
		return
	close_ui_base()

# 2. 加血
func heal_player():
	if not ui_opened:
		return
	close_ui_base()

# 3. 加移速
func speed_up():
	if not ui_opened:
		return
	close_ui_base()

# 4. 撕裂普攻
func rending_attack():
	if not ui_opened:
		return
	close_ui_base()

# 5. 野性蓄力
func wild_charge():
	if not ui_opened:
		return
	close_ui_base()

# 6. 嗜血
func bloodthirst():
	if not ui_opened:
		return
	close_ui_base()
