extends Node2D

# 属性值
@export var attack_power: int = 1
@export var max_attack: int = 10
@export var max_hp: int = 20
@export var current_hp: int = 20
@export var max_health_status: int = 10
@export var current_health_status: int = 10
@export var max_mp: int = 20
@export var current_mp: int = 20

@onready var attack_bar: ProgressBar = $"StatsPanel/攻击力行/Bar"
@onready var attack_value: Label = $"StatsPanel/攻击力行/Value"
@onready var hp_bar: ProgressBar = $"StatsPanel/生命值行/Bar"
@onready var hp_value: Label = $"StatsPanel/生命值行/Value"
@onready var health_bar: ProgressBar = $"StatsPanel/健康状态行/Bar"
@onready var health_value: Label = $"StatsPanel/健康状态行/Value"
@onready var mp_bar: ProgressBar = $"StatsPanel/法力值行/Bar"
@onready var mp_value: Label = $"StatsPanel/法力值行/Value"


func _ready() -> void:
	refresh_display()


func refresh_display() -> void:
	attack_bar.max_value = max_attack
	attack_bar.value = attack_power
	attack_value.text = "%d/%d" % [attack_power, max_attack]

	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_value.text = "%d/%d" % [current_hp, max_hp]

	health_bar.max_value = max_health_status
	health_bar.current_health = current_health_status
	health_value.text = "%d/%d" % [current_health_status, max_health_status]

	mp_bar.max_value = max_mp
	mp_bar.value = current_mp
	mp_value.text = "%d/%d" % [current_mp, max_mp]


func set_attack(current: int, maximum: int = -1) -> void:
	attack_power = current
	if maximum > 0: max_attack = maximum
	refresh_display()

func set_hp(current: int, maximum: int = -1) -> void:
	current_hp = current
	if maximum > 0: max_hp = maximum
	refresh_display()

func set_health_status(current: int, maximum: int = -1) -> void:
	current_health_status = current
	if maximum > 0: max_health_status = maximum
	refresh_display()

func set_mp(current: int, maximum: int = -1) -> void:
	current_mp = current
	if maximum > 0: max_mp = maximum
	refresh_display()


func _on_menu_button_pressed() -> void:
	get_tree().change_scene_to_file("res://场景/主城.tscn")
