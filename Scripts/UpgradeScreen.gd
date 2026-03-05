extends Control

@export var game_scene: PackedScene
@onready var ammo_button = $VBoxContainer/MaxAmmoButton
@onready var ammo_factory_button = $VBoxContainer/AmmoFactoryButton
@onready var ResourceLabel = $ResourceLabel
@onready var b5_btn = $VBoxContainer/UnlockBuilding5Button
@onready var b6_btn = $VBoxContainer/UnlockBuilding6Button


func _ready():
	update_resource_display()
	ammo_button.pressed.connect(_buy_starting_ammo_middle)
	ammo_factory_button.pressed.connect(_buy_ammo_factory_1)
	$VBoxContainer/ContinueButton.pressed.connect(continue_game)
	b5_btn.pressed.connect(_buy_building5)
	b6_btn.pressed.connect(_buy_building6)
	_update_upgrade_button_labels()
	update_building_buttons()


func update_building_buttons():
	b5_btn.disabled = GameManager.get_extra_buildings() >= 1
	b6_btn.disabled = GameManager.get_extra_buildings() >= 2 or GameManager.get_extra_buildings() < 1


func _buy_building5():
	_buy_extra_building(1, 25)


func _buy_building6():
	_buy_extra_building(2, 75)


func _buy_extra_building(target_level: int, cost: int):
	if GameManager.get_extra_buildings() >= target_level:
		return
	if GameManager.player_resources < cost:
		print("❌ Not enough resources")
		return

	GameManager.player_resources -= cost
	GameManager.set_extra_buildings(target_level)

	update_resource_display()
	update_building_buttons()
	print("✅ Extra buildings level now: %d" % GameManager.get_extra_buildings())


func update_resource_display():
	ResourceLabel.text = "Resources: %d" % GameManager.player_resources


func _update_upgrade_button_labels() -> void:
	var starting_level = GameManager.get_upgrade_level("starting_ammo_middle_1")
	var starting_cost = GameManager.get_upgrade_cost(2, starting_level, GameManager.PATH_CHEAP)
	ammo_button.text = "Starting Ammo/Max Ammo (Middle) L%d - Cost %d" % [starting_level + 1, starting_cost]
	ammo_button.disabled = not GameManager.can_buy_upgrade("starting_ammo_middle_1")

	var factory_level = GameManager.get_upgrade_level("ammo_factory_1")
	var factory_cost = GameManager.get_upgrade_cost(10, factory_level, GameManager.PATH_MEDIUM)
	ammo_factory_button.text = "Ammo Factory 1 L%d - Cost %d" % [factory_level + 1, factory_cost]
	ammo_factory_button.disabled = not GameManager.can_buy_upgrade("ammo_factory_1")


func _buy_starting_ammo_middle() -> void:
	if GameManager.try_buy_upgrade("starting_ammo_middle_1"):
		print("✅ Purchased starting_ammo_middle_1")
	else:
		print("❌ Could not purchase starting_ammo_middle_1")
	update_resource_display()
	_update_upgrade_button_labels()


func _buy_ammo_factory_1() -> void:
	if GameManager.try_buy_upgrade("ammo_factory_1"):
		print("✅ Purchased ammo_factory_1")
	else:
		print("❌ Could not purchase ammo_factory_1")
	update_resource_display()
	_update_upgrade_button_labels()


func continue_game():
	GameManager.continue_from_upgrades()
