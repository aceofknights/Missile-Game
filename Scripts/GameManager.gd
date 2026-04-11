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

const NEON_OUTER_ALPHA := 0.2
const NEON_OUTER_WIDTH_MULTIPLIER := 6.0
const NEON_MID_ALPHA := 0.3
const NEON_MID_WIDTH_MULTIPLIER := 3.0
const NEON_CORE_ALPHA := 1.0
const NEON_BASE_TRAIL_WIDTH := 2.0

const COST_MULTIPLIER := {
	PATH_CHEAP: 1.2,
	PATH_MEDIUM: 1.7,
	PATH_EXPENSIVE: 2
}
var wave_start_nonce := 0
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
var lure_next_ready_time := 0.0
var active_shield_emp_disabled_until := 0.0
var passive_shield_emp_disabled_until := 0.0
var world_special_state: Dictionary = {}

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


func _ensure_world_upgrade_data(world: int) -> void:
	if not world_upgrades.has(world):
		world_upgrades[world] = _default_upgrade_state()

	if world == current_world:
		var state: Dictionary = world_upgrades[world]
		var cannons: Dictionary = state["cannons"]
		for cannon_id in CANNON_IDS:
			if bool(cannons[cannon_id]["unlocked"]):
				_sync_cannon_ammo_caps_with_state(cannon_id, state)


func _sync_cannon_ammo_caps_with_state(cannon_id: String, state: Dictionary) -> void:
	var cannons: Dictionary = state["cannons"]
	if not cannons.has(cannon_id):
		return

	var cannon_state: Dictionary = cannons[cannon_id]
	if not bool(cannon_state["unlocked"]):
		return

	var current_ammo := int(cannon_state["current_ammo"])
	cannon_state["current_ammo"] = max(0, current_ammo)


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


#func get_shield_generator_cooldown_seconds() -> float:
	#var level := get_upgrade_level("shield_generator")
	#if level <= 0:
		#return 9999.0
	#return maxf(5.0, 30.0 - (3.0 * float(level)))


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
	var now_seconds := Time.get_ticks_msec() / 1000.0
	return has_active_shields_upgrade() and active_shield_is_held and active_shield_charge > 0.0 and now_seconds >= active_shield_emp_disabled_until


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

	var now_seconds := Time.get_ticks_msec() / 1000.0
	if now_seconds < active_shield_emp_disabled_until:
		active_shield_is_held = false
		return

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


func get_ion_wave_cooldown_remaining(now_seconds: float) -> float:
	return maxf(0.0, ion_wave_next_ready_time - now_seconds)


func is_ion_wave_active(now_seconds: float) -> bool:
	return now_seconds < ion_wave_end_time


func get_enemy_global_speed_multiplier(now_seconds: float) -> float:
	if is_ion_wave_active(now_seconds):
		return 0.2
	return 1.0


func get_lure_recharge_time() -> float:
	var level := get_upgrade_level("lure")
	if level <= 0:
		return 9999.0
	return maxf(4.0, 12.0 - float(level))


func can_trigger_lure(now_seconds: float) -> bool:
	return get_upgrade_level("lure") > 0 and now_seconds >= lure_next_ready_time


func trigger_lure(pos: Vector2, now_seconds: float) -> void:
	if not can_trigger_lure(now_seconds):
		return
	lure_position = pos
	lure_end_time = now_seconds + (2.0 + float(get_upgrade_level("lure")))
	lure_next_ready_time = now_seconds + get_lure_recharge_time()


func is_lure_active(now_seconds: float) -> bool:
	return now_seconds < lure_end_time


func get_lure_cooldown_remaining(now_seconds: float) -> float:
	return maxf(0.0, lure_next_ready_time - now_seconds)


func apply_emp_to_shields(duration: float) -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	var end_time := now_seconds + maxf(0.1, duration)
	active_shield_emp_disabled_until = maxf(active_shield_emp_disabled_until, end_time)
	passive_shield_emp_disabled_until = maxf(passive_shield_emp_disabled_until, end_time)
	active_shield_is_held = false


func is_active_shield_emp_disabled(now_seconds: float) -> bool:
	return now_seconds < active_shield_emp_disabled_until


func get_active_shield_emp_disabled_remaining(now_seconds: float) -> float:
	return maxf(0.0, active_shield_emp_disabled_until - now_seconds)


func is_passive_shield_emp_disabled(now_seconds: float) -> bool:
	return now_seconds < passive_shield_emp_disabled_until


