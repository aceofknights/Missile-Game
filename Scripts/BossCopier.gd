extends Area2D

signal enemy_died
signal boss_defeated
signal start_death_animation(boss: Node)

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var ion_missile_scene: PackedScene
@export var clone_scene: PackedScene

@export var boss_name: String = "COPIER"

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

@export var clone_active_group_size := 2
@export var clone_pattern_interval := 2.2
@export var clone_pattern_hold_duration := 0.8
@export var clone_scatter_move_speed := 260.0
@export var clone_min_spacing := 130.0
@export var clone_top_y_min := 80.0
@export var clone_top_y_max := 220.0
@export var line_spacing := 120.0
@export var arc_spacing := 95.0
@export var clone_center_offset_radius := 90.0

@export var real_orbit_radius := 58.0
@export var real_orbit_speed := 1.6

# Drag your actual visible sprite here in the inspector
@export_node_path("CanvasItem") var flash_sprite_path: NodePath

# Hit flash settings
@export var hit_flash_white: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var hit_flash_red: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_step_time: float = 0.08
@export var hit_flash_cycles: int = 3

# Shield transition settings
@export var shield_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var shield_flash_step_time: float = 0.06
@export var shield_flash_cycles: int = 2
@export var shield_pop_time: float = 0.12
@export var shield_on_start_scale_multiplier: float = 0.35
@export var shield_off_end_scale_multiplier: float = 0.25

# Movement settings for shielded phase
@export var move_margin_x: float = 120.0
@export var move_min_y: float = 90.0
@export var move_max_y: float = 220.0
@export var arrive_distance: float = 12.0
@export var target_pause_min: float = 0.25
@export var target_pause_max: float = 0.75

# Bob settings
@export var bob_amount: float = 8.0
@export var bob_speed: float = 2.2

@export var real_tell_color: Color = Color(1.0, 0.82, 0.95, 1.0)
@export var real_tell_scale_multiplier: float = 1.08

@onready var boss_health_label: Label = $boss_health
@onready var normal_fire_timer: Timer = $NormalFireTimer
@onready var ion_fire_timer: Timer = $IonFireTimer
@onready var shield_phase_timer: Timer = $PhaseTimer
@onready var clone_fire_delay_timer: Timer = $CloneDelayTimer
@onready var teleport_delay_timer: Timer = $CloneTimeoutTimer
@onready var invisible_timer: Timer = $VanishTimer
@onready var shield_sprite: Sprite2D = $ShieldSprite
@onready var flash_sprite: CanvasItem = get_node_or_null(flash_sprite_path) as CanvasItem

var health := 5
var shield_active := true
var invulnerable := true
var is_dead := false
var hit_used_this_down_window := false

var clones: Array[Area2D] = []
var real_orbit_center := Vector2.ZERO
var real_orbit_angle := 0.0

var _base_sprite_modulate: Color = Color(1, 1, 1, 1)
var _shield_base_modulate: Color = Color(1, 1, 1, 1)
var _hit_flash_tween: Tween
var _shield_tween: Tween

var _real_tell_active: bool = false
var _flash_sprite_base_scale: Vector2 = Vector2.ONE


var _move_target: Vector2 = Vector2.ZERO
var _move_pause_timer: float = 0.0
var _bob_time: float = 0.0
var _flash_sprite_base_position: Vector2 = Vector2.ZERO
var _shield_sprite_base_position: Vector2 = Vector2.ZERO
var _shield_sprite_base_scale: Vector2 = Vector2.ONE

var clone_pattern_timer: float = 0.0
var clone_pattern_hold_timer: float = 0.0
var real_phase_target: Vector2 = Vector2.ZERO
var _clone_pattern_fired_this_hold: bool = false


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
	add_to_group("boss")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	if flash_sprite:
		_base_sprite_modulate = flash_sprite.modulate
		_flash_sprite_base_position = flash_sprite.position
		_flash_sprite_base_scale = flash_sprite.scale
	else:
		print("❌ Copier flash sprite NOT found. Set flash_sprite_path in the inspector.")

	if shield_sprite:
		_shield_sprite_base_position = shield_sprite.position
		_shield_sprite_base_scale = shield_sprite.scale
		_shield_base_modulate = shield_sprite.modulate

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

	if boss_health_label:
		boss_health_label.text = "Copier HP %d" % health

	if state == BossState.SHIELDED:
		_update_movement(delta)
	elif state == BossState.CLONE_MOVEMENT or state == BossState.CLONE_ATTACK:
		_update_clone_phase_movement(delta)

	_update_bob(delta)


