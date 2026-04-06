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

const DEFAULT_STATUS_TEXT: String = "Home Base: Select your next mission"

const WORLD_NAMES := {
	1: "World 1 - Ember Reach",
	2: "World 2 - Frostline",
	3: "World 3 - Cyber Drift",
	4: "World 4 - Mirage Core",
	5: "World 5 - Void Crown"
}

const NORMAL_SCALE: Vector2 = Vector2.ONE
const HOVER_SCALE: Vector2 = Vector2(1.08, 1.08)
const HOVER_BRIGHTEN: Color = Color(1.25, 1.25, 1.25, 1.0)
const LOCKED_COLOR: Color = Color(0.35, 0.35, 0.35, 1.0)
const NORMAL_COLOR: Color = Color(1, 1, 1, 1)

var _hovered_world: int = -1
var _hover_pulse_time: float = 0.0


func _ready() -> void:
	world1_btn.pressed.connect(func(): _select_world(1))
	world2_btn.pressed.connect(func(): _select_world(2))
	world3_btn.pressed.connect(func(): _select_world(3))
	world4_btn.pressed.connect(func(): _select_world(4))
	world5_btn.pressed.connect(func(): _select_world(5))

	_connect_hover(world1_btn, world1_anim, 1)
	_connect_hover(world2_btn, world2_anim, 2)
	_connect_hover(world3_btn, world3_anim, 3)
	_connect_hover(world4_btn, world4_anim, 4)
	_connect_hover(world5_btn, world5_anim, 5)

	unlock_all_worlds_btn.pressed.connect(_unlock_all_worlds_for_debug)
	save_quit_button.pressed.connect(_on_save_and_quit_pressed)
	unlock_all_worlds_btn.visible = OS.is_debug_build()

	world1_anim.play("World 1 Spin")
	world2_anim.play("World 2 Spin")
	world3_anim.play("World 3 Spin")
	world4_anim.play("World 4 Spin")
	world5_anim.play("World 5 Spin")

	_refresh_buttons()


func _process(delta: float) -> void:
	if _hovered_world == -1:
		return

	_hover_pulse_time += delta
	var anim: AnimatedSprite2D = _get_world_anim(_hovered_world)
	if anim == null:
		return

	var pulse: float = 1.0 + (sin(_hover_pulse_time * 6.0) * 0.015)
	anim.scale = HOVER_SCALE * pulse


func _refresh_buttons() -> void:
	_set_world_button(world1_btn, world1_anim, 1)
	_set_world_button(world2_btn, world2_anim, 2)
	_set_world_button(world3_btn, world3_anim, 3)
	_set_world_button(world4_btn, world4_anim, 4)
	_set_world_button(world5_btn, world5_anim, 5)

	status_label.text = DEFAULT_STATUS_TEXT


func _set_world_button(btn: TextureButton, anim: AnimatedSprite2D, world: int) -> void:
	var unlocked: bool = world <= GameManager.highest_world_unlocked

	# Keep buttons active so hover still works even for locked worlds.
	btn.disabled = false

	if unlocked:
		anim.modulate = NORMAL_COLOR
	else:
		anim.modulate = LOCKED_COLOR

	anim.scale = NORMAL_SCALE


func _connect_hover(btn: TextureButton, anim: AnimatedSprite2D, world: int) -> void:
	btn.mouse_entered.connect(func(): _on_world_hovered(anim, world))
	btn.mouse_exited.connect(func(): _on_world_unhovered(anim, world))


func _on_world_hovered(anim: AnimatedSprite2D, world: int) -> void:
	_hovered_world = world
	_hover_pulse_time = 0.0

	var unlocked: bool = world <= GameManager.highest_world_unlocked
	var world_name: String = WORLD_NAMES.get(world, "World %d" % world)

	if unlocked:
		status_label.text = world_name
		anim.modulate = HOVER_BRIGHTEN
	else:
		status_label.text = "%s - Locked" % world_name
		anim.modulate = Color(0.6, 0.6, 0.6, 1.0)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(anim, "scale", HOVER_SCALE, 0.12)


func _on_world_unhovered(anim: AnimatedSprite2D, world: int) -> void:
	if _hovered_world == world:
		_hovered_world = -1

	var unlocked: bool = world <= GameManager.highest_world_unlocked

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(anim, "scale", NORMAL_SCALE, 0.12)

	if unlocked:
		anim.modulate = NORMAL_COLOR
	else:
		anim.modulate = LOCKED_COLOR

	status_label.text = DEFAULT_STATUS_TEXT


func _get_world_anim(world: int) -> AnimatedSprite2D:
	match world:
		1:
			return world1_anim
		2:
			return world2_anim
		3:
			return world3_anim
		4:
			return world4_anim
		5:
			return world5_anim
		_:
			return null


func _select_world(world: int) -> void:
	if world > GameManager.highest_world_unlocked:
		status_label.text = "World %d is locked. Clear World %d first." % [world, world - 1]
		return

	status_label.text = "Launching %s..." % WORLD_NAMES.get(world, "World %d" % world)
	GameManager.select_world(world)


func _unlock_all_worlds_for_debug() -> void:
	GameManager.highest_world_unlocked = GameManager.WORLD_COUNT
	GameManager.save_game()
	_refresh_buttons()
	status_label.text = "Debug: All worlds unlocked"


func _on_save_and_quit_pressed() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file("res://Scene/MainMenu.tscn")
