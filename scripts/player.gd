extends CharacterBody2D

signal landed
signal took_off

enum FlyState { FLYING, LANDING, LANDED, TAKING_OFF }
var state: FlyState = FlyState.LANDED

# ============================================================
#  CORE MOVEMENT STATS
# ============================================================
@export var rotation_speed: float = 3.0
@export var walk_speed: float = 150.0
@export var idle_speed: float = 60.0
@export var speed_boost: float = 160.0
@export var max_speed_boost: float = 1000.0
@export var permanent_speed_increment: float = 1.0
@export var landing_deceleration: float = 200.0
@export var landing_scale_target: float = 0.75
@export var landing_scale_speed: float = 0.25
@export var take_off_scale_speed: float = 0.25
@export var takeoff_forward_speed: float = 150.0

# ============================================================
#  DEFORMATION (Visual)
# ============================================================
@export var min_fps: float = 8.0
@export var max_fps: float = 48.0
@export var stretch_amount: float = 0.13
@export var squash_amount: float = 0.10
@export var boost_deformation_multiplier: float = 1.5

# ============================================================
#  LEG TRANSITION
# ============================================================
@export var leg_transition_duration: float = 0.3
@export var turn_animation_speed: float = 1.0

# ============================================================
#  COMBAT STATS
# ============================================================
@export var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")
@export var shoot_sound: AudioStreamPlayer2D
@export var shoot_cooldown: float = 1.5
@export var shoot_cooldown_decrement: float = 0.01

# ============================================================
#  HEALTH & HEARTS
# ============================================================
@export var max_health: int = 3
@export var invincibility_duration: float = 1.0
@export var max_heart_capacity: int = 6
@export var hearts_container: HBoxContainer = null
@export var initial_heart_amount_increment: float = 0.025
@export var total_heart_amount_increment: float = 0.025

# ============================================================
#  BUFFS
# ============================================================
@export var speed_boost_multiplier: float = 2.0
@export var speed_boost_duration: float = 25.0
@export var shoot_boost_cooldown: float = 0.2
@export var shoot_boost_duration: float = 25.0

# ============================================================
#  UI & AUDIO
# ============================================================
@export var buff_label: Label = null
@export var flying_sound: AudioStreamPlayer2D

# ============================================================
#  BOUNDARY PUSH
# ============================================================
@export var boundary_margin: float = 100.0
@export var boundary_push_strength: float = 400.0

# ============================================================
#  INTERNAL STATE (Non-exported)
# ============================================================
var speed_boost_active: bool = false
var shoot_boost_active: bool = false
var speed_boost_timer: float = 0.0
var shoot_boost_timer: float = 0.0

var original_idle_speed: float
var original_walk_speed: float
var original_shoot_cooldown: float

var health: int
var initial_max_health: int
var initial_max_heart_capacity: int
var initial_heart_progress: float = 0.0
var total_heart_progress: float = 0.0
var invincible: bool = false
var heart_full: Texture = preload("res://assets/fly/lives/heart_full.PNG")
var heart_broken: Texture = preload("res://assets/fly/lives/heart_broken.PNG")

var fly_visuals_base_scale: Vector2 = Vector2.ONE
var vertical_velocity: float = 0.0
var respawn_position: Vector2 = Vector2.ZERO
var shoot_timer: float = 0.0

var boundary_push: Vector2 = Vector2.ZERO
var current_deformation: float = 0.0
var is_fully_scaled: bool = false
var facing_direction: int = 1

var is_mating: bool = false
var mating_timer: float = 0.0
var mating_duration: float = 3.0
var female_partner: Node = null

# ============================================================
#  _ready()
# ============================================================
func _ready() -> void:
	if buff_label:
		var viewport_size = get_viewport().get_visible_rect().size
		buff_label.position = Vector2(viewport_size.x - buff_label.size.x - 50, 50)
		buff_label.visible = false

	fly_visuals_base_scale = $FlyVisuals.scale
	print("FlyVisuals base scale: ", fly_visuals_base_scale)

	$FlyVisuals.scale = fly_visuals_base_scale * landing_scale_target
	z_index = 1
	add_to_group("player")

	initial_max_health = max_health
	initial_max_heart_capacity = max_heart_capacity
	health = max_health

	collision_layer = 1
	collision_mask = 7

	$LandingDetector.collision_layer = 1
	$LandingDetector.collision_mask = 2

	$HeadDetector.collision_layer = 1
	$HeadDetector.collision_mask = 6
	$HeadDetector.add_to_group("head_detector")

	if flying_sound:
		flying_sound.stop()

	$FlyVisuals/Sprite2D.visible = true
	$FlyVisuals/Body_Wings.visible = false

	$FlyVisuals/Legs/NeutralLegs.visible = true
	$FlyVisuals/Legs/WalkingLegs.visible = false
	$FlyVisuals/Legs/FlyingLegs.visible = false
	$FlyVisuals/Legs/WalkingLegs.stop()

	original_idle_speed = idle_speed
	original_walk_speed = walk_speed
	original_shoot_cooldown = shoot_cooldown

	call_deferred("_set_initial_position")

	$RearDetector.area_entered.connect(_on_rear_detector_area_entered)
	$RearDetector.area_exited.connect(_on_rear_detector_area_exited)

	update_hearts()