func _update_movement(delta: float) -> void:
	var viewport: Vector2 = get_viewport_rect().size
	var boss_speed: float = move_speed

	if health >= 4:
		boss_speed *= 1.0
	elif health >= 2:
		boss_speed *= 1.4
	else:
		boss_speed *= 1.8

	if _move_pause_timer > 0.0:
		_move_pause_timer = maxf(0.0, _move_pause_timer - delta)
		if _move_pause_timer <= 0.0:
			_pick_new_move_target(false)
		return

	var to_target: Vector2 = _move_target - global_position
	var distance_to_target: float = to_target.length()

	if distance_to_target <= arrive_distance:
		_move_pause_timer = randf_range(target_pause_min, target_pause_max)
		return

	var direction: Vector2 = to_target.normalized()
	global_position += direction * boss_speed * delta
	global_position = _clamp_top_area(global_position, viewport)


func _update_clone_phase_movement(delta: float) -> void:
	var viewport := get_viewport_rect().size

	if global_position.distance_to(real_phase_target) > 4.0:
		global_position = global_position.move_toward(real_phase_target, clone_scatter_move_speed * delta)
		global_position = _clamp_top_area(global_position, viewport)

	if clone_pattern_hold_timer > 0.0:
		if not _real_tell_active:
			_set_real_tell_active(true)

		clone_pattern_hold_timer = maxf(0.0, clone_pattern_hold_timer - delta)

		if not _clone_pattern_fired_this_hold and clone_pattern_hold_timer <= clone_pattern_hold_duration * 0.55:
			_fire_clone_group_volley()
			_clone_pattern_fired_this_hold = true
		return

	if _real_tell_active:
		_set_real_tell_active(false)

	clone_pattern_timer = maxf(0.0, clone_pattern_timer - delta)
	if clone_pattern_timer <= 0.0:
		_begin_new_clone_pattern()

func _set_real_tell_active(active: bool) -> void:
	_real_tell_active = active

	if flash_sprite == null:
		return

	if active:
		flash_sprite.modulate = real_tell_color
		flash_sprite.scale = _flash_sprite_base_scale * real_tell_scale_multiplier
	else:
		flash_sprite.modulate = _base_sprite_modulate
		flash_sprite.scale = _flash_sprite_base_scale

func _update_bob(delta: float) -> void:
	if flash_sprite == null:
		return

	_bob_time += delta * bob_speed
	var bob_offset_y: float = sin(_bob_time) * bob_amount
	var bob_offset := Vector2(0.0, bob_offset_y)

	flash_sprite.position = _flash_sprite_base_position + bob_offset

	if shield_sprite:
		shield_sprite.position = _shield_sprite_base_position + bob_offset


func _pick_new_move_target(snap_to_target: bool) -> void:
	var viewport: Vector2 = get_viewport_rect().size
	_move_target = _clamp_top_area(
		Vector2(
			randf_range(move_margin_x, viewport.x - move_margin_x),
			randf_range(move_min_y, move_max_y)
		),
		viewport
	)

	if snap_to_target:
		global_position = _move_target


func _clamp_top_area(pos: Vector2, viewport: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 120.0, viewport.x - 120.0),
		clampf(pos.y, clone_top_y_min, minf(clone_top_y_max, viewport.y * 0.42))
	)


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
	if hit_used_this_down_window:
		return

	hit_used_this_down_window = true
	health -= 1
	_play_hit_flash()

	_set_shield_active(true)
	invulnerable = true

	if health <= 0:
		_die_for_real(no_reward)
		return

	_end_clone_phase_to_invisible_reset()


