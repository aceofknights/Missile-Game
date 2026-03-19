extends Area2D

signal enemy_died
signal boss_defeated

@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var ion_missile_scene: PackedScene
@export var clone_scene: PackedScene

@export var max_health := 5
@export var move_speed := 95.0
@export var shielded_phase_duration := 3.8
@export var clone_attack_delay := 1.0
@export var clone_phase_timeout := 4.6
@export var vanish_duration := 1.25
@export var reset_delay_after_reappear := 1.0
@export var normal_fire_interval := 1.25
@export var ion_fire_interval := 3.2
@export var clone_count_default := 3
@export var clone_count_enraged := 5

@onready var sprite: Sprite2D = $Sprite2D
@onready var boss_health_label: Label = $boss_health
@onready var normal_fire_timer: Timer = $NormalFireTimer
@onready var ion_fire_timer: Timer = $IonFireTimer
@onready var phase_timer: Timer = $PhaseTimer
@onready var clone_delay_timer: Timer = $CloneDelayTimer
@onready var clone_timeout_timer: Timer = $CloneTimeoutTimer
@onready var vanish_timer: Timer = $VanishTimer

var health := 5
var move_direction := 1.0
var shield_active := true
var invulnerable := true
var is_dead := false
var clones: Array[Area2D] = []


enum BossState {
	SHIELDED_ATTACK,
	CLONE_PREP,
	CLONE_ATTACK,
	VANISHED
}

var state: BossState = BossState.SHIELDED_ATTACK


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	normal_fire_timer.wait_time = normal_fire_interval
	normal_fire_timer.timeout.connect(_on_normal_fire_timer_timeout)
	normal_fire_timer.start()

	ion_fire_timer.wait_time = ion_fire_interval
	ion_fire_timer.timeout.connect(_on_ion_fire_timer_timeout)
	ion_fire_timer.start()

	phase_timer.one_shot = true
	phase_timer.timeout.connect(_on_phase_timer_timeout)

	clone_delay_timer.one_shot = true
	clone_delay_timer.timeout.connect(_on_clone_delay_timer_timeout)

	clone_timeout_timer.one_shot = true
	clone_timeout_timer.timeout.connect(_on_clone_timeout_timer_timeout)

	vanish_timer.one_shot = true
	vanish_timer.timeout.connect(_on_vanish_timer_timeout)

	_enter_clone_prep_phase()


func _process(delta: float) -> void:
	if is_dead:
		return
	_update_movement(delta)
	boss_health_label.text = "Copier HP %d" % health


func _update_movement(delta: float) -> void:
	if state == BossState.VANISHED:
		return

	var viewport = get_viewport_rect().size
	global_position.x += move_direction * move_speed * delta
	if global_position.x < 120.0:
		global_position.x = 120.0
		move_direction = 1.0
	elif global_position.x > viewport.x - 120.0:
		global_position.x = viewport.x - 120.0
		move_direction = -1.0


func _on_area_entered(area: Area2D) -> void:
	if area.name != "Projectile":
		return
	area.queue_free()
	die(false)


func die(no_reward := false) -> void:
	if is_dead:
		return
	if invulnerable or shield_active or state != BossState.CLONE_ATTACK:
		return

	health -= 1
	if health <= 0:
		_die_for_real(no_reward)
		return

	_enter_vanish_phase()


func _die_for_real(no_reward := false) -> void:
	if is_dead:
		return
	is_dead = true

	normal_fire_timer.stop()
	ion_fire_timer.stop()
	phase_timer.stop()
	clone_delay_timer.stop()
	clone_timeout_timer.stop()
	vanish_timer.stop()
	_clear_clones()

	if not no_reward:
		GameManager.add_resources(18)

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		get_tree().current_scene.add_child(explosion)

	emit_signal("boss_defeated")
	emit_signal("enemy_died")
	queue_free()


func _on_normal_fire_timer_timeout() -> void:
	if is_dead:
		return
	if state != BossState.SHIELDED_ATTACK and state != BossState.CLONE_ATTACK:
		return
	_spawn_missile(missile_scene)


func _on_ion_fire_timer_timeout() -> void:
	if is_dead:
		return
	if state != BossState.SHIELDED_ATTACK and state != BossState.CLONE_ATTACK:
		return
	_spawn_missile(ion_missile_scene)


func _spawn_missile(scene: PackedScene) -> void:
	if scene == null:
		return

	var missile = scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport = get_viewport_rect().size
	var target := Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	missile.global_position = global_position + Vector2(0, 24)
	missile.velocity = (target - missile.global_position).normalized()
	get_tree().current_scene.add_child(missile)


func _on_phase_timer_timeout() -> void:
	if is_dead:
		return
	_enter_clone_prep_phase()


func _enter_shielded_phase() -> void:
	state = BossState.SHIELDED_ATTACK
	shield_active = true
	invulnerable = true
	visible = true
	monitorable = true
	monitoring = true
	sprite.modulate = Color(0.52, 0.88, 1.0, 1.0)
	phase_timer.start(shielded_phase_duration)


func _enter_clone_prep_phase() -> void:
	state = BossState.CLONE_PREP
	shield_active = false
	invulnerable = true
	visible = true
	sprite.modulate = Color(1.0, 0.55, 0.58, 1.0)
	_clear_clones()
	_spawn_clones(_get_clone_count_for_current_health())
	clone_delay_timer.start(clone_attack_delay)


func _on_clone_delay_timer_timeout() -> void:
	if is_dead or state != BossState.CLONE_PREP:
		return
	state = BossState.CLONE_ATTACK
	invulnerable = false
	for clone in clones:
		if is_instance_valid(clone) and clone.has_method("begin_attack_phase"):
			clone.begin_attack_phase()
	clone_timeout_timer.start(clone_phase_timeout)


func _on_clone_timeout_timer_timeout() -> void:
	if is_dead:
		return
	_clear_clones()
	_enter_shielded_phase()


func _enter_vanish_phase() -> void:
	state = BossState.VANISHED
	invulnerable = true
	shield_active = true
	_clear_clones()
	visible = false
	monitoring = false
	monitorable = false
	vanish_timer.start(vanish_duration)


func _on_vanish_timer_timeout() -> void:
	if is_dead:
		return

	var viewport = get_viewport_rect().size
	global_position.x = randf_range(140.0, viewport.x - 140.0)
	global_position.y = randf_range(90.0, minf(200.0, viewport.y * 0.34))
	visible = true
	monitoring = true
	monitorable = true

	_enter_shielded_phase()
	phase_timer.stop()
	phase_timer.start(reset_delay_after_reappear)


func _spawn_clones(count: int) -> void:
	if clone_scene == null:
		return

	var viewport = get_viewport_rect().size
	for i in count:
		var clone = clone_scene.instantiate()
		clone.missile_scene = missile_scene
		clone.ion_missile_scene = ion_missile_scene
		clone.normal_fire_interval = normal_fire_interval
		clone.ion_fire_interval = ion_fire_interval
		clone.global_position = Vector2(
			randf_range(100.0, viewport.x - 100.0),
			randf_range(90.0, minf(220.0, viewport.y * 0.35))
		)
		clone.clone_destroyed.connect(_on_clone_destroyed)
		get_tree().current_scene.add_child(clone)
		clones.append(clone)


func _clear_clones() -> void:
	for clone in clones:
		if is_instance_valid(clone):
			clone.queue_free()
	clones.clear()


func _on_clone_destroyed(clone: Area2D) -> void:
	clones.erase(clone)


func _get_clone_count_for_current_health() -> int:
	if health <= 2:
		return clone_count_enraged
	return clone_count_default
