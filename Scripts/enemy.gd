extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 100.0
@export var trail_color: Color = Color.WHITE
@export var trail_width: float = 2.0
@export var trail_min_distance: float = 4.0
@export var offscreen_despawn_margin: float = 64.0

@export var neon_outer_alpha: float = 0.2
@export var neon_outer_width_multiplier: float = 6.0
@export var neon_mid_alpha: float = 0.3
@export var neon_mid_width_multiplier: float = 3.0
@export var neon_core_alpha: float = 1.0

signal enemy_died

var velocity := Vector2.ZERO
var is_dying := false
var lure_curve_time_remaining := 3.0

var trail_outer_line: Line2D
var trail_mid_line: Line2D
var trail_core_line: Line2D

var _last_neon_outer_alpha: float = -1.0
var _last_neon_outer_width_multiplier: float = -1.0
var _last_neon_mid_alpha: float = -1.0
var _last_neon_mid_width_multiplier: float = -1.0
var _last_neon_core_alpha: float = -1.0
var _last_trail_width: float = -1.0


func _ready() -> void:
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("enemy")
	add_to_group("normal_enemy_missile")

	monitoring = true
	monitorable = true

	# Make sure this missile checks layer 5 too.
	collision_mask |= (1 << 4)

	_cache_current_neon_values()
	_create_trail()


func _process(delta: float) -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	if GameManager.is_lure_active(now_seconds) and lure_curve_time_remaining > 0.0:
		var to_lure := (GameManager.lure_position - global_position).normalized()
		velocity = velocity.lerp(to_lure, minf(1.0, 4.0 * delta)).normalized()
		lure_curve_time_remaining = maxf(0.0, lure_curve_time_remaining - delta)

	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, false)
	var global_multiplier := GameManager.get_enemy_global_speed_multiplier(now_seconds)
	position += velocity * speed * zone_multiplier * global_multiplier * delta
	rotation = velocity.angle()

	_refresh_trail_visuals_if_needed()
	_update_trail()
	_despawn_if_out_of_bounds()

	if position.y >= get_viewport_rect().size.y:
		die(true)


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("ground_killzone"):
		die(true, true)
		return
	if area.is_in_group("active_base_shield"):
		die(true)
		return

	if area.has_method("handle_enemy_impact"):
		var blocked = area.handle_enemy_impact(self)
		if blocked:
			return

	if area.name == "Projectile":
		die(false)
		area.queue_free()
	elif area.is_in_group("defense_target"):
		if area.has_method("die"):
			area.call_deferred("die")
		else:
			area.queue_free()
		die(true)


func die(no_reward := false, spawn_explosion := true) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	emit_signal("enemy_died")

	if spawn_explosion and explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = not no_reward
		get_tree().current_scene.add_child(explosion)

	_cleanup_trail()
	queue_free()


func _exit_tree() -> void:
	_cleanup_trail()


func _create_trail() -> void:
	_sanitize_neon_values()

	var outer_color := Color(trail_color.r, trail_color.g, trail_color.b, neon_outer_alpha)
	var mid_color := Color(trail_color.r, trail_color.g, trail_color.b, neon_mid_alpha)
	var core_color := Color(trail_color.r, trail_color.g, trail_color.b, neon_core_alpha)

	trail_outer_line = Line2D.new()
	trail_outer_line.default_color = outer_color
	trail_outer_line.width = trail_width * neon_outer_width_multiplier
	trail_outer_line.z_as_relative = false
	trail_outer_line.z_index = 998
	_apply_line_style(trail_outer_line)
	trail_outer_line.add_point(global_position)
	get_tree().current_scene.add_child(trail_outer_line)

	trail_mid_line = Line2D.new()
	trail_mid_line.default_color = mid_color
	trail_mid_line.width = trail_width * neon_mid_width_multiplier
	trail_mid_line.z_as_relative = false
	trail_mid_line.z_index = 999
	_apply_line_style(trail_mid_line)
	trail_mid_line.add_point(global_position)
	get_tree().current_scene.add_child(trail_mid_line)

	trail_core_line = Line2D.new()
	trail_core_line.default_color = core_color
	trail_core_line.width = trail_width
	trail_core_line.z_as_relative = false
	trail_core_line.z_index = 1000
	_apply_line_style(trail_core_line)
	trail_core_line.add_point(global_position)
	get_tree().current_scene.add_child(trail_core_line)


