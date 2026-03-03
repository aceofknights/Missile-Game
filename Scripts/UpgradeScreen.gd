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
	print("Upgrades: %s" % GameManager.player_upgrades)
	print(get_tree().get_current_scene().get_tree_string())
	b5_btn.pressed.connect(_buy_building5)
	b6_btn.pressed.connect(_buy_building6)
	update_building_buttons()
	
func update_building_buttons():
	b5_btn.disabled = GameManager.extra_buildings >= 1
	b6_btn.disabled = GameManager.extra_buildings >= 2 or GameManager.extra_buildings < 1  # require 5th first

func _buy_building5():
	_buy_extra_building(1, 25) # cost 10, unlock extra_buildings=1

func _buy_building6():
	_buy_extra_building(2, 50) # cost 20, unlock extra_buildings=2

func _buy_extra_building(target_level: int, cost: int):
	if GameManager.extra_buildings >= target_level:
		return
	if GameManager.player_resources < cost:
		print("❌ Not enough resources")
		return

	GameManager.player_resources -= cost
	GameManager.extra_buildings = target_level

	update_resource_display()
	update_building_buttons()
	print("✅ Extra buildings level now: %d" % GameManager.extra_buildings)
	
func update_resource_display():
	ResourceLabel.text = "Resources: %d" % GameManager.player_resources

func _on_upgrade_selected(upgrade_key: String, cost: int, callback: Callable):
	if GameManager.player_resources >= cost:
		GameManager.player_resources -= cost
		GameManager.player_upgrades[upgrade_key] = GameManager.player_upgrades.get(upgrade_key, 0) + 1
		print("✅ Purchased upgrade: %s (level %d)" % [upgrade_key, GameManager.player_upgrades[upgrade_key]])
		update_resource_display()
		callback.call()  # Apply upgrade effect
	else:
		print("❌ Not enough resources for %s" % upgrade_key)

func upgrade_ammo():
	_on_upgrade_selected("ammo", 1, func ():
		GameManager.ammo_level += 1
		print("Ammo upgraded to %d" % GameManager.ammo_level)
	)

func upgrade_reload():
	if GameManager.reload_upgrade_bought:
		print("❌ Reload already bought")
		return
	_on_upgrade_selected("reload_speed", 10, func ():
		GameManager.reload_upgrade_bought = true
		GameManager.reload_speed_level += 1
		print("Reload speed upgraded to %d" % GameManager.reload_speed_level)
	)

func continue_game():
	GameManager.continue_from_upgrades()

