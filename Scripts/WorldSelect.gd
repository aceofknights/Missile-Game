extends Control

@onready var world1_btn: TextureButton = $World1Holder/World1Button
@onready var world2_btn: TextureButton = $World2Holder/World2Button
@onready var world3_btn: TextureButton = $World3Holder/World3Button
@onready var world4_btn: TextureButton = $World4Holder/World4Button
@onready var world5_btn: TextureButton = $World5Holder/World5Button

@onready var world1_anim: AnimatedSprite2D = $World1Holder/World1Button/AnimatedSprite2D
@onready var world2_anim: AnimatedSprite2D = $World2Holder/World2Button/AnimatedSprite2D
@onready var world3_anim: AnimatedSprite2D = $World3Holder/World3Button/AnimatedSprite2D
@onready var world4_anim: AnimatedSprite2D = $World4Holder/World4Button/AnimatedSprite2D
@onready var world5_anim: AnimatedSprite2D = $World5Holder/World5Button/AnimatedSprite2D

@onready var status_label: Label = $StatusLabel
@onready var unlock_all_worlds_btn: Button = $UnlockAllWorldsButton
@onready var save_quit_button: Button = $SaveQuitButton


func _ready() -> void:
	world1_btn.pressed.connect(func(): _select_world(1))
	world2_btn.pressed.connect(func(): _select_world(2))
	world3_btn.pressed.connect(func(): _select_world(3))
	world4_btn.pressed.connect(func(): _select_world(4))
	world5_btn.pressed.connect(func(): _select_world(5))

	unlock_all_worlds_btn.pressed.connect(_unlock_all_worlds_for_debug)
	save_quit_button.pressed.connect(_on_save_and_quit_pressed)
	unlock_all_worlds_btn.visible = OS.is_debug_build()

	world1_anim.play("World 1 Spin")
	world2_anim.play("World 2 Spin")
	world3_anim.play("World 3 Spin")
	world4_anim.play("World 4 Spin")
	world5_anim.play("World 5 Spin")

	_refresh_buttons()


func _refresh_buttons() -> void:
	_set_world_button(world1_btn, world1_anim, 1)
	_set_world_button(world2_btn, world2_anim, 2)
	_set_world_button(world3_btn, world3_anim, 3)
	_set_world_button(world4_btn, world4_anim, 4)
	_set_world_button(world5_btn, world5_anim, 5)
	status_label.text = "Home Base: Select your next mission"


func _set_world_button(btn: TextureButton, anim: AnimatedSprite2D, world: int) -> void:
	var unlocked: bool = world <= GameManager.highest_world_unlocked
	btn.disabled = not unlocked

	if unlocked:
		anim.modulate = Color(1, 1, 1, 1)
	else:
		anim.modulate = Color(0.35, 0.35, 0.35, 1)


func _select_world(world: int) -> void:
	if world > GameManager.highest_world_unlocked:
		status_label.text = "World %d is locked. Clear World %d first." % [world, world - 1]
		return

	status_label.text = "Launching World %d..." % world
	GameManager.select_world(world)


func _unlock_all_worlds_for_debug() -> void:
	GameManager.highest_world_unlocked = GameManager.WORLD_COUNT
	GameManager.save_game()
	_refresh_buttons()
	status_label.text = "Debug: All worlds unlocked"


func _on_save_and_quit_pressed() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file("res://Scene/MainMenu.tscn")
