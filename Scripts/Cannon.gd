extends Area2D

@export var projectile_scene: PackedScene
@export var cannon_id := GameManager.CANNON_MIDDLE
@export var fire_rate := 0.5

const WORLD_1_CANNON_COLOR := Color(0.15, 0.45, 0.35, 1.0) # dark teal-green
const WORLD_2_CANNON_COLOR := Color(0.45, 0.22, 0.18, 1.0) # dark rust
const WORLD_3_CANNON_COLOR := Color(0.28, 0.18, 0.45, 1.0) # dark purple
const WORLD_4_CANNON_COLOR := Color(0.18, 0.28, 0.42, 1.0) # dark blue
const WORLD_5_CANNON_COLOR := Color(0.32, 0.45, 0.18, 1.0) # toxic green
const DEFAULT_CANNON_COLOR := Color(0.35, 0.35, 0.35, 1.0)

var cooldown := 0.0
var shots_in_cycle := 0
var emp_disabled_remaining := 0.0
var jam_end_time: float = 0.0
var jam_misfire_radius: float = 0.0
var permanently_destroyed: bool = false
var shield_hits_remaining := 0

@onready var muzzle: Marker2D = get_node_or_null("CannonGun/Muzzle") as Marker2D
@onready var ammo_label: Label = $AmmoLabel
@onready var fire_rate_bar: ProgressBar = $FireRateBar
@onready var repair_label: Label = get_node_or_null("RepairLabel") as Label
@onready var cannon_gun: Sprite2D = get_node_or_null("CannonGun") as Sprite2D
@onready var cannon_base: Sprite2D = get_node_or_null("CannonBase") as Sprite2D
@onready var cannon_destroyed: Sprite2D = get_node_or_null("CannonDestroyed") as Sprite2D
@onready var shield_sprite: Sprite2D = Sprite2D.new()
@onready var shield_hits_label: Label = Label.new()


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

	_setup_cannon_gun_pivot()
	_setup_temp_shield_sprite()
	_setup_shield_hits_label()
	_reset_passive_shield_for_wave()
	_refresh_visibility_state()
	_update_overlay_positions()
	_update_ui()

	print(name, " monitoring=", monitoring, " monitorable=", monitorable)
	print(name, " layer=", collision_layer, " mask=", collision_mask)
	print(name, " groups=", get_groups())


func _process(delta: float) -> void:
	if emp_disabled_remaining > 0.0:
		emp_disabled_remaining = maxf(0.0, emp_disabled_remaining - delta)

	if _can_operate():
		_rotate_gun_to_mouse()
		if cooldown > 0.0:
			cooldown = maxf(0.0, cooldown - delta)

	_update_overlay_positions()
	_update_shield_state()
	_update_shield_hits_label()
	_update_ui()
	_refresh_visibility_state()


func _can_operate() -> bool:
	return GameManager.is_cannon_unlocked(cannon_id) and not GameManager.is_cannon_destroyed(cannon_id)


func _refresh_visibility_state() -> void:
	var unlocked: bool = GameManager.is_cannon_unlocked(cannon_id)
	var destroyed: bool = GameManager.is_cannon_destroyed(cannon_id)
	var active: bool = unlocked and not destroyed
	var jammed: bool = is_targeting_jammed()
	var world_color: Color = _get_world_cannon_color()

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

	if cannon_base:
		cannon_base.visible = active
		if destroyed:
			cannon_base.modulate = Color(0.35, 0.35, 0.35, 1.0)
		elif emp_disabled_remaining > 0.0:
			cannon_base.modulate = Color(0.55, 0.9, 1.0, 1.0)
		elif jammed:
			cannon_base.modulate = Color(0.8, 1.0, 1.0, 1.0)
		else:
			cannon_base.modulate = world_color

	if cannon_gun:
		cannon_gun.visible = active
		if destroyed:
			cannon_gun.modulate = Color(0.35, 0.35, 0.35, 1.0)
		elif emp_disabled_remaining > 0.0:
			cannon_gun.modulate = Color(0.55, 0.9, 1.0, 1.0)
		elif jammed:
			cannon_gun.modulate = Color(0.8, 1.0, 1.0, 1.0)
		else:
			cannon_gun.modulate = world_color

	if cannon_destroyed:
		cannon_destroyed.visible = unlocked and destroyed
		cannon_destroyed.modulate = world_color

	if shield_sprite:
		shield_sprite.visible = active and shield_hits_remaining > 0 and not _is_passive_shield_blocked_by_emp()


func _update_ui() -> void:
	if ammo_label:
		ammo_label.text = "%d/%d" % [
			GameManager.get_cannon_current_ammo(cannon_id),
			GameManager.get_cannon_max_ammo(cannon_id)
		]

	if fire_rate_bar:
		var delay: float = maxf(0.001, GameManager.get_cannon_fire_rate(cannon_id, fire_rate))
		fire_rate_bar.max_value = delay
		fire_rate_bar.value = delay - minf(delay, cooldown)


func _update_overlay_positions() -> void:
	ammo_label.global_position = global_position + Vector2(-45, 14)
	fire_rate_bar.global_position = global_position + Vector2(-45, 35)
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

	var final_target: Vector2 = _apply_jam_to_target(target_position)

	var projectile = projectile_scene.instantiate()
	projectile.global_position = muzzle.global_position if muzzle else global_position
	projectile.target = final_target
	get_tree().current_scene.add_child(projectile)

	_update_ui()
	return true


