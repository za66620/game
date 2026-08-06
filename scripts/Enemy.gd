extends CharacterBody2D

@export var patrol_range := 120.0
@export var health := 48

const SPEED := 90.0

var direction := -1
var start_x: float
var dead := false
var knockback_velocity := Vector2.ZERO

@onready var enemy_sprite: AnimatedSprite2D = $EnemySprite

func _ready() -> void:
	add_to_group("enemies")
	start_x = global_position.x

func _physics_process(delta: float) -> void:
	if dead:
		return
	if knockback_velocity.length() > 0.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	else:
		velocity.x = direction * SPEED
	enemy_sprite.flip_h = direction > 0
	move_and_slide()
	if global_position.x <= start_x - patrol_range:
		direction = 1
	elif global_position.x >= start_x + patrol_range:
		direction = -1

func stomp() -> void:
	dead = true
	_die_effect()
	queue_free()

func pound() -> void:
	stomp()

func hit(dmg: int, dir := Vector2.ZERO) -> void:
	health -= dmg
	if dir != Vector2.ZERO:
		knockback_velocity = dir * 260.0
	GameFeel.hitstop(0.05)
	GameFeel.burst(global_position, Color(0.92, 0.92, 0.97), 8)
	_flash()
	if health <= 0:
		dead = true
		_die_effect()
		queue_free()

func _die_effect() -> void:
	GameFeel.hitstop(0.08)
	GameFeel.shake(5.0, 0.18)
	GameFeel.burst(global_position, Color(0.92, 0.92, 0.97), 14)

func _flash() -> void:
	modulate = Color(1.6, 1.6, 1.6)
	await get_tree().create_timer(0.08).timeout
	if not is_queued_for_deletion():
		modulate = Color.WHITE
