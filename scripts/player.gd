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
@export var landing_scale_speed: float = 0.25
@export var take_off_scale_speed: float = 0.25
@export var takeoff_forward_speed: float = 150.0
@export var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")
@export var shoot_sound: AudioStreamPlayer2D
@export var flying_sound: AudioStreamPlayer2D
@export var max_health: int = 3
@export var invincibility_duration: float = 1.0

# ----- SHOOT COOLDOWN -----
@export var shoot_cooldown: float = 1.5

# ----- BOUNDARY PUSH (velocity‑based) -----
@export var boundary_margin: float = 100.0
@export var boundary_push_strength: float = 400.0

# ----- DEFORMATION (stretch & squash) -----
@export var min_fps: float = 8.0
@export var max_fps: float = 48.0
@export var stretch_amount: float = 0.13
@export var squash_amount: float = 0.10

# ----- LEG TRANSITION -----
@export var leg_transition_duration: float = 0.3
@export var turn_animation_speed: float = 1.0

var health: int
var invincible: bool = false

var fly_visuals_base_scale: Vector2 = Vector2.ONE
var vertical_velocity: float = 0.0
var respawn_position: Vector2 = Vector2.ZERO
var shoot_timer: float = 0.0

var boundary_push: Vector2 = Vector2.ZERO
var current_deformation: float = 0.0
var is_fully_scaled: bool = false
var facing_direction: int = 1

func _ready() -> void:
	fly_visuals_base_scale = $FlyVisuals.scale
	print("FlyVisuals base scale: ", fly_visuals_base_scale)
	
	$FlyVisuals.scale = fly_visuals_base_scale * landing_scale_target
	z_index = 1
	add_to_group("player")

	health = max_health

	collision_layer = 1
	collision_mask = 3

	$LandingDetector.collision_layer = 1
	$LandingDetector.collision_mask = 2

	$HeadDetector.collision_layer = 1
	$HeadDetector.collision_mask = 2

	if flying_sound:
		flying_sound.stop()

	$FlyVisuals/Sprite2D.visible = true
	$FlyVisuals/Body_Wings.visible = false

	$FlyVisuals/Legs/NeutralLegs.visible = true
	$FlyVisuals/Legs/WalkingLegs.visible = false
	$FlyVisuals/Legs/FlyingLegs.visible = false
	$FlyVisuals/Legs/WalkingLegs.stop()

	call_deferred("_set_initial_position")

func _set_initial_position() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var bottom_offset = 150
	respawn_position = Vector2(screen_size.x / 2, screen_size.y - bottom_offset)
	global_position = respawn_position
	print("Fly repositioned to: ", global_position)

