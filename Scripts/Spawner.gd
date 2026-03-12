extends Node2D

@export var enemy_scene: PackedScene
@export var spawn_interval = 2.0

var spawn_timer = 0.0
var screen_size

@export var boss_scene: PackedScene
const DEFAULT_BOSS_SCENE_PATH := "res://Scene/boss_ufo.tscn"
const WORLD_BOSS_SCENES := {
	1: "res://Scene/boss_ufo.tscn",
	2: "res://Scene/boss_carrier.tscn",
	3: "res://Scene/boss_world3.tscn",
	4: "res://Scene/boss_world4.tscn",
	5: "res://Scene/boss_world5.tscn"
}


# ✅ Safe add_child helper (prevents current_scene null crash during scene transitions)
func _add_to_scene(node: Node) -> void:
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.add_child(node)
	else:
		get_tree().root.add_child(node)


func _ready():
	screen_size = get_viewport_rect().size
	GameManager.spawner = self
	_ensure_boss_scene()


func _ensure_boss_scene() -> void:
	var world_boss_path: String = WORLD_BOSS_SCENES.get(GameManager.current_world, DEFAULT_BOSS_SCENE_PATH)
	var loaded = load(world_boss_path)
	if loaded is PackedScene:
		boss_scene = loaded
		print("ℹ️ Boss scene loaded for World %d from %s" % [GameManager.current_world, world_boss_path])
		return

	if boss_scene != null:
		return

	loaded = load(DEFAULT_BOSS_SCENE_PATH)
	if loaded is PackedScene:
		boss_scene = loaded
		print("ℹ️ Boss scene fallback loaded from %s" % DEFAULT_BOSS_SCENE_PATH)


func spawn_boss():
	_ensure_boss_scene()
	if not boss_scene:
		push_error("❌ No boss scene assigned on Spawner and fallback failed: %s" % DEFAULT_BOSS_SCENE_PATH)
		return

	var boss = boss_scene.instantiate()

	# ✅ Boss should end the world (unlock next + return to WorldSelect)
	if boss.has_signal("boss_defeated"):
		boss.boss_defeated.connect(Callable(GameManager, "on_boss_defeated"))
	else:
		# fallback if boss_defeated missing for some reason
		boss.enemy_died.connect(Callable(GameManager, "on_boss_defeated"))

	# Do NOT connect boss.enemy_died to _on_enemy_died (prevents wave logic weirdness)

	# If you still track boss as "alive", keep this

	boss.position = Vector2(screen_size.x / 2.0, 120.0)
	_add_to_scene(boss)


func spawn_enemy():
	if not enemy_scene:
		print("❌ ERROR: enemy_scene is still null!")
		return

	var enemy = enemy_scene.instantiate()

	print("📦 Spawning enemy. Total alive: %d" % GameManager.enemies_alive)

	enemy.enemy_died.connect(Callable(GameManager, "_on_enemy_died"))

	# Random X along top
	var x_pos = randf_range(0.0, screen_size.x)
	enemy.position = Vector2(x_pos, position.y)

	# Random X at bottom to target
	var target_x = randf_range(0.0, screen_size.x)
	var target_pos = Vector2(target_x, screen_size.y)

	# Set velocity vector toward the target
	var direction = (target_pos - enemy.position).normalized()
	enemy.velocity = direction

	_add_to_scene(enemy)
