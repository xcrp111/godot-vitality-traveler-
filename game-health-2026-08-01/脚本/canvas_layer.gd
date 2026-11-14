extends CanvasLayer
var ui_opened: bool = false
# 供外部信号调用，显示面板
func show_ui():
	if ui_opened:
		return
	visible = true
	# 暂停所有player、enemy分组节点
	get_tree().paused = true
	ui_opened = true

# 供外部信号调用，隐藏面板
func heal_player():
	if not ui_opened:
		return
	close_ui_base()

# 2. 加蓝按钮函数（永久提升蓝量上限+当前蓝）
func add_mana():
	if not ui_opened:
		return
	close_ui_base()

# 3. 移速提升按钮函数（永久基础移速）
func speed_up():
	if not ui_opened:
		return
	close_ui_base()

# 公共关闭UI、恢复游戏
func close_ui_base():
	visible = false
	get_tree().paused = false
	ui_opened = false


func _on_portal_open_ui() -> void:
	show_ui() 


func _on_portal_close_ui() -> void:
	close_ui_base()