func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1.0

	var controller_vector := Vector2.ZERO
	var raw_stick := Vector2.ZERO
	var deadzone := 0.2
	var stick_x = Input.get_axis("controller_move_left", "controller_move_right")
	var stick_y = Input.get_axis("controller_move_up", "controller_move_down")
	var stick_vec = Vector2(stick_x, stick_y)

	var using_controller := false
	if stick_vec.length() > deadzone:
		raw_stick = stick_vec
		controller_vector = stick_vec.normalized()
		using_controller = true

	if using_controller:
		input_vector = controller_vector

	var screen_size = get_viewport().get_visible_rect().size
	var push := Vector2.ZERO
	var margin = boundary_margin
	var max_push = boundary_push_strength

	if global_position.x < margin:
		var factor = 1.0 - (global_position.x / margin)
		push.x = max_push * factor
	elif global_position.x > screen_size.x - margin:
		var factor = (global_position.x - (screen_size.x - margin)) / margin
		push.x = -max_push * factor

	if global_position.y < margin:
		var factor = 1.0 - (global_position.y / margin)
		push.y = max_push * factor
	elif global_position.y > screen_size.y - margin:
		var factor = (global_position.y - (screen_size.y - margin)) / margin
		push.y = -max_push * factor

	boundary_push = push

	if shoot_timer > 0:
		shoot_timer -= delta

	if Input.is_action_just_pressed("shoot") and state == FlyState.FLYING and shoot_timer <= 0:
		shoot()
		shoot_timer = shoot_cooldown

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
			flying_update(input_vector, delta, using_controller, raw_stick)
		FlyState.TAKING_OFF:
			takeoff_update(delta)
		FlyState.LANDING:
			landing_update(delta)
		FlyState.LANDED:
			landed_update(input_vector, delta, using_controller)

	# ----- SCALING + VISIBILITY -----
	match state:
		FlyState.TAKING_OFF:
			if not $FlyVisuals/Body_Wings.visible:
				$FlyVisuals/Body_Wings.visible = true
				$FlyVisuals/Sprite2D.visible = false
				$FlyVisuals/Body_Wings.play("flying")
			$FlyVisuals.scale = $FlyVisuals.scale.move_toward(fly_visuals_base_scale, take_off_scale_speed * delta)
			is_fully_scaled = false
			current_deformation = 0.0
			if $FlyVisuals.scale.distance_to(fly_visuals_base_scale) < 0.001:
				$FlyVisuals.scale = fly_visuals_base_scale
				state = FlyState.FLYING
				is_fully_scaled = true
				print("Take off complete!")
		FlyState.LANDING:
			is_fully_scaled = false
			current_deformation = 0.0
			var target_scale = fly_visuals_base_scale * landing_scale_target
			if $FlyVisuals/Body_Wings.visible:
				$FlyVisuals.scale = $FlyVisuals.scale.move_toward(target_scale, landing_scale_speed * delta)
			print("LANDING: scale = ", $FlyVisuals.scale)
		FlyState.LANDED:
			print("LANDED branch reached!")
			if not $FlyVisuals/Sprite2D.visible:
				$FlyVisuals/Sprite2D.visible = true
				$FlyVisuals/Body_Wings.visible = false
				$FlyVisuals/Body_Wings.stop()
				print("Switched to Sprite2D, stopped Body_Wings")
			$FlyVisuals.scale = fly_visuals_base_scale * landing_scale_target
			is_fully_scaled = false
			current_deformation = 0.0
			facing_direction = 1
			print("LANDED: scale reset to ", $FlyVisuals.scale, " is_fully_scaled=", is_fully_scaled)
		FlyState.FLYING:
			if not $FlyVisuals/Body_Wings.visible:
				$FlyVisuals/Body_Wings.visible = true
				$FlyVisuals/Sprite2D.visible = false
				$FlyVisuals/Body_Wings.play("flying")
			if not is_fully_scaled:
				$FlyVisuals.scale = $FlyVisuals.scale.move_toward(fly_visuals_base_scale, take_off_scale_speed * delta)
				if $FlyVisuals.scale.distance_to(fly_visuals_base_scale) < 0.001:
					$FlyVisuals.scale = fly_visuals_base_scale
					is_fully_scaled = true
				current_deformation = 0.0
		_:
			pass

	# ----- ANIMATION SPEED (wings) -----
	if state == FlyState.FLYING or state == FlyState.TAKING_OFF:
		var current_speed = velocity.length()
		var min_speed = 0.0
		var max_speed = forward_speed + up_boost
		var t = clamp((current_speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)
		var target_fps = lerp(min_fps, max_fps, t)
		$FlyVisuals/Body_Wings.speed_scale = target_fps / $FlyVisuals/Body_Wings.sprite_frames.get_animation_speed("flying")

	# ----- DEFORMATION (only in FLYING and fully scaled) -----
	if state == FlyState.FLYING and is_fully_scaled:
		print("DEFORMATION running in FLYING")
		var current_speed = velocity.length()
		var min_speed = 0.0
		var max_speed = forward_speed + up_boost
		var target_deformation = clamp((current_speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)
		current_deformation = move_toward(current_deformation, target_deformation, 2.0 * delta)

		var stretch_factor = 1.0 + current_deformation * stretch_amount
		var squash_factor = 1.0 - current_deformation * squash_amount

		$FlyVisuals.scale = Vector2(
			fly_visuals_base_scale.x * squash_factor * facing_direction,
			fly_visuals_base_scale.y * stretch_factor
		)

# ----- FLYING STATE -----
func flying_update(input_vector: Vector2, delta: float, using_controller: bool, raw_stick: Vector2) -> void:
	var fly_speed: float
	var move_dir: Vector2
	var viewport_size: Vector2

	if using_controller:
		var target_rotation = input_vector.angle() + PI / 2
		var angle_diff = angle_difference(rotation, target_rotation)
		rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)

		var stick_magnitude = clamp(raw_stick.length(), 0.0, 1.0)
		fly_speed = forward_speed + up_boost * stick_magnitude

		move_dir = Vector2(0, -1).rotated(rotation)
		velocity = move_dir * fly_speed
		velocity += boundary_push
		move_and_slide()
		viewport_size = get_viewport().get_visible_rect().size
		position.x = clamp(position.x, 0.0, viewport_size.x)
		position.y = clamp(position.y, 0.0, viewport_size.y)
		
		if input_vector.x != 0:
			facing_direction = 1 if input_vector.x >= 0 else -1
		return

	if abs(input_vector.x) > 0.01:
		rotation += input_vector.x * rotation_speed * delta

	fly_speed = forward_speed
	if input_vector.y < 0:
		fly_speed += up_boost

	move_dir = Vector2(0, -1).rotated(rotation)
	velocity = move_dir * fly_speed
	velocity += boundary_push
	move_and_slide()

	viewport_size = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, viewport_size.x)
	position.y = clamp(position.y, 0.0, viewport_size.y)

	if input_vector.x != 0:
		facing_direction = 1 if input_vector.x >= 0 else -1

