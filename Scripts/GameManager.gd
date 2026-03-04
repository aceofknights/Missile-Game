extends Node

const WORLD_COUNT := 5

var current_wave := 1
var current_world := 1

# Currency can stay global for now; "planet upgrades" are per-world below.
var player_resources := 100

# Highest world index the player can select in World Select.
var highest_world_unlocked := 1

# Per-world upgrade storage.
# world_upgrades[world] = {
#   "ammo_level": int,
#   "reload_upgrade_bought": bool,
#   "reload_speed_level": int,
#   "extra_buildings": int,
#   "player_upgrades": Dictionary
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


func _default_upgrade_state() -> Dictionary:
	return {
		"ammo_level": 0,
		"reload_upgrade_bought": false,
		"reload_speed_level": -1,
		"extra_buildings": 0,
		"player_upgrades": {}
	}


func _ensure_world_upgrade_data(world: int) -> void:
	if not world_upgrades.has(world):
		world_upgrades[world] = _default_upgrade_state()


func _world_state() -> Dictionary:
	_ensure_world_upgrade_data(current_world)
	return world_upgrades[current_world]


func add_resources(amount: int):
	player_resources += amount
	print("💰 Gained %d resource(s). Total: %d" % [amount, player_resources])


func get_max_ammo() -> int:
	return 10 + (get_ammo_level() * 2)


func get_reload_speed():
	if has_reload_upgrade():
		return 5 - (get_reload_speed_level() * 0.1)
	return null


func has_reload_upgrade() -> bool:
	return bool(_world_state()["reload_upgrade_bought"])


func get_reload_speed_level() -> int:
	return int(_world_state()["reload_speed_level"])


func get_ammo_level() -> int:
	return int(_world_state()["ammo_level"])


func get_extra_buildings() -> int:
	return int(_world_state()["extra_buildings"])


func get_player_upgrades() -> Dictionary:
	return _world_state()["player_upgrades"]


func add_ammo_upgrade(levels := 1) -> void:
	var state = _world_state()
	state["ammo_level"] = int(state["ammo_level"]) + levels


func buy_reload_upgrade_once() -> bool:
	var state = _world_state()
	if bool(state["reload_upgrade_bought"]):
		return false
	state["reload_upgrade_bought"] = true
	state["reload_speed_level"] = int(state["reload_speed_level"]) + 1
	return true


func set_extra_buildings(level: int) -> void:
	var state = _world_state()
	state["extra_buildings"] = clamp(level, 0, 2)


func add_upgrade_stat(upgrade_key: String, amount := 1) -> void:
	var state = _world_state()
	var upgrades: Dictionary = state["player_upgrades"]
	upgrades[upgrade_key] = int(upgrades.get(upgrade_key, 0)) + amount


func start_new_game():
	# New campaign run starts from World 1; only World 1 unlocked.
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

	enemies_alive = 0
	wave_active = true

	if is_boss_wave:
		spawner.spawn_boss()
	else:
		enemies_to_spawn = current_wave * 2
		await spawn_enemies_gradually(enemies_to_spawn)


func spawn_enemies_gradually(count):
	var delay = max(0.3, 1.5 - (current_world * 0.2) - (current_wave * 0.05))
	print("⏱ Spawning enemies with delay of %.2f" % delay)

	for i in range(count):
		if not wave_active or spawner == null or !is_instance_valid(spawner):
			print("⛔️ Spawning cancelled: wave is no longer active or spawner is invalid")
			return
		spawner.spawn_enemy()
		await get_tree().create_timer(delay).timeout


func _on_enemy_died():
	enemies_alive -= 1
	print("Enemies remaining: %d" % enemies_alive)

	if enemies_alive <= 0 and wave_active:
		wave_active = false
		next_wave_or_boss()


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

	# Return to home base / world select after clearing a world.
	current_wave = 1
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func load_upgrade_screen():
	get_tree().change_scene_to_file("res://Scene/UpgradeScreen.tscn")


func advance_to_next_world():
	# Legacy compatibility helper.
	_on_world_defeated()
