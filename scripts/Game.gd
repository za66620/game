extends Node2D

const LEVELS: Array[String] = [
	"res://scenes/Level1.tscn",
	"res://scenes/Level2.tscn",
	"res://scenes/Level3.tscn",
]
const LEVEL_STARTS: Array[Vector2] = [
	Vector2(-1020, 520),
	Vector2(-1350, 520),
	Vector2(-1570, 520),
]

var current_level := 0
var total_souls := 0
var won := false
var respawning := false
var checkpoint_pos := Vector2.ZERO
var has_checkpoint := false
var current_boss: Node = null

@onready var player: CharacterBody2D = $Player
@onready var souls_label: Label = $HUD/PlayerStatus/SoulsLabel
@onready var health_bar: ProgressBar = $HUD/PlayerStatus/HealthBar
@onready var stamina_bar: ProgressBar = $HUD/PlayerStatus/StaminaBar
@onready var level_label: Label = $HUD/LevelLabel
@onready var message_label: Label = $HUD/MessageLabel
@onready var boss_panel: ColorRect = $HUD/BossPanel
@onready var boss_name_label: Label = $HUD/BossPanel/BossName
@onready var boss_health_bar: ProgressBar = $HUD/BossPanel/BossHealth
@onready var level_container: Node2D = $LevelContainer

func _ready() -> void:
	player.died.connect(_on_player_died)
	player.health_changed.connect(_on_player_health_changed)
	player.stamina_changed.connect(_on_player_stamina_changed)
	_load_level(current_level)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
	if not won and not respawning and player.global_position.y > 1200.0:
		player._die()

func _load_level(index: int) -> void:
	boss_panel.visible = false
	message_label.text = ""
	current_boss = null
	for child in level_container.get_children():
		child.queue_free()
	await get_tree().process_frame

	var level := (load(LEVELS[index]) as PackedScene).instantiate()
	level_container.add_child(level)

	for soul in get_tree().get_nodes_in_group("coins"):
		soul.collected.connect(_on_soul_collected)
	var goal: Node = get_tree().get_first_node_in_group("goal")
	if goal:
		goal.reached.connect(_on_goal_reached)

	has_checkpoint = false
	for checkpoint in get_tree().get_nodes_in_group("checkpoints"):
		checkpoint.activated.connect(_on_checkpoint_activated)

	current_boss = get_tree().get_first_node_in_group("boss")
	if current_boss:
		boss_panel.visible = true
		boss_name_label.text = current_boss.boss_name
		boss_health_bar.max_value = current_boss.max_health
		boss_health_bar.value = current_boss.health
		current_boss.health_changed.connect(_on_boss_health_changed)
		current_boss.defeated.connect(_on_boss_defeated)

	player.global_position = LEVEL_STARTS[index]
	player.reset_for_spawn()
	player.set_process(true)
	player.set_physics_process(true)
	level_label.text = "第 %d / %d 关" % [index + 1, LEVELS.size()]
	_update_hud()

func _on_soul_collected(_soul: Area2D) -> void:
	total_souls += 10
	AudioManager.play("coin")
	_update_hud()

func _on_goal_reached() -> void:
	if respawning or won:
		return
	AudioManager.play("win")
	if current_level < LEVELS.size() - 1:
		current_level += 1
		_load_level(current_level)
	else:
		won = true
		boss_panel.visible = false
		message_label.text = "薪火尚存——你已完成试炼！按 R 重新开始"
		_freeze_player()

func _on_checkpoint_activated(pos: Vector2) -> void:
	checkpoint_pos = pos
	has_checkpoint = true
	message_label.text = "余烬已点燃"
	await get_tree().create_timer(1.1).timeout
	if not respawning and not won:
		message_label.text = ""

func _on_player_died() -> void:
	if won or respawning:
		return
	respawning = true
	AudioManager.play("death")
	total_souls = maxi(0, total_souls - ceili(total_souls * 0.25))
	_update_hud()
	message_label.text = "你死了"
	player.set_process(false)
	player.set_physics_process(false)
	await get_tree().create_timer(1.15).timeout
	var respawn_at_checkpoint := has_checkpoint
	var respawn_position := checkpoint_pos
	await _load_level(current_level)
	if respawn_at_checkpoint:
		has_checkpoint = true
		checkpoint_pos = respawn_position
		player.global_position = respawn_position
		player.reset_for_spawn()
	message_label.text = ""
	respawning = false

func _on_player_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

func _on_player_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current

func _on_boss_health_changed(current: int, maximum: int) -> void:
	boss_health_bar.max_value = maximum
	boss_health_bar.value = current

func _on_boss_defeated() -> void:
	total_souls += 100 * (current_level + 1)
	_update_hud()
	boss_panel.visible = false
	message_label.text = "强敌已消灭——封印解除"
	await get_tree().create_timer(1.8).timeout
	if not respawning and not won:
		message_label.text = ""

func _freeze_player() -> void:
	player.set_process(false)
	player.set_physics_process(false)

func _update_hud() -> void:
	souls_label.text = "灵魂：%d" % total_souls
