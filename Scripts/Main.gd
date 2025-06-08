extends Node2D

@onready var pause_menu = $PauseMenu
@onready var cannon = $Cannon
@onready var AmmoLabel = $UI/AmmoLabel
@onready var destroy_all_button = $UI/DestroyAllButton
@onready var wave_label = $UI/WaveLabel
@onready var announcement_label = $UI/AnnouncementLabel

func _ready():
	get_tree().paused = false
	pause_menu.hide()
	print("Main game started: Wave %d, World %d" % [GameManager.current_wave, GameManager.current_world])
	destroy_all_button.pressed.connect(_on_destroy_all_pressed)
	GameManager.connect("announce_wave", Callable(self, "_on_announce_wave"))
	GameManager.start_wave()
	
func announce(text: String, duration: float = 2.0):
	announcement_label.text = text
	announcement_label.visible = true
	await get_tree().create_timer(duration).timeout
	announcement_label.visible = false

func _on_destroy_all_pressed():
	GameManager.wave_active = false
	GameManager.enemies_alive = 0
	GameManager.spawner = null  # Prevent future use of freed spawner

	var buildings = get_tree().get_nodes_in_group("building")
	for b in buildings:
		if b:
			b.queue_free()
	print("🔧 All buildings destroyed (debug)")

	
	
func _process(delta):
	AmmoLabel.text = "Ammo: %d / %d" % [cannon.current_ammo, cannon.max_ammo]
	wave_label.text = "🌊 Wave %d / 🌍 World %d" % [GameManager.current_wave, GameManager.current_world]
		# Check if all buildings are destroyed
	var buildings = get_tree().get_nodes_in_group("building")
	if buildings.size() == 0:
		print("🏚️ All buildings destroyed — returning to main menu")
		#get_tree().change_scene_to_file("res://Scene/MainMenu.tscn")  # or load_upgrade_screen() later
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
