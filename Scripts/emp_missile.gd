extends Area2D

signal enemy_died

@export var speed := 180.0
@export var emp_disable_duration := 1.6

var velocity := Vector2.ZERO
var is_dying := false


func _ready() -> void:
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("enemy")
	add_to_group("emp_missile")


func _process(delta: float) -> void:
	position += velocity * speed * delta
	if position.y >= get_viewport_rect().size.y:
		die(true)


func _on_area_entered(area: Area2D) -> void:
	if area.name == "Projectile":
		die(false)
		area.queue_free()
		return

	if area.is_in_group("defense_target"):
		if area.has_method("disable_temporarily"):
			area.disable_temporarily(emp_disable_duration)
		elif area.has_method("die"):
			area.call_deferred("die")
		die(true)


func die(no_reward := false) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	emit_signal("enemy_died")
	queue_free()
