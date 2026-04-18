extends Area2D

const BossEntranceUtils = preload("res://Scripts/BossEntranceUtils.gd")

signal enemy_died
signal boss_defeated
signal start_death_animation(boss: Node)
signal jam_charge_started(duration: float)
signal jam_pulse_started(duration: float, misfire_radius: float)

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var emp_missile_scene: PackedScene
@export var move_speed: float = 120.0
@export var max_health: int = 5
@export var shield_up_duration: float = 3.5
@export var shield_down_duration: float = 2.0
@export var missile_drop_interval: float = 1.2
@export var missile_drop_interval_min: float = 0.45
@export var emp_interval: float = 4.8
@export var emp_charge_duration: float = 0.8
@export var jam_interval: float = 6.5
@export var jam_charge_duration: float = 0.9
@export var jam_duration_min: float = 1.0
@export var jam_duration_max: float = 2.0
@export var jam_misfire_radius_min: float = 95.0
@export var jam_misfire_radius_max: float = 180.0
@export var boss_name: String = "CYBER DRONE"
@export var emp_initial_delay: float = 2.0
@export var jam_initial_delay: float = 4.5
@export var emp_attack_sound: AudioStream
@export var emp_attack_sound_volume_db: float = -8.0
@export var emp_attack_sound_pitch_min: float = 0.96
@export var emp_attack_sound_pitch_max: float = 1.05

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

# Movement settings
@export var move_margin_x: float = 120.0
@export var move_min_y: float = 90.0
@export var move_max_y: float = 220.0
@export var arrive_distance: float = 12.0
@export var target_pause_min: float = 0.25
@export var target_pause_max: float = 0.75

# Bob settings
@export var bob_amount: float = 8.0
@export var bob_speed: float = 2.3

@onready var shield_timer: Timer = $ShieldTimer
@onready var missile_timer: Timer = $MissileTimer
@onready var emp_timer: Timer = $EmpTimer
@onready var jam_timer: Timer = $JamTimer
@onready var jam_charge_timer: Timer = $JamChargeTimer
@onready var emp_charge_timer: Timer = $EmpChargeTimer
@onready var boss_health: Label = $boss_health
@onready var jam_ring: Line2D = $JamRing
@onready var shield_sprite: Sprite2D = $ShieldSprite
@onready var flash_sprite: CanvasItem = get_node_or_null(flash_sprite_path) as CanvasItem

var health: int = 5
var shield_active: bool = true
var hit_used_this_down_window: bool = false
var is_dead: bool = false
var queued_emp_targets: Array = []
var emp_charge_active: bool = false

var _base_sprite_modulate: Color = Color(1, 1, 1, 1)
var _shield_base_modulate: Color = Color(1, 1, 1, 1)
var _hit_flash_tween: Tween
var _shield_tween: Tween

var _move_target: Vector2 = Vector2.ZERO
var _move_pause_timer: float = 0.0
var _bob_time: float = 0.0
var _flash_sprite_base_position: Vector2 = Vector2.ZERO
var _shield_sprite_base_position: Vector2 = Vector2.ZERO
var _shield_sprite_base_scale: Vector2 = Vector2.ONE
var _intro_active: bool = true
var _emp_audio_player: AudioStreamPlayer2D


func _add_to_scene(node: Node) -> void:
	var parent: Node = get_parent()
	if is_instance_valid(parent):
		parent.add_child(node)
	else:
		get_tree().root.add_child(node)


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	add_to_group("boss")

	if flash_sprite:
		_base_sprite_modulate = flash_sprite.modulate
		_flash_sprite_base_position = flash_sprite.position
	else:
		print("❌ Cyber Drone flash sprite NOT found. Set flash_sprite_path in the inspector.")

	if shield_sprite:
		_shield_sprite_base_position = shield_sprite.position
		_shield_sprite_base_scale = shield_sprite.scale
		_shield_base_modulate = shield_sprite.modulate

	shield_timer.wait_time = shield_up_duration
	shield_timer.timeout.connect(_on_shield_timer_timeout)

	missile_timer.wait_time = missile_drop_interval
	missile_timer.timeout.connect(_on_missile_timer_timeout)

	emp_timer.wait_time = emp_interval
	emp_timer.timeout.connect(_on_emp_timer_timeout)

	emp_charge_timer.one_shot = true
	emp_charge_timer.wait_time = emp_charge_duration
	emp_charge_timer.timeout.connect(_on_emp_charge_timer_timeout)

	jam_timer.wait_time = jam_interval
	jam_timer.timeout.connect(_on_jam_timer_timeout)

	jam_charge_timer.one_shot = true
	jam_charge_timer.wait_time = jam_charge_duration
	jam_charge_timer.timeout.connect(_on_jam_charge_timer_timeout)

	_prepare_jam_ring()
	_setup_boss_audio_hooks()
	_set_shield_active(true, true)
	await BossEntranceUtils.play_intro(self, flash_sprite as Node2D)
	_intro_active = false
	shield_timer.start()
	missile_timer.start()
	get_tree().create_timer(emp_initial_delay).timeout.connect(_start_emp_timer_after_delay)
	get_tree().create_timer(jam_initial_delay).timeout.connect(_start_jam_timer_after_delay)
	_move_target = global_position
	_move_pause_timer = randf_range(target_pause_min, target_pause_max)

