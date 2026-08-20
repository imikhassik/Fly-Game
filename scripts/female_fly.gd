extends Node2D

signal mating_finished

var is_mating: bool = false
var mating_timer: float = 0.0
var mating_duration: float = 3.0
var player: Node = null

@onready var idle_sprite = $Sprite2D
@onready var animated_sprite = $AnimatedSprite2D
@onready var wings = $Wings
@onready var body_collision = $BodyCollision/CollisionPolygon2D

func _ready() -> void:
	add_to_group("female_fly")
	idle_sprite.visible = true
	animated_sprite.visible = false
	wings.visible = false

	# Set collision layer and mask
	$BodyCollision.collision_layer = 4
	$BodyCollision.collision_mask = 1

	player = get_tree().get_first_node_in_group("player")

func start_mating() -> void:
	if is_mating:
		return

	is_mating = true
	mating_timer = mating_duration

	idle_sprite.visible = false
	animated_sprite.visible = true
	animated_sprite.play("mating")
	wings.visible = true
	wings.play("flapping")

	print("Female: mating started!")

func _process(delta: float) -> void:
	# Toggle collision based on player state
	if not player:
		player = get_tree().get_first_node_in_group("player")
	else:
		# Only enable collision when player is LANDED
		body_collision.disabled = (player.state != player.FlyState.LANDED)

	if not is_mating:
		return

	mating_timer -= delta
	if mating_timer <= 0:
		is_mating = false

		var last_frame = animated_sprite.sprite_frames.get_frame_count("mating") - 1
		animated_sprite.frame = last_frame
		animated_sprite.pause()
		wings.frame = 2
		wings.pause()

		mating_finished.emit()
		print("Female: mating finished! (frame: ", animated_sprite.frame, ")")
