extends Area2D

@export var projectile_scene: PackedScene
@export var cannon_id := GameManager.CANNON_MIDDLE
@export var fire_rate := 0.5
@export var fire_sound: AudioStream
@export var fire_sound_volume_db: float = -7.0
@export var fire_sound_pitch_min: float = 0.96
@export var fire_sound_pitch_max: float = 1.05

const WORLD_1_CANNON_COLOR := Color(0.15, 0.45, 0.35, 1.0) # dark teal-green
const WORLD_2_CANNON_COLOR := Color(0.45, 0.22, 0.18, 1.0) # dark rust
const WORLD_3_CANNON_COLOR := Color(0.28, 0.18, 0.45, 1.0) # dark purple
const WORLD_4_CANNON_COLOR := Color(0.18, 0.28, 0.42, 1.0) # dark blue
const WORLD_5_CANNON_COLOR := Color(0.32, 0.45, 0.18, 1.0) # toxic green
const DEFAULT_CANNON_COLOR := Color(0.35, 0.35, 0.35, 1.0)
const RECOIL_DISTANCE_MIN := 7.0
const RECOIL_DISTANCE_MAX := 12.0
const RECOIL_KICK_TIME_MIN := 0.04
const RECOIL_KICK_TIME_MAX := 0.07
const RECOIL_RETURN_TIME_MIN := 0.10
const RECOIL_RETURN_TIME_MAX := 0.15
const TARGET_MARKER_TEXTURE := preload("res://assets/X_marker.png")
const DEATH_SCATTER_PARTICLE_TEXTURE := preload("res://circle.png")
const DEATH_SCATTER_PARTICLE_COUNT := 10
const DEATH_SCATTER_LIFETIME := 0.7
const DEATH_SCATTER_VELOCITY_MIN := 180.0
const DEATH_SCATTER_VELOCITY_MAX := 460.0
const DEATH_SCATTER_GRAVITY := 760.0
const BAR_READY_COLOR := Color(0.78, 0.84, 0.92, 0.95)
const BAR_BACKGROUND_COLOR := Color(0.015, 0.025, 0.04, 0.96)
const BAR_OUTLINE_COLOR := Color(0.32, 0.42, 0.52, 0.42)

var cooldown := 0.0
var shots_in_cycle := 0
var emp_disabled_remaining := 0.0
var jam_end_time: float = 0.0
var jam_misfire_radius: float = 0.0
var permanently_destroyed: bool = false
var shield_hits_remaining := 0
var shield_emp_disabled_remaining := 0.0
var _destruction_reaction_in_progress := false
var _cannon_gun_rest_position: Vector2 = Vector2.ZERO
var _cannon_base_rest_position: Vector2 = Vector2.ZERO
var _cannon_base_rest_scale: Vector2 = Vector2.ONE
var _cannon_gun_rest_scale: Vector2 = Vector2.ONE
var _recoil_tween: Tween
var _muzzle_flash_tween: Tween
var _bar_fill_style: StyleBoxFlat
var _bar_background_style: StyleBoxFlat
var _fire_audio_player: AudioStreamPlayer2D

@onready var muzzle: Marker2D = get_node_or_null("CannonGun/Muzzle") as Marker2D
@onready var ammo_label: Label = $AmmoLabel
@onready var fire_rate_bar: ProgressBar = $FireRateBar
@onready var repair_label: Label = get_node_or_null("RepairLabel") as Label
@onready var cannon_gun: Sprite2D = get_node_or_null("CannonGun") as Sprite2D
@onready var cannon_base: Sprite2D = get_node_or_null("CannonBase") as Sprite2D
@onready var cannon_destroyed: Sprite2D = get_node_or_null("CannonDestroyed") as Sprite2D
@onready var death_particles: GPUParticles2D = get_node_or_null("DeathParticles") as GPUParticles2D
@onready var shield_sprite: Sprite2D = Sprite2D.new()
@onready var shield_hits_label: Label = Label.new()
@onready var muzzle_flash: Polygon2D = Polygon2D.new()


