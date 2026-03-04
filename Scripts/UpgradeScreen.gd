extends Control

@export var game_scene: PackedScene
@onready var AmmoFactory = $VBoxContainer/AmmoFactoryButton
@onready var ResourceLabel = $ResourceLabel
@onready var b5_btn = $VBoxContainer/UnlockBuilding5Button
@onready var b6_btn = $VBoxContainer/UnlockBuilding6Button


func _ready():
	update_resource_display()
	$VBoxContainer/MaxAmmoButton.pressed.connect(upgrade_ammo)
	AmmoFactory.pressed.connect(upgrade_reload)
	$VBoxContainer/ContinueButton.pressed.connect(continue_game)
	print("Upgrade screen opened")
	print("Resources: %d" % GameManager.player_resources)
	print("Upgrades: %s" % GameManager.get_player_upgrades())
	print(get_tree().get_current_scene().get_tree_string())
	b5_btn.pressed.connect(_buy_building5)
	b6_btn.pressed.connect(_buy_building6)
	update_building_buttons()
	
func update_building_buttons():
	b5_btn.disabled = GameManager.get_extra_buildings() >= 1
	b6_btn.disabled = GameManager.get_extra_buildings() >= 2 or GameManager.get_extra_buildings() < 1  # require 5th first

func _buy_building5():
	_buy_extra_building(1, 25) # cost 10, unlock extra_buildings=1

func _buy_building6():
	_buy_extra_building(2, 50) # cost 20, unlock extra_buildings=2

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

func _on_upgrade_selected(upgrade_key: String, cost: int, callback: Callable):
	if GameManager.player_resources >= cost:
		GameManager.player_resources -= cost
		GameManager.add_upgrade_stat(upgrade_key)
		var level = int(GameManager.get_player_upgrades().get(upgrade_key, 0))
		print("✅ Purchased upgrade: %s (level %d)" % [upgrade_key, level])
		update_resource_display()
		callback.call()  # Apply upgrade effect
	else:
		print("❌ Not enough resources for %s" % upgrade_key)

func upgrade_ammo():
	_on_upgrade_selected("ammo", 1, func ():
		GameManager.add_ammo_upgrade(1)
		print("Ammo upgraded to %d" % GameManager.get_ammo_level())
	)

func upgrade_reload():
	if GameManager.has_reload_upgrade():
		print("❌ Reload already bought")
		return
	_on_upgrade_selected("reload_speed", 10, func ():
		GameManager.buy_reload_upgrade_once()
		print("Reload speed upgraded to %d" % GameManager.get_reload_speed_level())
	)

func continue_game():
	GameManager.continue_from_upgrades()

