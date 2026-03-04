extends RefCounted
class_name NodeContracts

# Utility helpers to validate scene structure against script expectations.
# Use these in _ready() for fast, readable diagnostics while iterating.

static func require_nodes(owner: Node, required_paths: Array[String]) -> bool:
	var all_present := true

	for path in required_paths:
		var node = owner.get_node_or_null(path)
		if node == null:
			all_present = false
			push_error("❌ Missing required node '%s' in scene '%s'" % [path, owner.name])

	if all_present:
		print("✅ Node contract passed for '%s'" % owner.name)

	return all_present


static func require_nodes_with_types(owner: Node, required: Dictionary) -> bool:
	# Dictionary format: {"NodePath": "TypeName"}
	# Example: {"UI/AmmoLabel": "Label", "PauseMenu": "CanvasLayer"}
	var all_present := true

	for path in required.keys():
		var expected_type: String = str(required[path])
		var node = owner.get_node_or_null(path)

		if node == null:
			all_present = false
			push_error("❌ Missing required node '%s' in scene '%s'" % [path, owner.name])
			continue

		if expected_type != "" and not node.is_class(expected_type):
			all_present = false
			push_error("❌ Node '%s' expected type '%s', got '%s'" % [path, expected_type, node.get_class()])

	if all_present:
		print("✅ Typed node contract passed for '%s'" % owner.name)

	return all_present
