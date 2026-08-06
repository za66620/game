extends Area2D

var velocity := Vector2.ZERO
var shooter: Node2D
var damage := 20

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter or body is Area2D:
		return
	if body.is_in_group("player"):
		if body.has_method("is_dodge_invulnerable") and body.is_dodge_invulnerable():
			return
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position, shooter)
		elif body.has_method("_die"):
			body._die()
		queue_free()
	else:
		queue_free()
