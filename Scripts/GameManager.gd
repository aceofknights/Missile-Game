extends Node

var current_wave = 1
var current_world = 1
var player_upgrades = {}
var player_resources = 0
var ammo_level = 0
var reload_speed_level = -1
var reload_upgrade_bought = false
var enemies_to_spawn = 1
var enemies_alive = 0
var is_boss_wave = false
var wave_active = false
var spawner: Node = null
signal announce_wave(message: String, duration: float)


func add_resources(amount: int):
	player_resources += amount
	print("💰 Gained %d resource(s). Total: %d" % [amount, player_resources])

func get_max_ammo():
	return 10 + (ammo_level * 2)

func get_reload_speed():
	if reload_upgrade_bought:
		return 5 - (reload_speed_level * 0.1)

func reload_bought():
	reload_upgrade_bought = true

func start_new_game():
	current_world = 1
	current_wave = 1
	player_resources = 0
	player_upgrades = {}
	get_tree().change_scene_to_file("res://Scene/Main.tscn")

func player_died():
	load_upgrade_screen()
	
func continue_from_upgrades():
	current_wave = 1  # Restart wave count
	get_tree().change_scene_to_file("res://Scene/Main.tscn")  # Load game scene

	
func start_wave():
	await get_tree().create_timer(2.0).timeout

	print("📣 start_wave() called")  # Add this
	print("🌊 Starting Wave %d" % current_wave)
	is_boss_wave = (current_wave % 10 == 0)
	
	enemies_alive = 0
	wave_active = true

	if is_boss_wave:
		spawner.spawn_boss()
	else:
		enemies_to_spawn = 0 + current_wave * 2
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
	print("GameManager noticed: an enemy died!")
	enemies_alive -= 1
	print("Enemies remaining: %d" % enemies_alive)

	if enemies_alive <= 0 and wave_active:
		print("✅ Wave %d completed!" % current_wave)
		wave_active = false
		next_wave_or_boss()


func next_wave_or_boss():
	if is_boss_wave:
		print("👹 Boss defeated! Proceeding to next world...")
		current_wave = 1
		current_world += 1
		get_tree().change_scene_to_file("res://scenes/UpgradeScreen.tscn")
	else:
		current_wave += 1
		await get_tree().create_timer(1.0).timeout
		emit_signal("announce_wave", "🌊 Wave %d Incoming..." % current_wave, 2.0)
		await get_tree().create_timer(2.0).timeout
		start_wave()
	
func load_boss_fight():
	get_tree().change_scene_to_file("res://BossFight.tscn")

func boss_defeated():
	advance_to_next_world()
	
func load_upgrade_screen():
	get_tree().change_scene_to_file("res://Scene/UpgradeScreen.tscn")

func advance_to_next_world():
	current_world += 1
	current_wave = 1
	get_tree().change_scene_to_file("res://MainGame.tscn")

