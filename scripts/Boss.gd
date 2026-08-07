extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal defeated

enum State { CHASE, WINDUP, ATTACK, RECOVER, STAGGERED }
enum AttackKind { SLASH, LUNGE, SWEEP }

@export var boss_name := "腐化骑士"
@export_range(0, 2) var variant := 0
@export var max_health := 160
@export var move_speed := 85.0
@export var attack_damage := 30
@export var arena_half_width := 260.0

var health := 160
var state := State.CHASE
var current_attack := AttackKind.SLASH
var state_time := 0.0
var attack_cooldown := 0.8
var facing := -1
var dead := false
var origin_x := 0.0
var melee_hit_consumed := false
var perfect_dodge_consumed := false
var combo_index := 0
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var active_sprite: AnimatedSprite2D = null
var sprite_origin := Vector2.ZERO

@onready var player: Node2D = get_tree().get_first_node_in_group("player")
@onready var corrupted_sprite: AnimatedSprite2D = $CorruptedKnight
@onready var beast_sprite: AnimatedSprite2D = $BeastHunter
@onready var abyss_sprite: AnimatedSprite2D = $AbyssChampion
@onready var warning_arc: Polygon2D = $WarningArc
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_shape: CollisionShape2D = $MeleeHitbox/CollisionShape2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	health = max_health
	origin_x = global_position.x
	var sprites: Array[AnimatedSprite2D] = [corrupted_sprite, beast_sprite, abyss_sprite]
	for index in range(sprites.size()):
		sprites[index].visible = index == variant
	active_sprite = sprites[variant]
	sprite_origin = active_sprite.position
	active_sprite.play(&"walk")
	_configure_variant_collision()
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
			_play_walk()
			var distance_x := absf(to_player.x)
			if player and attack_cooldown <= 0.0 and absf(to_player.y) < 92.0 and distance_x <= _trigger_range():
				_start_windup(_select_attack(distance_x))
			else:
				_chase_player()
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 8.0)
			warning_arc.visible = true
			warning_arc.modulate.a = 0.58 + sin(Time.get_ticks_msec() * 0.028) * 0.24
			_set_pose(-7.0, -float(facing) * _windup_tilt())
			if state_time <= 0.0:
				_begin_attack()
		State.ATTACK:
			warning_arc.visible = false
			velocity.x = float(facing) * _attack_speed()
			_set_pose(10.0, float(facing) * _attack_tilt())
			if state_time <= 0.0:
				_finish_attack()
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 680.0 * delta)
			if active_sprite:
				active_sprite.position = active_sprite.position.lerp(sprite_origin, minf(1.0, delta * 12.0))
				active_sprite.rotation = lerpf(active_sprite.rotation, 0.0, minf(1.0, delta * 12.0))
			if state_time <= 0.0:
				_reset_pose()
				state = State.CHASE
				attack_cooldown = _attack_cooldown()
		State.STAGGERED:
			warning_arc.visible = false
			_set_melee_active(false)
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			_reset_pose()
			modulate = Color(1.35, 1.35, 1.35)
			if state_time <= 0.0:
				modulate = Color.WHITE
				state = State.CHASE
				attack_cooldown = 0.65

	move_and_slide()
	if state == State.ATTACK:
		_check_melee_hit()

func _configure_variant_collision() -> void:
	var body_sizes := [Vector2(42, 66), Vector2(46, 72), Vector2(52, 82)]
	var melee_sizes := [Vector2(92, 54), Vector2(112, 58), Vector2(136, 64)]
	var body_rect := body_shape.shape as RectangleShape2D
	var melee_rect := melee_shape.shape as RectangleShape2D
	body_rect.size = body_sizes[variant]
	melee_rect.size = melee_sizes[variant]
	body_shape.position.y = -4.0
	melee_shape.position.y = -5.0
	warning_arc.scale = [Vector2(0.9, 0.9), Vector2(1.05, 0.95), Vector2(1.22, 1.05)][variant]

func _select_attack(distance_x: float) -> AttackKind:
	combo_index += 1
	match variant:
		0:
			return AttackKind.LUNGE if distance_x > 92.0 else AttackKind.SLASH
		1:
			return AttackKind.LUNGE if combo_index % 2 == 0 else AttackKind.SLASH
		_:
			if health <= max_health / 2 and combo_index % 3 == 0:
				return AttackKind.LUNGE
			return AttackKind.SWEEP

func _trigger_range() -> float:
	return [128.0, 154.0, 174.0][variant]