func _apply_jam_to_target(target_position: Vector2) -> Vector2:
	if not is_targeting_jammed():
		return target_position

	var angle: float = randf() * TAU
	var distance: float = sqrt(randf()) * jam_misfire_radius
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
	var jammed_target: Vector2 = target_position + offset

	print("🌀 Jammed shot from %s to %s (radius %.1f)" % [target_position, jammed_target, jam_misfire_radius])

	return jammed_target


func apply_targeting_jam(duration: float, radius: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	jam_end_time = maxf(jam_end_time, now + maxf(0.1, duration))
	jam_misfire_radius = maxf(jam_misfire_radius, radius)
	_refresh_visibility_state()
	print("🌀 Cannon jammed for %.2fs with radius %.1f" % [duration, radius])


func is_targeting_jammed() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return now < jam_end_time


func clear_targeting_jam() -> void:
	jam_end_time = 0.0
	jam_misfire_radius = 0.0
	_refresh_visibility_state()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy") and not area.is_in_group("emp_missile"):
		if handle_enemy_impact(area):
			return
		GameManager.destroy_cannon(cannon_id)
		_refresh_visibility_state()


func _setup_temp_shield_sprite() -> void:
	shield_sprite.texture = preload("res://assets/ShieldUfo.png")
	shield_sprite.modulate = Color(0.4, 0.95, 1.0, 0.35)
	shield_sprite.scale = Vector2(0.13, 0.1)
	shield_sprite.visible = false
	add_child(shield_sprite)


func _setup_shield_hits_label() -> void:
	shield_hits_label.top_level = true
	shield_hits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shield_hits_label.add_theme_color_override("font_color", Color(0.9, 1.0, 1.0, 1.0))
	shield_hits_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	shield_hits_label.add_theme_constant_override("outline_size", 2)
	shield_hits_label.visible = false
	shield_hits_label.z_index = 25
	add_child(shield_hits_label)


func _update_shield_hits_label() -> void:
	if shield_hits_label == null:
		return

	shield_hits_label.global_position = global_position + Vector2(-5, 0)

	var max_hits := GameManager.get_shield_generator_hit_capacity()
	var show := max_hits > 0 and _can_operate()
	shield_hits_label.visible = show
	if not show:
		return

	if _is_passive_shield_blocked_by_emp():
		shield_hits_label.text = "EMP"
	else:
		shield_hits_label.text = "%d" % max(0, shield_hits_remaining)


func _update_shield_state() -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()
	if max_hits <= 0 or not _can_operate():
		shield_hits_remaining = 0
		return

	if shield_hits_remaining < 0:
		shield_hits_remaining = 0
	elif shield_hits_remaining > max_hits:
		shield_hits_remaining = max_hits


func _reset_passive_shield_for_wave() -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()
	if max_hits > 0 and _can_operate():
		shield_hits_remaining = max_hits
	else:
		shield_hits_remaining = 0


func _is_passive_shield_blocked_by_emp() -> bool:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	return GameManager.is_passive_shield_emp_disabled(now_seconds)


func handle_enemy_impact(enemy: Area2D) -> bool:
	if _is_passive_shield_blocked_by_emp():
		return false

	_update_shield_state()
	if shield_hits_remaining > 0:
		shield_hits_remaining -= 1
		shield_hits_remaining = max(0, shield_hits_remaining)
		if enemy:
			enemy.call_deferred("die", true)
		return true
	return false


func disable_temporarily(duration: float) -> void:
	emp_disabled_remaining = maxf(emp_disabled_remaining, maxf(0.1, duration))
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
	var hover_sprite: Sprite2D = cannon_destroyed if is_destroyed() and cannon_destroyed else cannon_base
	if hover_sprite and hover_sprite.texture:
		var local_mouse: Vector2 = hover_sprite.to_local(global_mouse_position)
		if hover_sprite.get_rect().has_point(local_mouse):
			return true
	return global_position.distance_to(global_mouse_position) <= 70.0


func repair() -> void:
	if permanently_destroyed:
		return
	GameManager.set_cannon_unlocked(cannon_id, true)
	GameManager.set_cannon_current_ammo(cannon_id, GameManager.get_cannon_starting_ammo(cannon_id))
	cooldown = 0.0
	shots_in_cycle = 0
	emp_disabled_remaining = 0.0
	clear_targeting_jam()
	_reset_passive_shield_for_wave()
	_refresh_visibility_state()


func destroy_permanently() -> void:
	permanently_destroyed = true
	die()
	if is_instance_valid(cannon_base):
		cannon_base.queue_free()
	if is_instance_valid(cannon_gun):
		cannon_gun.queue_free()
	if is_instance_valid(cannon_destroyed):
		cannon_destroyed.queue_free()


func _rotate_gun_to_mouse() -> void:
	if cannon_gun == null:
		return

	var target_angle := global_position.angle_to_point(get_global_mouse_position())
	cannon_gun.global_rotation = target_angle + deg_to_rad(90.0)


func _setup_cannon_gun_pivot() -> void:
	if cannon_gun == null or cannon_gun.texture == null:
		return

	cannon_gun.centered = false
	var tex_size: Vector2 = cannon_gun.texture.get_size()

	# Places the texture so the node origin is at the bottom-center of the gun.
	cannon_gun.offset = Vector2(-tex_size.x * 0.5, -tex_size.y)


func _get_world_cannon_color() -> Color:
	match GameManager.current_world:
		1:
			return WORLD_1_CANNON_COLOR
		2:
			return WORLD_2_CANNON_COLOR
		3:
			return WORLD_3_CANNON_COLOR
		4:
			return WORLD_4_CANNON_COLOR
		5:
			return WORLD_5_CANNON_COLOR
		_:
			return DEFAULT_CANNON_COLOR
