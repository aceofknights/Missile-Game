extends Node

const WORLD_COUNT := 5
const SAVE_PATH := "user://savegame.save"
const SAVE_VERSION := 1

const CANNON_MIDDLE := "middle"
const CANNON_LEFT := "left"
const CANNON_RIGHT := "right"
const CANNON_IDS := [CANNON_MIDDLE, CANNON_LEFT, CANNON_RIGHT]

const PATH_CHEAP := "cheap"
const PATH_MEDIUM := "medium"
const PATH_EXPENSIVE := "expensive"

const COST_MULTIPLIER := {
	PATH_CHEAP: 1.5,
	PATH_MEDIUM: 2.0,
	PATH_EXPENSIVE: 3.0
}

var current_wave := 1
var current_world := 1
var transitioning_world := false
var player_resources := 0

var highest_world_unlocked := 1

# world_upgrades[world] = {
#   "extra_buildings": int,
#   "upgrade_levels": Dictionary,
#   "cannons": {
#      "middle": {"unlocked": bool, "destroyed": bool, "current_ammo": int, "ammo_factory_progress": float},
#      "left": {...},
#      "right": {...}
#   },
#   "ammo_factory_distribution_index": int
# }
var world_upgrades: Dictionary = {}

var enemies_to_spawn := 1
var enemies_alive := 0
var is_boss_wave := false
var wave_active := false
var spawner: Node = null
var active_shield_is_held := false
var active_shield_charge := 0.0
var active_shield_max_charge := 0.0
var ion_wave_end_time := 0.0
var ion_wave_next_ready_time := 0.0
var lure_end_time := 0.0
var lure_position := Vector2.ZERO

signal announce_wave(message: String, duration: float)
signal world_victory_requested
signal player_defeat_requested


func _ready():
	_ensure_world_upgrade_data(current_world)


func _int_to_string_dict(source: Dictionary) -> Dictionary:
	var converted := {}
	for key in source.keys():
		converted[str(key)] = source[key]
	return converted


func _string_to_int_dict(source: Dictionary) -> Dictionary:
	var converted := {}
	for key in source.keys():
		converted[int(str(key))] = source[key]
	return converted


