extends Area2D

# ----- CONFIG -----
@export var buff_type: String = "speed"   # "speed" or "shoot"
@export var drain_time: float = 1.5       # seconds to fully drain
@export var color_speed: Color = Color.GREEN
@export var color_shoot: Color = Color.RED

# ----- INTERNAL STATE -----
var drain_progress: float = 0.0
var is_draining: bool = false
var is_consumed: bool = false
var initial_scale: Vector2 = Vector2.ONE   # <-- Store initial scale

@onready var fill_sprite = $Fill
@onready var border_sprite = $Border

func _ready() -> void:
	# Store the starting scale (as set in the scene)
	initial_scale = fill_sprite.scale
	print("Food initial scale: ", initial_scale)
	
	# Set color based on buff type
	if buff_type == "speed":
		fill_sprite.modulate = color_speed
	else:
		fill_sprite.modulate = color_shoot
	
	border_sprite.modulate = Color.BLACK
	
	# Put food on Layer 3 so HeadDetector can detect it
	collision_layer = 4
	collision_mask = 0
	
	# Ensure food renders below the fly (fly is z_index = 1)
	z_index = 0

func _process(delta: float) -> void:
	if is_consumed:
		return
	
	# Check if the fly's head is touching this food
	var head = get_tree().get_first_node_in_group("head_detector")
	if head and head.get_overlapping_areas().has(self):
		# If interact button is held, start draining
		if Input.is_action_pressed("interact"):
			is_draining = true
			drain_progress += delta / drain_time
			
			# Shrink the circle from the outside in
			var new_scale = 1.0 - drain_progress
			fill_sprite.scale = initial_scale * new_scale   # <-- Scale from initial size
			
			if drain_progress >= 1.0:
				_apply_buff()
				return
		else:
			# If the button is released, reset progress
			is_draining = false
			drain_progress = 0.0
			border_sprite.scale = initial_scale   # <-- Reset to initial size
			fill_sprite.scale = initial_scale
	else:
		# If the head leaves, reset progress
		if is_draining:
			drain_progress += delta / drain_time
			var new_scale = 1.0 - drain_progress
			fill_sprite.scale = initial_scale * new_scale   # only fill shrinks

func _apply_buff() -> void:
	is_consumed = true
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if buff_type == "speed":
			player.apply_speed_boost()
		else:
			player.apply_shoot_boost()
			
	fill_sprite.visible = false
