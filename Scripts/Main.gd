extends Node2D

@onready var pause_menu = $PauseMenu
@onready var middle_cannon = $Cannon
@onready var left_cannon = $LeftCannon
@onready var right_cannon = $RightCannon
@onready var AmmoLabel = $UI/AmmoLabel
@onready var destroy_all_button = $UI/DestroyAllButton
@onready var wave_label = $UI/WaveLabel
@onready var announcement_label = $UI/AnnouncementLabel
@onready var repair_hint_label: Label = get_node_or_null("UI/RepairHintLabel") as Label
@onready var ResourceLabel = $UI/ResourceLabel
@onready var building5 = $Building5
@onready var building6 = $Building6
@onready var skip_to_boss = $UI/SkipToBoss
@onready var give_resources = $UI/GiveResources
@onready var ground: CanvasItem = $Ground
@onready var end_state_overlay: Control = $UI/EndStateOverlay
@onready var end_state_label: Label = $UI/EndStateOverlay/CenterContainer/Panel/VBoxContainer/EndStateLabel
@onready var end_state_continue_button: Button = $UI/EndStateOverlay/CenterContainer/Panel/VBoxContainer/ContinueButton


const EXPLOSION_SCENE := preload("res://Scene/explosion.tscn")
const AUTO_CANNON_SHOT_SCENE := preload("res://Scene/fighter_intercept_shot.tscn")
const TEMP_SHIELD_TEXTURE := preload("res://assets/ShieldUfo.png")
const ION_WAVE_TEXTURE := preload("res://assets/Ion Zone.png")
const BOSS_DEATH_EXPLOSION_COUNT := 16
const PLAYER_DEATH_EXPLOSION_COUNT := 14
const BOSS_DEATH_EXPLOSION_INTERVAL := 0.07
const PLAYER_DEATH_EXPLOSION_INTERVAL := 0.08
const DEFAULT_BOSS_EXPLOSION_SIZE := Vector2(240.0, 140.0)
const PLAYER_BOTTOM_EXPLOSION_Y_MARGIN := 18.0

@export var world_1_ground_color: Color = Color(0.15, 0.45, 0.35, 1.0) # dark teal-green
@export var world_2_ground_color: Color = Color(0.45, 0.22, 0.18, 1.0) # dark rust
@export var world_3_ground_color: Color = Color(0.28, 0.18, 0.45, 1.0) # dark purple
@export var world_4_ground_color: Color = Color(0.18, 0.28, 0.42, 1.0) # dark blue
@export var world_5_ground_color: Color = Color(0.32, 0.45, 0.18, 1.0) # toxic green
@export var default_ground_color: Color = Color(0.35, 0.35, 0.35, 1.0)

var _last_ground_world: int = -1
var base_buildings = 4
var extra_buildings = 0
var _end_menu_active := false
var _end_flow_in_progress := false

const REPAIR_HINT_LINGER_SECONDS := 1.0
var _repair_hint_linger_remaining := 0.0
var _auto_cannon_timer := 0.0
var _active_shield_sprite: Sprite2D
var _w_was_down := false
var _e_was_down := false
var _active_shield_hitbox: Area2D
var _active_shield_collision: CollisionShape2D
var _auto_cannon_label: Label
var _auto_cannon_bar: ProgressBar
var _ion_label: Label
var _ion_bar: ProgressBar
var _lure_label: Label
var _lure_bar: ProgressBar
var _shield_energy_label: Label
var _shield_energy_bar: ProgressBar
var _shield_emp_warn_cooldown := 0.0


func get_building_count() -> int:
	return base_buildings + GameManager.get_extra_buildings()


func _enter_tree() -> void:
	child_entered_tree.connect(_on_child_entered_tree)


func _on_child_entered_tree(node: Node) -> void:
	_connect_boss_signals(node)


