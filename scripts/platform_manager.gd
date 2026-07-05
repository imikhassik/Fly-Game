extends Node

@export var platform_scene: PackedScene = preload("res://scenes/platform.tscn")
@export var spawn_x_margin: float = 50.0
@export var platform_speed: float = 40.0
@export var starting_platform_path: NodePath

var spawn_interval: float = 20.0
var spawn_timer: float = 0.0
var is_moving: bool = false
var active_platforms: Array[Node] = []
var starting_platform: Node2D = null
var starting_platform_added: bool = false

func _ready() -> void:
	print("PlatformManager _ready() called.")
	
	var fly = get_tree().get_first_node_in_group("player")
	print("Fly variable after lookup: ", fly)
	if fly:
		print("Fly found: ", fly.name)
		fly.landed.connect(_on_fly_landed)
		fly.took_off.connect(_on_fly_took_off)
		print("Signals connected.")
	else:
		push_warning("No 'player' group found! PlatformManager cannot connect to fly.")
	
	if starting_platform_path:
		starting_platform = get_node(starting_platform_path)
		if starting_platform:
			print("Starting platform found: ", starting_platform.name)
		else:
			push_warning("Starting platform not found at path: ", starting_platform_path)
	else:
		push_warning("starting_platform_path not set in PlatformManager!")
	
	# Initial spawn interval (first platform appears in this range)
	spawn_interval = randf_range(15.0, 25.0)

func _process(delta: float) -> void:
	if not is_moving:
		return
	
	# Spawning
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		spawn_platform()
		# Subsequent platforms spawn every 35–50 seconds
		spawn_interval = randf_range(35.0, 50.0)
	
	# Movement
	for platform in active_platforms:
		if is_instance_valid(platform):
			platform.position.y += platform_speed * delta
			
			var screen_size: Vector2 = get_viewport().get_visible_rect().size
			if platform.position.y > screen_size.y + 200:
				active_platforms.erase(platform)
				platform.queue_free()

func spawn_platform() -> void:
	print("spawn_platform() called!")
	
	if platform_scene == null:
		push_warning("Platform scene not assigned in PlatformManager!")
		return
	
	var new_platform = platform_scene.instantiate()
	
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var random_x = randf_range(spawn_x_margin, screen_size.x - spawn_x_margin)
	
	new_platform.position = Vector2(random_x, -250)
	
	get_tree().current_scene.add_child(new_platform)
	active_platforms.append(new_platform)
	
	print("Platform spawned at: ", new_platform.position)

func _on_fly_landed() -> void:
	print("_on_fly_landed() called - pausing movement")
	is_moving = false

func _on_fly_took_off() -> void:
	print("_on_fly_took_off() called - resuming movement")
	is_moving = true
	spawn_timer = 0.0
	
	if starting_platform and not starting_platform_added:
		active_platforms.append(starting_platform)
		starting_platform_added = true
		print("Starting platform added to active list.")
