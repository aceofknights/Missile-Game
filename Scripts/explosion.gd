extends Area2D

@onready var shape = $CollisionShape2D.shape

func _ready():
	scale = Vector2(0, 0)
	shape.radius = 0

	var tween = get_tree().create_tween()

	# Grow
	tween.tween_property(self, "scale", Vector2(2, 2), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(shape, "radius", 48, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Shrink
	tween.tween_property(self, "scale", Vector2(0, 0), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(shape, "radius", 0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	$Timer.start()
	connect("area_entered", Callable(self, "_on_area_entered"))


func _on_area_entered(area):
	if area.is_in_group("enemy"):
		area.die()
 

func _on_timer_timeout():
	pass # Replace with function body.
	queue_free()
