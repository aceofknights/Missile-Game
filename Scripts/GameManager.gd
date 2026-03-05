extends Node

const WORLD_COUNT := 5

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

signal announce_wave(message: String, duration: float)


func _ready():
	_ensure_world_upgrade_data(current_world)


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
				_sync_cannon_ammo_caps(cannon_id)


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


func get_upgrade_definitions_world_1() -> Dictionary:
	# This structure is intentionally data-first so future worlds can extend it
	# while reusing the same key names and dependency checks.
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
		}
	}


func can_buy_upgrade(upgrade_key: String) -> bool:
	var defs = get_upgrade_definitions_world_1()
	if not defs.has(upgrade_key):
		return false

	var def: Dictionary = defs[upgrade_key]
	var level = get_upgrade_level(upgrade_key)
	if level >= int(def.get("max_level", 1)):
		return false

	for requirement in def.get("requires", []):
		var req_upgrade: String = requirement.get("upgrade", "")
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

	if upgrade_key == "starting_ammo_middle_1":
		_sync_cannon_ammo_caps(CANNON_MIDDLE)
	elif upgrade_key == "unlock_left_cannon":
		_sync_cannon_ammo_caps(CANNON_LEFT)
	elif upgrade_key == "unlock_right_cannon":
		_sync_cannon_ammo_caps(CANNON_RIGHT)

	return true


func add_resources(amount: int):
	player_resources += amount
	print("💰 Gained %d resource(s). Total: %d" % [amount, player_resources])


func set_cannon_unlocked(cannon_id: String, unlocked: bool) -> void:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return
	var cannon_state: Dictionary = cannons[cannon_id]
	cannon_state["unlocked"] = unlocked
	if unlocked:
		cannon_state["destroyed"] = false
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
			return 10 + (get_upgrade_level("starting_ammo_middle_1") * 2)
		CANNON_LEFT:
			# Placeholder world-1 tree values; these become upgrade-driven later.
			return 10
		CANNON_RIGHT:
			return 10
		_:
			return 0


func get_cannon_starting_ammo(cannon_id: String) -> int:
	# For now, world-1 starts from full for unlocked cannons.
	return get_cannon_max_ammo(cannon_id)


func _sync_cannon_ammo_caps(cannon_id: String) -> void:
	var cannons: Dictionary = _world_state()["cannons"]
	if not cannons.has(cannon_id):
		return
	var cannon_state: Dictionary = cannons[cannon_id]
	if not bool(cannon_state["unlocked"]):
		return
	var max_ammo = get_cannon_max_ammo(cannon_id)
	var current_ammo = int(cannon_state["current_ammo"])
	if current_ammo <= 0:
		cannon_state["current_ammo"] = get_cannon_starting_ammo(cannon_id)
	else:
		cannon_state["current_ammo"] = clamp(current_ammo, 0, max_ammo)


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
	var max_ammo = get_cannon_max_ammo(cannon_id)
	cannon_state["current_ammo"] = clamp(value, 0, max_ammo)


func spend_cannon_ammo(cannon_id: String, amount := 1) -> bool:
	if not is_cannon_unlocked(cannon_id) or is_cannon_destroyed(cannon_id):
		return false
	var current = get_cannon_current_ammo(cannon_id)
	if current < amount:
		return false
	set_cannon_current_ammo(cannon_id, current - amount)
	return true


func _get_ammo_factory_interval() -> float:
	var level = get_upgrade_level("ammo_factory_1")
	if level <= 0:
		return -1.0
	return max(3.0, 5.0 - (0.2 * (level - 1)))


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
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func player_died():
	load_upgrade_screen()


func continue_from_upgrades():
	current_wave = 1
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
	get_tree().change_scene_to_file("res://Scene/Main.tscn")


func start_wave():
	await get_tree().create_timer(2.0).timeout

	print("📣 start_wave() called")
	print("🌊 Starting Wave %d (World %d)" % [current_wave, current_world])
	is_boss_wave = (current_wave % 10 == 0)

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
	_on_world_defeated()


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
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func load_upgrade_screen():
	get_tree().change_scene_to_file("res://Scene/UpgradeScreen.tscn")


func advance_to_next_world():
	_on_world_defeated()
