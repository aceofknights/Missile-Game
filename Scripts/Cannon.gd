extends Area2D

@export var projectile_scene: PackedScene
@export var cannon_id := GameManager.CANNON_MIDDLE
@export var fire_rate := 0.5

var cooldown := 0.0
var shots_in_cycle := 0
var emp_disabled_remaining := 0.0
@onready var ammo_label: Label = $AmmoLabel
@onready var fire_rate_bar: ProgressBar = $FireRateBar
@onready var repair_label: Label = get_node_or_null("RepairLabel") as Label
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("cannon")
	add_to_group("defense_target")
	monitoring = true
	monitorable = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	ammo_label.top_level = true
	fire_rate_bar.top_level = true
	if repair_label:
		repair_label.top_level = true
	_refresh_visibility_state()
	_update_overlay_positions()
	_update_ui()


func _process(delta: float) -> void:
	if emp_disabled_remaining > 0.0:
		emp_disabled_remaining = max(0.0, emp_disabled_remaining - delta)
	if _can_operate():
		look_at(get_global_mouse_position())
		if cooldown > 0.0:
			cooldown = max(0.0, cooldown - delta)
	_update_overlay_positions()
	_update_ui()


func _can_operate() -> bool:
	_refresh_visibility_state()
	return GameManager.is_cannon_unlocked(cannon_id) and not GameManager.is_cannon_destroyed(cannon_id)


func _refresh_visibility_state() -> void:
	var unlocked = GameManager.is_cannon_unlocked(cannon_id)
	var destroyed = GameManager.is_cannon_destroyed(cannon_id)
	var active = unlocked and not destroyed
	visible = unlocked
	monitorable = active
	monitoring = active
	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.disabled = not active
	if ammo_label:
		ammo_label.visible = active
	if fire_rate_bar:
		fire_rate_bar.visible = active
	if repair_label:
		repair_label.visible = emp_disabled_remaining > 0.0
		if emp_disabled_remaining > 0.0:
			repair_label.text = "EMP %.1fs" % emp_disabled_remaining
	if sprite:
		if destroyed:
			sprite.modulate = Color(0.35, 0.35, 0.35, 1.0)
		elif emp_disabled_remaining > 0.0:
			sprite.modulate = Color(0.55, 0.9, 1.0, 1.0)
		else:
			sprite.modulate = Color(1, 1, 1, 1)


func _update_ui() -> void:
	if ammo_label:
		ammo_label.text = "%d/%d" % [GameManager.get_cannon_current_ammo(cannon_id), GameManager.get_cannon_max_ammo(cannon_id)]
	if fire_rate_bar:
		var delay = max(0.001, GameManager.get_cannon_fire_rate(cannon_id, fire_rate))
		fire_rate_bar.max_value = delay
		fire_rate_bar.value = delay - min(delay, cooldown)


func _update_overlay_positions() -> void:
	ammo_label.global_position = global_position + Vector2(-45, 32)
	fire_rate_bar.global_position = global_position + Vector2(-45, 56)
	if repair_label:
		repair_label.global_position = global_position + Vector2(-70, -68)


func can_fire() -> bool:
	return _can_operate() and emp_disabled_remaining <= 0.0 and cooldown <= 0.0 and GameManager.get_cannon_current_ammo(cannon_id) > 0


func try_fire_at(target_position: Vector2) -> bool:
	if not can_fire():
		return false
	if fire(target_position):
		shots_in_cycle += 1
		if shots_in_cycle >= GameManager.get_cannon_shots_per_cycle(cannon_id):
			shots_in_cycle = 0
			cooldown = GameManager.get_cannon_fire_rate(cannon_id, fire_rate)
		_update_ui()
		return true
	return false


func fire(target_position: Vector2) -> bool:
	if not GameManager.spend_cannon_ammo(cannon_id, 1):
		return false

	var projectile = projectile_scene.instantiate()
	projectile.global_position = global_position
	projectile.target = target_position
	get_tree().current_scene.add_child(projectile)
	_update_ui()
	return true


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy"):
		GameManager.destroy_cannon(cannon_id)
		_refresh_visibility_state()




func disable_temporarily(duration: float) -> void:
	emp_disabled_remaining = max(emp_disabled_remaining, max(0.1, duration))
	_refresh_visibility_state()

func die() -> void:
	GameManager.destroy_cannon(cannon_id)
	_refresh_visibility_state()


func is_destroyed() -> bool:
	return GameManager.is_cannon_destroyed(cannon_id)


func is_hovered(global_mouse_position: Vector2) -> bool:
	if not GameManager.is_cannon_unlocked(cannon_id) or not is_destroyed():
		return false
	return _is_mouse_over_cannon(global_mouse_position)


func is_hovered_any_state(global_mouse_position: Vector2) -> bool:
	if not GameManager.is_cannon_unlocked(cannon_id):
		return false
	return _is_mouse_over_cannon(global_mouse_position)


func _is_mouse_over_cannon(global_mouse_position: Vector2) -> bool:
	if sprite and sprite.texture:
		var local_mouse = sprite.to_local(global_mouse_position)
		if sprite.get_rect().has_point(local_mouse):
			return true
	return global_position.distance_to(global_mouse_position) <= 70.0


func repair() -> void:
	GameManager.set_cannon_unlocked(cannon_id, true)
	GameManager.set_cannon_current_ammo(cannon_id, GameManager.get_cannon_starting_ammo(cannon_id))
	cooldown = 0.0
	shots_in_cycle = 0
	_refresh_visibility_state()
