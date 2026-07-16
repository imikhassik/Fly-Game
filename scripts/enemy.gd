extends CharacterBody2D

# ----- EXPORTS -----
@export var enemy_types: Array[EnemyType]   # <-- REPLACES textures

@export var rotation_speed: float = 4.0
@export var min_chase_distance: float = 30.0
@export var retreat_speed: float = 80.0
@export var projectile_scene: PackedScene = preload("res://scenes/enemy_projectile.tscn")
@export var shoot_sound: AudioStreamPlayer2D

# ----- SHOOTING (random interval) -----
# These will be overwritten by the chosen type, but keep them as fallback
@export var shoot_interval_min: float = 0.5
@export var shoot_interval_max: float = 2.0

# ----- INTERNAL STATE -----
var speed: float = 60.0
var health: int = 1
var shoot_timer: float = 0.0
var current_shoot_interval: float = 0.0
var is_retreating: bool = false
var retreat_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("enemy")
	z_index = 2
	
	# ----- PICK RANDOM ENEMY TYPE (skin + behavior) -----
	if enemy_types.size() > 0:
		var chosen_type = enemy_types[randi() % enemy_types.size()]
		$Sprite2D.texture = chosen_type.texture
		speed = chosen_type.speed
		health = chosen_type.health
		shoot_interval_min = chosen_type.shoot_interval_min
		shoot_interval_max = chosen_type.shoot_interval_max
		
		# Initialize shoot timer based on the new interval
		shoot_timer = randf_range(0.0, 1.0)
		current_shoot_interval = randf_range(shoot_interval_min, shoot_interval_max)
	else:
		# Fallback values (should not happen if you set up the Inspector)
		push_warning("No enemy_types assigned! Using default fallback stats.")
		shoot_timer = randf_range(0.0, 1.0)
		current_shoot_interval = randf_range(shoot_interval_min, shoot_interval_max)
	
	# ----- INITIAL BEHAVIOR (check if fly is landed) -----
	var fly = get_tree().get_first_node_in_group("player")
	if fly:
		if fly.state == fly.FlyState.LANDED or fly.state == fly.FlyState.LANDING:
			_start_glide_across_screen()
		else:
			is_retreating = false
			_enable_collision_with_fly()

func _physics_process(delta: float) -> void:
	var fly = get_tree().get_first_node_in_group("player")
	
	# Collision toggle
	if fly and (fly.state == fly.FlyState.FLYING or fly.state == fly.FlyState.TAKING_OFF) and not is_retreating:
		_enable_collision_with_fly()
	else:
		_disable_collision_with_fly()
	
	if fly == null:
		_start_retreat()
		_apply_retreat()
		return
	
	# Chase if flying or taking off
	if fly.state == fly.FlyState.FLYING or fly.state == fly.FlyState.TAKING_OFF:
		_chase_fly(delta, fly)
	else:
		_start_retreat()
		_apply_retreat()

# ----- COLLISION HELPERS -----
func _enable_collision_with_fly() -> void:
	collision_layer = 2
	collision_mask = 1

func _disable_collision_with_fly() -> void:
	collision_layer = 0
	collision_mask = 0

# ----- INITIAL GLIDE (when spawned while fly is landed) -----
func _start_glide_across_screen() -> void:
	var screen_center = get_viewport().get_visible_rect().size / 2
	var direction_to_center = (screen_center - global_position).normalized()
	
	rotation = direction_to_center.angle() + PI / 2
	retreat_direction = direction_to_center
	is_retreating = true
	_disable_collision_with_fly()

# ----- CHASE LOGIC -----
func _chase_fly(delta: float, fly: Node) -> void:
	if is_retreating:
		is_retreating = false
		_enable_collision_with_fly()
		retreat_direction = Vector2.ZERO
	
	var distance_to_fly = global_position.distance_to(fly.global_position)
	
	if distance_to_fly < min_chase_distance:
		velocity = Vector2.ZERO
	else:
		var direction_to_fly = (fly.global_position - global_position).normalized()
		
		var target_rotation = direction_to_fly.angle() + PI / 2
		var angle_diff = angle_difference(rotation, target_rotation)
		rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)
		
		velocity = direction_to_fly * speed
		move_and_slide()
		
		# SHOOTING (random interval)
		shoot_timer += delta
		if shoot_timer >= current_shoot_interval:
			shoot_timer = 0.0
			shoot_at_fly(fly)
			current_shoot_interval = randf_range(shoot_interval_min, shoot_interval_max)

# ----- RETREAT LOGIC -----
func _start_retreat() -> void:
	if not is_retreating:
		is_retreating = true
		if velocity.length() > 0:
			retreat_direction = velocity.normalized()
		else:
			retreat_direction = Vector2(0, 1)
		_disable_collision_with_fly()

func _apply_retreat() -> void:
	if not is_retreating:
		return
	
	_disable_collision_with_fly()
	
	velocity = retreat_direction * retreat_speed
	move_and_slide()
	
	var screen_size = get_viewport().get_visible_rect().size
	var margin = 150
	if (global_position.x < -margin or global_position.x > screen_size.x + margin or
		global_position.y < -margin or global_position.y > screen_size.y + margin):
		queue_free()

# ----- SHOOTING -----
func shoot_at_fly(fly: Node) -> void:
	if projectile_scene == null:
		return
	
	var projectile = projectile_scene.instantiate()
	
	var offset = Vector2(0, -20).rotated(rotation)
	projectile.global_position = global_position + offset
	
	var direction = (fly.global_position - global_position).normalized()
	projectile.direction = direction
	
	get_tree().current_scene.add_child(projectile)
	
	if shoot_sound:
		shoot_sound.play()

# ----- DAMAGE -----
func take_damage() -> void:
	health -= 1
	if health <= 0:
		queue_free()