func save_game() -> bool:
	var save_data := {
		"version": SAVE_VERSION,
		"current_world": current_world,
		"current_wave": current_wave,
		"player_resources": player_resources,
		"highest_world_unlocked": highest_world_unlocked,
		"world_upgrades": _int_to_string_dict(world_upgrades)
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save game: %s" % FileAccess.get_open_error())
		return false

	file.store_string(JSON.stringify(save_data))
	return true


func has_save_game() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func erase_save_game() -> void:
	if not has_save_game():
		return

	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		push_error("Failed to open user directory while deleting save.")
		return
	user_dir.remove("savegame.save")


func load_game() -> bool:
	if not has_save_game():
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file: %s" % FileAccess.get_open_error())
		return false

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file format invalid.")
		return false

	var save_data: Dictionary = parsed
	current_world = int(save_data.get("current_world", 1))
	current_wave = int(save_data.get("current_wave", 1))
	player_resources = int(save_data.get("player_resources", 0))
	highest_world_unlocked = clamp(int(save_data.get("highest_world_unlocked", 1)), 1, WORLD_COUNT)
	world_upgrades = _string_to_int_dict(save_data.get("world_upgrades", {}))

	for world in range(1, WORLD_COUNT + 1):
		_ensure_world_upgrade_data(world)
		var state: Dictionary = world_upgrades[world]
		var cannons: Dictionary = state["cannons"]
		for cannon_id in CANNON_IDS:
			if not cannons.has(cannon_id):
				cannons[cannon_id] = _default_cannon_state(cannon_id)
				continue
			var cannon_state: Dictionary = cannons[cannon_id]
			cannon_state["unlocked"] = bool(cannon_state.get("unlocked", cannon_id == CANNON_MIDDLE))
			cannon_state["destroyed"] = bool(cannon_state.get("destroyed", false))
			cannon_state["current_ammo"] = int(cannon_state.get("current_ammo", 0))
			cannon_state["ammo_factory_progress"] = float(cannon_state.get("ammo_factory_progress", 0.0))
			_sync_cannon_ammo_caps_with_state(cannon_id, state)

		state["extra_buildings"] = int(state.get("extra_buildings", 0))
		state["upgrade_levels"] = state.get("upgrade_levels", {})
		state["ammo_factory_distribution_index"] = int(state.get("ammo_factory_distribution_index", 0))

	current_world = clamp(current_world, 1, highest_world_unlocked)
	_ensure_world_upgrade_data(current_world)
	return true


func _default_cannon_state(cannon_id: String) -> Dictionary:
	return {
		"unlocked": cannon_id == CANNON_MIDDLE,
		"destroyed": false,
		"current_ammo": 0,
		"ammo_factory_progress": 0.0
	}


func _default_upgrade_state() -> Dictionary:
	return {
		"extra_buildings": 0,
		"upgrade_levels": {},
		"cannons": {
			CANNON_MIDDLE: _default_cannon_state(CANNON_MIDDLE),
			CANNON_LEFT: _default_cannon_state(CANNON_LEFT),
			CANNON_RIGHT: _default_cannon_state(CANNON_RIGHT)
		},
		"ammo_factory_distribution_index": 0
	}


# Replace _ensure_world_upgrade_data with this version
func _ensure_world_upgrade_data(world: int) -> void:
	if not world_upgrades.has(world):
		world_upgrades[world] = _default_upgrade_state()

	# IMPORTANT: use the local dictionary directly (no _world_state() calls)
	if world == current_world:
		var state: Dictionary = world_upgrades[world]
		var cannons: Dictionary = state["cannons"]
		for cannon_id in CANNON_IDS:
			if bool(cannons[cannon_id]["unlocked"]):
				_sync_cannon_ammo_caps_with_state(cannon_id, state)


# Add this new helper (does NOT call _world_state)
func _sync_cannon_ammo_caps_with_state(cannon_id: String, state: Dictionary) -> void:
	var cannons: Dictionary = state["cannons"]
	if not cannons.has(cannon_id):
		return

	var cannon_state: Dictionary = cannons[cannon_id]
	if not bool(cannon_state["unlocked"]):
		return

	# Keep ammo bounded below zero only. Do not auto-refill here.
	var current_ammo := int(cannon_state["current_ammo"])
	cannon_state["current_ammo"] = max(0, current_ammo)

# Keep your existing _sync_cannon_ammo_caps, but rewrite it as a wrapper:
func _sync_cannon_ammo_caps(cannon_id: String) -> void:
	var state := _world_state()
	_sync_cannon_ammo_caps_with_state(cannon_id, state)

func _world_state() -> Dictionary:
	_ensure_world_upgrade_data(current_world)
	return world_upgrades[current_world]


func get_upgrade_level(upgrade_key: String) -> int:
	var levels: Dictionary = _world_state()["upgrade_levels"]
	return int(levels.get(upgrade_key, 0))


func add_upgrade_level(upgrade_key: String, amount := 1) -> int:
	var state = _world_state()
	var levels: Dictionary = state["upgrade_levels"]
	levels[upgrade_key] = int(levels.get(upgrade_key, 0)) + amount

	# Keep unlock upgrades in sync with cannon availability.
	if upgrade_key == "unlock_left_cannon" and int(levels[upgrade_key]) > 0:
		set_cannon_unlocked(CANNON_LEFT, true)
	elif upgrade_key == "unlock_right_cannon" and int(levels[upgrade_key]) > 0:
		set_cannon_unlocked(CANNON_RIGHT, true)

	return int(levels[upgrade_key])


func get_upgrade_cost(base_cost: int, level: int, path_rate: String) -> int:
	var multiplier = float(COST_MULTIPLIER.get(path_rate, COST_MULTIPLIER[PATH_MEDIUM]))
	return int(round(base_cost * pow(multiplier, level)))


func get_shield_generator_hit_capacity() -> int:
	var level := get_upgrade_level("shield_generator")
	if level <= 0:
		return 0
	return 1 + level


func get_shield_generator_cooldown_seconds() -> float:
	var level := get_upgrade_level("shield_generator")
	if level <= 0:
		return 9999.0
	return maxf(5.0, 30.0 - (3.0 * float(level)))


func has_active_shields_upgrade() -> bool:
	return get_upgrade_level("active_shields") > 0


func get_active_shield_max_charge() -> float:
	var level := get_upgrade_level("active_shields")
	if level <= 0:
		return 0.0
	return 10.0 + float(level)


func get_active_shield_recharge_interval() -> float:
	var level := get_upgrade_level("active_shields")
	if level <= 0:
		return 9999.0
	return maxf(3.0, 20.0 - float(level))


func set_active_shield_held(is_held: bool) -> void:
	active_shield_is_held = is_held


func is_active_shield_up() -> bool:
	return has_active_shields_upgrade() and active_shield_is_held and active_shield_charge > 0.0


func update_active_shield(delta: float) -> void:
	if not has_active_shields_upgrade():
		active_shield_charge = 0.0
		active_shield_max_charge = 0.0
		active_shield_is_held = false
		return

	var previous_max := active_shield_max_charge
	active_shield_max_charge = get_active_shield_max_charge()
	if previous_max <= 0.0:
		active_shield_charge = active_shield_max_charge

	if active_shield_is_held and active_shield_charge > 0.0:
		active_shield_charge = maxf(0.0, active_shield_charge - delta)
	else:
		var recharge_per_second := 1.0 / get_active_shield_recharge_interval()
		active_shield_charge = minf(active_shield_max_charge, active_shield_charge + (recharge_per_second * delta))


func get_ion_wave_duration() -> float:
	var level := get_upgrade_level("ion_wave")
	if level <= 0:
		return 0.0
	return 10.0 + float(level)


func get_ion_wave_recharge_time() -> float:
	var level := get_upgrade_level("ion_wave")
	if level <= 0:
		return 9999.0
	return maxf(10.0, 45.0 - (2.0 * float(level)))


func can_trigger_ion_wave(now_seconds: float) -> bool:
	return get_upgrade_level("ion_wave") > 0 and now_seconds >= ion_wave_next_ready_time


func trigger_ion_wave(now_seconds: float) -> void:
	ion_wave_end_time = now_seconds + get_ion_wave_duration()
	ion_wave_next_ready_time = now_seconds + get_ion_wave_recharge_time()


func is_ion_wave_active(now_seconds: float) -> bool:
	return now_seconds < ion_wave_end_time


func get_enemy_global_speed_multiplier(now_seconds: float) -> float:
	if is_ion_wave_active(now_seconds):
		return 0.6
	return 1.0


func can_trigger_lure() -> bool:
	return get_upgrade_level("lure") > 0


func trigger_lure(pos: Vector2, now_seconds: float) -> void:
	if not can_trigger_lure():
		return
	lure_position = pos
	lure_end_time = now_seconds + (2.0 + float(get_upgrade_level("lure")))


func is_lure_active(now_seconds: float) -> bool:
	return now_seconds < lure_end_time

func is_upgrade_available_in_world(upgrade_key: String, world: int) -> bool:
	var defs = get_upgrade_definitions_world_1()
	if not defs.has(upgrade_key):
		return false

	var def: Dictionary = defs[upgrade_key]
	var min_world: int = int(def.get("min_world", 1))

	return world >= min_world

func get_upgrade_definitions_world_1() -> Dictionary:
	# World 1 base tree. Later worlds can extend this while preserving the keys.
	return {
		"starting_ammo_middle_1": {
			"display_name": "Starting Ammo/Max Ammo (Middle)",
			"max_level": 10,
			"base_cost": 2,
			"path_rate": PATH_CHEAP,
			"requires": []
		},
		
		"ammo_factory_1": {
			"display_name": "Ammo Factory 1",
			"max_level": 10,
			"base_cost": 10,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"ammo_factory_2": {
			"display_name": "Ammo Factory 2",
			"max_level": 10,
			"base_cost": 20,
			"path_rate": PATH_MEDIUM,
			"requires": [{"upgrade": "ammo_factory_1", "min_level": 10}]
		},
		"max_ammo_middle_2": {"display_name": "Max Ammo 2 (Middle)", "max_level": 10, "base_cost": 3, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"max_ammo_middle_3": {"display_name": "Max Ammo 3 (Middle)", "max_level": 10, "base_cost": 5, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "max_ammo_middle_2", "min_level": 10}]},
		"max_ammo_left_2": {"display_name": "Max Ammo 2 (Left)", "max_level": 10, "base_cost": 3, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "unlock_left_cannon", "min_level": 1}]},
		"max_ammo_left_3": {"display_name": "Max Ammo 3 (Left)", "max_level": 10, "base_cost": 5, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "max_ammo_left_2", "min_level": 10}]},
		"max_ammo_right_2": {"display_name": "Max Ammo 2 (Right)", "max_level": 10, "base_cost": 3, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "unlock_right_cannon", "min_level": 1}]},
		"max_ammo_right_3": {"display_name": "Max Ammo 3 (Right)", "max_level": 10, "base_cost": 5, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "max_ammo_right_2", "min_level": 10}]},
		"starting_ammo_middle_2": {"display_name": "Starting Ammo 2 (Middle)", "max_level": 10, "base_cost": 3, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"starting_ammo_middle_3": {"display_name": "Starting Ammo 3 (Middle)", "max_level": 10, "base_cost": 5, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "starting_ammo_middle_2", "min_level": 10}]},
		"unlock_left_cannon": {
			"display_name": "Unlock Left Cannon",
			"max_level": 1,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"unlock_right_cannon": {
			"display_name": "Unlock Right Cannon",
			"max_level": 1,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"starting_ammo_left_2": {"display_name": "Starting Ammo 2 (Left)", "max_level": 10, "base_cost": 3, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "unlock_left_cannon", "min_level": 1}]},
		"starting_ammo_left_3": {"display_name": "Starting Ammo 3 (Left)", "max_level": 10, "base_cost": 5, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "starting_ammo_left_2", "min_level": 10}]},
		"starting_ammo_right_2": {"display_name": "Starting Ammo 2 (Right)", "max_level": 10, "base_cost": 3, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "unlock_right_cannon", "min_level": 1}]},
		"starting_ammo_right_3": {"display_name": "Starting Ammo 3 (Right)", "max_level": 10, "base_cost": 5, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "starting_ammo_right_2", "min_level": 10}]},
		"double_turret_middle": {"display_name": "Double Turret (Middle)", "max_level": 1, "base_cost": 50, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"double_turret_left": {"display_name": "Double Turret (Left)", "max_level": 1, "base_cost": 80, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "unlock_left_cannon", "min_level": 1}]},
		"double_turret_right": {"display_name": "Double Turret (Right)", "max_level": 1, "base_cost": 80, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "unlock_right_cannon", "min_level": 1}]},
		"fire_rate_middle": {"display_name": "Fire Rate (Middle)", "max_level": 5, "base_cost": 10, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"fire_rate_left": {"display_name": "Fire Rate (Left)", "max_level": 5, "base_cost": 10, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "unlock_left_cannon", "min_level": 1}]},
		"fire_rate_right": {"display_name": "Fire Rate (Right)", "max_level": 5, "base_cost": 10, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "unlock_right_cannon", "min_level": 1}]},
		"explosion_size": {"display_name": "Explosion Size", "description": "+1 explosion size per level.", "max_level": 3, "base_cost": 30, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"explosion_duration": {"display_name": "Explosion Duration", "description": "+0.2s max-size explosion hold per level.", "max_level": 5, "base_cost": 24, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"missile_speed": {"display_name": "Missile Speed", "max_level": 10, "base_cost": 15, "path_rate": PATH_CHEAP, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"building_5": {"display_name": "Building 5", "max_level": 1, "base_cost": 25, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"building_6": {"display_name": "Building 6", "max_level": 1, "base_cost": 75, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "building_5", "min_level": 1}]},
		"repair_shop": {"display_name": "Repair Shop", "description": "Unlocks R repairs for destroyed buildings/cannons and lowers repair cost per level.", "max_level": 10, "base_cost": 20, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"shield_generator": {"display_name": "Shield Generator", "description": "Each building shield blocks 1 hit, +1 hit per level. Cooldown 30s, -3s per level.", "max_level": 5, "base_cost": 40, "path_rate": PATH_EXPENSIVE, "min_world": 2, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"active_shields": {"display_name": "Active Shields", "description": "Hold Space for full-base shield. Battery +1s/level, recharge +1s/level faster.", "max_level": 5, "base_cost": 50, "path_rate": PATH_EXPENSIVE, "min_world": 2, "requires": [{"upgrade": "shield_generator", "min_level": 1}]},
		"auto_cannon": {"display_name": "Auto Cannon", "description": "Auto-targets enemy missiles. Fire interval starts at 20s and improves by 2s/level.", "max_level": 5, "base_cost": 50, "path_rate": PATH_EXPENSIVE, "min_world": 3, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"lure": {"display_name": "Lure", "description": "Press E to deploy lure. Lasts 2s +1s per level.", "max_level": 3, "base_cost": 60, "path_rate": PATH_MEDIUM, "min_world": 4, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"ion_wave": {"display_name": "Ion Wave", "description": "Press E to slow all missiles. Slow duration +1s/level, recharge -2s/level.", "max_level": 5, "base_cost": 65, "path_rate": PATH_MEDIUM, "min_world": 5, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]},
		"resource_gain": {"display_name": "Resource Gain", "description": "+1 resource per kill per level.", "max_level": 5, "base_cost": 50, "path_rate": PATH_MEDIUM, "requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 1}]}
	}


func can_buy_upgrade(upgrade_key: String) -> bool:
	var defs = get_upgrade_definitions_world_1()
	if not defs.has(upgrade_key):
		return false

	if not is_upgrade_available_in_world(upgrade_key, current_world):
		return false

	var def: Dictionary = defs[upgrade_key]
	var level: int = get_upgrade_level(upgrade_key)
	if level >= int(def.get("max_level", 1)):
		return false

	for requirement in def.get("requires", []):
		var req_upgrade: String = String(requirement.get("upgrade", ""))
		var req_level: int = int(requirement.get("min_level", 1))
		if get_upgrade_level(req_upgrade) < req_level:
			return false

	return true


func try_buy_upgrade(upgrade_key: String) -> bool:
	if not can_buy_upgrade(upgrade_key):
		return false

	var defs = get_upgrade_definitions_world_1()
	var def: Dictionary = defs[upgrade_key]
	var level = get_upgrade_level(upgrade_key)
	var cost = get_upgrade_cost(int(def.get("base_cost", 1)), level, String(def.get("path_rate", PATH_MEDIUM)))
	if player_resources < cost:
		return false

	player_resources -= cost
	add_upgrade_level(upgrade_key)

	if upgrade_key in ["starting_ammo_middle_1", "starting_ammo_middle_2", "starting_ammo_middle_3", "max_ammo_middle_2", "max_ammo_middle_3"]:
		_sync_cannon_ammo_caps(CANNON_MIDDLE)
	elif upgrade_key == "unlock_left_cannon":
		_sync_cannon_ammo_caps(CANNON_LEFT)
	elif upgrade_key in ["starting_ammo_left_2", "starting_ammo_left_3", "max_ammo_left_2", "max_ammo_left_3"]:
		_sync_cannon_ammo_caps(CANNON_LEFT)
	elif upgrade_key == "unlock_right_cannon":
		_sync_cannon_ammo_caps(CANNON_RIGHT)
	elif upgrade_key in ["starting_ammo_right_2", "starting_ammo_right_3", "max_ammo_right_2", "max_ammo_right_3"]:
		_sync_cannon_ammo_caps(CANNON_RIGHT)
	elif upgrade_key == "building_5":
		set_extra_buildings(1)
	elif upgrade_key == "building_6":
		set_extra_buildings(2)

	return true


func add_resources(amount: int):
	var scaled_amount = amount + (amount * get_upgrade_level("resource_gain"))
	player_resources += scaled_amount
	print("💰 Gained %d resource(s). Total: %d" % [amount, player_resources])


func set_cannon_unlocked(cannon_id: String, unlocked: bool) -> void:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return
	var cannon_state: Dictionary = cannons[cannon_id]
	var was_unlocked := bool(cannon_state["unlocked"])
	cannon_state["unlocked"] = unlocked
	if unlocked:
		cannon_state["destroyed"] = false
		if not was_unlocked:
			cannon_state["current_ammo"] = get_cannon_starting_ammo(cannon_id)
		_sync_cannon_ammo_caps(cannon_id)


func is_cannon_unlocked(cannon_id: String) -> bool:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return false
	return bool(cannons[cannon_id]["unlocked"])


func is_cannon_destroyed(cannon_id: String) -> bool:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return true
	return bool(cannons[cannon_id]["destroyed"])


func destroy_cannon(cannon_id: String) -> void:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return
	var cannon_state: Dictionary = cannons[cannon_id]
	if not bool(cannon_state["unlocked"]):
		return
	cannon_state["destroyed"] = true
	print("💥 Cannon destroyed: %s" % cannon_id)


func get_cannon_max_ammo(cannon_id: String) -> int:
	match cannon_id:
		CANNON_MIDDLE:
			return 10 + (get_upgrade_level("starting_ammo_middle_1") * 2) + (get_upgrade_level("max_ammo_middle_2") * 2) + (get_upgrade_level("max_ammo_middle_3") * 2)
		CANNON_LEFT:
			return 10 + (get_upgrade_level("max_ammo_left_2") * 2) + (get_upgrade_level("max_ammo_left_3") * 2)
		CANNON_RIGHT:
			return 10 + (get_upgrade_level("max_ammo_right_2") * 2) + (get_upgrade_level("max_ammo_right_3") * 2)
		_:
			return 0

func _get_upgrade_level_from_state(state: Dictionary, upgrade_key: String) -> int:
	var levels: Dictionary = state.get("upgrade_levels", {})
	return int(levels.get(upgrade_key, 0))


func _get_cannon_max_ammo_from_state(state: Dictionary, cannon_id: String) -> int:
	match cannon_id:
		CANNON_MIDDLE:
			return 10 + (_get_upgrade_level_from_state(state, "starting_ammo_middle_1") * 2) + (_get_upgrade_level_from_state(state, "max_ammo_middle_2") * 2) + (_get_upgrade_level_from_state(state, "max_ammo_middle_3") * 2)
		CANNON_LEFT:
			return 10 + (_get_upgrade_level_from_state(state, "max_ammo_left_2") * 2) + (_get_upgrade_level_from_state(state, "max_ammo_left_3") * 2)
		CANNON_RIGHT:
			return 10 + (_get_upgrade_level_from_state(state, "max_ammo_right_2") * 2) + (_get_upgrade_level_from_state(state, "max_ammo_right_3") * 2)
		_:
			return 0


func _get_cannon_starting_ammo_from_state(state: Dictionary, cannon_id: String) -> int:
	var bonus := 0
	match cannon_id:
		CANNON_MIDDLE:
			bonus = (_get_upgrade_level_from_state(state, "starting_ammo_middle_1") * 2) + (_get_upgrade_level_from_state(state, "starting_ammo_middle_2") * 2) + (_get_upgrade_level_from_state(state, "starting_ammo_middle_3") * 2)
		CANNON_LEFT:
			bonus = (_get_upgrade_level_from_state(state, "starting_ammo_left_2") * 2) + (_get_upgrade_level_from_state(state, "starting_ammo_left_3") * 2)
		CANNON_RIGHT:
			bonus = (_get_upgrade_level_from_state(state, "starting_ammo_right_2") * 2) + (_get_upgrade_level_from_state(state, "starting_ammo_right_3") * 2)
	return max(0, 10 + bonus)

func get_cannon_starting_ammo(cannon_id: String) -> int:
	return _get_cannon_starting_ammo_from_state(_world_state(), cannon_id)




func get_cannon_current_ammo(cannon_id: String) -> int:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return 0
	return int(cannons[cannon_id]["current_ammo"])


func set_cannon_current_ammo(cannon_id: String, value: int) -> void:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return
	var cannon_state: Dictionary = cannons[cannon_id]
	cannon_state["current_ammo"] = max(0, value)


func spend_cannon_ammo(cannon_id: String, amount := 1) -> bool:
	if not is_cannon_unlocked(cannon_id) or is_cannon_destroyed(cannon_id):
		return false
	var current = get_cannon_current_ammo(cannon_id)
	if current < amount:
		return false
	set_cannon_current_ammo(cannon_id, current - amount)
	return true


func _get_ammo_factory_interval() -> float:
	var l1 = get_upgrade_level("ammo_factory_1")
	var l2 = get_upgrade_level("ammo_factory_2")
	if l1 <= 0 and l2 <= 0:
		return -1.0
	if l2 > 0:
		return max(1.5, 3.0 - (0.1666667 * l2))
	return max(3.0, 5.0 - (0.2222222 * (l1 - 1)))


func _give_factory_ammo_tick() -> bool:
	var state = _world_state()
	var cannons: Dictionary = state["cannons"]
	var start_index = int(state["ammo_factory_distribution_index"])

	for offset in range(CANNON_IDS.size()):
		var idx = (start_index + offset) % CANNON_IDS.size()
		var cannon_id = CANNON_IDS[idx]
		var cannon_state: Dictionary = cannons[cannon_id]
		if not bool(cannon_state["unlocked"]) or bool(cannon_state["destroyed"]):
			continue

		var max_ammo = get_cannon_max_ammo(cannon_id)
		var current_ammo = int(cannon_state["current_ammo"])
		if current_ammo >= max_ammo:
			continue

		cannon_state["current_ammo"] = current_ammo + 1
		state["ammo_factory_distribution_index"] = (idx + 1) % CANNON_IDS.size()
		return true

	return false


func update_ammo_factory(delta: float) -> void:
	var interval = _get_ammo_factory_interval()
	if interval <= 0.0:
		return

	var state = _world_state()
	var middle_state: Dictionary = state["cannons"][CANNON_MIDDLE]
	middle_state["ammo_factory_progress"] = float(middle_state["ammo_factory_progress"]) + delta

	while float(middle_state["ammo_factory_progress"]) >= interval:
		middle_state["ammo_factory_progress"] = float(middle_state["ammo_factory_progress"]) - interval
		if not _give_factory_ammo_tick():
			middle_state["ammo_factory_progress"] = 0.0
			break




func get_cannon_shots_per_cycle(cannon_id: String) -> int:
	if cannon_id == CANNON_MIDDLE and get_upgrade_level("double_turret_middle") > 0:
		return 2
	if cannon_id == CANNON_LEFT and get_upgrade_level("double_turret_left") > 0:
		return 2
	if cannon_id == CANNON_RIGHT and get_upgrade_level("double_turret_right") > 0:
		return 2
	return 1


func get_cannon_fire_rate(cannon_id: String, base_rate: float) -> float:
	var level := 0
	if cannon_id == CANNON_MIDDLE:
		level = get_upgrade_level("fire_rate_middle")
	elif cannon_id == CANNON_LEFT:
		level = get_upgrade_level("fire_rate_left")
	elif cannon_id == CANNON_RIGHT:
		level = get_upgrade_level("fire_rate_right")
	return max(0.05, base_rate * pow(0.95, level))


func get_missile_speed_multiplier() -> float:
	return 1.0 + (0.2 * get_upgrade_level("missile_speed"))


func get_explosion_radius_bonus() -> float:
	return float(get_upgrade_level("explosion_size"))


func get_explosion_duration_bonus() -> float:
	return 0.2 * float(get_upgrade_level("explosion_duration"))


func can_use_repair_shop() -> bool:
	return get_upgrade_level("repair_shop") > 0


func get_repair_shop_cost() -> int:
	return max(10, 20 - get_upgrade_level("repair_shop"))

func get_total_ammo_status() -> String:
	var parts: Array[String] = []
	for cannon_id in CANNON_IDS:
		if not is_cannon_unlocked(cannon_id):
			continue
		var current = get_cannon_current_ammo(cannon_id)
		var max_ammo = get_cannon_max_ammo(cannon_id)
		var destroyed_suffix = ""
		if is_cannon_destroyed(cannon_id):
			destroyed_suffix = " (destroyed)"
		parts.append("%s: %d/%d%s" % [cannon_id, current, max_ammo, destroyed_suffix])
	return " | ".join(parts)


func get_extra_buildings() -> int:
	return int(_world_state()["extra_buildings"])


func set_extra_buildings(level: int) -> void:
	var state = _world_state()
	state["extra_buildings"] = clamp(level, 0, 2)


func get_player_upgrades() -> Dictionary:
	# Compatibility with existing UI callers.
	return _world_state()["upgrade_levels"]


func add_upgrade_stat(upgrade_key: String, amount := 1) -> void:
	add_upgrade_level(upgrade_key, amount)


func get_max_ammo() -> int:
	return get_cannon_max_ammo(CANNON_MIDDLE)


func get_reload_speed():
	# Deprecated by ammo factory but still used in older scenes.
	return null


func has_reload_upgrade() -> bool:
	return get_upgrade_level("ammo_factory_1") > 0


func get_reload_speed_level() -> int:
	return get_upgrade_level("ammo_factory_1")


func get_ammo_level() -> int:
	return get_upgrade_level("starting_ammo_middle_1")


func buy_reload_upgrade_once() -> bool:
	if get_upgrade_level("ammo_factory_1") > 0:
		return false
	add_upgrade_level("ammo_factory_1")
	return true


func start_new_game():
	current_world = 1
	current_wave = 1
	player_resources = 0
	highest_world_unlocked = 1
	world_upgrades.clear()
	_ensure_world_upgrade_data(1)
	save_game()
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func player_died():
	save_game()
	emit_signal("player_defeat_requested")




func reset_cannons_for_new_run() -> void:
	var state := _world_state()
	var cannons: Dictionary = state["cannons"]
	for cannon_id in CANNON_IDS:
		if not bool(cannons[cannon_id]["unlocked"]):
			continue
		cannons[cannon_id]["destroyed"] = false
		cannons[cannon_id]["current_ammo"] = _get_cannon_starting_ammo_from_state(state, cannon_id)
	state["ammo_factory_distribution_index"] = 0
	cannons[CANNON_MIDDLE]["ammo_factory_progress"] = 0.0

func continue_from_upgrades():
	current_wave = 1
	reset_cannons_for_new_run()
	_reset_temporary_upgrade_runtime_state()
	get_tree().change_scene_to_file("res://Scene/Main.tscn")


func select_world(world: int) -> void:
	if world < 1 or world > WORLD_COUNT:
		return
	if world > highest_world_unlocked:
		print("🔒 World %d is locked" % world)
		return

	current_world = world
	current_wave = 1
	_ensure_world_upgrade_data(current_world)
	reset_cannons_for_new_run()
	_reset_temporary_upgrade_runtime_state()
	get_tree().change_scene_to_file("res://Scene/Main.tscn")


func _reset_temporary_upgrade_runtime_state() -> void:
	active_shield_is_held = false
	active_shield_charge = 0.0
	active_shield_max_charge = 0.0
	ion_wave_end_time = 0.0
	ion_wave_next_ready_time = 0.0
	lure_end_time = 0.0


func start_wave():
	await get_tree().create_timer(2.0).timeout

	print("📣 start_wave() called")
	print("🌊 Starting Wave %d (World %d)" % [current_wave, current_world])
	
	if current_world == 1:
		is_boss_wave = (current_wave % 10 == 0)
	elif current_world == 2:
		is_boss_wave = (current_wave % 15 == 0)
	elif current_world == 3:
		is_boss_wave = (current_wave % 20 == 0)
	elif current_world == 4:
		is_boss_wave = (current_wave % 35 == 0)
	elif current_world == 5:
		is_boss_wave = (current_wave % 50 == 0)


	wave_active = true
	enemies_alive = 0

	if is_boss_wave:
		enemies_alive = 1
		spawner.spawn_boss()
	else:
		enemies_to_spawn = current_wave * 2
		await spawn_enemies_gradually(enemies_to_spawn)


func spawn_enemies_gradually(count):
	var delay = max(0.3, 1.5 - (current_world * 0.2) - (current_wave * 0.05))
	print("⏱ Spawning enemies with delay of %.2f" % delay)

	for _i in range(count):
		if not wave_active or spawner == null or !is_instance_valid(spawner):
			print("⛔️ Spawning cancelled: wave is no longer active or spawner is invalid")
			return

		enemies_alive += 1
		spawner.spawn_enemy()

		await get_tree().create_timer(delay).timeout


func _clear_active_enemies() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()


func _go_to_world_select_deferred() -> void:
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")
	transitioning_world = false


func _on_enemy_died():
	enemies_alive -= 1
	print("Enemies remaining: %d" % enemies_alive)

	if enemies_alive <= 0 and wave_active:
		wave_active = false
		next_wave_or_boss()


func on_boss_defeated() -> void:
	if transitioning_world:
		return
	if not is_boss_wave:
		return
	emit_signal("world_victory_requested")


func next_wave_or_boss():
	if is_boss_wave:
		_on_world_defeated()
	else:
		current_wave += 1
		await get_tree().create_timer(1.0).timeout
		emit_signal("announce_wave", "🌊 Wave %d Incoming..." % current_wave, 2.0)
		await get_tree().create_timer(2.0).timeout
		start_wave()


func _on_world_defeated() -> void:
	print("👹 World %d boss defeated!" % current_world)
	var next_world = current_world + 1
	if next_world <= WORLD_COUNT:
		highest_world_unlocked = max(highest_world_unlocked, next_world)
		_ensure_world_upgrade_data(next_world)

	current_wave = 1
	save_game()
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func load_upgrade_screen():
	get_tree().change_scene_to_file("res://Scene/UpgradeScreen.tscn")


func advance_to_next_world():
	_on_world_defeated()


func continue_after_victory() -> void:
	_on_world_defeated()


func continue_after_player_defeat() -> void:
	load_upgrade_screen()
