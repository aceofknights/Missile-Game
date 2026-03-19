extends Area2D

signal clone_destroyed(clone: Area2D)

@export var missile_scene: PackedScene
@export var ion_missile_scene: PackedScene
@export var normal_fire_interval: float = 1.45
@export var ion_fire_interval: float = 3.6

@onready var normal_timer: Timer = $NormalFireTimer
@onready var ion_timer: Timer = $IonFireTimer

var attack_enabled := false


func _ready() -> void:
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	normal_timer.one_shot = false
	normal_timer.wait_time = normal_fire_interval
	normal_timer.timeout.connect(_on_normal_fire_timeout)

	ion_timer.one_shot = false
	ion_timer.wait_time = ion_fire_interval
	ion_timer.timeout.connect(_on_ion_fire_timeout)


func begin_attack_phase() -> void:
	if attack_enabled:
		return
	attack_enabled = true
	normal_timer.start(randf_range(0.2, normal_fire_interval))
	ion_timer.start(randf_range(0.6, ion_fire_interval))


func stop_attack_phase() -> void:
	attack_enabled = false
	normal_timer.stop()
	ion_timer.stop()


func _on_area_entered(area: Area2D) -> void:
	if area.name != "Projectile":
		return
	area.queue_free()
	_destroy_clone()


func _on_normal_fire_timeout() -> void:
	if not attack_enabled:
		return
	_spawn_missile(missile_scene)


func _on_ion_fire_timeout() -> void:
	if not attack_enabled:
		return
	_spawn_missile(ion_missile_scene)


func _spawn_missile(scene: PackedScene) -> void:
	if scene == null:
		return

	var missile = scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport = get_viewport_rect().size
	var target := Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	missile.global_position = global_position + Vector2(0, 24)
	missile.velocity = (target - missile.global_position).normalized()
	get_tree().current_scene.add_child(missile)


func _destroy_clone() -> void:
	stop_attack_phase()
	emit_signal("clone_destroyed", self)
	queue_free()
