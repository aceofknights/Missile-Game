extends Area2D

signal enemy_died
signal boss_defeated
signal laser_charge_started(duration: float, target_name: String)
signal laser_fired(target_name: String)

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var scatter_missile_scene: PackedScene
@export var emp_missile_scene: PackedScene
@export var ion_missile_scene: PackedScene
@export var plane_scene: PackedScene
@export var fighter_projectile_scene: PackedScene
@export var laser_weak_point_scene: PackedScene

# --------------------------------------------------
# DEBUG ATTACK TOGGLES
# Turn these on/off in the inspector for testing.
# --------------------------------------------------
@export var debug_enable_shield_cycle := true
@export var debug_enable_normal_missiles := true
@export var debug_enable_scatter_missiles := true
@export var debug_enable_emp := true
@export var debug_enable_ion := true
@export var debug_enable_fighters := true
@export var debug_enable_bombers := true
@export var debug_enable_laser := true

# Core boss tuning
@export var max_health := 10
@export var move_speed := 120.0
@export var phase_health_thresholds: Array[int] = [8, 5, 2]

# Shield windows (per phase)
@export var shield_up_by_phase: Array[float] = [3.2, 2.6, 2.2, 1.5]
@export var shield_down_by_phase: Array[float] = [2.1, 1.7, 1.3, 0.9]

# Generic missiles
@export var normal_missile_interval_by_phase: Array[float] = [1.1, 0.9, 0.75, 0.58]

# Scatter missiles
@export var scatter_interval_by_phase: Array[float] = [4.2, 3.0, 2.4, 1.9]
@export var scatter_split_delay: float = 0.95
@export var scatter_spread_offset_3: float = 140.0
@export var scatter_spread_offset_5: float = 210.0

# EMP volleys
@export var emp_interval_by_phase: Array[float] = [7.5, 5.8, 4.5, 3.6]

# Ion missiles / zones
@export var ion_interval_by_phase: Array[float] = [8.2, 5.4, 4.2, 3.2]
@export var ion_zone_duration_by_phase: Array[float] = [4.5, 5.5, 6.0, 6.5]
@export var ion_zone_radius_by_phase: Array[float] = [105.0, 120.0, 135.0, 150.0]
@export var ion_player_slow_by_phase: Array[float] = [0.65, 0.55, 0.48, 0.42]
@export var ion_enemy_boost_by_phase: Array[float] = [1.28, 1.38, 1.5, 1.62]
@export var ion_max_active_zones_by_phase: Array[int] = [1, 1, 2, 3]

# Carrier behavior reuse
@export var fighter_spawn_interval_by_phase: Array[float] = [4.2, 3.0, 2.25, 1.8]
@export var bomber_spawn_interval_by_phase: Array[float] = [5.2, 3.8, 2.8, 2.2]
@export var max_fighters_by_phase: Array[int] = [2, 3, 4, 5]
@export var max_bombers_by_phase: Array[int] = [1, 2, 3, 4]

# Signature laser
@export var laser_unlock_phase := 3
@export var laser_base_interval_by_phase: Array[float] = [999.0, 999.0, 13.0, 9.0]
@export var laser_charge_duration_by_phase: Array[float] = [3.2, 2.8, 2.4, 1.8]
@export var laser_weak_point_hp_by_phase: Array[int] = [2, 3, 4, 5]
@export var laser_target_cannons_weight := 0.6
@export var boss_invulnerable_during_laser_charge := true

@onready var sprite: Sprite2D = $Sprite2D
@onready var boss_health_label: Label = $boss_health
@onready var shield_timer: Timer = $ShieldTimer
@onready var missile_timer: Timer = $MissileTimer
@onready var scatter_timer: Timer = $ScatterTimer
@onready var emp_timer: Timer = $EmpTimer
@onready var ion_timer: Timer = $IonTimer
@onready var fighter_timer: Timer = $FighterSpawnTimer
@onready var bomber_timer: Timer = $BomberSpawnTimer
@onready var laser_timer: Timer = $LaserTimer
@onready var laser_charge_timer: Timer = $LaserChargeTimer

var health := 10
var move_direction := 1.0
var shield_active := true
var hit_used_this_down_window := false
var is_dead := false

var fighters: Array[Area2D] = []
var bombers: Array[Area2D] = []

var laser_charge_active := false
var laser_interrupted := false
var laser_target: Node2D = null
var laser_weak_point: Area2D = null


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	shield_timer.timeout.connect(_on_shield_timer_timeout)
	missile_timer.timeout.connect(_on_missile_timer_timeout)
	scatter_timer.timeout.connect(_on_scatter_timer_timeout)
	emp_timer.timeout.connect(_on_emp_timer_timeout)
	ion_timer.timeout.connect(_on_ion_timer_timeout)
	fighter_timer.timeout.connect(_on_fighter_timer_timeout)
	bomber_timer.timeout.connect(_on_bomber_timer_timeout)
	laser_timer.timeout.connect(_on_laser_timer_timeout)
	laser_charge_timer.timeout.connect(_on_laser_charge_timer_timeout)

	_apply_phase_tuning(true)
	_update_visuals()
	_update_label()


