extends Area2D

signal enemy_died
signal boss_defeated
signal jam_charge_started(duration: float)
signal jam_pulse_started(duration: float, misfire_radius: float)

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var emp_missile_scene: PackedScene
@export var move_speed := 120.0
@export var max_health := 5
@export var shield_up_duration := 3.5
@export var shield_down_duration := 2.0
@export var missile_drop_interval := 1.2
@export var missile_drop_interval_min := 0.45
@export var emp_interval := 4.8
@export var emp_charge_duration := 0.8
@export var jam_interval := 6.5
@export var jam_charge_duration := 0.9
@export var jam_duration_min := 1.0
@export var jam_duration_max := 2.0
@export var jam_misfire_radius := 95.0

@onready var shield_timer: Timer = $ShieldTimer
@onready var missile_timer: Timer = $MissileTimer
@onready var emp_timer: Timer = $EmpTimer
@onready var jam_timer: Timer = $JamTimer
@onready var jam_charge_timer: Timer = $JamChargeTimer
@onready var emp_charge_timer: Timer = $EmpChargeTimer
@onready var sprite: Sprite2D = $Sprite2D
@onready var boss_health = $boss_health
@onready var jam_ring: Line2D = $JamRing
@onready var emp_ring: Line2D = $EmpRing

var health := 5
var shield_active := true
var hit_used_this_down_window := false
var move_direction := 1.0
var is_dead := false
var queued_emp_targets: Array = []
var emp_charge_active := false


func _add_to_scene(node: Node) -> void:
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.add_child(node)
	else:
		get_tree().root.add_child(node)


func _ready() -> void:
	health = max_health
	add_to_group("enemy")

	shield_timer.wait_time = shield_up_duration
	shield_timer.timeout.connect(_on_shield_timer_timeout)
	shield_timer.start()

	missile_timer.wait_time = missile_drop_interval
	missile_timer.timeout.connect(_on_missile_timer_timeout)
	missile_timer.start()

	emp_timer.wait_time = emp_interval
	emp_timer.timeout.connect(_on_emp_timer_timeout)
	emp_timer.start()
	emp_charge_timer.one_shot = true
	emp_charge_timer.wait_time = emp_charge_duration
	emp_charge_timer.timeout.connect(_on_emp_charge_timer_timeout)

	jam_timer.wait_time = jam_interval
	jam_timer.timeout.connect(_on_jam_timer_timeout)
	jam_timer.start()

	jam_charge_timer.one_shot = true
	jam_charge_timer.wait_time = jam_charge_duration
	jam_charge_timer.timeout.connect(_on_jam_charge_timer_timeout)

	_prepare_jam_ring()
	_prepare_emp_ring()
	_update_visuals()


func _process(delta: float) -> void:
	if is_dead:
		return

	boss_health.text = "Health %d" % health
	_move_like_ufo(delta)
	_animate_jam_ring(delta)
	_animate_emp_ring(delta)
	_update_missile_rate_by_health()


func _move_like_ufo(delta: float) -> void:
	var viewport = get_viewport_rect().size
	global_position.x += move_direction * move_speed * delta

	var boss_speed
	if health >= 4:
		boss_speed = 1
	elif health >= 2:
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


func _update_missile_rate_by_health() -> void:
	var lost_health := float(max_health - health)
	var t := lost_health / max(1.0, float(max_health - 1))
	var current_interval = lerp(missile_drop_interval, missile_drop_interval_min, t)
	if abs(missile_timer.wait_time - current_interval) > 0.01:
		missile_timer.wait_time = current_interval
		if missile_timer.is_stopped():
			missile_timer.start()


func die(no_reward := false) -> void:
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
	print("🤖 Cyber Drone hit! Remaining HP: %d" % health)

	if health <= 0:
		_die_for_real(no_reward)
		return

	_update_visuals()


func _die_for_real(no_reward := false) -> void:
	is_dead = true
	missile_timer.stop()
	shield_timer.stop()
	emp_timer.stop()
	emp_charge_timer.stop()
	jam_timer.stop()
	jam_charge_timer.stop()

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


func _on_shield_timer_timeout() -> void:
	if shield_active:
		shield_active = false
		hit_used_this_down_window = false
		shield_timer.wait_time = shield_down_duration
	else:
		shield_active = true
		shield_timer.wait_time = shield_up_duration

	_update_visuals()
	shield_timer.start()


func _on_missile_timer_timeout() -> void:
	if is_dead:
		return
	spawn_normal_missile()


func _on_emp_timer_timeout() -> void:
	if is_dead:
		return
	_queue_emp_attack()


