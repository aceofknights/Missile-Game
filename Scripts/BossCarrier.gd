extends Area2D

signal enemy_died
signal boss_defeated
signal start_death_animation(boss: Node)

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var plane_scene: PackedScene
@export var fighter_projectile_scene: PackedScene
@export var move_speed: float = 90.0
@export var max_health: int = 5
@export var immunity_duration: float = 2.5
@export var shield_up_duration: float = 3.5
@export var shield_down_duration: float = 2.0
@export var boss_name: String = "CARRIER"

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
@export var move_margin_x: float = 160.0
@export var move_min_y: float = 80.0
@export var move_max_y: float = 200.0
@export var arrive_distance: float = 14.0
@export var target_pause_min: float = 0.25
@export var target_pause_max: float = 0.75

# Bob settings
@export var bob_amount: float = 8.0
@export var bob_speed: float = 2.1

@onready var hanger: Node2D = $Sprite2D/Hanger
@onready var boss_health_label: Label = $boss_health
@onready var fighter_spawn_timer: Timer = $FighterSpawnTimer
@onready var bomber_spawn_timer: Timer = $BomberSpawnTimer
@onready var immunity_timer: Timer = $ImmunityTimer
@onready var shield_timer: Timer = $ShieldTimer
@onready var shield_sprite: Sprite2D = $ShieldSprite
@onready var flash_sprite: CanvasItem = get_node_or_null(flash_sprite_path) as CanvasItem

var health: int = 5
var phase: int = 1
var is_immune: bool = false
var is_dead: bool = false
var shield_active: bool = true
var hit_used_this_down_window: bool = false
var fighters: Array[Area2D] = []
var bombers: Array[Area2D] = []

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
	add_to_group("boss")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	if flash_sprite:
		_base_sprite_modulate = flash_sprite.modulate
		_flash_sprite_base_position = flash_sprite.position
	else:
		print("❌ Carrier flash sprite NOT found. Set flash_sprite_path in the inspector.")

	if shield_sprite:
		_shield_sprite_base_position = shield_sprite.position
		_shield_sprite_base_scale = shield_sprite.scale
		_shield_base_modulate = shield_sprite.modulate

	fighter_spawn_timer.timeout.connect(_on_fighter_spawn_timer_timeout)
	bomber_spawn_timer.timeout.connect(_on_bomber_spawn_timer_timeout)
	immunity_timer.timeout.connect(_on_immunity_timeout)
	shield_timer.timeout.connect(_on_shield_timer_timeout)

	shield_timer.wait_time = shield_up_duration
	shield_timer.start()

	_update_phase_state()
	_update_label()
	_set_shield_active(true, true)
	_pick_new_move_target(true)


func _process(delta: float) -> void:
	if is_dead:
		return

	_update_movement(delta)
	_update_bob(delta)
	_update_label()


func _update_movement(delta: float) -> void:
	var viewport: Vector2 = get_viewport_rect().size
	var carrier_speed: float = move_speed

	if phase == 2:
		carrier_speed *= 1.15
	elif phase == 3:
		carrier_speed *= 1.35

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
	global_position += direction * carrier_speed * delta

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


func _on_area_entered(area: Area2D) -> void:
	if area.name != "Projectile":
		return
	area.queue_free()
	die(false)


func die(no_reward: bool = false) -> void:
	if is_dead:
		return
	if shield_active:
		print("🛡️ Carrier shield blocked the hit")
		return
	if is_immune:
		print("⚠️ Carrier is immune")
		return
	if hit_used_this_down_window:
		print("🛡️ Carrier already took a hit during this shield break")
		return

	hit_used_this_down_window = true
	health -= 1
	_play_hit_flash()

	# Bring shield back immediately after a successful hit
	_set_shield_active(true)
	shield_timer.stop()
	shield_timer.wait_time = shield_up_duration
	shield_timer.start()

	print("🚢 Carrier hit! Remaining HP: %d" % health)
	print("🛡️ Shield restored after hit")

	if health <= 0:
		_die_for_real(no_reward)
		return

	_reset_fighter_accuracy()
	_start_immunity_window()
	_update_phase_state()
	_update_label()


func _die_for_real(no_reward: bool = false) -> void:
	if is_dead:
		return

	_prepare_for_death_animation()

	if not no_reward:
		GameManager.add_resources(15)

	emit_signal("start_death_animation", self)


func _start_immunity_window() -> void:
	is_immune = true
	immunity_timer.wait_time = immunity_duration
	immunity_timer.start()


func _on_immunity_timeout() -> void:
	is_immune = false


func _on_shield_timer_timeout() -> void:
	if shield_active:
		_set_shield_active(false)
		hit_used_this_down_window = false
		shield_timer.wait_time = shield_down_duration
		print("⚡ Carrier shield DOWN")
	else:
		_set_shield_active(true)
		shield_timer.wait_time = shield_up_duration
		print("🛡️ Carrier shield UP")

	shield_timer.start()


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

	var speed_boost: float = 1.35 if phase == 3 else 1.0
	for fighter in fighters:
		if is_instance_valid(fighter):
			fighter.set_speed_multiplier(speed_boost)
	for bomber in bombers:
		if is_instance_valid(bomber):
			bomber.set_speed_multiplier(speed_boost)