func _process(delta: float) -> void:
	if is_dead:
		return

	_update_linear_movement(delta)
	_prune_planes()
	_update_label()

	if laser_charge_active and is_instance_valid(laser_weak_point):
		laser_weak_point.global_position = global_position + Vector2(0, 58)


func _on_area_entered(area: Area2D) -> void:
	if area.name != "Projectile":
		return
	area.queue_free()
	die(false)


func die(no_reward := false) -> void:
	if is_dead:
		return
	if shield_active:
		return
	if laser_charge_active and boss_invulnerable_during_laser_charge:
		return
	if hit_used_this_down_window:
		return

	hit_used_this_down_window = true
	health -= 1
	if health <= 0:
		_die_for_real(no_reward)
		return

	_apply_phase_tuning(false)
	_update_visuals()
	_update_label()


func _die_for_real(no_reward := false) -> void:
	if is_dead:
		return
	is_dead = true

	for t in [shield_timer, missile_timer, scatter_timer, emp_timer, ion_timer, fighter_timer, bomber_timer, laser_timer, laser_charge_timer]:
		t.stop()

	_cleanup_laser_state()
	for fighter in fighters:
		if is_instance_valid(fighter):
			fighter.queue_free()
	for bomber in bombers:
		if is_instance_valid(bomber):
			bomber.queue_free()
	fighters.clear()
	bombers.clear()

	if not no_reward:
		GameManager.add_resources(30)

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		_add_to_scene(explosion)

	emit_signal("boss_defeated")
	emit_signal("enemy_died")
	queue_free()


func _phase_index() -> int:
	if health > phase_health_thresholds[0]:
		return 0
	if health > phase_health_thresholds[1]:
		return 1
	if health > phase_health_thresholds[2]:
		return 2
	return 3


func _apply_phase_tuning(force_restart_timers: bool) -> void:
	var p := _phase_index()

	if debug_enable_shield_cycle and not laser_charge_active:
		shield_timer.wait_time = _phase_value_float(shield_up_by_phase, p)
		if force_restart_timers or shield_timer.is_stopped():
			shield_active = true
			hit_used_this_down_window = false
			shield_timer.start()
	else:
		shield_timer.stop()
		shield_active = false
		hit_used_this_down_window = false

	missile_timer.wait_time = _phase_value_float(normal_missile_interval_by_phase, p)
	scatter_timer.wait_time = _phase_value_float(scatter_interval_by_phase, p)
	emp_timer.wait_time = _phase_value_float(emp_interval_by_phase, p)
	ion_timer.wait_time = _phase_value_float(ion_interval_by_phase, p)
	fighter_timer.wait_time = _phase_value_float(fighter_spawn_interval_by_phase, p)
	bomber_timer.wait_time = _phase_value_float(bomber_spawn_interval_by_phase, p)

	if force_restart_timers:
		if debug_enable_normal_missiles:
			missile_timer.start(randf_range(0.2, missile_timer.wait_time))
		else:
			missile_timer.stop()

		if debug_enable_scatter_missiles:
			scatter_timer.start(randf_range(0.8, scatter_timer.wait_time))
		else:
			scatter_timer.stop()

		if debug_enable_emp:
			emp_timer.start(randf_range(1.2, emp_timer.wait_time))
		else:
			emp_timer.stop()

		if debug_enable_ion:
			ion_timer.start(randf_range(1.4, ion_timer.wait_time))
		else:
			ion_timer.stop()

		if debug_enable_fighters:
			fighter_timer.start(randf_range(0.6, fighter_timer.wait_time))
		else:
			fighter_timer.stop()

		if debug_enable_bombers:
			bomber_timer.start(randf_range(0.9, bomber_timer.wait_time))
		else:
			bomber_timer.stop()

	if debug_enable_laser and p + 1 >= laser_unlock_phase:
		laser_timer.wait_time = _phase_value_float(laser_base_interval_by_phase, p)
		if force_restart_timers or laser_timer.is_stopped():
			laser_timer.start(randf_range(1.4, laser_timer.wait_time))
	else:
		laser_timer.stop()


func _update_linear_movement(delta: float) -> void:
	var viewport := get_viewport_rect().size
	global_position.x += move_direction * move_speed * delta
	if global_position.x < 150.0:
		global_position.x = 150.0
		move_direction = 1.0
	elif global_position.x > viewport.x - 150.0:
		global_position.x = viewport.x - 150.0
		move_direction = -1.0


