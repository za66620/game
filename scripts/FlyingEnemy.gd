extends CharacterBody2D

@export var bob_range := 60.0
@export var bob_speed := 2.0
@export var health := 2

var origin_y: float
var time := 0.0
var dead := false

func _ready() -> void:
	add_to_group("enemies")
	origin_y = global_position.y

func _physics_process(delta: float) -> void:
	if dead:
		return
	time += delta * bob_speed
	global_position.y = origin_y + sin(time) * bob_range

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
