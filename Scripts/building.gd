extends Area2D

var destroyed := false
@onready var sprite: Sprite2D = $Sprite2D
@onready var repair_label: Label = $RepairLabel


func _ready():
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("building")
	add_to_group("defense_target")
	repair_label.top_level = true
	_update_visual_state()


func _process(_delta: float) -> void:
	repair_label.global_position = global_position + Vector2(-70, -64)
	repair_label.visible = destroyed and GameManager.can_use_repair_shop()
	if repair_label.visible:
		repair_label.text = "[R] Repair (%d)" % GameManager.get_repair_shop_cost()


func _on_area_entered(area):
	if destroyed:
		return
	if area.is_in_group("enemy"):
		print("Building destroyed by Enemy")
		area.call_deferred("die", false)
		die()


func die():
	if destroyed:
		return
	print("building destroyed")
	destroyed = true
	monitoring = false
	monitorable = false
	_update_visual_state()


func _update_visual_state() -> void:
	if sprite:
		sprite.modulate = Color(0.25, 0.25, 0.25, 1.0) if destroyed else Color(0.0823529, 0.0784314, 0.960784, 1)


func is_destroyed() -> bool:
	return destroyed


func is_hovered(global_mouse_position: Vector2) -> bool:
	if not destroyed:
		return false
	return global_position.distance_to(global_mouse_position) <= 52.0


func repair() -> void:
	destroyed = false
	monitoring = true
	monitorable = true
	_update_visual_state()
