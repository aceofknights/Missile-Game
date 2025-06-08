extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 400
var target: Vector2  # This stores where the projectile is going

func _ready():
	look_at(target)
	connect("area_entered", Callable(self, "_on_area_entered"))

func _process(delta):
	var direction = (target - global_position)
	if direction.length() < speed * delta:
		explode()
	else:
		position += direction.normalized() * speed * delta

func _on_area_entered(area):
	if area.is_in_group("enemy"):
		print("🎯 Hit enemy!")
		explode()

func explode():
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)
	queue_free()
