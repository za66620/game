extends Area2D

var velocity := Vector2.ZERO

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		return
	if body.is_in_group("enemies") and body.has_method("hit"):
		body.hit(1)
		queue_free()
		return
	if body is StaticBody2D:
		if body.has_method("shoot_hit"):
			body.shoot_hit()
		queue_free()