func _ready() -> void:
	_ensure_repair_hint_label()
	_apply_ground_color()

	NodeContracts.require_nodes_with_types(self, {
		"Cannon": "Area2D",
		"LeftCannon": "Area2D",
		"RightCannon": "Area2D",
		"Spawner": "Node2D",
		"UI": "CanvasLayer",
		"UI/AmmoLabel": "Label",
		"UI/ResourceLabel": "Label",
		"UI/WaveLabel": "Label",
		"UI/DestroyAllButton": "Button",
		"PauseMenu": "CanvasLayer"
	})

	get_tree().paused = false
	pause_menu.hide()

	if repair_hint_label:
		repair_hint_label.visible = false
		repair_hint_label.modulate.a = 1.0

	print("Main game started: Wave %d, World %d" % [GameManager.current_wave, GameManager.current_world])

	destroy_all_button.pressed.connect(_on_destroy_all_pressed)
	skip_to_boss.pressed.connect(_skip_to_boss)
	give_resources.pressed.connect(_give_resource)
	end_state_continue_button.pressed.connect(_on_end_state_continue_pressed)
	end_state_overlay.visible = false

	GameManager.connect("announce_wave", Callable(self, "_on_announce_wave"))
	if not GameManager.world_victory_requested.is_connected(Callable(self, "_on_world_victory_requested")):
		GameManager.world_victory_requested.connect(_on_world_victory_requested)
	if not GameManager.player_defeat_requested.is_connected(Callable(self, "_on_player_defeat_requested")):
		GameManager.player_defeat_requested.connect(_on_player_defeat_requested)
	GameManager.start_wave()
	_apply_building_unlocks()
	_create_active_shield_sprite()
	_create_ability_status_ui()

	# Connect to any boss already present in the scene.
	for node in get_tree().get_nodes_in_group("enemy"):
		_connect_boss_signals(node)

func _apply_ground_color() -> void:
	if ground == null:
		return

	if _last_ground_world == GameManager.current_world:
		return

	_last_ground_world = GameManager.current_world

	match GameManager.current_world:
		1:
			ground.modulate = world_1_ground_color
		2:
			ground.modulate = world_2_ground_color
		3:
			ground.modulate = world_3_ground_color
		4:
			ground.modulate = world_4_ground_color
		5:
			ground.modulate = world_5_ground_color
		_:
			ground.modulate = default_ground_color

func _ensure_repair_hint_label() -> void:
	if repair_hint_label != null:
		return

	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return

	var label := Label.new()
	label.name = "RepairHintLabel"
	label.visible = false
	label.offset_left = 395.0
	label.offset_top = 346.0
	label.offset_right = 815.0
	label.offset_bottom = 569.0
	label.text = "Hit R to repair for cost: 20"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(label)
	repair_hint_label = label


func _give_resource() -> void:
	GameManager.player_resources += 10000


func _get_ordered_cannons() -> Array:
	return [middle_cannon, left_cannon, right_cannon]


