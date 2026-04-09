extends Control

@export var game_scene: PackedScene

@onready var new_game_button: Button = $VBoxContainer/NewGame
@onready var continue_button: Button = $VBoxContainer/Continue
@onready var quit_button: Button = $VBoxContainer/Quit

@onready var overwrite_confirm: CanvasLayer = $OverwriteConfirm
@onready var confirm_button: Button = $OverwriteConfirm/CenterContainer/PopupOffset/PanelContainer/Padding/Content/Buttons/ConfirmButton
@onready var cancel_button: Button = $OverwriteConfirm/CenterContainer/PopupOffset/PanelContainer/Padding/Content/Buttons/CancelButton
@onready var dimmer: ColorRect = $OverwriteConfirm/Dimmer


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(quit_game)

	confirm_button.pressed.connect(_confirm_new_game)
	cancel_button.pressed.connect(_on_overwrite_cancelled)
	dimmer.gui_input.connect(_on_dimmer_gui_input)

	overwrite_confirm.visible = false
	_refresh_continue_state()


func _refresh_continue_state() -> void:
	continue_button.disabled = not GameManager.has_save_game()


func _on_new_game_pressed() -> void:
	if GameManager.has_save_game():
		new_game_button.disabled = true
		overwrite_confirm.visible = true
		return

	_confirm_new_game()


func _confirm_new_game() -> void:
	overwrite_confirm.visible = false
	new_game_button.disabled = false
	GameManager.erase_save_game()
	GameManager.start_new_game()


func _on_overwrite_cancelled() -> void:
	overwrite_confirm.visible = false
	new_game_button.disabled = false


func _on_continue_pressed() -> void:
	if not GameManager.load_game():
		_refresh_continue_state()
		return

	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func _on_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_overwrite_cancelled()


func quit_game() -> void:
	get_tree().quit()
