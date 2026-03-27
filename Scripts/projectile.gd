extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 360
@export var trail_color: Color = Color.WHITE
@export var trail_width: float = 2.0
@export var trail_min_distance: float = 4.0
var target: Vector2
var trail_line: Line2D


func _ready() -> void:
	speed *= GameManager.get_missile_speed_multiplier()
	look_at(target)
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("projectile")
	_create_trail()


func _process(delta: float) -> void:
	var direction := target - global_position
	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, true)
	var step := speed * zone_multiplier * delta

	if direction.length() < step:
		explode()
	else:
		position += direction.normalized() * step
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
