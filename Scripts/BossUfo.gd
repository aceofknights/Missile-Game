extends Area2D

signal enemy_died
signal boss_defeated

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var scatter_missile_scene: PackedScene
@export var move_speed := 120.0
@export var max_health := 3
@export var shield_up_duration := 3.5
@export var shield_down_duration := 2.0
@export var missile_drop_interval := 1.0

# Scatter starts at 8 seconds and speeds up each time boss is hit
@export var scatter_start_interval := 8.0
@export var scatter_interval_step := 2.0
@export var scatter_min_interval := 3.0

@onready var shield_timer: Timer = $ShieldTimer
@onready var missile_timer: Timer = $MissileTimer
@onready var scatter_timer: Timer = $ScatterTimer
@onready var sprite: Sprite2D = $BossSprite
@onready var boss_health = $boss_health
@onready var shield_sprite: Sprite2D = $ShieldSprite


var health := 3
var shield_active := true
var hit_used_this_down_window := false
var move_direction := 1.0
var is_dead := false
var current_scatter_interval := 8.0


func _add_to_scene(node: Node) -> void:
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.add_child(node)
	else:
		get_tree().root.add_child(node)


func _ready():
	health = max_health
	current_scatter_interval = scatter_start_interval
	add_to_group("enemy")

	shield_timer.wait_time = shield_up_duration
	shield_timer.timeout.connect(_on_shield_timer_timeout)
	shield_timer.start()

	missile_timer.wait_time = missile_drop_interval
	missile_timer.timeout.connect(_on_missile_timer_timeout)
	missile_timer.start()

	scatter_timer.one_shot = true
	scatter_timer.timeout.connect(_on_scatter_timer_timeout)
	_schedule_next_scatter()

	_set_shield_active(true)


func _process(delta):
	if is_dead:
		return

	boss_health.text = "Health %d" % health

	var viewport = get_viewport_rect().size
	global_position.x += move_direction * move_speed * delta

	var boss_speed

	if health >= 3:
		boss_speed = 1
	elif health == 2:
		boss_speed = 2
		if move_direction == 1:
			move_direction = boss_speed
		elif move_direction == -1:
			move_direction = -boss_speed
	else:
		boss_speed = 5
		if move_direction == 2:
			move_direction = boss_speed
		elif move_direction == -2:
			move_direction = -boss_speed

	if global_position.x < 120:
		global_position.x = 120
		move_direction = boss_speed
	elif global_position.x > viewport.x - 120:
		global_position.x = viewport.x - 120
		move_direction = -boss_speed


func die(no_reward := false):
	if is_dead:
		return
	if shield_active:
		print("🛡️ Boss shield blocked the hit")
		return
	if hit_used_this_down_window:
		print("🛡️ Boss already took a hit during this shield break")
		return

	hit_used_this_down_window = true
	health -= 1
	print("👾 Boss hit! Remaining HP: %d" % health)

	if health <= 0:
		_die_for_real(no_reward)
		return

	# Speed up scatter every time the boss is hit
	current_scatter_interval = max(scatter_min_interval, current_scatter_interval - scatter_interval_step)
	print("☄️ Scatter interval now: %.2f seconds" % current_scatter_interval)

	# Restart timer so the ramp-up is felt immediately
	_schedule_next_scatter()

	if health == 1:
		var viewport = get_viewport_rect().size
		if global_position.x < 120:
			global_position.x = 120
			move_direction = 5.0
		elif global_position.x > viewport.x - 120:
			global_position.x = viewport.x - 120
			move_direction = -5.0

	if health == 2:
		var viewport = get_viewport_rect().size
		if global_position.x < 120:
			global_position.x = 120
			move_direction = 2.0
		elif global_position.x > viewport.x - 120:
			global_position.x = viewport.x - 120
			move_direction = -2.0



func _die_for_real(no_reward := false):
	is_dead = true
	missile_timer.stop()
	shield_timer.stop()
	scatter_timer.stop()

	if not no_reward:
		GameManager.add_resources(10)

	emit_signal("boss_defeated")
	emit_signal("enemy_died")

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		_add_to_scene(explosion)

	queue_free()


func _on_shield_timer_timeout():
	if shield_active:
		_set_shield_active(false)
		hit_used_this_down_window = false
		shield_timer.wait_time = shield_down_duration
		print("⚡ Boss shield DOWN")
	else:
		_set_shield_active(true)
		shield_timer.wait_time = shield_up_duration
		print("🛡️ Boss shield UP")

	shield_timer.start()


func _on_missile_timer_timeout():
	if is_dead:
		return
	spawn_normal_missile()


func _on_scatter_timer_timeout():
	if is_dead:
		return
	spawn_scatter_missile()
	_schedule_next_scatter()


func _schedule_next_scatter():
	if is_dead:
		return
	scatter_timer.stop()
	scatter_timer.wait_time = current_scatter_interval
	scatter_timer.start()


func spawn_normal_missile():
	if is_dead:
		return
	if missile_scene == null:
		return

	var missile = missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport = get_viewport_rect().size
	var target = Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	var direction = (target - global_position).normalized()

	missile.global_position = global_position + Vector2(0, 30)
	missile.velocity = direction

	_add_to_scene(missile)


func spawn_scatter_missile():
	if is_dead:
		return
	if scatter_missile_scene == null:
		return

	var missile = scatter_missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport = get_viewport_rect().size
	var target = Vector2(randf_range(80.0, viewport.x - 80.0), viewport.y)
	var direction = (target - global_position).normalized()

	missile.global_position = global_position + Vector2(0, 35)
	missile.velocity = direction

	_add_to_scene(missile)
	print("☄️ Scatter missile launched")


func _set_shield_active(value: bool) -> void:
	shield_active = value

	if shield_sprite:
		shield_sprite.visible = shield_active
