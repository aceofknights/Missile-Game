extends Area2D

signal plane_removed(plane: Area2D)

@export var role := "fighter"
@export var missile_scene: PackedScene
@export var explosion_scene: PackedScene
@export var fighter_projectile_scene: PackedScene
@export var base_speed := 145.0
@export var base_accuracy := 0.95
@export var min_accuracy := 0.45
@export var accuracy_decay_per_second := 0.10
@export var fighter_action_interval := 0.9
@export var bomber_action_interval := 1.8

@export var fighter_burst_count: int = 4
@export var fighter_burst_spacing: float = 0.08
@export var fighter_target_range: float = 520.0
@export var fighter_spread_degrees: float = 6.0

@export var fighter_texture: Texture2D
@export var bomber_texture: Texture2D
@export var fighter_scale: Vector2 = Vector2(1, 1)
@export var bomber_scale: Vector2 = Vector2(1, 1)
@export var fighter_color: Color = Color()
@export var bomber_color: Color = Color()

@onready var action_timer: Timer = $ActionTimer
@onready var sprite: Sprite2D = $Sprite2D
@onready var death_particles: GPUParticles2D = get_node_or_null("DeathParticles") as GPUParticles2D

var direction := Vector2.RIGHT
var speed_multiplier := 1.0
var accuracy_multiplier := 1.0
var _is_dead := false
var _entry_active := false
var _entry_target := Vector2.ZERO
var _entry_speed_multiplier := 1.4
var _burst_firing := false


func _ready() -> void:
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	
	if role == "bomber":
		action_timer.wait_time = bomber_action_interval
	else:
		action_timer.wait_time = fighter_action_interval
	action_timer.timeout.connect(_on_action_timer_timeout)
	action_timer.start()

	if death_particles:
		death_particles.emitting = false

	_apply_role_visuals()
	_apply_death_particle_color()


func _apply_role_visuals() -> void:
	if sprite == null:
		return

	if role == "bomber":
		if bomber_texture:
			sprite.texture = bomber_texture
		sprite.scale = bomber_scale
		sprite.modulate = bomber_color
	else:
		if fighter_texture:
			sprite.texture = fighter_texture
		sprite.scale = fighter_scale
		sprite.modulate = fighter_color


func _process(delta: float) -> void:
	if _is_dead:
		return

	if _entry_active:
		var step := base_speed * maxf(0.4, _entry_speed_multiplier) * delta
		position = position.move_toward(_entry_target, step)
		if position.distance_to(_entry_target) <= 6.0:
			_entry_active = false
			_set_random_patrol_direction()
		return

	if role == "fighter":
		accuracy_multiplier = max(min_accuracy, accuracy_multiplier - (accuracy_decay_per_second * delta))

	var viewport := get_viewport_rect().size
	position += direction * base_speed * speed_multiplier * delta

	if position.x < 80.0:
		position.x = 80.0
		direction.x = abs(direction.x)
	elif position.x > viewport.x - 80.0:
		position.x = viewport.x - 80.0
		direction.x = -abs(direction.x)

	if position.y < 60.0:
		position.y = 60.0
		direction.y = abs(direction.y)
	elif position.y > viewport.y * 0.45:
		position.y = viewport.y * 0.45
		direction.y = -abs(direction.y)

	if direction.length() > 0.001:
		rotation = direction.angle()


func configure_side_entry(target: Vector2, speed_multiplier_override := 1.4) -> void:
	_entry_target = target
	_entry_active = true
	_entry_speed_multiplier = speed_multiplier_override
	direction = (target - global_position).normalized()


func _set_random_patrol_direction() -> void:
	var x_dir := 1.0
	if randf() < 0.5:
		x_dir = -1.0
	var y_dir := randf_range(-0.45, 0.45)
	direction = Vector2(x_dir, y_dir).normalized()


func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = max(0.2, multiplier)


func reset_accuracy() -> void:
	accuracy_multiplier = 1.0


func _on_action_timer_timeout() -> void:
	if _is_dead:
		return

	if role == "fighter":
		if not _burst_firing:
			_fire_intercept_burst()
	else:
		_drop_bomb()


