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

var base_buildings = 4
var extra_buildings = 0
const REPAIR_HINT_LINGER_SECONDS := 1.0
var _repair_hint_linger_remaining := 0.0


func get_building_count():
	return base_buildings + GameManager.get_extra_buildings()


func _ready():
	_ensure_repair_hint_label()
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
	GameManager.connect("announce_wave", Callable(self, "_on_announce_wave"))
	GameManager.start_wave()
	_apply_building_unlocks()
	give_resources.pressed.connect(_give_resource)


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
	label.offset_top = 546.0
	label.offset_right = 815.0
	label.offset_bottom = 569.0
	label.text = "Hit R to repair for cost: 20"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(label)
	repair_hint_label = label


func _give_resource():
	GameManager.player_resources += 100


func _get_ordered_cannons() -> Array:
	return [middle_cannon, left_cannon, right_cannon]


func _fire_closest_cannon(target_position: Vector2) -> void:
	var best_cannon: Node = null
	var best_distance_sq := INF

	for cannon in _get_ordered_cannons():
		if cannon == null or not cannon.has_method("can_fire"):
			continue
		if not cannon.can_fire():
			continue
		var distance_sq = cannon.global_position.distance_squared_to(target_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_cannon = cannon

	if best_cannon != null and best_cannon.has_method("try_fire_at"):
		best_cannon.try_fire_at(target_position)


func _skip_to_boss():
	GameManager.current_wave = 10


func _apply_building_unlocks():
	_set_building_active(building5, GameManager.get_extra_buildings() >= 1)
	_set_building_active(building6, GameManager.get_extra_buildings() >= 2)


func _set_building_active(b: Node, active: bool):
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


func announce(text: String, duration: float = 2.0):
	announcement_label.text = text
	announcement_label.visible = true
	await get_tree().create_timer(duration).timeout
	announcement_label.visible = false


func _on_destroy_all_pressed():
	GameManager.wave_active = false
	GameManager.enemies_alive = 0
	GameManager.spawner = null

	var buildings = get_tree().get_nodes_in_group("building")
	for b in buildings:
		if b and b.has_method("die"):
			b.die()
	print("🔧 All buildings destroyed (debug)")


func _process(delta):
	GameManager.update_ammo_factory(delta)
	AmmoLabel.text = "Ammo: %s" % GameManager.get_total_ammo_status()
	wave_label.text = "🌊 Wave %d / 🌍 World %d" % [GameManager.current_wave, GameManager.current_world]
	ResourceLabel.text = "Resources: %d" % GameManager.player_resources
	_update_repair_hint(delta)

	if _count_surviving_buildings() == 0:
		print("🏚️ All buildings destroyed — returning to upgrade screen")
		GameManager.player_died()


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
		_repair_hint_linger_remaining = max(0.0, _repair_hint_linger_remaining - delta)
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
	var mouse_pos = get_global_mouse_position()

	for cannon in _get_ordered_cannons():
		if cannon and cannon.has_method("is_hovered") and cannon.is_hovered(mouse_pos):
			return cannon

	for b in get_tree().get_nodes_in_group("building"):
		if b and b.has_method("is_hovered") and b.is_hovered(mouse_pos):
			return b

	return null


func _attempt_repair_hovered_defense() -> void:
	if not GameManager.can_use_repair_shop():
		return
	var target = _find_hovered_destroyed_defense()
	if target == null:
		return
	var cost = GameManager.get_repair_shop_cost()
	if GameManager.player_resources < cost:
		return
	if target.has_method("repair"):
		GameManager.player_resources -= cost
		target.repair()
		if repair_hint_label:
			_repair_hint_linger_remaining = REPAIR_HINT_LINGER_SECONDS


func _unhandled_input(event):
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


func _on_wave_cleared():
	GameManager.start_next_wave()


func _on_player_died():
	GameManager.player_died()


func _on_announce_wave(message: String, duration: float):
	announce(message, duration)
