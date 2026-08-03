extends CharacterBody2D

signal died

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const AIR_JUMP_FACTOR := 0.85
const MAX_JUMPS := 2

const DASH_SPEED := 700.0
const DASH_TIME := 0.15
const DASH_COOLDOWN := 0.5

const WALL_SLIDE_SPEED := 70.0
const WALL_JUMP_VELOCITY_X := 420.0

const POUND_VELOCITY := 1000.0
const POUND_BOUNCE := -320.0

const ATTACK_TIME := 0.34
const ATTACK_COOLDOWN := 0.42
const ATTACK_ACTIVE_FROM := 0.24
const ATTACK_ACTIVE_UNTIL := 0.08

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var jumps_remaining := MAX_JUMPS
var dead := false
var facing := 1
var is_dashing := false
var is_pounding := false
var dash_cooldown_left := 0.0
var dash_time_left := 0.0
var wall_dir := 0
var teleport_lock := 0.0
var attack_cooldown_left := 0.0
var attack_time_left := 0.0
var attacking := false
var attack_hits: Dictionary = {}

@onready var knight_sprite: AnimatedSprite2D = $KnightSprite
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var attack_hitbox: Area2D = $AttackHitbox

func _ready() -> void:
	attack_hitbox.body_entered.connect(_on_attack_body_entered)
	knight_sprite.pause()
	_update_visuals()

func _physics_process(delta: float) -> void:
	if dead:
		return
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	teleport_lock = maxf(0.0, teleport_lock - delta)
	attack_cooldown_left = maxf(0.0, attack_cooldown_left - delta)
	_update_attack(delta)

	var direction := Input.get_axis("left", "right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1

	if Input.is_action_just_pressed("attack") and attack_cooldown_left <= 0.0:
		_start_attack()

	if Input.is_action_just_pressed("down") and not is_on_floor() and not is_dashing and not is_pounding:
		is_pounding = true
		velocity.y = POUND_VELOCITY

	if Input.is_action_just_pressed("dash") and dash_cooldown_left <= 0.0 and not is_pounding and not attacking:
		is_dashing = true
		dash_time_left = DASH_TIME
		dash_cooldown_left = DASH_COOLDOWN
		AudioManager.play("stomp")

	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			is_dashing = false
		else:
			velocity = Vector2(facing * DASH_SPEED, 0.0)
			move_and_slide()
			_update_visuals()
			return

	if not is_on_floor():
		if not is_pounding:
			velocity.y += gravity * delta
	else:
		jumps_remaining = MAX_JUMPS

	var jump_consumed := false
	wall_dir = 0
	if is_on_wall() and not is_on_floor() and not is_pounding:
		wall_dir = signi(int(round(get_wall_normal().x)))
		if Input.is_action_just_pressed("jump"):
			velocity.x = wall_dir * WALL_JUMP_VELOCITY_X
			velocity.y = JUMP_VELOCITY * 0.9
			jumps_remaining = MAX_JUMPS - 1
			jump_consumed = true
			AudioManager.play("jump")
		elif Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	if not is_pounding and not jump_consumed and Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			jumps_remaining = MAX_JUMPS - 1
			AudioManager.play("jump")
		elif jumps_remaining > 0 and not is_on_wall():
			velocity.y = JUMP_VELOCITY * AIR_JUMP_FACTOR
			jumps_remaining -= 1
			AudioManager.play("jump")

	if is_pounding:
		velocity.y = POUND_VELOCITY
	else:
		velocity.x = direction * SPEED * (0.45 if attacking else 1.0)
		if wall_dir != 0 and Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	move_and_slide()

	if is_pounding and is_on_floor():
		_pound_shockwave()
		velocity.y = POUND_BOUNCE
		is_pounding = false
		AudioManager.play("stomp")

	_check_collisions()
	_update_visuals()

func _update_visuals() -> void:
	# Every frame is a strict side view; mirroring swaps the travel direction.
	knight_sprite.flip_h = facing < 0
	attack_shape.position.x = facing * 42.0
	if dead:
		knight_sprite.pause()
		knight_sprite.frame = 0
		return
	if attacking:
		if knight_sprite.animation != &"slash":
			knight_sprite.play(&"slash")
	elif is_dashing:
		knight_sprite.play(&"walk")
		knight_sprite.speed_scale = 2.4
	elif not is_on_floor():
		knight_sprite.pause()
		knight_sprite.frame = 2 if velocity.y < 0.0 else 3
	elif absf(velocity.x) > 1.0:
		knight_sprite.play(&"walk")
		knight_sprite.speed_scale = 1.0
	else:
		knight_sprite.pause()
		knight_sprite.frame = 0

func _check_collisions() -> void:
	if is_dashing:
		return
	for i in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider is Node2D and collider.is_in_group("enemies"):
			if attacking and collider.has_method("hit"):
				collider.hit(2)
				continue
			if velocity.y > 0 and global_position.y < collider.global_position.y:
				_stomp(collider)
			else:
				_die()
		elif collider is Node2D and collider.is_in_group("spikes"):
			_die()

func _pound_shockwave() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("pound"):
			enemy.pound()

func _stomp(enemy: Node2D) -> void:
	velocity.y = JUMP_VELOCITY * 0.6
	jumps_remaining = 1
	AudioManager.play("stomp")
	if enemy.has_method("stomp"):
		enemy.stomp()

func launch(vy: float) -> void:
	if dead:
		return
	is_pounding = false
	velocity.y = vy
	jumps_remaining = MAX_JUMPS - 1

func _start_attack() -> void:
	if dead or is_dashing:
		return
	attacking = true
	attack_time_left = ATTACK_TIME
	attack_cooldown_left = ATTACK_COOLDOWN
	attack_hits.clear()
	attack_shape.set_deferred("disabled", true)
	knight_sprite.play(&"slash")
	AudioManager.play("stomp")

func _update_attack(delta: float) -> void:
	if not attacking:
		return
	attack_time_left -= delta
	var active := attack_time_left <= ATTACK_ACTIVE_FROM and attack_time_left >= ATTACK_ACTIVE_UNTIL
	attack_shape.set_deferred("disabled", not active)
	if attack_time_left <= 0.0:
		attacking = false
		attack_shape.set_deferred("disabled", true)

func _on_attack_body_entered(body: Node2D) -> void:
	if not attacking or not body.is_in_group("enemies") or not body.has_method("hit"):
		return
	var body_id := body.get_instance_id()
	if attack_hits.has(body_id):
		return
	attack_hits[body_id] = true
	body.hit(2)

func teleport_to(pos: Vector2) -> bool:
	if teleport_lock > 0.0 or dead:
		return false
	teleport_lock = 0.5
	global_position = pos
	velocity = Vector2.ZERO
	is_pounding = false
	is_dashing = false
	return true

func _die() -> void:
	if dead or is_dashing:
		return
	dead = true
	is_pounding = false
	is_dashing = false
	attacking = false
	attack_shape.set_deferred("disabled", true)
	wall_dir = 0
	_update_visuals()
	died.emit()
