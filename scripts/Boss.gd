extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal defeated

enum State { CHASE, WINDUP, ATTACK, RECOVER, STAGGERED }

@export var boss_name := "守门者"
@export_range(0, 2) var variant := 0
@export var max_health := 160
@export var move_speed := 85.0
@export var attack_damage := 30
@export var arena_half_width := 260.0

var health := 160
var state := State.CHASE
var state_time := 0.0
var attack_cooldown := 1.0
var facing := -1
var dead := false
var origin_x := 0.0
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var player: Node2D = get_tree().get_first_node_in_group("player")
@onready var snail_sprite: Sprite2D = $SnailSprite
@onready var warden_sprite: AnimatedSprite2D = $WardenSprite
@onready var dragon_sprite: Sprite2D = $DragonSprite
@onready var warning_arc: Polygon2D = $WarningArc

func _ready() -> void:
	health = max_health
	origin_x = global_position.x
	snail_sprite.visible = variant == 0
	warden_sprite.visible = variant == 1
	dragon_sprite.visible = variant == 2
	if variant == 1:
		warden_sprite.play(&"walk")
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
			var attack_range := 105.0 if variant == 1 else 420.0
			if player and attack_cooldown <= 0.0 and absf(to_player.x) <= attack_range and absf(to_player.y) < 90.0:
				_start_windup()
			else:
				velocity.x = facing * move_speed
				if global_position.x <= origin_x - arena_half_width:
					facing = 1
				elif global_position.x >= origin_x + arena_half_width:
					facing = -1
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 0.2)
			warning_arc.visible = true
			warning_arc.modulate.a = 0.35 + sin(Time.get_ticks_msec() * 0.025) * 0.25
			if state_time <= 0.0:
				_perform_attack()
				state = State.ATTACK
				state_time = 0.2
		State.ATTACK:
			warning_arc.visible = false
			if variant == 1:
				velocity.x = facing * 360.0
			else:
				velocity.x = move_toward(velocity.x, 0.0, 80.0)
			if state_time <= 0.0:
				state = State.RECOVER
				state_time = 0.65 if variant == 2 else 0.5
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 100.0)
			if state_time <= 0.0:
				state = State.CHASE
				attack_cooldown = [1.25, 0.85, 1.05][variant]
		State.STAGGERED:
			warning_arc.visible = false
			velocity.x = 0.0
			modulate = Color(1.4, 1.4, 1.4)
			if state_time <= 0.0:
				modulate = Color.WHITE
				state = State.CHASE
				attack_cooldown = 0.6

	move_and_slide()

func _start_windup() -> void:
	state = State.WINDUP
	state_time = [0.62, 0.42, 0.75][variant]
	warning_arc.visible = true

func _perform_attack() -> void:
	if not player or player.dead:
		return
	if variant == 1:
		if absf(player.global_position.x - global_position.x) < 125.0 and absf(player.global_position.y - global_position.y) < 80.0:
			player.take_damage(attack_damage, global_position, self)
	else:
		_spawn_projectile(270.0 if variant == 0 else 390.0)
		if absf(player.global_position.x - global_position.x) < 85.0:
			player.take_damage(attack_damage, global_position, self)

func _spawn_projectile(projectile_speed: float) -> void:
	var bullet := (load("res://scenes/Bullet.tscn") as PackedScene).instantiate() as Area2D
	bullet.velocity = Vector2(facing * projectile_speed, 0.0)
	bullet.shooter = self
	bullet.damage = attack_damage
	bullet.global_position = global_position + Vector2(facing * 58.0, -16.0)
	get_tree().current_scene.add_child(bullet)

func _update_facing() -> void:
	snail_sprite.flip_h = facing > 0
	warden_sprite.flip_h = facing > 0
	dragon_sprite.flip_h = facing > 0
	warning_arc.scale.x = facing

func hit(damage: int) -> void:
	if dead:
		return
	health = maxi(0, health - damage)
	health_changed.emit(health, max_health)
	_flash()
	if health <= 0:
		dead = true
		warning_arc.visible = false
		defeated.emit()
		queue_free()

func stomp() -> void:
	hit(12)

func pound() -> void:
	hit(24)

func stagger() -> void:
	if dead:
		return
	state = State.STAGGERED
	state_time = 1.15
	attack_cooldown = 0.8

func _flash() -> void:
	modulate = Color(1.7, 0.75, 0.75)
	await get_tree().create_timer(0.1).timeout
	if not dead and state != State.STAGGERED:
		modulate = Color.WHITE