func is_upgrade_available_in_world(upgrade_key: String, world: int) -> bool:
	var defs = get_upgrade_definitions_world_1()
	if not defs.has(upgrade_key):
		return false

	var def: Dictionary = defs[upgrade_key]
	var min_world: int = int(def.get("min_world", 1))

	return world >= min_world


func get_upgrade_definitions_world_1() -> Dictionary:
	return {
		"starting_ammo_middle_1": {
			"display_name": "+2 Max Ammo (Middle)",
			"description": "Adds 2 max ammo to the middle cannon per level.",
			"max_level": 10,
			"base_cost": 1,
			"path_rate": PATH_CHEAP,
			"requires": []
		},

		"ammo_factory_1": {
			"display_name": "Ammo Factory 1",
			"description": "Boosts ammo production for your base. Improves with each level.",
			"max_level": 10,
			"base_cost": 10,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"ammo_factory_2": {
			"display_name": "Ammo Factory 2",
			"description": "Further increases ammo production for sustained fights.",
			"max_level": 10,
			"base_cost": 20,
			"path_rate": PATH_MEDIUM,
			"requires": [{"upgrade": "ammo_factory_1", "min_level": 10}]
		},
		"starting_ammo_middle_2": {
			"display_name": "+2 Max Ammo (Middle)",
			"description": "Adds 2 more max ammo to the middle cannon per level.",
			"max_level": 10,
			"base_cost": 3,
			"path_rate": PATH_CHEAP,
			"requires": [{"upgrade": "starting_ammo_middle_1", "min_level": 10}]
		},
		"starting_ammo_middle_3": {
			"display_name": "+2 Max Ammo (Middle)",
			"description": "Pushes the middle cannon's ammo capacity even higher.",
			"max_level": 10,
			"base_cost": 5,
			"path_rate": PATH_CHEAP,
			"requires": [{"upgrade": "starting_ammo_middle_2", "min_level": 10}]
		},
		"unlock_left_cannon": {
			"display_name": "Unlock Left Cannon",
			"description": "Brings the left cannon online and expands your firing coverage.",
			"max_level": 1,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 10}
			]
		},
		"unlock_right_cannon": {
			"display_name": "Unlock Right Cannon",
			"description": "Brings the right cannon online and strengthens your defense line.",
			"max_level": 1,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 10}
			]
		},
		"starting_ammo_left_2": {
			"display_name": "+2 Max Ammo (Left)",
			"description": "Adds 2 max ammo to the left cannon per level.",
			"max_level": 10,
			"base_cost": 3,
			"path_rate": PATH_CHEAP,
			"requires": [{"upgrade": "unlock_left_cannon", "min_level": 1}]
		},
		"starting_ammo_left_3": {
			"display_name": "+2 Max Ammo (Left)",
			"description": "Raises the left cannon's ammo capacity even further.",
			"max_level": 10,
			"base_cost": 5,
			"path_rate": PATH_CHEAP,
			"requires": [{"upgrade": "starting_ammo_left_2", "min_level": 10}]
		},
		"starting_ammo_right_2": {
			"display_name": "+2 Max Ammo (Right)",
			"description": "Adds 2 max ammo to the right cannon per level.",
			"max_level": 10,
			"base_cost": 3,
			"path_rate": PATH_CHEAP,
			"requires": [{"upgrade": "unlock_right_cannon", "min_level": 1}]
		},
		"starting_ammo_right_3": {
			"display_name": "+2 Max Ammo (Right)",
			"description": "Raises the right cannon's ammo capacity even further.",
			"max_level": 10,
			"base_cost": 5,
			"path_rate": PATH_CHEAP,
			"requires": [{"upgrade": "starting_ammo_right_2", "min_level": 10}]
		},
		"double_turret_middle": {
			"display_name": "Double Turret (Middle)",
			"description": "Upgrades the middle cannon to fire two shots before reload.",
			"max_level": 1,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 10}
			]
		},
		"double_turret_left": {
			"display_name": "Double Turret (Left)",
			"description": "Upgrades the left cannon to fire two shots before reload.",
			"max_level": 1,
			"base_cost": 80,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "unlock_left_cannon", "min_level": 1}
			]
		},
		"double_turret_right": {
			"display_name": "Double Turret (Right)",
			"description": "Upgrades the right cannon to fire two shots before reload.",
			"max_level": 1,
			"base_cost": 80,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "unlock_right_cannon", "min_level": 1}
			]
		},
		"fire_rate_middle": {
			"display_name": "Fire Rate (Middle)",
			"description": "Increases the middle cannon's firing speed each level.",
			"max_level": 5,
			"base_cost": 10,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 10}
			]
		},
		"fire_rate_left": {
			"display_name": "Fire Rate (Left)",
			"description": "Increases the left cannon's firing speed each level.",
			"max_level": 5,
			"base_cost": 10,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "unlock_left_cannon", "min_level": 1}
			]
		},
		"fire_rate_right": {
			"display_name": "Fire Rate (Right)",
			"description": "Increases the right cannon's firing speed each level.",
			"max_level": 5,
			"base_cost": 10,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "unlock_right_cannon", "min_level": 1}
			]
		},
		"explosion_size": {
			"display_name": "Explosion Size",
			"description": "Increases explosion radius by 1 per level.",
			"max_level": 3,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"explosion_duration": {
			"display_name": "Explosion Duration",
			"description": "Adds 0.2 seconds of max-size explosion duration per level.",
			"max_level": 3,
			"base_cost": 75,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"missile_speed": {
			"display_name": "Missile Speed",
			"description": "Increases missile travel speed each level for faster interceptions.",
			"max_level": 10,
			"base_cost": 15,
			"path_rate": PATH_CHEAP,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"building_5": {
			"display_name": "Building 5",
			"description": "Adds a fifth building to strengthen your base.",
			"max_level": 1,
			"base_cost": 25,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"building_6": {
			"display_name": "Building 6",
			"description": "Adds a sixth building for even greater base durability.",
			"max_level": 1,
			"base_cost": 75,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "building_5", "min_level": 1}
			]
		},
		"building_ammo_bonus": {
			"display_name": "Building Ammo Boost",
			"description": "Increase the ammo gained after each wave per building by 1",
			"max_level": 1,
			"base_cost": 100,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "building_6", "min_level": 1}
			]
		},
		"repair_shop": {
			"display_name": "Repair Shop",
			"description": "Unlocks repairs with R and reduces repair cost each level.",
			"max_level": 10,
			"base_cost": 20,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"shield_generator": {
			"display_name": "Shield Generator",
			"description": "Gives each building a shield that blocks 1 hit, plus 1 more hit per level.",
			"max_level": 5,
			"base_cost": 40,
			"path_rate": PATH_EXPENSIVE,
			"min_world": 2,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"active_shields": {
			"display_name": "Active Shields",
			"description": "Hold Space to deploy a full-base shield. Battery duration and recharge speed improve each level.",
			"max_level": 5,
			"base_cost": 50,
			"path_rate": PATH_EXPENSIVE,
			"min_world": 2,
			"requires": [
				{"upgrade": "shield_generator", "min_level": 1}
			]
		},
		"auto_cannon": {
			"display_name": "Auto Cannon",
			"description": "Automatically targets enemy missiles. Fire interval starts at 20s and improves by 2s per level.",
			"max_level": 5,
			"base_cost": 50,
			"path_rate": PATH_EXPENSIVE,
			"min_world": 3,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"lure": {
			"display_name": "Lure",
			"description": "Press E to deploy a lure that lasts 2 seconds, plus 1 extra second per level.",
			"max_level": 3,
			"base_cost": 60,
			"path_rate": PATH_MEDIUM,
			"min_world": 4,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"ion_wave": {
			"display_name": "Ion Wave",
			"description": "Press W to slow all missiles. Duration increases by 1 second per level and recharge drops by 2 seconds per level.",
			"max_level": 5,
			"base_cost": 65,
			"path_rate": PATH_MEDIUM,
			"min_world": 5,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		},
		"resource_gain": {
			"display_name": "Resource Gain",
			"description": "Earn 1 additional resource per kill for each level purchased.",
			"max_level": 5,
			"base_cost": 50,
			"path_rate": PATH_MEDIUM,
			"requires": [
				{"upgrade": "starting_ammo_middle_1", "min_level": 1}
			]
		}
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

	if upgrade_key in ["starting_ammo_middle_1", "starting_ammo_middle_2", "starting_ammo_middle_3"]:
		_sync_cannon_ammo_caps(CANNON_MIDDLE)
	elif upgrade_key == "unlock_left_cannon":
		_sync_cannon_ammo_caps(CANNON_LEFT)
	elif upgrade_key in ["starting_ammo_left_2", "starting_ammo_left_3"]:
		_sync_cannon_ammo_caps(CANNON_LEFT)
	elif upgrade_key == "unlock_right_cannon":
		_sync_cannon_ammo_caps(CANNON_RIGHT)
	elif upgrade_key in ["starting_ammo_right_2", "starting_ammo_right_3"]:
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
			return 10 \
				+ (get_upgrade_level("starting_ammo_middle_1") * 2) \
				+ (get_upgrade_level("starting_ammo_middle_2") * 2) \
				+ (get_upgrade_level("starting_ammo_middle_3") * 2)
		CANNON_LEFT:
			return 10 \
				+ (get_upgrade_level("starting_ammo_left_2") * 2) \
				+ (get_upgrade_level("starting_ammo_left_3") * 2)
		CANNON_RIGHT:
			return 10 \
				+ (get_upgrade_level("starting_ammo_right_2") * 2) \
				+ (get_upgrade_level("starting_ammo_right_3") * 2)
		_:
			return 0


func _get_upgrade_level_from_state(state: Dictionary, upgrade_key: String) -> int:
	var levels: Dictionary = state.get("upgrade_levels", {})
	return int(levels.get(upgrade_key, 0))


func _get_cannon_max_ammo_from_state(state: Dictionary, cannon_id: String) -> int:
	match cannon_id:
		CANNON_MIDDLE:
			return 10 \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_middle_1") * 2) \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_middle_2") * 2) \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_middle_3") * 2)
		CANNON_LEFT:
			return 10 \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_left_2") * 2) \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_left_3") * 2)
		CANNON_RIGHT:
			return 10 \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_right_2") * 2) \
				+ (_get_upgrade_level_from_state(state, "starting_ammo_right_3") * 2)
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


