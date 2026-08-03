extends StaticBody2D

func _ready() -> void:
	$Detector.body_entered.connect(_on_detector_entered)

func _on_detector_entered(body: Node2D) -> void:
	if body.is_in_group("player") and (body.is_pounding or body.is_dashing):
		_break()

func shoot_hit() -> void:
	_break()

func _break() -> void:
	AudioManager.play("stomp")
	var coin: Area2D = (load("res://scenes/Coin.tscn") as PackedScene).instantiate()
	coin.global_position = global_position
	var game: Node = get_tree().get_first_node_in_group("game")
	if game:
		coin.collected.connect(game._on_coin_collected)
	get_parent().add_child(coin)
	queue_free()
