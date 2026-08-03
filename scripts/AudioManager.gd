extends Node

const SOUNDS := {
	"jump": preload("res://sounds/jump.wav"),
	"coin": preload("res://sounds/coin.wav"),
	"stomp": preload("res://sounds/stomp.wav"),
	"death": preload("res://sounds/death.wav"),
	"win": preload("res://sounds/win.wav"),
}

var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for key in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.stream = SOUNDS[key]
		add_child(player)
		_players.append(player)

func play(sound: String) -> void:
	if not SOUNDS.has(sound):
		return
	for player in _players:
		if player.stream == SOUNDS[sound]:
			player.stop()
			player.play()
			return
