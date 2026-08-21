extends Control

var is_paused: bool = false

func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS   # so it can react even when game is paused

func _input(event: InputEvent) -> void:
	# Toggle pause on Space or Start button (ui_menu)
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_menu"):
		toggle_pause()

func toggle_pause() -> void:
	is_paused = !is_paused
	visible = is_paused
	get_tree().paused = is_paused