# ----- TAKEOFF STATE (forward only) -----
func takeoff_update(delta: float) -> void:
	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * takeoff_forward_speed
	velocity += boundary_push
	move_and_slide()

# ----- LANDED (WALKING) STATE -----
func landed_update(input_vector: Vector2, delta: float, using_controller: bool) -> void:
	var move_dir: Vector2
	var viewport_size: Vector2

	if using_controller:
		var target_rotation = input_vector.angle() + PI / 2
		var angle_diff = angle_difference(rotation, target_rotation)
		rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)
		if _is_head_on_platform():
			move_dir = Vector2(0, -1).rotated(rotation)
			velocity = move_dir * walk_speed
		else:
			velocity = Vector2.ZERO
		velocity += boundary_push
		move_and_slide()
		viewport_size = get_viewport().get_visible_rect().size
		position.x = clamp(position.x, 0.0, viewport_size.x)
		position.y = clamp(position.y, 0.0, viewport_size.y)
		
		if input_vector.x != 0:
			facing_direction = 1 if input_vector.x >= 0 else -1
		
		# ----- LEG ANIMATION (controller) -----
		var should_walk = (input_vector.length() > 0.1) and _is_head_on_platform()
		if should_walk:
			if not $FlyVisuals/Legs/WalkingLegs.visible:
				$FlyVisuals/Legs/NeutralLegs.visible = false
				$FlyVisuals/Legs/WalkingLegs.visible = true
				$FlyVisuals/Legs/FlyingLegs.visible = false
				$FlyVisuals/Legs/WalkingLegs.modulate.a = 1.0
			$FlyVisuals/Legs/WalkingLegs.play("walk")
			if input_vector.y < 0:
				var current_speed = velocity.length()
				var max_speed = walk_speed
				var t = clamp(current_speed / max_speed, 0.0, 1.0)
				var target_fps = lerp(6.0, 24.0, t)
				$FlyVisuals/Legs/WalkingLegs.speed_scale = target_fps / $FlyVisuals/Legs/WalkingLegs.sprite_frames.get_animation_speed("walk")
			else:
				# Turning in place or moving down (no forward movement)
				$FlyVisuals/Legs/WalkingLegs.speed_scale = turn_animation_speed
		else:
			if $FlyVisuals/Legs/WalkingLegs.visible:
				$FlyVisuals/Legs/WalkingLegs.stop()
				$FlyVisuals/Legs/WalkingLegs.visible = false
				$FlyVisuals/Legs/NeutralLegs.visible = true
				$FlyVisuals/Legs/NeutralLegs.modulate.a = 1.0
		return

	# ----- KEYBOARD -----
	if abs(input_vector.x) > 0.01:
		rotation += input_vector.x * rotation_speed * delta

	if input_vector.y < 0:
		if _is_head_on_platform():
			move_dir = Vector2(0, -1).rotated(rotation)
			velocity = move_dir * walk_speed
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO

	velocity += boundary_push
	move_and_slide()

	viewport_size = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, viewport_size.x)
	position.y = clamp(position.y, 0.0, viewport_size.y)

	if input_vector.x != 0:
		facing_direction = 1 if input_vector.x >= 0 else -1

	# ----- LEG ANIMATION (keyboard) -----
	var should_walk = (input_vector.length() > 0.1) and _is_head_on_platform()
	if should_walk:
		if not $FlyVisuals/Legs/WalkingLegs.visible:
			$FlyVisuals/Legs/NeutralLegs.visible = false
			$FlyVisuals/Legs/WalkingLegs.visible = true
			$FlyVisuals/Legs/FlyingLegs.visible = false
			$FlyVisuals/Legs/WalkingLegs.modulate.a = 1.0
		$FlyVisuals/Legs/WalkingLegs.play("walk")
		if input_vector.y < 0:
			var current_speed = velocity.length()
			var max_speed = walk_speed
			var t = clamp(current_speed / max_speed, 0.0, 1.0)
			var target_fps = lerp(6.0, 24.0, t)
			$FlyVisuals/Legs/WalkingLegs.speed_scale = target_fps / $FlyVisuals/Legs/WalkingLegs.sprite_frames.get_animation_speed("walk")
		else:
			# Turning in place (keyboard A/D)
			$FlyVisuals/Legs/WalkingLegs.speed_scale = turn_animation_speed
	else:
		if $FlyVisuals/Legs/WalkingLegs.visible:
			$FlyVisuals/Legs/WalkingLegs.stop()
			$FlyVisuals/Legs/WalkingLegs.visible = false
			$FlyVisuals/Legs/NeutralLegs.visible = true
			$FlyVisuals/Legs/NeutralLegs.modulate.a = 1.0
			
