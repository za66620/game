extends Node

const HIT_BURST := preload("res://scenes/HitBurst.tscn")

var _hitstop_until := 0
var _slowmo_until := 0
var _slowmo_factor := 1.0

var _shake_left := 0.0
var _shake_duration := 0.0
var _shake_intensity := 0.0
var _camera: Camera2D = null

var _flash_left := 0.0
var _flash_total := 0.0
var _flash_rect: ColorRect = null

var _fade_alpha := 0.0
var _fade_target := 0.0
var _fade_speed := 0.0
var _fade_active := false

var _last_msec := 0

func _ready() -> void:
	_last_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_delta := float(now - _last_msec) / 1000.0
	_last_msec = now

	if _hitstop_until > 0 and now >= _hitstop_until:
		_hitstop_until = 0
		_apply_time_scale()
	if _slowmo_until > 0 and now >= _slowmo_until:
		_slowmo_until = 0
		_slowmo_factor = 1.0
		_apply_time_scale()

	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - real_delta)
		if _camera == null or not is_instance_valid(_camera):
			_camera = get_tree().get_first_node_in_group("camera") as Camera2D
		if _camera:
			var decay := _shake_left / _shake_duration if _shake_duration > 0.0 else 0.0
			_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_intensity * decay
	elif _camera and is_instance_valid(_camera):
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		_shake_intensity = 0.0
		_shake_duration = 0.0

	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - real_delta)
		if _flash_rect == null or not is_instance_valid(_flash_rect):
			_flash_rect = get_tree().get_first_node_in_group("hit_flash") as ColorRect
		if _flash_rect:
			_flash_rect.color.a = 0.42 * (_flash_left / _flash_total) if _flash_total > 0.0 else 0.0

	if _fade_active:
		_fade_alpha = move_toward(_fade_alpha, _fade_target, _fade_speed * real_delta)
		if _flash_rect == null or not is_instance_valid(_flash_rect):
			_flash_rect = get_tree().get_first_node_in_group("hit_flash") as ColorRect
		if _flash_rect:
			_flash_rect.color = Color(0, 0, 0, _fade_alpha)
		if absf(_fade_alpha - _fade_target) < 0.001:
			_fade_active = false

func fade_out(duration := 0.3) -> void:
	_fade_target = 1.0
	_fade_speed = 1.0 / duration
	_fade_active = true

func fade_in(duration := 0.4) -> void:
	_fade_target = 0.0
	_fade_speed = 1.0 / duration
	_fade_active = true

func hitstop(duration: float) -> void:
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	_hitstop_until = maxi(_hitstop_until, until)
	_apply_time_scale()

func slow_mo(factor: float, duration: float) -> void:
	_slowmo_until = Time.get_ticks_msec() + int(duration * 1000.0)
	_slowmo_factor = factor
	_apply_time_scale()

func _apply_time_scale() -> void:
	var now := Time.get_ticks_msec()
	if _hitstop_until > now:
		Engine.time_scale = 0.0
	elif _slowmo_until > now:
		Engine.time_scale = _slowmo_factor
	else:
		Engine.time_scale = 1.0

func shake(intensity: float, duration: float) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_duration = duration
	_shake_left = duration

func burst(pos: Vector2, color: Color, count := 12) -> void:
	var particles := HIT_BURST.instantiate() as CPUParticles2D
	particles.global_position = pos
	particles.amount = count
	particles.color = color
	particles.emitting = true
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(particles)
	else:
		add_child(particles)
	var free_timer := get_tree().create_timer(1.2, true, false, true)
	free_timer.timeout.connect(particles.queue_free)

func flash_red() -> void:
	_flash_total = 0.35
	_flash_left = _flash_total
	if _flash_rect == null or not is_instance_valid(_flash_rect):
		_flash_rect = get_tree().get_first_node_in_group("hit_flash") as ColorRect
	if _flash_rect:
		_flash_rect.color = Color(0.9, 0.05, 0.05, 0.42)

func ghost_trail(pos: Vector2, color: Color, size := Vector2(40, 50)) -> void:
	var ghost := ColorRect.new()
	ghost.size = size
	ghost.position = pos - size * 0.5
	ghost.color = color
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(ghost)
	else:
		add_child(ghost)
	var fade := get_tree().create_tween()
	fade.tween_property(ghost, "modulate:a", 0.0, 0.14)
	fade.tween_callback(ghost.queue_free)
