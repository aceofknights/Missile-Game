extends RefCounted
class_name IonHazardController


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func has_active_zone() -> bool:
	var tree := _tree()
	return tree != null and tree.get_nodes_in_group("ion_zone").size() > 0


static func has_active_ion_missile() -> bool:
	var tree := _tree()
	return tree != null and tree.get_nodes_in_group("ion_missile").size() > 0


static func can_launch_ion_missile() -> bool:
	return not has_active_zone() and not has_active_ion_missile()


static func can_spawn_zone() -> bool:
	return not has_active_zone()