func _ready() -> void:
	add_to_group("cannon")
	add_to_group("defense_target")
	monitoring = true
	monitorable = true
	connect("area_entered", Callable(self, "_on_area_entered"))

	ammo_label.top_level = true
	ammo_label.z_index = 30
	ammo_label.add_theme_font_size_override("font_size", 13)
	fire_rate_bar.top_level = true
	fire_rate_bar.z_index = 14
	if repair_label:
		repair_label.top_level = true

	_setup_cannon_gun_pivot()
	_setup_muzzle_flash()
	_setup_temp_shield_sprite()
	_setup_shield_hits_label()
	_setup_fire_audio_hook()
	_setup_reload_bar_style()
	_reset_passive_shield_for_wave()
	_cache_visual_rest_state()
	_configure_death_particles()
	_refresh_visibility_state()
	_update_overlay_positions()
	_update_ui()

	print(name, " monitoring=", monitoring, " monitorable=", monitorable)
	print(name, " layer=", collision_layer, " mask=", collision_mask)
	print(name, " groups=", get_groups())


func _process(delta: float) -> void:
	if emp_disabled_remaining > 0.0:
		emp_disabled_remaining = maxf(0.0, emp_disabled_remaining - delta)

	if shield_emp_disabled_remaining > 0.0:
		shield_emp_disabled_remaining = maxf(0.0, shield_emp_disabled_remaining - delta)

	if _can_operate():
		_rotate_gun_to_mouse()
		if cooldown > 0.0:
			cooldown = maxf(0.0, cooldown - delta)

	_update_overlay_positions()
	_update_shield_state()
	_update_shield_hits_label()
	_update_ui()
	_refresh_visibility_state()


func _can_operate() -> bool:
	return GameManager.is_cannon_unlocked(cannon_id) and not GameManager.is_cannon_destroyed(cannon_id)


func _refresh_visibility_state() -> void:
	var unlocked: bool = GameManager.is_cannon_unlocked(cannon_id)
	var destroyed: bool = GameManager.is_cannon_destroyed(cannon_id)
	var active: bool = unlocked and not destroyed
	var jammed: bool = is_targeting_jammed()
	var world_color: Color = _get_world_cannon_color()

	visible = unlocked
	monitorable = active
	monitoring = active

	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.disabled = not active

	if ammo_label:
		ammo_label.visible = active

	if fire_rate_bar:
		fire_rate_bar.visible = active

	if repair_label:
		repair_label.visible = emp_disabled_remaining > 0.0
		if emp_disabled_remaining > 0.0:
			repair_label.text = "EMP %.1fs" % emp_disabled_remaining

	if cannon_base:
		cannon_base.visible = active
		if not active:
			cannon_base.position = _cannon_base_rest_position
			cannon_base.scale = _cannon_base_rest_scale
		if destroyed:
			cannon_base.modulate = Color(0.35, 0.35, 0.35, 1.0)
		elif emp_disabled_remaining > 0.0:
			cannon_base.modulate = Color(0.55, 0.9, 1.0, 1.0)
		elif jammed:
			cannon_base.modulate = Color(0.8, 1.0, 1.0, 1.0)
		else:
			cannon_base.modulate = world_color

	if cannon_gun:
		cannon_gun.visible = active
		if not active:
			cannon_gun.position = _cannon_gun_rest_position
			cannon_gun.scale = _cannon_gun_rest_scale
		if destroyed:
			cannon_gun.modulate = Color(0.35, 0.35, 0.35, 1.0)
		elif emp_disabled_remaining > 0.0:
			cannon_gun.modulate = Color(0.55, 0.9, 1.0, 1.0)
		elif jammed:
			cannon_gun.modulate = Color(0.8, 1.0, 1.0, 1.0)
		else:
			cannon_gun.modulate = world_color

	if cannon_destroyed:
		cannon_destroyed.visible = unlocked and destroyed
		cannon_destroyed.modulate = world_color

	if shield_sprite:
		shield_sprite.visible = active and shield_hits_remaining > 0 and not _is_passive_shield_blocked_by_emp()


