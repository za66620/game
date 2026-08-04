extends CharacterBody2D

signal died
signal health_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)

const SPEED := 285.0
const JUMP_VELOCITY := -540.0
const WALL_SLIDE_SPEED := 70.0
const WALL_JUMP_VELOCITY_X := 400.0

const MAX_HEALTH := 100
const MAX_STAMINA := 100.0
const STAMINA_REGEN := 34.0
const STAMINA_REGEN_DELAY := 0.78

const ATTACK_DAMAGE := 24
const ATTACK_STAMINA := 24.0
const ATTACK_TIME := 0.44
const ATTACK_ACTIVE_FROM := 0.28
const ATTACK_ACTIVE_UNTIL := 0.1

const DASH_SPEED := 610.0
const DASH_TIME := 0.23
const DASH_COOLDOWN := 0.18
const DASH_STAMINA := 32.0
const NORMAL_COLLISION_MASK := 3
const DASH_COLLISION_MASK := 1

const PARRY_WINDOW := 0.17
const GUARD_STAMINA_MULTIPLIER := 1.35
const GUARD_BREAK_TIME := 0.72
const HURT_INVULN_TIME := 0.62

const POUND_VELOCITY := 1000.0
const POUND_BOUNCE := -300.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var health := MAX_HEALTH
var stamina := MAX_STAMINA
var dead := false
var facing := 1
var attacking := false
var is_dashing := false
var is_pounding := false
var blocking := false

var attack_time_left := 0.0
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var stamina_regen_delay_left := 0.0
var hurt_invuln_left := 0.0
var stagger_left := 0.0
var parry_left := 0.0
var wall_dir := 0
var teleport_lock := 0.0
var attack_hits: Dictionary = {}

@onready var knight_sprite: AnimatedSprite2D = $KnightSprite
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var contact_sensor: Area2D = $ContactSensor
@onready var shield_guard: Node2D = $ShieldGuard

func _ready() -> void:
	attack_hitbox.body_entered.connect(_on_attack_body_entered)
	knight_sprite.pause()
	health_changed.emit(health, MAX_HEALTH)
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_visuals()

