extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal defeated

enum State { CHASE, WINDUP, ATTACK, RECOVER, STAGGERED }
enum AttackKind { MELEE, PROJECTILE }

const MELEE_TRIGGER_RANGE := 138.0
const MELEE_HIT_TIME := 0.2

@export var boss_name := "守门者"
@export_range(0, 2) var variant := 0
@export var max_health := 160
@export var move_speed := 85.0
@export var attack_damage := 30
@export var arena_half_width := 260.0

var health := 160
var state := State.CHASE
var current_attack := AttackKind.MELEE
var state_time := 0.0
var attack_cooldown := 1.0
var facing := -1
var dead := false
var origin_x := 0.0
var melee_hit_consumed := false
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var active_sprite: Node2D = null
var sprite_origin := Vector2.ZERO

@onready var player: Node2D = get_tree().get_first_node_in_group("player")
@onready var snail_sprite: Sprite2D = $SnailSprite
@onready var warden_sprite: AnimatedSprite2D = $WardenSprite
@onready var dragon_sprite: Sprite2D = $DragonSprite
@onready var warning_arc: Polygon2D = $WarningArc
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_shape: CollisionShape2D = $MeleeHitbox/CollisionShape2D

func _ready() -> void:
	health = max_health
	origin_x = global_position.x
	snail_sprite.visible = variant == 0
	warden_sprite.visible = variant == 1
	dragon_sprite.visible = variant == 2
	active_sprite = [snail_sprite, warden_sprite, dragon_sprite][variant]
	sprite_origin = active_sprite.position
	if variant == 1:
		warden_sprite.play(&"walk")
	_set_melee_active(false)
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	state_time = maxf(0.0, state_time - delta)
	if not is_on_floor():
		velocity.y += gravity * delta

	var to_player := Vector2.ZERO
	if player and not player.dead:
		to_player = player.global_position - global_position
		if absf(to_player.x) > 4.0:
			facing = 1 if to_player.x > 0.0 else -1
	_update_facing()

	match state:
		State.CHASE:
			warning_arc.visible = false
			_set_melee_active(false)
			_reset_pose()
			var distance_x := absf(to_player.x)
			if player and attack_cooldown <= 0.0 and absf(to_player.y) < 95.0:
				if distance_x <= MELEE_TRIGGER_RANGE:
					_start_windup(AttackKind.MELEE)
				elif variant != 1 and distance_x <= 430.0:
					_start_windup(AttackKind.PROJECTILE)
				else:
					_chase_player()
			else:
				_chase_player()
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 7.0)
			warning_arc.visible = true
			warning_arc.modulate.a = 0.55 + sin(Time.get_ticks_msec() * 0.025) * 0.25
			if current_attack == AttackKind.MELEE:
				_set_pose(-9.0, -float(facing) * 0.16)
			else:
				_set_pose(-4.0, -float(facing) * 0.07)
			if state_time <= 0.0:
				_begin_attack()
		State.ATTACK:
			warning_arc.visible = false
			if current_attack == AttackKind.MELEE:
				velocity.x = float(facing) * [245.0, 335.0, 285.0][variant]
				_set_pose(13.0, float(facing) * 0.2)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
				_reset_pose()
			if state_time <= 0.0:
				_set_melee_active(false)
				state = State.RECOVER
				state_time = [0.58, 0.5, 0.66][variant]
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 620.0 * delta)
			if active_sprite:
				active_sprite.position = active_sprite.position.lerp(sprite_origin, minf(1.0, delta * 12.0))
				active_sprite.rotation = lerpf(active_sprite.rotation, 0.0, minf(1.0, delta * 12.0))
			if state_time <= 0.0:
				_reset_pose()
				state = State.CHASE
				attack_cooldown = [1.15, 0.82, 1.0][variant]
		State.STAGGERED:
			warning_arc.visible = false
			_set_melee_active(false)
			velocity.x = 0.0
			_reset_pose()
			modulate = Color(1.35, 1.35, 1.35)
			if state_time <= 0.0:
				modulate = Color.WHITE
				state = State.CHASE
				attack_cooldown = 0.65

	move_and_slide()
	if state == State.ATTACK and current_attack == AttackKind.MELEE:
		_check_melee_hit()

