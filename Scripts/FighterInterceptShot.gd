extends Area2D

@export var speed := 420.0
@export var max_lifetime := 1.8
@export var hit_radius := 22.0

var target_node: Area2D
var target_position := Vector2.ZERO
var _lifetime := 0.0


func _ready() -> void:
	add_to_group("enemy")
	monitoring = false
	monitorable = false


func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()
		return

	if is_instance_valid(target_node):
		target_position = target_node.global_position
		if global_position.distance_to(target_node.global_position) <= hit_radius:
			if target_node.has_method("die"):
				target_node.call_deferred("die", true)
			else:
				target_node.queue_free()
			queue_free()
			return

	var to_target := target_position - global_position
	if to_target.length() <= speed * delta:
		global_position = target_position
		queue_free()
		return

	var step := to_target.normalized() * speed * delta
	global_position += step
	rotation = step.angle()
