extends Node

func _ready() -> void:
	_ensure_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_ensure_action("left", [KEY_A, KEY_LEFT])
	_ensure_action("right", [KEY_D, KEY_RIGHT])
	_ensure_action("dash", [KEY_SHIFT])
	_ensure_action("down", [KEY_S, KEY_DOWN])
	_ensure_action("shoot", [KEY_J])
	_ensure_action("restart", [KEY_R])

func _ensure_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
