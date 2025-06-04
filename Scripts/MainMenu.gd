extends Control

@export var game_scene: PackedScene

func _ready():
	$VBoxContainer/Start.pressed.connect(start_game)
	$VBoxContainer/Quit.pressed.connect(quit_game)

func start_game():
	if game_scene:
		get_tree().change_scene_to_packed(game_scene)
	else:
		print("❌ game_scene not assigned!")

func quit_game():
	get_tree().quit()