func _update_ui() -> void:
	if ammo_label:
		ammo_label.visible = _can_operate()
		ammo_label.text = "%d/%d" % [
			GameManager.get_cannon_current_ammo(cannon_id),
			GameManager.get_cannon_max_ammo(cannon_id)
		]
		ammo_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	if fire_rate_bar:
		fire_rate_bar.max_value = 1.0
		fire_rate_bar.value = _get_fire_rate_bar_fill_ratio()
		_update_reload_bar_style()


func _update_overlay_positions() -> void:
	ammo_label.global_position = global_position + Vector2(-45, 34)
	fire_rate_bar.global_position = global_position + Vector2(-52, 34)
	if repair_label:
		repair_label.global_position = global_position + Vector2(-70, -84)


func can_fire() -> bool:
	return _can_operate() and emp_disabled_remaining <= 0.0 and cooldown <= 0.0 and GameManager.get_cannon_current_ammo(cannon_id) > 0


func try_fire_at(target_position: Vector2) -> bool:
	if not can_fire():
		return false

	if fire(target_position):
		shots_in_cycle += 1
		if shots_in_cycle >= GameManager.get_cannon_shots_per_cycle(cannon_id):
			shots_in_cycle = 0
			cooldown = GameManager.get_cannon_fire_rate(cannon_id, fire_rate)
		_update_ui()
		return true

	return false


func fire(target_position: Vector2) -> bool:
	if not GameManager.spend_cannon_ammo(cannon_id, 1):
		return false

	var final_target: Vector2 = _apply_jam_to_target(target_position)

	var projectile = projectile_scene.instantiate()
	projectile.global_position = muzzle.global_position if muzzle else global_position
	projectile.target = final_target
	var target_marker := _spawn_target_marker(final_target)
	if "target_marker" in projectile:
		projectile.target_marker = target_marker
	get_tree().current_scene.add_child(projectile)
	_play_fire_feedback()

	_update_ui()
	return true


func _apply_jam_to_target(target_position: Vector2) -> Vector2:
	if not is_targeting_jammed():
		return target_position

	var angle: float = randf() * TAU
	var distance: float = sqrt(randf()) * jam_misfire_radius
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
	var jammed_target: Vector2 = target_position + offset

	print("🌀 Jammed shot from %s to %s (radius %.1f)" % [target_position, jammed_target, jam_misfire_radius])

	return jammed_target


