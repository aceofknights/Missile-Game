extends Node2D

@onready var pause_menu = $PauseMenu
@onready var cannon = $Cannon
@onready var AmmoLabel = $UI/AmmoLabel

func _ready():
	get_tree().paused = false
	pause_menu.hide()
	print("Main game started: Wave %d, World %d" % [GameManager.current_wave, GameManager.current_world])

func _process(delta):
	AmmoLabel.text = "Ammo: %d / %d" % [cannon.current_ammo, cannon.max_ammo]
	
		# Check if all buildings are destroyed
	var buildings = get_tree().get_nodes_in_group("building")
	if buildings.size() == 0:
		print("🏚️ All buildings destroyed — returning to main menu")
		get_tree().change_scene_to_file("res://MainMenu.tscn")  # or load_upgrade_screen() later
		
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
