extends CanvasLayer
## 全局复用菜单 — 拖到任意场景即可使用。

@onready var menu_btn: Button = $MenuButton
@onready var menu_panel: Control = $MenuPanel
@onready var restart_btn: Button = $MenuPanel/VBoxContainer/RestartBtn
@onready var home_btn: Button = $MenuPanel/VBoxContainer/HomeBtn
@onready var close_btn: Button = $MenuPanel/VBoxContainer/CloseBtn
@onready var quit_btn: Button = $MenuPanel/VBoxContainer/QuitBtn

func _ready() -> void:
	menu_btn.pressed.connect(_open)
	restart_btn.pressed.connect(_on_restart)
	home_btn.pressed.connect(_on_home)
	close_btn.pressed.connect(_close)
	quit_btn.pressed.connect(_on_quit)
	menu_panel.visible = false

func _open() -> void:
	menu_panel.visible = true

func _close() -> void:
	menu_panel.visible = false

func _on_restart() -> void:
	_close()
	get_tree().reload_current_scene()

func _on_home() -> void:
	_close()
	get_tree().change_scene_to_file("res://场景/主城.tscn")

func _on_quit() -> void:
	get_tree().quit()
