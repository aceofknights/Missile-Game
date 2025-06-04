extends Node

var current_wave = 1
var current_world = 1
var player_upgrades = {}
var player_resources = 0

func start_new_game():
	current_world = 1
	current_wave = 1
	player_resources = 0
	player_upgrades = {}
	get_tree().change_scene_to_file("res://MainGame.tscn")

func player_died():
	load_upgrade_screen()
	
func start_next_wave():
	current_wave += 1
	if current_wave > 10:
		load_boss_fight()
	else:
		get_tree().reload_current_scene()

func load_boss_fight():
	get_tree().change_scene_to_file("res://BossFight.tscn")

func boss_defeated():
	advance_to_next_world()
	
func load_upgrade_screen():
	get_tree().change_scene_to_file("res://UpgradeScreen.tscn")

func advance_to_next_world():
	current_world += 1
	current_wave = 1
	get_tree().change_scene_to_file("res://MainGame.tscn")

