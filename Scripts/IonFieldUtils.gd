extends RefCounted
class_name IonFieldUtils


static func get_speed_multiplier_at(point: Vector2, for_player_projectile: bool) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1.0

	var multiplier := 1.0
	for zone in tree.get_nodes_in_group("ion_zone"):
		if zone == null or not zone.has_method("contains_point"):
			continue
		if not zone.contains_point(point):
			continue
		if for_player_projectile:
			multiplier *= float(zone.player_projectile_speed_multiplier)
		else:
			multiplier *= float(zone.enemy_missile_speed_multiplier)
	return maxf(0.1, multiplier)
