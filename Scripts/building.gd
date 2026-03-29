extends Area2D

var destroyed := false
var permanently_destroyed := false
var shield_hits_remaining := 0
var shield_cooldown_remaining := 0.0
@onready var sprite: Sprite2D = $Sprite2D
@onready var repair_label: Label = get_node_or_null("RepairLabel") as Label
@onready var shield_sprite: Sprite2D = Sprite2D.new()


func _ready():
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("building")
	add_to_group("defense_target")
	if repair_label:
		repair_label.top_level = true
	_setup_temp_shield_sprite()
	_update_visual_state()


func _process(_delta: float) -> void:
	_update_shield_state(_delta)
	if not repair_label:
		return
	repair_label.global_position = global_position + Vector2(-70, -64)
	repair_label.visible = false


func _on_area_entered(area):
	if destroyed:
		return
	if area.is_in_group("enemy"):
		print("Building destroyed by Enemy")
		area.call_deferred("die", false)
		die()


func _setup_temp_shield_sprite() -> void:
	shield_sprite.texture = preload("res://circle.png")
	shield_sprite.modulate = Color(0.4, 0.95, 1.0, 0.35)
	shield_sprite.scale = Vector2(0.2, 0.12)
	shield_sprite.visible = false
	add_child(shield_sprite)


func _update_shield_state(delta: float) -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()
	if max_hits <= 0 or destroyed:
		shield_hits_remaining = 0
		shield_cooldown_remaining = 0.0
		if shield_sprite:
			shield_sprite.visible = false
		return

	if shield_hits_remaining <= 0:
		if shield_cooldown_remaining <= 0.0:
			shield_hits_remaining = max_hits
		else:
			shield_cooldown_remaining = maxf(0.0, shield_cooldown_remaining - delta)

	if shield_sprite:
		shield_sprite.visible = shield_hits_remaining > 0


func handle_enemy_impact(enemy: Area2D) -> bool:
	if GameManager.is_active_shield_up():
		if enemy:
			enemy.call_deferred("die", true)
		return true

	if destroyed:
		return false

	_update_shield_state(0.0)
	if shield_hits_remaining > 0:
		shield_hits_remaining -= 1
		if shield_hits_remaining <= 0:
			shield_cooldown_remaining = GameManager.get_shield_generator_cooldown_seconds()
		if enemy:
			enemy.call_deferred("die", true)
		return true

	return false


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
	return _is_mouse_over_defense(global_mouse_position)


func is_hovered_any_state(global_mouse_position: Vector2) -> bool:
	return _is_mouse_over_defense(global_mouse_position)


func _is_mouse_over_defense(global_mouse_position: Vector2) -> bool:
	if sprite and sprite.texture:
		var local_mouse = sprite.to_local(global_mouse_position)
		if sprite.get_rect().has_point(local_mouse):
			return true
	return global_position.distance_to(global_mouse_position) <= 52.0


func repair() -> void:
	if permanently_destroyed:
		return
	destroyed = false
	monitoring = true
	monitorable = true
	_update_visual_state()


func destroy_permanently() -> void:
	if permanently_destroyed:
		return
	permanently_destroyed = true
	destroyed = true
	monitoring = false
	monitorable = false
	if is_in_group("building"):
		remove_from_group("building")
	queue_free()
