extends Control

func _ready() -> void:
	var window = get_window()
	
	# Center the window on the primary screen
	var screen_size = DisplayServer.screen_get_size()
	var window_size = window.size
	window.position = Vector2i(
		(screen_size.x - window_size.x) / 2,
		(screen_size.y - window_size.y) / 2
	)
	
	# Then maximize (OS will handle it from the centered position)
	window.mode = Window.MODE_MAXIMIZED
