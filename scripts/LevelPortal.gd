extends Area2D

signal entered

@export var active := false

var pulse_time := 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var outer_ring: Line2D = $Visual/OuterRing
@onready var inner_ring: Line2D = $Visual/InnerRing
@onready var core: Polygon2D = $Visual/Core

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	set_active(active)

func _process(delta: float) -> void:
	if not active:
		return
	pulse_time += delta
	outer_ring.rotation += delta * 0.9
	inner_ring.rotation -= delta * 1.35
	var pulse := 1.0 + sin(pulse_time * 4.2) * 0.07
	$Visual.scale = Vector2.ONE * pulse
	core.modulate.a = 0.62 + sin(pulse_time * 5.0) * 0.18

func set_active(value: bool) -> void:
	active = value
	visible = value
	monitoring = value
	set_process(value)
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", not value)

func _on_body_entered(body: Node2D) -> void:
	if not active or not body.is_in_group("player"):
		return
	active = false
	monitoring = false
	collision_shape.set_deferred("disabled", true)
	entered.emit()
