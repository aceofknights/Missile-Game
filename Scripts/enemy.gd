extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 100.0
@export var trail_color: Color = Color.WHITE
@export var trail_width: float = 2.0
@export var trail_min_distance: float = 4.0

signal enemy_died

var velocity := Vector2.ZERO
var is_dying := false
var trail_line: Line2D
var lure_curve_time_remaining := 3.0


func _ready() -> void:
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("enemy")
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
	_update_trail()

	if position.y >= get_viewport_rect().size.y:
		die(true)


func _on_area_entered(area: Area2D) -> void:
	if GameManager.is_active_shield_up():
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


func die(no_reward := false) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	emit_signal("enemy_died")

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = not no_reward
		get_tree().current_scene.add_child(explosion)

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
