extends CharacterBody2D

@export var patrol_range := 100.0
@export var charge_range := 300.0

const PATROL_SPEED := 40.0
const CHARGE_SPEED := 300.0
const STUN_TIME := 2.0

enum State { PATROL, CHARGE, STUNNED }

var state := State.PATROL
var direction := -1
var start_x: float
var dead := false
var stun_timer := 0.0
var facing := -1
var health := 120

@onready var player: Node2D = get_tree().get_first_node_in_group("player")
@onready var heavy_sprite: Sprite2D = $HeavySprite

func _ready() -> void:
	add_to_group("enemies")
	start_x = global_position.x

func _physics_process(delta: float) -> void:
	if dead:
		return
	match state:
		State.PATROL:
			velocity.x = direction * PATROL_SPEED
			heavy_sprite.flip_h = direction > 0
			move_and_slide()
			if global_position.x <= start_x - patrol_range:
				direction = 1
			elif global_position.x >= start_x + patrol_range:
				direction = -1
			_try_charge()
		State.CHARGE:
			velocity.x = facing * CHARGE_SPEED
			heavy_sprite.flip_h = facing > 0
			move_and_slide()
			if is_on_wall():
				state = State.STUNNED
				stun_timer = STUN_TIME
				heavy_sprite.modulate = Color(0.7, 0.7, 0.75)
		State.STUNNED:
			velocity.x = 0.0
			stun_timer -= delta
			if stun_timer <= 0.0:
				state = State.PATROL
				heavy_sprite.modulate = Color.WHITE

func _try_charge() -> void:
	if not player or player.dead:
		return
	var to_player := player.global_position - global_position
	if absf(to_player.x) < charge_range and absf(to_player.y) < 60.0:
		facing = signf(to_player.x)
		if facing == 0.0:
			facing = 1.0
		state = State.CHARGE
		heavy_sprite.modulate = Color(1.0, 0.45, 0.45)

func stomp() -> void:
	hit(36 if state == State.STUNNED else 12)

func hit(dmg: int, _direction := Vector2.ZERO) -> void:
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