func _chase_player() -> void:
	if not player or player.dead:
		velocity.x = 0.0
		return
	var desired_velocity := float(facing) * move_speed
	if global_position.x <= origin_x - arena_half_width and desired_velocity < 0.0:
		desired_velocity = move_speed
	elif global_position.x >= origin_x + arena_half_width and desired_velocity > 0.0:
		desired_velocity = -move_speed
	velocity.x = desired_velocity

func _start_windup(kind: AttackKind) -> void:
	current_attack = kind
	state = State.WINDUP
	if kind == AttackKind.MELEE:
		state_time = [0.58, 0.46, 0.62][variant]
		warning_arc.color = Color(0.95, 0.1, 0.07, 0.52)
	else:
		state_time = [0.78, 0.7, 0.86][variant]
		warning_arc.color = Color(1.0, 0.5, 0.08, 0.5)
	warning_arc.visible = true

func _begin_attack() -> void:
	state = State.ATTACK
	if current_attack == AttackKind.MELEE:
		state_time = MELEE_HIT_TIME
		melee_hit_consumed = false
		_set_melee_active(true)
	else:
		state_time = 0.18
		_spawn_projectile(270.0 if variant == 0 else 390.0)

func _check_melee_hit() -> void:
	if melee_hit_consumed:
		return
	for body in melee_hitbox.get_overlapping_bodies():
		if body.is_in_group("player"):
			melee_hit_consumed = true
			if body.has_method("take_damage"):
				body.take_damage(attack_damage, global_position, self)
			return

func _set_melee_active(value: bool) -> void:
	melee_shape.set_deferred("disabled", not value)

func _spawn_projectile(projectile_speed: float) -> void:
	if not player or player.dead:
		return
	var bullet := (load("res://scenes/Bullet.tscn") as PackedScene).instantiate() as Area2D
	bullet.velocity = Vector2(facing * projectile_speed, 0.0)
	bullet.shooter = self
	bullet.damage = attack_damage
	bullet.global_position = global_position + Vector2(facing * 50.0, -14.0)
	get_tree().current_scene.add_child(bullet)

func _update_facing() -> void:
	snail_sprite.flip_h = facing > 0
	warden_sprite.flip_h = facing > 0
	dragon_sprite.flip_h = facing > 0
	warning_arc.scale.x = facing
	melee_hitbox.position.x = float(facing) * 55.0

func _set_pose(forward_offset: float, angle: float) -> void:
	if active_sprite:
		active_sprite.position = sprite_origin + Vector2(float(facing) * forward_offset, 0.0)
		active_sprite.rotation = angle

func _reset_pose() -> void:
	if active_sprite:
		active_sprite.position = sprite_origin
		active_sprite.rotation = 0.0

func hit(damage: int, direction := Vector2.ZERO) -> void:
	if dead:
		return
	health = maxi(0, health - damage)
	health_changed.emit(health, max_health)
	if direction != Vector2.ZERO:
		velocity.x += direction.x * 70.0
	GameFeel.hitstop(0.055)
	GameFeel.burst(global_position, Color(1.0, 0.35, 0.2), 10)
	_flash()
	if health <= 0:
		_die()

func stomp() -> void:
	hit(12)

func pound() -> void:
	hit(24)

func stagger() -> void:
	if dead:
		return
	state = State.STAGGERED
	state_time = 1.05
	attack_cooldown = 0.8
	_set_melee_active(false)

func _die() -> void:
	dead = true
	state = State.STAGGERED
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	warning_arc.visible = false
	_set_melee_active(false)
	GameFeel.hitstop(0.12)
	GameFeel.slow_mo(0.35, 0.42)
	GameFeel.shake(8.0, 0.35)
	GameFeel.burst(global_position, Color(0.92, 0.22, 0.12), 22)
	defeated.emit()
	await get_tree().create_timer(0.22, true, false, true).timeout
	queue_free()

func _flash() -> void:
	modulate = Color(1.7, 0.68, 0.62)
	await get_tree().create_timer(0.1, true, false, true).timeout
	if not dead and state != State.STAGGERED:
		modulate = Color.WHITE