func _fire_intercept_burst() -> void:
	if fighter_projectile_scene == null:
		return

	var projectile := _pick_intercept_target()
	if projectile == null:
		return

	var hit_chance: float = clamp(base_accuracy * accuracy_multiplier, min_accuracy, 0.99)
	if randf() > hit_chance:
		return

	_burst_firing = true
	call_deferred("_run_fighter_burst", projectile)


func _run_fighter_burst(projectile: Area2D) -> void:
	await _run_fighter_burst_async(projectile)


func _run_fighter_burst_async(projectile: Area2D) -> void:
	for _i in range(fighter_burst_count):
		if _is_dead:
			break
		if not is_instance_valid(projectile):
			break

		_fire_single_intercept_round(projectile)

		if _i < fighter_burst_count - 1:
			await get_tree().create_timer(fighter_burst_spacing).timeout

	_burst_firing = false


func _fire_single_intercept_round(projectile: Area2D) -> void:
	if fighter_projectile_scene == null:
		return
	if not is_instance_valid(projectile):
		return

	var shot = fighter_projectile_scene.instantiate()
	var muzzle_pos := global_position + Vector2(0, 8)
	var aim_pos := projectile.global_position

	var to_target := aim_pos - muzzle_pos
	if to_target.length() > 0.001:
		var spread_radians := deg_to_rad(randf_range(-fighter_spread_degrees, fighter_spread_degrees))
		to_target = to_target.rotated(spread_radians)
		aim_pos = muzzle_pos + to_target

	shot.global_position = muzzle_pos

	if shot.has_method("setup_shot"):
		shot.setup_shot(projectile, aim_pos)

	get_tree().current_scene.add_child(shot)


func _pick_intercept_target() -> Area2D:
	var best_projectile: Area2D = null
	var best_distance_sq: float = INF

	for node in get_tree().get_nodes_in_group("projectile"):
		if not (node is Area2D):
			continue

		var projectile := node as Area2D
		if not is_instance_valid(projectile):
			continue

		var distance_sq := global_position.distance_squared_to(projectile.global_position)
		if distance_sq > fighter_target_range * fighter_target_range:
			continue

		if projectile.global_position.y > get_viewport_rect().size.y * 0.72:
			continue

		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_projectile = projectile

	return best_projectile


func _drop_bomb() -> void:
	if missile_scene == null:
		return

	var targets: Array = []
	for node in get_tree().get_nodes_in_group("defense_target"):
		if node == null:
			continue
		if node.has_method("is_destroyed") and node.is_destroyed():
			continue
		targets.append(node)

	if targets.is_empty():
		return

	var target: Node2D = targets[randi() % targets.size()]
	var bomb = missile_scene.instantiate()
	bomb.global_position = global_position + Vector2(0, 16)
	bomb.velocity = (target.global_position - bomb.global_position).normalized()
	GameManager.enemies_alive += 1
	bomb.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))
	get_tree().current_scene.add_child(bomb)


func _on_area_entered(area: Area2D) -> void:
	if area.name == "Projectile":
		die(false)
		area.queue_free()


func die(no_reward := false) -> void:
	if _is_dead:
		return
	_is_dead = true

	if not no_reward:
		GameManager.add_resources(1)

	emit_signal("plane_removed", self)

	_play_death_particles_and_remove()


func _play_death_particles_and_remove() -> void:
	if death_particles == null:
		queue_free()
		return

	monitoring = false
	monitorable = false
	action_timer.stop()

	if sprite:
		sprite.visible = false

	death_particles.reparent(get_tree().current_scene)
	death_particles.global_position = global_position
	death_particles.global_rotation = global_rotation
	death_particles.emitting = true

	var cleanup_time: float = maxf(0.1, death_particles.lifetime + 0.1)
	await get_tree().create_timer(cleanup_time).timeout

	if is_instance_valid(death_particles):
		death_particles.queue_free()

	queue_free()

func _apply_death_particle_color() -> void:
	if death_particles == null:
		return

	var tint := Color(1, 1, 1, 1)

	if role == "bomber":
		if bomber_color != Color():
			tint = bomber_color
	elif fighter_color != Color():
		tint = fighter_color

	death_particles.modulate = tint
