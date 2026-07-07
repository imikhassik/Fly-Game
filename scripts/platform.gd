@tool
extends StaticBody2D

@export var force_variant: int = 0

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
	
	# Get references (children are not reset – keep their editor transforms)
	var sprite = chosen.get_node("Sprite2D")
	var collision = chosen.get_node("CollisionPolygon2D")
	
	# Preserve the sprite's editor scale (so your manual sizing remains)
	var base_scale = sprite.scale
	
	# ----- APPLY RANDOM TRANSFORMS TO THE PARENT (Area2D) -----
	# Flip (horizontal/vertical) using parent scale
	var flip_h = randi() % 2 == 0
	var flip_v = randi() % 2 == 0
	chosen.scale.x = -1 if flip_h else 1
	chosen.scale.y = -1 if flip_v else 1
	
	# Random rotation (±15 degrees)
	var rotation_deg = randf_range(-15.0, 15.0)
	chosen.rotation = deg_to_rad(rotation_deg)
	
	# Restore the sprite's scale (preserve your editor sizing)
	sprite.scale = base_scale
	
	# --- DO NOT reset position, rotation, or flip of children ---
	# They keep their editor-defined local transforms.
