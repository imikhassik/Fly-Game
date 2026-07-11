extends CharacterBody2D

@export var speed: float = 60.0
@export var health: int = 1
@export var shoot_interval: float = 2.0
@export var rotation_speed: float = 4.0
@export var min_chase_distance: float = 30.0
@export var retreat_speed: float = 80.0
@export var projectile_scene: PackedScene = preload("res://scenes/enemy_projectile.tscn")
@export var shoot_sound: AudioStreamPlayer2D

var shoot_timer: float = 0.0
var is_retreating: bool = false
var retreat_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("enemy")
	shoot_timer = randf_range(0.0, shoot_interval)

func _physics_process(delta: float) -> void:
	var fly = get_tree().get_first_node_in_group("player")
	
	# If no fly, retreat
	if fly == null:
		_start_retreat()
		_apply_retreat(delta)
		return
	
	# Only chase if fly is flying or taking off
	if fly.state == fly.FlyState.FLYING or fly.state == fly.FlyState.TAKING_OFF:
		is_retreating = false
		_chase_fly(delta, fly)
	else:
		# Fly is landed, landing, or anything else -> retreat
		_start_retreat()
		_apply_retreat(delta)

func _chase_fly(delta: float, fly: Node) -> void:
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
		
		# Shooting
		shoot_timer += delta
		if shoot_timer >= shoot_interval:
			shoot_timer = 0.0
			shoot_at_fly(fly)

func _start_retreat() -> void:
	if not is_retreating:
		is_retreating = true
		if velocity.length() > 0:
			retreat_direction = velocity.normalized()
		else:
			retreat_direction = Vector2(0, 1)

func _apply_retreat(delta: float) -> void:
	if not is_retreating:
		return
	
	velocity = retreat_direction * retreat_speed
	move_and_slide()
	
	var screen_size = get_viewport().get_visible_rect().size
	var margin = 150
	if (global_position.x < -margin or global_position.x > screen_size.x + margin or
		global_position.y < -margin or global_position.y > screen_size.y + margin):
		queue_free()

func shoot_at_fly(fly: Node) -> void:
	if projectile_scene == null:
		return
	
	var projectile = projectile_scene.instantiate()
	
	var offset = Vector2(0, -20).rotated(rotation)
	projectile.global_position = global_position + offset
	
	var direction = (fly.global_position - global_position).normalized()
	projectile.direction = direction
	
	get_tree().current_scene.add_child(projectile)
	
	# Play shooting sound
	if shoot_sound:
		shoot_sound.play()

func take_damage() -> void:
	health -= 1
	if health <= 0:
		queue_free()
