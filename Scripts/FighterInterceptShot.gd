extends Area2D

@export var speed: float = 1300.0
@export var max_lifetime: float = 0.35
@export var hit_radius: float = 24.0

var target_node: Area2D = null
var target_position: Vector2 = Vector2.ZERO
var _lifetime: float = 0.0
var _direction: Vector2 = Vector2.ZERO


func setup_shot(target: Area2D, aim_position: Vector2) -> void:
	target_node = target
	target_position = aim_position

	var to_target: Vector2 = target_position - global_position
	if to_target.length() <= 0.001:
		_direction = Vector2.DOWN
	else:
		_direction = to_target.normalized()

	rotation = _direction.angle()


func _ready() -> void:
	add_to_group("enemy")
	monitoring = false
	monitorable = false

	# Fallback in case setup_shot was not called
	if _direction == Vector2.ZERO:
		if is_instance_valid(target_node):
			target_position = target_node.global_position

		var to_target: Vector2 = target_position - global_position
		if to_target.length() <= 0.001:
			_direction = Vector2.DOWN
		else:
			_direction = to_target.normalized()

		rotation = _direction.angle()


func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()
		return

	if is_instance_valid(target_node):
		if target_node.is_in_group("boss") or target_node.has_signal("boss_defeated"):
			queue_free()
			return

		if global_position.distance_to(target_node.global_position) <= hit_radius:
			_destroy_target_projectile()
			queue_free()
			return

	global_position += _direction * speed * delta


func _destroy_target_projectile() -> void:
	if not is_instance_valid(target_node):
		return

	if target_node.has_method("explode"):
		target_node.call_deferred("explode")
	elif target_node.has_method("die"):
		target_node.call_deferred("die", true)
	else:
		_spawn_fallback_explosion(target_node.global_position)
		target_node.queue_free()


func _spawn_fallback_explosion(world_pos: Vector2) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	if not "EXPLOSION_SCENE" in current_scene:
		return

	var explosion_scene = current_scene.EXPLOSION_SCENE
	if explosion_scene == null:
		return

	var explosion = explosion_scene.instantiate()
	explosion.global_position = world_pos
	explosion.gives_reward = false
	current_scene.add_child(explosion)
