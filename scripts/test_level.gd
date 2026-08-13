extends Control

@onready var enemy_buzz = $EnemyBuzz

func _ready() -> void:
	var window = get_window()
	
	# Center the window on the primary screen
	var screen_size = DisplayServer.screen_get_size()
	var window_size = window.size
	window.position = Vector2i(
		(screen_size.x - window_size.x) / 2,
		(screen_size.y - window_size.y) / 2
	)
	if enemy_buzz:
		enemy_buzz.stop()
	
	# Then maximize (OS will handle it from the centered position)
	window.mode = Window.MODE_MAXIMIZED

func _process(delta: float) -> void:
	if not enemy_buzz:
		return
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	var has_enemy = enemies.size() > 0
	
	if has_enemy:
		if not enemy_buzz.playing:
			enemy_buzz.play()
	else:
		if enemy_buzz.playing:
			enemy_buzz.stop()
