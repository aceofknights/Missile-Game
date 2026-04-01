extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 360
@export var trail_color: Color = Color.WHITE
@export var trail_width: float = 2.0
@export var trail_min_distance: float = 4.0

@export var neon_outer_alpha: float = 0.2
@export var neon_outer_width_multiplier: float = 6
@export var neon_mid_alpha: float = 0.3
@export var neon_mid_width_multiplier: float = 3
@export var neon_core_alpha: float = 1.0

const WORLD_1_PROJECTILE_COLOR := Color(0.15, 0.45, 0.35, 1.0) # dark teal-green
const WORLD_2_PROJECTILE_COLOR := Color(0.45, 0.22, 0.18, 1.0) # dark rust
const WORLD_3_PROJECTILE_COLOR := Color(0.28, 0.18, 0.45, 1.0) # dark purple
const WORLD_4_PROJECTILE_COLOR := Color(0.18, 0.28, 0.42, 1.0) # dark blue
const WORLD_5_PROJECTILE_COLOR := Color(0.32, 0.45, 0.18, 1.0) # toxic green
const DEFAULT_PROJECTILE_COLOR := Color(0.35, 0.35, 0.35, 1.0)

var target: Vector2
var trail_outer_line: Line2D
var trail_mid_line: Line2D
var trail_core_line: Line2D

var _last_neon_outer_alpha: float = -1.0
var _last_neon_outer_width_multiplier: float = -1.0
var _last_neon_mid_alpha: float = -1.0
var _last_neon_mid_width_multiplier: float = -1.0
var _last_neon_core_alpha: float = -1.0
var _last_trail_width: float = -1.0

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	speed *= GameManager.get_missile_speed_multiplier()
	look_at(target)
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("projectile")
	_apply_world_color()
	_cache_current_neon_values()
	_create_trail()


func _process(delta: float) -> void:
	var direction := target - global_position
	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, true)
	var step := speed * zone_multiplier * delta

	if direction.length() < step:
		explode()
	else:
		position += direction.normalized() * step

	_refresh_trail_visuals_if_needed()
	_update_trail()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy"):
		explode()


func explode() -> void:
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)

	_cleanup_trail()
	queue_free()


func _exit_tree() -> void:
	_cleanup_trail()


func _create_trail() -> void:
	_sanitize_neon_values()

	var world_color := _get_world_projectile_color()
	var outer_color := Color(world_color.r, world_color.g, world_color.b, neon_outer_alpha)
	var mid_color := Color(world_color.r, world_color.g, world_color.b, neon_mid_alpha)
	var core_color := Color(world_color.r, world_color.g, world_color.b, neon_core_alpha)

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


func _apply_world_color() -> void:
	var world_color := _get_world_projectile_color()
	if sprite:
		sprite.modulate = world_color


func _get_world_projectile_color() -> Color:
	match GameManager.current_world:
		1:
			return WORLD_1_PROJECTILE_COLOR
		2:
			return WORLD_2_PROJECTILE_COLOR
		3:
			return WORLD_3_PROJECTILE_COLOR
		4:
			return WORLD_4_PROJECTILE_COLOR
		5:
			return WORLD_5_PROJECTILE_COLOR
		_:
			return DEFAULT_PROJECTILE_COLOR


func _refresh_trail_visuals_if_needed() -> void:
	_sanitize_neon_values()

	if not _neon_values_changed():
		return

	_refresh_trail_visuals()
	_cache_current_neon_values()


func _refresh_trail_visuals() -> void:
	var world_color := _get_world_projectile_color()
	var outer_color := Color(world_color.r, world_color.g, world_color.b, neon_outer_alpha)
	var mid_color := Color(world_color.r, world_color.g, world_color.b, neon_mid_alpha)
	var core_color := Color(world_color.r, world_color.g, world_color.b, neon_core_alpha)

	if trail_outer_line:
		trail_outer_line.default_color = outer_color
		trail_outer_line.width = trail_width * neon_outer_width_multiplier

	if trail_mid_line:
		trail_mid_line.default_color = mid_color
		trail_mid_line.width = trail_width * neon_mid_width_multiplier

	if trail_core_line:
		trail_core_line.default_color = core_color
		trail_core_line.width = trail_width

	if sprite:
		sprite.modulate = world_color


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
