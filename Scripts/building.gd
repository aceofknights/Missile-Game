extends Area2D

var destroyed := false
var permanently_destroyed := false
var shield_hits_remaining := 0
var shield_cooldown_remaining := 0.0

const WORLD_1_BUILDING_COLOR := Color(0.15, 0.45, 0.35, 1.0) # dark teal-green
const WORLD_2_BUILDING_COLOR := Color(0.45, 0.22, 0.18, 1.0) # dark rust
const WORLD_3_BUILDING_COLOR := Color(0.28, 0.18, 0.45, 1.0) # dark purple
const WORLD_4_BUILDING_COLOR := Color(0.18, 0.28, 0.42, 1.0) # dark blue
const WORLD_5_BUILDING_COLOR := Color(0.32, 0.45, 0.18, 1.0) # toxic green
const DEFAULT_BUILDING_COLOR := Color(0.35, 0.35, 0.35, 1.0)

@onready var sprite: Sprite2D = $Sprite2D
@onready var destroyed_sprite: Sprite2D = get_node_or_null("Destroyed") as Sprite2D
@onready var repair_label: Label = get_node_or_null("RepairLabel") as Label
@onready var shield_sprite: Sprite2D = Sprite2D.new()
@onready var shield_hits_label: Label = Label.new()


func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	add_to_group("building")
	add_to_group("defense_target")

	if repair_label:
		repair_label.top_level = true

	_setup_temp_shield_sprite()
	_setup_shield_hits_label()
	_update_visual_state()


func _process(delta: float) -> void:
	_update_shield_state(delta)
	_update_shield_hits_label()

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
		die()


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

	var now_seconds := Time.get_ticks_msec() / 1000.0
	if GameManager.is_passive_shield_emp_disabled(now_seconds):
		shield_hits_label.text = "EMP"
	else:
		shield_hits_label.text = "%d" % max(0, shield_hits_remaining)


func _update_shield_state(delta: float) -> void:
	var max_hits := GameManager.get_shield_generator_hit_capacity()

	if max_hits <= 0 or destroyed:
		shield_hits_remaining = 0
		shield_cooldown_remaining = 0.0
		if shield_sprite:
			shield_sprite.visible = false
		return

	var now_seconds := Time.get_ticks_msec() / 1000.0
	if GameManager.is_passive_shield_emp_disabled(now_seconds):
		if shield_sprite:
			shield_sprite.visible = false
		return

	if shield_hits_remaining <= 0:
		if shield_cooldown_remaining <= 0.0:
			shield_hits_remaining = max_hits
		else:
			shield_cooldown_remaining = maxf(0.0, shield_cooldown_remaining - delta)

	if shield_sprite:
		shield_sprite.visible = shield_hits_remaining > 0


func handle_enemy_impact(enemy: Area2D) -> bool:
	if destroyed:
		return false
	if enemy == null:
		return false

	var now_seconds := Time.get_ticks_msec() / 1000.0
	if GameManager.is_passive_shield_emp_disabled(now_seconds):
		return false

	if enemy.has_meta("building_shield_hit"):
		return true
	enemy.set_meta("building_shield_hit", true)

	_update_shield_state(0.0)

	if shield_hits_remaining > 0:
		shield_hits_remaining -= 1
		if shield_hits_remaining <= 0:
			shield_cooldown_remaining = GameManager.get_shield_generator_cooldown_seconds()
		enemy.call_deferred("die", true)
		return true

	return false


func die() -> void:
	if destroyed:
		return

	print("building destroyed")
	destroyed = true
	monitoring = false
	monitorable = false
	_update_visual_state()


func _update_visual_state() -> void:
	var world_color := _get_world_building_color()

	if sprite:
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
