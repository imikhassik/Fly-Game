extends Area2D

@export var speed: float = 400.0
@export var lifetime: float = 2.0

var direction: Vector2 = Vector2.UP

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		body.queue_free()
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	# If the area is an enemy projectile, destroy both
	if area.is_in_group("enemy_projectile"):
		area.queue_free()
		queue_free()
