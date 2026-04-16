extends Area2D

var destroyed := false
var permanently_destroyed := false
var shield_hits_remaining := 0
var emp_shield_disabled_remaining := 0.0
var _destruction_reaction_in_progress := false
const WORLD_1_BUILDING_COLOR := Color(0.15, 0.45, 0.35, 1.0) # dark teal-green
const WORLD_2_BUILDING_COLOR := Color(0.45, 0.22, 0.18, 1.0) # dark rust
const WORLD_3_BUILDING_COLOR := Color(0.28, 0.18, 0.45, 1.0) # dark purple
const WORLD_4_BUILDING_COLOR := Color(0.18, 0.28, 0.42, 1.0) # dark blue
const WORLD_5_BUILDING_COLOR := Color(0.32, 0.45, 0.18, 1.0) # toxic green
const DEFAULT_BUILDING_COLOR := Color(0.35, 0.35, 0.35, 1.0)
const DEATH_SCATTER_PARTICLE_TEXTURE := preload("res://circle.png")
const DEATH_SCATTER_PARTICLE_COUNT := 22
const DEATH_SCATTER_LIFETIME := 0.65
const DEATH_SCATTER_VELOCITY_MIN := 140.0
const DEATH_SCATTER_VELOCITY_MAX := 340.0
const DEATH_SCATTER_GRAVITY := 720.0

const WAVE_AMMO_ICON_TEXTURE := preload("res://assets/UpgradeIcons/yellow plus ammo.png")
@export var WAVE_AMMO_ICON_TEXTURE_COLOR := Color(1,1,1,1)

@onready var sprite: Sprite2D = $Sprite2D
@onready var destroyed_sprite: Sprite2D = get_node_or_null("Destroyed") as Sprite2D
@onready var death_particles: GPUParticles2D = get_node_or_null("DeathParticles") as GPUParticles2D
@onready var repair_label: Label = get_node_or_null("RepairLabel") as Label
@onready var shield_sprite: Sprite2D = Sprite2D.new()
@onready var shield_hits_label: Label = Label.new()
var _sprite_rest_position: Vector2 = Vector2.ZERO
var _sprite_rest_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	add_to_group("building")
	add_to_group("defense_target")

	if repair_label:
		repair_label.top_level = true

	_setup_temp_shield_sprite()
	_setup_shield_hits_label()
	_reset_passive_shield_for_wave()
	_cache_visual_rest_state()
	_configure_death_particles()
	_update_visual_state()


func _process(_delta: float) -> void:
	_update_shield_state()
	_update_shield_hits_label()
	if emp_shield_disabled_remaining > 0.0:
		emp_shield_disabled_remaining = maxf(0.0, emp_shield_disabled_remaining - _delta)
		
	if not repair_label:
		return

	repair_label.global_position = global_position + Vector2(-70, -64)
	repair_label.visible = false


func _on_area_entered(area: Area2D) -> void:
	if destroyed:
		return

	if area.is_in_group("enemy"):
		if handle_enemy_impact(area):
			return

		print("Building destroyed by Enemy")
		area.call_deferred("die", false)
		die(area.global_position)


func _setup_temp_shield_sprite() -> void:
	shield_sprite.texture = preload("res://assets/ShieldUfo.png")
	shield_sprite.modulate = Color(0.4, 0.95, 1.0, 0.35)
	shield_sprite.scale = Vector2(0.13, 0.1)
	shield_sprite.visible = false
	add_child(shield_sprite)


func _setup_shield_hits_label() -> void:
	shield_hits_label.top_level = false
	shield_hits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shield_hits_label.add_theme_color_override("font_color", Color(0.9, 1.0, 1.0, 1.0))
	shield_hits_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	shield_hits_label.add_theme_constant_override("outline_size", 2)
	shield_hits_label.visible = false
	shield_hits_label.z_index = 25
	add_child(shield_hits_label)


func _update_shield_hits_label() -> void:
	if shield_hits_label == null:
		return

	shield_hits_label.position = Vector2(-5, 10)

	var max_hits := GameManager.get_shield_generator_hit_capacity()
	var show := max_hits > 0 and not destroyed
	shield_hits_label.visible = show
	if not show:
		return

	if _is_passive_shield_blocked_by_emp():
		shield_hits_label.text = "EMP"
	else:
		shield_hits_label.text = "%d" % max(0, shield_hits_remaining)


func _update_shield_state() -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()

	if max_hits <= 0 or destroyed:
		shield_hits_remaining = 0
		if shield_sprite:
			shield_sprite.visible = false
		return

	if shield_hits_remaining < 0:
		shield_hits_remaining = 0
	elif shield_hits_remaining > max_hits:
		shield_hits_remaining = max_hits

	if shield_sprite:
		shield_sprite.visible = shield_hits_remaining > 0 and not _is_passive_shield_blocked_by_emp()


func _reset_passive_shield_for_wave() -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()
	if max_hits > 0 and not destroyed:
		shield_hits_remaining = max_hits
	else:
		shield_hits_remaining = 0


func _is_passive_shield_blocked_by_emp() -> bool:
	return emp_shield_disabled_remaining > 0.0
	
func has_active_shield() -> bool:
	return not destroyed and shield_hits_remaining > 0 and not _is_passive_shield_blocked_by_emp()


func disable_shield_temporarily(duration: float) -> void:
	if destroyed:
		return
	if shield_hits_remaining <= 0:
		return

	emp_shield_disabled_remaining = maxf(emp_shield_disabled_remaining, maxf(0.1, duration))
	_update_shield_state()
	_update_shield_hits_label()
	