func _die_for_real(no_reward := false) -> void:
	if is_dead:
		return

	_prepare_for_death_animation()

	if not no_reward:
		GameManager.add_resources(18)

	emit_signal("start_death_animation", self)


func _prepare_for_death_animation() -> void:
	is_dead = true

	_clear_all_timers()
	_clear_clones()
	_set_shield_active(false, true)

	if _hit_flash_tween:
		_hit_flash_tween.kill()
		_hit_flash_tween = null

	if _shield_tween:
		_shield_tween.kill()
		_shield_tween = null

	if flash_sprite:
		flash_sprite.modulate = _base_sprite_modulate
		flash_sprite.position = _flash_sprite_base_position
		flash_sprite.scale = _flash_sprite_base_scale

	if shield_sprite:
		shield_sprite.position = _shield_sprite_base_position
		shield_sprite.scale = _shield_sprite_base_scale
		shield_sprite.modulate = _shield_base_modulate
		shield_sprite.visible = false

	monitoring = false
	monitorable = false

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.disabled = true


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
	hit_used_this_down_window = false
	visible = true
	monitoring = true
	monitorable = true

	_clear_clones()
	_pick_new_move_target(true)
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
	hit_used_this_down_window = false
	_start_real_firing(false)

	_teleport_real_boss()
	teleport_delay_timer.start(teleport_settle_delay)


func _on_teleport_delay_timeout() -> void:
	if is_dead:
		return

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
		if is_instance_valid(clone) and clone.has_method("set_firing_enabled"):
			clone.set_firing_enabled(true)

	_begin_new_clone_pattern()


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

	var count := _get_clone_count_for_health()
	if count <= 0:
		return

	var positions := _generate_spread_positions(count + 1)
	if positions.size() < count + 1:
		return

	positions.shuffle()

	global_position = positions[0]
	real_phase_target = global_position

	for i in range(count):
		var clone = clone_scene.instantiate()
		clone.missile_scene = missile_scene
		clone.fire_interval = normal_fire_interval
		clone.clone_destroyed.connect(_on_clone_destroyed)

		clone.global_position = positions[i + 1]
		if clone.has_method("begin_clone_phase"):
			clone.begin_clone_phase(positions[i + 1], 0.0, false)

		get_tree().current_scene.add_child(clone)
		clones.append(clone)

	clone_pattern_timer = clone_pattern_interval
	clone_pattern_hold_timer = 0.0
	_clone_pattern_fired_this_hold = false


func _generate_spread_positions(count: int) -> Array[Vector2]:
	var viewport := get_viewport_rect().size
	var positions: Array[Vector2] = []
	var attempts: int = 0
	var max_attempts: int = 500

	while positions.size() < count and attempts < max_attempts:
		attempts += 1

		var candidate := Vector2(
			randf_range(120.0, viewport.x - 120.0),
			randf_range(clone_top_y_min, minf(clone_top_y_max, viewport.y * 0.42))
		)

		var valid := true
		for existing in positions:
			if candidate.distance_to(existing) < clone_min_spacing:
				valid = false
				break

		if valid:
			positions.append(candidate)

	return positions


