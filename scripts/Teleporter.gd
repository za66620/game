extends Area2D

@export var pair_id := 0

func _ready() -> void:
	add_to_group("teleporters")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or not body.has_method("teleport_to"):
		return
	var target := _find_pair()
	if target:
		body.teleport_to(target.global_position + Vector2(0, -24))
		AudioManager.play("jump")

func _find_pair() -> Area2D:
	for node in get_tree().get_nodes_in_group("teleporters"):
		if node != self and node.pair_id == pair_id:
			return node
	return null