# ----- LANDING STATE -----
func landing_update(delta: float) -> void:
	vertical_velocity = move_toward(vertical_velocity, 0.0, landing_deceleration * delta)
	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * vertical_velocity
	velocity += boundary_push
	move_and_slide()

	if abs(vertical_velocity) < 1.0:
		if $FlyVisuals.scale.distance_to(fly_visuals_base_scale * landing_scale_target) < 0.001:
			state = FlyState.LANDED
			velocity = Vector2.ZERO
			print("Landed!")

# ----- TRANSITION TRIGGERS -----
func start_landing() -> void:
	state = FlyState.LANDING
	vertical_velocity = velocity.length()
	landed.emit()
	_vibrate(1.0, 0.2)
	if flying_sound and flying_sound.playing:
		flying_sound.stop()
	
	$FlyVisuals.scale = fly_visuals_base_scale
	is_fully_scaled = false
	current_deformation = 0.0
	
	$FlyVisuals/Sprite2D.visible = false
	$FlyVisuals/Body_Wings.visible = true
	$FlyVisuals/Body_Wings.play("flying")
	
	# ----- LEG TRANSITION (Fly -> Neutral) -----
	# Kill any existing tween to avoid conflicts
	var tween = get_tree().create_tween()
	tween.kill()
	
	# Set initial states
	$FlyVisuals/Legs/FlyingLegs.visible = true
	$FlyVisuals/Legs/NeutralLegs.visible = true
	$FlyVisuals/Legs/WalkingLegs.visible = false
	$FlyVisuals/Legs/FlyingLegs.modulate.a = 1.0
	$FlyVisuals/Legs/NeutralLegs.modulate.a = 0.0
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property($FlyVisuals/Legs/FlyingLegs, "modulate:a", 0.0, leg_transition_duration)
	tween.tween_property($FlyVisuals/Legs/NeutralLegs, "modulate:a", 1.0, leg_transition_duration)
	
	print("Landing started...")

