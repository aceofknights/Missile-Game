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
@onready var repair_button = $UI/RepairButton

var base_buildings = 4
var extra_buildings = 0

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
		"UI/RepairButton": "Button",
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
	repair_button.pressed.connect(_repair_destroyed_defense)
	_update_repair_button()


func _give_resource():
	GameManager.player_resources += 100


func _update_repair_button() -> void:
	if not GameManager.can_use_repair_shop():
		repair_button.visible = false
		return
	repair_button.visible = true
	repair_button.text = "Repair Destroyed (%d)" % GameManager.get_repair_shop_cost()


func _repair_destroyed_defense() -> void:
	if not GameManager.can_use_repair_shop():
		return
	var cost = GameManager.get_repair_shop_cost()
	if GameManager.player_resources < cost:
		return
	var repaired = false
	for cannon_id in GameManager.CANNON_IDS:
		if GameManager.is_cannon_unlocked(cannon_id) and GameManager.is_cannon_destroyed(cannon_id):
			GameManager.player_resources -= cost
			GameManager.set_cannon_unlocked(cannon_id, true)
			GameManager.set_cannon_current_ammo(cannon_id, GameManager.get_cannon_starting_ammo(cannon_id))
			repaired = true
			break
	if repaired:
		return
	var buildings = get_tree().get_nodes_in_group("building")
	if buildings.size() < get_building_count():
		GameManager.player_resources -= cost
		get_tree().reload_current_scene()


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
		if b:
			b.queue_free()
	print("🔧 All buildings destroyed (debug)")


func _process(delta):
	GameManager.update_ammo_factory(delta)
	AmmoLabel.text = "Ammo: %s" % GameManager.get_total_ammo_status()
	wave_label.text = "🌊 Wave %d / 🌍 World %d" % [GameManager.current_wave, GameManager.current_world]
	ResourceLabel.text = "Resources: %d" % GameManager.player_resources
	_update_repair_button()

	var buildings = get_tree().get_nodes_in_group("building")
	if buildings.size() == 0:
		print("🏚️ All buildings destroyed — returning to upgrade screen")
		GameManager.player_died()


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			pause_menu.hide_pause_menu()
		else:
			pause_menu.show_pause_menu()


func _on_wave_cleared():
	GameManager.start_next_wave()


func _on_player_died():
	GameManager.player_died()


func _on_announce_wave(message: String, duration: float):
	announce(message, duration)