func handle_enemy_impact(enemy: Area2D) -> bool:
	if destroyed:
		return false
	if enemy == null:
		return false
	if _is_passive_shield_blocked_by_emp():
		return false

	if enemy.has_meta("building_shield_hit"):
		return true
	enemy.set_meta("building_shield_hit", true)

	_update_shield_state()

	if shield_hits_remaining > 0:
		shield_hits_remaining -= 1
		shield_hits_remaining = max(0, shield_hits_remaining)
		enemy.call_deferred("die", true)
		return true

	return false


func die(hit_from: Vector2 = Vector2.ZERO) -> void:
	if destroyed or _destruction_reaction_in_progress:
		return

	_destruction_reaction_in_progress = true
	monitoring = false
	monitorable = false
	await _play_hit_reaction(hit_from)
	_play_death_particles(hit_from)

	print("building destroyed")
	destroyed = true
	_destruction_reaction_in_progress = false
	_update_visual_state()


func _update_visual_state() -> void:
	var world_color := _get_world_building_color()

	if sprite:
		sprite.position = _sprite_rest_position
		sprite.scale = _sprite_rest_scale
		sprite.modulate = world_color
		sprite.visible = not destroyed

	if destroyed_sprite:
		destroyed_sprite.visible = destroyed
		if not destroyed:
			destroyed_sprite.modulate = world_color


func _get_world_building_color() -> Color:
	match GameManager.current_world:
		1:
			return WORLD_1_BUILDING_COLOR
		2:
			return WORLD_2_BUILDING_COLOR
		3:
			return WORLD_3_BUILDING_COLOR
		4:
			return WORLD_4_BUILDING_COLOR
		5:
			return WORLD_5_BUILDING_COLOR
		_:
			return DEFAULT_BUILDING_COLOR


func is_destroyed() -> bool:
	return destroyed


func _cache_visual_rest_state() -> void:
	if sprite:
		_sprite_rest_position = sprite.position
		_sprite_rest_scale = sprite.scale


func _play_hit_reaction(hit_from: Vector2) -> void:
	if sprite == null:
		return

	var world_color := _get_world_building_color()
	var impact_dir := Vector2.ZERO
	if hit_from != Vector2.ZERO:
		impact_dir = (global_position - hit_from).normalized()
	if impact_dir == Vector2.ZERO:
		impact_dir = Vector2(0.0, -1.0)

	var nudge := impact_dir * 5.0
	var flash_color := world_color.lerp(Color.WHITE, 0.75)
	var squash_scale := Vector2(_sprite_rest_scale.x * 1.08, _sprite_rest_scale.y * 0.9)

	sprite.position = _sprite_rest_position
	sprite.scale = _sprite_rest_scale
	sprite.modulate = world_color

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "position", _sprite_rest_position + nudge, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", squash_scale, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate", flash_color, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished


func play_wave_ammo_bonus_animation(icon_count: int) -> void:
	if destroyed:
		return

	var total_icons: int = clamp(icon_count, 1, 2)
	for i in range(total_icons):
		_spawn_wave_ammo_icon(i, total_icons)


func _spawn_wave_ammo_icon(icon_index: int, total_icons: int) -> void:
	var icon := Sprite2D.new()
	icon.texture = WAVE_AMMO_ICON_TEXTURE
	icon.z_index = 80
	icon.top_level = true
	icon.scale = Vector2(0.08, 0.08)

	var x_offset := 0.0
	if total_icons == 2:
		x_offset = -10.0 if icon_index == 0 else 10.0

	icon.global_position = global_position + Vector2(x_offset, -18.0)
	icon.modulate = Color(1.0, 1.0, 1.0, 0.0)
	get_tree().current_scene.add_child(icon)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(icon, "global_position", icon.global_position + Vector2(0.0, -42.0), 0.95)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "modulate:a", 1.0, 0.22)
	tween.chain().tween_property(icon, "modulate:a", 0.0, 0.45)
	tween.finished.connect(func() -> void:
		if is_instance_valid(icon):
			icon.queue_free()
	)


func _configure_death_particles() -> void:
	if death_particles == null:
		return
	death_particles.emitting = false
	death_particles.one_shot = true


func _play_death_particles(hit_from: Vector2) -> void:
	if death_particles == null:
		return

	var scatter_direction := Vector2.UP
	if hit_from != Vector2.ZERO:
		scatter_direction = (global_position - hit_from).normalized()
	if scatter_direction == Vector2.ZERO:
		scatter_direction = Vector2.UP

	death_particles.global_position = global_position + scatter_direction * 4.0
	death_particles.global_rotation = scatter_direction.angle()
	death_particles.modulate = _get_world_building_color().lerp(Color.WHITE, 0.45)
	death_particles.restart()
	death_particles.emitting = true


func is_hovered(global_mouse_position: Vector2) -> bool:
	if not destroyed:
		return false
	return _is_mouse_over_defense(global_mouse_position)


func is_hovered_any_state(global_mouse_position: Vector2) -> bool:
	return _is_mouse_over_defense(global_mouse_position)


func _is_mouse_over_defense(global_mouse_position: Vector2) -> bool:
	var target_sprite: Sprite2D = destroyed_sprite if destroyed and destroyed_sprite else sprite
	if target_sprite and target_sprite.texture:
		var local_mouse := target_sprite.to_local(global_mouse_position)
		if target_sprite.get_rect().has_point(local_mouse):
			return true
	return global_position.distance_to(global_mouse_position) <= 52.0


func repair() -> void:
	if permanently_destroyed:
		return
	destroyed = false
	monitoring = true
	monitorable = true
	_reset_passive_shield_for_wave()
	_update_visual_state()


func destroy_permanently() -> void:
	if permanently_destroyed:
		return

	permanently_destroyed = true
	destroyed = true
	monitoring = false
	monitorable = false

	if is_in_group("building"):
		remove_from_group("building")

	queue_free()
