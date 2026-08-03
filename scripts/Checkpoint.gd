extends Area2D

signal activated(position: Vector2)

var active := false

func _ready() -> void:
	add_to_group("checkpoints")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if active:
		return
	if body.is_in_group("player"):
		active = true
		$CheckpointColor.color = Color(0.2, 0.9, 0.3)
		activated.emit(global_position + Vector2(0, -30))