func _get_wave_building_ammo_per_building() -> int:
	if get_upgrade_level("building_ammo_bonus") > 0:
		return 2
	return 1


func _get_surviving_buildings_for_wave_bonus() -> int:
	return _get_surviving_building_nodes_for_wave_bonus().size()


func _get_surviving_building_nodes_for_wave_bonus() -> Array:
	var tree := get_tree()
	if tree == null:
		return []

	var buildings: Array = []
	for node in tree.get_nodes_in_group("building"):
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("is_destroyed") and bool(node.is_destroyed()):
			continue
		buildings.append(node)

	return buildings


func _grant_wave_building_ammo_bonus() -> void:
	if current_wave <= 1:
		return

	var state := _world_state()
	var cannons: Dictionary = state["cannons"]
	var available_cannons: Array[String] = []
	for cannon_id in CANNON_IDS:
		var cannon_state: Dictionary = cannons[cannon_id]
		if not bool(cannon_state["unlocked"]) or bool(cannon_state["destroyed"]):
			continue
		available_cannons.append(cannon_id)

	if available_cannons.is_empty():
		return

	var surviving_buildings_nodes := _get_surviving_building_nodes_for_wave_bonus()
	var surviving_buildings := surviving_buildings_nodes.size()
	if surviving_buildings <= 0:
		return

	var ammo_per_building := _get_wave_building_ammo_per_building()
	for building in surviving_buildings_nodes:
		if building != null and is_instance_valid(building) and building.has_method("play_wave_ammo_bonus_animation"):
			building.play_wave_ammo_bonus_animation(ammo_per_building)

	var total_bonus_ammo := surviving_buildings * ammo_per_building
	var distribution_index := 0

	while total_bonus_ammo > 0:
		var granted_this_pass := false
		for offset in range(available_cannons.size()):
			var idx := (distribution_index + offset) % available_cannons.size()
			var cannon_id := available_cannons[idx]
			var cannon_state: Dictionary = cannons[cannon_id]
			var current_ammo := int(cannon_state["current_ammo"])
			var max_ammo := _get_cannon_max_ammo_from_state(state, cannon_id)
			if current_ammo >= max_ammo:
				continue

			cannon_state["current_ammo"] = current_ammo + 1
			total_bonus_ammo -= 1
			distribution_index = (idx + 1) % available_cannons.size()
			granted_this_pass = true

			if total_bonus_ammo <= 0:
				break

		if not granted_this_pass:
			break

	print("🔋 Wave ammo bonus granted: +%d ammo from %d surviving buildings" % [surviving_buildings * ammo_per_building, surviving_buildings])


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
	return _world_state()["upgrade_levels"]