func _begin_new_clone_pattern() -> void:
	var units: Array[Node2D] = []
	units.append(self)

	for clone in clones:
		if is_instance_valid(clone):
			units.append(clone)

	if units.size() <= 1:
		return

	var viewport := get_viewport_rect().size
	var pattern_type := randi() % 3

	var anchor := Vector2(
		randf_range(180.0, viewport.x - 180.0),
		randf_range(clone_top_y_min + 10.0, minf(clone_top_y_max, viewport.y * 0.40))
	)

	var targets: Array[Vector2] = []

	match pattern_type:
		0:
			var total_width := float(units.size() - 1) * line_spacing
			var start_x := clampf(anchor.x - total_width * 0.5, 120.0, viewport.x - 120.0 - total_width)
			for i in range(units.size()):
				targets.append(_clamp_top_area(Vector2(start_x + i * line_spacing, anchor.y), viewport))
		1:
			var total_width := float(units.size() - 1) * line_spacing * 0.8
			var start_x := clampf(anchor.x - total_width * 0.5, 120.0, viewport.x - 120.0 - total_width)
			var start_y := clampf(anchor.y - float(units.size() - 1) * 24.0, clone_top_y_min, clone_top_y_max)
			for i in range(units.size()):
				targets.append(_clamp_top_area(Vector2(start_x + i * line_spacing * 0.8, start_y + i * 48.0), viewport))
		2:
			var arc_step := PI / maxf(2.0, float(units.size() - 1))
			var arc_radius := arc_spacing * maxf(1.8, float(units.size()) * 0.45)
			for i in range(units.size()):
				var angle := PI + arc_step * float(i)
				targets.append(_clamp_top_area(anchor + Vector2(cos(angle), sin(angle)) * arc_radius, viewport))

	targets.shuffle()

	real_phase_target = targets[0]

	for i in range(clones.size()):
		var clone = clones[i]
		if not is_instance_valid(clone):
			continue
		if clone.has_method("set_move_target"):
			clone.set_move_target(targets[i + 1], clone_scatter_move_speed)

	_assign_active_clone_group()
	clone_pattern_hold_timer = clone_pattern_hold_duration
	clone_pattern_timer = clone_pattern_interval
	_clone_pattern_fired_this_hold = false


func _assign_active_clone_group() -> void:
	var valid_clones: Array[Area2D] = []
	for clone in clones:
		if is_instance_valid(clone):
			valid_clones.append(clone)

	if valid_clones.is_empty():
		return

	for clone in valid_clones:
		if clone.has_method("set_active_shooter"):
			clone.set_active_shooter(false)

	valid_clones.shuffle()

	var group_size: int = min(clone_active_group_size, valid_clones.size())
	for i in range(group_size):
		var clone := valid_clones[i]
		if clone.has_method("set_active_shooter"):
			clone.set_active_shooter(true)


func _fire_clone_group_volley() -> void:
	if state != BossState.CLONE_ATTACK:
		return

	for clone in clones:
		if not is_instance_valid(clone):
			continue
		if clone.has_method("fire_attack_now"):
			clone.fire_attack_now()


func _start_real_firing(enabled: bool) -> void:
	if enabled:
		if normal_fire_timer.is_stopped():
			normal_fire_timer.start(randf_range(0.35, normal_fire_interval))
		if ion_fire_timer.is_stopped():
			ion_fire_timer.start(randf_range(0.8, ion_fire_interval))
	else:
		normal_fire_timer.stop()
		ion_fire_timer.stop()


func _on_normal_fire_timer_timeout() -> void:
	if is_dead:
		return
	if not visible:
		return
	_spawn_missile(missile_scene)
	normal_fire_timer.start(normal_fire_interval)


func _on_ion_fire_timer_timeout() -> void:
	if is_dead:
		return
	if not visible:
		return
	if not IonHazardController.can_launch_ion_missile():
		ion_fire_timer.start(ion_fire_interval)
		return
	_spawn_missile(ion_missile_scene)
	ion_fire_timer.start(ion_fire_interval)


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
	global_position = _clamp_top_area(
		Vector2(
			randf_range(140.0, viewport.x - 140.0),
			randf_range(90.0, minf(220.0, viewport.y * 0.36))
		),
		viewport
	)


func _on_clone_destroyed(clone: Area2D) -> void:
	clones.erase(clone)
	if clones.is_empty() and (state == BossState.CLONE_MOVEMENT or state == BossState.CLONE_ATTACK):
		_end_clone_phase_to_invisible_reset()


func _clear_clones() -> void:
	for clone in clones:
		if is_instance_valid(clone):
			clone.queue_free()
	clones.clear()


func _get_clone_count_for_health() -> int:
	if health <= critical_phase_health_threshold:
		return clone_count_critical
	if health <= mid_phase_health_threshold:
		return clone_count_mid
	return clone_count_healthy


