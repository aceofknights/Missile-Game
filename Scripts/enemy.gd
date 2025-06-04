extends Area2D
@export var explosion_scene: PackedScene
var speed = 150
var velocity = Vector2.ZERO

func _ready():
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("enemy")
	# this is a test comment
func _process(delta):
	position += velocity * speed * delta
	
	# Check if hit the ground
	if position.y >= get_viewport_rect().size.y:
		queue_free()  # You can also trigger damage here
		print("Enemy hit the ground!")

func _on_area_entered(area):
	if area.name == "Projectile":
		die()
		area.queue_free()
		print("Enemy destroyed by projectile!")

func die():
	print("Enemy died")
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)
	queue_free()

