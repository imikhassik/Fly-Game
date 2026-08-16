extends Node2D

signal mating_finished

var is_mating: bool = false
var mating_timer: float = 0.0
var mating_duration: float = 3.0

@onready var idle_sprite = $Sprite2D
@onready var animated_sprite = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("female_fly")
	idle_sprite.visible = true
	animated_sprite.visible = false

func start_mating() -> void:
	if is_mating:
		return

	is_mating = true
	mating_timer = mating_duration

	idle_sprite.visible = false
	animated_sprite.visible = true
	animated_sprite.play("mating")

	print("Female: mating started!")

func _process(delta: float) -> void:
	if not is_mating:
		return

	mating_timer -= delta
	if mating_timer <= 0:
		is_mating = false

		# Set to the last frame of the animation
		var last_frame = animated_sprite.sprite_frames.get_frame_count("mating") - 1
		animated_sprite.frame = last_frame
		animated_sprite.pause()   # or stop() – pause is safer

		mating_finished.emit()
		print("Female: mating finished! (frame: ", animated_sprite.frame, ")")