func _set_shield_active(value: bool, instant: bool = false) -> void:
	shield_active = value

	if shield_sprite == null:
		return

	if instant:
		if _shield_tween:
			_shield_tween.kill()
			_shield_tween = null
		shield_sprite.visible = value
		shield_sprite.scale = _shield_sprite_base_scale
		shield_sprite.modulate = _shield_base_modulate
		return

	_play_shield_transition(value)


func _play_shield_transition(turning_on: bool) -> void:
	if shield_sprite == null:
		return

	if _shield_tween:
		_shield_tween.kill()

	shield_sprite.modulate = _shield_base_modulate
	_shield_tween = create_tween()

	var cycles: int = max(1, shield_flash_cycles)

	if turning_on:
		shield_sprite.visible = true
		shield_sprite.scale = _shield_sprite_base_scale * shield_on_start_scale_multiplier

		for _i in range(cycles):
			_shield_tween.tween_property(shield_sprite, "modulate", shield_flash_color, shield_flash_step_time)
			_shield_tween.tween_property(shield_sprite, "modulate", _shield_base_modulate, shield_flash_step_time)

		_shield_tween.tween_property(shield_sprite, "scale", _shield_sprite_base_scale, shield_pop_time)
		_shield_tween.finished.connect(_on_shield_tween_finished.bind(true))
	else:
		shield_sprite.visible = true
		shield_sprite.scale = _shield_sprite_base_scale

		for _i in range(cycles):
			_shield_tween.tween_property(shield_sprite, "modulate", shield_flash_color, shield_flash_step_time)
			_shield_tween.tween_property(shield_sprite, "modulate", _shield_base_modulate, shield_flash_step_time)

		_shield_tween.tween_property(
			shield_sprite,
			"scale",
			_shield_sprite_base_scale * shield_off_end_scale_multiplier,
			shield_pop_time
		)
		_shield_tween.finished.connect(_on_shield_tween_finished.bind(false))


func _on_shield_tween_finished(should_remain_visible: bool) -> void:
	_shield_tween = null
	if shield_sprite == null:
		return

	shield_sprite.modulate = _shield_base_modulate
	shield_sprite.scale = _shield_sprite_base_scale
	shield_sprite.visible = should_remain_visible


func _play_hit_flash() -> void:
	if flash_sprite == null:
		print("❌ Cannot flash copier: flash_sprite is null")
		return

	if _hit_flash_tween:
		_hit_flash_tween.kill()

	flash_sprite.modulate = _base_sprite_modulate
	_hit_flash_tween = create_tween()

	var cycles: int = max(1, hit_flash_cycles)
	for _i in range(cycles):
		_hit_flash_tween.tween_property(flash_sprite, "modulate", hit_flash_white, hit_flash_step_time)
		_hit_flash_tween.tween_property(flash_sprite, "modulate", hit_flash_red, hit_flash_step_time)

	_hit_flash_tween.tween_property(flash_sprite, "modulate", _base_sprite_modulate, hit_flash_step_time)
	_hit_flash_tween.finished.connect(_on_hit_flash_finished)


func _on_hit_flash_finished() -> void:
	_hit_flash_tween = null
	if flash_sprite:
		flash_sprite.modulate = _base_sprite_modulate


func get_boss_visual_node() -> CanvasItem:
	return flash_sprite


func get_boss_death_particles() -> GPUParticles2D:
	return get_node_or_null("DeathParticles") as GPUParticles2D


func get_boss_body_size() -> Vector2:
	var sprite_node := flash_sprite as Sprite2D
	if sprite_node and sprite_node.texture:
		return sprite_node.texture.get_size() * sprite_node.scale

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rect_shape := collision_shape.shape as RectangleShape2D
		return rect_shape.size * collision_shape.scale

	if collision_shape and collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		var diameter: float = circle_shape.radius * 2.0
		return Vector2(diameter, diameter) * collision_shape.scale

	return Vector2(180.0, 120.0)


func get_boss_health() -> int:
	return health


func get_boss_max_health() -> int:
	return max_health


func is_boss_dead() -> bool:
	return is_dead


func get_boss_display_name() -> String:
	return boss_name
