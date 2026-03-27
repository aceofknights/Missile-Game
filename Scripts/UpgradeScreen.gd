extends Control

@export var game_scene: PackedScene
@onready var resource_label: Label = $MarginContainer/VBoxContainer/ResourceLabel
@onready var tree_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/TreeVBox

var _upgrade_buttons: Dictionary = {}

const TREE_ORDER := [
	{"label": "First Upgrade", "indent": 0},
	{"key": "starting_ammo_middle_1", "indent": 1},
	{"label": "Offensive > Ammo", "indent": 0},
	{"key": "ammo_factory_1", "indent": 1},
	{"key": "ammo_factory_2", "indent": 2},
	{"key": "max_ammo_middle_2", "indent": 1},
	{"key": "max_ammo_middle_3", "indent": 2},
	{"key": "starting_ammo_middle_2", "indent": 1},
	{"key": "starting_ammo_middle_3", "indent": 2},
	{"key": "starting_ammo_left_2", "indent": 2},
	{"key": "starting_ammo_left_3", "indent": 3},
	{"key": "starting_ammo_right_2", "indent": 2},
	{"key": "starting_ammo_right_3", "indent": 3},
	{"label": "Offensive > Cannon", "indent": 0},
	{"key": "double_turret_middle", "indent": 1},
	{"key": "fire_rate_middle", "indent": 1},
	{"key": "unlock_left_cannon", "indent": 1},
	{"key": "double_turret_left", "indent": 2},
	{"key": "fire_rate_left", "indent": 2},
	{"key": "unlock_right_cannon", "indent": 1},
	{"key": "double_turret_right", "indent": 2},
	{"key": "fire_rate_right", "indent": 2},
	{"label": "Offensive > Missile", "indent": 0},
	{"key": "explosion_size", "indent": 1},
	{"key": "explosion_duration", "indent": 1},
	{"key": "missile_speed", "indent": 1},
	{"label": "Defensive", "indent": 0},
	{"key": "building_5", "indent": 1},
	{"key": "building_6", "indent": 2},
	{"key": "repair_shop", "indent": 1},
	{"key": "shield", "indent":1},
	{"label": "Economy", "indent": 0},
	{"key": "resource_gain", "indent": 1}
]


func _ready():
	$MarginContainer/VBoxContainer/ContinueButton.pressed.connect(continue_game)
	$MarginContainer/VBoxContainer/SaveQuitButton.pressed.connect(_on_save_and_quit_pressed)
	$MarginContainer/VBoxContainer/WorldSelectButton.pressed.connect(_on_back_to_world_select_pressed)
	_build_tree()
	_refresh_view()


func _build_tree() -> void:
	for child in tree_vbox.get_children():
		child.queue_free()
	_upgrade_buttons.clear()

	var defs = GameManager.get_upgrade_definitions_world_1()
	for item in TREE_ORDER:
		if item.has("label"):
			var section := Label.new()
			section.text = "%s%s" % ["  ".repeat(int(item.get("indent", 0))), String(item["label"])]
			tree_vbox.add_child(section)
			continue

		var key := String(item.get("key", ""))
		if key == "":
			continue
		if not defs.has(key):
			continue
		if not GameManager.is_upgrade_available_in_world(key, GameManager.current_world):
			continue

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func(): _buy_upgrade(key))
		_upgrade_buttons[key] = {
			"button": btn,
			"indent": int(item.get("indent", 0))
		}
		tree_vbox.add_child(btn)

func _buy_upgrade(upgrade_key: String) -> void:
	GameManager.try_buy_upgrade(upgrade_key)
	_refresh_view()


func _refresh_view() -> void:
	resource_label.text = "Resources: %d" % GameManager.player_resources
	var defs = GameManager.get_upgrade_definitions_world_1()
	for key in _upgrade_buttons.keys():
		var meta: Dictionary = _upgrade_buttons[key]
		var btn: Button = meta["button"]
		var indent: int = meta["indent"]
		var def: Dictionary = defs[key]
		var level = GameManager.get_upgrade_level(key)
		var max_level = int(def.get("max_level", 1))
		var cost = GameManager.get_upgrade_cost(int(def.get("base_cost", 1)), level, String(def.get("path_rate", GameManager.PATH_MEDIUM)))
		var description := String(def.get("description", ""))
		btn.text = "%s%s L%d/%d - Cost %d" % ["  ".repeat(indent), String(def.get("display_name", key)), level, max_level, cost]
		if description != "":
			btn.text += "\n%s%s" % ["  ".repeat(indent + 1), description]
		btn.disabled = not GameManager.can_buy_upgrade(key)


func continue_game():
	GameManager.continue_from_upgrades()


func _on_save_and_quit_pressed() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file("res://Scene/MainMenu.tscn")


func _on_back_to_world_select_pressed() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")
