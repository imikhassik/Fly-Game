extends CharacterBody2D

signal landed
signal took_off

# ----- STATES -----
enum FlyState { FLYING, LANDING, LANDED, TAKING_OFF }
var state: FlyState = FlyState.LANDED

# ----- MOVEMENT (shared) -----
@export var rotation_speed: float = 3.0        # A/D rotation speed (rad/s)

# ----- WALKING -----
@export var walk_speed: float = 150.0

# ----- FLYING -----
@export var forward_speed: float = 60.0        # constant drift
@export var up_boost: float = 160.0            # extra speed when W pressed

# ----- LANDING / TAKEOFF -----
@export var landing_deceleration: float = 200.0
@export var landing_scale_target: float = 0.75
@export var landing_scale_speed: float = 0.03
@export var take_off_scale_speed: float = 0.03
@export var takeoff_forward_speed: float = 150.0

# Internal
var original_scale: Vector2 = Vector2.ONE
var vertical_velocity: float = 0.0

func _ready() -> void:
	original_scale = $Sprite2D.scale
	$Sprite2D.scale = original_scale * landing_scale_target
	$Sprite2D.rotation = 0.0
	add_to_group("player") 

func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0
	if Input.is_action_pressed("move_up"):
		input_vector.y -= 1.0
	# 'move_down' is intentionally omitted (does nothing)
	
	if Input.is_action_just_pressed("land"):
		match state:
			FlyState.FLYING:
				start_landing()
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

# ----- FLYING STATE (same as walking + constant drift) -----
func flying_update(input_vector: Vector2, delta: float) -> void:
	# 1. Rotate freely (no clamp)
	if abs(input_vector.x) > 0.01:
		rotation += input_vector.x * rotation_speed * delta
	
	# 2. Speed: constant drift + boost if W pressed
	var speed = forward_speed
	if input_vector.y < 0:   # W pressed
		speed += up_boost
	# (S does nothing)
	
	# 3. Move in facing direction
	var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
	velocity = forward_dir * speed
	move_and_slide()
	
	# 4. Screen clamp
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, screen_size.x)
	position.y = clamp(position.y, 0.0, screen_size.y)
	
	# 5. Sprite inherits parent rotation, so local rotation must be 0
	$Sprite2D.rotation = 0.0

# ----- LANDED (WALKING) STATE -----
func landed_update(input_vector: Vector2, delta: float) -> void:
	# 1. Rotate freely (no clamp)
	if abs(input_vector.x) > 0.01:
		rotation += input_vector.x * rotation_speed * delta
	
	# 2. Speed: only if W pressed
	if input_vector.y < 0:
		var forward_dir: Vector2 = Vector2(0, -1).rotated(rotation)
		velocity = forward_dir * walk_speed
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()
	
	# 3. Screen clamp
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	position.x = clamp(position.x, 0.0, screen_size.x)
	position.y = clamp(position.y, 0.0, screen_size.y)
	
	# 4. Sprite inherits parent rotation, so local rotation must be 0
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

# ----- SCALE TRANSITIONS -----
func _process(delta: float) -> void:
	if state == FlyState.LANDING:
		var target = original_scale * landing_scale_target
		$Sprite2D.scale = $Sprite2D.scale.move_toward(target, landing_scale_speed * delta)
	elif state == FlyState.TAKING_OFF:
		var target = original_scale
		$Sprite2D.scale = $Sprite2D.scale.move_toward(target, take_off_scale_speed * delta)