func start_take_off() -> void:
	state = FlyState.TAKING_OFF
	took_off.emit()
	_vibrate(0.8, 0.3)
	if flying_sound and not flying_sound.playing:
		flying_sound.play()
	
	$FlyVisuals/Sprite2D.visible = false
	$FlyVisuals/Body_Wings.visible = true
	$FlyVisuals/Body_Wings.play("flying")
	
	# ----- LEG TRANSITION (Neutral/Walk -> Fly) -----
	var tween = get_tree().create_tween()
	tween.kill()
	
	# Determine which legs are currently visible
	var current_legs = $FlyVisuals/Legs/WalkingLegs if $FlyVisuals/Legs/WalkingLegs.visible else $FlyVisuals/Legs/NeutralLegs
	$FlyVisuals/Legs/FlyingLegs.visible = true
	$FlyVisuals/Legs/FlyingLegs.modulate.a = 0.0
	current_legs.modulate.a = 1.0
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(current_legs, "modulate:a", 0.0, leg_transition_duration)
	tween.tween_property($FlyVisuals/Legs/FlyingLegs, "modulate:a", 1.0, leg_transition_duration)
	
	print("Taking off...")

# ----- HELPER FUNCTIONS -----
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

func _is_head_on_platform() -> bool:
	var overlapping = $HeadDetector.get_overlapping_areas()
	for area in overlapping:
		if area.collision_layer & 2:
			return true
	return false

func _vibrate(duration: float = 0.3, intensity: float = 0.7) -> void:
	var joypads = Input.get_connected_joypads()
	for device in joypads:
		Input.start_joy_vibration(device, intensity, intensity, duration)

func shoot() -> void:
	if projectile_scene == null:
		print("No projectile scene assigned!")
		return

	_vibrate(0.1, 0.03)

	var projectile = projectile_scene.instantiate()
	var offset: Vector2 = Vector2(0, -25).rotated(rotation)
	projectile.global_position = global_position + offset
	projectile.direction = Vector2(0, -1).rotated(rotation)

	get_tree().current_scene.add_child(projectile)

	if shoot_sound:
		shoot_sound.play()

func take_damage() -> void:
	if invincible:
		return
	_vibrate(0.5, 0.3)
	health -= 1
	print("Fly took damage! Health: ", health)
	if health <= 0:
		respawn()
	else:
		_start_invincibility()

func _start_invincibility() -> void:
	invincible = true
	$FlyVisuals.modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(invincibility_duration).timeout
	$FlyVisuals.modulate = Color.WHITE
	invincible = false

func respawn() -> void:
	global_position = respawn_position
	health = max_health
	velocity = Vector2.ZERO
	state = FlyState.FLYING
	$FlyVisuals.scale = fly_visuals_base_scale
	is_fully_scaled = true
	facing_direction = 1
	invincible = false
	$FlyVisuals.modulate = Color.WHITE
	$FlyVisuals/Sprite2D.visible = false
	$FlyVisuals/Body_Wings.visible = true
	$FlyVisuals/Body_Wings.play("flying")
	
	# Legs: set flying legs visible with full alpha
	$FlyVisuals/Legs/NeutralLegs.visible = false
	$FlyVisuals/Legs/WalkingLegs.visible = false
	$FlyVisuals/Legs/FlyingLegs.visible = true
	$FlyVisuals/Legs/WalkingLegs.stop()
	$FlyVisuals/Legs/FlyingLegs.modulate.a = 1.0
	print("Fly respawned (FLYING).")