# ============================================================
#  POSITION INIT
# ============================================================
func _set_initial_position() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var bottom_offset = 150
	respawn_position = Vector2(screen_size.x / 2, screen_size.y - bottom_offset)
	global_position = respawn_position
	print("Fly repositioned to: ", global_position)

# ============================================================
#  _physics_process()
# ============================================================
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

	# Boundary push (unchanged)
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

	# Shoot cooldown
	if shoot_timer > 0:
		shoot_timer -= delta

	if Input.is_action_just_pressed("shoot") and state == FlyState.FLYING and shoot_timer <= 0:
		shoot()
		shoot_timer = shoot_cooldown

	# Land / Take off
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

	# ----- MATING INPUT -----
	if Input.is_action_just_pressed("interact"):
		if state == FlyState.LANDED and not is_mating:
			if female_partner and female_partner.has_method("start_mating"):
				start_mating()

	# State updates
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
		FlyState.LANDED:
			if not is_mating:
				if not $FlyVisuals/Sprite2D.visible:
					$FlyVisuals/Sprite2D.visible = true
					$FlyVisuals/Body_Wings.visible = false
					$FlyVisuals/Body_Wings.stop()
			else:
				# Keep wings flapping during mating
				$FlyVisuals/Sprite2D.visible = false
				if not $FlyVisuals/Body_Wings.visible:
					$FlyVisuals/Body_Wings.visible = true
					$FlyVisuals/Body_Wings.play("flying")
			
			$FlyVisuals.scale = fly_visuals_base_scale * landing_scale_target
			is_fully_scaled = false
			current_deformation = 0.0
			facing_direction = 1
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
		var max_speed = idle_speed + speed_boost
		var t = clamp((current_speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)
		var target_fps = lerp(min_fps, max_fps, t)
		$FlyVisuals/Body_Wings.speed_scale = target_fps / $FlyVisuals/Body_Wings.sprite_frames.get_animation_speed("flying")

	# ----- DEFORMATION (only in FLYING and fully scaled) -----
	if state == FlyState.FLYING and is_fully_scaled:
		var current_speed = velocity.length()
		var min_speed = 0.0
		var max_speed = idle_speed + speed_boost
		var target_deformation = clamp((current_speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)
		current_deformation = move_toward(current_deformation, target_deformation, 2.0 * delta)

		# Apply extra multiplier when boosted
		var multiplier = boost_deformation_multiplier if speed_boost_active else 1.0

		var stretch_factor = 1.0 + current_deformation * stretch_amount * multiplier
		var squash_factor = 1.0 - current_deformation * squash_amount * multiplier

		$FlyVisuals.scale = Vector2(
			fly_visuals_base_scale.x * squash_factor * facing_direction,
			fly_visuals_base_scale.y * stretch_factor
		)

	# ----- BUFF TIMERS -----
	var any_buff_active = false
	var label_text = ""

	if speed_boost_active:
		speed_boost_timer -= delta
		any_buff_active = true
		label_text += "%.0f\n" % speed_boost_timer
		if speed_boost_timer <= 0:
			speed_boost_active = false
			idle_speed = original_idle_speed
			walk_speed = original_walk_speed
			print("Speed boost expired.")

	if shoot_boost_active:
		shoot_boost_timer -= delta
		any_buff_active = true
		label_text += "%.0f" % shoot_boost_timer
		if shoot_boost_timer <= 0:
			shoot_boost_active = false
			shoot_cooldown = original_shoot_cooldown
			print("Shoot boost expired.")

	if buff_label:
		if any_buff_active:
			buff_label.text = label_text
			buff_label.visible = true
		else:
			buff_label.visible = false

	if is_mating:
		mating_timer -= delta
		if mating_timer <= 0:
			finish_mating()

# ============================================================
#  FLYING STATE
# ============================================================
func flying_update(input_vector: Vector2, delta: float, using_controller: bool, raw_stick: Vector2) -> void:
	var fly_speed: float
	var move_dir: Vector2
	var viewport_size: Vector2

	if using_controller:
		var target_rotation = input_vector.angle() + PI / 2
		var angle_diff = angle_difference(rotation, target_rotation)
		rotation += clamp(angle_diff, -rotation_speed * delta, rotation_speed * delta)

		var stick_magnitude = clamp(raw_stick.length(), 0.0, 1.0)
		fly_speed = idle_speed + speed_boost * stick_magnitude

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

	fly_speed = idle_speed
	if input_vector.y < 0:
		fly_speed += speed_boost

	move_dir = Vector2(0, -1).rotated(rotation)
	velocity = move_dir * fly_speed
	velocity += boundary_push
	move_and_slide()

	viewport_size = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, viewport_size.x)
	position.y = clamp(position.y, 0.0, viewport_size.y)

	if input_vector.x != 0:
		facing_direction = 1 if input_vector.x >= 0 else -1

# ============================================================
#  TAKEOFF STATE
# ============================================================
func takeoff_update(_delta: float) -> void:
	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * takeoff_forward_speed
	velocity += boundary_push
	move_and_slide()

# ============================================================
#  LANDED (WALKING) STATE
# ============================================================
func landed_update(input_vector: Vector2, delta: float, using_controller: bool) -> void:
	if is_mating:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var move_dir: Vector2
	var viewport_size: Vector2
	var should_walk: bool

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
		should_walk = (input_vector.length() > 0) and _is_head_on_platform()
		if should_walk:
			if not $FlyVisuals/Legs/WalkingLegs.visible:
				$FlyVisuals/Legs/NeutralLegs.visible = false
				$FlyVisuals/Legs/WalkingLegs.visible = true
				$FlyVisuals/Legs/FlyingLegs.visible = false
				$FlyVisuals/Legs/WalkingLegs.modulate.a = 1.0
			$FlyVisuals/Legs/WalkingLegs.play("walk")
			var base_fps = $FlyVisuals/Legs/WalkingLegs.sprite_frames.get_animation_speed("walk")
			if input_vector.y < 0:
				var current_speed = velocity.length()
				var max_speed = walk_speed
				var t = clamp(current_speed / max_speed, 0.0, 1.0)
				var target_fps = lerp(6.0, 24.0, t)
				$FlyVisuals/Legs/WalkingLegs.speed_scale = target_fps / base_fps
			else:
				var target_fps = 24.0
				$FlyVisuals/Legs/WalkingLegs.speed_scale = target_fps / base_fps
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
	should_walk = (input_vector.length() > 0) and _is_head_on_platform()
	if should_walk:
		if not $FlyVisuals/Legs/WalkingLegs.visible:
			$FlyVisuals/Legs/NeutralLegs.visible = false
			$FlyVisuals/Legs/WalkingLegs.visible = true
			$FlyVisuals/Legs/FlyingLegs.visible = false
			$FlyVisuals/Legs/WalkingLegs.modulate.a = 1.0
		$FlyVisuals/Legs/WalkingLegs.play("walk")
		var base_fps = $FlyVisuals/Legs/WalkingLegs.sprite_frames.get_animation_speed("walk")
		if input_vector.y < 0:
			var current_speed = velocity.length()
			var max_speed = walk_speed
			var t = clamp(current_speed / max_speed, 0.0, 1.0)
			var target_fps = lerp(6.0, 24.0, t)
			$FlyVisuals/Legs/WalkingLegs.speed_scale = target_fps / base_fps
		else:
			var target_fps = 24.0
			$FlyVisuals/Legs/WalkingLegs.speed_scale = target_fps / base_fps
	else:
		if $FlyVisuals/Legs/WalkingLegs.visible:
			$FlyVisuals/Legs/WalkingLegs.stop()
			$FlyVisuals/Legs/WalkingLegs.visible = false
			$FlyVisuals/Legs/NeutralLegs.visible = true
			$FlyVisuals/Legs/NeutralLegs.modulate.a = 1.0

# ============================================================
#  LANDING STATE
# ============================================================
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

# ============================================================
#  TRANSITION TRIGGERS
# ============================================================
func start_landing() -> void:
	state = FlyState.LANDING
	var max_landing_speed = original_idle_speed * 1.2
	vertical_velocity = min(velocity.length(), max_landing_speed)
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

	var tween = get_tree().create_tween()
	tween.kill()

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

	var tween = get_tree().create_tween()
	tween.kill()

	var current_legs = $FlyVisuals/Legs/WalkingLegs if $FlyVisuals/Legs/WalkingLegs.visible else $FlyVisuals/Legs/NeutralLegs
	$FlyVisuals/Legs/FlyingLegs.visible = true
	$FlyVisuals/Legs/FlyingLegs.modulate.a = 0.0
	current_legs.modulate.a = 1.0

	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(current_legs, "modulate:a", 0.0, leg_transition_duration)
	tween.tween_property($FlyVisuals/Legs/FlyingLegs, "modulate:a", 1.0, leg_transition_duration)

	print("Taking off...")

# ============================================================
#  HELPER FUNCTIONS
# ============================================================
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

	update_hearts()

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
	max_health = initial_max_health
	max_heart_capacity = initial_max_heart_capacity
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

	$FlyVisuals/Legs/NeutralLegs.visible = false
	$FlyVisuals/Legs/WalkingLegs.visible = false
	$FlyVisuals/Legs/FlyingLegs.visible = true
	$FlyVisuals/Legs/WalkingLegs.stop()
	$FlyVisuals/Legs/FlyingLegs.modulate.a = 1.0

	update_hearts()

	print("Fly respawned (FLYING).")

func apply_speed_boost() -> void:
	speed_boost_active = true
	speed_boost_timer = speed_boost_duration
	idle_speed = original_idle_speed * speed_boost_multiplier
	walk_speed = original_walk_speed * speed_boost_multiplier
	print("Speed boost applied!")

func apply_shoot_boost() -> void:
	shoot_boost_active = true
	shoot_boost_timer = shoot_boost_duration
	shoot_cooldown = shoot_boost_cooldown
	print("Shoot boost applied!")
	
func apply_permanent_speed_increment() -> void:
	if speed_boost >= max_speed_boost:
		print("Maximum speed reached.")
		return
	
	speed_boost += permanent_speed_increment
	idle_speed += permanent_speed_increment * 0.1
	original_idle_speed = idle_speed
	print("Permanent speed increment applied: idle_speed=%.1f, speed_boost=%.1f" % [idle_speed, speed_boost])

func apply_permanent_shoot_increment() -> void:
	if shoot_cooldown <= 0.001:
		print("Minimum shoot cooldown reached.")
		return
		
	shoot_cooldown -= shoot_cooldown_decrement
	original_shoot_cooldown = shoot_cooldown
	print("Shoot cooldown permanently decreased to: %.2f" % shoot_cooldown)
	
func apply_permanent_health_increment() -> void:
	if max_health >= max_heart_capacity:
		print("Max health already at capacity.")
		return

	initial_heart_progress += initial_heart_amount_increment
	if initial_heart_progress >= 1.0:
		max_health += 1
		health = min(health + 1, max_health)
		initial_heart_progress -= 1.0
		update_hearts()
		print("Max health increased to: %d" % max_health)

func apply_permanent_capacity_increment() -> void:
	if max_heart_capacity >= 10:
		print("Max heart capacity already at maximum.")
		return

	total_heart_progress += total_heart_amount_increment
	if total_heart_progress >= 1.0:
		max_heart_capacity += 1
		total_heart_progress -= 1.0
		update_hearts()
		print("Max heart capacity increased to: %d" % max_heart_capacity)
	
# ============================================================
#  MATING
# ============================================================
func _on_rear_detector_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent.is_in_group("female_fly"):
		female_partner = parent

func _on_rear_detector_area_exited(area: Area2D) -> void:
	if area.get_parent() == female_partner:
		female_partner = null

func start_mating() -> void:
	if not female_partner or is_mating:
		return

	is_mating = true
	mating_timer = mating_duration

	state = FlyState.LANDED
	velocity = Vector2.ZERO

	$FlyVisuals/Sprite2D.visible = false
	$FlyVisuals/Body_Wings.visible = true
	$FlyVisuals/Body_Wings.play("flying")

	if female_partner.has_method("start_mating"):
		female_partner.start_mating()

	_start_mating_vibration()

	print("Mating started!")

func _start_mating_vibration() -> void:
	var pulse_interval = 1.0 / 3.0
	var total_pulses = mating_duration / pulse_interval

	for i in range(int(total_pulses)):
		if not is_mating:
			break
		_vibrate(0.08, 0.5)
		await get_tree().create_timer(pulse_interval).timeout

	_vibrate(0.3, 0.7)

func finish_mating() -> void:
	is_mating = false
	female_partner = null

	$FlyVisuals/Sprite2D.visible = true
	$FlyVisuals/Body_Wings.visible = false
	$FlyVisuals/Body_Wings.stop()
	
	apply_permanent_capacity_increment()
	
	print("Mating finished!")

# ============================================================
#  HEARTS
# ============================================================
func update_hearts() -> void:
	if not hearts_container:
		return

	for i in range(hearts_container.get_child_count()):
		var heart = hearts_container.get_child(i)
		heart.visible = (i < max_health)
		if i < health:
			heart.texture = heart_full
		else:
			heart.texture = heart_broken

func increase_max_health(amount: int = 1) -> void:
	max_health += amount
	health = min(health + amount, max_health)
	update_hearts()

func apply_heart_boost() -> void:
	if health < max_health:
		health += 1
		update_hearts()
		print("Heart mended!")
	elif max_health < max_heart_capacity:
		max_health += 1
		health += 1
		update_hearts()
		print("New heart added!")
	else:
		print("No room for more hearts!")
