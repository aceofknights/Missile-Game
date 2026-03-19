extends Area2D

signal clone_destroyed(clone: Area2D)

@export var missile_scene: PackedScene
@export var fire_interval: float = 3.5
@export var orbit_radius: float = 52.0
@export var orbit_speed: float = 1.8

@onready var fire_timer: Timer = get_node_or_null("FireTimer")

var orbit_center: Vector2 = Vector2.ZERO
var orbit_angle: float = 0.0
var orbit_enabled: bool = false
var firing_enabled: bool = false
var is_dying: bool = false


func _ready() -> void:
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	if fire_timer == null:
		push_error("Clone scene is missing FireTimer")
		return

	fire_timer.wait_time = fire_interval
	fire_timer.timeout.connect(_on_fire_timer_timeout)


func begin_clone_phase(center: Vector2, start_angle: float, can_fire: bool) -> void:
	orbit_center = center
	orbit_angle = start_angle
	orbit_enabled = true
	firing_enabled = can_fire

	if fire_timer == null:
		return

	if firing_enabled:
		fire_timer.start(randf_range(0.2, fire_interval))
	else:
		fire_timer.stop()


func set_firing_enabled(enabled: bool) -> void:
	firing_enabled = enabled

	if fire_timer == null:
		return

	if firing_enabled:
		fire_timer.start(randf_range(0.2, fire_interval))
	else:
		fire_timer.stop()


func _process(delta: float) -> void:
	if not orbit_enabled:
		return

	orbit_angle += orbit_speed * delta
	global_position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius


func _on_area_entered(area: Area2D) -> void:
	if is_dying:
		return

	if area.name == "Projectile":
		area.queue_free()
		_destroy_clone()
	elif area.name == "Explosion":
		_destroy_clone()
	elif area.is_in_group("defense_target"):
		if area.has_method("die"):
			area.call_deferred("die")
		else:
			area.queue_free()
		_destroy_clone()


func _destroy_clone() -> void:
	if is_dying:
		return

	is_dying = true
	emit_signal("clone_destroyed", self)
	queue_free()


func _on_fire_timer_timeout() -> void:
	if not firing_enabled:
		return
	_spawn_normal_missile()


func _spawn_normal_missile() -> void:
	if missile_scene == null:
		return

	var missile = missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport: Vector2 = get_viewport_rect().size
	var target: Vector2 = Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	missile.global_position = global_position + Vector2(0, 24)
	missile.velocity = (target - missile.global_position).normalized()
	get_tree().current_scene.add_child(missile)
