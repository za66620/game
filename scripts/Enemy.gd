extends CharacterBody2D

@export var patrol_range := 120.0
@export var health := 48

const SPEED := 90.0

var direction := -1
var start_x: float
var dead := false

@onready var enemy_sprite: AnimatedSprite2D = $EnemySprite

func _ready() -> void:
	add_to_group("enemies")
	start_x = global_position.x

func _physics_process(_delta: float) -> void:
	if dead:
		return
	velocity.x = direction * SPEED
	enemy_sprite.flip_h = direction > 0
	move_and_slide()
	if global_position.x <= start_x - patrol_range:
		direction = 1
	elif global_position.x >= start_x + patrol_range:
		direction = -1

func stomp() -> void:
	dead = true
	queue_free()

func pound() -> void:
	stomp()

func hit(dmg: int) -> void:
	health -= dmg
	_flash()
	if health <= 0:
		dead = true
		queue_free()

func _flash() -> void:
	modulate = Color(1.6, 1.6, 1.6)
	await get_tree().create_timer(0.08).timeout
	if not is_queued_for_deletion():
		modulate = Color.WHITE
