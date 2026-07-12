extends Control

func _ready() -> void:
	# Center the window
	var window = get_window()
	window.position = Vector2i(
		(DisplayServer.screen_get_size().x - window.size.x) / 2,
		(DisplayServer.screen_get_size().y - window.size.y) / 2
	)
