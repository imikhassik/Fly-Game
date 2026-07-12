extends Area2D

@export var speed: float = 150.0
@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.DOWN

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	z_index = 2
	
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		# If the fly is landed or landing, ignore completely – projectile passes through
		if body.state in [body.FlyState.LANDED, body.FlyState.LANDING]:
			return
		# Otherwise, deal damage and remove the projectile
		if body.has_method("take_damage"):
			body.take_damage()
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_projectile"):
		area.queue_free()
		queue_free()
