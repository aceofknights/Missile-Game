extends Node2D

@export var enemy_scene: PackedScene
@export var spawn_interval = 2.0

var spawn_timer = 0.0
var screen_size

func _ready():
	screen_size = get_viewport_rect().size
	GameManager.spawner = self
	
#func _process(delta):
	#spawn_timer += delta
	#if spawn_timer >= spawn_interval:
		#spawn_timer = 0
		#spawn_enemy()

@export var boss_scene: PackedScene

func spawn_boss():
	if not boss_scene:
		print("❌ No boss scene assigned!")
		return

	var boss = boss_scene.instantiate()
	boss.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))
	GameManager.enemies_alive += 1

	boss.position = Vector2(screen_size.x / 2, -100)  # Drop from center top
	boss.velocity = Vector2(0, 1)  # Slow descent

	get_tree().current_scene.add_child(boss)

func spawn_enemy():
	if not enemy_scene:
		print("❌ ERROR: enemy_scene is still null!")
		return
		
	var enemy = enemy_scene.instantiate()
	GameManager.enemies_alive += 1
	print("📦 Spawning enemy. Total alive: %d" % GameManager.enemies_alive)

	enemy.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	
	# Random X along top
	var x_pos = randf_range(0, screen_size.x)
	enemy.position = Vector2(x_pos, position.y)
	
	# Random X at bottom to target
	var target_x = randf_range(0, screen_size.x)
	var target_pos = Vector2(target_x, screen_size.y)
	
	# Set velocity vector toward the target
	var direction = (target_pos - enemy.position).normalized()
	enemy.velocity = direction

	get_tree().current_scene.add_child(enemy)
