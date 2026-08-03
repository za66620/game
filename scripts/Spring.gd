extends Area2D

@export var launch_velocity := -900.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("launch"):
		body.launch(launch_velocity)
		AudioManager.play("jump")
		_animate()

func _animate() -> void:
	var rect: ColorRect = $SpringColor
	var tween := create_tween()
	tween.tween_property(rect, "scale", Vector2(1.0, 0.4), 0.08)
	tween.tween_property(rect, "scale", Vector2(1.0, 1.0), 0.15)
