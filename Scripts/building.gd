extends Area2D

func _ready():
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("building")

func _on_area_entered(area):
	if area.is_in_group("enemy"):
		print("Building destroyed by Enemy")
		area.call_deferred("die", false)  # Ask the enemy to kill itself
		die()

func die():
	print("building destroyed")
	queue_free()
