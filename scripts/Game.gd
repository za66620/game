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
var lives := 3
var total_coins := 0
var won := false
var game_over := false
var checkpoint_pos := Vector2.ZERO
var has_checkpoint := false

@onready var player: CharacterBody2D = $Player
@onready var hud_label: Label = $HUD/CoinsLabel
@onready var level_label: Label = $HUD/LevelLabel
@onready var message_label: Label = $HUD/MessageLabel
@onready var level_container: Node2D = $LevelContainer

func _ready() -> void:
	player.died.connect(_on_player_died)
	_load_level(current_level)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
	if not won and not game_over and player.global_position.y > 1200:
		_on_player_died()

func _load_level(index: int) -> void:
	for child in level_container.get_children():
		child.queue_free()
	await get_tree().process_frame

	var level: Node = (load(LEVELS[index]) as PackedScene).instantiate()
	level_container.add_child(level)

	for coin in get_tree().get_nodes_in_group("coins"):
		coin.collected.connect(_on_coin_collected)
	var goal: Node = get_tree().get_first_node_in_group("goal")
	if goal:
		goal.reached.connect(_on_goal_reached)

	has_checkpoint = false
	for checkpoint in get_tree().get_nodes_in_group("checkpoints"):
		checkpoint.activated.connect(_on_checkpoint_activated)

	player.global_position = LEVEL_STARTS[index]
	player.velocity = Vector2.ZERO
	player.dead = false
	player.set_process(true)
	player.set_physics_process(true)

	level_label.text = "第 %d / %d 关" % [index + 1, LEVELS.size()]
	_update_hud()

func _on_coin_collected(_coin: Area2D) -> void:
	total_coins += 1
	AudioManager.play("coin")
	_update_hud()

func _on_goal_reached() -> void:
	AudioManager.play("win")
	if current_level < LEVELS.size() - 1:
		current_level += 1
		_load_level(current_level)
	else:
		won = true
		message_label.text = "恭喜通关！按 R 重新开始"
		_freeze_player()

func _on_checkpoint_activated(pos: Vector2) -> void:
	checkpoint_pos = pos
	has_checkpoint = true

func _on_player_died() -> void:
	if won or game_over:
		return
	AudioManager.play("death")
	lives -= 1
	if lives <= 0:
		game_over = true
		message_label.text = "游戏结束！按 R 重新开始"
		_freeze_player()
	else:
		if has_checkpoint:
			player.global_position = checkpoint_pos
			player.velocity = Vector2.ZERO
			player.dead = false
			player.set_process(true)
			player.set_physics_process(true)
		else:
			_load_level(current_level)
	_update_hud()

func _freeze_player() -> void:
	player.set_process(false)
	player.set_physics_process(false)

func _update_hud() -> void:
	hud_label.text = "生命: %d   金币: %d" % [lives, total_coins]