func _apply_line_style(line: Line2D) -> void:
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND


func _update_trail() -> void:
	if trail_core_line == null or trail_mid_line == null or trail_outer_line == null:
		return

	var point_count := trail_core_line.get_point_count()
	if point_count == 0:
		trail_core_line.add_point(global_position)
		trail_mid_line.add_point(global_position)
		trail_outer_line.add_point(global_position)
		return

	var last_point := trail_core_line.get_point_position(point_count - 1)
	if last_point.distance_to(global_position) >= trail_min_distance:
		trail_core_line.add_point(global_position)
		trail_mid_line.add_point(global_position)
		trail_outer_line.add_point(global_position)


func _cleanup_trail() -> void:
	if is_instance_valid(trail_core_line):
		trail_core_line.queue_free()
	if is_instance_valid(trail_mid_line):
		trail_mid_line.queue_free()
	if is_instance_valid(trail_outer_line):
		trail_outer_line.queue_free()

	trail_core_line = null
	trail_mid_line = null
	trail_outer_line = null


func _refresh_trail_visuals_if_needed() -> void:
	_sanitize_neon_values()

	if not _neon_values_changed():
		return

	_refresh_trail_visuals()
	_cache_current_neon_values()


func _refresh_trail_visuals() -> void:
	var outer_color := Color(trail_color.r, trail_color.g, trail_color.b, neon_outer_alpha)
	var mid_color := Color(trail_color.r, trail_color.g, trail_color.b, neon_mid_alpha)
	var core_color := Color(trail_color.r, trail_color.g, trail_color.b, neon_core_alpha)

	if trail_outer_line:
		trail_outer_line.default_color = outer_color
		trail_outer_line.width = trail_width * neon_outer_width_multiplier

	if trail_mid_line:
		trail_mid_line.default_color = mid_color
		trail_mid_line.width = trail_width * neon_mid_width_multiplier

	if trail_core_line:
		trail_core_line.default_color = core_color
		trail_core_line.width = trail_width


func _sanitize_neon_values() -> void:
	trail_width = clampf(trail_width, 0.5, 12.0)
	trail_min_distance = clampf(trail_min_distance, 1.0, 64.0)

	neon_outer_alpha = clampf(neon_outer_alpha, 0.0, 1.0)
	neon_outer_width_multiplier = clampf(neon_outer_width_multiplier, 1.0, 12.0)
	neon_mid_alpha = clampf(neon_mid_alpha, 0.0, 1.0)
	neon_mid_width_multiplier = clampf(neon_mid_width_multiplier, 1.0, 12.0)
	neon_core_alpha = clampf(neon_core_alpha, 0.0, 1.0)


func _neon_values_changed() -> bool:
	return (
		_last_neon_outer_alpha != neon_outer_alpha
		or _last_neon_outer_width_multiplier != neon_outer_width_multiplier
		or _last_neon_mid_alpha != neon_mid_alpha
		or _last_neon_mid_width_multiplier != neon_mid_width_multiplier
		or _last_neon_core_alpha != neon_core_alpha
		or _last_trail_width != trail_width
	)


func _cache_current_neon_values() -> void:
	_last_neon_outer_alpha = neon_outer_alpha
	_last_neon_outer_width_multiplier = neon_outer_width_multiplier
	_last_neon_mid_alpha = neon_mid_alpha
	_last_neon_mid_width_multiplier = neon_mid_width_multiplier
	_last_neon_core_alpha = neon_core_alpha
	_last_trail_width = trail_width


func _despawn_if_out_of_bounds() -> void:
	var viewport_size := get_viewport_rect().size
	if global_position.x < -offscreen_despawn_margin:
		die(true, false)
		return
	if global_position.x > viewport_size.x + offscreen_despawn_margin:
		die(true, false)
		return
	if global_position.y < -offscreen_despawn_margin:
		die(true, false)
