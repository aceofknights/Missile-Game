extends Area2D

signal enemy_died
signal boss_defeated

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var ion_missile_scene: PackedScene
@export var clone_scene: PackedScene

@export var max_health := 5
@export var move_speed := 95.0
@export var shielded_phase_duration := 3.8
@export var invisible_duration := 2.0
@export var clone_fire_delay := 1.0
@export var teleport_settle_delay := 0.1

@export var normal_fire_interval := 2.15
@export var ion_fire_interval := 3.0

@export var clone_count_healthy := 3
@export var clone_count_mid := 5
@export var clone_count_critical := 7
@export var mid_phase_health_threshold := 3
@export var critical_phase_health_threshold := 1

@export var clone_orbit_radius := 64.0
@export var clone_orbit_speed := 1.9
@export var real_orbit_radius := 58.0
@export var real_orbit_speed := 1.6

@onready var boss_health_label: Label = $boss_health
@onready var normal_fire_timer: Timer = $NormalFireTimer
@onready var ion_fire_timer: Timer = $IonFireTimer
@onready var shield_phase_timer: Timer = $PhaseTimer
@onready var clone_fire_delay_timer: Timer = $CloneDelayTimer
@onready var teleport_delay_timer: Timer = $CloneTimeoutTimer
@onready var invisible_timer: Timer = $VanishTimer
@onready var shield_sprite: Sprite2D = $ShieldSprite

var health := 5
var move_direction := 1.0
var shield_active := true
var invulnerable := true
var is_dead := false

var clones: Array[Area2D] = []
var real_orbit_center := Vector2.ZERO
var real_orbit_angle := 0.0


enum BossState {
	SHIELDED,
	TELEPORTING_TO_CLONE,
	CLONE_MOVEMENT,
	CLONE_ATTACK,
	INVISIBLE_RESET
}

var state: BossState = BossState.SHIELDED


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	normal_fire_timer.wait_time = normal_fire_interval
	normal_fire_timer.timeout.connect(_on_normal_fire_timer_timeout)
	ion_fire_timer.wait_time = ion_fire_interval
	ion_fire_timer.timeout.connect(_on_ion_fire_timer_timeout)

	shield_phase_timer.one_shot = true
	shield_phase_timer.timeout.connect(_on_shield_phase_timer_timeout)

	clone_fire_delay_timer.one_shot = true
	clone_fire_delay_timer.timeout.connect(_on_clone_fire_delay_timer_timeout)

	teleport_delay_timer.one_shot = true
	teleport_delay_timer.timeout.connect(_on_teleport_delay_timeout)

	invisible_timer.one_shot = true
	invisible_timer.timeout.connect(_on_invisible_timer_timeout)

	_enter_shielded_phase()


func _process(delta: float) -> void:
	if is_dead:
		return

	boss_health_label.text = "Copier HP %d" % health

	if state == BossState.SHIELDED:
		_update_linear_movement(delta)
	elif state == BossState.CLONE_MOVEMENT or state == BossState.CLONE_ATTACK:
		_update_real_orbit(delta)


func _update_linear_movement(delta: float) -> void:
	var viewport = get_viewport_rect().size
	global_position.x += move_direction * move_speed * delta

	if global_position.x < 120.0:
		global_position.x = 120.0
		move_direction = 1.0
	elif global_position.x > viewport.x - 120.0:
		global_position.x = viewport.x - 120.0
		move_direction = -1.0


func _update_real_orbit(delta: float) -> void:
	real_orbit_angle += real_orbit_speed * delta
	global_position = real_orbit_center + Vector2(cos(real_orbit_angle), sin(real_orbit_angle)) * real_orbit_radius


func _on_area_entered(area: Area2D) -> void:
	if area.name != "Projectile":
		return
	area.queue_free()
	die(false)


func die(no_reward := false) -> void:
	if is_dead:
		return
	if state != BossState.CLONE_MOVEMENT and state != BossState.CLONE_ATTACK:
		return
	if invulnerable or shield_active:
		return

	health -= 1
	if health <= 0:
		_die_for_real(no_reward)
		return

	_end_clone_phase_to_invisible_reset()


func _die_for_real(no_reward := false) -> void:
	if is_dead:
		return
	is_dead = true

	_clear_all_timers()
	_clear_clones()
	_set_shield_active(false)

	if not no_reward:
		GameManager.add_resources(18)

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		get_tree().current_scene.add_child(explosion)

	emit_signal("boss_defeated")
	emit_signal("enemy_died")
	queue_free()