func apply_targeting_jam(duration: float, radius: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	jam_end_time = maxf(jam_end_time, now + maxf(0.1, duration))
	jam_misfire_radius = maxf(jam_misfire_radius, radius)
	_refresh_visibility_state()
	print("🌀 Cannon jammed for %.2fs with radius %.1f" % [duration, radius])


func is_targeting_jammed() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return now < jam_end_time


func clear_targeting_jam() -> void:
	jam_end_time = 0.0
	jam_misfire_radius = 0.0
	_refresh_visibility_state()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy") and not area.is_in_group("emp_missile"):
		if handle_enemy_impact(area):
			return
		die(area.global_position)


func _setup_temp_shield_sprite() -> void:
	shield_sprite.texture = preload("res://assets/ShieldUfo.png")
	shield_sprite.modulate = Color(0.4, 0.95, 1.0, 0.35)
	shield_sprite.scale = Vector2(0.13, 0.1)
	shield_sprite.visible = false
	add_child(shield_sprite)


func _setup_shield_hits_label() -> void:
	shield_hits_label.top_level = true
	shield_hits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shield_hits_label.add_theme_color_override("font_color", Color(0.38, 0.92, 1.0, 1.0))
	shield_hits_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	shield_hits_label.add_theme_constant_override("outline_size", 2)
	shield_hits_label.add_theme_font_size_override("font_size", 12)
	shield_hits_label.visible = false
	shield_hits_label.z_index = 25
	add_child(shield_hits_label)


func _setup_fire_audio_hook() -> void:
	_fire_audio_player = AudioStreamPlayer2D.new()
	_fire_audio_player.name = "FireAudio"
	_fire_audio_player.max_polyphony = 2
	_fire_audio_player.bus = "Master"
	_fire_audio_player.volume_db = fire_sound_volume_db
	add_child(_fire_audio_player)


func _setup_reload_bar_style() -> void:
	if fire_rate_bar == null:
		return

	fire_rate_bar.custom_minimum_size = Vector2(104.0, 12.0)
	fire_rate_bar.step = 0.001
	fire_rate_bar.self_modulate = Color.WHITE

	_bar_background_style = StyleBoxFlat.new()
	_bar_background_style.bg_color = BAR_BACKGROUND_COLOR
	_bar_background_style.border_width_left = 1
	_bar_background_style.border_width_top = 1
	_bar_background_style.border_width_right = 1
	_bar_background_style.border_width_bottom = 1
	_bar_background_style.border_color = BAR_OUTLINE_COLOR
	_bar_background_style.corner_radius_top_left = 5
	_bar_background_style.corner_radius_top_right = 5
	_bar_background_style.corner_radius_bottom_right = 5
	_bar_background_style.corner_radius_bottom_left = 5
	_bar_background_style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	_bar_background_style.shadow_size = 3

	_bar_fill_style = StyleBoxFlat.new()
	_bar_fill_style.corner_radius_top_left = 4
	_bar_fill_style.corner_radius_top_right = 4
	_bar_fill_style.corner_radius_bottom_right = 4
	_bar_fill_style.corner_radius_bottom_left = 4
	_bar_fill_style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	_bar_fill_style.shadow_size = 2

	fire_rate_bar.add_theme_stylebox_override("background", _bar_background_style)
	fire_rate_bar.add_theme_stylebox_override("fill", _bar_fill_style)


func _setup_muzzle_flash() -> void:
	if muzzle == null:
		return

	muzzle_flash.polygon = PackedVector2Array([
		Vector2(0, -34),
		Vector2(12, -4),
		Vector2(0, 8),
		Vector2(-12, -4)
	])
	muzzle_flash.color = Color(1.0, 0.92, 0.6, 0.85)
	muzzle_flash.visible = false
	muzzle_flash.z_index = 5
	muzzle.add_child(muzzle_flash)


func _update_shield_hits_label() -> void:
	if shield_hits_label == null:
		return

	var max_hits := GameManager.get_shield_generator_hit_capacity()
	var show := max_hits > 0 and _can_operate() and shield_hits_remaining > 0
	shield_hits_label.visible = show
	if not show:
		return

	shield_hits_label.global_position = global_position + Vector2(-18, 14)
	shield_hits_label.text = _get_shield_pips_text(shield_hits_remaining)
	var pip_color := Color(0.38, 0.92, 1.0, 1.0)
	if _is_passive_shield_blocked_by_emp():
		pip_color = Color(0.58, 0.86, 1.0, 0.55)
	shield_hits_label.add_theme_color_override("font_color", pip_color)


func _update_shield_state() -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()
	if max_hits <= 0 or not _can_operate():
		shield_hits_remaining = 0
		return

	if shield_hits_remaining < 0:
		shield_hits_remaining = 0
	elif shield_hits_remaining > max_hits:
		shield_hits_remaining = max_hits


func _reset_passive_shield_for_wave() -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()
	if max_hits > 0 and _can_operate():
		shield_hits_remaining = max_hits
	else:
		shield_hits_remaining = 0


func _is_passive_shield_blocked_by_emp() -> bool:
	return shield_emp_disabled_remaining > 0.0
	

func handle_enemy_impact(enemy: Area2D) -> bool:
	if _is_passive_shield_blocked_by_emp():
		return false

	_update_shield_state()
	if shield_hits_remaining > 0:
		shield_hits_remaining -= 1
		shield_hits_remaining = max(0, shield_hits_remaining)
		if enemy:
			enemy.call_deferred("die", true)
		return true
	return false


func disable_temporarily(duration: float) -> void:
	var applied_duration: float = maxf(0.1, duration)
	emp_disabled_remaining = maxf(emp_disabled_remaining, applied_duration)
	shield_emp_disabled_remaining = maxf(shield_emp_disabled_remaining, applied_duration)
	_refresh_visibility_state()


func die(hit_from: Vector2 = Vector2.ZERO) -> void:
	if is_destroyed() or _destruction_reaction_in_progress:
		return

	_destruction_reaction_in_progress = true
	monitoring = false
	monitorable = false
	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.disabled = true
	await _play_hit_reaction(hit_from)
	_play_death_particles(hit_from)

	GameManager.destroy_cannon(cannon_id)
	_destruction_reaction_in_progress = false
	_refresh_visibility_state()


func is_destroyed() -> bool:
	return GameManager.is_cannon_destroyed(cannon_id)


func is_hovered(global_mouse_position: Vector2) -> bool:
	if not GameManager.is_cannon_unlocked(cannon_id) or not is_destroyed():
		return false
	return _is_mouse_over_cannon(global_mouse_position)


func is_hovered_any_state(global_mouse_position: Vector2) -> bool:
	if not GameManager.is_cannon_unlocked(cannon_id):
		return false
	return _is_mouse_over_cannon(global_mouse_position)


func _is_mouse_over_cannon(global_mouse_position: Vector2) -> bool:
	var hover_sprite: Sprite2D = cannon_destroyed if is_destroyed() and cannon_destroyed else cannon_base
	if hover_sprite and hover_sprite.texture:
		var local_mouse: Vector2 = hover_sprite.to_local(global_mouse_position)
		if hover_sprite.get_rect().has_point(local_mouse):
			return true
	return global_position.distance_to(global_mouse_position) <= 70.0


func repair() -> void:
	if permanently_destroyed:
		return
	GameManager.set_cannon_unlocked(cannon_id, true)
	GameManager.set_cannon_current_ammo(cannon_id, GameManager.get_cannon_starting_ammo(cannon_id))
	cooldown = 0.0
	shots_in_cycle = 0
	emp_disabled_remaining = 0.0
	shield_emp_disabled_remaining = 0.0
	clear_targeting_jam()
	_reset_passive_shield_for_wave()
	_refresh_visibility_state()


func destroy_permanently() -> void:
	permanently_destroyed = true
	die()
	if is_instance_valid(cannon_base):
		cannon_base.queue_free()
	if is_instance_valid(cannon_gun):
		cannon_gun.queue_free()
	if is_instance_valid(cannon_destroyed):
		cannon_destroyed.queue_free()


func _rotate_gun_to_mouse() -> void:
	if cannon_gun == null:
		return

	var target_angle := global_position.angle_to_point(get_global_mouse_position())
	cannon_gun.global_rotation = target_angle + deg_to_rad(90.0)


func _setup_cannon_gun_pivot() -> void:
	if cannon_gun == null or cannon_gun.texture == null:
		return

	_cannon_gun_rest_position = cannon_gun.position
	cannon_gun.centered = false
	var tex_size: Vector2 = cannon_gun.texture.get_size()

	# Places the texture so the node origin is at the bottom-center of the gun.
	cannon_gun.offset = Vector2(-tex_size.x * 0.5, -tex_size.y)


func _cache_visual_rest_state() -> void:
	if cannon_base:
		_cannon_base_rest_position = cannon_base.position
		_cannon_base_rest_scale = cannon_base.scale
	if cannon_gun:
		_cannon_gun_rest_position = cannon_gun.position
		_cannon_gun_rest_scale = cannon_gun.scale


func _play_fire_feedback() -> void:
	_play_fire_sound()
	_play_recoil_feedback()
	_play_muzzle_flash_feedback()
	_play_base_kick_feedback()


func _play_hit_reaction(hit_from: Vector2) -> void:
	var impact_dir := Vector2.ZERO
	if hit_from != Vector2.ZERO:
		impact_dir = (global_position - hit_from).normalized()
	if impact_dir == Vector2.ZERO:
		impact_dir = Vector2(0.0, -1.0)

	var nudge := impact_dir * 4.0
	var world_color := _get_world_cannon_color()
	var flash_color := world_color.lerp(Color.WHITE, 0.78)
	var tween := create_tween()
	tween.set_parallel(true)

	if cannon_base:
		cannon_base.position = _cannon_base_rest_position
		cannon_base.scale = _cannon_base_rest_scale
		cannon_base.modulate = world_color
		tween.tween_property(cannon_base, "position", _cannon_base_rest_position + nudge, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(cannon_base, "scale", Vector2(_cannon_base_rest_scale.x * 1.06, _cannon_base_rest_scale.y * 0.92), 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(cannon_base, "modulate", flash_color, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if cannon_gun:
		cannon_gun.position = _cannon_gun_rest_position
		cannon_gun.scale = _cannon_gun_rest_scale
		cannon_gun.modulate = world_color
		tween.tween_property(cannon_gun, "position", _cannon_gun_rest_position + nudge, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(cannon_gun, "scale", Vector2(_cannon_gun_rest_scale.x * 1.08, _cannon_gun_rest_scale.y * 0.9), 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(cannon_gun, "modulate", flash_color, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await tween.finished


func _play_recoil_feedback() -> void:
	if cannon_gun == null:
		return

	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()

	var rest_global_position: Vector2 = cannon_gun.get_parent().to_global(_cannon_gun_rest_position)
	var forward_direction: Vector2 = Vector2.UP.rotated(cannon_gun.global_rotation)
	var recoil_distance: float = 8.0
	var kick_time: float = 0.05
	var return_time: float = 0.12
	var recoil_target_global: Vector2 = rest_global_position - (forward_direction * recoil_distance)
	cannon_gun.global_position = rest_global_position
	cannon_gun.scale = _cannon_gun_rest_scale
	_recoil_tween = create_tween()
	_recoil_tween.set_ease(Tween.EASE_OUT)
	_recoil_tween.set_trans(Tween.TRANS_CUBIC)
	_recoil_tween.tween_property(cannon_gun, "global_position", recoil_target_global, kick_time)
	_recoil_tween.set_ease(Tween.EASE_IN_OUT)
	_recoil_tween.set_trans(Tween.TRANS_SINE)
	_recoil_tween.tween_property(cannon_gun, "global_position", rest_global_position, return_time)


func _play_muzzle_flash_feedback() -> void:
	if muzzle_flash == null:
		return

	if _muzzle_flash_tween and _muzzle_flash_tween.is_valid():
		_muzzle_flash_tween.kill()

	muzzle_flash.visible = true
	muzzle_flash.color = _get_world_cannon_color().lerp(Color(1.0, 0.95, 0.72, 1.0), 0.75)
	muzzle_flash.color.a = randf_range(0.78, 0.92)
	muzzle_flash.scale = Vector2(randf_range(0.92, 1.08), randf_range(0.92, 1.1))
	_muzzle_flash_tween = create_tween()
	_muzzle_flash_tween.set_parallel(true)
	_muzzle_flash_tween.tween_property(muzzle_flash, "scale", Vector2(randf_range(1.25, 1.45), randf_range(1.45, 1.8)), 0.06)
	_muzzle_flash_tween.tween_property(muzzle_flash, "rotation", randf_range(-0.18, 0.18), 0.04)
	_muzzle_flash_tween.tween_property(muzzle_flash, "color:a", 0.0, 0.08)
	_muzzle_flash_tween.finished.connect(func() -> void:
		if is_instance_valid(muzzle_flash):
			muzzle_flash.visible = false
			muzzle_flash.scale = Vector2.ONE
			muzzle_flash.rotation = 0.0
	)


func _play_base_kick_feedback() -> void:
	if cannon_base == null:
		return

	var kick_tween := create_tween()
	var kick_offset := Vector2(randf_range(-1.6, 1.6), randf_range(1.2, 2.8))
	kick_tween.set_parallel(true)
	kick_tween.tween_property(cannon_base, "position", _cannon_base_rest_position + kick_offset, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	kick_tween.tween_property(cannon_base, "scale", Vector2(_cannon_base_rest_scale.x * randf_range(1.01, 1.04), _cannon_base_rest_scale.y * randf_range(0.97, 1.0)), 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	kick_tween.chain().set_parallel(true)
	kick_tween.tween_property(cannon_base, "position", _cannon_base_rest_position, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kick_tween.tween_property(cannon_base, "scale", _cannon_base_rest_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_fire_sound() -> void:
	if _fire_audio_player == null:
		return

	_fire_audio_player.stream = fire_sound
	_fire_audio_player.volume_db = fire_sound_volume_db + randf_range(-1.2, 0.9)
	_fire_audio_player.pitch_scale = randf_range(fire_sound_pitch_min, fire_sound_pitch_max)
	if fire_sound != null:
		_fire_audio_player.play()


func _get_fire_rate_bar_fill_ratio() -> float:
	var shots_per_cycle := GameManager.get_cannon_shots_per_cycle(cannon_id)
	if cooldown > 0.0:
		var delay: float = maxf(0.001, GameManager.get_cannon_fire_rate(cannon_id, fire_rate))
		return clampf(1.0 - (cooldown / delay), 0.0, 1.0)

	if shots_per_cycle <= 1:
		return 1.0

	return clampf(float(shots_per_cycle - shots_in_cycle) / float(shots_per_cycle), 0.0, 1.0)


func _update_reload_bar_style() -> void:
	if _bar_fill_style == null:
		return

	var world_color := _get_world_cannon_color()
	var charged_ratio := _get_fire_rate_bar_fill_ratio()
	var shots_per_cycle := GameManager.get_cannon_shots_per_cycle(cannon_id)
	var ready_color := world_color.lerp(Color(0.46, 0.56, 0.66, 1.0), 0.74)
	var reload_color := world_color.lerp(Color(0.30, 0.36, 0.42, 1.0), 0.78)
	var fill_color := ready_color if cooldown <= 0.0 else reload_color
	fill_color = fill_color.lerp(Color.WHITE, charged_ratio * 0.06)
	_bar_fill_style.bg_color = fill_color
	_bar_background_style.border_color = world_color.lerp(BAR_OUTLINE_COLOR, 0.55)
	_bar_background_style.bg_color = BAR_BACKGROUND_COLOR.lerp(world_color, 0.06)
	fire_rate_bar.self_modulate = Color(1.0, 1.0, 1.0, 0.94 if _can_operate() else 0.45)
	if shots_per_cycle > 1 and cooldown <= 0.0 and shots_in_cycle > 0:
		_bar_fill_style.bg_color = world_color.lerp(Color(0.42, 0.48, 0.54, 1.0), 0.78)


func _get_shield_pips_text(count: int) -> String:
	var clamped_count : int = max(0, count)
	if clamped_count <= 0:
		return ""
	return "■ ".repeat(clamped_count).strip_edges()


func _spawn_target_marker(target_position: Vector2) -> Sprite2D:
	var marker := Sprite2D.new()
	marker.texture = TARGET_MARKER_TEXTURE
	marker.centered = true
	marker.top_level = true
	marker.z_index = 40
	marker.modulate = _get_world_cannon_color()
	marker.scale = Vector2(0.34, 0.34)
	get_tree().current_scene.add_child(marker)
	marker.global_position = target_position
	return marker


func _configure_death_particles() -> void:
	if death_particles == null:
		return

	death_particles.emitting = false
	death_particles.one_shot = true
	death_particles.amount = DEATH_SCATTER_PARTICLE_COUNT

	var mat := death_particles.process_material as ParticleProcessMaterial
	if mat:
		mat.color = Color.WHITE
		mat.color_ramp = null


func _play_death_particles(hit_from: Vector2) -> void:
	if death_particles == null:
		return

	var scatter_direction := Vector2.UP
	if hit_from != Vector2.ZERO:
		scatter_direction = (global_position - hit_from).normalized()
	if scatter_direction == Vector2.ZERO:
		scatter_direction = Vector2.UP

	var world_color := _get_world_cannon_color()

	death_particles.global_position = global_position + scatter_direction * 8.0
	death_particles.global_rotation = scatter_direction.angle()
	death_particles.self_modulate = world_color
	death_particles.restart()
	death_particles.emitting = true


func _get_world_cannon_color() -> Color:
	match GameManager.current_world:
		1:
			return WORLD_1_CANNON_COLOR
		2:
			return WORLD_2_CANNON_COLOR
		3:
			return WORLD_3_CANNON_COLOR
		4:
			return WORLD_4_CANNON_COLOR
		5:
			return WORLD_5_CANNON_COLOR
		_:
			return DEFAULT_CANNON_COLOR
