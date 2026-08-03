extends CharacterBody2D

@export var patrol_range := 120.0
@export var fire_interval := 2.5
@export var detect_range := 300.0
@export var health := 2

const SPEED := 60.0
const BULLET_SPEED := 260.0

var direction := -1
var start_x: float
var dead := false
var fire_timer := 1.0

@onready var player: Node2D = get_tree().get_first_node_in_group("player")
@onready var shooting_sprite: Sprite2D = $ShootingSprite

func _ready() -> void:
	add_to_group("enemies")
	start_x = global_position.x

func _physics_process(delta: float) -> void:
	if dead:
		return
	velocity.x = direction * SPEED
	shooting_sprite.flip_h = direction > 0
	move_and_slide()
	if global_position.x <= start_x - patrol_range:
		direction = 1
	elif global_position.x >= start_x + patrol_range:
		direction = -1

	fire_timer -= delta
	if fire_timer <= 0.0 and player and not player.dead:
		var to_player := player.global_position - global_position
		if absf(to_player.y) < 80.0 and absf(to_player.x) < detect_range:
			_shoot(signf(to_player.x))
			fire_timer = fire_interval

func _shoot(dir: float) -> void:
	var bullet: Area2D = (load("res://scenes/Bullet.tscn") as PackedScene).instantiate()
	bullet.velocity = Vector2(dir * BULLET_SPEED, 0)
	bullet.shooter = self
	bullet.global_position = global_position + Vector2(dir * 20, 0)
	get_tree().current_scene.add_child(bullet)

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
