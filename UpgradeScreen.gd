extends Control

func _ready():
	print("Upgrade screen opened")
	print("Resources: %d" % GameManager.player_resources)
	print("Upgrades: %s" % GameManager.player_upgrades)

func _on_upgrade_selected(upgrade_key: String, cost: int):
	if GameManager.player_resources >= cost:
		GameManager.player_resources -= cost
		GameManager.player_upgrades[upgrade_key] = GameManager.player_upgrades.get(upgrade_key, 0) + 1
		print("Purchased upgrade: %s (level %d)" % [upgrade_key, GameManager.player_upgrades[upgrade_key]])
	else:
		print("Not enough resources")

func _on_continue_pressed():
	GameManager.start_next_wave()
