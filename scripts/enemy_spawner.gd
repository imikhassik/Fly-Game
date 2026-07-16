extends Node2D

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

@export var spawn_interval_min: float = 10.0
@export var spawn_interval_max: float = 20.0
@export var spawn_margin: float = 100.0
@export var max_enemies: int = 5
@export var initial_spawn_delay_min: float = 1.0
@export var initial_spawn_delay_max: float = 3.0

var spawn_timer: float = 0.0
var next_interval: float = 0.0
var first_spawn_done: bool = false

func _ready() -> void:
	next_interval = randf_range(initial_spawn_delay_min, initial_spawn_delay_max)

func _process(delta: float) -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	if enemies.size() >= max_enemies:
		return
	
	spawn_timer += delta
	if spawn_timer >= next_interval:
		spawn_timer = 0.0
		if not first_spawn_done:
			first_spawn_done = true
			next_interval = randf_range(spawn_interval_min, spawn_interval_max)
		else:
			next_interval = randf_range(spawn_interval_min, spawn_interval_max)
		spawn_enemy()

func spawn_enemy() -> void:
	if enemy_scene == null:
		push_warning("Enemy scene not assigned in EnemySpawner!")
		return
	
	var enemy = enemy_scene.instantiate()
	
	var screen_size = get_viewport().get_visible_rect().size
	var side = randi() % 4
	var spawn_pos: Vector2
	
	match side:
		0: # Top
			spawn_pos = Vector2(randf_range(0, screen_size.x), -spawn_margin)
		1: # Bottom
			spawn_pos = Vector2(randf_range(0, screen_size.x), screen_size.y + spawn_margin)
		2: # Left
			spawn_pos = Vector2(-spawn_margin, randf_range(0, screen_size.y))
		3: # Right
			spawn_pos = Vector2(screen_size.x + spawn_margin, randf_range(0, screen_size.y))
	
	enemy.global_position = spawn_pos
	# Enemies always spawn facing UP (rotation = PI/2)
	enemy.rotation = PI / 2
	
	get_tree().current_scene.add_child(enemy)
