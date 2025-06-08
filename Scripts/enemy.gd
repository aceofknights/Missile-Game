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
		die(true)  # So we still emit enemy_died

func _on_area_entered(area):
	print("Entered: ", area.name)
	if area.name == "Projectile":
		print("🔫 Hit by projectile")
		die(false)
		area.queue_free()
	elif area.is_in_group("building"):
		print("🏠 Hit a building")
		area.queue_free()
		die(true)


func die(no_reward := false):
	if is_dying:
		print("⚠️ Already dying, skipping...")
		return
	is_dying = true
	
	# Only reward when not falling
	if not no_reward:
		GameManager.add_resources(1)
	
	print("Enemy died")
	emit_signal("enemy_died")
	
	if explosion_scene:
		print("💥 Spawning explosion")
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		# ✅ Set reward flag for the explosion
		explosion.gives_reward = not no_reward
  # true = player deserves reward

		get_tree().current_scene.add_child(explosion)
	else:
		print("❌ No explosion scene!")
	queue_free()

