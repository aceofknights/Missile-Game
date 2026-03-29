extends Area2D

signal enemy_died

@export var speed: float = 180.0
@export var emp_disable_duration: float = 1.6
@export var trail_color: Color = Color.WHITE
@export var trail_width: float = 2.0
@export var trail_min_distance: float = 4.0

var velocity: Vector2 = Vector2.ZERO
var is_dying: bool = false
var trail_line: Line2D


func _ready() -> void:
	rotation = velocity.angle()
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	add_to_group("enemy")
	add_to_group("emp_missile")
	_create_trail()


func _physics_process(delta: float) -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, false)
	var global_multiplier := GameManager.get_enemy_global_speed_multiplier(now_seconds)
	position += velocity * speed * zone_multiplier * global_multiplier * delta
	rotation = velocity.angle()
	_update_trail()

	if position.y >= get_viewport_rect().size.y:
		die(true)


func _on_area_entered(area: Area2D) -> void:
	if area.name == "Projectile":
		die(false)
		area.queue_free()
		return

	if area.is_in_group("active_base_shield"):
		GameManager.apply_emp_to_shields(emp_disable_duration)
		die(true)
		return

	if area.is_in_group("defense_target") or area.is_in_group("cannon"):
		GameManager.apply_emp_to_shields(emp_disable_duration)
		if area.has_method("disable_temporarily"):
			area.disable_temporarily(emp_disable_duration)
		elif area.has_method("die"):
			area.call_deferred("die")
		die(true)


func die(no_reward := false) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	emit_signal("enemy_died")
	_cleanup_trail()
	queue_free()


func _exit_tree() -> void:
	_cleanup_trail()


func _create_trail() -> void:
	trail_line = Line2D.new()
	trail_line.default_color = trail_color
	trail_line.width = trail_width
	trail_line.z_as_relative = false
	trail_line.z_index = 1000
	trail_line.add_point(global_position)
	get_tree().current_scene.add_child(trail_line)


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
