extends RefCounted
class_name EmpAttackUtils


static func get_active_cannons(tree: SceneTree) -> Array:
	var active_cannons: Array = []
	for node in tree.get_nodes_in_group("cannon"):
		if node == null:
			continue
		if node.has_method("is_destroyed") and node.is_destroyed():
			continue
		if node.has_method("_can_operate") and not node._can_operate():
			continue
		active_cannons.append(node)
	return active_cannons


static func select_emp_targets_for_health(active_cannons: Array, current_health: int) -> Array:
	if active_cannons.is_empty():
		return []
	if current_health <= 2:
		return active_cannons.duplicate()
	return [active_cannons[randi() % active_cannons.size()]]


static func spawn_emp_volley(
	owner: Node,
	emp_missile_scene: PackedScene,
	origin: Vector2,
	targets: Array,
	enemy_died_callback: Callable
) -> int:
	if owner == null or emp_missile_scene == null or targets.is_empty():
		return 0

	var spawned := 0
	for target in targets:
		if target == null:
			continue
		var direction = (target.global_position - origin).normalized()
		if direction == Vector2.ZERO:
			continue

		var missile = emp_missile_scene.instantiate()
		GameManager.enemies_alive += 1
		if enemy_died_callback.is_valid():
			missile.connect("enemy_died", enemy_died_callback)
		missile.global_position = origin
		missile.velocity = direction
		owner.call("_add_to_scene", missile)
		spawned += 1

	return spawned
