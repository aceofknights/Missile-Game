extends Area2D

func _ready():
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("building")

func _on_area_entered(area):
	if area.is_in_group("enemy"):
		die()
		area.queue_free()
		print("Building destroyed by Enemy")

func die():
	print("building destroyed")
	queue_free()
