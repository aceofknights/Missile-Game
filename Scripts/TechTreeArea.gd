extends Control

var owner_screen: Control

@export var line_width: float = 3.0
@export var line_color_locked: Color = Color(0.28, 0.30, 0.35, 0.75)
@export var line_color_active: Color = Color(0.35, 0.75, 1.0, 0.95)

func _draw() -> void:
	if owner_screen == null:
		return
	if not owner_screen.has_method("_get_tree_connections"):
		return
	if not owner_screen.has_method("_get_tree_buttons"):
		return

	var connections: Array = owner_screen._get_tree_connections()
	var nodes: Dictionary = owner_screen._get_tree_buttons()

	for connection in connections:
		var from_key: String = String(connection.get("from", ""))
		var to_key: String = String(connection.get("to", ""))

		if not nodes.has(from_key) or not nodes.has(to_key):
			continue

		var from_node := nodes[from_key] as Control
		var to_node := nodes[to_key] as Control

		if from_node == null or to_node == null:
			continue
		if not is_instance_valid(from_node) or not is_instance_valid(to_node):
			continue
		if not from_node.visible or not to_node.visible:
			continue

		# True visual center of each icon, converted into TechTreeArea local space.
		var start := from_node.get_global_rect().get_center() - global_position
		var finish := to_node.get_global_rect().get_center() - global_position
		var mid_x := (start.x + finish.x) * 0.5

		var color := line_color_locked
		if owner_screen.has_method("_is_connection_active") and owner_screen._is_connection_active(from_key, to_key):
			color = line_color_active

		draw_line(start, Vector2(mid_x, start.y), color, line_width, true)
		draw_line(Vector2(mid_x, start.y), Vector2(mid_x, finish.y), color, line_width, true)
		draw_line(Vector2(mid_x, finish.y), finish, color, line_width, true)
