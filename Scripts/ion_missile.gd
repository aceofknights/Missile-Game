extends Area2D

signal enemy_died

@export var speed: float = 165.0
@export var trail_color: Color = Color.WHITE
@export var trail_width: float = 2.0
@export var trail_min_distance: float = 4.0
@export var ion_zone_scene: PackedScene
@export var ion_zone_duration: float = 5.0
@export var ion_zone_radius: float = 120.0
@export var max_active_zones: int = 1
@export var zone_player_projectile_speed_multiplier: float = 0.55
@export var zone_enemy_missile_speed_multiplier: float = 1.4
@export var explode_height_ratio_min: float = 0.45
@export var explode_height_ratio_max: float = 0.65

var velocity: Vector2 = Vector2.ZERO
var is_dying := false
var trigger_y: float = 0.0
var trail_line: Line2D


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("ion_missile")
	rotation = velocity.angle()
	area_entered.connect(_on_area_entered)
	_create_trail()

	var viewport_height := get_viewport_rect().size.y
	var min_y := viewport_height * minf(explode_height_ratio_min, explode_height_ratio_max)
	var max_y := viewport_height * maxf(explode_height_ratio_min, explode_height_ratio_max)
	trigger_y = randf_range(min_y, max_y)


func _physics_process(delta: float) -> void:
	if is_dying:
		return

	var speed_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, false)
	position += velocity * speed * speed_multiplier * delta
	_update_trail()

	if global_position.y >= trigger_y:
		_detonate(true, true)


func _on_area_entered(area: Area2D) -> void:
	if is_dying:
		return

	if area.name == "Projectile":
		area.queue_free()
		_detonate(false, false)
	elif area.name == "Explosion":
		_detonate(false, false)
	elif area.is_in_group("defense_target"):
		if area.has_method("die"):
			area.call_deferred("die")
		_detonate(true, true)


func _detonate(no_reward: bool, spawn_zone: bool) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	if spawn_zone:
		_spawn_ion_zone_if_possible()

	emit_signal("enemy_died")
	_cleanup_trail()
	queue_free()


func _spawn_ion_zone_if_possible() -> void:
	if ion_zone_scene == null:
		return
	if not IonHazardController.can_spawn_zone(max_active_zones):
		return

	var zone = ion_zone_scene.instantiate()
	zone.global_position = global_position
	zone.duration = ion_zone_duration
	zone.radius = ion_zone_radius
	zone.player_projectile_speed_multiplier = zone_player_projectile_speed_multiplier
	zone.enemy_missile_speed_multiplier = zone_enemy_missile_speed_multiplier
	get_tree().current_scene.add_child(zone)


func _exit_tree() -> void:
	_cleanup_trail()


func _create_trail() -> void:
	trail_line = Line2D.new()
	trail_line.default_color = trail_color
	trail_line.width = trail_width
	trail_line.z_index = -1
	trail_line.add_point(global_position)
	get_tree().current_scene.add_child.call_deferred(trail_line)


func _update_trail() -> void:
	if trail_line == null:
		return
	var point_count := trail_line.get_point_count()
	if point_count == 0:
		trail_line.add_point(global_position)
		return
	var last_point := trail_line.get_point_position(point_count - 1)
	if last_point.distance_to(global_position) >= trail_min_distance:
		trail_line.add_point(global_position)


func _cleanup_trail() -> void:
	if is_instance_valid(trail_line):
		trail_line.queue_free()
	trail_line = null
