extends AnimatableBody2D

@export var offset := Vector2(0, 0)
@export var speed := 90.0

var origin: Vector2

func _ready() -> void:
	origin = global_position

func _physics_process(delta: float) -> void:
	var t := (sin(Time.get_ticks_msec() / 1000.0 * speed) + 1.0) / 2.0
	global_position = origin + offset * t
