extends CanvasLayer

@export var main_menu_scene: PackedScene = null


func _ready():
	visible = false
	$Panel/VBoxContainer/Resume.pressed.connect(_on_resume_pressed)
	$Panel/VBoxContainer/Main_Menu.pressed.connect(_on_main_menu_pressed)
	$Panel/VBoxContainer/Quit.pressed.connect(_on_quit_pressed)

func show_pause_menu():
	visible = true
	get_tree().paused = true

func hide_pause_menu():
	visible = false
	get_tree().paused = false

func _on_resume_pressed():
	print("Resuming game")
	hide_pause_menu()

func _on_main_menu_pressed():
	print("Trying fallback load...")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scene/MainMenu.tscn")

func _on_quit_pressed():
	print("Quitting game")
	get_tree().quit()