func _on_shield_timer_timeout() -> void:
	if is_dead or laser_charge_active or not debug_enable_shield_cycle:
		return
	var p := _phase_index()
	if shield_active:
		shield_active = false
		hit_used_this_down_window = false
		shield_timer.wait_time = _phase_value_float(shield_down_by_phase, p)
	else:
		shield_active = true
		shield_timer.wait_time = _phase_value_float(shield_up_by_phase, p)
	shield_timer.start()
	_update_visuals()


func _on_missile_timer_timeout() -> void:
	if is_dead or not debug_enable_normal_missiles:
		return
	_spawn_targeted_missile(missile_scene, global_position + Vector2(0, 30))


func _on_scatter_timer_timeout() -> void:
	if is_dead or not debug_enable_scatter_missiles or scatter_missile_scene == null:
		return

	var scatter = scatter_missile_scene.instantiate()
	GameManager.enemies_alive += 1
	scatter.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var p := _phase_index()
	var splits := 3 if p == 0 else 5
	scatter.split_delay = scatter_split_delay
	scatter.split_offsets = _build_scatter_offsets(splits)

	var viewport := get_viewport_rect().size
	var target := Vector2(randf_range(100.0, viewport.x - 100.0), viewport.y)
	scatter.global_position = global_position + Vector2(0, 34)
	scatter.velocity = (target - scatter.global_position).normalized()
	_add_to_scene(scatter)


func _on_emp_timer_timeout() -> void:
	if is_dead or not debug_enable_emp:
		return
	var active_cannons := EmpAttackUtils.get_active_cannons(get_tree())
	if active_cannons.is_empty():
		return
	EmpAttackUtils.spawn_emp_volley(
		self,
		emp_missile_scene,
		global_position + Vector2(0, 28),
		active_cannons,
		Callable(GameManager, "_on_enemy_died")
	)


func _on_ion_timer_timeout() -> void:
	if is_dead or not debug_enable_ion or ion_missile_scene == null:
		return

	var p := _phase_index()
	if IonHazardController.get_active_zone_count() >= _phase_value_int(ion_max_active_zones_by_phase, p):
		return

	var missile = ion_missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))
	missile.ion_zone_duration = _phase_value_float(ion_zone_duration_by_phase, p)
	missile.ion_zone_radius = _phase_value_float(ion_zone_radius_by_phase, p)
	missile.max_active_zones = _phase_value_int(ion_max_active_zones_by_phase, p)
	missile.zone_player_projectile_speed_multiplier = _phase_value_float(ion_player_slow_by_phase, p)
	missile.zone_enemy_missile_speed_multiplier = _phase_value_float(ion_enemy_boost_by_phase, p)

	var viewport := get_viewport_rect().size
	var target := Vector2(randf_range(140.0, viewport.x - 140.0), viewport.y)
	missile.global_position = global_position + Vector2(0, 32)
	missile.velocity = (target - missile.global_position).normalized()
	_add_to_scene(missile)


func _on_fighter_timer_timeout() -> void:
	if not debug_enable_fighters:
		return
	_spawn_plane_if_possible("fighter")


func _on_bomber_timer_timeout() -> void:
	if not debug_enable_bombers:
		return
	_spawn_plane_if_possible("bomber")


func _spawn_plane_if_possible(role: String) -> void:
	if is_dead or plane_scene == null:
		return

	_prune_planes()
	var p := _phase_index()
	if role == "fighter":
		if fighters.size() >= _phase_value_int(max_fighters_by_phase, p):
			return
	else:
		if bombers.size() >= _phase_value_int(max_bombers_by_phase, p):
			return

	var plane = plane_scene.instantiate()
	plane.role = role
	plane.missile_scene = missile_scene
	plane.explosion_scene = explosion_scene
	plane.fighter_projectile_scene = fighter_projectile_scene
	plane.global_position = global_position + Vector2(randf_range(-180.0, 180.0), randf_range(-25.0, 42.0))
	plane.direction = Vector2(signf(randf() - 0.5), randf_range(-0.28, 0.28)).normalized()
	plane.plane_removed.connect(_on_plane_removed)
	plane.set_speed_multiplier(1.0 + (0.12 * p))
	_add_to_scene(plane)

	if role == "fighter":
		fighters.append(plane)
	else:
		bombers.append(plane)


func _on_laser_timer_timeout() -> void:
	if is_dead or laser_charge_active or not debug_enable_laser:
		return

	laser_target = _choose_laser_target()
	if laser_target == null:
		return

	laser_charge_active = true
	laser_interrupted = false
	shield_active = false
	hit_used_this_down_window = false
	_update_visuals()

	_spawn_laser_weak_point()

	var p := _phase_index()
	var charge_duration := _phase_value_float(laser_charge_duration_by_phase, p)
	emit_signal("laser_charge_started", charge_duration, laser_target.name)
	laser_charge_timer.start(charge_duration)


