extends CharacterBody2D

signal landed
signal took_off

enum FlyState { FLYING, LANDING, LANDED, TAKING_OFF }
var state: FlyState = FlyState.LANDED

@export var rotation_speed: float = 3.0
@export var walk_speed: float = 150.0
@export var forward_speed: float = 60.0
@export var up_boost: float = 160.0
@export var landing_deceleration: float = 200.0
@export var landing_scale_target: float = 0.75
@export var landing_scale_speed: float = 0.03
@export var take_off_scale_speed: float = 0.03
@export var takeoff_forward_speed: float = 150.0

var original_scale: Vector2 = Vector2.ONE
var vertical_velocity: float = 0.0

func _ready() -> void:
	original_scale = $Sprite2D.scale
	$Sprite2D.scale = original_scale * landing_scale_target
	$Sprite2D.rotation = 0.0
	z_index = 1
	add_to_group("player")
	
	# ----- COLLISION LAYERS -----
	collision_layer = 1
	collision_mask = 1
	
	$LandingDetector.collision_layer = 1
	$LandingDetector.collision_mask = 2
	
	$HeadDetector.collision_layer = 1
	$HeadDetector.collision_mask = 2

func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1.0

	if Input.is_action_just_pressed("land"):
		match state:
			FlyState.FLYING:
				if _is_fully_on_platform():
					start_landing()
				else:
					print("Cannot land - not fully on a platform!")
			FlyState.LANDED:
				start_take_off()
			_:
				pass

	match state:
		FlyState.FLYING:
			flying_update(input_vector, delta)
		FlyState.LANDING:
			landing_update(delta)
		FlyState.LANDED:
			landed_update(input_vector, delta)
		FlyState.TAKING_OFF:
			take_off_update(delta)

# ----- FLYING STATE -----
func flying_update(input_vector: Vector2, delta: float) -> void:
	if abs(input_vector.x) > 0.01:
		rotation += input_vector.x * rotation_speed * delta

	var speed = forward_speed
	if input_vector.y < 0:
		speed += up_boost

	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * speed
	move_and_slide()

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, screen_size.x)
	position.y = clamp(position.y, 0.0, screen_size.y)

	$Sprite2D.rotation = 0.0

# ----- LANDED (WALKING) STATE -----
func landed_update(input_vector: Vector2, delta: float) -> void:
	if abs(input_vector.x) > 0.01:
		rotation += input_vector.x * rotation_speed * delta

	if input_vector.y < 0:  # W – forward
		if _is_head_on_platform():
			var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
			velocity = forward_dir * walk_speed
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, screen_size.x)
	position.y = clamp(position.y, 0.0, screen_size.y)

	$Sprite2D.rotation = 0.0

# ----- LANDING STATE -----
func landing_update(delta: float) -> void:
	vertical_velocity = move_toward(vertical_velocity, 0.0, landing_deceleration * delta)
	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * vertical_velocity
	move_and_slide()

	if abs(vertical_velocity) < 1.0:
		if $Sprite2D.scale.distance_to(original_scale * landing_scale_target) < 0.001:
			state = FlyState.LANDED
			velocity = Vector2.ZERO
			print("Landed!")

# ----- TAKING OFF STATE -----
func take_off_update(_delta: float) -> void:
	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * takeoff_forward_speed
	move_and_slide()

	if $Sprite2D.scale.distance_to(original_scale) < 0.01:
		state = FlyState.FLYING
		velocity = Vector2.ZERO
		print("Take off complete!")

# ----- TRANSITION TRIGGERS -----
func start_landing() -> void:
	state = FlyState.LANDING
	vertical_velocity = velocity.length()
	landed.emit()
	print("Landing started...")

func start_take_off() -> void:
	state = FlyState.TAKING_OFF
	took_off.emit()
	print("Taking off...")

# ----- HELPER FUNCTIONS FOR PLATFORM GEOMETRY -----
func _get_platform_polygon_global(area: Area2D) -> PackedVector2Array:
	var platform_collision = area.get_node("CollisionPolygon2D")
	if not platform_collision:
		return PackedVector2Array()

	var polygon = platform_collision.polygon
	if polygon.is_empty():
		return PackedVector2Array()

	var platform_pos = area.global_position
	var platform_scale = area.scale
	var platform_rotation = area.rotation

	var global_polygon: PackedVector2Array = []
	for point in polygon:
		var transformed = point * platform_scale
		transformed = transformed.rotated(platform_rotation)
		global_polygon.append(platform_pos + transformed)

	return global_polygon

func _get_detector_corners() -> Array[Vector2]:
	var detector_shape = $LandingDetector.get_node("CollisionShape2D")
	var detector_pos = $LandingDetector.global_position
	var detector_size = detector_shape.shape.size * $LandingDetector.scale

	return [
		detector_pos + Vector2(-detector_size.x/2, -detector_size.y/2),
		detector_pos + Vector2( detector_size.x/2, -detector_size.y/2),
		detector_pos + Vector2( detector_size.x/2,  detector_size.y/2),
		detector_pos + Vector2(-detector_size.x/2,  detector_size.y/2)
	]

# ----- LANDING DETECTION (FULL OVERLAP) -----
func _is_fully_on_platform() -> bool:
	var corners = _get_detector_corners()
	var areas = $LandingDetector.get_overlapping_areas()
	for area in areas:
		if area.collision_layer & 2:
			var poly = _get_platform_polygon_global(area)
			if poly.is_empty():
				continue
			var all_inside = true
			for corner in corners:
				if not Geometry2D.is_point_in_polygon(corner, poly):
					all_inside = false
					break
			if all_inside:
				return true
	return false

# ----- HEAD DETECTION (FOR WALKING) -----
func _is_head_on_platform() -> bool:
	var overlapping = $HeadDetector.get_overlapping_areas()
	for area in overlapping:
		if area.collision_layer & 2:
			return true
	return false

# ----- SCALE TRANSITIONS -----
func _process(delta: float) -> void:
	if state == FlyState.LANDING:
		var target = original_scale * landing_scale_target
		$Sprite2D.scale = $Sprite2D.scale.move_toward(target, landing_scale_speed * delta)
	elif state == FlyState.TAKING_OFF:
		var target = original_scale
		$Sprite2D.scale = $Sprite2D.scale.move_toward(target, take_off_scale_speed * delta)
