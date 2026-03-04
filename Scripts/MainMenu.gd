extends Control

@export var game_scene: PackedScene

func _ready():
	$VBoxContainer/Start.pressed.connect(start_game)
	$VBoxContainer/Quit.pressed.connect(quit_game)

func start_game():
	GameManager.start_new_game()

func quit_game():
	get_tree().quit()

