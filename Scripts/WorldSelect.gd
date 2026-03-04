extends Control

@onready var world1_btn: Button = $CenterContainer/VBoxContainer/World1Button
@onready var world2_btn: Button = $CenterContainer/VBoxContainer/World2Button
@onready var world3_btn: Button = $CenterContainer/VBoxContainer/World3Button
@onready var world4_btn: Button = $CenterContainer/VBoxContainer/World4Button
@onready var world5_btn: Button = $CenterContainer/VBoxContainer/World5Button
@onready var status_label: Label = $StatusLabel


func _ready():
	world1_btn.pressed.connect(func(): _select_world(1))
	world2_btn.pressed.connect(func(): _select_world(2))
	world3_btn.pressed.connect(func(): _select_world(3))
	world4_btn.pressed.connect(func(): _select_world(4))
	world5_btn.pressed.connect(func(): _select_world(5))
	_refresh_buttons()


func _refresh_buttons() -> void:
	_set_world_button(world1_btn, 1)
	_set_world_button(world2_btn, 2)
	_set_world_button(world3_btn, 3)
	_set_world_button(world4_btn, 4)
	_set_world_button(world5_btn, 5)
	status_label.text = "Home Base: Select your next mission"


func _set_world_button(btn: Button, world: int) -> void:
	var unlocked = world <= GameManager.highest_world_unlocked
	btn.disabled = not unlocked
	if unlocked:
		btn.text = "World %d - Deploy" % world
	else:
		btn.text = "World %d - Locked" % world


func _select_world(world: int) -> void:
	if world > GameManager.highest_world_unlocked:
		status_label.text = "World %d is locked. Clear World %d first." % [world, world - 1]
		return

	status_label.text = "Launching World %d..." % world
	GameManager.select_world(world)
