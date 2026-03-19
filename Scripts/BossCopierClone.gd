extends Area2D

signal clone_destroyed(clone: Area2D)

@export var missile_scene: PackedScene
@export var fire_interval: float = 1.5
@export var orbit_radius: float = 52.0
@export var orbit_speed: float = 1.8

@onready var fire_timer: Timer = $FireTimer

var orbit_center := Vector2.ZERO
var orbit_angle := 0.0
var orbit_enabled := false
var firing_enabled := false


func _ready() -> void:
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	fire_timer.wait_time = fire_interval
	fire_timer.timeout.connect(_on_fire_timer_timeout)


func begin_clone_phase(center: Vector2, start_angle: float, can_fire: bool) -> void:
	orbit_center = center
	orbit_angle = start_angle
	orbit_enabled = true
	firing_enabled = can_fire
	if firing_enabled:
		fire_timer.start(randf_range(0.2, fire_interval))
	else:
		fire_timer.stop()


func set_firing_enabled(enabled: bool) -> void:
	firing_enabled = enabled
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
	if area.name != "Projectile":
		return
	area.queue_free()
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

	var viewport = get_viewport_rect().size
	var target := Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	missile.global_position = global_position + Vector2(0, 24)
	missile.velocity = (target - missile.global_position).normalized()
	get_tree().current_scene.add_child(missile)
