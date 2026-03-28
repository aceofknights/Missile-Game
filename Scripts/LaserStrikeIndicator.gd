extends Node2D

signal strike_impact(target: Node2D, target_name: String)

@export var speed: float = 1800.0
@export var impact_distance: float = 20.0

var _target_node: Node2D = null
var _target_name: String = ""
var _fallback_target_position: Vector2 = Vector2.ZERO


func setup_strike(spawn_position: Vector2, target_node: Node2D, target_name: String) -> void:
	global_position = spawn_position
	_target_node = target_node
	_target_name = target_name
	if is_instance_valid(_target_node):
		_fallback_target_position = _target_node.global_position
	else:
		_fallback_target_position = spawn_position


func _process(delta: float) -> void:
	var target_position: Vector2 = _resolve_target_position()
	var offset: Vector2 = target_position - global_position
	var distance: float = offset.length()
	if distance <= impact_distance:
		_impact()
		return

	var step: float = speed * delta
	if distance <= step:
		global_position = target_position
		_impact()
		return

	var direction: Vector2 = offset / distance
	rotation = direction.angle()
	global_position += direction * step


func _resolve_target_position() -> Vector2:
	if is_instance_valid(_target_node):
		_fallback_target_position = _target_node.global_position
	return _fallback_target_position


func _impact() -> void:
	emit_signal("strike_impact", _target_node, _target_name)
	queue_free()
