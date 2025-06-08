extends Control

@export var game_scene: PackedScene
@onready var upgrade_btn_2 = $VBoxContainer/UpgradeButton2


func _ready():
	$VBoxContainer/UpgradeButton.pressed.connect(upgrade_ammo)
	upgrade_btn_2.pressed.connect(upgrade_reload)
	$VBoxContainer/ContinueButton.pressed.connect(continue_game)
	print("Upgrade screen opened")
	print("Resources: %d" % GameManager.player_resources)
	print("Upgrades: %s" % GameManager.player_upgrades)
	print(get_tree().get_current_scene().get_tree_string())
	
func _on_upgrade_selected(upgrade_key: String, cost: int):
	if GameManager.player_resources >= cost:
		GameManager.player_resources -= cost
		GameManager.player_upgrades[upgrade_key] = GameManager.player_upgrades.get(upgrade_key, 0) + 1
		print("Purchased upgrade: %s (level %d)" % [upgrade_key, GameManager.player_upgrades[upgrade_key]])
	else:
		print("Not enough resources")
		
func upgrade_ammo():
	GameManager.ammo_level += 1
	print("Ammo upgraded to %d" % GameManager.ammo_level)

func upgrade_reload():
	if GameManager.reload_upgrade_bought == false:
		GameManager.reload_upgrade_bought = true
		GameManager.reload_speed_level += 1
		print("Reload speed upgraded to %d" % GameManager.reload_speed_level)


func continue_game():
	GameManager.continue_from_upgrades()