func add_upgrade_stat(upgrade_key: String, amount := 1) -> void:
	add_upgrade_level(upgrade_key, amount)


func get_max_ammo() -> int:
	return get_cannon_max_ammo(CANNON_MIDDLE)


func get_reload_speed():
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
	lure_next_ready_time = 0.0
	active_shield_emp_disabled_until = 0.0
	passive_shield_emp_disabled_until = 0.0
	world_special_state = {}


func start_wave():
	wave_start_nonce += 1
	var my_nonce: int = wave_start_nonce

	await get_tree().create_timer(2.0).timeout

	if my_nonce != wave_start_nonce:
		print("⛔ start_wave() cancelled by newer wave request")
		return

	print("📣 start_wave() called")
	print("🌊 Starting Wave %d (World %d)" % [current_wave, current_world])
	_grant_wave_building_ammo_bonus()

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
		_spawn_world_special_attacks()

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


func _special_state() -> Dictionary:
	if world_special_state.is_empty():
		world_special_state = {
			"scatter_last_wave": -99,
			"emp_last_wave": -99,
			"ion_target_total": randi_range(2, 5),
			"ion_spawned_total": 0,
			"plane_target_total": randi_range(4, 8),
			"plane_spawned_total": 0
		}
	return world_special_state


func _spawn_world_special_attacks() -> void:
	if spawner == null or not is_instance_valid(spawner):
		return
	var state := _special_state()

	match current_world:
		2:
			_try_spawn_scatter(state)
		3:
			_try_spawn_side_planes(state)
		4:
			_try_spawn_emp(state)
			_try_spawn_side_planes(state)
		5:
			_try_spawn_ion(state)
			_try_spawn_side_planes(state)


