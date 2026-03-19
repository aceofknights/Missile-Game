extends Area2D

@export var duration: float = 3.0
@export var radius: float = 120.0
@export var player_projectile_speed_multiplier: float = 0.55
@export var enemy_missile_speed_multiplier: float = 1.4

@onready var life_timer: Timer = $LifeTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("ion_zone")
	monitoring = false
	monitorable = false

	var circle := collision_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		collision_shape.shape = circle
	circle.radius = radius

	if sprite:
		var diameter := maxf(1.0, radius * 2.0)
		sprite.scale = Vector2(diameter / 128.0, diameter / 128.0)

	life_timer.wait_time = duration
	life_timer.one_shot = true
	life_timer.timeout.connect(queue_free)
	life_timer.start()


func contains_point(point: Vector2) -> bool:
	return global_position.distance_squared_to(point) <= radius * radius
