extends Area2D

signal enemy_died

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var scatter_missile_scene: PackedScene
@export var move_speed := 120.0
@export var max_health := 3
@export var shield_up_duration := 3.5
@export var shield_down_duration := 2.0
@export var missile_drop_interval := 1.0
@export var scatter_min_interval := 5.0
@export var scatter_max_interval := 8.0

@onready var shield_timer: Timer = $ShieldTimer
@onready var missile_timer: Timer = $MissileTimer
@onready var scatter_timer: Timer = $ScatterTimer
@onready var sprite: Sprite2D = $Sprite2D
@onready var boss_health = $boss_health

var health := 3
var shield_active := true
var hit_used_this_down_window := false
var scatter_released := false
var move_direction := 1.0
var is_dead := false


func _ready():
	health = max_health
	add_to_group("enemy")
	shield_timer.wait_time = shield_up_duration
	shield_timer.timeout.connect(_on_shield_timer_timeout)
	shield_timer.start()

	missile_timer.wait_time = missile_drop_interval
	missile_timer.timeout.connect(_on_missile_timer_timeout)
	missile_timer.start()

	scatter_timer.one_shot = true
	scatter_timer.timeout.connect(_on_scatter_timer_timeout)

	_update_visuals()


func _process(delta):
	if is_dead:
		return
	boss_health.text = "Health %d" % health
	var viewport = get_viewport_rect().size
	global_position.x += move_direction * move_speed * delta

	var boss_speed

	if health == 3:
		boss_speed = 1
	elif health == 2:
		boss_speed = 2
		if move_direction == 1:
			move_direction = boss_speed
		elif move_direction == -1:
			move_direction = boss_speed * -1
	else:
		boss_speed = 5
		if move_direction == 2:
			move_direction = boss_speed
		elif move_direction == -2:
			move_direction = boss_speed * -1

	if global_position.x < 120:
		global_position.x = 120
		move_direction = boss_speed
	elif global_position.x > viewport.x - 120:
		global_position.x = viewport.x - 120
		move_direction = boss_speed * -1


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

	if health == 1:
		var viewport = get_viewport_rect().size
		if global_position.x < 120:
			global_position.x = 120
			move_direction = 5.0
		elif global_position.x > viewport.x - 120:
			global_position.x = viewport.x - 120
			move_direction = -5.0

	# 🔧 PATCH: start repeating scatter when entering phase (HP == 1)
	if health == 1 and not scatter_released:
		scatter_released = true
		spawn_scatter_missile()          # fire one immediately (optional)
		_schedule_next_scatter()         # then keep firing every 5–8 seconds

	if health == 2:
		var viewport = get_viewport_rect().size
		if global_position.x < 120:
			global_position.x = 120
			move_direction = 2.0
		elif global_position.x > viewport.x - 120:
			global_position.x = viewport.x - 120
			move_direction = -2.0

	_update_visuals()


func _die_for_real(no_reward := false):
	is_dead = true
	missile_timer.stop()
	shield_timer.stop()
	scatter_timer.stop() # 🔧 PATCH: stop scatter timer too

	if not no_reward:
		GameManager.add_resources(10)

	emit_signal("enemy_died")

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		get_tree().current_scene.add_child(explosion)

	queue_free()


func _on_shield_timer_timeout():
	if shield_active:
		shield_active = false
		hit_used_this_down_window = false
		shield_timer.wait_time = shield_down_duration
		print("⚡ Boss shield DOWN")
	else:
		shield_active = true
		shield_timer.wait_time = shield_up_duration
		print("🛡️ Boss shield UP")

	_update_visuals()
	shield_timer.start()


func _on_missile_timer_timeout():
	if is_dead:
		return
	spawn_normal_missile()


# 🔧 PATCH: scatter timer callback + scheduler
func _on_scatter_timer_timeout():
	if is_dead:
		return
	if health == 1:
		spawn_scatter_missile()
		_schedule_next_scatter()

func _schedule_next_scatter():
	if is_dead:
		return
	if health != 1:
		return
	scatter_timer.wait_time = randf_range(scatter_min_interval, scatter_max_interval)
	scatter_timer.start()


func spawn_normal_missile():
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
	get_tree().current_scene.add_child(missile)


func spawn_scatter_missile():
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
	get_tree().current_scene.add_child(missile)
	print("☄️ Scatter missile launched")


func _update_visuals():
	if shield_active:
		sprite.modulate = Color(0.5, 0.85, 1.0, 1.0)
	else:
		sprite.modulate = Color(1.0, 0.45, 0.45, 1.0)