func _spawn_laser_weak_point() -> void:
	_cleanup_laser_weak_point()
	if laser_weak_point_scene == null:
		return
	laser_weak_point = laser_weak_point_scene.instantiate()
	var p := _phase_index()
	laser_weak_point.max_hp = _phase_value_int(laser_weak_point_hp_by_phase, p)
	laser_weak_point.global_position = global_position + Vector2(0, 58)
	laser_weak_point.weak_point_destroyed.connect(_on_laser_weak_point_destroyed)
	_add_to_scene(laser_weak_point)


func _on_laser_weak_point_destroyed() -> void:
	if not laser_charge_active:
		return
	laser_interrupted = true
	_cleanup_laser_state()


func _on_laser_charge_timer_timeout() -> void:
	if is_dead:
		return

	if laser_interrupted:
		return

	if is_instance_valid(laser_target):
		if laser_target.has_method("destroy_permanently"):
			laser_target.destroy_permanently()
		elif laser_target.has_method("die"):
			laser_target.call_deferred("die")
		emit_signal("laser_fired", laser_target.name)

	_cleanup_laser_state()


func _cleanup_laser_state() -> void:
	laser_charge_timer.stop()
	_cleanup_laser_weak_point()
	laser_charge_active = false
	laser_interrupted = false
	laser_target = null

	if is_dead:
		return

	if debug_enable_shield_cycle:
		shield_active = true
		hit_used_this_down_window = false
		shield_timer.wait_time = _phase_value_float(shield_up_by_phase, _phase_index())
		shield_timer.start()
	else:
		shield_active = false
		hit_used_this_down_window = false
		shield_timer.stop()

	_update_visuals()


func _cleanup_laser_weak_point() -> void:
	if is_instance_valid(laser_weak_point):
		laser_weak_point.queue_free()
	laser_weak_point = null


func _choose_laser_target() -> Node2D:
	var cannon_targets: Array = []
	for cannon in get_tree().get_nodes_in_group("cannon"):
		if cannon == null:
			continue
		if cannon.has_method("is_destroyed") and cannon.is_destroyed():
			continue
		if cannon.has_method("_can_operate") and not cannon._can_operate():
			continue
		cannon_targets.append(cannon)

	var building_targets: Array = []
	for building in get_tree().get_nodes_in_group("building"):
		if building == null:
			continue
		if building.has_method("is_destroyed") and building.is_destroyed():
			continue
		building_targets.append(building)

	var prefer_cannon := randf() < laser_target_cannons_weight
	if prefer_cannon and not cannon_targets.is_empty():
		return cannon_targets[randi() % cannon_targets.size()]
	if not prefer_cannon and not building_targets.is_empty():
		return building_targets[randi() % building_targets.size()]
	if not cannon_targets.is_empty():
		return cannon_targets[randi() % cannon_targets.size()]
	if not building_targets.is_empty():
		return building_targets[randi() % building_targets.size()]
	return null


func _build_scatter_offsets(split_count: int) -> Array[float]:
	if split_count <= 3:
		return [-scatter_spread_offset_3, 0.0, scatter_spread_offset_3]
	return [
		-scatter_spread_offset_5,
		-scatter_spread_offset_3,
		0.0,
		scatter_spread_offset_3,
		scatter_spread_offset_5
	]


func _spawn_targeted_missile(scene: PackedScene, spawn_pos: Vector2) -> void:
	if scene == null:
		return
	var missile = scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))
	var viewport := get_viewport_rect().size
	var target := Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	missile.global_position = spawn_pos
	missile.velocity = (target - spawn_pos).normalized()
	_add_to_scene(missile)


func _on_plane_removed(plane: Area2D) -> void:
	fighters.erase(plane)
	bombers.erase(plane)


func _prune_planes() -> void:
	fighters = fighters.filter(func(p): return is_instance_valid(p))
	bombers = bombers.filter(func(p): return is_instance_valid(p))


func _update_visuals() -> void:
	if laser_charge_active:
		sprite.modulate = Color(1.0, 0.22, 0.2, 1.0)
	elif shield_active:
		sprite.modulate = Color(0.52, 0.88, 1.0, 1.0)
	else:
		sprite.modulate = Color(1.0, 0.6, 0.45, 1.0)


func _update_label() -> void:
	boss_health_label.text = "Mothership HP %d  P%d" % [health, _phase_index() + 1]


func _phase_value_float(values: Array[float], phase: int) -> float:
	if values.is_empty():
		return 1.0
	return values[clampi(phase, 0, values.size() - 1)]


func _phase_value_int(values: Array[int], phase: int) -> int:
	if values.is_empty():
		return 1
	return values[clampi(phase, 0, values.size() - 1)]


func _add_to_scene(node: Node) -> void:
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.add_child(node)
	else:
		get_tree().root.add_child(node)
