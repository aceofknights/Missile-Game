extends Node2D

@onready var pause_menu = $PauseMenu
@onready var middle_cannon = $Cannon
@onready var left_cannon = $LeftCannon
@onready var right_cannon = $RightCannon
@onready var AmmoLabel = $UI/AmmoLabel
@onready var destroy_all_button = $UI/DestroyAllButton
@onready var wave_label = $UI/WaveLabel
@onready var announcement_label = $UI/AnnouncementLabel
@onready var ResourceLabel = $UI/ResourceLabel
@onready var building5 = $Building5
@onready var building6 = $Building6
@onready var skip_to_boss = $UI/SkipToBoss
@onready var give_resources = $UI/GiveResources

var base_buildings = 4
var extra_buildings = 0
var next_cannon_index := 0


func get_building_count():
	return base_buildings + GameManager.get_extra_buildings()


func _ready():
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
	print("Main game started: Wave %d, World %d" % [GameManager.current_wave, GameManager.current_world])
	destroy_all_button.pressed.connect(_on_destroy_all_pressed)
	skip_to_boss.pressed.connect(_skip_to_boss)
	GameManager.connect("announce_wave", Callable(self, "_on_announce_wave"))
	GameManager.start_wave()
	_apply_building_unlocks()
	give_resources.pressed.connect(_give_resource)


func _give_resource():
	GameManager.player_resources += 100


func _get_ordered_cannons() -> Array:
	return [middle_cannon, left_cannon, right_cannon]


func _fire_alternating_cannon(target_position: Vector2) -> void:
	var cannons = _get_ordered_cannons()
	var cannon_count = cannons.size()
	if cannon_count == 0:
		return

	for offset in range(cannon_count):
		var idx = (next_cannon_index + offset) % cannon_count
		var cannon = cannons[idx]
		if cannon == null:
			continue
		if cannon.try_fire_at(target_position):
			next_cannon_index = (idx + 1) % cannon_count
			return


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

	if _count_surviving_buildings() == 0:
		print("🏚️ All buildings destroyed — returning to upgrade screen")
		GameManager.player_died()


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


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			pause_menu.hide_pause_menu()
		else:
			pause_menu.show_pause_menu()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_fire_alternating_cannon(get_global_mouse_position())
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_attempt_repair_hovered_defense()


func _on_wave_cleared():
	GameManager.start_next_wave()


func _on_player_died():
	GameManager.player_died()


func _on_announce_wave(message: String, duration: float):
	announce(message, duration)