func _start_emp_timer_after_delay() -> void:
	if not is_dead:
		emp_timer.start()


func _start_jam_timer_after_delay() -> void:
	if not is_dead:
		jam_timer.start()
		

func _process(delta: float) -> void:
	if is_dead or _intro_active:
		return

	if boss_health:
		boss_health.text = "Health %d" % health

	_update_movement(delta)
	_update_bob(delta)
	_animate_jam_ring(delta)
	_update_missile_rate_by_health()


func _update_movement(delta: float) -> void:
	var viewport: Vector2 = get_viewport_rect().size
	var drone_speed: float = move_speed

	if health >= 4:
		drone_speed *= 1.0
	elif health >= 2:
		drone_speed *= 1.5
	else:
		drone_speed *= 2.0

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
	global_position += direction * drone_speed * delta

	global_position.x = clampf(global_position.x, move_margin_x, viewport.x - move_margin_x)
	global_position.y = clampf(global_position.y, move_min_y, move_max_y)


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
	_move_target = Vector2(
		randf_range(move_margin_x, viewport.x - move_margin_x),
		randf_range(move_min_y, move_max_y)
	)

	if snap_to_target:
		global_position = _move_target


func _update_missile_rate_by_health() -> void:
	var lost_health: float = float(max_health - health)
	var t: float = lost_health / maxf(1.0, float(max_health - 1))
	var current_interval: float = lerp(missile_drop_interval, missile_drop_interval_min, t)
	if abs(missile_timer.wait_time - current_interval) > 0.01:
		missile_timer.wait_time = current_interval
		if missile_timer.is_stopped():
			missile_timer.start()


func die(no_reward: bool = false) -> void:
	if is_dead or _intro_active:
		return
	if shield_active:
		print("🛡️ Boss shield blocked the hit")
		return
	if hit_used_this_down_window:
		print("🛡️ Boss already took a hit during this shield break")
		return

	hit_used_this_down_window = true
	health -= 1
	GameManager.trigger_hit_stop(0.14, 0.04)
	_play_hit_flash()

	# Bring shield back immediately after a successful hit
	_set_shield_active(true)
	shield_timer.stop()
	shield_timer.wait_time = shield_up_duration
	shield_timer.start()

	print("🤖 Cyber Drone hit! Remaining HP: %d" % health)
	print("🛡️ Shield restored after hit")

	if health <= 0:
		_die_for_real(no_reward)
		return


func _die_for_real(no_reward: bool = false) -> void:
	if is_dead:
		return

	_prepare_for_death_animation()

	if not no_reward:
		GameManager.add_resources(10)

	emit_signal("start_death_animation", self)


func _prepare_for_death_animation() -> void:
	is_dead = true
	missile_timer.stop()
	shield_timer.stop()
	emp_timer.stop()
	emp_charge_timer.stop()
	jam_timer.stop()
	jam_charge_timer.stop()
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

	if shield_sprite:
		shield_sprite.position = _shield_sprite_base_position
		shield_sprite.scale = _shield_sprite_base_scale
		shield_sprite.modulate = _shield_base_modulate
		shield_sprite.visible = false

	_hide_jam_charge_ring()

	monitoring = false
	monitorable = false

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.disabled = true


func _on_shield_timer_timeout() -> void:
	if shield_active:
		_set_shield_active(false)
		hit_used_this_down_window = false
		shield_timer.wait_time = shield_down_duration
	else:
		_set_shield_active(true)
		shield_timer.wait_time = shield_up_duration

	shield_timer.start()


func _on_missile_timer_timeout() -> void:
	if is_dead:
		return
	spawn_normal_missile()


func _on_emp_timer_timeout() -> void:
	if is_dead:
		return
	_queue_emp_attack()


func _on_emp_charge_timer_timeout() -> void:
	if is_dead:
		return

	emp_charge_active = false

	var valid_targets: Array = []
	for target in queued_emp_targets:
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("is_destroyed") and target.is_destroyed():
			continue
		valid_targets.append(target)

	if valid_targets.is_empty():
		queued_emp_targets.clear()
		return

	var attack_origin: Vector2 = global_position + Vector2(0, 28)
	EmpAttackUtils.spawn_emp_volley(
		self,
		emp_missile_scene,
		attack_origin,
		valid_targets,
		Callable(GameManager, "_on_enemy_died")
	)
	queued_emp_targets.clear()


