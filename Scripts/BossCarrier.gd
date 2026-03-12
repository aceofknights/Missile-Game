extends Area2D

signal enemy_died
signal boss_defeated

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var plane_scene: PackedScene
@export var move_speed := 90.0
@export var max_health := 5
@export var immunity_duration := 2.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var boss_health_label: Label = $boss_health
@onready var fighter_spawn_timer: Timer = $FighterSpawnTimer
@onready var bomber_spawn_timer: Timer = $BomberSpawnTimer
@onready var immunity_timer: Timer = $ImmunityTimer

var health := 5
var phase := 1
var move_direction := 1.0
var is_immune := false
var is_dead := false
var fighters: Array[Area2D] = []
var bombers: Array[Area2D] = []

const PHASE_MAX_UNITS := {
	1: 3,
	2: 5,
	3: 7
}

const PHASE_FIGHTER_SPAWN := {
	1: 3.0,
	2: 1.8,
	3: 1.0
}

const PHASE_BOMBER_SPAWN := {
	1: 3.2,
	2: 2.0,
	3: 1.1
}


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	connect("area_entered", Callable(self, "_on_area_entered"))

	fighter_spawn_timer.timeout.connect(_on_fighter_spawn_timer_timeout)
	bomber_spawn_timer.timeout.connect(_on_bomber_spawn_timer_timeout)
	immunity_timer.timeout.connect(_on_immunity_timeout)

	_update_phase_state()
	_update_visuals()
	_update_label()


func _process(delta: float) -> void:
	if is_dead:
		return

	var viewport = get_viewport_rect().size
	position.x += move_direction * move_speed * delta

	if position.x < 160.0:
		position.x = 160.0
		move_direction = 1.0
	elif position.x > viewport.x - 160.0:
		position.x = viewport.x - 160.0
		move_direction = -1.0

	_update_label()


func _on_area_entered(area: Area2D) -> void:
	if area.name != "Projectile":
		return
	area.queue_free()
	die(false)


func die(no_reward := false) -> void:
	if is_dead:
		return
	if is_immune:
		return

	health -= 1
	if health <= 0:
		_die_for_real(no_reward)
		return

	_reset_fighter_accuracy()
	_start_immunity_window()
	_update_phase_state()
	_update_visuals()
	_update_label()


func _die_for_real(no_reward := false) -> void:
	if is_dead:
		return
	is_dead = true

	fighter_spawn_timer.stop()
	bomber_spawn_timer.stop()
	immunity_timer.stop()

	for fighter in fighters:
		if is_instance_valid(fighter):
			fighter.queue_free()
	for bomber in bombers:
		if is_instance_valid(bomber):
			bomber.queue_free()
	fighters.clear()
	bombers.clear()

	if not no_reward:
		GameManager.add_resources(15)

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		get_tree().current_scene.add_child(explosion)

	emit_signal("boss_defeated")
	emit_signal("enemy_died")
	queue_free()


func _start_immunity_window() -> void:
	is_immune = true
	immunity_timer.wait_time = immunity_duration
	immunity_timer.start()


func _on_immunity_timeout() -> void:
	is_immune = false
	_update_visuals()


func _update_phase_state() -> void:
	if health <= 1:
		phase = 3
	elif health <= 3:
		phase = 2
	else:
		phase = 1

	fighter_spawn_timer.wait_time = PHASE_FIGHTER_SPAWN[phase]
	bomber_spawn_timer.wait_time = PHASE_BOMBER_SPAWN[phase]

	if fighter_spawn_timer.is_stopped():
		fighter_spawn_timer.start()
	if bomber_spawn_timer.is_stopped():
		bomber_spawn_timer.start()

	var speed_boost = 1.35 if phase == 3 else 1.0
	for fighter in fighters:
		if is_instance_valid(fighter):
			fighter.set_speed_multiplier(speed_boost)
	for bomber in bombers:
		if is_instance_valid(bomber):
			bomber.set_speed_multiplier(speed_boost)


func _on_fighter_spawn_timer_timeout() -> void:
	_prune_units()
	if fighters.size() >= PHASE_MAX_UNITS[phase]:
		return
	var fighter = _spawn_plane("fighter")
	if fighter != null:
		fighters.append(fighter)


func _on_bomber_spawn_timer_timeout() -> void:
	_prune_units()
	if bombers.size() >= PHASE_MAX_UNITS[phase]:
		return
	var bomber = _spawn_plane("bomber")
	if bomber != null:
		bombers.append(bomber)


func _spawn_plane(role: String) -> Area2D:
	if plane_scene == null:
		return null
	var plane = plane_scene.instantiate()
	plane.role = role
	plane.missile_scene = missile_scene
	plane.explosion_scene = explosion_scene
	plane.global_position = global_position + Vector2(randf_range(-180.0, 180.0), randf_range(-30.0, 40.0))
	plane.direction = Vector2(sign(randf() - 0.5), randf_range(-0.3, 0.3)).normalized()
	plane.plane_removed.connect(_on_plane_removed)
	if phase == 3:
		plane.set_speed_multiplier(1.35)
	get_tree().current_scene.add_child(plane)
	return plane


func _on_plane_removed(plane: Area2D) -> void:
	fighters.erase(plane)
	bombers.erase(plane)


func _prune_units() -> void:
	fighters = fighters.filter(func(p): return is_instance_valid(p))
	bombers = bombers.filter(func(p): return is_instance_valid(p))


func _reset_fighter_accuracy() -> void:
	for fighter in fighters:
		if is_instance_valid(fighter):
			fighter.reset_accuracy()


func _update_label() -> void:
	boss_health_label.text = "Carrier HP %d  P%d" % [health, phase]


func _update_visuals() -> void:
	if is_immune:
		sprite.modulate = Color(0.65, 0.82, 1.0, 1.0)
	else:
		sprite.modulate = Color(1.0, 0.6, 0.35, 1.0)
