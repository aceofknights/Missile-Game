extends Control

@export var game_scene: PackedScene

func _ready():
	$VBoxContainer/NewGame.pressed.connect(_on_new_game_pressed)
	$VBoxContainer/Continue.pressed.connect(_on_continue_pressed)
	$VBoxContainer/Quit.pressed.connect(quit_game)
	$OverwriteConfirm.confirmed.connect(_confirm_new_game)
	$OverwriteConfirm.canceled.connect(func(): $VBoxContainer/NewGame.disabled = false)
	_refresh_continue_state()


func _refresh_continue_state() -> void:
	$VBoxContainer/Continue.disabled = not GameManager.has_save_game()


func _on_new_game_pressed() -> void:
	if GameManager.has_save_game():
		$VBoxContainer/NewGame.disabled = true
		$OverwriteConfirm.popup_centered()
		return
	_confirm_new_game()


func _confirm_new_game() -> void:
	$VBoxContainer/NewGame.disabled = false
	GameManager.erase_save_game()
	GameManager.start_new_game()


func _on_continue_pressed() -> void:
	if not GameManager.load_game():
		_refresh_continue_state()
		return
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func quit_game():
	get_tree().quit()