func _clear_all_timers() -> void:
	normal_fire_timer.stop()
	ion_fire_timer.stop()
	shield_phase_timer.stop()
	clone_fire_delay_timer.stop()
	teleport_delay_timer.stop()
	invisible_timer.stop()


func _enter_shielded_phase() -> void:
	state = BossState.SHIELDED
	_set_shield_active(true)
	invulnerable = true
	visible = true
	monitoring = true
	monitorable = true

	_clear_clones()
	_start_real_firing(true)
	shield_phase_timer.start(shielded_phase_duration)


func _on_shield_phase_timer_timeout() -> void:
	if is_dead:
		return
	_begin_clone_phase()


func _begin_clone_phase() -> void:
	state = BossState.TELEPORTING_TO_CLONE
	_set_shield_active(false)
	invulnerable = false
	_start_real_firing(false)

	_teleport_real_boss()
	teleport_delay_timer.start(teleport_settle_delay)


func _on_teleport_delay_timeout() -> void:
	if is_dead:
		return

	real_orbit_center = global_position
	real_orbit_angle = randf() * TAU

	_spawn_clones_for_current_phase()
	state = BossState.CLONE_MOVEMENT
	clone_fire_delay_timer.start(clone_fire_delay)


func _on_clone_fire_delay_timer_timeout() -> void:
	if is_dead:
		return
	if state != BossState.CLONE_MOVEMENT:
		return

	state = BossState.CLONE_ATTACK
	_start_real_firing(true)
	for clone in clones:
		if is_instance_valid(clone):
			clone.set_firing_enabled(true)


func _end_clone_phase_to_invisible_reset() -> void:
	if state == BossState.INVISIBLE_RESET:
		return

	state = BossState.INVISIBLE_RESET
	_start_real_firing(false)
	clone_fire_delay_timer.stop()
	_clear_clones()

	visible = false
	monitoring = false
	monitorable = false
	_set_shield_active(true)
	invulnerable = true
	invisible_timer.start(invisible_duration)


func _on_invisible_timer_timeout() -> void:
	if is_dead:
		return

	_teleport_real_boss()
	_enter_shielded_phase()


func _spawn_clones_for_current_phase() -> void:
	if clone_scene == null:
		return

	var viewport := get_viewport_rect().size
	var count := _get_clone_count_for_health()
	for i in range(count):
		var clone = clone_scene.instantiate()
		clone.missile_scene = missile_scene
		clone.fire_interval = normal_fire_interval
		clone.orbit_radius = clone_orbit_radius + randf_range(-14.0, 14.0)
		clone.orbit_speed = clone_orbit_speed + randf_range(-0.35, 0.35)

		var center := Vector2(
			randf_range(120.0, viewport.x - 120.0),
			randf_range(90.0, minf(250.0, viewport.y * 0.4))
		)
		clone.global_position = center
		clone.begin_clone_phase(center, randf() * TAU, false)
		clone.clone_destroyed.connect(_on_clone_destroyed)

		get_tree().current_scene.add_child(clone)
		clones.append(clone)


func _on_clone_destroyed(clone: Area2D) -> void:
	clones.erase(clone)
	if clones.is_empty() and (state == BossState.CLONE_MOVEMENT or state == BossState.CLONE_ATTACK):
		_end_clone_phase_to_invisible_reset()


func _clear_clones() -> void:
	for clone in clones:
		if is_instance_valid(clone):
			clone.queue_free()
	clones.clear()


func _start_real_firing(enabled: bool) -> void:
	if enabled:
		normal_fire_timer.start(randf_range(0.15, normal_fire_interval))
		ion_fire_timer.start(randf_range(0.6, ion_fire_interval))
	else:
		normal_fire_timer.stop()
		ion_fire_timer.stop()


func _on_normal_fire_timer_timeout() -> void:
	if is_dead:
		return
	if not visible:
		return
	_spawn_missile(missile_scene)


func _on_ion_fire_timer_timeout() -> void:
	if is_dead:
		return
	if not visible:
		return
	if not IonHazardController.can_launch_ion_missile():
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


func _teleport_real_boss() -> void:
	var viewport := get_viewport_rect().size
	global_position = Vector2(
		randf_range(140.0, viewport.x - 140.0),
		randf_range(90.0, minf(220.0, viewport.y * 0.36))
	)


func _get_clone_count_for_health() -> int:
	if health <= critical_phase_health_threshold:
		return clone_count_critical
	if health <= mid_phase_health_threshold:
		return clone_count_mid
	return clone_count_healthy


func _set_shield_active(value: bool) -> void:
	shield_active = value
	if shield_sprite:
		shield_sprite.visible = shield_active
