extends CanvasLayer
var ui_opened: bool = false

# 供外部信号调用，显示面板
func show_ui():
	if ui_opened:
		return
	visible = true
	get_tree().paused = true
	ui_opened = true
	_randomize_buffs()
<<<<<<< Updated upstream:game-health/脚本/canvas_layer.gd

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
>>>>>>> Stashed changes:game-health-2026-08-01/脚本/canvas_layer.gd

# 从6个增益中随机选3个显示
func _randomize_buffs():
	var hbox = $HBoxContainer
	if not hbox:
		return
	var buttons: Array = hbox.get_children()
	buttons.shuffle()
	for i in buttons.size():
		buttons[i].visible = (i < 3)

# 原有关闭方法
func heal_player():
	if not ui_opened: return
	close_ui_base()

func add_mana():
	if not ui_opened: return
	close_ui_base()

func speed_up():
	if not ui_opened: return
	close_ui_base()

# 新增关闭方法
func rending_attack():
	if not ui_opened: return
	close_ui_base()

func wild_charge():
	if not ui_opened: return
	close_ui_base()

func bloodthirst():
	if not ui_opened: return
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
func close_ui_base():
	visible = false
	get_tree().paused = false
	ui_opened = false


func _on_portal_open_ui() -> void:
	show_ui()


func _on_portal_close_ui() -> void:
	close_ui_base()
