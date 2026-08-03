extends CharacterBody2D

signal died

const SPEED := 320.0
const JUMP_VELOCITY := -560.0

const DASH_SPEED := 700.0
const DASH_TIME := 0.15
const DASH_COOLDOWN := 0.5
const NORMAL_COLLISION_MASK := 3
const DASH_COLLISION_MASK := 1

const WALL_SLIDE_SPEED := 70.0
const WALL_JUMP_VELOCITY_X := 420.0

const POUND_VELOCITY := 1000.0
const POUND_BOUNCE := -320.0

const ATTACK_TIME := 0.34
const ATTACK_COOLDOWN := 0.42
const ATTACK_ACTIVE_FROM := 0.24
const ATTACK_ACTIVE_UNTIL := 0.08

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var dead := false
var facing := 1
var is_dashing := false
var is_pounding := false
var blocking := false
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
@onready var contact_sensor: Area2D = $ContactSensor
@onready var shield_guard: Node2D = $ShieldGuard

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
	blocking = Input.is_action_pressed("down") and is_on_floor() and not attacking and not is_dashing

	if Input.is_action_just_pressed("attack") and attack_cooldown_left <= 0.0 and not blocking:
		_start_attack()

	if Input.is_action_just_pressed("down") and not is_on_floor() and not is_dashing and not is_pounding:
		is_pounding = true
		velocity.y = POUND_VELOCITY

	var dash_combo_pressed := direction != 0.0 and Input.is_action_pressed("dash") and (
		Input.is_action_just_pressed("dash")
		or Input.is_action_just_pressed("left")
		or Input.is_action_just_pressed("right")
	)
	if dash_combo_pressed and dash_cooldown_left <= 0.0 and not is_pounding and not attacking and not blocking:
		_begin_dash(1 if direction > 0.0 else -1)

	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			_end_dash()
		else:
			velocity = Vector2(facing * DASH_SPEED, 0.0)
			move_and_slide()
			_update_visuals()
			return

	if not is_on_floor():
		if not is_pounding:
			velocity.y += gravity * delta
	var jump_consumed := false
	wall_dir = 0
	if is_on_wall() and not is_on_floor() and not is_pounding:
		wall_dir = signi(int(round(get_wall_normal().x)))
		if Input.is_action_just_pressed("jump"):
			velocity.x = wall_dir * WALL_JUMP_VELOCITY_X
			velocity.y = JUMP_VELOCITY * 0.9
			jump_consumed = true
			AudioManager.play("jump")
		elif Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	if not is_pounding and not jump_consumed and not blocking and Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			AudioManager.play("jump")

	if is_pounding:
		velocity.y = POUND_VELOCITY
	elif blocking:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	else:
		velocity.x = direction * SPEED * (0.45 if attacking else 1.0)
		if wall_dir != 0 and Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	move_and_slide()
	if blocking and not is_on_floor():
		blocking = false
	_check_enemy_contacts()

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
	shield_guard.visible = blocking
	shield_guard.position.x = facing * 28.0
	shield_guard.scale = Vector2(0.8 * facing, 0.8)
	knight_sprite.position.y = 9.0 if attacking else 0.0
	if dead:
		knight_sprite.animation = &"walk"
		knight_sprite.pause()
		knight_sprite.frame = 0
		return
	if attacking:
		if knight_sprite.animation != &"slash":
			knight_sprite.play(&"slash")
		return
	else:
		if knight_sprite.animation != &"walk":
			knight_sprite.animation = &"walk"
	if is_dashing:
		knight_sprite.play(&"walk")
		knight_sprite.speed_scale = 2.4
	elif blocking:
		knight_sprite.pause()
		knight_sprite.frame = 0
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
		if collider is Node2D and collider.is_in_group("spikes"):
			_die()

func _check_enemy_contacts() -> void:
	if is_dashing or dead:
		return
	for body in contact_sensor.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if attacking:
			_on_attack_body_entered(body)
			continue
		if blocking and _is_in_front(body.global_position):
			velocity.x = -facing * 60.0
			continue
		if velocity.y > 0.0 and global_position.y < body.global_position.y:
			_stomp(body)
		else:
			_die()
		return

func _pound_shockwave() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("pound"):
			enemy.pound()

func _stomp(enemy: Node2D) -> void:
	velocity.y = JUMP_VELOCITY * 0.6
	AudioManager.play("stomp")
	if enemy.has_method("stomp"):
		enemy.stomp()

func launch(vy: float) -> void:
	if dead:
		return
	is_pounding = false
	velocity.y = vy

func _start_attack() -> void:
	if dead or is_dashing or blocking:
		return
	attacking = true
	attack_time_left = ATTACK_TIME
	attack_cooldown_left = ATTACK_COOLDOWN
	attack_hits.clear()
	attack_shape.set_deferred("disabled", true)
	knight_sprite.speed_scale = 1.0
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
		knight_sprite.animation = &"walk"
		knight_sprite.frame = 0
		knight_sprite.position.y = 0.0

func _begin_dash(dash_direction: int) -> void:
	facing = dash_direction
	blocking = false
	is_dashing = true
	dash_time_left = DASH_TIME
	dash_cooldown_left = DASH_COOLDOWN
	collision_mask = DASH_COLLISION_MASK
	AudioManager.play("stomp")

func _end_dash() -> void:
	is_dashing = false
	collision_mask = NORMAL_COLLISION_MASK

func block_hit(source_position: Vector2) -> bool:
	if dead or is_dashing:
		return is_dashing
	if not blocking or not _is_in_front(source_position):
		return false
	shield_guard.modulate = Color(1.7, 1.7, 1.7)
	get_tree().create_timer(0.08).timeout.connect(_reset_shield_flash)
	AudioManager.play("stomp")
	return true

func _reset_shield_flash() -> void:
	if is_instance_valid(shield_guard):
		shield_guard.modulate = Color.WHITE

func _is_in_front(source_position: Vector2) -> bool:
	return (source_position.x - global_position.x) * facing >= -4.0

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
	_end_dash()
	return true

func _die() -> void:
	if dead or is_dashing:
		return
	dead = true
	is_pounding = false
	_end_dash()
	blocking = false
	attacking = false
	attack_shape.set_deferred("disabled", true)
	wall_dir = 0
	_update_visuals()
	died.emit()

func reset_for_spawn() -> void:
	dead = false
	is_pounding = false
	attacking = false
	blocking = false
	_end_dash()
	velocity = Vector2.ZERO
	shield_guard.modulate = Color.WHITE
	attack_shape.set_deferred("disabled", true)
	_update_visuals()
