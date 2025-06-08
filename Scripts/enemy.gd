extends Area2D
@export var explosion_scene: PackedScene
var speed = 150
var velocity = Vector2.ZERO
signal enemy_died
var is_dying = false

func _ready():
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("enemy")
	# this is a test comment
	
func _process(delta):
	position += velocity * speed * delta
	
	# Check if hit the ground
	if position.y >= get_viewport_rect().size.y:
		print("Enemy hit the ground!")
		die()

func _on_area_entered(area):
	if area.name == "Projectile":
		die()
		area.queue_free()
		print("Enemy destroyed by projectile!")
	elif area.is_in_group("building"):
		print("🏠 Hit a building")
		area.queue_free()
		die()

func die():
	if is_dying:
		print("⚠️ Already dying, skipping...")
		return
	is_dying = true
	
	print("Enemy died")
	emit_signal("enemy_died")
	
	if explosion_scene:
		print("💥 Spawning explosion")
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)
	else:
		print("❌ No explosion scene!")
	queue_free()