func _try_spawn_scatter(state: Dictionary) -> void:
	if current_wave < 5:
		return

	var min_gap := 3
	if current_wave >= 12:
		min_gap = 2
	if current_wave - int(state["scatter_last_wave"]) < min_gap:
		return

	var base_chance := 0.18
	var extra := clampf((float(current_wave) - 5.0) * 0.02, 0.0, 0.25)
	var chance := base_chance + extra
	if randf() <= chance:
		if spawner.has_method("spawn_scatter_missile"):
			spawner.spawn_scatter_missile()
			state["scatter_last_wave"] = current_wave


func _try_spawn_emp(state: Dictionary) -> void:
	if current_wave < 5:
		return
	if current_wave - int(state["emp_last_wave"]) < 3:
		return

	if randf() <= 0.24:
		if spawner.has_method("spawn_emp_missile"):
			spawner.spawn_emp_missile()
			state["emp_last_wave"] = current_wave


func _try_spawn_ion(state: Dictionary) -> void:
	var target_total := int(state["ion_target_total"])
	var spawned_total := int(state["ion_spawned_total"])
	if spawned_total >= target_total:
		return
	if current_wave < 5:
		return

	var waves_left: int = max(1, 50 - current_wave)
	var remaining: int = max(1, target_total - spawned_total)
	var chance := clampf(float(remaining) / float(waves_left), 0.04, 0.16)
	if randf() <= chance:
		if spawner.has_method("spawn_ion_missile"):
			spawner.spawn_ion_missile()
			state["ion_spawned_total"] = spawned_total + 1


func _try_spawn_side_planes(state: Dictionary) -> void:
	var target_total := int(state["plane_target_total"])
	var spawned_total := int(state["plane_spawned_total"])
	if spawned_total >= target_total:
		return
	if current_wave < 5:
		return

	var max_wave := 20
	if current_world == 4:
		max_wave = 35
	elif current_world == 5:
		max_wave = 50

	var waves_left: int = max(1, max_wave - current_wave)
	var remaining: int = max(1, target_total - spawned_total)
	var spawn_chance := clampf(float(remaining) / float(waves_left), 0.12, 0.35)
	if randf() > spawn_chance:
		return

	var burst_count := 1
	if remaining >= 3 and randf() < 0.22:
		burst_count = 2

	var spawned_now := 0
	for _i in range(burst_count):
		if int(state["plane_spawned_total"]) >= target_total:
			break
		var role := "fighter"
		if randf() < 0.35:
			role = "bomber"
		if spawner.has_method("spawn_side_plane"):
			spawner.spawn_side_plane(role)
			state["plane_spawned_total"] = int(state["plane_spawned_total"]) + 1
			spawned_now += 1
		if spawned_now > 0:
			await get_tree().create_timer(randf_range(0.2, 0.8)).timeout


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
		emit_signal("announce_wave", "Wave %d" % current_wave, 2.0)
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