func _fire_closest_cannon(target_position: Vector2) -> void:
	var best_cannon: Node = null
	var best_distance_sq: float = INF

	for cannon in _get_ordered_cannons():
		if cannon == null or not cannon.has_method("can_fire"):
			continue
		if not cannon.can_fire():
			continue

		var distance_sq: float = cannon.global_position.distance_squared_to(target_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_cannon = cannon

	if best_cannon != null and best_cannon.has_method("try_fire_at"):
		best_cannon.try_fire_at(target_position)


func _skip_to_boss() -> void:
	if GameManager.current_world == 1:
		GameManager.current_wave = 10
	elif GameManager.current_world == 2:
		GameManager.current_wave = 15
	elif GameManager.current_world == 3:
		GameManager.current_wave = 20
	elif GameManager.current_world == 4:
		GameManager.current_wave = 35
	elif GameManager.current_world == 5:
		GameManager.current_wave = 50


func _apply_building_unlocks() -> void:
	_set_building_active(building5, GameManager.get_extra_buildings() >= 1)
	_set_building_active(building6, GameManager.get_extra_buildings() >= 2)


func _set_building_active(b: Node, active: bool) -> void:
	if b == null:
		return

	if b is CanvasItem:
		b.visible = active

	if b is Area2D:
		b.monitoring = active
		b.monitorable = active
		var cs = b.get_node_or_null("CollisionShape2D")
		if cs:
			cs.disabled = not active

	if active:
		if not b.is_in_group("building"):
			b.add_to_group("building")
	else:
		if b.is_in_group("building"):
			b.remove_from_group("building")


func announce(text: String, duration: float = 2.0) -> void:
	announcement_label.text = text
	announcement_label.visible = true
	await get_tree().create_timer(duration).timeout
	announcement_label.visible = false


func _on_destroy_all_pressed() -> void:
	GameManager.wave_active = false
	GameManager.enemies_alive = 0
	GameManager.spawner = null

	var buildings = get_tree().get_nodes_in_group("building")
	for b in buildings:
		if b and b.has_method("die"):
			b.die()

	print("🔧 All buildings destroyed (debug)")


func _process(delta: float) -> void:
	if _end_menu_active:
		return

	GameManager.update_ammo_factory(delta)
	GameManager.update_active_shield(delta)
	_handle_upgrade_hotkeys()
	_update_auto_cannon(delta)
	_update_active_shield_visual()
	_update_ability_status_ui()
	_shield_emp_warn_cooldown = maxf(0.0, _shield_emp_warn_cooldown - delta)
	AmmoLabel.text = "Ammo: %s" % GameManager.get_total_ammo_status()
	wave_label.text = "🌊 Wave %d / 🌍 World %d" % [GameManager.current_wave, GameManager.current_world]
	ResourceLabel.text = "Resources: %d" % GameManager.player_resources
	_apply_ground_color()
	_update_repair_hint(delta)

	if _count_surviving_buildings() == 0 and not _end_flow_in_progress:
		print("🏚️ All buildings destroyed — returning to upgrade screen")
		GameManager.player_died()


func _create_active_shield_sprite() -> void:
	_active_shield_hitbox = Area2D.new()
	_active_shield_hitbox.collision_layer = 4
	_active_shield_hitbox.collision_mask = 1
	_active_shield_hitbox.monitoring = true
	_active_shield_hitbox.monitorable = true
	_active_shield_hitbox.position = Vector2(576, 560)
	_active_shield_hitbox.add_to_group("active_base_shield")
	add_child(_active_shield_hitbox)

	_active_shield_sprite = Sprite2D.new()
	_active_shield_sprite.texture = TEMP_SHIELD_TEXTURE
	_active_shield_sprite.modulate = Color(0.3, 0.9, 1.0, 0.35)
	_active_shield_sprite.visible = false
	_active_shield_sprite.z_index = 500
	_active_shield_sprite.scale = Vector2(2.8, 0.8)
	_active_shield_hitbox.add_child(_active_shield_sprite)

	_active_shield_collision = CollisionShape2D.new()
	var shield_shape := EllipseShape2D.new()
	shield_shape.radius = Vector2(220, 88)
	_active_shield_collision.shape = shield_shape
	_active_shield_collision.disabled = true
	_active_shield_hitbox.add_child(_active_shield_collision)


func _handle_upgrade_hotkeys() -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var hold_space := Input.is_key_pressed(KEY_SPACE)
	if hold_space and GameManager.is_active_shield_emp_disabled(now_seconds) and _shield_emp_warn_cooldown <= 0.0:
		announce("⚠ Shield disabled by EMP!", 0.6)
		_shield_emp_warn_cooldown = 0.8
	GameManager.set_active_shield_held(hold_space)
	var w_down := Input.is_key_pressed(KEY_W)
	if w_down and not _w_was_down:
		_w_was_down = true
		if GameManager.can_trigger_ion_wave(now_seconds):
			GameManager.trigger_ion_wave(now_seconds)
			_spawn_ion_wave_animation()
			announce("⚡ Ion Wave Activated!", 1.2)
	if not w_down:
		_w_was_down = false

	var e_down := Input.is_key_pressed(KEY_E)
	if e_down and not _e_was_down:
		_e_was_down = true
		if GameManager.can_trigger_lure(now_seconds):
			GameManager.trigger_lure(get_global_mouse_position(), now_seconds)
			announce("🎯 Lure Deployed!", 1.0)
	if not e_down:
		_e_was_down = false


func _update_auto_cannon(delta: float) -> void:
	var level := GameManager.get_upgrade_level("auto_cannon")
	if level <= 0:
		return

	_auto_cannon_timer -= delta
	if _auto_cannon_timer > 0.0:
		return

	var fire_interval := maxf(2.0, 20.0 - (2.0 * float(level)))

	var best_enemy: Area2D = null
	var best_dist_sq := INF
	for node in get_tree().get_nodes_in_group("enemy"):
		if not (node is Area2D):
			continue
		if _is_boss_enemy(node):
			continue
		var as_area := node as Area2D
		var dist_sq := as_area.global_position.distance_squared_to(middle_cannon.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_enemy = as_area

	if best_enemy == null:
		return

	var shot := AUTO_CANNON_SHOT_SCENE.instantiate()
	if shot == null:
		return
	_auto_cannon_timer = fire_interval
	shot.global_position = middle_cannon.global_position
	shot.target_node = best_enemy
	shot.target_position = best_enemy.global_position
	add_child(shot)


func _is_boss_enemy(node: Node) -> bool:
	if node == null:
		return false
	if node.is_in_group("boss"):
		return true
	if node.has_signal("boss_defeated"):
		return true
	return String(node.name).to_lower().begins_with("boss")


func _update_active_shield_visual() -> void:
	if _active_shield_sprite == null:
		return
	var active := GameManager.is_active_shield_up()
	_active_shield_sprite.visible = active
	if _active_shield_collision:
		_active_shield_collision.disabled = not active


func _create_ability_status_ui() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return

	_auto_cannon_label = Label.new()
	_auto_cannon_label.text = "Auto Cannon"
	_auto_cannon_label.offset_left = 20
	_auto_cannon_label.offset_top = 60
	_auto_cannon_label.offset_right = 220
	_auto_cannon_label.offset_bottom = 80
	ui.add_child(_auto_cannon_label)

	_auto_cannon_bar = ProgressBar.new()
	_auto_cannon_bar.min_value = 0.0
	_auto_cannon_bar.max_value = 1.0
	_auto_cannon_bar.show_percentage = false
	_auto_cannon_bar.offset_left = 20
	_auto_cannon_bar.offset_top = 82
	_auto_cannon_bar.offset_right = 220
	_auto_cannon_bar.offset_bottom = 100
	ui.add_child(_auto_cannon_bar)

	_ion_label = Label.new()
	_ion_label.text = "Ion Wave Cooldown"
	_ion_label.offset_left = 20
	_ion_label.offset_top = 106
	_ion_label.offset_right = 220
	_ion_label.offset_bottom = 126
	ui.add_child(_ion_label)

	_ion_bar = ProgressBar.new()
	_ion_bar.min_value = 0.0
	_ion_bar.max_value = 1.0
	_ion_bar.show_percentage = false
	_ion_bar.offset_left = 20
	_ion_bar.offset_top = 128
	_ion_bar.offset_right = 220
	_ion_bar.offset_bottom = 146
	ui.add_child(_ion_bar)

	_lure_label = Label.new()
	_lure_label.text = "Lure Cooldown"
	_lure_label.offset_left = 20
	_lure_label.offset_top = 152
	_lure_label.offset_right = 220
	_lure_label.offset_bottom = 172
	ui.add_child(_lure_label)

	_lure_bar = ProgressBar.new()
	_lure_bar.min_value = 0.0
	_lure_bar.max_value = 1.0
	_lure_bar.show_percentage = false
	_lure_bar.offset_left = 20
	_lure_bar.offset_top = 174
	_lure_bar.offset_right = 220
	_lure_bar.offset_bottom = 192
	ui.add_child(_lure_bar)

	_shield_energy_label = Label.new()
	_shield_energy_label.text = "Active Shield Energy"
	_shield_energy_label.offset_left = 20
	_shield_energy_label.offset_top = 198
	_shield_energy_label.offset_right = 260
	_shield_energy_label.offset_bottom = 218
	ui.add_child(_shield_energy_label)

	_shield_energy_bar = ProgressBar.new()
	_shield_energy_bar.min_value = 0.0
	_shield_energy_bar.max_value = 1.0
	_shield_energy_bar.show_percentage = false
	_shield_energy_bar.offset_left = 20
	_shield_energy_bar.offset_top = 220
	_shield_energy_bar.offset_right = 260
	_shield_energy_bar.offset_bottom = 238
	ui.add_child(_shield_energy_bar)


func _update_ability_status_ui() -> void:
	var auto_level := GameManager.get_upgrade_level("auto_cannon")
	var auto_interval := maxf(2.0, 20.0 - (2.0 * float(auto_level)))
	var auto_ready_ratio := 1.0
	if auto_level > 0:
		auto_ready_ratio = clampf(1.0 - (_auto_cannon_timer / auto_interval), 0.0, 1.0)

	if _auto_cannon_label:
		_auto_cannon_label.visible = auto_level > 0
		_auto_cannon_label.text = "Auto Cannon: %s" % ("READY" if _auto_cannon_timer <= 0.0 and auto_level > 0 else "Charging")
	if _auto_cannon_bar:
		_auto_cannon_bar.visible = auto_level > 0
		_auto_cannon_bar.value = auto_ready_ratio

	var now_seconds := Time.get_ticks_msec() / 1000.0
	var ion_level := GameManager.get_upgrade_level("ion_wave")
	var ion_cd := GameManager.get_ion_wave_cooldown_remaining(now_seconds)
	var ion_max_cd := GameManager.get_ion_wave_recharge_time()
	var ion_ready_ratio := 1.0
	if ion_level > 0:
		ion_ready_ratio = clampf(1.0 - (ion_cd / maxf(0.01, ion_max_cd)), 0.0, 1.0)
		if GameManager.is_ion_wave_active(now_seconds):
			ion_ready_ratio = 1.0

	if _ion_label:
		_ion_label.visible = ion_level > 0
		if ion_level > 0 and GameManager.is_ion_wave_active(now_seconds):
			_ion_label.text = "Ion Wave: ACTIVE %.1fs" % maxf(0.0, GameManager.ion_wave_end_time - now_seconds)
		else:
			_ion_label.text = "Ion Wave: %s" % ("READY" if ion_cd <= 0.0 and ion_level > 0 else "%.1fs" % ion_cd)
	if _ion_bar:
		_ion_bar.visible = ion_level > 0
		_ion_bar.value = ion_ready_ratio

	var lure_level := GameManager.get_upgrade_level("lure")
	var lure_cd := GameManager.get_lure_cooldown_remaining(now_seconds)
	var lure_max_cd := GameManager.get_lure_recharge_time()
	var lure_ready_ratio := 1.0
	if lure_level > 0:
		lure_ready_ratio = clampf(1.0 - (lure_cd / maxf(0.01, lure_max_cd)), 0.0, 1.0)

	if _lure_label:
		_lure_label.visible = lure_level > 0
		if lure_level > 0 and GameManager.is_lure_active(now_seconds):
			_lure_label.text = "Lure: ACTIVE %.1fs" % maxf(0.0, GameManager.lure_end_time - now_seconds)
		else:
			_lure_label.text = "Lure: %s" % ("READY" if lure_cd <= 0.0 and lure_level > 0 else "%.1fs" % lure_cd)
	if _lure_bar:
		_lure_bar.visible = lure_level > 0
		_lure_bar.value = lure_ready_ratio

	var active_shield_level := GameManager.get_upgrade_level("active_shields")
	var shield_ratio := 0.0
	if GameManager.active_shield_max_charge > 0.0:
		shield_ratio = clampf(GameManager.active_shield_charge / GameManager.active_shield_max_charge, 0.0, 1.0)

	if _shield_energy_label:
		_shield_energy_label.visible = active_shield_level > 0
		if GameManager.is_active_shield_emp_disabled(now_seconds):
			_shield_energy_label.text = "Active Shield: EMP %.1fs" % GameManager.get_active_shield_emp_disabled_remaining(now_seconds)
		else:
			_shield_energy_label.text = "Active Shield Energy: %d%%" % int(round(shield_ratio * 100.0))
	if _shield_energy_bar:
		_shield_energy_bar.visible = active_shield_level > 0
		_shield_energy_bar.value = shield_ratio


func _spawn_ion_wave_animation() -> void:
	var wave := Sprite2D.new()
	wave.texture = ION_WAVE_TEXTURE
	wave.position = Vector2(576, 640)
	wave.modulate = Color(0.6, 0.95, 1.0, 0.55)
	wave.scale = Vector2(0.25, 0.05)
	wave.z_index = 450
	add_child(wave)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector2(4.5, 1.5), 0.8)
	tween.tween_property(wave, "position", Vector2(576, 280), 0.8)
	tween.tween_property(wave, "modulate:a", 0.0, 1.2)
	tween.finished.connect(func(): wave.queue_free())


func _update_repair_hint(delta: float) -> void:
	if repair_hint_label == null:
		return

	if not GameManager.can_use_repair_shop():
		repair_hint_label.visible = false
		_repair_hint_linger_remaining = 0.0
		return

	var hovered_destroyed_target = _find_hovered_destroyed_defense()
	if hovered_destroyed_target != null:
		_repair_hint_linger_remaining = REPAIR_HINT_LINGER_SECONDS
		repair_hint_label.modulate.a = 1.0
		repair_hint_label.text = "Hit R to repair for cost: %d" % GameManager.get_repair_shop_cost()
		repair_hint_label.visible = true
		return

	if _repair_hint_linger_remaining > 0.0:
		_repair_hint_linger_remaining = maxf(0.0, _repair_hint_linger_remaining - delta)
		repair_hint_label.modulate.a = _repair_hint_linger_remaining / REPAIR_HINT_LINGER_SECONDS
		repair_hint_label.visible = true
		return

	repair_hint_label.modulate.a = 1.0
	repair_hint_label.visible = false


func _count_surviving_buildings() -> int:
	var total := 0
	for b in get_tree().get_nodes_in_group("building"):
		if b and b.has_method("is_destroyed") and not b.is_destroyed():
			total += 1
	return total


func _find_hovered_destroyed_defense() -> Node:
	var mouse_pos: Vector2 = get_global_mouse_position()

	for cannon in _get_ordered_cannons():
		if cannon and cannon.has_method("is_hovered") and cannon.is_hovered(mouse_pos):
			return cannon

	for b in get_tree().get_nodes_in_group("building"):
		if b and b.has_method("is_hovered") and b.is_hovered(mouse_pos):
			return b

	return null


func _on_boss_jam_charge_started(_duration: float) -> void:
	announce("⚠ Relay charging: incoming target jam", 0.8)


func _on_boss_jam_pulse_started(duration: float, misfire_radius: float) -> void:
	print("🌀 Boss jam pulse: duration=%.2f radius=%.1f" % [duration, misfire_radius])
	announce("📡 Targeting JAMMED", minf(duration, 1.4))

	for cannon in get_tree().get_nodes_in_group("cannon"):
		if cannon == null:
			continue
		if cannon.has_method("is_destroyed") and cannon.is_destroyed():
			continue
		if cannon.has_method("apply_targeting_jam"):
			cannon.apply_targeting_jam(duration, misfire_radius)


func _attempt_repair_hovered_defense() -> void:
	if not GameManager.can_use_repair_shop():
		return

	var target = _find_hovered_destroyed_defense()
	if target == null:
		return

	var cost: int = GameManager.get_repair_shop_cost()
	if GameManager.player_resources < cost:
		return

	if target.has_method("repair"):
		GameManager.player_resources -= cost
		target.repair()
		if repair_hint_label:
			_repair_hint_linger_remaining = REPAIR_HINT_LINGER_SECONDS


func _unhandled_input(event: InputEvent) -> void:
	if _end_menu_active:
		return

	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			pause_menu.hide_pause_menu()
		else:
			pause_menu.show_pause_menu()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_fire_closest_cannon(get_global_mouse_position())
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_attempt_repair_hovered_defense()


func _on_wave_cleared() -> void:
	GameManager.start_next_wave()


func _on_player_died() -> void:
	GameManager.player_died()


func _on_announce_wave(message: String, duration: float) -> void:
	announce(message, duration)


func _on_world_victory_requested() -> void:
	if _end_flow_in_progress:
		return

	_end_flow_in_progress = true
	var boss := _find_boss_candidate()
	var explosion_center: Vector2 = Vector2(get_viewport_rect().size.x * 0.5, 120.0)
	var explosion_size := DEFAULT_BOSS_EXPLOSION_SIZE
	if boss != null:
		explosion_center = boss.global_position
		explosion_size = _estimate_boss_body_size(boss)

	await _spawn_burst_explosions_in_rect(explosion_center, explosion_size, BOSS_DEATH_EXPLOSION_COUNT, BOSS_DEATH_EXPLOSION_INTERVAL)
	_show_end_menu("VICTORY")
	_end_flow_in_progress = false


func _on_player_defeat_requested() -> void:
	if _end_flow_in_progress:
		return

	_end_flow_in_progress = true
	await _spawn_bottom_explosions(PLAYER_DEATH_EXPLOSION_COUNT, PLAYER_DEATH_EXPLOSION_INTERVAL)
	_show_end_menu("DEFEAT")
	_end_flow_in_progress = false


func _show_end_menu(title_text: String) -> void:
	_end_menu_active = true
	end_state_label.text = title_text
	end_state_overlay.visible = true
	pause_menu.visible = false
	get_tree().paused = true


func _on_end_state_continue_pressed() -> void:
	get_tree().paused = false
	_end_menu_active = false
	end_state_overlay.visible = false

	if end_state_label.text == "VICTORY":
		GameManager.continue_after_victory()
	else:
		GameManager.continue_after_player_defeat()


func _spawn_burst_explosions_in_rect(center: Vector2, size: Vector2, count: int, spacing_seconds: float) -> void:
	var half_size: Vector2 = size * 0.5
	for _i in range(count):
		var random_offset := Vector2(
			randf_range(-half_size.x, half_size.x),
			randf_range(-half_size.y, half_size.y)
		)
		_spawn_explosion(center + random_offset)
		await get_tree().create_timer(spacing_seconds).timeout


func _spawn_bottom_explosions(count: int, spacing_seconds: float) -> void:
	var viewport_size := get_viewport_rect().size
	var y := viewport_size.y - PLAYER_BOTTOM_EXPLOSION_Y_MARGIN
	for _i in range(count):
		var random_x := randf_range(40.0, viewport_size.x - 40.0)
		var random_y := randf_range(y - 36.0, y)
		_spawn_explosion(Vector2(random_x, random_y))
		await get_tree().create_timer(spacing_seconds).timeout


func _spawn_explosion(world_position: Vector2) -> void:
	var explosion = EXPLOSION_SCENE.instantiate()
	explosion.global_position = world_position
	explosion.gives_reward = false
	add_child(explosion)


func _find_boss_candidate() -> Area2D:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Area2D and enemy.has_signal("boss_defeated"):
			return enemy
	return null


func _estimate_boss_body_size(boss: Area2D) -> Vector2:
	var sprite := boss.get_node_or_null("Sprite2D") as Sprite2D
	if sprite and sprite.texture:
		return sprite.texture.get_size() * sprite.global_scale

	var collision_shape := boss.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rect_shape := collision_shape.shape as RectangleShape2D
		return rect_shape.size * collision_shape.global_scale

	if collision_shape and collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		var diameter := circle_shape.radius * 2.0
		return Vector2(diameter, diameter) * collision_shape.global_scale

	return DEFAULT_BOSS_EXPLOSION_SIZE


func _connect_boss_signals(boss: Node) -> void:
	if boss == null:
		return

	if boss.has_signal("jam_charge_started"):
		var charge_callable := Callable(self, "_on_boss_jam_charge_started")
		if not boss.jam_charge_started.is_connected(charge_callable):
			boss.jam_charge_started.connect(charge_callable)

	if boss.has_signal("jam_pulse_started"):
		var pulse_callable := Callable(self, "_on_boss_jam_pulse_started")
		if not boss.jam_pulse_started.is_connected(pulse_callable):
			boss.jam_pulse_started.connect(pulse_callable)