func _physics_process(delta: float) -> void:
	if dead:
		return
	_update_timers(delta)
	_update_stamina(delta)
	_update_attack(delta)

	var direction := Input.get_axis("left", "right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1

	if stagger_left > 0.0:
		blocking = false
		velocity.x = move_toward(velocity.x, 0.0, SPEED * delta * 5.0)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		_update_visuals()
		return

	_update_block_state()

	if Input.is_action_just_pressed("attack"):
		_start_attack()

	if Input.is_action_just_pressed("down") and not is_on_floor() and not is_dashing and not is_pounding and not attacking:
		is_pounding = true
		velocity.y = POUND_VELOCITY

	var dash_combo_pressed := direction != 0.0 and Input.is_action_pressed("dash") and (
		Input.is_action_just_pressed("dash")
		or Input.is_action_just_pressed("left")
		or Input.is_action_just_pressed("right")
	)
	if dash_combo_pressed:
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

	if not is_on_floor() and not is_pounding:
		velocity.y += gravity * delta

	var jump_consumed := false
	wall_dir = 0
	if is_on_wall() and not is_on_floor() and not is_pounding and not attacking:
		wall_dir = signi(int(round(get_wall_normal().x)))
		if Input.is_action_just_pressed("jump"):
			velocity.x = wall_dir * WALL_JUMP_VELOCITY_X
			velocity.y = JUMP_VELOCITY * 0.9
			jump_consumed = true
			AudioManager.play("jump")
		elif Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	if not is_pounding and not jump_consumed and not blocking and not attacking and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		AudioManager.play("jump")

	if is_pounding:
		velocity.y = POUND_VELOCITY
	elif blocking:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
	elif attacking:
		velocity.x = direction * SPEED * 0.22
	else:
		velocity.x = direction * SPEED
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

	_check_hazards()
	_update_visuals()

func _update_timers(delta: float) -> void:
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	teleport_lock = maxf(0.0, teleport_lock - delta)
	hurt_invuln_left = maxf(0.0, hurt_invuln_left - delta)
	stagger_left = maxf(0.0, stagger_left - delta)
	parry_left = maxf(0.0, parry_left - delta)
	stamina_regen_delay_left = maxf(0.0, stamina_regen_delay_left - delta)

func _update_stamina(delta: float) -> void:
	if stamina_regen_delay_left > 0.0 or attacking or is_dashing or blocking or stagger_left > 0.0:
		return
	if stamina < MAX_STAMINA:
		stamina = minf(MAX_STAMINA, stamina + STAMINA_REGEN * delta)
		stamina_changed.emit(stamina, MAX_STAMINA)

func _spend_stamina(amount: float) -> bool:
	if stamina + 0.001 < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	stamina_regen_delay_left = STAMINA_REGEN_DELAY
	stamina_changed.emit(stamina, MAX_STAMINA)
	return true

func _update_block_state() -> void:
	var wants_block := Input.is_action_pressed("down") and is_on_floor() and not attacking and not is_dashing and stagger_left <= 0.0
	if wants_block and not blocking and stamina > 0.0:
		blocking = true
		parry_left = PARRY_WINDOW
	elif not wants_block:
		blocking = false

func _start_attack() -> void:
	if dead or attacking or is_dashing or blocking or stagger_left > 0.0:
		return
	if not _spend_stamina(ATTACK_STAMINA):
		return
	attacking = true
	attack_time_left = ATTACK_TIME
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
	if dead or is_dashing or attacking or blocking or is_pounding or stagger_left > 0.0 or dash_cooldown_left > 0.0:
		return
	if not _spend_stamina(DASH_STAMINA):
		return
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

func block_hit(source_position: Vector2, damage := 20, attacker: Node = null) -> bool:
	if dead or is_dashing:
		return is_dashing
	if not blocking or not _is_in_front(source_position):
		return false
	if parry_left > 0.0:
		stamina = minf(MAX_STAMINA, stamina + 12.0)
		stamina_changed.emit(stamina, MAX_STAMINA)
		if attacker and attacker.has_method("stagger"):
			attacker.stagger()
		_flash_shield(Color(1.8, 1.8, 0.7))
		AudioManager.play("stomp")
		return true
	var guard_cost := float(damage) * GUARD_STAMINA_MULTIPLIER
	if stamina >= guard_cost:
		_spend_stamina(guard_cost)
		_flash_shield(Color(1.5, 1.5, 1.8))
		return true
	stamina = 0.0
	stamina_changed.emit(stamina, MAX_STAMINA)
	blocking = false
	stagger_left = GUARD_BREAK_TIME
	_apply_damage(maxi(1, int(round(damage * 0.4))), source_position)
	return true

func take_damage(damage: int, source_position := Vector2.ZERO, attacker: Node = null) -> void:
	if dead or is_dashing or hurt_invuln_left > 0.0:
		return
	if block_hit(source_position, damage, attacker):
		return
	_apply_damage(damage, source_position)

func _apply_damage(damage: int, source_position: Vector2) -> void:
	if dead:
		return
	health = maxi(0, health - damage)
	hurt_invuln_left = HURT_INVULN_TIME
	stamina_regen_delay_left = STAMINA_REGEN_DELAY
	if source_position != Vector2.ZERO:
		var knock_dir := -1.0 if source_position.x > global_position.x else 1.0
		velocity = Vector2(knock_dir * 230.0, -190.0)
	health_changed.emit(health, MAX_HEALTH)
	modulate = Color(1.0, 0.45, 0.45)
	get_tree().create_timer(0.12).timeout.connect(_reset_hurt_flash)
	if health <= 0:
		_die()

func _reset_hurt_flash() -> void:
	if not dead:
		modulate = Color.WHITE

func _flash_shield(color: Color) -> void:
	shield_guard.modulate = color
	get_tree().create_timer(0.09).timeout.connect(_reset_shield_flash)

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
	body.hit(ATTACK_DAMAGE)

func _check_enemy_contacts() -> void:
	if is_dashing or dead:
		return
	for body in contact_sensor.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if attacking:
			_on_attack_body_entered(body)
			continue
		if velocity.y > 0.0 and global_position.y < body.global_position.y - 8.0:
			_stomp(body)
			return
		if block_hit(body.global_position, 24, body):
			continue
		take_damage(24, body.global_position, body)
		return

func _check_hazards() -> void:
	if is_dashing:
		return
	for i in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider is Node2D and collider.is_in_group("spikes"):
			_die()

func _pound_shockwave() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("pound") and global_position.distance_to(enemy.global_position) < 150.0:
			enemy.pound()

func _stomp(enemy: Node2D) -> void:
	velocity.y = JUMP_VELOCITY * 0.55
	AudioManager.play("stomp")
	if enemy.has_method("stomp"):
		enemy.stomp()

func _update_visuals() -> void:
	knight_sprite.flip_h = facing < 0
	attack_shape.position.x = facing * 42.0
	shield_guard.visible = blocking
	shield_guard.position.x = facing * 28.0
	shield_guard.scale = Vector2(0.8 * facing, 0.8)
	knight_sprite.position.y = 9.0 if attacking else 0.0
	knight_sprite.modulate = Color(0.62, 0.82, 1.0, 0.62) if is_dashing else Color.WHITE
	if dead:
		knight_sprite.animation = &"walk"
		knight_sprite.pause()
		knight_sprite.frame = 0
		return
	if attacking:
		if knight_sprite.animation != &"slash":
			knight_sprite.play(&"slash")
		return
	if knight_sprite.animation != &"walk":
		knight_sprite.animation = &"walk"
	if is_dashing:
		knight_sprite.play(&"walk")
		knight_sprite.speed_scale = 2.8
	elif blocking:
		knight_sprite.pause()
		knight_sprite.frame = 0
	elif stagger_left > 0.0:
		knight_sprite.pause()
		knight_sprite.frame = 3
	elif not is_on_floor():
		knight_sprite.pause()
		knight_sprite.frame = 2 if velocity.y < 0.0 else 3
	elif absf(velocity.x) > 1.0:
		knight_sprite.play(&"walk")
		knight_sprite.speed_scale = 1.0
	else:
		knight_sprite.pause()
		knight_sprite.frame = 0

func launch(vy: float) -> void:
	if dead:
		return
	is_pounding = false
	velocity.y = vy

func teleport_to(pos: Vector2) -> bool:
	if teleport_lock > 0.0 or dead:
		return false
	teleport_lock = 0.5
	global_position = pos
	velocity = Vector2.ZERO
	is_pounding = false
	_end_dash()
	return true

func heal_full() -> void:
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	health_changed.emit(health, MAX_HEALTH)
	stamina_changed.emit(stamina, MAX_STAMINA)

func _die() -> void:
	if dead or is_dashing:
		return
	dead = true
	health = 0
	health_changed.emit(health, MAX_HEALTH)
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
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	is_pounding = false
	attacking = false
	blocking = false
	stagger_left = 0.0
	hurt_invuln_left = 0.0
	parry_left = 0.0
	_end_dash()
	velocity = Vector2.ZERO
	modulate = Color.WHITE
	shield_guard.modulate = Color.WHITE
	attack_shape.set_deferred("disabled", true)
	health_changed.emit(health, MAX_HEALTH)
	stamina_changed.emit(stamina, MAX_STAMINA)
	_update_visuals()
