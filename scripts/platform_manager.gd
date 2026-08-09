extends Node

@export var platform_scene: PackedScene = preload("res://scenes/platform.tscn")
@export var spawn_x_margin: float = 50.0
@export var platform_speed: float = 40.0
@export var starting_platform_path: NodePath

# ----- PLATFORM SCALING -----
@export var landed_scale: float = 1.0
@export var flying_scale: float = 0.5
@export var scale_speed: float = 0.5

@export var food_scene: PackedScene = preload("res://scenes/food.tscn")
@export var food_spawn_chance: float = 1.0   # 30% chance per platform

var spawn_interval: float = 20.0
var spawn_timer: float = 0.0
var is_moving: bool = false
var active_platforms: Array[Node] = []
var starting_platform: Node2D = null
var starting_platform_added: bool = false
var target_platform_scale: float = 1.0

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
			# ----- DELAY REPOSITIONING UNTIL WINDOW IS FULLY SIZED -----
			call_deferred("_reposition_starting_platform")
		else:
			push_warning("Starting platform not found at path: ", starting_platform_path)
	else:
		push_warning("starting_platform_path not set in PlatformManager!")
	
	spawn_interval = randf_range(15.0, 25.0)
	target_platform_scale = landed_scale
	if starting_platform:
		starting_platform.scale = Vector2(landed_scale, landed_scale)

func _reposition_starting_platform() -> void:
	if starting_platform:
		var screen_size = get_viewport().get_visible_rect().size
		var bottom_offset = 150
		starting_platform.global_position = Vector2(screen_size.x / 2, screen_size.y - bottom_offset)
		print("Starting platform repositioned to: ", starting_platform.global_position)

func _process(delta: float) -> void:
	var current_scale = Vector2(target_platform_scale, target_platform_scale)
	
	for platform in active_platforms:
		if is_instance_valid(platform):
			platform.scale = platform.scale.move_toward(current_scale, scale_speed * delta)

func _physics_process(delta: float) -> void:
	if not is_moving:
		return
	
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		spawn_platform()
		spawn_interval = randf_range(35.0, 50.0)
	
	for platform in active_platforms:
		if is_instance_valid(platform):
			platform.position.y += platform_speed * delta
			
			var screen_size = get_viewport().get_visible_rect().size
			if platform.position.y > screen_size.y + 200:
				active_platforms.erase(platform)
				platform.queue_free()

func spawn_platform() -> void:
	print("spawn_platform() called!")
	
	if platform_scene == null:
		push_warning("Platform scene not assigned in PlatformManager!")
		return
	
	var new_platform = platform_scene.instantiate()
	
	var screen_size = get_viewport().get_visible_rect().size
	var random_x = randf_range(spawn_x_margin, screen_size.x - spawn_x_margin)
	
	new_platform.position = Vector2(random_x, -250)
	new_platform.scale = Vector2(target_platform_scale, target_platform_scale)
	
	get_tree().current_scene.add_child(new_platform)
	active_platforms.append(new_platform)
	
	print("Platform spawned at: ", new_platform.position)
	
	# Spawn food on this platform
	if food_scene and randf() < food_spawn_chance:
		var food = food_scene.instantiate()
		food.position = Vector2(0, -20)   # local offset relative to platform (optional)
		food.buff_type = "shoot" if randf() < 0.5 else "speed"
		new_platform.add_child(food)      # make it a child of the platform
		print("Food spawned on platform at ", new_platform.position + food.position)

func _on_fly_landed() -> void:
	print("_on_fly_landed() called - pausing movement, scaling to 100%")
	is_moving = false
	target_platform_scale = landed_scale

func _on_fly_took_off() -> void:
	print("_on_fly_took_off() called - resuming movement, scaling to 50%")
	is_moving = true
	spawn_timer = 0.0
	target_platform_scale = flying_scale
	
	if starting_platform and not starting_platform_added:
		active_platforms.append(starting_platform)
		starting_platform_added = true
		print("Starting platform added to active list.")