func _on_jam_timer_timeout() -> void:
	if is_dead:
		return
	_show_jam_charge_ring()
	emit_signal("jam_charge_started", jam_charge_duration)
	jam_charge_timer.start()


func _on_jam_charge_timer_timeout() -> void:
	if is_dead:
		return
	_hide_jam_charge_ring()
	var duration: float = _current_jam_duration()
	var radius: float = _current_jam_radius()
	emit_signal("jam_pulse_started", duration, radius)
	jam_timer.start()


func _current_jam_duration() -> float:
	var lost_health_ratio: float = float(max_health - health) / maxf(1.0, float(max_health - 1))
	return lerp(jam_duration_min, jam_duration_max, lost_health_ratio)


func _current_jam_radius() -> float:
	var lost_health_ratio: float = float(max_health - health) / maxf(1.0, float(max_health - 1))
	return lerp(jam_misfire_radius_min, jam_misfire_radius_max, lost_health_ratio)


func spawn_normal_missile() -> void:
	if missile_scene == null:
		return

	var missile: Area2D = missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport: Vector2 = get_viewport_rect().size
	var target: Vector2 = Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	var direction: Vector2 = (target - global_position).normalized()

	missile.global_position = global_position + Vector2(0, 32)
	missile.velocity = direction
	_add_to_scene(missile)


func _queue_emp_attack() -> void:
	if emp_charge_active:
		return

	var emp_targets: Array = _get_emp_targets()
	queued_emp_targets = EmpAttackUtils.select_emp_targets_for_health(emp_targets, health)

	if queued_emp_targets.is_empty():
		return

	emp_charge_active = true
	_play_variation_sound(_emp_audio_player, emp_attack_sound, emp_attack_sound_volume_db, emp_attack_sound_pitch_min, emp_attack_sound_pitch_max)
	emp_charge_timer.start()


func spawn_emp_missile() -> void:
	if emp_missile_scene == null:
		return

	EmpAttackUtils.spawn_emp_volley(
		self,
		emp_missile_scene,
		global_position + Vector2(0, 28),
		EmpAttackUtils.select_emp_targets_for_health(_get_emp_targets(), health),
		Callable(GameManager, "_on_enemy_died")
	)


func _prepare_jam_ring() -> void:
	if jam_ring == null:
		return
	jam_ring.visible = false
	jam_ring.width = 6.0
	jam_ring.default_color = Color(0.4, 0.95, 1.0, 0.85)
	jam_ring.clear_points()
	var points: int = 48
	var radius: float = 56.0
	for i in range(points + 1):
		var angle: float = TAU * float(i) / float(points)
		jam_ring.add_point(Vector2(cos(angle), sin(angle)) * radius)


func _show_jam_charge_ring() -> void:
	if jam_ring == null:
		return
	jam_ring.visible = true
	jam_ring.scale = Vector2(0.3, 0.3)
	jam_ring.modulate.a = 0.2


func _hide_jam_charge_ring() -> void:
	if jam_ring == null:
		return
	jam_ring.visible = false


func _animate_jam_ring(delta: float) -> void:
	if jam_ring == null or not jam_ring.visible:
		return
	var growth: float = 2.2 * delta / maxf(0.01, float(jam_charge_duration))
	jam_ring.scale += Vector2(growth, growth)
	jam_ring.modulate.a = minf(1.0, jam_ring.modulate.a + (1.8 * delta / maxf(0.01, float(jam_charge_duration))))


func _setup_boss_audio_hooks() -> void:
	_emp_audio_player = AudioStreamPlayer2D.new()
	_emp_audio_player.name = "EmpAbilityAudio"
	_emp_audio_player.bus = "Master"
	add_child(_emp_audio_player)


func _play_variation_sound(player: AudioStreamPlayer2D, stream: AudioStream, volume_db: float, pitch_min: float, pitch_max: float) -> void:
	if player == null or stream == null:
		return

	player.stream = stream
	player.volume_db = volume_db + randf_range(-1.0, 0.8)
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()


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
		print("❌ Cannot flash cyber drone: flash_sprite is null")
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

func _get_emp_targets() -> Array:
	var targets: Array = []

	for cannon in EmpAttackUtils.get_active_cannons(get_tree()):
		if cannon == null or not is_instance_valid(cannon):
			continue
		if cannon.has_method("is_destroyed") and cannon.is_destroyed():
			continue
		targets.append(cannon)

	for node in get_tree().get_nodes_in_group("building"):
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("is_destroyed") and node.is_destroyed():
			continue
		if node.has_method("has_active_shield") and node.has_active_shield():
			targets.append(node)

	return targets