func _windup_duration() -> float:
	match current_attack:
		AttackKind.SLASH:
			return [0.56, 0.38, 0.48][variant]
		AttackKind.LUNGE:
			return [0.64, 0.46, 0.54][variant]
		AttackKind.SWEEP:
			return 0.72 if health > max_health / 2 else 0.58
	return 0.5

func _active_duration() -> float:
	match current_attack:
		AttackKind.SLASH:
			return 0.15
		AttackKind.LUNGE:
			return 0.17
		AttackKind.SWEEP:
			return 0.2
	return 0.16

func _recovery_duration() -> float:
	match current_attack:
		AttackKind.SLASH:
			return [0.56, 0.42, 0.54][variant]
		AttackKind.LUNGE:
			return [0.68, 0.5, 0.62][variant]
		AttackKind.SWEEP:
			return 0.78 if health > max_health / 2 else 0.64
	return 0.55

func _attack_speed() -> float:
	match current_attack:
		AttackKind.SLASH:
			return [185.0, 265.0, 205.0][variant]
		AttackKind.LUNGE:
			return [300.0, 390.0, 340.0][variant]
		AttackKind.SWEEP:
			return 245.0
	return 220.0

func _attack_cooldown() -> float:
	var base := [1.0, 0.72, 0.88][variant]
	if variant == 2 and health <= max_health / 2:
		base -= 0.12
	return base

func _windup_tilt() -> float:
	return 0.12 if current_attack == AttackKind.SLASH else 0.18

func _attack_tilt() -> float:
	return 0.18 if current_attack != AttackKind.SWEEP else 0.24

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
	state_time = _windup_duration()
	warning_arc.color = [
		Color(0.92, 0.18, 0.08, 0.5),
		Color(0.72, 0.9, 0.18, 0.5),
		Color(0.62, 0.18, 0.95, 0.52),
	][variant]
	warning_arc.visible = true
	active_sprite.animation = &"attack"
	active_sprite.frame = 0
	active_sprite.pause()

func _begin_attack() -> void:
	state = State.ATTACK
	state_time = _active_duration()
	melee_hit_consumed = false
	perfect_dodge_consumed = false
	_set_melee_active(true)
	active_sprite.play(&"attack")
	active_sprite.speed_scale = [1.0, 1.25, 0.92][variant]
	GameFeel.shake(1.5 + float(variant), 0.08)

func _finish_attack() -> void:
	_set_melee_active(false)
	state = State.RECOVER
	state_time = _recovery_duration()
	active_sprite.pause()
	active_sprite.frame = 2

func _check_melee_hit() -> void:
	if melee_hit_consumed:
		return
	for body in melee_hitbox.get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		if body.has_method("is_dodge_invulnerable") and body.is_dodge_invulnerable():
			melee_hit_consumed = true
			if not perfect_dodge_consumed and body.has_method("perfect_dodge"):
				perfect_dodge_consumed = true
				body.perfect_dodge(self)
			return
		melee_hit_consumed = true
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, global_position, self)
		return

func _set_melee_active(value: bool) -> void:
	melee_shape.set_deferred("disabled", not value)

func _update_facing() -> void:
	corrupted_sprite.flip_h = facing > 0
	beast_sprite.flip_h = facing > 0
	abyss_sprite.flip_h = facing > 0
	warning_arc.scale.x = absf(warning_arc.scale.x) * float(facing)
	melee_hitbox.position.x = float(facing) * [52.0, 62.0, 72.0][variant]

func _play_walk() -> void:
	if active_sprite.animation != &"walk" or not active_sprite.is_playing():
		active_sprite.play(&"walk")
	active_sprite.speed_scale = [0.8, 1.15, 0.72][variant]

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
		velocity.x += direction.x * [62.0, 48.0, 35.0][variant]
	GameFeel.hitstop(0.048 if variant < 2 else 0.06)
	GameFeel.shake(2.5 + float(variant), 0.1)
	GameFeel.burst(global_position, Color(1.0, 0.35, 0.2), 11 + variant * 2)
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
	state_time = [1.0, 0.72, 0.6][variant]
	attack_cooldown = 0.8
	_set_melee_active(false)

func on_perfect_dodged() -> void:
	if dead or state != State.ATTACK:
		return
	_set_melee_active(false)
	state = State.RECOVER
	state_time = _recovery_duration() + 0.18
	velocity.x *= 0.2

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
	GameFeel.burst(global_position, Color(0.92, 0.22, 0.12), 24)
	defeated.emit()
	await get_tree().create_timer(0.22, true, false, true).timeout
	queue_free()

func _flash() -> void:
	modulate = Color(1.7, 0.68, 0.62)
	await get_tree().create_timer(0.1, true, false, true).timeout
	if not dead and state != State.STAGGERED:
		modulate = Color.WHITE
