@tool
extends StaticBody2D

@export var force_variant: int = 0  # 0 = random, 1-5 = specific variant

func _ready() -> void:
	# Gather all variant nodes
	var variants: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("Variant"):
			variants.append(child)
	
	if variants.is_empty():
		push_warning("No variants found in platform scene!")
		return
	
	# Determine which variant to use
	var chosen: Node
	if force_variant >= 1 and force_variant <= variants.size():
		chosen = variants[force_variant - 1]
	else:
		chosen = variants.pick_random()
	
	# Enable the chosen variant, disable all others
	for variant in variants:
		variant.visible = (variant == chosen)
		variant.process_mode = PROCESS_MODE_DISABLED if variant != chosen else PROCESS_MODE_INHERIT
	
	# Get the sprite and collision from the chosen variant
	var sprite = chosen.get_node("Sprite2D")
	var collision = chosen.get_node("CollisionPolygon2D")
	
	# Use the existing scale set in the editor as the BASE scale
	var base_scale = sprite.scale
	
	var scale_factor = randf_range(0.8, 1.2)
	var final_scale = base_scale * scale_factor
	sprite.scale = final_scale
	collision.scale = final_scale
	
	# Apply random flip (optional)
	sprite.flip_h = randi() % 2 == 0
	sprite.flip_v = randi() % 2 == 0
	
	# Apply random rotation (e.g., ±15 degrees)
	var rotation_deg = randf_range(-15.0, 15.0)
	sprite.rotation = deg_to_rad(rotation_deg)
	collision.rotation = deg_to_rad(rotation_deg)