func _on_emp_charge_timer_timeout() -> void:
	if is_dead:
		return
	_hide_emp_charge_ring()
	emp_charge_active = false
	var attack_origin := global_position + Vector2(0, 28)
	EmpAttackUtils.spawn_emp_volley(
		self,
		emp_missile_scene,
		attack_origin,
		queued_emp_targets,
		Callable(GameManager, "_on_enemy_died")
	)
	queued_emp_targets.clear()


func _on_jam_timer_timeout() -> void:
	if is_dead:
		return
	_show_jam_charge_ring()
	emit_signal("jam_charge_started", jam_charge_duration)
	jam_charge_timer.start()


func _on_jam_charge_timer_timeout() -> void:
	if is_dead:
		return
	_hide_jam_charge_ring()
	var duration := _current_jam_duration()
	emit_signal("jam_pulse_started", duration, jam_misfire_radius)
	jam_timer.start()


func _current_jam_duration() -> float:
	var lost_health_ratio := float(max_health - health) / max(1.0, float(max_health - 1))
	return lerp(jam_duration_min, jam_duration_max, lost_health_ratio)


func spawn_normal_missile() -> void:
	if missile_scene == null:
		return

	var missile = missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport = get_viewport_rect().size
	var target = Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	var direction = (target - global_position).normalized()

	missile.global_position = global_position + Vector2(0, 32)
	missile.velocity = direction
	_add_to_scene(missile)


func _queue_emp_attack() -> void:
	if emp_charge_active:
		return
	var active_cannons := EmpAttackUtils.get_active_cannons(get_tree())
	queued_emp_targets = EmpAttackUtils.select_emp_targets_for_health(active_cannons, health)
	if queued_emp_targets.is_empty():
		return
	emp_charge_active = true
	_show_emp_charge_ring()
	emp_charge_timer.start()


func spawn_emp_missile() -> void:
	if emp_missile_scene == null:
		return

	EmpAttackUtils.spawn_emp_volley(
		self,
		emp_missile_scene,
		global_position + Vector2(0, 28),
		EmpAttackUtils.select_emp_targets_for_health(EmpAttackUtils.get_active_cannons(get_tree()), health),
		Callable(GameManager, "_on_enemy_died")
	)


func _prepare_jam_ring() -> void:
	if jam_ring == null:
		return
	jam_ring.visible = false
	jam_ring.width = 6.0
	jam_ring.default_color = Color(0.4, 0.95, 1.0, 0.85)
	jam_ring.clear_points()
	var points := 48
	var radius := 56.0
	for i in range(points + 1):
		var angle := TAU * float(i) / float(points)
		jam_ring.add_point(Vector2(cos(angle), sin(angle)) * radius)


func _prepare_emp_ring() -> void:
	if emp_ring == null:
		return
	emp_ring.visible = false
	emp_ring.width = 5.0
	emp_ring.default_color = Color(0.2, 1.0, 1.0, 0.85)
	emp_ring.clear_points()
	var points := 40
	var radius := 42.0
	for i in range(points + 1):
		var angle := TAU * float(i) / float(points)
		emp_ring.add_point(Vector2(cos(angle), sin(angle)) * radius)


func _show_jam_charge_ring() -> void:
	if jam_ring == null:
		return
	jam_ring.visible = true
	jam_ring.scale = Vector2(0.3, 0.3)
	jam_ring.modulate.a = 0.2


func _hide_jam_charge_ring() -> void:
	if jam_ring == null:
		return
	jam_ring.visible = false


func _show_emp_charge_ring() -> void:
	if emp_ring == null:
		return
	emp_ring.visible = true
	emp_ring.scale = Vector2(0.35, 0.35)
	emp_ring.modulate.a = 0.2


func _hide_emp_charge_ring() -> void:
	if emp_ring == null:
		return
	emp_ring.visible = false


func _animate_jam_ring(delta: float) -> void:
	if jam_ring == null or not jam_ring.visible:
		return
	var growth := 2.2 * delta / max(0.01, jam_charge_duration)
	jam_ring.scale += Vector2(growth, growth)
	jam_ring.modulate.a = min(1.0, jam_ring.modulate.a + (1.8 * delta / max(0.01, jam_charge_duration)))


func _animate_emp_ring(delta: float) -> void:
	if emp_ring == null or not emp_ring.visible:
		return
	var growth := 2.4 * delta / max(0.01, emp_charge_duration)
	emp_ring.scale += Vector2(growth, growth)
	emp_ring.modulate.a = min(1.0, emp_ring.modulate.a + (2.0 * delta / max(0.01, emp_charge_duration)))


func _update_visuals() -> void:
	if shield_active:
		sprite.modulate = Color(0.7, 0.95, 1.0, 1.0)
	else:
		sprite.modulate = Color(1.0, 0.55, 0.55, 1.0)