func _on_fighter_spawn_timer_timeout() -> void:
	_prune_units()

	var available_slots: int = PHASE_MAX_UNITS[phase] - fighters.size()
	if available_slots <= 0:
		return

	var launch_count: int = min(available_slots, _get_fighter_launch_count())
	var spawned_fighters := _spawn_plane_formation("fighter", launch_count)
	for fighter in spawned_fighters:
		fighters.append(fighter)


func _on_bomber_spawn_timer_timeout() -> void:
	_prune_units()

	var available_slots: int = PHASE_MAX_UNITS[phase] - bombers.size()
	if available_slots <= 0:
		return

	var launch_count: int = min(available_slots, _get_bomber_launch_count())
	var spawned_bombers := _spawn_plane_formation("bomber", launch_count)
	for bomber in spawned_bombers:
		bombers.append(bomber)

func _get_fighter_launch_count() -> int:
	match phase:
		1:
			return 2
		2:
			return 2
		3:
			return 3
		_:
			return 2


func _get_bomber_launch_count() -> int:
	match phase:
		1:
			return 1
		2:
			return 1
		3:
			return 2
		_:
			return 1


func _spawn_plane_formation(role: String, count: int) -> Array[Area2D]:
	var spawned: Array[Area2D] = []
	if count <= 0:
		return spawned

	var launch_origin: Vector2 = global_position
	if hanger:
		launch_origin = hanger.global_position

	var offsets := _get_formation_offsets(count, role)

	for offset in offsets:
		var plane := _spawn_plane(role, launch_origin + offset)
		if plane != null:
			spawned.append(plane)

	return spawned


func _get_formation_offsets(count: int, role: String) -> Array[Vector2]:
	var offsets: Array[Vector2] = []

	if role == "fighter":
		match count:
			1:
				offsets = [Vector2(0, 0)]
			2:
				offsets = [Vector2(-28, 8), Vector2(28, 8)]
			3:
				offsets = [Vector2(0, 0), Vector2(-34, 16), Vector2(34, 16)]
			_:
				for i in range(count):
					offsets.append(Vector2((i - (count - 1) * 0.5) * 28.0, 8.0))
	else:
		match count:
			1:
				offsets = [Vector2(0, 0)]
			2:
				offsets = [Vector2(-22, 10), Vector2(22, 10)]
			_:
				for i in range(count):
					offsets.append(Vector2((i - (count - 1) * 0.5) * 22.0, 10.0))

	return offsets
	

func _spawn_plane(role: String, spawn_position: Vector2) -> Area2D:
	if plane_scene == null:
		return null

	var plane: Area2D = plane_scene.instantiate()
	plane.role = role
	plane.missile_scene = missile_scene
	plane.explosion_scene = explosion_scene
	plane.fighter_projectile_scene = fighter_projectile_scene
	plane.global_position = spawn_position
	plane.plane_removed.connect(_on_plane_removed)

	var entry_target := spawn_position + Vector2(
		randf_range(-80.0, 80.0),
		randf_range(40.0, 90.0)
	)

	if plane.has_method("configure_side_entry"):
		plane.configure_side_entry(entry_target, 1.5)
	else:
		plane.direction = Vector2(sign(randf() - 0.5), randf_range(-0.3, 0.3)).normalized()

	if phase == 3 and plane.has_method("set_speed_multiplier"):
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
	if boss_health_label:
		boss_health_label.text = "Carrier HP %d  P%d" % [health, phase]


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
		print("❌ Cannot flash carrier: flash_sprite is null")
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


func _prepare_for_death_animation() -> void:
	is_dead = true

	fighter_spawn_timer.stop()
	bomber_spawn_timer.stop()
	immunity_timer.stop()
	shield_timer.stop()
	_set_shield_active(false, true)

	if _hit_flash_tween:
		_hit_flash_tween.kill()
		_hit_flash_tween = null

	if _shield_tween:
		_shield_tween.kill()
		_shield_tween = null

	for fighter in fighters:
		if is_instance_valid(fighter):
			fighter.queue_free()
	for bomber in bombers:
		if is_instance_valid(bomber):
			bomber.queue_free()
	fighters.clear()
	bombers.clear()

	if flash_sprite:
		flash_sprite.modulate = _base_sprite_modulate
		flash_sprite.position = _flash_sprite_base_position

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

	return Vector2(240.0, 140.0)


func get_boss_health() -> int:
	return health


func get_boss_max_health() -> int:
	return max_health


func is_boss_dead() -> bool:
	return is_dead


func get_boss_display_name() -> String:
	return boss_name
