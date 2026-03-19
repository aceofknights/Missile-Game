extends Area2D

signal enemy_died

@export var speed: float = 165.0
@export var ion_zone_scene: PackedScene
@export var ion_zone_duration: float = 5.0
@export var ion_zone_radius: float = 120.0
@export var explode_height_ratio_min: float = 0.45
@export var explode_height_ratio_max: float = 0.65

var velocity: Vector2 = Vector2.ZERO
var is_dying := false
var trigger_y: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("ion_missile")
	rotation = velocity.angle()
	area_entered.connect(_on_area_entered)

	var viewport_height := get_viewport_rect().size.y
	var min_y := viewport_height * minf(explode_height_ratio_min, explode_height_ratio_max)
	var max_y := viewport_height * maxf(explode_height_ratio_min, explode_height_ratio_max)
	trigger_y = randf_range(min_y, max_y)


func _physics_process(delta: float) -> void:
	if is_dying:
		return

	var speed_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, false)
	position += velocity * speed * speed_multiplier * delta

	if global_position.y >= trigger_y:
		_detonate(true)


func _on_area_entered(area: Area2D) -> void:
	if is_dying:
		return
	if area.name == "Projectile":
		area.queue_free()
		_detonate(false)
	elif area.is_in_group("defense_target"):
		if area.has_method("die"):
			area.call_deferred("die")
		_detonate(true)


func _detonate(no_reward: bool) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	_spawn_ion_zone_if_possible()
	emit_signal("enemy_died")
	queue_free()


func _spawn_ion_zone_if_possible() -> void:
	if ion_zone_scene == null:
		return
	if not IonHazardController.can_spawn_zone():
		return

	var zone = ion_zone_scene.instantiate()
	zone.global_position = global_position
	zone.duration = ion_zone_duration
	zone.radius = ion_zone_radius
	get_tree().current_scene.add_child(zone)
