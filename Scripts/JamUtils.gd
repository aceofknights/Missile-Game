extends RefCounted
class_name JamUtils


static func is_jammed(jam_end_time: float, tree: SceneTree) -> bool:
	return tree.get_processed_time() < jam_end_time


static func get_jammed_target(original_target: Vector2, radius: float) -> Vector2:
	if radius <= 0.0:
		return original_target

	var angle: float = randf() * TAU
	var distance: float = sqrt(randf()) * radius
	var offset := Vector2(cos(angle), sin(angle)) * distance
	return original_target + offset
